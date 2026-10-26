import SwiftUI

/// One account. A profile can have a Claude Desktop side (its own data
/// folder), a Claude Code side (its own CLAUDE_CONFIG_DIR), or both.
struct Profile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var color: ProfileColor
    /// Claude Desktop data folder. nil means the profile is Code-only.
    var desktopDataDir: String?
    /// Claude Code config folder. nil means the profile is Desktop-only.
    var codeConfigDir: String?
    /// Hand the Code profile to Desktop, so its Code tab uses the same login.
    var desktopUsesCodeProfile = true
    var dockAppPath: String?
    var origin: ProfileOrigin
    var createdAt = Date()
    var lastLaunched: Date?

    var letter: String { String(name.first ?? "?").uppercased() }
    var isDefault: Bool { origin == .system }
    var hasDesktop: Bool { desktopDataDir != nil }
    var hasCode: Bool { codeConfigDir != nil }

    /// The CLAUDE_CONFIG_DIR handed to Claude Desktop, if any.
    var desktopCodeDir: String? { desktopUsesCodeProfile ? codeConfigDir : nil }
}

enum ProfileOrigin: String, Codable {
    case system, claudeSwitch, cli, multiClaude, multipleClaude

    var label: String {
        switch self {
        case .system: "Your main Claude"
        case .claudeSwitch: "Claude Switch"
        case .cli: "claude-switch CLI"
        case .multiClaude: "Imported from Multi-Claude"
        case .multipleClaude: "Imported from Multiple Claude"
        }
    }
}

enum ProfileColor: String, Codable, CaseIterable, Identifiable {
    case tangerine, coral, violet, ocean, leaf, sun, pink, ink

    var id: String { rawValue }

    var hex: UInt32 {
        switch self {
        case .tangerine: 0xFF6B2C
        case .coral: 0xE5484D
        case .violet: 0x7C5CFF
        case .ocean: 0x2F7BF5
        case .leaf: 0x1F9D63
        case .sun: 0xFFC53D
        case .pink: 0xFF5FA8
        case .ink: 0x17120E
        }
    }

    var color: Color { Color(hex: hex) }
    var nsColor: NSColor { NSColor(hex: hex) }

    /// Text on top of the color: ink on light colors, paper on dark ones.
    var onColor: Color { self == .sun || self == .tangerine || self == .pink ? Brand.ink : Brand.paper }
    var onNSColor: NSColor { self == .sun || self == .tangerine || self == .pink ? NSColor(hex: 0x17120E) : NSColor(hex: 0xFFF5EC) }

    /// Multi-Claude stores color names; anything unknown lands on coral.
    init(multiClaudeName: String?) {
        switch multiClaudeName?.lowercased() {
        case "violet", "purple": self = .violet
        case "blue", "ocean", "sky", "indigo": self = .ocean
        case "green", "emerald", "leaf", "teal": self = .leaf
        case "yellow", "amber", "sun": self = .sun
        case "pink", "rose": self = .pink
        case "orange", "tangerine": self = .tangerine
        case "slate", "gray", "graphite", "black": self = .ink
        default: self = .coral
        }
    }

    static func next(after used: [ProfileColor]) -> ProfileColor {
        allCases.first { !used.contains($0) } ?? allCases[used.count % allCases.count]
    }
}

/// What `claude auth status` reports for a Claude Code profile.
struct CodeAuth: Equatable {
    var loggedIn: Bool
    var email: String?
    var plan: String?
    var org: String?

    var planLabel: String? {
        guard let plan, !plan.isEmpty else { return nil }
        return plan.prefix(1).uppercased() + plan.dropFirst()
    }
}
