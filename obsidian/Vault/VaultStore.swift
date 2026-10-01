import Foundation
import Observation

/// In-memory view of the vault: folder tree, flat file list and link lookup tables.
@Observable
final class VaultStore {
    private(set) var tree: [FileNode] = []
    private(set) var files: [String] = []
    private(set) var resolver = LinkResolver(paths: [])
    private(set) var noteCount = 0
    var folderIcons = FolderIconConfig()
    /// Root folders whose contents are shown directly at the top of the tree.
    private(set) var unwrappedPrefixes: [String] = []

    /// Path as shown to the user, without an unwrapped root folder.
    func displayPath(_ path: String) -> String {
        for prefix in unwrappedPrefixes where path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }

    func rebuild(paths: [String]) {
        let visible = paths.filter { PathPolicy.isSafe($0) && !PathPolicy.isIgnored($0) }
        let sorted = visible.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard sorted != files else { return }
        files = sorted
        (tree, unwrappedPrefixes) = Self.unwrap(FileNode.buildTree(from: sorted))
        resolver = LinkResolver(paths: sorted)
        noteCount = sorted.count { PathPolicy.kind(of: $0) == .note }
    }

    /// Promotes the contents of wrapper folders to the top level: any root folder in
    /// `AppConfig.unwrappedFolders`, or the only folder when the repo root holds nothing else.
    static func unwrap(_ tree: [FileNode]) -> ([FileNode], [String]) {
        var prefixes: [String] = []
        var result: [FileNode] = []
        for node in tree {
            if node.isFolder, AppConfig.unwrappedFolders.contains(node.name.lowercased()) {
                result += node.children
                prefixes.append(node.path + "/")
            } else {
                result.append(node)
            }
        }
        if prefixes.isEmpty, result.count == 1, let only = result.first, only.isFolder {
            return (only.children, [only.path + "/"])
        }
        let folders = result.filter(\.isFolder).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let files = result.filter { !$0.isFolder }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return (folders + files, prefixes)
    }

    func contains(_ path: String) -> Bool {
        files.contains(path)
    }

    /// Case-insensitive file-name search; name matches rank above folder matches.
    func search(_ query: String, limit: Int = 200) -> [String] {
        let terms = query.lowercased().split(separator: " ").map(String.init)
        guard !terms.isEmpty else { return [] }
        let hits = files.filter { path in
            let lower = path.lowercased()
            return terms.allSatisfy { lower.contains($0) }
        }
        let ranked = hits.sorted { a, b in
            let na = PathPolicy.displayName(a).lowercased(), nb = PathPolicy.displayName(b).lowercased()
            let pa = na.hasPrefix(terms[0]) ? 0 : (terms.allSatisfy(na.contains) ? 1 : 2)
            let pb = nb.hasPrefix(terms[0]) ? 0 : (terms.allSatisfy(nb.contains) ? 1 : 2)
            if pa != pb { return pa < pb }
            return na.localizedStandardCompare(nb) == .orderedAscending
        }
        return Array(ranked.prefix(limit))
    }
}
