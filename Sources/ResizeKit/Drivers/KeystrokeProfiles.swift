import Foundation

public enum AppCategory: String, CaseIterable, Sendable {
    case browser = "Browsers"
    case terminal = "Terminals"
    case editor = "Editors"
}

public struct KnownApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String
    public let category: AppCategory
}

public enum KeystrokeProfiles {
    public static let chromiumSteps = [25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300, 400, 500]
    public static let firefoxSteps = [30, 50, 67, 80, 90, 100, 110, 120, 133, 150, 170, 200, 240, 300, 400, 500]
    public static let safariSteps = [50, 75, 85, 100, 115, 125, 150, 175, 200, 250, 300]

    private static let chromium = KeystrokeProfile(scale: .steps(chromiumSteps))

    /// Known apps, in the order shown in the UI.
    public static let knownApps: [KnownApp] = [
        KnownApp(bundleID: "com.google.Chrome", name: "Chrome", category: .browser),
        KnownApp(bundleID: "com.apple.Safari", name: "Safari", category: .browser),
        KnownApp(bundleID: "org.mozilla.firefox", name: "Firefox", category: .browser),
        KnownApp(bundleID: "com.microsoft.edgemac", name: "Edge", category: .browser),
        KnownApp(bundleID: "com.brave.Browser", name: "Brave", category: .browser),
        KnownApp(bundleID: "company.thebrowser.Browser", name: "Arc", category: .browser),
        KnownApp(bundleID: "com.vivaldi.Vivaldi", name: "Vivaldi", category: .browser),
        KnownApp(bundleID: "com.operasoftware.Opera", name: "Opera", category: .browser),
        KnownApp(bundleID: "com.apple.Terminal", name: "Terminal", category: .terminal),
        KnownApp(bundleID: "com.googlecode.iterm2", name: "iTerm2", category: .terminal),
        KnownApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty", category: .terminal),
        KnownApp(bundleID: "net.kovidgoyal.kitty", name: "kitty", category: .terminal),
        KnownApp(bundleID: "org.alacritty", name: "Alacritty", category: .terminal),
        KnownApp(bundleID: "com.github.wez.wezterm", name: "WezTerm", category: .terminal),
        KnownApp(bundleID: "dev.warp.Warp-Stable", name: "Warp", category: .terminal),
        KnownApp(bundleID: "com.microsoft.VSCode", name: "VS Code", category: .editor),
        KnownApp(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor", category: .editor),
    ]

    public static let byBundleID: [String: KeystrokeProfile] = [
        "com.google.Chrome": chromium,
        "com.microsoft.edgemac": chromium,
        "com.brave.Browser": chromium,
        "company.thebrowser.Browser": chromium,
        "com.vivaldi.Vivaldi": chromium,
        "com.operasoftware.Opera": chromium,
        "org.mozilla.firefox": KeystrokeProfile(scale: .steps(firefoxSteps)),
        "com.apple.Safari": KeystrokeProfile(scale: .steps(safariSteps)),
        "com.microsoft.VSCode": chromium,                    // Electron
        "com.todesktop.230313mzl4w4u92": chromium,           // Cursor (Electron)
        "com.apple.Terminal": KeystrokeProfile(scale: .points(defaultBase: 12, pointsPerStep: 1)),
        "com.googlecode.iterm2": KeystrokeProfile(scale: .points(defaultBase: 12, pointsPerStep: 1)),
        "com.mitchellh.ghostty": KeystrokeProfile(scale: .points(defaultBase: 13, pointsPerStep: 1)),
        // TODO verify: kitty's default step is 2pt on some versions.
        "net.kovidgoyal.kitty": KeystrokeProfile(scale: .points(defaultBase: 11, pointsPerStep: 1)),
        // TODO verify step size.
        "org.alacritty": KeystrokeProfile(scale: .points(defaultBase: 11.25, pointsPerStep: 1)),
        // TODO verify: WezTerm scales by ×1.1 per step, not +1pt; model as steps if so.
        "com.github.wez.wezterm": KeystrokeProfile(scale: .points(defaultBase: 12, pointsPerStep: 1)),
        // TODO verify.
        "dev.warp.Warp-Stable": KeystrokeProfile(scale: .points(defaultBase: 13, pointsPerStep: 1)),
    ]

    public static func isKnown(_ bundleID: String) -> Bool { byBundleID[bundleID] != nil }

    public static func profile(for bundleID: String) -> KeystrokeProfile {
        byBundleID[bundleID] ?? .generic
    }
}
