# Claude Switch for Mac

A SwiftUI app that runs every Claude account side by side: Claude Desktop and
Claude Code, one login per profile.

## How it works

- **Claude Desktop profiles.** Each profile starts Claude Desktop with
  `--user-data-dir=~/Library/Application Support/Claude-<name>`, so every
  account gets its own window, chats and login. Running instances are found by
  reading each Claude process's arguments.
- **Claude Code profiles.** The same `~/.claude-<name>` folders the CLI makes
  (`.profile-name` marker, shared items symlinked from `~/.claude`). Code opens
  in Terminal, iTerm, Ghostty or Warp with `CLAUDE_CONFIG_DIR` set.
- **One profile, both apps.** When a profile has both, Desktop gets the Code
  folder as `CLAUDE_CONFIG_DIR`, so its Code tab uses the same login.
- **Dock apps.** `~/Applications/Claude Switch/<Name>.app` holds the bundled
  `ProfileLauncher`, an Info.plist with the profile's folders and a generated
  icon. It opens (or focuses) that profile's Claude and exits.
- **Import.** Profiles from Multi-Claude (`multi-claude/profiles.json`),
  Multiple Claude and the CLI are opened from their existing folders. Nothing is
  moved or copied, so the other tool keeps working.

The profile list lives in `~/Library/Application Support/Claude Switch/profiles.json`.

## Build

```bash
cd mac
xcodegen generate
xcodebuild -project ClaudeSwitch.xcodeproj -scheme ClaudeSwitch -configuration Release -derivedDataPath build/dd build
```

The app is not sandboxed: it starts Claude with arguments, writes to
`~/Applications` and reads other tools' profile folders, which the Mac App
Store sandbox doesn't allow. Ship it with Developer ID signing and notarization.

- `swift scripts/make-app-icon.swift` redraws the app icon.
- Launch with `-demo` for website screenshots with sample profiles.
