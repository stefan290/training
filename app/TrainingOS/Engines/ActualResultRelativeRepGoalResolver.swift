import Foundation

/// Strength Source Content V1: resolves `RepPrescriptionKind
/// .priorSlotActualResultRelative` — Family E's Friday-Legs2 backoff,
/// source text "1/2 Tuesday's" (`Strength_Program_2.xlsx`, `c.) Mesocycle`
/// footnote B48/B49). Pure read — never mutates anything, never itself
/// decides whether to backfill (that's `PriorSlotActualResultRepGoalBackfillUseCase`'s
/// job); mirrors `AutoregulationRatingResolver`'s own discipline exactly,
/// reusing its `mostRecentlyCompletedPrescription` selection logic for the
/// cross-slot lookup.
///
/// **The exact recovered source rule** (footnote's own worked example:
/// Tuesday logged 10,8,8,8,7,7 across 6 sets; Friday — which has only 2
/// sets — targets 5,4): `target[i] = floor(referencedSlot's actual reps at
/// set-index i / 2)`, for i = 0..<requiredSetCount (this row's own set
/// count, never the referenced slot's larger count) — a PER-SET-INDEX
/// correspondence, never "half of the total," "half of the last set," or
/// "half of the average." Always rounds down (Swift's `/` on non-negative
/// `Int`s already truncates toward zero, which is floor for this domain —
/// no separate rounding call needed). The one-half fraction is a fixed,
/// source-confirmed constant — this resolver exists for exactly the one
/// recovered relationship, not a configurable/generalized fraction.
enum ActualResultRelativeRepGoalResolver {
    /// `nil` targets (with `.repGoalRequiresPriorSlotActualResult`) when
    /// the referenced slot has not yet logged enough actual reps to cover
    /// `requiredSetCount` — an honest "not yet available" state, never a
    /// fabricated target. Never reads or mutates the referenced slot's own
    /// `SetResult`s/`SetPrescription`s.
    static func resolvedRepTargets(
        referenceSlot: PrescriptionTemplate,
        requiredSetCount: Int,
        in instance: ProgramInstance
    ) -> (targets: [Int]?, reasonCode: StrengthReasonCode) {
        guard requiredSetCount > 0 else { return (nil, .calibrationRequired) }
        guard let referenced = AutoregulationRatingResolver.mostRecentlyCompletedPrescription(for: referenceSlot, in: instance) else {
            return (nil, .repGoalRequiresPriorSlotActualResult)
        }
        let actualReps = referenced.loggedSetResults
            .sorted { $0.setIndex < $1.setIndex }
            .map(\.reps)
        guard actualReps.count >= requiredSetCount else {
            return (nil, .repGoalRequiresPriorSlotActualResult)
        }
        let targets = actualReps.prefix(requiredSetCount).map { $0 / 2 }
        return (Array(targets), .repGoalSchedule)
    }
}
