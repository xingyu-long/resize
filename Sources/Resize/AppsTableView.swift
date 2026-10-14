import ResizeKit
import SwiftUI
import UniformTypeIdentifiers

struct AppsTableView: View {
    @Environment(AppState.self) private var state
    @State private var selection: Set<String> = []
    @State private var showPicker = false

    var body: some View {
        Group {
            if state.rules.isEmpty {
                ContentUnavailableView {
                    Label("No apps yet", systemImage: "app.dashed")
                } description: {
                    Text("Add the browsers and terminals you want Resize to zoom for you.")
                } actions: {
                    Button("Add Apps…") { showPicker = true }.buttonStyle(.borderedProminent)
                }
            } else {
                table
            }
        }
        .navigationTitle("Apps")
        .toolbar {
            ToolbarItemGroup {
                Button { showPicker = true } label: { Label("Add app", systemImage: "plus") }
                    .help("Add apps")
                Button { state.removeApps(selection); selection = [] } label: { Label("Remove app", systemImage: "minus") }
                    .help("Remove the selected apps")
                    .disabled(selection.isEmpty)
                Button("Apply Now") { state.applyNow() }
            }
        }
        .sheet(isPresented: $showPicker) {
            AppPickerView(excluding: Set(state.rules.map(\.bundleID))) { state.addApps($0) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let apps = urls.compactMap(InstalledAppsScanner.app(at:))
            state.addApps(apps)
            return !apps.isEmpty
        }
    }

    private func columnTitle(_ title: String, mode: DisplayMode) -> Text {
        state.currentMode == mode ? Text(title) + Text("  Now").foregroundStyle(.tint) : Text(title)
    }

    private var table: some View {
        Table(state.rules, selection: $selection) {
            TableColumn("") { rule in
                Toggle("Enabled", isOn: state.enabledBinding(rule.bundleID))
                    .labelsHidden().toggleStyle(.checkbox)
            }
            .width(28)
            TableColumn("App") { rule in
                HStack(spacing: 8) {
                    AppIconView(bundleID: rule.bundleID)
                    Text(rule.displayName).lineLimit(1)
                }
                .opacity(rule.enabled ? 1 : 0.5)
            }
            TableColumn(columnTitle("On laptop", mode: .laptop)) { rule in
                ZoomPicker(
                    selection: state.overrideBinding(rule.bundleID, .laptop),
                    defaultPercent: state.defaultPercent(for: .laptop))
            }
            TableColumn(columnTitle("On external monitor", mode: .external)) { rule in
                ZoomPicker(
                    selection: state.overrideBinding(rule.bundleID, .external),
                    defaultPercent: state.defaultPercent(for: .external))
            }
            TableColumn("Status") { rule in
                let status = state.statusText(for: rule)
                Label(status.text, systemImage: status.symbol)
                    .foregroundStyle(status.color)
                    .lineLimit(1)
                    .help(status.text)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, ids.count == 1 {
                Button("Show Details") { state.route = .app(id) }
                Button("Test Now") { state.testNow(bundleID: id) }
                Divider()
            }
            Button("Remove", role: .destructive) { state.removeApps(ids) }
        } primaryAction: { ids in
            if let id = ids.first { state.route = .app(id) }
        }
    }
}

#Preview {
    AppsTableView().environment(AppState.preview()).frame(width: 640, height: 400)
}
