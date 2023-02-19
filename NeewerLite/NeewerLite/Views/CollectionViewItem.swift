//
//  CollectionViewItem.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class CollectionViewItem: NSCollectionViewItem, NSTextFieldDelegate, ColorWheelDelegate, NSTabViewDelegate {

    @IBOutlet var lightModeButton1: NSSegmentedControl!
    @IBOutlet var lightModeButton: NSSegmentedControl!
    @IBOutlet weak var lightModeTabView: NSTabView!
    @IBOutlet weak var nameField: NSTextField!
    @IBOutlet weak var switchButton: NSSwitch!

    // CCT Controls
    @IBOutlet weak var cctBrrValueField: NSTextField!
    @IBOutlet weak var cctCctValueField: NSTextField!
    @IBOutlet weak var cctBrrSlide: NSSlider!
    @IBOutlet weak var cctCctSlide: NSSlider!

    // HSI Controls
    @IBOutlet weak var hsiBrrValueField: NSTextField!
    @IBOutlet weak var hsiSatValueField: NSTextField!
    @IBOutlet weak var hsiColorWheel: ColorWheel!
    @IBOutlet weak var hsiBrrSlide: NSSlider!
    @IBOutlet weak var hsiSatSlide: NSSlider! // Saturation
    // @IBOutlet weak var hsi_cctValueField: NSTextField!
    // @IBOutlet weak var hsi_cctSlide: NSSlider!

    // Scene Controls
    @IBOutlet weak var sceneTabView: NSTabView!
    @IBOutlet weak var sceneModeButton1: NSButton!
    @IBOutlet weak var sceneModeButton2: NSButton!
    @IBOutlet weak var sceneModeButton3: NSButton!
    @IBOutlet weak var scenebrrSlide: NSSlider!
    @IBOutlet weak var scenebrrValueField: NSTextField!
    @IBOutlet weak var followMusicButton: NSButton!

    @IBOutlet weak var scene1Button: NSButton!
    @IBOutlet weak var scene2Button: NSButton!
    @IBOutlet weak var scene3Button: NSButton!
    @IBOutlet weak var scene4Button: NSButton!
    @IBOutlet weak var scene5Button: NSButton!
    @IBOutlet weak var scene6Button: NSButton!
    @IBOutlet weak var scene7Button: NSButton!
    @IBOutlet weak var scene8Button: NSButton!
    @IBOutlet weak var scene9Button: NSButton!

    private var currentSceneIndex: UInt8 = 0
    private var tabView1: NSTabViewItem?
    private var tabView2: NSTabViewItem?

    var currentScene: UInt8 {
        get {
            if currentSceneIndex == 0 {
                if let dev = device {
                    currentSceneIndex = dev.channel.value
                } else {
                    currentSceneIndex = 1
                }
            }
            return currentSceneIndex
        }
        set {
            if (1...9).contains(newValue) {
                currentSceneIndex = newValue
                updateScene(false)
            }
        }
    }

    var nameEditor: NSTextField?

    var device: NeewerLight? {
        didSet {
            if let dev = device {
                lightModeButton1.removeFromSuperview()
                lightModeButton.removeFromSuperview()

                if dev.supportRGB {
                    lightModeButton.frame = NSRect(x: 242, y: 240, width: 163, height: 24)
                    self.view.addSubview(lightModeButton)
                } else {
                    lightModeButton1.frame = NSRect(x: 293, y: 240, width: 61, height: 24)
                    self.view.addSubview(lightModeButton1)
                }

                self.cctCctSlide.minValue = Double(dev.minCCT)
                self.cctCctSlide.maxValue = Double(dev.maxCCT)

                updateDeviceColorToWheel()
            }
        }
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.borderWidth = isSelected ? 5.0 : 1.0
        }
    }

    var image: NSImage? {
        didSet {
            guard isViewLoaded else { return }
            if let image = image {
                imageView?.image = image
                let width: CGFloat = (imageView?.frame.size.height)! * image.size.width / image.size.height
                var frame = imageView?.frame
                frame?.size.width = width
                imageView?.frame = frame!
            } else {
                imageView?.image = nil
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.2).cgColor
        view.layer?.borderColor = NSColor.lightGray.withAlphaComponent(0.6).cgColor
        view.layer?.borderWidth = 1.0
        view.layer?.cornerRadius = 10.0

        self.followMusicButton.state = .off
        self.lightModeButton1.selectedSegment = 0
        self.lightModeButton.selectedSegment = 0
        self.lightModeTabView.selectTabViewItem(at: 0)

        // CCT tab
        self.cctBrrSlide.minValue = 0.0
        self.cctBrrSlide.maxValue = 100.0 // do not exceed 100.0 here, LED only takes 100.0

        self.cctCctSlide.minValue = 32.0
        self.cctCctSlide.maxValue = 56.0 // do not exceed 100.0 here

        self.cctCctValueField.stringValue = ""
        self.cctBrrValueField.stringValue = ""

        // HSI tab
        self.hsiColorWheel.delegate = self
        self.hsiBrrSlide.minValue = 0.0
        self.hsiBrrSlide.maxValue = 100.0 // do not exceed 100.0 here, LED only takes 100.0
        self.hsiSatSlide.minValue = 0.0
        self.hsiSatSlide.maxValue = 100.0
        self.hsiSatValueField.stringValue = ""
        self.hsiBrrValueField.stringValue = ""

        // Scene tab
        self.scenebrrSlide.minValue = 0.0
        self.scenebrrSlide.maxValue = 100.0 // do not exceed 100.0 here, LED only takes 100.0
        self.scenebrrSlide.allowsTickMarkValuesOnly = true

        resetSceneButtons()
    }

    @IBAction func modeAction(_ sender: NSSegmentedControl) {
        if [0, 1, 2].contains(sender.selectedSegment) {
            lightModeTabView.selectTabViewItem(at: sender.selectedSegment)
        }
    }

    @IBAction func toggleFollowMusicAction(_ sender: NSButton) {
        if let dev = device {
            Logger.debug("sender.state= \(sender.state)")
            dev.followMusic = sender.state == .on
            Logger.debug("dev.followMusic= \(dev.followMusic)")
            if let app = NSApp.delegate as? AppDelegate {
                app.updateAudioDriver()
            }
        }
    }

    @IBAction func moreAction(_ sender: NSButton) {
        let menu = NSMenu(title: "MoreMenu")
        let item = NSMenuItem(title: NSLocalizedString("Rename Light", comment: ""),
                              action: #selector(renameAction(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)

        var location = sender.bounds.origin
        location.y += 20

        menu.popUp(positioning: menu.item(at: 0), at: location, in: sender)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if self.nameEditor == nil {
            return
        }
        let newName = self.nameEditor!.stringValue
        self.nameEditor!.removeFromSuperview()
        self.nameEditor = nil
        self.nameField.isHidden = false
        if let dev = device {
            dev.userLightName = newName
        }
        self.nameField.stringValue = newName
    }

    @objc func renameAction(_ sender: Any) {
        nameEditor = NSTextField(frame: self.nameField.frame)
        nameEditor!.delegate = self

        if let dev = device {
            nameEditor!.stringValue = dev.userLightName
        }

        self.view.addSubview(nameEditor!)
        self.nameField.isHidden = true
    }

    func updateCCTValueField() {
        if let dev = device {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let str1 = NSAttributedString(string: "\(dev.cctValue)00",
                                          attributes: [
                                                .paragraphStyle: paragraph,
                                                .font: NSFont.monospacedSystemFont(ofSize: 27, weight: .regular)
                                            ])
            let str2 = NSAttributedString(string: "K",
                                          attributes: [
                                                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                                                .paragraphStyle: paragraph
                                          ])
            let str = NSMutableAttributedString(attributedString: str1)
            str.append(str2)
            cctCctValueField.attributedStringValue = str
        }
    }

    func updateBRRValueField() {
        if let dev = device {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let str1 = NSAttributedString(string: "\(dev.brrValue)",
                                          attributes: [
                                            .font: NSFont.monospacedSystemFont(ofSize: 27, weight: .regular),
                                            .paragraphStyle: paragraph
                                          ])
            let str2 = NSAttributedString(string: "%",
                                          attributes: [
                                            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
                                            .paragraphStyle: paragraph
                                          ])
            let str = NSMutableAttributedString(attributedString: str1)
            str.append(str2)
            cctBrrValueField.attributedStringValue = str
        }
    }

    @IBAction func slideAction(_ sender: NSSlider) {
        if sender == cctBrrSlide {
            if let dev = device {
                dev.setBRRLightValues(CGFloat(cctBrrSlide.doubleValue) / 100.0)
                scenebrrSlide.doubleValue = Double(dev.brrValue)
                updateBRRValueField()
            }
        } else if sender == cctCctSlide {
            if let dev = device {
                dev.setCCTLightValues(CGFloat(cctCctSlide.doubleValue), CGFloat(hsiBrrSlide.doubleValue) / 100.0)
                updateCCTValueField()
            }
        } else if sender == hsiBrrSlide {
            if let dev = device {
                dev.setBRRLightValues(CGFloat(hsiBrrSlide.doubleValue) / 100.0)
                hsiBrrValueField.stringValue = "\(dev.brrValue)"
                scenebrrSlide.doubleValue = Double(dev.brrValue)
            }
        } else if sender == hsiSatSlide {
            if let dev = device {
                hsiColorWheel.setSaturation(CGFloat(hsiSatSlide.doubleValue/100.0))
                dev.setRGBLightValues(hsiColorWheel.color.hueComponent, hsiColorWheel.color.saturationComponent)
                hsiSatValueField.stringValue = "\(dev.satruationValue)"
            }
        } else if sender == scenebrrSlide {
            if let dev = device {
                updateScene(false)
                hsiBrrSlide.doubleValue = Double(dev.brrValue)
            }
        }
    }

    @IBAction func toggleAction(_ sender: Any) {
        if let dev = device {
            if dev.isOn.value {
                dev.sendPowerOffRequest()
            } else {
                dev.sendPowerOnRequest()
            }
        }
    }

    @IBAction func changeModeAction(_ sender: NSButton) {
        resetSceneModeButtons()
        sender.state = .on
        switch sender.tag {
            case 0:
                sceneTabView.selectTabViewItem(at: 0)
                sceneModeButton1.state = .on
                sceneModeButton1.alphaValue = 1.0
            case 1:
                sceneTabView.selectTabViewItem(at: 1)
                sceneModeButton2.state = .on
                sceneModeButton2.alphaValue = 1.0
            case 2:
                sceneTabView.selectTabViewItem(at: 2)
                sceneModeButton3.state = .on
                sceneModeButton3.alphaValue = 1.0
            default:
                sceneTabView.selectTabViewItem(at: 0)
                sceneModeButton1.state = .on
                sceneModeButton1.alphaValue = 1.0
        }
        updateScene(true)
    }

    func resetSceneModeButtons() {
        sceneModeButton1.state = .off
        sceneModeButton2.state = .off
        sceneModeButton3.state = .off
        sceneModeButton1.alphaValue = 0.4
        sceneModeButton2.alphaValue = 0.4
        sceneModeButton3.alphaValue = 0.4
    }

    func resetSceneButtons() {
        resetSceneModeButtons()

        scene1Button.state = .off
        scene2Button.state = .off
        scene3Button.state = .off
        scene4Button.state = .off
        scene5Button.state = .off
        scene6Button.state = .off
        scene7Button.state = .off
        scene8Button.state = .off
        scene9Button.state = .off

        scene1Button.alphaValue = 0.4
        scene2Button.alphaValue = 0.4
        scene3Button.alphaValue = 0.4
        scene4Button.alphaValue = 0.4
        scene5Button.alphaValue = 0.4
        scene6Button.alphaValue = 0.4
        scene7Button.alphaValue = 0.4
        scene8Button.alphaValue = 0.4
        scene9Button.alphaValue = 0.4
    }

    @IBAction func channelAction(_ sender: NSButton) {
        resetSceneButtons()
        sender.state = .on
        sender.alphaValue = 1
        currentScene = UInt8(sender.tag)
    }

    func updateScene(_ changeModeOnly: Bool) {
        if lightModeTabView.selectedTabViewItem != lightModeTabView.tabViewItem(at: 2) {
            return
        }
        if let dev = device {
            if dev.supportRGB {
                if changeModeOnly {
                    if dev.lightMode != .SCEMode {
                        dev.setScene(currentScene, brightness: CGFloat(scenebrrSlide.doubleValue))
                        scenebrrValueField.stringValue = "\(dev.brrValue)"
                    }
                } else {
                    dev.setScene(currentScene, brightness: CGFloat(scenebrrSlide.doubleValue))
                    scenebrrValueField.stringValue = "\(dev.brrValue)"
                }

            }
        }
    }

    func updateDeviceColorToWheel() {
        if let dev = device {
            if dev.supportRGB {
                // colorWheel does not need to consider brightness. Alway pass in 1.0
                self.hsiColorWheel.setViewColor(NSColor(calibratedHue: CGFloat(dev.hueValue) / 360.0,
                                                        saturation: CGFloat(dev.satruationValue) / 100.0,
                                                        brightness: 1.0,
                                                        alpha: 1.0))
            }
        }
    }

    func updateDeviceStatus() {
        guard let dev = device else {
            self.cctCctValueField.stringValue = ""
            self.cctBrrValueField.stringValue = ""
            self.hsiBrrValueField.stringValue = ""
            self.lightModeTabView.selectTabViewItem(at: 0)
            self.lightModeButton!.selectedSegment = 0
            resetSceneButtons()
            return
        }

        if dev.isOn.value {
            self.switchButton.state = .on
        } else {
            self.switchButton.state = .off
        }

        // Mode tab updates
        if dev.supportRGB {
            if dev.lightMode == .CCTMode {
                lightModeTabView.selectTabViewItem(at: 0)
                lightModeButton.selectedSegment = 0
            } else if dev.lightMode == .HSIMode {
                lightModeTabView.selectTabViewItem(at: 1)
                lightModeButton.selectedSegment = 1
            } else {
                lightModeTabView.selectTabViewItem(at: 2)
                lightModeButton.selectedSegment = 2
            }
        } else {
            lightModeTabView.selectTabViewItem(at: 0)
            lightModeButton1.selectedSegment = 0
        }

        // CCT updates
        updateCCTValueField()
        updateBRRValueField()
        cctCctSlide.doubleValue = Double(dev.cctValue)
        cctBrrSlide.doubleValue = Double(dev.brrValue)

        if dev.supportRGB {
            // HSI updates
            hsiBrrSlide.doubleValue = Double(dev.brrValue)
            hsiBrrValueField.stringValue = "\(dev.brrValue)"
            hsiSatSlide.doubleValue = Double(dev.satruationValue)
            hsiSatValueField.stringValue = "\(dev.satruationValue)"

            updateDeviceColorToWheel()

            // Scene updates
            scenebrrSlide.doubleValue = Double(dev.brrValue)

            resetSceneButtons()

            if dev.channel.value >= 1 && dev.channel.value <= 3 {
                sceneModeButton1.state = .on
                sceneModeButton1.alphaValue = 1.0
                sceneTabView.selectTabViewItem(at: 0)
            } else if dev.channel.value >= 4 && dev.channel.value <= 6 {
                sceneModeButton2.state = .on
                sceneModeButton2.alphaValue = 1.0
                sceneTabView.selectTabViewItem(at: 1)
            } else if dev.channel.value >= 7 && dev.channel.value <= 9 {
                sceneModeButton3.state = .on
                sceneModeButton3.alphaValue = 1.0
                sceneTabView.selectTabViewItem(at: 2)
            }

            switch dev.channel.value {
                case 1:
                    scene1Button.state = .on
                    scene1Button.alphaValue = 1
                case 2:
                    scene2Button.state = .on
                    scene2Button.alphaValue = 1
                case 3:
                    scene3Button.state = .on
                    scene3Button.alphaValue = 1
                case 4:
                    scene4Button.state = .on
                    scene4Button.alphaValue = 1
                case 5:
                    scene5Button.state = .on
                    scene5Button.alphaValue = 1
                case 6:
                    scene6Button.state = .on
                    scene6Button.alphaValue = 1
                case 7:
                    scene7Button.state = .on
                    scene7Button.alphaValue = 1
                case 8:
                    scene8Button.state = .on
                    scene8Button.alphaValue = 1
                case 9:
                    scene9Button.state = .on
                    scene9Button.alphaValue = 1
                default:
                    scene1Button.state = .off
                    scene1Button.alphaValue = 0.4
            }
        }
    }

    func updateWithViewObject(_ viewObj: DeviceViewObject) {
        device = viewObj.device
        self.image = viewObj.deviceImage
        self.nameField.stringValue = viewObj.device.userLightName
        self.nameField.toolTip = "\(viewObj.device.rawName)\n\(viewObj.deviceIdentifier)"
        updateDeviceStatus()
    }

    func updateHueAndSaturationAndBrightness(_ hue: CGFloat,
                                             saturation: CGFloat,
                                             brightness: CGFloat,
                                             updateWheel: Bool) {
        if let dev = device {
            if dev.supportRGB {
                dev.setRGBLightValues(hue, saturation, brightness)
                self.hsiSatSlide.doubleValue = Double(saturation * 100.0)
                self.hsiSatValueField.stringValue = "\(dev.satruationValue)"
                self.hsiBrrSlide.doubleValue =  Double(brightness * 100.0)
                if updateWheel {
                    updateDeviceColorToWheel()
                }
            }
        }
    }

    func hueAndSaturationSelected(_ hue: CGFloat, saturation: CGFloat) {
        updateHueAndSaturationAndBrightness(hue,
                                            saturation: saturation,
                                            brightness: hsiBrrSlide.doubleValue / 100.0,
                                            updateWheel: false)
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if tabView == lightModeTabView {
            if let dev = device {
                if tabViewItem == tabView.tabViewItem(at: 0) {
                    // CCT mode
                    dev.setCCTLightValues(CGFloat(dev.cctValue) / 100.0, CGFloat(dev.brrValue) / 100.0)
                } else if tabViewItem == tabView.tabViewItem(at: 1) {
                    // HSI mode
                    if dev.supportRGB {
                        dev.setRGBLightValues(hsiColorWheel.color.hueComponent, hsiColorWheel.color.saturationComponent)
                    }
                } else {
                    // scene mode
                    updateScene(true)
                }
            }
        }
    }
}
