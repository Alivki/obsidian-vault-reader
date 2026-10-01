import SwiftUI

struct FolderPanel: View {
    let nav: NavigationModel
    @Binding var showSettings: Bool
    var searchFocused: FocusState<Bool>.Binding
    let closable: Bool
    let onSelect: (String) -> Void
    let onClose: () -> Void

    @Environment(AppModel.self) private var model
    @SceneStorage("expandedFolders") private var expandedStorage = ""
    @State private var query = ""

    private var expanded: Set<String> {
        Set(expandedStorage.split(separator: "\n").map(String.init))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if closable {
                    SidebarToggleButton(action: onClose)
                }
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(Shad.mutedForeground)
                }
                .buttonStyle(.shad(.ghost, size: .icon))
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 10)
            .padding(.top, Shad.isMac ? 28 : 4)
            .frame(maxWidth: 600)

            ShadSearchField(text: $query, focus: searchFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: 600)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        searchResults
                    } else if model.vault.tree.isEmpty {
                        emptyState
                    } else {
                        ForEach(visibleRows) { row in
                            TreeRow(
                                node: row.node,
                                depth: row.depth,
                                isExpanded: expanded.contains(row.node.path),
                                isSelected: nav.current == row.node.path,
                                icon: row.node.isFolder ? model.vault.folderIcons.icon(forFolder: row.node.path) : nil
                            ) { tap(row.node) }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: 600, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await model.refresh(force: true) }

            SyncStatusBar()
                .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Shad.sidebar.ignoresSafeArea())
        .onAppear {
            revealCurrent()
            #if DEBUG
            if DemoVault.isEnabled, let folders = UserDefaults.standard.string(forKey: "demoExpand") {
                expandedStorage = folders.replacingOccurrences(of: ",", with: "\n")
            }
            #endif
        }
    }

    // MARK: - Rows

    private struct Row: Identifiable {
        let node: FileNode
        let depth: Int
        var id: String { node.path }
    }

    private var visibleRows: [Row] {
        var rows: [Row] = []
        let expanded = expanded
        func walk(_ nodes: [FileNode], depth: Int) {
            for node in nodes {
                rows.append(Row(node: node, depth: depth))
                if node.isFolder, expanded.contains(node.path) { walk(node.children, depth: depth + 1) }
            }
        }
        walk(model.vault.tree, depth: 0)
        return rows
    }

    private func tap(_ node: FileNode) {
        if node.isFolder {
            var set = expanded
            if set.contains(node.path) { set.remove(node.path) } else { set.insert(node.path) }
            withAnimation(.easeOut(duration: 0.15)) { expandedStorage = set.sorted().joined(separator: "\n") }
        } else {
            onSelect(node.path)
        }
    }

    private func revealCurrent() {
        guard let current = nav.current else { return }
        var set = expanded
        var folder = PathPolicy.parentFolder(current)
        while !folder.isEmpty {
            set.insert(folder)
            folder = PathPolicy.parentFolder(folder)
        }
        expandedStorage = set.sorted().joined(separator: "\n")
    }

    @ViewBuilder private var searchResults: some View {
        let results = model.vault.search(query)
        if results.isEmpty {
            Text("No matching notes")
                .font(Shad.font(14))
                .foregroundStyle(Shad.mutedForeground)
                .padding(16)
        } else {
            ForEach(results, id: \.self) { path in
                SearchRow(path: path, vaultDisplayPath: model.vault.displayPath, isSelected: nav.current == path) {
                    query = ""
                    onSelect(path)
                }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.sync.isSyncing {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<8, id: \.self) { index in
                    Skeleton(width: [180, 140, 200, 120, 160, 190, 110, 150][index], height: 14)
                }
            }
            .padding(14)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "folder")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Shad.mutedForeground)
                Text("No notes yet").font(Shad.font(15, .semibold))
                Text("Pull to refresh or sync to download your vault.")
                    .font(Shad.font(13.5))
                    .foregroundStyle(Shad.mutedForeground)
                    .multilineTextAlignment(.center)
                Button("Sync now") { Task { await model.refresh() } }
                    .buttonStyle(.shad(.outline, size: .sm))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 48)
        }
    }
}

// MARK: - Tree row

private struct TreeRow: View {
    let node: FileNode
    let depth: Int
    let isExpanded: Bool
    let isSelected: Bool
    let icon: FolderIconKind?
    let action: () -> Void

    @State private var hovering = false
    private static let indent: CGFloat = 18
    private static let leading: CGFloat = 8
    private static let chevronWidth: CGFloat = 14

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Group {
                    if node.isFolder {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Shad.mutedForeground)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    } else {
                        Color.clear
                    }
                }
                .frame(width: Self.chevronWidth)

                switch icon {
                case .symbol(let name):
                    Image(systemName: name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Shad.icon)
                        .frame(width: 18)
                case .emoji(let emoji):
                    Text(emoji).font(.system(size: 14)).frame(width: 18)
                case nil:
                    EmptyView()
                }
                Text(node.displayName)
                    .font(Shad.font(Shad.isMac ? 14 : 16))
                    .foregroundStyle(isSelected ? Shad.foreground : Shad.treeText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.leading, Self.leading + CGFloat(depth) * Self.indent)
            .padding(.trailing, 8)
            .frame(height: Shad.isMac ? 30 : 38)
            .background(
                RoundedRectangle(cornerRadius: Shad.radiusSmall)
                    .fill(isSelected ? Shad.sidebarAccent : hovering ? Shad.sidebarAccent.opacity(0.6) : .clear)
            )
            .overlay(alignment: .leading) { guides.allowsHitTesting(false) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(node.isFolder ? "\(node.displayName) folder" : node.displayName)
        .accessibilityValue(node.isFolder ? (isExpanded ? "expanded" : "collapsed") : "")
    }

    private var guides: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<depth, id: \.self) { level in
                Rectangle()
                    .fill(Shad.treeGuide)
                    .frame(width: 1)
                    .offset(x: Self.leading + CGFloat(level) * Self.indent + Self.chevronWidth / 2)
            }
        }
    }
}

private struct SearchRow: View {
    let path: String
    let vaultDisplayPath: (String) -> String
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PathPolicy.displayName(path))
                    .font(Shad.font(Shad.isMac ? 14 : 16, .medium))
                    .foregroundStyle(Shad.foreground)
                    .lineLimit(1)
                let folder = PathPolicy.parentFolder(vaultDisplayPath(path))
                if !folder.isEmpty {
                    Text(folder.replacingOccurrences(of: "/", with: " / "))
                        .font(Shad.font(12.5))
                        .foregroundStyle(Shad.mutedForeground)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Shad.radiusSmall)
                    .fill(isSelected || hovering ? Shad.sidebarAccent : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Sync status

struct SyncStatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            VStack(spacing: 1) {
                HStack(spacing: 6) {
                    if model.sync.isSyncing { ProgressView().controlSize(.mini) }
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(Shad.foreground)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Shad.mutedForeground)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, Shad.isMac ? 10 : 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if case .failed = model.sync.status { Task { await model.refresh() } }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var title: String {
        switch model.sync.status {
        case .checking: return "Checking for Changes…"
        case .downloading(let done, let total): return "Downloading \(done) of \(total)…"
        case .offline: return "Offline"
        case .failed: return "Couldn’t Update"
        case .upToDate, .idle:
            guard let last = model.sync.index.lastSync else { return "Not Updated Yet" }
            if Date().timeIntervalSince(last) < 60 { return "Updated Just Now" }
            return "Updated \(last.formatted(.relative(presentation: .named)))"
        }
    }

    private var subtitle: String? {
        switch model.sync.status {
        case .offline: return "Showing saved notes"
        case .failed(let message): return message
        case .checking, .downloading: return nil
        case .upToDate, .idle:
            let count = model.vault.noteCount
            return count == 0 ? nil : "\(count) note\(count == 1 ? "" : "s")"
        }
    }
}
