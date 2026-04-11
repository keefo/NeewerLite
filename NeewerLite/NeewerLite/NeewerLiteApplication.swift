//
//  NeewerLiteApplication.swift
//  NeewerLite
//
//  Created to prevent app activation on URL events
//

import Cocoa

class NeewerLiteApplication: NSApplication {
    
    private var shouldPreventActivation = false
    
    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
    }
    
    // This is called BEFORE the app activates from URL scheme
    override func activate(ignoringOtherApps flag: Bool) {
        // Only prevent activation if we're handling a URL event in background
        if shouldPreventActivation {
            Logger.info(LogTag.app, "🔗 Prevented activation from URL event")
            return
        }
        super.activate(ignoringOtherApps: flag)
    }
    
    func setShouldPreventActivation(_ prevent: Bool) {
        shouldPreventActivation = prevent
    }
}
