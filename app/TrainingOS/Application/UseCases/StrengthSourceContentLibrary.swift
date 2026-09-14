import Foundation

/// Strength Source Content V1: the 2 recovered `Strength_Program_1.xlsx`/
/// `Strength_Program_2.xlsx` configurations (`PowerliftingFamily.d`/`.e`) —
/// real, distinct, source-backed general Strength Training content that
/// reuses `PowerliftingProgramGenerator`'s engine internally.
///
/// **Deliberately NOT part of `PowerliftingBuiltInLibrary.all`** — this is
/// the one load-bearing architectural decision this file exists to
/// encode. `LongTermPlanner.powerliftingParameterCandidates(component:)`
/// resolves a `.powerlifting` `TrainingMixComponent`'s frequency through
/// `closestByDayCount(component:library:)`, which ties-break by `name`
/// string sort and surfaces `Array(sorted.prefix(2))` (best match PLUS a
/// runner-up) whenever multiple library entries are equally close to the
/// requested frequency. Both Family D and Family E are 4-day — exactly
/// Family B's own day count — so adding them to `PowerliftingBuiltInLibrary
/// .all` would make one silently appear as a "runner-up" `ProgramCandidate`
/// for any existing 4-day Powerlifting recommendation request, changing
/// the CLOSED, already-verified Powerlifting recommendation candidate set
/// (`TRAININGOS_PRODUCT_MODEL_ALIGNMENT.md`/`STRENGTH_SOURCE_CONTENT_V1.md`
/// explicitly forbid this). Keeping this list separate means:
///   - `ProgramCapabilityRegistry.supportedFrequencies(for: .powerlifting)`
///     is untouched (still derived only from `PowerliftingBuiltInLibrary
///     .all` — `{4, 5}` from Family B/C only).
///   - Existing Powerlifting recommendation behavior is provably
///     unchanged — nothing here is read by `powerliftingParameterCandidates`.
///   - Content identity is preserved automatically: these names never
///     appear alongside "4-Day Powerlifting Strength"/"5-Day Powerlifting
///     Hypertrophy" in any candidate list, and never say "Powerlifting"
///     or "RP" at all (see `PowerliftingProgramGenerator.definitionName`).
///
/// This is a deliberately narrow "building block" surface for this
/// checkpoint — direct capability-gating, source-fidelity testing, and
/// dogfood materialization only. Wiring these into an athlete-facing
/// recommendation/selection path (Build My Own Mix, `TrainingMix`
/// candidates, etc.) is explicit FOLLOW-UP, out of this checkpoint's scope.
struct StrengthSourceContentConfiguration {
    var name: String
    var configuration: PowerliftingProgramConfiguration
}

enum StrengthSourceContentLibrary {
    static let all: [StrengthSourceContentConfiguration] = [
        StrengthSourceContentConfiguration(
            name: "Strength Program 1 (General Strength)",
            configuration: PowerliftingProgramConfiguration(family: .d, dayCount: 4)
        ),
        StrengthSourceContentConfiguration(
            name: "Strength Program 2 (General Strength)",
            configuration: PowerliftingProgramConfiguration(family: .e, dayCount: 4)
        ),
    ]
}
