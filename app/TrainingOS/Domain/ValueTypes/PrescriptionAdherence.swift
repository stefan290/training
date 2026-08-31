import Foundation

/// Stage FF.E1: whether the athlete explicitly confirmed they followed the
/// FINAL Functional Fitness prescription (FF.L1's own `stimulus`, after
/// Stage CP.2 adaptation — never `intendedStimulus`), scoped only to the
/// dimensions TrainingOS actually prescribes today (movement identity/
/// variant, `WorkoutFormat`, rounds/duration-cap/work-rest structure).
/// Deliberately NOT a numeric-load/reps/distance/calories certification —
/// generated Functional Fitness content does not prescribe those with
/// enough precision for a claim about them to be honest yet
/// (`FUNCTIONAL_FITNESS_EXECUTION_TRUTH_DESIGN.md`).
///
/// Deliberately a separate concept from `ResultContext` (Rx/Scaled) —
/// `ResultContext` is a cross-modality enum shared with
/// `WorkoutResult`/`IntervalResult`/`SteadyStateResult`, defaults to `.rx`
/// unconditionally on every real Functional Fitness result, and is never
/// actually confirmed by any athlete today. Reinterpreting it would let a
/// completely unconfirmed default silently become "evidence." This type
/// exists specifically so "we don't know" (`.unknown`) is a real,
/// representable state — the exact state `ResultContext`'s own two cases
/// cannot express.
///
/// `.unknown` is the safe default for every record — legacy rows, a
/// migration, or a result whose completion flow never asked. It is not a
/// normal user-facing choice for a newly logged workout (see
/// `FunctionalFitnessExecutionViewModel.finish`'s own doc comment).
enum PrescriptionAdherence: String, Codable, CaseIterable {
    /// No explicit confirmation exists — legacy records, migration,
    /// interrupted flows, defensive fallback. NEVER inferred from
    /// `ResultContext` or any other historical signal.
    case unknown
    /// The athlete explicitly confirmed the FINAL prescription's
    /// movements/format/structure were followed. Evaluates FINAL only —
    /// never a claim about `intendedStimulus`, and never a claim about
    /// numeric load/reps/distance/calories that were never prescribed.
    case asPrescribed
    /// The athlete explicitly confirmed something differed materially
    /// from the FINAL prescription. Coarse and deliberately unspecific —
    /// WHY it differed is out of scope for this stage.
    case modified
}
