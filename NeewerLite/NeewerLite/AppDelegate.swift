//
//  AppDelegate.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Accelerate
import Cocoa
import CoreBluetooth
import Dispatch
import IOBluetooth
import Sparkle
import SwiftUI

#if DEBUG
    let debugFakeLights = false
#else
    let debugFakeLights = false
#endif

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {

    @IBOutlet var window: NSWindow!
    @IBOutlet weak var appMenu: NSMenu!
    @IBOutlet weak var collectionView: NSCollectionView!
    @IBOutlet weak var mylightTableView: NSTableView!
    @IBOutlet weak var scanTableView: NSTableView!
    @IBOutlet weak var scanningStatus: NSTextField!
    @IBOutlet weak var viewsButton: NSSegmentedControl!
    @IBOutlet weak var audioDriveSwitch: NSSwitch!
    @IBOutlet weak var gainValueField: NSTextField!

    @IBOutlet weak var scanButton: NSButton!

    @IBOutlet var view0: NSView!
    @IBOutlet var view1: NSView!
    @IBOutlet var view2: NSView!

    private lazy var view4: SettingsView = SettingsView()
    var audioSpectrogramViewVisible: Bool = false

    private var statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var audioSpectrogram: AudioSpectrogram?
    private var spectrogramViewObject = SpectrogramViewObject()
    private let audioAnalysisEngine = AudioAnalysisEngine()
    private var soundToLightMode: SoundToLightMode = PulseMode()
    private let bleThrottle = BLESmartThrottle()
    private let commandHandler = CommandHandler()
    private var renameVC: RenameViewController?
    private var activeVisualization: AudioVisualizerPlugin?
    private var visualizationPopup: NSPopUpButton?
    private var audioInputPopup: NSPopUpButton?

    // Sound-to-Light UI state
    private var currentModeType: SoundToLightModeType = .pulse
    private var currentReactivity: Reactivity = .moderate
    private var currentPaletteIndex: Int = -1 // -1 = mode default
    private var modePopup: NSPopUpButton?
    private var reactivityPopup: NSPopUpButton?
    private var palettePopup: NSPopUpButton?
    private var presetPopup: NSPopUpButton?
    private var musicLightListView: NSScrollView?
    private let musicLightListId = NSUserInterfaceItemIdentifier("MusicLightCell")
    /// Original light modes saved before Music View forces HSI.
    private var musicModeOverrides: [String: NeewerLight.Mode] = [:]

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
                scanningStatus?.stringValue = "Scan New Lights.".localized
                scanningTimer = Timer.scheduledTimer(
                    timeInterval: 0.5,
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
    var server: NeewerLiteServer?
    var launching: Bool = true
    var commonJobTimer: Timer?

    var statusItemIcon: ButtonState = .off {
        didSet {
            if let button = statusItem.button {
                switch statusItemIcon {
                case .on:
                    button.image = NSImage(
                        systemSymbolName: "light.panel.fill", accessibilityDescription: nil)
                case .off:
                    button.image = NSImage(
                        systemSymbolName: "light.panel", accessibilityDescription: nil)
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        Logger.initialize()

        NSApp.setActivationPolicy(.accessory)

        Logger.info(LogTag.app, "App launch")

        scanningStatus?.stringValue = ""
        let idx = UserDefaults.standard.value(forKey: "viewIdx") as? Int
        self.viewsButton.selectSegment(withTag: idx ?? 0)

        localizeXIBStrings()

        appMenu.delegate = self
        self.statusItem.menu = appMenu
        self.statusItemIcon = .off
        window.minSize = NSSize(width: 580, height: 400)
        window.delegate = self

        registerCommands()

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        collectionView.dataSource = self
        collectionView.delegate = self

        let layout = CenteredFlowLayout()
        layout.itemSize = CollectionViewItem.frame().size
        layout.interitemSpacing = 10
        layout.lineSpacing = 10
        layout.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        collectionView.collectionViewLayout = layout

        setupMusicLightList()
        setupVisualizationPlugins()
        setupSoundToLightControls()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseUpdate(_:)),
            name: ContentManager.databaseUpdatedNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDatabaseCountdown(_:)),
            name: ContentManager.databaseUpdatedCountdownNotification,
            object: nil
        )
        ContentManager.shared.loadDatabaseFromDisk()
        ContentManager.shared.downloadDatabase(force: false)

        loadLightsFromDisk()
        restoreFollowMusicSelections()
        self.updateUI()

        // Skip BLE and network services when running under unit tests
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }

        cbCentralManager = CBCentralManager(delegate: self, queue: nil)
        keepLightConnectionAlive()

        self.switchViewAction(self.viewsButton)

        server = NeewerLiteServer(appDelegate: self)
        server!.start()
        commonJobTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) {
            [weak self] _ in
            self?.commonJob()
        }
        launching = false

        // Start minimized to tray — hide the window
        window.orderOut(nil)

#if DEBUG
        // Stage-0 baseline: launch with --baseline-audio to auto-show the Music View
        // and start the audio driver without manual UI interaction.
        // Usage: NeewerLite --baseline-audio
        // Remove this block (and its AppDelegate.swift counterpart) before shipping.
        if CommandLine.arguments.contains("--baseline-audio") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self else { return }
                self.showWindowAction(self)
                self.viewsButton.selectSegment(withTag: 2)
                self.switchViewAction(self.viewsButton)
                self.audioDriveSwitch.state = .on
                self.toggleAudioDriver(self.audioDriveSwitch)
            }
        }
#endif

        sync_sp_plugin()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide the window and remove from Dock instead of closing
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
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

    @objc func handleDatabaseCountdown(_ notification: Notification) {
        // reload image or refresh UI
        guard let remaining = notification.userInfo?["remaining"] as? TimeInterval else { return }
        Logger.debug("Database sync in \(Int(remaining)) seconds.")
    }

    @objc func handleDatabaseUpdate(_ notification: Notification) {
        // reload image or refresh UI
        guard let status = notification.userInfo?["status"] as? ContentManager.DBUpdateStatus else {
            return
        }

        switch status {
        case .success:
            Logger.info("✅ Database download completed.")
            Task { @MainActor in
                self.updateUI()
            }
        case .failure(let error):
            Logger.error("❌ Database Update failed: \(error.localizedDescription)")
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Database Update Failed".localized
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    func commonJob() {
        sync_sp_plugin()
    }

    func sync_sp_plugin() {
        struct Holder {
            static var hasRun = false
        }
        guard !Holder.hasRun else {
            return
        }
        var sp_installed_version = ""
        var sp_bundled_version = ""
        do {
            let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
            let manifestURL =
                appSupport
                .appendingPathComponent("com.elgato.StreamDeck")
                .appendingPathComponent("Plugins")
                .appendingPathComponent("com.beyondcow.neewerlite.sdPlugin")
                .appendingPathComponent("manifest.json")

            let data = try Data(contentsOf: manifestURL)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                sp_installed_version = json["Version"] as! String
            }
        } catch {
            Logger.error(LogTag.app, "Failed to read manifest: \(error)")
        }

        if let info = Bundle.main.infoDictionary {
            if let sp_plugin_version = info["SDPluginVersion"] as? String {
                sp_bundled_version = sp_plugin_version
            }
        }

        if sp_installed_version != sp_bundled_version {
            if let bundleID = defaultBundleID(forFileExtension: "streamDeckPlugin") {
                if bundleID == "com.elgato.StreamDeck" {
                    if let pluginURL = Bundle.main.url(
                        forResource: "com.beyondcow.neewerlite", withExtension: "streamDeckPlugin")
                    {
                        Holder.hasRun = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            let alert = NSAlert()
                            if sp_installed_version.isEmpty {
                                alert.messageText = "You have Stream Deck".localized
                                alert.informativeText =
                                    "Do you want to install the Neewerlite Stream Deck plugin?".localized
                            } else {
                                alert.messageText = "Found an old Neewerlite Stream Deck plugin".localized
                                alert.informativeText =
                                    "Do you want to update the Neewerlite Stream Deck plugin from %@ to %@?".localized(sp_installed_version, sp_bundled_version)
                            }
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "Yes".localized)
                            alert.addButton(withTitle: "No".localized)
                            if alert.runModal() == .alertFirstButtonReturn {
                                NSWorkspace.shared.open(pluginURL)
                            }
                        }
                    }
                }
            }
        }
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

    private func saveFollowMusicSelections() {
        let ids = viewObjects.filter { $0.followMusic }.map { $0.deviceIdentifier }
        UserDefaults.standard.set(ids, forKey: "stlFollowMusicDevices")
    }

    private func restoreFollowMusicSelections() {
        guard let ids = UserDefaults.standard.stringArray(forKey: "stlFollowMusicDevices") else { return }
        let idSet = Set(ids)
        for device in viewObjects where idSet.contains(device.deviceIdentifier) {
            device.device.followMusic = true
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

    // MARK: - XIB String Localization

    /// Overrides hardcoded English strings from MainMenu.xib with localized versions.
    /// Called once at launch before the window is shown.
    private func localizeXIBStrings() {
        // -- Status-bar app menu --
        for item in appMenu.items {
            switch item.action {
            case #selector(showWindowAction(_:)):
                item.title = "Show Window".localized
            case #selector(showSettingsAction(_:)):
                item.title = "Settings".localized
            case #selector(aboutAction(_:)):
                item.title = "About".localized
            case #selector(NSApplication.terminate(_:)):
                item.title = "Quit".localized
            default:
                if item.action == #selector(SUUpdater.checkForUpdates(_:)) {
                    item.title = "Check for Updates...".localized
                }
            }
        }

        // -- Help menu custom items (find by action, not title — title may be localized) --
        if let mainMenu = NSApp.mainMenu {
            for menuItem in mainMenu.items {
                guard let submenu = menuItem.submenu else { continue }
                for item in submenu.items {
                    switch item.action {
                    case #selector(syncDatabaseAction(_:)):
                        item.title = "Sync Database".localized
                    case #selector(checklogAction(_:)):
                        item.title = "Check Logs".localized
                    default:
                        if item.action == #selector(NSApplication.showHelp(_:)) {
                            item.title = "NeewerLite Help".localized
                        }
                    }
                }
            }
        }

        // -- "My Lights" header in view0 --
        if let label = findTextField(in: view0, withTitle: "My Lights") {
            label.stringValue = "My Lights".localized
        }

        // -- "Listen" label in view2 --
        if let label = findTextField(in: view2, withTitle: "Listen") {
            label.stringValue = "Listen".localized
        }

        // -- "Preview Feature (Not working)" label in view2 --
        if let label = findTextField(in: view2, withTitle: "Preview Feature (Not working)") {
            label.stringValue = "Preview Feature (Not working)".localized
        }

        // -- Scan button in view0 --
        scanButton.title = "Scan".localized
    }

    /// Recursively finds an NSTextField whose stringValue matches `title`.
    private func findTextField(in view: NSView, withTitle title: String) -> NSTextField? {
        for subview in view.subviews {
            if let textField = subview as? NSTextField, textField.stringValue == title {
                return textField
            }
            if let found = findTextField(in: subview, withTitle: title) {
                return found
            }
        }
        return nil
    }

    func registerCommands() {
        commandHandler.register(
            command: Command(
                type: .scanLight,
                action: { _ in
                    // from open command neewerlite://scanLight
                    self.viewsButton.selectSegment(withTag: 0)
                    self.switchViewAction(self.viewsButton)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.forceScanAction(self.scanButton)
                    }
                }))

        commandHandler.register(
            command: Command(
                type: .turnOnLight,
                action: { cmdParameter in
                    if let lightname = cmdParameter.lightName() {
                        self.viewObjects.forEach {
                            if lightname.caseInsensitiveCompare($0.device.userLightName.value)
                                == .orderedSame
                            {
                                $0.turnOnLight()
                            }
                        }
                    } else {
                        self.viewObjects.forEach { $0.turnOnLight() }
                    }
                    self.statusItemIcon = .on
                }))

        commandHandler.register(
            command: Command(
                type: .turnOffLight,
                action: { cmdParameter in
                    if let lightname = cmdParameter.lightName() {
                        self.viewObjects.forEach {
                            if lightname.caseInsensitiveCompare($0.device.userLightName.value)
                                == .orderedSame
                            {
                                $0.turnOffLight()
                            }
                        }
                    } else {
                        self.viewObjects.forEach { $0.turnOffLight() }
                    }
                    self.statusItemIcon = .on
                }))

        commandHandler.register(
            command: Command(
                type: .toggleLight,
                action: { cmdParameter in
                    if let lightname = cmdParameter.lightName() {
                        self.viewObjects.forEach {
                            if lightname.caseInsensitiveCompare($0.device.userLightName.value)
                                == .orderedSame
                            {
                                $0.toggleLight()
                            }
                        }
                    } else {
                        self.viewObjects.forEach { $0.toggleLight() }
                    }
                    self.statusItemIcon = .off
                }))

        commandHandler.register(
            command: Command(
                type: .setLightCCT,
                action: { cmdParameter in
                    let cct = cmdParameter.CCT()
                    let brr = cmdParameter.brightness()
                    let gmm = cmdParameter.GMM()
                    func act(_ viewObj: DeviceViewObject) {
                        if viewObj.isON {
                            Task { @MainActor in
                                viewObj.changeToCCTMode()
                                viewObj.updateCCT(cct, gmm, brr)
                            }
                        }
                    }

                    if let lightname = cmdParameter.lightName() {
                        self.viewObjects.forEach {
                            if lightname.caseInsensitiveCompare($0.device.userLightName.value)
                                == .orderedSame
                            {
                                act($0)
                            }
                        }
                    } else {
                        self.viewObjects.forEach { act($0) }
                    }
                    self.statusItemIcon = .on
                }))

        commandHandler.register(
            command: Command(
                type: .setLightHSI,
                action: { cmdParameter in
                    let hueVal: Double
                    if let color = cmdParameter.RGB() {
                        hueVal = CGFloat(color.hueComponent * 360.0)
                    } else if let hue = cmdParameter.HUE() {
                        hueVal = CGFloat(hue)
                    } else {
                        return
                    }
                    let sat = cmdParameter.saturation()
                    let brr = cmdParameter.brightness()
                    func act(_ viewObj: DeviceViewObject, showAlert: Bool) {
                        if viewObj.isON {
                            if viewObj.device.supportRGB {
                                Task { @MainActor in
                                    viewObj.changeToHSIMode()
                                    viewObj.updateHSI(hue: hueVal, sat: sat, brr: brr)
                                }
                            } else {
                                if showAlert {
                                    Task { @MainActor in
                                        let alert = NSAlert()
                                        alert.messageText = "This light does not support RGB".localized
                                        alert.informativeText = "\(viewObj.device.nickName)"
                                        alert.alertStyle = .informational
                                        alert.addButton(withTitle: "OK".localized)
                                        alert.runModal()
                                    }
                                }
                            }
                        }
                    }

                    if let lightname = cmdParameter.lightName() {
                        self.viewObjects.forEach {
                            if lightname.caseInsensitiveCompare($0.device.userLightName.value)
                                == .orderedSame
                            {
                                act($0, showAlert: true)
                            }
                        }
                    } else {
                        self.viewObjects.forEach { act($0, showAlert: false) }
                    }
                    self.statusItemIcon = .on
                }))

        commandHandler.register(
            command: Command(
                type: .setLightScene,
                action: { cmdParameter in
                    let explicitSceneId = cmdParameter.sceneId()
                    let sceneName = cmdParameter.sceneName()
                    let brr = cmdParameter.brightness()

                    func act(_ viewObj: DeviceViewObject, showAlert: Bool) {
                        if viewObj.isON {
                            if viewObj.device.supportRGB {
                                let sceneId: Int
                                if let id = explicitSceneId {
                                    sceneId = id
                                } else if let name = sceneName {
                                    let nameKey = name.lowercased().replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
                                    if let match = viewObj.device.supportedFX.first(where: { $0.name_key == nameKey }) {
                                        sceneId = Int(match.id)
                                    } else {
                                        sceneId = cmdParameter.scene()
                                    }
                                } else {
                                    sceneId = 1
                                }
                                Task { @MainActor in
                                    viewObj.changeToSCEMode()
                                    viewObj.changeToSCE(sceneId, brr)
                                }
                            } else {
                                if showAlert {
                                    Task { @MainActor in
                                        let alert = NSAlert()
                                        alert.messageText = "This light does not support RGB".localized
                                        alert.informativeText = "\(viewObj.device.nickName)"
                                        alert.alertStyle = .informational
                                        alert.addButton(withTitle: "OK".localized)
                                        alert.runModal()
                                    }
                                }
                            }
                        }
                    }

                    if let lightname = cmdParameter.lightName() {
                        self.viewObjects.forEach {
                            if lightname.caseInsensitiveCompare($0.device.userLightName.value)
                                == .orderedSame
                            {
                                act($0, showAlert: true)
                            }
                        }
                    } else {
                        self.viewObjects.forEach { act($0, showAlert: false) }
                    }
                    self.statusItemIcon = .on
                }))
    }

    private var stlDebugFrameCount: UInt64 = 0

    private func driveLightFromFrequency(_ frequency: [Float]) {
        // Only drive lights when Music View is active.
        guard audioSpectrogramViewVisible else { return }

        stlDebugFrameCount += 1

        let normalized = normalizeMelSpectrum(frequency)

        // Debug: log mel bin range and engine output once per second (~46 Hz)
        let shouldLog = stlDebugFrameCount <= 3 || stlDebugFrameCount % 46 == 0
        if shouldLog {
            let melMax = frequency.filter { $0.isFinite }.max() ?? 0
            let posCount = normalized.filter { $0 > 0 }.count
            let normMax = normalized.max() ?? 0
            Logger.debug(.none, "[STL] frame \(stlDebugFrameCount): melMax=\(String(format: "%.1f", melMax)) pos=\(posCount)/60 normMax=\(String(format: "%.3f", normMax))")
        }

        // Run the analysis engine every frame (~46 Hz) for accurate beat detection.
        let features = audioAnalysisEngine.analyze(normalized)

        if shouldLog {
            Logger.debug(.none, "[STL]   features: bass=\(String(format: "%.3f", features.bassEnergy)) mid=\(String(format: "%.3f", features.midEnergy)) high=\(String(format: "%.3f", features.highEnergy)) overall=\(String(format: "%.3f", features.overallEnergy)) beat=\(features.isBeat) gate=\(features.noiseGateOpen) rms=\(String(format: "%.4f", features.rawRMS)) flat=\(String(format: "%.3f", features.spectralFlatness))")
        }

        // Compute light command from the active mapping mode
        let command = soundToLightMode.process(features)

        if shouldLog {
            Logger.debug(.none, "[STL]   command: hue=\(String(format: "%.1f", command.hue)) sat=\(String(format: "%.2f", command.saturation)) brr=\(String(format: "%.3f", command.brightness))")
        }

        // Send to each device that has followMusic enabled, with smart throttling.
        // Music View forces HSI mode, so always send HSI commands when supported.
        // Call device BLE methods directly (not through the view layer) because
        // this callback fires on the audio capture thread.
        var sentCount = 0
        var skipCount = 0
        var offCount = 0
        self.viewObjects.forEach { device in
            guard device.followMusic && device.isON else {
                if device.followMusic { offCount += 1 }
                return
            }

            let deviceId = device.deviceIdentifier
            guard bleThrottle.shouldSend(command: command, deviceId: deviceId) else {
                skipCount += 1
                return
            }

            let light = device.device
            if soundToLightMode.supportsHSI {
                let hue360 = CGFloat(command.hue)
                let sat = CGFloat(command.saturation)
                let brr = CGFloat(command.brightness) * 100.0
                light.setHSILightValues(
                    brr100: brr,
                    hue: hue360 / 360.0,
                    hue360: hue360,
                    sat: sat)
                sentCount += 1
            } else if soundToLightMode.supportsCCT {
                light.setCCTLightValues(
                    brr: CGFloat(command.brightness),
                    cct: CGFloat(command.cct),
                    gmm: CGFloat(command.gm))
                sentCount += 1
            }

            bleThrottle.didSend(command: command, deviceId: deviceId)
        }

        if shouldLog || features.isBeat {
            let followCount = self.viewObjects.filter { $0.followMusic }.count
            Logger.debug(.none, "[STL]   send: \(sentCount) sent, \(skipCount) throttled, \(offCount) off | followMusic=\(followCount) total=\(self.viewObjects.count) | beat=\(features.isBeat) brr=\(String(format: "%.0f%%", command.brightness * 100))")
        }
    }

    func checkAudioDriver() {
        // Only start/stop the audio driver based on the Listen switch state.
        // Don't change the switch — it's a manual user control.
        if audioDriveSwitch.state == .on {
            toggleAudioDriver(audioDriveSwitch!)
        }
    }

    @IBAction func checklogAction(_ sender: NSMenuItem) {
        Logger.syncToFile()
        if let fileURL = Logger.currentLogFileURL,
            FileManager.default.fileExists(atPath: fileURL.path)
        {
            if let consoleAppURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.apple.Console")
            {
                let config = NSWorkspace.OpenConfiguration()
                NSWorkspace.shared.open(
                    [fileURL], withApplicationAt: consoleAppURL, configuration: config
                ) { app, error in
                    if let error = error {
                        Task { @MainActor in
                            let alert = NSAlert()
                            alert.messageText = "Failed to open log file".localized
                            alert.informativeText = "Failed to open log file in Console. %@".localized(String(describing: error))
                            alert.alertStyle = .warning
                            alert.runModal()
                        }
                    }
                }
            } else {
                Task { @MainActor in
                    let alert = NSAlert()
                    alert.messageText = "Console app not found".localized
                    alert.informativeText =
                        "Console app not found, unable to open the log file. %@".localized(fileURL.absoluteString)
                    alert.alertStyle = .warning
                    alert.runModal()
                }
            }
        } else {
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Log file not found".localized
                if let url = Logger.currentLogFileURL {
                    alert.informativeText = "%@ log file does not exist.".localized(url.path)
                } else {
                    alert.informativeText = "Log file URL is unavailable.".localized
                }
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @IBAction func syncDatabaseAction(_ sender: NSMenuItem) {
        ContentManager.shared.downloadDatabase(force: true)
    }



    @IBAction func changeGainAction(_ sender: NSSlider) {
        if let safe = audioSpectrogram {
            safe.zeroReference = sender.doubleValue
        }
        gainValueField.stringValue = "\(sender.doubleValue)"
    }

    // MARK: - Music View Light List

    private func setupMusicLightList() {
        let listFrame = NSRect(x: 10, y: 10, width: 145, height: 355)

        let scrollView = NSScrollView(frame: listFrame)
        scrollView.autoresizingMask = [.maxXMargin, .height]
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 24
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none

        let column = NSTableColumn(identifier: musicLightListId)
        column.width = listFrame.width - 20
        tableView.addTableColumn(column)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        view2.addSubview(scrollView)
        musicLightListView = scrollView
    }

    func refreshMusicLightList() {
        guard let scrollView = musicLightListView,
              let tableView = scrollView.documentView as? NSTableView else { return }
        tableView.reloadData()
    }

    @objc private func toggleMusicLightList(_ sender: NSButton) {
        guard let listView = musicLightListView else { return }
        listView.isHidden = !listView.isHidden
        layoutMusicViewContent()
    }

    /// Recalculates visualization and light-list frames from current view2 bounds.
    private func layoutMusicViewContent() {
        let bounds = view2.bounds
        let listHidden = musicLightListView?.isHidden ?? false
        let vizX: CGFloat = listHidden ? 10 : 160
        let vizW = bounds.width - vizX - 10
        let vizH = bounds.height - 70  // 10 bottom + 14 labels + 22 popups + 14 gap + 10 top

        if let vizView = activeVisualization?.visualizerView {
            vizView.frame = NSRect(x: vizX, y: 10, width: vizW, height: vizH)
        }

        if let listView = musicLightListView, !listHidden {
            listView.frame = NSRect(x: 10, y: 10, width: 145, height: vizH)
        }
    }

    @objc private func micButtonClicked(_ sender: NSButton) {
        // Toggle the hidden NSSwitch state and trigger the audio driver
        audioDriveSwitch.state = (audioDriveSwitch.state == .on) ? .off : .on
        toggleAudioDriver(audioDriveSwitch)
        // Update icon tint to reflect state
        sender.contentTintColor = (audioDriveSwitch.state == .on) ? .controlAccentColor : .secondaryLabelColor
    }

    @objc func musicLightCheckboxClicked(_ sender: NSButton) {
        let row = sender.tag
        guard row >= 0 && row < viewObjects.count else { return }
        let device = viewObjects[row]
        let devId = device.deviceIdentifier
        device.device.followMusic = (sender.state == .on)

        // Persist follow-music selections
        saveFollowMusicSelections()

        if device.followMusic {
            // Save original mode and force HSI for Sound-to-Light
            if musicModeOverrides[devId] == nil {
                musicModeOverrides[devId] = device.device.lightMode
            }
            device.device.lightMode = .HSIMode
        } else {
            // Restore original mode
            restoreLightMode(device)
        }
        checkAudioDriver()
    }

    /// Force all follow-music lights into HSI mode (called when entering Music View).
    private func applyMusicModeOverrides() {
        for device in viewObjects where device.followMusic {
            let devId = device.deviceIdentifier
            if musicModeOverrides[devId] == nil {
                musicModeOverrides[devId] = device.device.lightMode
            }
            device.device.lightMode = .HSIMode
        }
    }

    /// Restore a single light to its pre-music mode and send the matching BLE command.
    private func restoreLightMode(_ device: DeviceViewObject) {
        let devId = device.deviceIdentifier
        guard let originalMode = musicModeOverrides.removeValue(forKey: devId) else { return }
        let light = device.device
        switch originalMode {
        case .CCTMode:
            light.setCCTLightValues(
                brr: CGFloat(light.brrValue.value),
                cct: CGFloat(light.cctValue.value),
                gmm: CGFloat(light.gmmValue.value))
        case .HSIMode:
            break // already in HSI, nothing to do
        default:
            light.lightMode = originalMode
        }
    }

    /// Restore all follow-music lights to their original modes (called when leaving Music View).
    private func restoreAllMusicModeOverrides() {
        for device in viewObjects where musicModeOverrides[device.deviceIdentifier] != nil {
            restoreLightMode(device)
        }
    }

    // MARK: - Visualization Plugin System

    private func setupVisualizationPlugins() {
        let manager = VisualizationPluginManager.shared

        // Register built-in visualizations (all code-driven, no XIB).
        manager.register(name: SpectrumVisualization.displayName) { frame in
            SpectrumVisualization(frame: frame)
        }
        manager.register(name: SpectrogramVisualization.displayName) { frame in
            SpectrogramVisualization(frame: frame)
        }
        manager.register(name: WaveformVisualization.displayName) { frame in
            WaveformVisualization(frame: frame)
        }

        // Discover any bundle-based plugins in PlugIns/Visualizations/.
        manager.discoverBundlePlugins()

        // Create the default visualization and add it to view2.
        let vizFrame = NSRect(x: 160, y: 10, width: 469, height: 355)
        if let defaultPlugin = manager.plugin(at: 0, frame: vizFrame) {
            let v = defaultPlugin.visualizerView
            v.frame = vizFrame
            v.autoresizingMask = [.width, .height]
            view2.addSubview(v)
            activeVisualization = defaultPlugin
        }

        // Hide the static "Preview Feature (Not working)" label — replaced by the popup.
        for subview in view2.subviews where subview is NSTextField {
            if let tf = subview as? NSTextField,
               tf.stringValue.contains("Preview Feature") || tf.stringValue.contains("Preview Feature (Not working)".localized) {
                tf.isHidden = true
                break
            }
        }

        // Add a visualization picker popup to the Music View (view2).
        let popup = NSPopUpButton(frame: NSRect(x: 105, y: 381, width: 85, height: 22), pullsDown: false)
        popup.autoresizingMask = [.maxXMargin, .minYMargin]
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        for name in manager.pluginNames {
            popup.addItem(withTitle: name.localized)
        }
        popup.selectItem(at: 0)
        popup.target = self
        popup.action = #selector(visualizationSelectionChanged(_:))
        view2.addSubview(popup)
        visualizationPopup = popup
    }

    // MARK: - Sound-to-Light Controls

    private func setupSoundToLightControls() {
        // Restore persisted settings
        if let modeRaw = UserDefaults.standard.string(forKey: "stlMode"),
           let modeType = SoundToLightModeType(rawValue: modeRaw) {
            currentModeType = modeType
        }
        if let reactRaw = UserDefaults.standard.object(forKey: "stlReactivity") as? Int,
           let react = Reactivity(rawValue: reactRaw) {
            currentReactivity = react
        }
        currentPaletteIndex = UserDefaults.standard.object(forKey: "stlPalette") as? Int ?? -1

        // Restore sensitivity (noise gate threshold)
        if let savedSens = UserDefaults.standard.object(forKey: "stlSensitivity") as? Double {
            let inverted = Float(1.0 - savedSens)
            audioAnalysisEngine.rmsFloorThreshold = inverted * 0.2
            audioAnalysisEngine.rmsPassthroughThreshold = max(audioAnalysisEngine.rmsFloorThreshold + 0.11, 0.15)
            audioAnalysisEngine.rmsCloseThreshold = audioAnalysisEngine.rmsFloorThreshold * 0.5
        }

        rebuildSoundToLightMode()

        // Two-row layout: labels above popups
        let smallFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let miniFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))
        let rowY: CGFloat = 381
        let labelY: CGFloat = rowY + 22

        // Sidebar toggle button
        let sidebarBtn = NSButton(frame: NSRect(x: 6, y: rowY - 1, width: 24, height: 24))
        sidebarBtn.bezelStyle = .inline
        sidebarBtn.isBordered = false
        sidebarBtn.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle light list")
        sidebarBtn.contentTintColor = .secondaryLabelColor
        sidebarBtn.target = self
        sidebarBtn.action = #selector(toggleMusicLightList(_:))
        sidebarBtn.autoresizingMask = [.maxXMargin, .minYMargin]
        view2.addSubview(sidebarBtn)

        // Hide the original Listen label and switch (keep switch for state tracking)
        for subview in view2.subviews where subview is NSTextField {
            if let tf = subview as? NSTextField,
               tf.stringValue == "Listen" || tf.stringValue == "Listen".localized {
                tf.isHidden = true
                break
            }
        }
        audioDriveSwitch.isHidden = true

        // Mic toggle button
        let micBtn = NSButton(frame: NSRect(x: 32, y: rowY - 1, width: 24, height: 24))
        micBtn.bezelStyle = .inline
        micBtn.isBordered = false
        micBtn.image = NSImage(systemSymbolName: "microphone.fill", accessibilityDescription: "Listen".localized)
        micBtn.contentTintColor = .secondaryLabelColor
        micBtn.target = self
        micBtn.action = #selector(micButtonClicked(_:))
        micBtn.autoresizingMask = [.maxXMargin, .minYMargin]
        view2.addSubview(micBtn)

        // --- Audio Input popup ---
        let inputPop = NSPopUpButton(frame: NSRect(x: 62, y: rowY, width: 100, height: 22), pullsDown: false)
        inputPop.controlSize = .small
        inputPop.font = smallFont
        inputPop.autoresizingMask = [.maxXMargin, .minYMargin]
        populateAudioInputPopup(inputPop)
        inputPop.target = self
        inputPop.action = #selector(audioInputSelectionChanged(_:))
        view2.addSubview(inputPop)
        audioInputPopup = inputPop
        addToolbarLabel("Input".localized, x: 62, y: labelY, width: 100, font: miniFont)

        // Reposition Spectrum popup (created in setupVisualizationPlugins)
        visualizationPopup?.frame = NSRect(x: 170, y: rowY, width: 96, height: 22)
        addToolbarLabel("Visualization".localized, x: 170, y: labelY, width: 96, font: miniFont)

        // --- Mode popup ---
        let modePop = NSPopUpButton(frame: NSRect(x: 274, y: rowY, width: 96, height: 22), pullsDown: false)
        modePop.controlSize = .small
        modePop.font = smallFont
        modePop.autoresizingMask = [.maxXMargin, .minYMargin]
        for mode in SoundToLightModeType.allCases {
            modePop.addItem(withTitle: mode.rawValue.localized)
        }
        modePop.selectItem(withTitle: currentModeType.rawValue.localized)
        modePop.target = self
        modePop.action = #selector(modeSelectionChanged(_:))
        view2.addSubview(modePop)
        modePopup = modePop
        addToolbarLabel("Mode".localized, x: 274, y: labelY, width: 96, font: miniFont)

        // --- Reactivity popup ---
        let reactPop = NSPopUpButton(frame: NSRect(x: 378, y: rowY, width: 86, height: 22), pullsDown: false)
        reactPop.controlSize = .small
        reactPop.font = smallFont
        reactPop.autoresizingMask = [.maxXMargin, .minYMargin]
        for r in Reactivity.allCases {
            reactPop.addItem(withTitle: r.displayName.localized)
        }
        reactPop.selectItem(at: currentReactivity.rawValue)
        reactPop.target = self
        reactPop.action = #selector(reactivitySelectionChanged(_:))
        view2.addSubview(reactPop)
        reactivityPopup = reactPop
        addToolbarLabel("Reactivity".localized, x: 378, y: labelY, width: 86, font: miniFont)

        // --- Palette popup ---
        let palPop = NSPopUpButton(frame: NSRect(x: 472, y: rowY, width: 78, height: 22), pullsDown: false)
        palPop.controlSize = .small
        palPop.font = smallFont
        palPop.autoresizingMask = [.maxXMargin, .minYMargin]
        palPop.addItem(withTitle: "Default".localized)
        for p in ColorPalette.palettes {
            palPop.addItem(withTitle: p.name.localized)
        }
        palPop.selectItem(at: currentPaletteIndex + 1) // +1 because index 0 = "Default"
        palPop.target = self
        palPop.action = #selector(paletteSelectionChanged(_:))
        view2.addSubview(palPop)
        palettePopup = palPop
        addToolbarLabel("Palette".localized, x: 472, y: labelY, width: 78, font: miniFont)

        // --- Preset popup ---
        let prePop = NSPopUpButton(frame: NSRect(x: 558, y: rowY, width: 78, height: 22), pullsDown: false)
        prePop.controlSize = .small
        prePop.font = smallFont
        prePop.autoresizingMask = [.maxXMargin, .minYMargin]
        prePop.addItem(withTitle: "Custom".localized)
        for p in SoundToLightPreset.presets {
            prePop.addItem(withTitle: p.name.localized)
        }
        prePop.selectItem(at: 0)
        prePop.target = self
        prePop.action = #selector(presetSelectionChanged(_:))
        view2.addSubview(prePop)
        presetPopup = prePop
        addToolbarLabel("Preset".localized, x: 558, y: labelY, width: 78, font: miniFont)

        // --- Sensitivity slider (noise gate threshold) ---
        let savedSensValue = UserDefaults.standard.object(forKey: "stlSensitivity") as? Double
            ?? Double(audioAnalysisEngine.rmsFloorThreshold) / 0.2
        let sensSlider = NLSlider(frame: NSRect(x: 644, y: rowY, width: 120, height: 22))
        sensSlider.minValue = 0.0
        sensSlider.maxValue = 1.0
        sensSlider.currentValue = CGFloat(savedSensValue)
        sensSlider.customBarDrawing = NLSlider.brightnessBar()
        sensSlider.autoresizingMask = [.maxXMargin, .minYMargin]
        sensSlider.callback = { [weak self] value in
            self?.applySensitivity(Double(value))
        }
        view2.addSubview(sensSlider)
        addToolbarLabel("Sensitivity".localized, x: 644, y: labelY, width: 120, font: miniFont)

        updatePaletteAvailability()
    }

    private func addToolbarLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, font: NSFont) {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .tertiaryLabelColor
        label.alignment = .center
        label.frame = NSRect(x: x, y: y, width: width, height: 14)
        label.autoresizingMask = [.maxXMargin, .minYMargin]
        view2.addSubview(label)
    }

    private func rebuildSoundToLightMode() {
        let palette: ColorPalette? = (currentPaletteIndex >= 0 && currentPaletteIndex < ColorPalette.palettes.count)
            ? ColorPalette.palettes[currentPaletteIndex] : nil
        soundToLightMode = currentModeType.createMode(reactivity: currentReactivity, palette: palette)
        bleThrottle.reset()
    }

    @objc private func modeSelectionChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        let allModes = SoundToLightModeType.allCases
        guard index >= 0 && index < allModes.count else { return }
        currentModeType = allModes[index]
        UserDefaults.standard.set(currentModeType.rawValue, forKey: "stlMode")
        rebuildSoundToLightMode()
        presetPopup?.selectItem(at: 0) // back to "Custom"
        updatePaletteAvailability()
    }

    /// Disable the palette popup for modes that ignore palettes (e.g. Bass Cannon, Strobe).
    private func updatePaletteAvailability() {
        let modeUsesPalette = (currentModeType == .pulse || currentModeType == .colorFlow)
        palettePopup?.isEnabled = modeUsesPalette
    }

    @objc private func reactivitySelectionChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard let react = Reactivity(rawValue: index) else { return }
        currentReactivity = react
        UserDefaults.standard.set(currentReactivity.rawValue, forKey: "stlReactivity")
        rebuildSoundToLightMode()
        presetPopup?.selectItem(at: 0)
    }

    @objc private func paletteSelectionChanged(_ sender: NSPopUpButton) {
        currentPaletteIndex = sender.indexOfSelectedItem - 1 // "Default" is at index 0
        UserDefaults.standard.set(currentPaletteIndex, forKey: "stlPalette")
        rebuildSoundToLightMode()
        presetPopup?.selectItem(at: 0)
    }

    @objc private func presetSelectionChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem - 1 // "Custom" is at index 0
        let isPreset = index >= 0 && index < SoundToLightPreset.presets.count

        // Enable/disable individual controls based on whether a named preset is active.
        let unlocked = !isPreset
        modePopup?.isEnabled = unlocked
        reactivityPopup?.isEnabled = unlocked
        // Palette availability depends on both preset lock AND mode support.
        // It's updated after mode is set below, or here for "Custom".
        if unlocked {
            updatePaletteAvailability()
        } else {
            palettePopup?.isEnabled = false
        }

        guard isPreset else { return } // "Custom" selected — just unlock, don't change settings
        let preset = SoundToLightPreset.presets[index]
        currentModeType = preset.modeType
        currentReactivity = preset.reactivity
        currentPaletteIndex = preset.paletteIndex

        // Update other popups to reflect the preset
        modePopup?.selectItem(withTitle: currentModeType.rawValue)
        reactivityPopup?.selectItem(at: currentReactivity.rawValue)
        palettePopup?.selectItem(at: currentPaletteIndex + 1)

        // Persist
        UserDefaults.standard.set(currentModeType.rawValue, forKey: "stlMode")
        UserDefaults.standard.set(currentReactivity.rawValue, forKey: "stlReactivity")
        UserDefaults.standard.set(currentPaletteIndex, forKey: "stlPalette")

        rebuildSoundToLightMode()
    }

    @objc private func visualizationSelectionChanged(_ sender: NSPopUpButton) {
        switchVisualization(to: sender.indexOfSelectedItem)
    }

    private func populateAudioInputPopup(_ popup: NSPopUpButton) {
        popup.removeAllItems()
        let devices = AudioSpectrogram.availableInputDevices()
        if devices.isEmpty {
            popup.addItem(withTitle: "No Input".localized)
            popup.isEnabled = false
            return
        }
        let savedUID = UserDefaults.standard.string(forKey: "stlAudioInputUID")
        var selectedIndex = 0
        for (idx, device) in devices.enumerated() {
            popup.addItem(withTitle: device.localizedName)
            popup.lastItem?.representedObject = device.uniqueID as NSString
            if device.uniqueID == savedUID {
                selectedIndex = idx
            }
        }
        popup.selectItem(at: selectedIndex)
        popup.isEnabled = true
    }

    @objc private func audioInputSelectionChanged(_ sender: NSPopUpButton) {
        guard let uid = sender.selectedItem?.representedObject as? String else { return }
        UserDefaults.standard.set(uid, forKey: "stlAudioInputUID")
        audioSpectrogram?.switchInputDevice(uniqueID: uid)
    }

    private func applySensitivity(_ value: Double) {
        // Invert: left(0)=max filtering, right(1)=no filtering
        let inverted = Float(1.0 - value)
        audioAnalysisEngine.rmsFloorThreshold = inverted * 0.2
        audioAnalysisEngine.rmsPassthroughThreshold = max(audioAnalysisEngine.rmsFloorThreshold + 0.11, 0.15)
        audioAnalysisEngine.rmsCloseThreshold = audioAnalysisEngine.rmsFloorThreshold * 0.5
        UserDefaults.standard.set(value, forKey: "stlSensitivity")
    }

    private func switchVisualization(to index: Int) {
        let manager = VisualizationPluginManager.shared
        let frame = activeVisualization?.visualizerView.frame
                     ?? NSRect(x: 160, y: 10, width: 469, height: 355)

        guard let plugin = manager.plugin(at: index, frame: frame) else { return }
        guard plugin !== activeVisualization else { return }

        // Remove old visualization view.
        activeVisualization?.visualizerView.removeFromSuperview()

        // Add new visualization view in the same position.
        let v = plugin.visualizerView
        v.frame = frame
        v.autoresizingMask = [.width, .height]
        view2.addSubview(v)

        activeVisualization = plugin

        // Update waterfall/spectrogram image generation.
        audioSpectrogram?.waterfallEnabled = plugin.needsSpectrogramImage
    }

    @IBAction func toggleAudioDriver(_ sender: NSSwitch) {
        if sender.state == .on {
            if audioSpectrogram == nil {
                Logger.info(LogTag.click, "autio driver start")
                let savedInputUID = UserDefaults.standard.string(forKey: "stlAudioInputUID")
                audioSpectrogram = AudioSpectrogram(inputDeviceUID: savedInputUID)
                audioSpectrogram!.audioSpectrogramImageUpdateCallback = { [weak self] cgimg in
                    guard let safeSelf = self else { return }
                    if safeSelf.audioSpectrogramViewVisible {
                        safeSelf.activeVisualization?.updateSpectrogramImage(cgimg)
                    }
                }
                audioSpectrogram!.waterfallEnabled = activeVisualization?.needsSpectrogramImage ?? false
                audioSpectrogram!.frequencyUpdateCallback = { [weak self] frequencyData in
                    guard let safeSelf = self else { return }
                    safeSelf.driveLightFromFrequency(frequencyData)
                    if safeSelf.audioSpectrogramViewVisible {
                        let sens = Float(UserDefaults.standard.double(forKey: "stlSensitivity"))
                        let scaled = frequencyData.map { $0 * sens }
                        safeSelf.activeVisualization?.updateFrequency(scaled)
                    }
                }
                audioSpectrogram!.volumeUpdateCallback = { [weak self] volume in
                    // Mac output volume — reserved for future use
                    _ = volume
                }
                audioSpectrogram!.amplitudeUpdateCallback = { [weak self] amp in
                    guard let safeSelf = self else { return }
                    safeSelf.spectrogramViewObject.updateAmplitude(amplitude: amp)
                    // Normalize mic RMS (0…~32767) to 0–1 on a log scale so the
                    // bar heights track real-world loudness, not Mac output volume.
                    let normalizedAmp = Float(min(1.0, max(0.0, log10(max(1.0, Double(amp))) / log10(10000.0))))
                    safeSelf.activeVisualization?.volume = normalizedAmp
                }
                audioSpectrogram!.startRunning()
            }
        } else {
            if audioSpectrogram != nil {
                Logger.info(LogTag.click, "autio driver stop")
                audioSpectrogram!.stopRunning()
                audioSpectrogram!.frequencyUpdateCallback = nil
                audioSpectrogram = nil
                audioAnalysisEngine.reset()
                soundToLightMode.reset()
                bleThrottle.reset()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
                self.activeVisualization?.clear()
            }
        }
    }

    @IBAction func aboutAction(_ sender: AnyObject) {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                "Copyright © \(Calendar.current.component(.year, from: Date())) Keefo"
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        self.window.makeKeyAndOrderFront(nil)
        self.window.orderFrontRegardless()
    }

    @IBAction func showSettingsAction(_ sender: AnyObject) {
        showWindowAction(sender)
        viewsButton.selectSegment(withTag: 3)
        switchViewAction(viewsButton)
    }

    @IBAction func switchViewAction(_ sender: NSSegmentedControl) {
        guard let contentView = self.window.contentView else {
            return
        }
        for subview in contentView.subviews {
            subview.removeFromSuperview()
        }
        let views: [NSView?] = [self.view0, self.view1, self.view2, self.view4]
        if sender.selectedSegment >= 0 && sender.selectedSegment < views.count {

            UserDefaults.standard.setValue(sender.selectedSegment, forKey: "viewIdx")

            if let selectedView = views[sender.selectedSegment] {
                self.audioSpectrogramViewVisible = false
                if selectedView == self.view0 {
                    window.title = "NeewerLite - Scan View".localized
                    if !launching {
                        Logger.info(LogTag.click, "Scan View")
                    }
                } else if selectedView == self.view1 {
                    window.title = "NeewerLite - Control View".localized
                    if !launching {
                        Logger.info(LogTag.click, "Control View")
                    }
                } else if selectedView == self.view2 {
                    window.title = "NeewerLite - Music View".localized
                    if !launching {
                        Logger.info(LogTag.click, "Music View")
                    }
                } else if selectedView == self.view4 {
                    window.title = "NeewerLite - Settings".localized
                    if !launching {
                        Logger.info(LogTag.click, "Settings View")
                    }
                    refreshSettingsView()
                }
                selectedView.frame = contentView.bounds
                selectedView.autoresizingMask = [.width, .height]
                contentView.addSubview(selectedView)
                updateUI()
                if selectedView == self.view2 {
                    self.audioSpectrogramViewVisible = true
                    self.layoutMusicViewContent()
                    self.activeVisualization?.clear()
                    applyMusicModeOverrides()
                    // Resume audio if Listen was on
                    if self.audioDriveSwitch.state == .on {
                        self.audioSpectrogram?.startRunning()
                    }
                } else {
                    // Pause audio and restore lights when leaving Music View
                    self.audioSpectrogram?.stopRunning()
                    restoreAllMusicModeOverrides()
                }
            }
        }
    }

    @IBAction func forceScanAction(_ sender: NSButton) {
        if sender.title == "Scan".localized {
            scanning = false
            scanningNewLightMode = true
            scanningViewObjects.removeAll()
            scanTableView.reloadData()
            scanAction(sender)
            sender.title = "Stop".localized
            Logger.info(LogTag.click, "Scan")
        } else {
            scanningNewLightMode = false
            scanningStatus?.stringValue = ""
            sender.title = "Scan".localized
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
        peripheralInvalidCache.removeAll()
        Logger.debug("\(peripheralCache)")

        let list = cbCentralManager?.retrieveConnectedPeripherals(withServices: [
            NeewerLightConstant.Constants.NeewerBleServiceUUID
        ])
        if let safeList = list {
            for peripheral in safeList {
                if let services = peripheral.services {
                    guard
                        let neewerService: CBService = services.first(where: {
                            $0.uuid == NeewerLightConstant.Constants.NeewerBleServiceUUID
                        })
                    else {
                        continue
                    }
                    advancePeripheralToDevice(
                        peripheral: peripheral, service: neewerService, updateUI: false,
                        addNew: scanningNewLightMode)
                }
            }
        }

        self.statusItemIcon = .off
        updateUI()
        cbCentralManager?.scanForPeripherals(
            withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
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
        scanningStatus?.stringValue = "Scan New Lights".localized + dots
    }

    @objc func handleURLEvent(
        _ event: NSAppleEventDescriptor?, withReplyEvent: NSAppleEventDescriptor?
    ) {
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
            let displayName = $0.device.userLightName.value.isEmpty ? $0.device.nickName : $0.device.userLightName.value
            let name =
                optKeyPressed
                ? "\(displayName) - \($0.device.identifier) - \($0.device.rawName)"
                : displayName
            let item = NSMenuItem(
                title: name, action: #selector(self.showWindowAction(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(
                systemSymbolName: $0.isON ? "lightbulb" : "lightbulb.slash",
                accessibilityDescription: "Light".localized)
            item.tag = lightTag
            appMenu.insertItem(item, at: 2)
        }
    }

    @MainActor
    public func updateUI() {
        statusItem.button?.alignment = .center
        statusItem.button?.imagePosition = .imageOverlaps

        // make view items order stable
        viewObjects.sort { $0.deviceIdentifier > $1.deviceIdentifier }
        collectionView.reloadData()

        let deviceIdentifiers: [String] = mylightTableView.selectedRowIndexes.compactMap {
            rowIndex in
            guard rowIndex >= 0 && rowIndex < viewObjects.count else {
                return nil  // Ignore this index as it's out of the bounds of the array
            }
            return viewObjects[rowIndex].deviceIdentifier
        }

        mylightTableView.reloadData()
        var newIndexSet = IndexSet()
        for (index, item) in viewObjects.enumerated()
        where deviceIdentifiers.contains(item.deviceIdentifier) {
            newIndexSet.insert(index)
        }
        mylightTableView.selectRowIndexes(newIndexSet, byExtendingSelection: false)
        mylightTableView.enclosingScrollView?.display()
        mylightTableView.display()

        scanTableView.reloadData()

        refreshMusicLightList()
    }

    func forgetLight(_ light: NeewerLight) {
        Logger.info(LogTag.click, "do forget light \(light.getConfig(true))")
        var found = false
        for (index, viewObj) in viewObjects.enumerated()
        where viewObj.device.identifier == light.identifier {
            viewObjects.remove(at: index)
            found = true
            break
        }
        if found {
            saveLightsToDisk()
            Task { @MainActor in
                self.updateUI()
            }
        }
    }

    func advancePeripheralToDevice(
        peripheral: CBPeripheral, service: CBService, updateUI: Bool, addNew: Bool
    ) {
        if let characteristics = service.characteristics {
            guard
                let characteristic1: CBCharacteristic = characteristics.first(where: {
                    $0.uuid == NeewerLightConstant.Constants.NeewerDeviceCtlCharacteristicUUID
                })
            else {
                Logger.debug("NeewerGattCharacteristicUUID not found")
                return
            }

            guard
                let characteristic2: CBCharacteristic = characteristics.first(where: {
                    $0.uuid == NeewerLightConstant.Constants.NeewerGattCharacteristicUUID
                })
            else {
                Logger.debug("NeewerGattCharacteristicUUID not found")
                return
            }

            let identifier = "\(peripheral.identifier)"

            var update = updateUI
            // Logger.info("advance peripheral to device \(peripheral) \(service)")
            var found = false
            if let targetViewObject = viewObjects.first(where: { $0.deviceIdentifier == identifier }
            ) {
                found = true
                if targetViewObject.device.peripheral == nil {
                    targetViewObject.device.setPeripheral(
                        peripheral, characteristic1, characteristic2)
                }
                targetViewObject.device.startLightOnNotify()
            }

            if !found {
                if addNew {
                    if scanningViewObjects.contains(where: { $0.deviceIdentifier == identifier }) {
                        Logger.debug("already added")
                    } else {
                        let light: NeewerLight = NeewerLight(
                            peripheral, characteristic1, characteristic2)
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
                Task { @MainActor in
                    self.updateUI()
                }
            }
        }
    }

    func grayoutLightViewObject(_ identifier: UUID) {
        if let targetViewObject = viewObjects.first(where: {
            $0.deviceIdentifier == "\(identifier)"
        }) {
            Logger.info("grayoutLightViewObject \(identifier)")
            targetViewObject.device.setPeripheral(nil, nil, nil)
            Task { @MainActor in
                self.updateUI()
            }
        }
    }

    // MARK: - Settings View

    func refreshSettingsView() {
        view4.refresh()
    }

}

extension AppDelegate: NSCollectionViewDelegate, NSCollectionViewDataSource {

    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int)
        -> Int
    {
        return viewObjects.count
    }

    func collectionView(
        _ itemForRepresentedObjectAtcollectionView: NSCollectionView,
        itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {

        let item = collectionView.makeItem(
            withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "CollectionViewItem"),
            for: indexPath)

        if let collectionViewItem = item as? CollectionViewItem {
            let viewObject = viewObjects[indexPath.section + indexPath.item]
            viewObject.view = collectionViewItem
            collectionViewItem.updateWithViewObject(viewObject)
        }

        return item
    }
}

extension AppDelegate: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {

        switch central.state {
        case .unauthorized:
            Logger.debug(LogTag.bluetooth, "authorization: \(central.authorization)")
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
            Logger.debug(LogTag.bluetooth, "powered on")
            central.scanForPeripherals(withServices: nil, options: nil)
            // scanAction(self)
            self.scanning = true
        case .poweredOff:
            central.stopScan()
            Logger.debug(LogTag.bluetooth, "powered off")
            self.scanning = false
        case .resetting:
            Logger.debug(LogTag.bluetooth, "resetting")
        @unknown default: break
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any], rssi RSSI: NSNumber
    ) {
        guard let name = peripheral.name else { return }
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

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        Logger.info(
            LogTag.bluetooth,
            "didFailToConnect peripheral \(peripheral) error \(String(describing: error))")
        if peripheralCache[peripheral.identifier] != nil {
            peripheral.delegate = nil
            peripheralCache.removeValue(forKey: peripheral.identifier)
        }
        grayoutLightViewObject(peripheral.identifier)
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        Logger.info(
            LogTag.bluetooth,
            "didDisconnectPeripheral peripheral \(peripheral) error \(String(describing: error))")
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

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService])
    {
        // Logger.info("A peripheral: \(peripheral.name!) didModifyServices \(invalidatedServices)")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            guard
                let neewerService: CBService = services.first(where: {
                    $0.uuid == NeewerLightConstant.Constants.NeewerBleServiceUUID
                })
            else {
                cbCentralManager?.cancelPeripheralConnection(peripheral)
                peripheralInvalidCache[peripheral.identifier] = true
                if peripheralCache[peripheral.identifier] != nil {
                    peripheral.delegate = nil
                    peripheralCache.removeValue(forKey: peripheral.identifier)
                }
                return
            }
            Logger.info(LogTag.bluetooth, "A Valid Neewer Light Found: \(peripheral) \(services)")
            // discover characteristics of services
            peripheral.discoverCharacteristics(nil, for: neewerService)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {

        advancePeripheralToDevice(
            peripheral: peripheral, service: service, updateUI: true, addNew: scanningNewLightMode)
    }
}

extension AppDelegate: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int {
        // Return the number of rows based on your data source count.
        if tableView == mylightTableView {
            return viewObjects.count
        } else if tableView == scanTableView {
            return scanningViewObjects.count
        } else if let scrollView = musicLightListView,
                  tableView == scrollView.documentView as? NSTableView {
            return viewObjects.count
        }
        return 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        // Example: Creating a simple NSTextField as a cell view
        if tableView == mylightTableView {
            let cellIdentifier = NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.0")

            if let cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil)
                as? MyLightTableCellView
            {
                // Assuming "YourModel" has a property named "name" to display
                let viewObj = viewObjects[row]
                cellView.titleLabel?.stringValue =
                    "\(viewObj.device.nickName) (\(viewObj.device.rawName))"
                cellView.subtitleLabel?.stringValue = viewObj.device.userLightName.value
                cellView.iconImageView?.image =
                    ContentManager.shared.fetchCachedLightImage(lightType: viewObj.device.lightType)
                    ?? (viewObj.device.productId.flatMap { ContentManager.shared.fetchCachedLightImage(productId: $0) })
                    ?? NSImage(named: "defaultLightImage")
                cellView.button?.tag = row
                cellView.button?.title = "Forget".localized
                cellView.button?.action = #selector(forgetAction(_:))
                cellView.button?.target = self
                if debugFakeLights {
                    cellView.isConnected = true
                } else {
                    cellView.isConnected = viewObj.deviceConnected
                }
                if !viewObj.hasMAC {
                    cellView.titleLabel?.stringValue = "%@ (missing MAC❗️)".localized(viewObj.device.nickName)
                }
                cellView.light = viewObj.device
                return cellView
            }
        } else if tableView == scanTableView {
            let cellIdentifier = NSUserInterfaceItemIdentifier("AutomaticTableColumnIdentifier.0")

            if let cellView = tableView.makeView(withIdentifier: cellIdentifier, owner: nil)
                as? MyLightTableCellView
            {
                // Assuming "YourModel" has a property named "name" to display
                let viewObj = scanningViewObjects[row]
                cellView.iconImageView?.image =
                    ContentManager.shared.fetchCachedLightImage(lightType: viewObj.device.lightType)
                    ?? (viewObj.device.productId.flatMap { ContentManager.shared.fetchCachedLightImage(productId: $0) })
                    ?? NSImage(named: "defaultLightImage")
                cellView.titleLabel?.stringValue = viewObj.device.rawName
                cellView.subtitleLabel?.stringValue = viewObj.device.nickName
                cellView.button?.tag = row
                cellView.button?.title = "Connect".localized
                cellView.button?.action = #selector(connnectNewLightAction(_:))
                cellView.button?.target = self
                cellView.light = viewObj.device
                return cellView
            }
        } else if let scrollView = musicLightListView,
                  tableView == scrollView.documentView as? NSTableView {
            guard row < viewObjects.count else { return nil }
            let viewObj = viewObjects[row]
            let cellId = musicLightListId
            let cellView: NSTableCellView
            if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? NSTableCellView {
                cellView = reused
            } else {
                cellView = NSTableCellView()
                cellView.identifier = cellId
                let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(musicLightCheckboxClicked(_:)))
                checkbox.font = NSFont.systemFont(ofSize: 11)
                checkbox.autoresizingMask = [.width]
                cellView.addSubview(checkbox)
            }
            if let checkbox = cellView.subviews.first as? NSButton {
                let name = viewObj.device.userLightName.value.isEmpty
                    ? viewObj.device.nickName : viewObj.device.userLightName.value
                checkbox.title = name
                checkbox.tag = row
                checkbox.state = viewObj.device.followMusic ? .on : .off
                checkbox.frame = NSRect(x: 2, y: 0, width: 130, height: 22)
                checkbox.toolTip = viewObj.deviceConnected ? "Connected".localized : "Disconnected".localized
                checkbox.isEnabled = viewObj.deviceConnected
            }
            return cellView
        }
        return nil
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if let scrollView = musicLightListView,
           tableView == scrollView.documentView as? NSTableView {
            return false
        }
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

    func isUserLightNameUsed(_ text: String, dev: NeewerLight?) -> Bool {
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

//    @IBAction func renameAction(_ sender: NSButton) {
//        let rowIndex = sender.tag
//        // Retrieve the corresponding object from your data source
//        if rowIndex >= 0 && rowIndex < viewObjects.count {
//            Logger.info(LogTag.click, "rename light")
//            let viewObject = viewObjects[rowIndex]
//            if renameVC != nil {
//                renameVC = nil
//            }
//            renameVC = RenameViewController()
//            renameVC?.onOK = { [weak self] text in
//                guard let safeSelf = self else { return true }
//                if safeSelf.isUserLightNameUsed(text, dev: viewObject.device) {
//                    Logger.info(LogTag.click, "rename light, name conflict.")
//                    return false
//                }
//                viewObject.device.userLightName.value = "\(text)"
//                safeSelf.saveLightsToDisk()
//                safeSelf.updateUI()
//                return true
//            }
//            renameVC?.setCurrentValue(viewObject.device.userLightName.value)
//            self.window?.beginSheet(renameVC!.sheetWindow, completionHandler: nil)
//        }
//    }

    @IBAction func forgetAction(_ sender: NSButton) {
        let rowIndex = sender.tag
        // Retrieve the corresponding object from your data source
        if rowIndex >= 0 && rowIndex < viewObjects.count {
            Logger.info(LogTag.click, "forget light")
            let viewObject = viewObjects[rowIndex]
            let alert = NSAlert()
            alert.icon =
                ContentManager.shared.fetchCachedLightImage(lightType: viewObject.device.lightType)
                ?? (viewObject.device.productId.flatMap { ContentManager.shared.fetchCachedLightImage(productId: $0) })
                ?? NSImage(named: "defaultLightImage")
            alert.messageText = "Remove light \"%@\"".localized(viewObject.deviceName)
            alert.informativeText = "Are you sure you want to remove this light from your library?".localized
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Yes".localized)
            alert.addButton(withTitle: "No".localized)

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                self.forgetLight(viewObject.device)
            case .alertSecondButtonReturn:
                Logger.info(LogTag.click, "forget light, cancel")
            default:
                break
            }
        }
    }
}

extension AppDelegate: Sparkle.SUUpdaterDelegate {

    func updaterMayCheck(forUpdates updater: SUUpdater) -> Bool {
        return true
    }
    func updater(_ updater: SUUpdater, failedToDownloadUpdate item: SUAppcastItem, error: any Error)
    {
        Logger.error("updater failedToDownloadUpdate error: \(error)")
    }

    func updater(_ updater: SUUpdater, didDownloadUpdate item: SUAppcastItem) {
        Logger.info("updater didDownloadUpdate \(item)")
    }

    func updater(_ updater: SUUpdater, didAbortWithError error: any Error) {
        Logger.error("updater didAbortWithError \(error)")
    }

    func updater(_ updater: SUUpdater, didFinishLoading appcast: SUAppcast) {
        Logger.info("updater didFinishLoading \(appcast)")
        if let items = appcast.items {
            for item in items {
                if let app = item as? SUAppcastItem {
                    Logger.info("app.title \(app.title ?? "")")
                    Logger.info("app.dateString \(app.dateString ?? "")")
                    Logger.info("app.displayVersionString \(app.displayVersionString ?? "")")
                    Logger.info("app.versionString \(app.versionString ?? "")")
                    Logger.info("app.itemDescription \(app.itemDescription ?? "")")
                }
            }
        }
    }
}
