import Foundation

nonisolated enum NoteBlock: Sendable, Equatable {
    case markdown(String)
    case table(HTMLTable)
}

nonisolated struct PreprocessedNote: Sendable, Equatable {
    var blocks: [NoteBlock]
    var properties: [NoteProperty]
    var markdown: String {
        blocks.compactMap { block in
            if case .markdown(let text) = block { return text }
            return nil
        }.joined(separator: "\n\n")
    }
    var tags: [String] { Frontmatter.tags(from: properties) }
}

/// Rewrites Obsidian-flavoured Markdown into CommonMark that MarkdownUI understands.
///
/// | Obsidian                 | Output                                             |
/// |--------------------------|----------------------------------------------------|
/// | `---` frontmatter        | removed; returned as `properties`                  |
/// | `[[Note]]`, `[[N\|A]]`   | `[Note](vault://open?path=…)`                      |
/// | `[[Note#Heading]]`       | `[Note › Heading](vault://open?path=…&heading=…)`  |
/// | `![[img.png\|300]]`      | `![img.png](vault-file://image?path=…&w=300)`      |
/// | `![[Other note]]`        | `[↪ Other note](vault://open?path=…)`              |
/// | `![[file.pdf]]`          | `[📄 file.pdf](vault-file://open?path=…)`          |
/// | `> [!note] Title`        | `> ℹ️ **Title**`                                   |
/// | `==text==`               | `**text**`                                         |
/// | `%%comment%%`            | removed (also multi-line)                          |
/// | `$x$`, `$$…$$`           | inline code / ```math block (shown raw)            |
///
/// Fenced code blocks and inline code spans are passed through untouched.
/// The scanner is linear and regex-free, so hostile input can't trigger
/// catastrophic backtracking.
nonisolated struct ObsidianPreprocessor {
    let resolver: LinkResolver
    let currentPath: String?

    func process(_ source: String) -> PreprocessedNote {
        var text = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let (body, yaml) = Frontmatter.split(text)
        let properties = yaml.map(Frontmatter.parse) ?? []

        var output: [String] = []
        var textLines = Set<Int>()   // lines eligible for Obsidian-style hard line breaks
        var tableAt: [Int: HTMLTable] = [:]   // output line index -> parsed <table>
        var htmlBuffer: [String]?
        var fence: Fence?
        var inMath = false
        var inComment = false

        for rawLine in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)

            if htmlBuffer != nil {
                htmlBuffer?.append(line)
                let html = htmlBuffer!.joined(separator: "\n").lowercased()
                if html.components(separatedBy: "</table").count > html.components(separatedBy: "<table").count - 1 {
                    flushTable(htmlBuffer!, into: &output, tables: &tableAt)
                    htmlBuffer = nil
                }
                continue
            }
            if let open = fence {
                output.append(line)
                if open.isClosed(by: line) { fence = nil }
                continue
            }
            if inMath {
                if let end = line.range(of: "$$") {
                    let before = line[..<end.lowerBound]
                    if !before.trimmingCharacters(in: .whitespaces).isEmpty { output.append(String(before)) }
                    output.append("```")
                    inMath = false
                } else {
                    output.append(line)
                }
                continue
            }
            if !inComment {
                if let open = Fence(opening: line) {
                    fence = open
                    output.append(line)
                    continue
                }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("$$") {
                    let rest = trimmed.dropFirst(2)
                    output.append("```math")
                    if let end = rest.range(of: "$$") {
                        output.append(rest[..<end.lowerBound].trimmingCharacters(in: .whitespaces))
                        output.append("```")
                    } else {
                        if !rest.trimmingCharacters(in: .whitespaces).isEmpty { output.append(String(rest)) }
                        inMath = true
                    }
                    continue
                }
                if trimmed.lowercased().hasPrefix("<table") {
                    let lower = trimmed.lowercased()
                    if lower.components(separatedBy: "</table").count > lower.components(separatedBy: "<table").count - 1 {
                        flushTable([line], into: &output, tables: &tableAt)
                    } else {
                        htmlBuffer = [line]
                    }
                    continue
                }
                if let callout = calloutHeader(line) {
                    output.append(contentsOf: callout)
                    continue
                }
            }

            let result = processInline(line, inComment: inComment)
            inComment = result.inComment
            if result.droppedEntireLine { continue }
            textLines.insert(output.count)
            output.append(Self.stripBlockID(result.text))
        }
        if let pending = htmlBuffer { flushTable(pending, into: &output, tables: &tableAt) }
        if inMath { output.append("```") }
        // Obsidian renders a single newline as a line break; CommonMark joins the lines.
        // Two trailing spaces turn it into a hard break when another text line follows.
        for index in textLines.sorted() where index + 1 < output.count && textLines.contains(index + 1) {
            let line = output[index]
            let next = output[index + 1].trimmingCharacters(in: .whitespaces)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty, !next.isEmpty, !line.hasSuffix("  ") {
                output[index] = line + "  "
            }
        }

        var blocks: [NoteBlock] = []
        var pending: [String] = []
        func flushMarkdown() {
            if pending.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                blocks.append(.markdown(pending.joined(separator: "\n")))
            }
            pending.removeAll()
        }
        for (index, line) in output.enumerated() {
            if let table = tableAt[index] {
                flushMarkdown()
                blocks.append(.table(table))
            } else {
                pending.append(line)
            }
        }
        flushMarkdown()
        return PreprocessedNote(blocks: blocks, properties: properties)
    }

    /// Parsed tables become their own block; unparseable HTML falls back to plain text.
    private func flushTable(_ lines: [String], into output: inout [String], tables: inout [Int: HTMLTable]) {
        if let table = HTMLTableParser.parse(lines.joined(separator: "\n")) {
            tables[output.count] = table
            output.append("")
        } else {
            output.append(contentsOf: lines)
        }
    }

    // MARK: - Inline scanner

    struct InlineResult {
        var text: String
        var inComment: Bool
        var droppedEntireLine: Bool
    }

    func processInline(_ line: String, inComment startInComment: Bool) -> InlineResult {
        let chars = Array(line)
        let n = chars.count
        var out = ""
        var i = 0
        var inComment = startInComment
        var removedComment = false

        func starts(_ pattern: String, at index: Int) -> Bool {
            var j = index
            for p in pattern {
                guard j < n, chars[j] == p else { return false }
                j += 1
            }
            return true
        }
        // Next-occurrence tables make every closer lookup O(1), keeping the scanner
        // linear even on lines full of unclosed `[[`, `==` or `%%`.
        func nextTable(_ a: Character, _ b: Character) -> [Int] {
            var table = Array(repeating: n, count: n + 1)
            var k = n - 2
            while k >= 0 {
                table[k] = (chars[k] == a && chars[k + 1] == b) ? k : table[k + 1]
                k -= 1
            }
            return table
        }
        let nextBrackets = nextTable("]", "]")
        let nextEquals = nextTable("=", "=")
        let nextPercent = nextTable("%", "%")
        func find(_ pattern: String, from start: Int) -> Int? {
            guard start < n else { return nil }
            let table = pattern == "]]" ? nextBrackets : pattern == "==" ? nextEquals : nextPercent
            return table[start] < n ? table[start] : nil
        }

        while i < n {
            if inComment {
                removedComment = true
                if let end = find("%%", from: i) {
                    i = end + 2
                    inComment = false
                } else {
                    i = n
                }
                continue
            }
            let c = chars[i]
            switch c {
            case "\\":
                out.append(c)
                if i + 1 < n { out.append(chars[i + 1]) }
                i += 2

            case "`":
                var run = 0
                while i + run < n, chars[i + run] == "`" { run += 1 }
                if let close = Self.findBacktickRun(chars, length: run, from: i + run) {
                    out.append(contentsOf: chars[i..<(close + run)])
                    i = close + run
                } else {
                    out.append(String(repeating: "`", count: run))
                    i += run
                }

            case "%" where starts("%%", at: i):
                inComment = true
                removedComment = true
                i += 2

            case "!" where starts("![[", at: i):
                if let end = find("]]", from: i + 3), end > i + 3 {
                    out += embed(String(chars[(i + 3)..<end]))
                    i = end + 2
                } else {
                    out.append(c)
                    i += 1
                }

            case "[" where starts("[[", at: i):
                if let end = find("]]", from: i + 2), end > i + 2 {
                    out += link(String(chars[(i + 2)..<end]))
                    i = end + 2
                } else {
                    out.append(c)
                    i += 1
                }

            case "=" where starts("==", at: i):
                if i + 2 < n, chars[i + 2] != " ", chars[i + 2] != "=",
                   let end = find("==", from: i + 3), chars[end - 1] != " " {
                    let inner = processInline(String(chars[(i + 2)..<end]), inComment: false).text
                    out += "**\(inner)**"
                    i = end + 2
                } else {
                    out += "=="
                    i += 2
                }

            case "$":
                if let (content, next) = Self.inlineMath(chars, at: i) {
                    out += Self.codeSpan(content)
                    i = next
                } else {
                    out.append(c)
                    i += 1
                }

            default:
                out.append(c)
                i += 1
            }
        }

        let dropped = removedComment && out.trimmingCharacters(in: .whitespaces).isEmpty
        return InlineResult(text: out, inComment: inComment, droppedEntireLine: dropped)
    }

    // MARK: - Links and embeds

    struct Wikilink {
        var target: String
        var heading: String?
        var alias: String?
    }

    static func parseWikilink(_ inner: String) -> Wikilink {
        var targetPart = inner
        var alias: String?
        if let pipe = inner.firstIndex(of: "|") {
            targetPart = String(inner[..<pipe])
            if targetPart.hasSuffix("\\") { targetPart.removeLast() }   // `\|` inside tables
            alias = String(inner[inner.index(after: pipe)...])
                .replacingOccurrences(of: "\\|", with: "|")
                .trimmingCharacters(in: .whitespaces)
            if alias?.isEmpty == true { alias = nil }
        }
        var heading: String?
        if let hash = targetPart.firstIndex(of: "#") {
            heading = targetPart[targetPart.index(after: hash)...].trimmingCharacters(in: .whitespaces)
            if heading?.isEmpty == true { heading = nil }
            targetPart = String(targetPart[..<hash])
        }
        return Wikilink(target: targetPart.trimmingCharacters(in: .whitespaces), heading: heading, alias: alias)
    }

    func link(_ inner: String) -> String {
        let wiki = Self.parseWikilink(inner)
        let headingLabel = wiki.heading.map { $0.hasPrefix("^") ? "" : $0 } ?? ""
        let display: String
        if let alias = wiki.alias {
            display = alias
        } else if wiki.target.isEmpty {
            display = headingLabel
        } else if !headingLabel.isEmpty {
            display = "\(wiki.target) › \(headingLabel)"
        } else {
            display = wiki.target
        }
        let text = Self.escape(display)

        if wiki.target.isEmpty {
            guard let currentPath else { return text }
            return "[\(text)](\(VaultURL.note(currentPath, heading: wiki.heading)))"
        }
        guard let path = resolver.resolve(wiki.target, from: currentPath) else {
            return "[\(text)](\(VaultURL.missingNote(wiki.target)))"
        }
        if PathPolicy.kind(of: path) == .note {
            return "[\(text)](\(VaultURL.note(path, heading: wiki.heading)))"
        }
        return "[\(text)](\(VaultURL.file(path)))"
    }

    func embed(_ inner: String) -> String {
        let wiki = Self.parseWikilink(inner)
        guard !wiki.target.isEmpty else { return "" }
        let path = resolver.resolve(wiki.target, from: currentPath)
        let kind: FileKind = path.map(PathPolicy.kind(of:))
            ?? (PathPolicy.fileExtension(wiki.target).isEmpty ? .note : PathPolicy.kind(of: wiki.target))

        switch kind {
        case .image:
            let width = wiki.alias.flatMap(Self.parseWidth)
            let alt = Self.escape(width == nil ? (wiki.alias ?? PathPolicy.lastComponent(wiki.target)) : PathPolicy.lastComponent(wiki.target))
            guard let path else { return "![\(alt)](\(VaultURL.missingImage(wiki.target)))" }
            return "![\(alt)](\(VaultURL.image(path, width: width)))"

        case .pdf, .other:
            let label = Self.escape(wiki.alias ?? PathPolicy.lastComponent(wiki.target))
            let icon = kind == .pdf ? "📄" : "📎"
            guard let path else { return "[\(icon) \(label)](\(VaultURL.missingNote(wiki.target)))" }
            return "[\(icon) \(label)](\(VaultURL.file(path)))"

        case .note:
            let base = path.map(PathPolicy.displayName) ?? wiki.target
            let label = Self.escape(wiki.alias ?? (wiki.heading.map { "\(base) › \($0)" } ?? base))
            guard let path else { return "[↪ \(label)](\(VaultURL.missingNote(wiki.target)))" }
            return "[↪ \(label)](\(VaultURL.note(path, heading: wiki.heading)))"
        }
    }

    // MARK: - Callouts

    func calloutHeader(_ line: String) -> [String]? {
        var index = line.startIndex
        var sawQuote = false
        while index < line.endIndex, line[index] == " " || line[index] == ">" {
            if line[index] == ">" { sawQuote = true }
            index = line.index(after: index)
        }
        guard sawQuote, line[index...].hasPrefix("[!") else { return nil }
        let typeStart = line.index(index, offsetBy: 2)
        guard let close = line[typeStart...].firstIndex(of: "]") else { return nil }
        let type = line[typeStart..<close].lowercased()
        guard (1...30).contains(type.count),
              type.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }

        var rest = line[line.index(after: close)...]
        if rest.first == "+" || rest.first == "-" { rest = rest.dropFirst() }
        let rawTitle = rest.trimmingCharacters(in: .whitespaces)
        let title = rawTitle.isEmpty
            ? Self.escape(type.prefix(1).uppercased() + type.dropFirst())
            : processInline(rawTitle, inComment: false).text

        let quote = line[..<index].trimmingCharacters(in: .whitespaces)
        return ["\(quote) \(Self.calloutIcon(type)) **\(title)**", quote]
    }

    static func calloutIcon(_ type: String) -> String {
        switch type {
        case "tip", "hint", "important": "💡"
        case "warning", "caution", "attention": "⚠️"
        case "danger", "error", "bug": "⛔"
        case "success", "check", "done": "✅"
        case "failure", "fail", "missing": "❌"
        case "question", "help", "faq": "❓"
        case "example": "📋"
        case "quote", "cite": "❝"
        case "abstract", "summary", "tldr": "📝"
        case "todo": "☑️"
        default: "ℹ️"
        }
    }

    // MARK: - Helpers

    static func parseWidth(_ alias: String) -> Int? {
        let first = alias.split(separator: "x", maxSplits: 1).first.map(String.init) ?? alias
        guard let width = Int(first.trimmingCharacters(in: .whitespaces)), (1...4000).contains(width) else { return nil }
        return width
    }

    static func findBacktickRun(_ chars: [Character], length: Int, from start: Int) -> Int? {
        var j = start
        while j < chars.count {
            if chars[j] == "`" {
                var run = 0
                while j + run < chars.count, chars[j + run] == "`" { run += 1 }
                if run == length { return j }
                j += run
            } else {
                j += 1
            }
        }
        return nil
    }

    /// Obsidian/Pandoc rule: `$` must hug its content and the closing `$` can't be
    /// followed by a digit, so "$5 and $10" stays plain text.
    static func inlineMath(_ chars: [Character], at i: Int) -> (String, Int)? {
        let n = chars.count
        let limit = min(n, i + 1000)   // bounded scan: no quadratic blow-up on many `$`
        if i + 1 < n, chars[i + 1] == "$" {
            var j = i + 2
            while j + 1 < limit {
                if chars[j] == "$", chars[j + 1] == "$", j > i + 2 { return (String(chars[(i + 2)..<j]), j + 2) }
                j += 1
            }
            return nil
        }
        guard i + 1 < n, !chars[i + 1].isWhitespace else { return nil }
        var j = i + 1
        while j < limit {
            if chars[j] == "$", chars[j - 1] != "\\", !chars[j - 1].isWhitespace, j > i + 1,
               !(j + 1 < n && chars[j + 1].isNumber) {
                return (String(chars[(i + 1)..<j]), j + 1)
            }
            j += 1
        }
        return nil
    }

    static func codeSpan(_ content: String) -> String {
        content.contains("`") ? "`` \(content) ``" : "`\(content)`"
    }

    /// Escapes characters that would otherwise change Markdown structure inside link text.
    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            if "\\[]*_`<>|".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// Drops trailing Obsidian block IDs like ` ^abc123`.
    static func stripBlockID(_ line: String) -> String {
        guard let caret = line.range(of: " ^", options: .backwards) else { return line }
        let id = line[caret.upperBound...]
        guard !id.isEmpty, id.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }) else { return line }
        return String(line[..<caret.lowerBound])
    }
}

private nonisolated struct Fence {
    let marker: Character
    let length: Int

    init?(opening line: String) {
        let leading = line.prefix { $0 == " " }
        guard leading.count <= 3 else { return nil }
        let rest = line.dropFirst(leading.count)
        guard let first = rest.first, first == "`" || first == "~" else { return nil }
        let run = rest.prefix { $0 == first }.count
        guard run >= 3 else { return nil }
        if first == "`", rest.dropFirst(run).contains("`") { return nil }
        marker = first
        length = run
    }

    func isClosed(by line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let run = trimmed.prefix { $0 == marker }.count
        return run >= length && run == trimmed.count
    }
}
