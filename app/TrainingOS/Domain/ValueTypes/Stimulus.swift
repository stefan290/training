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
///
/// **Stage 4E addition:** `.carry`, `.locomotion`, `.trunk` — Stage 4E §7
/// explicitly names these alongside squat/hinge/push/pull as required
/// movement-pattern categories; the original 7 cases had no way to
/// distinguish a farmer's-carry-style slot, a running/rowing-style
/// locomotion slot, or a core/trunk slot from `.other`. Purely additive —
/// a `String`-rawValue enum gaining cases is free, no persistence risk,
/// and every existing stored `MovementFunction` value is unaffected.
enum MovementFunction: String, Codable, CaseIterable {
    case squatLoaded
    case hingeLoaded
    case pressLoaded
    case gymnasticsPull
    case gymnasticsPush
    case monostructural
    case carry
    case locomotion
    case trunk
    /// Stage 9B addition: no existing case distinguished jumping/plyometric
    /// movements (e.g. box jumps) from any other lower-body pattern —
    /// confirmed the smallest clean addition after implementation audit,
    /// same purely-additive, no-persistence-risk precedent as the Stage 4E
    /// additions above.
    case jumping
    case other
    /// Stage 10C.1 additions: `.gymnasticsPull` is specifically
    /// bodyweight/gymnastics-flavored (Pull-up, Toes-to-Bar) — no case
    /// existed for a general LOADED pull at all (barbell/machine/cable
    /// row or pulldown), and none of `.pressLoaded`'s existing users
    /// distinguish horizontal from vertical pressing. Without these,
    /// a horizontal-pull-intent slot and a vertical-pull-intent slot
    /// were indistinguishable by movement function (only `primaryTargets`
    /// overlap could gate them, and `.back` overlaps both) — confirmed
    /// during this stage's own audit as a real substitution-safety risk
    /// once Lat Pulldown/Seated Cable Row were added. `.verticalPushLoaded`
    /// exists for the same reason on the press side: reusing generic
    /// `.pressLoaded` for a new Overhead Press exercise was found to
    /// let it wrongly satisfy the existing "Horizontal Push" slot
    /// grouping (`HypertrophyProgramGenerator.movementPatternGroupings`)
    /// purely via shared `.shoulders`/`.pressLoaded` overlap — a
    /// concrete, discovered collision, not a hypothetical one.
    /// `.pressLoaded` itself is left completely unchanged for every
    /// exercise that already carries it (Bench Press, Incline Dumbbell
    /// Press, Wall Ball, Thruster, Dumbbell Snatch) — only the new
    /// Overhead Press exercise uses `.verticalPushLoaded` instead.
    case horizontalPullLoaded
    case verticalPullLoaded
    case verticalPushLoaded
    /// Stage 10R.1 Slice 1A addition: a loaded knee-flexion isolation
    /// movement (leg curl family) — distinguishes a real "Hamstrings
    /// Isolation" source category slot from a hip-hinge/deadlift-pattern
    /// exercise that happens to share the `.hamstrings` target
    /// (`hingeLoaded`, e.g. Romanian/Conventional/Stiff-Legged Deadlift).
    /// Without this, a Hamstrings-Isolation-intent slot could not be
    /// distinguished from a hip-hinge slot by movement function alone —
    /// the exact same class of collision `.verticalPushLoaded`/
    /// `.horizontalPullLoaded` were added to solve, discovered while
    /// recovering the real RP source category database
    /// (`SOURCE_PROGRAM_MANIFEST.md` §5). Additive only — `Leg Curl`/
    /// `Seated Leg Curl` keep every existing tag unchanged.
    case kneeFlexionLoaded
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
