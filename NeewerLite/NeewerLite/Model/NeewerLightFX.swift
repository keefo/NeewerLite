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
        super.init()
    }

    init(id: UInt16, name: String, brr: Bool) {
        self.id = id
        self.name = name
        self.needBRR = brr
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

    // Class method to create a "Lighting" scene
    class func lightingScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x01, name: "Lighting")
        scene.needBRR = true
        scene.needCCT = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "Paparazzi" scene
    class func paparazziScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x02, name: "Paparazzi")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "Defective bulb" scene
    class func defectiveBulbScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x03, name: "Defective bulb")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create an "Explosion" scene
    class func explosionScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x04, name: "Explosion")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        scene.needSparks = true
        scene.sparkLevel = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]
        return scene
    }

    // Class method to create a "Welding" scene
    class func weldingScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x05, name: "Welding")
        scene.needBRR = true
        scene.needBRRUpperBound = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "CCT flash" scene
    class func cctFlashScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x06, name: "CCT flash")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "HUE flash" scene
    class func hueFlashScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x07, name: "HUE flash")
        scene.needBRR = true
        scene.needHUE = true
        scene.needSAT = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "CCT pulse" scene
    class func cctPulseScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x08, name: "CCT pulse")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "HUE pulse" scene
    class func huePulseScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x09, name: "HUE pulse")
        scene.needBRR = true
        scene.needHUE = true
        scene.needSAT = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "Cop Car" scene
    class func copCarScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x0A, name: "Cop Car")
        scene.needBRR = true
        scene.needColor = true
        scene.colors = [ColorItem(key: "Red", value: 0x00),
                        ColorItem(key: "Blue", value: 0x01),
                        ColorItem(key: "Red and Blue", value: 0x2),
                        ColorItem(key: "White and Blue", value: 0x3),
                        ColorItem(key: "Red blue white", value: 0x4)]
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "Candlelight" scene
    class func candlelightScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x0B, name: "Candlelight")
        scene.needBRR = true
        scene.needBRRUpperBound = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        scene.needSparks = true
        scene.sparkLevel = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]
        return scene
    }

    // Class method to create a "HUE Loop" scene
    class func hueLoopScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x0C, name: "HUE Loop")
        scene.needBRR = true
        scene.needHUE = true
        scene.needHUEUpperBound = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "CCT Loop" scene
    class func cctLoopScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x0D, name: "CCT Loop")
        scene.needBRR = true
        scene.needCCT = true
        scene.needCCTUpperBound = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create an "INT loop" scene
    class func intLoopScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x0E, name: "INT loop")
        scene.needBRR = true
        scene.needBRRUpperBound = true
        scene.needHUE = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "TV Screen" scene
    class func tvScreenScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x0F, name: "TV Screen")
        scene.needBRR = true
        scene.needCCT = true
        scene.needGM = true
        scene.needSpeed = true
        scene.speedLevel = 10
        return scene
    }

    // Class method to create a "Firework" scene
    class func fireworkScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x10, name: "Firework")
        scene.needBRR = true
        scene.needSpeed = true
        scene.speedLevel = 10
        scene.needColor = true
        scene.colors = [ColorItem(key: "Single color", value: 0x00),
                        ColorItem(key: "Color", value: 0x01),
                        ColorItem(key: "Combined", value: 0x2)]
        scene.needSparks = true
        scene.sparkLevel = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A]
        return scene
    }

    // Class method to create a "Party" scene
    class func partyScene() -> NeewerLightFX {
        let scene = NeewerLightFX(id: 0x11, name: "Party")
        scene.needBRR = true
        scene.needSpeed = true
        scene.speedLevel = 10
        scene.needColor = true
        scene.colors = [ColorItem(key: "Single color", value: 0x00),
                        ColorItem(key: "Color", value: 0x01),
                        ColorItem(key: "Combined", value: 0x2)]
        return scene
    }
}
