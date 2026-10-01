import Foundation

nonisolated struct GitHubUser: Decodable, Sendable {
    let login: String
    let name: String?
}

nonisolated struct GitHubRepo: Decodable, Sendable {
    let fullName: String
    let defaultBranch: String
}

nonisolated struct GitHubBranch: Decodable, Sendable {
    let name: String
    let commit: GitHubBranchCommit
}

nonisolated struct GitHubBranchCommit: Decodable, Sendable {
    let sha: String
    let commit: GitHubCommitDetail
}

nonisolated struct GitHubCommitDetail: Decodable, Sendable {
    let tree: GitHubTreeRef
}

nonisolated struct GitHubTreeRef: Decodable, Sendable {
    let sha: String
}

nonisolated struct GitTree: Decodable, Sendable {
    let sha: String
    let tree: [GitTreeEntry]
    let truncated: Bool
}

nonisolated struct GitTreeEntry: Decodable, Sendable {
    let path: String
    let mode: String
    let type: String
    let sha: String
    let size: Int?

    var isRegularFile: Bool { type == "blob" && (mode == "100644" || mode == "100755") }
    var isTree: Bool { type == "tree" }
}

nonisolated struct DeviceCodeResponse: Decodable, Sendable {
    let deviceCode: String
    let userCode: String
    let expiresIn: Int
    let interval: Int
}

nonisolated struct AccessTokenResponse: Decodable, Sendable {
    let accessToken: String?
    let error: String?
    let errorDescription: String?
    let interval: Int?
}
