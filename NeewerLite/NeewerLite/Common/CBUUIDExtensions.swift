//
//  CBUUIDExtensions.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import CoreBluetooth

extension CBUUID {

    static let NeewerBleServiceUUID = CBUUID(string: "69400001-B5A3-F393-E0A9-E50E24DCCA99")

    static let NeewerDeviceCtlCharacteristicUUID = CBUUID(string: "69400002-B5A3-F393-E0A9-E50E24DCCA99")
    static let NeewerGattCharacteristicUUID = CBUUID(string: "69400003-B5A3-F393-E0A9-E50E24DCCA99")
}

