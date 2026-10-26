import AppKit
import Darwin

/// Starts and finds Claude Desktop instances. Each profile is one Claude
/// process pointed at its own data folder with `--user-data-dir`, the same
/// mechanism Multi-Claude uses, so their data folders work unchanged.
enum ClaudeDesktop {
    static let bundleID = "com.anthropic.claudefordesktop"
    static let dataDirFlag = "--user-data-dir="

    static var appURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var defaultDataDir: String { normalize(Paths.home + "/Library/Application Support/Claude") }

    /// The Claude Code folder Claude Code uses when CLAUDE_CONFIG_DIR is unset.
    static var defaultCodeDir: String { normalize(Paths.home + "/.claude") }

    static func normalize(_ path: String) -> String {
        let expanded = path.hasPrefix("~") ? Paths.home + path.dropFirst() : path
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    /// The Claude process using a data folder, if one is open. Claude holds a
    /// LevelDB lock inside its data folder while it runs; F_GETLK asks who
    /// holds it without taking the lock, and works inside the App Sandbox.
    static func runningInstance(dataDir: String) -> NSRunningApplication? {
        for lock in ["Local Storage/leveldb/LOCK", "Session Storage/LOCK"] {
            let fd = open(normalize(dataDir) + "/" + lock, O_RDONLY)
            guard fd >= 0 else { continue }
            defer { close(fd) }
            var query = flock()
            query.l_type = Int16(F_WRLCK)
            query.l_whence = Int16(SEEK_SET)
            guard fcntl(fd, F_GETLK, &query) == 0, query.l_type != Int16(F_UNLCK) else { continue }
            if let app = NSRunningApplication(processIdentifier: query.l_pid), app.bundleIdentifier == bundleID {
                return app
            }
        }
        return nil
    }

    enum LaunchError: LocalizedError {
        case claudeMissing
        var errorDescription: String? {
            "Claude Desktop isn't installed. Get it from claude.ai/download, then try again."
        }
    }

    /// Brings the profile's Claude to the front, or starts a new instance on
    /// its data folder. `codeConfigDir` becomes CLAUDE_CONFIG_DIR so the Code
    /// tab inside Desktop signs in with the matching Claude Code profile.
    static func launch(dataDir: String, codeConfigDir: String?) async throws {
        let dataDir = normalize(dataDir)
        if let running = runningInstance(dataDir: dataDir) {
            running.activate(options: [.activateAllWindows])
            return
        }
        guard let url = appURL else { throw LaunchError.claudeMissing }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // Without a new instance LaunchServices would focus whichever Claude
        // is already open, even when it belongs to another profile.
        config.createsNewApplicationInstance = true
        if dataDir != defaultDataDir {
            config.arguments = [dataDirFlag + dataDir]
        }
        // Setting CLAUDE_CONFIG_DIR to ~/.claude changes Claude Code's keychain
        // entry, so the default folder is left unset.
        if let codeConfigDir, normalize(codeConfigDir) != defaultCodeDir {
            config.environment = ["CLAUDE_CONFIG_DIR": normalize(codeConfigDir)]
        }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }
}
