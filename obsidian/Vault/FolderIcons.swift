import Foundation
import SwiftUI

enum FolderIconKind: Equatable, Sendable {
    case symbol(String)
    case emoji(String)
}

/// Icons set in Obsidian's Iconize plugin: per-folder icons and custom rules.
nonisolated struct FolderIconConfig: Sendable {
    struct Rule: Sendable {
        let pattern: String
        let regex: NSRegularExpression?
        let icon: FolderIconKind
        let usesPath: Bool
    }

    var exact: [String: FolderIconKind] = [:]
    var rules: [Rule] = []
    /// Repo-path prefix of the vault the config belongs to (e.g. `Vault/`).
    var vaultPrefix = ""

    /// A folder only gets an icon if Iconize defines one for it.
    func icon(forFolder path: String) -> FolderIconKind? {
        if let icon = exact[path] { return icon }
        let relative = path.hasPrefix(vaultPrefix) ? String(path.dropFirst(vaultPrefix.count)) : path
        let name = PathPolicy.lastComponent(path)
        for rule in rules {
            let subject = rule.usesPath ? relative : name
            if let regex = rule.regex {
                if regex.firstMatch(in: subject, range: NSRange(subject.startIndex..., in: subject)) != nil { return rule.icon }
            } else if subject.contains(rule.pattern) {
                return rule.icon
            }
        }
        return nil
    }
}

nonisolated enum FolderIcons {
    static let configSuffix = ".obsidian/plugins/obsidian-icon-folder/data.json"
    static let maxConfigBytes = 1024 * 1024

    /// The plugin config may live at the repo root or inside one vault folder.
    static func isConfigPath(_ path: String) -> Bool {
        guard path.hasSuffix(configSuffix), PathPolicy.isSafe(path) else { return false }
        let prefix = path.dropLast(configSuffix.count)
        return prefix.isEmpty || (prefix.hasSuffix("/") && !prefix.dropLast().contains("/") && !prefix.hasPrefix("."))
    }

    /// True for hidden folders on the way to the config, e.g. `.obsidian/plugins`.
    static func leadsToConfig(_ folder: String) -> Bool {
        let parts = folder.split(separator: "/")
        guard let firstHidden = parts.firstIndex(where: { $0.hasPrefix(".") }), firstHidden <= 1 else { return false }
        let route = configSuffix.split(separator: "/").dropLast()
        let tail = parts[firstHidden...]
        return tail.count <= route.count && zip(tail, route).allSatisfy { $0 == $1 }
    }

    /// Parses Iconize's `data.json`:
    /// `{ "<path>": "LiCalendar" | "🎁" | { "iconName": … }, "settings": { "rules": [ … ] } }`.
    static func parseConfig(_ data: Data, configPath: String) -> FolderIconConfig {
        var config = FolderIconConfig()
        guard data.count <= maxConfigBytes,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return config }
        config.vaultPrefix = String(configPath.dropLast(configSuffix.count))

        for (key, value) in object where key != "settings" && config.exact.count < 5_000 {
            let name: String?
            if let string = value as? String { name = string }
            else if let dict = value as? [String: Any] { name = dict["iconName"] as? String }
            else { name = nil }
            guard let name, let icon = icon(named: name) else { continue }
            let path = config.vaultPrefix + key.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if PathPolicy.isSafe(path) { config.exact[path] = icon }
        }

        let settings = object["settings"] as? [String: Any]
        let rawRules = (settings?["rules"] as? [[String: Any]] ?? []).prefix(200)
        let sorted = rawRules.sorted { ($0["order"] as? Int ?? 0) < ($1["order"] as? Int ?? 0) }
        for raw in sorted {
            guard let pattern = raw["rule"] as? String, (1...200).contains(pattern.count),
                  let iconName = raw["icon"] as? String, let icon = icon(named: iconName),
                  (raw["for"] as? String ?? "everything") != "files" else { continue }
            config.rules.append(FolderIconConfig.Rule(
                pattern: pattern,
                regex: try? NSRegularExpression(pattern: pattern),
                icon: icon,
                usesPath: raw["useFilePath"] as? Bool ?? false
            ))
        }
        return config
    }

    static func icon(named raw: String) -> FolderIconKind? {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.count <= 64 else { return nil }
        if let first = name.unicodeScalars.first, first.properties.isEmojiPresentation || (name.count <= 2 && first.properties.isEmoji && !first.isASCII) {
            return .emoji(String(name.prefix(2)))
        }
        // "LiCalendarDays" -> "calendar-days" (strip the 2-letter icon-pack prefix).
        guard name.count > 2, name.prefix(2).allSatisfy(\.isLetter) else { return nil }
        var kebab = ""
        for character in name.dropFirst(2) {
            if character.isUppercase, !kebab.isEmpty { kebab.append("-") }
            kebab.append(Character(character.lowercased()))
        }
        return .symbol(lucide[kebab] ?? "folder")
    }

    /// Lucide → SF Symbols for the icons people commonly use on folders.
    static let lucide: [String: String] = [
        "code": "chevron.left.forwardslash.chevron.right", "code-2": "chevron.left.forwardslash.chevron.right",
        "code-xml": "chevron.left.forwardslash.chevron.right", "braces": "curlybraces", "terminal": "terminal",
        "pen-tool": "pencil.tip.crop.circle", "pen": "pencil", "pencil": "pencil", "pen-line": "pencil.line",
        "calendar": "calendar", "calendar-days": "calendar", "calendar-range": "calendar",
        "calendar-check": "calendar.badge.checkmark", "calendar-clock": "calendar.badge.clock",
        "list-checks": "checklist", "list-todo": "checklist", "check-square": "checkmark.square",
        "square-check": "checkmark.square", "clipboard-check": "list.clipboard", "clipboard-list": "list.clipboard",
        "clipboard": "clipboard", "graduation-cap": "graduationcap", "school": "graduationcap",
        "gift": "gift", "archive": "archivebox", "scan": "viewfinder", "frame": "square.dashed",
        "square-dashed": "square.dashed", "box-select": "square.dashed", "library": "books.vertical",
        "library-big": "books.vertical", "landmark": "building.columns", "book": "book.closed",
        "book-open": "book", "notebook": "book.closed", "folder": "folder", "folder-open": "folder",
        "home": "house", "house": "house", "star": "star", "heart": "heart", "briefcase": "briefcase",
        "inbox": "tray", "image": "photo", "images": "photo.on.rectangle", "music": "music.note",
        "brain": "brain", "lightbulb": "lightbulb", "user": "person", "users": "person.2",
        "settings": "gearshape", "cog": "gearshape", "file-text": "doc.text", "file": "doc",
        "flask-conical": "flask", "globe": "globe", "database": "cylinder", "cpu": "cpu",
        "shield": "shield", "lock": "lock", "tag": "tag", "tags": "tag", "bookmark": "bookmark",
        "map": "map", "plane": "airplane", "dumbbell": "dumbbell", "utensils": "fork.knife",
        "chef-hat": "fork.knife", "cooking-pot": "fork.knife", "camera": "camera", "video": "video",
        "trash": "trash", "zap": "bolt", "sparkles": "sparkles", "flag": "flag", "target": "target",
        "trophy": "trophy", "calculator": "plus.forwardslash.minus", "sigma": "sum", "atom": "atom",
        "leaf": "leaf", "wallet": "creditcard", "dollar-sign": "dollarsign.circle", "newspaper": "newspaper",
        "building": "building.2", "building-2": "building.2", "network": "network", "server": "server.rack",
        "bug": "ladybug", "film": "film", "gamepad-2": "gamecontroller", "rocket": "paperplane",
        "message-square": "message", "mail": "envelope", "phone": "phone", "link": "link",
        "layers": "square.stack.3d.up", "layout-grid": "square.grid.2x2", "box": "shippingbox", "package": "shippingbox",
    ]
}
