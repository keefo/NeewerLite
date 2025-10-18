//
//  Logger.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Foundation
import Network
import Cocoa

public enum LogTag: Int, Codable {
    case none = 0
    case app = 1
    case click = 2
    case bluetooth = 3
    case wifi = 4
    case heart = 5
    case server = 6
}

struct LogEntry: Codable {
    var tag: LogTag
    var timestamp: String
    var level: String
    var filename: String
    var line: Int
    var message: String

    enum CodingKeys: String, CodingKey {
        case tag = "g"
        case timestamp = "t"
        case level = "v"
        case filename = "f"
        case line = "n"
        case message = "m"
    }
}

struct LogBuffer: Codable {
    var version: String
    var osversion: String
    var logs: [LogEntry]
}

private extension Date {
    func formattedLogFileDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy_MM_dd_HH_mm_ss"
        return formatter.string(from: self)
    }
}

public class Logger {

    static let logUrl = URL(string: "https://beyondcow.com/neewerlite/log")!
    static let bundleVersion = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
    static let monitor: NWPathMonitor = NWPathMonitor()
    static let osVersionString = "\(ProcessInfo.processInfo.operatingSystemVersionString)"
    
    private static var logBuffer: LogBuffer = LogBuffer(version: bundleVersion, osversion: osVersionString, logs: [])
    private static let logThreshold = 50 // Number of logs to collect before sending
    private static let batchingInterval = 60.0 // Time interval in seconds
    private static var timer: Timer?
    private static var networkDown: Bool = false
    private static var logFileURL: URL? {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let logsDirectory = appSupportURL.appendingPathComponent("NeewerLite/Logs")
        try? FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let filename = "neewerlite_log_\(Date().formattedLogFileDate()).log"
        return logsDirectory.appendingPathComponent(filename)
    }
    private static let logQueue = DispatchQueue(label: "com.neewerlite.logger.queue")
    private static let maxLogFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    public static var currentLogFileURL: URL?
    private static let lastCleanupKey = "LoggerLastCleanupDate"
    private static let cleanupInterval: TimeInterval = 2 * 60 * 60 // 2 hours
    private static var fileHandle: FileHandle? = {
        guard let url = logFileURL else { return nil }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        do {
            let handle = try FileHandle(forUpdating: url)
            handle.seekToEndOfFile()
            currentLogFileURL = url
            return handle
        } catch {
            print("Logger init error:", error)
            return nil
        }
    }()
    
    static func initialize() {
        initializeTimer()
        cleanupOldLogs()
    }
    
    private static func initializeTimer() {
        monitor.pathUpdateHandler = { path in
            if path.status == .satisfied {
                networkDown = false
            } else {
                networkDown = true
            }
        }

        monitor.start(queue: DispatchQueue.global(qos: .background))
        timer = Timer.scheduledTimer(withTimeInterval: batchingInterval, repeats: true) { _ in
            sendBatchedLogs()
            maybeCleanupOldLogs()
        }
    }
    
    private static func maybeCleanupOldLogs() {
        let now = Date()
        let defaults = UserDefaults.standard
        if let lastCleanup = defaults.object(forKey: lastCleanupKey) as? Date {
            if now.timeIntervalSince(lastCleanup) < cleanupInterval {
                return // Not time yet
            }
        }
        cleanupOldLogs()
        defaults.set(now, forKey: lastCleanupKey)
    }
    
    public static func cleanupOldLogs(olderThan days: Int = 7) {
        guard let logsDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("NeewerLite/Logs") else {
            return
        }

        let calendar = Calendar.current
        let thresholdDate = calendar.date(byAdding: .day, value: -days, to: Date())!

        do {
            let logFiles = try FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])

            for fileURL in logFiles {
                let attributes = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                if let modifiedDate = attributes.contentModificationDate,
                   modifiedDate < thresholdDate {
                    try FileManager.default.removeItem(at: fileURL)
                    print("🧹 Deleted old log: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            print("❌ Failed to clean up old logs: \(error)")
        }
    }

    
    private static func sendLogEntry(_ logEntry: LogEntry) {
#if DEBUG
        return
#else
        logBuffer.logs.append(logEntry)

        if logBuffer.logs.count >= logThreshold {
            sendBatchedLogs()
        }
#endif
    }

    private static func addLogEntry(_ logEntry: LogEntry) {
#if DEBUG
        return
#else
        logBuffer.logs.append(logEntry)
        if logBuffer.logs.count >= logThreshold {
            sendBatchedLogs()
        }
#endif
    }

    private static func sendBatchedLogs() {
#if DEBUG
        return
#else
        guard !logBuffer.logs.isEmpty else { return }
        guard !networkDown else { return }

        var request = URLRequest(url: logUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let jsonData = try JSONEncoder().encode(logBuffer)
            request.httpBody = jsonData
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // Handle response here (e.g., check for success or failure)
                if let error = error {
                    print("Error sending log entry: \(error)")
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    print("Server responded with status code: \(httpResponse.statusCode)")
                }
            }
            task.resume()
        } catch {
            print("Error encoding log entry: \(error)")
        }

        logBuffer.logs.removeAll()
#endif
    }

    public typealias FlushCompletion = () -> Void

    public class func flush(completion: @escaping FlushCompletion) {
#if DEBUG
        completion()
        return
#else
#endif
        if logBuffer.logs.count < 0 {
            completion()
            return
        }
        var request = URLRequest(url: logUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3 
        do {
            let jsonData = try JSONEncoder().encode(logBuffer)
            request.httpBody = jsonData
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                // Handle response here (e.g., check for success or failure)
                if let error = error {
                    print("Error sending log entry: \(error)")
                    completion()
                    return
                }
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    print("Server responded with status code: \(httpResponse.statusCode)")
                }
                completion()
            }
            task.resume()
            logBuffer.logs.removeAll()
        } catch {
            completion()
        }
    }

    private static func rotateLogFile() {
        logQueue.async {
            fileHandle?.closeFile()
            fileHandle = nil
            // Re-initialize fileHandle
            if let url = logFileURL {
                FileManager.default.createFile(atPath: url.path, contents: nil)
                do {
                    let handle = try FileHandle(forUpdating: url)
                    handle.seekToEndOfFile()
                    currentLogFileURL = url
                    fileHandle = handle
                } catch {
                    print("Logger rotate error:", error)
                }
            }
        }
    }
    
    public static func syncToFile() {
        // Avoid deadlock by checking if we're on main thread
        if Thread.isMainThread {
            logQueue.async {
                fileHandle?.synchronizeFile()
            }
        } else {
            logQueue.sync {
                fileHandle?.synchronizeFile()
            }
        }
    }
    
    private static func writeToFile(_ string: String) {
        logQueue.async {
            guard let handle = fileHandle else {
                print("Logger error: fileHandle is nil")
                return
            }
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let entry = "\(timestamp) - \(string)\n"
            if let data = entry.data(using: .utf8) {
                do {
                    try handle.write(contentsOf: data)
                    try handle.synchronize()
                } catch {
                    print("Logger write error:", error)
                }
            }
            if let size = try? handle.offset(), size >= maxLogFileSize {
                rotateLogFile()
            }
        }
    }

    public class func debug(_ tag: LogTag, _ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
#if DEBUG
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [DEBUG] \(message ?? "")")
#endif
    }

    public class func debug(_ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
#if DEBUG
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [DEBUG] \(message ?? "")")
#endif
    }

    public class func info(_ tag: LogTag, _ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
            let logEntry = LogEntry(tag: tag,
                                    timestamp: ISO8601DateFormatter().string(from: Date()),
                                    level: "INFO",
                                    filename: fileName,
                                    line: line,
                                    message: message)
            Logger.addLogEntry(logEntry)
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [INFO][\(tag)] \(message ?? "")")
    }

    public class func info(_ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
            let logEntry = LogEntry(tag: LogTag.none,
                                    timestamp: ISO8601DateFormatter().string(from: Date()),
                                    level: "INFO",
                                    filename: fileName,
                                    line: line,
                                    message: message)
            Logger.addLogEntry(logEntry)
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [INFO] \(message ?? "")")
    }

    public class func warn(_ tag: LogTag, _ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
            let logEntry = LogEntry(tag: tag,
                                    timestamp: ISO8601DateFormatter().string(from: Date()),
                                    level: "WARN",
                                    filename: fileName,
                                    line: line,
                                    message: message)
            Logger.addLogEntry(logEntry)
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [WARN][\(tag)] \(message ?? "")")
    }

    public class func warn(_ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
            let logEntry = LogEntry(tag: LogTag.none,
                                    timestamp: ISO8601DateFormatter().string(from: Date()),
                                    level: "WARN",
                                    filename: fileName,
                                    line: line,
                                    message: message)
            Logger.addLogEntry(logEntry)
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [WARN] \(message ?? "")")
    }

    public class func error(_ tag: LogTag, _ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
            let logEntry = LogEntry(tag: tag,
                                    timestamp: ISO8601DateFormatter().string(from: Date()),
                                    level: "ERR",
                                    filename: fileName,
                                    line: line,
                                    message: message)
            Logger.addLogEntry(logEntry)
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [ERRO][\(tag)] \(message ?? "")")
    }

    public class func error(_ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
            let logEntry = LogEntry(tag: LogTag.none,
                                    timestamp: ISO8601DateFormatter().string(from: Date()),
                                    level: "ERR",
                                    filename: fileName,
                                    line: line,
                                    message: message)
            Logger.addLogEntry(logEntry)
        } else {
            print("\(fileName):\(function):\(line)")
        }
        writeToFile("\(fileName):\(function):\(line): [ERRO] \(message ?? "")")
    }
}
