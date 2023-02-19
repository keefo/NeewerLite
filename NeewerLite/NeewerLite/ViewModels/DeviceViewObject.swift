//
//  DeviceViewObject.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class DeviceViewObject {
    private var syncLifetime: Timer?
    private var doNotUpdateUI: Bool = false

    var device: NeewerLight
    var view: CollectionViewItem?

    init(_ device: NeewerLight) {
        self.device = device
        self.syncLifetime = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            self.doNotUpdateUI = true
            device.sendReadRequest()
            device.saveToUserDefault()
        }
        self.device.isOn.bind { (_) in
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.channel.bind { (channel) in
            if self.doNotUpdateUI {
                Logger.debug("Device channel update: \(channel) doNotUpdateUI")
                self.doNotUpdateUI = false
                return
            }
            Logger.debug("Device channel update: \(channel)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
    }

    deinit {
        Logger.debug("DeviceViewObject deinit")
        clear()
    }

    public func clear() {
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
        } else if device.rawName.contains("RGB176") {
            img = NSImage(named: "light-rgb176")
        } else if device.rawName.contains("SNL660") {
            img = NSImage(named: "light-rgb660-pro")
        }
        if img == nil {
            img = NSImage(named: "defaultLightImage")
        }
        return img!
    }()

    public var followMusic: Bool {
        return device.followMusic
    }

    public var isON: Bool {
        return device.isOn.value
    }

    public var isCCTMode: Bool {
        return device.lightMode == .CCTMode
    }

    public var isHSIMode: Bool {
        return device.lightMode == .HSIMode
    }

    public var isSCEMode: Bool {
        return device.lightMode == .SCEMode
    }

    public func changeToMode(_ mode: Int) {
        if let theView = view {
            theView.lightModeButton.selectedSegment = mode
            theView.lightModeButton.performClick(nil)
        }
    }

    public func changeToCCTMode() {
        if !isCCTMode {
            changeToMode(0)
        }
    }

    public func changeToHSIMode() {
        if !isHSIMode {
            changeToMode(1)
        }
    }

    public func changeToSCEMode() {
        if !isSCEMode {
            changeToMode(2)
        }
    }

    public func changeToSCE(_ val: Int) {
        if let theView = view {
            let btn = NSButton()
            btn.tag = val
            theView.channelAction(btn)
            theView.updateScene(true)
        }
    }

    public func updateCCT(_ cct: Int, _ bri: Double) {
        if let theView = view {
            var cttVal = Double(cct)
            if device.supportLongCCT {
                if cttVal < 3200 {
                    cttVal = 3200
                }
                if cttVal > 8500 {
                    cttVal = 8500
                }
            } else {
                if cttVal < 3200 {
                    cttVal = 3200
                }
                if cttVal > 5600 {
                    cttVal = 5600
                }
            }
            theView.cctCctSlide.doubleValue = Double(cttVal/100.0)
            theView.cctBrrSlide.doubleValue = bri
            theView.slideAction(theView.cctCctSlide)
            theView.slideAction(theView.cctBrrSlide)
        }
    }

    public var HSB: HSB {
        @available(*, unavailable)
        get {
            fatalError("You cannot read from this object.")
        }
        set {
            if let theView = view {
                theView.updateHueAndSaturationAndBrightness(newValue.hue,
                                                            saturation: newValue.saturation,
                                                            brightness: newValue.brightness,
                                                            updateWheel: true)
            }
        }
    }

    public func toggleLight() {
        if device.isOn.value {
            device.sendPowerOffRequest()
        } else {
            device.sendPowerOnRequest()
        }
    }

    public func turnOnLight() {
        device.sendPowerOnRequest()
    }

    public func turnOffLight() {
        device.sendPowerOffRequest()
    }
}
