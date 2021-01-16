//
//  CollectionViewItem.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class CollectionViewItem: NSCollectionViewItem, NSTextFieldDelegate {

    @IBOutlet weak var nameField: NSTextField!
    @IBOutlet weak var switchButton: NSSwitch!
    @IBOutlet weak var ch1Button: NSButton!
    @IBOutlet weak var ch2Button: NSButton!
    @IBOutlet weak var ch3Button: NSButton!
    @IBOutlet weak var ch4Button: NSButton!
    @IBOutlet weak var ch5Button: NSButton!
    @IBOutlet weak var ch6Button: NSButton!
    @IBOutlet weak var ch7Button: NSButton!
    @IBOutlet weak var ch8Button: NSButton!
    @IBOutlet weak var brrSlide: NSSlider!
    @IBOutlet weak var cctSlide: NSSlider!
    @IBOutlet weak var brrValueField: NSTextField!
    @IBOutlet weak var cctValueField: NSTextField!

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
                var textFrame = nameField.frame
                textFrame.origin.x = NSMaxX(frame!) + 17
                textFrame.size.width = 480 - 65 - nw
                nameField.frame = textFrame
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

        self.brrSlide.minValue = 0.0
        self.brrSlide.maxValue = 100.0 // do not exceed 100.0 here, LED only takes 100.0
        self.brrSlide.allowsTickMarkValuesOnly = true
        self.brrSlide.numberOfTickMarks = 100

        self.cctSlide.minValue = 32.0
        self.cctSlide.maxValue = 56.0 // do not exceed 100.0 here
        self.cctSlide.allowsTickMarkValuesOnly = true
        self.cctSlide.numberOfTickMarks = 24

        self.brrValueField.stringValue = ""
        self.cctValueField.stringValue = ""
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

    @IBAction func channelAction(_ sender: Any)
    {
        if let dev = self.device {
            dev.sendReadRequest()
        }
    }

    @IBAction func slideAction(_ sender: NSSlider)
    {
        if sender == self.brrSlide || sender == self.cctSlide {
            if let dev = self.device {
                dev.setCCTLightValues(self.cctSlide.doubleValue, self.brrSlide.doubleValue)
                self.brrValueField.stringValue = "\(dev.brrValue)"
                self.cctValueField.stringValue = "\(dev.cctValue)00K"
            }
        }
    }

    func updateDeviceStatus() {
        if let dev = self.device {
            if dev.isOn.value {
                self.switchButton.state = .on
            } else {
                self.switchButton.state = .off
            }
            
            ch1Button.state = dev.channel.value == 1 ? .on : .off
            ch2Button.state = dev.channel.value == 2 ? .on : .off
            ch3Button.state = dev.channel.value == 3 ? .on : .off
            ch4Button.state = dev.channel.value == 4 ? .on : .off
            ch5Button.state = dev.channel.value == 5 ? .on : .off
            ch6Button.state = dev.channel.value == 6 ? .on : .off
            ch7Button.state = dev.channel.value == 7 ? .on : .off
            ch8Button.state = dev.channel.value == 8 ? .on : .off

            self.brrValueField.stringValue = "\(dev.brrValue)"
            self.cctValueField.stringValue = "\(dev.cctValue)00K"
            self.brrSlide.doubleValue = Double(dev.brrValue)
            self.cctSlide.doubleValue = Double(dev.cctValue)
        } else {
            self.brrValueField.stringValue = ""
            self.cctValueField.stringValue = ""
        }
    }

    func updateWithViewObject(_ vo: DeviceViewObject) {
        self.device = vo.device
        self.image = vo.deviceImage
        self.nameField.stringValue = vo.deviceName
        self.nameField.toolTip = "\(vo.device.rawName)\n\(vo.deviceIdentifier)"
        updateDeviceStatus()
    }
}

