import Foundation

/// URLSession factory hardened for this app:
/// - ephemeral: no cookies, no credential store, no on-disk URL cache (blob bodies
///   would otherwise land unencrypted in Caches/)
/// - TLS 1.2+ only (ATS already forbids plain HTTP)
/// - redirects are only followed to the *same* https host, so the bearer token can
///   never be forwarded to another server.
nonisolated enum SecureSession {
    static let github: URLSession = make(delegate: SameHostRedirectGuard())
    /// Used only for opt-in remote images in notes. Never carries credentials.
    static let media: URLSession = make(delegate: HTTPSOnlyRedirectGuard())

    private static func make(delegate: URLSessionTaskDelegate) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.httpMaximumConnectionsPerHost = AppConfig.maxConcurrentDownloads
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}

nonisolated final class SameHostRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let from = task.originalRequest?.url
        guard let to = request.url, to.scheme == "https", to.host == from?.host else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

nonisolated final class HTTPSOnlyRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var request = request
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(request.url?.scheme == "https" ? request : nil)
    }
}
