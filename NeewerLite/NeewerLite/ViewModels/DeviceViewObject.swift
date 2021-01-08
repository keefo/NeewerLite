//
//  DeviceViewObject.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class DeviceViewObject
{
    var device: NeewerLight

    init(_ device: NeewerLight) {
        self.device = device
    }

    public lazy var deviceName: String = {
        return "\(device.peripheral.name ?? "Unknow Name")"
    }()

    public lazy var deviceIdentifier: String = {
        return "\(device.peripheral.identifier)"
    }()

    public lazy var deviceImage: NSImage = {
        var img = NSImage(named: "defaultLightImage")
        if deviceName.contains("RGB660 PRO") {
            img = NSImage(named: "light-rgb660-pro")
        }
        if img == nil {
            img = NSImage(named: "defaultLightImage")
        }
        return img!
    }()
}

