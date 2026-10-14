import AppKit

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let url: URL

    public init(bundleID: String, name: String, url: URL) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
    }

    public var category: AppCategory? {
        KeystrokeProfiles.knownApps.first { $0.bundleID == bundleID }?.category
    }
}

public enum InstalledAppsScanner {
    public static var searchDirectories: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// Reads an app's bundle ID and display name from its Info.plist.
    public static func app(at url: URL) -> InstalledApp? {
        guard url.pathExtension == "app", let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String)
            ?? (info?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        return InstalledApp(bundleID: bundleID, name: name, url: url)
    }

    /// Known apps (browsers, terminals, editors) that are installed, in the UI's display order.
    public static func installedKnownApps() -> [InstalledApp] {
        KeystrokeProfiles.knownApps.compactMap { known in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: known.bundleID) else { return nil }
            return InstalledApp(bundleID: known.bundleID, name: known.name, url: url)
        }
    }

    /// Every app in the standard folders (and one level of subfolders such as Utilities), sorted by name.
    public static func scanAll(directories: [URL] = searchDirectories) -> [InstalledApp] {
        var found: [String: InstalledApp] = [:]
        let fm = FileManager.default
        func visit(_ dir: URL, depth: Int) {
            guard let items = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
            for item in items {
                if item.pathExtension == "app" {
                    if let app = app(at: item), found[app.bundleID] == nil { found[app.bundleID] = app }
                } else if depth < 1, (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    visit(item, depth: depth + 1)
                }
            }
        }
        directories.forEach { visit($0, depth: 0) }
        return found.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Regular (Dock) apps running right now.
    @MainActor
    public static func runningApps() -> [InstalledApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .compactMap { app in
                guard let id = app.bundleIdentifier, let url = app.bundleURL else { return nil }
                return InstalledApp(bundleID: id, name: app.localizedName ?? id, url: url)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
