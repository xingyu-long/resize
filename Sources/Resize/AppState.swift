import AppKit
import Observation
import ResizeKit

enum SettingsRoute: Hashable {
    case general
    case apps
    case app(String)
}

@Observable @MainActor
final class AppState {
    private(set) var config: AppConfig
    private(set) var currentMode: DisplayMode
    private(set) var isTrusted: Bool
    private(set) var lastResults: [String: ApplyResult] = [:]
    var route: SettingsRoute = .apps

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let registry: DriverRegistry
    @ObservationIgnored private var coordinator: ZoomCoordinator!
    @ObservationIgnored private var displayMonitor: DisplayMonitor?
    @ObservationIgnored private var launchMonitor: AppLaunchMonitor?
    @ObservationIgnored private var trustTimer: Timer?
    @ObservationIgnored private var pendingApplies: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var defaultsApply: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// `startMonitoring: false` gives previews and tests an inert state.
    init(store: ConfigStore = ConfigStore(), startMonitoring: Bool = true) {
        self.store = store
        self.config = store.load()
        self.registry = DriverRegistry()
        self.currentMode = DisplayMonitor.currentMode()
        self.isTrusted = AccessibilityPermission.isTrusted

        coordinator = ZoomCoordinator(
            config: { [unowned self] in self.config },
            registry: registry,
            currentMode: { [unowned self] in self.currentMode })
        coordinator.onResultsChanged = { [weak self] in
            guard let self else { return }
            self.lastResults = self.coordinator.lastResults
        }
        guard startMonitoring else { return }
        startMonitors()
        refreshTrust()
    }

    // MARK: - Monitors

    private func startMonitors() {
        let display = DisplayMonitor(debounce: config.displayChangeDebounceSeconds) { [weak self] mode in
            guard let self else { return }
            self.currentMode = mode
            Task { await self.coordinator.applyAll(mode: mode) }
        }
        display.start()
        displayMonitor = display

        let launch = AppLaunchMonitor(
            onLaunch: { [weak self] id in
                guard let self else { return }
                Task { await self.coordinator.appLaunched(bundleID: id) }
            },
            onTerminate: { [weak self] id in self?.coordinator.appTerminated(bundleID: id) })
        launch.start()
        launchMonitor = launch

        observers.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.coordinator.screenUnlocked() }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshTrust() }
        })
    }

    // MARK: - Accessibility

    /// macOS sends no notification when trust changes, so poll while it's missing.
    func refreshTrust() {
        isTrusted = AccessibilityPermission.isTrusted
        if isTrusted {
            trustTimer?.invalidate()
            trustTimer = nil
        } else if trustTimer == nil {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshTrust() }
            }
        }
    }

    func requestAccessibility() {
        AccessibilityPermission.request()
        AccessibilityPermission.openSettings()
        refreshTrust()
    }

    // MARK: - Reading

    var rules: [AppRule] { config.rules }

    func rule(_ bundleID: String) -> AppRule? { config.rule(for: bundleID) }

    func percent(for rule: AppRule, mode: DisplayMode) -> Int { config.percent(for: rule, mode: mode) }

    func defaultPercent(for mode: DisplayMode) -> Int { config.defaultPercents[mode] ?? 100 }

    func isRunning(_ bundleID: String) -> Bool { ZoomCoordinator.systemRunningPID(bundleID) != nil }

    func driverDescription(for rule: AppRule) -> String { registry.driver(for: rule).describe(for: rule) }

    func driverLimitations(for rule: AppRule) -> String? { registry.driver(for: rule).limitations(for: rule) }

    func effectivePercent(for rule: AppRule, mode: DisplayMode) -> Int {
        registry.driver(for: rule).effectivePercent(for: rule, requested: percent(for: rule, mode: mode))
    }

    func baseFontDefault(for rule: AppRule) -> Double? {
        if case .points(let base, _) = KeystrokeProfiles.profile(for: rule.bundleID).scale { return base }
        return nil
    }

    var configFileURL: URL { store.url }

    // MARK: - Editing

    private func update(_ body: (inout AppConfig) -> Void) {
        body(&config)
        store.save(config)
    }

    private func updateRule(_ bundleID: String, _ body: (inout AppRule) -> Void) {
        update { cfg in
            guard let i = cfg.rules.firstIndex(where: { $0.bundleID == bundleID }) else { return }
            body(&cfg.rules[i])
        }
    }

    /// Apply a rule change right away, debounced so dragging a slider doesn't spam keystrokes.
    private func scheduleApply(_ bundleID: String) {
        pendingApplies[bundleID]?.cancel()
        pendingApplies[bundleID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            self.pendingApplies[bundleID] = nil
            await self.coordinator.ruleChanged(bundleID: bundleID)
        }
    }

    func setOverride(_ percent: Int?, for mode: DisplayMode, bundleID: String) {
        updateRule(bundleID) { $0.setOverride(percent.map(AppConfig.clamp), for: mode) }
        if mode == currentMode { scheduleApply(bundleID) }
    }

    func setEnabled(_ enabled: Bool, bundleID: String) {
        updateRule(bundleID) { $0.enabled = enabled }
        if enabled { scheduleApply(bundleID) }
    }

    func setBaseFontSize(_ size: Double?, bundleID: String) {
        updateRule(bundleID) { $0.baseFontSize = size }
        scheduleApply(bundleID)
    }

    func setBaseFont(_ size: Double?, bundleID: String) {
        setBaseFontSize(size.flatMap { $0 > 0 ? $0 : nil }, bundleID: bundleID)
    }

    func setDefault(_ percent: Int, for mode: DisplayMode) {
        update { $0.defaultPercents[mode] = AppConfig.clamp(percent) }
        guard mode == currentMode else { return }
        defaultsApply?.cancel()
        defaultsApply = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            await self.coordinator.defaultsChanged()
        }
    }

    /// The menu bar −/+: step the current mode's value through the presets and store it as an override.
    func step(bundleID: String, by direction: Int) {
        guard let rule = rule(bundleID) else { return }
        let current = percent(for: rule, mode: currentMode)
        let presets = AppConfig.presetPercents
        let next = direction > 0
            ? presets.first { $0 > current } ?? presets.last!
            : presets.last { $0 < current } ?? presets.first!
        setOverride(next, for: currentMode, bundleID: bundleID)
    }

    func addApps(_ apps: [InstalledApp]) {
        let existing = Set(config.rules.map(\.bundleID))
        let new = apps.filter { !existing.contains($0.bundleID) }
        guard !new.isEmpty else { return }
        update { cfg in
            cfg.rules += new.map { AppRule(bundleID: $0.bundleID, displayName: $0.name) }
        }
        new.forEach { scheduleApply($0.bundleID) }
    }

    func removeApps(_ bundleIDs: Set<String>) {
        update { $0.rules.removeAll { bundleIDs.contains($0.bundleID) } }
        bundleIDs.forEach {
            pendingApplies[$0]?.cancel()
            coordinator.forget(bundleID: $0)
        }
        if case .app(let id) = route, bundleIDs.contains(id) { route = .apps }
    }

    func setPaused(_ paused: Bool) {
        update { $0.paused = paused }
        if !paused { Task { await coordinator.applyAll(mode: currentMode, force: true) } }
    }

    func setApplyOnLaunch(_ value: Bool) { update { $0.applyOnLaunch = value } }

    func completeOnboarding(apps: [InstalledApp]) {
        addApps(apps)
        update { $0.hasCompletedOnboarding = true }
        route = .apps
    }

    // MARK: - Actions

    func openSettings(route: SettingsRoute? = nil) {
        if let route { self.route = route }
        SettingsWindowController.shared.show(state: self)
    }

    func applyNow() {
        Task { await coordinator.applyAll(mode: currentMode, force: true) }
    }

    func testNow(bundleID: String) {
        Task { await coordinator.applyOne(bundleID: bundleID, mode: currentMode, force: true) }
    }
}

extension AppState {
    /// Inert state with sample data for SwiftUI previews.
    static func preview(onboarded: Bool = true, mode: DisplayMode = .external) -> AppState {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("resize-preview-\(UUID().uuidString).json")
        let state = AppState(store: ConfigStore(url: url), startMonitoring: false)
        state.config = AppConfig(
            rules: [
                AppRule(bundleID: "com.google.Chrome", displayName: "Chrome", externalPercent: 150),
                AppRule(bundleID: "com.apple.Safari", displayName: "Safari"),
                AppRule(bundleID: "com.mitchellh.ghostty", displayName: "Ghostty"),
                AppRule(bundleID: "com.apple.Terminal", displayName: "Terminal", laptopPercent: 90, externalPercent: 110),
            ],
            hasCompletedOnboarding: onboarded)
        state.currentMode = mode
        return state
    }
}
