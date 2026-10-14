import ResizeKit
import SwiftUI

/// One card per display mode: a snapping slider over the presets with a big value label.
/// With `useDefault`, it also offers a "Use default" toggle (per-app overrides).
struct ZoomCard: View {
    let mode: DisplayMode
    let isNow: Bool
    @Binding var percent: Int
    var useDefault: Binding<Bool>?
    var defaultPercent: Int?

    private var title: String { mode == .laptop ? "On laptop screen" : "On external monitor" }
    private var symbol: String { mode == .laptop ? "laptopcomputer" : "display" }
    private var presets: [Int] { AppConfig.presetPercents }
    private var isDisabled: Bool { useDefault?.wrappedValue ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: symbol).font(.headline)
                if isNow {
                    Text("Now")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
                Spacer()
                if let useDefault {
                    Toggle("Use default", isOn: useDefault)
                        .toggleStyle(.checkbox)
                        .font(.callout)
                }
            }
            Text("\(isDisabled ? (defaultPercent ?? percent) : percent)%")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(isDisabled ? .secondary : .primary)
                .monospacedDigit()
            Slider(
                value: Binding(
                    get: { Double(nearestPresetIndex(for: percent)) },
                    set: { percent = presets[Int($0.rounded())] }),
                in: 0...Double(presets.count - 1), step: 1
            ) {
                Text(title)
            } minimumValueLabel: {
                Text("\(presets.first!)%").font(.caption2)
            } maximumValueLabel: {
                Text("\(presets.last!)%").font(.caption2)
            }
            .disabled(isDisabled)
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isNow ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
    }

    private func nearestPresetIndex(for value: Int) -> Int {
        presets.indices.min { abs(presets[$0] - value) < abs(presets[$1] - value) } ?? 0
    }
}
