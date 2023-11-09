//
//  CBCharacteristicExtensions.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/16/21.
//

import Foundation
import CoreBluetooth

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

func getConnectedBluetoothDevices() -> [[String: String]]? {
    // Run the system_profiler command

    let task = Process()
    task.launchPath = "/usr/sbin/system_profiler"
    task.arguments = ["-xml", "SPBluetoothDataType"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.launch()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [[String: Any]] else {
        print("Failed to deserialize plist")
        return nil
    }

    var result : [[String: String]] = []
    for dict in plist {
        if let items = dict["_items"] as? [[String: Any]] {
            for item in items {
                for subitem in item {
                    if subitem.key == "device_connected" {
                        if let devices = subitem.value as? [Any] {
                            for dev in devices {
                                if let devdict = dev as? [String: Any] {
                                    for (key, value) in devdict {
                                        if let keyStr = key as? String, let valueDict = value as? [String: Any] {
                                            if var newDict = valueDict as? [String: String] {
                                                newDict["name"] = keyStr
                                                result.append(newDict)
                                            }
                                        }
                                    }
                                }
                            }
                            return result
                        }
                    }
                }
            }
        }
    }

    return result
}



