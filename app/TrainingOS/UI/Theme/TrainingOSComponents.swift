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

/// Visual Design checkpoint: the artifact's recurring dark-pill
/// "eyebrow label + −/value/+" stat control (Strength's kg/reps/RIR
/// row, Functional Fitness's Rounds/+reps row) — a display/interaction
/// shell only. `onIncrement`/`onDecrement` are supplied by the caller so
/// this never owns or mutates state itself (a plain local `@State`
/// closure for a scratch value, or a real ViewModel method for
/// persisted state, e.g. `FunctionalFitnessExecutionViewModel.
/// incrementRound()`); `emphasizePlus` matches the artifact's one
/// deliberate "this is the primary action here" accent-colored +
/// button (e.g. Rounds, never every stepper on a screen).
struct TrainingOSStatStepper: View {
    let label: String
    let value: Int
    var emphasizePlus: Bool = false
    var displayValue: ((Int) -> String)? = nil
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(spacing: 7) {
            Text(label.uppercased())
                .font(Theme.label)
                .tracking(1.0)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                stepButton("minus", action: onDecrement)
                Text(displayValue?(value) ?? "\(value)")
                    .font(Theme.numeric.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 34)
                stepButton("plus", emphasized: emphasizePlus, action: onIncrement)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.ground, in: RoundedRectangle(cornerRadius: 10))
    }

    private func stepButton(_ systemImage: String, emphasized: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(emphasized ? Color.white : Theme.textSecondary)
                .background(emphasized ? Theme.primary : Theme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

/// Visual Design checkpoint (continuation): the artifact's own recurring
/// accent-filled, full-height pill CTA ("Continue"/"Accept route"/
/// "Start Muscle Gain I"/"Log Set") — one shared shape so every screen's
/// primary action reads as the same product, never a bespoke
/// `.borderedProminent` per screen (the exact "generic SwiftUI" gap this
/// checkpoint's own sweep found repeated across ~20 files). A caller
/// still supplies its own `.frame(maxWidth: .infinity)` when it wants the
/// full-width treatment (every real CTA in the artifact is full-width);
/// this style only owns the pill's own height/corner radius/color/type —
/// zero layout opinion beyond that.
struct TrainingOSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body.weight(.bold))
            .foregroundStyle(Theme.onPrimary)
            .padding(.vertical, 17)
            .padding(.horizontal, 22)
            .background(Theme.primary, in: RoundedRectangle(cornerRadius: Theme.cardCornerRadius))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

/// The artifact's neutral/outlined pill — a secondary action ("Adjust"/
/// "Cancel"/"Resume Later") or an action that ends something rather than
/// advancing it ("Finish" on a timer) — never accent-filled, so it never
/// competes with the one real primary action on screen.
struct TrainingOSSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body.weight(.medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 17)
            .padding(.horizontal, 22)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCornerRadius)
                    .strokeBorder(Color.primary.opacity(0.14))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == TrainingOSPrimaryButtonStyle {
    static var trainingOSPrimary: TrainingOSPrimaryButtonStyle { .init() }
}

extension ButtonStyle where Self == TrainingOSSecondaryButtonStyle {
    static var trainingOSSecondary: TrainingOSSecondaryButtonStyle { .init() }
}

/// Visual Design checkpoint (continuation): the artifact's own recurring
/// selectable capsule tag/chip ("Also keep," "What you want to do,"
/// Readiness's level/gateway rows) — accent-filled when selected, a
/// muted surface otherwise. Replaces ad hoc `.buttonStyle(.bordered)
/// .tint(...)` selection rows wherever a screen offers a small set of
/// mutually-exclusive or multi-select choices, never a full-width CTA.
struct TrainingOSChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.body.weight(.medium))
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .foregroundStyle(isSelected ? Theme.onPrimary : Theme.textMuted)
                .background(isSelected ? Theme.primary : Theme.surfaceSecondary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
