import Foundation

nonisolated struct RemoteFile: Sendable, Equatable, Hashable {
    let path: String
    let sha: String
    let size: Int
}

nonisolated struct SyncPlan: Sendable, Equatable {
    /// Notes that must be fetched now (new, changed, or missing on disk).
    var downloadNow: [RemoteFile] = []
    /// Attachments that are new or changed; fetched lazily when viewed.
    var markStale: [RemoteFile] = []
    /// Paths that no longer exist in the repo.
    var removed: [String] = []
    var unchanged = 0
}

/// Pure diff between the remote tree and the local index. Because blob SHAs are
/// content hashes, "same SHA" means "same bytes", so the diff is exact.
nonisolated enum SyncDiff {
    static func plan(
        remote: [RemoteFile],
        local: [String: IndexEntry],
        isEager: (String) -> Bool = { PathPolicy.kind(of: $0) == .note }
    ) -> SyncPlan {
        var plan = SyncPlan()
        var remotePaths = Set<String>()
        for file in remote {
            remotePaths.insert(file.path)
            let existing = local[file.path]
            let eager = isEager(file.path)
            if let existing, existing.sha == file.sha {
                if eager && !existing.isCurrent { plan.downloadNow.append(file) } else { plan.unchanged += 1 }
            } else if eager {
                plan.downloadNow.append(file)
            } else {
                plan.markStale.append(file)
            }
        }
        plan.removed = local.keys.filter { !remotePaths.contains($0) }.sorted()
        plan.downloadNow.sort { $0.path < $1.path }
        plan.markStale.sort { $0.path < $1.path }
        return plan
    }
}
