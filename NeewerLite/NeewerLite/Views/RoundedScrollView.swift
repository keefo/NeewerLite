//
//  RoundedScrollView.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/4/23.
//

import Foundation
import Cocoa

class RoundedScrollView: NSScrollView {

    var bgColor: NSColor = NSColor(calibratedWhite: 0.5, alpha: 0.03)
    var borderColor: NSColor = NSColor(calibratedWhite: 0.5, alpha: 0.21)
    var borderWidth: CGFloat = 1.0
    var cornerRadius: CGFloat = 10.0

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Assuming that documentView is an NSTableView
        if let tableView = self.documentView as? NSTableView {
            // Get the height of the content of the table view
            let contentHeight = tableView.numberOfRows > 0 ? tableView.rect(ofRow: tableView.numberOfRows - 1).maxY : 0

            // Create a path with rounded corners that matches the content height
            let contentRect = CGRect(x: 0, y: 0, width: self.bounds.width, height: contentHeight + 10)

            // Clip the drawing to the rounded path
            let roundedPath = NSBezierPath(roundedRect: contentRect,
                                           xRadius: cornerRadius,
                                           yRadius: cornerRadius)
            roundedPath.addClip()

            // Draw the background
            bgColor.setFill()
            roundedPath.fill()

            // Stroke the border
            borderColor.setStroke()
            roundedPath.lineWidth = borderWidth
            roundedPath.stroke()
        }
        // Continue with the rest of the drawing, if necessary
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        wantsLayer = true  // Opt in to layer-backing
        layer?.cornerRadius = cornerRadius
        layer?.masksToBounds = true
        self.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 40, right: 0)
    }
}
