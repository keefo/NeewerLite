//
//  MySplitViewDelegate.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/14/23.
//

import Foundation
import Cocoa

class MySplitViewDelegate: NSObject, NSSplitViewDelegate {

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview subview: NSView) -> Bool {
        // Assuming the left view is the first subview
        return subview != splitView.subviews.first
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            // Assuming the left view is the first subview and the first divider is adjusting the left view
            return 400 // minimum width for the left view
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            // The maximum position for the left edge of the first divider
            // This ensures that the right pane does not get smaller than 200 pixels
            // Calculate this based on the splitView's width minus 200 pixels for the right pane
            let splitViewWidth = splitView.bounds.width
            return splitViewWidth - 200
        }
        return proposedMaximumPosition
    }
}
