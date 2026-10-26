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
    /// The sandbox needs the user to grant the home folder before anything loads.
    private(set) var needsHomeAccess = false
    private(set) var isSearching = false
    /// Set once a search has run, so the sheet can say "nothing else found".
    private(set) var searched = false

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
        guard HomeAccess.restore() else { needsHomeAccess = true; return }
        start()
    }

    func grantHomeAccess() {
        guard HomeAccess.request() else {
            error = "Claude Switch needs your home folder “\((Paths.home as NSString).lastPathComponent)”. Try again and click Allow access without selecting a folder inside it."
            return
        }
        needsHomeAccess = false
        start()
    }

    private func start() {
        load()
        refreshRunning()
        refreshAuth()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshRunning() }
        }
        // First run: look for profiles nobody told us about too, then offer them all.
        if !UserDefaults.standard.bool(forKey: "importOffered") {
            UserDefaults.standard.set(true, forKey: "importOffered")
            search(openSheet: true)
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
        importCandidates = Importers.all().filter { !isKnown($0) }
        selection = selection ?? profiles.first?.id
        save()
    }

    private func isKnown(_ candidate: ImportCandidate) -> Bool {
        let dirs = Set(profiles.flatMap { [$0.desktopDataDir, $0.codeConfigDir] }.compactMap { $0 }.map(ClaudeDesktop.normalize))
        return [candidate.desktopDataDir, candidate.codeConfigDir].compactMap { $0 }.contains { dirs.contains(ClaudeDesktop.normalize($0)) }
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
        runningDesktop = Set([profiles[0], profiles[1], profiles[4]].compactMap(\.desktopDataDir).map(ClaudeDesktop.normalize))
        codeAuth = [
            profiles[0].id: CodeAuth(loggedIn: true, email: "alex@company.com", plan: "team"),
            profiles[1].id: CodeAuth(loggedIn: true, email: "alex@hey.com", plan: "max"),
            profiles[2].id: CodeAuth(loggedIn: true, email: "alex@acme.dev", plan: "pro"),
            profiles[3].id: CodeAuth(loggedIn: true, email: "alex.builds@gmail.com", plan: "pro"),
        ]
        selection = profiles[0].id
    }

    /// Searches the home folder for Claude Desktop and Claude Code folders that
    /// aren't profiles yet and adds them to the import list.
    func search(openSheet: Bool = false) {
        guard !isSearching else { return }
        isSearching = true
        let known = Set(profiles.flatMap { [$0.desktopDataDir, $0.codeConfigDir] }.compactMap { $0 }
            + importCandidates.flatMap { [$0.desktopDataDir, $0.codeConfigDir] }.compactMap { $0 }
            + [ClaudeDesktop.defaultDataDir, ClaudeDesktop.defaultCodeDir])
            .map(ClaudeDesktop.normalize)
        Task.detached(priority: .userInitiated) {
            let found = Importers.search(skipping: Set(known))
            await MainActor.run {
                self.importCandidates.append(contentsOf: found)
                self.isSearching = false
                self.searched = true
                if openSheet && !self.importCandidates.isEmpty { self.showImport = true }
            }
        }
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
        let now = Set(profiles.compactMap(\.desktopDataDir)
            .filter { ClaudeDesktop.runningInstance(dataDir: $0) != nil }
            .map(ClaudeDesktop.normalize))
        if now != runningDesktop { runningDesktop = now }
    }

    func refreshAuth() {
        guard !demo else { return }
        let targets = profiles.compactMap { p in p.codeConfigDir.map { (p.id, $0) } }
        Task.detached(priority: .utility) {
            var result: [UUID: CodeAuth] = [:]
            for (id, dir) in targets {
                result[id] = ClaudeCode.authStatus(configDir: dir)
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
        ClaudeDesktop.runningInstance(dataDir: dir)?.terminate()
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
        profiles.append(profile)
        selection = profile.id
        save()
        refreshAuth()
    }

    func importProfiles(_ candidates: [ImportCandidate]) {
        for candidate in candidates {
            let isDesktop = candidate.desktopDataDir != nil
            // A profile of the same name missing this half gets it: a CLI "work"
            // and a Desktop "work" become one profile.
            if let index = profiles.firstIndex(where: {
                $0.name.caseInsensitiveCompare(candidate.name) == .orderedSame && (isDesktop ? !$0.hasDesktop : !$0.hasCode)
            }) {
                if isDesktop {
                    profiles[index].desktopDataDir = candidate.desktopDataDir
                    profiles[index].color = candidate.color
                }
                if let code = candidate.codeConfigDir, !profiles[index].hasCode { profiles[index].codeConfigDir = code }
                continue
            }
            var name = candidate.name
            var suffix = 2
            while profiles.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                name = "\(candidate.name)-\(suffix)"; suffix += 1
            }
            profiles.append(Profile(name: name, color: candidate.origin == .found ? .next(after: profiles.map(\.color)) : candidate.color,
                                    desktopDataDir: candidate.desktopDataDir, codeConfigDir: candidate.codeConfigDir,
                                    origin: candidate.origin))
        }
        let imported = Set(candidates.map(\.id))
        importCandidates.removeAll { imported.contains($0.id) }
        save()
        refreshAuth()
        refreshRunning()
    }

    func update(_ profile: Profile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
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

    /// Removes the profile. With `trashData`, its folders go to the Trash
    /// (recoverable), never for the main profile or folders another tool owns.
    func delete(_ profile: Profile, trashData: Bool) {
        guard !profile.isDefault else { return }
        if isRunning(profile) { quitDesktop(profile) }
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
        importCandidates = Importers.all().filter { !isKnown($0) }
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
