import Foundation

enum Paths {
    /// The real home folder. Inside the App Sandbox NSHomeDirectory() is the
    /// app's container, so ask the user database instead.
    static let home: String = {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir { return String(cString: dir) }
        return NSHomeDirectory()
    }()
    static let fm = FileManager.default

    /// Our own files. In the sandbox this lands inside the app's container.
    static var appSupport: URL {
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Claude Switch")
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var profilesFile: URL { appSupport.appendingPathComponent("profiles.json") }

    /// Same naming as Multi-Claude, so the folders read the same in Finder.
    static func desktopDataDir(for name: String) -> String {
        home + "/Library/Application Support/Claude-\(name)"
    }

    /// Same naming as the claude-switch CLI: ~/.claude-<name>.
    static func codeConfigDir(for name: String) -> String { home + "/.claude-\(name)" }

    static func tilde(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func exists(_ path: String) -> Bool { fm.fileExists(atPath: path) }
}

enum ProfileName {
    /// The CLI's rule, so every profile name is also a valid folder and alias.
    static func problem(with name: String, taken: [String]) -> String? {
        if name.isEmpty { return "Give it a name." }
        if name.lowercased() == "default" { return "“default” is your main Claude." }
        if name.count > 32 { return "32 characters max." }
        if name.range(of: "^[A-Za-z][A-Za-z0-9_-]*$", options: .regularExpression) == nil {
            return "Letters, numbers, - and _. Start with a letter."
        }
        if taken.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            return "You already have a profile called \(name)."
        }
        return nil
    }
}
