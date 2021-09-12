//
//  CollectionViewItem.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class CollectionViewItem: NSCollectionViewItem, NSTextFieldDelegate, ColorWheelDelegate, NSTabViewDelegate {

    @IBOutlet weak var lightModeTabView: NSTabView!
    @IBOutlet weak var nameField: NSTextField!
    @IBOutlet weak var switchButton: NSSwitch!
    @IBOutlet weak var brrSlide: NSSlider!
    @IBOutlet weak var cctSlide: NSSlider!
    @IBOutlet weak var brrValueField: NSTextField!
    @IBOutlet weak var cctValueField: NSTextField!
    @IBOutlet weak var colorWheel: ColorWheel!

    @IBOutlet weak var sceneTabView: NSTabView!
    @IBOutlet weak var sceneModeButton1: NSButton!
    @IBOutlet weak var sceneModeButton2: NSButton!
    @IBOutlet weak var sceneModeButton3: NSButton!
    @IBOutlet weak var scenebrrSlide: NSSlider!
    @IBOutlet weak var scenebrrValueField: NSTextField!

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

    var currentScene: UInt8 {
        set {
            if newValue >= 1 && newValue <= 9 {
                currentSceneIndex = newValue
                updateScene()
            }
        }
        get {
            if currentSceneIndex == 0 {
                if let dev = self.device {
                    currentSceneIndex = dev.channel.value
                } else {
                    currentSceneIndex = 1
                }
            }
            return currentSceneIndex
        }
    }

    var nameEditor: NSTextField?

    var device: NeewerLight? {
        didSet {
            if let dev = self.device {
                dev.isOn.bind { (on) in
                    DispatchQueue.main.async {
                        self.updateDeviceStatus()
                    }
                }
                dev.channel.bind { (ch) in
                    DispatchQueue.main.async {
                        self.updateDeviceStatus()
                    }
                }
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
                let nw : CGFloat = (imageView?.frame.size.height)! * image.size.width / image.size.height
                var frame = imageView?.frame
                frame?.size.width = nw
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

        self.colorWheel.delegate = self

        self.brrSlide.minValue = 0.0
        self.brrSlide.maxValue = 100.0 // do not exceed 100.0 here, LED only takes 100.0
        self.brrSlide.allowsTickMarkValuesOnly = true
        self.brrSlide.numberOfTickMarks = 100

        self.cctSlide.minValue = 32.0
        self.cctSlide.maxValue = 56.0 // do not exceed 100.0 here
        self.cctSlide.allowsTickMarkValuesOnly = true
        self.cctSlide.numberOfTickMarks = 24

        self.scenebrrSlide.minValue = 0.0
        self.scenebrrSlide.maxValue = 100.0 // do not exceed 100.0 here, LED only takes 100.0
        self.scenebrrSlide.allowsTickMarkValuesOnly = true
        self.scenebrrSlide.numberOfTickMarks = 100

        resetSceneButtons()

        self.brrValueField.stringValue = ""
        self.cctValueField.stringValue = ""
        self.scenebrrValueField.stringValue = ""
    }

    @IBAction func moreAction(_ sender: NSButton)
    {
        let menu = NSMenu(title: "MoreMenu")
        let item = NSMenuItem(title: NSLocalizedString("Rename Light", comment: ""), action: #selector(renameAction(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)

        var location = sender.bounds.origin
        location.y += 20

        menu.popUp(positioning: menu.item(at: 0), at: location, in: sender)
    }

    func controlTextDidEndEditing(_ obj: Notification)
    {
        if self.nameEditor == nil {
            return
        }
        let newName = self.nameEditor!.stringValue
        self.nameEditor!.removeFromSuperview()
        self.nameEditor = nil
        self.nameField.isHidden = false
        if let dev = self.device {
            dev.deviceName = newName
        }
        self.nameField.stringValue = newName
    }

    @objc func renameAction(_ sender: Any)
    {
        nameEditor = NSTextField(frame: self.nameField.frame)
        nameEditor!.delegate = self

        if let dev = self.device {
            let name = dev.deviceName
            nameEditor!.stringValue = name.replacingOccurrences(of: "NEEWER-", with: "")
        }

        self.view.addSubview(nameEditor!);
        self.nameField.isHidden = true
    }

    @IBAction func slideAction(_ sender: NSSlider)
    {
        if sender == self.brrSlide {
            if let dev = self.device {
                dev.setBRRLightValues(CGFloat(self.brrSlide.doubleValue))
                self.brrValueField.stringValue = "\(dev.brrValue)"
                self.scenebrrSlide.doubleValue = Double(dev.brrValue)
            }
        }
        else if sender == self.cctSlide {
            if let dev = self.device {
                dev.setCCTLightValues(CGFloat(self.cctSlide.doubleValue), CGFloat(self.brrSlide.doubleValue))
                self.cctValueField.stringValue = "\(dev.cctValue)00K"
            }
        }
        else if sender == self.scenebrrSlide
        {
            if let dev = self.device {
                updateScene()
                self.brrSlide.doubleValue = Double(dev.brrValue)
            }
        }
    }

    @IBAction func toggleAction(_ sender: Any)
    {
        if let dev = self.device {
            if dev.isOn.value {
                dev.sendPowerOffRequest()
            } else {
                dev.sendPowerOnRequest()
            }
        }
    }

    @IBAction func changeModeAction(_ sender: NSButton)
    {
        sceneModeButton1.state = .off
        sceneModeButton2.state = .off
        sceneModeButton3.state = .off
        sender.state = .on
        switch sender.tag {
            case 0:
                sceneTabView.selectTabViewItem(at: 0)
            case 1:
                sceneTabView.selectTabViewItem(at: 1)
            case 2:
                sceneTabView.selectTabViewItem(at: 2)
            default:
                sceneTabView.selectTabViewItem(at: 0)
        }
        updateScene()
    }

    func resetSceneButtons()
    {
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

    @IBAction func channelAction(_ sender: NSButton)
    {
        resetSceneButtons()
        sender.state = .on
        sender.alphaValue = 1
        self.currentScene = UInt8(sender.tag)
    }

    func updateScene()
    {
        if lightModeTabView.selectedTabViewItem != lightModeTabView.tabViewItem(at: 1) {
            return
        }
        if let dev = self.device {
            dev.setScene(self.currentScene, brightness: CGFloat(self.scenebrrSlide.doubleValue))
            self.scenebrrValueField.stringValue = "\(dev.brrValue)"
        }
    }

    func updateDeviceStatus() {
        if let dev = self.device {
            if dev.isOn.value {
                self.switchButton.state = .on
            } else {
                self.switchButton.state = .off
            }

            self.brrValueField.stringValue = "\(dev.brrValue)"
            self.cctValueField.stringValue = "\(dev.cctValue)00K"
            self.brrSlide.doubleValue = Double(dev.brrValue)
            self.cctSlide.doubleValue = Double(dev.cctValue)
            self.scenebrrSlide.doubleValue = Double(dev.brrValue)

            // colorWheel does not need to consider brightness. Alway pass in 1.0
            self.colorWheel.setViewColor(NSColor(calibratedHue: CGFloat(dev.hueValue) / 360.0, saturation: CGFloat(dev.satruationValue) / 100.0, brightness: 1.0, alpha: 1.0))

            if dev.isSceneOn.value {
                self.lightModeTabView.selectTabViewItem(at: 1)
            } else {
                self.lightModeTabView.selectTabViewItem(at: 0)
            }

            resetSceneButtons()

            if dev.channel.value >= 1 && dev.channel.value <= 3 {
                self.sceneModeButton1.state = .on
                self.sceneTabView.selectTabViewItem(at: 0)
            }
            else if dev.channel.value >= 4 && dev.channel.value <= 6 {
                self.sceneModeButton2.state = .on
                self.sceneTabView.selectTabViewItem(at: 1)
            }
            else if dev.channel.value >= 7 && dev.channel.value <= 9 {
                self.sceneModeButton3.state = .on
                self.sceneTabView.selectTabViewItem(at: 2)
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
                    scene5Button.alphaValue = 1
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

        } else {
            self.brrValueField.stringValue = ""
            self.cctValueField.stringValue = ""
            self.lightModeTabView.selectTabViewItem(at: 0)
            resetSceneButtons()
        }
    }

    func updateWithViewObject(_ vo: DeviceViewObject) {
        self.device = vo.device
        self.image = vo.deviceImage
        self.nameField.stringValue = vo.deviceName
        self.nameField.toolTip = "\(vo.device.rawName)\n\(vo.deviceIdentifier)"
        updateDeviceStatus()
    }

    func hueAndSaturationSelected(_ hue: CGFloat, saturation: CGFloat) {
        if let dev = self.device {
            dev.setRGBLightValues(hue, saturation)
        }
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?)
    {
        if tabView == self.lightModeTabView {
            if let dev = self.device {
                if self.lightModeTabView.selectedTabViewItem == self.lightModeTabView.tabViewItem(at: 1) {
                    // scene mode
                    dev.isSceneOn.value = true
                    self.updateScene()
                } else {
                    dev.isSceneOn.value = false
                    if dev.lightMode == .CCTMode {
                        dev.setCCTLightValues(CGFloat(dev.cctValue), CGFloat(dev.brrValue))
                    } else {
                        dev.setRGBLightValues(self.colorWheel.color.hueComponent, self.colorWheel.color.saturationComponent)
                    }
                }
            }
        }
    }
}



