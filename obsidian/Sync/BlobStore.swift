import CryptoKit
import Foundation

/// Content-addressed cache: each file is stored as `files/<blob-sha>.<ext>`.
///
/// Repo paths are never used as filesystem paths, which removes path traversal
/// (`../../`), symlink tricks and case-insensitive-filesystem collisions as a class.
/// Every download is verified against its git blob hash before it is written.
nonisolated struct BlobStore: Sendable {
    let root: URL

    static let `default`: BlobStore = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return BlobStore(root: base.appending(path: "VaultReader", directoryHint: .isDirectory))
    }()

    var filesDirectory: URL { root.appending(path: "files", directoryHint: .isDirectory) }
    var indexURL: URL { root.appending(path: "index.json", directoryHint: .notDirectory) }

    func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        // Re-downloadable private data: keep it out of iCloud/iTunes backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var rootURL = root
        try? rootURL.setResourceValues(values)
    }

    func fileURL(sha: String, path: String) -> URL? {
        guard PathPolicy.isValidSHA(sha) else { return nil }
        let ext = PathPolicy.fileExtension(path)
        let name = ext.isEmpty ? sha : "\(sha).\(ext)"
        return filesDirectory.appending(path: name, directoryHint: .notDirectory)
    }

    func exists(sha: String, path: String) -> Bool {
        guard let url = fileURL(sha: sha, path: path) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @discardableResult
    func write(_ data: Data, sha: String, path: String) throws -> URL {
        guard let url = fileURL(sha: sha, path: path) else { throw GitHubError.invalidResponse }
        guard Self.gitBlobHash(of: data, hexLength: sha.utf8.count) == sha else { throw GitHubError.integrityMismatch }
        try prepare()
        try data.write(to: url, options: Self.writeOptions)
        return url
    }

    func read(sha: String, path: String, maxBytes: Int) throws -> Data {
        guard let url = fileURL(sha: sha, path: path) else { throw CocoaError(.fileNoSuchFile) }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= maxBytes else { throw GitHubError.tooLarge }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    /// Deletes every cached blob whose file name isn't in `keep`.
    func collectGarbage(keeping keep: Set<String>) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: filesDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where !keep.contains(file.lastPathComponent) {
            try? fm.removeItem(at: file)
        }
    }

    func removeAll() {
        try? FileManager.default.removeItem(at: root)
    }

    static var writeOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #else
        [.atomic]
        #endif
    }

    /// `git hash-object`: hash of "blob <size>\0<content>".
    static func gitBlobHash(of data: Data, hexLength: Int = 40) -> String {
        let header = Data("blob \(data.count)\u{0}".utf8)
        if hexLength == 64 {
            var hasher = SHA256()
            hasher.update(data: header)
            hasher.update(data: data)
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        var hasher = Insecure.SHA1()
        hasher.update(data: header)
        hasher.update(data: data)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
