import Testing
@testable import obsidian

@MainActor
struct PreprocessorTests {
    let resolver = LinkResolver(paths: [
        "Areas/Math/Linear Algebra.md",
        "Areas/Programming/Swift.md",
        "Projects/Swift.md",
        "attachments/diagram.png",
        "attachments/paper.pdf",
        "Home.md",
    ])

    func run(_ input: String, from path: String? = "Areas/Math/Notes.md") -> String {
        ObsidianPreprocessor(resolver: resolver, currentPath: path).process(input).markdown
    }

    @Test("Conversion table", arguments: [
        ("[[Home]]", "[Home](vault://open?path=Home.md)"),
        ("[[Home|Start here]]", "[Start here](vault://open?path=Home.md)"),
        ("[[Home#Intro]]", "[Home › Intro](vault://open?path=Home.md&heading=Intro)"),
        ("[[Missing note]]", "[Missing note](vault://missing?name=Missing%20note)"),
        ("![[diagram.png]]", "![diagram.png](vault-file://image?path=attachments%2Fdiagram.png)"),
        ("![[diagram.png|300]]", "![diagram.png](vault-file://image?path=attachments%2Fdiagram.png&w=300)"),
        ("![[paper.pdf]]", "[📄 paper.pdf](vault-file://open?path=attachments%2Fpaper.pdf)"),
        ("![[Home]]", "[↪ Home](vault://open?path=Home.md)"),
        ("==important==", "**important**"),
        ("a %%hidden%% b", "a  b"),
        ("price $5 and $10", "price $5 and $10"),
        ("energy $E=mc^2$ here", "energy `E=mc^2` here"),
        ("`[[not a link]]`", "`[[not a link]]`"),
        ("``code with ` tick [[x]]``", "``code with ` tick [[x]]``"),
        ("\\[[escaped]]", "\\[[escaped]]"),
        ("line ^block-id", "line"),
    ])
    func table(input: String, expected: String) {
        #expect(run(input) == expected)
    }

    @Test func fencedCodeBlocksAreUntouched() {
        let input = "```swift\nlet x = \"[[Home]]\" // ==no== %%no%%\n```\n[[Home]]"
        #expect(run(input) == "```swift\nlet x = \"[[Home]]\" // ==no== %%no%%\n```\n[Home](vault://open?path=Home.md)")
    }

    @Test func tildeFencesAndLongerClosers() {
        let input = "~~~~\n[[Home]]\n~~~\nstill code\n~~~~\n[[Home]]"
        let output = run(input).split(separator: "\n").map(String.init)
        #expect(output[1] == "[[Home]]")
        #expect(output[3] == "still code")
        #expect(output[5] == "[Home](vault://open?path=Home.md)")
    }

    @Test func singleNewlinesBecomeHardBreaks() {
        #expect(run("link\ntext\n\nnext") == "link  \ntext\n\nnext")
    }

    @Test func pipeInTableIsAnAliasNotACellBreak() {
        #expect(run("| [[Home\\|Start]] | x |") == "| [Start](vault://open?path=Home.md) | x |")
    }

    @Test func aliasWithMarkdownCharactersIsEscaped() {
        #expect(run("[[Home|a]b*c]]") == "[a\\]b\\*c](vault://open?path=Home.md)")
    }

    @Test func closestMatchWinsForDuplicateNames() {
        #expect(run("[[Swift]]", from: "Areas/Programming/Other.md") == "[Swift](vault://open?path=Areas%2FProgramming%2FSwift.md)")
        #expect(run("[[Swift]]", from: "Projects/Other.md") == "[Swift](vault://open?path=Projects%2FSwift.md)")
    }

    @Test func nestedFolderPathLinks() {
        #expect(run("[[Math/Linear Algebra]]") == "[Math/Linear Algebra](vault://open?path=Areas%2FMath%2FLinear%20Algebra.md)")
    }

    @Test func multiLineComments() {
        #expect(run("before\n%%\nsecret\n%%\nafter") == "before  \nafter")
    }

    @Test func calloutBecomesTitledQuote() {
        #expect(run("> [!warning] Careful\n> body") == "> ⚠️ **Careful**\n>\n> body")
        #expect(run("> [!tip]\n> body") == "> 💡 **Tip**\n>\n> body")
    }

    @Test func displayMathBecomesCodeBlock() {
        #expect(run("$$\na^2+b^2\n$$") == "```math\na^2+b^2\n```")
        #expect(run("$$x$$") == "```math\nx\n```")
    }

    @Test func frontmatterIsRemovedAndParsed() {
        let note = ObsidianPreprocessor(resolver: resolver, currentPath: nil).process("""
        ---
        title: sample-note
        author:
          - Sample Author
        aliases:
        created: 2025-03-14T09:30
        tags: [example, "#draft"]
        ---
        # Body
        """)
        #expect(note.markdown == "# Body")
        #expect(note.properties.map(\.key) == ["title", "author", "aliases", "created", "tags"])
        #expect(note.properties[1].values == ["Sample Author"])
        #expect(note.properties[2].values.isEmpty)
        #expect(note.properties[3].date != nil)
        #expect(note.tags == ["example", "draft"])
    }

    @Test func unterminatedConstructsStayLiteral() {
        #expect(run("[[unterminated") == "[[unterminated")
        #expect(run("![[") == "![[")
        #expect(run("==open") == "==open")
    }

    @Test func pathologicalInputIsFast() {
        let nasty = String(repeating: "[[a|", count: 20_000) + String(repeating: "$", count: 20_000)
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = run(nasty) }
        #expect(elapsed < .seconds(5))
    }
}
