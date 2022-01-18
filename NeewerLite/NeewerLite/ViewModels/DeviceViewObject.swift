//
//  DeviceViewObject.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

typealias HSB_t = (CGFloat,CGFloat,CGFloat)

class DeviceViewObject
{
    private var syncLifetime: Timer?
    private var doNotUpdateUI: Bool = false

    var device: NeewerLight
    var view: CollectionViewItem? = nil

    init(_ device: NeewerLight) {
        self.device = device
        self.syncLifetime = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            self.doNotUpdateUI = true
            device.sendReadRequest()
            device.saveToUserDefault()
        }
        self.device.isOn.bind { (on) in
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.channel.bind { (ch) in
            if self.doNotUpdateUI {
                Logger.debug("Device channel update: \(ch) doNotUpdateUI")
                self.doNotUpdateUI = false
                return
            }
            Logger.debug("Device channel update: \(ch)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
    }

    deinit {
        Logger.debug("DeviceViewObject deinit")
        if let safeTimer = self.syncLifetime {
            safeTimer.invalidate()
        }
    }

    public lazy var deviceName: String = {
        return device.deviceName
    }()

    public lazy var deviceIdentifier: String = {
        return "\(device.identifier)"
    }()

    public lazy var deviceImage: NSImage = {
        var img = NSImage(named: "defaultLightImage")
        if device.rawName.contains("RGB660") || device.rawName.contains("RGB480") {
            img = NSImage(named: "light-rgb660-pro")
        }
        else if device.rawName.contains("SNL660") {
            img = NSImage(named: "light-rgb660-pro")
        }
        if img == nil {
            img = NSImage(named: "defaultLightImage")
        }
        return img!
    }()

    public var followMusic: Bool {
        return self.device.followMusic
    }

    public var isON: Bool {
        return self.device.isOn.value
    }

    public var isHSIMode: Bool {
        return self.device.lightMode == .HSIMode
    }

    public var HSB : HSB_t {
        @available(*, unavailable)
        get {
            fatalError("You cannot read from this object.")
        }
        set {
            if let theView = view {
                theView.updateHueAndSaturationAndBrightness(newValue.0, saturation: CGFloat(self.device.satruationValue)/100.0, brightness: CGFloat(self.device.brrValue)/100.0, updateWheel: true)
            }
        }
    }

    public func toggleLight()
    {
        device.isOn.value ? device.sendPowerOffRequest() : device.sendPowerOnRequest()
    }

    public func turnOnLight()
    {
        device.sendPowerOnRequest()
    }

    public func turnOffLight()
    {
        device.sendPowerOffRequest()
    }
}

