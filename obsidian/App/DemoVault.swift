#if DEBUG
import Foundation

/// DEBUG-only: launch with `-demoVault` to explore the UI with sample notes
/// and no GitHub account. Compiled out of release builds.
enum DemoVault {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demoVault") }

    static let notes: [String: String] = [
        "Inbox/Quick capture.md": "# Quick capture\nLoose ideas go here.",
        "Projects/Website redesign.md": """
        ---
        title: Website redesign
        owner:
          - Sample Author
        aliases:
        created: 2025-03-14T09:30
        status: in progress
        tags:
          - example
        ---
        # Website redesign
        ## Goals
        https://example.com
        Simplify navigation and make every page readable on small screens. See the kickoff in [[2025-01-06]] and the ==open questions== below.

        > [!tip] Reminder
        > Check contrast in dark mode.

        ```swift
        let x = "[[not a link]]"
        ```

        | Task | Status |
        |---|---|
        | Wireframes | Done |
        | [[Pancakes\\|Sample link]] | – |
        """,
        "Areas/Cooking/Pancakes.md": "# Pancakes\n- [x] Flour\n- [ ] Milk\n- [ ] Eggs",
        "Areas/Cooking/Weekly plan.md": """
        # Weekly plan
        <table>
        <tr><td colspan="4"><strong>Prep day:</strong> wash vegetables and cook grains for the week</td></tr>
        <tr>
          <td>Monday</td>
          <td rowspan="2">soup<br>bread</td>
          <td rowspan="2">salad<br>leftovers</td>
          <td rowspan="4">fruit<br>→ yogurt<br>→ nuts<br><strong>drink water</strong></td>
        </tr>
        <tr><td>Tuesday</td></tr>
        <tr>
          <td>Wednesday</td>
          <td rowspan="2">pasta</td>
          <td rowspan="2">curry<br>rice</td>
        </tr>
        <tr><td>Thursday</td></tr>
        </table>

        Enjoy.
        """,
        "Areas/Math/Linear algebra.md": "# Linear algebra\nInline $a^2 + b^2$.",
        "Areas/Programming/Swift.md": "# Swift",
        "Areas/Reading/Book list.md": "# Book list",
        "Journal/2025-01/2025-01-06.md": "# 2025-01-06\nBack to [[Website redesign]].",
        "Journal/2025-01/2025-01-07.md": "# 2025-01-07",
        "Journal/2025-02/2025-02-01.md": "# 2025-02-01",
        "Tasks/Errands.md": "# Errands",
        "Courses/Intro to databases.md": "# Intro to databases",
        "Archive/Old notes.md": "# Old notes",
        "Templates/Daily.md": "# Daily template",
        ".obsidian/plugins/obsidian-icon-folder/data.json": #"{"settings":{"rules":[{"rule":"^\\d{4}-\\d{2}$","icon":"LiCalendar","for":"folders","order":0}]},"Projects":"LiPenTool","Areas":"LiLibrary","Journal":"LiCalendar","Tasks":"LiClipboardCheck","Courses":"LiGraduationCap","Archive":"LiArchive"}"#,
    ]

    static func makeStore() -> (BlobStore, LocalIndex) {
        let store = BlobStore(root: FileManager.default.temporaryDirectory.appending(path: "DemoVault"))
        store.removeAll()
        try? store.prepare()
        var index = LocalIndex()
        index.branch = "main"
        index.lastSync = Date().addingTimeInterval(-120)
        for (path, text) in notes {
            let path = "Vault/" + path
            let data = Data(text.utf8)
            let sha = BlobStore.gitBlobHash(of: data)
            try? store.write(data, sha: sha, path: path)
            index.files[path] = IndexEntry(sha: sha, size: data.count, localSha: sha)
        }
        try? index.save(to: store.indexURL)
        return (store, index)
    }
}
#endif
