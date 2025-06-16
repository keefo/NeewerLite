//
//  CollectionViewItem.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Cocoa

class CollectionViewItem: NSCollectionViewItem, NSTextFieldDelegate, NSTabViewDelegate {

    @IBOutlet weak var lightModeTabView: NSTabView!
    @IBOutlet weak var nameField: NSTextField!
    @IBOutlet weak var switchButton: NSSwitch!

    private var renameVC: RenameViewController?
    private var imageFetchOperation: ImageFetchOperation?

    private var buildingView: Bool = false
    private var currentSceneIndex: UInt8 = 0
    private var tabView1: NSTabViewItem?
    private var tabView2: NSTabViewItem?
    var nameObservation: NSKeyValueObservation?
    private var overlay: BlockingOverlayView?
    private let valueTextColor: NSColor = NSColor.secondaryLabelColor

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
                imageView?.imageScaling = .scaleProportionallyUpOrDown
                imageView?.image = image
            } else {
                if let dev = device {
                    Logger.debug("missing image for lightType \(dev.lightType)")
                }
                imageView?.image = NSImage(named: "defaultLightImage")
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
        // self.followMusicButton.state = .off
    }

    @IBAction func moreAction(_ sender: NSButton) {
        let menu = NSMenu(title: "MoreMenu")
        let item = NSMenuItem(title: NSLocalizedString("Rename Light", comment: ""),
                              action: #selector(renameAction(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)

        if let safeDev = self.device {
            if let safeLink = safeDev.productLink {
                if URL(string:safeLink) != nil {
                    let item = NSMenuItem(title: NSLocalizedString("Open product page", comment: ""),
                                      action: #selector(linkAction(_:)), keyEquivalent: "")
                    item.target = self
                    menu.addItem(item)
                }
            }
        }

        var location = sender.bounds.origin
        location.y += 20

        menu.popUp(positioning: menu.item(at: 0), at: location, in: sender)
    }
    
    @objc func linkAction(_ sender: Any) {
        if let safeDev = self.device {
            if let safeLink = safeDev.productLink {
                if let url = URL(string:safeLink) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
    
    @objc func renameAction(_ sender: Any) {
        if renameVC != nil {
            renameVC = nil
        }
        renameVC = RenameViewController()
        renameVC?.onOK = { [weak self] text in
            guard let safeSelf = self else { return true }
            if let safeDev = safeSelf.device {
                if let app = NSApp.delegate as? AppDelegate {
                    if app.isUserLightNameUsed(text, dev: safeDev) {
                        return false
                    }
                }
                safeDev.userLightName.value = "\(text)"
                safeSelf.updateDeviceName()
            }
            return true
        }
        if let dev = device {
            renameVC?.setCurrentValue(dev.userLightName.value)
        }

        self.view.window?.beginSheet(renameVC!.sheetWindow, completionHandler: nil)
        //renameVC?.popover.show(relativeTo: nameField.bounds, of: nameField, preferredEdge: .minY)
    }

    func formatBrrValue(_ val: String, _ ali: NSTextAlignment) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ali
        var font1 = NSFont.monospacedSystemFont(ofSize: 27, weight: .regular)
        var font2 = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        if let fontURL = Bundle.main.url(forResource: "digital-7-mono", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, CTFontManagerScope.process, nil)
            if let customFont1 = NSFont(name: "Digital-7Mono", size: 45) { // Replace "ActualFontName" with the actual font name.
                font1 = customFont1
            }
            if let customFont2 = NSFont(name: "Digital-7Mono", size: 18) { // Replace "ActualFontName" with the actual font name.
                font2 = customFont2
            }
        }

        let str1 = NSAttributedString(string: "\(val)",
                                      attributes: [
                                        .font: font1,
                                        .paragraphStyle: paragraph,
                                        .foregroundColor: valueTextColor
                                      ])
        let str2 = NSAttributedString(string: "%",
                                      attributes: [
                                        .font: font2,
                                        .paragraphStyle: paragraph,
                                        .foregroundColor: valueTextColor
                                      ])
        let str = NSMutableAttributedString(attributedString: str1)
        str.append(str2)
        return str
    }

    func formatHUEValue(_ val: String, _ ali: NSTextAlignment) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ali
        var font1 = NSFont.monospacedSystemFont(ofSize: 27, weight: .regular)
        if let fontURL = Bundle.main.url(forResource: "digital-7-mono", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, CTFontManagerScope.process, nil)
            if let customFont1 = NSFont(name: "Digital-7Mono", size: 40) { // Replace "ActualFontName" with the actual font name.
                font1 = customFont1
            }
        }

        let str1 = NSAttributedString(string: "\(val)°",
                                      attributes: [
                                        .font: font1,
                                        .paragraphStyle: paragraph,
                                        .foregroundColor: valueTextColor
                                      ])
        let str = NSMutableAttributedString(attributedString: str1)
        return str
    }

    func formatSATValue(_ val: String, _ ali: NSTextAlignment) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ali
        var font1 = NSFont.monospacedSystemFont(ofSize: 27, weight: .regular)
        if let fontURL = Bundle.main.url(forResource: "digital-7-mono", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, CTFontManagerScope.process, nil)
            if let customFont1 = NSFont(name: "Digital-7Mono", size: 40) { // Replace "ActualFontName" with the actual font name.
                font1 = customFont1
            }
        }

        let str1 = NSAttributedString(string: "\(val)",
                                      attributes: [
                                        .font: font1,
                                        .paragraphStyle: paragraph,
                                        .foregroundColor: valueTextColor
                                      ])
        let str = NSMutableAttributedString(attributedString: str1)
        return str
    }

    func formatCCTValue(_ val: String, _ ali: NSTextAlignment) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ali
        var font1 = NSFont.monospacedSystemFont(ofSize: 27, weight: .regular)
        var font2 = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        if let fontURL = Bundle.main.url(forResource: "digital-7-mono", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, CTFontManagerScope.process, nil)
            if let customFont1 = NSFont(name: "Digital-7Mono", size: 45) { // Replace "ActualFontName" with the actual font name.
                font1 = customFont1
            }
            if let customFont2 = NSFont(name: "Digital-7Mono", size: 18) { // Replace "ActualFontName" with the actual font name.
                font2 = customFont2
            }
        }

        let str1 = NSAttributedString(string: "\(val)",
                                      attributes: [
                                        .paragraphStyle: paragraph,
                                        .font: font1,
                                        .foregroundColor: valueTextColor
                                      ])
        let str2 = NSAttributedString(string: "00K",
                                      attributes: [
                                        .font: font2,
                                        .paragraphStyle: paragraph,
                                        .foregroundColor: valueTextColor
                                      ])
        let str = NSMutableAttributedString(attributedString: str1)
        str.append(str2)
        return str
    }

    func formatGMMValue(_ val: String, _ ali: NSTextAlignment) -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = ali
        var font1 = NSFont.monospacedSystemFont(ofSize: 27, weight: .regular)
        if let fontURL = Bundle.main.url(forResource: "digital-7-mono", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, CTFontManagerScope.process, nil)
            if let customFont1 = NSFont(name: "Digital-7Mono", size: 45) { // Replace "ActualFontName" with the actual font name.
                font1 = customFont1
            }
        }
        let str1 = NSAttributedString(string: "\(val)",
                                      attributes: [
                                        .font: font1,
                                        .paragraphStyle: paragraph,
                                        .foregroundColor: valueTextColor
                                      ])
        let str = NSMutableAttributedString(attributedString: str1)
        return str
    }

    @IBAction func toggleAction(_ sender: Any) {
        if let dev = device {
            if let event = NSApplication.shared.currentEvent {
                let isAltKeyPressed = event.modifierFlags.contains(.option)
                if isAltKeyPressed {
                    // for debug purpose
                    if dev.isOn.value {
                        dev.sendPowerOffRequest(true)
                    } else {
                        dev.sendPowerOnRequest(true)
                    }
                    return
                }
            }
            if dev.isOn.value {
                dev.sendPowerOffRequest()
            } else {
                dev.sendPowerOnRequest()
            }
        }
    }

    func updateDeviceName() {
        guard let dev = device else {
            self.nameField.stringValue = ""
            return
        }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 5.0 // Adjust the spacing to your needs

        // Attributes for the first line
        let firstLineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular), // Large font size
            .foregroundColor: NSColor.gray, // Light gray color
            .paragraphStyle: paragraphStyle
        ]

        // Attributes for the second line
        let secondLineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .regular), // Smaller font size
            .foregroundColor: NSColor.darkGray, // Light gray color
            .paragraphStyle: paragraphStyle
        ]

        // Create the attributed string for the first line
        let firstLine = NSAttributedString(string: "\(dev.nickName)\n", attributes: firstLineAttributes)

        // Create the attributed string for the second line
        let secondLine = NSAttributedString(string: "\(dev.userLightName.value)", attributes: secondLineAttributes)

        // Combine the attributed strings
        let finalString = NSMutableAttributedString()
        finalString.append(firstLine)
        finalString.append(secondLine)

        // Set the attributed string to the NSTextField
        self.nameField.attributedStringValue = finalString
    }

    @MainActor
    func selectTabViewItemSafely(withIdentifier identifier: Any) {
        guard let tabView = self.lightModeTabView else {
            return
        }
        guard tabView.tabViewItems.contains(where: { $0.identifier as? String == identifier as? String }) else {
            if tabView.tabViewItems.count > 0 {
                tabView.selectTabViewItem(at: 0)
            }
            return
        }
        tabView.selectTabViewItem(withIdentifier: identifier)
    }

    func updateDeviceStatus() {
        guard let dev = device else {
            return
        }

        self.switchButton.state = dev.isOn.value ? .on : .off

        // Mode tab updates
        if !buildingView {
            self.selectTabViewItemSafely(withIdentifier: dev.lastTab)
        }
    }

    func buildView() {
        if let dev = device {
            buildingView = true

            let removeTabItem: (String) -> Void = { idf in
                if let tabviewitem = self.lightModeTabView.tabViewItems.first(where: { $0.identifier as? String == idf }) {
                    self.lightModeTabView.removeTabViewItem(tabviewitem)
                }
            }

            removeTabItem(TabId.cct.rawValue)
            removeTabItem(TabId.source.rawValue)
            removeTabItem(TabId.hsi.rawValue)
            removeTabItem(TabId.scene.rawValue)

            if true {
                let view = buildCCTView(device: dev)
                let tab = NSTabViewItem(identifier: TabId.cct.rawValue )
                tab.view = view
                tab.label = "CCT"
                self.lightModeTabView.addTabViewItem(tab)
            }

            if dev.supportRGB {
                let view = buildHSIView(device: dev)
                let tab = NSTabViewItem(identifier: TabId.hsi.rawValue)
                tab.view = view
                tab.label = "HSI"
                self.lightModeTabView.addTabViewItem(tab)
            }

            if true {
                let view = buildLightSourceView(device: dev)
                let tab = NSTabViewItem(identifier: TabId.source.rawValue)
                tab.view = view
                tab.label = "Light Source"
                self.lightModeTabView.addTabViewItem(tab)
            }

            if dev.maxChannel > 0 {
                let view = buildFXView(device: dev)
                let tab = NSTabViewItem(identifier: TabId.scene.rawValue)
                tab.view = view
                tab.label = "FX"
                self.lightModeTabView.addTabViewItem(tab)
            }

            buildingView = false
        }
    }

    func buildHSIView(device dev: NeewerLight) -> NSView {
        let viewWidth = self.lightModeTabView.bounds.width
        let viewHeigth = self.lightModeTabView.bounds.height - 46
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeigth))
        view.autoresizingMask = [.width, .height]

        let valueWidth = 80.0
        let wheelWidth = 150.0
        let wheelX = (view.bounds.width - wheelWidth) / 2.0 + 10.0
        let offsetX = 50.0
        var offsetY = 20.0
        var topY = 30.0
        var topX = wheelX - valueWidth
        let topDX = valueWidth + wheelWidth + 50.0

        let color = NSColor(calibratedHue: CGFloat(dev.hueValue.value) / 360.0,
                            saturation: CGFloat(dev.satValue.value) / 100.0,
                            brightness: 1.0,
                            alpha: 1.0)

        let wheel = ColorWheel(frame: NSRect(x: wheelX, y: 40, width: wheelWidth, height: wheelWidth), color: color)
        wheel.autoresizingMask = [.minXMargin, .maxYMargin]
        wheel.tag = ControlTag.wheel.rawValue
        wheel.callback = { [weak self] hue, sat in
            guard let safeSelf = self else { return }
            if let safeDev = safeSelf.device {
                if safeDev.supportRGB {
                    safeDev.lightMode = .HSIMode
                    safeDev.setRGBLightValues(brr: CGFloat(safeDev.brrValue.value) / 100.0, hue: hue, hue360: hue * 360.0, sat: sat)
                }
            }
        }

        view.addSubview(wheel)

        let createLabel: (String) -> NSTextField = { stringValue in
            let label = NSTextField(frame: NSRect(x: offsetX - 40, y: offsetY - 4, width: 30, height: 18))
            label.autoresizingMask = [.minYMargin, .maxXMargin]
            label.stringValue = stringValue
            label.alignment = .right
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.labelFont(ofSize: 9)
            return label
        }

        let createValueField: (ControlTag, NSAttributedString) -> NSTextField = { tag, stringValue in
            let label = NSTextField(frame: NSRect(x: topX, y: topY+15, width: valueWidth, height: 37))
            label.autoresizingMask = [.minYMargin, .maxXMargin, .minXMargin]
            label.attributedStringValue = stringValue
            label.tag = tag.rawValue
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            topX += topDX
            return label
        }

        let createValueLabel: (String) -> NSTextField = { stringValue in
            let label = NSTextField(frame: NSRect(x: topX, y: topY + 55, width: valueWidth, height: 19))
            label.autoresizingMask = [.minYMargin, .maxXMargin, .minXMargin]
            label.stringValue = stringValue
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.systemFont(ofSize: 11)
            return label
        }

        offsetY = 13.0
        view.addSubview(createLabel("BRR"))
        let brrSlide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: view.bounds.width - 80, height: 20))
        brrSlide.autoresizingMask = [.width, .maxYMargin]
        brrSlide.tag = ControlTag.brr.rawValue
        brrSlide.type = .brr
        brrSlide.minValue = 0.0
        brrSlide.maxValue = 100.0
        brrSlide.currentValue = CGFloat(dev.brrValue.value)
        brrSlide.customBarDrawing = NLSlider.brightnessBar()
        brrSlide.callback = { [weak self] val in
            guard let safeSelf = self else { return }
            if let safeDev = safeSelf.device {
                if safeDev.supportRGB {
                    safeDev.lightMode = .HSIMode
                }
                safeDev.setBRRLightValues(CGFloat(val))
            }
        }
        view.addSubview(brrSlide)

        view.addSubview(createValueLabel("Brightness"))
        view.addSubview(createValueField(ControlTag.brr, formatBrrValue("\(dev.brrValue.value)", .center)))

        topX = wheelX - valueWidth
        topY = 120
        view.addSubview(createValueLabel("HUE"))
        view.addSubview(createValueField(ControlTag.hue, formatHUEValue("\(dev.hueValue.value)", .center)))

        topX = wheel.frame.maxX - 20.0
        view.addSubview(createValueLabel("Saturation"))
        view.addSubview(createValueField(ControlTag.sat, formatSATValue("\(dev.satValue.value)", .center)))

//        let checkbox = NSButton(checkboxWithTitle: "Music", target: self, action: #selector(fllowMusicClicked))
//        checkbox.state = .off // Or .on if you want it checked initially
//        // Set the frame of the checkbox (position and size)
//        checkbox.frame = NSRect(x: 230, y: 40, width: 110, height: 30)
//        // Add the checkbox to the view
//        view.addSubview(checkbox)

        return view
    }

    func buildCCTView(device dev: NeewerLight) -> NSView {
        let viewWidth = self.lightModeTabView.bounds.width
        let viewHeight = self.lightModeTabView.bounds.height - 46
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))
        view.autoresizingMask = [.width, .height]

        let cctrange = dev.CCTRange()

        let valueItem = dev.supportGMRange.value ? 3 : 2
        var topY = 100.0
        let valueItemWidth = 98.0
        // Define the gap between subviews
        let gap: CGFloat = 10
        let sliderWidth: CGFloat = view.bounds.width - 80

        // Calculate the total width needed for all three subviews and two gaps
        let totalWidth = (valueItemWidth * Double(valueItem)) + (gap * 2.0)

        // Calculate the x-coordinate for the leftmost subview to center them
        var topX = (view.frame.size.width - totalWidth) / 2.0
        let topDX = valueItemWidth + gap

        let offsetX = 50.0
        var offsetY = 50.0
        if dev.supportGMRange.value {
            offsetY = 70.0
            topY = 110
        }

        let createLabel: (String) -> NSTextField = { stringValue in
            let label = NSTextField(frame: NSRect(x: offsetX - 40, y: offsetY - 4, width: 30, height: 18))
            label.autoresizingMask = [.minYMargin, .maxXMargin]
            label.stringValue = stringValue
            label.alignment = .right
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.labelFont(ofSize: 9)
            return label
        }

        let createValueField: (ControlTag, NSAttributedString) -> NSTextField = { tag, stringValue in
            let label = NSTextField(frame: NSRect(x: topX, y: topY, width: valueItemWidth, height: 50))
            label.autoresizingMask = [.minYMargin, .maxXMargin, .minXMargin]
            label.attributedStringValue = stringValue
            label.tag = tag.rawValue
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            topX += topDX
            return label
        }

        let createValueLabel: (String) -> NSTextField = { stringValue in
            let label = NSTextField(frame: NSRect(x: topX, y: topY + 55, width: valueItemWidth, height: 19))
            label.autoresizingMask = [.minYMargin, .maxXMargin, .minXMargin]
            label.stringValue = stringValue
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.systemFont(ofSize: 11)
            return label
        }

        view.addSubview(createLabel("BRR"))
        let brrSlide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: sliderWidth, height: 20))
        brrSlide.autoresizingMask = [.width, .maxYMargin]
        brrSlide.tag = ControlTag.brr.rawValue
        brrSlide.type = .brr
        brrSlide.minValue = 0.0
        brrSlide.maxValue = 100.0
        brrSlide.currentValue = CGFloat(dev.brrValue.value)
        brrSlide.customBarDrawing = NLSlider.brightnessBar()
        brrSlide.callback = { [weak self] val in
            guard let safeSelf = self else { return }
            if let safeDev = safeSelf.device {
                safeDev.setCCTLightValues(brr: CGFloat(val), cct: CGFloat(dev.cctValue.value), gmm: CGFloat(dev.gmmValue.value))
            }
        }
        view.addSubview(brrSlide)
        view.addSubview(createValueLabel("Brightness"))
        view.addSubview(createValueField(ControlTag.brr, formatBrrValue("\(dev.brrValue.value)", .center)))

        offsetY -= 30

        view.addSubview(createLabel("CCT"))
        let cctSlide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: sliderWidth, height: 20))
        cctSlide.autoresizingMask = [.width, .maxYMargin]
        cctSlide.tag = ControlTag.cct.rawValue
        cctSlide.type = .cct
        cctSlide.minValue = Double(cctrange.minCCT)
        cctSlide.maxValue = Double(cctrange.maxCCT)
        cctSlide.currentValue = CGFloat(dev.cctValue.value)
        cctSlide.customBarDrawing = NLSlider.cttBar()
        cctSlide.callback = { val in
            print("dev.brrValue.value: \(dev.brrValue.value)")
            dev.setCCTLightValues(brr: CGFloat(dev.brrValue.value), cct: CGFloat(val), gmm: CGFloat(dev.gmmValue.value))
        }
        view.addSubview(cctSlide)
        view.addSubview(createValueLabel("CCT"))
        view.addSubview(createValueField(ControlTag.cct, formatCCTValue("\(dev.cctValue.value)", .center)))

        offsetY -= 30

        if dev.supportGMRange.value {
            view.addSubview(createLabel("GM"))
            let gmmSlide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: sliderWidth, height: 20))
            gmmSlide.autoresizingMask = [.width, .maxYMargin]
            gmmSlide.tag = ControlTag.gmm.rawValue
            gmmSlide.type = .gmm
            gmmSlide.customBarDrawing = NLSlider.gmBar()
            gmmSlide.minValue = -50.0
            gmmSlide.maxValue = 50.0
            gmmSlide.currentValue = CGFloat(dev.gmmValue.value)
            gmmSlide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    safeDev.setCCTLightValues(brr: CGFloat(safeDev.brrValue.value), cct: CGFloat(safeDev.cctValue.value), gmm: CGFloat(val))
                }
            }
            view.addSubview(gmmSlide)
            view.addSubview(createValueLabel("GM"))
            view.addSubview(createValueField(ControlTag.gmm, formatGMMValue("\(dev.gmmValue.value)", .center)))
        }
        return view
    }

    func buildFXView(device dev: NeewerLight) -> NSView {
        let viewWidth = self.lightModeTabView.bounds.width
        let viewHeight = self.lightModeTabView.bounds.height - 46
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))
        view.autoresizingMask = [.width, .height]
        //view.wantsLayer = true
        //view.layer?.backgroundColor = NSColor.yellow.cgColor

        let cctrange = dev.CCTRange()

        let createLabel: (CGFloat, String) -> NSTextField = { offsetY, stringValue in
            let label = NSTextField(frame: NSRect(x: 15, y: offsetY, width: 35, height: 20))
            label.autoresizingMask = [.minYMargin, .maxXMargin]
            label.stringValue = stringValue
            label.alignment = .right
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.labelFont(ofSize: 9)
            return label
        }

        let fxs = dev.supportedFX

        view.addSubview(createLabel(viewHeight - 30, "Scene"))

        // Create an NSPopUpButton and set its frame
        let popUpButton = NSPopUpButton(frame: NSRect(x: 60, y: viewHeight - 28, width: viewWidth - 120, height: 20), pullsDown: false)
        popUpButton.autoresizingMask = [.minYMargin, .width]
        popUpButton.controlSize = .small
        popUpButton.target = self
        popUpButton.action = #selector(fxClicked(_:))
        let menu = NSMenu()
        // Populate the menu with menu items
        for scene in fxs {
            let menuItem = NSMenuItem(title: "\(scene.id) - \(scene.name)", action: nil, keyEquivalent: "")
            if !scene.iconName.isEmpty {
                menuItem.image = NSImage(systemSymbolName: scene.iconName, accessibilityDescription: "")
            }
            menuItem.tag = Int(scene.id)
            menuItem.target = self // Set the target to your desired target
            menu.addItem(menuItem)
        }
        popUpButton.menu = menu
        view.addSubview(popUpButton)

        popUpButton.selectItem(withTag: Int(dev.channel.value))
        if let selectedItem = popUpButton.selectedItem {
            fxClicked(popUpButton)
        }
        return view
    }

    func buildLightSourceView(device dev: NeewerLight) -> NSView {
        let viewWidth = self.lightModeTabView.bounds.width
        let viewHeight = self.lightModeTabView.bounds.height - 46
        let view = NSView(frame: NSRect(x: 0, y: 0, width: viewWidth, height: viewHeight))
        view.autoresizingMask = [.width, .height]
        //view.wantsLayer = true
        //view.layer?.backgroundColor = NSColor.yellow.cgColor

        let createLabel: (CGFloat, String) -> NSTextField = { offsetY, stringValue in
            let label = NSTextField(frame: NSRect(x: 15, y: offsetY, width: 35, height: 20))
            label.autoresizingMask = [.minYMargin, .maxXMargin]
            label.stringValue = stringValue
            label.alignment = .right
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.labelFont(ofSize: 9)
            return label
        }

        let fxs = dev.supportedSource

        view.addSubview(createLabel(viewHeight - 30, "Source"))

        // Create an NSPopUpButton and set its frame
        let popUpButton = NSPopUpButton(frame: NSRect(x: 60, y: viewHeight - 28, width: viewWidth - 120, height: 20), pullsDown: false)
        popUpButton.autoresizingMask = [.minYMargin, .width]
        popUpButton.controlSize = .small
        popUpButton.target = self
        popUpButton.action = #selector(sourceClicked(_:))
        let menu = NSMenu()
        // Populate the menu with menu items
        for scene in fxs {
            let menuItem = NSMenuItem(title: "\(scene.id) - \(scene.name)", action: nil, keyEquivalent: "")
            menuItem.tag = Int(scene.id)
            menuItem.target = self // Set the target to your desired target
            menu.addItem(menuItem)
        }
        popUpButton.menu = menu
        view.addSubview(popUpButton)

        popUpButton.selectItem(withTag: 0)
        if let selectedItem = popUpButton.selectedItem {
            sourceClicked(popUpButton)
        }
        return view
    }

    @objc func fllowMusicClicked(_ sender: NSButton) {
        if let dev = device {
            let isChecked = sender.state == .on
            dev.followMusic = isChecked
            Logger.debug("dev.followMusic= \(dev.followMusic)")
            if let app = NSApp.delegate as? AppDelegate {
                app.checkAudioDriver()
            }
        }
    }

    @objc func sourceClicked(_ sender: NSPopUpButton) {
        
        guard let dev = device else {
            return
        }
        guard let selectedItem = sender.selectedItem else {
            return
        }
        let fxid = selectedItem.tag
        let fxs = dev.supportedSource
        let theFx = fxs.first { (fxItem) -> Bool in
            return fxItem.id == fxid
        }
        guard let safeFx = theFx else {
            return
        }
        
        let cctrange = dev.CCTRange()
        guard let theView = sender.superview else {
            return
        }
        for subview in theView.subviews {
            if subview is FXView {
                subview.removeFromSuperview()
            }
        }
        
        let fxsubview = FXView(frame: NSRect(x: 0, y: 0, width: theView.bounds.width, height: theView.bounds.height - 35))
        fxsubview.autoresizingMask = [.width, .height]
        //fxsubview.wantsLayer = true
        //fxsubview.layer?.backgroundColor = NSColor.green.cgColor
        theView.addSubview(fxsubview)

        let offsetX = 50.0
        let topY = 90.0
        var offsetY = fxsubview.bounds.height - 26
        let sliderWidth = fxsubview.bounds.width - 80
        
        let valueItemWidth = 98.0
        // Define the gap between subviews
        let gap: CGFloat = 10
        var valueItem = 0
        if safeFx.needBRR {
            valueItem += 1
        }
        if safeFx.needCCT {
            valueItem += 1
        }
        if safeFx.needGM  && dev.supportGMRange.value {
            valueItem += 1
        }
        // Calculate the total width needed for all three subviews and two gaps
        let totalWidth = (valueItemWidth * Double(valueItem)) + (gap * 2.0)

        // Calculate the x-coordinate for the leftmost subview to center them
        var topX = (fxsubview.frame.size.width - totalWidth) / 2.0
        let topDX = valueItemWidth + gap
        
        let createLabel: (CGFloat, String) -> NSTextField = { offsetY, stringValue in
            let label = NSTextField(frame: NSRect(x: 5, y: offsetY, width: 35, height: 20))
            label.autoresizingMask = [.minYMargin, .maxXMargin]
            label.stringValue = stringValue
            label.alignment = .right
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.labelFont(ofSize: 9)
            return label
        }

        let createBigValueField: (ControlTag, NSAttributedString) -> NSTextField = { tag, stringValue in
            let label = NSTextField(frame: NSRect(x: topX, y: topY, width: valueItemWidth, height: 50))
            label.autoresizingMask = [.minYMargin, .maxXMargin, .minXMargin]
            label.attributedStringValue = stringValue
            label.tag = tag.rawValue
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            topX += topDX
            return label
        }

        let createBigValueLabel: (String) -> NSTextField = { stringValue in
            let label = NSTextField(frame: NSRect(x: topX, y: topY + 55, width: valueItemWidth, height: 19))
            label.autoresizingMask = [.minYMargin, .maxXMargin, .minXMargin]
            label.stringValue = stringValue
            label.alignment = .center
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.systemFont(ofSize: 11)
            return label
        }
        
        offsetY -= 80
        
        if safeFx.needBRR {
            
            fxsubview.addSubview(createBigValueLabel("Brightness"))
            fxsubview.addSubview(createBigValueField(ControlTag.brr, formatBrrValue("\(dev.brrValue.value)", .center)))

            fxsubview.addSubview(createLabel(offsetY-4, "BRR"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: sliderWidth, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.brr.rawValue
            slide.type = .brr
            slide.minValue = 0.0
            slide.maxValue = 100.0
            slide.currentValue = CGFloat(safeFx.brrValue)
            slide.customBarDrawing = NLSlider.brightnessBar()
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    safeFx.brrValue = val
                    safeDev.setCCTLightValues(brr: CGFloat(safeFx.brrValue), cct: CGFloat(safeFx.cctValue), gmm: CGFloat(safeFx.gmValue))
                }
            }
            fxsubview.addSubview(slide)
            offsetY -= 30
        }

        if safeFx.needCCT {
            fxsubview.addSubview(createBigValueLabel("CCT"))
            fxsubview.addSubview(createBigValueField(ControlTag.cct, formatCCTValue("\(dev.cctValue.value)", .center)))

            fxsubview.addSubview(createLabel(offsetY-4, "CCT"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: sliderWidth, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.cct.rawValue
            slide.type = .cct
            slide.minValue = Double(cctrange.minCCT)
            slide.maxValue = Double(cctrange.maxCCT)
            slide.currentValue = CGFloat(safeFx.cctValue)
            slide.customBarDrawing = NLSlider.cttBar()
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    safeFx.cctValue = val
                    safeDev.setCCTLightValues(brr: CGFloat(safeFx.brrValue), cct: CGFloat(safeFx.cctValue), gmm: CGFloat(safeFx.gmValue))
                }
            }
            fxsubview.addSubview(slide)
            offsetY -= 30
        }

        if safeFx.needGM  && dev.supportGMRange.value {
            fxsubview.addSubview(createBigValueLabel("GM"))
            fxsubview.addSubview(createBigValueField(ControlTag.gmm, formatCCTValue("\(dev.gmmValue.value)", .center)))

            fxsubview.addSubview(createLabel(offsetY-4, "GM"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: sliderWidth, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.gmm.rawValue
            slide.type = .gmm
            slide.minValue = -50.0
            slide.maxValue = 50.0
            slide.currentValue = CGFloat(safeFx.gmValue)
            slide.customBarDrawing = NLSlider.gmBar()
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    safeFx.gmValue = val
                    safeDev.setCCTLightValues(brr: CGFloat(safeFx.brrValue), cct: CGFloat(safeFx.cctValue), gmm: CGFloat(safeFx.gmValue))
                }
            }
            fxsubview.addSubview(slide)
            offsetY -= 30
        }

        dev.setCCTLightValues(brr: CGFloat(safeFx.brrValue), cct: CGFloat(safeFx.cctValue), gmm: CGFloat(safeFx.gmValue))
    }

    @objc func fxClicked(_ sender: NSPopUpButton) {
        if buildingView {
            return
        }
        guard let dev = device else {
            return
        }
        guard let selectedItem = sender.selectedItem else {
            return
        }
        let fxid = selectedItem.tag
        let fxs = dev.supportedFX
        let theFx = fxs.first { (fxItem) -> Bool in
            return fxItem.id == fxid
        }
        guard let safeFx = theFx else {
            return
        }
        let cctrange = dev.CCTRange()
        guard let theView = sender.superview else {
            return
        }
        for subview in theView.subviews {
            if subview is FXView {
                subview.removeFromSuperview()
            }
        }

        let fxsubview = FXView(frame: NSRect(x: 0, y: 0, width: theView.bounds.width, height: theView.bounds.height - 35))
        fxsubview.autoresizingMask = [.width, .height]
        //fxsubview.wantsLayer = true
        //fxsubview.layer?.backgroundColor = NSColor.green.cgColor
        theView.addSubview(fxsubview)

        let offsetX = 55.0
        var offsetY = fxsubview.bounds.height - 26
        let slideW = fxsubview.bounds.width - 110

        let createLabel: (CGFloat, String) -> NSTextField = { offsetY, stringValue in
            let label = NSTextField(frame: NSRect(x: 15, y: offsetY, width: 35, height: 20))
            label.autoresizingMask = [.minYMargin, .maxXMargin]
            label.stringValue = stringValue
            label.alignment = .right
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.labelFont(ofSize: 9)
            return label
        }

        let createValeLabel: (CGFloat, String, Int) -> NSTextField = { offsetY, stringValue, tag in
            let label = NSTextField(frame: NSRect(x: offsetX + slideW + 5, y: offsetY + 4, width: 50, height: 18))
            label.autoresizingMask = [.maxYMargin, .minXMargin]
            label.stringValue = stringValue
            label.alignment = .left
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .medium)
            label.tag = tag
            return label
        }

        if safeFx.needBRR {
            fxsubview.addSubview(createLabel(offsetY-4, "BRR"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: slideW, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.brr.rawValue
            slide.type = .brr
            slide.minValue = 0.0
            slide.maxValue = 100.0
            slide.currentValue = CGFloat(safeFx.brrValue)
            slide.customBarDrawing = NLSlider.brightnessBar()
            if safeFx.needBRRUpperBound {
                slide.needUpperBound = true
                slide.currentUpperValue = CGFloat(safeFx.brrUpperValue)
            }
            let valueField = createValeLabel(offsetY-4, "", slide.tag)
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    safeFx.brrValue = val
                    if safeFx.needBRRUpperBound {
                        safeFx.brrUpperValue = slide.currentUpperValue
                        valueField.stringValue = "\(Int(val))%~\(Int(safeFx.brrUpperValue))%"
                    } else {
                        valueField.stringValue = "\(Int(val))%"
                    }
                    safeDev.sendSceneCommand(safeFx)
                }
            }
            fxsubview.addSubview(slide)
            fxsubview.addSubview(valueField)
            offsetY -= 30
        }

        if safeFx.needColor {
            fxsubview.addSubview(createLabel(offsetY-4, "Color"))

            let popUpButton = NSPopUpButton(frame: NSRect(x: 60, y: offsetY-1, width: fxsubview.bounds.width - 120, height: 20), pullsDown: false)
            popUpButton.autoresizingMask = [.minYMargin, .width]
            popUpButton.controlSize = .small
            popUpButton.target = self
            popUpButton.action = #selector(fxColorClicked(_:))
            let menu = NSMenu()

            var btnoffsetX = offsetX
            for color in safeFx.colors {
                let menuItem = NSMenuItem(title: "\(color.key)", action: nil, keyEquivalent: "")
                menuItem.tag = Int(color.value)
                menu.addItem(menuItem)
            }
            popUpButton.menu = menu
            fxsubview.addSubview(popUpButton)

            popUpButton.selectItem(withTag: safeFx.colorValue)

            offsetY -= 30
        }

        if safeFx.needCCT {
            fxsubview.addSubview(createLabel(offsetY-4, "CCT"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: slideW, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.cct.rawValue
            slide.type = .cct
            slide.minValue = Double(cctrange.minCCT)
            slide.maxValue = Double(cctrange.maxCCT)
            slide.currentValue = CGFloat(safeFx.cctValue)
            slide.customBarDrawing = NLSlider.cttBar()
            if safeFx.needCCTUpperBound {
                slide.needUpperBound = true
                slide.currentUpperValue = CGFloat(safeFx.cctUpperValue)
            }
            let valueField = createValeLabel(offsetY-4, "", slide.tag)
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    safeFx.cctValue = val
                    if safeFx.needCCTUpperBound {
                        safeFx.cctUpperValue = slide.currentUpperValue
                        valueField.stringValue = "\(Int(val))00k~\(Int(safeFx.cctUpperValue))00k"
                    } else {
                        valueField.stringValue = "\(Int(val))00k"
                    }
                    safeDev.sendSceneCommand(safeFx)
                }
            }
            fxsubview.addSubview(slide)
            fxsubview.addSubview(valueField)
            offsetY -= 30
        }

        if safeFx.needGM {
            fxsubview.addSubview(createLabel(offsetY-4, "GM"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: slideW, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.gmm.rawValue
            slide.type = .gmm
            slide.minValue = -50.0
            slide.maxValue = 50.0
            slide.currentValue = CGFloat(safeFx.gmValue)
            slide.customBarDrawing = NLSlider.gmBar()
            let valueField = createValeLabel(offsetY-4, "", slide.tag)
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    valueField.stringValue = "\(Int(val))"
                    safeFx.gmValue = val
                    safeDev.sendSceneCommand(safeFx)
                }
            }
            fxsubview.addSubview(slide)
            fxsubview.addSubview(valueField)
            offsetY -= 30
        }

        if safeFx.needHUE {
            fxsubview.addSubview(createLabel(offsetY-4, "HUE"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: slideW, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.hue.rawValue
            slide.type = .hue
            slide.minValue = 0
            slide.maxValue = 360
            slide.currentValue = CGFloat(safeFx.hueValue)
            if safeFx.needHUEUpperBound {
                slide.needUpperBound = true
                slide.currentUpperValue = CGFloat(safeFx.hueUpperValue)
            }
            slide.customBarDrawing = NLSlider.hueBar()
            let valueField = createValeLabel(offsetY-4, "", slide.tag)
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    safeFx.hueValue = val
                    if safeFx.needHUEUpperBound {
                        safeFx.hueUpperValue = slide.currentUpperValue
                        valueField.stringValue = "\(Int(val))~\(Int(safeFx.hueUpperValue))"
                    } else {
                        valueField.stringValue = "\(Int(val))°"
                    }
                    safeDev.sendSceneCommand(safeFx)
                }
            }
            fxsubview.addSubview(slide)
            fxsubview.addSubview(valueField)
            offsetY -= 30
        }

        if safeFx.needSAT {
            fxsubview.addSubview(createLabel(offsetY-4, "SAT"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: slideW, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.sat.rawValue
            slide.type = .sat
            slide.minValue = 0
            slide.maxValue = 100
            slide.currentValue = CGFloat(safeFx.satValue)
            slide.customBarDrawing = NLSlider.satBar()
            let valueField = createValeLabel(offsetY-4, "", slide.tag)
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    valueField.stringValue = "\(Int(val))%"
                    safeFx.satValue = val
                    safeDev.sendSceneCommand(safeFx)
                }
            }
            fxsubview.addSubview(slide)
            fxsubview.addSubview(valueField)
            offsetY -= 30
        }

        if safeFx.needSpeed {
            fxsubview.addSubview(createLabel(offsetY-4, "Speed"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: slideW, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.speed.rawValue
            slide.type = .speed
            slide.minValue = 1
            slide.maxValue = 10
            slide.currentValue = CGFloat(safeFx.speedValue)
            slide.customBarDrawing = NLSlider.speedBar()
            slide.steps = 10
            let valueField = createValeLabel(offsetY-4, "", slide.tag)
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    valueField.stringValue = "\(Int(val+1))"
                    safeFx.speedValue = Int(val+1)
                    safeDev.sendSceneCommand(safeFx)
                }
            }
            fxsubview.addSubview(slide)
            fxsubview.addSubview(valueField)
            offsetY -= 30
        }

        if safeFx.needSparks {
            fxsubview.addSubview(createLabel(offsetY-4, "Sparks"))
            let slide = NLSlider(frame: NSRect(x: offsetX, y: offsetY, width: slideW, height: 20))
            slide.autoresizingMask = [.width, .maxYMargin]
            slide.tag = ControlTag.spark.rawValue
            slide.type = .spark
            slide.minValue = 1
            slide.maxValue = 10
            slide.currentValue = CGFloat(safeFx.sparksValue)
            slide.customBarDrawing = NLSlider.sparkBar()
            slide.steps = 10
            let valueField = createValeLabel(offsetY-4, "", slide.tag)
            slide.callback = { [weak self] val in
                guard let safeSelf = self else { return }
                if let safeDev = safeSelf.device {
                    valueField.stringValue = "\(Int(val))"
                    safeFx.sparksValue = Int(val)
                    safeDev.sendSceneCommand(safeFx)
                }
            }
            fxsubview.addSubview(slide)
            fxsubview.addSubview(valueField)
            offsetY -= 30
        }

        dev.sendSceneCommand(safeFx)
    }

    @objc func fxColorClicked(_ sender: NSPopUpButton) {
        guard let dev = device else {
            return
        }
        guard let selectedItem = sender.selectedItem else {
            return
        }
        let fxid = dev.channel.value
        let fxs = dev.supportedFX
        let theFx = fxs.first { (fxItem) -> Bool in
            return fxItem.id == fxid
        }
        guard let safeFx = theFx else {
            return
        }
        safeFx.colorValue = selectedItem.tag
        dev.sendSceneCommand(safeFx)
        Logger.debug("\(selectedItem.tag)-\(selectedItem.title)")
    }

    func updateDeviceValueField(type: ControlTag, value: Any) {
        guard !buildingView else {
            return
        }
        guard let item = self.lightModeTabView.selectedTabViewItem else {
            return
        }
        guard let view = item.view else {
            return
        }

        // Define a lambda (closure) that processes an NSView
        let processSubView: (NSView) -> Void = { subview in
            if subview.tag == type.rawValue {
                if let field = subview as? NSTextField {
                    if type == ControlTag.brr {
                        field.attributedStringValue = self.formatBrrValue("\(value)", .center)
                    } else if type == ControlTag.cct {
                        field.attributedStringValue = self.formatCCTValue("\(value)", .center)
                    } else if type == ControlTag.gmm {
                        field.attributedStringValue = self.formatGMMValue("\(value)", .center)
                    } else if type == ControlTag.hue {
                        field.attributedStringValue = self.formatHUEValue("\(value)", .center)
                    } else if type == ControlTag.sat {
                        field.attributedStringValue = self.formatSATValue("\(value)", .center)
                    }
                } else if let slider = subview as? NLSlider {
                    if let dev = self.device {
                        slider.pauseNotify = true
                        if type == ControlTag.brr {
                            slider.currentValue = CGFloat(dev.brrValue.value)
                        } else if type == ControlTag.cct {
                            slider.currentValue = CGFloat(dev.cctValue.value)
                        } else if type == ControlTag.gmm {
                            slider.currentValue = CGFloat(dev.gmmValue.value)
                        }
                        slider.pauseNotify = false
                    }
                }
            }
        }

        view.subviews.forEach { subview in
            if subview.isKind(of: FXView.self) {
                subview.subviews.forEach { ssubview in
                    processSubView(ssubview)
                }
            } else {
                processSubView(subview)
            }
        }
    }

    func updateWithViewObject(_ viewObj: DeviceViewObject) {
        device = viewObj.device
        if let dev = device {
            self.image = ContentManager.shared.fetchCachedLightImage(lightType: dev.lightType)
            updateDeviceName()
            self.nameField.toolTip = "\(dev.rawName)\n\(viewObj.deviceIdentifier)"
            imageFetchOperation?.cancel() // Cancel any ongoing operation
            let operation = ImageFetchOperation(lightType: dev.lightType) { [weak self] image in
                self?.image = image
            }
            ContentManager.shared.operationQueue.addOperation(operation)
            imageFetchOperation = operation
        }

        buildView()

        updateDeviceStatus()

        if debugFakeLights {
            removeGrayOut()
        } else {
            if device?.peripheral == nil {
                grayOut()
            } else {
                removeGrayOut()
            }
        }
    }

    func grayOut() {
        if overlay == nil {
            overlay = BlockingOverlayView(frame: self.view.bounds)
            overlay?.wantsLayer = true
            overlay?.layer?.backgroundColor = NSColor(white: 0.5, alpha: 0.5).cgColor
            overlay?.autoresizingMask = [.width, .height]

            // Label setup
            let label = NSTextField(labelWithString: "Light is not connected")
            label.frame = NSRect(x: 0, y: 5, width: self.view.bounds.width, height: 20)
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.textColor = NSColor.white
            label.alignment = .center
            view.addSubview(label)
            overlay?.addSubview(label)

        }
        if let safeView = overlay {
            safeView.frame = view.bounds
            self.view.addSubview(safeView, positioned: .above, relativeTo: nil)
        }
    }

    func removeGrayOut() {
        if overlay != nil {
            overlay?.removeFromSuperview()
            overlay = nil
        }
    }

    func getCCTValuesFromView() -> (brr: CGFloat, cct: CGFloat, gmm: CGFloat) {
        var brr = 0.0
        var cct = 0.0
        var gmm = 0.0

        if let dev = device {
            brr = CGFloat(dev.brrValue.value)
            cct = CGFloat(dev.cctValue.value)
            gmm = CGFloat(dev.gmmValue.value)
        }

        guard let item = self.lightModeTabView.selectedTabViewItem else {
            return (brr, cct, gmm)
        }
        guard let view = item.view else {
            return (brr, cct, gmm)
        }
        view.subviews.forEach { subview in
            if let slider = subview as? NLSlider {
                if slider.tag == ControlTag.cct.rawValue {
                    cct = slider.currentValue
                } else if slider.tag == ControlTag.brr.rawValue {
                    brr = slider.currentValue
                } else if slider.tag == ControlTag.gmm.rawValue {
                    gmm = slider.currentValue
                }
            }
        }
        return (brr, cct, gmm)
    }

    func getHSIWheelFromView() -> ColorWheel? {
        guard let item = self.lightModeTabView.selectedTabViewItem else {
            return nil
        }
        guard let view = item.view else {
            return nil
        }
        if let btn = view.subviews.first(where: { $0.isKind(of: ColorWheel.self) }) {
            return btn as? ColorWheel
        }
        return nil
    }

    func getHSIBrrSlideFromView() -> NLSlider? {
        guard let item = self.lightModeTabView.selectedTabViewItem else {
            return nil
        }
        guard let view = item.view else {
            return nil
        }
        if let idf = item.identifier as? String {
            if idf == TabId.hsi.rawValue || item.label == "HSI" {
                if let btn = view.subviews.first(where: { $0.isKind(of: NLSlider.self) && $0.tag == ControlTag.brr.rawValue }) {
                    return btn as? NLSlider
                }
            }
        }
        return nil
    }

    func getBrrSlideFromView() -> NLSlider? {
        guard let item = self.lightModeTabView.selectedTabViewItem else {
            return nil
        }
        guard let view = item.view else {
            return nil
        }
        if let btn = view.subviews.first(where: { $0.isKind(of: NLSlider.self) && $0.tag == ControlTag.brr.rawValue }) {
            return btn as? NLSlider
        }
        if let fxview = view.subviews.first(where: { $0.isKind(of: FXView.self) }) {
            if let btn = fxview.subviews.first(where: { $0.isKind(of: NLSlider.self) && $0.tag == ControlTag.brr.rawValue }) {
                return btn as? NLSlider
            }
        }
        return nil
    }

    func getHSIValuesFromView() -> (brr: CGFloat, hue: CGFloat, sat: CGFloat) {
        var hue = 0.0
        var sat = 0.0
        var brr = 0.0

        if let dev = device {
            hue = CGFloat(dev.hueValue.value)
            sat = CGFloat(dev.satValue.value)
            brr = CGFloat(dev.brrValue.value)
        }

        guard let item = self.lightModeTabView.selectedTabViewItem else {
            return (brr, hue, sat)
        }
        guard let view = item.view else {
            return (brr, hue, sat)
        }
        view.subviews.forEach { subview in
            if let slider = subview as? NLSlider {
                if slider.tag == ControlTag.brr.rawValue {
                    brr = slider.currentValue
                }
            } else if let wheel = subview as? ColorWheel {
                if wheel.tag == ControlTag.wheel.rawValue {
                    hue = wheel.color.hueComponent
                    sat = wheel.color.saturationComponent
                }
            }
        }
        return (brr, hue, sat)
    }

    func getFXListButtonFromView() -> NSPopUpButton? {
        guard let item = self.lightModeTabView.selectedTabViewItem else {
            return nil
        }
        guard let view = item.view else {
            return nil
        }
        if let btn = view.subviews.first(where: { $0.isKind(of: NSPopUpButton.self) }) {
            return btn as? NSPopUpButton
        }
        return nil
    }

    func updteFX(_ fxx: Int) {
        if let btn = getFXListButtonFromView() {
            btn.selectItem(withTag: fxx)
            fxClicked(btn)
        }
    }

    func updteBrightness(_ brr: Double) {
        if let brrSlider = getBrrSlideFromView() {
            brrSlider.currentValue = brr
        } else if let dev = device {
            dev.setBRRLightValues(brr)
        }
    }

    func updateHSI(hue: CGFloat, sat: CGFloat, brr: Double?) {
        if let dev = device {
            if dev.supportRGB {
                Logger.debug("brr: \(brr) hue: \(hue) sat: \(sat)")
                let val = getHSIValuesFromView()
                let brrValue = brr != nil ? brr! : val.brr
                let hueVal = Double(hue) / 360.0
                if let wheel = getHSIWheelFromView() {
                    let color = NSColor(calibratedHue: hueVal, saturation: sat, brightness: brrValue, alpha: 1)
                    wheel.setViewColor(color)
                }
                if let brrSlide = getHSIBrrSlideFromView() {
                    brrSlide.pauseNotify = true
                    brrSlide.currentValue = brrValue * brrSlide.maxValue
                    brrSlide.pauseNotify = false
                }
                dev.setRGBLightValues(brr: brrValue, hue: hueVal, hue360: hue, sat: sat)
            }
        }
    }

    func updateCCT(cct: CGFloat, gmm: CGFloat, brr: Double?) {
        if let dev = device {
            Logger.debug("update cct: \(cct) gm: \(gmm) brr: \(brr)")
            guard let item = self.lightModeTabView.selectedTabViewItem else {
                return
            }
            guard let view = item.view else {
                return
            }
            if let idf = item.identifier as? String {
                if idf == TabId.hsi.rawValue {
                    let val = getCCTValuesFromView()
                    let brrValue = brr != nil ? brr! : val.brr
                    dev.setCCTLightValues(brr: brrValue, cct: cct, gmm: gmm)
                }
            }
        }
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        if tabView == lightModeTabView {
            if buildingView {
                return
            }
            if let dev = device {
                if let idf = tabViewItem?.identifier as? String {
                    if idf == TabId.cct.rawValue || tabViewItem?.label == "CCT" {
                        // CCT mode
                        let val = getCCTValuesFromView()
                        dev.setCCTLightValues(brr: CGFloat(val.brr), cct: CGFloat(val.cct), gmm: CGFloat(val.gmm))
                    } else if idf == TabId.source.rawValue || tabViewItem?.label == "Light Source" {
                        // CCT mode
                        let val = getCCTValuesFromView()
                        dev.setCCTLightValues(brr: CGFloat(val.brr), cct: CGFloat(val.cct), gmm: CGFloat(val.gmm))
                    } else if idf == TabId.hsi.rawValue || tabViewItem?.label == "HSI" {
                        // HSI mode
                        if dev.supportRGB {
                            let val = getHSIValuesFromView()
                            dev.setRGBLightValues(brr: CGFloat(val.brr), hue: val.hue, hue360: val.hue * 360.0, sat: val.sat)
                        }
                    } else if idf == TabId.scene.rawValue || tabViewItem?.label == "FX" {
                        // scene mode
                        if let btn = getFXListButtonFromView() {
                            btn.selectItem(withTag: Int(dev.channel.value))
                            fxClicked(btn)
                        }
                    } else {
                        // unknow view
                    }
                    dev.lastTab = idf
                }
            }
        }
    }
}
