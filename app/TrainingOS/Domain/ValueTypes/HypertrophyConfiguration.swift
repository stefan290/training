import Foundation

/// The day-split pattern a `HypertrophyProgramConfiguration` uses.
/// `.fullBody` trains every major group every session; the specialization
/// splits bias volume toward one region while still training everything
/// else at maintenance volume (`PROGRAM_FAMILY_MATRIX.md`). "Novice" is
/// deliberately not a case here — Stage 4 research confirmed no isolable
/// novice-specific mechanism exists in Family A; novice-configured variants
/// are the same rules at a lower `dayCount`, nothing more.
enum HypertrophySplit: String, Codable, CaseIterable {
    case fullBody
    case legs
    case armsShoulders
    case backChest
}

/// The three phases of the approved Hypertrophy `ProgramJourney`
/// (Basic Hypertrophy -> Metabolite Focus -> Resensitization). Each phase
/// is a fully independent `ProgramDefinition` — this enum only tags which
/// rule-parameterization a given definition used; only
/// `TrainingPlan.orderedPhases` (pre-existing) does the actual sequencing —
/// see Stage 3 decision A1 and `TrainingPhase.swift`'s "ProgramJourney
/// note."
enum HypertrophyPhaseType: String, Codable, CaseIterable {
    case basicHypertrophy
    case metaboliteFocus
    case resensitization
}

/// The full "recipe" `HypertrophyProgramGenerator` needs to produce a
/// template graph — the "Configuration = recipe" half of the Stage 4
/// architecture. Deliberately just data: no rule logic lives here, only
/// what the generator needs to pick day count / split / phase-specific
/// multipliers.
struct HypertrophyProgramConfiguration: Codable, Equatable {
    var dayCount: Int
    var split: HypertrophySplit
    var phaseType: HypertrophyPhaseType
}
