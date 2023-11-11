//
//  CodableValue.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/5/23.
//

import Foundation

// Create an enum that can represent any Codable value
enum CodableValue: Codable, CustomStringConvertible {
    case intValue(Int)
    case stringValue(String)
    case boolValue(Bool)
    case int8Value(Int8)
    case uint8Value(UInt8)
    case fxValue(NeewerLightFX)
    case fxsValue([NeewerLightFX])
    case sourceValue(NeewerLightSource)
    case sourcesValue([NeewerLightSource])

    // Implement Codable for the enum
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .intValue(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .stringValue(stringValue)
        } else if let boolValue = try? container.decode(Bool.self) {
            self = .boolValue(boolValue)
        } else if let int8Value = try? container.decode(Int8.self) {
            self = .int8Value(int8Value)
        } else if let uint8Value = try? container.decode(UInt8.self) {
            self = .uint8Value(uint8Value)
        } else if let fxValue = try? container.decode(NeewerLightFX.self) {
            self = .fxValue(fxValue)
        } else if let fxsValue = try? container.decode([NeewerLightFX].self) {
            self = .fxsValue(fxsValue)
        } else if let sourceValue = try? container.decode(NeewerLightSource.self) {
            self = .sourceValue(sourceValue)
        } else if let sourcesValue = try? container.decode([NeewerLightSource].self) {
            self = .sourcesValue(sourcesValue)
        } else {
            throw DecodingError.typeMismatch(CodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported type for CodableValue"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .intValue(let intValue):
                try container.encode(intValue)
            case .stringValue(let stringValue):
                try container.encode(stringValue)
            case .boolValue(let boolValue):
                try container.encode(boolValue)
            case .int8Value(let int8Value):
                try container.encode(int8Value)
            case .uint8Value(let uint8Value):
                try container.encode(uint8Value)
            case .fxValue(let fxValue):
                try container.encode(fxValue)
            case .fxsValue(let fxsValue):
                try container.encode(fxsValue)
            case .sourceValue(let sourceValue):
                try container.encode(sourceValue)
            case .sourcesValue(let sourcesValue):
                try container.encode(sourcesValue)
        }
    }

    var description: String {
        switch self {
            case .intValue(let value):
                return "\(value)"
            case .stringValue(let value):
                return value
            case .boolValue(let value):
                return "\(value)"
            case .int8Value(let value):
                return "\(value)"
            case .uint8Value(let value):
                return "\(value)"
            case .fxValue(let value):
                return "\(value)"
            case .fxsValue(let value):
                return "\(value)"
            case .sourceValue(let value):
                return "\(value)"
            case .sourcesValue(let value):
                return "\(value)"
        }
    }

    // Provide a computed property for each case to get its associated value
    var stringValue: String? {
        if case let .stringValue(value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case let .intValue(value) = self { return value }
        return nil
    }

    var uint8Value: UInt8? {
        if case let .uint8Value(value) = self { return value }
        return nil
    }

    var int8Value: Int8? {
        if case let .int8Value(value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case let .boolValue(value) = self { return value }
        return nil
    }

    var fxValue: NeewerLightFX? {
        if case let .fxValue(value) = self { return value }
        return nil
    }

    var fxsValue: [NeewerLightFX]? {
        if case let .fxsValue(value) = self { return value }
        return nil
    }

    var sourceValue: NeewerLightSource? {
        if case let .sourceValue(value) = self { return value }
        return nil
    }

    var sourcesValue: [NeewerLightSource]? {
        if case let .sourcesValue(value) = self { return value }
        return nil
    }
}
