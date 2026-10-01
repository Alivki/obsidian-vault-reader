import Foundation
import Observation

/// Keeps the local cache in step with the repo's default branch.
///
/// 1. `GET branch` with ETag → 304 / same commit → done
/// 2. `GET tree?recursive=1` → filter → diff against `index.json`
/// 3. Notes download now (≤ 6 in parallel), attachments lazily on first view
/// 4. Commit SHA + ETag are only recorded once every note downloaded, so a
///    partial sync is completed automatically next time.
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle
        case checking
        case downloading(done: Int, total: Int)
        case upToDate
        case offline
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var index: LocalIndex
    private(set) var lastAttempt: Date?
    let store: BlobStore

    var onFilesChanged: (([String]) -> Void)?
    var onUnauthorized: (() -> Void)?

    private var running: Task<Void, Never>?
    private var inflight: [String: Task<URL, Error>] = [:]
    private var pendingSave: Task<Void, Never>?

    init(store: BlobStore = .default) {
        self.store = store
        try? store.prepare()
        index = LocalIndex.load(from: store.indexURL)
    }

    var isSyncing: Bool {
        switch status {
        case .checking, .downloading: true
        default: false
        }
    }

    var allPaths: [String] { Array(index.files.keys) }

    func sync(client: GitHubClient, force: Bool = false) async {
        if let running {
            await running.value
            if !force { return }
        }
        let task = Task { await performSync(client: client, force: force) }
        running = task
        await task.value
        running = nil
    }

    /// Returns a local file URL for `path`, downloading the current version if needed.
    /// Falls back to an older cached copy when offline.
    func localURL(for path: String, client: GitHubClient?) async throws -> URL {
        guard let entry = index.files[path] else { throw CocoaError(.fileNoSuchFile) }
        if entry.isCurrent, store.exists(sha: entry.sha, path: path), let url = store.fileURL(sha: entry.sha, path: path) {
            return url
        }
        let fallback = entry.localSha.flatMap { sha in
            store.exists(sha: sha, path: path) ? store.fileURL(sha: sha, path: path) : nil
        }
        guard let client else {
            if let fallback { return fallback }
            throw URLError(.notConnectedToInternet)
        }
        do {
            let url = try await fetchShared(path: path, sha: entry.sha, size: entry.size, client: client)
            if index.files[path]?.sha == entry.sha {
                index.files[path]?.localSha = entry.sha
                scheduleIndexSave()
            }
            return url
        } catch {
            if case GitHubError.unauthorized = error { onUnauthorized?() }
            if let fallback { return fallback }
            throw error
        }
    }

    func clearCache() {
        running?.cancel()
        inflight.values.forEach { $0.cancel() }
        inflight.removeAll()
        store.removeAll()
        try? store.prepare()
        index = LocalIndex()
        status = .idle
        lastAttempt = nil
        publishFiles()
    }

    // MARK: - Sync

    private func performSync(client: GitHubClient, force: Bool) async {
        lastAttempt = Date()
        status = .checking
        do {
            if index.branch == nil || force {
                let repo = try await client.repo()
                guard GitHubClient.isValidBranchName(repo.defaultBranch) else { throw GitHubError.invalidResponse }
                if index.branch != repo.defaultBranch {
                    index.branch = repo.defaultBranch
                    index.etag = nil
                }
            }
            guard let branchName = index.branch else { throw GitHubError.invalidResponse }

            var result = try await client.branch(branchName, etag: force ? nil : index.etag)
            if case .notModified = result {
                if notesComplete { return markUpToDate() }
                result = try await client.branch(branchName, etag: nil)
            }
            guard case let .modified(branch, etag) = result else { throw GitHubError.invalidResponse }
            if !force, branch.commit.sha == index.commitSha, notesComplete {
                index.etag = etag
                return markUpToDate()
            }

            let entries = try await fetchTree(client: client, sha: branch.commit.commit.tree.sha)
            let remote = entries.compactMap { entry -> RemoteFile? in
                guard entry.isRegularFile, PathPolicy.isSafe(entry.path),
                      !PathPolicy.isIgnored(entry.path) || FolderIcons.isConfigPath(entry.path),
                      PathPolicy.isValidSHA(entry.sha) else { return nil }
                return RemoteFile(path: entry.path, sha: entry.sha, size: max(entry.size ?? 0, 0))
            }

            for (path, entry) in index.files {
                if let local = entry.localSha, !store.exists(sha: local, path: path) {
                    index.files[path]?.localSha = nil
                }
            }

            let plan = SyncDiff.plan(remote: remote, local: index.files)
            for path in plan.removed { index.files[path] = nil }
            for file in plan.markStale + plan.downloadNow {
                index.files[file.path] = IndexEntry(sha: file.sha, size: file.size, localSha: index.files[file.path]?.localSha)
            }
            publishFiles()

            let failures = try await download(plan.downloadNow, client: client)
            if failures == 0 {
                index.commitSha = branch.commit.sha
                index.etag = etag
                index.lastSync = Date()
            } else {
                index.etag = nil
            }
            collectGarbage()
            try? saveIndex()
            status = failures == 0 ? .upToDate : .failed("\(failures) note\(failures == 1 ? "" : "s") couldn't be downloaded")
        } catch {
            handle(error)
        }
    }

    private var notesComplete: Bool {
        index.files.allSatisfy { path, entry in
            PathPolicy.kind(of: path) != .note || entry.size > AppConfig.maxNoteBytes
                || (entry.isCurrent && store.exists(sha: entry.sha, path: path))
        }
    }

    private func markUpToDate() {
        index.lastSync = Date()
        try? saveIndex()
        status = .upToDate
    }

    private func handle(_ error: Error) {
        try? saveIndex()
        if error is CancellationError {
            status = .idle
        } else if let urlError = error as? URLError, urlError.isOffline || urlError.code == .cancelled {
            status = urlError.code == .cancelled ? .idle : .offline
        } else {
            status = .failed((error as? LocalizedError)?.errorDescription ?? "Sync failed.")
            if case GitHubError.unauthorized = error { onUnauthorized?() }
        }
    }

    private func fetchTree(client: GitHubClient, sha: String) async throws -> [GitTreeEntry] {
        let tree = try await client.tree(sha: sha, recursive: true)
        if !tree.truncated {
            guard tree.tree.count <= AppConfig.maxTreeEntries else { throw GitHubError.treeTooLarge }
            return tree.tree
        }
        // Very large repos: GitHub truncates recursive trees, so walk folder by folder.
        var result: [GitTreeEntry] = []
        var queue: [(prefix: String, sha: String)] = [("", sha)]
        while let (prefix, treeSha) = queue.popLast() {
            try Task.checkCancellation()
            let level = try await client.tree(sha: treeSha, recursive: false)
            for entry in level.tree {
                let path = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"
                if entry.isTree {
                    if PathPolicy.isSafe(path), PathPolicy.isValidSHA(entry.sha),
                       !PathPolicy.isIgnored(path) || FolderIcons.leadsToConfig(path) {
                        queue.append((path, entry.sha))
                    }
                } else {
                    result.append(GitTreeEntry(path: path, mode: entry.mode, type: entry.type, sha: entry.sha, size: entry.size))
                }
                if result.count + queue.count > AppConfig.maxTreeEntries { throw GitHubError.treeTooLarge }
            }
        }
        return result
    }

    /// Downloads notes with bounded parallelism. Returns the number of failures.
    private func download(_ files: [RemoteFile], client: GitHubClient) async throws -> Int {
        let files = files.filter { $0.size <= AppConfig.maxNoteBytes }
        guard !files.isEmpty else { return 0 }
        let store = store
        var done = 0
        var failures = 0
        var unauthorized = false
        status = .downloading(done: 0, total: files.count)

        await withTaskGroup(of: (RemoteFile, Error?).self) { group in
            var pending = files.makeIterator()
            for _ in 0..<AppConfig.maxConcurrentDownloads {
                guard let file = pending.next() else { break }
                group.addTask { await Self.fetch(file, client: client, store: store) }
            }
            while let (file, error) = await group.next() {
                done += 1
                if let error {
                    failures += 1
                    if case GitHubError.unauthorized = error {
                        unauthorized = true
                        group.cancelAll()
                    }
                } else {
                    index.files[file.path]?.localSha = file.sha
                }
                status = .downloading(done: done, total: files.count)
                if !unauthorized, !Task.isCancelled, let next = pending.next() {
                    group.addTask { await Self.fetch(next, client: client, store: store) }
                }
            }
        }
        try Task.checkCancellation()
        if unauthorized { throw GitHubError.unauthorized }
        return failures
    }

    nonisolated private static func fetch(_ file: RemoteFile, client: GitHubClient, store: BlobStore) async -> (RemoteFile, Error?) {
        do {
            let data = try await client.blob(sha: file.sha, maxBytes: AppConfig.maxNoteBytes)
            try store.write(data, sha: file.sha, path: file.path)
            return (file, nil)
        } catch {
            return (file, error)
        }
    }

    private func fetchShared(path: String, sha: String, size: Int, client: GitHubClient) async throws -> URL {
        let limit = PathPolicy.kind(of: path) == .note ? AppConfig.maxNoteBytes
            : FolderIcons.isConfigPath(path) ? FolderIcons.maxConfigBytes : AppConfig.maxMediaBytes
        guard size <= limit else { throw GitHubError.tooLarge }
        let key = store.fileURL(sha: sha, path: path)?.lastPathComponent ?? sha
        if let existing = inflight[key] { return try await existing.value }
        let store = store
        let task = Task.detached {
            let data = try await client.blob(sha: sha, maxBytes: limit)
            return try store.write(data, sha: sha, path: path)
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        return try await task.value
    }

    private func collectGarbage() {
        var keep = Set(inflight.keys)
        for (path, entry) in index.files {
            if let local = entry.localSha, let name = store.fileURL(sha: local, path: path)?.lastPathComponent {
                keep.insert(name)
            }
        }
        store.collectGarbage(keeping: keep)
    }

    private func publishFiles() {
        onFilesChanged?(allPaths)
    }

    private func saveIndex() throws {
        pendingSave?.cancel()
        pendingSave = nil
        try index.save(to: store.indexURL)
    }

    private func scheduleIndexSave() {
        pendingSave?.cancel()
        pendingSave = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            try? saveIndex()
        }
    }
}
