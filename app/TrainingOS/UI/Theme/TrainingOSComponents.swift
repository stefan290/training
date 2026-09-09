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

    /// Design Fidelity Correction 01 bug fix: a caller's OWN
    /// `.frame(maxWidth: .infinity)` at the call site (the pattern every
    /// existing consumer already used, expecting a full-bleed CTA
    /// matching the artifact's `height:56` buttons) does not reliably
    /// widen this button when it sits among sibling views with a
    /// stronger width preference (e.g. a `ScrollView` or a `Spacer`-
    /// bearing row) in the same stack — `configuration.label` alone,
    /// with no `.frame` of its own, reports only its own text's natural
    /// (narrow) ideal width during the stack's layout negotiation, so it
    /// consistently loses that negotiation regardless of the caller's
    /// outer frame. Confirmed reproducing on the ALREADY-SHIPPED Weekly
    /// Composition Editor's "Use This Mix" button, not something newly
    /// introduced here. Fixed at the source, inside the style itself, so
    /// every existing full-width call site is corrected without touching
    /// any of them.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity)
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

/// Design Fidelity Correction 01: the artifact's recurring onboarding
/// step tracker (Screen 17/18's `<div style="display:flex;gap:5px">`
/// segment row, directly below the device status area — never a
/// centered `.navigationTitle`). Cumulative fill: every segment up to
/// and including the current step reads as progress made, matching the
/// artifact's Screen 18 (step 2 of 4) showing its first TWO segments
/// filled, not just the second. Currently consumed only by
/// `OnboardingFlowView`'s Goal step; not yet propagated to the other
/// onboarding steps — that is later, separately authorized work.
struct OnboardingProgressIndicator: View {
    let currentStepIndex: Int
    let totalSteps: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Capsule()
                    .fill(index <= currentStepIndex ? Theme.primary : Theme.progressTrackInactive)
                    .frame(height: 3)
            }
        }
    }
}

/// Screen 23's "Training days per week" bar (a row of blocks up to the
/// chosen value, with a numeric scale beneath). Tapping a segment sets
/// that value directly (no separate stepper needed); `range` is the real
/// selectable bound the caller already enforces elsewhere (1...7 for
/// training days). See `fillColor(for:)` for the distance-based fill —
/// R6 Final User-Visual Correction replaced this struct's original flat
/// two-tier fill (which read as materially more visually dominant than
/// the artifact) with one that falls off with distance from the
/// selection, matching the artifact's own real shape.
struct TrainingOSCapacityBar: View {
    let value: Int
    let range: ClosedRange<Int>
    let onSelect: (Int) -> Void

    private var values: [Int] { Array(range) }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 5) {
                ForEach(values, id: \.self) { candidate in
                    Button {
                        onSelect(candidate)
                    } label: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(fillColor(for: candidate))
                            .frame(height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                ForEach(values, id: \.self) { candidate in
                    Text("\(candidate)")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(candidate == value ? Theme.primary : Theme.textInactive)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// R6 Final User-Visual Correction: the artifact's own bar (Screen 23)
    /// is not a flat "filled vs. unfilled" fill — only the selected value
    /// itself reads at full accent; a bar one step below it reads as a
    /// muted mid-tone, and anything two or more steps below it (or not
    /// yet reached) reads as the same quiet, flat inactive tone. The
    /// previous two-tier version (55%/100% accent opacity for every
    /// filled bar) made every bar up to the selection read almost as
    /// bright as the selection itself — materially more visually
    /// dominant than the artifact. This reproduces the same "brightness
    /// falls off with distance from the selection" shape without
    /// inventing four new bespoke color tokens for one control.
    private func fillColor(for candidate: Int) -> Color {
        guard candidate <= value else { return Theme.progressTrackInactive }
        switch value - candidate {
        case 0: return Theme.primary
        case 1: return Theme.primary.opacity(0.5)
        default: return Theme.progressTrackInactive
        }
    }
}
