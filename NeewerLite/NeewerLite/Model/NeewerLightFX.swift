//
//  NeewerLightFX.swift
//  NeewerLite
//
//  Created by Xu Lian on 10/25/23.
//

import Foundation

struct ColorItem: Codable {
    let key: String
    let value: Int

    enum CodingKeys: String, CodingKey {
        case key
        case value
    }
}

class NeewerLightFX: NSObject, Codable {
    var id: UInt16
    var name: String
    var name_key: String {
        return name.lowercased().replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }
    var iconName: String
    var imageURL: String?
    var category: String?
    var cmdPattern: String?
    
    var needBRR: Bool = false
    var needBRRUpperBound: Bool = false
    var needCCT: Bool = false
    var needCCTUpperBound: Bool = false
    var needGM: Bool = false
    var needSAT: Bool = false
    var needHUE: Bool = false
    var needHUEUpperBound: Bool = false
    var needSpeed: Bool = false
    var speedLevel: UInt8 = 0
    var needSparks: Bool = false
    var sparkLevel: [UInt8] = []
    var needColor: Bool = false
    var colors: [ColorItem] = []

    var featureValues: [String: CGFloat] = [:]
    
    init(id: UInt16, name: String) {
        self.id = id
        self.name = name
        self.iconName = ""
        super.init()
    }

    init(id: UInt16, name: String, brr: Bool) {
        self.id = id
        self.name = name
        self.needBRR = brr
        self.iconName = ""
        super.init()
    }

    override var description: String {
        return "[\(self.id), \(self.name), \(featureValues)]"
    }

    // Computed properties to access specific features' CGFloat values conveniently
    var brrValue: CGFloat {
        get { featureValues["brrValue"] ?? 50.0 }
        set { featureValues["brrValue"] = newValue }
    }
    var brrUpperValue: CGFloat {
        get { featureValues["brrUpperValue"] ?? 80.0 }
        set { featureValues["brrUpperValue"] = newValue }
    }
    var cctValue: CGFloat {
        get { featureValues["cctValue"] ?? 10.0 }
        set { featureValues["cctValue"] = newValue }
    }
    var cctUpperValue: CGFloat {
        get { featureValues["cctUpperValue"] ?? 20.0 }
        set { featureValues["cctUpperValue"] = newValue }
    }
    var gmValue: CGFloat {
        get { featureValues["gmValue"] ?? -50.0 }
        set { featureValues["gmValue"] = newValue }
    }

    var satValue: CGFloat {
        get { featureValues["satValue"] ?? 10.0 }
        set { featureValues["satValue"] = newValue }
    }

    var hueValue: CGFloat {
        get { featureValues["hueValue"] ?? 10.0 }
        set { featureValues["hueValue"] = newValue }
    }

    var hueUpperValue: CGFloat {
        get { featureValues["hueUpperValue"] ?? 180.0 }
        set { featureValues["hueUpperValue"] = newValue }
    }

    var speedValue: Int {
        get { Int(featureValues["speedValue"] ?? 1) }
        set { featureValues["speedValue"] = CGFloat(newValue) }
    }

    var sparksValue: Int {
        get { Int(featureValues["sparksValue"] ?? 1) }
        set { featureValues["sparksValue"] = CGFloat(newValue) }
    }

    var colorValue: Int {
        get { Int(featureValues["colorValue"] ?? 1) }
        set { featureValues["colorValue"] = CGFloat(newValue) }
    }
}

extension NeewerLightFX {
    
    struct FieldSpec {
        let name: String
        let type: String
        let min: Int
        let max: Int
        var closedRange: ClosedRange<Int> { min...max }
    }

    class func parseFields(_ format: String) -> [String: FieldSpec] {
        // {name:type:range(min,max)}
        let r = #/\{\s*(?<name>[A-Za-z_]\w*)\s*:\s*(?<type>[A-Za-z0-9_]+)\s*:\s*range\(\s*(?<min>\d+)\s*,\s*(?<max>\d+)\s*\)\s*\}/#

        var out: [String: FieldSpec] = [:]

        for m in format.matches(of: r) {
            let name = String(m.output.name)
            let type = String(m.output.type)
            let min  = Int(m.output.min)!
            let max  = Int(m.output.max)!

            // Skip invalid ranges
            guard min <= max else { continue }
            // Keep first occurrence; ignore later duplicates (optional)
            if out[name] == nil {
                out[name] = FieldSpec(name: name, type: type, min: min, max: max)
            }
        }
        return out
    }

    class func parseNamedCmdToFX(item: NamedPattern) -> NeewerLightFX {
        let scene = NeewerLightFX(id: UInt16(item.id), name: item.name)
        scene.cmdPattern = item.cmd
        if let icon = item.icon {
            scene.iconName = icon
        }
        scene.imageURL = item.image
        scene.category = item.category
        let fields = parseFields(item.cmd)
        let flagMappings: [(String, ReferenceWritableKeyPath<NeewerLightFX, Bool>)] = [
            ("brr", \.needBRR),
            ("brr2", \.needBRRUpperBound),
            ("cct", \.needCCT),
            ("cct2", \.needCCTUpperBound),
            ("gm", \.needGM),
            ("hue", \.needHUE),
            ("hue2", \.needHUEUpperBound),
            ("sat", \.needSAT)
        ]
        for (key, keyPath) in flagMappings {
            if fields[key] != nil {
                scene[keyPath: keyPath] = true
            }
        }
        if let sparks = fields["sparks"] {
            scene.needSparks = true
            scene.speedLevel = UInt8(sparks.max)
        }
        if let speed = fields["speed"] {
            scene.needSpeed = true
            scene.speedLevel = UInt8(speed.max)
        }
        if let color = fields["color"] {
            scene.needColor = true
            scene.colors = color.closedRange.map { ColorItem(key: item.color?[$0] ?? "\($0)", value: $0) }
        }
        return scene
    }

}
