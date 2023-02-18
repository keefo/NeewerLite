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

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var appMenu: NSMenu!
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var audioSpectrogramView: AudioSpectrogramView!

    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var audioSpectrogram: AudioSpectrogram?
    private var spectrogramViewObject  = SpectrogramViewObject()
    private let commandHandler = CommandHandler()

    var cbCentralManager: CBCentralManager?
    /*
     when discovery a new device, it will save to peripheralCache
     then connect to the new device, if connection is established. then move from peripheralCache
     to viewObjects
     */
    var peripheralCache: [UUID: CBPeripheral] = [:]
    var peripheralIgnoreCache: [UUID: Bool] = [:]
    var viewObjects: [DeviceViewObject] = []
    var scanning: Bool = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appMenu.delegate = self
        self.statusItem.menu = appMenu
        if let button = statusItem.button {
            button.image = NSImage(named: "statusItemOffIcon")
        }

        registerCommands()

        NSAppleEventManager.shared().setEventHandler(self,
                                                     andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))

        self.collectionView.dataSource = self
        self.collectionView.delegate = self
        self.cbCentralManager = CBCentralManager(delegate: self, queue: nil)

        keepLightConnectionAlive()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Store all Lights values
        for viewObject in viewObjects {
            viewObject.device.saveToUserDefault()
            viewObject.clear()
        }
    }

    func keepLightConnectionAlive() {
        Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { _ in
            var removed: Int = 0
            for viewObject in self.viewObjects {
                viewObject.device.sendKeepAlive(self.cbCentralManager)
                if viewObject.device.offCounter > 2 {
                    removed += 1
                }
            }
            if removed > 0 {
                DispatchQueue.main.async {
                    self.viewObjects.removeAll { $0.device.offCounter > 2 }
                    self.updateUI()
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
                    if lightname.caseInsensitiveCompare($0.device.userLightName) == .orderedSame {
                        $0.turnOnLight()
                    }
                }
            } else {
                self.viewObjects.forEach { $0.turnOnLight() }
            }
            self.statusItem.button?.image = NSImage(named: "statusItemOnIcon")
        }))

        commandHandler.register(command: Command(type: .turnOffLight, action: { cmdParameter in
            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName) == .orderedSame {
                        $0.turnOffLight()
                    }
                }
            } else {
                self.viewObjects.forEach { $0.turnOffLight() }
            }
            self.statusItem.button?.image = NSImage(named: "statusItemOnIcon")
        }))

        commandHandler.register(command: Command(type: .toggleLight, action: { cmdParameter in
            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName) == .orderedSame {
                        $0.toggleLight()
                    }
                }
            } else {
                self.viewObjects.forEach { $0.toggleLight() }
            }
            self.statusItem.button?.image = NSImage(named: "statusItemOffIcon")
        }))

        commandHandler.register(command: Command(type: .setLightRGB, action: { cmdParameter in
            guard let color = cmdParameter.RGB() else {
                return
            }
            if let lightname = cmdParameter.lightName() {
                self.viewObjects.forEach {
                    if lightname.caseInsensitiveCompare($0.device.userLightName) == .orderedSame {
                        if $0.isON && $0.isHSIMode {
                            $0.HSB = HSB(hue: CGFloat(color.hueComponent), saturation: 1.0, brightness: CGFloat(1.0), alpha: 1)
                        }
                    }
                }
            } else {
                self.viewObjects.forEach {
                    if $0.isON && $0.isHSIMode {
                        $0.HSB = HSB(hue: CGFloat(color.hueComponent), saturation: 1.0, brightness: CGFloat(1.0), alpha: 1)
                    }
                }
            }
            self.statusItem.button?.image = NSImage(named: "statusItemOnIcon")
        }))
    }

    func updateAudioDriver() {
        if viewObjects.contains(where: { $0.isON && $0.followMusic }) {
             if audioSpectrogram == nil {
                Logger.debug("startAudioDriver")
                audioSpectrogram = AudioSpectrogram()
                audioSpectrogram!.delegate = self
                audioSpectrogram!.startRunning()
            }
        } else {
            if audioSpectrogram != nil {
                Logger.debug("stopAudioDriver")
                audioSpectrogram!.stopRunning()
                audioSpectrogram!.delegate = nil
                audioSpectrogram = nil
            }
            audioSpectrogramView.clearFrequency()
        }
    }

    @IBAction func aboutAction(_ sender: AnyObject) {
        showWindowAction(sender)
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © \(Calendar.current.component(.year, from: Date())) Keefo"
        ])
    }

    @IBAction func showWindowAction(_ sender: AnyObject) {
        self.window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
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
            Logger.info("scanForPeripherals...")
        }

        Logger.debug("\(peripheralCache)")
        Logger.debug("\(viewObjects)")
        viewObjects.forEach { $0.clear() }
        viewObjects.removeAll()
        peripheralCache.removeAll()
        Logger.debug("\(peripheralCache)")
        Logger.debug("\(viewObjects)")

        let list = cbCentralManager?.retrieveConnectedPeripherals(withServices: [NeewerLight.Constants.NeewerBleServiceUUID])
        if let safeList = list {
            for peripheral in safeList {
                if let services = peripheral.services {
                    guard let neewerService: CBService = services.first(where: {$0.uuid == NeewerLight.Constants.NeewerBleServiceUUID}) else {
                        continue
                    }
                    advancePeripheralToDevice(peripheral: peripheral, service: neewerService, updateUI: false)
                }
            }
        }
        statusItem.button?.image = NSImage(named: "statusItemOffIcon")
        updateUI()
        cbCentralManager?.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
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
            let name = optKeyPressed ? "\($0.device.userLightName) - \($0.device.identifier) - \($0.device.rawName)" : "\($0.device.userLightName)"
            let item =  NSMenuItem(title: name, action: #selector(self.showWindowAction(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: $0.isON ? "lightbulb" : "lightbulb.slash", accessibilityDescription: "Light")
            item.tag = lightTag
            appMenu.insertItem(item, at: 2)
        }
    }

    public func updateUI() {
        statusItem.button?.alignment = .center
        statusItem.button?.title = "\(viewObjects.count)"
        statusItem.button?.imagePosition = .imageOverlaps

        // make view items order stable
        viewObjects.sort { $0.deviceIdentifier > $1.deviceIdentifier }

        print("collectionView: \(String(describing: collectionView))")
        collectionView.reloadData()
    }

    func advancePeripheralToDevice(peripheral: CBPeripheral, service: CBService, updateUI: Bool) {
        if let characteristics = service.characteristics {
            guard let characteristic1: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.Constants.NeewerDeviceCtlCharacteristicUUID}) else {
                Logger.info("NeewerGattCharacteristicUUID not found")
                return
            }

            guard let characteristic2: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.Constants.NeewerGattCharacteristicUUID}) else {
                Logger.info("NeewerGattCharacteristicUUID not found")
                return
            }

            Logger.info("advance peripheral to device \(peripheral) \(service)")

            let light: NeewerLight = NeewerLight(peripheral, characteristic1, characteristic2)
            viewObjects.append(DeviceViewObject(light))
            light.startLightOnNotify()

            // after moved to the devices data store, remove from cache
            if peripheralCache[peripheral.identifier] != nil {
                peripheralCache.removeValue(forKey: peripheral.identifier)
            }

            if updateUI {
                DispatchQueue.main.async {
                    self.updateUI()
                }
            }
        }
    }
}

extension AppDelegate: AudioSpectrogramDelegate {
    func updateFrequency(frequency: [Float]) {
        if frequency[1].isInfinite {
            return
        }
        DispatchQueue.main.async {
            if let visible = self.audioSpectrogramView.window?.isVisible {
                if visible {
                    self.audioSpectrogramView.updateFrequency(frequency: frequency.map { CGFloat($0) })
                }
            }
            let time = CFAbsoluteTimeGetCurrent()
            if time - self.spectrogramViewObject.lastTime > 0.2 {
                self.spectrogramViewObject.update(time: time, frequency: frequency[1])
                // self.spectrogram_data.last_n_BRR.removeFirst()
                // self.spectrogram_data.last_n_BRR.append(frequency.reduce(0, +) / Float(frequency.count) * 3.0)
                let hue = self.spectrogramViewObject.hue
                let brr = 1.0
                Logger.debug("frequency: \(frequency[1])) hue: \(hue)")
                self.viewObjects.forEach { if $0.followMusic && $0.isON && $0.isHSIMode {
                    $0.HSB = HSB(hue: CGFloat(hue), saturation: 1.0, brightness: CGFloat(brr), alpha: 1)
                }}
                // self.spectrogram_data.hueBase += 0.001
                // Logger.debug("self.spectrogram_data.hueBase: \(self.spectrogram_data.hueBase)")
            }
        }
    }

    func removeLightViewObject(_ identifier: UUID) {
        if viewObjects.contains(where: { $0.deviceIdentifier == "\(identifier)" }) {
            Logger.error("removeLightViewObject \(identifier)")
            viewObjects.removeAll(where: { $0.deviceIdentifier == "\(identifier)" })
            // peripheral.delegate = nil
            // devices.removeValue(forKey: peripheral.identifier)
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
                Logger.info("scanForPeripherals...")
                central.scanForPeripherals(withServices: nil, options: nil)
                // scanAction(self)
                self.scanning = true
            case .poweredOff:
                central.stopScan()
                self.scanning = false
            case .resetting: break
            @unknown default: break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name else {return}
        if NeewerLight.isValidPeripheralName(name) == false {
            peripheralIgnoreCache[peripheral.identifier] = true
            return
        }
        if peripheralIgnoreCache[peripheral.identifier] != nil {
            return
        }
        if viewObjects.contains(where: { $0.deviceIdentifier == "\(peripheral.identifier)" }) {
            return
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
        if peripheralCache[peripheral.identifier] != nil {
            peripheral.delegate = nil
            peripheralCache.removeValue(forKey: peripheral.identifier)
        }
        removeLightViewObject(peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if peripheralCache[peripheral.identifier] != nil {
            peripheral.delegate = nil
            peripheralCache.removeValue(forKey: peripheral.identifier)
        }
        if viewObjects.contains(where: { $0.deviceIdentifier == "\(peripheral.identifier)" }) {
            Logger.info("didDisconnectPeripheral: \(peripheral) \(String(describing: error))")
            Logger.info("try to connect to \(peripheral.identifier)")
            cbCentralManager?.connect(peripheral, options: nil)
            // removeLightViewObject(peripheral.identifier)
        }
    }
}

extension AppDelegate: CBPeripheralDelegate {

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        // Logger.info("A peripheral: \(peripheral.name!) didModifyServices \(invalidatedServices)")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            guard let neewerService: CBService = services.first(where: {$0.uuid == NeewerLight.Constants.NeewerBleServiceUUID}) else {
                cbCentralManager?.cancelPeripheralConnection(peripheral)
                peripheralIgnoreCache[peripheral.identifier] = true
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

        advancePeripheralToDevice(peripheral: peripheral, service: service, updateUI: true)
    }
}
