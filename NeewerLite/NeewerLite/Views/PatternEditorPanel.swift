import Cocoa

final class PatternEditorPanel: NSWindowController, NSTextViewDelegate {
    private var panel: NSPanel!
    private var saveButton: NSButton!
    private var cancelButton: NSButton!
    private var resetButton: NSButton!
    private var validButton: NSButton!
    private var helpButton: NSButton!
    private var onSave: ((String?) -> Void)?
    var textView: NSTextView!

    private let patternVariables = [
        "cmdtag", "powertag", "ccttag", "hsitag", "rgbtag", "size", "checksum"
    ]
    private let typeSuggestions = [
        "uint8", "uint16_le", "uint16_be"
    ]
    private let enumRangeSuggestions = [
        "enum(1=on,2=off)", "range(0,255)"
    ]

    private var autocompletePopover: NSPopover?
    private var autocompleteTableView: AutocompleteTableView?
    private var currentSuggestions: [String] = []

    enum AutocompleteContext {
        case variable
        case type
        case enumOrRange
    }

    convenience init(initialPattern: String, onSave: @escaping (String?) -> Void) {
        self.init(window: nil)
        self.onSave = onSave

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Edit Command Patterns"

        textView = NSTextView(frame: NSRect(x: 20, y: 60, width: 460, height: 320))
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.string = initialPattern
        textView.delegate = self
        panel.contentView?.addSubview(textView)

        var x = 400
        saveButton = NSButton(frame: NSRect(x: x, y: 20, width: 80, height: 30))
        saveButton.title = "Save"
        saveButton.bezelStyle = .rounded
        saveButton.action = #selector(saveAction)
        saveButton.target = self
        panel.contentView?.addSubview(saveButton)
        x -= 85

        validButton = NSButton(frame: NSRect(x: x, y: 20, width: 80, height: 30))
        validButton.title = "Valid"
        validButton.bezelStyle = .rounded
        validButton.action = #selector(validAction)
        validButton.target = self
        panel.contentView?.addSubview(validButton)
        x -= 85
        
        resetButton = NSButton(frame: NSRect(x: x, y: 20, width: 80, height: 30))
        resetButton.title = "Discard"
        resetButton.bezelStyle = .rounded
        resetButton.action = #selector(resetAction)
        resetButton.target = self
        panel.contentView?.addSubview(resetButton)
        x -= 85

        
        cancelButton = NSButton(frame: NSRect(x: 15, y: 20, width: 80, height: 30))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.action = #selector(cancelAction)
        cancelButton.target = self
        panel.contentView?.addSubview(cancelButton)
        
        helpButton = NSButton(frame: NSRect(x: cancelButton.frame.maxX + 5, y: 20, width: 80, height: 30))
        helpButton.title = "Help"
        helpButton.bezelStyle = .rounded
        helpButton.action = #selector(helpAction)
        helpButton.target = self
        panel.contentView?.addSubview(helpButton)
        
        self.window = panel
        highlightJSON()
    }

    func show() {
        NSApp.mainWindow?.beginSheet(panel, completionHandler: nil)
    }
    
    @objc private func helpAction() {
        if let url = URL(string: "https://github.com/keefo/NeewerLite/wiki/Command-Pattern-Guide") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func saveAction() {
        let text = textView.string
        var allValid = true
        var invalidKeys: [String: String] = [:]

        // Try to decode as [String: String]
        if let data = text.data(using: .utf8),
        let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, pattern) in dict {
                let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
                if !isValid {
                    allValid = false
                    invalidKeys[key] = error
                }
            }
        } else {
            allValid = false
        }
        
        if allValid {
            onSave?(textView.string)
            closePanel()
        }
        else {
            let alert = NSAlert()
            alert.messageText = "Some patterns are INVALID!"
            if invalidKeys.isEmpty {
                alert.informativeText = "❌ JSON is invalid or not a dictionary."
            } else {
                alert.informativeText = "❌ Invalid patterns: " + invalidKeys.map { "\($0): \($1)" }.joined(separator: ", ")
            }
            alert.alertStyle = .warning
            alert.beginSheetModal(for: panel, completionHandler: nil)
        }
    }

    @objc private func cancelAction() {
        onSave?(nil)
        closePanel()
    }

    @objc private func resetAction() {
        onSave?("reset")
        closePanel()
    }

   @objc private func validAction() {
        let text = textView.string
        var allValid = true
        var invalidKeys: [String: String] = [:]

        // Try to decode as [String: String]
        if let data = text.data(using: .utf8),
        let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, pattern) in dict {
                let (isValid, error) = CommandPatternParser.validate(pattern: pattern)
                if !isValid {
                    allValid = false
                    invalidKeys[key] = error
                }
            }
        } else {
            allValid = false
        }

        let alert = NSAlert()
        if allValid {
            alert.messageText = "All patterns are valid!"
            alert.informativeText = "✅ Valid."
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Some patterns are INVALID!"
            if invalidKeys.isEmpty {
                alert.informativeText = "❌ JSON is invalid or not a dictionary."
            } else {
                alert.informativeText = "❌ Invalid patterns: " + invalidKeys.map { "\($0): \($1)" }.joined(separator: ", ")
            }
            alert.alertStyle = .warning
        }
        alert.beginSheetModal(for: panel, completionHandler: nil)
    }

    private func closePanel() {
        panel.orderOut(nil)
        if let parent = panel.sheetParent {
            parent.endSheet(panel)
        } else {
            NSApp.mainWindow?.endSheet(panel)
        }
    }

    // MARK: - Syntax Highlighting

    func textDidChange(_ notification: Notification) {
        highlightJSON()
    }

    private func highlightJSON() {
        let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
        let text = textView.string
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: attributed.length)

        attributed.addAttribute(.font, value: codeFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        let keyPattern = #""([^"]+)"\s*:"# // JSON keys
        let stringPattern = #":\s*"([^"]*)""# // JSON string values
        let numberPattern = #":\s*([0-9\.\-]+)"# // JSON numbers
        let bracePattern = #"[{}\[\],:]"# // Braces, brackets, colons, commas

        if let regex = try? NSRegularExpression(pattern: keyPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: NSColor.systemBlue, range: match.range(at: 1))
            }
        }
        if let regex = try? NSRegularExpression(pattern: stringPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: NSColor.systemBrown, range: match.range(at: 1))
            }
        }
        if let regex = try? NSRegularExpression(pattern: numberPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: NSColor.systemPurple, range: match.range(at: 1))
            }
        }
        if let regex = try? NSRegularExpression(pattern: bracePattern) {
            for match in regex.matches(in: text, range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: NSColor.systemGray, range: match.range)
            }
        }
        // Highlight predefined variables like {cmdtag}
        let varPattern = "\\{(" + patternVariables.joined(separator: "|") + ")\\}"
        if let regex = try? NSRegularExpression(pattern: varPattern) {
            for match in regex.matches(in: text, range: fullRange) {
                attributed.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: match.range)
                attributed.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: match.range)
            }
        }
        // --- JSON validation and error highlighting ---
        var jsonErrorRange: NSRange?
        do {
            let data = text.data(using: .utf8) ?? Data()
            _ = try JSONSerialization.jsonObject(with: data)
            panel.title = "Edit Command Patterns"
        } catch let error as NSError {
            if let errorRange = error.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                jsonErrorRange = NSRange(location: errorRange, length: min(1, attributed.length - errorRange))
            }
            panel.title = "Edit Command Patterns (Invalid JSON)"
        }
        if let errorRange = jsonErrorRange, errorRange.location < attributed.length {
            attributed.addAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.3), range: errorRange)
        }

        let selectedRange = textView.selectedRange()
        textView.textStorage?.setAttributedString(attributed)
        textView.setSelectedRange(selectedRange)
    }

    // MARK: - Autocomplete
    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let nsText = textView.string as NSString
        let cursor = affectedCharRange.location

        // Show variable autocomplete after '{'
        if replacementString == "{" {
            DispatchQueue.main.async { [weak self] in
                self?.showAutocomplete(for: .variable)
            }
        }
        // If autocomplete is open and user types anything else, close it
        else if autocompletePopover?.isShown == true {
            closeAutocomplete()
        }
        return true
    }

    private func showAutocomplete(for context: AutocompleteContext) {
        if autocompletePopover?.isShown == true { return }

        switch context {
        case .variable:
            currentSuggestions = patternVariables
        case .type:
            currentSuggestions = typeSuggestions
        case .enumOrRange:
            currentSuggestions = enumRangeSuggestions
        }

        let tableView = AutocompleteTableView()
        tableView.autocompleteDelegate = self
        autocompleteTableView = tableView
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("var"))
        column.width = 180
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.dataSource = self
        tableView.delegate = self
        tableView.reloadData()

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: min(200, currentSuggestions.count * 22)))
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true

        let contentView = NSView(frame: scrollView.frame)
        contentView.addSubview(scrollView)

        let popover = NSPopover()
        popover.contentViewController = NSViewController()
        popover.contentViewController?.view = contentView
        popover.behavior = .applicationDefined
        self.autocompletePopover = popover

        // Position at caret
        if let selectedRange = textView.selectedRanges.first as? NSRange,
           let layoutManager = textView.layoutManager,
           let textContainer = textView.textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: selectedRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            let containerOrigin = textView.textContainerOrigin
            let caretRect = NSRect(x: rect.origin.x + containerOrigin.x, y: rect.origin.y + containerOrigin.y, width: 1, height: rect.height)
            popover.show(relativeTo: caretRect, of: textView, preferredEdge: .maxY)
        }

        // Make table view first responder and select first row
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            tableView.window?.makeFirstResponder(tableView)
            if self.currentSuggestions.count > 0 {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
    }

    func insertSelectedAutocomplete() {
        guard let tableView = autocompleteTableView else { return }
        let row = tableView.selectedRow
        if row >= 0 && row < currentSuggestions.count {
            let insertion = currentSuggestions[row]
            if let selectedRange = textView.selectedRanges.first as? NSRange {
                textView.insertText(insertion, replacementRange: selectedRange)
            }
        }
        closeAutocomplete()
    }

    func closeAutocomplete() {
        autocompletePopover?.close()
        autocompletePopover = nil
        autocompleteTableView = nil
        textView.window?.makeFirstResponder(textView)
    }
}

// MARK: - AutocompleteTableView

class AutocompleteTableView: NSTableView {
    weak var autocompleteDelegate: PatternEditorPanel?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return or Enter
            autocompleteDelegate?.insertSelectedAutocomplete()
        case 53: // Escape
            autocompleteDelegate?.closeAutocomplete()
        case 125: // Down arrow
            let next = min(selectedRow + 1, numberOfRows - 1)
            selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        case 126: // Up arrow
            let prev = max(selectedRow - 1, 0)
            selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
        default:
            autocompleteDelegate?.closeAutocomplete()
            if let textView = autocompleteDelegate?.textView {
                textView.window?.makeFirstResponder(textView)
                textView.keyDown(with: event)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0 {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            autocompleteDelegate?.insertSelectedAutocomplete()
        }
    }
}

// MARK: - NSTableViewDataSource & Delegate
extension PatternEditorPanel: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return currentSuggestions.count
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTextField(labelWithString: currentSuggestions[row])
        cell.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
        return cell
    }
}
