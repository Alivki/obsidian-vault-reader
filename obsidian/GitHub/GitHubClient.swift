import Foundation

nonisolated enum GitHubError: LocalizedError, Sendable {
    case unauthorized
    case notFound
    case forbidden
    case rateLimited(resetAt: Date?)
    case http(Int)
    case invalidResponse
    case tooLarge
    case integrityMismatch
    case treeTooLarge

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Your GitHub session expired or was revoked. Sign in again."
        case .notFound: "\(AppConfig.repoFullName) wasn't found. Make sure the GitHub App is installed on it."
        case .forbidden: "GitHub refused the request. Check the app's repository permissions."
        case .rateLimited(let reset):
            if let reset { "GitHub rate limit reached. Try again \(reset.formatted(.relative(presentation: .named)))." }
            else { "GitHub rate limit reached. Try again later." }
        case .http(let code): "GitHub returned HTTP \(code)."
        case .invalidResponse: "GitHub sent an unexpected response."
        case .tooLarge: "File is too large to download."
        case .integrityMismatch: "A downloaded file failed its integrity check."
        case .treeTooLarge: "The vault has too many files."
        }
    }
}

/// Thin, read-only wrapper over the handful of GitHub REST endpoints the app needs.
/// All URLs are built from constants plus validated SHAs, so note content can never
/// steer where the token is sent.
nonisolated struct GitHubClient: Sendable {
    let token: String
    var session: URLSession = SecureSession.github

    enum BranchResult: Sendable {
        case notModified
        case modified(GitHubBranch, etag: String?)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func user() async throws -> GitHubUser {
        try await getJSON("/user")
    }

    func repo() async throws -> GitHubRepo {
        try await getJSON(repoPath(""))
    }

    func branch(_ name: String, etag: String?) async throws -> BranchResult {
        guard Self.isValidBranchName(name) else { throw GitHubError.invalidResponse }
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? name
        var request = makeRequest(repoPath("/branches/\(encoded)"))
        if let etag, etag.utf8.count < 200, !etag.contains(where: \.isNewline) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await send(request)
        if response.statusCode == 304 { return .notModified }
        let branch = try Self.decoder.decode(GitHubBranch.self, from: data)
        guard PathPolicy.isValidSHA(branch.commit.sha), PathPolicy.isValidSHA(branch.commit.commit.tree.sha) else {
            throw GitHubError.invalidResponse
        }
        return .modified(branch, etag: response.value(forHTTPHeaderField: "ETag"))
    }

    func tree(sha: String, recursive: Bool) async throws -> GitTree {
        guard PathPolicy.isValidSHA(sha) else { throw GitHubError.invalidResponse }
        return try await getJSON(repoPath("/git/trees/\(sha)"), query: recursive ? "recursive=1" : nil, maxBytes: 64 * 1024 * 1024)
    }

    /// Downloads a blob's raw bytes. Size is bounded and the caller verifies the git hash.
    func blob(sha: String, maxBytes: Int) async throws -> Data {
        guard PathPolicy.isValidSHA(sha) else { throw GitHubError.invalidResponse }
        let request = makeRequest(repoPath("/git/blobs/\(sha)"), accept: "application/vnd.github.raw+json")
        let (data, _) = try await send(request, maxBytes: maxBytes)
        return data
    }

    // MARK: - Plumbing

    private func repoPath(_ suffix: String) -> String {
        "/repos/\(AppConfig.repoOwner)/\(AppConfig.repoName)\(suffix)"
    }

    private func makeRequest(_ path: String, query: String? = nil, accept: String = "application/vnd.github+json") -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = AppConfig.apiHost
        components.percentEncodedPath = path
        components.percentEncodedQuery = query
        var request = URLRequest(url: components.url!)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("VaultReader", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func getJSON<T: Decodable>(_ path: String, query: String? = nil, maxBytes: Int = 4 * 1024 * 1024) async throws -> T {
        let (data, _) = try await send(makeRequest(path, query: query), maxBytes: maxBytes)
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw GitHubError.invalidResponse }
    }

    private func send(_ request: URLRequest, maxBytes: Int = 4 * 1024 * 1024) async throws -> (Data, HTTPURLResponse) {
        guard GitHubToken.isWellFormed(token) else { throw GitHubError.unauthorized }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == AppConfig.apiHost else {
            throw GitHubError.invalidResponse
        }
        switch http.statusCode {
        case 200...299, 304:
            guard data.count <= maxBytes else { throw GitHubError.tooLarge }
            return (data, http)
        case 401:
            throw GitHubError.unauthorized
        case 403, 429:
            let remaining = http.value(forHTTPHeaderField: "x-ratelimit-remaining")
            if http.statusCode == 429 || remaining == "0" {
                let reset = http.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
                throw GitHubError.rateLimited(resetAt: reset.map(Date.init(timeIntervalSince1970:)))
            }
            throw GitHubError.forbidden
        case 404:
            throw GitHubError.notFound
        default:
            throw GitHubError.http(http.statusCode)
        }
    }

    static func isValidBranchName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 250 && !name.contains("..")
            && !name.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F || " ~^:?*[\\".unicodeScalars.contains($0) }
    }
}

nonisolated extension CharacterSet {
    /// RFC 3986 unreserved characters. Everything else gets percent-encoded.
    static let urlUnreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
}
