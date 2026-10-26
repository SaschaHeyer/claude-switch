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

    // MARK: - Login

    /// Who a config folder is signed in as, read from the account Claude Code
    /// keeps in .claude.json. Reading a file works in the App Sandbox, running
    /// `claude auth status` doesn't. Tokens stay in the Keychain, untouched.
    static func authStatus(configDir: String) -> CodeAuth {
        let file = ClaudeDesktop.normalize(configDir) == ClaudeDesktop.defaultCodeDir
            ? Paths.home + "/.claude.json"
            : configDir + "/.claude.json"
        guard let data = Paths.fm.contents(atPath: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = json["oauthAccount"] as? [String: Any],
              let email = account["emailAddress"] as? String
        else { return CodeAuth(loggedIn: false) }
        let plan = (account["organizationType"] as? String).map { $0.replacingOccurrences(of: "claude_", with: "") }
        return CodeAuth(loggedIn: true, email: email, plan: plan, org: account["organizationName"] as? String)
    }
}

struct ProfileError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
