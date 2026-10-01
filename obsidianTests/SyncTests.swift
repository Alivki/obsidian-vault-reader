import Foundation
import Testing
@testable import obsidian

@MainActor
struct SyncDiffTests {
    let a = String(repeating: "a", count: 40)
    let b = String(repeating: "b", count: 40)
    let c = String(repeating: "c", count: 40)

    @Test func addChangeDeleteRename() {
        let local: [String: IndexEntry] = [
            "same.md": IndexEntry(sha: a, size: 1, localSha: a),
            "changed.md": IndexEntry(sha: a, size: 1, localSha: a),
            "old-name.md": IndexEntry(sha: c, size: 1, localSha: c),
            "img.png": IndexEntry(sha: a, size: 1, localSha: a),
        ]
        let remote = [
            RemoteFile(path: "same.md", sha: a, size: 1),
            RemoteFile(path: "changed.md", sha: b, size: 1),
            RemoteFile(path: "new-name.md", sha: c, size: 1),
            RemoteFile(path: "img.png", sha: b, size: 1),
            RemoteFile(path: "new.jpg", sha: c, size: 1),
        ]
        let plan = SyncDiff.plan(remote: remote, local: local)
        #expect(plan.downloadNow.map(\.path) == ["changed.md", "new-name.md"])
        #expect(plan.markStale.map(\.path) == ["img.png", "new.jpg"])
        #expect(plan.removed == ["old-name.md"])
        #expect(plan.unchanged == 1)
    }

    @Test func missingLocalNoteIsRedownloaded() {
        let local = ["n.md": IndexEntry(sha: a, size: 1, localSha: nil)]
        let plan = SyncDiff.plan(remote: [RemoteFile(path: "n.md", sha: a, size: 1)], local: local)
        #expect(plan.downloadNow.map(\.path) == ["n.md"])
    }

    @Test func staleMediaStaysLazy() {
        let local = ["i.png": IndexEntry(sha: a, size: 1, localSha: nil)]
        let plan = SyncDiff.plan(remote: [RemoteFile(path: "i.png", sha: a, size: 1)], local: local)
        #expect(plan.downloadNow.isEmpty)
        #expect(plan.unchanged == 1)
    }
}

@MainActor
struct SecurityTests {
    @Test("Unsafe paths are rejected", arguments: [
        "../etc/passwd", "a/../../b", "/abs.md", "a//b.md", "./a.md", "a\\b.md",
        "evil\u{202E}dm.exe", "new\nline.md", "", "a/", "nul\u{0}.md",
    ])
    func unsafePaths(path: String) {
        #expect(!PathPolicy.isSafe(path))
    }

    @Test func safePaths() {
        #expect(PathPolicy.isSafe("Areas/Math/Linear Algebra.md"))
        #expect(PathPolicy.isSafe("ø/æ/å.md"))
    }

    @Test func ignoredPaths() {
        #expect(PathPolicy.isIgnored(".obsidian/app.json"))
        #expect(PathPolicy.isIgnored(".git/config"))
        #expect(PathPolicy.isIgnored("notes/.DS_Store"))
        #expect(PathPolicy.isIgnored(".trash/x.md"))
        #expect(!PathPolicy.isIgnored("notes/a.md"))
    }

    @Test func shaValidation() {
        #expect(PathPolicy.isValidSHA(String(repeating: "0", count: 40)))
        #expect(!PathPolicy.isValidSHA("../" + String(repeating: "0", count: 37)))
        #expect(!PathPolicy.isValidSHA(String(repeating: "A", count: 40)))
    }

    @Test func gitBlobHashMatchesGit() {
        // `printf 'hello\n' | git hash-object --stdin`
        #expect(BlobStore.gitBlobHash(of: Data("hello\n".utf8)) == "ce013625030ba8dba906f756967f9e9ca394464a")
    }

    @Test func blobStoreRejectsTamperedContent() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BlobStore(root: root)
        #expect(throws: GitHubError.self) {
            try store.write(Data("evil".utf8), sha: "ce013625030ba8dba906f756967f9e9ca394464a", path: "a.md")
        }
        let url = try store.write(Data("hello\n".utf8), sha: "ce013625030ba8dba906f756967f9e9ca394464a", path: "x/../../a.md")
        #expect(url.deletingLastPathComponent().standardizedFileURL == store.filesDirectory.standardizedFileURL)
    }

    @Test func relativeLinksCannotEscapeVault() {
        #expect(LinkResolver.normalize("a/../../etc") == nil)
        #expect(LinkResolver.normalize("a/./b/../c.md") == "a/c.md")
        #expect(VaultURL.relativePath(of: URL(string: "vault-rel://vault/a/b.md")!) == "a/b.md")
        #expect(VaultURL.relativePath(of: URL(string: "vault-rel://vault/../../x")!) == nil)
        #expect(VaultURL.relativePath(of: URL(string: "vault-rel://other/a.md")!) == nil)
    }

    @Test func tokenFormat() {
        #expect(GitHubToken.isWellFormed("ghu_" + String(repeating: "a", count: 36)))
        #expect(!GitHubToken.isWellFormed("ghu_abc\r\nX-Evil: 1" + String(repeating: "a", count: 20)))
        #expect(!GitHubToken.isWellFormed("short"))
    }

    @Test func indexDropsMalformedEntries() {
        var index = LocalIndex()
        index.files["../escape.md"] = IndexEntry(sha: String(repeating: "a", count: 40), size: 1, localSha: nil)
        index.files["ok.md"] = IndexEntry(sha: String(repeating: "a", count: 40), size: 1, localSha: "nope")
        index.files["good.md"] = IndexEntry(sha: String(repeating: "a", count: 40), size: 1, localSha: nil)
        #expect(Array(index.sanitized().files.keys) == ["good.md"])
    }
}

@MainActor
struct VaultModelTests {
    @Test func treeSortsFoldersFirstNaturally() {
        let tree = FileNode.buildTree(from: ["b.md", "10 - x/a.md", "2 - y/a.md", "a.md"])
        #expect(tree.map(\.name) == ["2 - y", "10 - x", "a.md", "b.md"])
    }

    @Test func resolverPrefersExactPath() {
        let resolver = LinkResolver(paths: ["a/Note.md", "b/Note.md"])
        #expect(resolver.resolve("b/Note", from: "a/x.md") == "b/Note.md")
        #expect(resolver.resolve("Note", from: "a/x.md") == "a/Note.md")
        #expect(resolver.resolve("note", from: "b/x.md") == "b/Note.md")
    }
}
