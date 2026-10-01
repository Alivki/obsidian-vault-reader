import Observation

@Observable
final class NavigationModel {
    private(set) var current: String?
    private(set) var backStack: [String] = []
    private(set) var forwardStack: [String] = []
    private static let limit = 100

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func open(_ path: String) {
        guard path != current else { return }
        if let current {
            backStack.append(current)
            if backStack.count > Self.limit { backStack.removeFirst() }
        }
        current = path
        forwardStack.removeAll()
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current { forwardStack.append(current) }
        current = previous
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current { backStack.append(current) }
        current = next
    }

    func restore(_ path: String) {
        current = path
    }

    func close() {
        current = nil
        backStack.removeAll()
        forwardStack.removeAll()
    }
}
