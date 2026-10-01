import Foundation
import Testing
@testable import obsidian

@MainActor
struct HTMLTableTests {
    static let plan = """
    <table class="plan">
    <tr><td colspan="5"><strong>Before:</strong> gather the materials</td></tr>
    <tr>
      <td>step one</td>
      <td rowspan="2">first line<br>second line</td>
      <td rowspan="2">alpha</td>
      <td rowspan="2">beta</td>
      <td rowspan="5">summary<br><strong>done</strong></td>
    </tr>
    <tr><td>step two</td></tr>
    <tr>
      <td>step three</td>
      <td rowspan="3">gamma</td>
      <td rowspan="3">delta</td>
      <td rowspan="3">epsilon</td>
    </tr>
    <tr><td>step four</td></tr>
    <tr><td>step five</td></tr>
    </table>
    """

    @Test func placesRowAndColumnSpans() throws {
        let table = try #require(HTMLTableParser.parse(Self.plan))
        #expect(table.rowCount == 6)
        #expect(table.columnCount == 5)
        let positions = table.cells.map { [$0.row, $0.column, $0.rowSpan, $0.columnSpan] }
        #expect(positions == [
            [0, 0, 1, 5],
            [1, 0, 1, 1], [1, 1, 2, 1], [1, 2, 2, 1], [1, 3, 2, 1], [1, 4, 5, 1],
            [2, 0, 1, 1],
            [3, 0, 1, 1], [3, 1, 3, 1], [3, 2, 3, 1], [3, 3, 3, 1],
            [4, 0, 1, 1],
            [5, 0, 1, 1],
        ])
        #expect(String(table.cells[2].content.characters) == "first line\nsecond line")
        #expect(String(table.cells[0].content.characters) == "Before: gather the materials")
    }

    @Test func preprocessorSplitsTableIntoItsOwnBlock() {
        let note = ObsidianPreprocessor(resolver: LinkResolver(paths: []), currentPath: nil)
            .process("# Plan\n\n" + Self.plan + "\n\nThe end")
        #expect(note.blocks.count == 3)
        if case .table(let table) = note.blocks[1] { #expect(table.columnCount == 5) } else { Issue.record("expected table") }
    }

    @Test func entitiesAndHostileInput() {
        #expect(HTMLTableParser.decodeEntities("a &amp; b &#8594; &#x41; &bogus; &#0;") == "a & b → A &bogus; &#0;")
        #expect(HTMLTableParser.parse("<table><tr><td rowspan=999999 colspan=-4>x</td></tr></table>")?.cells.first?.columnSpan == 1)
        #expect(HTMLTableParser.parse("<table><script>alert(1)</script></table>") == nil)
        #expect(HTMLTableParser.parse(String(repeating: "<td>", count: 10_000)) != nil)
    }

    @Test func wrapperFolderIsUnwrapped() {
        let vault = VaultStore()
        vault.rebuild(paths: ["Vault/Projects/a.md", "Vault/b.md"])
        #expect(vault.tree.map(\.name) == ["Projects", "b.md"])
        #expect(vault.displayPath("Vault/Projects/a.md") == "Projects/a.md")
        #expect(vault.resolver.resolve("a", from: nil) == "Vault/Projects/a.md")
    }

    @Test func iconizeConfig() {
        let json = Data(#"{"settings":{"rules":[{"rule":"^\\d{4}-\\d{2}$","icon":"LiCalendarDays","for":"folders","order":0},{"rule":"draft","icon":"LiPen","for":"files","order":1}]},"Projects":"LiPenTool","x":"🎁","y":"LiNotARealIcon"}"#.utf8)
        let icons = FolderIcons.parseConfig(json, configPath: "Vault/.obsidian/plugins/obsidian-icon-folder/data.json")
        #expect(icons.icon(forFolder: "Vault/Projects") == .symbol("pencil.tip.crop.circle"))
        #expect(icons.icon(forFolder: "Vault/Journal/2025-01") == .symbol("calendar"))
        #expect(icons.icon(forFolder: "Vault/x") == .emoji("🎁"))
        #expect(icons.icon(forFolder: "Vault/y") == .symbol("folder"))
        #expect(icons.icon(forFolder: "Vault/Areas") == nil)
        #expect(icons.icon(forFolder: "Vault/drafts") == nil)
        #expect(FolderIcons.isConfigPath(".obsidian/plugins/obsidian-icon-folder/data.json"))
        #expect(!FolderIcons.isConfigPath("a/b/.obsidian/plugins/obsidian-icon-folder/data.json"))
        #expect(FolderIcons.leadsToConfig("Vault/.obsidian/plugins"))
        #expect(!FolderIcons.leadsToConfig(".git/objects"))
    }
}
