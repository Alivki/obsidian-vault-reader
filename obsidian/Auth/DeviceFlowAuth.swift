import Foundation

nonisolated enum DeviceFlowError: LocalizedError, Sendable {
    case expired
    case denied
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .expired: "The code expired before it was confirmed. Start again to get a new one."
        case .denied: "Access was denied on GitHub."
        case .invalidResponse: "GitHub sent an unexpected response."
        case .server(let message): message
        }
    }
}

nonisolated struct DeviceCode: Sendable, Equatable {
    let deviceCode: String
    let userCode: String
    let expiresAt: Date
    let interval: Int
}

/// GitHub OAuth Device Flow (RFC 8628). No client secret, no redirect URL,
/// no custom URL scheme registered with the OS.
nonisolated struct DeviceFlowClient: Sendable {
    var session: URLSession = SecureSession.github

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    func requestCode() async throws -> DeviceCode {
        let data = try await post("/login/device/code", form: ["client_id": AppConfig.githubClientID])
        guard let response = try? Self.decoder.decode(DeviceCodeResponse.self, from: data),
              Self.isPlausibleUserCode(response.userCode),
              !response.deviceCode.isEmpty, response.deviceCode.utf8.count < 256
        else { throw DeviceFlowError.invalidResponse }
        return DeviceCode(
            deviceCode: response.deviceCode,
            userCode: response.userCode,
            expiresAt: Date().addingTimeInterval(TimeInterval(min(max(response.expiresIn, 60), 1800))),
            interval: min(max(response.interval, 5), 60)
        )
    }

    func pollForToken(_ code: DeviceCode) async throws -> String {
        var interval = code.interval
        while Date() < code.expiresAt {
            try await Task.sleep(for: .seconds(interval))
            let data = try await post("/login/oauth/access_token", form: [
                "client_id": AppConfig.githubClientID,
                "device_code": code.deviceCode,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            ])
            guard let response = try? Self.decoder.decode(AccessTokenResponse.self, from: data) else {
                throw DeviceFlowError.invalidResponse
            }
            if let token = response.accessToken {
                guard GitHubToken.isWellFormed(token) else { throw DeviceFlowError.invalidResponse }
                return token
            }
            switch response.error {
            case "authorization_pending": continue
            case "slow_down": interval = min(max(response.interval ?? interval + 5, interval + 5), 60)
            case "expired_token": throw DeviceFlowError.expired
            case "access_denied": throw DeviceFlowError.denied
            default: throw DeviceFlowError.server(response.errorDescription ?? "Sign-in failed (\(response.error ?? "unknown error")).")
            }
        }
        throw DeviceFlowError.expired
    }

    private func post(_ path: String, form: [String: String]) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://\(AppConfig.webHost)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = form
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlUnreserved) ?? "")"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.host == AppConfig.webHost else {
            throw DeviceFlowError.invalidResponse
        }
        // GitHub reports flow errors as 200 + {"error": …}; other statuses are real failures.
        guard (200...299).contains(http.statusCode), data.count < 64 * 1024 else {
            throw DeviceFlowError.server("GitHub returned HTTP \(http.statusCode).")
        }
        return data
    }

    static func isPlausibleUserCode(_ code: String) -> Bool {
        (4...16).contains(code.count) && code.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}
