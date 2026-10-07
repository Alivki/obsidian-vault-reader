# Vault Reader

A read-only Obsidian vault reader for iOS and macOS that syncs notes from a GitHub repo.

## Setup

1. **Create a GitHub App** (Settings → Developer settings → GitHub Apps):
   - Enable **Device Flow**
   - Repository permissions: **Contents: Read-only**
   - No webhook or callback URL needed
   - Install it on your vault repo
2. **Edit `obsidian/App/AppConfig.swift`**: set `githubClientID`, `repoOwner`, `repoName`, and `unwrappedFolders` (or `[]`).
3. **Signing**: in Xcode, select your Team and change the bundle IDs (`com.alivki.vaultreader*`) for both targets.
4. Open `obsidian.xcodeproj` and run. Requires iOS 17 / macOS 14.
