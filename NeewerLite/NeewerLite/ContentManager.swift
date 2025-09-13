//
//  ContentManager.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/10/23.
//

import Cocoa
import Foundation

private let supportedVersion: Double = 3.0

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

struct FxPattern: Decodable {
    let id: Int
    let name: String
    let cmd: String
    let color: [String]?
}

struct NeewerLightDbItem: Decodable {
    let type: UInt8
    let image: String
    let link: String?
    let supportRGB: Bool?
    let supportCCTGM: Bool?
    let supportMusic: Bool?
    let support17FX: Bool?
    let support9FX: Bool?
    let cctRange: ccTRange?
    let newPowerLightCommand: Bool?
    let newRGBLightCommand: Bool?
    let commandPatterns: [String: String]?
    let fxPatterns: [FxPattern]?
}

struct Database: Decodable {
    let version: Double
    let lights: [NeewerLightDbItem]

    enum CodingKeys: String, CodingKey {
        case version
        case lights
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Double.self, forKey: .version)
        self.version = version

        guard version <= supportedVersion else {
            self.lights = []
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "Unsupported database version: \(version)")
        }

        self.lights = try container.decode([NeewerLightDbItem].self, forKey: .lights)
    }
}

class ContentManager {

    static let databaseUpdatedNotification = Notification.Name("LightDatabaseUpdated")
    static let databaseUpdatedCountdownNotification = Notification.Name(
        "LightDatabaseSyncCountdown")

    enum DBUpdateStatus {
        case success
        case failure(Error)
    }

    static let shared = ContentManager()

    private let fileManager = FileManager.default
    private let session = URLSession(configuration: .default)
    private var failedURLs = Set<URL>()
    private var lastCheckedDate: Date? {  // Store the ETag value
        didSet {
            UserDefaults.standard.setValue(lastCheckedDate, forKey: "lastCheckedDate")
        }
    }
    public let operationQueue: OperationQueue

    // Cache for the parsed JSON data
    private var databaseCache: Database?

    // Image Cache Directory
    private lazy var cacheDirectory: URL = {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let cacheURL = appSupportURL.appendingPathComponent("NeewerLite/LightImageCache")
        if !fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.createDirectory(
                at: cacheURL, withIntermediateDirectories: true, attributes: nil)
        }
        return cacheURL
    }()

    // JSON Database URL
    private let jsonDatabaseURL = URL(
        string: "https://raw.githubusercontent.com/keefo/NeewerLite/main/Database/lights.json")!
    private var localDatabaseURL: URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let cacheURL = appSupportURL.appendingPathComponent("NeewerLite/database.json")
        return cacheURL
    }
    private var ttlTimer: Timer?
    private let ttlInterval: TimeInterval = 28800  // 8 hours
    private var nextDownloadDate: Date? {
        guard let last = lastCheckedDate else { return nil }
        return last.addingTimeInterval(ttlInterval)
    }
    public var remainingTTL: TimeInterval? {
        guard let next = nextDownloadDate else { return nil }
        return max(next.timeIntervalSinceNow, 0)
    }

    private init() {
        operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 10  // Adjust this as needed
        ttlTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkTTL()
        }
        RunLoop.main.add(ttlTimer!, forMode: .common)
    }

    private func checkTTL() {
        guard let remaining = remainingTTL else { return }
        NotificationCenter.default.post(
            name: ContentManager.databaseUpdatedCountdownNotification, object: nil,
            userInfo: ["remaining": remaining])
        if remaining <= 0 {
            if self.shouldDownloadDatabase() {
                Task.detached(priority: .background) {
                    do {
                        try await self.downloadDatabaseNow()
                    } catch {
                        Logger.error("❌ Failed to download database: \(error)")
                    }
                }
            }
        }
    }

    public func loadDatabaseFromDisk(reload: Bool = false) {
        if databaseCache == nil || reload {
            do {
                #if DEBUG
                    // Try to load from resources in debug build
                    if let resourceURL = Bundle.main.url(
                        forResource: "lights", withExtension: "json")
                    {
                        let data = try Data(contentsOf: resourceURL)
                        databaseCache = try JSONDecoder().decode(Database.self, from: data)
                        return
                    }
                #endif
                // Fallback to local cache file
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

                if case DecodingError.dataCorrupted(let context) = error,
                    context.debugDescription.contains("Unsupported database version")
                {
                    Task { @MainActor in
                        let alert = NSAlert()
                        alert.messageText = "Database Error"
                        alert.informativeText =
                            "\(context.debugDescription).\nPlease update to the latest version of the app."
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            }
        }
    }

    public func downloadDatabase(force: Bool) {
        if !force && !self.shouldDownloadDatabase() {
            return
        }
        Task.detached(priority: .background) {
            do {
                try await self.downloadDatabaseNow()
                if force {
                    Task { @MainActor in
                        let alert = NSAlert()
                        alert.messageText = "Finish"
                        alert.informativeText = "The database is up to date."
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }
                }
            } catch {
                Logger.error("❌ Failed to download database: \(error)")
            }
        }
    }

    // MARK: - JSON Database Management
    private func downloadDatabaseNow() async throws {
        lastCheckedDate = Date()
        do {
            Logger.info("Download database...")
            let (data, _) = try await session.data(from: jsonDatabaseURL)
            Logger.info("Download content: \(String(data: data, encoding: .utf8) ?? "<binary>")")
            try data.write(to: localDatabaseURL)
            loadDatabaseFromDisk(reload: true)
            NotificationCenter.default.post(
                name: Self.databaseUpdatedNotification,
                object: nil,
                userInfo: ["status": Self.DBUpdateStatus.success]
            )
        } catch {
            NotificationCenter.default.post(
                name: Self.databaseUpdatedNotification,
                object: nil,
                userInfo: ["status": Self.DBUpdateStatus.failure(error)]
            )
            throw error
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
        let updateInterval: TimeInterval = 28800  // For example, 8 hours
        if let lastCheckedDate = lastCheckedDate,
            Date().timeIntervalSince(lastCheckedDate) < updateInterval
        {
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

        if isImageCached(lightType: lightType),
            let image = NSImage(contentsOf: cachedImageURL(lightType: lightType))
        {
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
            else {
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
        if isImageCached(lightType: lightType),
            let image = NSImage(contentsOf: cachedImageURL(lightType: lightType))
        {
            return image
        }
        return nil
    }

    func fetchLightProperty(lightType: UInt8) -> NeewerLightDbItem? {
        return databaseCache?.lights.first(where: { $0.type == lightType })
    }

    func fetchLightImage(lightType: UInt8) async throws -> NSImage? {
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
