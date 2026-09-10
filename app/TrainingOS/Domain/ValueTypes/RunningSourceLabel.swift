import Foundation

/// The exact workout-family vocabulary observed in RP's own 5K reference
/// program (`RUNNING_PROGRAMMING_MODEL_R1.md` §7, `Workout Blocks` sheet's
/// own `Source Label` column) — preserved as source provenance, never
/// translated into an unsupported physiological category.
///
/// **Deliberately closed and deliberately NOT one of:** VO2max, Threshold
/// run, Base, Long run, or any other generic exercise-science vocabulary.
/// R1 §7 found no evidence RP's own source ever uses those words for this
/// program, and found that "Tempo" and "Hard" are the *same* structural
/// slot at different points in the program's life (a label change over
/// time, not two coexisting families) — so this enum's cases are exactly
/// RP's own observed labels, not a reinterpretation of them. Running R2's
/// own directive requires these labels to "survive representation
/// unchanged"; this type is what makes that a compile-time guarantee
/// rather than a free-text convention that could silently drift.
///
/// **R3 CORRECTION (concrete source contradiction found during
/// implementation, not a re-audit):** while building the literal 25-
/// workout V1 program from `RP_5K_TrainingPeaks_Reference.xlsx`'s
/// `Workout Blocks` sheet directly (145 rows, every row re-inspected),
/// an 8th real `Source Label` value was found — `"Recovery"` — used as
/// the recovery leg between `Active` work bouts in relative weeks 5-8
/// (e.g. W09 block 8/10), distinct from `Easy`'s own separate role
/// (recovery within a `Repeat Group`, or standalone post-work volume).
/// R1 §7's taxonomy (and this enum, until now) missed this label — it
/// was not one of the representative weeks R1's analysis walked through
/// in prose. Added here as `.recovery`; R1 §7 itself is corrected with a
/// disclosed addendum, never rewritten.
enum RunningSourceLabel: String, Codable, CaseIterable {
    case warmUp
    case tempo
    case active
    case easy
    case hard
    case coolDown
    case warmUpEasyWalkSlowJog
    case recovery
}
