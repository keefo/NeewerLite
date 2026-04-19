//
//  MyLightTableCellView.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/1/23.
//

import Foundation
import Cocoa

class MyLightTableCellView: NSTableCellView {
    var imageFetchOperation: ImageFetchOperation?

    @IBOutlet var iconImageView: NSImageView!
    @IBOutlet var titleLabel: NSTextField!
    @IBOutlet var subtitleLabel: NSTextField!
    @IBOutlet var button: NSButton!

    // Trailing constraints: swap between cell-trailing and button-leading
    private var titleTrailingToCell: NSLayoutConstraint?
    private var titleTrailingToButton: NSLayoutConstraint?
    private var subtitleTrailingToCell: NSLayoutConstraint?
    private var subtitleTrailingToButton: NSLayoutConstraint?

    var light: NeewerLight? {
        didSet {
            if let safeLight = light {
                imageFetchOperation?.cancel() // Cancel any ongoing operation
                let operation = ImageFetchOperation(lightType: safeLight.lightType, productId: safeLight.productId) { [weak self] image in
                    self?.iconImageView?.image = image
                }
                ContentManager.shared.operationQueue.addOperation(operation)
                imageFetchOperation = operation
            }
        }
    }

    // NSTrackingArea to track the mouse hover event
    private var trackingArea: NSTrackingArea?
    var isConnected: Bool = false {
        didSet {
            if isConnected {
                titleLabel.textColor = NSColor.labelColor
                subtitleLabel.textColor = NSColor.secondaryLabelColor
            } else {
                titleLabel.textColor = NSColor.disabledControlTextColor
                subtitleLabel.textColor = NSColor.disabledControlTextColor
            }
        }
    }

    override func awakeFromNib() {
        super.awakeFromNib()

        // Customize the appearance and behavior of your elements here
        titleLabel?.font = NSFont.systemFont(ofSize: 14)
        subtitleLabel?.font = NSFont.systemFont(ofSize: 12)
        titleLabel?.isSelectable = true

        button?.isHidden = true

        setupTrailingConstraints()
    }

    private func setupTrailingConstraints() {
        guard let titleLabel = titleLabel, let subtitleLabel = subtitleLabel, let button = button else { return }

        // Button must not be compressed when shown
        button.setContentCompressionResistancePriority(.required, for: .horizontal)

        // Find the XIB trailing-to-cell constraints by identifier
        for constraint in self.constraints {
            if constraint.identifier == "titleTrailing" {
                titleTrailingToCell = constraint
            }
            if constraint.identifier == "subtitleTrailing" {
                subtitleTrailingToCell = constraint
            }
        }

        // Create alternative trailing constraints: label.trailing = button.leading - 8
        titleTrailingToButton = titleLabel.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8)
        subtitleTrailingToButton = subtitleLabel.trailingAnchor.constraint(equalTo: button.leadingAnchor, constant: -8)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        // Remove the old tracking area if it exists
        if let existingTrackingArea = trackingArea {
            self.removeTrackingArea(existingTrackingArea)
        }

        // Define the options for the tracking area
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]

        // Create a new tracking area that covers the entire view
        trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)

        // Add the new tracking area to the view
        self.addTrackingArea(trackingArea!)

        if let loc = self.window?.mouseLocationOutsideOfEventStream {
            let mouseLocation = self.convert(loc, from: nil)
            if let nextEvent = self.window?.currentEvent {
                if self.bounds.contains(mouseLocation) {
                    self.mouseEntered(with: nextEvent)
                } else {
                    self.mouseExited(with: nextEvent)
                }
            }
        }
    }

    private func resetLayout() {
        let showButton = !(button?.isHidden ?? true)
        titleTrailingToCell?.isActive = !showButton
        titleTrailingToButton?.isActive = showButton
        subtitleTrailingToCell?.isActive = !showButton
        subtitleTrailingToButton?.isActive = showButton
    }

    // Mouse entered the tracking area
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        button?.isHidden = false
        resetLayout()
    }

    // Mouse exited the tracking area
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        button?.isHidden = true
        resetLayout()
    }

    // Ensure the button is hidden when the view is reused
    override func prepareForReuse() {
        super.prepareForReuse()
        button?.isHidden = true
        resetLayout()
    }
}
