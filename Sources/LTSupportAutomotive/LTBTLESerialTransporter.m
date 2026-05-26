//
//  Copyright (c) Dr. Michael Lauer Information Technology. All rights reserved.
//
#import "LTBTLESerialTransporter.h"

#import "LTBTLEReadCharacteristicStream.h"
#import "LTBTLEWriteCharacteristicStream.h"

#import "helpers.h"

NSString* const LTBTLESerialTransporterDidUpdateSignalStrength = @"LTBTLESerialTransporterDidUpdateSignalStrength";

//#define DEBUG_THIS_FILE

#ifdef DEBUG_THIS_FILE
    #define XLOG LOG
#else
    #define XLOG(...)
#endif

@implementation LTBTLESerialTransporter
{
    CBCentralManager* _manager;
    NSUUID* _identifier;
    NSArray<CBUUID*>* _serviceUUIDs;
    CBPeripheral* _adapter;
    CBCharacteristic* _reader;
    CBCharacteristic* _writer;

    NSMutableArray<CBPeripheral*>* _possibleAdapters;

    dispatch_queue_t _dispatchQueue;

    LTBTLESerialTransporterConnectionBlock _connectionBlock;
    LTBTLEReadCharacteristicStream* _inputStream;
    LTBTLEWriteCharacteristicStream* _outputStream;

    NSNumber* _signalStrength;
    NSTimer* _signalStrengthUpdateTimer;
}

#pragma mark -
#pragma mark Lifecycle

+(instancetype)transporterWithIdentifier:(NSUUID*)identifier serviceUUIDs:(NSArray<CBUUID*>*)serviceUUIDs
{
    return [[self alloc] initWithIdentifier:identifier serviceUUIDs:serviceUUIDs];
}

-(instancetype)initWithIdentifier:(NSUUID*)identifier serviceUUIDs:(NSArray<CBUUID*>*)serviceUUIDs
{
    if ( ! ( self = [super init] ) )
    {
        return nil;
    }

    _identifier = identifier;
    _serviceUUIDs = serviceUUIDs;

    _dispatchQueue = dispatch_queue_create( [NSStringFromClass(self.class) UTF8String], DISPATCH_QUEUE_SERIAL );
    _possibleAdapters = [NSMutableArray array];

    XLOG( @"Created w/ identifier %@, services %@", _identifier, _serviceUUIDs );

    return self;
}

-(void)dealloc
{
    [self disconnect];
}

#pragma mark -
#pragma mark API

-(void)connectWithBlock:(LTBTLESerialTransporterConnectionBlock)block
{
    _connectionBlock = block;

    // Re-use the existing CBCentralManager when the caller invokes
    // connectWithBlock: more than once (typical after a failed first
    // connect and a retry). Allocating a new manager each time leaks
    // the previous instance and leaves its in-flight scan/connect
    // operations alive in CoreBluetooth — over time the system starts
    // throttling our BLE access. If a manager already exists and is
    // powered on, jump straight back into the discovery path.
    if ( _manager )
    {
        [self resetTransientStateForReconnect];
        if ( _manager.state == CBManagerStatePoweredOn )
        {
            [self centralManagerDidUpdateState:_manager];
        }
        return;
    }

    _manager = [[CBCentralManager alloc] initWithDelegate:self queue:_dispatchQueue options:nil];
}

-(void)resetTransientStateForReconnect
{
    if ( _manager.isScanning )
    {
        [_manager stopScan];
    }
    if ( _adapter )
    {
        [_manager cancelPeripheralConnection:_adapter];
        _adapter = nil;
    }
    [_possibleAdapters enumerateObjectsUsingBlock:^(CBPeripheral * _Nonnull peripheral, NSUInteger idx, BOOL * _Nonnull stop) {
        [self->_manager cancelPeripheralConnection:peripheral];
    }];
    [_possibleAdapters removeAllObjects];
    _reader = nil;
    _writer = nil;
}

-(void)disconnect
{
    [self stopUpdatingSignalStrength];

    [_inputStream close];
    [_outputStream close];

    if ( _adapter )
    {
        [_manager cancelPeripheralConnection:_adapter];
    }

    [_possibleAdapters enumerateObjectsUsingBlock:^(CBPeripheral * _Nonnull peripheral, NSUInteger idx, BOOL * _Nonnull stop) {
        [self->_manager cancelPeripheralConnection:peripheral];
    }];
}

-(void)startUpdatingSignalStrengthWithInterval:(NSTimeInterval)interval
{
    // NSTimer is scheduled onto the current runloop, so this method only
    // worked previously when callers happened to invoke it from the
    // main thread. Marshal explicitly to the main queue so the timer
    // always lands on a runloop that is actually running.
    dispatch_async( dispatch_get_main_queue(), ^{
        [self->_signalStrengthUpdateTimer invalidate];
        self->_signalStrengthUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:interval target:self selector:@selector(onSignalStrengthUpdateTimerFired:) userInfo:nil repeats:YES];
    });
}

-(void)stopUpdatingSignalStrength
{
    // Match the schedule context: invalidate must run on the runloop
    // that scheduled the timer (main).
    dispatch_async( dispatch_get_main_queue(), ^{
        [self->_signalStrengthUpdateTimer invalidate];
        self->_signalStrengthUpdateTimer = nil;
    });
}

#pragma mark -
#pragma mark NSTimer

-(void)onSignalStrengthUpdateTimerFired:(NSTimer*)timer
{
    if ( _adapter.state != CBPeripheralStateConnected )
    {
        return;
    }

    [_adapter readRSSI];
}

#pragma mark -
#pragma mark <CBCentralManagerDelegate>

-(void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if ( central.state != CBManagerStatePoweredOn )
    {
        // Anything other than PoweredOn (Unauthorized, Unsupported,
        // PoweredOff, Resetting, Unknown) means the manager will not
        // deliver a peripheral. Wake the caller now so they don't
        // wait forever for a connection that cannot happen.
        if ( central.state == CBManagerStateUnauthorized
          || central.state == CBManagerStateUnsupported
          || central.state == CBManagerStatePoweredOff )
        {
            [self connectionAttemptFailed];
        }
        return;
    }
    NSArray<CBPeripheral*>* peripherals = [_manager retrieveConnectedPeripheralsWithServices:_serviceUUIDs];
    if ( peripherals.count )
    {
        LOG( @"CONNECTED (already) %@", _adapter );
        if ( _adapter.state == CBPeripheralStateConnected )
        {
            _adapter = peripherals.firstObject;
            _adapter.delegate = self;
            [self peripheral:_adapter didDiscoverServices:nil];
        }
        else
        {
            [_possibleAdapters addObject:peripherals.firstObject];
            [self centralManager:central didDiscoverPeripheral:peripherals.firstObject advertisementData:@{} RSSI:@127];
        }
        return;
    }

    if ( _identifier )
    {
        peripherals = [_manager retrievePeripheralsWithIdentifiers:@[_identifier]];
    }
    if ( !peripherals.count )
    {
        // some devices are not advertising the service ID, hence we need to scan for all services
        [_manager scanForPeripheralsWithServices:nil options:nil];
        return;
    }

    _adapter = peripherals.firstObject;
    _adapter.delegate = self;
    LOG( @"DISCOVER (cached) %@", _adapter );
    [_manager connectPeripheral:_adapter options:nil];
}

-(void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral*)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI
{
    if ( _adapter )
    {
        LOG( @"[IGNORING] DISCOVER %@ (RSSI=%@) w/ advertisement %@", peripheral, RSSI, advertisementData );
        return;
    }

    LOG( @"DISCOVER %@ (RSSI=%@) w/ advertisement %@", peripheral, RSSI, advertisementData );
    [_possibleAdapters addObject:peripheral];
    peripheral.delegate = self;
    [_manager connectPeripheral:peripheral options:nil];
}

-(void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    LOG( @"CONNECT %@", peripheral );
    [peripheral discoverServices:_serviceUUIDs];
}

-(void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    LOG( @"Failed to connect %@: %@", peripheral, error );
    [_possibleAdapters removeObject:peripheral];
    // Only abandon the attempt when there are no more candidates
    // queued; otherwise let the remaining peripherals decide success
    // or failure via the discovery delegate path.
    if ( _possibleAdapters.count == 0 && _adapter == nil )
    {
        [self connectionAttemptFailed];
    }
}

-(void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    LOG( @"Did disconnect %@: %@", peripheral, error );
    if ( peripheral == _adapter )
    {
        [_inputStream close];
        [_outputStream close];
    }
}

#pragma mark -
#pragma mark <CBPeripheralDelegate>

-(void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error
{
    if ( error )
    {
        LOG( @"Could not read signal strength for %@: %@", peripheral, error );
        return;
    }

    _signalStrength = RSSI;
    LTPostNotificationOnMain( LTBTLESerialTransporterDidUpdateSignalStrength, self );
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if ( _adapter )
    {
        LOG( @"[IGNORING] SERVICES %@: %@", peripheral, peripheral.services );
        return;
    }

    if ( error )
    {
        LOG( @"Could not discover services: %@", error );
        [_manager cancelPeripheralConnection:peripheral];
        [_possibleAdapters removeObject:peripheral];
        if ( _possibleAdapters.count == 0 && _adapter == nil )
        {
            [self connectionAttemptFailed];
        }
        return;
    }

    if ( !peripheral.services.count )
    {
        LOG( @"Peripheral does not offer requested services" );

        [_manager cancelPeripheralConnection:peripheral];
        [_possibleAdapters removeObject:peripheral];
        if ( _possibleAdapters.count == 0 && _adapter == nil )
        {
            [self connectionAttemptFailed];
        }
        return;
    }

    _adapter = peripheral;
    _adapter.delegate = self;
    // Remove the now-promoted peripheral from the candidate pool. The
    // old code left the same peripheral in both _adapter and
    // _possibleAdapters, so disconnect later issued
    // cancelPeripheralConnection twice on the same CBPeripheral —
    // CoreBluetooth ends up in an internal state where subsequent
    // connects to the same identifier are silently dropped, and the
    // user needs to toggle Bluetooth to recover.
    [_possibleAdapters removeObject:peripheral];
    if ( _manager.isScanning )
    {
        [_manager stopScan];
    }

    // Iterate every service the peripheral exposed, not just the first
    // one. Several real ELM-class adapters (VGate iCar Pro firmware
    // variants, some OBDLink BLE adapters) advertise multiple services
    // where read/write live in different services — only inspecting
    // services.firstObject made those adapters look "incompatible".
    for ( CBService* service in peripheral.services )
    {
        [peripheral discoverCharacteristics:nil forService:service];
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    for ( CBCharacteristic* characteristic in service.characteristics )
    {
        if ( characteristic.properties & CBCharacteristicPropertyNotify )
        {
            LOG( @"Did see notify characteristic" );
            _reader = characteristic;

            //[peripheral readValueForCharacteristic:characteristic];
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
        }

        // Accept either Write (with response) or WriteWithoutResponse —
        // a non-trivial subset of BLE OBD adapters expose only the
        // latter. The actual writeValue:type: call selects the matching
        // type, see LTBTLEWriteCharacteristicStream.
        if ( characteristic.properties & ( CBCharacteristicPropertyWrite | CBCharacteristicPropertyWriteWithoutResponse ) )
        {
            LOG( @"Did see write characteristic" );
            _writer = characteristic;
        }
    }

    // Wait until all requested services have reported back before
    // deciding success/failure. With multiple services in flight we'd
    // otherwise call connectionAttemptFailed after the first service's
    // characteristics arrive even though a later service still has
    // pending discovery.
    BOOL anyServicePending = NO;
    for ( CBService* svc in peripheral.services )
    {
        if ( svc.characteristics == nil )
        {
            anyServicePending = YES;
            break;
        }
    }
    if ( anyServicePending )
    {
        return;
    }

    if ( _reader && _writer )
    {
        [self connectionAttemptSucceeded];
    }
    else
    {
        [self connectionAttemptFailed];
    }
}

-(void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
#ifdef DEBUG_THIS_FILE
    NSString* debugString = [[NSString alloc] initWithData:characteristic.value encoding:NSUTF8StringEncoding];
    NSString* replacedWhitespace = [[debugString stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"] stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    XLOG( @"%@ >>> %@", peripheral, replacedWhitespace );
#endif

    if ( error )
    {
        LOG( @"Could not update value for characteristic %@: %@", characteristic, error );
        return;
    }

    [_inputStream characteristicDidUpdateValue];
}

-(void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if ( error )
    {
        LOG( @"Could not write to characteristic %@: %@", characteristic, error );
        return;
    }

    [_outputStream characteristicDidWriteValue];
}

#pragma mark -
#pragma mark Helpers

-(void)connectionAttemptSucceeded
{
    _inputStream = [[LTBTLEReadCharacteristicStream alloc] initWithCharacteristic:_reader];
    _outputStream = [[LTBTLEWriteCharacteristicStream alloc] initToCharacteristic:_writer];
    _connectionBlock( _inputStream, _outputStream );
    _connectionBlock = nil;
}

-(void)connectionAttemptFailed
{
    if ( !_connectionBlock )
    {
        return;
    }
    _connectionBlock( nil, nil );
    _connectionBlock = nil;
}

@end
