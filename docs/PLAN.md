# Resize — Implementation Plan (Phase 1–2)

This document is the single source of truth for building Resize. It is written so an
engineer (or model) with **no prior context** can implement it step by step.

---

## 1. Product summary

Resize is a native macOS **menu bar app**. The user picks apps (browsers, terminals, editors,
anything) and sets **one zoom percentage per app for each of two display modes**:

- **Laptop** — only the built-in display is active.
- **External** — at least one external display is connected (lid open or closed).

When the display setup changes, or a managed app launches, Resize applies the right zoom
to each managed app automatically.

### Decisions already made (do not re-litigate)

- **Zoom is per app, not per tab or per window.** One value per app per display mode.
- **Only two profiles: Laptop and External.** Multiple external monitors are all treated as "External".
- **Global default zoom per mode** (e.g. laptop 100%, external 125%). Every app follows the defaults unless the user sets
  a per-app override. The UI must be intuitive and native-feeling; see Step 13.
- **Zoom is stored as a percentage** (e.g. `125`). Each driver translates it into whatever the app uses.
- **Driver ladder** (most exact first): direct control channel → config file + live reload → keystrokes.
  Phase 1–2 builds only the **keystroke driver**, used as the universal fallback, so every app works from day one.
- **Distribution:** outside the Mac App Store (notarized DMG later). **No App Sandbox.** Accessibility is required.
- **Minimum macOS 14** (Sonoma): `MenuBarExtra`, `SMAppService`, the `@Observable` macro.

### Out of scope for this phase (later phases, see §9)

Browser extension + native messaging, AppleScript/CLI/config-file drivers, per-window zoom,
multiple named external-monitor profiles, notarization/DMG.

---

## 2. Tech stack and repo layout

- Swift 5.10+ / Swift 6 toolchain, SwiftUI + AppKit, **Swift Package Manager** (no .xcodeproj).
- A shell script wraps the SPM executable into a real `.app` bundle with `LSUIElement` set, so
  there's no Dock icon.

```
resize/
├── CLAUDE.md                     # short pointer to this plan
├── docs/PLAN.md                  # this file
├── Package.swift
├── Sources/
│   ├── ResizeKit/               # all logic, no SwiftUI; unit-testable
│   │   ├── Model/
│   │   │   ├── DisplayMode.swift
│   │   │   ├── AppRule.swift
│   │   │   └── AppConfig.swift
│   │   ├── Persistence/
│   │   │   └── ConfigStore.swift
│   │   ├── Monitoring/
│   │   │   ├── DisplayMonitor.swift
│   │   │   └── AppLaunchMonitor.swift
│   │   ├── Drivers/
│   │   │   ├── ZoomDriver.swift
│   │   │   ├── DriverRegistry.swift
│   │   │   ├── KeystrokeProfile.swift
│   │   │   ├── KeystrokeProfiles.swift   # known apps table
│   │   │   ├── KeystrokeDriver.swift
│   │   │   └── KeySender.swift           # CGEvent wrapper (protocol + real impl)
│   │   ├── Permissions/
│   │   │   └── AccessibilityPermission.swift
│   │   └── Coordinator/
│   │       └── ZoomCoordinator.swift
│   └── Resize/                  # the app target (SwiftUI)
│       ├── ResizeApp.swift
│       ├── AppState.swift
│       ├── MenuBarView.swift
│       ├── SettingsView.swift
│       ├── AppPickerView.swift
│       └── LaunchAtLogin.swift
├── Resources/
│   └── Info.plist
├── Tests/
│   └── ResizeKitTests/
│       ├── KeystrokeMathTests.swift
│       ├── AppConfigCodingTests.swift
│       ├── DriverRegistryTests.swift
│       └── CoordinatorTests.swift
└── scripts/
    ├── bundle.sh                 # swift build → Resize.app
    └── run.sh                    # bundle + open
```

---

## 3. Step-by-step implementation

Do the steps in order. After each step, `swift build` and `swift test` must pass.

### Step 0 — Check the environment

1. Run `swift --version` and `xcodebuild -version`. Full Xcode is needed for SwiftUI/AppKit SDKs, not just the Command Line Tools.
2. The repo is a fresh git repo on branch `master`. Before the first commit, create a feature branch (`git checkout -b scaffold`).
3. Add `.gitignore`: `.build/`, `build/`, `*.app`, `.swiftpm/`, `DerivedData/`, `.DS_Store`.

### Step 1 — `Package.swift`

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Resize",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Resize", targets: ["Resize"])],
    targets: [
        .target(name: "ResizeKit"),
        .executableTarget(name: "Resize", dependencies: ["ResizeKit"]),
        .testTarget(name: "ResizeKitTests", dependencies: ["ResizeKit"]),
    ]
)
```

Use `swift-tools-version:5.10` so strict Swift 6 concurrency isn't forced. Mark UI-touching types `@MainActor`.

### Step 2 — Model (`ResizeKit/Model`)

```swift
public enum DisplayMode: String, Codable, CaseIterable, Sendable {
    case laptop, external
}

public struct AppRule: Codable, Identifiable, Hashable, Sendable {
    public var id: String { bundleID }
    public var bundleID: String
    public var displayName: String
    public var enabled: Bool = true
    /// nil = follow the global default for that mode (AppConfig.defaultPercents).
    public var laptopPercent: Int? = nil
    public var externalPercent: Int? = nil
    /// For point-based apps (terminals): the font size that equals 100%.
    /// nil = use the KeystrokeProfile default.
    public var baseFontSize: Double? = nil

    public func percent(for mode: DisplayMode, defaults: [DisplayMode: Int]) -> Int {
        let own = mode == .laptop ? laptopPercent : externalPercent
        return own ?? defaults[mode] ?? 100
    }
}

public struct AppConfig: Codable, Sendable {
    public var version: Int = 1
    /// Global defaults. Every app follows these unless it has its own override.
    public var defaultPercents: [DisplayMode: Int] = [.laptop: 100, .external: 125]
    public var rules: [AppRule] = []
    public var hasCompletedOnboarding: Bool = false
    public var paused: Bool = false            // master on/off switch from the menu bar
    public var applyOnLaunch: Bool = true
    public var displayChangeDebounceSeconds: Double = 1.5
    public var launchApplyDelaySeconds: Double = 2.0
}
```

Clamp the allowed percentages to 25…500 in the UI.

Make `DisplayMode` conform to `CodingKeyRepresentable`. Without it, `[DisplayMode: Int]` encodes as a JSON array instead of
`{"laptop":100,"external":125}`. Decode missing keys with defaults (a custom `init(from:)` using `decodeIfPresent`) so older config files still load.

### Step 3 — Persistence (`ConfigStore.swift`)

- Path: `~/Library/Application Support/Resize/config.json`. Create the directory if it's missing.
- `load() -> AppConfig`: if the file is missing or corrupt, return the default (and log). Never crash.
- `save(_:)`: pretty-printed JSON with sorted keys, written atomically.
- Allow an injectable URL in the initializer for tests.

### Step 4 — Display detection (`DisplayMonitor.swift`)

- `public static func currentMode() -> DisplayMode`
  - Get the active displays with `CGGetActiveDisplayList`.
  - If any display has `CGDisplayIsBuiltin(id) == 0` → `.external`, otherwise `.laptop`.
  - Clamshell mode (only the external display active) → `.external`. This falls out of the rule above automatically.
  - Ignore mirrored secondaries: skip a display if `CGDisplayIsInMirrorSet` is true and it isn't the primary in the mirror set (`CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay`).
- `DisplayMonitor` class:
  - Observe `NSApplication.didChangeScreenParametersNotification`. It's simpler and Swift-friendly; no C callback needed.
  - Also observe `NSWorkspace.didWakeNotification`, because displays can change during sleep.
  - **Debounce:** on each event, cancel the pending `Task` and start a new one that sleeps `debounceSeconds`, then computes `currentMode()`. Fire `onModeChange(mode)` **only if the mode differs from the last one reported**, but always fire once at startup.
  - API: `init(debounce: Double, onModeChange: @escaping @MainActor (DisplayMode) -> Void)`, `start()`, `stop()`.

### Step 5 — App launch monitoring (`AppLaunchMonitor.swift`)

- Observe `NSWorkspace.shared.notificationCenter`:
  - `didLaunchApplicationNotification` → `onLaunch(bundleID)`.
  - `didTerminateApplicationNotification` → `onTerminate(bundleID)`.
- Get the bundle ID from `userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication`.

### Step 6 — Accessibility permission (`AccessibilityPermission.swift`)

- `static var isTrusted: Bool { AXIsProcessTrusted() }`
- `static func request()`: call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true`.
- `static func openSettings()`: open `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- macOS sends no notification when trust changes, so the UI polls `isTrusted` every 2s **only while** the permission banner is visible.
- **Dev gotcha (put this in the README too):** with ad-hoc signing, each rebuild can invalidate the
  Accessibility grant. If keystrokes stop working after a rebuild, remove Resize from
  System Settings → Privacy & Security → Accessibility and add it again. `bundle.sh` signs with a
  stable identifier to reduce this.

### Step 7 — Driver abstraction (`ZoomDriver.swift`, `DriverRegistry.swift`)

```swift
public enum DriverMethod: String, Sendable { case direct, configReload, keystroke }

public enum DriverStatus: Equatable, Sendable {
    case ready
    case needsSetup(String)      // human-readable instructions
    case unavailable(String)
}

public struct ZoomContext: Sendable {
    public let rule: AppRule
    public let percent: Int
    public let app: NSRunningApplication   // must be running
}

@MainActor
public protocol ZoomDriver {
    var method: DriverMethod { get }
    /// Whether this driver handles the bundle ID. The fallback driver returns true for everything.
    func supports(bundleID: String) -> Bool
    func status(for rule: AppRule) -> DriverStatus
    /// true if apply() must bring the app to the front (callers serialize these).
    var requiresFocus: Bool { get }
    func apply(_ ctx: ZoomContext) async throws
    /// Short label for the UI, e.g. "Approximate (keystrokes)".
    func describe(for rule: AppRule) -> String
}
```

`DriverRegistry`:
- Holds `[ZoomDriver]` in priority order, with **`KeystrokeDriver` always last**.
- `driver(for rule: AppRule) -> ZoomDriver`: the first driver that `supports` the bundle ID **and** whose
  status is `.ready`. If none is ready, return the first one that supports it (so the UI can show
  setup instructions). The keystroke driver guarantees a result.
- In Phase 1–2 the registry contains only `KeystrokeDriver`. The design must make adding
  `ChromiumExtensionDriver`, `TerminalAppleScriptDriver`, etc. a one-line registration.

### Step 8 — Keystroke profiles (`KeystrokeProfile.swift`, `KeystrokeProfiles.swift`)

```swift
public enum ZoomScale: Sendable, Equatable {
    /// Discrete zoom levels (percent). Each zoom-in press moves one step. 100 must be present.
    case steps([Int])
    /// Font-point based: each press = ±pointsPerStep; 100% = baseFontSize.
    case points(defaultBase: Double, pointsPerStep: Double)
}

public struct KeyCombo: Sendable, Equatable {
    public let keyCode: CGKeyCode
    public let flags: CGEventFlags
}

public struct KeystrokeProfile: Sendable {
    public let scale: ZoomScale
    public let reset: KeyCombo     // usually ⌘0
    public let zoomIn: KeyCombo    // usually ⌘=
    public let zoomOut: KeyCombo   // usually ⌘-
}
```

Key codes from Carbon `HIToolbox/Events.h`: `kVK_ANSI_0 = 0x1D`, `kVK_ANSI_Equal = 0x18`,
`kVK_ANSI_Minus = 0x1B`. Default flags: `.maskCommand`.

Known-app table (`KeystrokeProfiles.byBundleID: [String: KeystrokeProfile]`):

| App | Bundle ID | Scale |
|---|---|---|
| Chrome | `com.google.Chrome` | chromium steps |
| Edge | `com.microsoft.edgemac` | chromium steps |
| Brave | `com.brave.Browser` | chromium steps |
| Arc | `company.thebrowser.Browser` | chromium steps |
| Vivaldi | `com.vivaldi.Vivaldi` | chromium steps |
| Opera | `com.operasoftware.Opera` | chromium steps |
| Firefox | `org.mozilla.firefox` | firefox steps |
| Safari | `com.apple.Safari` | safari steps |
| VS Code | `com.microsoft.VSCode` | chromium steps (Electron) |
| Cursor | `com.todesktop.230313mzl4w4u92` | chromium steps (Electron) |
| Terminal | `com.apple.Terminal` | points(12, 1) |
| iTerm2 | `com.googlecode.iterm2` | points(12, 1) |
| Ghostty | `com.mitchellh.ghostty` | points(13, 1) |
| kitty | `net.kovidgoyal.kitty` | points(11, 1) — kitty's default step is 2pt on some versions; **verify** |
| Alacritty | `org.alacritty` | points(11.25, 1) — **verify** step size |
| WezTerm | `com.github.wez.wezterm` | points(12, 1) — WezTerm scales by ×1.1 per step, not +1pt; **verify** and model as steps if needed |
| Warp | `dev.warp.Warp-Stable` | points(13, 1) — **verify** |

Step tables:
- `chromiumSteps = [25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300, 400, 500]`
- `firefoxSteps = [30, 50, 67, 80, 90, 100, 110, 120, 133, 150, 170, 200, 240, 300, 400, 500]`
- `safariSteps  = [50, 75, 85, 100, 115, 125, 150, 175, 200, 250, 300]`

**Unknown apps** use `chromiumSteps` with the default keys (most apps that support ⌘= are
Electron or behave similarly).

Notes the implementer must respect:
- Terminal.app labels "Bigger" as ⌘+ (⇧⌘=). Plain ⌘= also works in current macOS. If testing shows it doesn't, set `zoomIn.flags = [.maskCommand, .maskShift]` for Terminal only.
- "Verify" rows: test manually and adjust the table. Leave a `// verified on <app version>` comment.

### Step 9 — Keystroke math (pure functions, fully unit-tested)

In `KeystrokeProfile` (or a `KeystrokeMath` enum):

```swift
/// Number of presses after reset. Positive = zoom in, negative = zoom out.
static func presses(for percent: Int, scale: ZoomScale, baseFontSize: Double?) -> Int
```

- `.steps(levels)`: find the index of 100 and the index of the level **nearest** to `percent`
  (on a tie, pick the larger). Return `targetIndex - index100`.
- `.points(defaultBase, perStep)`: `base = baseFontSize ?? defaultBase`;
  `targetPts = base * percent / 100`; return `Int(((targetPts - base) / perStep).rounded())`.
- Also `static func effectivePercent(...)`: the percent actually reached, shown in the UI as "≈ 125%".

Tests (`KeystrokeMathTests`):
- chromium 100→0, 110→+1, 125→+2, 150→+3, 90→−1, 67→−3, 120→+2 (nearest to 125; tie rule), 1000→clamped to last index.
- points base 12: 125% → 15pt → +3 presses; 100% → 0; 75% → −3.

### Step 10 — Sending keys (`KeySender.swift`)

```swift
@MainActor public protocol KeySending {
    func send(_ combo: KeyCombo, times: Int) async
}
```

Real implementation, `CGEventKeySender`:
- For each press: create `CGEvent(keyboardEventSource: src, virtualKey:, keyDown: true)`, set `.flags`,
  `post(tap: .cghidEventTap)`; then the matching keyUp. Use `CGEventSource(stateID: .hidSystemState)`.
- Wait **40 ms** between presses (`try? await Task.sleep(for: .milliseconds(40))`). Some apps drop key events sent faster than that.
- A mock `RecordingKeySender` lives in tests so the driver/coordinator can be tested without real events.

Why not `CGEvent.postToPid`? It's unreliable for menu key equivalents in many apps (Chromium
especially). We bring the app to the front instead (Step 11). Keep `postToPid` as a possible future option.

### Step 11 — `KeystrokeDriver.swift`

- `method = .keystroke`, `requiresFocus = true`, `supports` → always `true`.
- `status`: `.needsSetup("Grant Accessibility access…")` if not trusted; otherwise `.ready`.
- `describe`: a known profile → "Approximate (keystrokes)"; unknown → "Generic (keystrokes, assumes Chrome-like steps)".
- `apply(ctx)`:
  1. `profile = KeystrokeProfiles.byBundleID[ctx.rule.bundleID] ?? .generic`.
  2. `ctx.app.activate()`. Then poll `NSWorkspace.shared.frontmostApplication?.processIdentifier == ctx.app.processIdentifier`
     every 50 ms for up to 1.5 s. On timeout, throw `ZoomError.couldNotFocus`.
  3. Wait an extra 150 ms so the key window settles.
  4. Send `reset` once, wait 100 ms.
  5. `n = presses(...)`. Send `zoomIn` n times if n > 0, `zoomOut` |n| times if n < 0.
- Limitation to document in the code: zoom applies to the **focused window/tab**. For browsers, that's
  why the extension driver comes in Phase 4. Accept it for now.

### Step 12 — `ZoomCoordinator.swift` (the brain)

`@MainActor final class ZoomCoordinator`. It depends on: a config provider (closure returning `AppConfig`),
`DriverRegistry`, a `currentMode` provider, and a logger.

State:
- `lastApplied: [String: (mode: DisplayMode, percent: Int)]`, keyed by bundle ID.
- `isApplying: Bool` plus a queue, so runs never overlap. If a run is requested during a run, set
  `pendingRun = true` and run once more after the current one finishes.
- `lastResults: [String: ApplyResult]` for the UI (`success(percentReached)`, `failed(String)`, `skipped(reason)`).

Methods:
- `applyAll(mode:, force: Bool = false)`:
  1. Remember `previousFront = NSWorkspace.shared.frontmostApplication`.
  2. For each enabled rule whose app is running (`NSRunningApplication.runningApplications(withBundleIdentifier:)`, take the first):
     skip if `!force && lastApplied[id] == (mode, percent)`. Otherwise get the driver and `apply`, then record the result.
     Run drivers with `requiresFocus` sequentially. Others may run concurrently (that only matters in later phases).
  3. Re-activate `previousFront` if it still exists and isn't terminated.
- `applyOne(bundleID:, mode:)`: same flow for one app. Used on launch, after `launchApplyDelaySeconds`.
- `appTerminated(bundleID:)`: remove `lastApplied[bundleID]` so the next launch re-applies.
- `ruleChanged(bundleID:)`: remove `lastApplied` for it and apply immediately in the current mode.
- `defaultsChanged()`: re-apply to every rule that has no override for the current mode.
- Resolve percentages with `rule.percent(for: mode, defaults: config.defaultPercents)`.
- If `config.paused` is true, every method is a no-op. Un-pausing triggers `applyAll(force: true)`.

Wiring (in `AppState`):
- `DisplayMonitor.onModeChange` → `coordinator.applyAll(mode:)`.
- `AppLaunchMonitor.onLaunch` → if `config.applyOnLaunch` and a rule exists → wait for the delay → `applyOne`.
- `AppLaunchMonitor.onTerminate` → `appTerminated`.
- Don't apply while the screen is locked or the screensaver is running (keystrokes would go to the wrong place).
  Check `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`. If locked, defer: also observe
  `com.apple.screenIsUnlocked` on `DistributedNotificationCenter` and run any pending apply then.

Tests (`CoordinatorTests`) use a fake driver + fake mode + fake running-app lookup. To make that possible,
abstract `runningApp(for bundleID) -> NSRunningApplication?` behind a closure. Since `NSRunningApplication`
can't be built in tests, have `ZoomContext` carry `pid` and `bundleID` instead, and let the driver look up the
running app itself. Adjust the protocol in Step 7 accordingly. Cover:
- skip when unchanged; force re-applies; terminated app re-applies on next launch; disabled rules ignored;
  overlapping requests are coalesced.

### Step 13 — App target UI (`Sources/Resize`)

`ResizeApp.swift`:
```swift
@main struct ResizeApp: App {
    @State private var state = AppState()
    var body: some Scene {
        MenuBarExtra("Resize", systemImage: "plus.magnifyingglass") {
            MenuBarView().environment(state)
        }
        .menuBarExtraStyle(.window)
        Window("Resize Settings", id: "settings") {
            SettingsView().environment(state)
        }
        .windowResizability(.contentSize)
    }
}
```

`AppState` (`@Observable @MainActor`): owns `ConfigStore`, `config`, the monitors, the coordinator, `currentMode`,
`isTrusted`, and `lastResults`. Every mutation of `config` saves to disk and calls `coordinator.ruleChanged`
where relevant. Starts the monitors in `init`.

#### UX principles (apply to every screen)

- **It should feel like a built-in macOS utility.** Use native SwiftUI controls, SF Symbols, system colors and
  materials, and support light and dark mode. No custom chrome, no web-style UI.
- **Two concepts only:** *Default zoom* (per display mode) and *per-app override*. An app with no override
  shows "Default (125%)" in secondary text; changing it shows the value in normal text with a small "↺" button to reset it to the default.
- **Always show which mode is active.** The column or card for the current mode gets an accent highlight and a "Now" badge.
- **Changes apply immediately,** with no Save button. Changing the value for the *current* mode applies it to that app right away (debounced 0.5 s).
- **Nothing is hidden behind jargon.** Driver details ("Approximate (keystrokes)") appear only as a small ⓘ popover.

#### Onboarding (first launch, `OnboardingView`, shown in the settings window while `hasCompletedOnboarding == false`)

Three short pages, with Back/Continue:
1. **Welcome:** one sentence explaining the app, plus a laptop ↔ monitor illustration made from SF Symbols (`laptopcomputer`, `arrow.left.arrow.right`, `display`).
2. **Pick your apps:** a grid of **installed** known apps (scan `/Applications` and `~/Applications` for the bundle IDs in
   `KeystrokeProfiles`, using `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`), grouped "Browsers" / "Terminals" /
   "Editors", with a checkbox on each icon. All are pre-checked. A "+ Other app…" button opens the app picker.
3. **Set default zoom:** two big cards side by side, **"On laptop screen"** (default 100%) and **"On external monitor"** (default 125%).
   Each has a slider (snapping to the preset values) plus a value label. Below them: an Accessibility permission row with a
   "Grant Access" button and a live ✓ once granted. "Done" saves and opens the main settings view.

#### Menu bar popover (`MenuBarView`, `.menuBarExtraStyle(.window)`, about 320 pt wide)

```
┌───────────────────────────────────────┐
│ 🖥  External monitor           [ ● On ] │  ← mode + master toggle (config.paused)
├───────────────────────────────────────┤
│ ⚠︎ Accessibility needed  [Grant…]      │  ← only if not trusted
├───────────────────────────────────────┤
│ [icon] Chrome          −  125%  +   ✓  │  ← quick adjust for the CURRENT mode
│ [icon] Ghostty         −  110%  +   ✓  │
│ [icon] Terminal        −  125%  +   ⚠︎  │  ← ⚠︎ tooltip = last error
│ (apps that aren't running are dimmed)  │
├───────────────────────────────────────┤
│ Apply Now          Settings…    Quit   │
└───────────────────────────────────────┘
```

- The −/+ buttons move through the preset list for the current mode and write an override for that app.
- Clicking an app name opens Settings with that app selected.
- The menu bar icon is `plus.magnifyingglass`. While `paused`, it's `minus.magnifyingglass`, and the header shows "Paused".

#### Settings window (`SettingsView`, about 720×480, `NavigationSplitView`)

Sidebar: **General**, **Apps**, then a list of every added app (icon + name) for direct selection.

**Apps page** (the main page) is a `Table` with these columns:

| | App | On laptop | On external monitor | Status |
|---|---|---|---|---|
| ☑︎ | [icon] Chrome | Default (100%) ▾ | **150%** ▾ ↺ | ✓ Applied |
| ☑︎ | [icon] Ghostty | Default (100%) ▾ | Default (125%) ▾ | Not running |

- The first column is the enabled checkbox. The zoom cells are `Picker`s with the options "Default (N%)", a divider,
  presets 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, and "Custom…" (a popover with a stepper, 25–500).
- The column for the current mode gets a "Now" badge in its header.
- The toolbar has **+** (opens the app picker), **−** (removes the selection), and "Apply Now".
- Drag and drop: dropping a `.app` from Finder onto the table adds it.
- Empty state: `ContentUnavailableView("No apps yet", systemImage: "app.dashed", description: …)` with an "Add Apps…" button.

**App detail page** (selected from the sidebar):
- A header with the large icon, name and bundle ID (secondary text).
- Two cards, **On laptop screen** and **On external monitor**. Each has a "Use default" toggle and, when it's off,
  a slider with snapping plus a value field.
- For point-based apps: a "Base font size (= 100%)" field with the hint "Your normal font size in <App>".
- A "How it's applied" row: the driver description, "≈ N% reached" (from `effectivePercent`), and an ⓘ popover
  explaining limitations (e.g. "Changes zoom of the focused tab only").
- A "Test now" button: applies this app's value for the current mode immediately.
- A "Remove app" button at the bottom (destructive style, with a confirmation dialog).

**General page:**
- **Default zoom:** the same two cards as onboarding (laptop / external). Changing them re-applies to every app using the default.
- **Behavior:** Launch at login (`SMAppService.mainApp`), "Apply when an app launches", "Pause Resize".
- **Permissions:** an Accessibility row with a status dot and a "Grant…" / "Open Settings" button.
- **About:** version, plus "Show config file in Finder".

#### App picker (`AppPickerView`, a sheet, about 520×440)

- A search field at the top that filters everything below.
- **Suggested:** installed known apps not yet added, shown as an icon grid grouped Browsers / Terminals / Editors.
- **Running now:** `NSWorkspace.shared.runningApplications` with `.regular` activation policy, minus apps already added.
- **All applications:** the contents of `/Applications`, `/System/Applications`, `~/Applications` (scanned once in the background, sorted by name).
- Multi-select with checkmarks. The footer has "Choose Other…" (an `NSOpenPanel` for `.app`), Cancel, and **Add (N)**.
- New apps are added with **no overrides**, so they follow the defaults.

#### Files

Add to `Sources/Resize/`: `OnboardingView.swift`, `AppsTableView.swift`, `AppDetailView.swift`, `GeneralSettingsView.swift`,
`ZoomPicker.swift` (shared picker with Default/presets/Custom), `ZoomCard.swift` (shared laptop/external card),
`AppIconView.swift` (icon from bundle ID, cached), and `InstalledAppsScanner.swift`. The scanner can live in `ResizeKit` because it's pure Foundation.

`LaunchAtLogin.swift`: a small wrapper around `SMAppService.mainApp`. This only works when running from a real `.app` bundle.

Use `#Preview` blocks with a mock `AppState` for every view so the UI can be iterated on in Xcode previews (open `Package.swift` in Xcode).

### Step 14 — Bundling (`Resources/Info.plist`, `scripts/bundle.sh`, `scripts/run.sh`)

`Info.plist` keys: `CFBundleIdentifier = dev.xingyulong.Resize` (ask the user if they want a different one),
`CFBundleName = Resize`, `CFBundleExecutable = Resize`, `CFBundlePackageType = APPL`,
`CFBundleShortVersionString = 0.1.0`, `CFBundleVersion = 1`, `LSMinimumSystemVersion = 14.0`,
`LSUIElement = true`, `NSAppleEventsUsageDescription` (for later phases).

`bundle.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Resize"
APP="$ROOT/build/Resize.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Resize"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - --identifier dev.xingyulong.Resize "$APP"
echo "$APP"
```
`run.sh`: `pkill -x Resize || true; open "$(scripts/bundle.sh)"`.

### Step 15 — Docs and finishing

- `README.md`: what the app does, how to build/run (`scripts/run.sh`), the Accessibility note, the supported-apps table, and known limitations
  (keystroke mode affects only the focused tab/window; briefly switches focus).
- Make sure `swift build`, `swift test`, and `scripts/bundle.sh` all succeed.
- Commit on the `scaffold` branch. End the commit message with the co-author line the harness provides.

---

## 4. Manual test checklist (run after Step 14)

1. Launch `build/Resize.app`. The menu bar icon appears and there's no Dock icon.
2. Grant Accessibility. The banner disappears within about 2 s.
3. Add Chrome, Safari, Terminal and one more terminal. Set Laptop 100% and External 125%.
4. Plug in the external monitor. After about 1.5 s each app flashes to the front briefly, then focus returns to the original app. Zoom levels match.
5. Unplug. Everything goes back to 100%.
6. Quit Chrome and relaunch it while on the external display. It gets 125% about 2 s after launch.
7. "Apply Now" re-applies even when nothing changed.
8. Lock the screen, then plug or unplug. Nothing happens while locked; it applies after unlock.
9. Restart the app. The config persists.
10. Fill in the "verify" rows of the profile table with what you observed.

---

## 5. Known risks / gotchas

- **Focus stealing:** the keystroke driver visibly switches apps. Keep it fast and always restore the previously front app.
- **Typing in progress:** if the user is typing when the display changes, keystrokes could mix with theirs. The debounce helps. Optionally skip applying if `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown) < 1.0`, and retry after 2 s.
- **Fullscreen / other Spaces:** `activate()` may switch Spaces. That's acceptable for v1.
- **Apps with no windows:** the keys do nothing. That's harmless.
- **Browsers zoom per site:** ⌘0/⌘= changes only the current site's zoom. This is a known limitation until Phase 4.

---

## 6. Future phases (for context only — do NOT build now)

Each one is a new `ZoomDriver` registered **before** `KeystrokeDriver` in `DriverRegistry`:

- **Phase 3 — exact terminal drivers:** Terminal.app via AppleScript (`set font size of every tab of every window`);
  Alacritty via `alacritty msg config font.size=<pt>`; kitty via `kitty @ set-font-size <pt>` (needs `allow_remote_control` + `listen_on`;
  report `.needsSetup` with instructions otherwise).
- **Phase 4 — browser extension:** one WebExtension for Chromium browsers + Firefox. It uses `tabs.setZoomSettings({scope:"per-tab"})` +
  `tabs.setZoom` on every tab, and re-applies on `tabs.onCreated`/`tabs.onUpdated`. It talks to the app through a native messaging host binary
  (manifests installed into each browser's `NativeMessagingHosts` directory) + a Unix socket/XPC to the main app.
  Safari stays on keystrokes, because it has no `tabs.setZoom`.
- **Phase 5:** iTerm2 (Python API), Ghostty (config include + reload), WezTerm (Lua reads a JSON file on the reload watch list),
  VS Code/Cursor (`window.zoomLevel = log(p/100)/log(1.2)` in settings.json).
- Later: named per-monitor profiles, notarized DMG, Sparkle updates.
