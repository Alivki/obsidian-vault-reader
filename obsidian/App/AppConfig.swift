import Foundation

/// Compile-time configuration. Nothing here is secret: a GitHub App client ID
/// is public by design (Device Flow needs no client secret).
nonisolated enum AppConfig {
    static let githubClientID = "Iv23liHFdVTQJOHGgAf1"
    static let repoOwner = "Alivki"
    static let repoName = "obsidian-vault"
    static var repoFullName: String { "\(repoOwner)/\(repoName)" }

    static let apiHost = "api.github.com"
    static let webHost = "github.com"
    static let apiVersion = "2022-11-28"

    /// Hard-coded rather than taken from the device-code response, so a tampered
    /// response can never make the app open an arbitrary URL.
    static let deviceVerificationURL = URL(string: "https://github.com/login/device")!
    static let tokenManagementURL = URL(string: "https://github.com/settings/apps/authorizations")!

    /// Root folders that aren't shown themselves; their contents appear at the top
    /// of the folder tree, as if the folder were always open. Matched case-insensitively.
    static let unwrappedFolders: Set<String> = ["bogju"]

    static let maxNoteBytes = 5 * 1024 * 1024
    static let maxMediaBytes = 50 * 1024 * 1024
    static let maxRemoteImageBytes = 15 * 1024 * 1024
    static let maxTreeEntries = 50_000
    static let maxConcurrentDownloads = 6
    static let maxImagePixelSize = 2_400
}
