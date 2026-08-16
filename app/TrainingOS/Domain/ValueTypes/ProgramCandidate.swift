import Foundation

/// The 9 factors `PROGRAM_RECOMMENDATION_MODEL.md` §3 names — each a
/// plain boolean-satisfied + note, mirroring `GoalAlignmentFactor`'s
/// exact shape.
enum ProgramFitFactorKind: String, Codable, CaseIterable {
    case phaseGoalMatch
    case availabilityMatch
    case sessionDurationMatch
    case experienceMatch
    case performanceProfileMatch
    case musclePriorityMatch
    case modalityMatch
    case recoveryDemandMatch
    case programAvailabilityMatch
}

struct ProgramFitFactor: Equatable {
    var kind: ProgramFitFactorKind
    var satisfied: Bool
    /// Display copy only — CLAUDE.md rule 16 applies here exactly as it
    /// does to `GoalAlignmentFactor`.
    var note: String

    init(kind: ProgramFitFactorKind, satisfied: Bool, note: String) {
        self.kind = kind
        self.satisfied = satisfied
        self.note = note
    }
}

/// One recommendation unit — always executable. `programDefinition` is
/// NOT optional (Decision 4, Stage 5A): a `ProgramCandidate` is only ever
/// constructed once `ProgramCapabilityRegistry.canInstantiate` has
/// already passed. A conceptually-good path TrainingOS cannot yet
/// execute is a `CapabilityGap`, never a `ProgramCandidate`.
/// `PROGRAM_RECOMMENDATION_MODEL.md` §1.
struct ProgramCandidate {
    var componentLabel: String
    var programmingSystem: ProgrammingSystemKind
    var programDefinition: ProgramDefinition
    /// Reused directly from Stage 4G, never reimplemented —
    /// `PROGRAM_RECOMMENDATION_MODEL.md` §2.
    var fitRating: GoalAlignmentRating
    var factors: [ProgramFitFactor]
    var reasonCodes: [PlannerReasonCode]

    init(
        componentLabel: String,
        programmingSystem: ProgrammingSystemKind,
        programDefinition: ProgramDefinition,
        fitRating: GoalAlignmentRating,
        factors: [ProgramFitFactor],
        reasonCodes: [PlannerReasonCode]
    ) {
        self.componentLabel = componentLabel
        self.programmingSystem = programmingSystem
        self.programDefinition = programDefinition
        self.fitRating = fitRating
        self.factors = factors
        self.reasonCodes = reasonCodes
    }
}
