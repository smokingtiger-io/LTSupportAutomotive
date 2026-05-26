//
//  Smoke tests for PID formatters fixed in C3, C4, M3, M4.
//
#import <XCTest/XCTest.h>
@import LTSupportAutomotive;

@interface PIDFormatTests : XCTestCase
@end

@implementation PIDFormatTests

- (id<NSObject>)decodeResponseForPID:(LTOBD2PID*)pid lines:(NSArray<NSString*>*)lines command:(NSString*)command
{
    LTOBD2ProtocolISO15765_4* protocol = [LTOBD2ProtocolISO15765_4 protocolVariantWith11BitHeaders];
    NSDictionary<NSString*,LTOBD2ProtocolResult*>* decoded = [protocol decode:lines originatingCommand:command];
    [pid didCompleteResponse:lines completionTime:0];
    [pid didCookResponse:decoded withProtocolType:OBD2VehicleProtocolCAN_11B_500K];
    return pid;
}

// C4: PID 0x43 should be a 2-byte percentage in [0, 25700] %.
- (void)test_PID_0x43_absoluteLoad_twoBytePercent
{
    LTOBD2PID_ABSOLUTE_ENGINE_LOAD_43* pid = [LTOBD2PID_ABSOLUTE_ENGINE_LOAD_43 pidForMode1];
    [self decodeResponseForPID:pid lines:@[ @"7E8 04 41 43 FF FF" ] command:@"0143"];
    NSString* formatted = pid.formattedResponse;
    // (0xFFFF * 100) / 255 == 25700.0
    XCTAssertTrue([formatted containsString:@"25700"], @"expected ~25700%% for max 2-byte load, got %@", formatted);
}

- (void)test_PID_0x43_absoluteLoad_midrange
{
    LTOBD2PID_ABSOLUTE_ENGINE_LOAD_43* pid = [LTOBD2PID_ABSOLUTE_ENGINE_LOAD_43 pidForMode1];
    [self decodeResponseForPID:pid lines:@[ @"7E8 04 41 43 00 FF" ] command:@"0143"];
    // (0x00FF * 100) / 255 == 100.0
    NSString* formatted = pid.formattedResponse;
    XCTAssertTrue([formatted containsString:@"100"], @"expected ~100%% for 0x00FF, got %@", formatted);
}

// C3: PID 0x32 vapor pressure is signed ((A*256+B)/4) Pa.
- (void)test_PID_0x32_evapVapor_positive
{
    LTOBD2PID_EVAP_SYS_VAPOR_PRESSURE_32* pid = [LTOBD2PID_EVAP_SYS_VAPOR_PRESSURE_32 pidForMode1];
    [self decodeResponseForPID:pid lines:@[ @"7E8 04 41 32 10 00" ] command:@"0132"];
    // 0x1000 / 4 = 1024.00 Pa
    XCTAssertTrue([pid.formattedResponse containsString:@"1024"], @"got %@", pid.formattedResponse);
}

- (void)test_PID_0x32_evapVapor_negative
{
    LTOBD2PID_EVAP_SYS_VAPOR_PRESSURE_32* pid = [LTOBD2PID_EVAP_SYS_VAPOR_PRESSURE_32 pidForMode1];
    [self decodeResponseForPID:pid lines:@[ @"7E8 04 41 32 FF F0" ] command:@"0132"];
    // (int16_t)0xFFF0 == -16; / 4 == -4.0 Pa
    XCTAssertTrue([pid.formattedResponse containsString:@"-4"], @"expected negative pressure, got %@", pid.formattedResponse);
}

// M4: PID 0xA6 odometer must use floating-point division and report NO DATA when missing.
- (void)test_PID_0xA6_odometer_fractionalKilometers
{
    LTOBD2PID_ODOMETER_A6* pid = [LTOBD2PID_ODOMETER_A6 pidForMode1];
    // 4-byte payload 00 00 00 67 = 103 -> 10.30 km after /10.0
    [self decodeResponseForPID:pid lines:@[ @"7E8 06 41 A6 00 00 00 67" ] command:@"01A6"];
    NSString* formatted = pid.formattedResponse;
    XCTAssertTrue([formatted containsString:@"10.30"] || [formatted containsString:@"10.3"], @"expected fractional km, got %@", formatted);
}

- (void)test_PID_0xA6_odometer_noDataGuard
{
    LTOBD2PID_ODOMETER_A6* pid = [LTOBD2PID_ODOMETER_A6 pidForMode1];
    // No cookedResponse populated -> formattedResponse must not crash and should not say "0.00 km".
    XCTAssertNoThrow([pid formattedResponse]);
    NSString* formatted = pid.formattedResponse;
    XCTAssertFalse([formatted containsString:@"0.00"], @"expected NO DATA placeholder, got %@", formatted);
}

@end
