//
//  CommandPatternParser.swift
//  CommandPatternParser
//
//  Created by Xu Lian on 07/24/25.
//
import Foundation

fileprivate let knownVars: Set<String> = [
    "cmdtag", "powertag", "ccttag", "hsitag", "rgbtag", "size", "checksum"
]
fileprivate let validTypes = [
    "uint8", "uint16_le", "uint16_be", "hex"
]

struct CommandPatternParser {
    static func tokenize(pattern: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var insideBraces = false

        for char in pattern {
            if char == "{" {
                insideBraces = true
                current.append(char)
            } else if char == "}" {
                insideBraces = false
                current.append(char)
            } else if char == " " && !insideBraces {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
    
    static func toInt(_ value: Any) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let str as String:
            if let doubleValue = Double(str) {
                return Int(doubleValue)   // truncates fractional part
            }
            return nil
        case let double as Double:
            return Int(double)
        case let float as Float:
            return Int(float)
        case let number as NSNumber:
            return number.intValue
        default:
            return nil
        }
    }
    
    static func toInt8(_ value: Any) -> Int8? {
        let intValue: Int?

        switch value {
        case let int as Int:
            intValue = int
        case let str as String:
            if let doubleValue = Double(str) {
                intValue = Int(doubleValue) // truncates decimals
            } else {
                intValue = nil
            }
        case let double as Double:
            intValue = Int(double)
        case let float as Float:
            intValue = Int(float)
        case let number as NSNumber:
            intValue = number.intValue
        default:
            intValue = nil
        }

        // Now check Int8 range
        if let intValue = intValue,
           intValue >= Int(Int8.min), intValue <= Int(Int8.max) {
            return Int8(intValue)
        }

        return nil // out of range or not convertible
    }
    
    static func buildCommand(from pattern: String, values: [String: Any]) -> Data {
        let tokens = tokenize(pattern: pattern)
        var bytes: [UInt8] = []
        var sizeIndex: Int? = nil
        var afterSize = false
        var payloadLength = 0

        for (_, token) in tokens.enumerated()
        {
            if token.hasPrefix("{") && token.hasSuffix("}") {
                let inner = String(token.dropFirst().dropLast())
                let parts = inner.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
                let field = String(parts[0])
                let type = parts.count > 1 ? String(parts[1]) : "uint8"
                let extra = parts.count > 2 ? String(parts[2]) : nil

                if field == "checksum" {
                    // Do not count checksum in payload size
                    continue
                } else if field == "cmdtag" {
                    bytes.append(UInt8(NeewerLightConstant.BleCommand.prefixTag))
                } else if field == "powertag" {
                    bytes.append(UInt8(NeewerLightConstant.BleCommand.powerTag))
                } else if field == "ccttag" {
                    bytes.append(UInt8(NeewerLightConstant.BleCommand.setCCTLightTag))
                } else if field == "hsitag" {
                    bytes.append(UInt8(NeewerLightConstant.BleCommand.setRGBLightTag))
                } else if field == "fxtag" {
                    bytes.append(UInt8(NeewerLightConstant.BleCommand.setSceneTag))
                } else if field == "fxsubtag" {
                    bytes.append(UInt8(NeewerLightConstant.BleCommand.setSCESubTag))
                } else if field == "size" {
                    sizeIndex = bytes.count
                    bytes.append(0) // placeholder for size
                    afterSize = true
                } else if let value = values[field] {
                    // --- ENUM SUPPORT ---
                    if let extra = extra, extra.starts(with: "enum(") {
                        let enumMap = parseEnum(extra)
                        if let intValue = value as? Int, enumMap.values.contains(intValue) {
                            bytes.append(UInt8(intValue))
                            if afterSize { payloadLength += 1 }
                        } else if let strValue = value as? String, let mapped = enumMap[strValue] {
                            bytes.append(UInt8(mapped))
                            if afterSize { payloadLength += 1 }
                        } else {
                            Logger.warn("tag \(token) value is invalid \(value)")
                            return Data()
                        }
                    // --- RANGE SUPPORT ---
                    } else if let extra = extra, extra.starts(with: "range(") {
                        let (min, max) = parseRange(extra)
                        if type == "uint8" {
                            if let intValue = toInt8(value) {
                                var intValue = intValue
                                if intValue < min {
                                    intValue = Int8(min)
                                }
                                else if intValue > max {
                                    intValue = Int8(max)
                                }
                                bytes.append(UInt8(intValue))
                                if afterSize { payloadLength += 1 }
                            }
                            else {
                                Logger.warn("tag \(token) value is invalid \(value)")
                                return Data()
                            }
                        } else if type == "uint16_le" {
                            if let intValue = toInt(value) {
                                var intValue = intValue
                                if intValue < min {
                                    intValue = min
                                }
                                else if intValue > max {
                                    intValue = max
                                }
                                bytes.append(UInt8(intValue & 0xFF))
                                bytes.append(UInt8((intValue >> 8) & 0xFF))
                                if afterSize { payloadLength += 2 }
                            } else {
                                Logger.warn("tag \(token) value is invalid \(value)")
                                return Data()
                            }
                        } else if type == "uint16_be" {
                            if let intValue = toInt(value) {
                                var intValue = intValue
                                if intValue < min {
                                    intValue = min
                                }
                                else if intValue > max {
                                    intValue = max
                                }
                                bytes.append(UInt8((intValue >> 8) & 0xFF))
                                bytes.append(UInt8(intValue & 0xFF))
                                if afterSize { payloadLength += 2 }
                            } else {
                                Logger.warn("tag \(token) value is invalid \(value)")
                                return Data()
                            }
                        } else {
                            // fallback for other types
                            if let intValue = toInt(value) {
                                var intValue = intValue
                                if intValue < min {
                                    intValue = min
                                }
                                else if intValue > max {
                                    intValue = max
                                }
                                bytes.append(UInt8(intValue))
                                if afterSize { payloadLength += 1 }
                            } else {
                                Logger.warn("tag \(token) value is invalid \(value)")
                                return Data()
                            }
                        }
                    } else if type == "uint8", let intValue = toInt(value) {
                        bytes.append(UInt8(intValue < 0 ? intValue + 0x100 : intValue))
                        if afterSize { payloadLength += 1 }
                    } else if type == "uint8", let uintValue = toInt8(value) {
                        bytes.append(UInt8(uintValue))
                        if afterSize { payloadLength += 1 }
                    } else if type == "uint16_le", let intValue = toInt(value) {
                        // Little-endian: low byte first, then high byte
                        bytes.append(UInt8(intValue & 0xFF))
                        bytes.append(UInt8((intValue >> 8) & 0xFF))
                        if afterSize { payloadLength += 2 }
                    } else if type == "uint16_be", let intValue = toInt(value) {
                        // Big-endian: high byte first, then low byte
                        bytes.append(UInt8((intValue >> 8) & 0xFF))
                        bytes.append(UInt8(intValue & 0xFF))
                        if afterSize { payloadLength += 2 }
                    } else if type == "hex", let hexString = value as? String, let byte = UInt8(hexString, radix: 16) {
                        bytes.append(byte)
                        if afterSize { payloadLength += 1 }
                    } else {
                        if let intValue = toInt(value) {
                            bytes.append(UInt8(intValue < 0 ? intValue + 0x100 : intValue))
                            if afterSize { payloadLength += 1 }
                        }
                    }
                } else {
                    Logger.warn("Unsupported tag \(token) in command pattern \(pattern)")
                    return Data()
                }
            } else if token.hasPrefix("0x"), let byte = UInt8(token.dropFirst(2), radix: 16) {
                bytes.append(byte)
                if afterSize { payloadLength += 1 }
            } else {
                Logger.warn("Unsupported tag \(token) in command pattern \(pattern)")
                return Data()
            }
        }

        // Fill in the size byte if needed
        if let sizeIndex = sizeIndex {
            bytes[sizeIndex] = UInt8(payloadLength)
        }

        // Handle checksum (must be last in pattern)
        if let lastToken = tokens.last,
           lastToken.hasPrefix("{"),
           lastToken.hasSuffix("}"),
           lastToken.contains("checksum") {
            let sum = bytes.reduce(0) { $0 + UInt16($1) }
            bytes.append(UInt8(sum & 0xFF))
        }

        return Data(bytes)
    }

    private static func parseEnum(_ enumString: String) -> [String: Int] {
        var result: [String: Int] = [:]
        let trimmed = enumString.replacingOccurrences(of: "enum(", with: "").replacingOccurrences(of: ")", with: "")
        let pairs = trimmed.split(separator: ",")
        for pair in pairs {
            let parts = pair.split(separator: "=")
            if parts.count == 2,
               let key = parts.last,
               let value = Int(parts.first!.trimmingCharacters(in: .whitespaces)) {
                result[String(key).trimmingCharacters(in: .whitespaces)] = value
            }
        }
        return result
    }

    private static func parseRange(_ rangeString: String) -> (Int, Int) {
        let trimmed = rangeString.replacingOccurrences(of: "range(", with: "").replacingOccurrences(of: ")", with: "")
        let parts = trimmed.split(separator: ",")
        if parts.count == 2,
           let min = Int(parts[0].trimmingCharacters(in: .whitespaces)),
           let max = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
            return (min, max)
        }
        return (Int.min, Int.max)
    }
}

extension CommandPatternParser {
    /// Returns (isValid, errorMessage)
    static func validate(pattern: String) -> (Bool, String?) {
        let tokens = tokenize(pattern: pattern)
        guard !tokens.isEmpty else { return (false, "Pattern is empty.") }

        for (i, token) in tokens.enumerated() {
            if token.hasPrefix("{") && token.hasSuffix("}") {
                let inner = String(token.dropFirst().dropLast())
                let parts = inner.split(separator: ":", omittingEmptySubsequences: false)
                // Must have at least field name
                if parts.isEmpty { return (false, "Token \(i+1) is missing field name.") }
                let field = String(parts[0])
                // If type is present, check it's a known type
                if parts.count > 1 {
                    let type = String(parts[1])
                    if !validTypes.contains(type) {
                        return (false, "Token \(i+1) has unknown type '\(type)'.")
                    }
                } else {
                    // If no type and not a known var, report unknown var
                    if !knownVars.contains(field) {
                        return (false, "Token \(i+1) has unknown variable '\(field)'.")
                    }
                }
                // If extra is present, check enum/range format
                if parts.count > 2 {
                    let extra = String(parts[2])
                    if !(extra.starts(with: "enum(") || extra.starts(with: "range(")) {
                        return (false, "Token \(i+1) has invalid extra '\(extra)'.")
                    }
                }
            } else if token.hasPrefix("0x") {
                // Should be a valid hex byte
                if UInt8(token.dropFirst(2), radix: 16) == nil {
                    return (false, "Token \(i+1) has invalid hex byte '\(token)'.")
                }
            } else {
                // If token is a number, it must start with 0x
                if let _ = UInt(token) {
                    return (false, "Token \(i+1) is a number but does not start with 0x (must be hex).")
                }
            }
        }
        // If we got here, pattern is valid
        return (true, nil)
    }
}
