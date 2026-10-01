import QuickLook
import SwiftUI

struct MainView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var systemOpenURL
    @AppStorage(Prefs.confirmExternalLinks) private var confirmExternalLinks = true
    @SceneStorage("lastNote") private var lastNote = ""

    @State private var nav = NavigationModel()
    @State private var treeOpen = true
    @State private var showSettings = false
    @State private var previewURL: URL?
    @State private var pendingExternalURL: URL?
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 860
            ZStack(alignment: .leading) {
                if nav.current == nil {
                    folderPanel(closable: false)
                } else {
                    HStack(spacing: 0) {
                        if wide && treeOpen {
                            folderPanel(closable: true)
                                .frame(width: 300)
                                .transition(.move(edge: .leading))
                            ShadSeparator(vertical: true).ignoresSafeArea()
                        }
                        ReaderView(nav: nav, treeOpen: treeOpen, onOpenTree: { setTree(true) }, onClose: closeNote, onOpenFile: openFile)
                    }
                    if !wide && treeOpen {
                        folderPanel(closable: true)
                            .transition(.move(edge: .leading))
                            .zIndex(1)
                    }
                }
            }
        }
        .environment(\.openURL, OpenURLAction(handler: handle))
        .quickLookPreview($previewURL)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert(
            "Open external link?",
            isPresented: Binding(get: { pendingExternalURL != nil }, set: { if !$0 { pendingExternalURL = nil } }),
            presenting: pendingExternalURL
        ) { url in
            Button("Open") { systemOpenURL(url) }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            Text(url.absoluteString)
        }
        .background { shortcuts }
        .task {
            if nav.current == nil, !lastNote.isEmpty, model.vault.contains(lastNote) { nav.restore(lastNote) }
            #if DEBUG
            if DemoVault.isEnabled, let note = UserDefaults.standard.string(forKey: "demoNote"), !note.isEmpty {
                nav.open(note)
                treeOpen = UserDefaults.standard.bool(forKey: "demoTree")
            }
            #endif
            await model.syncIfNeeded()
            await model.loadUser()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.syncIfNeeded() } }
        }
        .onChange(of: nav.current) { _, path in lastNote = path ?? "" }
    }

    private func folderPanel(closable: Bool) -> some View {
        FolderPanel(
            nav: nav,
            showSettings: $showSettings,
            searchFocused: $searchFocused,
            closable: closable,
            onSelect: select,
            onClose: { setTree(false) }
        )
    }

    private func select(_ path: String) {
        searchFocused = false
        nav.open(path)
        setTree(false)
    }

    private func closeNote() {
        withAnimation(.snappy(duration: 0.28)) {
            nav.close()
            treeOpen = true
        }
    }

    private func setTree(_ open: Bool) {
        withAnimation(.snappy(duration: 0.28)) { treeOpen = open }
    }

    @ViewBuilder private var shortcuts: some View {
        Group {
            Button("Search") { setTree(true); searchFocused = true }.keyboardShortcut("k", modifiers: .command)
            Button("Toggle Folders") { if nav.current != nil { setTree(!treeOpen) } }.keyboardShortcut("\\", modifiers: .command)
            Button("Close Note") { if nav.current != nil { closeNote() } }.keyboardShortcut("w", modifiers: .command)
            Button("Back") { nav.goBack() }.keyboardShortcut("[", modifiers: .command)
            Button("Forward") { nav.goForward() }.keyboardShortcut("]", modifiers: .command)
            Button("Sync") { Task { await model.refresh() } }.keyboardShortcut("r", modifiers: .command)
            Button("Settings") { showSettings = true }.keyboardShortcut(",", modifiers: .command)
        }
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Links

    /// Every link tap in a note lands here. Only known schemes do anything:
    /// internal vault links navigate, web/mail links ask first, and everything else
    /// (`file:`, `javascript:`, `shortcuts:`, `tel:`, other apps' deep links…) is blocked.
    private func handle(_ url: URL) -> OpenURLAction.Result {
        let scheme = url.scheme?.lowercased() ?? ""
        let params = VaultURL.parameters(of: url)
        switch scheme {
        case VaultURL.noteScheme:
            if url.host() == "open", let path = params["path"], model.vault.contains(path) {
                nav.open(path)
            } else {
                model.toasts.show("“\(params["name"] ?? "Note")” doesn't exist yet", icon: "doc.questionmark")
            }
            return .handled

        case VaultURL.fileScheme:
            if url.host() == "open", let path = params["path"], model.vault.contains(path) {
                openFile(path)
            } else {
                model.toasts.show("“\(params["name"] ?? "File")” isn't in the vault", icon: "questionmark.folder")
            }
            return .handled

        case VaultURL.relativeScheme:
            guard let relative = VaultURL.relativePath(of: url),
                  let path = model.vault.resolver.resolve(relative, from: nil) else {
                model.toasts.show("That link points outside the vault", icon: "link.badge.plus")
                return .handled
            }
            if PathPolicy.kind(of: path) == .note { nav.open(path) } else { openFile(path) }
            return .handled

        case "http", "https", "mailto":
            let hasCredentials = url.user() != nil || url.password() != nil
            if confirmExternalLinks || hasCredentials || scheme == "http" {
                pendingExternalURL = url
                return .handled
            }
            return .systemAction(url)

        default:
            model.toasts.show("Blocked a “\(scheme.isEmpty ? "unknown" : scheme):” link", icon: "hand.raised")
            return .discarded
        }
    }

    private func openFile(_ path: String) {
        Task {
            do {
                let source = try await model.fileURL(path)
                previewURL = try PreviewFiles.prepare(source: source, displayName: PathPolicy.lastComponent(path))
            } catch {
                model.toasts.show((error as? LocalizedError)?.errorDescription ?? "Couldn't open the file", icon: "exclamationmark.triangle")
            }
        }
    }
}

struct SidebarToggleButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Shad.mutedForeground)
        }
        .buttonStyle(.shad(.ghost, size: .icon))
        .accessibilityLabel("Show folders")
        .help("Folders (⌘\\)")
    }
}
