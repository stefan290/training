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
        /// Stage 10B.6 additions — only populated by
        /// `RollTacticalWindowUseCase.strengthSlotContext` for a
        /// `.doubleProgression` template; `nil` for every legacy
        /// Family A/B/C slot. Pre-resolved by the caller (which already
        /// has `performanceProfile` in scope) rather than resolved inside
        /// this materializer, matching this struct's own documented
        /// contract: "everything the template graph itself cannot know."
        var doubleProgressionWeightKg: Double?
        var doubleProgressionReasonCode: ProgressionReasonCode?
        var doubleProgressionRepGoal: RepGoal?
        var doubleProgressionSetCount: Int?

        init(
            rmKilograms: Double? = nil,
            weekOneResolvedWeightKg: Double? = nil,
            previousWeekSetCount: Int? = nil,
            autoregulationRating: Int? = nil,
            doubleProgressionWeightKg: Double? = nil,
            doubleProgressionReasonCode: ProgressionReasonCode? = nil,
            doubleProgressionRepGoal: RepGoal? = nil,
            doubleProgressionSetCount: Int? = nil
        ) {
            self.rmKilograms = rmKilograms
            self.weekOneResolvedWeightKg = weekOneResolvedWeightKg
            self.previousWeekSetCount = previousWeekSetCount
            self.autoregulationRating = autoregulationRating
            self.doubleProgressionWeightKg = doubleProgressionWeightKg
            self.doubleProgressionReasonCode = doubleProgressionReasonCode
            self.doubleProgressionRepGoal = doubleProgressionRepGoal
            self.doubleProgressionSetCount = doubleProgressionSetCount
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

                // Templates whose *load* actually depends on another
                // slot's just-resolved weight (`loadRuleKind == .linkedToPairedSlot`)
                // are resolved last, so that dependency is always available
                // in this same pass. Keyed on `loadRuleKind` specifically —
                // NOT on `pairedSlot == nil` — because `pairedSlot` is also
                // legitimately set on a *primary* template purely as its
                // own autoregulation rating source (see
                // `HypertrophyProgramGenerator`), which carries no load-
                // resolution-order requirement at all.
                let orderedTemplates = blockTemplate.orderedPrescriptionTemplates
                    .sorted { ($0.loadRuleKind == .linkedToPairedSlot ? 1 : 0) < ($1.loadRuleKind == .linkedToPairedSlot ? 1 : 0) }

                for template in orderedTemplates {
                    guard let rules = template.rules, let slot = template.exerciseSlot else { continue }
                    let ctx = slotContext(slot)
                    let pairedResolvedWeight = template.pairedSlot.flatMap { resolvedWeightsByTemplateID[$0.id] }
                    let resolvedExercise = SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance)

                    let weightKg: Double?
                    let repGoal: RepGoal?
                    let setCount: Int?
                    let loadReasonCode: StrengthReasonCode?
                    let setCountReasonCode: StrengthReasonCode?
                    let repGoalReasonCode: StrengthReasonCode?
                    let progressionReasonCode: ProgressionReasonCode?

                    // Stage 10B.6: Hypertrophy V2 templates resolve
                    // entirely through their own engine (already computed
                    // by the caller's `slotContext` — see `SlotContext`'s
                    // doc comment) — never through `StrengthProgressionEngine`/
                    // `SourceCompatibleDeloadStrategy`, regardless of
                    // `isDeload`. Family A/B/C templates never carry this
                    // load rule kind, so the branch below is unreachable
                    // for them.
                    if rules.loadRule == .doubleProgression {
                        weightKg = ctx.doubleProgressionWeightKg
                        progressionReasonCode = ctx.doubleProgressionReasonCode
                        repGoal = ctx.doubleProgressionRepGoal
                        setCount = ctx.doubleProgressionSetCount
                        loadReasonCode = nil
                        setCountReasonCode = nil
                        repGoalReasonCode = nil
                    } else if isDeload {
                        let weightResult = deloadStrategy.resolveDeloadWeight(
                            rules: rules, dayPositionInWeek: dayIndex, dayCount: orderedTemplateSessions.count,
                            weekOneResolvedWeightKg: ctx.weekOneResolvedWeightKg, equipmentProfile: equipmentProfile
                        )
                        let repResult = deloadStrategy.resolveDeloadRepGoal(
                            rules: rules, dayPositionInWeek: dayIndex, dayCount: orderedTemplateSessions.count
                        )
                        let setResult = deloadStrategy.resolveDeloadSetCount(rules: rules)
                        weightKg = weightResult.weightKg
                        repGoal = repResult.repGoal
                        setCount = setResult.sets
                        loadReasonCode = weightResult.reasonCode
                        repGoalReasonCode = repResult.reasonCode
                        setCountReasonCode = setResult.reasonCode
                        progressionReasonCode = nil
                    } else {
                        let weightResult = StrengthProgressionEngine.resolveWeight(
                            rules: rules, weekIndex: weekIndex, rmKilograms: ctx.rmKilograms,
                            weekOneResolvedWeightKg: ctx.weekOneResolvedWeightKg,
                            pairedSlotResolvedWeightKg: pairedResolvedWeight, equipmentProfile: equipmentProfile
                        )
                        let repResult = StrengthProgressionEngine.resolveRepGoal(rules: rules, weekIndex: weekIndex)
                        let setResult = StrengthProgressionEngine.resolveSetCount(
                            rules: rules, weekIndex: weekIndex,
                            previousWeekSetCount: ctx.previousWeekSetCount, autoregulationRating: ctx.autoregulationRating
                        )
                        weightKg = weightResult.weightKg
                        repGoal = repResult.repGoal
                        setCount = setResult.sets
                        loadReasonCode = weightResult.reasonCode
                        repGoalReasonCode = repResult.reasonCode
                        setCountReasonCode = setResult.reasonCode
                        progressionReasonCode = nil
                    }

                    if let weightKg {
                        resolvedWeightsBySlotID[slot.id] = weightKg
                        resolvedWeightsByTemplateID[template.id] = weightKg
                    }

                    let prescription = ExercisePrescription(exercise: resolvedExercise)
                    prescription.sourceExerciseSlot = slot
                    prescription.sourcePrescriptionTemplate = template
                    // Stage 6D Part 7 / Stage 10B.6: capture the reason
                    // codes the engine already computed for this
                    // decision, at the one moment they're available —
                    // never re-derived later.
                    prescription.appliedLoadReasonCode = loadReasonCode
                    prescription.appliedSetCountReasonCode = setCountReasonCode
                    prescription.appliedRepGoalReasonCode = repGoalReasonCode
                    prescription.appliedProgressionReasonCode = progressionReasonCode
                    context.insert(prescription)
                    block.addPrescription(prescription)

                    let finalSetCount = setCount ?? 0
                    // Stage 10R.1D: a `RepGoal` is now one of two distinct
                    // kinds — a genuine fixed rep count, or an RIR/effort
                    // target with no rep count at all — never collapsed
                    // into one fabricated number. `targetRir` is the
                    // explicit RIR value for `.rir`, or Hypertrophy V2's
                    // separate explicit companion value for `.fixedReps`
                    // (nil for every Family A/B/C `.fixedReps` row, e.g.
                    // Powerlifting's Triples). `repRangeLow`/`repRangeHigh`
                    // are nil whenever there is no fixed rep count to show
                    // (an RIR-only prescription, or a deload set whose rep
                    // target could not be resolved — `repGoal == nil`).
                    let resolvedRepRangeLow: Int?
                    let resolvedRepRangeHigh: Int?
                    let resolvedTargetRir: Int?
                    switch repGoal?.prescription {
                    case .fixedReps(let n):
                        resolvedRepRangeLow = n
                        resolvedRepRangeHigh = repGoal?.repRangeHigh ?? n
                        resolvedTargetRir = repGoal?.targetRir
                    case .rir(let n):
                        resolvedRepRangeLow = nil
                        resolvedRepRangeHigh = nil
                        resolvedTargetRir = n
                    case nil:
                        resolvedRepRangeLow = nil
                        resolvedRepRangeHigh = nil
                        resolvedTargetRir = nil
                    }
                    for _ in 0..<finalSetCount {
                        let setPrescription = SetPrescription(
                            repRangeLow: resolvedRepRangeLow,
                            repRangeHigh: resolvedRepRangeHigh,
                            targetWeight: weightKg,
                            targetRir: resolvedTargetRir
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
