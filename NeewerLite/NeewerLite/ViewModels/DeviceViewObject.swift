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
    var initing: Bool = false

    init(_ device: NeewerLight) {
        self.device = device

        super.init()
        initing = true

        self.syncLifetime = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            //device.sendReadRequest()
        }

        self.device.isOn.bind { (_) in
            guard !self.initing else {
                return
            }
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.channel.bind { (channel) in
            guard !self.initing else {
                return
            }
            Logger.debug("Device channel update: \(channel)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.userLightName.bind { (name) in
            guard !self.initing else {
                return
            }
            Logger.debug("Device name update: \(name)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceName()
                }
            }
        }

        self.device.brrValue.bind { (val) in
            guard !self.initing else {
                return
            }
            Logger.debug("Device brightness update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.brr, value: val)
                }
            }
        }

        self.device.cctValue.bind { (val) in
            guard !self.initing else {
                return
            }
            Logger.debug("Device CCT update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.cct, value: val)
                }
            }
        }

        self.device.gmmValue.bind { (val) in
            guard !self.initing else {
                return
            }
            Logger.debug("Device GM update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.gmm, value: val)
                }
            }
        }

        self.device.hueValue.bind { (val) in
            guard !self.initing else {
                return
            }
            Logger.debug("Device HUE update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.hue, value: val)
                }
            }
        }

        self.device.satValue.bind { (val) in
            guard !self.initing else {
                return
            }
            Logger.debug("Device HUE update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.sat, value: val)
                }
            }
        }

        self.device.supportGMRange.bind { support in
            guard !self.initing else {
                return
            }
            Logger.debug("Device supportGMRange update: \(support)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    // need to rebuild view
                    theView.buildView()
                }
            }
        }

        initing = false
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

    public func changeToMode(_ mode: TabId) {
        guard !self.initing else {
            return
        }
        if let theView = view {
            theView.selectTabViewItemSafely(withIdentifier: mode.rawValue)
        }
    }

    public func changeToCCTMode() {
        guard !self.initing else {
            return
        }
        if !isCCTMode {
            changeToMode(TabId.cct)
        }
    }

    public func changeToHSIMode() {
        guard !self.initing else {
            return
        }
        if device.supportRGB {
            if !isHSIMode {
                changeToMode(TabId.hsi)
            }
        }
    }

    public func changeToSCEMode() {
        guard !self.initing else {
            return
        }
        if device.supportRGB {
            if !isSCEMode {
                changeToMode(TabId.scene)
            }
        }
    }

    public func changeToSCE(_ val: Int, _ brr: Double?) {
        guard !self.initing else {
            return
        }
        if let theView = view {
            theView.updteFX(val)
            if let brrVal = brr {
                theView.updteBrightness(brrVal)
            }
        }
    }

    public func updateCCT(_ cct: Int, _ gmm: Int, _ brr: Double?) {
        guard !self.initing else {
            return
        }
        if let theView = view {
            var cctVal = Double(cct)
            if cctVal > 900 {
                cctVal /= 100.0
            }
            let cctrange = device.CCTRange()
            cctVal = cctVal.clamped(to: Double(cctrange.minCCT)...Double(cctrange.maxCCT))

            var gmmValue = Double(gmm)
            if device.supportGMRange.value {
                gmmValue = gmmValue.clamped(to: -50...50)
            } else {
                gmmValue = 0.0
            }

            theView.updateCCT(cct: cctVal, gmm: gmmValue, brr: brr)
        }
    }

    public func updateHSI(hue: CGFloat, sat: CGFloat, brr: Double?) {
        guard !self.initing else {
            return
        }
        if let theView = view {
            theView.updateHSI(hue: hue, sat: sat, brr: brr)
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
