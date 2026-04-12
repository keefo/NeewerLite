//
//  VisualizationPluginManager.swift
//  NeewerLite
//
//  Created by Xu Lian on 4/11/26.
//

import Cocoa

/// Discovers, registers, and manages audio visualization plugins.
/// Supports both built-in (code-registered) and bundle-loaded plugins.
class VisualizationPluginManager {
    static let shared = VisualizationPluginManager()

    struct PluginEntry {
        let name: String
        /// Pre-created instance (e.g., XIB-loaded AudioSpectrogramVisualization).
        var instance: AudioVisualizerPlugin?
        /// Factory for lazy instantiation. Receives the desired frame rect.
        let factory: ((NSRect) -> AudioVisualizerPlugin)?
    }

    private(set) var entries: [PluginEntry] = []

    /// Register a pre-created plugin instance (e.g., the XIB-loaded spectrogram view).
    func register(instance: AudioVisualizerPlugin) {
        entries.append(PluginEntry(
            name: type(of: instance).displayName,
            instance: instance,
            factory: nil))
    }

    /// Register a plugin type with a lazy factory.
    func register(name: String, factory: @escaping (NSRect) -> AudioVisualizerPlugin) {
        entries.append(PluginEntry(name: name, instance: nil, factory: factory))
    }

    /// Get or create the plugin at the given index.
    func plugin(at index: Int, frame: NSRect) -> AudioVisualizerPlugin? {
        guard entries.indices.contains(index) else { return nil }
        if let inst = entries[index].instance { return inst }
        if let factory = entries[index].factory {
            let inst = factory(frame)
            entries[index].instance = inst
            return inst
        }
        return nil
    }

    /// Names of all available plugins, in registration order.
    var pluginNames: [String] { entries.map { $0.name } }

    // MARK: - Bundle Discovery

    /// Scan the app's PlugIns/Visualizations directory for `.bundle` files
    /// whose principal class is an `AudioVisualizerPluginBase` subclass.
    func discoverBundlePlugins() {
        guard let plugInsPath = Bundle.main.builtInPlugInsPath else { return }
        let vizDir = (plugInsPath as NSString).appendingPathComponent("Visualizations")

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(atPath: vizDir) else { return }

        for name in contents where name.hasSuffix(".bundle") {
            let path = (vizDir as NSString).appendingPathComponent(name)
            guard let bundle = Bundle(path: path),
                  bundle.load(),
                  let cls = bundle.principalClass as? AudioVisualizerPluginBase.Type else {
                continue
            }
            let displayName = cls.displayName
            register(name: displayName) { frame in
                cls.init(frame: frame)
            }
        }
    }
}
