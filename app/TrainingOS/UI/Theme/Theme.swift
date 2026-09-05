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

/// Design tokens transcribed from the approved artifact
/// (`project/Training OS.dc.html`, "Visual system"/token usage traced
/// directly from its own stylesheet and every screen's inline styles —
/// V1 R1 "Design Foundation" checkpoint). `positive` and `attention` are
/// only specified for dark mode in the artifact; this pass reuses the
/// same hex in light mode rather than inventing a light-mode value —
/// revisit with the design source before shipping Light Mode for real.
///
/// **R1 color correction:** the artifact's own CSS body default
/// (`body{color:#F1F3F2}`) — used for headings, session names, and
/// direct-answer numeric values — was previously mis-mapped to
/// `textPrimary`'s dark value, which is actually the artifact's
/// SECONDARY body-copy tone. Verified by reading the artifact's real
/// color usage directly (`#F1F3F2` 28 uses = headings/values,
/// `#B4BDB9` 177 uses = secondary descriptive copy, `#8A9490` 457 uses =
/// muted field labels/metadata keys, `#5C666B` 166 uses = inactive
/// chrome, e.g. unselected tab icons) — a real, load-bearing four-tier
/// hierarchy, not two. `textPrimary` now correctly carries `#F1F3F2`;
/// `textSecondary` keeps its prior `#8A9490` role (it was already being
/// used at that tier's call sites, e.g. metadata/labels); `textMuted` and
/// `textInactive` are new tokens for the two tiers this pass discovered
/// had no token at all.
///
/// **Fonts (R1): a genuine, disclosed blocker.** Chivo and Roboto Mono
/// are NOT bundled anywhere in this repository (confirmed: no `.ttf`/
/// `.otf` files exist under `app/`, and no font name resembling either
/// appears in any project asset) — the artifact's own HTML export never
/// included font binaries, and downloading them from the internet was
/// explicitly out of scope for this checkpoint without separate
/// authorization. `heading`/`body` therefore keep the SYSTEM font but
/// adopt the artifact's real weight/tracking role Chivo would have
/// carried (heavy display weights for primary values, light weight for
/// descriptive body copy); `numeric`/`label` keep the system's
/// monospaced-digit design as Roboto Mono's role substitute. Swap the
/// `design: .default` fonts below for a real Chivo `Font.custom` (and
/// `numeric`/`label` for Roboto Mono) the moment font files are actually
/// added to the project — no other call site should need to change.
enum Theme {
    static let ground = Color(light: "#F2F4F3", dark: "#0E1214")
    static let surfacePrimary = Color(light: "#FFFFFF", dark: "#12181B")
    static let surfaceSecondary = Color(light: "#FFFFFF", dark: "#161C20")
    static let primary = Color(light: "#3A5BD9", dark: "#7C9CFF")
    static let positive = Color(hex: "#6FD79E")
    static let attention = Color(hex: "#E8B457")
    /// Primary foreground — headings, session names, direct-answer
    /// values. Artifact: `#F1F3F2` (dark, the CSS body default).
    static let textPrimary = Color(light: "#10151A", dark: "#F1F3F2")
    /// Secondary — descriptive body copy, metadata keys/labels.
    /// Artifact: `#8A9490` (dark).
    static let textSecondary = Color(light: "#5F6B70", dark: "#8A9490")
    /// Muted — the artifact's own secondary-body tone (longer
    /// explanatory sentences), one step brighter than `textSecondary`.
    /// Artifact: `#B4BDB9` (dark).
    static let textMuted = Color(light: "#6B7570", dark: "#B4BDB9")
    /// Inactive — unselected chrome (e.g. tab icons), the dimmest tier.
    /// Artifact: `#5C666B` (dark).
    static let textInactive = Color(light: "#9AA3A0", dark: "#5C666B")

    /// Primary human-facing hierarchy (Chivo's role — see the type-level
    /// doc comment on the font blocker). Large, heavy display value.
    static let headingXL = Font.system(size: 34, weight: .black, design: .default)
    static let heading = Font.system(.title2, design: .default).weight(.bold)
    static let body = Font.system(.body, design: .default).weight(.light)
    /// Roboto Mono's role — numeric values, metadata, technical/compact
    /// system information. Never used for primary human-facing prose.
    static let numeric = Font.system(.body, design: .monospaced)
    static let label = Font.system(.caption2, design: .monospaced).weight(.medium)
    /// A short, uppercase, tracked eyebrow/metadata-key line (e.g. a
    /// date header, a "SESSION 2" marker) — the artifact's own recurring
    /// `letter-spacing:.16em;text-transform:uppercase` treatment.
    static let eyebrow = Font.system(.caption, design: .monospaced).weight(.medium)

    /// Shared corner radius for a standard card (the artifact's own
    /// recurring `border-radius:12-14px` on session/info cards).
    static let cardCornerRadius: CGFloat = 14
    /// The artifact's own recurring outer screen padding.
    static let screenPadding: CGFloat = 16
}
