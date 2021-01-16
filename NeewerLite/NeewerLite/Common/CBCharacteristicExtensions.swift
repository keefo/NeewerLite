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
