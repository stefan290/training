import Foundation
import SwiftData

/// Stage 8B: what the user reported before starting one Session. One
/// per Session at most (`Session.readinessCheckIn`) — per-Session, not
/// per-block/modality (Stage 8A decision D1). A skipped check-in is
/// `nil` on the Session, never a row with defaulted-to-good fields
/// (`READINESS_MODEL.md` §5) — that distinction is what keeps a later
/// "you reported low energy" explanation honest.
///
/// Every field is a typed, closed value (`ReadinessLevel` ordinal,
/// `MuscleGroup` arrays) rather than free text or a derived summary —
/// this is what lets future longitudinal queries (repeated poor sleep,
/// recurring pain in the same area, etc.) run directly against this
/// history later without a schema migration (Stage 8A decision D10).
///
/// `reportedPain` and `reportedStiffness` are two permanently separate
/// arrays, never one combined field — pain/injury and stiffness/mobility
/// limitation stay distinguishable readiness signals even though the UI
/// reaches both through one shared Tier 0.5 gateway question ("Pain or
/// stiffness today?") — Stage 8A decision D2. Neither is ever populated
/// by inference from the other, from `soreMuscleGroups`, or from
/// `overallRecovery`.
@Model
final class ReadinessCheckIn {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var sleep: ReadinessLevel?
    var energy: ReadinessLevel?
    var overallRecovery: ReadinessLevel?
    var soreMuscleGroups: [MuscleGroup]
    var reportedPain: [MuscleGroup]
    var reportedStiffness: [MuscleGroup]

    /// Plain inverse — the owning `@Relationship` is declared on
    /// `Session.readinessCheckIn` (mirrors `WorkoutBlock.result`/
    /// `WorkoutResult.workoutBlock`'s exact shape).
    var session: Session?

    /// `ReadinessAdaptationDecision.readinessCheckIn`'s required inverse —
    /// nothing reads this collection. Same established fix as
    /// `ExercisePrescription.readinessAdaptationDecisions`; `.nullify`
    /// because a decision's own fields already carry everything needed to
    /// explain it (mirrors `PersonalRecord`'s "copy the value, keep the
    /// pointer as traceability only" pattern) — it must survive even if
    /// this check-in is ever deleted.
    @Relationship(deleteRule: .nullify, inverse: \ReadinessAdaptationDecision.readinessCheckIn)
    var adaptationDecisions: [ReadinessAdaptationDecision] = []

    init(
        id: UUID = UUID(),
        recordedAt: Date,
        sleep: ReadinessLevel? = nil,
        energy: ReadinessLevel? = nil,
        overallRecovery: ReadinessLevel? = nil,
        soreMuscleGroups: [MuscleGroup] = [],
        reportedPain: [MuscleGroup] = [],
        reportedStiffness: [MuscleGroup] = []
    ) {
        self.id = id
        self.recordedAt = recordedAt
        self.sleep = sleep
        self.energy = energy
        self.overallRecovery = overallRecovery
        self.soreMuscleGroups = soreMuscleGroups
        self.reportedPain = reportedPain
        self.reportedStiffness = reportedStiffness
    }

    /// True only when every answered signal is at/above neutral and
    /// nothing was reported for pain/stiffness/soreness — the "everything
    /// looks good" fast-path outcome. A check-in with every field `nil`
    /// (nothing answered at all, but not skipped outright) also reads as
    /// "no signal available," never as an implicit good report — callers
    /// that need to distinguish "actively confirmed good" from "answered
    /// nothing" should inspect the individual fields directly.
    var hasNoAdverseSignal: Bool {
        let levels = [sleep, energy, overallRecovery].compactMap { $0 }
        let allLevelsNeutralOrBetter = levels.allSatisfy { $0.rawValue >= ReadinessLevel.ok.rawValue }
        return allLevelsNeutralOrBetter && soreMuscleGroups.isEmpty && reportedPain.isEmpty && reportedStiffness.isEmpty
    }
}
