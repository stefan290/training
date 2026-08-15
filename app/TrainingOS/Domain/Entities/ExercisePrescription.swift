import Foundation
import SwiftData

/// One movement inside a WorkoutBlock: which canonical Exercise, in what
/// order, and what is prescribed for it. For STRENGTH/HYPERTROPHY/ACCESSORY
/// blocks the prescription is expressed per set via `setPrescriptions`. For
/// AMRAP/FOR_TIME blocks it is a rep count per round. For STEADY_STATE/
/// INTERVALS it is a target duration. Only the fields relevant to the
/// block's type are populated; this mirrors the handoff's "Movement"
/// concept without introducing a separate entity.
@Model
final class ExercisePrescription {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var exercise: Exercise?
    /// Stable position among a block's movements, assigned by
    /// `WorkoutBlock.addPrescription(_:)`.
    var sortIndex: Int

    /// AMRAP / For Time: reps prescribed per round for this movement.
    var repsPerRound: Int?
    /// Steady state / intervals: target duration for this movement.
    var targetDurationSeconds: Int?
    /// Whether the user substituted a different exercise than prescribed
    /// (e.g. scaling Toes-to-Bar to Knee Raises). Recorded, never assumed
    /// permanent — handoff's scaling-is-sticky-but-not-assumed rule.
    var substitutionUsed: Bool
    /// Stage 4C addition: why, if `substitutionUsed`. This is the THIS
    /// SESSION ONLY substitution scope's entire persisted footprint —
    /// deliberately just these two existing/additive fields, not a new
    /// entity; see `SlotSelectionOverride`'s doc comment for why GOING
    /// FORWARD needs a different mechanism and this one doesn't.
    var substitutionReason: SubstitutionReason?

    @Relationship(deleteRule: .cascade, inverse: \SetPrescription.exercisePrescription)
    var setPrescriptions: [SetPrescription] = []

    /// Nullify, not cascade: logged sets must outlive the session-context
    /// prescription they were logged under (the "must never lose a logged
    /// set" invariant applies here too, not only at the Program level).
    @Relationship(deleteRule: .nullify, inverse: \SetResult.exercisePrescription)
    var loggedSetResults: [SetResult] = []

    init(
        id: UUID = UUID(),
        exercise: Exercise? = nil,
        repsPerRound: Int? = nil,
        targetDurationSeconds: Int? = nil,
        substitutionUsed: Bool = false,
        substitutionReason: SubstitutionReason? = nil
    ) {
        self.id = id
        self.exercise = exercise
        self.sortIndex = 0
        self.repsPerRound = repsPerRound
        self.targetDurationSeconds = targetDurationSeconds
        self.substitutionUsed = substitutionUsed
        self.substitutionReason = substitutionReason
    }

    /// The only way application code should attach a SetPrescription (a
    /// target set) to a movement. Mutates exactly one side; SwiftData
    /// maintains `setPrescription.exercisePrescription` from the declared
    /// inverse.
    func addSetPrescription(_ prescription: SetPrescription) {
        prescription.sortIndex = setPrescriptions.count
        setPrescriptions.append(prescription)
    }

    /// The only way application code should attach a logged SetResult to
    /// the movement it was performed against (session context, as opposed
    /// to the permanent history in ExercisePerformanceProfile). Mutates
    /// exactly one side; SwiftData maintains the inverse.
    func addLoggedSetResult(_ result: SetResult) {
        loggedSetResults.append(result)
    }

    var orderedSetPrescriptions: [SetPrescription] {
        setPrescriptions.sorted { $0.sortIndex < $1.sortIndex }
    }
}
