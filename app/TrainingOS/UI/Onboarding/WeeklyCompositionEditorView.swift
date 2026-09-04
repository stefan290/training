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
            Form {
                Section {
                    Text("How do you want to train?")
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Choose exactly how many sessions of each style you want each week. TrainingOS will build the best real program it can for this exact mix.")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                }
                Section {
                    ForEach(TrainingStyle.allCases) { style in
                        if style != .cycling || cyclingAvailable {
                            row(for: style)
                        }
                    }
                }
                Section {
                    HStack {
                        Text("\(total) / \(capacity) sessions")
                            .font(Theme.body)
                            .foregroundStyle(total > capacity ? Theme.attention : Theme.textPrimary)
                        Spacer()
                        Text("\(remaining) remaining")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if !cyclingAvailable {
                    Section {
                        Text("Cycling needs a bike in your Training Environment.")
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .font(Theme.label)
                            .foregroundStyle(Theme.attention)
                    }
                }
            }
            .navigationTitle("Build My Own Mix")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use This Mix") {
                        let nonZero = selections.compactMap { style, frequency in
                            frequency > 0 ? (style: style, frequency: frequency) : nil
                        }
                        if !onUse(nonZero) {
                            validationMessage = "This exact combination isn't supported yet — try a different mix."
                        }
                    }
                }
            }
        }
    }

    private func row(for style: TrainingStyle) -> some View {
        let allowed = allowedValues(for: style)
        let current = selections[style] ?? 0
        return HStack {
            Text(PlanPresentation.trainingStyleLabel(style))
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button {
                if let index = allowed.firstIndex(of: current), index > 0 {
                    selections[style] = allowed[index - 1]
                }
            } label: {
                Image(systemName: "minus.circle")
            }
            .disabled(current == 0)
            Text("\(current)")
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
                .frame(minWidth: 24)
                .multilineTextAlignment(.center)
            Button {
                if let index = allowed.firstIndex(of: current), index < allowed.count - 1 {
                    selections[style] = allowed[index + 1]
                }
            } label: {
                Image(systemName: "plus.circle")
            }
            .disabled(allowed.last == current)
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
