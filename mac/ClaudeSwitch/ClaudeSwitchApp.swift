import SwiftUI

@main
struct ClaudeSwitchApp: App {
    @State private var store: ProfileStore

    init() {
        Fonts.register()
        _store = State(initialValue: ProfileStore())
    }

    var body: some Scene {
        Window("Claude Switch", id: "main") {
            ContentView()
                .environment(store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Profile…") { store.showNewProfile = true }.keyboardShortcut("n")
            }
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(store)
        } label: {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

struct SettingsView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings").font(.display(30))
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Open Claude Code in")
                Picker("", selection: $store.terminal) {
                    ForEach(TerminalApp.allCases) { app in
                        Text(app.name + (app.isInstalled ? "" : "  (not installed)")).tag(app)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("Where things live")
                PathRow(label: "Profiles list", path: Paths.profilesFile.path)
                PathRow(label: "Dock apps", path: Paths.dockAppsDir.path)
            }
            if !store.importCandidates.isEmpty {
                Button("Import \(store.importCandidates.count) profile(s)…") { store.showImport = true }
                    .buttonStyle(.ghost)
            }
        }
        .padding(28)
        .frame(width: 440, alignment: .leading)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .preferredColorScheme(.light)
    }
}
