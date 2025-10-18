//
//  LogMonitorViewController.swift
//  NeewerLite
//
//  Created by Xu Lian on 7/27/25.
//

import Cocoa
import os.log

class LogMonitorViewController: NSViewController, NSWindowDelegate {

    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var levelSegmentedControl: NSSegmentedControl!
    private var categorySegmentedControl: NSSegmentedControl!
    private var startStopButton: NSButton!
    private var clearButton: NSButton!
    private var exportButton: NSButton!

    private var logStreamTask: Process?
    private var isStreaming = false
    private let subsystem = "com.beyondcow.neewerlite"
    private var logBuffer: [String] = []
    private let maxLogLines = 1000

    // Window owned by this view controller
    private var logWindow: NSWindow?

    // Flag to prevent any operations during deallocation
    private var isDeallocating = false

    override func loadView() {
        // Create the main view
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setupUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureUI()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Auto-start streaming when window appears
        if !isStreaming {
            startLogStreaming()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        // Set flag early and immediately stop everything
        isDeallocating = true
        isStreaming = false

        // Immediately clear all handlers to prevent any callbacks
        if let task = logStreamTask {
            task.terminationHandler = nil
            if let pipe = task.standardOutput as? Pipe {
                pipe.fileHandleForReading.readabilityHandler = nil
            }
        }

        // Then call the stop method
        stopLogStreaming()
    }

    deinit {
        // Set deallocation flag immediately to prevent any further operations
        isDeallocating = true

        // Ensure streaming is stopped first
        isStreaming = false

        // Clean up process safely with more defensive checks
        if let task = logStreamTask {
            // Clear handlers first to prevent callbacks during deallocation
            task.terminationHandler = nil

            if let pipe = task.standardOutput as? Pipe {
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = nil
                // Close handle if possible, but don't crash if it fails
                do {
                    try handle.close()
                } catch {
                    // Handle might already be closed during deallocation
                }
            }

            // Terminate process if running, but don't wait
            if task.isRunning {
                task.terminate()
            }
        }

        // Clear all references
        logStreamTask = nil
        logBuffer.removeAll()

        // Clear window reference if it exists
        if let window = logWindow {
            window.delegate = nil
            window.contentViewController = nil
        }
        logWindow = nil

        // Don't access UI elements in deinit as they might already be deallocating
        // The UI cleanup will happen naturally through the view hierarchy
    }

    private func setupUI() {
        // Title label
        let titleLabel = NSTextField(labelWithString: "NeewerLite Log Monitor")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)

        // Level label
        let levelLabel = NSTextField(labelWithString: "Level:")
        levelLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(levelLabel)

        // Level segmented control
        levelSegmentedControl = NSSegmentedControl(
            labels: ["All", "Debug", "Info", "Default", "Error"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(levelChanged(_:)))
        levelSegmentedControl.selectedSegment = 0
        levelSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(levelSegmentedControl)

        // Category label
        let categoryLabel = NSTextField(labelWithString: "Category:")
        categoryLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(categoryLabel)

        // Category segmented control
        categorySegmentedControl = NSSegmentedControl(
            labels: ["All", "App", "Bluetooth", "WiFi", "Server", "UI"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(categoryChanged(_:)))
        categorySegmentedControl.selectedSegment = 0
        categorySegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(categorySegmentedControl)

        // Create scroll view and text view
        scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.isEditable = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        view.addSubview(scrollView)

        // Buttons
        startStopButton = NSButton(
            title: "Start", target: self, action: #selector(startStopClicked(_:)))
        startStopButton.bezelStyle = .rounded
        startStopButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startStopButton)

        clearButton = NSButton(title: "Clear", target: self, action: #selector(clearClicked(_:)))
        clearButton.bezelStyle = .rounded
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearButton)

        exportButton = NSButton(title: "Export", target: self, action: #selector(exportClicked(_:)))
        exportButton.bezelStyle = .rounded
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exportButton)

        // Setup constraints
        NSLayoutConstraint.activate([
            // Title label
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            // Level controls
            levelLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 15),
            levelLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),

            levelSegmentedControl.centerYAnchor.constraint(equalTo: levelLabel.centerYAnchor),
            levelSegmentedControl.leadingAnchor.constraint(
                equalTo: levelLabel.trailingAnchor, constant: 10),
            levelSegmentedControl.widthAnchor.constraint(equalToConstant: 300),

            // Category controls
            categoryLabel.centerYAnchor.constraint(equalTo: levelLabel.centerYAnchor),
            categoryLabel.leadingAnchor.constraint(
                equalTo: levelSegmentedControl.trailingAnchor, constant: 20),

            categorySegmentedControl.centerYAnchor.constraint(equalTo: categoryLabel.centerYAnchor),
            categorySegmentedControl.leadingAnchor.constraint(
                equalTo: categoryLabel.trailingAnchor, constant: 10),
            categorySegmentedControl.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            categorySegmentedControl.widthAnchor.constraint(equalToConstant: 340),

            // Scroll view (main content area)
            scrollView.topAnchor.constraint(
                equalTo: levelSegmentedControl.bottomAnchor, constant: 15),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollView.bottomAnchor.constraint(equalTo: startStopButton.topAnchor, constant: -15),

            // Buttons
            startStopButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            startStopButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            startStopButton.widthAnchor.constraint(equalToConstant: 80),
            startStopButton.heightAnchor.constraint(equalToConstant: 32),

            clearButton.centerYAnchor.constraint(equalTo: startStopButton.centerYAnchor),
            clearButton.leadingAnchor.constraint(
                equalTo: startStopButton.trailingAnchor, constant: 10),
            clearButton.widthAnchor.constraint(equalToConstant: 80),
            clearButton.heightAnchor.constraint(equalToConstant: 32),

            exportButton.centerYAnchor.constraint(equalTo: startStopButton.centerYAnchor),
            exportButton.leadingAnchor.constraint(
                equalTo: clearButton.trailingAnchor, constant: 10),
            exportButton.widthAnchor.constraint(equalToConstant: 80),
            exportButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func configureUI() {
        // Configure text view
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor

        // Ensure text view is properly set up for display
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        textView.needsDisplay = true

        // Add a test message to verify text view is working
        let testMessage = NSAttributedString(string: "Log Monitor Ready - Waiting for logs...\n")
        textView.textStorage?.append(testMessage)
    }

    @objc private func levelChanged(_ sender: NSSegmentedControl) {
        if isStreaming {
            restartLogStreaming()
        }
    }

    @objc private func categoryChanged(_ sender: NSSegmentedControl) {
        if isStreaming {
            restartLogStreaming()
        }
    }

    @objc private func startStopClicked(_ sender: NSButton) {
        if isStreaming {
            stopLogStreaming()
        } else {
            startLogStreaming()
        }
    }

    @objc private func clearClicked(_ sender: NSButton) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isDeallocating else { return }
            self.textView?.string = ""
            self.logBuffer.removeAll()
        }
    }

    @objc private func exportClicked(_ sender: NSButton) {
        guard !isDeallocating else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "neewerlite_logs_\(Int(Date().timeIntervalSince1970)).txt"

        guard let window = view.window, !isDeallocating else { return }

        savePanel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, !self.isDeallocating else { return }
            if response == .OK, let url = savePanel.url {
                let logContent = self.logBuffer.joined(separator: "\n")
                try? logContent.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func startLogStreaming() {
        guard !isStreaming else { return }

        logStreamTask = Process()
        logStreamTask?.launchPath = "/usr/bin/log"

        var arguments = ["stream", "--style", "compact", "--info", "--debug"]

        // Add predicate based on selections
        var predicateComponents: [String] = []
        predicateComponents.append("subsystem == '\(subsystem)'")

        // Add level filter
        switch levelSegmentedControl.selectedSegment {
        case 1: predicateComponents.append("messageType == 'debug'")
        case 2: predicateComponents.append("messageType == 'info'")
        case 3: predicateComponents.append("messageType == 'default'")
        case 4: predicateComponents.append("messageType == 'error'")
        default: break  // All levels
        }

        // Add category filter
        switch categorySegmentedControl.selectedSegment {
        case 1: predicateComponents.append("category == 'App'")
        case 2: predicateComponents.append("category == 'Bluetooth'")
        case 3: predicateComponents.append("category == 'WiFi'")
        case 4: predicateComponents.append("category == 'Server'")
        case 5: predicateComponents.append("category == 'UI'")
        default: break  // All categories
        }

        if !predicateComponents.isEmpty {
            arguments.append("--predicate")
            arguments.append(predicateComponents.joined(separator: " && "))
        }

        logStreamTask?.arguments = arguments

        let pipe = Pipe()
        logStreamTask?.standardOutput = pipe

        let outputHandle = pipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            // Capture self weakly to avoid retain cycles
            guard let self = self else {
                // Clear the handler if self is deallocated
                handle.readabilityHandler = nil
                return
            }

            // Check deallocation flag first - this is critical
            guard !self.isDeallocating else {
                handle.readabilityHandler = nil
                return
            }

            // Check if we're still streaming before processing
            guard self.isStreaming else {
                handle.readabilityHandler = nil
                return
            }

            // Additional safety check - make sure we still have a valid text view
            guard self.textView != nil else {
                handle.readabilityHandler = nil
                return
            }

            let data = handle.availableData
            guard !data.isEmpty else { return }

            if let output = String(data: data, encoding: .utf8) {
                self.appendLogOutput(output)
            }
        }

        logStreamTask?.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                // Use weak self to avoid retain cycles
                guard let self = self else { return }

                // Check deallocation flag
                guard !self.isDeallocating else { return }

                self.isStreaming = false
                self.startStopButton?.title = "Start"
                self.startStopButton?.isEnabled = true
            }
        }

        do {
            try logStreamTask?.run()
            isStreaming = true
            DispatchQueue.main.async {
                self.startStopButton.title = "Stop"
            }
        } catch {
            DispatchQueue.main.async {
                self.appendLogOutput("Failed to start log streaming: \(error)\n")
            }
        }
    }

    func stopLogStreaming() {
        // Don't proceed if already deallocating and process was cleaned up
        guard !isDeallocating || logStreamTask != nil else { return }

        guard isStreaming || logStreamTask != nil else { return }

        // Set streaming to false immediately to prevent new data processing
        isStreaming = false

        // Clean up the process and file handles
        if let task = logStreamTask {
            // Clear the termination handler first to avoid callbacks during cleanup
            task.terminationHandler = nil

            // Clean up file handles
            if let pipe = task.standardOutput as? Pipe {
                let handle = pipe.fileHandleForReading
                // Clear the handler first to stop callbacks
                handle.readabilityHandler = nil
                // Close the handle safely
                do {
                    try handle.close()
                } catch {
                    // Handle might already be closed, ignore error
                }
            }

            // Terminate the process if still running
            if task.isRunning {
                task.terminate()
                // Don't wait synchronously as it might block during deallocation
            }
        }

        // Clear the task reference
        logStreamTask = nil

        // Update UI on main thread only if not deallocating
        if !isDeallocating {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, !self.isDeallocating else { return }
                self.startStopButton?.title = "Start"
            }
        }
    }

    private func restartLogStreaming() {
        guard !isDeallocating else { return }
        stopLogStreaming()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self, !self.isDeallocating else { return }
            self.startLogStreaming()
        }
    }

    private func appendLogOutput(_ output: String) {
        // Early exit if deallocating
        guard !isDeallocating else { return }

        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

        DispatchQueue.main.async { [weak self] in
            // Use weak self and guard to ensure safe access
            guard let self = self else { return }

            // Check deallocation flag first - critical safety check
            guard !self.isDeallocating else { return }

            // Double-check streaming state on main thread
            guard self.isStreaming else { return }

            // Ensure text view still exists before updating - critical for crash prevention
            guard let textView = self.textView,
                let textStorage = textView.textStorage,
                textView.superview != nil
            else { return }

            for line in lines {
                // Check again during the loop in case deallocation started
                guard !self.isDeallocating else { return }

                self.logBuffer.append(line)

                // Maintain buffer size
                if self.logBuffer.count > self.maxLogLines {
                    self.logBuffer.removeFirst(self.logBuffer.count - self.maxLogLines)
                }

                // Append to text view with structured color coding
                let attributedString = self.createStyledLogLine(line)
                textStorage.append(attributedString)
            }

            // Final safety check before display updates
            guard !self.isDeallocating else { return }

            // Safety checks before updating display
            guard let layoutManager = textView.layoutManager,
                let textContainer = textView.textContainer
            else { return }

            // Force text view to update display
            textView.needsDisplay = true
            layoutManager.ensureLayout(for: textContainer)

            // Auto-scroll to bottom
            textView.scrollToEndOfDocument(nil)
        }
    }

    private func createStyledLogLine(_ line: String) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(string: line + "\n")
        let fullRange = NSRange(location: 0, length: line.count)

        // Set default text color
        attributedString.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

        // Parse the log line using regex pattern
        // Format: timestamp level process[pid:tid] [subsystem:category] [file:function:line] message
        let pattern =
            #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) (\w+) ([^\[]+\[[^\]]+\]) (\[[^\]]+\]) (\[[^\]]+\]) (.*)$"#

        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            if let match = regex.firstMatch(
                in: line, options: [], range: NSRange(location: 0, length: line.count))
            {

                // Color the timestamp (gray)
                if match.range(at: 1).location != NSNotFound {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.systemGray, range: match.range(at: 1))
                    attributedString.addAttribute(
                        .font, value: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                        range: match.range(at: 1))
                }

                // Color the log level
                if match.range(at: 2).location != NSNotFound {
                    let levelRange = match.range(at: 2)
                    let level = (line as NSString).substring(with: levelRange)

                    let levelColor: NSColor
                    switch level {
                    case "E": levelColor = NSColor.systemRed
                    case "Db": levelColor = NSColor.systemPurple
                    case "I": levelColor = NSColor.systemBlue
                    case "D": levelColor = NSColor.systemOrange
                    default: levelColor = NSColor.textColor
                    }

                    attributedString.addAttribute(
                        .foregroundColor, value: levelColor, range: levelRange)
                    attributedString.addAttribute(
                        .font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                        range: levelRange)
                }

                // Color the process info (light gray)
                if match.range(at: 3).location != NSNotFound {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.secondaryLabelColor,
                        range: match.range(at: 3))
                    attributedString.addAttribute(
                        .font, value: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                        range: match.range(at: 3))
                }

                // Color the subsystem:category (blue)
                if match.range(at: 4).location != NSNotFound {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.systemTeal, range: match.range(at: 4))
                    attributedString.addAttribute(
                        .font, value: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium),
                        range: match.range(at: 4))
                }

                // Color the file:function:line (green)
                if match.range(at: 5).location != NSNotFound {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.systemGreen, range: match.range(at: 5))
                    attributedString.addAttribute(
                        .font, value: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                        range: match.range(at: 5))
                }

                // Color the message (default text color, slightly larger)
                if match.range(at: 6).location != NSNotFound {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.textColor, range: match.range(at: 6))
                    attributedString.addAttribute(
                        .font, value: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        range: match.range(at: 6))
                }

            } else {
                // Fallback: if regex doesn't match, apply simple level-based coloring
                if line.contains(" E ") {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.systemRed, range: fullRange)
                } else if line.contains(" Db ") {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.systemPurple, range: fullRange)
                } else if line.contains(" I ") {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.systemBlue, range: fullRange)
                } else if line.contains(" D ") {
                    attributedString.addAttribute(
                        .foregroundColor, value: NSColor.systemOrange, range: fullRange)
                }
            }
        } catch {
            // If regex fails, apply simple level-based coloring
            if line.contains(" E ") {
                attributedString.addAttribute(
                    .foregroundColor, value: NSColor.systemRed, range: fullRange)
            } else if line.contains(" Db ") {
                attributedString.addAttribute(
                    .foregroundColor, value: NSColor.systemPurple, range: fullRange)
            } else if line.contains(" I ") {
                attributedString.addAttribute(
                    .foregroundColor, value: NSColor.systemBlue, range: fullRange)
            } else if line.contains(" D ") {
                attributedString.addAttribute(
                    .foregroundColor, value: NSColor.systemOrange, range: fullRange)
            }
        }

        return attributedString
    }

    // MARK: - Window Management

    func createAndShowWindow() {
        if logWindow == nil {
            logWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )

            logWindow?.title = "NeewerLite Log Monitor"
            logWindow?.contentViewController = self
            logWindow?.center()

            // Set this view controller as the window delegate
            logWindow?.delegate = self

            // Set minimum size for the window
            logWindow?.minSize = NSSize(width: 600, height: 400)
        }

        logWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Stop streaming when window is about to close
        stopLogStreaming()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Clean up when window is closing
        guard let window = notification.object as? NSWindow,
            window == logWindow
        else { return }

        // Set deallocation flag to prevent further operations immediately
        isDeallocating = true
        isStreaming = false

        // Synchronously clean up the process completely
        if let task = logStreamTask {
            task.terminationHandler = nil

            if let pipe = task.standardOutput as? Pipe {
                let handle = pipe.fileHandleForReading
                handle.readabilityHandler = nil
                try? handle.close()
            }

            if task.isRunning {
                task.terminate()
            }
        }

        logStreamTask = nil

        // Clear delegates and content before releasing
        window.delegate = nil
        window.contentViewController = nil

        // Clear our reference
        logWindow = nil

        // Notify AppDelegate to clear its references
        // Use async to avoid potential issues during window closing sequence
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.clearLogMonitorReferences()
            }
        }
    }
}
