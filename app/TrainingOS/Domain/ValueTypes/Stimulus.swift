import Foundation

/// How long a block is intended to take, coarse and deterministic by
/// design (`TrainingStressProfile.swift`'s doc comment explains why
/// precision is deliberately avoided) — shared between `Stimulus` and
/// `TrainingStressProfile` rather than declared twice.
enum DurationDomain: String, Codable, CaseIterable {
    case short   // roughly <5 min
    case medium  // roughly 5-15 min
    case long    // roughly >15 min
}

enum IntensityClassification: String, Codable, CaseIterable {
    case low
    case moderate
    case high
}

enum LoadingClassification: String, Codable, CaseIterable {
    case bodyweightOnly
    case light
    case moderate
    case heavy
}

enum SkillDemand: String, Codable, CaseIterable {
    case low
    case moderate
    case high
}

enum SystemicDemandLevel: String, Codable, CaseIterable {
    case low
    case moderate
    case high
}

/// The three broad categories CrossFit's own programming material names —
/// SOURCE-DERIVED, see `PROGRAMMING_SOURCES.md` §4.
enum FunctionalModality: String, Codable, CaseIterable {
    case metabolicConditioning
    case gymnastics
    case weightlifting
}

/// A closed set of movement-pattern requirements a movement slot can carry.
/// `.other` exists so this never blocks a movement pattern the model hasn't
/// anticipated, mirroring `PhaseType.custom`'s existing precedent.
enum MovementFunction: String, Codable, CaseIterable {
    case squatLoaded
    case hingeLoaded
    case pressLoaded
    case gymnasticsPull
    case gymnasticsPush
    case monostructural
    case other
}

/// How many slots of a given `FunctionalModality` a stimulus calls for —
/// an array of pairs rather than `[FunctionalModality: Int]` so `Stimulus`
/// stays trivially `Codable` (a `Dictionary` keyed by a non-string-backed
/// enum needs no special handling for `Codable` synthesis, but an array of
/// named pairs is simpler to reason about and equally typed).
struct ModalityCount: Codable, Equatable {
    var modality: FunctionalModality
    var count: Int
}

/// What a Functional Fitness block is *for* — kept strictly separate from
/// `WorkoutFormat` (the structural container). See
/// `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §1.1/§2 for the full
/// rationale; this is that design, implemented.
struct Stimulus: Codable, Equatable {
    var targetDurationDomain: DurationDomain
    var intensity: IntensityClassification
    var loading: LoadingClassification
    var movementFunctions: [MovementFunction]
    var movementModalityMix: [ModalityCount]
    var skillDemand: SkillDemand
    var systemicDemand: SystemicDemandLevel
    var scoreType: ScoreType
}
