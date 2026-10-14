import AppKit
import CoreGraphics

/// Snapshot of one display, so the mode decision is a pure, testable function.
public struct DisplayInfo: Equatable, Sendable {
    public var isBuiltin: Bool
    public var isActive: Bool
    public var isInMirrorSet: Bool

    public init(isBuiltin: Bool, isActive: Bool, isInMirrorSet: Bool) {
        self.isBuiltin = isBuiltin
        self.isActive = isActive
        self.isInMirrorSet = isInMirrorSet
    }
}

@MainActor
public final class DisplayMonitor {
    private let debounce: Double
    private let onModeChange: @MainActor (DisplayMode) -> Void
    private var lastReported: DisplayMode?
    private var pending: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    public init(debounce: Double, onModeChange: @escaping @MainActor (DisplayMode) -> Void) {
        self.debounce = debounce
        self.onModeChange = onModeChange
    }

    /// Any non-built-in display counts as external. This covers clamshell mode (only the external
    /// display is active) and mirrored external displays (which drop out of the active list).
    public nonisolated static func mode(for displays: [DisplayInfo]) -> DisplayMode {
        displays.contains { !$0.isBuiltin && ($0.isActive || $0.isInMirrorSet) } ? .external : .laptop
    }

    public nonisolated static func currentMode() -> DisplayMode {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return .laptop }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return .laptop }
        let infos = ids.prefix(Int(count)).map { id in
            DisplayInfo(
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                isActive: CGDisplayIsActive(id) != 0,
                isInMirrorSet: CGDisplayIsInMirrorSet(id) != 0)
        }
        return mode(for: infos)
    }

    public func start() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule() }
        })
        schedule() // always report once at startup
    }

    public func stop() {
        pending?.cancel()
        pending = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        workspaceObservers.removeAll()
    }

    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self, debounce] in
            // Startup fires immediately; later events wait out the debounce window.
            if self?.lastReported != nil {
                try? await Task.sleep(for: .seconds(debounce))
            }
            guard !Task.isCancelled, let self else { return }
            let mode = Self.currentMode()
            guard mode != self.lastReported else { return }
            self.lastReported = mode
            self.onModeChange(mode)
        }
    }
}
