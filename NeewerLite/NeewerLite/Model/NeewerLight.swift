//
//  NeewerDevice.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa
import CoreBluetooth
import IOBluetooth

protocol ObservableNeewerLightProtocol {
    var isOn: Observable<Bool> { get set }
    var channel: Observable<UInt8> { get set }
    var userLightName: Observable<String> { get set }
    var supportGMRange: Observable<Bool> { get set }
    var brrValue: Observable<Int> { get set }
    var cctValue: Observable<Int> { get set }
    var hueValue: Observable<Int> { get set }
    var satValue: Observable<Int> { get set }
    var gmmValue: Observable<Int> { get set }
}

class NeewerLight: NSObject, ObservableNeewerLightProtocol {

    enum Mode: UInt8 {
        case CCTMode = 1    // Bi-color mode
        case HSIMode        // Color mode
        case SCEMode        // Scene mode, or animation mode or channel mode
        case SRCMode        // Source mode
    }

    struct BleUpdate {
        static let channelUpdatePrefix = Data([0x78, 0x01, 0x01])
    }

    var peripheral: CBPeripheral?
    var deviceCtlCharacteristic: CBCharacteristic?
    var gattCharacteristic: CBCharacteristic?

    var fake: Bool = false // this is for debugging purpose
    var isOn: Observable<Bool> = Observable(false)
    var channel: Observable<UInt8> = Observable(1) // 1 ~ maxChannel
    var userLightName: Observable<String> = Observable("")
    var supportGMRange: Observable<Bool> = Observable(false)
    var brrValue: Observable<Int> = Observable(+50) // Brightness, range 0~100
    var cctValue: Observable<Int> = Observable(+53) // CCT - Correlated color temperature, range depents on light type 1800K ~ 5300K
    var hueValue: Observable<Int> = Observable(+00) // HUE 0~360
    var satValue: Observable<Int> = Observable(+00) // Saturation range 0~100
    var gmmValue: Observable<Int> = Observable(-50) // GM, use name gmm for better code alignment, range -50~50
    var lastTab: String = ""

    var maxChannel: UInt8 {
        return UInt8(supportedFX.count)
    }

    var lightType: UInt8 {
        return _lightType
    }

    var supportedFX: [NeewerLightFX] = []
    var supportedSource: [NeewerLightSource] = []

    var connectionBreakCounter: Int = 0  // if connection break too many times which mean this light disappeared from bluetooth fabric.

    private var _writeDispatcher: DispatchWorkItem?
    private var _rawName: String?
    private var _identifier: String?
    private var _nickName: String?
    private var _projectName: String?
    private var _macAddress: String?
    private var _lightType: UInt8 = 0 {
        didSet {
            let fxs = NeewerLightConstant.getLightFX(lightType: _lightType)
            if supportedFX.isEmpty {
                supportedFX = fxs
            } else {
                // Assuming both `fxs` and `supportedFX` are of the same type and contain unique ids.
                supportedFX = fxs.map { fx1 in
                    let newFx = fx1
                    if let matchingFx = supportedFX.first(where: { $0.id == fx1.id }) {
                        newFx.featureValues = matchingFx.featureValues
                    }
                    return newFx
                }
                Logger.debug("supportedFX: \(supportedFX)")
            }

            let sources = NeewerLightConstant.getLightSources(lightType: _lightType)
            if supportedSource.isEmpty {
                supportedSource = sources
            } else {
                // Assuming both `fxs` and `supportedFX` are of the same type and contain unique ids.
                supportedSource = sources.map { fx2 in
                    let newFx = fx2
                    if let matchingFx = supportedSource.first(where: { $0.id == fx2.id }) {
                        newFx.featureValues = matchingFx.featureValues
                    }
                    return newFx
                }
                Logger.debug("supportedSource: \(supportedSource)")
            }
        }
    }

    var lightMode: NeewerLight.Mode = .CCTMode {
        didSet {
            Logger.debug("lightMode: \(lightMode)")
        }
    }

    // var brrValue: Int = 50    // 0~100
    // var cctValue: Int = 53  // 5300K
    // var hueValue: Int = 0     // 0~360
    // var gmValue: Int = -50     // -50~50
    // var satruationValue: Int = 0 // 0~100
    var followMusic: Bool = false
    var macCheckCount: Int = 10

    // read only properties
    var supportRGB: Bool {
        // some lights are only Bi-Color which does not support RGB.
        return NeewerLightConstant.getRGBLightTypes().contains(_lightType)
    }

    func CCTRange() -> (minCCT: Int, maxCCT: Int) {
        // Default CCT range from 3200k–5600k
        // some lights support extended CCT range from 3200K–8500K such as
        // https://neewer.com/products/neewer-sl80-10w-rgb-led-video-light-10097903?_pos=1&_sid=dfa97e049&_ss=r&variant=37586440683713
        if ligthType == 6 {
            if projectName.contains("SL140") {
                // https://neewer.com/products/neewer-sl-140-rgb-led-light-full-color-rechargeable-pocket-size-10097200?_pos=2&_sid=3ff26da17&_ss=r
                return (minCCT: 25, maxCCT: 90)
            } else {
                return (minCCT: 25, maxCCT: 85)
            }
        }
        if ligthType == 22 {
            return (minCCT: 27, maxCCT: 65)
        }
        return (minCCT: 32, maxCCT: 56)
    }

    var deviceName: String {
        var name = String(rawName)
        if name.hasPrefix("NW") {
            return "NW-\(projectName)"
        }
        return name
    }

    var nickNameSuffix: String {
        // In andorid app the suffix is MAC address last 3 without :
        // 00:1A:2B:3C:4D:5E -> 3C4D5E
        // macOS Bluetooth Frameword does not provide a way to get MAC.
        if _macAddress != nil {
            return String(_macAddress?.replacingOccurrences(of: ":", with: "").suffix(6) ?? identifier.suffix(6))
        }
        return String(identifier.suffix(6))
    }

    var nickName: String {
        if _nickName == nil {
            let name = NeewerLightConstant.getLightNames(rawName: String(rawName), identifier: String(nickNameSuffix))
            _nickName = name.nickName
        }
        return _nickName!
    }

    var projectName: String {
        if _projectName == nil {
            let name = NeewerLightConstant.getLightNames(rawName: String(rawName), identifier: String(nickNameSuffix))
            _projectName = name.projectName
        }
        if _projectName == nil {
            Logger.error("Unable to get projectName")
        }
        return _projectName!
    }

    public lazy var identifier: String = {
        if _identifier != nil {
            return _identifier!
        }
        if let sefePeripheral = peripheral {
            _identifier = "\(sefePeripheral.identifier)"
        }
        return "\(_identifier ?? "")"
    }()

    public lazy var rawName: String = {
        if _rawName != nil {
            return _rawName!
        }
        guard let name = peripheral?.name else { return "" }
        _rawName = name
        return _rawName!
    }()

    public func getMAC() -> String {
        return _macAddress ?? ""
    }

    private lazy var ligthType: UInt8 = {
        if _lightType <= 0 {
            _lightType = NeewerLightConstant.getLightType(nickName: nickName, str: "", projectName: projectName)
        }
        return _lightType
    }()

    init(_ peripheral: CBPeripheral, _ deviceCtlCharacteristic: CBCharacteristic, _ gattCharacteristic: CBCharacteristic) {
        super.init()
        setPeripheral(peripheral, deviceCtlCharacteristic, gattCharacteristic)
        // Logger.debug("     config: \(getConfig())")
        Logger.debug("    rawName: \(rawName)")
        Logger.debug("        MAC: \(_macAddress ?? "")")
        Logger.debug(" identifier: \(identifier)")
        Logger.debug("projectName: \(projectName)")
        Logger.debug("   nickName: \(nickName)")
        Logger.debug("  ligthType: \(ligthType)")
    }

    func getConfig(_ intrinsicOnly: Bool = false) -> [String: CodableValue] {
        var vals: [String: CodableValue] = [:]
        vals["mac"] = _macAddress.map { CodableValue.stringValue($0) }
        vals["rawname"] = _rawName.map { CodableValue.stringValue($0) }
        vals["identifier"] = _identifier.map { CodableValue.stringValue($0) }
        if !intrinsicOnly {
            vals["on"] = CodableValue.boolValue(isOn.value)
            vals["mod"] = CodableValue.uint8Value(lightMode.rawValue)
            vals["cct"] = CodableValue.intValue(cctValue.value)
            vals["brr"] = CodableValue.intValue(brrValue.value)
            vals["chn"] = CodableValue.uint8Value(channel.value)
            vals["hue"] = CodableValue.intValue(hueValue.value)
            vals["sat"] = CodableValue.intValue(satValue.value)
            vals["gmm"] = CodableValue.intValue(gmmValue.value)
            if userLightName.value.lengthOfBytes(using: .utf8) > 0 {
                vals["nme"] = CodableValue.stringValue(userLightName.value)
            }
            vals["supportedFX"] = CodableValue.fxsValue(supportedFX)
            vals["supportedSource"] = CodableValue.sourcesValue(supportedSource)
            vals["lastTab"] = CodableValue.stringValue(lastTab)
        } else {
            vals["type"] = CodableValue.uint8Value(_lightType)
            vals["nickname"] = CodableValue.stringValue(nickName)
            vals["projectname"] = CodableValue.stringValue(projectName)
        }
        return vals
    }

    init(_ config: [String: CodableValue]) {

        super.init()
        fake = config["fake"]?.boolValue ?? false
        lastTab = config["lastTab"]?.stringValue ?? "cctTab"
        _macAddress = config["mac"]?.stringValue ?? ""
        _rawName = config["rawname"]?.stringValue ?? ""
        _identifier = config["identifier"]?.stringValue ?? ""
        isOn.value = config["on"]?.boolValue ?? false

        if let val = config["mod"]?.uint8Value {
            Logger.debug("load mod \(val)")
            if UInt8(val) == NeewerLight.Mode.CCTMode.rawValue {
                lightMode = .CCTMode
            } else if UInt8(val) == NeewerLight.Mode.HSIMode.rawValue {
                lightMode = .HSIMode
            } else if UInt8(val) == NeewerLight.Mode.SCEMode.rawValue {
                lightMode = .SCEMode
            }
        }

        cctValue.value = config["cct"]?.intValue ?? 0
        brrValue.value = config["brr"]?.intValue ?? 0
        channel.value = config["chn"]?.uint8Value ?? 1
        hueValue.value = config["hue"]?.intValue ?? 1
        satValue.value = config["sat"]?.intValue ?? 1
        userLightName.value = config["nme"]?.stringValue ?? ""

        if let val = config["supportedFX"]?.fxsValue {
            supportedFX.removeAll()
            supportedFX.append(contentsOf: val)
        }

        if let val = config["supportedSource"]?.sourcesValue {
            supportedSource.removeAll()
            supportedSource.append(contentsOf: val)
        }

        if let safeMac = _macAddress {
            if (safeMac.lengthOfBytes(using: .utf8)) > 8 && self.ligthType == 22 {
                supportGMRange.value = true
            }
        }

        Logger.debug("        rawName: \(rawName)")
        Logger.debug("            MAC: \(_macAddress ?? "")")
        Logger.debug("     identifier: \(identifier)")
        Logger.debug("    projectName: \(projectName)")
        Logger.debug("       nickName: \(nickName)")
        Logger.debug("      ligthType: \(ligthType)")
        Logger.debug("    supportedFX: \(supportedFX)")
        Logger.debug("supportedSource: \(supportedSource)")
    }

    deinit {
        self.peripheral?.delegate = nil
        Logger.debug("deinit: \(self)")
    }

    func setPeripheral(_ peripheral: CBPeripheral?, _ deviceCtlCharacteristic: CBCharacteristic?, _ gattCharacteristic: CBCharacteristic?) {
        self.peripheral = peripheral
        self.deviceCtlCharacteristic = deviceCtlCharacteristic
        self.gattCharacteristic = gattCharacteristic
        self.peripheral?.delegate = self
        if _macAddress == nil || _macAddress == "" {
            discoverMAC(self.peripheral!)
        }
    }

    func hasMAC() -> Bool {
        if let mac = _macAddress {
            if mac.lengthOfBytes(using: .utf8) == 17 {
                return true
            }
        }
        return false
    }

    func isValid() -> Bool {
        if _macAddress == nil || _identifier == nil {
            return false
        }
        return _macAddress != "" && _identifier != ""
    }

    func sendKeepAlive(_ cbm: CBCentralManager?) {
        guard let peripheral = self.peripheral else {
            return
        }
        if peripheral.state == .connected {
            Logger.debug("sendKeepAlive self.peripheral.state: connected")
        } else if peripheral.state == .disconnected {
            Logger.debug("sendKeepAlive self.peripheral.state: disconnected")
        } else if peripheral.state == .connecting {
            Logger.debug("sendKeepAlive self.peripheral.state: connecting")
        } else if peripheral.state == .disconnecting {
            Logger.debug("sendKeepAlive self.peripheral.state: disconnecting")
        } else {
            Logger.debug("sendKeepAlive self.peripheral.state: unknow")
        }

        if peripheral.state == .connected {
            connectionBreakCounter = 0
        }
        if peripheral.state != .connected {
            cbm?.connect(peripheral, options: nil)
            connectionBreakCounter += 1
        } else {
            if isOn.value {
                sendPowerOnRequest()
            } else {
                sendPowerOffRequest()
            }
        }
    }

    func sendPowerOnRequest() {
        Logger.debug("send powerOn")
        isOn.value = true
        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        self.write(data: NeewerLightConstant.BleCommand.powerOn as Data, to: characteristic)
    }

    func sendPowerOffRequest() {
        Logger.debug("send powerOff")
        isOn.value = false
        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        self.write(data: NeewerLightConstant.BleCommand.powerOff as Data, to: characteristic)
    }

    func sendReadRequest() {
        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        write(data: NeewerLightConstant.BleCommand.readRequest as Data, to: characteristic)
    }

    func startLightOnNotify() {
        guard let characteristic = gattCharacteristic else {
            return
        }
        if !characteristic.canNotify {
            Logger.debug("gattCharacteristic can not Notify")
            return
        }
        peripheral?.setNotifyValue(true, for: characteristic)
    }

    func stopLightOnNotify() {
        guard let characteristic = gattCharacteristic else {
            return
        }
        if !characteristic.canNotify {
            Logger.debug("gattCharacteristic can not Notify")
            return
        }
        peripheral?.setNotifyValue(false, for: characteristic)
    }

    // Set correlated color temperature and bulb brightness in CCT Mode
    public func setCCTLightValues(brr: CGFloat, cct: CGFloat, gmm: CGFloat) {
        var cmd: Data = Data()
        Logger.debug("setCCTLightValues")

        if supportGMRange.value {
            cmd = getCCTDATALightValue(brightness: brr, correlatedColorTemperature: cct, gmm: gmm)
        } else if supportRGB {
            cmd = getCCTLightValue(brightness: brr, correlatedColorTemperature: cct)
        } else {
            cmd = getCCTOnlyLightValue(brightness: brr, correlatedColorTemperature: cct)
        }
        lightMode = .CCTMode
        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        write(data: cmd as Data, to: characteristic)
    }

    // Set RBG light in HSV Mode
    public func setRGBLightValues(brr: CGFloat, hue: CGFloat, sat: CGFloat) {
        var cmd: Data = Data()
        // Logger.debug("hue: \(hue) sat: \(sat)")
        cmd = getRGBLightValue(brightness: brr, hue: hue, satruation: sat)

        lightMode = .HSIMode

        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        write(data: cmd as Data, to: characteristic)
    }

    // Set Scene
    public func setScene(_ scene: UInt8, brightness brr: CGFloat) {
        var cmd: Data = Data()
        cmd = getSceneValue(scene, brightness: CGFloat(brr))
        lightMode = .SCEMode

        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        write(data: cmd as Data, to: characteristic)
    }

    // Send Scene
    public func sendSceneCommand(_ fxx: NeewerLightFX) {
        var cmd: Data = Data()

        if NeewerLightConstant.getRGBLightTypesThatSupport17FX().contains(_lightType) {
            cmd = getSceneCommand(_macAddress ?? "", fxx)
            channel.value = UInt8(fxx.id)
        } else {
            cmd = getSceneValue(UInt8(fxx.id), brightness: CGFloat(fxx.brrValue))
        }
        lightMode = .SCEMode

        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        write(data: cmd as Data, to: characteristic)
    }

    private func handleNotifyValueUpdate(_ data: Data) {
        guard validateCheckSum(data) else {
            Logger.error("recived notify value update, but the checksum is invalid. \(data.hexEncodedString())")
            return
        }

        if data.prefix(upTo: BleUpdate.channelUpdatePrefix.count) == BleUpdate.channelUpdatePrefix
            && data.count == BleUpdate.channelUpdatePrefix.count + 2 {
            // data[3] range in [0,1,2,3,4,5,6,7,8]
            if maxChannel >= 1 {
                channel.value = UInt8(data[3]+1).clamped(to: 1...maxChannel) // only 1-maxChannel channel a allowed.
            } else {
                channel.value = UInt8(data[3]+1).clamped(to: 1...30)
            }
        } else {
            Logger.info("handleNotifyValueUpdate \(data.hexEncodedString())")
        }
    }

    private func validateCheckSum(_ data: Data) -> Bool {
        if data.count < 2 {
            return false
        }

        var checkSum: Int = 0
        for idx in 0 ..< data.count - 1 {
            checkSum += Int(data[idx])
        }

        if data[data.count - 1]  == UInt8(checkSum & 0xFF) {
            return true
        }
        return false
    }

    private func appendCheckSum(_ bArr: [Int]) -> [UInt8] {
        var bArr1: [UInt8] = [UInt8](repeating: 0, count: bArr.count)

        var checkSum: Int = 0
        for idx in 0 ..< bArr.count - 1 {
            bArr1[idx] = bArr[idx] < 0 ? UInt8(bArr[idx] + 0x100) : UInt8(bArr[idx])
            checkSum += Int(bArr1[idx])
        }

        bArr1[bArr.count - 1] = UInt8(checkSum & 0xFF)
        return bArr1
    }

    private func composeSingleCommand(_ tag: Int, _ vals: Int...) -> [UInt8] {
        let byteCount = vals.count
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)
        bArr[0] = NeewerLightConstant.BleCommand.prefixTag
        bArr[1] = tag
        bArr[2] = byteCount

        var idx = 3
        for val in vals {
            bArr[idx] = val
            idx += 1
        }
        return appendCheckSum(bArr)
    }

    private func composeSingleCommandWithMac(_ tag: Int, _ mac: String, _ subtag: Int, _ vals: [Int]) -> [UInt8] {
        let byteCount = vals.count
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 11)
        bArr[0] = NeewerLightConstant.BleCommand.prefixTag
        bArr[1] = tag
        bArr[2] = byteCount + 7
        var intArray = mac.split(separator: ":").compactMap { Int($0, radix: 16) }
        while intArray.count < 6 {
            intArray.append(0)
        }
        bArr[3] = intArray[0]
        bArr[4] = intArray[1]
        bArr[5] = intArray[2]
        bArr[6] = intArray[3]
        bArr[7] = intArray[4]
        bArr[8] = intArray[5]
        bArr[9] = subtag
        var idx = 10
        for val in vals {
            bArr[idx] = val
            idx += 1
        }
        return appendCheckSum(bArr)
    }

    private func getCCTDATALightValue(brightness brr: CGFloat, correlatedColorTemperature cct: CGFloat, gmm: CGFloat) -> Data {
        var ratio = 100.0
        if brr > 1.0 {
            ratio = 1.0
        }
        // cct range from 0x20(32) - 0x38(56) 32 stands for 3200K 65 stands for 5600K
        let cctrange = CCTRange()
        let newCctValue: Int = Int(cct).clamped(to: cctrange.minCCT...cctrange.maxCCT)
        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr * ratio).clamped(to: 0...100)
        let newGmValue: Int = Int(gmm).clamped(to: -50...50)

        gmmValue.value = newGmValue
        cctValue.value = newCctValue
        brrValue.value = newBrrValue

        Logger.debug("brrValue.value: \(brrValue.value)")
        Logger.debug("cctValue.value: \(cctValue.value)")
        Logger.debug("gmmValue.value: \(gmmValue.value)")

        let dimmingCurveType = 0x04
        let iArr: [Int] = [brrValue.value, cctValue.value, gmmValue.value+50, dimmingCurveType]

        let bArr1: [UInt8] = composeSingleCommandWithMac(NeewerLightConstant.BleCommand.setCCTDataTag, _macAddress!, NeewerLightConstant.BleCommand.setCCTLightTag, iArr)
        let data = NSData(bytes: bArr1, length: bArr1.count) as Data

        return data
    }

    private func getCCTLightValue(brightness brr: CGFloat, correlatedColorTemperature cct: CGFloat) -> Data {
        var ratio = 100.0
        if brr >= 1.0 {
            ratio = 1.0
        }
        // cct range from 0x20(32) - 0x38(56) 32 stands for 3200K 65 stands for 5600K
        let cctrange = CCTRange()
        let newCctValue: Int = Int(cct).clamped(to: cctrange.minCCT...cctrange.maxCCT)
        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr * ratio).clamped(to: 0...100)

        if newCctValue == 0 {
            // only adjust the brightness and keep the color temp
            if brrValue.value == newBrrValue {
                return Data()
            }
            brrValue.value = newBrrValue

            let bArr1: [UInt8] = composeSingleCommand(NeewerLightConstant.BleCommand.setCCTLightTag, brrValue.value)

            let data = NSData(bytes: bArr1, length: bArr1.count)
            return data as Data
        }

        cctValue.value = newCctValue
        brrValue.value = newBrrValue

        let bArr1: [UInt8] = composeSingleCommand(NeewerLightConstant.BleCommand.setCCTLightTag, brrValue.value, cctValue.value)

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    // Not sure what is is L stand for.
    private func getCCTOnlyLightValue(brightness brr: CGFloat, correlatedColorTemperature cct: CGFloat) -> Data {
        // cct range from 0x20(32) - 0x38(56) 32 stands for 3200K 65 stands for 5600K
        let cctrange = CCTRange()
        let newCctValue: Int = Int(cct).clamped(to: cctrange.minCCT...cctrange.maxCCT)
        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr).clamped(to: 0...100)

        if newCctValue == 0 {
            // only adjust the brightness and keep the color temp
            if brrValue.value == newBrrValue {
                return Data()
            }
            brrValue.value = newBrrValue

            let bArr1: [UInt8] = composeSingleCommand(NeewerLightConstant.BleCommand.setLongCCTLightBrightnessTag, brrValue.value)

            let data = NSData(bytes: bArr1, length: bArr1.count)
            return data as Data
        }

        cctValue.value = newCctValue
        brrValue.value = newBrrValue

        let bArr1 = composeSingleCommand(NeewerLightConstant.BleCommand.setLongCCTLightBrightnessTag, brrValue.value)
        let bArr2 = composeSingleCommand(NeewerLightConstant.BleCommand.setLongCCTLightCCTTag, cctValue.value)
        let bArr = bArr1 + bArr2

        let data = NSData(bytes: bArr, length: bArr.count)
        return data as Data
    }

    public func setBRRLightValues(_ brr: CGFloat) {
        var cmd: Data = Data()
        if lightMode == .CCTMode {
            if supportRGB {
                cmd = getCCTLightValue(brightness: brr, correlatedColorTemperature: CGFloat(cctValue.value))
            } else {
                cmd = getCCTOnlyLightValue(brightness: brr, correlatedColorTemperature: CGFloat(cctValue.value))
            }
        } else if lightMode == .HSIMode {
            cmd = getRGBLightValue(brightness: brr, hue: CGFloat(hueValue.value) / 360.0, satruation: CGFloat(satValue.value) / 100.0)
        } else {
            cmd = getSceneValue(channel.value, brightness: CGFloat(brr))
        }
        guard let characteristic = deviceCtlCharacteristic else {
            return
        }
        write(data: cmd as Data, to: characteristic)
    }

    private func getRGBLightValue(brightness brr: CGFloat, hue theHue: CGFloat, satruation sat: CGFloat ) -> Data {
        var ratio = 100.0
        if brr > 1.0 {
            ratio = 1.0
        }
        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr * ratio).clamped(to: 0...100)
        let newSatValue: Int = Int(sat * 100.0).clamped(to: 0...100)
        let newHueValue = Int(theHue * 360.0).clamped(to: 0...360)

        // Red  7886 0400 0064 643F
        // Blue 7886 04E7 0064 64B0
        // Yell 7886 043E 0064 64B0
        // Gree 7886 0476 0064 643F
        // Red  7886 0468 0164 643F
        // Logger.debug("hue \(newHueValue) sat \(newSatValue)")

        let byteCount = 4
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

        bArr[0] = NeewerLightConstant.BleCommand.prefixTag
        bArr[1] = NeewerLightConstant.BleCommand.setRGBLightTag
        bArr[2] = byteCount
        // 4 eletements
        bArr[3] = Int(newHueValue & 0xFF)
        bArr[4] = Int((newHueValue & 0xFF00) >> 8) // callcuated from rgb
        bArr[5] = newSatValue // satruation 0x00 ~ 0x64
        bArr[6] = newBrrValue // brightness

        brrValue.value = newBrrValue
        hueValue.value = newHueValue
        satValue.value = newSatValue

        let bArr1: [UInt8] = appendCheckSum(bArr)

        return NSData(bytes: bArr1, length: bArr1.count) as Data
    }

    private func getSceneValue(_ scene: UInt8, brightness brr: CGFloat) -> Data {

        // 78 88 02 (br) 01 - sets the brightness to (br), and shows "emergency mode A" (the "police sirens")
        // 78 88 02 (br) 02 - " ", and shoes "emergency mode B", but just stays one color?
        // 78 88 02 (br) 03 - " ", and shows "emergency mode C", which is... ambulance? I'm not sure
        // 78 88 02 (br) 04 - " ", and shows "party mode A", alternating colors
        // 78 88 02 (br) 05 - " ", and shows "party mode B", same as A, but faster
        // 78 88 02 (br) 06 - " ", and shows "party mode C", fading in and out (candle-light?)
        // 78 88 02 (br) 07 - " ", and shows "lightning mode A"
        // 78 88 02 (br) 08 - " ", and shows "lightning mode B"
        // 78 88 02 (br) 09 - " ", and shows "lightning mode C"

        // brr range from 0x00 - 0x64
        let newBrrValue: Int = Int(brr).clamped(to: 0...100)
        brrValue.value = newBrrValue

        // scene from 1 ~ 9
        channel.value = scene.clamped(to: 1...maxChannel)

        let byteCount = 2
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)

        bArr[0] = NeewerLightConstant.BleCommand.prefixTag
        bArr[1] = NeewerLightConstant.BleCommand.setSceneTag
        bArr[2] = byteCount
        // 2 eletements
        bArr[3] = Int(brr)   // brightness value from 0-100
        bArr[4] = Int(scene)

        let bArr1: [UInt8] = appendCheckSum(bArr)

        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    func getSceneCommand(_ mac: String, _ fxx: NeewerLightFX) -> Data {

        /*
         Oct 25 01:41:40.143  ATT Send         0x004A  00:00:00:00:00:00  Write Command - Handle:0x000E - Value: 7891 0BDF 243A B446 5D8B 1107 0103 4F  SEND
         Oct 25 01:41:42.493  ATT Send         0x004A  00:00:00:00:00:00  Write Command - Handle:0x000E - Value: 7891 0BDF 243A B446 5D8B 1107 0101 4D  SEND

         CMD TAG   SIZE       MAC                     SCE_TAG  SCE_ID(01~0C)     (BRR 00~64)    (COLOR 00~02)      (Speed 00~0A)      (checksum)
         78   91   0B         (DF 24 3A B4 46 5D)     8B       11                 07             01                 03                 4F

         Name               ID
         Lighting           01             BRR   CTT   SPEED
         Paparazzi          02             BRR   CTT   GM       SPEED
         Defective bulb     03             BRR   CTT   GM       SPEED
         Explosion          04             BRR   CTT   GM       SPEED     Sparks(01~0A)
         Welding            05             BRR_low   BRR_high     CTT   GM       SPEED
         CCT flash          06             BRR   CTT   GM       SPEED
         HUE flash          07             BRR   HUE (2Bytes little Endian 0000~6801)   SAT (00~64)   SPEED
         CCT pulse          08             BRR   CCT   GM       SPEED
         HUE pulse          09             BRR   HUE (2Bytes little Endian 0000~6801)   SAT (00~64)   SPEED
         Cop Car            0A             BRR   RED_AND_BLUE(00~05 Red,Blue, Red and Blue, White and Blue, Red blue  white) SPEED
         Candlelight        0B             BRR_low   BRR_high   CTT     GM       SPEED     Sparks
         HUE Loop           0C             BRR   HUE_low  HUE_high      SPEED
         CCT Loop           0D             BRR   CCT_low  CCT_high      SPEED
         INT loop           0E             BRR_low   BRR_high   HUE     SPEED
         TV Screen          0F             BRR   CCT   GM       SPEED
         Firework           10             BRR   COLOR(00 Single color, 01 Color, 02 Combined)   SPEED   Sparks
         Party              11             BRR   COLOR(00 Single color, 01 Color, 02 Combined)   SPEED
         */
        // scene from 1 ~ 9
        channel.value = UInt8(fxx.id).clamped(to: 1...maxChannel)

        var byteCount = 8
        if fxx.needBRR {
            byteCount += 1
        }
        if fxx.needBRRUpperBound {
            byteCount += 1
        }
        if fxx.needHUE {
            byteCount += 2
        }
        if fxx.needHUEUpperBound {
            byteCount += 2
        }
        if fxx.needSAT {
            byteCount += 1
        }
        if fxx.needCCT {
            byteCount += 1
        }
        if fxx.needCCTUpperBound {
            byteCount += 1
        }
        if fxx.needGM {
            byteCount += 1
        }
        if fxx.needColor && fxx.colors.count > 0 {
            byteCount += 1
        }
        if fxx.needSpeed {
            byteCount += 1
        }
        if fxx.needSparks && fxx.sparkLevel.count > 0 {
            byteCount += 1
        }
        var bArr: [Int] = [Int](repeating: 0, count: byteCount + 4)
        bArr[0] = NeewerLightConstant.BleCommand.prefixTag      // 78
        bArr[1] = NeewerLightConstant.BleCommand.setSCEDataTag  // 91
        bArr[2] = byteCount
        var intArray = mac.split(separator: ":").compactMap { Int($0, radix: 16) }
        while intArray.count < 6 {
            intArray.append(0)
        }
        bArr[3] = intArray[0]
        bArr[4] = intArray[1]
        bArr[5] = intArray[2]
        bArr[6] = intArray[3]
        bArr[7] = intArray[4]
        bArr[8] = intArray[5]
        bArr[9] = NeewerLightConstant.BleCommand.setSCESubTag
        bArr[10] = Int(channel.value)
        var idx = 11
        if fxx.needBRR {
            let newBrrValue: Int = Int(fxx.brrValue).clamped(to: 0...100)
            bArr[idx] = newBrrValue
            idx += 1
        }
        if fxx.needBRRUpperBound {
            let newBrrValue: Int = Int(fxx.brrUpperValue).clamped(to: 0...100)
            bArr[idx] = newBrrValue
            idx += 1
        }
        if fxx.needHUE {
            let newHueValue = Int(fxx.hueValue).clamped(to: 0...360)
            bArr[idx] = Int(newHueValue & 0xFF)
            idx += 1
            bArr[idx] = Int((newHueValue & 0xFF00) >> 8) // callcuated from rgb
            idx += 1
        }
        if fxx.needHUEUpperBound {
            let newHueValue = Int(fxx.hueUpperValue).clamped(to: 0...360)
            bArr[idx] = Int(newHueValue & 0xFF)
            idx += 1
            bArr[idx] = Int((newHueValue & 0xFF00) >> 8) // callcuated from rgb
            idx += 1
        }
        if fxx.needSAT {
            let newSatValue: Int = Int(fxx.satValue).clamped(to: 0...100)
            bArr[idx] = newSatValue
            idx += 1
        }
        if fxx.needCCT {
            let cctrange = CCTRange()
            let newCctValue: Int = Int(fxx.cctValue).clamped(to: cctrange.minCCT...cctrange.maxCCT)
            bArr[idx] = newCctValue
            idx += 1
        }
        if fxx.needCCTUpperBound {
            let cctrange = CCTRange()
            let newCctValue: Int = Int(fxx.cctUpperValue).clamped(to: cctrange.minCCT...cctrange.maxCCT)
            bArr[idx] = newCctValue
            idx += 1
        }
        if fxx.needGM {
            let newValue: Int = Int(fxx.gmValue).clamped(to: -50...50) + 50
            bArr[idx] = newValue
            idx += 1
        }
        if fxx.needColor && fxx.colors.count > 0 {
            let newValue: Int = Int(fxx.colorValue).clamped(to: 0...fxx.colors.count)
            bArr[idx] = newValue
            idx += 1
        }
        if fxx.needSpeed {
            let newValue: Int = Int(fxx.speedValue).clamped(to: 1...10)
            bArr[idx] = newValue
            idx += 1
        }
        if fxx.needSparks && fxx.sparkLevel.count > 0 {
            let newValue: Int = Int(fxx.sparksValue).clamped(to: 1...fxx.sparkLevel.count)
            bArr[idx] = newValue
            idx += 1
        }

        let bArr1: [UInt8] = appendCheckSum(bArr)

        // Nov 06 23:52:46.851  ATT Send         0x005B  00:00:00:00:00:00  Write Command - Handle:0x000E - Value: 7891 0BDF 243A B446 5D8B 0132 3706 A3  SEND
        let data = NSData(bytes: bArr1, length: bArr1.count)
        return data as Data
    }

    private func write(data value: Data, to characteristic: CBCharacteristic) {
        guard let peripheral = self.peripheral else {
            return
        }
        if value.count > 1 {
            if peripheral.state != .connected {
                Logger.warn("peripheral is not connected, can not send command!")
                return
            }
            _writeDispatcher?.cancel()
            let currentWorkItem = DispatchWorkItem {
                Logger.debug("write data: \(value.hexEncodedString())")
                if characteristic.properties.contains(CBCharacteristicProperties.writeWithoutResponse) {
                    peripheral.writeValue(value, for: characteristic, type: .withoutResponse)
                } else if characteristic.properties.contains(CBCharacteristicProperties.write) {
                    peripheral.writeValue(value, for: characteristic, type: .withResponse)
                }
            }
            _writeDispatcher = currentWorkItem
            // Writing too fast to the device could lead to BLE jam, slow down the request with 15ms delay.
            DispatchQueue.main.asyncAfter(deadline: .now() + (15.0 / 1000.0), execute: currentWorkItem)
         }
    }

    private func discoverMAC(_ peripheral: CBPeripheral) {
        if (_macAddress == nil || _macAddress == "") && macCheckCount > 0 {
            macCheckCount -= 1
            let name = peripheral.name
            if let devices = getConnectedBluetoothDevices() {
                for dev in devices {
                    if let devName = dev["name"], let deviceAddress = dev["device_address"] {
                        if devName == name {
                            Logger.debug("Found Device: \(devName) MAC: \(deviceAddress)")
                            _macAddress = deviceAddress
                            _projectName = nil
                            _nickName = nil
                            if let safeMac = _macAddress {
                                if (safeMac.lengthOfBytes(using: .utf8)) > 8 && _lightType == 22 {
                                    supportGMRange.value = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

extension NeewerLight: CBPeripheralDelegate {

    func peripheralDidUpdateRSSI(_ peripheral: CBPeripheral, error: Error?) {
        if let err = error {
            Logger.error("peripheralDidUpdateRSSI err: \(err)")
            return
        }
        Logger.debug("peripheralDidUpdateRSSI")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        // Logger.debug("didUpdateValueFor characteristic: \(characteristic)")
        if let err = error {
            Logger.error("peripheral didUpdateValueFor err: \(err)")
            return
        }
        if let data: Data = characteristic.value as Data? {
            handleNotifyValueUpdate(data)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        // self.writeGroup.leave()
        if let err = error {
            Logger.error("peripheral didWriteValueFor err: \(err)")
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            Logger.error("peripheral didUpdateNotificationStateFor err: \(err)")
            return
        }
        Logger.debug("didUpdateNotificationStateFor characteristic: \(characteristic)")
        let properties: CBCharacteristicProperties = characteristic.properties
        Logger.debug("properties: \(properties)")
        Logger.debug("properties.rawValue: \(properties.rawValue)")
        // self.write(data: cmd_check_power as Data, to: characteristic)
        sendReadRequest()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error {
            Logger.error("peripheral didDiscoverDescriptorsFor err: \(err)")
            return
        }

        Logger.debug("didDiscoverDescriptorsFor characteristic: \(characteristic)")
        guard let descriptors = characteristic.descriptors else {
            return
        }

        let characteristicConfigurationDescriptor = descriptors.first { (des) -> Bool in
            return des.uuid == CBUUID(string: CBUUIDClientCharacteristicConfigurationString)
        }

        if let characteristic = characteristicConfigurationDescriptor {
            peripheral.readValue(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor descriptor: CBDescriptor, error: Error?) {
        Logger.debug("didUpdateValueFor descriptor: \(descriptor)")
        if let err = error {
            Logger.error("peripheral didUpdateValueFor err: \(err)")
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: Error?) {
        Logger.debug("didWriteValueFor descriptor: \(descriptor)")
        if let err = error {
            Logger.error("peripheral didWriteValueFor err: \(err)")
            return
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        discoverMAC(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didOpen channel: CBL2CAPChannel?, error: Error?) {
        Logger.debug("peripheral didOpen channel: \(channel!)")
        if let err = error {
            Logger.error("peripheral didOpen err: \(err)")
            return
        }
    }
}
