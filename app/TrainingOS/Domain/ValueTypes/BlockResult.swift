import Foundation

/// A thin, named wrapper around the block's logged `SetResult`s — exists
/// only so `BlockResult.strength`'s payload has a name symmetrical with
/// its siblings, per the brief's own illustrative shape. Carries no state
/// of its own beyond the existing `SetResult` rows.
struct StrengthBlockResult {
    let setResults: [SetResult]
}

/// The generalized result abstraction validated in Stage 3B
/// (`PRESCRIPTION_RESULT_MODEL_REVIEW.md` §3). Not persisted directly, for
/// the same reason as `BlockPrescription` — synthesized by
/// `WorkoutBlock.blockResult` from whichever typed, persisted result
/// relationship is populated. The legacy `WorkoutResult` model (Stage 1-2)
/// is intentionally *not* one of these cases — see
/// `STAGE3C_IMPLEMENTATION_REPORT.md` for why blocks that only have a
/// legacy `WorkoutResult` return `nil` from `blockResult` rather than being
/// force-mapped into one of the new typed cases.
enum BlockResult {
    case strength(StrengthBlockResult)
    case steadyState(SteadyStateResult)
    case intervals(IntervalResult)
    case functionalFitness(FunctionalFitnessResult)
}
