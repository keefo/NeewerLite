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

    private var peripheral: CBPeripheral
    private var deviceCtlCharacteristic: CBCharacteristic?
    private var gattCharacteristic: CBCharacteristic?

    var isOn: Observable<Bool> = Observable(false)
    var channel: Observable<UInt8> = Observable(1)

    var deviceName: String = "Unknow"
    var channelValue: Int = 1  // 1
    var cctValue: Int = 0x53  // 5300K
    var brrValue: Int = 50    // 50% brightness

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
    }

    func saveToUserDefault() {
        var vals: [String: String] = [:]
        vals["on"] = isOn.value ? "1" : "0"
        vals["cct"] = "\(cctValue)"
        vals["brr"] = "\(brrValue)"
        vals["chn"] = "\(channelValue)"
        vals["nme"] = deviceName
        UserDefaults.standard.set(vals, forKey: "\(self.peripheral.identifier)")
    }

    func readFromUserDefault() {
        let vals = UserDefaults.standard.object(forKey: "\(self.peripheral.identifier)") as? [String: String] ?? [String: String]()
        if let val = vals["on"] {
            isOn.value = val == "1" ? true : false
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
            channelValue = Int(val) ?? 1
            Logger.debug("load channelValue \(channelValue)")
            self.channel.value = UInt8(channelValue)
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

    private func updateLightChannel(_ data: Data)
    {
        if data[3] > 8 {
            return
        }
        channelValue = Int(data[3])
        Logger.debug("channelValue \(channelValue)")
        self.channel.value = UInt8(channelValue)
    }

    private func handleNotifyValueUpdate(_ data: Data)
    {
        if data.count >= 5 && data[0] == cmd_prefix_tag {
            Logger.debug("handleNotifyValueUpdate \(data.hexEncodedString())")
            if data[1] == 1 {
                if data[3] != 0 {
                    updateLightChannel(data);
                } else {
                    // No channel
                    updateLightChannel(data);
                    // setCurrentLight();
                }
            } else if (data[1] != 2) {

            } else {
                if data[3] == 1 {
                    // set switch ON
                    Logger.debug("received switch ON notification.")
                    isOn.value = true
                } else {
                    // set switch OFF
                    Logger.debug("received switch OFF notification.")
                    isOn.value = false
                }
            }
        }
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

    private func getCCTLightValue(brightness brr: Double, correlatedColorTemperature cct: Double ) -> Data {

        assert(cct>=32.0 && cct<=56.0)
        assert(brr>=0 && brr<=100.0)

        // cct range from 0x20(32) - 0x38(56) 32 stands for 3200K 65 stands for 5600K
        let newCctValue: Int = Int(cct)

        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr)

        if cctValue == newCctValue && brrValue == newBrrValue {
            return Data()
        }

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

    // Set correlated color temperature and bulb brightness in CCT Mode
    func setCCTLightValues(_ cct: Double, _ brr: Double)
    {
        if let characteristic = deviceCtlCharacteristic {
            let cmd = getCCTLightValue(brightness: brr, correlatedColorTemperature: cct)
            write(data: cmd as Data, to: characteristic)
        }
    }

    private func write(data value: Data, to characteristic: CBCharacteristic)
    {
        if value.count > 1 {
            Logger.debug("write data: \(value.hexEncodedString())")
            peripheral.writeValue(value, for: characteristic, type: .withResponse)
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

