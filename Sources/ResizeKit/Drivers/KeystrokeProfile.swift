import CoreGraphics

public enum ZoomScale: Sendable, Equatable {
    /// Discrete zoom levels (percent). Each zoom-in press moves one step. 100 must be present.
    case steps([Int])
    /// Font-point based: each press = ±pointsPerStep; 100% = baseFontSize.
    case points(defaultBase: Double, pointsPerStep: Double)
}

public struct KeyCombo: Sendable, Equatable {
    public let keyCode: CGKeyCode
    public let flags: CGEventFlags

    public init(keyCode: CGKeyCode, flags: CGEventFlags = .maskCommand) {
        self.keyCode = keyCode
        self.flags = flags
    }

    // Carbon HIToolbox/Events.h virtual key codes.
    public static let cmd0 = KeyCombo(keyCode: 0x1D)       // kVK_ANSI_0
    public static let cmdEqual = KeyCombo(keyCode: 0x18)   // kVK_ANSI_Equal
    public static let cmdMinus = KeyCombo(keyCode: 0x1B)   // kVK_ANSI_Minus
}

public struct KeystrokeProfile: Sendable, Equatable {
    public let scale: ZoomScale
    public let reset: KeyCombo     // usually ⌘0
    public let zoomIn: KeyCombo    // usually ⌘=
    public let zoomOut: KeyCombo   // usually ⌘-

    public init(
        scale: ZoomScale,
        reset: KeyCombo = .cmd0,
        zoomIn: KeyCombo = .cmdEqual,
        zoomOut: KeyCombo = .cmdMinus
    ) {
        self.scale = scale
        self.reset = reset
        self.zoomIn = zoomIn
        self.zoomOut = zoomOut
    }

    /// Unknown apps: assume Chrome-like steps and the standard keys.
    public static let generic = KeystrokeProfile(scale: .steps(KeystrokeProfiles.chromiumSteps))

    /// Number of presses after reset. Positive = zoom in, negative = zoom out.
    public static func presses(for percent: Int, scale: ZoomScale, baseFontSize: Double?) -> Int {
        switch scale {
        case .steps(let levels):
            guard let i100 = levels.firstIndex(of: 100) else { return 0 }
            return nearestIndex(to: percent, in: levels) - i100
        case .points(let defaultBase, let perStep):
            let base = baseFontSize ?? defaultBase
            guard base > 0, perStep > 0 else { return 0 }
            let target = base * Double(percent) / 100
            return Int(((target - base) / perStep).rounded())
        }
    }

    /// The percent actually reached by `presses(for:...)`, shown in the UI as "≈ 125%".
    public static func effectivePercent(for percent: Int, scale: ZoomScale, baseFontSize: Double?) -> Int {
        switch scale {
        case .steps(let levels):
            return levels[nearestIndex(to: percent, in: levels)]
        case .points(let defaultBase, let perStep):
            let base = baseFontSize ?? defaultBase
            guard base > 0 else { return percent }
            let n = presses(for: percent, scale: scale, baseFontSize: baseFontSize)
            return Int((max(base + Double(n) * perStep, 0) / base * 100).rounded())
        }
    }

    /// Index of the level nearest to `percent`; on a tie the larger level wins.
    private static func nearestIndex(to percent: Int, in levels: [Int]) -> Int {
        var best = 0
        for (i, level) in levels.enumerated() {
            let d = abs(level - percent), bestD = abs(levels[best] - percent)
            if d < bestD || (d == bestD && level > levels[best]) { best = i }
        }
        return best
    }
}
