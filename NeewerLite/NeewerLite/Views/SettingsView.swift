//
//  SettingsView.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/18/26.
//

import Cocoa
import Sparkle

class SettingsView: NSView {

    private var dbInfoLabel: NSTextField!
    private var dbSyncStatusLabel: NSTextField!
    private var dbSourceURLField: NSTextField!
    private var dbStatusIcon: NSTextField!
    private var deleteDBButton: NSButton!
    private var syncDBButton: NSButton!
    private var languagePopUp: NSPopUpButton!
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

        // --- App Info Section ---
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"

        let appInfoLabel = NSTextField(labelWithString: "NeewerLite v%@ (%@)".localized(appVersion, buildNumber))
        appInfoLabel.font = NSFont.boldSystemFont(ofSize: 16)
        appInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appInfoLabel)

        // --- Check for Updates Button ---
        let updateButton = NSButton(title: "Check for Updates…".localized, target: self, action: #selector(checkForUpdates))
        updateButton.bezelStyle = .rounded
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(updateButton)

        // --- GitHub Button ---
        let githubButton = NSButton(title: "GitHub Repo".localized, target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(githubButton)

        // --- Database Section Header + Status Icon ---
        let dbHeader = NSTextField(labelWithString: "Light Database".localized)
        dbHeader.font = NSFont.boldSystemFont(ofSize: 14)
        dbHeader.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dbHeader)

        let statusIcon = NSTextField(labelWithString: "")
        statusIcon.font = NSFont.systemFont(ofSize: 14)
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusIcon)
        dbStatusIcon = statusIcon

        // --- Database Info ---
        let infoLabel = NSTextField(labelWithString: "")
        infoLabel.font = NSFont.systemFont(ofSize: 12)
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.maximumNumberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(infoLabel)
        dbInfoLabel = infoLabel

        // --- Sync Status ---
        let syncStatusLabel = NSTextField(labelWithString: "")
        syncStatusLabel.font = NSFont.systemFont(ofSize: 11)
        syncStatusLabel.textColor = .tertiaryLabelColor
        syncStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(syncStatusLabel)
        dbSyncStatusLabel = syncStatusLabel

        // --- Sync Source URL ---
        let sourceURLField = NSTextField(labelWithString: "")
        sourceURLField.font = NSFont.systemFont(ofSize: 11)
        sourceURLField.textColor = .tertiaryLabelColor
        sourceURLField.isSelectable = true
        sourceURLField.allowsEditingTextAttributes = true
        sourceURLField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sourceURLField)
        dbSourceURLField = sourceURLField

        // --- Sync Database Button ---
        let syncButton = NSButton(title: "Sync Database Now".localized, target: self, action: #selector(syncDatabase))
        syncButton.bezelStyle = .rounded
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(syncButton)
        syncDBButton = syncButton

        // --- Delete Local DB Button ---
        let deleteButton = NSButton(title: "Delete Local DB".localized, target: self, action: #selector(deleteLocalDB))
        deleteButton.bezelStyle = .rounded
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)
        deleteDBButton = deleteButton

        // --- View in Finder Button ---
        let finderButton = NSButton(title: "View in Finder".localized, target: self, action: #selector(viewInFinder))
        finderButton.bezelStyle = .rounded
        finderButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(finderButton)

        // --- Language Section ---
        let langHeader = NSTextField(labelWithString: "Language".localized)
        langHeader.font = NSFont.boldSystemFont(ofSize: 14)
        langHeader.translatesAutoresizingMaskIntoConstraints = false
        addSubview(langHeader)

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
        addSubview(langPopUp)
        languagePopUp = langPopUp

        let langNote = NSTextField(labelWithString: "Restart required".localized)
        langNote.font = NSFont.systemFont(ofSize: 11)
        langNote.textColor = .tertiaryLabelColor
        langNote.translatesAutoresizingMaskIntoConstraints = false
        addSubview(langNote)

        // Layout
        NSLayoutConstraint.activate([
            appInfoLabel.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            appInfoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),

            updateButton.topAnchor.constraint(equalTo: appInfoLabel.bottomAnchor, constant: 12),
            updateButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),

            githubButton.centerYAnchor.constraint(equalTo: updateButton.centerYAnchor),
            githubButton.leadingAnchor.constraint(equalTo: updateButton.trailingAnchor, constant: 8),

            dbHeader.topAnchor.constraint(equalTo: updateButton.bottomAnchor, constant: 24),
            dbHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),

            statusIcon.centerYAnchor.constraint(equalTo: dbHeader.centerYAnchor),
            statusIcon.leadingAnchor.constraint(equalTo: dbHeader.trailingAnchor, constant: 6),

            infoLabel.topAnchor.constraint(equalTo: dbHeader.bottomAnchor, constant: 8),
            infoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            infoLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padding),

            sourceURLField.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 6),
            sourceURLField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            sourceURLField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padding),

            syncStatusLabel.topAnchor.constraint(equalTo: sourceURLField.bottomAnchor, constant: 6),
            syncStatusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            syncStatusLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -padding),

            syncButton.topAnchor.constraint(equalTo: syncStatusLabel.bottomAnchor, constant: 12),
            syncButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),

            deleteButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            deleteButton.leadingAnchor.constraint(equalTo: syncButton.trailingAnchor, constant: 8),

            finderButton.centerYAnchor.constraint(equalTo: syncButton.centerYAnchor),
            finderButton.leadingAnchor.constraint(equalTo: deleteButton.trailingAnchor, constant: 8),

            langHeader.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 24),
            langHeader.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),

            langPopUp.centerYAnchor.constraint(equalTo: langHeader.centerYAnchor),
            langPopUp.leadingAnchor.constraint(equalTo: langHeader.trailingAnchor, constant: 12),
            langPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),

            langNote.topAnchor.constraint(equalTo: langHeader.bottomAnchor, constant: 6),
            langNote.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
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
        } else {
            stopFileMonitor()
            NotificationCenter.default.removeObserver(self, name: ContentManager.databaseUpdatedNotification, object: nil)
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

    @objc private func viewInFinder() {
        let url = ContentManager.shared.localDatabaseURL
        if ContentManager.shared.localDatabaseExists {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
        }
    }
}
