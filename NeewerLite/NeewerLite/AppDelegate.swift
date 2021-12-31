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

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet var appMenu: NSMenu!
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var audioSpectrogramView: AudioSpectrogramView!
    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var audioSpectrogram: AudioSpectrogram? = nil

    struct spectrogram_data_t {
        var lastTime: CFAbsoluteTime = 0
        var last_n_HUE = [Float](repeating: 0, count: 3)
       //var last_n_BRR = [Float](repeating: 0, count: 8)
        var hueBase: Float = 0.0
    }

    private var spectrogram_data  = spectrogram_data_t()

    var cbCentralManager: CBCentralManager?
    var tempDevices: [UUID: CBPeripheral] = [:]
    var devices: [UUID: NeewerLight] = [:]
    var viewObjects: [DeviceViewObject] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        appMenu.delegate = self
        self.statusItem.menu = appMenu

        if let button = statusItem.button {
            button.image = NSImage(named: "statusItemOffIcon")
        }

        self.window.minSize = NSMakeSize(580, 400)
        updateUI()

        cbCentralManager = CBCentralManager(delegate: self, queue: nil)

        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        return true
    }

    func updateAudioDriver() {
        if viewObjects.contains(where: { $0.isON && $0.followMusic }) {
             if audioSpectrogram == nil {
                Logger.debug("startAudioDriver")
                audioSpectrogram = AudioSpectrogram()
                audioSpectrogram!.delegate = self
                audioSpectrogram!.startRunning()
            }
        }
        else{
            if audioSpectrogram != nil {
                Logger.debug("stopAudioDriver")
                audioSpectrogram!.stopRunning()
                audioSpectrogram!.delegate = nil
                audioSpectrogram = nil
            }
            audioSpectrogramView.clearFrequency()
        }
    }

    @IBAction func scanAction(_ sender: Any) {
        devices.removeAll()
        viewObjects.removeAll()
        statusItem.button?.image = NSImage(named: "statusItemOffIcon")
        updateUI()
        let list = cbCentralManager?.retrieveConnectedPeripherals(withServices: [NeewerLight.Constants.NeewerBleServiceUUID])
        if let safeList = list {
            for peripheral in safeList {
                if let services = peripheral.services {
                    guard let neewerService: CBService = services.first(where: {$0.uuid == NeewerLight.Constants.NeewerBleServiceUUID}) else {
                        continue
                    }

                    if let characteristics = neewerService.characteristics {

                        guard let characteristic1: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.Constants.NeewerDeviceCtlCharacteristicUUID}) else {
                            Logger.info("NeewerGattCharacteristicUUID not found")
                            return
                        }

                        guard let characteristic2: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.Constants.NeewerGattCharacteristicUUID}) else {
                            Logger.info("NeewerGattCharacteristicUUID not found")
                            return
                        }

                        let light: NeewerLight = NeewerLight(peripheral, characteristic1, characteristic2)
                        devices[peripheral.identifier] = light
                        light.startLightOnNotify()

                        tempDevices.removeValue(forKey: peripheral.identifier)

                        DispatchQueue.main.async {
                            self.updateUI()
                        }
                    }
                }
            }
        }
    }

    @IBAction func aboutAction(_ sender: Any) {
        showWindow(sender)
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © \(Calendar.current.component(.year, from: Date())) Keefo"
        ])
    }

    @IBAction func showWindow(_ sender: Any) {
        self.window.makeKeyAndOrderFront(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor?, withReplyEvent: NSAppleEventDescriptor?) {
        if let url = event?.paramDescriptor(forKeyword: keyDirectObject)?.stringValue {
            if let range = url.range(of: "neewerlite://") {
                let cmd = url[range.upperBound...]
                switch cmd {
                    case "turnOnLight":
                        viewObjects.forEach { $0.turnOnLight() }
                        statusItem.button?.image = NSImage(named: "statusItemOnIcon")
                    case "turnOffLight":
                        viewObjects.forEach { $0.turnOffLight() }
                        statusItem.button?.image = NSImage(named: "statusItemOffIcon")
                    case "toggleLight":
                        viewObjects.forEach { $0.toggleLight() }
                        statusItem.button?.image = NSImage(named: "statusItemOffIcon")
                    case "scanLight":
                        scanAction(cmd)
                    default:
                        Logger.info("unknown command: [\(cmd)]")
                }
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Store all Lights values
        for device in devices {
            device.value.saveToUserDefault()
        }
    }

    func menuWillOpen(_ menu: NSMenu)
    {
        Logger.debug("menuWillOpen \(menu)")
        let lightTag = 8
        let optKeyPressed = NSEvent.modifierFlags.contains(.option)

        appMenu.items = appMenu.items.filter { $0.tag != lightTag }

        viewObjects.reversed().forEach {
            let name = optKeyPressed ? "\($0.device.userLightName) - \($0.device.identifier) - \($0.device.rawName)" : "\($0.device.userLightName)"
            let item =  NSMenuItem(title: name, action: #selector(self.showWindow(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: $0.isON ? "lightbulb" : "lightbulb.slash", accessibilityDescription: "Light")
            item.tag = lightTag
            appMenu.insertItem(item, at: 2)
        }
    }

    public func updateUI() {
        viewObjects.removeAll()

        viewObjects.append(contentsOf: devices.sorted(by: { $0.0.uuidString < $1.0.uuidString }).map {
            return DeviceViewObject($0.value)
        })

        statusItem.button?.title = "\(viewObjects.count)"

        // make view items order stable
        viewObjects.sort {
            $0.deviceIdentifier > $1.deviceIdentifier
        }

        collectionView.reloadData()
    }
}

extension AppDelegate :  AudioSpectrogramDelegate {
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
            if time - self.spectrogram_data.lastTime > 0.2 {
                self.spectrogram_data.lastTime = time

                self.spectrogram_data.last_n_HUE.removeFirst()
                self.spectrogram_data.last_n_HUE.append(frequency[1])

                //self.spectrogram_data.last_n_BRR.removeFirst()
                //self.spectrogram_data.last_n_BRR.append(frequency.reduce(0, +) / Float(frequency.count) * 3.0)

                var hue = sqrt(vDSP.meanSquare(self.spectrogram_data.last_n_HUE)) * 2.0 / 128.0 + self.spectrogram_data.hueBase
                let brr = 1.0
                if hue > 1.0 {
                    hue = hue - 1.0
                }
                Logger.debug("hue: \(hue)")
                self.viewObjects.forEach { if $0.followMusic && $0.isON && $0.isHSIMode {
                    $0.HSB = (CGFloat(hue), 1.0, CGFloat(brr))
                }}

                //self.spectrogram_data.hueBase += 0.001
                //Logger.debug("self.spectrogram_data.hueBase: \(self.spectrogram_data.hueBase)")
            }
        }
    }
}

extension AppDelegate :  NSCollectionViewDataSource {

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return viewObjects.count
    }

    func collectionView(_ itemForRepresentedObjectAtcollectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {

        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CollectionViewItem"), for: indexPath)

        if let collectionViewItem = item as? CollectionViewItem {
            let vo = viewObjects[indexPath.section + indexPath.item]
            vo.view = collectionViewItem
            collectionViewItem.updateWithViewObject(vo)
        }

        return item
    }
}

extension AppDelegate : NSCollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
        return NSSize(width: 480, height: 280)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, insetForSectionAt section: Int) -> NSEdgeInsets
    {
        return NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat
    {
        return 10.0
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat
    {
        return 10.0
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> NSSize
    {
        return NSSize(width: 0, height: 0)
    }

    func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, referenceSizeForFooterInSection section: Int) -> NSSize
    {
        return NSSize(width: 0, height: 0)
    }
}

extension AppDelegate :  CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {
            case .unauthorized:
                switch central.authorization {
                    case .allowedAlways:break
                    case .denied:break
                    case .restricted:break
                    case .notDetermined:break
                    @unknown default:
                        break
                }
            case .unknown: break
            case .unsupported: break
            case .poweredOn:
                central.scanForPeripherals(withServices: nil, options: nil)
                Logger.info("Scanning...")
                break
            case .poweredOff:
                cbCentralManager?.stopScan()
                break
            case .resetting: break
            @unknown default: break
        }

    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        guard let name = peripheral.name else {return}

        if NeewerLight.isValidPeripheralName(name) == false {
            Logger.debug("Invalid Peripheral Name: \(name)")
            return
        }

        if devices[peripheral.identifier] != nil || tempDevices[peripheral.identifier] != nil {
            return
        }

        peripheral.delegate = self
        tempDevices[peripheral.identifier] = peripheral

        Logger.info("Neewer Light Found: \(peripheral.name!) \(peripheral.identifier)")

        cbCentralManager?.connect(peripheral, options: nil)
    }
}

extension AppDelegate :  CBPeripheralDelegate {

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        //discover all service
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            guard let neewerService: CBService = services.first(where: {$0.uuid == NeewerLight.Constants.NeewerBleServiceUUID}) else {
                return
            }

            //discover characteristics of services
            peripheral.discoverCharacteristics(nil, for: neewerService)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        if let characteristics = service.characteristics {

            guard let characteristic1: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.Constants.NeewerDeviceCtlCharacteristicUUID}) else {
                Logger.info("NeewerGattCharacteristicUUID not found")
                return
            }

            guard let characteristic2: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.Constants.NeewerGattCharacteristicUUID}) else {
                Logger.info("NeewerGattCharacteristicUUID not found")
                return
            }

            let light: NeewerLight = NeewerLight(peripheral, characteristic1, characteristic2)
            devices[peripheral.identifier] = light
            light.startLightOnNotify()

            tempDevices.removeValue(forKey: peripheral.identifier)

            DispatchQueue.main.async {
                self.updateUI()
            }
        }
    }
}

