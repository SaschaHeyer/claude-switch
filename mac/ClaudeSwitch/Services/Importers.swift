import Foundation

/// A profile another tool made, offered for import. Importing only records
/// where the data lives: folders are never moved or copied, so the other
/// tool keeps working and switching back stays possible.
struct ImportCandidate: Identifiable, Hashable {
    var id: String { desktopDataDir ?? codeConfigDir ?? name }
    var name: String
    var color: ProfileColor
    var desktopDataDir: String?
    var codeConfigDir: String?
    var origin: ProfileOrigin
    var hasData: Bool
    /// The account a found folder is signed in to, to tell profiles apart.
    var email: String? = nil

    var path: String { desktopDataDir ?? codeConfigDir ?? "" }
    var sourceLabel: String {
        switch origin {
        case .multiClaude: "Multi-Claude"
        case .multipleClaude: "Multiple Claude"
        case .cli: "Claude Code"
        default: desktopDataDir != nil ? "Claude Desktop" : "Claude Code"
        }
    }
}

enum Importers {
    static func all() -> [ImportCandidate] { multiClaude() + multipleClaude() }

    /// Multi-Claude (multiclaude.app): ~/Library/Application Support/multi-claude/profiles.json
    static func multiClaude() -> [ImportCandidate] {
        let file = Paths.home + "/Library/Application Support/multi-claude/profiles.json"
        guard let data = Paths.fm.contents(atPath: file),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profiles = root["profiles"] as? [[String: Any]]
        else { return [] }

        return profiles.compactMap { entry in
            guard let name = entry["name"] as? String, let dataDir = entry["dataDir"] as? String else { return nil }
            return ImportCandidate(
                name: name,
                color: ProfileColor(multiClaudeName: entry["color"] as? String),
                desktopDataDir: dataDir,
                codeConfigDir: multiClaudeCodeDir(appPath: entry["appPath"] as? String),
                origin: .multiClaude,
                hasData: Paths.exists(dataDir + "/config.json")
            )
        }
    }

    /// Profiles with "isolate Claude Code" keep their CLAUDE_CONFIG_DIR in the wrapper's Info.plist.
    private static func multiClaudeCodeDir(appPath: String?) -> String? {
        guard let appPath,
              let plist = NSDictionary(contentsOfFile: appPath + "/Contents/Info.plist"),
              let dir = plist["MCProfileClaudeConfigDir"] as? String, !dir.isEmpty
        else { return nil }
        return dir
    }

    /// Multiple Claude: ~/Library/Application Support/MultipleClaude/profiles/<name>/desktop-data
    static func multipleClaude() -> [ImportCandidate] {
        let root = Paths.home + "/Library/Application Support/MultipleClaude/profiles"
        let names = (try? Paths.fm.contentsOfDirectory(atPath: root)) ?? []
        return names.sorted().compactMap { name in
            let dataDir = root + "/" + name + "/desktop-data"
            guard Paths.exists(dataDir) else { return nil }
            return ImportCandidate(
                name: name.prefix(1).uppercased() + name.dropFirst(),
                color: .ocean,
                desktopDataDir: dataDir,
                codeConfigDir: nil,
                origin: .multipleClaude,
                hasData: Paths.exists(dataDir + "/config.json")
            )
        }
    }

    // MARK: - Search

    /// Looks through the home folder for Claude folders nobody told us about:
    /// Claude Desktop data folders started with --user-data-dir, and Claude
    /// Code folders used with CLAUDE_CONFIG_DIR. Folders are recognised by
    /// what's inside them, not by their name.
    static func search(skipping known: Set<String>) -> [ImportCandidate] {
        let home = URL(fileURLWithPath: Paths.home)
        let roots: [(URL, Int)] = [
            (home.appendingPathComponent("Library/Application Support"), 4),
            (home, 4),
        ]
        // Big trees that never hold a Claude profile, or belong to other apps.
        let skip: Set<String> = [
            "Library", "node_modules", ".git", ".Trash", ".cache", ".npm", ".pnpm-store", ".yarn",
            ".cargo", ".rustup", ".gradle", ".m2", ".pyenv", ".nvm", ".bun", ".docker", ".local",
            "Pictures", "Music", "Movies", "Photos Library.photoslibrary", "Containers",
            "Group Containers", "Caches", "Google", "Chrome", "Code", "Slack", "Arc",
        ]

        var seen = known
        var found: [ImportCandidate] = []

        for (root, maxDepth) in roots {
            guard let walker = Paths.fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                   options: [.skipsPackageDescendants]) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                // ~/Library is walked on its own, only Application Support.
                if skip.contains(url.lastPathComponent) { walker.skipDescendants(); continue }
                if walker.level >= maxDepth { walker.skipDescendants() }
                let path = ClaudeDesktop.normalize(url.path)
                guard !seen.contains(path) else { walker.skipDescendants(); continue }

                if isDesktopDataDir(path) {
                    seen.insert(path)
                    walker.skipDescendants()
                    found.append(ImportCandidate(name: suggestedName(for: url, prefix: "Claude-"), color: .ocean,
                                                 desktopDataDir: path, origin: .found,
                                                 hasData: desktopSignedIn(dataDir: path)))
                } else if isCodeConfigDir(path) {
                    seen.insert(path)
                    walker.skipDescendants()
                    let auth = ClaudeCode.authStatus(configDir: path)
                    found.append(ImportCandidate(name: suggestedName(for: url, prefix: ".claude-"), color: .leaf,
                                                 codeConfigDir: path, origin: .found,
                                                 hasData: auth.loggedIn, email: auth.email))
                }
            }
        }
        return found
    }

    /// Claude Desktop's data folder: Electron storage plus Claude's own files.
    static func isDesktopDataDir(_ path: String) -> Bool {
        Paths.exists(path + "/config.json")
            && Paths.exists(path + "/Local Storage")
            && (Paths.exists(path + "/claude_desktop_config.json") || Paths.exists(path + "/window-state.json"))
    }

    /// A Claude Code config folder: the account file or the session history.
    static func isCodeConfigDir(_ path: String) -> Bool {
        Paths.exists(path + "/.claude.json")
            || (Paths.exists(path + "/history.jsonl") && Paths.exists(path + "/projects"))
    }

    private static func suggestedName(for url: URL, prefix: String) -> String {
        var name = url.lastPathComponent
        if name.hasPrefix(prefix) { name = String(name.dropFirst(prefix.count)) }
        if ["desktop-data", "data", "claude", ".claude"].contains(name.lowercased()) {
            name = url.deletingLastPathComponent().lastPathComponent
        }
        let cleaned = name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let start = cleaned.drop { !$0.isLetter }
        return start.isEmpty ? "Profile" : String(start.prefix(1).uppercased() + start.dropFirst()).prefix(32).description
    }

    /// Signed in at some point. Claude Desktop writes the account id here;
    /// we never read tokens.
    static func desktopSignedIn(dataDir: String) -> Bool {
        guard let data = Paths.fm.contents(atPath: dataDir + "/config.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["lastKnownAccountUuid"] != nil
    }
}
