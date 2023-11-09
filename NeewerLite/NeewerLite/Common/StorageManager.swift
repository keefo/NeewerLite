//
//  StorageManager.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/8/23.
//

import Foundation

class StorageManager {
    private let fileManager: FileManager
    private let appSupportDirectory: URL

    init?() {
        fileManager = FileManager.default
        // Find the application support directory in the user domain
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        // Append your app's identifier to ensure uniqueness
        appSupportDirectory = appSupportURL.appendingPathComponent(Bundle.main.bundleIdentifier ?? "NeewerLite")
        do {
            try fileManager.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true, attributes: nil)
        } catch {
            print("Could not create directory at \(appSupportDirectory): \(error)")
            return nil
        }
    }

    func save(data: Data, to fileName: String) -> Bool {
        let fileURL = appSupportDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL)
            Logger.debug("Data saved to \(fileURL)")
            return true
        } catch {
            Logger.error("Could not write data to \(fileURL): \(error)")
        }
        return false
    }

    func load(from fileName: String) -> Data? {
        let fileURL = appSupportDirectory.appendingPathComponent(fileName)
        do {
            return try Data(contentsOf: fileURL)
        } catch {
            Logger.error("Could not read data from \(fileURL): \(error)")
            return nil
        }
    }
}
