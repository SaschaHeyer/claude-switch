import AppKit

/// Builds ~/Applications/Claude Switch/<Name>.app: the bundled ProfileLauncher,
/// an Info.plist naming the profile's folders, and a generated icon. It shows
/// up in Spotlight and Launchpad and can be pinned to the Dock.
enum DockApps {
    static func create(for profile: Profile) throws -> String {
        guard let dataDir = profile.desktopDataDir else {
            throw ProfileError("Only profiles with Claude Desktop get a Dock app.")
        }
        guard let launcher = Bundle.main.url(forResource: "ProfileLauncher", withExtension: nil) else {
            throw ProfileError("The profile launcher is missing from Claude Switch. Reinstall the app.")
        }

        let fm = FileManager.default
        try fm.createDirectory(at: Paths.dockAppsDir, withIntermediateDirectories: true)
        let app = Paths.dockAppsDir.appendingPathComponent("\(profile.name).app")
        if fm.fileExists(atPath: app.path) { try fm.removeItem(at: app) }

        let contents = app.appendingPathComponent("Contents")
        let macOS = contents.appendingPathComponent("MacOS")
        let resources = contents.appendingPathComponent("Resources")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try fm.copyItem(at: launcher, to: macOS.appendingPathComponent("launcher"))

        let slug = profile.name.lowercased().replacingOccurrences(of: "_", with: "-")
        var plist: [String: Any] = [
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "launcher",
            "CFBundleIdentifier": "dev.claudeswitch.profile.\(slug)",
            "CFBundleName": profile.name,
            "CFBundleDisplayName": profile.name,
            "CFBundleIconFile": "icon",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
            "CSProfileID": profile.id.uuidString,
            "CSDataDir": dataDir,
        ]
        if let code = profile.desktopCodeDir { plist["CSCodeConfigDir"] = code }
        let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        try ProfileIcon.writeICNS(letter: profile.letter, color: profile.color, to: resources.appendingPathComponent("icon.icns"))

        // The copied launcher's signature no longer matches the new bundle.
        _ = ClaudeCode.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path], env: nil, timeout: 20)
        NSWorkspace.shared.noteFileSystemChanged(app.path)
        return app.path
    }

    static func remove(at path: String) {
        guard path.hasPrefix(Paths.dockAppsDir.path) else { return }  // never touch other tools' apps
        try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
    }
}

/// The profile icon: a squircle in the profile color with its letter.
enum ProfileIcon {
    static func image(letter: String, color: ProfileColor, size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = rect.width * 0.09
            let body = rect.insetBy(dx: inset, dy: inset)
            let radius = body.width * 0.225
            let shadowOffset = rect.width * 0.022

            NSColor(hex: 0x17120E).setFill()
            NSBezierPath(roundedRect: body.offsetBy(dx: 0, dy: -shadowOffset * 1.6), xRadius: radius, yRadius: radius).fill()

            let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
            color.nsColor.setFill()
            shape.fill()
            NSColor(hex: 0x17120E).setStroke()
            shape.lineWidth = max(1, rect.width * 0.022)
            shape.stroke()

            let font = NSFont(name: "BricolageGrotesque-ExtraBold", size: body.height * 0.62)
                ?? .systemFont(ofSize: body.height * 0.6, weight: .heavy)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color.onNSColor]
            let text = NSAttributedString(string: letter, attributes: attrs)
            let textSize = text.size()
            text.draw(at: NSPoint(x: body.midX - textSize.width / 2, y: body.midY - textSize.height / 2 + body.height * 0.02))
            return true
        }
    }

    static func writeICNS(letter: String, color: ProfileColor, to url: URL) throws {
        let iconset = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: iconset) }

        for base in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let px = base * scale
                let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
                try png(image(letter: letter, color: color, size: CGFloat(px)), pixels: px)
                    .write(to: iconset.appendingPathComponent(name))
            }
        }
        _ = ClaudeCode.run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", url.path], env: nil, timeout: 20)
        guard FileManager.default.fileExists(atPath: url.path) else { throw ProfileError("Couldn't build the Dock icon.") }
    }

    private static func png(_ image: NSImage, pixels: Int) throws -> Data {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { throw ProfileError("Couldn't draw the icon.") }
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = rep.representation(using: .png, properties: [:]) else { throw ProfileError("Couldn't save the icon.") }
        return data
    }
}
