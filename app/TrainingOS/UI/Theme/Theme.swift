import SwiftUI
import UIKit

extension Color {
    /// `"#RRGGBB"` -> Color. No alpha support needed for this token set.
    init(hex: String) {
        var sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        sanitized = sanitized.replacingOccurrences(of: "#", with: "")
        var rgb: UInt64 = 0
        Scanner(string: sanitized).scanHexInt64(&rgb)
        let r = Double((rgb & 0xFF0000) >> 16) / 255
        let g = Double((rgb & 0x00FF00) >> 8) / 255
        let b = Double(rgb & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// Resolves to `dark` under the dark appearance and `light` otherwise,
    /// so tokens automatically follow the system appearance.
    init(light: String, dark: String) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light))
        })
    }
}

/// Design tokens transcribed from handoff section 18 ("Visual system").
/// `positive` and `attention` are only specified for dark mode in the
/// handoff; this pass reuses the same hex in light mode rather than
/// inventing a light-mode value — revisit with the design source before
/// shipping Light Mode for real (screen 29).
///
/// Chivo and Roboto Mono are not bundled in this pass (no font files were
/// part of the handoff export), so `numeric` falls back to the system
/// monospaced-digit font. See ARCHITECTURE.md.
enum Theme {
    static let ground = Color(light: "#F2F4F3", dark: "#0E1214")
    static let surfacePrimary = Color(light: "#FFFFFF", dark: "#12181B")
    static let surfaceSecondary = Color(light: "#FFFFFF", dark: "#161C20")
    static let primary = Color(light: "#3A5BD9", dark: "#7C9CFF")
    static let positive = Color(hex: "#6FD79E")
    static let attention = Color(hex: "#E8B457")
    static let textPrimary = Color(light: "#10151A", dark: "#B4BDB9")
    static let textSecondary = Color(light: "#5F6B70", dark: "#8A9490")

    static let heading = Font.system(.title2, design: .default).weight(.bold)
    static let body = Font.system(.body, design: .default).weight(.light)
    static let numeric = Font.system(.body, design: .monospaced)
    static let label = Font.system(.caption2, design: .monospaced).weight(.medium)
}
