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

        let appInfoLabel = NSTextField(labelWithString: "NeewerLite v\(appVersion) (\(buildNumber))")
        appInfoLabel.font = NSFont.boldSystemFont(ofSize: 16)
        appInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appInfoLabel)

        // --- Check for Updates Button ---
        let updateButton = NSButton(title: "Check for Updates…", target: self, action: #selector(checkForUpdates))
        updateButton.bezelStyle = .rounded
        updateButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(updateButton)

        // --- GitHub Button ---
        let githubButton = NSButton(title: "GitHub Repo", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(githubButton)

        // --- Database Section Header + Status Icon ---
        let dbHeader = NSTextField(labelWithString: "Light Database")
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
        let syncButton = NSButton(title: "Sync Database Now", target: self, action: #selector(syncDatabase))
        syncButton.bezelStyle = .rounded
        syncButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(syncButton)
        syncDBButton = syncButton

        // --- Delete Local DB Button ---
        let deleteButton = NSButton(title: "Delete Local DB", target: self, action: #selector(deleteLocalDB))
        deleteButton.bezelStyle = .rounded
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)
        deleteDBButton = deleteButton

        // --- View in Finder Button ---
        let finderButton = NSButton(title: "View in Finder", target: self, action: #selector(viewInFinder))
        finderButton.bezelStyle = .rounded
        finderButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(finderButton)

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
        ])
    }

    func refresh() {
        let cm = ContentManager.shared

        if cm.localDatabaseExists {
            let info = "Version: \(cm.databaseVersion)  •  Lights: \(cm.databaseLightCount)  •  Neewer Home Lights: \(cm.databaseHomeDeviceCount)  •  FX Presets: \(cm.databaseFxPresetCount)  •  Gels: \(cm.databaseGelCount)"
            dbInfoLabel.stringValue = info
            dbStatusIcon.stringValue = "✅"
            deleteDBButton.isEnabled = true
        } else {
            dbInfoLabel.stringValue = "No local database"
            dbStatusIcon.stringValue = "⚠️"
            deleteDBButton.isEnabled = false
        }

        if let remaining = cm.remainingTTL {
            let minutes = Int(remaining) / 60
            let hours = minutes / 60
            let mins = minutes % 60
            dbSyncStatusLabel.stringValue = "Next auto-sync in \(hours)h \(mins)m"
        } else {
            dbSyncStatusLabel.stringValue = "Auto-sync pending…"
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
        syncDBButton.isEnabled = true
        refresh()
    }

    @objc private func syncDatabase() {
        syncDBButton.isEnabled = false
        dbSyncStatusLabel.stringValue = "Syncing…"
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
