import Foundation
import SwiftData

/// Stage 8B: the audit trail for one same-day readiness adaptation —
/// a dedicated sibling to `PlannerDecision`, not an extension of it
/// (`PlannerDecision`'s back-references are entirely strategic-layer and
/// never reach `Session`/`WorkoutBlock`/`ExercisePrescription` level;
/// widening it would overload a type scoped for a different layer,
/// exactly the CLAUDE.md rule 18 discipline applied to a new type
/// instead of an existing one — Stage 8A decision D8).
///
/// **This entity is readiness-specific, by design, permanently — not a
/// general "session-local adaptation" record.** A future Training
/// Environment / Equipment Profile feature (deferred,
/// `READINESS_DECISION_MODEL.md` §7) needs its own sibling provenance
/// type for equipment/environment-driven substitutions and reductions;
/// it must never be folded into this one.
///
/// Typed original/proposed value pairs, never opaque display strings
/// (Stage 8A decision D10) — only the pair relevant to `actionKind` is
/// populated; display copy is generated from these fields, never the
/// other way around.
///
/// `setPrescription`/`exercisePrescription`/`functionalFitnessMovement`/
/// `workoutBlock` mirror `PlannerDecision`'s own "multiple optional typed
/// back-references, as many as are relevant" shape rather than an unsafe
/// enum-with-payload holding a `@Model` reference.
@Model
final class ReadinessAdaptationDecision {
    @Attribute(.unique) var id: UUID
    var decidedAt: Date
    var triggeringSignals: [ReadinessSignalSource]
    var actionKind: ReadinessActionKind
    var userResponse: UserAdaptationResponse
    var explanation: String

    // MARK: Typed original/proposed values — only the relevant pair is set.

    /// Level 2 (set-count reduction): the prescribed count before/after.
    var originalSetCount: Int?
    var proposedSetCount: Int?

    /// Level 2 (load reduction) — schema-complete per Stage 8A decision
    /// D10, but never populated by `EvaluateReadinessAdaptationUseCase` in
    /// Stage 8B (see `ReadinessActionKind.loadReduced`'s own doc comment).
    var originalWeight: Double?
    var proposedWeight: Double?

    /// Level 3 (substitution): which canonical Exercise before/after.
    var originalExercise: Exercise?
    var proposedExercise: Exercise?

    // MARK: Back-references — as many as are relevant are set. Each
    // referenced type declares the required inverse (a `.nullify` array
    // nothing reads) so a cascade-deleted Session/Block/Prescription
    // nullifies cleanly instead of crashing — the same established fix as
    // `ExercisePrescription.sourceExerciseSlot`/`ExerciseSlot
    // .materializedPrescriptions` (`DELETE_RULE_MATRIX.md`'s
    // "One-directional references" section).

    var exercisePrescription: ExercisePrescription?
    var functionalFitnessMovement: FunctionalFitnessMovement?
    var workoutBlock: WorkoutBlock?
    var readinessCheckIn: ReadinessCheckIn?

    init(
        id: UUID = UUID(),
        decidedAt: Date,
        triggeringSignals: [ReadinessSignalSource],
        actionKind: ReadinessActionKind,
        userResponse: UserAdaptationResponse,
        explanation: String,
        originalSetCount: Int? = nil,
        proposedSetCount: Int? = nil,
        originalWeight: Double? = nil,
        proposedWeight: Double? = nil,
        originalExercise: Exercise? = nil,
        proposedExercise: Exercise? = nil,
        exercisePrescription: ExercisePrescription? = nil,
        functionalFitnessMovement: FunctionalFitnessMovement? = nil,
        workoutBlock: WorkoutBlock? = nil,
        readinessCheckIn: ReadinessCheckIn? = nil
    ) {
        self.id = id
        self.decidedAt = decidedAt
        self.triggeringSignals = triggeringSignals
        self.actionKind = actionKind
        self.userResponse = userResponse
        self.explanation = explanation
        self.originalSetCount = originalSetCount
        self.proposedSetCount = proposedSetCount
        self.originalWeight = originalWeight
        self.proposedWeight = proposedWeight
        self.originalExercise = originalExercise
        self.proposedExercise = proposedExercise
        self.exercisePrescription = exercisePrescription
        self.functionalFitnessMovement = functionalFitnessMovement
        self.workoutBlock = workoutBlock
        self.readinessCheckIn = readinessCheckIn
    }
}
