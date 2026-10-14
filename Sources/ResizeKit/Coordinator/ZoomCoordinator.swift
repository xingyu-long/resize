import AppKit
import CoreGraphics
import os

public enum ApplyResult: Equatable, Sendable {
    case success(percentReached: Int)
    case failed(String)
    case skipped(String)
}

/// Decides what to zoom, when, and runs drivers one at a time.
///
/// Requests are merged into a pending set and drained by a single loop, so runs never overlap and
/// requests that arrive mid-run are coalesced into one more pass.
@MainActor
public final class ZoomCoordinator {
    struct Applied: Equatable {
        var mode: DisplayMode
        var percent: Int
    }

    private struct Pending {
        var mode: DisplayMode
        var force: Bool
        /// nil = every enabled rule.
        var bundleIDs: Set<String>?
    }

    private static let log = Logger(subsystem: "dev.xingyulong.Resize", category: "ZoomCoordinator")

    private let config: () -> AppConfig
    private let registry: DriverRegistry
    private let currentMode: () -> DisplayMode
    private let runningPID: (String) -> pid_t?
    private let frontmostPID: () -> pid_t?
    private let activate: (pid_t) -> Void
    private let isScreenLocked: () -> Bool

    private var lastApplied: [String: Applied] = [:]
    private var pending: Pending?
    private var isApplying = false

    /// Latest outcome per bundle ID, for the UI.
    public private(set) var lastResults: [String: ApplyResult] = [:] {
        didSet { onResultsChanged?() }
    }
    public var onResultsChanged: (() -> Void)?

    public init(
        config: @escaping () -> AppConfig,
        registry: DriverRegistry,
        currentMode: @escaping () -> DisplayMode = { DisplayMonitor.currentMode() },
        runningPID: @escaping (String) -> pid_t? = ZoomCoordinator.systemRunningPID,
        frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier },
        activate: @escaping (pid_t) -> Void = { NSRunningApplication(processIdentifier: $0)?.activate() },
        isScreenLocked: @escaping () -> Bool = ZoomCoordinator.systemScreenLocked
    ) {
        self.config = config
        self.registry = registry
        self.currentMode = currentMode
        self.runningPID = runningPID
        self.frontmostPID = frontmostPID
        self.activate = activate
        self.isScreenLocked = isScreenLocked
    }

    // MARK: - Requests

    public func applyAll(mode: DisplayMode, force: Bool = false) async {
        await request(mode: mode, force: force, bundleIDs: nil)
    }

    public func applyOne(bundleID: String, mode: DisplayMode, force: Bool = false) async {
        await request(mode: mode, force: force, bundleIDs: [bundleID])
    }

    /// An app launched: give its windows a moment to appear, then apply.
    public func appLaunched(bundleID: String) async {
        let cfg = config()
        guard cfg.applyOnLaunch, cfg.rule(for: bundleID) != nil else { return }
        try? await Task.sleep(for: .seconds(cfg.launchApplyDelaySeconds))
        await applyOne(bundleID: bundleID, mode: currentMode())
    }

    /// Forget the app so its next launch is applied again.
    public func appTerminated(bundleID: String) {
        lastApplied.removeValue(forKey: bundleID)
        lastResults.removeValue(forKey: bundleID)
    }

    /// A rule's settings changed: apply immediately in the current mode.
    public func ruleChanged(bundleID: String) async {
        lastApplied.removeValue(forKey: bundleID)
        await applyOne(bundleID: bundleID, mode: currentMode(), force: true)
    }

    /// Global defaults changed. Apps whose resolved percent didn't change are skipped by the diff check.
    public func defaultsChanged() async {
        await applyAll(mode: currentMode())
    }

    /// Run whatever was deferred while the screen was locked.
    public func screenUnlocked() async {
        await drain()
    }

    public func forget(bundleID: String) {
        lastApplied.removeValue(forKey: bundleID)
        lastResults.removeValue(forKey: bundleID)
    }

    // MARK: - Queue

    private func request(mode: DisplayMode, force: Bool, bundleIDs: Set<String>?) async {
        guard !config().paused else { return }
        if var p = pending {
            p.mode = mode
            p.force = p.force || force
            switch (p.bundleIDs, bundleIDs) {
            case (let a?, let b?): p.bundleIDs = a.union(b)
            default: p.bundleIDs = nil
            }
            pending = p
        } else {
            pending = Pending(mode: mode, force: force, bundleIDs: bundleIDs)
        }
        await drain()
    }

    private func drain() async {
        guard !isApplying else { return }
        // Keystrokes would go to the lock screen; wait for `screenUnlocked()`.
        guard !isScreenLocked() else {
            Self.log.info("Screen locked; deferring apply")
            return
        }
        isApplying = true
        defer { isApplying = false }
        while let job = pending {
            pending = nil
            guard !config().paused else { continue }
            await run(job)
        }
    }

    // MARK: - Work

    private func run(_ job: Pending) async {
        let cfg = config()
        let previousFront = frontmostPID()
        var changedFocus = false

        for rule in cfg.rules where rule.enabled {
            if let ids = job.bundleIDs, !ids.contains(rule.bundleID) { continue }
            guard let pid = runningPID(rule.bundleID) else {
                lastResults[rule.bundleID] = .skipped("Not running")
                continue
            }
            let percent = cfg.percent(for: rule, mode: job.mode)
            let applied = Applied(mode: job.mode, percent: percent)
            if !job.force && lastApplied[rule.bundleID] == applied { continue }

            let driver = registry.driver(for: rule)
            switch driver.status(for: rule) {
            case .ready: break
            case .needsSetup(let message), .unavailable(let message):
                lastResults[rule.bundleID] = .failed(message)
                continue
            }

            do {
                if driver.requiresFocus { changedFocus = true }
                try await driver.apply(ZoomContext(rule: rule, percent: percent, pid: pid))
                lastApplied[rule.bundleID] = applied
                lastResults[rule.bundleID] = .success(
                    percentReached: driver.effectivePercent(for: rule, requested: percent))
            } catch {
                Self.log.error("Zoom failed for \(rule.bundleID): \(error.localizedDescription)")
                lastResults[rule.bundleID] = .failed(error.localizedDescription)
            }
        }

        if changedFocus, let previous = previousFront, frontmostPID() != previous, runningPID(forPID: previous) {
            activate(previous)
        }
    }

    private func runningPID(forPID pid: pid_t) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return !app.isTerminated
    }

    // MARK: - System defaults

    public nonisolated static func systemRunningPID(_ bundleID: String) -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }?.processIdentifier
    }

    public nonisolated static func systemScreenLocked() -> Bool {
        let dict = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (dict?["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
