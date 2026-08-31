import Foundation

/// The smallest honest mapping from `AdaptationObjective` to `Stimulus`'s
/// own existing fields — Stage CP.2's locked design
/// (`TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`'s "objective ->
/// existing Stimulus preference mapping"). Two deliberately different
/// uses of the same underlying direction table:
///
/// - `objectivesServed(by:)` is a READ: a coarse, categorical
///   classification of which objectives a given `Stimulus` already
///   serves. May reason about several fields at once — it never mutates
///   anything.
/// - `nudge(_:toward:)` is a WRITE: the one-field mutation that steers a
///   `Stimulus` toward a single objective, for
///   `FunctionalFitnessDecisionEngine`'s same-week complementarity check.
///   Exactly one field per call, mirroring the engine's own existing
///   "adjust one dimension, never several" discipline.
///
/// `maxStrength`/`muscleGain` have **NO CP.2 mapping** — confirmed by
/// audit that Functional Fitness's coarse `Stimulus` model cannot
/// honestly express true maximal-strength or hypertrophy-volume
/// programming; both objectives' real home is Hypertrophy/Powerlifting
/// exclusively and must never influence an FF candidate's ranking.
enum AdaptationObjectiveStimulusMapping {
    /// Coarse, categorical, no numeric scoring — a `Stimulus` either
    /// plausibly serves an objective's documented direction or it
    /// doesn't. A `Stimulus` may serve zero, one, or several objectives
    /// at once.
    /// Each mapped objective is keyed to exactly one `Stimulus` field/value
    /// pair — deliberately coarser than the design brief's own prose
    /// ("power: short AND explosive," "anaerobicCapacity: high intensity
    /// AND high systemic demand") so that every check here has a matching
    /// ONE-FIELD `nudge(_:toward:)` mutation; a `Stimulus` can still serve
    /// several objectives simultaneously (non-mutually-exclusive, per
    /// `AdaptationObjective`'s own doc comment), just never via a
    /// multi-field AND. No numeric scoring anywhere in this function.
    static func objectivesServed(by stimulus: Stimulus) -> Set<AdaptationObjective> {
        var served: Set<AdaptationObjective> = []
        if stimulus.intensity == .high { served.insert(.power) }
        if stimulus.targetDurationDomain == .long { served.insert(.aerobicCapacity) }
        if stimulus.targetDurationDomain == .short { served.insert(.anaerobicCapacity) }
        if stimulus.systemicDemand == .high { served.insert(.workCapacity) }
        if stimulus.skillDemand == .high { served.insert(.skillAcquisition) }
        // maxStrength, muscleGain: intentionally never served by any FF
        // Stimulus — no honest mapping exists (see this type's own doc
        // comment).
        return served
    }

    /// The one-field nudge toward `objective` — `nil` when the stimulus
    /// already serves it (nothing to change) or when `objective` has no
    /// honest FF mapping at all (`maxStrength`/`muscleGain`).
    static func nudge(_ stimulus: Stimulus, toward objective: AdaptationObjective) -> Stimulus? {
        var nudged = stimulus
        switch objective {
        case .power:
            guard stimulus.intensity != .high else { return nil }
            nudged.intensity = .high
        case .aerobicCapacity:
            guard stimulus.targetDurationDomain != .long else { return nil }
            nudged.targetDurationDomain = .long
        case .anaerobicCapacity:
            guard stimulus.targetDurationDomain != .short else { return nil }
            nudged.targetDurationDomain = .short
        case .workCapacity:
            guard stimulus.systemicDemand != .high else { return nil }
            nudged.systemicDemand = .high
        case .skillAcquisition:
            guard stimulus.skillDemand != .high else { return nil }
            nudged.skillDemand = .high
        case .maxStrength, .muscleGain:
            // NO CP.2 MAPPING YET — never nudges an FF candidate toward
            // either; both objectives' real home is Hypertrophy/
            // Powerlifting exclusively.
            return nil
        }
        return nudged
    }
}
