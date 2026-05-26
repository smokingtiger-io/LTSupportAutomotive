//
//  Copyright (c) Dr. Michael Lauer Information Technology. All rights reserved.
//
#import "LTBTLEWriteCharacteristicStream.h"

@implementation LTBTLEWriteCharacteristicStream
{
    __weak id<NSStreamDelegate> _delegate;
    CBCharacteristic* _characteristic;

    NSStreamStatus _status;
}

#pragma mark -
#pragma mark Lifecycle

-(instancetype)initToCharacteristic:(CBCharacteristic*)characteristic
{
    // Either Write or WriteWithoutResponse is acceptable; the actual
    // write call selects the type matching what's advertised. Reject
    // characteristics that offer neither so we fail fast instead of
    // silently no-oping on writeValue:forCharacteristic:.
    NSAssert(
        characteristic.properties & ( CBCharacteristicPropertyWrite | CBCharacteristicPropertyWriteWithoutResponse ),
        @"Characteristic has to offer at least one write property"
    );

    if ( ! ( self = [super init] ) )
    {
        return self;
    }

    _characteristic = characteristic;
    _delegate = self;
    _status = NSStreamStatusNotOpen;

    return self;
}

#pragma mark -
#pragma mark API

-(void)characteristicDidWriteValue
{
    [self.delegate stream:self handleEvent:NSStreamEventHasSpaceAvailable];
}

#pragma mark -
#pragma mark NSStream Overrides

-(void)setDelegate:(id<NSStreamDelegate>)delegate
{
    if ( _delegate == delegate )
    {
        return;
    }

    _delegate = delegate ?: self;
}

-(id<NSStreamDelegate>)delegate
{
    return _delegate;
}

-(void)open
{
    _status = NSStreamStatusOpening;
    _status = NSStreamStatusOpen;
    [self.delegate stream:self handleEvent:NSStreamEventOpenCompleted];
    [self.delegate stream:self handleEvent:NSStreamEventHasSpaceAvailable];
}

-(void)close
{
    _status = NSStreamStatusClosed;
    [self.delegate stream:self handleEvent:NSStreamEventEndEncountered];
}

-(void)scheduleInRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString*)mode
{
    // nothing to do here
}

-(void)removeFromRunLoop:(NSRunLoop *)aRunLoop forMode:(NSString*)mode
{
    // nothing to do here
}

-(id)propertyForKey:(NSString *)key
{
    return nil;
}

-(BOOL)setProperty:(id)property forKey:(NSString *)key
{
    // nothing to do here
    return NO;
}

#pragma mark -
#pragma mark NSOutputStream Overrides

-(NSInteger)write:(const uint8_t *)buffer maxLength:(NSUInteger)len
{
    if ( _status != NSStreamStatusOpen )
    {
        return -1;
    }

    // Prefer .withResponse when the characteristic advertises it (the
    // delivery callback we already wire up gives us reliable
    // characteristicDidWriteValue events). Fall back to
    // .withoutResponse for adapters that only support that. Previously
    // .withResponse was always used, which silently failed on
    // writeWithoutResponse-only adapters.
    CBCharacteristicWriteType writeType =
        ( _characteristic.properties & CBCharacteristicPropertyWrite )
            ? CBCharacteristicWriteWithResponse
            : CBCharacteristicWriteWithoutResponse;
    NSUInteger maxWriteForCharacteristic = [_characteristic.service.peripheral maximumWriteValueLengthForType:writeType];
    NSUInteger lengthToWrite = MIN( len, maxWriteForCharacteristic );
    NSData* value = [NSData dataWithBytes:buffer length:lengthToWrite];
    [_characteristic.service.peripheral writeValue:value forCharacteristic:_characteristic type:writeType];

    // writeWithoutResponse never fires didWriteValueForCharacteristic,
    // so synthesize the HasSpaceAvailable signal that the stream
    // consumer expects after every successful enqueue.
    if ( writeType == CBCharacteristicWriteWithoutResponse )
    {
        [self characteristicDidWriteValue];
    }

    return lengthToWrite;
}

-(BOOL)hasSpaceAvailable
{
    if ( _status != NSStreamStatusOpen )
    {
        return NO;
    }
    return YES;
}

@end
