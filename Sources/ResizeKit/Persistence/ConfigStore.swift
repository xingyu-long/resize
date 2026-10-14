import Foundation
import os

/// Loads and saves `AppConfig` as JSON. Never throws on load: a missing or corrupt file yields defaults.
public struct ConfigStore: Sendable {
    public let url: URL
    private static let log = Logger(subsystem: "dev.xingyulong.Resize", category: "ConfigStore")

    public static var defaultURL: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Resize", isDirectory: true)
            .appendingPathComponent("config.json")
    }

    public init(url: URL = ConfigStore.defaultURL) {
        self.url = url
    }

    public func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppConfig() }
        do {
            return try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
        } catch {
            Self.log.error("Could not read config, using defaults: \(error.localizedDescription)")
            return AppConfig()
        }
    }

    public func save(_ config: AppConfig) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        } catch {
            Self.log.error("Could not save config: \(error.localizedDescription)")
        }
    }
}
