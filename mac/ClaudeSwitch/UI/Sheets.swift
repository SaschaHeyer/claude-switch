import SwiftUI

struct NewProfileSheet: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var spec = ProfileStore.NewProfile()
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    private var problem: String? {
        spec.name.isEmpty ? nil : ProfileName.problem(with: spec.name, taken: store.profiles.map(\.name))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 18) {
                ProfileBadge(letter: spec.name.isEmpty ? "?" : String(spec.name.prefix(1)).uppercased(), color: spec.color, size: 64)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: spec.color)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("New profile")
                    Text("One account,\nits own login.").font(.display(30)).tracking(-0.8).lineSpacing(-4)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Work, Personal, Client…", text: $spec.name)
                    .textFieldStyle(.plain)
                    .font(.display(28))
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Brand.white))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Brand.ink, lineWidth: Brand.border))
                    .focused($nameFocused)
                    .onSubmit(create)
                Text(problem ?? error ?? " ").font(.body(12)).foregroundStyle(Color(hex: 0xC2410C))
            }

            HStack(spacing: 10) {
                ForEach(ProfileColor.allCases) { color in
                    Circle().fill(color.color)
                        .frame(width: 28, height: 28)
                        .overlay(Circle().strokeBorder(Brand.ink, lineWidth: spec.color == color ? 3 : 1.5))
                        .scaleEffect(spec.color == color ? 1.15 : 1)
                        .onTapGesture { spec.color = color }
                }
            }

            VStack(spacing: 12) {
                Toggle(isOn: $spec.desktop) { option("Claude Desktop", "Its own window, chats and login.") }
                Toggle(isOn: $spec.code) { option("Claude Code", "Its own terminal login. Skills and settings stay shared.") }
                if spec.code {
                    Toggle(isOn: $spec.zshAlias) { option("Shell alias", "Adds claude-\(spec.name.isEmpty ? "name" : spec.name) to ~/.zshrc, like the CLI does.") }
                }
            }
            .toggleStyle(InkToggleStyle())
            .padding(18)
            .inkCard(radius: 18, shadow: 3)

            HStack {
                Button("Cancel") { dismiss() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create \(spec.name.isEmpty ? "profile" : spec.name)", action: create)
                    .buttonStyle(.ink)
                    .keyboardShortcut(.defaultAction)
                    .disabled(spec.name.isEmpty || problem != nil || !(spec.desktop || spec.code))
            }
        }
        .padding(28)
        .frame(width: 480)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .onAppear {
            spec.color = .next(after: store.profiles.map(\.color))
            nameFocused = true
        }
    }

    private func option(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.bodyBold(14))
            Text(detail).font(.body(12)).foregroundStyle(Brand.inkSoft)
        }
    }

    private func create() {
        do {
            try store.create(spec)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ImportSheet: View {
    @Environment(ProfileStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    private var candidates: [ImportCandidate] { store.importCandidates }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(candidates.isEmpty ? "Search" : "Welcome over")
                Text(candidates.isEmpty ? (store.isSearching ? "Looking for\nyour Claudes…" : "Nothing new\nfound.") : "We found your\nprofiles.")
                    .font(.display(40)).tracking(-1.2).lineSpacing(-6)
                Text(candidates.isEmpty && !store.isSearching
                     ? "Every Claude folder in your home folder is already a profile. Made one somewhere unusual? Search again any time."
                     : "Claude Switch opens them straight from their existing folders. Nothing is moved or copied, your chats and logins stay, and the old app keeps working if you ever want to go back.")
                    .font(.body(14)).foregroundStyle(Brand.inkSoft).fixedSize(horizontal: false, vertical: true)
            }

            if !candidates.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                            if index > 0 { Rectangle().fill(Brand.line).frame(height: 1) }
                            row(candidate)
                        }
                    }
                }
                .frame(maxHeight: 330)
                .fixedSize(horizontal: false, vertical: true)
                .inkCard(radius: 18, shadow: 3)
            }

            HStack(spacing: 10) {
                if store.isSearching {
                    ProgressView().controlSize(.small)
                    Text("Searching your home folder…").font(.body(13)).foregroundStyle(Brand.inkSoft)
                } else {
                    Button { store.search() } label: {
                        Label(store.searched ? "Search again" : "Search my Mac", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.pill(.ghost, size: 13))
                    .help("Finds Claude Desktop and Claude Code folders anywhere in your home folder")
                }
            }

            HStack {
                Button(candidates.isEmpty ? "Done" : "Not now") { dismiss() }.buttonStyle(.ghost).keyboardShortcut(.cancelAction)
                Spacer()
                if !candidates.isEmpty {
                    Button("Bring \(chosen.count) over") {
                        store.importProfiles(candidates.filter { chosen.contains($0.id) })
                        dismiss()
                    }
                    .buttonStyle(.ink)
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen.isEmpty)
                }
            }
        }
        .padding(30)
        .frame(width: 560)
        .background(Brand.paper)
        .foregroundStyle(Brand.ink)
        .onAppear { chosen = Set(candidates.map(\.id)) }
        // Results arriving from a search start out ticked.
        .onChange(of: candidates.map(\.id)) { old, new in chosen.formUnion(Set(new).subtracting(old)) }
    }

    private func row(_ candidate: ImportCandidate) -> some View {
        HStack(spacing: 14) {
            ProfileBadge(letter: String(candidate.name.prefix(1)).uppercased(), color: candidate.color, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(candidate.name).font(.bodyBold(15))
                    if let email = candidate.email {
                        Text(email).font(.body(12)).foregroundStyle(Brand.inkSoft).lineLimit(1)
                    }
                }
                Text(Paths.tilde(candidate.path)).font(.mono(10.5)).foregroundStyle(Brand.inkSoft)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Chip(text: candidate.sourceLabel, fill: candidate.origin == .found ? Brand.white : Brand.cream)
            CheckBox(on: chosen.contains(candidate.id))
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if chosen.contains(candidate.id) { chosen.remove(candidate.id) } else { chosen.insert(candidate.id) }
        }
    }
}

struct CheckBox: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(on ? Brand.ink : Brand.white)
            .frame(width: 22, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Brand.ink, lineWidth: Brand.border))
            .overlay {
                if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .black)).foregroundStyle(Brand.paper) }
            }
    }
}
