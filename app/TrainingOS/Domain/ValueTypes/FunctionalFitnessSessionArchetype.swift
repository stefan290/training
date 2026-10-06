import Foundation

/// Dogfood Round 2 (Finding 4): a real, explicit **TrainingOS PRODUCT
/// DECISION** — never attributed to any source — for how the CURRENT
/// phase's own adaptation priority reshapes a Functional Fitness
/// session's actual identity, not merely whether a strength block is
/// attached (that was Dogfood Round 1's own, now-recognized-as-
/// insufficient, bias). Persisted on the real generated content
/// (`FunctionalFitnessPrescriptionTemplate`/`FunctionalFitnessPrescription`)
/// so the athlete-facing presentation layer renders the real decision
/// that was made at programming time — it never re-derives or guesses
/// this from the phase at render time.
enum FunctionalFitnessSessionArchetype: String, Codable, CaseIterable {
    /// The authored plan's own intended shape, unbiased — a dedicated
    /// Functional-Fitness-performance phase (or fat loss/endurance-event/
    /// transition/no-phase-context), where traditional mixed-modal
    /// programming is already the correct identity. This is the default
    /// for every intent this checkpoint's bias doesn't touch.
    case unbiased
    /// Muscle Gain: Functional Bodybuilding / athletic hypertrophy is the
    /// session's dominant identity. The real loaded strength/accessory
    /// block (rotating squat/hinge/press/pull patterns) leads; composed
    /// conditioning favors loaded compound patterns over pure
    /// monostructural filler and is presented as a subordinate finisher,
    /// never the headline.
    case functionalBodybuilding
    /// Strength: strength/power dominant. The same real strength block
    /// leads; composed conditioning still favors loaded patterns but may
    /// still include a monostructural/conditioning fill ("controlled
    /// conditioning as appropriate") since a Strength phase's own
    /// systemic-demand ceiling is higher than Muscle Gain's — the one
    /// deliberate, real distinction from `.functionalBodybuilding`.
    case strengthPower
    /// Recovery/Maintenance: the existing down-regulation bias — no
    /// strength block, reduced loading/intensity/systemic demand.
    case recoveryConditioning

    /// Athlete-facing label for the presentation layer — real
    /// programming data, not improvised display copy.
    var displayLabel: String {
        switch self {
        case .unbiased: "Functional Fitness"
        case .functionalBodybuilding: "Functional Bodybuilding"
        case .strengthPower: "Strength & Conditioning"
        case .recoveryConditioning: "Recovery Conditioning"
        }
    }

    /// Whether this archetype's own conditioning component is presented
    /// as subordinate to a dominant strength/accessory block, rather than
    /// as the session's own primary identity — never true for `.unbiased`
    /// (there is no dominant block to be subordinate to) or
    /// `.recoveryConditioning` (conditioning, reduced, is the whole
    /// session).
    var conditioningIsSubordinate: Bool {
        switch self {
        case .functionalBodybuilding, .strengthPower: true
        case .unbiased, .recoveryConditioning: false
        }
    }

    /// Whether this archetype prefers `.loaded` movement functions
    /// (squat/hinge/press) over `.gymnastics` ones when both are eligible
    /// for primary coverage — real, athlete-visible movement-selection
    /// bias toward compound loaded patterns, never a fabricated new
    /// `MovementFunction` case.
    var prefersLoadedMovementEmphasis: Bool {
        switch self {
        case .functionalBodybuilding, .strengthPower: true
        case .unbiased, .recoveryConditioning: false
        }
    }
}
