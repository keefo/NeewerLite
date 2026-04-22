//
//  SettingsView.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/18/26.
//

import Cocoa
import ServiceManagement
import Sparkle

private final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
}

private func dictionary(at keyPath: String, in root: [String: Any]) -> [String: Any]? {
    let keys = keyPath.split(separator: ".").map(String.init)
    guard !keys.isEmpty else { return nil }
    var current: Any = root
    for key in keys {
        guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
        current = next
    }
    return current as? [String: Any]
}

private func setDictionary(_ value: [String: Any], at keyPath: String, in root: inout [String: Any]) {
    let keys = keyPath.split(separator: ".").map(String.init)
    guard !keys.isEmpty else { return }
    setDictionary(value, keys: keys, in: &root)
}

private func setDictionary(_ value: [String: Any], keys: [String], in root: inout [String: Any]) {
    if keys.count == 1 {
        root[keys[0]] = value
        return
    }
    var child = root[keys[0]] as? [String: Any] ?? [:]
    setDictionary(value, keys: Array(keys.dropFirst()), in: &child)
    root[keys[0]] = child
}

private struct MCPClientDef {
    let name: String
    let installPaths: [String]
    let configPath: String       // may start with ~
    let configKey: String        // e.g. "mcpServers", "servers", "mcp.servers"
    /// Returns the JSON object written under config[configKey]["neewerlite"]
    let configEntry: () -> [String: Any]
    var configURL: URL {
        URL(fileURLWithPath: NSString(string: configPath).expandingTildeInPath)
    }
    var isInstalled: Bool {
        installPaths.contains { path in
            let expandedPath = NSString(string: path).expandingTildeInPath
            return FileManager.default.fileExists(atPath: expandedPath)
        }
    }
    var isConfigured: Bool {
        guard let data = try? Data(contentsOf: configURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = dictionary(at: configKey, in: json) else { return false }
        return servers["neewerlite"] != nil
    }
}

private let kMCPClients: [MCPClientDef] = [
    .init(name: "Claude Desktop",
        installPaths: ["/Applications/Claude.app"],
          configPath: "~/Library/Application Support/Claude/claude_desktop_config.json",
          configKey: "mcpServers",
          configEntry: { ["command": "npx", "args": ["-y", "mcp-remote", "http://127.0.0.1:18486/mcp"]] }),
    .init(name: "Cursor",
        installPaths: ["/Applications/Cursor.app"],
          configPath: "~/.cursor/mcp.json",
          configKey: "mcpServers",
          configEntry: { ["url": "http://127.0.0.1:18486/mcp", "type": "streamable-http"] }),
    .init(name: "Windsurf",
        installPaths: ["/Applications/Windsurf.app"],
          configPath: "~/.codeium/windsurf/mcp_config.json",
          configKey: "mcpServers",
          configEntry: { ["url": "http://127.0.0.1:18486/mcp", "type": "streamable-http"] }),
    .init(name: "VS Code (Copilot)",
        installPaths: ["/Applications/Visual Studio Code.app"],
          configPath: "~/Library/Application Support/Code/User/mcp.json",
          configKey: "servers",
          configEntry: { ["url": "http://127.0.0.1:18486/mcp", "type": "streamable-http"] }),
        .init(name: "OpenClaw",
        installPaths: ["/Applications/OpenClaw.app", "~/.openclaw"],
            configPath: "~/.openclaw/openclaw.json",
            configKey: "mcp.servers",
            configEntry: { ["url": "http://127.0.0.1:18486/mcp"] }),
]

class SettingsView: NSView {

    private var dbInfoLabel: NSTextField!
    private var appInfoLabel: NSTextField = NSTextField(labelWithString: "")
    private var dbSyncStatusLabel: NSTextField!
    private var dbSourceURLField: NSTextField!
    private var dbStatusIcon: NSTextField!
    private var deleteDBButton: NSButton!
    private var syncDBButton: NSButton!
    private var languagePopUp: NSPopUpButton!
    private var launchAtLoginCheckbox: NSButton!
    private var serverCheckbox: NSButton!
    private var observingHTTPServer = false
    private var serverURLLabel: NSTextField!
    private var serverTestButton: NSButton!
    private var mcpClientCheckboxes: [(MCPClientDef, NSButton)] = []
    private var fileMonitorSource: DispatchSourceFileSystemObject?
    private var dirMonitorSource: DispatchSourceFileSystemObject?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        wantsLayer = true

        let padding: CGFloat = 20
        let contentView = FlippedContentView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = contentView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        // --- App Info Section ---
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        appInfoLabel.stringValue = "NeewerLite v\(appVersion) (\(buildNumber))"

        appInfoLabel.font = NSFont.boldSystemFont(ofSize: 16)
        appInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(appInfoLabel)

        // --- Check for Updates Button ---
        let updateButton = NSButton(title: "Check for Updates…".localized, target: self, action: #selector(checkForUpdates))
        updateButton.bezelStyle = .rounded
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(updateButton)

        // --- GitHub Button ---
        let githubButton = NSButton(title: "GitHub Repo".localized, target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(githubButton)

        // --- Database Section Header + Status Icon ---
        let dbHeader = NSTextField(labelWithString: "Light Database".localized)
        dbHeader.font = NSFont.boldSystemFont(ofSize: 14)
        dbHeader.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dbHeader)

        let statusIcon = NSTextField(labelWithString: "")
        statusIcon.font = NSFont.systemFont(ofSize: 14)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusIcon)
        dbStatusIcon = statusIcon

        // --- Database Info ---
        let infoLabel = NSTextField(labelWithString: "")
        infoLabel.font = NSFont.systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.maximumNumberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(infoLabel)
        dbInfoLabel = infoLabel

        // --- Sync Status ---
        let syncStatusLabel = NSTextField(labelWithString: "")
        syncStatusLabel.font = NSFont.systemFont(ofSize: 11)
        syncStatusLabel.textColor = .tertiaryLabelColor
        syncStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(syncStatusLabel)
        dbSyncStatusLabel = syncStatusLabel

        // --- Sync Source URL ---
        let sourceURLField = NSTextField(labelWithString: "")
        sourceURLField.font = NSFont.systemFont(ofSize: 11)
        sourceURLField.textColor = .tertiaryLabelColor
        sourceURLField.isSelectable = true
        sourceURLField.allowsEditingTextAttributes = true
        sourceURLField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sourceURLField)
        dbSourceURLField = sourceURLField

        // --- Sync Database Button ---
        let syncButton = NSButton(title: "Sync Database Now".localized, target: self, action: #selector(syncDatabase))
        syncButton.bezelStyle = .rounded
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(syncButton)
        syncDBButton = syncButton

        // --- Delete Local DB Button ---
        let deleteButton = NSButton(title: "Delete Local DB".localized, target: self, action: #selector(deleteLocalDB))
        deleteButton.bezelStyle = .rounded
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deleteButton)
        deleteDBButton = deleteButton

        // --- View in Finder Button ---
        let finderButton = NSButton(title: "View in Finder".localized, target: self, action: #selector(viewInFinder))
        finderButton.bezelStyle = .rounded
        finderButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(finderButton)

        // --- Language Section ---
        let langHeader = NSTextField(labelWithString: "Language".localized)
        langHeader.font = NSFont.boldSystemFont(ofSize: 14)
        langHeader.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(langHeader)

        let langPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        langPopUp.translatesAutoresizingMaskIntoConstraints = false
        let supportedLanguages: [(code: String, name: String)] = [
            ("system", "System Default".localized),
            ("en", "English"),
            ("zh-Hans", "简体中文"),
            ("ja", "日本語"),
            ("de", "Deutsch"),
            ("fr", "Français"),
            ("es", "Español"),
            ("ko", "한국어")
        ]
        for lang in supportedLanguages {
            langPopUp.addItem(withTitle: lang.name)
            langPopUp.lastItem?.representedObject = lang.code
        }
        // Select current language
        if let override = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = override.first {
            if let idx = supportedLanguages.firstIndex(where: { $0.code == first }) {
                langPopUp.selectItem(at: idx)
            }
        } else {
            langPopUp.selectItem(at: 0) // System Default
        }
        langPopUp.target = self
        langPopUp.action = #selector(languageChanged(_:))
        contentView.addSubview(langPopUp)
        languagePopUp = langPopUp

        let langNote = NSTextField(labelWithString: "Restart required".localized)
        langNote.font = NSFont.systemFont(ofSize: 11)
        langNote.textColor = .tertiaryLabelColor
        langNote.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(langNote)

        // --- Launch at Login Section ---
        let loginCheckbox = NSButton(checkboxWithTitle: "Launch at Login".localized, target: self, action: #selector(launchAtLoginChanged(_:)))
        loginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        loginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        contentView.addSubview(loginCheckbox)
        launchAtLoginCheckbox = loginCheckbox

        // --- HTTP Server Section ---
        let serverEnabled = UserDefaults.standard.bool(forKey: "HTTPServerEnabled")
        let srvCheckbox = NSButton(checkboxWithTitle: "HTTP Server".localized, target: self, action: #selector(serverToggled(_:)))
        srvCheckbox.translatesAutoresizingMaskIntoConstraints = false
        srvCheckbox.state = serverEnabled ? .on : .off
        contentView.addSubview(srvCheckbox)
        serverCheckbox = srvCheckbox

        let srvURLLabel = NSTextField(labelWithString: "http://127.0.0.1:18486")
        srvURLLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        srvURLLabel.textColor = .secondaryLabelColor
        srvURLLabel.isSelectable = true
        srvURLLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(srvURLLabel)
        serverURLLabel = srvURLLabel

        let testButton = NSButton(title: "Test ↗".localized, target: self, action: #selector(openPingURL))
        testButton.bezelStyle = .inline
        testButton.font = NSFont.systemFont(ofSize: 11)
        testButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(testButton)
        serverTestButton = testButton

        let srvNote = NSTextField(labelWithString: "Enables Stream Deck and MCP (AI agent) integration.".localized)
        srvNote.font = NSFont.systemFont(ofSize: 11)
        srvNote.textColor = .tertiaryLabelColor
        srvNote.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(srvNote)

        updateServerUI(enabled: serverEnabled)

        // --- Section Separators ---
        let sep1 = NSBox()
        sep1.boxType = .separator
        sep1.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep1)

        let sep2 = NSBox()
        sep2.boxType = .separator
        sep2.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep2)

        let sep3 = NSBox()
        sep3.boxType = .separator
        sep3.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep3)

        let sep4 = NSBox()
        sep4.boxType = .separator
        sep4.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep4)

        let bottomSpacer = NSView()
        bottomSpacer.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(bottomSpacer)

        // Layout
        NSLayoutConstraint.activate([
            appInfoLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding),
            appInfoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            updateButton.topAnchor.constraint(equalTo: appInfoLabel.bottomAnchor, constant: 12),
            updateButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            githubButton.centerYAnchor.constraint(equalTo: updateButton.centerYAnchor),
            githubButton.leadingAnchor.constraint(equalTo: updateButton.trailingAnchor, constant: 8),

            sep1.topAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: 16),
            sep1.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            sep1.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),

            dbHeader.topAnchor.constraint(equalTo: sep1.bottomAnchor, constant: 16),
            dbHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            statusIcon.centerYAnchor.constraint(equalTo: dbHeader.centerYAnchor),
            statusIcon.leadingAnchor.constraint(equalTo: dbHeader.trailingAnchor, constant: 6),

            infoLabel.topAnchor.constraint(equalTo: dbHeader.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -padding),

            sourceURLField.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 6),
            sourceURLField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            sourceURLField.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -padding),

            syncStatusLabel.topAnchor.constraint(equalTo: sourceURLField.bottomAnchor, constant: 6),
            syncStatusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            syncStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -padding),

            syncButton.topAnchor.constraint(equalTo: syncStatusLabel.bottomAnchor, constant: 12),
            syncButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            deleteButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor, constant: 8),

            finderButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            finderButton.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 8),

            sep2.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 16),
            sep2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            sep2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),

            langHeader.topAnchor.constraint(equalTo: sep2.bottomAnchor, constant: 16),
            langHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            langPopUp.centerYAnchor.constraint(equalTo: langHeader.centerYAnchor),
            langPopUp.leadingAnchor.constraint(equalTo: langHeader.trailingAnchor, constant: 12),
            langPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

            langNote.topAnchor.constraint(equalTo: langHeader.bottomAnchor, constant: 6),
            langNote.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            sep3.topAnchor.constraint(equalTo: langNote.bottomAnchor, constant: 16),
            sep3.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            sep3.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),

            loginCheckbox.topAnchor.constraint(equalTo: sep3.bottomAnchor, constant: 16),
            loginCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            sep4.topAnchor.constraint(equalTo: loginCheckbox.bottomAnchor, constant: 16),
            sep4.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            sep4.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),

            srvCheckbox.topAnchor.constraint(equalTo: sep4.bottomAnchor, constant: 16),
            srvCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),

            srvURLLabel.centerYAnchor.constraint(equalTo: srvCheckbox.centerYAnchor),
            srvURLLabel.leadingAnchor.constraint(equalTo: srvCheckbox.trailingAnchor, constant: 8),

            serverTestButton.centerYAnchor.constraint(equalTo: srvCheckbox.centerYAnchor),
            serverTestButton.leadingAnchor.constraint(equalTo: srvURLLabel.trailingAnchor, constant: 6),

            srvNote.topAnchor.constraint(equalTo: srvCheckbox.bottomAnchor, constant: 6),
            srvNote.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
        ])

        // --- MCP Clients Section ---
        let sep5 = NSBox()
        sep5.boxType = .separator
        sep5.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep5)

        let mcpHeader = NSTextField(labelWithString: "MCP Clients".localized)
        mcpHeader.font = NSFont.boldSystemFont(ofSize: 14)
        mcpHeader.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mcpHeader)

        let mcpNote = NSTextField(labelWithString: "Check a client to write NeewerLite into its MCP config file.".localized)
        mcpNote.font = NSFont.systemFont(ofSize: 11)
        mcpNote.textColor = .tertiaryLabelColor
        mcpNote.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mcpNote)

        var mcpConstraints: [NSLayoutConstraint] = [
            sep5.topAnchor.constraint(equalTo: srvNote.bottomAnchor, constant: 16),
            sep5.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            sep5.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            mcpHeader.topAnchor.constraint(equalTo: sep5.bottomAnchor, constant: 16),
            mcpHeader.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            mcpNote.topAnchor.constraint(equalTo: mcpHeader.bottomAnchor, constant: 4),
            mcpNote.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
        ]

        var prevAnchor = mcpNote.bottomAnchor
        for client in kMCPClients {
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: #selector(mcpClientToggled(_:)))
            checkbox.translatesAutoresizingMaskIntoConstraints = false
            checkbox.state = client.isConfigured ? .on : .off
            checkbox.isEnabled = client.isInstalled
            contentView.addSubview(checkbox)

            let nameLabel = NSTextField(labelWithString: client.name)
            nameLabel.font = NSFont.systemFont(ofSize: 13)
            nameLabel.textColor = client.isInstalled ? .labelColor : .tertiaryLabelColor
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(nameLabel)

            let pathLabel = NSTextField(labelWithString: client.isInstalled ? client.configPath : "Not installed".localized)
            pathLabel.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
            pathLabel.textColor = .tertiaryLabelColor
            pathLabel.lineBreakMode = .byTruncatingMiddle
            pathLabel.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(pathLabel)

            mcpClientCheckboxes.append((client, checkbox))

            mcpConstraints += [
                checkbox.topAnchor.constraint(equalTo: prevAnchor, constant: 12),
                checkbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
                nameLabel.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
                nameLabel.leadingAnchor.constraint(equalTo: checkbox.trailingAnchor, constant: 6),
                pathLabel.centerYAnchor.constraint(equalTo: checkbox.centerYAnchor),
                pathLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
                pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -padding),
            ]
            prevAnchor = checkbox.bottomAnchor
        }

        let copyConfigButton = NSButton(title: "Copy MCP Config".localized, target: self, action: #selector(copyMCPConfig))
        copyConfigButton.bezelStyle = .rounded
        copyConfigButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyConfigButton)

        mcpConstraints += [
            copyConfigButton.topAnchor.constraint(equalTo: prevAnchor, constant: 16),
            copyConfigButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
        ]
        NSLayoutConstraint.activate(mcpConstraints)

        NSLayoutConstraint.activate([
            bottomSpacer.topAnchor.constraint(equalTo: copyConfigButton.bottomAnchor),
            bottomSpacer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomSpacer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomSpacer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomSpacer.heightAnchor.constraint(greaterThanOrEqualToConstant: padding)
        ])
    }

    func refresh() {
        let cm = ContentManager.shared

        if cm.localDatabaseExists {
            let ver = String(format: "%.1f", cm.databaseVersion)
            let info = "Version: %@  •  Lights: %d  •  Neewer Home Lights: %d  •  FX Presets: %d  •  Gels: %d".localized(ver, cm.databaseLightCount, cm.databaseHomeDeviceCount, cm.databaseFxPresetCount, cm.databaseGelCount)
            dbInfoLabel.stringValue = info
            dbStatusIcon.stringValue = "✅"
            deleteDBButton.isEnabled = true
        } else {
            dbInfoLabel.stringValue = "No local database".localized
            dbStatusIcon.stringValue = "⚠️"
            deleteDBButton.isEnabled = false
        }

        if let remaining = cm.remainingTTL {
            let minutes = Int(remaining) / 60
            let hours = minutes / 60
            let mins = minutes % 60
            dbSyncStatusLabel.stringValue = "Next auto-sync in %dh %dm".localized(hours, mins)
        } else {
            dbSyncStatusLabel.stringValue = "Auto-sync pending…".localized
        }

        dbSourceURLField.stringValue = cm.jsonDatabaseURL.absoluteString
    }

    @objc private func checkForUpdates() {
        SUUpdater.shared()?.checkForUpdates(self)
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/keefo/NeewerLite") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        guard let code = sender.selectedItem?.representedObject as? String else { return }
        if code == "system" {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        }
        UserDefaults.standard.synchronize()

        let alert = NSAlert()
        alert.messageText = "Language Changed".localized
        alert.informativeText = "Please restart NeewerLite for the language change to take effect.".localized
        alert.addButton(withTitle: "Restart Now".localized)
        alert.addButton(withTitle: "Later".localized)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", "sleep 0.5; open \"\(Bundle.main.bundlePath)\""]
            task.launch()
            NSApp.terminate(nil)
        }
    }

    // MARK: - File Monitor

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            startFileMonitor()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(databaseDidUpdate),
                name: ContentManager.databaseUpdatedNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(refreshLoginItemStatus),
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
            if !observingHTTPServer {
                UserDefaults.standard.addObserver(self, forKeyPath: "HTTPServerEnabled", options: .new, context: nil)
                observingHTTPServer = true
            }
        } else {
            stopFileMonitor()
            NotificationCenter.default.removeObserver(self, name: ContentManager.databaseUpdatedNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
            if observingHTTPServer {
                UserDefaults.standard.removeObserver(self, forKeyPath: "HTTPServerEnabled")
                observingHTTPServer = false
            }
        }
    }

    private func startFileMonitor() {
        stopFileMonitor()
        let dbURL = ContentManager.shared.localDatabaseURL
        let dirURL = dbURL.deletingLastPathComponent()

        // Monitor directory for file create/delete
        let dirFd = open(dirURL.path, O_EVTONLY)
        if dirFd >= 0 {
            let dirSource = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: dirFd,
                eventMask: .write,
                queue: .main
            )
            dirSource.setEventHandler { [weak self] in
                ContentManager.shared.loadDatabaseFromDisk(reload: true)
                self?.refresh()
                // Re-attach file monitor since file may have been created/deleted
                self?.attachFileMonitor()
            }
            dirSource.setCancelHandler {
                close(dirFd)
            }
            dirSource.resume()
            dirMonitorSource = dirSource
        }

        // Monitor file itself for content changes
        attachFileMonitor()
    }

    private func attachFileMonitor() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil

        let dbURL = ContentManager.shared.localDatabaseURL
        let fileFd = open(dbURL.path, O_EVTONLY)
        guard fileFd >= 0 else { return }
        let fileSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileFd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        fileSource.setEventHandler { [weak self] in
            ContentManager.shared.loadDatabaseFromDisk(reload: true)
            self?.refresh()
            // Re-attach if file was deleted/renamed
            self?.attachFileMonitor()
        }
        fileSource.setCancelHandler {
            close(fileFd)
        }
        fileSource.resume()
        fileMonitorSource = fileSource
    }

    private func stopFileMonitor() {
        fileMonitorSource?.cancel()
        fileMonitorSource = nil
        dirMonitorSource?.cancel()
        dirMonitorSource = nil
    }

    deinit {
        stopFileMonitor()
        NotificationCenter.default.removeObserver(self)
        if observingHTTPServer {
            UserDefaults.standard.removeObserver(self, forKeyPath: "HTTPServerEnabled")
        }
    }

    @objc private func databaseDidUpdate() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.syncDBButton.isEnabled = true
            self.refresh()
        }
    }

    @objc private func syncDatabase() {
        syncDBButton.isEnabled = false
        dbSyncStatusLabel.stringValue = "Syncing…".localized
        ContentManager.shared.downloadDatabase(force: true, silent: true)
    }

    @objc private func deleteLocalDB() {
        ContentManager.shared.deleteLocalDatabase()
        refresh()
    }

    @objc private func refreshLoginItemStatus() {
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == "HTTPServerEnabled" else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let enabled = UserDefaults.standard.bool(forKey: "HTTPServerEnabled")
            self.serverCheckbox.state = enabled ? .on : .off
            self.updateServerUI(enabled: enabled)
        }
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.error("Launch at Login toggle failed: \(error)")
            // Revert checkbox to actual state
            sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
        }
    }

    @objc private func serverToggled(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: "HTTPServerEnabled")
        updateServerUI(enabled: enabled)
        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate else { return }
        if enabled {
            if appDelegate.server == nil {
                appDelegate.server = NeewerLiteServer(appDelegate: appDelegate)
            }
            appDelegate.server?.start()
        } else {
            appDelegate.server?.stop()
        }
    }

    private func updateServerUI(enabled: Bool) {
        serverURLLabel.textColor = enabled ? .secondaryLabelColor : .tertiaryLabelColor
        serverTestButton.isEnabled = enabled
    }

    @objc private func openPingURL() {
        if let url = URL(string: "http://127.0.0.1:18486/ping") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - MCP Client Config

    @objc private func mcpClientToggled(_ sender: NSButton) {
        guard let (client, _) = mcpClientCheckboxes.first(where: { $0.1 === sender }) else { return }
        do {
            if sender.state == .on {
                try writeMCPConfig(to: client.configURL, key: client.configKey, entry: client.configEntry())
            } else {
                try removeMCPConfig(from: client.configURL, key: client.configKey)
            }
        } catch {
            Logger.error("MCP config write failed for \(client.name): \(error)")
            sender.state = client.isConfigured ? .on : .off
            let alert = NSAlert()
            alert.messageText = "Could not update config".localized
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func writeMCPConfig(to url: URL, key: String, entry: [String: Any]) throws {
        var config: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            config = json
        }
        var servers = dictionary(at: key, in: config) ?? [:]
        servers["neewerlite"] = entry
        setDictionary(servers, at: key, in: &config)
        let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func removeMCPConfig(from url: URL, key: String) throws {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var servers = dictionary(at: key, in: config) else { return }
        servers.removeValue(forKey: "neewerlite")
        setDictionary(servers, at: key, in: &config)
        let out = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
        try out.write(to: url, options: .atomic)
    }

    @objc private func copyMCPConfig() {
        let json = """
        {
          "mcpServers": {
            "neewerlite": {
                            "command": "npx",
                            "args": ["-y", "mcp-remote", "http://127.0.0.1:18486/mcp"]
            }
          }
        }
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(json, forType: .string)
    }

    @objc private func viewInFinder() {
        let url = ContentManager.shared.localDatabaseURL
        if ContentManager.shared.localDatabaseExists {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }
}
