import Foundation

nonisolated struct FileNode: Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let isFolder: Bool
    var children: [FileNode]

    var id: String { path }
    var kind: FileKind { isFolder ? .other : PathPolicy.kind(of: path) }
    var displayName: String { isFolder ? name : PathPolicy.displayName(path) }

    /// Builds a folder tree from flat repo paths. Folders first, then natural
    /// ("1, 2, 10") case-insensitive order, so numeric prefixes keep their order.
    static func buildTree(from paths: [String]) -> [FileNode] {
        final class Builder {
            var folders: [String: Builder] = [:]
            var files: [String: String] = [:]   // name -> path
        }
        let root = Builder()
        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            guard let fileName = parts.last else { continue }
            var node = root
            for part in parts.dropLast() {
                if let next = node.folders[part] { node = next } else {
                    let next = Builder()
                    node.folders[part] = next
                    node = next
                }
            }
            node.files[fileName] = path
        }

        func convert(_ builder: Builder, prefix: String) -> [FileNode] {
            let folders = builder.folders.map { name, child in
                let path = prefix.isEmpty ? name : "\(prefix)/\(name)"
                return FileNode(name: name, path: path, isFolder: true, children: convert(child, prefix: path))
            }
            let files = builder.files.map { name, path in
                FileNode(name: name, path: path, isFolder: false, children: [])
            }
            return folders.sorted(by: naturalOrder) + files.sorted(by: naturalOrder)
        }
        return convert(root, prefix: "")
    }

    private static func naturalOrder(_ a: FileNode, _ b: FileNode) -> Bool {
        a.name.localizedStandardCompare(b.name) == .orderedAscending
    }
}
