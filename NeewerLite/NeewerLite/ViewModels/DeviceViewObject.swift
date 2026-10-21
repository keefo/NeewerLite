//
//  DeviceViewObject.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class DeviceViewObject: NSObject {

    var device: NeewerLight
    var view: CollectionViewItem?
    var initing: Bool = false

    init(_ device: NeewerLight) {
        self.device = device

        super.init()
        initing = true

        self.device.isOn.bind { [weak self] (_) in
            guard let self, !self.initing else {
                return
            }
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.channel.bind { [weak self] (channel) in
            guard let self, !self.initing else {
                return
            }
            Logger.debug("Device channel update: \(channel)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceStatus()
                }
            }
        }
        self.device.userLightName.bind { [weak self] (name) in
            guard let self, !self.initing else {
                return
            }
            Logger.debug("Device name update: \(name)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceName()
                }
            }
        }

        self.device.brrValue.bind { [weak self] (val) in
            guard let self, !self.initing else {
                return
            }
            Logger.debug("Device brightness update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.brr, value: val)
                }
            }
        }

        self.device.cctValue.bind { [weak self] (val) in
            guard let self, !self.initing else {
                return
            }
            Logger.debug("Device CCT update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.cct, value: val)
                }
            }
        }

        self.device.gmmValue.bind { [weak self] (val) in
            guard let self, !self.initing else {
                return
            }
            Logger.debug("Device GM update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.gmm, value: val)
                }
            }
        }

        self.device.hueValue.bind { [weak self] (val) in
            guard let self, !self.initing else {
                return
            }
            Logger.debug("Device HUE update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.hue, value: val)
                }
            }
        }

        self.device.satValue.bind { [weak self] (val) in
            guard let self, !self.initing else {
                return
            }
            Logger.debug("Device HUE update: \(val)")
            DispatchQueue.main.async {
                if let theView = self.view {
                    theView.updateDeviceValueField(type: ControlTag.sat, value: val)
                }
            }
        }

        self.device.supportGMRange.bind { [weak self] support in
            guard let self, !self.initing else {
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
        guard let peripheral = device.peripheral else {
            return false
        }
        return peripheral.state == .connected
            && device.deviceCtlCharacteristic != nil
            && device.gattCharacteristic != nil
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

    @MainActor public func changeToMode(_ mode: TabId) {
        guard !self.initing else {
            return
        }
        if let theView = view {
            theView.selectTabViewItemSafely(withIdentifier: mode.rawValue)
        }
    }

    @MainActor public func changeToCCTMode() {
        guard !self.initing else {
            return
        }
        if !isCCTMode {
            changeToMode(TabId.cct)
        }
    }

    @MainActor public func changeToHSIMode() {
        guard !self.initing else {
            return
        }
        if device.supportRGB {
            if !isHSIMode {
                changeToMode(TabId.hsi)
            }
        }
    }

    @MainActor public func changeToSCEMode() {
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
            theView.updateFX(val)
            if let brrVal = brr {
                theView.updateBrightness(brrVal)
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
            if device.supportCCTGM {
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
