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
    @IBOutlet var button2: NSButton!

    var light: NeewerLight? {
        didSet {
            if let safeLight = light {
                imageFetchOperation?.cancel() // Cancel any ongoing operation
                let operation = ImageFetchOperation(lightType: safeLight.lightType) { [weak self] image in
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
        button2?.isHidden = true
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

    private func getButtonMinX() -> CGFloat {
        var minX = self.bounds.width
        if let btn = button {
            if !btn.isHidden {
                if btn.frame.origin.x < minX {
                    minX = btn.frame.origin.x
                }
            }
        }
        if let btn = button2 {
            if !btn.isHidden {
                if btn.frame.origin.x < minX {
                    minX = btn.frame.origin.x
                }
            }
        }
        return minX
    }

    private func resetLayout() {
        var showBtn = false
        if let btn = button2 {
            showBtn = !btn.isHidden
        }
        var frame1 = titleLabel.frame
        var frame2 = subtitleLabel.frame
        if showBtn {
            frame1.size.width = self.bounds.width - 220
            frame2.size.width = self.bounds.width - 220
            titleLabel.frame = frame1
            subtitleLabel.frame = frame2
        } else {
            frame1.size.width = self.bounds.width - 100
            frame2.size.width = self.bounds.width - 100
        }
        titleLabel.frame = frame1
        subtitleLabel.frame = frame2
    }

    // Mouse entered the tracking area
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        button?.isHidden = false
        button2?.isHidden = false
        resetLayout()
    }

    // Mouse exited the tracking area
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        button?.isHidden = true
        button2?.isHidden = true
        resetLayout()
    }

    // Ensure the button is hidden when the view is reused
    override func prepareForReuse() {
        super.prepareForReuse()
        button?.isHidden = true
        button2?.isHidden = true
        resetLayout()
    }
}
