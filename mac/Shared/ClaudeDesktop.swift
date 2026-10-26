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

    static var defaultDataDir: String {
        normalize(NSHomeDirectory() + "/Library/Application Support/Claude")
    }

    /// The Claude Code folder Claude Code uses when CLAUDE_CONFIG_DIR is unset.
    static var defaultCodeDir: String { normalize(NSHomeDirectory() + "/.claude") }

    static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    /// Running Claude Desktop main processes, keyed by data folder.
    static func runningInstances() -> [String: NSRunningApplication] {
        var result: [String: NSRunningApplication] = [:]
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let args = processArguments(pid: app.processIdentifier) ?? []
            let dir = args.first { $0.hasPrefix(dataDirFlag) }.map { String($0.dropFirst(dataDirFlag.count)) }
            result[normalize(dir ?? defaultDataDir)] = app
        }
        return result
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
        if let running = runningInstances()[dataDir] {
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
            try? FileManager.default.createDirectory(atPath: dataDir, withIntermediateDirectories: true)
            config.arguments = [dataDirFlag + dataDir]
        }
        // Setting CLAUDE_CONFIG_DIR to ~/.claude changes Claude Code's keychain
        // entry, so the default folder is left unset.
        if let codeConfigDir, normalize(codeConfigDir) != defaultCodeDir {
            var env = ProcessInfo.processInfo.environment
            env["CLAUDE_CONFIG_DIR"] = normalize(codeConfigDir)
            config.environment = env
        }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// argv of another process of the same user, read with KERN_PROCARGS2.
    static func processArguments(pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }

        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }  // executable path
        while index < size, buffer[index] == 0 { index += 1 }  // padding

        var args: [String] = []
        while args.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }
}
