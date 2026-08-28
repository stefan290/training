import Foundation
import SwiftData

/// Builds `IntervalMaterializer.WeekContext` from a `ProgramInstance`'s
/// *actual* prior-week history — the interval sibling of
/// `FunctionalFitnessExposureHistoryBuilder`. Lives in
/// `Application/UseCases/`, not `Engines/`, for the identical reason: it
/// touches `@Model` types directly, while `IntervalProgressionEngine`
/// itself stays pure.
///
/// **Stage 10R.6C.** Before this, both `RollTacticalWindowUseCase.
/// materializeFirstWindow` and `.rollForward` always passed
/// `weekContext: { _ in .init() }` — correct at week 0 (nothing precedes
/// it), silently wrong at week 1+ (a gated template's real prior result
/// was simply never looked up). This resolver is the one seam both call
/// sites now share — never a second, divergent implementation.
///
/// **Known, disclosed limitation:** `WeekContext.previousActualZone` is
/// always left `nil`. `IntervalRepResult` only ever records a raw
/// `averageHeartRate` (bpm) — there is no persisted per-user
/// bpm-to-`HeartRateZone` mapping anywhere in the domain model, and
/// inventing one (an arbitrary threshold table) would be exactly the kind
/// of ambiguous training rule CLAUDE.md rule 10 forbids and exactly what
/// D-10R6-8 says not to do ("do not modify Interval progression rules").
/// `IntervalProgressionEngine.resolveIntensity` already has a fully
/// defined, pre-existing fallback for a `nil` zone (falls back to
/// `progression.startZone`/calendar-based progression), so this is a safe,
/// documented gap — not a fabrication.
enum IntervalWeekContextBuilder {
    /// Returns the `weekContext` closure `IntervalMaterializer.materializeWeek`
    /// expects for materializing `weekIndex` of `instance` — resolving each
    /// `WorkoutBlockTemplate`'s real previous-week (`weekIndex - 1`) actual
    /// result, if one exists. Week 0 (or any block template with no
    /// resolvable previous-week counterpart) legitimately yields an empty
    /// `WeekContext` — not an error, exactly like
    /// `FunctionalFitnessExposureHistoryBuilder` legitimately returning `[]`
    /// for a fresh instance.
    static func build(instance: ProgramInstance, weekIndex: Int) -> (WorkoutBlockTemplate) -> IntervalMaterializer.WeekContext {
        { blockTemplate in
            guard weekIndex > 0 else { return .init() }
            guard let rules = blockTemplate.intervalPrescriptionTemplate?.progressionRules else { return .init() }

            let previousWeekBlocks = ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex - 1).flatMap(\.orderedBlocks)
            guard
                let block = previousWeekBlocks.first(where: { $0.intervalPrescription?.sourceWorkoutBlockTemplate?.id == blockTemplate.id }),
                let prescription = block.intervalPrescription,
                let result = block.intervalResult
            else { return .init() }

            let reps = result.orderedRepResults
            guard !reps.isEmpty else { return .init() }

            let completedCount = reps.filter(\.wasCompletedAsPrescribed).count
            let outcome = IntervalProgressionEngine.evaluateSessionOutcome(
                criteria: rules.completionCriteria, completedCount: completedCount, totalCount: prescription.intervalCount, worstRpe: result.rpe
            )

            return IntervalMaterializer.WeekContext(
                previousActualIntervalCount: reps.count,
                previousActualWorkDurationSeconds: Self.averageInt(reps.compactMap(\.actualWorkDurationSeconds)),
                previousActualWorkDistanceMeters: Self.averageDouble(reps.compactMap(\.actualWorkDistanceMeters)),
                previousActualZone: nil,
                previousActualRecoveryDurationSeconds: Self.averageInt(reps.compactMap(\.actualRecoveryDurationSeconds)),
                previousOutcome: outcome
            )
        }
    }

    private static func averageInt(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / values.count
    }

    private static func averageDouble(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
