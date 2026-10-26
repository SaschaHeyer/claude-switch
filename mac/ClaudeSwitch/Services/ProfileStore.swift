import AppKit
import Observation

@MainActor @Observable
final class ProfileStore {
    private(set) var profiles: [Profile] = []
    /// Normalized data folders of the Claude Desktop instances that are open.
    private(set) var runningDesktop: Set<String> = []
    private(set) var codeAuth: [UUID: CodeAuth] = [:]
    private(set) var importCandidates: [ImportCandidate] = []
    var selection: UUID?
    var error: String?
    var showImport = false
    var showNewProfile = false

    var terminal: TerminalApp {
        didSet { UserDefaults.standard.set(terminal.rawValue, forKey: "terminal") }
    }

    private var timer: Timer?
    /// `-demo` shows sample profiles for website screenshots and saves nothing.
    private let demo = ProcessInfo.processInfo.arguments.contains("-demo")

    init() {
        let saved = UserDefaults.standard.string(forKey: "terminal").flatMap(TerminalApp.init(rawValue:))
        terminal = saved ?? TerminalApp.installed.first ?? .terminal
        if demo { loadDemo(); return }
        load()
        refreshRunning()
        refreshAuth()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRunning() }
        }
        if !importCandidates.isEmpty && !UserDefaults.standard.bool(forKey: "importOffered") {
            showImport = true
            UserDefaults.standard.set(true, forKey: "importOffered")
        }
    }

    var selected: Profile? { profiles.first { $0.id == selection } }

    func isRunning(_ profile: Profile) -> Bool {
        guard let dir = profile.desktopDataDir else { return false }
        return runningDesktop.contains(ClaudeDesktop.normalize(dir))
    }

    // MARK: - Loading

    private func load() {
        if let data = try? Data(contentsOf: Paths.profilesFile),
           let saved = try? JSONDecoder.iso.decode([Profile].self, from: data) {
            profiles = saved
        } else {
            profiles = [defaultProfile()]
        }
        adoptCLIProfiles()
        importCandidates = Importers.all().filter { candidate in
            !profiles.contains { $0.desktopDataDir.map(ClaudeDesktop.normalize) == ClaudeDesktop.normalize(candidate.desktopDataDir) }
        }
        selection = selection ?? profiles.first?.id
        save()
    }

    private func defaultProfile() -> Profile {
        Profile(
            name: "Main",
            color: .tangerine,
            desktopDataDir: ClaudeDesktop.appURL != nil || Paths.exists(ClaudeDesktop.defaultDataDir) ? ClaudeDesktop.defaultDataDir : nil,
            codeConfigDir: ClaudeDesktop.defaultCodeDir,
            origin: .system
        )
    }

    /// Profiles made with the CLI are ours already: add them without asking.
    /// A CLI profile whose name matches a Desktop-only profile joins it.
    private func adoptCLIProfiles() {
        for cli in ClaudeCode.discoverCLIProfiles() {
            let dir = ClaudeDesktop.normalize(cli.dir)
            if profiles.contains(where: { $0.codeConfigDir.map(ClaudeDesktop.normalize) == dir }) { continue }
            if let index = profiles.firstIndex(where: { $0.codeConfigDir == nil && $0.name.caseInsensitiveCompare(cli.name) == .orderedSame }) {
                profiles[index].codeConfigDir = dir
            } else {
                profiles.append(Profile(name: cli.name, color: .next(after: profiles.map(\.color)), codeConfigDir: dir, origin: .cli))
            }
        }
    }

    private func loadDemo() {
        let lib = Paths.home + "/Library/Application Support/Claude-"
        profiles = [
            Profile(name: "Work", color: .coral, desktopDataDir: lib + "Work", codeConfigDir: Paths.home + "/.claude-work", origin: .claudeSwitch),
            Profile(name: "Personal", color: .violet, desktopDataDir: lib + "Personal", codeConfigDir: ClaudeDesktop.defaultCodeDir, origin: .system),
            Profile(name: "Acme", color: .ocean, desktopDataDir: lib + "Acme", codeConfigDir: Paths.home + "/.claude-acme", origin: .multiClaude),
            Profile(name: "Side-project", color: .leaf, codeConfigDir: Paths.home + "/.claude-side-project", origin: .cli),
            Profile(name: "Team", color: .sun, desktopDataDir: lib + "Team", origin: .claudeSwitch),
        ]
        profiles[0].dockAppPath = Paths.dockAppsDir.path + "/Work.app"
        runningDesktop = Set([profiles[0], profiles[1], profiles[4]].compactMap(\.desktopDataDir).map(ClaudeDesktop.normalize))
        codeAuth = [
            profiles[0].id: CodeAuth(loggedIn: true, email: "alex@company.com", plan: "team"),
            profiles[1].id: CodeAuth(loggedIn: true, email: "alex@hey.com", plan: "max"),
            profiles[2].id: CodeAuth(loggedIn: true, email: "alex@acme.dev", plan: "pro"),
            profiles[3].id: CodeAuth(loggedIn: true, email: "alex.builds@gmail.com", plan: "pro"),
        ]
        selection = profiles[0].id
    }

    func save() {
        guard !demo else { return }
        guard let data = try? JSONEncoder.iso.encode(profiles) else { return }
        try? data.write(to: Paths.profilesFile, options: .atomic)
    }

    func reload() {
        load()
        refreshRunning()
        refreshAuth()
    }

    // MARK: - Status

    func refreshRunning() {
        guard !demo else { return }
        let now = Set(ClaudeDesktop.runningInstances().keys)
        if now != runningDesktop { runningDesktop = now }
    }

    func refreshAuth() {
        guard !demo else { return }
        let targets = profiles.compactMap { p in p.codeConfigDir.map { (p.id, $0) } }
        Task.detached(priority: .utility) {
            var result: [UUID: CodeAuth] = [:]
            for (id, dir) in targets {
                if let auth = ClaudeCode.authStatus(configDir: dir) { result[id] = auth }
            }
            let found = result
            await MainActor.run { self.codeAuth = found }
        }
    }

    func desktopSignedIn(_ profile: Profile) -> Bool {
        profile.desktopDataDir.map(Importers.desktopSignedIn) ?? false
    }

    // MARK: - Launching

    func launchDesktop(_ profile: Profile) {
        guard let dir = profile.desktopDataDir else { return }
        touch(profile)
        Task {
            do {
                try await ClaudeDesktop.launch(dataDir: dir, codeConfigDir: profile.desktopCodeDir)
                try? await Task.sleep(for: .seconds(1))
                refreshRunning()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func quitDesktop(_ profile: Profile) {
        guard let dir = profile.desktopDataDir else { return }
        ClaudeDesktop.runningInstances()[ClaudeDesktop.normalize(dir)]?.terminate()
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refreshRunning()
        }
    }

    func launchCode(_ profile: Profile, folder: String?) {
        guard let dir = profile.codeConfigDir else { return }
        touch(profile)
        do {
            try Terminals.open(configDir: dir, folder: folder, in: terminal, profileName: profile.name)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func touch(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].lastLaunched = Date()
        save()
    }

    // MARK: - Editing

    struct NewProfile {
        var name = ""
        var color: ProfileColor = .coral
        var desktop = true
        var code = true
        var dockApp = true
        var zshAlias = true
    }

    func create(_ spec: NewProfile) throws {
        if let problem = ProfileName.problem(with: spec.name, taken: profiles.map(\.name)) { throw ProfileError(problem) }
        guard spec.desktop || spec.code else { throw ProfileError("Pick Claude Desktop, Claude Code or both.") }

        var profile = Profile(name: spec.name, color: spec.color, origin: .claudeSwitch)
        if spec.desktop {
            let dir = Paths.desktopDataDir(for: spec.name)
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            profile.desktopDataDir = dir
        }
        if spec.code {
            profile.codeConfigDir = try ClaudeCode.createProfile(name: spec.name, addAlias: spec.zshAlias)
        }
        if spec.desktop && spec.dockApp {
            profile.dockAppPath = try? DockApps.create(for: profile)
        }
        profiles.append(profile)
        selection = profile.id
        save()
        refreshAuth()
    }

    func importProfiles(_ candidates: [ImportCandidate], makeDockApps: Bool) {
        var failures: [String] = []
        func dockApp(for profile: Profile) -> String? {
            do { return try DockApps.create(for: profile) } catch {
                failures.append("\(profile.name): \(error.localizedDescription)")
                return nil
            }
        }
        for candidate in candidates {
            var name = candidate.name
            var suffix = 2
            while profiles.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0.hasDesktop }) {
                name = "\(candidate.name)-\(suffix)"; suffix += 1
            }
            // A Code profile of the same name (from the CLI) becomes the other half.
            if let index = profiles.firstIndex(where: { !$0.hasDesktop && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                profiles[index].desktopDataDir = candidate.desktopDataDir
                profiles[index].color = candidate.color
                if makeDockApps { profiles[index].dockAppPath = dockApp(for: profiles[index]) }
                continue
            }
            var profile = Profile(name: name, color: candidate.color, desktopDataDir: candidate.desktopDataDir,
                                  codeConfigDir: candidate.codeConfigDir, origin: candidate.origin)
            if makeDockApps { profile.dockAppPath = dockApp(for: profile) }
            profiles.append(profile)
        }
        let imported = Set(candidates.map(\.id))
        importCandidates.removeAll { imported.contains($0.id) }
        save()
        refreshAuth()
        if !failures.isEmpty { error = "Imported, but some Dock apps failed.\n" + failures.joined(separator: "\n") }
    }

    func update(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let old = profiles[index]
        profiles[index] = profile
        // The Dock app bakes in color, letter and folders.
        if old.dockAppPath != nil,
           old.color != profile.color || old.desktopCodeDir != profile.desktopCodeDir || old.name != profile.name {
            if let path = old.dockAppPath { DockApps.remove(at: path) }
            profiles[index].dockAppPath = try? DockApps.create(for: profiles[index])
        }
        save()
    }

    func addCode(to profile: Profile) {
        var updated = profile
        do {
            updated.codeConfigDir = try ClaudeCode.createProfile(name: profile.name, addAlias: true)
            update(updated)
            refreshAuth()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func addDesktop(to profile: Profile) {
        var updated = profile
        let dir = Paths.desktopDataDir(for: profile.name)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        updated.desktopDataDir = dir
        update(updated)
    }

    func makeDockApp(_ profile: Profile) {
        do {
            var updated = profile
            updated.dockAppPath = try DockApps.create(for: profile)
            update(updated)
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: updated.dockAppPath!)])
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Removes the profile. With `trashData`, its folders go to the Trash
    /// (recoverable), never for the main profile or folders another tool owns.
    func delete(_ profile: Profile, trashData: Bool) {
        guard !profile.isDefault else { return }
        if isRunning(profile) { quitDesktop(profile) }
        if let path = profile.dockAppPath { DockApps.remove(at: path) }
        if trashData {
            if let dir = profile.desktopDataDir, profile.origin == .claudeSwitch || profile.origin == .cli {
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)
            }
            if let dir = profile.codeConfigDir, ClaudeDesktop.normalize(dir) != ClaudeDesktop.defaultCodeDir {
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: dir), resultingItemURL: nil)
                ClaudeCode.removeZshAlias(name: profile.name)
            }
        }
        profiles.removeAll { $0.id == profile.id }
        if selection == profile.id { selection = profiles.first?.id }
        importCandidates = Importers.all().filter { c in
            !profiles.contains { $0.desktopDataDir.map(ClaudeDesktop.normalize) == ClaudeDesktop.normalize(c.desktopDataDir) }
        }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        profiles.move(fromOffsets: source, toOffset: destination)
        save()
    }
}

extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
