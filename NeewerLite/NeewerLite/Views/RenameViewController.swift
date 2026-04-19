//
//  RenameViewController.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/4/23.
//

import Foundation
import Cocoa

class RenameViewController: NSObject {

    // Reference to the sheet's text field
    private var titleTextField: NSTextField?
    private var sheetTextField: NSTextField?

    var sheetWindow = NSWindow (
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 120),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )

    var onOK: ((String) -> Bool)?

    override init() {
        super.init()

        titleTextField = NSTextField(frame: NSRect(x: 20, y: 75, width: 360, height: 24))
        titleTextField?.stringValue = "Enter a new name for your light".localized
        titleTextField?.isEditable = false
        titleTextField?.isSelectable = false
        titleTextField?.isBordered = false
        titleTextField?.drawsBackground = false
        titleTextField?.lineBreakMode = .byTruncatingTail
        titleTextField?.autoresizingMask = [.width]
        sheetWindow.contentView?.addSubview(titleTextField!)

        // Set up the text field
        let textField = NSTextField(frame: NSRect(x: 20, y: 50, width: 360, height: 24))
        textField.placeholderString = "Enter a new name for your light".localized
        textField.autoresizingMask = [.width]
        sheetWindow.contentView?.addSubview(textField)

        // Set up the OK button
        let okButton = NSButton(title: "OK".localized, target: self, action: #selector(okButtonClicked(_:)))
        okButton.bezelStyle = .rounded
        okButton.sizeToFit()
        okButton.frame.origin = NSPoint(x: 400 - 20 - okButton.frame.width, y: 10)
        okButton.autoresizingMask = [.minXMargin]
        sheetWindow.contentView?.addSubview(okButton)

        // Set up the Cancel button
        let cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelButtonClicked(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.sizeToFit()
        cancelButton.frame.origin = NSPoint(x: okButton.frame.minX - cancelButton.frame.width - 5, y: 10)
        cancelButton.autoresizingMask = [.minXMargin]
        sheetWindow.contentView?.addSubview(cancelButton)

        // Keep a reference to the text field if needed
        self.sheetTextField = textField
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setCurrentValue(_ text: String) {
        sheetTextField?.stringValue = text
    }

    @objc func okButtonClicked(_ sender: NSButton) {
        let enteredText = self.sheetTextField?.stringValue ?? ""
        if let blk = self.onOK {
            if blk(enteredText) {
                if let sheetWindow = sender.window, let mainWindow = NSApplication.shared.mainWindow {
                    mainWindow.endSheet(sheetWindow, returnCode: .OK)
                }
            }
        }
    }

    @objc func cancelButtonClicked(_ sender: NSButton) {
        // User canceled, maybe handle this if needed
        // ...
        if let sheetWindow = sender.window, let mainWindow = NSApplication.shared.mainWindow {
            mainWindow.endSheet(sheetWindow, returnCode: .OK)
        }
    }
}
