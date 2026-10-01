import SwiftUI

struct ReaderView: View {
    let nav: NavigationModel
    let treeOpen: Bool
    let onOpenTree: () -> Void
    let onClose: () -> Void
    let onOpenFile: (String) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Group {
                if let path = nav.current, model.vault.contains(path) {
                    if PathPolicy.kind(of: path) == .note {
                        NoteView(path: path).id(path)
                    } else {
                        AttachmentView(path: path, onOpen: onOpenFile).id(path)
                    }
                } else {
                    ContentUnavailable(
                        icon: "doc.questionmark",
                        title: "Note not found",
                        message: "It may have been moved or deleted in the vault."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Shad.background.ignoresSafeArea())
    }

    private var topBar: some View {
        ZStack {
            Text(breadcrumb)
                .font(Shad.font(14))
                .foregroundStyle(Shad.mutedForeground)
                .lineLimit(1)
                .truncationMode(.head)
                .padding(.horizontal, Shad.isMac ? 120 : 52)
            HStack(spacing: 2) {
                if !treeOpen { SidebarToggleButton(action: onOpenTree) }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Shad.mutedForeground)
                }
                .buttonStyle(.shad(.ghost, size: .icon))
                .accessibilityLabel("Close note")
                .help("Close note (⌘W)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, Shad.isMac ? 28 : 4)
        .padding(.bottom, 4)
        .frame(minHeight: 44)
    }

    private var breadcrumb: String {
        guard let path = nav.current else { return "" }
        var parts = PathPolicy.parentFolder(model.vault.displayPath(path)).split(separator: "/").map(String.init)
        parts.append(PathPolicy.displayName(path))
        return parts.joined(separator: " / ")
    }
}

struct ContentUnavailable: View {
    let icon: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Shad.mutedForeground)
                .padding(.bottom, 4)
            Text(title).font(Shad.font(16, .semibold)).foregroundStyle(Shad.foreground)
            if let message {
                Text(message)
                    .font(Shad.font(14))
                    .foregroundStyle(Shad.mutedForeground)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: 360)
    }
}

struct AttachmentView: View {
    let path: String
    let onOpen: (String) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(PathPolicy.lastComponent(path))
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(Shad.foreground)
                HStack(spacing: 8) {
                    ShadBadge(PathPolicy.fileExtension(path).uppercased(), variant: .outline)
                    if let size = model.sync.index.files[path]?.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(Shad.font(13))
                            .foregroundStyle(Shad.mutedForeground)
                    }
                }
                if PathPolicy.kind(of: path) == .image {
                    VaultImageView(url: URL(string: VaultURL.image(path, width: nil)))
                }
                Button {
                    onOpen(path)
                } label: {
                    Label("Open", systemImage: "eye")
                }
                .buttonStyle(.shad(.outline))
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
    }
}
