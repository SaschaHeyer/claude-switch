import Foundation

/// Claude Code profiles, kept compatible with the claude-switch CLI:
/// ~/.claude-<name>/ with a .profile-name marker and the shared items
/// symlinked from ~/.claude.
enum ClaudeCode {
    static let marker = ".profile-name"
    static let sharedItems = ["skills", "CLAUDE.md", "settings.json", "plugins"]
    static var zshrc: String { Paths.home + "/.zshrc" }

    /// Profiles the CLI created, as (name, folder).
    static func discoverCLIProfiles() -> [(name: String, dir: String)] {
        let entries = (try? Paths.fm.contentsOfDirectory(atPath: Paths.home)) ?? []
        return entries
            .filter { $0.hasPrefix(".claude-") }
            .map { (String($0.dropFirst(".claude-".count)), Paths.home + "/" + $0) }
            .filter { Paths.exists($0.1 + "/" + marker) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    static func createProfile(name: String, addAlias: Bool) throws -> String {
        let dir = Paths.codeConfigDir(for: name)
        if Paths.exists(dir) && !Paths.exists(dir + "/" + marker) {
            throw ProfileError("\(Paths.tilde(dir)) already exists and isn't a profile. Pick another name.")
        }
        try Paths.fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try (name + "\n").write(toFile: dir + "/" + marker, atomically: true, encoding: .utf8)

        let home = ClaudeDesktop.defaultCodeDir
        for item in sharedItems where Paths.exists(home + "/" + item) {
            let link = dir + "/" + item
            if (try? Paths.fm.destinationOfSymbolicLink(atPath: link)) == nil, !Paths.exists(link) {
                try? Paths.fm.createSymbolicLink(atPath: link, withDestinationPath: home + "/" + item)
            }
        }
        if addAlias { addZshAlias(name: name, dir: dir) }
        return dir
    }

    /// The same alias block the CLI writes, so `claude-switch delete` removes it too.
    static func addZshAlias(name: String, dir: String) {
        let existing = (try? String(contentsOfFile: zshrc, encoding: .utf8)) ?? ""
        guard !existing.contains("alias claude-\(name)=") else { return }
        let block = "\n# Claude profile: \(name)\nalias claude-\(name)='CLAUDE_CONFIG_DIR=\"\(dir)\" claude'\n"
        if let handle = FileHandle(forWritingAtPath: zshrc) {
            handle.seekToEndOfFile()
            handle.write(Data(block.utf8))
            try? handle.close()
        } else {
            try? block.write(toFile: zshrc, atomically: true, encoding: .utf8)
        }
    }

    static func removeZshAlias(name: String) {
        guard let text = try? String(contentsOfFile: zshrc, encoding: .utf8) else { return }
        let kept = text.components(separatedBy: "\n").filter {
            $0 != "# Claude profile: \(name)" && !$0.hasPrefix("alias claude-\(name)=")
        }
        try? kept.joined(separator: "\n").write(toFile: zshrc, atomically: true, encoding: .utf8)
    }

    // MARK: - The claude binary

    /// GUI apps don't get the shell PATH, so look in the usual places first
    /// and ask a login shell last.
    static let binary: String? = {
        let candidates = [
            Paths.home + "/.local/bin/claude",
            Paths.home + "/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            Paths.home + "/.npm-global/bin/claude",
            Paths.home + "/.bun/bin/claude",
        ]
        if let found = candidates.first(where: { Paths.fm.isExecutableFile(atPath: $0) }) { return found }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let out = run(shell, ["-lic", "command -v claude"], env: nil, timeout: 5)?
            .split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces)
        return out.flatMap { Paths.fm.isExecutableFile(atPath: $0) ? $0 : nil }
    }()

    /// Login state of one config folder via `claude auth status`.
    static func authStatus(configDir: String) -> CodeAuth? {
        guard let binary else { return nil }
        var env = ProcessInfo.processInfo.environment
        if ClaudeDesktop.normalize(configDir) == ClaudeDesktop.defaultCodeDir {
            env.removeValue(forKey: "CLAUDE_CONFIG_DIR")
        } else {
            env["CLAUDE_CONFIG_DIR"] = configDir
        }
        guard let out = run(binary, ["auth", "status"], env: env, timeout: 10),
              let start = out.firstIndex(of: "{"),
              let json = try? JSONSerialization.jsonObject(with: Data(out[start...].utf8)) as? [String: Any]
        else { return CodeAuth(loggedIn: false) }
        return CodeAuth(
            loggedIn: json["loggedIn"] as? Bool ?? false,
            email: json["email"] as? String,
            plan: json["subscriptionType"] as? String,
            org: json["orgName"] as? String
        )
    }

    static func run(_ path: String, _ args: [String], env: [String: String]?, timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let env { process.environment = env }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline { usleep(50_000) }
        if process.isRunning { process.terminate(); return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

struct ProfileError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
