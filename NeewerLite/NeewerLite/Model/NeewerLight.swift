//
//  NeewerDevice.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa
import CoreBluetooth
import IOBluetooth


extension Data {
    struct HexEncodingOptions: OptionSet {
        let rawValue: Int
        static let upperCase = HexEncodingOptions(rawValue: 1 << 0)
    }

    func hexEncodedString(options: HexEncodingOptions = []) -> String {
        let format = options.contains(.upperCase) ? "%02hhX," : "%02hhx,"
        return map { String(format: format, $0) }.joined()
    }

    func octEncodedString(options: HexEncodingOptions = []) -> String {
        let format = "%02hhD,"
        return map { String(format: format, $0) }.joined()
    }
}


extension CBCharacteristic {

    public func propertyEnabled(_ property: CBCharacteristicProperties) -> Bool {
        return (self.properties.rawValue & property.rawValue) > 0
    }

    public var canNotify: Bool {
        return propertyEnabled(.notify) || propertyEnabled(.indicate) || propertyEnabled(.notifyEncryptionRequired) || propertyEnabled(.indicateEncryptionRequired)
    }

    public var canRead: Bool {
        return propertyEnabled(.read)
    }

    public var canWrite: Bool {
        return propertyEnabled(.write) || self.propertyEnabled(.writeWithoutResponse)
    }

}

class NeewerLight: NSObject {

    var peripheral: CBPeripheral
    var deviceCtlCharacteristic: CBCharacteristic?
    var gattCharacteristic: CBCharacteristic?

    fileprivate var _isOn: Bool = false

    init(_ peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        self.peripheral.delegate = self
    }

    var isOn: Bool {
        return _isOn
    }

    let cmd_power_on = NSData(bytes: [0x78,0x81,0x01,0x01,0xFB] as [UInt8], length: 5)
    let cmd_power_off = NSData(bytes: [0x78,0x81,0x01,0x02,0xFC] as [UInt8], length: 5)

    func powerOn()
    {
        if let characteristic = deviceCtlCharacteristic {
            Logger.debug("send powerOn")
            self.write(data: cmd_power_on as Data, to: characteristic)
            _isOn = true;
        }
    }

    func powerOff()
    {
        if let characteristic = deviceCtlCharacteristic {
            Logger.debug("send powerOff")
            self.write(data: cmd_power_off as Data, to: characteristic)
            _isOn = false;
        }
    }

    func startLightOnNotify()
    {
        if let characteristic = gattCharacteristic {
            if !characteristic.canNotify {
                Logger.info("gattCharacteristic can not Notify")
                return
            }
            //peripheral.discoverDescriptors(for: characteristic)
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func stopLightOnNotify()
    {
        if let characteristic = gattCharacteristic {
            if !characteristic.canNotify {
                Logger.info("gattCharacteristic can not Notify")
                return
            }
            peripheral.setNotifyValue(false, for: characteristic)
        }
    }


    private func checkSum(_ bArr: inout [Int]) {
        var i: Int = 0;
        for i2 in 0 ..< bArr.count - 1 {
            if bArr[i2] < 0 {
                bArr[i2] += 256
            }
            if bArr[i2] != 0 {
                i += 1
            }
        }
        bArr[bArr.count - 1] = i;
    }

    private func setLightValue(_ i1: Int, _ i2: Int, _ i3: Int ) -> Data {
        var bArr: [Int] = [Int](repeating: 0, count: i2 + 4)

        bArr[0] = 120;
        bArr[1] = i1
        bArr[2] = i2
        bArr[3] = i3
        checkSum(&bArr)

        var bArr1: [UInt8] = [UInt8](repeating: 0, count: i2 + 4)

        for i in 0 ..< bArr.count {
            bArr1[i] = UInt8(bArr[i])
        }

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    func setLightValue(_ tag: Int, _ value: Int)
    {
        Logger.info("setLightValue: \(value) for tag: \(tag)")
        let cmd = setLightValue(tag, 1, Int(value))
        write(data: cmd as Data, to: deviceCtlCharacteristic!)
    }

    // Set correlated color temperature
    func setLightCCT(_ i: Int)
    {
        let CCT_TAG = 0x83
        Logger.info("setLightCCT: \(i)")
        setLightValue(CCT_TAG, i);
    }

    // Set bulb brightness
    func setLightBRR(_ i: Int)
    {
        let BRR_TAG = 0x82
        Logger.info("setLightBRR: \(i)")
        setLightValue(BRR_TAG, i);
    }

    private func handleDescriptorUpdate(_ descriptor: CBDescriptor)
    {
        Logger.info("characteristic: \(descriptor.characteristic.uuid.uuidString)")
        Logger.info("descriptor: \(descriptor.uuid.uuidString)")
        if descriptor.uuid == CBUUID(string: CBUUIDClientCharacteristicConfigurationString) {
            if let value = descriptor.value as? Data {
                print("Characterstic \(descriptor.characteristic.uuid.uuidString) is also known as \(value.hexEncodedString())")
            }
        }
    }

    private func write(data value: Data, to characteristic: CBCharacteristic)
    {
        Logger.info("write data: \(value.hexEncodedString())")
        peripheral.writeValue(value, for: characteristic, type: .withResponse)
    }
}


extension NeewerLight :  CBPeripheralDelegate {

    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?)
    {
        Logger.info("peripheralDidUpdateRSSI")
        if let err = error {
            Logger.error("err: \(err)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?)
    {
        Logger.info("didUpdateValueFor characteristic: \(characteristic)")
        if let err = error {
            Logger.error("err: \(err)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?)
    {
        Logger.debug("didWriteValueFor characteristic: \(characteristic)")
        if let err = error {
            Logger.error("err: \(err)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?)
    {
        Logger.debug("didUpdateNotificationStateFor characteristic: \(characteristic)")
        if let err = error {
            Logger.error("err: \(err)")
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
        } else {
            handleDescriptorUpdate(descriptor)
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

