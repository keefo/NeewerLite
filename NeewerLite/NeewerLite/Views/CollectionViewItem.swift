//
//  CollectionViewItem.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class CollectionViewItem: NSCollectionViewItem {

    @IBOutlet weak var nameField: NSTextField!
    @IBOutlet weak var identifierField: NSTextField!
    @IBOutlet weak var switchButton: NSSwitch!

    var device: NeewerLight?

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
                textFrame.size.width = 480 - 40 - 17
                nameField.frame = textFrame

                textFrame = identifierField.frame
                textFrame.origin.x = NSMaxX(frame!) + 17
                textFrame.size.width = 480 - 40 - 17
                identifierField.frame = textFrame
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
    }


    @IBAction func toggleAction(_ sender: Any)
    {
        if let dev = self.device {
            if dev.isOn {
                dev.powerOff()
            } else {
                dev.powerOn()
            }
        }
    }


    @IBAction func slideAction(_ sender: NSSlider)
    {
        Logger.info("sender= \(sender.intValue)")
        if let dev = self.device {
            dev.setLightCCT(Int(sender.intValue))
            dev.setLightBRR(Int(sender.intValue))
        }
    }

    func updateWithViewObject(_ vo: DeviceViewObject) {
        self.device = vo.device
        self.image = vo.deviceImage
        self.nameField.stringValue = vo.deviceName
        self.identifierField.stringValue = vo.deviceIdentifier
    }

}
