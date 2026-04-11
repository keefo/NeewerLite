//
//  GelSwatchCell.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/10/26.
//

import Cocoa

/// A single gel-swatch item inside the NSCollectionView in the Gels tab.
final class GelSwatchCell: NSCollectionViewItem {

    static let identifier = NSUserInterfaceItemIdentifier("GelSwatchCell")

    private let swatchView = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let codeLabel = NSTextField(labelWithString: "")

    var gel: NeewerGel? {
        didSet { configure() }
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 68, height: 68))
        view.wantsLayer = true

        // Swatch colour square
        swatchView.wantsLayer = true
        swatchView.layer?.cornerRadius = 6
        swatchView.frame = NSRect(x: 4, y: 26, width: 60, height: 36)
        swatchView.autoresizingMask = [.minXMargin, .maxXMargin]
        view.addSubview(swatchView)

        // Gel name label
        nameLabel.font = NSFont.systemFont(ofSize: 9, weight: .medium)
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 0, y: 12, width: 68, height: 14)
        nameLabel.autoresizingMask = [.width]
        view.addSubview(nameLabel)

        // Manufacturer + code label
        codeLabel.font = NSFont.systemFont(ofSize: 8)
        codeLabel.alignment = .center
        codeLabel.textColor = NSColor.secondaryLabelColor
        codeLabel.frame = NSRect(x: 0, y: 0, width: 68, height: 12)
        codeLabel.autoresizingMask = [.width]
        view.addSubview(codeLabel)
    }

    override var isSelected: Bool {
        didSet { updateSelectionRing() }
    }

    private func configure() {
        guard let gel = gel else { return }
        swatchView.layer?.backgroundColor = gel.swatchColor.cgColor
        nameLabel.stringValue = gel.name
        if !gel.manufacturer.isEmpty && !gel.code.isEmpty {
            codeLabel.stringValue = "\(gel.manufacturer) \(gel.code)"
        } else {
            codeLabel.stringValue = ""
        }
        updateSelectionRing()
    }

    private func updateSelectionRing() {
        view.layer?.borderWidth = isSelected ? 2.0 : 0
        view.layer?.borderColor = isSelected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        view.layer?.cornerRadius = isSelected ? 8 : 0
    }
}
