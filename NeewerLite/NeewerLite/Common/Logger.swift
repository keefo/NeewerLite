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

    static func initializeTimer() {
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
        }
    }

    private static func sendLogEntry(_ logEntry: LogEntry) {
        logBuffer.logs.append(logEntry)

        if logBuffer.logs.count >= logThreshold {
            sendBatchedLogs()
        }
    }

    private static func addLogEntry(_ logEntry: LogEntry) {
        logBuffer.logs.append(logEntry)
        if logBuffer.logs.count >= logThreshold {
            sendBatchedLogs()
        }
    }

    private static func sendBatchedLogs() {
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
    }

    public typealias FlushCompletion = () -> Void

    public class func flush(completion: @escaping FlushCompletion) {

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

    public class func debug(_ message: String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
#if DEBUG
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let message = message {
            print("\(fileName):\(function):\(line): \(message)")
        } else {
            print("\(fileName):\(function):\(line)")
        }
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
    }
}
