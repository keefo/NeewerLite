//
//  ContentManager.swift
//  NeewerLite
//
//  Created by Xu Lian on 11/10/23.
//

import Cocoa
import Foundation

private let supportedVersion: Double = 4.0

class ImageFetchOperation: Operation {
    var lightType: UInt8
    var productId: String?
    var completionHandler: ((NSImage?) -> Void)?

    init(lightType: UInt8, productId: String? = nil, completionHandler: ((NSImage?) -> Void)?) {
        self.lightType = lightType
        self.productId = productId
        self.completionHandler = completionHandler
    }

    override func main() {
        if isCancelled {
            return
        }
        Task {
            let image: NSImage?
            if let pid = self.productId {
                image = try? await ContentManager.shared.fetchLightImage(productId: pid)
            } else {
                image = try? await ContentManager.shared.fetchLightImage(lightType: self.lightType)
            }
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

struct NamedPattern: Decodable {
    let id: Int
    let name: String
    let cmd: String
    let defaultCmd: String?
    let icon: String?
    let image: String?
    let category: String?
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
    let sourcePatterns: [NamedPattern]?
    let fxPreset: String?
    let fxPatterns: [String]?
}

struct HomeDevice: Decodable {
    let productId: String
    let name: String
    let image: String?
    let supportColor: Bool?
    let supportScene: Bool?
    let supportDIY: Bool?
    let supportMusic: Bool?
    let commandPatterns: [String: String]?
    let fxPreset: String?
    let fxPatterns: [String]?
}

struct Database: Decodable {
    let version: Double
    let fxPresets: [String: [NamedPattern]]
    let lights: [NeewerLightDbItem]
    let gels: [NeewerGel]
    let homeDevices: [HomeDevice]

    enum CodingKeys: String, CodingKey {
        case version
        case fxPresets
        case lights
        case gels
        case homeDevices = "neewer_home"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Double.self, forKey: .version)
        self.version = version

        guard version <= supportedVersion else {
            self.fxPresets = [:]
            self.lights = []
            self.gels = []
            self.homeDevices = []
            throw DecodingError.dataCorruptedError(
                forKey: .version, in: container,
                debugDescription: "Unsupported database version: \(version)")
        }

        self.fxPresets = try container.decodeIfPresent([String: [NamedPattern]].self, forKey: .fxPresets) ?? [:]
        self.lights = try container.decode([NeewerLightDbItem].self, forKey: .lights)
        self.gels = try container.decodeIfPresent([NeewerGel].self, forKey: .gels) ?? []
        self.homeDevices = try container.decodeIfPresent([HomeDevice].self, forKey: .homeDevices) ?? []
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
    #if DEBUG
    let jsonDatabaseURL = URL(
        string: "https://raw.githubusercontent.com/keefo/NeewerLite/user/keefo/add-neewer-home-support/Database/lights.json")!
    private let imageBaseURL = URL(
        string: "https://raw.githubusercontent.com/keefo/NeewerLite/user/keefo/add-neewer-home-support/Database/")!
    #else
    let jsonDatabaseURL = URL(
        string: "https://raw.githubusercontent.com/keefo/NeewerLite/main/Database/lights.json")!
    private let imageBaseURL = URL(
        string: "https://raw.githubusercontent.com/keefo/NeewerLite/main/Database/")!
    #endif

    /// Resolves image references from the database.
    /// Accepts either a full URL (legacy) or a bare filename resolved against imageBaseURL.
    func resolveImageURL(_ ref: String, subdirectory: String) -> URL? {
        if ref.hasPrefix("http://") || ref.hasPrefix("https://") {
            return URL(string: ref)
        }
        return imageBaseURL.appendingPathComponent(subdirectory).appendingPathComponent(ref)
    }
    var localDatabaseURL: URL {
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
        let cacheURL = appSupportURL.appendingPathComponent("NeewerLite/database.json")
        return cacheURL
    }

    var localDatabaseExists: Bool {
        fileManager.fileExists(atPath: localDatabaseURL.path)
    }

    func deleteLocalDatabase() {
        try? fileManager.removeItem(atPath: localDatabaseURL.path)
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
                // Load from local cache file
                if fileManager.fileExists(atPath: localDatabaseURL.path) {
                    let data = try Data(contentsOf: localDatabaseURL)
                    databaseCache = try JSONDecoder().decode(Database.self, from: data)
                    GelLibrary.shared.reload()
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

    public func downloadDatabase(force: Bool, silent: Bool = false) {
        if !force && !self.shouldDownloadDatabase() {
            return
        }
        Task.detached(priority: .background) {
            do {
                try await self.downloadDatabaseNow()
                if force && !silent {
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
            var request = URLRequest(url: jsonDatabaseURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, _) = try await session.data(for: request)
            try await Task.sleep(nanoseconds: 1_000_000_000)
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
        #if DEBUG
        return true
        #endif
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

    private func saveImageToCache(_ data: Data, url: URL) {
        let cachedURL = self.cachedURL(for: url)
        fileManager.createFile(atPath: cachedURL.path, contents: data, attributes: nil)
    }

    // MARK: - Handling Network Failures
    func clearFailedURLs() {
        failedURLs.removeAll()
    }

    // MARK: - Scene Image Fetching and Caching

    func fetchCachedSceneImage(urlString: String) -> NSImage? {
        guard let url = resolveImageURL(urlString, subdirectory: "scene_images") else { return nil }
        let cached = cachedURL(for: url)
        if fileManager.fileExists(atPath: cached.path),
           let image = NSImage(contentsOf: cached)
        {
            return image
        }
        return nil
    }

    func fetchSceneImage(urlString: String) async -> NSImage? {
        guard let url = resolveImageURL(urlString, subdirectory: "scene_images") else { return nil }
        if failedURLs.contains(url) { return nil }

        let cached = cachedURL(for: url)
        if fileManager.fileExists(atPath: cached.path),
           let image = NSImage(contentsOf: cached)
        {
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }
            if let img = NSImage(data: data) {
                saveImageToCache(data, url: url)
                return img
            }
        } catch {
            failedURLs.insert(url)
        }
        return nil
    }

    // MARK: - Light Image Fetching and Caching

    func fetchCachedLightImage(lightType: UInt8) -> NSImage? {
        if isImageCached(lightType: lightType),
            let image = NSImage(contentsOf: cachedImageURL(lightType: lightType))
        {
            return image
        }
        return nil
    }

    func fetchCachedLightImage(productId: String) -> NSImage? {
        guard let device = fetchHomeDevice(productId: productId),
              let imageRef = device.image,
              let url = resolveImageURL(imageRef, subdirectory: "light_images") else {
            return nil
        }
        let cached = cachedURL(for: url)
        if fileManager.fileExists(atPath: cached.path),
           let image = NSImage(contentsOf: cached)
        {
            return image
        }
        return nil
    }

    func fetchLightImage(productId: String) async throws -> NSImage? {
        guard let device = fetchHomeDevice(productId: productId),
              let imageRef = device.image,
              let url = resolveImageURL(imageRef, subdirectory: "light_images") else {
            return nil
        }

        if failedURLs.contains(url) {
            return nil
        }

        let cached = cachedURL(for: url)
        if fileManager.fileExists(atPath: cached.path),
           let image = NSImage(contentsOf: cached)
        {
            return image
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            if let img = NSImage(data: data) {
                saveImageToCache(data, url: url)
                return img
            }
        } catch {
            failedURLs.insert(url)
        }
        return nil
    }

    func fetchLightProperty(lightType: UInt8) -> NeewerLightDbItem? {
        return databaseCache?.lights.first(where: { $0.type == lightType })
    }

    func resolvedFxPatterns(for item: NeewerLightDbItem) -> [NamedPattern] {
        // Priority: fxPatterns (refs) > fxPreset > none
        if let refs = item.fxPatterns, !refs.isEmpty {
            return refs.compactMap { resolveFxRef($0) }
        }
        if let presetName = item.fxPreset,
           let patterns = databaseCache?.fxPresets[presetName] {
            return patterns
        }
        return []
    }

    func resolvedFxPatterns(for device: HomeDevice) -> [NamedPattern] {
        if let refs = device.fxPatterns, !refs.isEmpty {
            return refs.compactMap { resolveFxRef($0) }
        }
        if let presetName = device.fxPreset,
           let patterns = databaseCache?.fxPresets[presetName] {
            return patterns
        }
        return []
    }

    private func resolveFxRef(_ ref: String) -> NamedPattern? {
        let parts = ref.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              let id = Int(parts[1]),
              let patterns = databaseCache?.fxPresets[String(parts[0])] else { return nil }
        return patterns.first(where: { $0.id == id })
    }

    func fetchHomeDevice(productId: String) -> HomeDevice? {
        return databaseCache?.homeDevices.first(where: { $0.productId == productId })
    }

    func fetchGels() -> [NeewerGel] {
        return databaseCache?.gels ?? []
    }

    var databaseVersion: Double {
        return databaseCache?.version ?? 0
    }

    var databaseLightCount: Int {
        return databaseCache?.lights.count ?? 0
    }

    var databaseHomeDeviceCount: Int {
        return databaseCache?.homeDevices.count ?? 0
    }

    var databaseFxPresetCount: Int {
        return databaseCache?.fxPresets.count ?? 0
    }

    var databaseGelCount: Int {
        return databaseCache?.gels.count ?? 0
    }

    func fetchLightImage(lightType: UInt8) async throws -> NSImage? {
        guard let imageRef = fetchImageRef(for: lightType),
              let url = resolveImageURL(imageRef, subdirectory: "light_images") else {
            throw NSError(domain: "NoImageURLFound", code: Int(lightType), userInfo: nil)
        }
        return try await fetchImage(from: url.absoluteString, lightType: lightType)
    }

    private func fetchImageRef(for lightType: UInt8) -> String? {
        if let safeCache = databaseCache {
            let lights = safeCache.lights
            if let found = lights.first(where: { $0.type == lightType }) {
                return found.image
            }
        }
        return nil
    }
}
