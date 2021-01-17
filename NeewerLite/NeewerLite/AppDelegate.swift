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
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var collectionView: NSCollectionView!
    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var cbCentralManager: CBCentralManager?
    var tempDevices: [UUID: CBPeripheral] = [:]
    var devices: [UUID: NeewerLight] = [:]
    var viewObjects: [DeviceViewObject] = []

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        NSApp.setActivationPolicy(.accessory)

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

    @objc func showWindow(_ sender: Any) {
        self.window.makeKeyAndOrderFront(self)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
            }
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Store all Lights values
        for device in devices {
            device.value.saveToUserDefault()
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

        let menu = NSMenu(title: "statusBarMenu")
        let itemShow =  NSMenuItem(title: "Show Window", action: #selector(self.showWindow(_:)), keyEquivalent: "")
        itemShow.target = self
        menu.addItem(itemShow)

        menu.addItem(NSMenuItem.separator())

        for vo in viewObjects {
            let item =  NSMenuItem(title: vo.deviceName, action: #selector(self.showWindow(_:)), keyEquivalent: "")
            itemShow.target = self
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let itemQuit =  NSMenuItem(title: "Quit", action: #selector(NSApplication.shared.terminate), keyEquivalent: "")
        itemQuit.target = NSApp
        menu.addItem(itemQuit)

        self.statusItem.menu = menu

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
            collectionViewItem.updateWithViewObject(viewObjects[indexPath.section + indexPath.item])
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
        guard peripheral.name != nil else {return}

        if peripheral.name?.contains("NWR") == false &&
            peripheral.name?.contains("NEEWER") == false &&
            peripheral.name?.contains("SL") == false
        {
            return
        }

        if devices[peripheral.identifier] != nil || tempDevices[peripheral.identifier] != nil {
            return
        }
        

        peripheral.delegate = self
        tempDevices[peripheral.identifier] = peripheral

        Logger.debug("Neewer Light Found! \(peripheral.name!) \(peripheral.identifier)")

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
            guard let neewerService: CBService = services.first(where: {$0.uuid == CBUUID.NeewerBleServiceUUID}) else {
                return
            }

            //discover characteristics of services
            peripheral.discoverCharacteristics(nil, for: neewerService)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {

        if let characteristics = service.characteristics {

            guard let characteristic1: CBCharacteristic = characteristics.first(where: {$0.uuid == CBUUID.NeewerDeviceCtlCharacteristicUUID}) else {
                Logger.info("NeewerGattCharacteristicUUID not found")
                return
            }

            guard let characteristic2: CBCharacteristic = characteristics.first(where: {$0.uuid == CBUUID.NeewerGattCharacteristicUUID}) else {
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

