import SwiftUI

/// V1 R1 "Design Foundation" checkpoint: the minimum reusable primitives
/// actually justified by Today (and obvious later reuse across Plan/
/// Progress once those get their own reconciliation checkpoints) —
/// deliberately NOT a large abstract design-system framework. Two
/// components only: a card container and a section-header eyebrow, both
/// already-recurring, hand-rolled patterns across the current codebase
/// this pass consolidates into one place.

/// The artifact's own recurring card treatment (`background:#12181B` /
/// `#161C20`, `border:1px solid rgba(255,255,255,.09)`, `border-radius:
/// 12-14px`) — a `ViewModifier` rather than a wrapping container view so
/// it composes with any existing content, matching how every current
/// hand-rolled card site already shapes its own `VStack`.
struct TrainingOSCardStyle: ViewModifier {
    /// `true` for the one emphasized/"up next" card per screen (the
    /// artifact's own accent-tinted border treatment, e.g. Today's
    /// primary session hero) — never more than one per screen judged
    /// emphasized, or the emphasis itself stops meaning anything.
    var emphasized: Bool = false
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.surfacePrimary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(emphasized ? Theme.primary.opacity(0.32) : Color.primary.opacity(0.06))
            )
    }
}

extension View {
    /// `.trainingOSCard()` — the shared card container. `emphasized: true`
    /// only for the one primary/"up next" item on a screen.
    func trainingOSCard(emphasized: Bool = false, padding: CGFloat = 14) -> some View {
        modifier(TrainingOSCardStyle(emphasized: emphasized, padding: padding))
    }
}

/// The artifact's own recurring uppercase, tracked, muted eyebrow line
/// used as a section/metadata-key header (e.g. "SESSION 2", a date
/// header) — text only, no chrome of its own, so it composes freely
/// above any content.
struct SectionHeader: View {
    let title: String
    var color: Color = Theme.textSecondary

    var body: some View {
        Text(title.uppercased())
            .font(Theme.eyebrow)
            .tracking(1.4)
            .foregroundStyle(color)
    }
}
