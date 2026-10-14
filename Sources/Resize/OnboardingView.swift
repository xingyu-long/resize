import ResizeKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var state
    @State private var page = 0
    @State private var installed = InstalledAppsScanner.installedKnownApps()
    @State private var extra: [InstalledApp] = []
    @State private var selected: Set<String> = []
    @State private var showPicker = false
    @State private var didPreselect = false

    private let pageCount = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: pickApps
                default: defaults
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(28)

            Divider()
            HStack {
                if page > 0 { Button("Back") { page -= 1 } }
                Spacer()
                Text("\(page + 1) of \(pageCount)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if page < pageCount - 1 {
                    Button("Continue") { page += 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Done", action: finish).keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .onAppear {
            if !didPreselect {
                selected = Set(installed.map(\.bundleID))
                didPreselect = true
            }
            state.refreshTrust()
        }
        .sheet(isPresented: $showPicker) {
            AppPickerView(excluding: Set((installed + extra).map(\.bundleID))) { apps in
                extra += apps
                selected.formUnion(apps.map(\.bundleID))
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                Image(systemName: "laptopcomputer")
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.secondary)
                Image(systemName: "display")
            }
            .font(.system(size: 52))
            .foregroundStyle(.tint)
            Text("Welcome to Resize").font(.largeTitle.weight(.medium))
            Text("Resize sets the zoom of your browsers and terminals for you, so everything stays comfortable when you plug into a bigger screen and when you unplug again.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
        }
    }

    private var pickApps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick your apps").font(.title2.weight(.medium))
            Text("These are installed on your Mac. Uncheck any you don't want Resize to manage.")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AppCategory.allCases, id: \.self) { category in
                        let apps = (installed + extra).filter { ($0.category ?? .editor) == category && ($0.category != nil || category == .editor) }
                        if !apps.isEmpty { group(category.rawValue, apps) }
                    }
                    let others = extra.filter { $0.category == nil }
                    if !others.isEmpty { group("Other", others) }
                }
            }
            Button("Other app…") { showPicker = true }
        }
    }

    private func group(_ title: String, _ apps: [InstalledApp]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(apps) { app in
                    Toggle(isOn: Binding(
                        get: { selected.contains(app.bundleID) },
                        set: { on in
                            if on { selected.insert(app.bundleID) } else { selected.remove(app.bundleID) }
                        })
                    ) {
                        VStack(spacing: 4) {
                            URLIconView(url: app.url, size: 36)
                            Text(app.name).font(.caption).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var defaults: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set default zoom").font(.title2.weight(.medium))
            HStack(alignment: .top, spacing: 12) {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    ZoomCard(mode: mode, isNow: state.currentMode == mode, percent: state.defaultBinding(mode))
                }
            }
            Text("You can change these any time, and give single apps their own zoom in Settings.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Image(systemName: state.isTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(state.isTrusted ? .green : .orange)
                VStack(alignment: .leading) {
                    Text(state.isTrusted ? "Accessibility access granted" : "Resize needs Accessibility access")
                    if !state.isTrusted {
                        Text("It presses keyboard shortcuts like ⌘= in your apps.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if !state.isTrusted { Button("Grant Access") { state.requestAccessibility() } }
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func finish() {
        state.completeOnboarding(apps: (installed + extra).filter { selected.contains($0.bundleID) })
    }
}

#Preview {
    OnboardingView().environment(AppState.preview(onboarded: false)).frame(width: 720, height: 480)
}
