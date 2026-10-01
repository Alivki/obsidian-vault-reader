import Foundation

/// Resolves Obsidian link targets (`[[Note]]`, `[[Folder/Note]]`, `![[image.png]]`)
/// to repo paths, roughly the way Obsidian does:
/// 1. exact path (with or without `.md`), 2. relative to the current note's folder,
/// 3. by file name — preferring the match closest to the current note.
nonisolated struct LinkResolver: Sendable {
    private let pathsByLowercase: [String: String]
    private let byName: [String: [String]]

    init(paths: [String]) {
        var pathsByLowercase: [String: String] = [:]
        var byName: [String: [String]] = [:]
        for path in paths {
            pathsByLowercase[path.lowercased()] = path
            let name = PathPolicy.lastComponent(path).lowercased()
            byName[name, default: []].append(path)
            if PathPolicy.kind(of: path) == .note {
                byName[String(name.dropLast(3)), default: []].append(path)
            }
        }
        self.pathsByLowercase = pathsByLowercase
        self.byName = byName
    }

    func resolve(_ rawTarget: String, from currentPath: String?) -> String? {
        var target = rawTarget.trimmingCharacters(in: .whitespaces)
        while target.hasPrefix("/") { target.removeFirst() }
        guard !target.isEmpty, target.count <= 1024 else { return nil }
        let lower = target.lowercased()
        let candidates = lower.hasSuffix(".md") ? [lower] : [lower, lower + ".md"]

        for candidate in candidates {
            if let path = pathsByLowercase[candidate] { return path }
        }
        if let currentPath {
            let folder = PathPolicy.parentFolder(currentPath).lowercased()
            for candidate in candidates {
                if let joined = Self.normalize(folder.isEmpty ? candidate : "\(folder)/\(candidate)"),
                   let path = pathsByLowercase[joined] {
                    return path
                }
            }
        }

        let name = PathPolicy.lastComponent(lower)
        var matches = byName[name] ?? []
        if lower.contains("/") {
            matches = matches.filter { path in
                candidates.contains { path.lowercased().hasSuffix("/\($0)") }
            }
        }
        return Self.closest(Array(Set(matches)), to: currentPath)
    }

    /// Prefers the match sharing the most leading folders with the current note,
    /// then the shallowest, then alphabetical.
    static func closest(_ matches: [String], to currentPath: String?) -> String? {
        guard matches.count > 1 else { return matches.first }
        let here = currentPath.map { PathPolicy.parentFolder($0).split(separator: "/") } ?? []
        func shared(_ path: String) -> Int {
            let folders = PathPolicy.parentFolder(path).split(separator: "/")
            return zip(folders, here).prefix { $0 == $1 }.count
        }
        return matches.min { a, b in
            let sa = shared(a), sb = shared(b)
            if sa != sb { return sa > sb }
            let da = a.split(separator: "/").count, db = b.split(separator: "/").count
            if da != db { return da < db }
            return a < b
        }
    }

    /// Collapses `.` and `..`; returns nil if the path would escape the vault root.
    static func normalize(_ path: String) -> String? {
        var parts: [Substring] = []
        for part in path.split(separator: "/") {
            switch part {
            case ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }
}
