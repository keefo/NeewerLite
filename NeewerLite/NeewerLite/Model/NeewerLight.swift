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
    var isSceneOn: Observable<Bool> { get set }
    var channel: Observable<UInt8> { get set }
}

enum NeewerLightMode: UInt8 {
    case CCTMode = 1
    case RGBMode
}

class NeewerLight: NSObject, ObservableNeewerLightProtocol {

    private var peripheral: CBPeripheral
    private var deviceCtlCharacteristic: CBCharacteristic?
    private var gattCharacteristic: CBCharacteristic?

    var isOn: Observable<Bool> = Observable(false)
    var isSceneOn: Observable<Bool> = Observable(false)
    var channel: Observable<UInt8> = Observable(1)

    private var writeWorkItem: DispatchWorkItem?

    var deviceName: String = "Unknow"
    var lightMode: NeewerLightMode  = .CCTMode
    var channelValue: UInt8 = 1 // 1 ~ 9
    var cctValue: Int = 0x53  // 5300K
    var brrValue: Int = 50    // 0~100
    var hueValue: Int = 0     // 0~360
    var satruationValue: Int = 0 // 0~100

    public lazy var identifier: String = {
        return "\(peripheral.identifier)"
    }()

    public lazy var rawName: String = {
        if let name = peripheral.name {
            return name
        }
        return ""
    }()

    private let cmd_prefix_tag = 0x78  // 120
    private let cmd_set_rgb_light_tag = 0x86  // Set RGB Light Mode.
    private let cmd_set_cct_light_tag = 0x87  // Set CCT Light Mode.
    private let cmd_set_scene_tag = 0x88      // Set Scene Light Mode.
    private let cmd_power_on = NSData(bytes: [0x78,0x81,0x01,0x01,0xFB] as [UInt8], length: 5)
    private let cmd_power_off = NSData(bytes: [0x78,0x81,0x01,0x02,0xFC] as [UInt8], length: 5)
    private let cmd_read_request = NSData(bytes: [0x78,0x84,0x00,0xFC] as [UInt8], length: 4)

    init(_ peripheral: CBPeripheral, _ deviceCtlCharacteristic: CBCharacteristic, _ gattCharacteristic: CBCharacteristic) {
        self.peripheral = peripheral
        self.deviceCtlCharacteristic = deviceCtlCharacteristic
        self.gattCharacteristic = gattCharacteristic
        super.init()
        self.peripheral.delegate = self
        readFromUserDefault()
        Logger.debug("config: \(getConfig())")
    }

    private func getConfig() -> [String: String]
    {
        var vals: [String: String] = [:]
        vals["on"] = isOn.value ? "1" : "0"
        vals["mod"] = "\(lightMode.rawValue)"
        vals["sce"] = isSceneOn.value ? "1" : "0"
        vals["cct"] = "\(cctValue)"
        vals["brr"] = "\(brrValue)"
        vals["chn"] = "\(channelValue)"
        vals["hue"] = "\(hueValue)"
        vals["sat"] = "\(satruationValue)"
        vals["nme"] = deviceName
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

        if let val = vals["sce"] {
            isSceneOn.value = val == "1" ? true : false
        }

        if let val = vals["mod"] {
            Logger.debug("load mod \(val)")
            if UInt8(val) == NeewerLightMode.CCTMode.rawValue {
                lightMode = .CCTMode
            } else if UInt8(val) == NeewerLightMode.RGBMode.rawValue {
                lightMode = .RGBMode
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
            deviceName = val
        } else {
            deviceName = peripheral.name ?? "Unknow"
        }
    }

    func sendPowerOnRequest()
    {
        if let characteristic = deviceCtlCharacteristic {
            Logger.debug("send powerOn")
            self.write(data: cmd_power_on as Data, to: characteristic)
            isOn.value = true
        }
    }

    func sendPowerOffRequest()
    {
        if let characteristic = deviceCtlCharacteristic {
            Logger.debug("send powerOff")
            self.write(data: cmd_power_off as Data, to: characteristic)
            isOn.value = false
        }
    }

    func sendReadRequest()
    {
        if let characteristic = deviceCtlCharacteristic {
            write(data: cmd_read_request as Data, to: characteristic)
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

    private func handleNotifyValueUpdate(_ data: Data)
    {
        // Found a way to request data from a light, but don't know what is the data represents.
        Logger.debug("handleNotifyValueUpdate \(data.hexEncodedString())")
    }

    private func appendCheckSum(_ bArr: [Int]) -> [UInt8] {
        var bArr1: [UInt8] = [UInt8](repeating: 0, count: bArr.count)

        var checkSum: Int = 0
        for i in 0 ..< bArr.count - 1 {
            bArr1[i] = bArr[i] < 0 ? UInt8(bArr[i] + 256) : UInt8(bArr[i])
            checkSum = checkSum + Int(bArr1[i])
        }

        bArr1[bArr.count - 1] = UInt8(checkSum & 0xFF)
        return bArr1
    }

    private func getCCTLightValue(brightness brr: CGFloat, correlatedColorTemperature cct: CGFloat ) -> Data {

        assert(brr>=0 && brr<=100.0)

        // cct range from 0x20(32) - 0x38(56) 32 stands for 3200K 65 stands for 5600K
        let newCctValue: Int = Int(cct)
        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr)

        if newCctValue == 0 {
            // only adjust the brightness and keep the color temp
            if brrValue == newBrrValue {
                return Data()
            }
            brrValue = newBrrValue
            let byteCount = 1
            var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

            bArr[0] = cmd_prefix_tag;
            bArr[1] = cmd_set_cct_light_tag
            bArr[2] = byteCount
            bArr[3] = brrValue

            let bArr1: [UInt8] = appendCheckSum(bArr)

            let data = NSData(bytes: bArr1, length: bArr1.count)
            return data as Data
        }

        assert(cct>=32.0 && cct<=56.0)

        cctValue = newCctValue
        brrValue = newBrrValue

        let byteCount = 2
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

        bArr[0] = cmd_prefix_tag;
        bArr[1] = cmd_set_cct_light_tag
        bArr[2] = byteCount
        bArr[3] = brrValue
        bArr[4] = cctValue

        let bArr1: [UInt8] = appendCheckSum(bArr)

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    public func setBRRLightValues(_ brr: CGFloat)
    {
        if let characteristic = deviceCtlCharacteristic {
            if isSceneOn.value {
                let cmd = getSceneValue(channelValue, brightness: CGFloat(brr))
                write(data: cmd as Data, to: characteristic)
            }
            else {
                if lightMode == .CCTMode {
                    let cmd = getCCTLightValue(brightness: brr, correlatedColorTemperature: 0)
                    write(data: cmd as Data, to: characteristic)
                } else if lightMode == .RGBMode  {
                    let cmd = getRGBLightValue(brightness: brr, hue: CGFloat(hueValue) / 360.0, satruation: CGFloat(satruationValue) / 100.0)
                    write(data: cmd as Data, to: characteristic)
                }
            }
        }
    }

    // Set correlated color temperature and bulb brightness in CCT Mode
    public func setCCTLightValues(_ cct: CGFloat, _ brr: CGFloat)
    {
        if let characteristic = deviceCtlCharacteristic {
            let cmd = getCCTLightValue(brightness: brr, correlatedColorTemperature: cct)
            write(data: cmd as Data, to: characteristic)
            lightMode = .CCTMode
        }
    }


    private func getRGBLightValue(brightness brr: CGFloat, hue h: CGFloat, satruation sat: CGFloat ) -> Data {
        assert(brr>=0 && brr<=100.0)
        //assert(h>=0 && h<=1.0)
        //assert(sat>=0 && sat<=1.0)

        // brr range from 0x00 - 0x64
        var newBrrValue: Int = Int(brr)
        if newBrrValue < 0 {
            newBrrValue = 0
        }
        if newBrrValue > 100 {
            newBrrValue = 100
        }

        var newSatValue: Int = Int(sat * 100.0)
        if newSatValue < 0 {
            newSatValue = 0
        }
        if newSatValue > 100 {
            newSatValue = 100
        }

        var newHueValue = Int(h * 360.0)
        if newHueValue < 0 {
            newHueValue = 0
        }
        if newHueValue > 360 {
            newHueValue = 360
        }

        // Red  7886 0400 0064 643F
        // Blue 7886 04E7 0064 64B0
        // Yell 7886 043E 0064 64B0
        // Gree 7886 0476 0064 643F
        // Red  7886 0468 0164 643F
        //Logger.debug("hue \(newHueValue) sat \(newSatValue)")

        let byteCount = 4
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

        bArr[0] = cmd_prefix_tag;
        bArr[1] = cmd_set_rgb_light_tag
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

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }


    // Set RBG light in HSV Mode
    public func setRGBLightValues(_ hue: CGFloat, _ sat: CGFloat)
    {
        if let characteristic = deviceCtlCharacteristic {
            let cmd = getRGBLightValue(brightness: CGFloat(brrValue), hue: hue, satruation: sat)
            write(data: cmd as Data, to: characteristic)
            lightMode = .RGBMode
        }
    }

    private func getSceneValue(_ scene: UInt8, brightness brr: CGFloat) -> Data {
        assert(brr>=0 && brr<=100.0)

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
        let newBrrValue: Int = Int(brr)
        brrValue = newBrrValue

        channelValue = scene

        let byteCount = 2
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

        bArr[0] = cmd_prefix_tag;
        bArr[1] = cmd_set_scene_tag
        bArr[2] = byteCount
        // 2 eletements
        bArr[3] = Int(brr)   // brightness value from 0-100
        bArr[4] = Int(scene) // scene from 1 ~ 9

        let bArr1: [UInt8] = appendCheckSum(bArr)

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    // Set Scene
    public func setScene(_ scene: UInt8, brightness brr: CGFloat)
    {
        assert(scene>=1 && scene<=9)
        assert(brr>=0 && brr<=100.0)

        if let characteristic = deviceCtlCharacteristic {
            let cmd = getSceneValue(scene, brightness: CGFloat(brr))
            write(data: cmd as Data, to: characteristic)
            isSceneOn.value = true
        }
    }

    private func write(data value: Data, to characteristic: CBCharacteristic)
    {
        if value.count > 1 {
            writeWorkItem?.cancel()

            let currentWorkItem = DispatchWorkItem {
                Logger.debug("write data: \(value.hexEncodedString())")
                self.peripheral.writeValue(value, for: characteristic, type: .withResponse)
            }

            writeWorkItem = currentWorkItem
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

