import Foundation
@testable import ResizeKit

@MainActor
final class RecordingKeySender: KeySending {
    var sent: [(combo: KeyCombo, times: Int)] = []
    func send(_ combo: KeyCombo, times: Int) async { sent.append((combo, times)) }
}

@MainActor
final class FakeDriver: ZoomDriver {
    let method = DriverMethod.direct
    var requiresFocus = false
    var statusValue: DriverStatus = .ready
    var supported: ((String) -> Bool) = { _ in true }
    var error: Error?
    var onApply: ((ZoomContext) async -> Void)?
    private(set) var applied: [ZoomContext] = []

    func supports(bundleID: String) -> Bool { supported(bundleID) }
    func status(for rule: AppRule) -> DriverStatus { statusValue }
    func describe(for rule: AppRule) -> String { "fake" }
    func apply(_ ctx: ZoomContext) async throws {
        applied.append(ctx)
        await onApply?(ctx)
        if let error { throw error }
    }
}
