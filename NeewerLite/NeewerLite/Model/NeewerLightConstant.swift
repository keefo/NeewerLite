//
//  NeewerLightConstant.swift
//  NeewerLite
//
//  Created by Xu Lian on 10/23/23.
//

import Foundation
import CoreBluetooth
import IOBluetooth

class NeewerLightConstant {

    struct Constants {
        static let NeewerBleServiceUUID = CBUUID(string: "69400001-B5A3-F393-E0A9-E50E24DCCA99")
        static let NeewerDeviceCtlCharacteristicUUID = CBUUID(string: "69400002-B5A3-F393-E0A9-E50E24DCCA99")
        static let NeewerGattCharacteristicUUID = CBUUID(string: "69400003-B5A3-F393-E0A9-E50E24DCCA99")
    }

    struct BleCommand {
        static let prefixTag = 0x78         // 120 Every bluettooth cmd start with 120
        static let setLongCCTLightBrightnessTag = 0x82  // 130 Set long CCT Light brightness.
        static let setLongCCTLightCCTTag = 0x83         // 131 Set long CCT Light CCT.

        static let setRGBLightTag = 0x86  // 134 Set RGB Light Mode.
        static let setCCTLightTag = 0x87  // 135 Set CCT Light Mode.

        static let setSceneTag = 0x88      // 136 Set Scene Light Mode.
        static let setSCESubTag =  0x8B  //

        static let setHSVDataTag = 0x89  // 143 Set Continuity RGB Light HSV data.
        static let setCCTDataTag = 0x90  // 144 Set Continuity RGB Light Mode.
        static let setSCEDataTag = 0x91  //

        static let powerOn = Data([0x78, 0x81, 0x01, 0x01, 0xFB])
        static let powerOff = Data([0x78, 0x81, 0x01, 0x02, 0xFC])
        static let readRequest = Data([0x78, 0x84, 0x00, 0xFC])
    }

    class func getRGBLightTypes() -> [UInt8] {
        return [3, 5, 8, 9, 11, 12, 15, 16, 18, 19, 20, 21, 22, 26, 29, 32, 34, 39, 40, 42, 43, 56, 57, 59]
    }

    class func getMusicSupportLightTypes() -> [UInt8] {
        return [8, 18, 43, 20, 21, 40, 14, 34, 25, 30, 38, 28, 19, 26, 42, 16, 27, 32, 37, 31, 22, 44, 46, 45, 47, 49, 50, 51, 52, 53, 54, 55, 39, 58, 56, 57, 59, 60, 61, 62, 63]
    }

    class func getRGBLightTypesThatSupport17FX() -> [UInt8] {
        return [8, 16, 20, 22, 34, 40]
    }

    class func getRGBLightTypesThatSupport9FX() -> [UInt8] {
        return [3, 5]
    }

    class func isValidPeripheralName(_ peripheralName: String) -> Bool {
        let name = peripheralName.lowercased()
        if name.contains("nwr") ||
            name.contains("neewer") ||
            name.contains("sl") ||
            name.starts(with: "nw-") || // https://github.com/keefo/NeewerLite/issues/19
            name.starts(with: "neewer-") ||
            name.contains("nee") // https://github.com/keefo/NeewerLite/issues/15
        {
            return true
        }
        return false
    }

    class func getProjectName(_ idx: Int) -> String {
        switch idx {
            case 8:
                return "RGB1"
            case 14:
                return "SL90"
            case 18:
                return "RGB1200"
            case 21:
                return "RGB C80"
            case 22:
                return "CB60 RGB"
            case 24:
                return "Apollo 150D"
            case 25:
                return "MS60C"
            case 26:
                return "BH-30S RGB"
            case 28:
                return "CB200B"
            case 30:
                return "MS60B"
            case 31:
                return "CB60B"
            case 32:
                return "TL60 RGB"
            case 34:
                return "SL90 Pro"
            case 40:
                return "RGB62"
            case 42:
                return "BH-30S RGB"
            case 43:
                return "RGB1200"
            case 47:
                return "CB300B"
            case 49:
                return "CB100C"
            case 50:
                return "TL120C"
            case 53:
                return "FS230 5600K"
            case 54:
                return "FS150 5600K"
            case 55:
                return "FS230B"
            case 58:
                return "AS600B"
            case 59:
                return "TL60 RGB"
            case 60:
                return "PL60C"
            case 63:
                return "RP19C"
            default:
                return ""
        }
    }

    class func getProjectName(_ str: String) -> String {
        switch str {
            case "20200015":
                return "RGB1"
            case "20200037":
                return "SL90"
            case "20200049":
                return "RGB1200"
            case "20210006":
                return "Apollo 150D"
            case "20210007":
                return "RGB C80"
            case "20210012":
                return "CB60 RGB"
            case "20210018":
                return "BH-30S RGB"
            case "20210034":
                return "MS60B"
            case "20210035":
                return "MS60C"
            case "20210036":
                return "TL60 RGB"
            case "20210037":
                return "CB200B"
            case "20220014":
                return "CB60B"
            case "20220016":
                return "PL60C"
            case "20220035":
                return "MS150B"
            case "20220041":
                return "AS600B"
            case "20220043":
                return "FS150B"
            case "20220046":
                return "RP19C"
            case "20220051":
                return "CB100C"
            case "20220055":
                return "CB300B"
            case "20220057":
                return "SL90 Pro"
            case "20230021":
                return "BH-30S RGB"
            case "20230025":
                return "RGB1200"
            case "20230031":
                return "TL120C"
            case "20230050":
                return "FS230 5600K"
            case "20230051":
                return "FS230B"
            case "20230052":
                return "FS150 5600K"
            case "20230064":
                return "TL60 RGB"
            default:
                return ""
        }
    }

    class func isRGBOther(_ str: String) -> Bool {
        let STR = str.uppercased()
        return "RGB480" == STR
        || "RGB530" == STR
        || "RGB660" == STR
        || "RGB530 PRO" == STR
        || "RGB660 PRO" == STR
        || "RGB-P200" == STR
        || "RGB450" == STR
        || "RGB650" == STR
    }

    // classes4/sources/neewer/clj/fastble/data/BleDevice.java
    class func getLightNames(rawName: String, identifier: String) -> (nickName: String, projectName: String) {
        // Your code here
        var nickName = ""
        var projectName = ""
        var name = String(rawName)
        let suffix = identifier == "" ? "" : "-\(identifier.suffix(6))"

        if name.hasPrefix("NWR") {
            projectName = String(name.dropFirst(4))
        } else if name.hasPrefix("NEEWER") {
            projectName = String(name.dropFirst(7))
        } else if !name.hasPrefix("NW") || !name.contains("&") {
            projectName = name.hasPrefix("NW") ? String(name.dropFirst(3)) : name
        } else {
            let substring = String(name.dropFirst(3).prefix(upTo: name.lastIndex(of: "&")!))
            if Int64(substring) != nil {
                let result = NeewerLightConstant.getProjectName(substring)
                projectName = result
            } else {
                projectName = substring
            }
        }

        nickName = "\(projectName)\(suffix)"

        return (nickName: nickName, projectName: projectName)
    }

    class func getLightFX(lightType: UInt8) -> [NeewerLightFX] {
        var fxs: [NeewerLightFX] = []

        if getRGBLightTypesThatSupport17FX().contains(lightType) {
            fxs.append(NeewerLightFX.lightingScene())
            fxs.append(NeewerLightFX.paparazziScene())
            fxs.append(NeewerLightFX.defectiveBulbScene())
            fxs.append(NeewerLightFX.explosionScene())
            fxs.append(NeewerLightFX.weldingScene())
            fxs.append(NeewerLightFX.cctFlashScene())
            fxs.append(NeewerLightFX.hueFlashScene())
            fxs.append(NeewerLightFX.cctPulseScene())
            fxs.append(NeewerLightFX.huePulseScene())
            fxs.append(NeewerLightFX.copCarScene())
            fxs.append(NeewerLightFX.candlelightScene())
            fxs.append(NeewerLightFX.hueLoopScene())
            fxs.append(NeewerLightFX.cctLoopScene())
            fxs.append(NeewerLightFX.intLoopScene())
            fxs.append(NeewerLightFX.tvScreenScene())
            fxs.append(NeewerLightFX.fireworkScene())
            fxs.append(NeewerLightFX.partyScene())
        } else if getRGBLightTypesThatSupport9FX().contains(lightType) {

            fxs.append(NeewerLightFX(id: 0x1, name: "Squard Car", brr: true))
            fxs.append(NeewerLightFX(id: 0x2, name: "Ambulance", brr: true))
            fxs.append(NeewerLightFX(id: 0x3, name: "Fire Engine", brr: true))

            fxs.append(NeewerLightFX(id: 0x4, name: "Fireworks", brr: true))
            fxs.append(NeewerLightFX(id: 0x5, name: "Party", brr: true))
            fxs.append(NeewerLightFX(id: 0x6, name: "Candle Light", brr: true))

            fxs.append(NeewerLightFX(id: 0x7, name: "Paparazzi", brr: true))
            fxs.append(NeewerLightFX(id: 0x8, name: "Screen", brr: true))
            fxs.append(NeewerLightFX(id: 0x9, name: "Lighting", brr: true))
        }
        return fxs
    }

    class func getLightSources(lightType: UInt8) -> [NeewerLightSource] {
        var fxs: [NeewerLightSource] = []

        fxs.append(NeewerLightSource.sunlightSource())
        fxs.append(NeewerLightSource.whiteHalogenSource())
        fxs.append(NeewerLightSource.xenonShortarcLampSource())
        fxs.append(NeewerLightSource.horizonDaylightSource())
        fxs.append(NeewerLightSource.daylightSource())
        fxs.append(NeewerLightSource.tungstenSource())
        fxs.append(NeewerLightSource.studioBulbSource())
        fxs.append(NeewerLightSource.modelingLightsSource())
        fxs.append(NeewerLightSource.dysprosicLampSource())
        fxs.append(NeewerLightSource.hmi6000Source())

        return fxs
    }

    // classes4/sources/neewer/clj/fastble/data/BleDevice.java
    class func getLightType(nickName: String, str: String, projectName: String) -> UInt8 {
        // decoded from Android app,
        // what does these light types means?
        // Not sure.
        var lightType: UInt8 = 8
        if nickName.contains("SRP") || nickName.contains("RP18-P") {
            lightType = 1
            return lightType
        }
        if nickName.contains("RP18B PRO") {
            lightType = 51
            return lightType
        }

        if nickName.contains("SNL") || nickName.contains("NL") {
            if nickName.contains("SNL") {
                if nickName.contains("SNL960") || nickName.contains("SNL1320") || nickName.contains("SNL1920") {
                    lightType = 13
                    return lightType
                }
                lightType = 7
                return lightType
            }
            lightType = 2
            return lightType
        }

        if nickName.contains("GL1") {
            if nickName.contains("GL1 PRO") {
                lightType = 33
            } else if nickName.contains("GL1C") {
                lightType = 39
            } else {
                lightType = 4
            }
            return lightType
        }

        if nickName.contains("ZK-RY") {
            lightType = 17
            return lightType
        }

        if !nickName.contains("RGB") && !nickName.contains("SL") {
            if nickName.contains("ZY") || nickName.contains("ER1") {
                lightType = 23
                return lightType
            }
            if nickName.contains("DL200") {
                lightType = 35
                return lightType
            }
            if nickName.contains("X2") {
                lightType = 27
                return lightType
            }
            if nickName.contains("CB200B") {
                lightType = 28
                return lightType
            }
            if nickName.contains("Apollo 150D") {
                lightType = 24
                return lightType
            }
            if nickName.contains("MS60C") {
                lightType = 25
                return lightType
            }
            if nickName.contains("MS60B") {
                lightType = 30
                return lightType
            }
            if nickName.contains("CB60B") {
                lightType = 31
                return lightType
            }
            if nickName.contains("RGB62") {
                lightType = 40
                return lightType
            }
            if nickName.contains("GM16") {
                lightType = 36
                return lightType
            }
            if nickName.contains("FS150B") {
                lightType = 37
                return lightType
            }
            if nickName.contains("MS150B") {
                lightType = 38
                return lightType
            }
            if nickName.contains("DL300") {
                lightType = 41
                return lightType
            }
            if nickName.contains("T100C") {
                lightType = 44
                return lightType
            }
            if nickName.contains("A19C 220V") {
                lightType = 45
                return lightType
            }
            if nickName.contains("A19C(E26)") {
                lightType = 46
                return lightType
            }
            if nickName.contains("CB300B") {
                lightType = 47
                return lightType
            }
            if nickName.contains("R360") {
                lightType = 48
                return lightType
            }
            if nickName.contains("CB100C") {
                lightType = 49
                return lightType
            }
            if nickName.contains("TL120C") {
                lightType = 50
                return lightType
            }
            if nickName.contains("RL45B") {
                lightType = 52
                return lightType
            }
            if nickName.contains("FS230 5600K") {
                lightType = 53
                return lightType
            }
            if nickName.contains("FS150 5600K") {
                lightType = 54
                return lightType
            }
            if nickName.contains("FS230B") {
                lightType = 55
                return lightType
            }
            if nickName.contains("20220041") {
                lightType = 58
                return lightType
            }
            if nickName.contains("PL60C") {
                lightType = 60
                return lightType
            }
            if nickName.contains("BH40C") {
                lightType = 61
                return lightType
            }
            if nickName.contains("GR18C") {
                lightType = 62
                return lightType
            }
            if nickName.contains("RP19C") {
                lightType = 63
                return lightType
            }
            lightType = 0
            return lightType
        }

        if nickName.contains("RGB") {
            if projectName == "RGB1" || nickName.contains("RGB1-A") {
                lightType = 8
            } else if nickName.contains("RGB176") {
                lightType = nickName.contains("RGB176 A1") ? 20 : 5
            } else if nickName.contains("RGB18(II)") {
                lightType = 57
            } else {
                if nickName.contains("RGB18") {
                    lightType = 9
                } else if nickName.contains("RGB190") {
                    lightType = 11
                } else if nickName.contains("RGB960") || nickName.contains("RGB1320") || nickName.contains("RGB1920") {
                    lightType = 12
                } else if nickName.contains("RGB140") {
                    lightType = 15
                } else if nickName.contains("RGB168") {
                    lightType = 16
                }
                if nickName.contains("RGB1200") {
                    lightType = nickName.contains("20230025") ? 43 : 18
                } else if nickName.contains("CL124 RGB(II)") {
                    lightType = 56
                } else {
                    if nickName.contains("CL124-RGB") {
                        lightType = 19
                    } else if nickName.contains("RGB C80") || nickName.contains("RGBC80") {
                        lightType = 21
                    } else if nickName.contains("CB60 RGB") {
                        lightType = 22
                    } else if nickName.contains("RGB-P280") {
                        lightType = 29
                    }
                    if nickName.contains("BH-30S RGB") {
                        lightType = str.contains("20230021") ? 42 : 26
                    } else if nickName.contains("TL60 RGB") {
                        lightType = str.contains("20230064") ? 59 : 32
                    } else if nickName.contains("RGB62") {
                        lightType = 40
                    } else {
                        if isRGBOther(projectName) {
                            lightType = 3
                        }
                    }
                }
            }
        } else if nickName.contains("SL90 Pro") {
            lightType = 34
        } else if nickName.contains("SL90") {
            lightType = 14
        } else {
            lightType = 6
        }
        return lightType
    }

    class func getFakeLightConfigs() -> [[String: CodableValue]] {
        var lights: [[String: CodableValue]] = []
        if true {
            // CB60 RGB
            // https://ca.neewer.com/products/neewer-led-video-light-66601007?_pos=1&_sid=8fa195c56&_ss=r
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("DF:24:3A:B4:46:5D")
            cfg["rawname"] = CodableValue.stringValue("NW-20210012&FFFFFFFF")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
            lights.append(cfg)
        }
        if true {
            // RGB660 PRO
            // https://ca.neewer.com/products/neewer-2-packs-of-50w-rgb-660-pro-led-video-light-kit-66600132?_pos=2&_psq=RGB660+PRO&_ss=e&_v=1.0
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("ED:86:66:4A:18:74")
            cfg["rawname"] = CodableValue.stringValue("NEEWER-RGB660 PRO")
            cfg["identifier"] = CodableValue.stringValue("EC2907F4-B7DC-ED69-6385-19682E5FE87F")
            lights.append(cfg)
        }
        if true {
            // RGB1 RGB Stick Light
            // https://ca.neewer.com/products/neewer-cri98-rgb1-handheld-led-video-light-66601508?variant=46055559790882
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("F3:74:C6:C5:7C:EF")
            cfg["rawname"] = CodableValue.stringValue("NW-20200015&00000000")
            cfg["identifier"] = CodableValue.stringValue("85D152B3-AC94-3CBB-A475-9A3D2224E88F")
            lights.append(cfg)
        }
        if true {
            // Neewer RGB176 A1 Light
            // https://ca.neewer.com/products/neewer-rgb176-a1-led-video-light-66602544?_pos=1&_psq=RGB176+A1&_ss=e&_v=1.0
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("F3:74:C6:C5:7E:CF")
            cfg["rawname"] = CodableValue.stringValue("NW-RGB176 A1")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-0FD2-2531C7E4B053")
            lights.append(cfg)
        }

        if true {
            // Neewer SNL530 LED Light
            // https://neewer.com/products/neewer-2-pack-snl530-led-video-lighting-kit-66603091?_pos=1&_psq=NEEWER-SNL530&_ss=e&_v=1.0
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("FA:74:C6:C5:7E:AB")
            cfg["rawname"] = CodableValue.stringValue("NEEWER-SNL530")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-0FD2-2531DEE0BA8C")
            lights.append(cfg)
        }

        if true {
            // Neewer RBG168 LED Light
            // https://neewer.com/products/neewer-2-pack-snl530-led-video-lighting-kit-66603091?_pos=1&_psq=NEEWER-SNL530&_ss=e&_v=1.0
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("FA:74:C6:C5:CC:AB")
            cfg["rawname"] = CodableValue.stringValue("NEEWER-RGB168")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-0FD2-2531DEE0BAFA")
            lights.append(cfg)
        }

        if true {
            // Neewer RBG530 Pro LED Light
            // https://www.amazon.ca/3200K-5600K-Brightness-Adjustable-Applicable-Photography/dp/B082DZCJ7V
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("FA:74:C6:C5:AA:AB")
            cfg["rawname"] = CodableValue.stringValue("NEEWER-RGB530 Pro")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-0FD2-1A3BDEE0BAFA")
            lights.append(cfg)
        }

        if true {
            // Neewer GL1 Key Light
            // https://www.amazon.ca/NEEWER-Streaming-Control-Android-Compatible/dp/B0BR4XX1HB
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("FA:74:C6:C5:AA:CC")
            cfg["rawname"] = CodableValue.stringValue("NEEWER-GL1")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-0FD2-1A3DDEE0BAFA")
            lights.append(cfg)
        }

        if true {
            // Neewer GL1C RGB Light
            // https://www.amazon.ca/NEEWER-Streaming-Lighting-Android-2900K-7000K/dp/B0CFF43DHC
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("FA:74:AA:BB:AA:DD")
            cfg["rawname"] = CodableValue.stringValue("NEEWER-GL1C")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-0FD2-7A8DDEE0BAFA")
            lights.append(cfg)
        }

        if true {
            // Neewer SL90 Pro Light
            // https://ca.neewer.com/products/neewer-sl90-12w-on-camera-rgb-panel-video-light-66600927?_pos=1&_psq=sl90+pro&_ss=e&_v=1.0
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("FA:58:9A:CC:EE:DD")
            cfg["rawname"] = CodableValue.stringValue("NW-20220057&00000000")
            cfg["identifier"] = CodableValue.stringValue("DEE0BA8C-D9B4-B7DB-012C-7A8DDEE0BAFA")
            lights.append(cfg)
        }

        if true {
            // Neewer RGB62
            // https://ca.neewer.com/products/neewer-rgb62-magnetic-rgb-video-light-66603000?_pos=1&_psq=RGB62&_ss=e&_v=1.0
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("12:38:9A:CC:EE:DD")
            cfg["rawname"] = CodableValue.stringValue("NW-RGB62")
            cfg["identifier"] = CodableValue.stringValue("FAE0BA8C-D9B4-B7DB-012C-7A8DDEE0BAFA")
            lights.append(cfg)
        }

        if true {
            // Fake new light
            var cfg: [String: CodableValue] = [:]
            cfg["fake"] = CodableValue.boolValue(true)
            cfg["mac"] = CodableValue.stringValue("12:32:9A:AC:EE:DD")
            cfg["rawname"] = CodableValue.stringValue("NEEWER-NL-116AI")
            cfg["identifier"] = CodableValue.stringValue("FAE0BA8C-ABCD-B7DB-012C-7A8DDEE0BAFA")
            lights.append(cfg)
        }

        return lights
    }
}
