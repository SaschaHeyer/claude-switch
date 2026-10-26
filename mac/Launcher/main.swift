import AppKit

// Runs inside ~/Applications/Claude Switch/<Profile>.app. Reads the profile
// from its own Info.plist, opens (or focuses) Claude Desktop and exits.

let info = Bundle.main.infoDictionary ?? [:]

func fail(_ message: String) -> Never {
    let alert = NSAlert()
    alert.messageText = "Couldn't open this profile"
    alert.informativeText = message
    alert.alertStyle = .warning
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let dataDir = info["CSDataDir"] as? String, !dataDir.isEmpty else {
    fail("This Dock app is missing its profile settings. Open Claude Switch and create the Dock app again.")
}
let codeConfigDir = info["CSCodeConfigDir"] as? String

Task { @MainActor in
    do {
        try await ClaudeDesktop.launch(dataDir: dataDir, codeConfigDir: codeConfigDir)
        exit(0)
    } catch {
        fail(error.localizedDescription)
    }
}

app.run()
