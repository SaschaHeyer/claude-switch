import SwiftUI

struct ContentView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 272)
            Rectangle().fill(Brand.ink).frame(width: Brand.border)
            Group {
                if let profile = store.selected {
                    ProfileDetail(profile: profile).id(profile.id)
                } else {
                    EmptyDetail()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Brand.paper)
        .ignoresSafeArea()
        .frame(minWidth: 940, minHeight: 640)
        .preferredColorScheme(.light)
        .sheet(isPresented: $store.showNewProfile) { NewProfileSheet() }
        .sheet(isPresented: $store.showImport) { ImportSheet() }
        .alert("Something went wrong", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }
}

struct Wordmark: View {
    var size: CGFloat = 26

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("claude").font(.display(size))
            Text("switch").font(.displayLight(size))
        }
        .tracking(-0.6)
        .foregroundStyle(Brand.ink)
    }
}

struct Sidebar: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Wordmark()
                .padding(.top, 46)
                .padding(.horizontal, 20)

            HStack {
                Eyebrow("Profiles · \(store.profiles.count)")
                Spacer()
                Button { store.reload() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.inkSoft)
                .help("Look for new profiles and refresh logins")
            }
            .padding(.horizontal, 20)
            .padding(.top, 26)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.profiles) { profile in
                        SidebarRow(profile: profile, selected: store.selection == profile.id)
                            // Double click opens the profile, or brings its open Claude to the front.
                            .onTapGesture(count: 2) {
                                if profile.hasDesktop { store.launchDesktop(profile) } else { store.launchCode(profile, folder: nil) }
                            }
                            .simultaneousGesture(TapGesture().onEnded { store.selection = profile.id })
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                if !store.importCandidates.isEmpty {
                    Button { store.showImport = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.down.to.line.compact").font(.system(size: 13, weight: .heavy))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(store.importCandidates.count) profile\(store.importCandidates.count == 1 ? "" : "s") to bring over")
                                    .font(.bodyBold(13))
                                Text("From Multi-Claude, data stays put").font(.body(11)).foregroundStyle(Brand.inkSoft)
                            }
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Brand.ink)
                        .padding(12)
                        .inkCard(fill: Brand.cream, radius: 16, shadow: 3)
                    }
                    .buttonStyle(.plain)
                }

                Button { store.showNewProfile = true } label: {
                    Label("New profile", systemImage: "plus").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.pill(.ink, size: 14, fullWidth: true))
                .keyboardShortcut("n")
            }
            .padding(16)
        }
        .background(Brand.paper)
    }
}

struct SidebarRow: View {
    @Environment(ProfileStore.self) private var store
    let profile: Profile
    let selected: Bool
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            ProfileBadge(letter: profile.letter, color: profile.color, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name).font(.bodyBold(15)).foregroundStyle(Brand.ink).lineLimit(1)
                HStack(spacing: 4) {
                    if profile.hasDesktop { Chip(text: "Desktop", fill: selected ? Brand.cream : Brand.white) }
                    if profile.hasCode { Chip(text: "Code", fill: selected ? Brand.cream : Brand.white) }
                }
            }
            Spacer(minLength: 0)
            if store.isRunning(profile) { LiveDot() }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 16).fill(Brand.white)
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.ink, lineWidth: Brand.border))
                    .background(RoundedRectangle(cornerRadius: 16).fill(Brand.ink).offset(y: 3))
            } else if hover {
                RoundedRectangle(cornerRadius: 16).fill(Brand.cream.opacity(0.7))
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .contextMenu {
            if profile.hasDesktop { Button("Open Claude Desktop") { store.launchDesktop(profile) } }
            if profile.hasCode { Button("Open Claude Code") { store.launchCode(profile, folder: nil) } }
        }
    }
}

struct EmptyDetail: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        VStack(spacing: 20) {
            Text("Pick a profile,\nor make one.").font(.display(44)).multilineTextAlignment(.center)
            Button("New profile") { store.showNewProfile = true }.buttonStyle(.ink)
        }
        .foregroundStyle(Brand.ink)
    }
}
