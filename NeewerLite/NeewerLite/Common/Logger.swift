//
//  Logger.swift
//  NeewerLite
//
//  Created by Xu Lian on 1/5/21.
//

import Foundation

public class Logger {
    public class func debug(_ message:String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
#if DEBUG
        if let message = message {
            print("\(file):\(function):\(line): \(message)")
        } else {
            print("\(file):\(function):\(line)")
        }
#endif
    }

    public class func info(_ message:String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        if let message = message {
            print("\(file):\(function):\(line): \(message)")
        } else {
            print("\(file):\(function):\(line)")
        }
    }

    public class func error(_ message:String? = nil, function: String = #function, file: String = #file, line: Int = #line) {
        if let message = message {
            print("\(file):\(function):\(line): \(message)")
        } else {
            print("\(file):\(function):\(line)")
        }
    }
}
