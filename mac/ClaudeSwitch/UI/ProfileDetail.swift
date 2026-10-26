import SwiftUI

struct ProfileDetail: View {
    @Environment(ProfileStore.self) private var store
    let profile: Profile
    @State private var folder: String?
    @State private var confirmDelete = false
    @State private var copied = false

    private var running: Bool { store.isRunning(profile) }
    private var auth: CodeAuth? { store.codeAuth[profile.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                hero
                HStack(alignment: .top, spacing: 20) {
                    desktopCard
                    codeCard
                }
                footer
            }
            .padding(.horizontal, 32)
            .padding(.top, 44)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.never)
        .confirmationDialog("Delete \(profile.name)?", isPresented: $confirmDelete) {
            Button("Remove from Claude Switch") { store.delete(profile, trashData: false) }
            if profile.origin == .claudeSwitch || profile.origin == .cli {
                Button("Remove and move its data to the Trash", role: .destructive) { store.delete(profile, trashData: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(profile.origin == .multiClaude || profile.origin == .multipleClaude
                 ? "Its data folder stays where it is, so the tool you imported it from keeps working."
                 : "Removing keeps its folders, so you can import it again later.")
        }
    }

    // MARK: Hero

    private var hero: some View {
        HStack(alignment: .bottom, spacing: 24) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Eyebrow(profile.origin.label, color: profile.color.onColor.opacity(0.75))
                    if running {
                        HStack(spacing: 6) {
                            LiveDot(size: 8)
                            Text("Open now").font(.mono(10.5))
                        }
                        .foregroundStyle(Brand.ink)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Brand.white))
                        .overlay(Capsule().strokeBorder(Brand.ink, lineWidth: 1.5))
                    }
                }
                Text(profile.name)
                    .font(.display(76))
                    .tracking(-2.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .foregroundStyle(profile.color.onColor)
                Text(subtitle)
                    .font(.body(16))
                    .foregroundStyle(profile.color.onColor.opacity(0.85))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 10) {
                if profile.hasDesktop {
                    Button { store.launchDesktop(profile) } label: {
                        Label(running ? "Bring to front" : "Open Claude", systemImage: running ? "macwindow" : "arrow.up.right")
                    }
                    .buttonStyle(.pill(.ink, size: 16))
                    .keyboardShortcut(.return)
                }
                if profile.hasCode {
                    Button { store.launchCode(profile, folder: folder) } label: {
                        Label("Claude Code", systemImage: "terminal")
                    }
                    .buttonStyle(.pill(.color(Brand.white, Brand.ink), size: 14))
                }
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .bottomLeading)
        .background(alignment: .topTrailing) {
            Text(profile.letter)
                .font(.display(300))
                .foregroundStyle(profile.color.onColor.opacity(0.08))
                .offset(x: 10, y: -90)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .inkCard(fill: profile.color.color, radius: 28, shadow: 6)
    }

    private var subtitle: String {
        if let auth, auth.loggedIn {
            return [auth.email, auth.planLabel.map { "Claude \($0)" }].compactMap { $0 }.joined(separator: "  ·  ")
        }
        if store.desktopSignedIn(profile) { return "Signed in to Claude Desktop" }
        return "Not signed in yet. Open it and log in once."
    }

    // MARK: Cards

    private var desktopCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(icon: "macwindow", title: "Claude Desktop", status: profile.hasDesktop
                       ? (running ? ("Open", Brand.go) : (store.desktopSignedIn(profile) ? ("Signed in", Brand.inkSoft) : ("New", Brand.inkSoft)))
                       : nil)

            if let dir = profile.desktopDataDir {
                PathRow(label: "Data folder", path: dir)

                if let code = profile.codeConfigDir, ClaudeDesktop.normalize(code) != ClaudeDesktop.defaultCodeDir {
                    Toggle(isOn: Binding(
                        get: { profile.desktopUsesCodeProfile },
                        set: { var p = profile; p.desktopUsesCodeProfile = $0; store.update(p) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Same login for the Code tab").font(.bodyBold(13))
                            Text("Desktop's Claude Code uses this profile's Code folder.").font(.body(12)).foregroundStyle(Brand.inkSoft)
                        }
                    }
                    .toggleStyle(InkToggleStyle())
                }

                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button(running ? "Bring to front" : "Open") { store.launchDesktop(profile) }
                        .buttonStyle(.pill(.ink, size: 13))
                    if running {
                        Button("Quit") { store.quitDesktop(profile) }.buttonStyle(.pill(.ghost, size: 13))
                    }
                }
            } else {
                Text("This profile only runs in the terminal. Give it its own Claude Desktop too.")
                    .font(.body(13)).foregroundStyle(Brand.inkSoft)
                Spacer(minLength: 0)
                Button("Add Claude Desktop") { store.addDesktop(to: profile) }.buttonStyle(.pill(.ghost, size: 13))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .inkCard()
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cardHeader(icon: "terminal", title: "Claude Code", status: profile.hasCode
                       ? (auth?.loggedIn == true ? (auth?.planLabel ?? "Signed in", Brand.go) : (auth == nil ? ("…", Brand.inkSoft) : ("Not signed in", Brand.inkSoft)))
                       : nil)

            if let dir = profile.codeConfigDir {
                PathRow(label: "Config folder", path: dir)

                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Start in")
                    HStack(spacing: 8) {
                        Button { pickFolder() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "folder").font(.system(size: 11, weight: .bold))
                                Text(folder.map(Paths.tilde) ?? "Home folder").font(.mono(11.5)).lineLimit(1).truncationMode(.head)
                            }
                            .foregroundStyle(Brand.ink)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Brand.paper))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Brand.ink, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                        if folder != nil {
                            Button { folder = nil } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .heavy)) }
                                .buttonStyle(.plain).foregroundStyle(Brand.inkSoft)
                        }
                    }
                }

                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    Button("Open in \(store.terminal.name)") { store.launchCode(profile, folder: folder) }
                        .buttonStyle(.pill(.ink, size: 13))
                    Button(copied ? "Copied" : "Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Terminals.command(configDir: dir, folder: folder), forType: .string)
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    }
                    .buttonStyle(.pill(.ghost, size: 13))
                }
            } else {
                Text("Give this account its own Claude Code login too. It works with the claude-switch CLI.")
                    .font(.body(13)).foregroundStyle(Brand.inkSoft)
                Spacer(minLength: 0)
                Button("Add Claude Code") { store.addCode(to: profile) }.buttonStyle(.pill(.ghost, size: 13))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .inkCard()
    }

    private func cardHeader(icon: String, title: String, status: (String, Color)?) -> some View {
        HStack(alignment: .center) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Brand.cream))
                .overlay(Circle().strokeBorder(Brand.ink, lineWidth: 1.5))
            Text(title).font(.display(24)).tracking(-0.6)
            Spacer()
            if let status {
                Text(status.0).font(.mono(10.5)).foregroundStyle(status.1)
            }
        }
        .foregroundStyle(Brand.ink)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            Eyebrow("Color")
            HStack(spacing: 8) {
                ForEach(ProfileColor.allCases) { color in
                    Circle()
                        .fill(color.color)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Brand.ink, lineWidth: profile.color == color ? 3 : 1.5))
                        .scaleEffect(profile.color == color ? 1.12 : 1)
                        .onTapGesture { var p = profile; p.color = color; store.update(p) }
                }
            }
            Spacer()
            if !profile.isDefault {
                Button("Delete profile") { confirmDelete = true }
                    .buttonStyle(.pill(.ghost, size: 12))
            }
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Start here"
        if panel.runModal() == .OK { folder = panel.url?.path }
    }
}

struct PathRow: View {
    let label: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Eyebrow(label)
            HStack(spacing: 6) {
                Text(Paths.tilde(path))
                    .font(.mono(11.5))
                    .foregroundStyle(Brand.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                } label: {
                    Image(systemName: "arrow.up.forward.square").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.inkSoft)
                .help("Show in Finder")
            }
        }
    }
}

struct InkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
            Spacer(minLength: 0)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Brand.go : Brand.paper)
                    .frame(width: 40, height: 24)
                    .overlay(Capsule().strokeBorder(Brand.ink, lineWidth: Brand.border))
                Circle().fill(Brand.white)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(Brand.ink, lineWidth: Brand.border))
                    .padding(.horizontal, 4)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
        }
    }
}
