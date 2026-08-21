import Foundation

/// Why a user (or the app, on the user's behalf) chose something other
/// than the slot's/prescription's default selection — a deliberately
/// separate vocabulary from `ProgressionReasonCode`. This answers "why did
/// I pick this exercise/activity"; `ProgressionReasonCode` (which already
/// carries `.substitutionEstimate`/`.calibrationRequired`) answers "how was
/// this recommended number derived." Conflating the two would mean either
/// duplicating `.calibrationRequired`'s meaning under a new name (a
/// duplicate-truth smell — Stage 4C's own explicit warning) or overloading
/// one enum with two unrelated questions.
///
/// Optional everywhere it's stored — Stage 4C explicitly does not require
/// the user to supply a reason; `nil` means "no reason recorded," a
/// legitimate, common state, never treated as a validation failure.
enum SubstitutionReason: String, Codable, CaseIterable {
    case userExerciseSubstitution
    case exerciseUnavailable
    case equipmentUnavailable
    case userPreference
    /// Stage 8B addition: a same-session substitution proposed by
    /// `EvaluateReadinessAdaptationUseCase` and accepted by the user. The
    /// *specific* trigger (pain vs. stiffness vs. soreness, and which body
    /// area) is never exploded into more `SubstitutionReason` cases — it
    /// lives on the paired `ReadinessAdaptationDecision.triggeringSignals`
    /// instead (Stage 8A decision D7).
    case readinessAdaptation
}
