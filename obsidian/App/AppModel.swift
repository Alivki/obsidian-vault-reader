import Foundation
import Observation

@Observable
final class AppModel {
    let auth = AuthManager()
    let vault = VaultStore()
    let sync: SyncEngine
    let toasts = ToastCenter()
    let images: VaultImageLoader
    private(set) var user: GitHubUser?
    private var lastAutoSync: Date?

    init() {
        #if DEBUG
        let sync = DemoVault.isEnabled ? SyncEngine(store: DemoVault.makeStore().0) : SyncEngine()
        if DemoVault.isEnabled { auth.enableDemo() }
        #else
        let sync = SyncEngine()
        #endif
        self.sync = sync
        images = VaultImageLoader(sync: sync, vault: vault, auth: auth)
        vault.rebuild(paths: sync.allPaths)
        sync.onFilesChanged = { [weak self] paths in self?.vault.rebuild(paths: paths) }
        sync.onUnauthorized = { [weak self] in self?.handleUnauthorized() }
        PreviewFiles.cleanUp()
        Task { await loadFolderIcons() }
    }

    func loadFolderIcons() async {
        guard let path = sync.index.files.keys.first(where: FolderIcons.isConfigPath),
              let url = try? await sync.localURL(for: path, client: auth.client),
              let data = try? Data(contentsOf: url) else { return }
        vault.folderIcons = FolderIcons.parseConfig(data, configPath: path)
    }

    /// Launch / foreground sync, throttled so quick app switches don't hit the API.
    func syncIfNeeded() async {
        guard auth.token != nil else { return }
        if let last = lastAutoSync, Date().timeIntervalSince(last) < 30 { return }
        await refresh()
    }

    func refresh(force: Bool = false) async {
        #if DEBUG
        if DemoVault.isEnabled { return }
        #endif
        guard let client = auth.client else { return }
        lastAutoSync = Date()
        await sync.sync(client: client, force: force)
        await loadFolderIcons()
    }

    func redownloadEverything() async {
        sync.clearCache()
        images.clear()
        await refresh(force: true)
    }

    func loadUser() async {
        guard user == nil, let client = auth.client else { return }
        user = try? await client.user()
    }

    func noteText(_ path: String) async throws -> String {
        let url = try await sync.localURL(for: path, client: auth.client)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= AppConfig.maxNoteBytes else { throw GitHubError.tooLarge }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    func fileURL(_ path: String) async throws -> URL {
        try await sync.localURL(for: path, client: auth.client)
    }

    func signOutAndDeleteData() {
        auth.signOut()
        sync.clearCache()
        images.clear()
        user = nil
        lastAutoSync = nil
        PreviewFiles.cleanUp()
    }

    private func handleUnauthorized() {
        auth.signOut(message: GitHubError.unauthorized.errorDescription)
        user = nil
    }
}

/// Quick Look needs a real file name to pick a viewer, so attachments are copied
/// to a throwaway temp folder under a sanitized name.
enum PreviewFiles {
    static var directory: URL { FileManager.default.temporaryDirectory.appending(path: "Preview", directoryHint: .isDirectory) }

    static func prepare(source: URL, displayName: String) throws -> URL {
        cleanUp()
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: sanitize(displayName), directoryHint: .notDirectory)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    static func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func sanitize(_ name: String) -> String {
        let allowed = name.filter { $0.isLetter || $0.isNumber || " -_.()".contains($0) }
        let trimmed = String(allowed.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).prefix(120))
        return trimmed.isEmpty ? "file" : trimmed
    }
}
