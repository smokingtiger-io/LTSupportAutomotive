//
//  Smoke tests for the protocol decoders fixed in C2 — short/malformed
//  lines must not crash and must not produce results for invalid input.
//
#import <XCTest/XCTest.h>
@import LTSupportAutomotive;

@interface ProtocolBoundsTests : XCTestCase
@end

@implementation ProtocolBoundsTests

- (void)test_iso15765_11bit_decodesNormalSingleFrame
{
    LTOBD2ProtocolISO15765_4* protocol = [LTOBD2ProtocolISO15765_4 protocolVariantWith11BitHeaders];
    NSDictionary* result = [protocol decode:@[ @"7E8 04 41 43 12 34" ] originatingCommand:@"0143"];
    XCTAssertEqual(result.count, 1);
}

- (void)test_iso15765_11bit_shortLineDoesNotCrash
{
    LTOBD2ProtocolISO15765_4* protocol = [LTOBD2ProtocolISO15765_4 protocolVariantWith11BitHeaders];
    XCTAssertNoThrow([protocol decode:@[ @"00 01" ] originatingCommand:@"0100"]);
    XCTAssertNoThrow([protocol decode:@[ @"" ] originatingCommand:@"0100"]);
    XCTAssertNoThrow([protocol decode:@[] originatingCommand:@"0100"]);
}

// Previously crashed: a 3-byte line with 29-bit headers tries
// bytesInLine[3] (addressIndex = 3) but the entry guard only required
// count >= 3.
- (void)test_iso15765_29bit_shortLineNoOutOfBounds
{
    LTOBD2ProtocolISO15765_4* protocol = [LTOBD2ProtocolISO15765_4 protocolVariantWith29BitHeaders];
    XCTAssertNoThrow([protocol decode:@[ @"18 DA F1 10" ] originatingCommand:@"0100"]);
    XCTAssertNoThrow([protocol decode:@[ @"00 01 02" ] originatingCommand:@"0100"]);
}

// Previously crashed: payloadIndex > count caused an NSUInteger
// underflow inside subarrayWithRange:.
- (void)test_iso15765_11bit_payloadTruncationNoCrash
{
    LTOBD2ProtocolISO15765_4* protocol = [LTOBD2ProtocolISO15765_4 protocolVariantWith11BitHeaders];
    // header (1) + PCI (1) + corrective (2 for "0100") + multi (0) = payloadIndex 4,
    // but the line only carries 3 bytes after the header.
    XCTAssertNoThrow([protocol decode:@[ @"7E8 04 41" ] originatingCommand:@"0100"]);
}

@end
