import Foundation

/// A profile another tool made, offered for import. Importing only records
/// where the data lives: folders are never moved or copied, so the other
/// tool keeps working and switching back stays possible.
struct ImportCandidate: Identifiable, Hashable {
    var id: String { desktopDataDir }
    var name: String
    var color: ProfileColor
    var desktopDataDir: String
    var codeConfigDir: String?
    var origin: ProfileOrigin
    var hasData: Bool
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

    /// Signed in at some point. Claude Desktop writes the account id here;
    /// we never read tokens.
    static func desktopSignedIn(dataDir: String) -> Bool {
        guard let data = Paths.fm.contents(atPath: dataDir + "/config.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return json["lastKnownAccountUuid"] != nil
    }
}
