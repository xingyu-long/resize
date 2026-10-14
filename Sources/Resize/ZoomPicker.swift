import ResizeKit
import SwiftUI

/// Per-app zoom cell: "Default (N%)", the presets, or a custom value. A ↺ button resets an override.
struct ZoomPicker: View {
    /// nil = follow the default.
    @Binding var selection: Int?
    let defaultPercent: Int
    var isCurrentMode = false

    @State private var showCustom = false
    @State private var customValue = 100

    private var presets: [Int] {
        var list = AppConfig.presetPercents
        if let selection, !list.contains(selection) { list = (list + [selection]).sorted() }
        return list
    }

    @ViewBuilder
    private func checkLabel(_ title: String, checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    var body: some View {
        HStack(spacing: 4) {
            Menu {
                Button { selection = nil } label: {
                    checkLabel("Default (\(defaultPercent)%)", checked: selection == nil)
                }
                Divider()
                ForEach(presets, id: \.self) { value in
                    Button { selection = value } label: {
                        checkLabel("\(value)%", checked: selection == value)
                    }
                }
                Divider()
                Button("Custom…") {
                    customValue = selection ?? defaultPercent
                    showCustom = true
                }
            } label: {
                if let selection {
                    Text("\(selection)%").fontWeight(.medium)
                } else {
                    Text("Default (\(defaultPercent)%)").foregroundStyle(.secondary)
                }
            }
            .menuStyle(.button)
            .fixedSize()
            .popover(isPresented: $showCustom, arrowEdge: .bottom) {
                CustomZoomPopover(value: $customValue) {
                    selection = AppConfig.clamp(customValue)
                    showCustom = false
                }
            }

            if selection != nil {
                Button { selection = nil } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .help("Use the default")
                    .accessibilityLabel("Reset to default")
            }
        }
    }
}

private struct CustomZoomPopover: View {
    @Binding var value: Int
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom zoom").font(.headline)
            HStack {
                TextField("Percent", value: $value, format: .number)
                    .frame(width: 60)
                    .multilineTextAlignment(.trailing)
                    .onSubmit(onDone)
                Text("%")
                Stepper("", value: $value, in: AppConfig.allowedPercents, step: 5)
                    .labelsHidden()
            }
            Text("\(AppConfig.allowedPercents.lowerBound)–\(AppConfig.allowedPercents.upperBound)%")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Set", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 190)
    }
}
