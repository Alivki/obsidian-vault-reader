import Foundation

nonisolated struct NoteProperty: Sendable, Equatable, Identifiable {
    let key: String
    let values: [String]
    let isList: Bool

    var id: String { key }
    var isTags: Bool { ["tags", "tag"].contains(key.lowercased()) }
    var isAliases: Bool { ["aliases", "alias"].contains(key.lowercased()) }
    var date: Date? { values.count == 1 ? Frontmatter.parseDate(values[0]) : nil }
}

/// Minimal, non-evaluating YAML reader for Obsidian properties:
/// `key: value`, `key: [a, b]`, and `key:` followed by `- item` lines.
/// Anchors, tags and other YAML features are deliberately not interpreted.
nonisolated enum Frontmatter {
    static let maxProperties = 50
    static let maxValues = 50
    static let maxValueLength = 500

    static func split(_ text: String) -> (body: String, yaml: ArraySlice<Substring>?) {
        guard text.hasPrefix("---\n") else { return (text, nil) }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let end = lines.indices.dropFirst().first(where: {
            let line = lines[$0].trimmingCharacters(in: .whitespaces)
            return line == "---" || line == "..."
        }) else { return (text, nil) }
        return (lines[(end + 1)...].joined(separator: "\n"), lines[1..<end])
    }

    static func parse(_ yaml: ArraySlice<Substring>) -> [NoteProperty] {
        var properties: [NoteProperty] = []
        var currentKey: String?
        var listValues: [String] = []
        var blockLines: [String]?

        func flush() {
            guard let key = currentKey else { return }
            if let block = blockLines {
                properties.append(NoteProperty(key: key, values: [clean(block.joined(separator: " "))].filter { !$0.isEmpty }, isList: false))
            } else {
                properties.append(NoteProperty(key: key, values: listValues, isList: true))
            }
            currentKey = nil
            listValues = []
            blockLines = nil
        }

        for raw in yaml {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indented = line.first == " " || line.first == "\t"

            if currentKey != nil {
                if blockLines != nil, indented {
                    blockLines?.append(trimmed)
                    continue
                }
                if blockLines == nil, trimmed == "-" || trimmed.hasPrefix("- ") {
                    if listValues.count < maxValues { listValues.append(clean(String(trimmed.dropFirst()))) }
                    continue
                }
                flush()
            }
            guard !indented, let colon = line.firstIndex(of: ":") else { continue }
            let key = clean(String(line[..<colon]))
            guard !key.isEmpty, key.count <= 80 else { continue }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            if value.isEmpty {
                currentKey = key
            } else if value == "|" || value == ">" || value == "|-" || value == ">-" {
                currentKey = key
                blockLines = []
            } else if value.hasPrefix("["), value.hasSuffix("]") {
                let items = value.dropFirst().dropLast().split(separator: ",").map { clean(String($0)) }.filter { !$0.isEmpty }
                properties.append(NoteProperty(key: key, values: Array(items.prefix(maxValues)), isList: true))
            } else {
                properties.append(NoteProperty(key: key, values: [clean(value)], isList: false))
            }
            if properties.count >= maxProperties { break }
        }
        flush()
        return Array(properties.prefix(maxProperties)).map { property in
            property.isTags
                ? NoteProperty(key: property.key, values: property.values.flatMap(splitTags), isList: true)
                : property
        }
    }

    static func tags(from properties: [NoteProperty]) -> [String] {
        var seen = Set<String>()
        return properties.filter(\.isTags).flatMap(\.values).filter { seen.insert($0.lowercased()).inserted }
    }

    private static func splitTags(_ value: String) -> [String] {
        value.split(whereSeparator: { $0 == " " || $0 == "," }).map { tag in
            var tag = String(tag)
            while tag.hasPrefix("#") { tag.removeFirst() }
            return tag
        }.filter { !$0.isEmpty && $0.count <= 64 }
    }

    static func clean(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
            value = String(value.dropFirst().dropLast())
        }
        value = value.filter { ch in !(ch.unicodeScalars.first.map { $0.value < 0x20 || (0x202A...0x202E).contains($0.value) } ?? false) }
        return String(value.prefix(maxValueLength))
    }

    static func parseDate(_ value: String) -> Date? {
        let value = value.trimmingCharacters(in: .whitespaces)
        guard value.count >= 10, value.count <= 30, value.first?.isNumber == true else { return nil }
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
