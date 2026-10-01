import Foundation

nonisolated enum FileKind: Sendable, Equatable {
    case note, image, pdf, other
}

/// Every repo path and SHA from the network passes through here before it is used.
nonisolated enum PathPolicy {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

    /// Obsidian hides dot-files; we also skip `.obsidian/`, `.trash/`, `.git*`, `.DS_Store`.
    static func isIgnored(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    /// Rejects anything that could confuse the UI or a filesystem:
    /// absolute paths, `.`/`..`, empty components, backslashes, control characters and
    /// bidi overrides (which can disguise a file's real name or extension).
    static func isSafe(_ path: String) -> Bool {
        guard !path.isEmpty, path.utf8.count <= 1024, !path.hasPrefix("/"), !path.hasSuffix("/") else { return false }
        for scalar in path.unicodeScalars {
            switch scalar.value {
            case 0..<0x20, 0x7F, 0x5C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069, 0xFEFF: return false
            default: continue
            }
        }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { component in
            !component.isEmpty && component != "." && component != ".." && component.utf8.count <= 255
        }
    }

    /// Git object IDs: 40 hex (SHA-1) or 64 hex (SHA-256 repos).
    static func isValidSHA(_ sha: String) -> Bool {
        (sha.utf8.count == 40 || sha.utf8.count == 64)
            && sha.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// Lowercased ASCII-alphanumeric extension of the last path component, or "".
    static func fileExtension(_ path: String) -> String {
        let name = lastComponent(path)
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return "" }
        let ext = name[name.index(after: dot)...].lowercased()
        guard (1...10).contains(ext.count), ext.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return "" }
        return ext
    }

    static func kind(of path: String) -> FileKind {
        let ext = fileExtension(path)
        if ext == "md" { return .note }
        if ext == "pdf" { return .pdf }
        if imageExtensions.contains(ext) { return .image }
        return .other
    }

    static func lastComponent(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }

    static func parentFolder(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    static func displayName(_ path: String) -> String {
        let name = lastComponent(path)
        return kind(of: path) == .note ? String(name.dropLast(3)) : name
    }
}
