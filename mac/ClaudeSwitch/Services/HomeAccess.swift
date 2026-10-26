import AppKit

/// The App Sandbox only lets Claude Switch into folders the user picks. The
/// profiles live all over the home folder (~/Library/Application Support,
/// ~/.claude-*), so the user grants the home folder once and we keep a
/// security-scoped bookmark to it.
enum HomeAccess {
    private static let key = "homeFolderBookmark"
    private static var active: URL?

    static var isGranted: Bool { active != nil }

    /// Reopens access from the saved bookmark. Call once at launch.
    @discardableResult
    static func restore() -> Bool {
        guard active == nil else { return true }
        guard let data = UserDefaults.standard.data(forKey: key) else { return false }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return false }
        if stale { save(url) }
        active = url
        return true
    }

    /// Asks the user to pick their home folder. Returns false if they picked
    /// something else or cancelled.
    @MainActor
    static func request() -> Bool {
        let panel = NSOpenPanel()
        panel.message = "Choose your home folder so Claude Switch can find and open your Claude profiles."
        panel.prompt = "Allow access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = false
        panel.directoryURL = URL(fileURLWithPath: Paths.home)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        guard url.standardizedFileURL.path == Paths.home else { return false }
        guard url.startAccessingSecurityScopedResource() else { return false }
        save(url)
        active = url
        return true
    }

    private static func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
