import Foundation

/// Internal URL schemes used between the preprocessor and the renderer.
/// None are registered with the OS, so other apps can't deep-link into the app.
///
/// - `vault://open?path=…&heading=…`     open a note
/// - `vault://missing?name=…`            unresolved wikilink
/// - `vault-file://image?path=…&w=…`     embedded image from the cache
/// - `vault-file://open?path=…`          open an attachment in Quick Look
/// - `vault-file://missing?name=…`       unresolved embed
/// - `vault-rel://vault/<folder>/`       base URL for plain relative markdown links
nonisolated enum VaultURL {
    static let noteScheme = "vault"
    static let fileScheme = "vault-file"
    static let relativeScheme = "vault-rel"

    static func note(_ path: String, heading: String? = nil) -> String {
        var url = "vault://open?path=\(encode(path))"
        if let heading, !heading.isEmpty { url += "&heading=\(encode(heading))" }
        return url
    }

    static func missingNote(_ name: String) -> String { "vault://missing?name=\(encode(name))" }

    static func image(_ path: String, width: Int?) -> String {
        "vault-file://image?path=\(encode(path))" + (width.map { "&w=\($0)" } ?? "")
    }

    static func missingImage(_ name: String) -> String { "vault-file://missing?name=\(encode(name))" }

    static func file(_ path: String) -> String { "vault-file://open?path=\(encode(path))" }

    static func baseURL(for notePath: String) -> URL? {
        let folder = PathPolicy.parentFolder(notePath)
        let encoded = folder.split(separator: "/").map { encode(String($0)) }.joined(separator: "/")
        return URL(string: "vault-rel://vault/" + (encoded.isEmpty ? "" : encoded + "/"))
    }

    static func parameters(of url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems ?? []
        var result: [String: String] = [:]
        for item in items where result[item.name] == nil { result[item.name] = item.value ?? "" }
        return result
    }

    /// Repo path a `vault-rel:` link points at, or nil if it tries to leave the vault.
    static func relativePath(of url: URL) -> String? {
        let absolute = url.absoluteURL
        guard absolute.scheme == relativeScheme, absolute.host() == "vault" else { return nil }
        let path = absolute.path(percentEncoded: false)
        guard let normalized = LinkResolver.normalize(path), PathPolicy.isSafe(normalized) else { return nil }
        return normalized
    }

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? ""
    }
}
