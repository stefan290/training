import Foundation
import SwiftData

/// Turns a `ProgramDefinition`'s frozen template graph into one week's
/// worth of real, dated execution rows (`Day -> Session -> WorkoutBlock ->
/// ExercisePrescription -> SetPrescription`) attached to a `ProgramInstance`
/// — the "ProgramInstance materializes dated executable Sessions from the
/// persisted template" half of the Stage 4 architecture.
///
/// **Scope, stated plainly:** only week 0 (fully resolvable from a tested
/// RM/starting value alone) and the deload week (given week 0's already-
/// resolved values) are implemented. Weeks 1-3 need the *actual* outcome
/// of the previous week — `autoregulatedSetCount`'s live rating,
/// `.autoregulated`'s previous set count — as runtime input; that data
/// doesn't exist until a user has actually trained that week, so
/// materializing it upfront would mean fabricating a rating (exactly the
/// "guess aggressively" Stage 4 explicitly rules out). A real app calls
/// `materializeWeek` again for week N once week N-1's actual results are
/// known — the same per-slot `StrengthProgressionEngine` calls, not a
/// new mechanism, so no additional engine work is needed to extend this
/// later.
///
/// **Calendar placement is naive by design:** each `TemplateSession` lands
/// on a consecutive calendar day starting at the caller-supplied
/// `startDate` (day 0, day 1, day 2, ...). Real preferred-day/availability
/// placement is `ConcurrentScheduler`'s job (Stage 4F), not this system's.
///
/// **No `Recommendation` is persisted.** `Recommendation.reasonCode` is
/// typed to `ProgressionReasonCode` (`DoubleProgressionEngine`'s
/// vocabulary); mapping `StrengthReasonCode` onto it would misrepresent
/// which engine actually produced the value. Resolved values are written
/// directly onto `SetPrescription.targetWeight`/`repRange*` instead,
/// exactly like Stage 1-2's hand-authored seed data — since the engine is
/// pure and deterministic, any later "why" audit can simply re-run it
/// rather than needing a stored explanation. A typed
/// `Recommendation.strengthReasonCode` sibling field (mirroring
/// `WorkoutBlock`'s typed-per-modality pattern) is a reasonable follow-up
/// if that auditability is needed, not a defect of this pass.
///
/// **Stage 4C addition:** every `ExercisePrescription` this materializer
/// creates resolves its exercise through
/// `SubstituteExerciseUseCase.resolvedExercise(for:in:)` rather than
/// reading `slot.resolvedExercise` directly — this is the GOING FORWARD
/// substitution hook (§30): a not-yet-materialized future Session
/// automatically picks up whatever `SlotSelectionOverride` exists for
/// this `instance`/slot at the time it's materialized, with the
/// template's own default as the fallback. Already-materialized Sessions
/// are never revisited by a later override — this function is never
/// called again for a week that's already been materialized.
enum StrengthMaterializer {
    /// Per-slot runtime context the caller must supply — everything the
    /// template graph itself cannot know (it's specific to who's running
    /// the program). `weekOneResolvedWeightKg`/`previousWeekSetCount` are
    /// only consulted for the deload week in this pass's scope; they're
    /// accepted here so the same struct already supports week-N-given-
    /// week-(N-1) materialization once that's built.
    struct SlotContext {
        var rmKilograms: Double?
        var weekOneResolvedWeightKg: Double?
        var previousWeekSetCount: Int?
        var autoregulationRating: Int?

        init(
            rmKilograms: Double? = nil,
            weekOneResolvedWeightKg: Double? = nil,
            previousWeekSetCount: Int? = nil,
            autoregulationRating: Int? = nil
        ) {
            self.rmKilograms = rmKilograms
            self.weekOneResolvedWeightKg = weekOneResolvedWeightKg
            self.previousWeekSetCount = previousWeekSetCount
            self.autoregulationRating = autoregulationRating
        }
    }

    /// The weight resolved for each `ExerciseSlot.id`, keyed so a caller
    /// materializing the deload week can pass week 0's values back in via
    /// `SlotContext.weekOneResolvedWeightKg`.
    typealias ResolvedWeightsBySlotID = [UUID: Double]

    @discardableResult
    static func materializeWeek(
        definition: ProgramDefinition,
        instance: ProgramInstance,
        weekIndex: Int,
        isDeload: Bool,
        startDate: Date,
        ownerUserID: UUID,
        equipmentProfile: EquipmentProfile,
        slotContext: (ExerciseSlot) -> SlotContext,
        context: ModelContext
    ) -> (sessions: [Session], resolvedWeightsBySlotID: ResolvedWeightsBySlotID) {
        let deloadStrategy = SourceCompatibleDeloadStrategy()
        var resolvedWeightsBySlotID: ResolvedWeightsBySlotID = [:]
        // `pairedSlot` is a reference to another `PrescriptionTemplate`
        // (despite the name, it does not point at an `ExerciseSlot`), so
        // looking up a paired slot's just-resolved weight needs a
        // separate map keyed by `PrescriptionTemplate.id` — conflating
        // this with `resolvedWeightsBySlotID` (keyed by `ExerciseSlot.id`,
        // the public, caller-facing identity) was a real bug caught by
        // this file's own tests.
        var resolvedWeightsByTemplateID: [UUID: Double] = [:]
        var sessions: [Session] = []

        let orderedTemplateSessions = definition.orderedTemplateSessions
        for (dayIndex, templateSession) in orderedTemplateSessions.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: dayIndex, to: startDate) ?? startDate
            let day = Day(ownerUserID: ownerUserID, date: date)
            context.insert(day)

            let session = Session(name: templateSession.name, modality: .hypertrophy, status: .scheduled, role: templateSession.role)
            context.insert(session)
            day.addSession(session)
            instance.addSession(session)
            sessions.append(session)

            for blockTemplate in templateSession.orderedBlockTemplates {
                let block = WorkoutBlock(type: blockTemplate.type)
                context.insert(block)
                session.addBlock(block)

                // Primary slots (no `pairedSlot`) resolved before paired
                // slots, so a paired slot's `.linkedToPairedSlot` can read
                // the primary's just-resolved weight in this same pass.
                let orderedTemplates = blockTemplate.orderedPrescriptionTemplates
                    .sorted { ($0.pairedSlot == nil ? 0 : 1) < ($1.pairedSlot == nil ? 0 : 1) }

                for template in orderedTemplates {
                    guard let rules = template.rules, let slot = template.exerciseSlot else { continue }
                    let ctx = slotContext(slot)
                    let pairedResolvedWeight = template.pairedSlot.flatMap { resolvedWeightsByTemplateID[$0.id] }

                    let weightResult: (weightKg: Double?, reasonCode: StrengthReasonCode)
                    let repResult: (repGoal: RepGoal?, reasonCode: StrengthReasonCode)
                    let setResult: (sets: Int?, reasonCode: StrengthReasonCode)

                    if isDeload {
                        weightResult = deloadStrategy.resolveDeloadWeight(
                            rules: rules, dayPositionInWeek: dayIndex, dayCount: orderedTemplateSessions.count,
                            weekOneResolvedWeightKg: ctx.weekOneResolvedWeightKg, equipmentProfile: equipmentProfile
                        )
                        repResult = deloadStrategy.resolveDeloadRepGoal(
                            rules: rules, dayPositionInWeek: dayIndex, dayCount: orderedTemplateSessions.count
                        )
                        setResult = deloadStrategy.resolveDeloadSetCount(rules: rules)
                    } else {
                        weightResult = StrengthProgressionEngine.resolveWeight(
                            rules: rules, weekIndex: weekIndex, rmKilograms: ctx.rmKilograms,
                            weekOneResolvedWeightKg: ctx.weekOneResolvedWeightKg,
                            pairedSlotResolvedWeightKg: pairedResolvedWeight, equipmentProfile: equipmentProfile
                        )
                        repResult = StrengthProgressionEngine.resolveRepGoal(rules: rules, weekIndex: weekIndex)
                        setResult = StrengthProgressionEngine.resolveSetCount(
                            rules: rules, weekIndex: weekIndex,
                            previousWeekSetCount: ctx.previousWeekSetCount, autoregulationRating: ctx.autoregulationRating
                        )
                    }

                    if let weightKg = weightResult.weightKg {
                        resolvedWeightsBySlotID[slot.id] = weightKg
                        resolvedWeightsByTemplateID[template.id] = weightKg
                    }

                    let prescription = ExercisePrescription(exercise: SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance))
                    prescription.sourceExerciseSlot = slot
                    prescription.sourcePrescriptionTemplate = template
                    context.insert(prescription)
                    block.addPrescription(prescription)

                    let setCount = setResult.sets ?? 0
                    // Stage 6D: `RepGoal.toFailure` is already resolved
                    // here — "to failure" is definitionally RIR 0, a
                    // direct translation of data the engine already
                    // produces, never an invented target. No family spec
                    // defines a target for `toFailure == false` (RP's own
                    // notation only ever specifies "X reps to failure" or
                    // a plain rep count — PROGRAM_LOGIC_SPEC.md never
                    // states a non-failure RIR), so that case stays `nil`
                    // rather than guessing one (CLAUDE.md rule 10).
                    let targetRir = (repResult.repGoal?.toFailure == true) ? 0 : nil
                    for _ in 0..<setCount {
                        let setPrescription = SetPrescription(
                            repRangeLow: repResult.repGoal?.reps ?? 0,
                            repRangeHigh: repResult.repGoal?.reps ?? 0,
                            targetWeight: weightResult.weightKg,
                            targetRir: targetRir
                        )
                        context.insert(setPrescription)
                        prescription.addSetPrescription(setPrescription)
                    }
                }
            }
        }

        return (sessions, resolvedWeightsBySlotID)
    }
}
