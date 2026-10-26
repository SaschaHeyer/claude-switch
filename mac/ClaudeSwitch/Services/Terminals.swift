import AppKit

/// Opens Claude Code for a profile in the user's terminal.
enum TerminalApp: String, CaseIterable, Identifiable {
    case terminal, iterm, ghostty, warp

    var id: String { rawValue }

    var name: String {
        switch self {
        case .terminal: "Terminal"
        case .iterm: "iTerm"
        case .ghostty: "Ghostty"
        case .warp: "Warp"
        }
    }

    var bundleID: String {
        switch self {
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        case .warp: "dev.warp.Warp-Stable"
        }
    }

    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var isInstalled: Bool { appURL != nil }

    static var installed: [TerminalApp] { allCases.filter(\.isInstalled) }
}

enum Terminals {
    /// The shell command for one profile, the same thing the CLI aliases run.
    static func command(configDir: String, folder: String?) -> String {
        var parts: [String] = []
        if let folder { parts.append("cd \(quote(folder))") }
        let claude = ClaudeCode.binary.map(quote) ?? "claude"
        if ClaudeDesktop.normalize(configDir) == ClaudeDesktop.defaultCodeDir {
            parts.append(claude)
        } else {
            parts.append("CLAUDE_CONFIG_DIR=\(quote(configDir)) \(claude)")
        }
        return parts.joined(separator: " && ")
    }

    static func open(configDir: String, folder: String?, in terminal: TerminalApp, profileName: String) throws {
        let cmd = command(configDir: configDir, folder: folder)
        switch terminal {
        case .iterm:
            let script = """
            tell application "iTerm"
                activate
                create window with default profile command \(appleScriptString("/bin/zsh -lic " + quote(cmd + "; exec $SHELL -l")))
            end tell
            """
            var error: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error { throw ProfileError(error[NSAppleScript.errorMessage] as? String ?? "iTerm didn't respond.") }
        case .ghostty:
            guard let url = terminal.appURL else { throw ProfileError("Ghostty isn't installed.") }
            let config = NSWorkspace.OpenConfiguration()
            config.createsNewApplicationInstance = true
            config.arguments = ["-e", "/bin/zsh", "-lic", cmd + "; exec $SHELL -l"]
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        case .terminal, .warp:
            // A .command file opens in a fresh window and needs no Automation permission.
            let file = try commandFile(cmd, name: profileName)
            guard let app = terminal.appURL else { throw ProfileError("\(terminal.name) isn't installed.") }
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private static func commandFile(_ cmd: String, name: String) throws -> URL {
        let dir = Paths.appSupport.appendingPathComponent("launch")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("claude-\(name).command")
        let body = """
        #!/bin/zsh -l
        clear
        printf '\\033]0;Claude · \(name)\\007'
        \(cmd)
        exec $SHELL -l

        """
        try body.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
