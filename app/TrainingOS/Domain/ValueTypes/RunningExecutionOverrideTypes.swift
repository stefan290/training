import Foundation

/// Whether an athlete's requested in-session intensity increase over the
/// prescribed value is permitted. Deliberately a closed, typed decision —
/// never a bare `Bool` — so a caller cannot silently drop the `reasonCode`
/// that always accompanies it (same discipline as every other engine
/// output in this codebase, e.g. `StrengthProgressionEngine`'s
/// `(weightKg, reasonCode)` tuple).
enum RunningOverrideDecision: String, Codable, Equatable {
    case allowed
    case rejected
    /// The requested intensity was not actually an increase over what was
    /// prescribed (equal or lower) — there is no "override" to evaluate.
    /// Kept distinct from `.allowed` so a test/caller can tell "no rule
    /// applies" apart from "a rule was evaluated and permitted it."
    case notApplicable
}

/// The Running foundation's execution-override reason-code vocabulary —
/// every `RunningOverrideDecision` is explainable via exactly one of
/// these, citing the exact FAQ/HowTo rule it enforces.
enum RunningOverrideReasonCode: String, Codable, CaseIterable {
    /// No increase was requested — see `RunningOverrideDecision.notApplicable`.
    case noIncreaseRequested
    /// FAQ "If I'm feeling strong... go faster... If it is the first rep
    /// of the workout, no." — never allowed on rep 1 regardless of any
    /// other condition.
    case rejectedRepOne
    /// FAQ "...If it is a run that is prescribed at 95% of threshold or
    /// lower, no." — a flat refusal, independent of rep index.
    case rejectedAtOrBelow95PercentThreshold
    /// FAQ "...If it is a run prescribed at a 6 on the RPE scale or
    /// lower, no."
    case rejectedAtOrBelowRPE6
    /// HowTo.txt line 9, corrected interpretation (R1 correction, accepted):
    /// "On days that are prescribed at a threshold percentage of 89% or
    /// less, please do not exceed these values" is an ATHLETE EXECUTION
    /// OVERRIDE LIMIT relative to THAT DAY'S OWN prescribed intensity —
    /// never a restriction on what may be prescribed. A prescription of,
    /// e.g., 80% is completely valid programming; an athlete may not
    /// execute it at 85%.
    case rejectedExceedsPrescribedAtOrBelow89Percent
    /// FAQ "...If you are midway through a set of intervals or a harder
    /// threshold bout and you're confident that if you go faster for the
    /// duration of the present rep that you'll still be able to hit at
    /// least the prescribed pace for all the other reps of the workout,
    /// then yes, you can go faster." Source gives no numeric ceiling for
    /// how much faster is allowed (CLAUDE.md rule 10 forbids inventing
    /// one) — this reason code marks only that none of the flat refusal
    /// conditions above applied, not any particular magnitude.
    case allowedWithinDocumentedConditions
}
