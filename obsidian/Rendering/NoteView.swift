import MarkdownUI
import SwiftUI

struct NoteView: View {
    let path: String

    @Environment(AppModel.self) private var model
    @ScaledMetric(relativeTo: .body) private var bodySize: CGFloat = Shad.isMac ? 16 : 17
    @State private var state: LoadState = .loading

    private enum LoadState {
        case loading
        case loaded(PreprocessedNote)
        case failed(String)
    }

    /// Re-render when the note's content changes or new files make links resolvable.
    private var reloadKey: String {
        "\(model.sync.index.files[path]?.sha ?? "")|\(model.sync.index.files[path]?.localSha ?? "")|\(model.vault.files.count)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch state {
                case .loading:
                    VStack(alignment: .leading, spacing: 14) {
                        Skeleton(width: 280, height: 34).padding(.bottom, 12)
                        ForEach(0..<6, id: \.self) { _ in Skeleton(height: 14) }
                        Skeleton(width: 220, height: 14)
                    }
                    .padding(.top, 24)
                case .failed(let message):
                    ContentUnavailable(icon: "exclamationmark.triangle", title: "Couldn't open this note", message: message)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                case .loaded(let note):
                    if !note.properties.isEmpty {
                        PropertiesView(properties: note.properties)
                            .padding(.bottom, 44)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(note.blocks.enumerated()), id: \.offset) { _, block in
                            switch block {
                            case .markdown(let text):
                                Markdown(text, baseURL: VaultURL.baseURL(for: path), imageBaseURL: VaultURL.baseURL(for: path))
                            case .table(let table):
                                HTMLTableView(table: table, fontSize: bodySize)
                                    .padding(.top, 8)
                                    .padding(.bottom, 18)
                            }
                        }
                    }
                    .markdownTheme(.vault(bodySize: bodySize))
                    .markdownImageProvider(VaultImageProvider())
                    .markdownInlineImageProvider(VaultInlineImageProvider(loader: model.images))
                    .textSelection(.enabled)
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, Shad.isMac ? 40 : 22)
            .padding(.top, 24)
            .padding(.bottom, 96)
            .frame(maxWidth: .infinity)
        }
        .task(id: reloadKey) { await load() }
    }

    private func load() async {
        do {
            let text = try await model.noteText(path)
            let note = ObsidianPreprocessor(resolver: model.vault.resolver, currentPath: path).process(text)
            state = .loaded(note)
        } catch {
            if case .loaded = state { return }   // keep showing the cached render
            state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}

/// Obsidian-style "Properties" block rendered from the note's frontmatter.
struct PropertiesView: View {
    let properties: [NoteProperty]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Properties")
                .font(Shad.font(17, .semibold))
                .foregroundStyle(Shad.foreground)
                .padding(.bottom, 12)
            ForEach(properties) { property in
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: property))
                            .font(.system(size: 14))
                            .foregroundStyle(Shad.mutedForeground)
                            .frame(width: 18)
                        Text(property.key)
                            .font(Shad.font(15))
                            .foregroundStyle(Shad.mutedForeground)
                            .lineLimit(1)
                    }
                    .frame(width: Shad.isMac ? 150 : 130, alignment: .leading)
                    value(for: property)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func value(for property: NoteProperty) -> some View {
        if property.values.isEmpty || property.values.allSatisfy(\.isEmpty) {
            Text("Empty").font(Shad.font(15)).foregroundStyle(Shad.mutedForeground.opacity(0.8))
        } else if property.isTags {
            FlowLayout(spacing: 6) {
                ForEach(property.values, id: \.self) { tag in
                    Text(tag)
                        .font(Shad.font(14, .medium))
                        .foregroundStyle(Shad.tagForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Shad.tagBackground))
                }
            }
        } else if let date = property.date {
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.system(size: 13)).foregroundStyle(Shad.mutedForeground)
                Text(date.formatted(date: .numeric, time: property.values[0].count > 10 ? .shortened : .omitted))
                    .font(Shad.font(15).monospacedDigit())
                    .foregroundStyle(Shad.foreground)
            }
        } else {
            FlowLayout(spacing: 12) {
                ForEach(Array(property.values.enumerated()), id: \.offset) { _, value in
                    Text(Self.display(value))
                        .font(Shad.font(15))
                        .foregroundStyle(Shad.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func icon(for property: NoteProperty) -> String {
        if property.isTags { return "tag" }
        if property.isAliases { return "arrow.turn.up.right" }
        if property.date != nil { return "clock" }
        if property.values.count == 1, ["true", "false"].contains(property.values[0].lowercased()) { return "checkmark.square" }
        if property.values.count == 1, Double(property.values[0]) != nil { return "number" }
        return property.isList ? "list.bullet" : "text.alignleft"
    }

    /// `[[Note]]` → `Note` for display.
    static func display(_ value: String) -> String {
        guard value.hasPrefix("[["), value.hasSuffix("]]") else { return value }
        let inner = value.dropFirst(2).dropLast(2)
        return String(inner.split(separator: "|").last ?? inner)
    }
}
