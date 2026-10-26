# Claude Switch for Mac

A SwiftUI app that runs every Claude account side by side: Claude Desktop and
Claude Code, one login per profile.

## How it works

Built for the Mac App Store, so it runs in the App Sandbox.

- **Home folder access.** On first launch the user picks their home folder
  once. A security-scoped bookmark keeps that access, which covers
  `~/Library/Application Support` and the `~/.claude-*` folders.
- **Claude Desktop profiles.** Each profile starts Claude Desktop with
  `--user-data-dir=~/Library/Application Support/Claude-<name>`, so every
  account gets its own window, chats and login. An open profile is found by
  asking (`F_GETLK`) who holds the LevelDB lock in its data folder. The lock
  is never taken.
- **Claude Code profiles.** The same `~/.claude-<name>` folders the CLI makes
  (`.profile-name` marker, shared items symlinked from `~/.claude`). The
  signed-in account is read from the folder's `.claude.json`. Code opens in
  Terminal, iTerm or Warp through a `.command` file, or in Ghostty with `-e`.
- **One profile, both apps.** When a profile has both, Desktop gets the Code
  folder as `CLAUDE_CONFIG_DIR`, so its Code tab uses the same login.
- **Import and search.** Profiles from Multi-Claude (`multi-claude/profiles.json`),
  Multiple Claude and the CLI are listed straight away. "Search my Mac" walks
  the home folder and recognises Claude folders by their contents. Everything
  opens from where it is: nothing is moved or copied.

The profile list lives in the app container:
`~/Library/Containers/dev.claudeswitch.app/Data/Library/Application Support/Claude Switch/profiles.json`.

## Build

```bash
cd mac
xcodegen generate
xcodebuild -project ClaudeSwitch.xcodeproj -scheme ClaudeSwitch -configuration Debug -derivedDataPath build/dd build
```

Debug builds are ad-hoc signed with the sandbox on. For the App Store, archive
the Release configuration in Xcode (automatic signing, team 3J5987UXFQ) and
upload it to App Store Connect.

- `swift scripts/make-app-icon.swift` redraws the app icon.
- Launch with `-demo` for website screenshots with sample profiles.
