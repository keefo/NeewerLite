//
//  RenameViewController.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/4/23.
//

import Foundation
import Cocoa

class PopoverContentViewController: NSViewController {
    var textField: NSTextField!
    var okButton: NSButton!
    var cancelButton: NSButton!

    var onOK: ((String) -> Bool)?
    var onCancel: (() -> Void)?

    init() {
        super.init(nibName: nil, bundle: nil)
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))

        // Text field setup
        textField = NSTextField(frame: NSRect(x: 20, y: 40, width: 160, height: 20))
        textField.placeholderString = "Give a label to your light..."
        view.addSubview(textField)

        // OK button setup
        okButton = NSButton(frame: NSRect(x: 200-60-10, y: 10, width: 60, height: 20))
        okButton.title = "OK"
        okButton.target = self
        okButton.action = #selector(okButtonClicked)
        view.addSubview(okButton)

        // Cancel button setup
        cancelButton = NSButton(frame: NSRect(x: okButton.frame.minX-80, y: 10, width: 80, height: 20))
        cancelButton.title = "Cancel"
        cancelButton.target = self
        cancelButton.action = #selector(cancelButtonClicked)
        view.addSubview(cancelButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func okButtonClicked() {
        let res = onOK?(textField.stringValue)
        if res == nil || res == true {
            view.window?.close()
        }
        if res == false {
            
        }
    }

    @objc func cancelButtonClicked() {
        onCancel?()
        view.window?.close()
    }
}

class RenameViewController: NSViewController {

    let popover = NSPopover()
    private let pvc = PopoverContentViewController()
    
    var onOK: ((String) -> Bool)? {
        didSet {
            pvc.onOK = { [weak self] text in
                // Do something with text here
                if let blk = self?.onOK {
                    return blk(text)
                }
                return true
            }
        }
    }

    var onCancel: (() -> Void)? {
        didSet {
            pvc.onCancel = { [weak self] in
                // Handle cancel here
                if let blk = self?.onCancel {
                    blk()
                }
            }
        }
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        // Configure the popover
        popover.contentViewController = pvc
        popover.behavior = .transient
        popover.animates = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Configure the popover
        popover.contentViewController = pvc
        popover.behavior = .transient
        popover.animates = true
    }

    func setCurrentValue(_ text: String) {
        pvc.textField.stringValue = text
    }

    func showPopover(sender: NSButton) {
        // Show the popover on the button click
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
}
