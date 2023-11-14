//
//  AppDelegate.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa
import CoreBluetooth
import IOBluetooth
import Dispatch
import Accelerate
import SwiftUI
import Sparkle

#if DEBUG
let debugFakeLights = false
#else
let debugFakeLights = false
#endif

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var appMenu: NSMenu!
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var audioSpectrogramView: AudioSpectrogramView!
    @IBOutlet weak var mylightTableView: NSTableView!
    @IBOutlet weak var scanTableView: NSTableView!
    @IBOutlet weak var scanningStatus: NSTextField!
    @IBOutlet weak var viewsButton: NSSegmentedControl!
    @IBOutlet weak var audioDriveSwitch: NSSwitch!
    @IBOutlet weak var gainValueField: NSTextField!
    @IBOutlet weak var screenImageView: NSImageView!

    @IBOutlet var view0: NSView!
    @IBOutlet var view1: NSView!
    @IBOutlet var view2: NSView!
    @IBOutlet var view3: NSView!
    var audioSpectrogramViewVisible: Bool = false

    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var audioSpectrogram: AudioSpectrogram?
    private var spectrogramViewObject  = SpectrogramViewObject()
    private let commandHandler = CommandHandler()
    private var renameVC: RenameViewController?

    var cbCentralManager: CBCentralManager?
    /*
     when discovery a new device, it will store in the peripheralCache temporarily,
     then connect to the new device, if connection is established. then move from peripheralCache
     to viewObjects
     */
    var peripheralCache: [UUID: CBPeripheral] = [:]
    var peripheralInvalidCache: [UUID: Bool] = [:]
    var viewObjects: [DeviceViewObject] = []
    var scanningViewObjects: [DeviceViewObject] = []
    var scanning: Bool = false
    var scanningNewLightMode: Bool = false {
        didSet {
            if scanningNewLightMode {
                scanningTimer?.invalidate()
                scanningStatus?.stringValue = "Scan New Lights."
                scanningTimer = Timer.scheduledTimer(timeInterval: 0.5,
                                                     target: self,
                                                     selector: #selector(scanningTimerFired),
                                                     userInfo: nil,
                                                     repeats: true)
            } else {
                scanningTimer?.invalidate()
                scanningStatus?.stringValue = ""
            }
        }
    }
    var scanningTimer: Timer?
    var launching: Bool = true

    var statusItemIcon: ButtonState = .off {
        didSet {
            if let button = statusItem.button {
                switch statusItemIcon {
                    case .on:
                        button.image = NSImage(systemSymbolName: "light.panel.fill", accessibilityDescription: nil)
                    case .off:
                        button.image = NSImage(systemSymbolName: "light.panel", accessibilityDescription: nil)
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        Logger.initializeTimer()

        NSApp.setActivationPolicy(.regular)
        // NSApp.setActivationPolicy(.accessory)

        Logger.info(LogTag.app, "App launch")

        scanningStatus?.stringValue = ""
        let idx = UserDefaults.standard.value(forKey: "viewIdx") as? Int
        self.viewsButton.selectSegment(withTag: idx ?? 0)

        appMenu.delegate = self
        self.statusItem.menu = appMenu
        self.statusItemIcon = .off
        window.minSize = NSSize(width: 580, height: 400)

        registerCommands()

        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))

        collectionView.dataSource = self
        collectionView.delegate = self

        audioSpectrogramView.mirror = true
        audioSpectrogramView.clearFrequency()

        loadLightsFromDisk()

        self.updateUI()

        cbCentralManager = CBCentralManager(delegate: self, queue: nil)

        keepLightConnectionAlive()

        cbCentralManager = CBCentralManager(delegate: self, queue: nil)

        self.switchViewAction(self.viewsButton)

        launching = false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            // If there are no visible windows, bring your windows back to the front
            showWindowAction(self)
        }
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        saveLightsToDisk()
        Logger.info(LogTag.app, "App Quit")
        Logger.flush {
            // Inform the application that it can now terminate
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Bring the application's windows to the front
        showWindowAction(self)
    }

    func loadLightsFromDisk() {

        if debugFakeLights {
            let cfgs = NeewerLightConstant.getFakeLightConfigs()
            for cfg in cfgs {
                let dev = NeewerLight(cfg)
                viewObjects.append(DeviceViewObject(dev))
            }
            return
        }

        let storageManager = StorageManager()
        if let loadedData = storageManager?.load(from: "MyLights.dat") {
            Logger.debug("Loaded data: \(loadedData)")
            let dencoder = JSONDecoder()
            do {
                let jsonData = try dencoder.decode([[String: CodableValue]].self, from: loadedData)
                for cfg in jsonData {
                    Logger.debug("\(cfg)")
                    let dev = NeewerLight(cfg)
                    viewObjects.append(DeviceViewObject(dev))
                }
            } catch {
                Logger.error("Load Lights Error encoding JSON: \(error)")
            }
        }
    }

    func saveLightsToDisk() {
        if debugFakeLights {
            return
        }
        Logger.debug("saveLightsToDisk")
        let encoder = JSONEncoder()
        do {
            var lights: [[String: CodableValue]] = []
            for viewObject in viewObjects {
                lights.append(viewObject.device.getConfig())
            }
            let jsonData = try encoder.encode(lights)
            let storageManager = StorageManager()
            _ = storageManager?.save(data: jsonData, to: "MyLights.dat")
        } catch {
            Logger.error("Save Lights Error encoding JSON: \(error)")
        }
    }

    func keepLightConnectionAlive() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            for viewObject in self.viewObjects {
                viewObject.device.sendKeepAlive(self.cbCentralManager)
                if viewObject.device.connectionBreakCounter > 2 {
                    viewObject.view?.grayOut()
                }
            }
        }
    }

    func registerCommands() {
        commandHandler.register(command: Command(type: .scanLight, action: { _ in
            self.scanAction(self)
        }))

        commandHandler.register(command: Command(type: .turnOnLight, action: { cmdParameter in
            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName.value) == .orderedSame {
                        $0.turnOnLight()
                    }
                }
            } else {
                self.viewObjects.forEach { $0.turnOnLight() }
            }
            self.statusItemIcon = .on
        }))

        commandHandler.register(command: Command(type: .turnOffLight, action: { cmdParameter in
            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName.value) == .orderedSame {
                        $0.turnOffLight()
                    }
                }
            } else {
                self.viewObjects.forEach { $0.turnOffLight() }
            }
            self.statusItemIcon = .on
        }))

        commandHandler.register(command: Command(type: .toggleLight, action: { cmdParameter in
            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName.value) == .orderedSame {
                        $0.toggleLight()
                    }
                }
            } else {
                self.viewObjects.forEach { $0.toggleLight() }
            }
            self.statusItemIcon = .off
        }))

        commandHandler.register(command: Command(type: .setLightCCT, action: { cmdParameter in
            let cct = cmdParameter.CCT()
            let bri = cmdParameter.brightness() * 100
            func act(_ viewObj: DeviceViewObject) {
                if viewObj.isON {
                    viewObj.changeToCCTMode()
                    viewObj.updateCCT(cct, bri)
                }
            }

            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName.value) == .orderedSame { act($0) }
                }
            } else {
                self.viewObjects.forEach { act($0) }
            }
            self.statusItemIcon = .on
        }))

        commandHandler.register(command: Command(type: .setLightHSI, action: { cmdParameter in
            guard let color = cmdParameter.RGB() else {
                return
            }
            let sat = cmdParameter.saturation()
            let bri = cmdParameter.brightness()
            func act(_ viewObj: DeviceViewObject) {
                if viewObj.isON && viewObj.device.supportRGB {
                    viewObj.changeToHSIMode()
                    viewObj.updateHSI(hue: CGFloat(color.hueComponent), sat: sat, brr: CGFloat(bri))
                }
            }

            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName.value) == .orderedSame { act($0) }
                }
            } else {
                self.viewObjects.forEach { act($0) }
            }
            self.statusItemIcon = .on
        }))

        commandHandler.register(command: Command(type: .setLightScene, action: { cmdParameter in
            let scene = cmdParameter.scene()

            func act(_ viewObj: DeviceViewObject) {
                if viewObj.isON && viewObj.device.supportRGB {
                    viewObj.changeToSCE(scene)
                    viewObj.changeToSCEMode()
                }
            }

            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName.value) == .orderedSame { act($0) }
                }
            } else {
                self.viewObjects.forEach { act($0) }
            }
            self.statusItemIcon = .on
        }))
    }

    private func driveLightFromFrequency(_ frequency: [Float]) {
        let time = CFAbsoluteTimeGetCurrent()
        if time - self.spectrogramViewObject.lastTime > 0.5 {
            self.spectrogramViewObject.updateFrequency(frequencyData: frequency)
            let hue = self.spectrogramViewObject.hue
            let brr = self.spectrogramViewObject.brr
            let sat = self.spectrogramViewObject.sat
            self.viewObjects.forEach {
                if $0.followMusic && $0.isON && $0.isHSIMode {
                    $0.updateHSI(hue: CGFloat(hue), sat: CGFloat(sat), brr: CGFloat(brr))
                }
            }
        }
    }

    func checkAudioDriver() {
        audioDriveSwitch?.state = self.viewObjects.contains(where: { $0.followMusic }) ? .on : .off
        toggleAudioDriver(audioDriveSwitch!)
    }

    @IBAction func toggleScreenDriver(_ sender: NSSwitch) {
        if sender.state == .on {

        } else {

        }
    }

    @IBAction func changeGainAction(_ sender: NSSlider) {
        if let safe = audioSpectrogram {
            safe.zeroReference = sender.doubleValue
        }
        gainValueField.stringValue = "\(sender.doubleValue)"
    }

    @IBAction func toggleAudioDriver(_ sender: NSSwitch) {
        if sender.state == .on {
            Logger.debug("Autio Driver ON")
            if audioSpectrogram == nil {
                Logger.debug("startAudioDriver")
                audioSpectrogram = AudioSpectrogram()
                audioSpectrogram!.audioSpectrogramImageUpdateCallback = { [weak self] cgimg in
                    guard let safeSelf = self else { return }
                    if safeSelf.audioSpectrogramViewVisible {
                        DispatchQueue.main.async {
                            safeSelf.audioSpectrogramView?.updateFrequencyImage(img: cgimg)
                        }
                    }
                }
                audioSpectrogram!.frequencyUpdateCallback = { [weak self] frequencyData in
                    guard let safeSelf = self else { return }
                    if safeSelf.audioSpectrogramViewVisible {
                        DispatchQueue.main.async {
                            safeSelf.audioSpectrogramView?.updateFrequency(frequencyData: frequencyData.map { CGFloat($0) })
                        }
                    }
                    safeSelf.driveLightFromFrequency(frequencyData)
                }
                audioSpectrogram!.volumeUpdateCallback = { [weak self] volume in
                    guard let safeSelf = self else { return }
                    safeSelf.audioSpectrogramView?.volume = CGFloat(volume)
                }
                audioSpectrogram!.amplitudeUpdateCallback = { [weak self] amp in
                    guard let safeSelf = self else { return }
                    safeSelf.spectrogramViewObject.updateAmplitude(amplitude: amp)
                }
                audioSpectrogram!.startRunning()
            }
        } else {
            Logger.debug("Autio Driver OFF")
            if audioSpectrogram != nil {
                Logger.debug("stopAudioDriver")
                audioSpectrogram!.stopRunning()
                audioSpectrogram!.frequencyUpdateCallback = nil
                audioSpectrogram = nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                // Your code here will be executed on the main thread after a 3-second delay.
                self.audioSpectrogramView.clearFrequency()
            }
        }
    }

    @IBAction func aboutAction(_ sender: AnyObject) {
        showWindowAction(sender)
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © \(Calendar.current.component(.year, from: Date())) Keefo"
        ])
        Logger.info(LogTag.click, "open about")
    }

    @IBAction func githubAction(_ sender: AnyObject) {
        guard let url = URL(string: "https://github.com/keefo/NeewerLite") else {
            return
        }
        NSWorkspace.shared.open(url)
        Logger.info(LogTag.click, "open github")
    }

    @IBAction func showWindowAction(_ sender: AnyObject) {
        NSApp.activate(ignoringOtherApps: true)
        self.window.makeKeyAndOrderFront(nil)
        self.window.orderFrontRegardless()
    }

    @IBAction func switchViewAction(_ sender: NSSegmentedControl) {
        guard let contentView = self.window.contentView else {
            return
        }
        for subview in contentView.subviews {
            subview.removeFromSuperview()
        }
        let views = [self.view0, self.view1, self.view2, self.view3]
        if sender.selectedSegment >= 0 && sender.selectedSegment < views.count {

            UserDefaults.standard.setValue(sender.selectedSegment, forKey: "viewIdx")

            if let selectedView = views[sender.selectedSegment] {
                self.audioSpectrogramViewVisible = false
                if selectedView == self.view0 {
                    window.title = "NeewerLite - Scan View"
                    if !launching {
                        Logger.info(LogTag.click, "Scan View")
                    }
                } else if selectedView == self.view1 {
                    window.title = "NeewerLite - Control View"
                    if !launching {
                        Logger.info(LogTag.click, "Control View")
                    }
                } else if selectedView == self.view2 {
                    window.title = "NeewerLite - Music View"
                    if !launching {
                        Logger.info(LogTag.click, "Music View")
                    }
                } else if selectedView == self.view3 {
                    window.title = "NeewerLite - Screen View"
                    if !launching {
                        Logger.info(LogTag.click, "Screen View")
                    }
                }
                selectedView.frame = contentView.bounds
                selectedView.autoresizingMask = [.width, .height]
                contentView.addSubview(selectedView)
                updateUI()
                if selectedView == self.view2 {
                    self.audioSpectrogramViewVisible = true
                    audioSpectrogramView.clearFrequency()
                }
            }
        }
    }

    @IBAction func forceScanAction(_ sender: NSButton) {
        if sender.title == "Scan" {
            scanning = false
            scanningNewLightMode = true
            scanningViewObjects.removeAll()
            scanTableView.reloadData()
            scanAction(sender)
            sender.title = "Stop"
            Logger.info(LogTag.click, "Scan")
        } else {
            scanningNewLightMode = false
            scanningStatus?.stringValue = ""
            sender.title = "Scan"
            Logger.info(LogTag.click, "Stop")
        }
    }

    @IBAction func scanAction(_ sender: AnyObject) {
        if scanning {
            // stop scanning
            cbCentralManager?.stopScan()
            scanning = false
        } else {
            // start scanning
            cbCentralManager?.scanForPeripherals(withServices: nil, options: nil)
            // scanAction(self)
            scanning = true
            Logger.debug("scanForPeripherals...")
        }

        Logger.debug("\(peripheralCache)")
        peripheralCache.removeAll()
        Logger.debug("\(peripheralCache)")

        let list = cbCentralManager?.retrieveConnectedPeripherals(withServices: [NeewerLightConstant.Constants.NeewerBleServiceUUID])
        if let safeList = list {
            for peripheral in safeList {
                if let services = peripheral.services {
                    guard let neewerService: CBService = services.first(where: {$0.uuid == NeewerLightConstant.Constants.NeewerBleServiceUUID}) else {
                        continue
                    }
                    advancePeripheralToDevice(peripheral: peripheral, service: neewerService, updateUI: false, addNew: scanningNewLightMode)
                }
            }
        }

        self.statusItemIcon = .off
        updateUI()
        cbCentralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
    }

    @objc func scanningTimerFired() {
        struct Holder {
            static var dotNumber: Int = 0
        }
        Holder.dotNumber += 1
        if Holder.dotNumber == 7 {
            Holder.dotNumber = 0
        }
        let dots = String(repeating: ".", count: Holder.dotNumber)
        scanningStatus?.stringValue = "Scan New Lights\(dots)"
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor?, withReplyEvent: NSAppleEventDescriptor?) {
        guard let url = event?.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            return
        }
        guard let theUrl = URL(string: url) else {
            return
        }
        let components = URLComponents(url: theUrl, resolvingAgainstBaseURL: false)!
        if components.scheme?.lowercased() != "neewerlite" {
            return
        }
        let cmd = components.host ?? ""
        commandHandler.execute(commandName: cmd, components: components)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let lightTag = 8
        let optKeyPressed = NSEvent.modifierFlags.contains(.option)

        appMenu.items = appMenu.items.filter { $0.tag != lightTag }

        viewObjects.reversed().forEach {
            let name = optKeyPressed ? "\($0.device.userLightName.value) - \($0.device.identifier) - \($0.device.rawName)" : "\($0.device.userLightName.value)"
            let item =  NSMenuItem(title: name, action: #selector(self.showWindowAction(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: $0.isON ? "lightbulb" : "lightbulb.slash", accessibilityDescription: "Light")
            item.tag = lightTag
            appMenu.insertItem(item, at: 2)
        }
    }

    public func updateUI() {
        statusItem.button?.alignment = .center
        statusItem.button?.imagePosition = .imageOverlaps

        // make view items order stable
        viewObjects.sort { $0.deviceIdentifier > $1.deviceIdentifier }
        collectionView.reloadData()

        let deviceIdentifiers: [String] = mylightTableView.selectedRowIndexes.compactMap { rowIndex in
            guard rowIndex >= 0 && rowIndex < viewObjects.count else {
                return nil // Ignore this index as it's out of the bounds of the array
            }
            return viewObjects[rowIndex].deviceIdentifier
        }

        mylightTableView.reloadData()
        var newIndexSet = IndexSet()
        for (index, item) in viewObjects.enumerated() {
            if deviceIdentifiers.contains(item.deviceIdentifier) {
                newIndexSet.insert(index)
            }
        }
        mylightTableView.selectRowIndexes(newIndexSet, byExtendingSelection: false)
        mylightTableView.enclosingScrollView?.display()
        mylightTableView.display()

        scanTableView.reloadData()
    }

    func forgetLight(_ light: NeewerLight) {
        Logger.info(LogTag.click, "do forget light \(light.getConfig(true))")
        var found = false
        for (index, viewObj) in viewObjects.enumerated() where viewObj.device.identifier == light.identifier {
            viewObjects.remove(at: index)
            found = true
            break
        }
        if found {
            saveLightsToDisk()
            self.updateUI()
        }
    }

    func advancePeripheralToDevice(peripheral: CBPeripheral, service: CBService, updateUI: Bool, addNew: Bool) {
        if let characteristics = service.characteristics {
            guard let characteristic1: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLightConstant.Constants.NeewerDeviceCtlCharacteristicUUID}) else {
                Logger.debug("NeewerGattCharacteristicUUID not found")
                return
            }

            guard let characteristic2: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLightConstant.Constants.NeewerGattCharacteristicUUID}) else {
                Logger.debug("NeewerGattCharacteristicUUID not found")
                return
            }

            let identifier = "\(peripheral.identifier)"

            var update = updateUI
            // Logger.info("advance peripheral to device \(peripheral) \(service)")
            var found = false
            if let targetViewObject = viewObjects.first(where: { $0.deviceIdentifier == identifier  }) {
                found = true
                if targetViewObject.device.peripheral == nil {
                    targetViewObject.device.setPeripheral(peripheral, characteristic1, characteristic2)
                }
                targetViewObject.device.startLightOnNotify()
            }

            if !found {
                if addNew {
                    if let voj = scanningViewObjects.first(where: {$0.deviceIdentifier == identifier}) {
                        Logger.debug("already added")
                    } else {
                        let light: NeewerLight = NeewerLight(peripheral, characteristic1, characteristic2)
                        scanningViewObjects.append(DeviceViewObject(light))
                        light.startLightOnNotify()
                        update = true
                    }
                }
            }

            // after moved to the devices data store, remove from cache
            if peripheralCache[peripheral.identifier] != nil {
                peripheralCache.removeValue(forKey: peripheral.identifier)
            }

            if update {
                DispatchQueue.main.async {
                    self.updateUI()
                }
            }
        }
    }

    func grayoutLightViewObject(_ identifier: UUID) {
        if let targetViewObject = viewObjects.first(where: { $0.deviceIdentifier == "\(identifier)"  }) {
            Logger.info("grayoutLightViewObject \(identifier)")
            targetViewObject.device.setPeripheral(nil, nil, nil)
            DispatchQueue.main.async {
                self.updateUI()
            }
        }
    }

}

extension AppDelegate: NSCollectionViewDataSource {

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewObjects.count
    }

    func collectionView(_ itemForRepresentedObjectAtcollectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {

        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CollectionViewItem"), for: indexPath)

        if let collectionViewItem = item as? CollectionViewItem {
            let viewObject = viewObjects[indexPath.section + indexPath.item]
            viewObject.view = collectionViewItem
            collectionViewItem.updateWithViewObject(viewObject)
        }

        return item
    }
}

extension AppDelegate: NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        return NSSize(width: 480, height: 280)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, insetForSectionAt section: Int) -> NSEdgeInsets {
        return NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return 10.0
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return 10.0
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize {
        return NSSize(width: 0, height: 0)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForFooterInSection section: Int) -> NSSize {
        return NSSize(width: 0, height: 0)
    }
}

extension AppDelegate: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {
            case .unauthorized:
                Logger.info(LogTag.bluetooth, "authorization: \(central.authorization)")
                switch central.authorization {
                    case .allowedAlways: break
                    case .denied: break
                    case .restricted: break
                    case .notDetermined: break
                    @unknown default:
                        break
                }
            case .unknown: break
            case .unsupported: break
            case .poweredOn:
                Logger.info(LogTag.bluetooth, "powered on")
                central.scanForPeripherals(withServices: nil, options: nil)
                // scanAction(self)
                self.scanning = true
            case .poweredOff:
                central.stopScan()
                Logger.info(LogTag.bluetooth, "powered off")
                self.scanning = false
            case .resetting:
                Logger.info(LogTag.bluetooth, "resetting")
            @unknown default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name else {return}
        if peripheralInvalidCache[peripheral.identifier] != nil {
            return
        }
        if !scanningNewLightMode {
            if NeewerLightConstant.isValidPeripheralName(name) == false {
                peripheralInvalidCache[peripheral.identifier] = true
                return
            }
        }
        if peripheralCache[peripheral.identifier] != nil {
            return
        }
        peripheral.delegate = self
        peripheralCache[peripheral.identifier] = peripheral
        cbCentralManager?.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        // discover all service
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Logger.info(LogTag.bluetooth, "didFailToConnect peripheral \(peripheral) error \(String(describing: error))")
        if peripheralCache[peripheral.identifier] != nil {
            peripheral.delegate = nil
            peripheralCache.removeValue(forKey: peripheral.identifier)
        }
        grayoutLightViewObject(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Logger.info(LogTag.bluetooth, "didDisconnectPeripheral peripheral \(peripheral) error \(String(describing: error))")
        if peripheralCache[peripheral.identifier] != nil {
            peripheral.delegate = nil
            peripheralCache.removeValue(forKey: peripheral.identifier)
        }
        if viewObjects.contains(where: { $0.deviceIdentifier == "\(peripheral.identifier)" }) {
            Logger.debug("didDisconnectPeripheral: \(peripheral) \(String(describing: error))")
            Logger.debug("try to connect to \(peripheral.identifier)")
            cbCentralManager?.connect(peripheral, options: nil)
            // grayoutLightViewObject(peripheral.identifier)
        }
    }
}

extension AppDelegate: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // Logger.info("A peripheral: \(peripheral.name!) didModifyServices \(invalidatedServices)")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            guard let neewerService: CBService = services.first(where: {$0.uuid == NeewerLightConstant.Constants.NeewerBleServiceUUID}) else {
                cbCentralManager?.cancelPeripheralConnection(peripheral)
                peripheralInvalidCache[peripheral.identifier] = true
                if peripheralCache[peripheral.identifier] != nil {
                    peripheral.delegate = nil
                    peripheralCache.removeValue(forKey: peripheral.identifier)
                }
                return
            }
            Logger.info("A Valid Neewer Light Found: \(peripheral) \(services)")
            // discover characteristics of services
            peripheral.discoverCharacteristics(nil, for: neewerService)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        advancePeripheralToDevice(peripheral: peripheral, service: service, updateUI: true, addNew: scanningNewLightMode)
    }
}

extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        // Return the number of rows based on your data source count.
        if tableView == mylightTableView {
            return viewObjects.count
        } else if tableView == scanTableView {
            return scanningViewObjects.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // Example: Creating a simple NSTextField as a cell view
        if tableView == mylightTableView {
            let cellIdentifier = NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.0")

            if let cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? MyLightTableCellView {
                // Assuming "YourModel" has a property named "name" to display
                let viewObj = viewObjects[row]
                cellView.titleLabel?.stringValue = "\(viewObj.device.nickName) (\(viewObj.device.rawName))"
                cellView.subtitleLabel?.stringValue = viewObj.device.userLightName.value
                cellView.iconImageView?.image = ContentManager.shared.fetchCachedLightImage(lightType: viewObj.device.lightType) ?? NSImage(named: "defaultLightImage")
                cellView.button?.tag = row
                cellView.button?.action = #selector(forgetAction(_:))
                cellView.button?.target = self
                cellView.button2?.tag = row
                cellView.button2?.action = #selector(renameAction(_:))
                cellView.button2?.target = self
                if debugFakeLights {
                    cellView.isConnected = true
                } else {
                    cellView.isConnected = viewObj.deviceConnected
                }
                if !viewObj.hasMAC {
                    cellView.titleLabel?.stringValue = "\(viewObj.device.nickName) (missing MAC❗️)"
                }
                cellView.light = viewObj.device
                return cellView
            }
        } else if tableView == scanTableView {
            let cellIdentifier = NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.0")

            if let cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? MyLightTableCellView {
                // Assuming "YourModel" has a property named "name" to display
                let viewObj = scanningViewObjects[row]
                cellView.iconImageView?.image = ContentManager.shared.fetchCachedLightImage(lightType: viewObj.device.lightType) ?? NSImage(named: "defaultLightImage")
                cellView.titleLabel?.stringValue = viewObj.device.rawName
                cellView.subtitleLabel?.stringValue = viewObj.device.nickName
                cellView.button?.tag = row
                cellView.button?.action = #selector(connnectNewLightAction(_:))
                cellView.button?.target = self
                cellView.light = viewObj.device
                return cellView
            }
        }
        return nil
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return tableView == mylightTableView
    }

    @IBAction func connnectNewLightAction(_ sender: NSButton) {
        let rowIndex = sender.tag
        if rowIndex >= 0 && rowIndex < scanningViewObjects.count {
            let viewObj = scanningViewObjects.remove(at: rowIndex)
            Logger.info(LogTag.click, "connect a new light \(viewObj.device.getConfig())")
            viewObjects.append(viewObj)
            self.updateUI()
            self.saveLightsToDisk()
        }
    }

    func isUserLightNameUsed(_ text: String, dev: NeewerLight? ) -> Bool {
        for viewObj in self.viewObjects {
            if viewObj.device.identifier == dev?.identifier {
                continue
            }
            if viewObj.device.userLightName.value == text {
                return true
            }
        }
        return false
    }

    @IBAction func renameAction(_ sender: NSButton) {
        let rowIndex = sender.tag
        // Retrieve the corresponding object from your data source
        if rowIndex >= 0 && rowIndex < viewObjects.count {
            Logger.info(LogTag.click, "rename light")
            let viewObject = viewObjects[rowIndex]
            if renameVC != nil {
                renameVC = nil
            }
            renameVC = RenameViewController()
            renameVC?.onOK = { [weak self] text in
                guard let safeSelf = self else { return true }
                if safeSelf.isUserLightNameUsed(text, dev: viewObject.device) {
                    Logger.info(LogTag.click, "rename light, name conflict.")
                    return false
                }
                viewObject.device.userLightName.value = "\(text)"
                safeSelf.saveLightsToDisk()
                safeSelf.updateUI()
                return true
            }
            renameVC?.setCurrentValue(viewObject.device.userLightName.value)
            self.window?.beginSheet(renameVC!.sheetWindow, completionHandler: nil)
        }
    }

    @IBAction func forgetAction(_ sender: NSButton) {
        let rowIndex = sender.tag
        // Retrieve the corresponding object from your data source
        if rowIndex >= 0 && rowIndex < viewObjects.count {
            Logger.info(LogTag.click, "forget light")
            let viewObject = viewObjects[rowIndex]
            let alert = NSAlert()
            alert.icon = ContentManager.shared.fetchCachedLightImage(lightType: viewObject.device.lightType) ?? NSImage(named: "defaultLightImage")
            alert.messageText = "Remove light \"\(viewObject.deviceName)\""
            alert.informativeText = "Are you sure you want to remove this light from you library?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "No")
            alert.addButton(withTitle: "Yes")

            let response = alert.runModal()
            switch response {
                case .alertFirstButtonReturn:
                    Logger.info(LogTag.click, "forget light, cancel")
                case .alertSecondButtonReturn:
                    self.forgetLight(viewObject.device)
                default:
                    break
            }
        }
    }
}
