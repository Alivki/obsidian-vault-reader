import Foundation

/// A table parsed from raw `<table>` HTML in a note (MarkdownUI doesn't render HTML).
nonisolated struct HTMLTable: Sendable, Equatable {
    struct Cell: Sendable, Equatable {
        var content: AttributedString
        var row: Int
        var column: Int
        var rowSpan: Int
        var columnSpan: Int
        var isHeader: Bool
    }

    var cells: [Cell]
    var rowCount: Int
    var columnCount: Int
}

/// Tiny, non-executing HTML reader that understands only table structure
/// (`table/tr/td/th` + `rowspan/colspan`) and inline formatting
/// (`strong/b/em/i/code/br/p`). Everything else is ignored as plain text;
/// nothing is fetched, styled or run. Input size, cell count and spans are capped.
nonisolated enum HTMLTableParser {
    static let maxBytes = 200_000
    static let maxCells = 2_000
    static let maxSpan = 50

    static func parse(_ html: String) -> HTMLTable? {
        guard html.utf8.count <= maxBytes else { return nil }
        var rows: [[RawCell]] = []
        var row: [RawCell]?
        var cell: RawCell?
        var bold = 0, italic = 0, code = 0
        var depth = 0
        var cellCount = 0

        func closeCell() {
            guard var finished = cell else { return }
            finished.finish()
            if row == nil { row = [] }
            row?.append(finished)
            cell = nil
        }
        func closeRow() {
            closeCell()
            if let finished = row, !finished.isEmpty { rows.append(finished) }
            row = nil
        }

        for token in tokenize(html) {
            switch token {
            case .text(let text):
                cell?.append(text, bold: bold > 0, italic: italic > 0, code: code > 0)
            case .tag(let name, let closing, let attributes):
                // Nested tables are flattened into the outer cell's text.
                if name == "table" { depth += closing ? -1 : 1; continue }
                if depth > 1, ["tr", "td", "th"].contains(name) { continue }
                switch name {
                case "tr":
                    closeRow()
                    if !closing { row = [] }
                case "td", "th":
                    closeCell()
                    guard !closing, cellCount < maxCells else { continue }
                    cellCount += 1
                    cell = RawCell(
                        isHeader: name == "th",
                        rowSpan: span(attributes["rowspan"]),
                        columnSpan: span(attributes["colspan"])
                    )
                case "br": cell?.lineBreak()
                case "p", "div", "li", "ul", "ol": cell?.softBreak()
                case "strong", "b": bold = max(0, bold + (closing ? -1 : 1))
                case "em", "i": italic = max(0, italic + (closing ? -1 : 1))
                case "code": code = max(0, code + (closing ? -1 : 1))
                default: continue
                }
            }
        }
        closeRow()
        return layout(rows)
    }

    private static func span(_ value: String?) -> Int {
        guard let value, let number = Int(value.trimmingCharacters(in: .whitespaces)) else { return 1 }
        return min(max(number, 1), maxSpan)
    }

    /// Standard HTML grid placement: each cell takes the next free slot in its row,
    /// and row-spanning cells reserve slots in the rows below.
    private static func layout(_ rows: [[RawCell]]) -> HTMLTable? {
        guard !rows.isEmpty else { return nil }
        var occupied = Set<Int>()   // row * 1000 + column
        var cells: [HTMLTable.Cell] = []
        var columnCount = 0
        for (r, rowCells) in rows.enumerated() {
            var column = 0
            for raw in rowCells {
                while occupied.contains(r * 1000 + column) { column += 1 }
                let rowSpan = min(raw.rowSpan, rows.count - r)
                let columnSpan = min(raw.columnSpan, 999 - column)
                guard columnSpan > 0 else { break }
                for dr in 0..<rowSpan {
                    for dc in 0..<columnSpan { occupied.insert((r + dr) * 1000 + column + dc) }
                }
                cells.append(HTMLTable.Cell(content: raw.text, row: r, column: column, rowSpan: rowSpan,
                                            columnSpan: columnSpan, isHeader: raw.isHeader))
                column += columnSpan
                columnCount = max(columnCount, column)
            }
        }
        guard !cells.isEmpty, columnCount > 0 else { return nil }
        return HTMLTable(cells: cells, rowCount: rows.count, columnCount: columnCount)
    }

    // MARK: - Cells

    private struct RawCell {
        let isHeader: Bool
        let rowSpan: Int
        let columnSpan: Int
        var text = AttributedString()
        private var atLineStart = true
        private var pendingSpace = false

        init(isHeader: Bool, rowSpan: Int, columnSpan: Int) {
            self.isHeader = isHeader
            self.rowSpan = rowSpan
            self.columnSpan = columnSpan
        }

        /// HTML whitespace rules: runs collapse to one space, leading space per line is dropped.
        mutating func append(_ raw: String, bold: Bool, italic: Bool, code: Bool) {
            var collapsed = ""
            for character in raw {
                if character.isWhitespace {
                    pendingSpace = true
                } else {
                    if pendingSpace, !atLineStart { collapsed.append(" ") }
                    pendingSpace = false
                    atLineStart = false
                    collapsed.append(character)
                }
            }
            guard !collapsed.isEmpty else { return }
            var run = AttributedString(collapsed)
            var intent: InlinePresentationIntent = []
            if bold || isHeader { intent.insert(.stronglyEmphasized) }
            if italic { intent.insert(.emphasized) }
            if code { intent.insert(.code) }
            if !intent.isEmpty { run.inlinePresentationIntent = intent }
            text += run
        }

        mutating func lineBreak() {
            text += AttributedString("\n")
            atLineStart = true
            pendingSpace = false
        }

        mutating func softBreak() {
            if !atLineStart { lineBreak() }
        }

        mutating func finish() {
            while let last = text.characters.last, last == "\n" {
                text.removeSubrange(text.characters.index(before: text.endIndex)..<text.endIndex)
            }
        }
    }

    // MARK: - Tokenizer

    enum Token: Equatable {
        case text(String)
        case tag(name: String, closing: Bool, attributes: [String: String])
    }

    static func tokenize(_ html: String) -> [Token] {
        let chars = Array(html)
        let n = chars.count
        var tokens: [Token] = []
        var text = ""
        var i = 0

        func flush() {
            if !text.isEmpty { tokens.append(.text(decodeEntities(text))) }
            text = ""
        }

        while i < n {
            guard chars[i] == "<" else {
                text.append(chars[i])
                i += 1
                continue
            }
            if i + 3 < n, chars[i + 1] == "!", chars[i + 2] == "-", chars[i + 3] == "-" {
                var j = i + 4
                while j + 2 < n, !(chars[j] == "-" && chars[j + 1] == "-" && chars[j + 2] == ">") { j += 1 }
                i = min(j + 3, n)
                continue
            }
            guard let close = chars[(i + 1)...].firstIndex(of: ">") else {
                text.append(contentsOf: chars[i...])
                break
            }
            var inner = String(chars[(i + 1)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
            let closing = inner.hasPrefix("/")
            if closing { inner.removeFirst() }
            if inner.hasSuffix("/") { inner.removeLast() }
            let name = String(inner.prefix { $0.isLetter || $0.isNumber }).lowercased()
            if name.isEmpty || !(name.first?.isLetter ?? false) {
                text.append(contentsOf: chars[i...close])   // not a tag: keep literally
            } else {
                flush()
                tokens.append(.tag(name: name, closing: closing, attributes: parseAttributes(String(inner.dropFirst(name.count)))))
            }
            i = close + 1
        }
        flush()
        return tokens
    }

    private static func parseAttributes(_ source: String) -> [String: String] {
        var attributes: [String: String] = [:]
        let chars = Array(source)
        var i = 0
        while i < chars.count, attributes.count < 20 {
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            let start = i
            while i < chars.count, !chars[i].isWhitespace, chars[i] != "=" { i += 1 }
            let name = String(chars[start..<i]).lowercased()
            while i < chars.count, chars[i].isWhitespace { i += 1 }
            var value = ""
            if i < chars.count, chars[i] == "=" {
                i += 1
                while i < chars.count, chars[i].isWhitespace { i += 1 }
                if i < chars.count, chars[i] == "\"" || chars[i] == "'" {
                    let quote = chars[i]
                    i += 1
                    let valueStart = i
                    while i < chars.count, chars[i] != quote { i += 1 }
                    value = String(chars[valueStart..<min(i, chars.count)])
                    i += 1
                } else {
                    let valueStart = i
                    while i < chars.count, !chars[i].isWhitespace { i += 1 }
                    value = String(chars[valueStart..<i])
                }
            }
            if !name.isEmpty { attributes[name] = value }
            if i == start { i += 1 }
        }
        return attributes
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "mdash": "—", "ndash": "–", "hellip": "…", "rarr": "→", "larr": "←", "deg": "°",
        "times": "×", "middot": "·", "bull": "•", "laquo": "«", "raquo": "»",
        "aelig": "æ", "oslash": "ø", "aring": "å", "AElig": "Æ", "Oslash": "Ø", "Aring": "Å",
    ]

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&", let semicolon = text[i...].prefix(12).firstIndex(of: ";") {
                let name = String(text[text.index(after: i)..<semicolon])
                if let replacement = namedEntities[name] ?? numericEntity(name) {
                    out += replacement
                    i = text.index(after: semicolon)
                    continue
                }
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return out
    }

    private static func numericEntity(_ name: String) -> String? {
        guard name.hasPrefix("#") else { return nil }
        let body = name.dropFirst()
        let value = body.lowercased().hasPrefix("x") ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
        guard let value, value >= 0x20, let scalar = Unicode.Scalar(value),
              !(0x202A...0x202E).contains(value), !(0x2066...0x2069).contains(value) else { return nil }
        return String(Character(scalar))
    }
}
