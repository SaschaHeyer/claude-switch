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
        let homeName = (Paths.home as NSString).lastPathComponent
        let panel = NSOpenPanel()
        panel.message = "Your home folder “\(homeName)” is already open. Don't select anything, just click Allow access."
        panel.prompt = "Allow access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = false
        panel.directoryURL = URL(fileURLWithPath: Paths.home)
        panel.accessoryView = hint(homeName: homeName)
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        // The home folder or anything above it covers every profile.
        let picked = url.standardizedFileURL.path
        guard Paths.home == picked || Paths.home.hasPrefix(picked.hasSuffix("/") ? picked : picked + "/") else { return false }
        guard url.startAccessingSecurityScopedResource() else { return false }
        save(url)
        active = url
        return true
    }

    /// A banner inside the open panel, so nobody hunts for the right folder.
    @MainActor
    private static func hint(homeName: String) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "house.fill", accessibilityDescription: nil) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 18, weight: .bold)
        icon.contentTintColor = NSColor(hex: 0xFF6B2C)
        let title = NSTextField(labelWithString: "“\(homeName)” is already selected")
        title.font = .boldSystemFont(ofSize: 14)
        let detail = NSTextField(labelWithString: "Claude Switch needs your whole home folder to find every Claude profile. Click Allow access without picking a folder below.")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byWordWrapping
        detail.maximumNumberOfLines = 2
        detail.preferredMaxLayoutWidth = 560
        let text = NSStackView(views: [title, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        let row = NSStackView(views: [icon, text])
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
        row.frame = NSRect(x: 0, y: 0, width: 620, height: 64)
        return row
    }

    private static func save(_ url: URL) {
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
