import AppKit
import ResizeKit
import SwiftUI
import UniformTypeIdentifiers

/// Sheet for choosing apps to manage: suggested known apps, running apps, and everything installed.
struct AppPickerView: View {
    let excluding: Set<String>
    let onAdd: ([InstalledApp]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selection: [String: InstalledApp] = [:]
    @State private var allApps: [InstalledApp] = []
    @State private var isScanning = true

    private let suggested = InstalledAppsScanner.installedKnownApps()

    private func matches(_ app: InstalledApp) -> Bool {
        !excluding.contains(app.bundleID)
            && (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search apps", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(12)

            List {
                let suggestedApps = suggested.filter(matches)
                if !suggestedApps.isEmpty {
                    Section("Suggested") {
                        ForEach(AppCategory.allCases, id: \.self) { category in
                            let apps = suggestedApps.filter { $0.category == category }
                            if !apps.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(category.rawValue).font(.caption).foregroundStyle(.secondary)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                                        ForEach(apps) { app in SuggestedTile(app: app, isSelected: isSelected(app)) { toggle(app) } }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                let running = InstalledAppsScanner.runningApps().filter(matches)
                if !running.isEmpty {
                    Section("Running now") {
                        ForEach(running) { app in AppRow(app: app, isSelected: isSelected(app)) { toggle(app) } }
                    }
                }

                Section("All applications") {
                    if isScanning {
                        HStack { ProgressView().controlSize(.small); Text("Looking for apps…").foregroundStyle(.secondary) }
                    }
                    ForEach(allApps.filter(matches)) { app in AppRow(app: app, isSelected: isSelected(app)) { toggle(app) } }
                }
            }
            .listStyle(.inset)

            Divider()
            HStack {
                Button("Choose Other…", action: chooseOther)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add (\(selection.count))") {
                    onAdd(selection.values.sorted { $0.name < $1.name })
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 520, height: 440)
        .task {
            let scanned = await Task.detached { InstalledAppsScanner.scanAll() }.value
            allApps = scanned
            isScanning = false
        }
    }

    private func isSelected(_ app: InstalledApp) -> Bool { selection[app.bundleID] != nil }

    private func toggle(_ app: InstalledApp) {
        if selection[app.bundleID] != nil {
            selection[app.bundleID] = nil
        } else {
            selection[app.bundleID] = app
        }
    }

    private func chooseOther() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let app = InstalledAppsScanner.app(at: url), !excluding.contains(app.bundleID) {
                selection[app.bundleID] = app
            }
        }
    }
}

private struct SuggestedTile: View {
    let app: InstalledApp
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                URLIconView(url: app.url, size: 36)
                Text(app.name).font(.caption).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.quaternary.opacity(0.4)),
                        in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint).padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                URLIconView(url: app.url)
                Text(app.name)
                Spacer()
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
