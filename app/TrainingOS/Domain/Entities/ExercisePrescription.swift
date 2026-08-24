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
    /// Stage 6B addition: the `ExerciseSlot` this movement was
    /// materialized from, when known — lets the live Change Exercise flow
    /// validate/rank alternatives through the same `SubstitutionValidator`/
    /// `SlotSelectionOverride` machinery Stage 4C already built, without
    /// re-deriving slot identity from anything else. `nil` for a
    /// prescription created outside the slot-based materializer path (an
    /// ad hoc/seed-authored movement) — Change Exercise stays unavailable
    /// for those rather than inventing an unconstrained substitution
    /// (CLAUDE.md rule 10). The delete rule lives on
    /// `ExerciseSlot.materializedPrescriptions` — this is a plain inverse
    /// property, same pattern as `SlotSelectionOverride.templateSlot`.
    var sourceExerciseSlot: ExerciseSlot?
    /// Stage 6D addition: the `PrescriptionTemplate` this movement was
    /// materialized from, when known — lets live execution resolve
    /// `template.pairedSlot`/`template.referencedAsPairedSlotBy` to know
    /// (a) whether this exercise's own next-week set count is
    /// `.autoregulated` and (b) whether *this* exercise IS some other
    /// slot's paired-slot rating source (`PROGRAM_LOGIC_SPEC.md`
    /// §FAMILY_A/B/C_AUTOREGULATION). `nil` for a prescription
    /// materialized outside the template pipeline (ad hoc/seed-authored),
    /// exactly mirroring `sourceExerciseSlot`'s own reasoning. The delete
    /// rule lives on `PrescriptionTemplate.materializedPrescriptions` —
    /// this is a plain inverse property.
    var sourcePrescriptionTemplate: PrescriptionTemplate?
    /// Stage 6D addition: the -1/0/+1 soreness/difficulty rating the user
    /// reports for this exercise once it's the completed "paired slot" for
    /// some other autoregulated slot — the exact, already-designed engine
    /// input `StrengthProgressionEngine.resolveSetCount`'s `.autoregulated`
    /// case has always accepted (`autoregulationRating`), just never
    /// collected anywhere in Stage 6 execution until now. `nil` until the
    /// user answers the one lightweight prompt this exercise triggers;
    /// never collected for an exercise nothing's set count depends on.
    var autoregulationRating: Int?
    /// Stage 6D Part 7 addition: the `StrengthReasonCode` `StrengthProgressionEngine`
    /// actually produced for THIS prescription's weight/set-count/rep-goal
    /// decision, captured at materialization time rather than re-derived
    /// later. Before this field existed, `StrengthMaterializer`/
    /// `SeedScenarios` computed a reason code alongside every decision and
    /// then discarded it — by the time a user viewed next week's
    /// prescription, this week's "why" was already gone. Populated at the
    /// same two call sites that already compute the value
    /// (`StrengthMaterializer.materializeWeek`,
    /// `SeedScenarios.materializedLowerASession`); `nil` for a prescription
    /// materialized outside that pipeline. This is provenance for an
    /// already-applied decision, never a second decision engine —
    /// `DoubleProgressionEngine`'s own `ProgressionReasonCode` vocabulary
    /// stays untouched and unrelated.
    var appliedLoadReasonCode: StrengthReasonCode?
    /// See `appliedLoadReasonCode` — the reason code for this
    /// prescription's resolved set count.
    var appliedSetCountReasonCode: StrengthReasonCode?
    /// See `appliedLoadReasonCode` — the reason code for this
    /// prescription's resolved rep goal.
    var appliedRepGoalReasonCode: StrengthReasonCode?
    /// Stage 10B.6 addition: the `ProgressionReasonCode` `HypertrophyV2ProgressionEngine`
    /// /`DoubleProgressionEngine` actually produced for THIS prescription's
    /// weight/set-count/rep-goal decision — the Hypertrophy V2 sibling of
    /// `appliedLoadReasonCode` above, kept as its own field rather than
    /// reusing that one because it is typed to a different reason-code
    /// vocabulary (`StrengthMaterializer`'s own doc comment: mapping one
    /// engine's reason codes onto the other would misrepresent which
    /// engine actually produced the value). `nil` for every Family A/B/C
    /// prescription; `appliedLoadReasonCode` stays `nil` for every V2
    /// prescription — the two are mutually exclusive by rule family.
    var appliedProgressionReasonCode: ProgressionReasonCode?

    @Relationship(deleteRule: .cascade, inverse: \SetPrescription.exercisePrescription)
    var setPrescriptions: [SetPrescription] = []

    /// Nullify, not cascade: logged sets must outlive the session-context
    /// prescription they were logged under (the "must never lose a logged
    /// set" invariant applies here too, not only at the Program level).
    @Relationship(deleteRule: .nullify, inverse: \SetResult.exercisePrescription)
    var loggedSetResults: [SetResult] = []

    /// Stage 8B addition: `ReadinessAdaptationDecision.exercisePrescription`'s
    /// required inverse — nothing reads this collection. Same established
    /// "un-inversed to-one reference to a deletable type crashes instead of
    /// nullifying" fix as `sourceExerciseSlot`/`ExerciseSlot
    /// .materializedPrescriptions` above.
    @Relationship(deleteRule: .nullify, inverse: \ReadinessAdaptationDecision.exercisePrescription)
    var readinessAdaptationDecisions: [ReadinessAdaptationDecision] = []

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

    /// Stage 8B addition: `orderedSetPrescriptions` minus any set a Level 2
    /// readiness adaptation marked `isAdaptedAway` — what should actually
    /// be executed/logged/previewed today. `orderedSetPrescriptions` itself
    /// is deliberately left unchanged everywhere else: it must keep meaning
    /// "the true original prescription" so `AutoregulationRatingResolver
    /// .previousWeekSetCount` and any other reader of the full historical
    /// count is never affected by a same-day adaptation
    /// (`READINESS_PROGRESSION_CONTRACT.md` §3/§4).
    var executableSetPrescriptions: [SetPrescription] {
        orderedSetPrescriptions.filter { !$0.isAdaptedAway }
    }
}
