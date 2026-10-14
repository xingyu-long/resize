import AppKit

@MainActor
public final class AppLaunchMonitor {
    private let onLaunch: @MainActor (String) -> Void
    private let onTerminate: @MainActor (String) -> Void
    private var observers: [NSObjectProtocol] = []

    public init(
        onLaunch: @escaping @MainActor (String) -> Void,
        onTerminate: @escaping @MainActor (String) -> Void
    ) {
        self.onLaunch = onLaunch
        self.onTerminate = onTerminate
    }

    public func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                if let id = Self.bundleID(from: note) { self?.onLaunch(id) }
            }
        })
        observers.append(nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                if let id = Self.bundleID(from: note) { self?.onTerminate(id) }
            }
        })
    }

    public func stop() {
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
    }

    private static func bundleID(from note: Notification) -> String? {
        (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
    }
}
