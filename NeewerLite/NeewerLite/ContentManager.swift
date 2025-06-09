//
//  ContentManager.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/10/23.
//

import Foundation
import Cocoa

class ImageFetchOperation: Operation {
    var lightType: UInt8
    var completionHandler: ((NSImage?) -> Void)?

    init(lightType: UInt8, completionHandler: ((NSImage?) -> Void)?) {
        self.lightType = lightType
        self.completionHandler = completionHandler
    }

    override func main() {
        if isCancelled {
            return
        }
        Task {
            let image = try? await ContentManager.shared.fetchLightImage(lightType: self.lightType)
            if !isCancelled {
                DispatchQueue.main.async {
                    self.completionHandler?(image)
                }
            }
        }
    }
}

struct ccTRange: Decodable {
    let min: Int
    let max: Int
}

struct NeewerLightDbItem: Decodable {
    let type: UInt8
    let link: String?
    let image: String
    let supportRGB: Bool
    let supportCCTGM: Bool
    let supportMusic: Bool
    let support17FX: Bool
    let support9FX: Bool
    let cctRange: ccTRange?
    let newPowerLightCommand: Bool?
    let newRGBLightCommand: Bool?
}

struct Database: Decodable {
    let version: Int
    let lights: [NeewerLightDbItem]
}


class ContentManager {
    static let shared = ContentManager()
    private let fileManager = FileManager.default
    private let session = URLSession(configuration: .default)
    private var failedURLs = Set<URL>()
    private var lastCheckedDate: Date? { // Store the ETag value
        didSet {
            UserDefaults.standard.setValue(lastCheckedDate, forKey: "lastCheckedDate")
        }
    }
    public let operationQueue: OperationQueue

    // Cache for the parsed JSON data
    private var databaseCache: Database?

    // Image Cache Directory
    private lazy var cacheDirectory: URL = {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheURL = appSupportURL.appendingPathComponent("NeewerLite/LightImageCache")
        if !fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.createDirectory(at: cacheURL, withIntermediateDirectories: true, attributes: nil)
        }
        return cacheURL
    }()

    // JSON Database URL
    private let jsonDatabaseURL = URL(string: "https://raw.githubusercontent.com/keefo/NeewerLite/main/Database/lights.json")!
    private var localDatabaseURL: URL {
        cacheDirectory.appendingPathComponent("database.json")
    }

    private init() {
        operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 10 // Adjust this as needed
    }

    private func loadDatabaseFromDisk(){
        if databaseCache == nil {
            do {
                if fileManager.fileExists(atPath: localDatabaseURL.path) {
                    let data = try Data(contentsOf: localDatabaseURL)
                    databaseCache = try JSONDecoder().decode(Database.self, from: data)
                }
            } catch {
                Logger.error("Error reading or parsing JSON: \(error)")
                do {
                    try fileManager.removeItem(atPath: localDatabaseURL.path)
                } catch {
                }
            }
        }
    }
    
    public func syncDatabase()
    {
        loadDatabaseFromDisk()
        Task.detached(priority: .background) {
            do {
                try await self.downloadDatabaseIfNeeded()
                Logger.info("✅ Database download completed.")
            } catch {
                Logger.error("❌ Failed to download database: \(error)")
            }
        }
    }
    
    // MARK: - JSON Database Management
    private func downloadDatabaseIfNeeded() async throws {
        if shouldDownloadDatabase() {
            do {
                let (data, _) = try await session.data(from: jsonDatabaseURL)
                try data.write(to: localDatabaseURL)
            } catch {
                Logger.error("Error downloading the database: \(error)")
                throw error
            }
            lastCheckedDate = Date()
        }
    }

    private func shouldDownloadDatabase() -> Bool {
        // Check if the local file exists and is valid
        if !fileManager.fileExists(atPath: localDatabaseURL.path) {
            return true
        }
        if let safeCache = databaseCache {
            if safeCache.version == 1 {
                return true
            }
        }
        // Check if enough time has passed since the last check
        let updateInterval: TimeInterval = 28800 // For example, 8 hours
        if let lastCheckedDate = lastCheckedDate,
           Date().timeIntervalSince(lastCheckedDate) < updateInterval {
            return false
        }
        return true
    }

    // MARK: - Image Fetching and Caching
    func fetchImage(from urlString: String, lightType: UInt8) async throws -> NSImage? {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "InvalidURL", code: 0, userInfo: nil)
        }

        if failedURLs.contains(url) {
            throw NSError(domain: "NetworkFailure", code: 0, userInfo: nil)
        }

        if isImageCached(lightType: lightType), let image = NSImage(contentsOf: cachedImageURL(lightType: lightType)) {
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "InvalidResponse", code: 0, userInfo: nil)
            }

            if let img = NSImage(data: data) {
                saveImageToCache(data, for: url, lightType: lightType)
                return img
            }
        } catch {
            failedURLs.insert(url)
        }
        return nil
    }

    private func cachedURL(for url: URL) -> URL {
        cacheDirectory.appendingPathComponent(url.lastPathComponent)
    }

    private func cachedImageURL(lightType: UInt8) -> URL {
        cacheDirectory.appendingPathComponent("\(lightType).png")
    }

    private func isImageCached(lightType: UInt8) -> Bool {
        fileManager.fileExists(atPath: cachedImageURL(lightType: lightType).path)
    }

    private func saveImageToCache(_ data: Data, for url: URL, lightType: UInt8) {
        let cachedURL = self.cachedImageURL(lightType: lightType)
        fileManager.createFile(atPath: cachedURL.path, contents: data, attributes: nil)
    }

    // MARK: - Handling Network Failures
    func clearFailedURLs() {
        failedURLs.removeAll()
    }

    func fetchCachedLightImage(lightType: UInt8) -> NSImage? {
        if isImageCached(lightType: lightType), let image = NSImage(contentsOf: cachedImageURL(lightType: lightType)) {
            return image
        }
        return nil
    }

    func fetchLightProperty(lightType: UInt8) -> NeewerLightDbItem? {
        if let safeCache = databaseCache {
            let lights = safeCache.lights
            if let found = lights.first(where: { $0.type == lightType }) {
                return found
            }
        }
        return nil
    }
    
    func fetchLightImage(lightType: UInt8) async throws -> NSImage? {
        try await downloadDatabaseIfNeeded()
        guard let imageUrl = fetchImageUrl(for: lightType) else {
            throw NSError(domain: "NoImageURLFound", code: Int(lightType), userInfo: nil)
        }
        return try await fetchImage(from: imageUrl, lightType: lightType)
    }

    private func fetchImageUrl(for lightType: UInt8) -> String? {
        if let safeCache = databaseCache {
            let lights = safeCache.lights
            if let found = lights.first(where: { $0.type == lightType }) {
                return found.image
            }
        }
        return nil
    }
}
