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

    // MARK: - {mac} token tests

    func testMacTokenEmits6Bytes() {
        // {mac} should emit 6 bytes from a colon-separated MAC string
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x01 {checksum}"
        let values: [String: Any] = ["mac": "DF:24:3A:B4:46:5D"]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // Expected: 78 91 08 DF 24 3A B4 46 5D 8B 01 checksum
        // size = 8 (6 mac + 8B + 01)
        // checksum = (0x78+0x91+0x08+0xDF+0x24+0x3A+0xB4+0x46+0x5D+0x8B+0x01) & 0xFF
        let sum = 0x78+0x91+0x08+0xDF+0x24+0x3A+0xB4+0x46+0x5D+0x8B+0x01
        let expected = Data([0x78, 0x91, 0x08, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x01, UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testMacTokenPadsShortMAC() {
        // MAC with fewer than 6 octets should be zero-padded
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x01 {checksum}"
        let values: [String: Any] = ["mac": "AA:BB"]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // Expected: 78 91 08 AA BB 00 00 00 00 8B 01 checksum
        let sum = 0x78+0x91+0x08+0xAA+0xBB+0x00+0x00+0x00+0x00+0x8B+0x01
        let expected = Data([0x78, 0x91, 0x08, 0xAA, 0xBB, 0x00, 0x00, 0x00, 0x00, 0x8B, 0x01, UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testMacTokenEmptyStringGives6Zeros() {
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x01 {checksum}"
        let values: [String: Any] = ["mac": ""]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // Expected: 78 91 08 00 00 00 00 00 00 8B 01 checksum
        let sum = 0x78+0x91+0x08+0x00+0x00+0x00+0x00+0x00+0x00+0x8B+0x01
        let expected = Data([0x78, 0x91, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x8B, 0x01, UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    // MARK: - 17FX scene pattern tests (must match getSceneCommand output exactly)

    func testLightingScenePattern() {
        // Lighting (0x01): MAC + 8B + id + BRR + CCT + SPEED
        // Matches getSceneCommand() for fxx.id=1, brr=50, cct=37, speed=7
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x01 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {speed:uint8:range(1,10)} {checksum}"
        let values: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 50, "cct": 37, "speed": 7
        ]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // 78 91 0B DF 24 3A B4 46 5D 8B 01 32 25 07 checksum
        //                                         brr=50 cct=37 speed=7
        // size = 0x0B (6 mac + 8B + id + brr + cct + speed = 11)
        let bytes: [UInt8] = [0x78, 0x91, 0x0B, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x01, 0x32, 0x25, 0x07]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testPaparazziScenePattern() {
        // Paparazzi (0x02): MAC + 8B + id + BRR + CCT + GM + SPEED
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x02 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}"
        let values: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 50, "cct": 37, "gm": 50, "speed": 7
        ]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let bytes: [UInt8] = [0x78, 0x91, 0x0C, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x02, 0x32, 0x25, 0x32, 0x07]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testHueFlashScenePattern() {
        // HUE flash (0x07): MAC + 8B + id + BRR + HUE(2bytes LE) + SAT + SPEED
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x07 {brr:uint8:range(0,100)} {hue:uint16_le:range(0,360)} {sat:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}"
        let values: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 50, "hue": 200, "sat": 80, "speed": 5
        ]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // HUE 200 = 0x00C8, LE = C8 00
        let bytes: [UInt8] = [0x78, 0x91, 0x0D, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x07, 0x32, 0xC8, 0x00, 0x50, 0x05]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testCopCarScenePattern() {
        // Cop Car (0x0A): MAC + 8B + id + BRR + COLOR + SPEED
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0A {brr:uint8:range(0,100)} {color:uint8:range(0,4)} {speed:uint8:range(1,10)} {checksum}"
        let values: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 50, "color": 2, "speed": 7
        ]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let bytes: [UInt8] = [0x78, 0x91, 0x0B, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x0A, 0x32, 0x02, 0x07]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testExplosionScenePattern() {
        // Explosion (0x04): MAC + 8B + id + BRR + CCT + GM + SPEED + SPARKS
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x04 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {sparks:uint8:range(1,10)} {checksum}"
        let values: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 50, "cct": 37, "gm": 50, "speed": 7, "sparks": 5
        ]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let bytes: [UInt8] = [0x78, 0x91, 0x0D, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x04, 0x32, 0x25, 0x32, 0x07, 0x05]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testWeldingScenePattern() {
        // Welding (0x05): MAC + 8B + id + BRR_low + BRR_high + CCT + GM + SPEED
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x05 {brr:uint8:range(0,100)} {brr2:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}"
        let values: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 30, "brr2": 80, "cct": 45, "gm": 50, "speed": 5
        ]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        let bytes: [UInt8] = [0x78, 0x91, 0x0D, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x05, 0x1E, 0x50, 0x2D, 0x32, 0x05]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testHueLoopScenePattern() {
        // HUE Loop (0x0C): MAC + 8B + id + BRR + HUE_low(2B LE) + HUE_high(2B LE) + SPEED
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0C {brr:uint8:range(0,100)} {hue:uint16_le:range(0,360)} {hue2:uint16_le:range(0,360)} {speed:uint8:range(1,10)} {checksum}"
        let values: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 50, "hue": 30, "hue2": 300, "speed": 5
        ]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // hue=30=0x001E LE: 1E 00; hue2=300=0x012C LE: 2C 01
        // size = 14 (6 mac + 1 fxsubtag + 1 sceneId + 1 brr + 2 hue + 2 hue2 + 1 speed)
        let bytes: [UInt8] = [0x78, 0x91, 0x0E, 0xDF, 0x24, 0x3A, 0xB4, 0x46, 0x5D, 0x8B, 0x0C, 0x32, 0x1E, 0x00, 0x2C, 0x01, 0x05]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    // MARK: - 9FX simple scene pattern tests (must match getSceneValue output exactly)

    func testSimpleScenePattern() {
        // Simple scene: 78 88 02 [brr] [sceneId] [checksum]
        let pattern = "{cmdtag} {fxtag} {size} {brr:uint8:range(0,100)} 0x01 {checksum}"
        let values: [String: Any] = ["brr": 50]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // 78 88 02 32 01 checksum
        let bytes: [UInt8] = [0x78, 0x88, 0x02, 0x32, 0x01]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testSimpleScenePatternScene9() {
        // Scene 9 with brightness 100
        let pattern = "{cmdtag} {fxtag} {size} {brr:uint8:range(0,100)} 0x09 {checksum}"
        let values: [String: Any] = ["brr": 100]

        let data = CommandPatternParser.buildCommand(from: pattern, values: values)
        // 78 88 02 64 09 checksum
        let bytes: [UInt8] = [0x78, 0x88, 0x02, 0x64, 0x09]
        let sum = bytes.reduce(0) { $0 + UInt16($1) }
        let expected = Data(bytes + [UInt8(sum & 0xFF)])
        XCTAssertEqual(data, expected)
    }

    func testMacTokenValidation() {
        // {mac} should pass validation
        let pattern = "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x01 {checksum}"
        let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
        XCTAssertTrue(isValid)
        XCTAssertNil(error)
    }

    // MARK: - 17FX pattern⟷factory parity tests

    /// The 17 fxPatterns that will replace the hardcoded factory methods.
    /// Format: {cmdtag} {fxdatatag} {size} {mac} {fxsubtag} <sceneId> <params...> {checksum}
    static let fx17Patterns: [NamedPattern] = [
        NamedPattern(id: 1, name: "Lighting", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x01 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: "bolt.fill", color: nil),
        NamedPattern(id: 2, name: "Paparazzi", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x02 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: "camera.shutter.button", color: nil),
        NamedPattern(id: 3, name: "Defective bulb", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x03 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: "lightbulb.min.badge.exclamationmark.fill", color: nil),
        NamedPattern(id: 4, name: "Explosion", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x04 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {sparks:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: "timelapse", color: nil),
        NamedPattern(id: 5, name: "Welding", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x05 {brr:uint8:range(0,100)} {brr2:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 6, name: "CCT flash", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x06 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 7, name: "HUE flash", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x07 {brr:uint8:range(0,100)} {hue:uint16_le:range(0,360)} {sat:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 8, name: "CCT pulse", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x08 {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 9, name: "HUE pulse", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x09 {brr:uint8:range(0,100)} {hue:uint16_le:range(0,360)} {sat:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 10, name: "Cop Car", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0A {brr:uint8:range(0,100)} {color:uint8:range(0,4)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: ["Red", "Blue", "Red and Blue", "White and Blue", "Red blue white"]),
        NamedPattern(id: 11, name: "Candlelight", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0B {brr:uint8:range(0,100)} {brr2:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {sparks:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 12, name: "HUE Loop", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0C {brr:uint8:range(0,100)} {hue:uint16_le:range(0,360)} {hue2:uint16_le:range(0,360)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 13, name: "CCT Loop", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0D {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {cct2:uint8:range(29,70)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 14, name: "INT loop", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0E {brr:uint8:range(0,100)} {brr2:uint8:range(0,100)} {hue:uint16_le:range(0,360)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: nil, color: nil),
        NamedPattern(id: 15, name: "TV Screen", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x0F {brr:uint8:range(0,100)} {cct:uint8:range(29,70)} {gm:uint8:range(0,100)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: "tv", color: nil),
        NamedPattern(id: 16, name: "Firework", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x10 {brr:uint8:range(0,100)} {color:uint8:range(0,2)} {speed:uint8:range(1,10)} {sparks:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: "fireworks", color: ["Single color", "Color", "Combined"]),
        NamedPattern(id: 17, name: "Party", cmd: "{cmdtag} {fxdatatag} {size} {mac} {fxsubtag} 0x11 {brr:uint8:range(0,100)} {color:uint8:range(0,2)} {speed:uint8:range(1,10)} {checksum}", defaultCmd: nil, icon: "party.popper.fill", color: ["Single color", "Color", "Combined"]),
    ]

    func testAll17PatternsProduceValidBytes() {
        // Every pattern must produce non-empty bytes with sample values
        let sampleValues: [String: Any] = [
            "mac": "DF:24:3A:B4:46:5D",
            "brr": 50, "brr2": 80,
            "cct": 37, "cct2": 50,
            "gm": 50, "hue": 200, "hue2": 300,
            "sat": 80, "speed": 5, "sparks": 3, "color": 1
        ]
        for pattern in Self.fx17Patterns {
            let data = CommandPatternParser.buildCommand(from: pattern.cmd, values: sampleValues)
            XCTAssertFalse(data.isEmpty, "\(pattern.name): pattern produced empty data")
            // All 17FX patterns must start with 78 91
            XCTAssertEqual(data[0], 0x78, "\(pattern.name): first byte must be 0x78")
            XCTAssertEqual(data[1], 0x91, "\(pattern.name): second byte must be 0x91")
        }
    }

    func testDbHasFxPatternsForSupport17FXTypes() {
        // All support17FX types in the DB must resolve to 17 patterns via fxPreset
        ContentManager.shared.loadDatabaseFromDisk()
        let support17FXTypes: [UInt8] = [8, 16, 20, 22, 25, 34, 42, 49, 62, 69, 71]
        for lightType in support17FXTypes {
            guard let item = ContentManager.shared.fetchLightProperty(lightType: lightType) else {
                XCTFail("Type \(lightType) not found in DB")
                continue
            }
            XCTAssertEqual(item.fxPreset, "fx17_mac", "Type \(lightType) must use fx17_mac preset")
            let resolved = ContentManager.shared.resolvedFxPatterns(for: item)
            XCTAssertEqual(resolved.count, 17, "Type \(lightType) must resolve to 17 fxPatterns")
        }
    }

    func testDbHasFxPatternsForSupport9FXTypes() {
        // All support9FX types in the DB must resolve to 9 patterns via fxPreset
        ContentManager.shared.loadDatabaseFromDisk()
        let support9FXTypes: [UInt8] = [3, 5]
        for lightType in support9FXTypes {
            guard let item = ContentManager.shared.fetchLightProperty(lightType: lightType) else {
                XCTFail("Type \(lightType) not found in DB")
                continue
            }
            XCTAssertEqual(item.fxPreset, "fx9_simple", "Type \(lightType) must use fx9_simple preset")
            let resolved = ContentManager.shared.resolvedFxPatterns(for: item)
            XCTAssertEqual(resolved.count, 9, "Type \(lightType) must resolve to 9 fxPatterns")
        }
    }

    func testGetLightFXReturnsPatternBasedFX() {
        // RED→GREEN: getLightFX() for support17FX types must return FX with cmdPattern set
        ContentManager.shared.loadDatabaseFromDisk()
        let support17FXTypes: [UInt8] = [8, 16, 20, 22, 25, 34, 42, 49, 62, 69, 71]
        for lightType in support17FXTypes {
            let fxList = NeewerLightConstant.getLightFX(lightType: lightType)
            XCTAssertEqual(fxList.count, 17, "Type \(lightType) must have 17 FX")
            for fx in fxList {
                XCTAssertNotNil(fx.cmdPattern, "Type \(lightType) FX '\(fx.name)' must have cmdPattern")
            }
        }
    }

    func testGetLightFXReturnsPatternBasedFXFor9FX() {
        // RED→GREEN: getLightFX() for support9FX types must return FX with cmdPattern set
        ContentManager.shared.loadDatabaseFromDisk()
        let support9FXTypes: [UInt8] = [3, 5]
        for lightType in support9FXTypes {
            let fxList = NeewerLightConstant.getLightFX(lightType: lightType)
            XCTAssertEqual(fxList.count, 9, "Type \(lightType) must have 9 FX")
            for fx in fxList {
                XCTAssertNotNil(fx.cmdPattern, "Type \(lightType) FX '\(fx.name)' must have cmdPattern")
            }
        }
    }

    // MARK: - fxPresets resolution tests

    func testFxPresetResolvesAllPatterns() {
        // A type with fxPreset should resolve to all patterns from that preset group
        ContentManager.shared.loadDatabaseFromDisk()
        guard let item = ContentManager.shared.fetchLightProperty(lightType: 8) else {
            XCTFail("Type 8 not found"); return
        }
        XCTAssertEqual(item.fxPreset, "fx17_mac")
        XCTAssertNil(item.fxPatterns)
        let resolved = ContentManager.shared.resolvedFxPatterns(for: item)
        XCTAssertEqual(resolved.count, 17)
        XCTAssertEqual(resolved.first?.name, "Lighting")
        XCTAssertEqual(resolved.last?.name, "Party")
    }

    func testFxPresetResolvesUniqueFx18Sub() {
        // Type 39 uses fx18_sub preset with 18 patterns
        ContentManager.shared.loadDatabaseFromDisk()
        guard let item = ContentManager.shared.fetchLightProperty(lightType: 39) else {
            XCTFail("Type 39 not found"); return
        }
        XCTAssertEqual(item.fxPreset, "fx18_sub")
        let resolved = ContentManager.shared.resolvedFxPatterns(for: item)
        XCTAssertEqual(resolved.count, 18)
    }

    func testFxPatternsRefResolvesIndividualItems() {
        // fxPatterns with "preset/id" refs should cherry-pick individual patterns
        ContentManager.shared.loadDatabaseFromDisk()
        let item = NeewerLightDbItem(
            type: 255,
            image: "test",
            link: nil,
            supportRGB: nil,
            supportCCTGM: nil,
            supportMusic: nil,
            support17FX: nil,
            support9FX: nil,
            cctRange: nil,
            newPowerLightCommand: nil,
            newRGBLightCommand: nil,
            commandPatterns: nil,
            sourcePatterns: nil,
            fxPreset: "fx17_mac",
            fxPatterns: ["fx17_mac/1", "fx9_simple/5", "fx17_mac/10"]
        )
        let resolved = ContentManager.shared.resolvedFxPatterns(for: item)
        XCTAssertEqual(resolved.count, 3)
        XCTAssertEqual(resolved[0].name, "Lighting")    // fx17_mac/1
        XCTAssertEqual(resolved[1].name, "Party")        // fx9_simple/5
        XCTAssertEqual(resolved[2].name, "Cop Car")      // fx17_mac/10
    }

    func testFxPatternsRefTakesPriorityOverPreset() {
        // When both fxPatterns and fxPreset are set, fxPatterns wins
        ContentManager.shared.loadDatabaseFromDisk()
        let item = NeewerLightDbItem(
            type: 255,
            image: "test",
            link: nil,
            supportRGB: nil,
            supportCCTGM: nil,
            supportMusic: nil,
            support17FX: nil,
            support9FX: nil,
            cctRange: nil,
            newPowerLightCommand: nil,
            newRGBLightCommand: nil,
            commandPatterns: nil,
            sourcePatterns: nil,
            fxPreset: "fx17_mac",
            fxPatterns: ["fx9_simple/1"]
        )
        let resolved = ContentManager.shared.resolvedFxPatterns(for: item)
        XCTAssertEqual(resolved.count, 1)
        XCTAssertEqual(resolved[0].name, "Squard Car")  // from fx9_simple, not fx17_mac
    }

    func testNoFxPresetOrPatternsReturnsEmpty() {
        ContentManager.shared.loadDatabaseFromDisk()
        let item = NeewerLightDbItem(
            type: 255,
            image: "test",
            link: nil,
            supportRGB: nil,
            supportCCTGM: nil,
            supportMusic: nil,
            support17FX: nil,
            support9FX: nil,
            cctRange: nil,
            newPowerLightCommand: nil,
            newRGBLightCommand: nil,
            commandPatterns: nil,
            sourcePatterns: nil,
            fxPreset: nil,
            fxPatterns: nil
        )
        let resolved = ContentManager.shared.resolvedFxPatterns(for: item)
        XCTAssertTrue(resolved.isEmpty)
    }
}
