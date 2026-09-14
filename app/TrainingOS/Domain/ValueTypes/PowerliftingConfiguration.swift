import Foundation

/// Which RP Powerlifting source family a `PowerliftingProgramConfiguration`
/// generates — Family B ("RP Powerlifting Strength", mixed 5RM/8RM basis,
/// 4-day) or Family C ("RP Powerlifting Hypertrophy-block", uniform 10RM
/// basis, 5-day). Deliberately not called `.strength`/`.hypertrophyBlock`
/// — those names would collide conceptually with the unrelated
/// `HypertrophyProgrammingSystem` (Family A) and invite confusing the two
/// systems, which share an engine but are otherwise unrelated products.
enum PowerliftingFamily: String, Codable, CaseIterable {
    case b
    case c
    /// Strength Source Content V1: `Strength_Program_1.xlsx` — a real,
    /// distinct 16-row/4-day (4/4/4/4) derivative built on Family B's own
    /// engine shape (mixed 5RM/8RM basis), re-verified cell-by-cell
    /// directly against the live workbook (`STRENGTH_SOURCE_RECOVERY_V1.md`
    /// §3, `STRENGTH_SOURCE_CONTENT_V1.md`). Genuinely different from
    /// stock Family B: the Triples protocol is relocated from Monday-
    /// Push1/Thursday-Deadlift onto Friday-Legs2; a 4th row was added to
    /// Thursday; deload weight rounds to 5 (see that struct's own note on
    /// rounding not being a generator-level concern). Reached athlete-
    /// facing only via `TrainingStyle.strengthTraining` — never exposed
    /// as "Powerlifting" (`TRAININGOS_PRODUCT_MODEL_ALIGNMENT.md` §18/§21).
    case d
    /// Strength Source Content V1: `Strength_Program_2.xlsx` — a real,
    /// distinct 16-row/4-day (4/4/4/4) derivative built on Family C's own
    /// engine shape (uniform 10RM basis), Wednesday genuinely removed.
    /// Genuinely different from stock Family C: working-week rounding is
    /// 2.5 (not stock Family C's 5); the Friday-Legs2 backoff (0.85×) is
    /// a plain `.rmBased` row sharing "Legs Move 2"'s RM/exercise
    /// identity with Tuesday's row (NOT `.linkedToPairedSlot` — the
    /// source formula reads the RM cell directly with its own factor,
    /// not Tuesday's resolved result; re-verified directly this pass).
    case e
}

/// The "recipe" `PowerliftingProgramGenerator` needs — deliberately
/// minimal, matching `HypertrophyProgramConfiguration`'s shape. `dayCount`
/// is a separate field rather than hardcoded per family because Family D
/// (`PROGRAM_LOGIC_SPEC.md` §5) is direct evidence this engine is meant
/// to be end-user-reconfigurable independent of its RM-basis/rating
/// engine — but V1's only 2 built-in configurations always pair each
/// family with its own native day count (B=4, C=5).
struct PowerliftingProgramConfiguration: Codable, Equatable {
    var family: PowerliftingFamily
    var dayCount: Int
}
