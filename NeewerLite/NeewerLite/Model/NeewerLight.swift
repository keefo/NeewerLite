//
//  NeewerDevice.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa
import CoreBluetooth
import IOBluetooth

protocol ObservableNeewerLightProtocol {
    var isOn: Observable<Bool> { get set }
    var channel: Observable<UInt8> { get set }
}

class NeewerLight: NSObject, ObservableNeewerLightProtocol {

    enum Mode: UInt8 {
        case CCTMode = 1    // Bi-color mode
        case HSIMode        // Color mode
        case SCEMode        // Scene mode, or animation mode or channel mode
    }

    struct Constants {
        static let NeewerBleServiceUUID = CBUUID(string: "69400001-B5A3-F393-E0A9-E50E24DCCA99")
        static let NeewerDeviceCtlCharacteristicUUID = CBUUID(string: "69400002-B5A3-F393-E0A9-E50E24DCCA99")
        static let NeewerGattCharacteristicUUID = CBUUID(string: "69400003-B5A3-F393-E0A9-E50E24DCCA99")
        static let RGBLightTypes: [Int8] = [3,5,9,11,12,15,16,18,19,20,21,22]
        static let ExtendedCCTLightTypes: [Int8] = [6]
    }

    struct BleCommand {
        static let prefix_tag = 0x78         // 120 Every bluettooth cmd start with 120
        static let set_rgb_light_tag = 0x86  // 134 Set RGB Light Mode.
        static let set_cct_light_tag = 0x87  // 135 Set CCT Light Mode.

        static let set_longcct_light_brightness_tag = 0x82  // 130 Set long CCT Light brightness.
        static let set_longcct_light_cct_tag = 0x83         // 131 Set long CCT Light CCT.

        static let set_scene_tag = 0x88      // 136 Set Scene Light Mode.
        static let power_on = NSData(bytes: [0x78,0x81,0x01,0x01,0xFB] as [UInt8], length: 5)
        static let power_off = NSData(bytes: [0x78,0x81,0x01,0x02,0xFC] as [UInt8], length: 5)
        static let read_request = NSData(bytes: [0x78,0x84,0x00,0xFC] as [UInt8], length: 4)
    }

    private var peripheral: CBPeripheral
    private var deviceCtlCharacteristic: CBCharacteristic?
    private var gattCharacteristic: CBCharacteristic?

    var isOn: Observable<Bool> = Observable(false)
    var channel: Observable<UInt8> = Observable(1)

    private var _writeDispatcher: DispatchWorkItem?
    private var _nickName: String?
    private var _projectName: String?
    private var _lightType: Int8 = -1

    var userLightName: String = "Unknow"
    var lightMode: NeewerLight.Mode = .CCTMode
    var channelValue: UInt8 = 1 // 1 ~ 9
    var cctValue: Int = 0x53  // 5300K
    var brrValue: Int = 50    // 0~100
    var hueValue: Int = 0     // 0~360
    var satruationValue: Int = 0 // 0~100
    var followMusic: Bool = false

    // read only properties
    var supportRGB: Bool {
        // some lights are only Bi-Color which does not support RGB.
        return NeewerLight.Constants.RGBLightTypes.contains(ligthType)
    }

    var supportLongCCT: Bool {
        // Default CCT range from 3200k–5600k
        // some lights support extended CCT range from 3200K–8500K such as
        // https://neewer.com/products/neewer-sl80-10w-rgb-led-video-light-10097903?_pos=1&_sid=dfa97e049&_ss=r&variant=37586440683713
        return NeewerLight.Constants.ExtendedCCTLightTypes.contains(ligthType)
    }

    var minCCT: Int {
        if supportLongCCT {
            if supportLongCCT && projectName.contains("SL140") {
                // https://neewer.com/products/neewer-sl-140-rgb-led-light-full-color-rechargeable-pocket-size-10097200?_pos=2&_sid=3ff26da17&_ss=r
                return 25
            }
        }
        return 32
    }

    var maxCCT: Int {
        if supportLongCCT {
            if projectName.contains("SL140") {
                // https://neewer.com/products/neewer-sl-140-rgb-led-light-full-color-rechargeable-pocket-size-10097200?_pos=2&_sid=3ff26da17&_ss=r
                return 90
            }
            return 85
        }
        return 56
    }

    var deviceName: String {
        let name = rawName
        if name.hasPrefix("NW") {
            return "NW-\(projectName)"
        }
        return name
    }

    var nickName: String {
        if _nickName == nil {
            let name = rawName

            let currentTimeMillis:() -> String = {
                // currentTimeMillis last 3 digits
                var darwinTime : timeval = timeval(tv_sec: 0, tv_usec: 0)
                gettimeofday(&darwinTime, nil)
                let last3digits = ((Int64(darwinTime.tv_sec) * 1000) + Int64(darwinTime.tv_usec / 1000)) % 1000
                return "\(last3digits)"
            }

            let str = currentTimeMillis()

            if name.hasPrefix("NW") {
                _nickName = "\(projectName)-\(str)"
            }
            else if name.hasPrefix("NEEWER") || name.hasPrefix("NWR") {
                _nickName = "\(name.replacingOccurrences(of: "NEEWER-", with: ""))-\(str)"
            }
            else {
                _nickName = name
            }
        }
        return _nickName!
    }

    var projectName: String {
        if _projectName == nil {
            let name = rawName
            if name.hasPrefix("NEEWER") || name.hasPrefix("NWR") {
                if let i = name.firstIndex(of:"-") {
                    _projectName = "\(name[name.index(i, offsetBy: 1)...])"
                }
                else if let i = name.firstIndex(of:"_") {
                    _projectName = "\(name[name.index(i, offsetBy: 1)...])"
                }
            }
            if name.hasPrefix("NW") && name.hasPrefix("&") {
                if let i = name.firstIndex(of:"-"), let j = name.lastIndex(of: "&"){
                    _projectName = "\(name[name.index(i, offsetBy: 1)...j])"
                }
                else if let i = name.firstIndex(of:"_"), let j = name.lastIndex(of: "&"){
                    _projectName = "\(name[name.index(i, offsetBy: 1)...j])"
                }
            }
        }
        return _projectName!
    }

    public lazy var identifier: String = {
        return "\(peripheral.identifier)"
    }()

    public lazy var rawName: String = {
        guard let name = peripheral.name else { return "" }
        return name
    }()

    private lazy var ligthType: Int8 = {
        if _lightType < 0 {
            _lightType = 8
            _lightType = NeewerLight.getLightTypeByName(nickName)
        }
        return _lightType
    }()

    
    private func getConfig() -> [String: String]
    {
        var vals: [String: String] = [:]
        vals["on"] = isOn.value ? "1" : "0"
        vals["mod"] = "\(lightMode.rawValue)"
        vals["cct"] = "\(cctValue)"
        vals["brr"] = "\(brrValue)"
        vals["chn"] = "\(channelValue)"
        vals["hue"] = "\(hueValue)"
        vals["sat"] = "\(satruationValue)"
        vals["nme"] = userLightName
        return vals
    }

    func saveToUserDefault() {
        let vals = getConfig()
        UserDefaults.standard.set(vals, forKey: "\(self.peripheral.identifier)")
    }

    func readFromUserDefault() {
        let vals = UserDefaults.standard.object(forKey: "\(self.peripheral.identifier)") as? [String: String] ?? [String: String]()
        if let val = vals["on"] {
            isOn.value = val == "1" ? true : false
        }

        if let val = vals["mod"] {
            Logger.debug("load mod \(val)")
            if UInt8(val) == NeewerLight.Mode.CCTMode.rawValue {
                lightMode = .CCTMode
            } else if UInt8(val) == NeewerLight.Mode.HSIMode.rawValue {
                lightMode = .HSIMode
            } else if UInt8(val) == NeewerLight.Mode.SCEMode.rawValue {
                lightMode = .SCEMode
            }
        }

        if let val = vals["cct"] {
            Logger.debug("load cct \(val)")
            cctValue = Int(val) ?? 0
        }
        if let val = vals["brr"] {
            Logger.debug("load brr \(val)")
            brrValue = Int(val) ?? 0
        }
        if let val = vals["chn"] {
            channelValue = UInt8(val) ?? 1
            Logger.debug("load channelValue \(channelValue)")
            self.channel.value = UInt8(channelValue)
        }
        if let val = vals["hue"] {
            hueValue = Int(val) ?? 1
            Logger.debug("load hueValue \(hueValue)")
        }
        if let val = vals["sat"] {
            satruationValue = Int(val) ?? 1
            Logger.debug("load satruationValue \(satruationValue)")
        }
        if let val = vals["nme"] {
            userLightName = val
        } else {
            userLightName = peripheral.name ?? "Unknow"
        }
    }

    init(_ peripheral: CBPeripheral, _ deviceCtlCharacteristic: CBCharacteristic, _ gattCharacteristic: CBCharacteristic) {
        self.peripheral = peripheral
        self.deviceCtlCharacteristic = deviceCtlCharacteristic
        self.gattCharacteristic = gattCharacteristic
        super.init()
        self.peripheral.delegate = self
        readFromUserDefault()
        Logger.debug("     config: \(getConfig())")
        Logger.debug("    rawName: \(rawName)")
        Logger.debug("projectName: \(projectName)")
        Logger.debug("   nickName: \(nickName)")
        Logger.debug("  ligthType: \(ligthType)")
    }

    class func isValidPeripheralName(_ peripheralName: String) -> Bool
    {
        if peripheralName.contains("NWR") ||
            peripheralName.contains("NEEWER") ||
            peripheralName.contains("SL")
        {
            return true
        }
        return false
    }

    class func getLightTypeByName(_ nickName: String) -> Int8
    {
        // decoded from Android app,
        // what does these light types means?
        // Not sure.
        var lightType: Int8 = 8
        if nickName.contains("SRP") || nickName.contains("RP18-P") {
            lightType = 1
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
        if nickName.contains("GL") {
            lightType = 4
            return lightType
        }
        if nickName.contains("ZK-RY") {
            lightType = 17
            return lightType
        }
        if nickName.contains("RGB") || nickName.contains("SL") {
            if nickName.contains("RGB") {
                if nickName.lengthOfBytes(using: String.Encoding.utf8) != 8 || !nickName.hasPrefix("RGB1") {
                    if nickName.contains("RGB176") {
                        if nickName.contains("RGB176A1") {
                            lightType = 20
                        } else {
                            lightType = 5
                        }
                    } else if nickName.contains("RGB18") {
                        lightType = 9
                    } else if nickName.contains("RGB190") {
                        lightType = 11
                    } else {
                        if nickName.contains("RGB960") || nickName.contains("RGB1320") || nickName.contains("RGB1920") {
                            lightType = 12
                            return lightType
                        }
                        if nickName.contains("RGB140") {
                            lightType = 15
                        } else if nickName.contains("RGB168") {
                            lightType = 16
                        } else if nickName.contains("RGB1200") {
                            lightType = 18
                        } else if nickName.contains("CL124-RGB") {
                            lightType = 19
                        } else if nickName.contains("RGBC80") {
                            lightType = 21
                        } else if nickName.contains("CB60 RGB") {
                            lightType = 22
                        } else {
                            lightType = 3
                        }
                    }
                    return lightType
                }
            }
            else if nickName.contains("SL90") {
                lightType = 14
                return lightType
            }
            else {
                lightType = 6
                return lightType
            }
        }
        else {
            lightType = 0
            return lightType
        }
        return lightType
    }

    func sendPowerOnRequest()
    {
        if let characteristic = deviceCtlCharacteristic {
            Logger.debug("send powerOn")
            self.write(data: NeewerLight.BleCommand.power_on as Data, to: characteristic)
            isOn.value = true
        }
    }

    func sendPowerOffRequest()
    {
        if let characteristic = deviceCtlCharacteristic {
            Logger.debug("send powerOff")
            self.write(data: NeewerLight.BleCommand.power_off as Data, to: characteristic)
            isOn.value = false
        }
    }

    func sendReadRequest()
    {
        if let characteristic = deviceCtlCharacteristic {
            write(data: NeewerLight.BleCommand.read_request as Data, to: characteristic)
        }
    }

    func startLightOnNotify()
    {
        if let characteristic = gattCharacteristic {
            if !characteristic.canNotify {
                Logger.debug("gattCharacteristic can not Notify")
                return
            }
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func stopLightOnNotify()
    {
        if let characteristic = gattCharacteristic {
            if !characteristic.canNotify {
                Logger.debug("gattCharacteristic can not Notify")
                return
            }
            peripheral.setNotifyValue(false, for: characteristic)
        }
    }

    // Set correlated color temperature and bulb brightness in CCT Mode
    public func setCCTLightValues(_ cct: CGFloat, _ brr: CGFloat)
    {
        if let characteristic = deviceCtlCharacteristic {
            if supportRGB {
                let cmd = getCCTLightValue(brightness: brr, correlatedColorTemperature: cct)
                write(data: cmd as Data, to: characteristic)
            }
            else {
                let cmd = getCCTOnlyLightValue(brightness: brr, correlatedColorTemperature: cct)
                write(data: cmd as Data, to: characteristic)
            }
            lightMode = .CCTMode
        }
    }

    // Set RBG light in HSV Mode
    public func setRGBLightValues(_ hue: CGFloat, _ sat: CGFloat)
    {
        Logger.debug("hue: \(hue) sat: \(sat)")
        if let characteristic = deviceCtlCharacteristic {
            let cmd = getRGBLightValue(brightness: CGFloat(brrValue) / 100.0, hue: hue, satruation: sat)
            write(data: cmd as Data, to: characteristic)
            lightMode = .HSIMode
        }
    }

    public func setRGBLightValues(_ hue: CGFloat, _ sat: CGFloat, _ brr: CGFloat)
    {
        if let characteristic = deviceCtlCharacteristic {
            let cmd = getRGBLightValue(brightness: brr, hue: hue, satruation: sat)
            write(data: cmd as Data, to: characteristic)
            lightMode = .HSIMode
        }
    }

    // Set Scene
    public func setScene(_ scene: UInt8, brightness brr: CGFloat)
    {
        if let characteristic = deviceCtlCharacteristic {
            let cmd = getSceneValue(scene, brightness: CGFloat(brr))
            write(data: cmd as Data, to: characteristic)
            lightMode = .SCEMode
        }
    }


    private func handleNotifyValueUpdate(_ data: Data)
    {
        // Found a way to request data from a light, but don't know what is the data represents.
        Logger.debug("handleNotifyValueUpdate \(data.hexEncodedString())")
    }

    
    private func appendCheckSum(_ bArr: [Int]) -> [UInt8] {
        var bArr1: [UInt8] = [UInt8](repeating: 0, count: bArr.count)

        var checkSum: Int = 0
        for i in 0 ..< bArr.count - 1 {
            bArr1[i] = bArr[i] < 0 ? UInt8(bArr[i] + 0x100) : UInt8(bArr[i])
            checkSum = checkSum + Int(bArr1[i])
        }

        bArr1[bArr.count - 1] = UInt8(checkSum & 0xFF)
        return bArr1
    }

    private func composeSingleCommand(_ tag: Int, _ vals: Int...) -> [UInt8] {
        let byteCount = vals.count
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)
        bArr[0] = NeewerLight.BleCommand.prefix_tag;
        bArr[1] = tag
        bArr[2] = byteCount
        var i = 3
        for val in vals {
            bArr[i] = val
            i = i + 1
        }
        return appendCheckSum(bArr)
    }

    private func getCCTLightValue(brightness brr: CGFloat, correlatedColorTemperature cct: CGFloat) -> Data {

        // cct range from 0x20(32) - 0x38(56) 32 stands for 3200K 65 stands for 5600K
        let newCctValue: Int = Int(cct).clamped(to: 32...maxCCT)
        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr * 100.0).clamped(to: 0...100)

        if newCctValue == 0 {
            // only adjust the brightness and keep the color temp
            if brrValue == newBrrValue {
                return Data()
            }
            brrValue = newBrrValue

            let bArr1: [UInt8] = composeSingleCommand(NeewerLight.BleCommand.set_cct_light_tag, brrValue)

            let data = NSData(bytes: bArr1, length: bArr1.count)
            return data as Data
        }

        cctValue = newCctValue
        brrValue = newBrrValue

        let bArr1: [UInt8] = composeSingleCommand(NeewerLight.BleCommand.set_cct_light_tag, brrValue, cctValue)

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    // Not sure what is is L stand for.
    private func getCCTOnlyLightValue(brightness brr: CGFloat, correlatedColorTemperature cct: CGFloat) -> Data {
        // cct range from 0x20(32) - 0x38(56) 32 stands for 3200K 65 stands for 5600K
        let newCctValue: Int = Int(cct).clamped(to: minCCT...maxCCT)
        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr).clamped(to: 0...100)

        if newCctValue == 0 {
            // only adjust the brightness and keep the color temp
            if brrValue == newBrrValue {
                return Data()
            }
            brrValue = newBrrValue

            let bArr1: [UInt8] = composeSingleCommand(NeewerLight.BleCommand.set_longcct_light_brightness_tag, brrValue)

            let data = NSData(bytes: bArr1, length: bArr1.count)
            return data as Data
        }

        cctValue = newCctValue
        brrValue = newBrrValue

        let bArr1 = composeSingleCommand(NeewerLight.BleCommand.set_longcct_light_brightness_tag, brrValue)
        let bArr2 = composeSingleCommand(NeewerLight.BleCommand.set_longcct_light_cct_tag, cctValue)
        let bArr = bArr1 + bArr2

        let data = NSData(bytes: bArr, length: bArr.count)
        return data as Data
    }

    public func setBRRLightValues(_ brr: CGFloat)
    {
        if let characteristic = deviceCtlCharacteristic {
            if lightMode == .CCTMode {
                if supportRGB {
                    let cmd = getCCTLightValue(brightness: brr, correlatedColorTemperature: CGFloat(cctValue))
                    write(data: cmd as Data, to: characteristic)
                }
                else {
                    let cmd = getCCTOnlyLightValue(brightness: brr, correlatedColorTemperature: CGFloat(cctValue))
                    write(data: cmd as Data, to: characteristic)
                }
            } else if lightMode == .HSIMode  {
                let cmd = getRGBLightValue(brightness: brr, hue: CGFloat(hueValue) / 360.0, satruation: CGFloat(satruationValue) / 100.0)
                write(data: cmd as Data, to: characteristic)
            } else {
                let cmd = getSceneValue(channelValue, brightness: CGFloat(brr))
                write(data: cmd as Data, to: characteristic)
            }
        }
    }

    private func getRGBLightValue(brightness brr: CGFloat, hue h: CGFloat, satruation sat: CGFloat ) -> Data {

        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr * 100.0).clamped(to: 0...100)
        let newSatValue: Int = Int(sat * 100.0).clamped(to: 0...100)
        let newHueValue = Int(h * 360.0).clamped(to: 0...360)

        // Red  7886 0400 0064 643F
        // Blue 7886 04E7 0064 64B0
        // Yell 7886 043E 0064 64B0
        // Gree 7886 0476 0064 643F
        // Red  7886 0468 0164 643F
        //Logger.debug("hue \(newHueValue) sat \(newSatValue)")

        let byteCount = 4
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

        bArr[0] = NeewerLight.BleCommand.prefix_tag;
        bArr[1] = NeewerLight.BleCommand.set_rgb_light_tag
        bArr[2] = byteCount
        // 4 eletements
        bArr[3] = Int(newHueValue & 0xFF)
        bArr[4] = Int((newHueValue & 0xFF00) >> 8) // callcuated from rgb
        bArr[5] = newSatValue // satruation 0x00 ~ 0x64
        bArr[6] = newBrrValue // brightness

        brrValue = newBrrValue
        hueValue = newHueValue
        satruationValue = newSatValue

        let bArr1: [UInt8] = appendCheckSum(bArr)

        return NSData(bytes: bArr1, length: bArr1.count) as Data
    }

    private func getSceneValue(_ scene: UInt8, brightness brr: CGFloat) -> Data {

        // 78 88 02 (br) 01 - sets the brightness to (br), and shows "emergency mode A" (the "police sirens")
        // 78 88 02 (br) 02 - " ", and shoes "emergency mode B", but just stays one color?
        // 78 88 02 (br) 03 - " ", and shows "emergency mode C", which is... ambulance? I'm not sure
        // 78 88 02 (br) 04 - " ", and shows "party mode A", alternating colors
        // 78 88 02 (br) 05 - " ", and shows "party mode B", same as A, but faster
        // 78 88 02 (br) 06 - " ", and shows "party mode C", fading in and out (candle-light?)
        // 78 88 02 (br) 07 - " ", and shows "lightning mode A"
        // 78 88 02 (br) 08 - " ", and shows "lightning mode B"
        // 78 88 02 (br) 09 - " ", and shows "lightning mode C"

        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr).clamped(to: 0...100)
        brrValue = newBrrValue

        // scene from 1 ~ 9
        channelValue = scene.clamped(to: 1...9)

        let byteCount = 2
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

        bArr[0] = NeewerLight.BleCommand.prefix_tag;
        bArr[1] = NeewerLight.BleCommand.set_scene_tag
        bArr[2] = byteCount
        // 2 eletements
        bArr[3] = Int(brr)   // brightness value from 0-100
        bArr[4] = Int(scene)

        let bArr1: [UInt8] = appendCheckSum(bArr)

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    private func write(data value: Data, to characteristic: CBCharacteristic)
    {
        if value.count > 1 {
            _writeDispatcher?.cancel()

            let currentWorkItem = DispatchWorkItem {
                //Logger.debug("write data: \(value.hexEncodedString())")
                self.peripheral.writeValue(value, for: characteristic, type: .withResponse)
            }

            _writeDispatcher = currentWorkItem
            // Writing too fast to the device could lead to BLE jam, slow down the request with 15ms delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + (15.0 / 1000.0), execute: currentWorkItem)
         }
    }
}


extension NeewerLight :  CBPeripheralDelegate {

    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?)
    {
        Logger.debug("peripheralDidUpdateRSSI")
        if let err = error {
            Logger.error("err: \(err)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        Logger.debug("didUpdateValueFor characteristic: \(characteristic)")
        if let err = error {
            Logger.error("err: \(err)")
        } else {
            if let data: Data = characteristic.value as Data? {
                handleNotifyValueUpdate(data)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    {
        //self.writeGroup.leave()
        if let err = error {
            Logger.error("didWriteValueFor err: \(err)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    {
        Logger.debug("didUpdateNotificationStateFor characteristic: \(characteristic)")
        if let err = error {
            Logger.error("err: \(err)")
        } else {
            let properties : CBCharacteristicProperties = characteristic.properties
            Logger.info("properties: \(properties)")
            Logger.info("properties.rawValue: \(properties.rawValue)")
            //self.write(data: cmd_check_power as Data, to: characteristic)
            sendReadRequest()
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?)
    {
        Logger.debug("didDiscoverDescriptorsFor characteristic: \(characteristic)")
        if let err = error {
            Logger.error("err: \(err)")
        }
        else{
            if let descriptors = characteristic.descriptors
            {
                let characteristicConfigurationDescriptor = descriptors.first { (des) -> Bool in
                    return des.uuid == CBUUID(string: CBUUIDClientCharacteristicConfigurationString)
                }

                if let cd = characteristicConfigurationDescriptor {
                    peripheral.readValue(for: cd)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?)
    {
        Logger.debug("didUpdateValueFor descriptor: \(descriptor)")
        if let err = error {
            Logger.error("err: \(err)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?)
    {
        Logger.debug("didWriteValueFor descriptor: \(descriptor)")
        if let err = error {
            Logger.error("err: \(err)")
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral)
    {
        Logger.debug("peripheralIsReady toSendWriteWithoutResponse: \(peripheral)")
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?)
    {
        Logger.debug("peripheral didOpen channel: \(channel!)")
        if let err = error {
            Logger.error("err: \(err)")
        }
    }
}

//extension NeewerLight
//{
//}
//
//class NeewerLight: Decodable {
//
//    enum CodingKeys: String, CodingKey {
//        case id
//        case employeeName = "employee_name"
//        case employeeSalary = "employee_salary"
//        case employeeAge = "employee_age"
//        case profileImage = "profile_image"
//    }
//
//
//}
//
