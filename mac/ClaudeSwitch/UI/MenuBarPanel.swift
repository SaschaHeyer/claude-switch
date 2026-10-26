import SwiftUI

/// The menu bar panel: every profile one click away.
struct MenuBarPanel: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark(size: 20)
                Spacer()
                Text("\(store.runningDesktop.count) open").font(.mono(10.5)).foregroundStyle(Brand.inkSoft)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            Rectangle().fill(Brand.ink).frame(height: Brand.border)

            VStack(spacing: 2) {
                ForEach(store.profiles) { profile in
                    MenuBarRow(profile: profile)
                }
            }
            .padding(8)

            Rectangle().fill(Brand.ink).frame(height: Brand.border)

            HStack {
                Button("Open Claude Switch") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.pill(.ink, size: 12))
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.pill(.ghost, size: 12))
            }
            .padding(12)
        }
        .frame(width: 320)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .preferredColorScheme(.light)
    }
}

private struct MenuBarRow: View {
    @Environment(ProfileStore.self) private var store
    let profile: Profile
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            ProfileBadge(letter: profile.letter, color: profile.color, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name).font(.bodyBold(14))
                if let email = store.codeAuth[profile.id]?.email {
                    Text(email).font(.body(11)).foregroundStyle(Brand.inkSoft).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if store.isRunning(profile) { LiveDot(size: 8) }
            if profile.hasCode {
                iconButton("terminal", help: "Claude Code in \(store.terminal.name)") { store.launchCode(profile, folder: nil) }
            }
            if profile.hasDesktop {
                iconButton("macwindow", help: "Claude Desktop") { store.launchDesktop(profile) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 12).fill(hover ? Brand.cream : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            if profile.hasDesktop { store.launchDesktop(profile) } else { store.launchCode(profile, folder: nil) }
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .heavy))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Brand.white))
                .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
