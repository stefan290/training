import Foundation

// MARK: - Units & preferences

enum WeightUnit: String, Codable, CaseIterable {
    case kilograms
    case pounds
}

// MARK: - Goal

enum GoalType: String, Codable, CaseIterable {
    case muscleGain
    case fatLoss
    case generalStrength
    case enduranceEvent
    case functionalFitness
    case maintenance
}

enum GoalStatus: String, Codable, CaseIterable {
    case active
    case achieved
    case abandoned
}

// MARK: - Plan / Phase

/// Mirrors handoff section 3: Plan DRAFT (proposal, nothing saved) -> ACTIVE -> SUPERSEDED.
enum PlanStatus: String, Codable, CaseIterable {
    case draft
    case active
    case superseded
}

/// A Phase decides which adaptation is prioritised. `custom` exists so the
/// model never blocks a Phase the enum hasn't anticipated; it is not a
/// license to invent new planning behaviour.
enum PhaseType: String, Codable, CaseIterable {
    case muscleGain
    case fatLoss
    case strength
    case enduranceEvent
    case functionalFitness
    case recovery
    case transition
    case maintenance
}

/// Mirrors handoff section 3: Phase PLANNED -> ACTIVE -> COMPLETED / PAUSED / ABANDONED.
enum PhaseStatus: String, Codable, CaseIterable {
    case planned
    case active
    case completed
    case paused
    case abandoned
}

/// Section 8: priority is derived from the active Phase, never asked as a
/// direct question. Stored explicitly so the derivation is inspectable.
enum TrainingPriority: String, Codable, CaseIterable {
    case strength
    case endurance
    case mixedModal
}

// MARK: - Program

enum ProgramSource: String, Codable, CaseIterable {
    case builtIn
    case imported
}

/// Section 9: STRICT is the V1 default. ADAPTIVE must be representable in
/// the schema now even though no adaptive behaviour is implemented yet.
enum AdherenceMode: String, Codable, CaseIterable {
    case strict
    case adaptive
}

// MARK: - Session

/// Mirrors handoff section 3 Session state model. MISSED is derived, never
/// written by a background process; it is included here as a legal value
/// but application code must only assign it when a SCHEDULED session's day
/// has passed, computed at read time or on next app open.
enum SessionStatus: String, Codable, CaseIterable {
    case scheduled
    case inProgress
    case completed
    case skipped
    case missed
    case abandoned
}

/// A high-level tag used for grouping/coloring in the UI. A Session's real
/// composition is its ordered WorkoutBlocks; this enum never drives
/// execution logic, only labels the Session for Today/Plan/Progress.
enum TrainingModality: String, Codable, CaseIterable {
    case strength
    case hypertrophy
    case conditioning
    case functionalFitness
    case hybrid
}

// MARK: - Workout block

/// Mirrors the block-type table in handoff section 2.2 exactly. This is the
/// modality-agnostic execution unit: a Session can chain any of these in any
/// order without special cases.
enum WorkoutBlockType: String, Codable, CaseIterable {
    case warmup
    case strength
    case hypertrophy
    case accessory
    case steadyState
    case intervals
    case amrap
    case emom
    case forTime
    case cooldown
    case mobility
}

enum BlockStatus: String, Codable, CaseIterable {
    case pending
    case active
    case completed
    case skipped
}

/// Section 2.2's "Scoring" column, generalised to a comparable direction
/// rather than one case per block type. NONE means the block is not scored
/// (warmup, cooldown, mobility) and can never produce a PersonalRecord.
enum ScoringDirection: String, Codable, CaseIterable {
    case none
    case higherIsBetter
    case lowerIsBetter
    case completionBased
}

/// Rx and Scaled results are stored as distinct contexts and never compete
/// for the same PersonalRecord.
enum ResultContext: String, Codable, CaseIterable {
    case rx
    case scaled
}

// MARK: - Progression engine reason codes

/// Progression-family reason codes from handoff section 13. Planning,
/// re-entry and import codes are intentionally not modelled yet — those
/// engines are out of scope for this pass. Codes are additive: never rename
/// or repurpose one, since stored Recommendations reference them.
enum ProgressionReasonCode: String, Codable, CaseIterable {
    case loadIncrease
    case repIncrease
    case doubleProgressionIncomplete
    case hold
    case loadDecrease
    case deloadPrescribed
    case percentageOfEstimate
    case calibrationRequired
    case recencyDecay
    case substitutionEstimate
}
