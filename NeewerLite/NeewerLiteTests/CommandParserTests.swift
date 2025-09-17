//
//  NeewerLiteTests.swift
//  NeewerLiteTests
//
//  Created by Xu Lian on 07/24/25.
//

import XCTest
@testable import NeewerLite

final class CommandPatternParserTests: XCTestCase {

    func testPowerOnCommandPattern() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}"
        let values: [String: Any] = ["state": 1] // 1 = on

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x81, 0x01, 0x01, 0xFB])
        XCTAssertEqual(data, expected)
    }

    func testPowerOffCommandPattern() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}"
        let values: [String: Any] = ["state": 2] // 2 = off

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x81, 0x01, 0x02, 0xFC])
        XCTAssertEqual(data, expected)
    }

    func testPowerOffCommandPatternWithInvalidValue() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}"
        let values: [String: Any] = ["state": 3] // 3 = invalid

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([])
        XCTAssertEqual(data, expected)
    }
    
    func testPowerOnCommandPatternWithName() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}"
        let values: [String: Any] = ["state": "on"] // 1 = on

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x81, 0x01, 0x01, 0xFB])
        XCTAssertEqual(data, expected)
    }

    func testPowerOffCommandPatternWithName() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {checksum}"
        let values: [String: Any] = ["state": "off"] // 2 = off

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x81, 0x01, 0x02, 0xFC])
        XCTAssertEqual(data, expected)
    }

    func testPowerCommandPatternOff() {
        let pattern = "{cmdtag} {powertag} {size} {mode:uint8:enum(0=off,1=on)} {checksum}"
        let values: [String: Any] = ["headerByte": 0x78, "mode": 0] // 0 = off

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // Should be: 0x78 0x81 0x01 0x00 0xFA (checksum: 0x78+0x81+0x01+0x00 = 0xFA)
        let expected = Data([0x78, 0x81, 0x01, 0x00, 0xFA])
        XCTAssertEqual(data, expected)
    }
    
    func testSize2PatternWithName() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)} {mode:uint8:enum(1=A,2=B,3=C)} {checksum}"
        let values: [String: Any] = ["state": "off", "mode": "B"]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        print("\(data.hexEncodedString())")
        let expected = Data([0x78, 0x81, 0x02, 0x02, 0x02, 0xFF])
        XCTAssertEqual(data, expected)
    }

    func testRangePatternValid() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:range(1,99)} {checksum}"
        let values: [String: Any] = ["state": 42]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // 0x78 + 0x81 + 0x01 + 0x2A = 0x124, 0x124 & 0xFF = 0x24
        let expected = Data([0x78, 0x81, 0x01, 0x2A, 0x24])
        XCTAssertEqual(data, expected)
    }

    func testRangePatternInvalidLow() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:range(1,99)} {checksum}"
        let values: [String: Any] = ["state": 0] // below range

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x81, 0x01, 0x01, 0xfb])
        XCTAssertEqual(data, expected)
    }

    func testRangePatternInvalidHigh() {
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:range(1,99)} {checksum}"
        let values: [String: Any] = ["state": 100] // above range

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x81, 0x01, 0x63, 0x5d])
        XCTAssertEqual(data, expected)
    }
    
    
    func testCCTPatternInvalidHigh() {
        let pattern = "{cmdtag} {ccttag} {size} {brr:uint8:range(0,100)} {cct:uint8:range(25,85)} {gm:uint8:range(0,100)} 0x00 0x00 {checksum}"
        let values: [String: Any] = ["brr": 101, "cct": 86, "gm": 101] // all above range

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x87, 0x05, 0x64, 0x55, 0x64, 0x00, 0x00, 0x21]) // Should fail due to out-of-range values
        XCTAssertEqual(data, expected)
    }

    func testCCTPatternValid() {
        let pattern = "{cmdtag} {ccttag} {size} {brr:uint8:range(0,100)} {cct:uint8:range(25,85)} {gm:uint8:range(0,100)} 0x00 0x00 {checksum}"
        let values: [String: Any] = ["brr": 50, "cct": 50, "gm": 50]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x87, 0x05, 0x32, 0x32, 0x32, 0x00, 0x00, 0x9A])
        XCTAssertEqual(data, expected)
    }

    func testHSIPatternValid() {
        let pattern = "{cmdtag} {hsitag} {size} {h:uint8:range(0,255)} {s:uint8:range(0,100)} {i:uint8:range(0,100)} {w:uint8:range(0,255)} {checksum}"
        let values: [String: Any] = ["h": 128, "s": 80, "i": 100, "w": 0]
        let expected = Data([0x78, 0x86, 0x04, 0x80, 0x50, 0x64, 0x00, 0x36])

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        XCTAssertEqual(data, expected)
    }

    func testHSIPatternWithUInt16LE() {
        let pattern = "{cmdtag} {hsitag} {size} {hue:uint16_le} {s:uint8:range(0,100)} {i:uint8:range(0,100)} {w:uint8:range(0,255)} {checksum}"
        let values: [String: Any] = ["hue": 0x1234, "s": 80, "i": 100, "w": 0]
        let expected = Data([0x78, 0x86, 0x05, 0x34, 0x12, 0x50, 0x64, 0x00, 0xFD])

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        XCTAssertEqual(data, expected)
    }

    func testHSIPatternWithUInt16BE() {
        let pattern = "{cmdtag} {hsitag} {size} {hue:uint16_be} {s:uint8:range(0,100)} {i:uint8:range(0,100)} {w:uint8:range(0,255)} {checksum}"
        let values: [String: Any] = ["hue": 0x1234, "s": 80, "i": 100, "w": 0]
        let expected = Data([0x78, 0x86, 0x05, 0x12, 0x34, 0x50, 0x64, 0x00, 0xFD])

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        XCTAssertEqual(data, expected)
    }

    func testHSIPatternWithUInt16LERangeValid() {
        let pattern = "{cmdtag} {hsitag} {size} {hue:uint16_le:range(0,360)} {s:uint8:range(0,100)} {i:uint8:range(0,100)} {w:uint8:range(0,255)} {checksum}"
        let values: [String: Any] = ["hue": 300, "s": 80, "i": 100, "w": 0]
        // 300 = 0x012C, little-endian: 0x2C 0x01
        // 0x78 + 0x86 + 0x05 + 0x2C + 0x01 + 0x50 + 0x64 + 0x00 = 0x1E4, 0x1E4 & 0xFF = 0xE4
        let expected = Data([0x78, 0x86, 0x05, 0x2C, 0x01, 0x50, 0x64, 0x00, 0xE4])

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        XCTAssertEqual(data, expected)
    }

    func testHSIPatternWithUInt16LERangeInvalid() {
        let pattern = "{cmdtag} {hsitag} {size} {hue:uint16_le:range(0,360)} {s:uint8:range(0,100)} {i:uint8:range(0,100)} {w:uint8:range(0,255)} {checksum}"
        let values: [String: Any] = ["hue": 400, "s": 80, "i": 100, "w": 0] // 400 is out of range

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let expected = Data([0x78, 0x86, 0x05, 0x68, 0x01, 0x50, 0x64, 0x00, 0x20]) // Should fail due to out-of-range hue
        XCTAssertEqual(data, expected)
    }

    func testPatternWithoutSize() {
        // Pattern omits {size}
        let pattern = "{cmdtag} {powertag} {state:uint8:enum(1=on,2=off)} {checksum}"
        let values: [String: Any] = ["state": 1]
        // Expected: 0x78, 0x81, 0x01, checksum = 0x78 + 0x81 + 0x01 = 0xFA
        let expected = Data([0x78, 0x81, 0x01, 0xFA])
        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        XCTAssertEqual(data, expected)
    }

    func testPatternWithoutChecksum() {
        // Pattern omits {checksum}
        let pattern = "{cmdtag} {powertag} {size} {state:uint8:enum(1=on,2=off)}"
        let values: [String: Any] = ["state": 2]
        // Expected: 0x78, 0x81, 0x01, 0x02 (no checksum)
        let expected = Data([0x78, 0x81, 0x01, 0x02])
        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        XCTAssertEqual(data, expected)
    }

    func testPatternWithoutSizeAndChecksum() {
        // Pattern omits both {size} and {checksum}
        let pattern = "{cmdtag} {powertag} {state:uint8:enum(1=on,2=off)}"
        let values: [String: Any] = ["state": 2]
        // Expected: 0x78, 0x81, 0x02 (no size, no checksum)
        let expected = Data([0x78, 0x81, 0x02])
        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        XCTAssertEqual(data, expected)
    }
    
    func testValidatePatternValid() {
        let pattern = "{cmdtag} {powertag} {state:uint8:enum(1=on,2=off)} {checksum}"
        let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
        XCTAssertTrue(isValid)
        XCTAssertNil(error)
    }

    func testValidatePatternUnknownType() {
        let pattern = "{cmdtag} {powertag} {state:float:enum(1=on,2=off)} {checksum}"
        let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
        XCTAssertFalse(isValid)
        XCTAssertTrue(error?.contains("unknown type") ?? false)
    }

    func testValidatePatternUnknownVar() {
        let pattern = "{cmdtag} {powertag} {unknownvar} {checksum}"
        let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
        XCTAssertFalse(isValid)
        XCTAssertTrue(error?.contains("unknown variable") ?? false)
    }

    func testValidatePatternInvalidHex() {
        let pattern = "{cmdtag} {powertag} 0xZZ {checksum}"
        let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
        XCTAssertFalse(isValid)
        XCTAssertTrue(error?.contains("invalid hex byte") ?? false)
    }

    func testValidatePatternNonHexNumber() {
        let pattern = "{cmdtag} {powertag} 123 {checksum}"
        let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
        XCTAssertFalse(isValid)
        XCTAssertTrue(error?.contains("does not start with 0x") ?? false)
    }
}
