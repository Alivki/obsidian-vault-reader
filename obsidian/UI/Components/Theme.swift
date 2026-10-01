import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum Shad {
    static let background = Color(light: 0xFFFFFF, dark: 0x09090B)
    static let foreground = Color(light: 0x09090B, dark: 0xFAFAFA)
    static let card = Color(light: 0xFFFFFF, dark: 0x0C0C0E)
    static let muted = Color(light: 0xF4F4F5, dark: 0x27272A)
    static let mutedForeground = Color(light: 0x71717A, dark: 0xA1A1AA)
    static let accent = Color(light: 0xF4F4F5, dark: 0x27272A)
    static let border = Color(light: 0xE4E4E7, dark: 0x27272A)
    static let input = Color(light: 0xE4E4E7, dark: 0x3F3F46)
    static let ring = Color(light: 0xA1A1AA, dark: 0x71717A)
    static let primary = Color(light: 0x18181B, dark: 0xFAFAFA)
    static let primaryForeground = Color(light: 0xFAFAFA, dark: 0x18181B)
    static let secondary = Color(light: 0xF4F4F5, dark: 0x27272A)
    static let destructive = Color(light: 0xDC2626, dark: 0xEF4444)
    static let destructiveSurface = Color(light: 0xFEF2F2, dark: 0x2A0F10)
    static let success = Color(light: 0x16A34A, dark: 0x22C55E)
    static let warning = Color(light: 0xD97706, dark: 0xF59E0B)
    static let searchFill = Color(light: 0xE9EAEE, dark: 0x232326)
    static let sidebar = Color(light: 0xF6F7F9, dark: 0x111113)
    static let sidebarAccent = Color(light: 0xE8EBEF, dark: 0x26262A)
    static let treeText = Color(light: 0x3F4651, dark: 0xD4D4D8)
    static let treeGuide = Color(light: 0xDCDFE4, dark: 0x2E2E33)
    static let icon = Color(light: 0x2D44D2, dark: 0x8B9CFF)
    static let link = Color(light: 0x2563EB, dark: 0x6EA0FF)
    static let tagBackground = Color(light: 0xE8F0FE, dark: 0x1C2A4A)
    static let tagForeground = Color(light: 0x2563EB, dark: 0x8AB4FF)
    static let reading = Color(light: 0x222429, dark: 0xE4E4E7)

    static let radius: CGFloat = 8
    static let radiusSmall: CGFloat = 6

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    #if os(macOS)
    static let isMac = true
    #else
    static let isMac = false
    #endif
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
        #else
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

enum Prefs {
    static let appearance = "appearance"
    static let confirmExternalLinks = "confirmExternalLinks"
    static let loadRemoteImages = "loadRemoteImages"
    static let installMarker = "installMarker"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum Clipboard {
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }
}
