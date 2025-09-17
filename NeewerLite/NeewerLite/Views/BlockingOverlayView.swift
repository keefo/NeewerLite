//
//  BlockingOverlayView.swift
//  NeewerLite
//
//  Created by Xu Lian on 10/25/23.
//

import Foundation
import Cocoa

class BlockingOverlayView: NSView {
    override func mouseDown(with event: NSEvent) { }
    override func mouseUp(with event: NSEvent) { }
    var bypassRect: NSRect?
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Always return self to capture all mouse events
        if let bypassRect, bypassRect.contains(point) {
            return nil
        }
        return self
    }
}
