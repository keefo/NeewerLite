//
//  NeewerLightFX.swift
//  NeewerLite
//
//  Created by Xu Lian on 10/25/23.
//

import Foundation

class NeewerLightSource: NSObject, Codable {
    var id: UInt16
    var name: String
    
    var cmdPattern: String?
    var defaultCmdPattern: String?
    var iconName: String
    
    var needBRR: Bool = false
    var needCCT: Bool = false
    var needGM: Bool = false

    var featureValues: [String: CGFloat] = [:]
    /// Original preset CCT/GM — not persisted, always set from factory methods.
    var defaultCCTValue: CGFloat?
    var defaultGMValue: CGFloat?

    private enum CodingKeys: String, CodingKey {
        case id, name, cmdPattern, defaultCmdPattern, iconName
        case needBRR, needCCT, needGM, featureValues
    }

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
    var cctValue: CGFloat {
        get { featureValues["cctValue"] ?? 10.0 }
        set { featureValues["cctValue"] = newValue }
    }
    var gmValue: CGFloat {
        get { featureValues["gmValue"] ?? -50.0 }
        set { featureValues["gmValue"] = newValue }
    }
}

extension NeewerLightSource {

    
    class func parseNamedCmdToLightSource(item: NamedPattern) -> NeewerLightSource {
        
        let src = NeewerLightSource(id: UInt16(item.id), name: item.name)
        src.cmdPattern = item.cmd
        if let icon = item.icon {
            src.iconName = icon
        }
        src.defaultCmdPattern = item.defaultCmd
        let fields = NeewerLightFX.parseFields(item.cmd)
        let flagMappings: [(String, ReferenceWritableKeyPath<NeewerLightSource, Bool>)] = [
            ("brr", \.needBRR),
            ("cct", \.needCCT),
            ("gm", \.needGM),
        ]
        for (key, keyPath) in flagMappings {
            if fields[key] != nil {
                src[keyPath: keyPath] = true
            }
        }
        return src
    }
    
    
    // Class method to create a "Lighting" scene
    class func sunlightSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x01, name: "Sunlight")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 56  // 5600K
        scene.gmValue = 4
        scene.defaultCCTValue = 56
        scene.defaultGMValue = 4
        return scene
    }

    class func whiteHalogenSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x02, name: "White Halogen light")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 32  // 3200K
        scene.gmValue = 2
        scene.defaultCCTValue = 32
        scene.defaultGMValue = 2
        return scene
    }

    class func xenonShortarcLampSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x03, name: "Xenon short-arc lamp")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 60  // 6000K
        scene.gmValue = -8
        scene.defaultCCTValue = 60
        scene.defaultGMValue = -8
        return scene
    }

    class func horizonDaylightSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x04, name: "Horizon daylight")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 25  // 2500K — golden hour
        scene.gmValue = 8
        scene.defaultCCTValue = 25
        scene.defaultGMValue = 8
        return scene
    }

    class func daylightSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x05, name: "Daylight")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 55  // 5500K
        scene.gmValue = 0
        scene.defaultCCTValue = 55
        scene.defaultGMValue = 0
        return scene
    }

    class func tungstenSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x06, name: "Tungsten")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 32  // 3200K
        scene.gmValue = -4
        scene.defaultCCTValue = 32
        scene.defaultGMValue = -4
        return scene
    }

    class func studioBulbSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x07, name: "Studio Bulb")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 34  // 3400K
        scene.gmValue = -2
        scene.defaultCCTValue = 34
        scene.defaultGMValue = -2
        return scene
    }

    class func modelingLightsSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x08, name: "Modeling Lights")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 45  // 4500K
        scene.gmValue = 0
        scene.defaultCCTValue = 45
        scene.defaultGMValue = 0
        return scene
    }

    class func dysprosicLampSource() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x09, name: "Dysprosic lamp")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 58  // 5800K
        scene.gmValue = -6
        scene.defaultCCTValue = 58
        scene.defaultGMValue = -6
        return scene
    }

    class func hmi6000Source() -> NeewerLightSource {
        let scene = NeewerLightSource(id: 0x0A, name: "HMI6000")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.cctValue = 60  // 6000K
        scene.gmValue = 2
        scene.defaultCCTValue = 60
        scene.defaultGMValue = 2
        return scene
    }
}
