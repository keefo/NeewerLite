//
//  DeviceViewObject.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class DeviceViewObject: NSObject {
    private var syncLifetime: Timer?

    var device: NeewerLight
    var view: CollectionViewItem?

    init(_ device: NeewerLight) {
        self.device = device

        super.init()

        self.syncLifetime = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            //device.sendReadRequest()
        }

        self.device.isOn.bind { (_) in
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.channel.bind { (channel) in
            Logger.debug("Device channel update: \(channel)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.userLightName.bind { (name) in
            Logger.debug("Device name update: \(name)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceName()
                }
            }
        }

        self.device.brrValue.bind { (val) in
            Logger.debug("Device brightness update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.brr, value: val)
                }
            }
        }

        self.device.cctValue.bind { (val) in
            Logger.debug("Device CCT update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.cct, value: val)
                }
            }
        }

        self.device.gmmValue.bind { (val) in
            Logger.debug("Device GM update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.gmm, value: val)
                }
            }
        }

        self.device.hueValue.bind { (val) in
            Logger.debug("Device HUE update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.hue, value: val)
                }
            }
        }

        self.device.satValue.bind { (val) in
            Logger.debug("Device HUE update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.sat, value: val)
                }
            }
        }

        self.device.supportGMRange.bind { support in
            Logger.debug("Device supportGMRange update: \(support)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    // need to rebuild view
                    theView.buildView()
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
    
//    public var deviceImage: NSImage?
//
//    public func setDeviceImage(_ img: NSImage) {
//        deviceImage = img
//    }
//
//    public lazy var deviceImage: NSImage = {
//        var img = NSImage(named: "defaultLightImage")
//        let type = device.lightType
//        let name = NeewerLightConstant.getLightImageName()[type] ?? "defaultLightImage"
//        img = NSImage(named: name)
//        if img == nil {
//            img = NSImage(named: "defaultLightImage")
//        }
//        return img!
//    }()

    public var followMusic: Bool {
        return device.followMusic
    }

    public var deviceConnected: Bool {
        return device.peripheral != nil
    }

    public var hasMAC: Bool {
        return device.hasMAC()
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
            theView.lightModeTabView.selectTabViewItem(at: mode)
            //theView.lightModeButton.selectedSegment = mode
            //theView.lightModeButton.performClick(nil)
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
            // TODO: make this pass to view
//            let btn = NSButton()
//            btn.tag = val
//            theView.channelAction(btn)
//            theView.updateScene(true)
        }
    }

    public func updateCCT(_ cct: Int, _ bri: Double) {
        if let theView = view {
            var cttVal = Double(cct)
            let cctrange = device.CCTRange()

            if cttVal < Double(cctrange.minCCT) {
                cttVal = Double(cctrange.minCCT)
            }
            if cttVal > Double(cctrange.maxCCT) {
                cttVal = Double(cctrange.maxCCT)
            }

            // TODO: update UI CCT values
            //            theView.cctCctSlide.doubleValue = Double(cttVal/100.0)
            //            theView.cctBrrSlide.doubleValue = bri
            //            theView.slideAction(theView.cctCctSlide)
            //            theView.slideAction(theView.cctBrrSlide)
        }
    }

    public var HSB: HSB {
        @available(*, unavailable)
        get {
            fatalError("You cannot read from this object.")
        }
        set {
            if let theView = view {
                // TODO: Need to PASS HSB into dev
                Logger.debug("Need to PASS HSB into dev \(newValue)")
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
