import SwiftUI

/// V1 "Explicit Weekly Composition" checkpoint (Checkpoint 1): the
/// "Build My Own Mix" editor — "How do you want to train?" with one
/// stepper row per `TrainingStyle`, capacity always visible, and only
/// REAL, currently-supported frequencies ever selectable
/// (`ProgramCapabilityRegistry.supportedFrequencies`, via
/// `LongTermPlanner.underlyingSystem`). Never lets the athlete pick a
/// value the production path would later reject — the CRITICAL
/// SOURCE-AUTHORITY CORRECTION this checkpoint locks: an unsupported
/// frequency (e.g. 2 Hypertrophy, 2 Strength Training) is never offered
/// as a choice in the first place, rather than accepted here and failing
/// later.
///
/// Visual Design checkpoint (continuation): rebuilt off the native
/// `Form` this screen had used since R6 — the single most explicitly
/// named priority gap in this continuation's own brief. Restyled onto
/// the R1 foundation (`SectionHeader`/`.trainingOSCard()`/
/// `TrainingOSStatStepper`/`TrainingOSPrimaryButtonStyle`): the artifact's
/// "Availability" screen shows the same "big number + capacity" shape for
/// a single weekly-load question — this generalizes that same visual
/// language to five per-style rows instead of one, since no exact
/// "Build My Own Mix" screen exists in the artifact for this real,
/// V1-only capability. Zero interaction/validation logic changed — same
/// `selections`/`allowedValues(for:)`/`onUse` contract as before.
struct WeeklyCompositionEditorView: View {
    let capacity: Int
    /// Whether Cycling can be offered at all this session — real TE.1
    /// equipment gating (`ActivityType.cycling.requiredEquipment`),
    /// resolved by the caller; never re-derived here.
    let cyclingAvailable: Bool
    let onCancel: () -> Void
    /// Returns `true` on a successful build (the caller already applied
    /// it to `reviewedMix`); `false` means validation failed and
    /// `validationMessage` explains why — the editor stays open either
    /// way so the athlete can adjust.
    let onUse: ([(style: TrainingStyle, frequency: Int)]) -> Bool

    @State private var selections: [TrainingStyle: Int] = [
        .hypertrophy: 0, .strengthTraining: 0, .functionalFitness: 0, .running: 0, .cycling: 0,
    ]
    @State private var validationMessage: String?

    private var total: Int { selections.values.reduce(0, +) }
    private var remaining: Int { max(0, capacity - total) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How do you want to train?")
                            .font(Theme.headingXL)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Choose exactly how many sessions of each style you want each week. TrainingOS will build the best real program it can for this exact mix.")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    capacitySummary

                    VStack(spacing: 10) {
                        ForEach(TrainingStyle.allCases) { style in
                            if style != .cycling || cyclingAvailable {
                                row(for: style)
                            }
                        }
                    }

                    if !cyclingAvailable {
                        Text("Cycling needs a bike in your Training Environment.")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(Theme.label)
                            .foregroundStyle(Theme.attention)
                    }

                    Button("Use This Mix") {
                        let nonZero = selections.compactMap { style, frequency in
                            frequency > 0 ? (style: style, frequency: frequency) : nil
                        }
                        if !onUse(nonZero) {
                            validationMessage = "This exact combination isn't supported yet — try a different mix."
                        }
                    }
                    .buttonStyle(.trainingOSPrimary)
                    .frame(maxWidth: .infinity)
                }
                .padding(Theme.screenPadding)
            }
            .background(Theme.ground)
            .navigationTitle("Build My Own Mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }

    /// The artifact's own "N / capacity" + "remaining" summary shape
    /// (its "Sessions per week" card) — a real number over threshold
    /// flips to the attention color, never a silent overflow.
    private var capacitySummary: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                SectionHeader(title: "Sessions per week")
                Text("\(total) / \(capacity)")
                    .font(Theme.numeric.weight(.bold))
                    .foregroundStyle(total > capacity ? Theme.attention : Theme.textPrimary)
            }
            Spacer()
            Text("\(remaining) remaining")
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
        }
        .trainingOSCard()
    }

    private func row(for style: TrainingStyle) -> some View {
        let allowed = allowedValues(for: style)
        let current = selections[style] ?? 0
        return HStack {
            Text(PlanPresentation.trainingStyleLabel(style))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            HStack(spacing: 10) {
                stepButton(systemImage: "minus") {
                    if let index = allowed.firstIndex(of: current), index > 0 {
                        selections[style] = allowed[index - 1]
                    }
                }
                .disabled(current == 0)
                Text("\(current)")
                    .font(Theme.numeric.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 24)
                    .multilineTextAlignment(.center)
                stepButton(systemImage: "plus") {
                    if let index = allowed.firstIndex(of: current), index < allowed.count - 1 {
                        selections[style] = allowed[index + 1]
                    }
                }
                .disabled(allowed.last == current)
            }
        }
        .trainingOSCard(emphasized: current > 0)
    }

    private func stepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .foregroundStyle(Theme.textSecondary)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// `0` plus every real, currently-supported frequency for this
    /// style's underlying system that still fits within what OTHER rows
    /// haven't already claimed — never a value the production path would
    /// reject. Running/Cycling collapse each other to `[0]` once the
    /// other is non-zero: both resolve to the same underlying `.steadyState`
    /// system and `TrainingMixComponent` has no per-component
    /// `ActivityType` of its own, a real architectural gap
    /// (`LongTermPlanner.CustomMixValidationError.conflictingEnduranceStyles`)
    /// — the editor prevents the combination rather than only rejecting
    /// it after the fact.
    private func allowedValues(for style: TrainingStyle) -> [Int] {
        if style == .running, (selections[.cycling] ?? 0) > 0 { return [0] }
        if style == .cycling, (selections[.running] ?? 0) > 0 { return [0] }

        let otherTotal = total - (selections[style] ?? 0)
        let remainingForThisRow = max(0, capacity - otherTotal)
        let system = LongTermPlanner.underlyingSystem(for: style)
        guard let supported = ProgramCapabilityRegistry.supportedFrequencies(for: system) else {
            return Array(0...remainingForThisRow)
        }
        return [0] + supported.filter { $0 <= remainingForThisRow }
    }
}
