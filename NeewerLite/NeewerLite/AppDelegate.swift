//
//  AppDelegate.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa
import CoreBluetooth
import IOBluetooth

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet var appMenu: NSMenu!
    @IBOutlet weak var collectionView: NSCollectionView!
    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var cbCentralManager: CBCentralManager?
    var tempDevices: [UUID: CBPeripheral] = [:]
    var devices: [UUID: NeewerLight] = [:]
    var viewObjects: [DeviceViewObject] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
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
                                       hasVisibleWindows flag: Bool) -> Bool
    {
        return true
    }

    @IBAction func scanAction(_ sender: Any) {
        cbCentralManager?.stopScan()
        devices.removeAll()
        viewObjects.removeAll()
        statusItem.button?.image = NSImage(named: "statusItemOffIcon")
        updateUI()
        cbCentralManager = CBCentralManager(delegate: self, queue: nil)
    }

    @IBAction func aboutAction(_ sender: Any) {
        showWindow(sender)
        func getYear () -> Int {
            return Calendar.current.component(.year, from: Date())
        }
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): "Copyright © \(getYear()) Keefo"
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
                if cmd == "turnOnLight" {
                    for vo in viewObjects {
                        if !vo.device.isOn.value {
                            vo.device.sendPowerOnRequest()
                        }
                    }
                    statusItem.button?.image = NSImage(named: "statusItemOnIcon")
                }
                else if cmd == "turnOffLight" {
                    for vo in viewObjects {
                        if vo.device.isOn.value {
                            vo.device.sendPowerOffRequest()
                        }
                    }
                    statusItem.button?.image = NSImage(named: "statusItemOffIcon")
                }
                else if cmd == "toggleLight" {
                    for vo in viewObjects {
                        if vo.device.isOn.value {
                            vo.device.sendPowerOffRequest()
                        }
                        else {
                            vo.device.sendPowerOnRequest()
                        }
                    }
                    statusItem.button?.image = NSImage(named: "statusItemOffIcon")
                }
                else if cmd == "scanLight" {
                    scanAction(cmd)
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
        for item in appMenu.items {
            if item.tag == 8 {
                appMenu.removeItem(item)
            }
        }

        let opt = NSEvent.modifierFlags.contains(.option)

        for vo in viewObjects.reversed() {
            var name = vo.device.userLightName
            if opt  {
                name = "\(vo.device.userLightName) - \(vo.device.identifier) - \(vo.device.rawName)"
            }
            let item =  NSMenuItem(title: name, action: #selector(self.showWindow(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: vo.device.isOn.value ? "lightbulb" : "lightbulb.slash", accessibilityDescription: "Light")
            item.tag = 8
            appMenu.insertItem(item, at: 2)
        }
    }

    public func updateUI() {
        viewObjects.removeAll()

        let sortedDevices = devices.sorted(by: { $0.0.uuidString < $1.0.uuidString })
        for device in sortedDevices {
            let vo = DeviceViewObject(device.value)
            viewObjects.append(vo)
        }
        statusItem.button?.title = "\(viewObjects.count)"

        // make view items order stable
        viewObjects.sort {
            $0.deviceIdentifier > $1.deviceIdentifier
        }

        collectionView.reloadData()
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
            guard let neewerService: CBService = services.first(where: {$0.uuid == NeewerLight.NeewerBleServiceUUID}) else {
                return
            }

            //discover characteristics of services
            peripheral.discoverCharacteristics(nil, for: neewerService)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        if let characteristics = service.characteristics {

            guard let characteristic1: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.NeewerDeviceCtlCharacteristicUUID}) else {
                Logger.info("NeewerGattCharacteristicUUID not found")
                return
            }

            guard let characteristic2: CBCharacteristic = characteristics.first(where: {$0.uuid == NeewerLight.NeewerGattCharacteristicUUID}) else {
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

