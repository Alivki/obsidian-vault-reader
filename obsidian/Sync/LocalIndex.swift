import Foundation

nonisolated struct IndexEntry: Codable, Sendable, Equatable {
    /// Blob SHA of the file at the synced commit.
    var sha: String
    var size: Int
    /// Blob SHA of the copy on disk, if any. Differs from `sha` while a newer
    /// version of a lazily-downloaded file hasn't been fetched yet.
    var localSha: String?

    var isCurrent: Bool { localSha == sha }
}

/// `index.json`: what was synced, from which commit, and what is on disk.
nonisolated struct LocalIndex: Codable, Sendable {
    static let currentVersion = 1

    var version = LocalIndex.currentVersion
    var repo = AppConfig.repoFullName
    var branch: String?
    var commitSha: String?
    var etag: String?
    var lastSync: Date?
    var files: [String: IndexEntry] = [:]

    static func load(from url: URL) -> LocalIndex {
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder.iso.decode(LocalIndex.self, from: data),
              index.version == currentVersion,
              index.repo == AppConfig.repoFullName
        else { return LocalIndex() }
        return index.sanitized()
    }

    func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.iso.encode(self).write(to: url, options: BlobStore.writeOptions)
    }

    /// The index is local state, but treat it as untrusted anyway: drop anything malformed.
    func sanitized() -> LocalIndex {
        var copy = self
        copy.files = files.filter { path, entry in
            PathPolicy.isSafe(path) && PathPolicy.isValidSHA(entry.sha)
                && (entry.localSha.map(PathPolicy.isValidSHA) ?? true)
        }
        if let commit = commitSha, !PathPolicy.isValidSHA(commit) { copy.commitSha = nil; copy.etag = nil }
        if let branch, !GitHubClient.isValidBranchName(branch) { copy.branch = nil }
        return copy
    }
}

nonisolated extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

nonisolated extension JSONEncoder {
    static let iso: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
