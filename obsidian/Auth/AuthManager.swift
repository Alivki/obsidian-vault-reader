import Foundation
import Observation

@Observable
final class AuthManager {
    enum Phase: Equatable {
        case signedOut(message: String?)
        case requestingCode
        case awaitingUser(DeviceCode)
        case signedIn
    }

    private(set) var phase: Phase
    private(set) var token: String?
    private var flowTask: Task<Void, Never>?

    init() {
        // Keychain items survive app deletion on iOS, but UserDefaults don't.
        // A missing marker means this is a fresh install: discard any leftover token.
        if !UserDefaults.standard.bool(forKey: Prefs.installMarker) {
            KeychainStore.delete()
            UserDefaults.standard.set(true, forKey: Prefs.installMarker)
        }
        let token = KeychainStore.load()
        self.token = token
        self.phase = token == nil ? .signedOut(message: nil) : .signedIn
    }

    var client: GitHubClient? { token.map { GitHubClient(token: $0) } }

    func startSignIn() {
        flowTask?.cancel()
        phase = .requestingCode
        flowTask = Task {
            let flow = DeviceFlowClient()
            do {
                let code = try await flow.requestCode()
                phase = .awaitingUser(code)
                let token = try await flow.pollForToken(code)
                try KeychainStore.save(token)
                self.token = token
                phase = .signedIn
            } catch is CancellationError {
                // cancelled by the user
            } catch {
                phase = .signedOut(message: Self.describe(error))
            }
        }
    }

    func cancelSignIn() {
        flowTask?.cancel()
        flowTask = nil
        phase = .signedOut(message: nil)
    }

    func signOut(message: String? = nil) {
        flowTask?.cancel()
        flowTask = nil
        KeychainStore.delete()
        token = nil
        phase = .signedOut(message: message)
    }

    #if DEBUG
    func enableDemo() {
        token = "demo"
        phase = .signedIn
    }
    #endif

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.isOffline {
            return "You appear to be offline. Connect to the internet and try again."
        }
        return (error as? LocalizedError)?.errorDescription ?? "Sign-in failed. Please try again."
    }
}

nonisolated extension URLError {
    var isOffline: Bool {
        [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
         .timedOut, .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed].contains(code)
    }
}
