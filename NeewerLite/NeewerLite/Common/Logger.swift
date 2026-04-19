//
//  Logger.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Foundation
import os.log

public enum LogTag: Int {
    case none = 0
    case app = 1
    case click = 2
    case bluetooth = 3
    case wifi = 4
    case heart = 5
    case server = 6
}

// MARK: - Logger

/// A lightweight, file-backed logger optimized for a long-running menu-bar app.
///
/// Performance optimizations (informed by CocoaLumberjack, SwiftyBeaver, swift-log):
///
/// - **`@autoclosure` messages** — string interpolation is not evaluated unless
///   the message will actually be logged. `debug()` calls compile away entirely
///   in Release builds, so their arguments have zero cost.
///
/// - **`os_log` replaces `print()`** — integrates with Console.app and
///   Instruments, is async-signal-safe, and avoids stdout buffering. Messages
///   use `%{public}@` so they remain readable in Console.
///
/// - **`#fileID` over `#file`** — produces `"Module/File.swift"` instead of
///   the full filesystem path. Extracts the filename with `Substring` slicing
///   instead of allocating a `URL` + calling `lastPathComponent`.
///
/// - **Buffered file I/O** — writes go through a serial `DispatchQueue` at
///   `.utility` QoS so logging never competes with UI or BLE dispatch.
///   `fsync` is deferred until 4 KB accumulates or a 5-second timer fires,
///   whichever comes first. This batches many small writes into fewer disk
///   flushes — important when BLE callbacks log at high frequency.
///
/// - **`DispatchSourceTimer` over `Timer`** — no run-loop dependency, so the
///   flush timer works correctly regardless of which thread logs are emitted from.
///
/// - **Single static `ISO8601DateFormatter`** — `DateFormatter` allocation
///   costs ~80 µs. One shared instance, accessed only on the serial log queue,
///   avoids both the cost and thread-safety concerns.
///
/// - **`@inline(__always)` on `extractFileName`** — the hot path (every log
///   call) avoids a function-call frame for a trivial string slice.
public final class Logger {

    // MARK: - Configuration

    private static let maxFileSize: UInt64 = 5 * 1024 * 1024       // 5 MB per log file
    private static let cleanupAgeDays = 7                           // delete logs older than this
    private static let cleanupCheckInterval: TimeInterval = 2 * 3600 // re-check every 2 hours
    private static let flushInterval: TimeInterval = 5.0            // periodic fsync interval
    private static let flushThreshold: UInt64 = 4096                // fsync after 4 KB of writes
    private static let cleanupDefaultsKey = "LoggerLastCleanupDate"

    // MARK: - Internal state (all mutable state accessed only on logQueue)

    /// Serial queue for all file I/O. `.utility` QoS keeps logging out of
    /// the way of UI rendering and BLE command dispatch.
    private static let logQueue = DispatchQueue(label: "com.neewerlite.logger", qos: .utility)

    private static let osLog = OSLog(
        subsystem: Bundle.main.bundleIdentifier ?? "com.beyondcow.NeewerLite",
        category: "general"
    )

    /// Reused across all writes — created once, used only on `logQueue`.
    /// ISO8601DateFormatter is not thread-safe; single-queue access is required.
    private static let dateFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    private static var fileHandle: FileHandle?
    private static var unflushedBytes: UInt64 = 0
    private static var flushTimer: DispatchSourceTimer?
    public static private(set) var currentLogFileURL: URL?

    // MARK: - Lifecycle

    /// Call once at app launch to open the log file and start the flush timer.
    static func initialize() {
        logQueue.async {
            openLogFile()
            startFlushTimer()
        }
        cleanupOldLogs()
    }

    // MARK: - Debug (compiled away in Release)

    public static func debug(_ tag: LogTag, _ message: @autoclosure () -> String, function: String = #function, file: String = #fileID, line: Int = #line) {
        #if DEBUG
        emit(.debug, tag: tag, message(), file, function, line)
        #endif
    }

    public static func debug(_ message: @autoclosure () -> String = "", function: String = #function, file: String = #fileID, line: Int = #line) {
        #if DEBUG
        emit(.debug, tag: .none, message(), file, function, line)
        #endif
    }

    // MARK: - Info

    public static func info(_ tag: LogTag, _ message: @autoclosure () -> String, function: String = #function, file: String = #fileID, line: Int = #line) {
        emit(.info, tag: tag, message(), file, function, line)
    }

    public static func info(_ message: @autoclosure () -> String = "", function: String = #function, file: String = #fileID, line: Int = #line) {
        emit(.info, tag: .none, message(), file, function, line)
    }

    // MARK: - Warn

    public static func warn(_ tag: LogTag, _ message: @autoclosure () -> String, function: String = #function, file: String = #fileID, line: Int = #line) {
        emit(.warn, tag: tag, message(), file, function, line)
    }

    public static func warn(_ message: @autoclosure () -> String = "", function: String = #function, file: String = #fileID, line: Int = #line) {
        emit(.warn, tag: .none, message(), file, function, line)
    }

    // MARK: - Error

    public static func error(_ tag: LogTag, _ message: @autoclosure () -> String, function: String = #function, file: String = #fileID, line: Int = #line) {
        emit(.error, tag: tag, message(), file, function, line)
    }

    public static func error(_ message: @autoclosure () -> String = "", function: String = #function, file: String = #fileID, line: Int = #line) {
        emit(.error, tag: .none, message(), file, function, line)
    }

    // MARK: - Flush

    /// Synchronously flush buffered writes to disk.
    public static func syncToFile() {
        logQueue.sync {
            syncFileToDisk()
        }
    }

    /// Flush and call completion on the main queue. For app termination.
    public typealias FlushCompletion = () -> Void

    public static func flush(completion: @escaping FlushCompletion) {
        logQueue.async {
            syncFileToDisk()
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    // MARK: - Cleanup

    public static func cleanupOldLogs(olderThan days: Int = 7) {
        guard let logsDir = logsDirectory else { return }
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: logsDir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles
            )
            for file in files {
                let attrs = try file.resourceValues(forKeys: [.contentModificationDateKey])
                if let modified = attrs.contentModificationDate, modified < threshold {
                    try FileManager.default.removeItem(at: file)
                }
            }
        } catch {
            // Best-effort cleanup — don't log to avoid recursion.
        }
    }

    // MARK: - Core emit (shared by all levels)

    private enum Level: String {
        case debug = "DEBUG"
        case info  = "INFO"
        case warn  = "WARN"
        case error = "ERRO"

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info:  return .info
            case .warn:  return .default   // visible in Console without toggling
            case .error: return .error
            }
        }
    }

    /// Format the message, send to os_log, then queue a file write.
    private static func emit(_ level: Level, tag: LogTag, _ msg: String,
                             _ fileID: String, _ function: String, _ line: Int) {
        let file = extractFileName(fileID)
        let tagStr = tag == .none ? "" : "[\(tag)]"
        let formatted = "\(file):\(function):\(line): [\(level.rawValue)]\(tagStr) \(msg)"

        // os_log is thread-safe — safe to call from any queue.
        os_log("%{public}@", log: osLog, type: level.osLogType, formatted)

        logQueue.async {
            writeEntry(formatted)
        }
    }

    /// Extract `"File.swift"` from `#fileID`'s `"Module/File.swift"` format.
    /// Uses `Substring` to avoid a heap allocation.
    @inline(__always)
    private static func extractFileName(_ fileID: String) -> Substring {
        if let idx = fileID.lastIndex(of: "/") {
            return fileID[fileID.index(after: idx)...]
        }
        return Substring(fileID)
    }

    // MARK: - File I/O (must run on logQueue)

    private static var logsDirectory: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return appSupport.appendingPathComponent("NeewerLite/Logs")
    }

    private static func openLogFile() {
        guard let dir = logsDirectory else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        let filename = "neewerlite_log_\(fmt.string(from: Date())).log"
        let url = dir.appendingPathComponent(filename)
        FileManager.default.createFile(atPath: url.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            fileHandle = handle
            currentLogFileURL = url
        } catch {
            // Silently fail — nothing we can safely log here.
        }
    }

    /// Append a formatted log line to the current file.
    /// Syncs to disk when unflushed data exceeds `flushThreshold`,
    /// and rotates the file when it exceeds `maxFileSize`.
    private static func writeEntry(_ message: String) {
        guard let handle = fileHandle else { return }

        let timestamp = dateFormatter.string(from: Date())
        let entry = "\(timestamp) \(message)\n"
        guard let data = entry.data(using: .utf8) else { return }

        do {
            try handle.write(contentsOf: data)
            unflushedBytes += UInt64(data.count)

            // Flush to bound data loss window on crash.
            if unflushedBytes >= flushThreshold {
                try handle.synchronize()
                unflushedBytes = 0
            }

            // Rotate when the file grows past the size cap.
            if let offset = try? handle.offset(), offset >= maxFileSize {
                rotateFile()
            }
        } catch {
            // Drop the entry rather than crash.
        }
    }

    private static func syncFileToDisk() {
        do {
            try fileHandle?.synchronize()
            unflushedBytes = 0
        } catch {
            // Best effort.
        }
    }

    private static func rotateFile() {
        fileHandle?.closeFile()
        fileHandle = nil
        openLogFile()
    }

    // MARK: - Timers

    private static func startFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: logQueue)
        timer.schedule(deadline: .now() + flushInterval, repeating: flushInterval)
        timer.setEventHandler {
            syncFileToDisk()
            maybeCleanupOldLogs()
        }
        timer.resume()
        flushTimer = timer  // prevent deallocation
    }

    private static func maybeCleanupOldLogs() {
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: cleanupDefaultsKey) as? Date,
           Date().timeIntervalSince(last) < cleanupCheckInterval {
            return
        }
        cleanupOldLogs()
        defaults.set(Date(), forKey: cleanupDefaultsKey)
    }
}
