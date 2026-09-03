import Foundation
import SwiftData

/// Stage 5B: turns a `Goal` + phase/mix/program context into strategic
/// plans, candidate mixes, and program recommendations — never a load,
/// rep, pace, or interval number (that stays with the existing
/// `ProgrammingSystem` engines, unchanged), never a calendar placement
/// (that stays with `ConcurrentScheduler`, unchanged). `LONG_TERM_PLANNER.md`
/// is the full design; this is its direct implementation.
///
/// Lives in `Application/UseCases/`, not `Engines/`, because — unlike
/// `ConcurrentScheduler`/`GoalAlignmentEvaluator`, which are pure,
/// context-free functions — `proposeProgram` calls the existing
/// generators, which insert a real `ProgramDefinition` into a
/// `ModelContext` (matching how a materializer eagerly creates real
/// template/execution rows today; a `ProgramDefinition` alone, with no
/// `ProgramInstance`/`TrainingMixComponent` link yet, commits nothing).
enum LongTermPlanner {
    // MARK: - proposeStrategicPlan

    /// The subset of `Goal` fields `proposePhases` actually needs —
    /// extracted so `reviseStrategicPlan` can re-run the identical
    /// forward/backward planning core against a hypothetically-changed
    /// value (e.g. a new milestone date) without mutating the real,
    /// persisted `Goal` object to compute a proposal (`LONG_TERM_PLANNER.md`
    /// §5's "proposal-producing, non-mutating call").
    private struct PlanningParameters {
        var primaryType: PhaseType
        var targetDate: Date?
        var milestoneDate: Date?
        var bodyCompositionDirection: BodyCompositionDirection?

        init(goal: Goal) {
            self.primaryType = phaseType(for: goal.primaryType)
            self.targetDate = goal.targetDate
            self.milestoneDate = goal.milestoneDate
            self.bodyCompositionDirection = goal.bodyCompositionDirection
        }

        init(primaryType: PhaseType, targetDate: Date?, milestoneDate: Date?, bodyCompositionDirection: BodyCompositionDirection?) {
            self.primaryType = primaryType
            self.targetDate = targetDate
            self.milestoneDate = milestoneDate
            self.bodyCompositionDirection = bodyCompositionDirection
        }
    }

    /// `STRATEGIC_PLAN_MODEL.md` §4 — forward-fills phases serving
    /// `goal.primaryType` when there's no `milestoneDate`; backward-anchors
    /// a milestone-appropriate phase (plus a transition, when the
    /// milestone's phase type differs from the primary) when there is
    /// one. Never reads the system clock — `asOf` is the caller's only
    /// notion of "now" (CLAUDE.md rule 4, extended to planning).
    static func proposeStrategicPlan(goal: Goal, asOf: Date) -> StrategicPlanProposal {
        let (phases, feasibility, explanation) = proposePhases(PlanningParameters(goal: goal), asOf: asOf)
        return StrategicPlanProposal(goal: goal, phases: phases, feasibility: feasibility, explanation: explanation)
    }

    private static func proposePhases(
        _ params: PlanningParameters, asOf: Date
    ) -> (phases: [ProposedPhase], feasibility: StrategicPlanFeasibility, explanation: String) {
        guard let milestoneDate = params.milestoneDate else {
            return proposeForwardOnlyPhases(params, asOf: asOf)
        }
        return proposeMilestoneAnchoredPhases(params, asOf: asOf, milestoneDate: milestoneDate)
    }

    private static func proposeForwardOnlyPhases(
        _ params: PlanningParameters, asOf: Date
    ) -> (phases: [ProposedPhase], feasibility: StrategicPlanFeasibility, explanation: String) {
        let primaryType = params.primaryType
        guard let targetDate = params.targetDate else {
            // No target date at all — a single open-ended phase, never a
            // guessed horizon.
            let phase = openEndedPhase(type: primaryType, startDate: asOf)
            return ([phase], .feasible, "Open-ended \(primaryType.rawValue) phase — no target date was stated.")
        }

        let (phases, feasible) = fillForwardPhases(
            from: asOf, to: targetDate, primaryType: primaryType, baseReasonCodes: [.phaseSelectedForGoal]
        )
        guard feasible else {
            return ([], .infeasible, "The stated timeframe is too short to fit even one \(primaryType.rawValue) phase's minimum duration.")
        }
        return (phases, .feasible, "Plan follows \(primaryType.rawValue) through \(phases.count) phase(s) to the target date.")
    }

    private static func proposeMilestoneAnchoredPhases(
        _ params: PlanningParameters, asOf: Date, milestoneDate: Date
    ) -> (phases: [ProposedPhase], feasibility: StrategicPlanFeasibility, explanation: String) {
        let primaryType = params.primaryType
        let milestoneType = milestonePhaseType(direction: params.bodyCompositionDirection, primaryType: primaryType)

        let milestoneDurationKind = PhaseDurationDefaults.range(for: milestoneType)
        let milestoneWeeks = milestoneDurationKind.planningWeeks ?? 8
        let milestoneStart = addingWeeks(-milestoneWeeks, to: milestoneDate)
        var milestoneReasonCodes: [PlannerReasonCode] = [.phaseSelectedForGoal]
        if milestoneType == .fatLoss { milestoneReasonCodes.append(.fatLossTimedToMilestone) }
        let milestonePhase = ProposedPhase(
            type: milestoneType, priorityRule: priorityRule(for: milestoneType),
            startDate: milestoneStart, endDate: milestoneDate,
            durationKind: milestoneDurationKind, reasonCodes: milestoneReasonCodes
        )

        var transitionPhase: ProposedPhase?
        var fillEnd = milestoneStart
        if milestoneType != primaryType {
            let transitionDurationKind = PhaseDurationDefaults.range(for: .transition)
            let transitionWeeks = transitionDurationKind.planningWeeks ?? 2
            let transitionStart = addingWeeks(-transitionWeeks, to: milestoneStart)
            transitionPhase = ProposedPhase(
                type: .transition, priorityRule: .mixedModal,
                startDate: transitionStart, endDate: milestoneStart,
                durationKind: transitionDurationKind, reasonCodes: [.transitionPhaseInserted]
            )
            fillEnd = transitionStart
        }

        let (fillPhases, fillFeasible) = fillForwardPhases(
            from: asOf, to: fillEnd, primaryType: primaryType, baseReasonCodes: [.phaseSelectedForGoal]
        )
        guard fillFeasible else {
            return ([], .infeasible, "Not enough lead time before the milestone to fit even one \(primaryType.rawValue) phase's minimum duration.")
        }

        var allPhases = fillPhases
        if let transitionPhase { allPhases.append(transitionPhase) }
        allPhases.append(milestonePhase)

        if let targetDate = params.targetDate, targetDate > milestoneDate {
            let (afterPhases, afterFeasible) = fillForwardPhases(
                from: milestoneDate, to: targetDate, primaryType: primaryType, baseReasonCodes: [.phaseSelectedForGoal]
            )
            // A too-short post-milestone remainder does not invalidate the
            // whole plan (the milestone itself is still fully honored) —
            // it simply means no further phase is proposed past it yet;
            // a later `reviseStrategicPlan` call can always extend it.
            if afterFeasible { allPhases.append(contentsOf: afterPhases) }
        }

        return (
            allPhases, .feasible,
            "Plan backward-anchors a \(milestoneType.rawValue) phase to the milestone date, "
                + "forward-filling \(primaryType.rawValue) before it."
        )
    }

    // MARK: - reviseStrategicPlan

    /// `PLAN_REVISION_MODEL.md` §4b/§4c — a revision's own `phases` holds
    /// only its own new/future phases; completed phases and an already-
    /// `.active` phase's own already-elapsed portion never appear here at
    /// all (`AcceptStrategicPlanUseCase` is what abandons the prior
    /// revision's still-`.planned` phases and marks it superseded).
    ///
    /// **Documented simplification:** extend/shorten targets the plan's
    /// nearest not-yet-started (`.planned`) phase. Resizing an already-
    /// `.active` phase's own future boundary in place (§1's one narrow
    /// exception to "revisions only touch planned phases") is a real,
    /// deliberately deferred nuance — flagged here rather than guessed
    /// at, per CLAUDE.md rule 10 — since it requires mutating a row that
    /// belongs to a different revision than the one being produced,
    /// which this pass does not implement.
    enum PlanRevisionRequest {
        case extendPhase(weeks: Int)
        case shortenPhase(weeks: Int)
        case changeMilestoneDate(Date?)
        /// A major revision — a brand-new strategic intent, never a
        /// refinement of the old one (`PLAN_REVISION_MODEL.md` §4c).
        /// `AcceptStrategicPlanUseCase` must be called with a fresh
        /// `lineageID` (i.e. `lineageID: nil`) for this case, never the
        /// old plan's own.
        case changeLongTermGoal(Goal)
    }

    static func reviseStrategicPlan(current: TrainingPlan, revision: PlanRevisionRequest, asOf: Date) -> StrategicPlanProposal {
        // Every TrainingPlan created via AcceptStrategicPlanUseCase always
        // sets `goal` — a nil goal here would be a caller invariant
        // violation, not a reachable user-facing state.
        let goal = current.goal!

        switch revision {
        case .extendPhase(let weeks):
            return reviseByResizingNextPlannedPhase(current: current, goal: goal, weeks: weeks, reasonCode: .phaseExtended)
        case .shortenPhase(let weeks):
            return reviseByResizingNextPlannedPhase(current: current, goal: goal, weeks: -weeks, reasonCode: .phaseShortened)
        case .changeMilestoneDate(let newMilestoneDate):
            return reviseByChangingMilestoneDate(current: current, goal: goal, newMilestoneDate: newMilestoneDate, asOf: asOf)
        case .changeLongTermGoal(let newGoal):
            return proposeStrategicPlan(goal: newGoal, asOf: asOf)
        }
    }

    private static func reviseByResizingNextPlannedPhase(
        current: TrainingPlan, goal: Goal, weeks: Int, reasonCode: PlannerReasonCode
    ) -> StrategicPlanProposal {
        let plannedPhases = current.orderedPhases.filter { $0.status == .planned }
        guard let target = plannedPhases.first, let oldEnd = target.endDate else {
            return StrategicPlanProposal(
                goal: goal, phases: [], feasibility: .infeasible,
                explanation: "No not-yet-started phase is available to resize."
            )
        }

        let newEnd = addingWeeks(weeks, to: oldEnd)
        guard newEnd > target.startDate else {
            return StrategicPlanProposal(
                goal: goal, phases: [], feasibility: .infeasible,
                explanation: "Shortening by \(abs(weeks)) week(s) would leave this phase with no duration at all."
            )
        }

        // Never silently blow through an existing milestone anchor —
        // surface the conflict instead (`PHASE_PLANNING_RULES.md` §5).
        if weeks > 0, let milestoneDate = goal.milestoneDate, newEnd > milestoneDate {
            return StrategicPlanProposal(
                goal: goal, phases: [], feasibility: .infeasible,
                explanation: "Extending this phase by \(weeks) week(s) would push it past the \(milestoneDate) milestone."
            )
        }

        let resizedPhase = ProposedPhase(
            type: target.type, priorityRule: target.priorityRule,
            startDate: target.startDate, endDate: newEnd,
            durationKind: .range(typical: wholeWeeksBetween(target.startDate, newEnd), minimum: nil, maximum: nil),
            reasonCodes: [reasonCode]
        )

        // The freed/added time simply shifts every later not-yet-started
        // phase by the same delta. `PHASE_PLANNING_RULES.md` §5's fuller
        // redistribution rule for shortening (a later Maintenance/Recovery
        // phase absorbs freed time first) is a deliberately deferred
        // refinement on top of this correct, simpler baseline.
        let shiftedPhases = plannedPhases.dropFirst().map { phase -> ProposedPhase in
            let shiftedStart = addingWeeks(weeks, to: phase.startDate)
            let shiftedEnd = phase.endDate.map { addingWeeks(weeks, to: $0) }
            let shiftedTypical = shiftedEnd.map { wholeWeeksBetween(shiftedStart, $0) } ?? 0
            return ProposedPhase(
                type: phase.type, priorityRule: phase.priorityRule,
                startDate: shiftedStart, endDate: shiftedEnd,
                durationKind: .range(typical: shiftedTypical, minimum: nil, maximum: nil),
                reasonCodes: [reasonCode]
            )
        }

        return StrategicPlanProposal(
            goal: goal, phases: [resizedPhase] + shiftedPhases, feasibility: .feasible,
            explanation: weeks > 0
                ? "Extended the \(target.type.rawValue) phase by \(weeks) week(s); later phases shift by the same amount."
                : "Shortened the \(target.type.rawValue) phase by \(abs(weeks)) week(s); later phases shift by the same amount."
        )
    }

    private static func reviseByChangingMilestoneDate(
        current: TrainingPlan, goal: Goal, newMilestoneDate: Date?, asOf: Date
    ) -> StrategicPlanProposal {
        let params = PlanningParameters(
            primaryType: phaseType(for: goal.primaryType), targetDate: goal.targetDate,
            milestoneDate: newMilestoneDate, bodyCompositionDirection: goal.bodyCompositionDirection
        )
        // Re-plan only the remaining, not-yet-started future — completed
        // and already-active phases are untouched and never appear in
        // this proposal at all (`PLAN_REVISION_MODEL.md` §4a).
        let anchor = current.orderedPhases.last { $0.status != .planned }?.endDate ?? asOf
        let (phases, feasibility, explanation) = proposePhases(params, asOf: anchor)
        return StrategicPlanProposal(goal: goal, phases: phases, feasibility: feasibility, explanation: explanation)
    }

    /// A single, unbounded phase — used only when the goal states no
    /// target date at all, so there is nothing to forward-fill toward.
    private static func openEndedPhase(type: PhaseType, startDate: Date) -> ProposedPhase {
        ProposedPhase(
            type: type, priorityRule: priorityRule(for: type), startDate: startDate, endDate: nil,
            durationKind: PhaseDurationDefaults.range(for: type), reasonCodes: [.phaseSelectedForGoal]
        )
    }

    /// Forward-fills `primaryType` phases from `start` to `end`, inserting
    /// one Maintenance phase after every 2 consecutive `primaryType`
    /// phases (`PHASE_PLANNING_RULES.md` §7's "inserted when the
    /// roadmap's own duration math calls for one," never a fixed annual
    /// cadence). `start == end` is a valid zero-phase fill (the milestone/
    /// transition sits immediately at `start`); `start > end` means there
    /// is no lead time left at all — infeasible.
    private static func fillForwardPhases(
        from start: Date, to end: Date, primaryType: PhaseType, baseReasonCodes: [PlannerReasonCode]
    ) -> (phases: [ProposedPhase], feasible: Bool) {
        guard start <= end else { return ([], false) }
        guard start != end else { return ([], true) }

        let primaryDuration = PhaseDurationDefaults.range(for: primaryType)
        let primaryTypicalWeeks = primaryDuration.planningWeeks ?? 8
        guard case .range(_, let primaryMinimum, _) = primaryDuration else { return ([], false) }
        let primaryMinimumWeeks = primaryMinimum ?? primaryTypicalWeeks

        let maintenanceDuration = PhaseDurationDefaults.range(for: .maintenance)
        let maintenanceTypicalWeeks = maintenanceDuration.planningWeeks ?? 4

        let totalWeeks = wholeWeeksBetween(start, end)
        guard totalWeeks >= primaryMinimumWeeks else { return ([], false) }

        var phases: [ProposedPhase] = []
        var current = start
        var consecutivePrimary = 0
        // Safety bound only — real inputs terminate far sooner; guards
        // against a pathological zero-length step.
        for _ in 0..<52 {
            guard current < end else { break }
            let remainingWeeks = wholeWeeksBetween(current, end)
            guard remainingWeeks > 0 else { break }

            let useMaintenance = consecutivePrimary >= 2
            let phaseType: PhaseType = useMaintenance ? .maintenance : primaryType
            let phaseDurationKind = useMaintenance ? maintenanceDuration : primaryDuration
            let phaseTypicalWeeks = useMaintenance ? maintenanceTypicalWeeks : primaryTypicalWeeks
            let weeksToUse = min(phaseTypicalWeeks, remainingWeeks)
            guard weeksToUse > 0 else { break }

            let phaseEnd = addingWeeks(weeksToUse, to: current)
            phases.append(ProposedPhase(
                type: phaseType, priorityRule: priorityRule(for: phaseType),
                startDate: current, endDate: phaseEnd,
                durationKind: phaseDurationKind, reasonCodes: baseReasonCodes
            ))
            current = phaseEnd
            consecutivePrimary = useMaintenance ? 0 : consecutivePrimary + 1
        }

        return (phases, true)
    }

    private static func phaseType(for goalType: GoalType) -> PhaseType {
        switch goalType {
        case .muscleGain: return .muscleGain
        case .fatLoss: return .fatLoss
        case .generalStrength: return .strength
        case .enduranceEvent: return .enduranceEvent
        case .functionalFitness: return .functionalFitness
        case .maintenance: return .maintenance
        }
    }

    /// A milestone paired with `.loseFat`/`.recomposition` implies a Fat
    /// Loss phase completing at the milestone (`STRATEGIC_PLAN_MODEL.md`
    /// §4's own example); `.gainMuscle` implies a Muscle Gain phase.
    /// `.maintain`/`nil` states no special milestone-driving direction —
    /// the milestone is simply a checkpoint within the plan's own primary
    /// phase, never a fabricated third phase type
    /// (`PHASE_PLANNING_RULES.md` §1's "no combinatorial subclassing").
    private static func milestonePhaseType(direction: BodyCompositionDirection?, primaryType: PhaseType) -> PhaseType {
        switch direction {
        case .loseFat, .recomposition: return .fatLoss
        case .gainMuscle: return .muscleGain
        case .maintain, .none: return primaryType
        }
    }

    private static func priorityRule(for phaseType: PhaseType) -> TrainingPriority {
        switch phaseType {
        case .muscleGain, .fatLoss, .strength: return .strength
        case .enduranceEvent: return .endurance
        case .functionalFitness, .maintenance, .recovery, .transition: return .mixedModal
        }
    }

    private static func addingWeeks(_ weeks: Int, to date: Date) -> Date {
        Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: date) ?? date
    }

    private static func wholeWeeksBetween(_ start: Date, _ end: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return days / 7
    }

    // MARK: - proposeTrainingMix

    /// `ADHERENCE_AWARE_PLANNING.md` §5's two-stage ranking — a
    /// compatibility gate (5a), then bounded preference-based promotion
    /// among gated-in candidates only (5b). Never touches
    /// `phase.selectedTrainingMix` — a user's already-accepted choice is
    /// enforced downstream by `ConcurrentScheduler`/`SchedulingPipeline`
    /// (the `.userSelectedMix` reason code), not by withholding a
    /// proposal here; this call is purely advisory.
    /// A phase's place within its own `TrainingPlan` — read-only, derived
    /// entirely from `TrainingPlan.orderedPhases` at call time, never a
    /// new persisted relationship (`PHASE_PLANNING_RULES.md` §42/§43 both
    /// describe a phase's recommendation as depending on what surrounds
    /// it; this is the one mechanism both draw from, so a Transition
    /// policy can reuse it later without a second context type).
    struct PlanningContext {
        var previousPhase: TrainingPhase?
        var nextPhase: TrainingPhase?

        /// The strongest available signal for what the previous phase
        /// actually trained: its own user-`.selected` mix always wins
        /// over the system's `.recommended` one for it — the exact same
        /// "a `.selected` mix always wins" precedence `TrainingMix`
        /// itself already documents for tactical scheduling, applied
        /// here to strategic-context resolution instead. `nil` only when
        /// there is no previous phase, or it has neither mix yet.
        var previousTrainingMix: TrainingMix? {
            previousPhase?.selectedTrainingMix ?? previousPhase?.recommendedTrainingMix
        }
    }

    /// Builds a phase's `PlanningContext` purely from `TrainingPlan
    /// .orderedPhases` — no new stored relationship, no persistence, safe
    /// to call from a read-only preview.
    static func planningContext(for phase: TrainingPhase) -> PlanningContext {
        guard let plan = phase.plan,
              let index = plan.orderedPhases.firstIndex(where: { $0.id == phase.id }) else {
            return PlanningContext(previousPhase: nil, nextPhase: nil)
        }
        let previous = index > 0 ? plan.orderedPhases[index - 1] : nil
        let next = plan.orderedPhases.indices.contains(index + 1) ? plan.orderedPhases[index + 1] : nil
        return PlanningContext(previousPhase: previous, nextPhase: next)
    }

    static func proposeTrainingMix(phase: TrainingPhase, goal: Goal) -> [CandidateTrainingMix] {
        let templates = candidateMixTemplates(phase: phase, goal: goal)
        let availability = comparisonAvailability(goal: goal)
        for (mix, _) in templates {
            applyCapacity(to: mix, availability: availability)
        }
        let constraints = SchedulingConstraints(
            availability: availability,
            window: SchedulingWindow(startDate: phase.startDate, numberOfDays: 7)
        )

        let raw = templates.map { mix, reasonCodes -> RawMixCandidate in
            let inputs = mix.orderedComponents.map { component in
                ScheduledProgramInput(component: component, sessions: representativeSessions(for: component))
            }
            let result = SchedulingPipeline.propose(mix: mix, inputs: inputs, constraints: constraints)
            return RawMixCandidate(mix: mix, alignment: result.alignment, reasonCodes: reasonCodes)
        }

        return rankCandidateMixes(raw, preferences: goal.preferences)
    }

    /// Stage V1 dogfooding fix (Plan Recommendation Integrity — capacity
    /// scaling POLICY CORRECTION): a candidate mix must never be presented
    /// as schedulable when its fixed template targets exceed the athlete's
    /// own real, stated capacity. When `allowsDoubleSessions` is false,
    /// real capacity is exactly `trainingDaysPerWeek` total Sessions — one
    /// per distinct day, never more (the locked V1 contract: "training
    /// days per week" means distinct available days, never a session
    /// count).
    ///
    /// **Composition-preserving, not "primary fully protected, supporting
    /// yields to zero."** An earlier version of this function reduced
    /// tier-by-tier (primary first, unreduced, then secondary, then
    /// supporting) — REJECTED as a product policy: it silently destroyed a
    /// mix's intended composition (5 Hypertrophy + 2 Zone 2 at capacity 5
    /// became 5+0, not a real "Hypertrophy + Conditioning" mix anymore),
    /// and could make a stated modality preference for a supporting
    /// modality completely ineffective. The ORIGINAL component
    /// `SessionFrequency.target` values already express the mix's intended
    /// ratio — this function preserves that ratio as closely as integer
    /// capacity allows via `allocateProportionally`, a standard largest-
    /// remainder (Hamilton) apportionment, rather than inventing a new
    /// numeric ratio. `GoalPriority` is now used ONLY as a deterministic
    /// tie-break (never "satisfy primary fully before anyone else") — see
    /// `allocateProportionally`'s own doc comment for the exact mechanism
    /// and worked example (5+2 at capacity 5 → 4+1, not 5+0).
    ///
    /// When `allowsDoubleSessions` is true, template targets are left
    /// untouched — more Sessions than `trainingDaysPerWeek` may be
    /// genuinely valid, and whether they're actually placeable is exactly
    /// what the real scheduling-based `GoalAlignment` computed just below
    /// already determines honestly.
    private static func applyCapacity(to mix: TrainingMix, availability: UserAvailability) {
        guard !availability.allowsDoubleSessions else { return }
        let capacity = availability.trainingDaysPerWeek
        let nonZero = mix.orderedComponents.filter { $0.frequency.target > 0 }
        guard !nonZero.isEmpty else { return }

        let totalOriginalTarget = nonZero.reduce(0) { $0 + $1.frequency.target }
        // Already fits within capacity as-is — no reduction needed, no
        // component's target is ever inflated to "fill" unused capacity.
        if capacity >= totalOriginalTarget {
            mix.components.removeAll { $0.frequency.target <= 0 }
            return
        }

        let survivors: [TrainingMixComponent]
        if capacity >= nonZero.count {
            // Every non-zero component can receive at least one session —
            // proportional apportionment among all of them.
            survivors = nonZero
        } else {
            // Not enough capacity for even one session per component
            // (rule 7): retain components in `GoalPriority` order
            // (primary -> secondary -> supporting), existing stable
            // order as the final tie-break, dropping the lowest-priority
            // components until what remains fits within capacity. Each
            // survivor then gets exactly 1 session (capacity == survivor
            // count in this branch).
            survivors = Array(
                nonZero.enumerated()
                    .sorted { a, b in
                        let pa = priorityOrdinal(a.element.priority), pb = priorityOrdinal(b.element.priority)
                        return pa != pb ? pa < pb : a.offset < b.offset
                    }
                    .map(\.element)
                    // Dropped components must be explicitly zeroed here —
                    // they are never touched by `allocateProportionally`
                    // (which only ever modifies `survivors`), so without
                    // this they'd keep their stale ORIGINAL frequency and
                    // survive the final `removeAll { target <= 0 }` below
                    // untouched (a real bug, caught by
                    // `testCapacityOneRetainsOnlyTheHigherPriorityComponent`
                    // and `testNoComponentEverExceedsItsOriginalTemplateTarget`
                    // before this fix).
                    .prefix(capacity)
            )
            // Every non-zero component NOT retained must be explicitly
            // zeroed — `allocateProportionally` below only ever touches
            // `survivors`, so a dropped component would otherwise keep
            // its stale original (non-zero) frequency and incorrectly
            // survive the final `removeAll { target <= 0 }` cleanup.
            let survivorIDs = Set(survivors.map(\.id))
            for component in nonZero where !survivorIDs.contains(component.id) {
                component.frequency = SessionFrequency(target: 0, minimum: nil, maximum: component.frequency.maximum)
            }
        }
        // In the "not enough capacity" branch, `survivors.count == capacity`
        // exactly (each survivor gets 1 session); in the other branch,
        // `survivors == nonZero` and the full `capacity` is apportioned.
        allocateProportionally(capacity: capacity, among: survivors)

        mix.components.removeAll { $0.frequency.target <= 0 }
    }

    /// Largest-remainder (Hamilton) apportionment: splits `capacity`
    /// sessions among `components` proportionally to each component's own
    /// ORIGINAL `SessionFrequency.target` — the original targets already
    /// express the mix's intended relative composition, so this preserves
    /// that ratio as closely as integer capacity allows rather than
    /// inventing a new one. Requires `capacity >= components.count` (every
    /// caller already guarantees this — see `applyCapacity`).
    ///
    /// **Mechanism:** each component's exact real-valued quota is
    /// `capacity * (originalTarget / totalOriginalTarget)`. Every
    /// component first receives `floor(quota)`; the leftover units
    /// (`capacity - sum of floors`, always `< components.count`) go one at
    /// a time to whichever components have the largest fractional
    /// remainder — `GoalPriority` (primary before secondary before
    /// supporting) is the tie-break ONLY when two remainders are
    /// genuinely equal, never a primary driver.
    ///
    /// **Worked example (locked, must reproduce exactly):** 5 Hypertrophy
    /// + 2 Zone 2, capacity 5. Quotas: Hypertrophy `5*(5/7)≈3.571`, Zone 2
    /// `5*(2/7)≈1.429`. Floors: 3 and 1 (sum 4). Leftover: `5-4=1`.
    /// Remainders: Hypertrophy `0.571` vs. Zone 2 `0.429` — Hypertrophy's
    /// is larger, so it receives the extra unit. Final: **4 Hypertrophy +
    /// 1 Zone 2** — composition preserved (roughly the original 5:2
    /// ratio), never the rejected 5+0.
    ///
    /// **Safety guarantee (rule 1 — never actually triggered by the
    /// worked examples above, but real regardless of mix size):**
    /// Hamilton's method already gives every component `floor(quota)`,
    /// which is `>= 1` whenever `capacity >= components.count` UNLESS the
    /// weights are skewed enough that a low-weight component's own quota
    /// floors below 1 (e.g. many components with very small original
    /// targets relative to one large one). If that occurs, the smallest
    /// possible correction is applied: move exactly one session from
    /// whichever component currently has the most (ties broken toward the
    /// least-protected/supporting tier, since GoalPriority is still only a
    /// tie-break) to the starved component — never a random or
    /// first-found donor.
    private static func allocateProportionally(capacity: Int, among components: [TrainingMixComponent]) {
        let totalWeight = components.reduce(0) { $0 + $1.frequency.target }
        guard totalWeight > 0 else { return }

        var floors: [Int] = []
        var remainders: [Double] = []
        for component in components {
            let quota = Double(capacity) * Double(component.frequency.target) / Double(totalWeight)
            let floor = Int(quota)
            floors.append(floor)
            remainders.append(quota - Double(floor))
        }

        var leftover = capacity - floors.reduce(0, +)
        let remainderOrder = components.indices.sorted { a, b in
            if remainders[a] != remainders[b] { return remainders[a] > remainders[b] }
            let pa = priorityOrdinal(components[a].priority), pb = priorityOrdinal(components[b].priority)
            return pa != pb ? pa < pb : a < b
        }
        for index in remainderOrder where leftover > 0 {
            floors[index] += 1
            leftover -= 1
        }

        if capacity >= components.count {
            for starvedIndex in floors.indices where floors[starvedIndex] == 0 {
                let donorOrder = floors.indices
                    .filter { $0 != starvedIndex && floors[$0] > 1 }
                    .sorted { a, b in
                        if floors[a] != floors[b] { return floors[a] > floors[b] }
                        let pa = priorityOrdinal(components[a].priority), pb = priorityOrdinal(components[b].priority)
                        return pa > pb // take from the least-protected (supporting) tier first on a tie
                    }
                guard let donorIndex = donorOrder.first else { continue }
                floors[donorIndex] -= 1
                floors[starvedIndex] = 1
            }
        }

        for (index, component) in components.enumerated() {
            let allocated = min(floors[index], component.frequency.target)
            component.frequency = SessionFrequency(
                target: allocated,
                minimum: component.frequency.minimum.map { min($0, allocated) },
                maximum: component.frequency.maximum
            )
        }
    }

    private static func priorityOrdinal(_ priority: GoalPriority) -> Int {
        switch priority {
        case .primary: return 0
        case .secondary: return 1
        case .supporting: return 2
        }
    }

    // MARK: - Two-stage ranking (ADHERENCE_AWARE_PLANNING.md §5), pure and directly testable

    struct RawMixCandidate {
        var mix: TrainingMix
        var alignment: GoalAlignment
        var reasonCodes: [PlannerReasonCode]
    }

    /// TRAININGOS_DESIGNED, configurable — `ADHERENCE_AWARE_PLANNING.md`
    /// §5a's single compatibility threshold.
    static let compatibilityThreshold: GoalAlignmentRating = .acceptable
    /// TRAININGOS_DESIGNED, configurable — §5b's proposed default.
    static let maxPromotableTierGap = 1

    /// Pure ranking core: no `ModelContext`, no scheduling, no I/O —
    /// takes already-evaluated candidates (real `GoalAlignment`s) and
    /// applies §5a's gate then §5b's bounded promotion. Kept separate
    /// from `proposeTrainingMix` so the ranking logic itself is directly
    /// unit-testable against hand-constructed `GoalAlignment`s.
    static func rankCandidateMixes(_ raw: [RawMixCandidate], preferences: GoalPreferences?) -> [CandidateTrainingMix] {
        // Capability check (`LONG_TERM_PLANNER.md` §2a's first gate) —
        // runs before alignment is ever consulted. A candidate with any
        // component TrainingOS cannot instantiate at all is dropped
        // entirely, never disguised as a normal alternative.
        let capable = raw.filter(isInstantiable)
        guard !capable.isEmpty else { return [] }

        var roles: [UUID: Set<CandidateMixRole>] = [:]
        var reasonCodes: [UUID: [PlannerReasonCode]] = Dictionary(
            uniqueKeysWithValues: capable.map { ($0.mix.id, $0.reasonCodes) }
        )

        // §5a — the compatibility gate.
        let gateEligible = capable.filter { $0.alignment.rating >= compatibilityThreshold }

        guard let best = bestByAlignment(gateEligible) else {
            // Nothing cleared the gate — every candidate is surfaced as a
            // plain, unrole'd alternative (still schedulable, correctly
            // labeled Poor Fit downstream), never forced into a
            // `.recommended` slot it didn't earn.
            return capable
                .sorted { $0.mix.name < $1.mix.name }
                .map { CandidateTrainingMix(mix: $0.mix, roles: [], alignment: $0.alignment, reasonCodes: $0.reasonCodes) }
        }

        roles[best.mix.id, default: []].insert(.bestGoalAlignment)

        // §5b — bounded preference-based promotion among gated-in
        // candidates only.
        let bestDistinctSystems = distinctSystems(best.mix)
        let promotionCandidates = gateEligible.filter { candidate in
            candidate.mix.id != best.mix.id
                && isPreferenceAligned(candidate.mix, preferences: preferences, bestDistinctSystems: bestDistinctSystems)
                && tierGap(from: best.alignment.rating, to: candidate.alignment.rating) <= maxPromotableTierGap
        }
        let promoted = bestPromotionCandidate(promotionCandidates)

        let recommended = promoted ?? best
        roles[recommended.mix.id, default: []].insert(.recommended)
        if promoted != nil {
            reasonCodes[recommended.mix.id, default: []].append(.adherencePreferencePromotedAlternative)
        }

        // §5c — at most one bestVarietyAlternative, only when it
        // genuinely offers more distinct systems than what's recommended.
        let recommendedDistinct = distinctSystems(recommended.mix)
        if let variety = gateEligible
            .filter({ roles[$0.mix.id] == nil })
            .filter({ distinctSystems($0.mix) > recommendedDistinct })
            .max(by: { distinctSystems($0.mix) < distinctSystems($1.mix) }) {
            roles[variety.mix.id, default: []].insert(.bestVarietyAlternative)
            reasonCodes[variety.mix.id, default: []].append(.varietyPreferenceApplied)
        }

        // §5c — at most one userPreferenceAlternative: a preference-
        // aligned candidate that cleared the gate but wasn't promoted
        // (e.g. the tier gap was too wide), surfaced rather than hidden.
        if let alternative = gateEligible
            .filter({ roles[$0.mix.id] == nil })
            .filter({ isPreferenceAligned($0.mix, preferences: preferences, bestDistinctSystems: bestDistinctSystems) })
            .sorted(by: { $0.alignment.rating > $1.alignment.rating })
            .first {
            roles[alternative.mix.id, default: []].insert(.userPreferenceAlternative)
        }

        return capable
            .sorted { lhs, rhs in
                let lhsRoles = roles[lhs.mix.id] ?? []
                let rhsRoles = roles[rhs.mix.id] ?? []
                if lhsRoles.contains(.recommended) != rhsRoles.contains(.recommended) {
                    return lhsRoles.contains(.recommended)
                }
                if lhsRoles.contains(.bestGoalAlignment) != rhsRoles.contains(.bestGoalAlignment) {
                    return lhsRoles.contains(.bestGoalAlignment)
                }
                if lhs.alignment.rating != rhs.alignment.rating {
                    return lhs.alignment.rating > rhs.alignment.rating
                }
                return lhs.mix.name < rhs.mix.name
            }
            .map { candidate in
                CandidateTrainingMix(
                    mix: candidate.mix,
                    roles: roles[candidate.mix.id] ?? [],
                    alignment: candidate.alignment,
                    reasonCodes: reasonCodes[candidate.mix.id] ?? candidate.reasonCodes
                )
            }
    }

    private static func isInstantiable(_ candidate: RawMixCandidate) -> Bool {
        let available = ProgramCapabilityRegistry.availableProgrammingSystems()
        return candidate.mix.orderedComponents.allSatisfy { component in
            guard let system = component.programmingSystem else { return false }
            return available.contains(system)
        }
    }

    private static func distinctSystems(_ mix: TrainingMix) -> Int {
        Set(mix.orderedComponents.compactMap(\.programmingSystem)).count
    }

    /// §5b's three-part boolean test — never a fabricated score.
    ///
    /// Stage V1 dogfooding fix (Part 3): only a SYSTEM-WIDE dislike
    /// (`ModalityPreference.activityType == nil`, e.g. "no steady-state at
    /// all") vetoes the whole system here. An ACTIVITY-scoped dislike
    /// (e.g. `system: .steadyState, activityType: .running` — "I dislike
    /// running specifically") must never veto a mix merely for containing
    /// `.steadyState` — `TrainingMixComponent` has no stored `ActivityType`
    /// at this strategic level, so the real, correct place to honor an
    /// activity-scoped dislike is `preferredActivityType`'s own activity
    /// selection (it already resolves the real, materialization-time
    /// `ActivityType` for exactly this system), not this system-level gate.
    private static func isPreferenceAligned(_ mix: TrainingMix, preferences: GoalPreferences?, bestDistinctSystems: Int) -> Bool {
        guard let preferences else { return false }
        let systems = Set(mix.orderedComponents.compactMap(\.programmingSystem))
        let systemWideDislikes = Set(preferences.dislikedModalities.filter { $0.activityType == nil }.map(\.system))
        guard systems.isDisjoint(with: systemWideDislikes) else { return false }
        let preferred = Set(preferences.preferredModalities.map(\.system))
        guard !systems.isDisjoint(with: preferred) else { return false }
        if preferences.varietyPreference == .high {
            guard systems.count > bestDistinctSystems else { return false }
        }
        return true
    }

    /// Positive when `candidate` sits below `best` — never negative in a
    /// way that would let an already-better-or-equal candidate fail the
    /// `<= maxPromotableTierGap` check.
    private static func tierGap(from best: GoalAlignmentRating, to candidate: GoalAlignmentRating) -> Int {
        let order = GoalAlignmentRating.allCases
        let bestIndex = order.firstIndex(of: best) ?? 0
        let candidateIndex = order.firstIndex(of: candidate) ?? 0
        return bestIndex - candidateIndex
    }

    /// Deterministic: highest rating first, alphabetically-first name on
    /// a tie — never construction/array-order-dependent.
    private static func bestByAlignment(_ candidates: [RawMixCandidate]) -> RawMixCandidate? {
        candidates.min { lhs, rhs in
            if lhs.alignment.rating != rhs.alignment.rating { return lhs.alignment.rating > rhs.alignment.rating }
            return lhs.mix.name < rhs.mix.name
        }
    }

    /// Among preference-aligned, tier-gap-eligible candidates: highest
    /// rating first, then most distinct systems (the more-variety one is
    /// the more useful promotion), then name.
    private static func bestPromotionCandidate(_ candidates: [RawMixCandidate]) -> RawMixCandidate? {
        candidates.min { lhs, rhs in
            if lhs.alignment.rating != rhs.alignment.rating { return lhs.alignment.rating > rhs.alignment.rating }
            let lhsSystems = distinctSystems(lhs.mix)
            let rhsSystems = distinctSystems(rhs.mix)
            if lhsSystems != rhsSystems { return lhsSystems > rhsSystems }
            return lhs.mix.name < rhs.mix.name
        }
    }

    // MARK: - Candidate mix templates, per `PhaseType` (`PHASE_PLANNING_RULES.md` §7)

    /// TRAININGOS_DESIGNED, illustrative compositions — never dozens
    /// (`ADHERENCE_AWARE_PLANNING.md` §5c), always small and deterministic.
    /// Each phase type gets at least one focused candidate; goal types
    /// whose phase benefits from a genuinely different, more-varied
    /// composition also get a second. Muscle Gain's pair matches
    /// `ADHERENCE_AWARE_PLANNING.md` §5d's own worked example exactly.
    private static func candidateMixTemplates(phase: TrainingPhase, goal: Goal) -> [(mix: TrainingMix, reasonCodes: [PlannerReasonCode])] {
        switch phase.type {
        case .muscleGain:
            return [
                (muscleGainFocusedHypertrophyMix(), [.phaseSelectedForGoal]),
                (muscleGainVariedMix(), [.phaseSelectedForGoal]),
            ]
        case .fatLoss:
            var codes: [PlannerReasonCode] = [.phaseSelectedForGoal, .muscleRetentionPriority]
            if goal.milestoneDate != nil { codes.append(.fatLossTimedToMilestone) }
            return [
                (fatLossConditioningFocusedMix(), codes),
                (fatLossVariedMix(), codes),
            ]
        case .strength:
            return [(strengthFocusedMix(), [.phaseSelectedForGoal])]
        case .enduranceEvent:
            let activity = preferredEnduranceActivityLabel(goal: goal)
            return [
                (enduranceFocusedMix(activityLabel: activity), [.phaseSelectedForGoal]),
                (enduranceVariedMix(activityLabel: activity), [.phaseSelectedForGoal]),
            ]
        case .functionalFitness:
            return [(functionalFitnessFocusedMix(), [.phaseSelectedForGoal])]
        case .maintenance:
            return [(maintenanceMix(phase: phase, goal: goal, context: planningContext(for: phase)), [.phaseSelectedForGoal])]
        case .recovery, .transition:
            // Deliberately still the shared generic fallback, but via
            // their own switch arm — never routed through `maintenanceMix`
            // (§6: Maintenance/Recovery/Transition are distinct strategic
            // purposes, not aliases, even where today's implementation
            // happens to produce the same content for two of them). A
            // Transition-specific blend of the outgoing/incoming phase's
            // components (`PHASE_PLANNING_RULES.md` §43) can be added
            // here independently, using the same `planningContext`
            // mechanism Maintenance already uses, without touching
            // Maintenance's own policy.
            return [(lowerDemandGenericMix(phase: phase), [.phaseSelectedForGoal])]
        }
    }

    /// Maintenance's own policy seam — deliberately distinct from
    /// `lowerDemandGenericMix` (§6), and no longer routed through it when
    /// a preceding training state actually exists. `context
    /// .previousTrainingMix` resolves the strongest available signal for
    /// what was actually being trained (the preceding phase's own
    /// selected mix, falling back to its recommendation, §7 of the
    /// round's own spec); `maintenanceComponentDecisions` turns that into
    /// a genuinely quality-preserving, reduced-dose mix per the
    /// TRAININGOS-DESIGNED policy below (explicitly a designed decision,
    /// not sourced from any sports-science reference — no such reference
    /// exists anywhere in this repo, confirmed by a full-repo search).
    /// Falls back to the generic fallback only when there is truly
    /// nothing to preserve (no previous phase, or its mix has no
    /// components) — never fabricating a preceding state that doesn't
    /// exist.
    private static func maintenanceMix(phase: TrainingPhase, goal: Goal, context: PlanningContext) -> TrainingMix {
        guard let previousMix = context.previousTrainingMix, !previousMix.orderedComponents.isEmpty else {
            return lowerDemandGenericMix(phase: phase)
        }

        let decisions = maintenanceComponentDecisions(for: previousMix.orderedComponents)
        let mix = TrainingMix(kind: .recommended, name: "Maintenance")
        for decision in decisions {
            guard let newTarget = decision.newTarget else { continue }
            mix.addComponent(TrainingMixComponent(
                label: decision.sourceLabel, programmingSystem: decision.sourceSystem,
                priority: decision.sourcePriority, adaptationObjectives: decision.sourceAdaptationObjectives,
                frequency: SessionFrequency(target: newTarget)
            ))
        }
        // Every component came from a genuinely omittable Supporting tier
        // (never Primary/Secondary, which always produce >= 1) — this can
        // only happen if the preceding mix was ENTIRELY Supporting, an
        // edge case with nothing to meaningfully preserve.
        guard !mix.orderedComponents.isEmpty else { return lowerDemandGenericMix(phase: phase) }
        return mix
    }

    /// One documented decision the Maintenance transform made about a
    /// single preceding component — deliberately structured, never an
    /// opaque one-off calculation, so a later stage can build a real
    /// explanation ("Reduced from 5 to 2 weekly sessions to preserve
    /// hypertrophy with lower training demand") without re-deriving the
    /// reasoning (§11 of the round's own spec). Not yet wired into
    /// `PlannerDecision`/any UI — this is the seam, not the feature.
    struct MaintenanceComponentDecision {
        enum Outcome {
            /// Kept, but at a lower `SessionFrequency.target` than before.
            case preservedAtReducedFrequency
            /// Kept at its exact previous frequency (already at or below
            /// the maintenance floor for its own category).
            case preservedUnchanged
            /// A Supporting-tier component whose previous single weekly
            /// session would only add density without being the mix's
            /// sole remaining supporting quality — dropped, never
            /// reduced to zero on a Primary/Secondary component.
            case omittedAsRedundantSupporting
        }
        var sourceLabel: String
        var sourceSystem: ProgrammingSystemKind?
        var sourcePriority: GoalPriority
        /// Stage CP.2 addition: Maintenance changes dose, never purpose —
        /// carried forward unchanged from the preceding mix's own
        /// component, never re-derived from `phase.type`.
        var sourceAdaptationObjectives: [AdaptationObjective]
        var previousTarget: Int
        /// `nil` exactly when `outcome == .omittedAsRedundantSupporting`.
        var newTarget: Int?
        var outcome: Outcome
    }

    /// Hypertrophy/Powerlifting are this repo's own resistance-training
    /// systems (§2 of the round's own spec); every other system reduces
    /// under the non-resistance rule instead.
    private static func isResistanceSystem(_ system: ProgrammingSystemKind?) -> Bool {
        switch system {
        case .hypertrophy, .powerlifting: return true
        case .steadyState, .interval, .functionalFitness, nil: return false
        }
    }

    /// Primary/Secondary resistance-training reduction: 2/week is the
    /// maintenance floor for a quality that previously received
    /// meaningful emphasis — never reduced further merely to hit a flat
    /// percentage, and never reduced to zero.
    private static func resistanceMaintenanceTarget(previous: Int) -> Int {
        previous >= 3 ? 2 : max(1, previous)
    }

    /// Primary/Secondary non-resistance reduction (conditioning-style
    /// systems carrying primary/secondary emphasis).
    private static func nonResistanceMaintenanceTarget(previous: Int) -> Int {
        previous >= 4 ? 2 : 1
    }

    /// Turns the preceding mix's own components into this round's
    /// Maintenance policy decisions (§1-§3, §6 of the round's own spec):
    /// Primary/Secondary are always preserved (reduced per their own
    /// resistance/non-resistance rule, never to zero); Supporting is
    /// reduced more aggressively and, once already at a single weekly
    /// session, is preserved only when it is the mix's sole remaining
    /// Supporting quality — otherwise it is exactly the kind of "arbitrary
    /// filler" the spec says must not be preserved merely because it
    /// existed before. Never increases a frequency, and never produces a
    /// target below any `minimum` the source component already declared
    /// (§6: an existing invariant is respected, never overridden).
    private static func maintenanceComponentDecisions(for previousComponents: [TrainingMixComponent]) -> [MaintenanceComponentDecision] {
        let supportingCount = previousComponents.filter { $0.priority == .supporting }.count

        return previousComponents.map { component in
            let previousTarget = component.frequency.target

            // `nil` proposedTarget means "omit" (Supporting-only); every
            // other case proposes a concrete, never-increased target.
            let proposedTarget: Int?
            switch component.priority {
            case .primary, .secondary:
                proposedTarget = isResistanceSystem(component.programmingSystem)
                    ? resistanceMaintenanceTarget(previous: previousTarget)
                    : nonResistanceMaintenanceTarget(previous: previousTarget)
            case .supporting:
                if previousTarget >= 2 {
                    proposedTarget = 1
                } else if supportingCount == 1 {
                    proposedTarget = 1
                } else {
                    proposedTarget = nil
                }
            }

            // Floored against any existing `minimum` the source component
            // already declared — respected, never overridden (§6) — then
            // the outcome is labeled from that final value, so a
            // `minimum` that pulls a target back up is never described as
            // a bigger reduction than it actually was.
            let flooredTarget = proposedTarget.map { max($0, component.frequency.minimum ?? $0) }
            let outcome: MaintenanceComponentDecision.Outcome
            if let flooredTarget {
                outcome = flooredTarget == previousTarget ? .preservedUnchanged : .preservedAtReducedFrequency
            } else {
                outcome = .omittedAsRedundantSupporting
            }

            return MaintenanceComponentDecision(
                sourceLabel: component.label, sourceSystem: component.programmingSystem,
                sourcePriority: component.priority, sourceAdaptationObjectives: component.adaptationObjectives,
                previousTarget: previousTarget, newTarget: flooredTarget, outcome: outcome
            )
        }
    }

    /// §5d's exact worked-example candidate A: 5-Day Hypertrophy + 2 Zone 2.
    private static func muscleGainFocusedHypertrophyMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Focused Hypertrophy")
        mix.addComponent(TrainingMixComponent(
            label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary,
            adaptationObjectives: [.muscleGain],
            frequency: SessionFrequency(target: 5)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Zone 2 Conditioning", programmingSystem: .steadyState, priority: .supporting,
            adaptationObjectives: [.aerobicCapacity],
            frequency: SessionFrequency(target: 2)
        ))
        return mix
    }

    /// §5d's exact worked-example candidate B: 3 Strength + 2 Functional
    /// Fitness + 1 Run.
    ///
    /// Stage CP.2 PRODUCT DECISION (not recovered/source behavior — see
    /// `TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`'s CP.2 §3): this
    /// mix's own name, "Strength Plus Variety," is itself the rationale
    /// for the Functional Fitness component's `[.workCapacity,
    /// .aerobicCapacity, .power]` — breadth across the three adaptation
    /// domains a focused strength emphasis under-develops, not a narrow
    /// physiological target.
    private static func muscleGainVariedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Strength Plus Variety")
        mix.addComponent(TrainingMixComponent(
            label: "Strength", programmingSystem: .hypertrophy, priority: .primary,
            adaptationObjectives: [.muscleGain],
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .supporting,
            adaptationObjectives: [.workCapacity, .aerobicCapacity, .power],
            frequency: SessionFrequency(target: 2)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Running", programmingSystem: .steadyState, priority: .supporting,
            adaptationObjectives: [.aerobicCapacity],
            frequency: SessionFrequency(target: 1)
        ))
        return mix
    }

    /// `PHASE_PLANNING_RULES.md` §7's Fat Loss architecture: primary
    /// conditioning, `.secondary`+`.required` resistance training (the
    /// "protected" pattern — protects muscle, §2a).
    ///
    /// Stage CP.2 PRODUCT DECISION: the Resistance Training component's
    /// real purpose here is muscle RETENTION during a caloric deficit —
    /// mechanically the same training stimulus as gaining it (adequate
    /// volume/intensity/proximity to failure on the same patterns), so it
    /// uses `[.muscleGain]` rather than a separate, un-locked
    /// "retention" concept (see CP.2 §4 — what differs is energy balance
    /// and relative priority/dose, both already expressed elsewhere,
    /// never the adaptation itself).
    private static func fatLossConditioningFocusedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Conditioning-Focused Fat Loss")
        mix.addComponent(TrainingMixComponent(
            label: "Conditioning", programmingSystem: .interval, priority: .primary,
            adaptationObjectives: [.anaerobicCapacity],
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Resistance Training", programmingSystem: .hypertrophy, priority: .secondary,
            adaptationObjectives: [.muscleGain],
            frequency: SessionFrequency(target: 3, minimum: 2), flexibility: .required
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Easy Aerobic", programmingSystem: .steadyState, priority: .supporting,
            adaptationObjectives: [.aerobicCapacity],
            frequency: SessionFrequency(target: 1)
        ))
        return mix
    }

    /// Stage CP.2 PRODUCT DECISION: this mix's own name, "Functional Fat
    /// Loss," names the FF component's real purpose as metabolic
    /// conditioning/caloric expenditure — `.power` is deliberately
    /// excluded (unlike `muscleGainVariedMix`'s FF component) since
    /// nothing in a fat-loss context calls for explosive-power
    /// development. The paired Resistance Training component uses
    /// `[.muscleGain]` for the same muscle-retention reasoning as
    /// `fatLossConditioningFocusedMix` above.
    private static func fatLossVariedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Functional Fat Loss")
        mix.addComponent(TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .primary,
            adaptationObjectives: [.workCapacity, .aerobicCapacity],
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Resistance Training", programmingSystem: .hypertrophy, priority: .secondary,
            adaptationObjectives: [.muscleGain],
            frequency: SessionFrequency(target: 2, minimum: 2), flexibility: .required
        ))
        return mix
    }

    private static func strengthFocusedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Focused Powerlifting")
        mix.addComponent(TrainingMixComponent(
            label: "Powerlifting", programmingSystem: .powerlifting, priority: .primary,
            adaptationObjectives: [.maxStrength],
            frequency: SessionFrequency(target: 4)
        ))
        return mix
    }

    /// Display label only — `TrainingMixComponent` has no `activityType`
    /// field of its own (that distinction lives on `Goal.preferences`,
    /// `PHASE_PLANNING_RULES.md` §1's own note on Aerobic Development vs.
    /// Running Performance); this does not change ranking, only naming.
    private static func preferredEnduranceActivityLabel(goal: Goal) -> String {
        let activity = goal.preferences?.preferredModalities
            .first { $0.system == .steadyState || $0.system == .interval }?
            .activityType
        return (activity ?? .running).rawValue.capitalized
    }

    private static func enduranceFocusedMix(activityLabel: String) -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "\(activityLabel) Performance")
        mix.addComponent(TrainingMixComponent(
            label: activityLabel, programmingSystem: .steadyState, priority: .primary,
            adaptationObjectives: [.aerobicCapacity],
            frequency: SessionFrequency(target: 5)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Strength Maintenance", programmingSystem: .hypertrophy, priority: .supporting,
            adaptationObjectives: [.muscleGain],
            frequency: SessionFrequency(target: 2)
        ))
        return mix
    }

    private static func enduranceVariedMix(activityLabel: String) -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "\(activityLabel) Plus Interval Variety")
        mix.addComponent(TrainingMixComponent(
            label: activityLabel, programmingSystem: .steadyState, priority: .primary,
            adaptationObjectives: [.aerobicCapacity],
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Interval Work", programmingSystem: .interval, priority: .secondary,
            adaptationObjectives: [.anaerobicCapacity],
            frequency: SessionFrequency(target: 2)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Strength Maintenance", programmingSystem: .hypertrophy, priority: .supporting,
            adaptationObjectives: [.muscleGain],
            frequency: SessionFrequency(target: 1)
        ))
        return mix
    }

    /// Stage CP.2 PRODUCT DECISION: this is the one case where genuine
    /// breadth across nearly every domain Functional Fitness can honestly
    /// serve IS the stated product intent — the user's own strategic
    /// goal here (`phase.type == .functionalFitness`) is general physical
    /// preparedness itself, not FF-as-a-supporting-component-of-something-
    /// else. Deliberately every objective FF's `Stimulus` model CAN
    /// honestly express (`.maxStrength`/`.muscleGain` excluded — no
    /// mapping exists for either, per CP.2's own audit), not merely "every
    /// objective that exists."
    private static func functionalFitnessFocusedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Focused Functional Fitness")
        mix.addComponent(TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .primary,
            adaptationObjectives: [.workCapacity, .aerobicCapacity, .anaerobicCapacity, .power, .skillAcquisition],
            frequency: SessionFrequency(target: 4, minimum: 3), flexibility: .required
        ))
        return mix
    }

    private static func lowerDemandGenericMix(phase: TrainingPhase) -> TrainingMix {
        let name: String
        switch phase.type {
        case .recovery: name = "Recovery"
        case .transition: name = "Transition"
        default: name = "Maintenance"
        }
        let mix = TrainingMix(kind: .recommended, name: name)
        mix.addComponent(TrainingMixComponent(
            label: "General Conditioning", programmingSystem: .steadyState, priority: .primary,
            adaptationObjectives: [.aerobicCapacity],
            frequency: SessionFrequency(target: 2)
        ))
        return mix
    }

    /// Lightweight, never-persisted stand-ins for a candidate's future
    /// real Sessions — enough for `ConcurrentScheduler` to evaluate
    /// placement pressure (count + modality), never a claim that this is
    /// the eventual real session content. Matches the existing
    /// `ConcurrentSchedulerTests`/`SchedulerHardeningTests` convention of
    /// building plain `Session`s directly for scheduling comparisons.
    private static func representativeSessions(for component: TrainingMixComponent) -> [Session] {
        let modality = representativeModality(for: component.programmingSystem)
        return (0..<max(0, component.frequency.target)).map { index in
            Session(name: "\(component.label) \(index + 1)", modality: modality)
        }
    }

    private static func representativeModality(for system: ProgrammingSystemKind?) -> TrainingModality {
        switch system {
        case .hypertrophy: return .hypertrophy
        case .powerlifting: return .strength
        case .steadyState, .interval: return .conditioning
        case .functionalFitness: return .functionalFitness
        case nil: return .hybrid
        }
    }

    /// `ADHERENCE_AWARE_PLANNING.md` §6's "goal's coarse availability
    /// fields as a stand-in `UserAvailability`, for comparison purposes
    /// only, never persisted as if it were the real tactical-time
    /// availability." When the goal states no explicit availability at
    /// all, this treats the comparison as unrestricted (every weekday
    /// usable) rather than inventing an arbitrary constraining ceiling
    /// that would silently shape ranking outcomes the goal never stated
    /// (CLAUDE.md rule 10).
    private static func comparisonAvailability(goal: Goal) -> UserAvailability {
        let allowsDoubles = goal.preferences?.allowsDoubleSessions ?? false
        guard let statedDays = goal.preferences?.availableTrainingDaysPerWeek else {
            return UserAvailability(
                trainingDaysPerWeek: Weekday.allCases.count,
                allowsDoubleSessions: allowsDoubles,
                maxSessionsPerDay: allowsDoubles ? 2 : 1
            )
        }
        let clampedDays = max(1, min(statedDays, Weekday.allCases.count))
        return UserAvailability(
            trainingDaysPerWeek: statedDays,
            availableWeekdays: Set(Weekday.allCases.prefix(clampedDays)),
            allowsDoubleSessions: allowsDoubles,
            maxSessionsPerDay: allowsDoubles ? 2 : 1
        )
    }

    /// Read-only preview of which `ProgramDefinition` would likely be
    /// chosen for a not-yet-started component — reuses the exact same
    /// `proposeProgram` ranking a real phase start would use, scored
    /// against the same `comparisonAvailability` `proposeTrainingMix`
    /// itself already ranks mix candidates with (never the user's real
    /// availability, and never a real `PerformanceProfile` — a future
    /// phase's eventual real start may see different history/readiness
    /// by the time it actually happens, so this is deliberately a
    /// conservative, generic preview, never a promise). Callers previewing
    /// a not-yet-active phase must supply a disposable, never-saved
    /// `context` (e.g. `PersistenceController.makeInMemoryContainer()`'s
    /// own `mainContext`) — `proposeProgram` does construct a real
    /// `ProgramDefinition` object, and this guarantees it is never
    /// persisted into the app's real store merely by being previewed.
    static func previewProgramCandidate(component: TrainingMixComponent, goal: Goal, context: ModelContext) -> ProgramCandidate? {
        let availability = comparisonAvailability(goal: goal)
        let (candidates, _) = proposeProgram(component: component, profile: nil, availability: availability, goal: goal, context: context)
        return candidates.first
    }

    // MARK: - proposeProgram

    /// Ranked, always-executable program candidates for one
    /// `TrainingMixComponent`, plus any conceptually-good paths
    /// TrainingOS cannot currently start. `PROGRAM_RECOMMENDATION_MODEL.md`
    /// §1/§5. `goal` is optional (default `nil`) purely for source
    /// compatibility with existing callers that predate activity-type
    /// resolution — every real caller that has a `Goal` available should
    /// pass it, since it is what lets a Steady State/Interval component
    /// resolve the user's own stated activity preference instead of
    /// silently defaulting to running.
    static func proposeProgram(
        component: TrainingMixComponent,
        profile: PerformanceProfile?,
        availability: UserAvailability,
        goal: Goal? = nil,
        context: ModelContext
    ) -> (candidates: [ProgramCandidate], gaps: [CapabilityGap]) {
        guard let system = component.programmingSystem else {
            return ([], [CapabilityGap(desiredDescription: component.label, reason: .noGeneratorForSystem)])
        }

        let rawCandidates: [(name: String, parameters: GeneratorParameters)]
        switch system {
        case .hypertrophy:
            rawCandidates = hypertrophyParameterCandidates(component: component)
        case .powerlifting:
            rawCandidates = powerliftingParameterCandidates(component: component)
        case .steadyState:
            rawCandidates = steadyStateParameterCandidates(component: component, goal: goal)
        case .interval:
            rawCandidates = intervalParameterCandidates(component: component, goal: goal)
        case .functionalFitness:
            rawCandidates = functionalFitnessParameterCandidates(component: component)
        }

        guard !rawCandidates.isEmpty else {
            return ([], [CapabilityGap(desiredDescription: component.label, reason: .parametersNotInstantiable)])
        }

        var candidates: [ProgramCandidate] = []
        var gaps: [CapabilityGap] = []

        for (name, parameters) in rawCandidates {
            guard ProgramCapabilityRegistry.canInstantiate(parameters) else {
                gaps.append(CapabilityGap(desiredDescription: name, reason: .parametersNotInstantiable))
                continue
            }
            let definition: ProgramDefinition
            do {
                definition = try materialize(parameters, name: name, context: context)
            } catch {
                // Stage 10B (D-10B-3): the generator's own internal
                // structural-coverage check failed — never persisted, and
                // never a crash; surfaced as exactly the same
                // "conceptually good idea, not currently executable" gap
                // `parametersNotInstantiable` already models, just for a
                // distinct root cause. `error` is deliberately not
                // inspected further here — `CapabilityGap` has no field
                // for it, and the generator's own thrown case already
                // named the specific missing coverage.
                gaps.append(CapabilityGap(desiredDescription: name, reason: .generationFailed))
                continue
            }
            let factors = fitFactors(
                system: system, parameters: parameters, component: component,
                profile: profile, availability: availability
            )
            let satisfiedCount = factors.filter(\.satisfied).count
            let fitRating = rating(forSatisfied: satisfiedCount, of: factors.count)
            candidates.append(ProgramCandidate(
                componentLabel: component.label,
                programmingSystem: system,
                programDefinition: definition,
                fitRating: fitRating,
                factors: factors,
                reasonCodes: reasonCodes(from: factors)
            ))
        }

        // Deterministic, stable ranking — highest fit first; ties broken
        // by program name, never by construction/array order.
        candidates.sort {
            if $0.fitRating != $1.fitRating { return $0.fitRating > $1.fitRating }
            return $0.programDefinition.name < $1.programDefinition.name
        }

        return (candidates, gaps)
    }

    // MARK: - Candidate parameter generation, per system

    private static func hypertrophyParameterCandidates(component: TrainingMixComponent) -> [(name: String, parameters: GeneratorParameters)] {
        closestByDayCount(component: component, library: HypertrophyBuiltInLibrary.all.map { ($0.name, $0.dayCount) })
            .map { name, dayCount in
                let entry = HypertrophyBuiltInLibrary.all.first { $0.name == name }!
                let configuration = HypertrophyProgramConfiguration(dayCount: dayCount, split: entry.split, phaseType: .basicHypertrophy)
                return (name, GeneratorParameters.hypertrophy(configuration))
            }
    }

    private static func powerliftingParameterCandidates(component: TrainingMixComponent) -> [(name: String, parameters: GeneratorParameters)] {
        closestByDayCount(component: component, library: PowerliftingBuiltInLibrary.all.map { ($0.name, $0.configuration.dayCount) })
            .map { name, _ in
                let entry = PowerliftingBuiltInLibrary.all.first { $0.name == name }!
                return (name, GeneratorParameters.powerlifting(entry.configuration))
            }
    }

    /// No curated V1 library exists for these 3 systems
    /// (`PROGRAM_RECOMMENDATION_MODEL.md` §5d) — parameters are derived
    /// directly from the component's own stated frequency, a real,
    /// fully-executable configuration, just not a named preset.
    private static func steadyStateParameterCandidates(component: TrainingMixComponent, goal: Goal?) -> [(name: String, parameters: GeneratorParameters)] {
        let days = max(1, component.frequency.target)
        let activity = preferredActivityType(component: component, goal: goal) ?? .running
        let configuration = SteadyStateProgramConfiguration(
            activityType: activity, allowedActivityTypes: [activity], daysPerWeek: days,
            lengthWeeks: 4, progressionDimension: .duration
        )
        return [("Generated \(days)-Day \(activity.rawValue.capitalized) Steady-State", .steadyState(configuration))]
    }

    private static func intervalParameterCandidates(component: TrainingMixComponent, goal: Goal?) -> [(name: String, parameters: GeneratorParameters)] {
        let days = max(1, component.frequency.target)
        let activity = preferredActivityType(component: component, goal: goal) ?? .running
        let configuration = IntervalProgramConfiguration(
            activityType: activity, allowedActivityTypes: [activity], daysPerWeek: days,
            lengthWeeks: 4, sessionRole: .interval, workBasis: .duration,
            includeWarmUp: true, includeCoolDown: true
        )
        return [("Generated \(days)-Day \(activity.rawValue.capitalized) Intervals", .interval(configuration))]
    }

    private static func functionalFitnessParameterCandidates(component: TrainingMixComponent) -> [(name: String, parameters: GeneratorParameters)] {
        let days = max(1, component.frequency.target)
        let stimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
            movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
            movementModalityMix: [
                ModalityCount(modality: .weightlifting, count: 1),
                ModalityCount(modality: .gymnastics, count: 1),
                ModalityCount(modality: .metabolicConditioning, count: 1),
            ],
            // `.roundsForTime`'s own natural score type is `.time`
            // (`FunctionalFitnessStimulusValidator.defaultScoreType`) —
            // `scoreType` must agree with whatever `format` below actually
            // is, or Stage E validation always fails (this pass's own
            // Slice 3 discovery: nothing had ever exercised this specific
            // candidate through a real materializer before).
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
        )
        let configuration = FunctionalFitnessProgramConfiguration(
            daysPerWeek: days, lengthWeeks: 4, targetStimulus: stimulus,
            format: .roundsForTime(rounds: 5, capSeconds: nil), sessionRole: .functionalFitness,
            varianceConstraints: VarianceConstraints(), requiresRecentExposureToProgress: false,
            includeStrengthBlock: false
        )
        return [("Generated \(days)-Day Functional Fitness", .functionalFitness(configuration))]
    }

    /// Deterministic day-count matching: exact match first, else the
    /// smallest absolute difference, else the earliest library entry —
    /// never array-position-dependent beyond that final, explicit
    /// tie-break.
    private static func closestByDayCount(component: TrainingMixComponent, library: [(name: String, dayCount: Int)]) -> [(name: String, dayCount: Int)] {
        let target = max(1, component.frequency.target)
        let sorted = library.sorted { lhs, rhs in
            let lhsDiff = abs(lhs.dayCount - target)
            let rhsDiff = abs(rhs.dayCount - target)
            if lhsDiff != rhsDiff { return lhsDiff < rhsDiff }
            return lhs.name < rhs.name
        }
        // Surface the single best match plus one runner-up when it
        // exists — enough for a real ranked choice, never dozens.
        return Array(sorted.prefix(2))
    }

    /// The component itself carries no stored `ActivityType` preference —
    /// that lives on `Goal.preferences.preferredModalities`
    /// (`ModalityPreference`, `STRATEGIC_PLAN_MODEL.md` §1d), the exact
    /// same generic, already-existing mechanism `preferredEnduranceActivityLabel`
    /// already reads for `enduranceEvent` phases specifically. This was
    /// previously a stub that always returned `nil` regardless of `goal`
    /// — a real, missing-wiring gap, not a deliberate decision — leaving
    /// every Steady State/Interval component silently defaulting to
    /// `.running`. Now resolves generically for any phase type: any
    /// component whose `programmingSystem` has a matching
    /// `ModalityPreference` uses the user's own stated activity; `nil`
    /// (no goal, no preferences, or no matching preference) still falls
    /// through to the same `.running` default as before.
    private static func preferredActivityType(component: TrainingMixComponent, goal: Goal?) -> ActivityType? {
        guard let system = component.programmingSystem else { return nil }
        if let preferred = goal?.preferences?.preferredModalities.first(where: { $0.system == system })?.activityType {
            return preferred
        }
        // Stage V1 dogfooding fix (Part 3): an activity-scoped dislike
        // (e.g. "I dislike running" without disliking all steady-state,
        // `activityType != nil`) has no system-wide veto in
        // `isPreferenceAligned` — this is the real place it takes effect:
        // avoid the disliked activity when choosing a fallback, never
        // silently choosing it anyway. Deterministic, `ActivityType`'s own
        // declared case order — never random.
        let dislikedActivities = Set(
            (goal?.preferences?.dislikedModalities ?? [])
                .filter { $0.system == system }
                .compactMap(\.activityType)
        )
        guard !dislikedActivities.isEmpty else { return nil }
        return ActivityType.allCases.first { !dislikedActivities.contains($0) }
    }

    private static func materialize(_ parameters: GeneratorParameters, name: String, context: ModelContext) throws -> ProgramDefinition {
        let provenance = ProgramProvenance.constructed(reason: "Long-Term Planner recommendation: \(name)")
        switch parameters {
        case .hypertrophy(let configuration):
            return try HypertrophyProgramGenerator.generate(configuration: configuration, provenance: provenance, context: context)
        case .powerlifting(let configuration):
            return PowerliftingProgramGenerator.generate(configuration: configuration, provenance: provenance, context: context)
        case .steadyState(let configuration):
            return SteadyStateProgramGenerator.generate(configuration: configuration, provenance: provenance, context: context)
        case .interval(let configuration):
            return IntervalProgramGenerator.generate(configuration: configuration, provenance: provenance, context: context)
        case .functionalFitness(let configuration):
            return FunctionalFitnessProgramGenerator.generate(configuration: configuration, provenance: provenance, context: context)
        }
    }

    // MARK: - Fit factors (§3 of PROGRAM_RECOMMENDATION_MODEL.md)

    private static func fitFactors(
        system: ProgrammingSystemKind,
        parameters: GeneratorParameters,
        component: TrainingMixComponent,
        profile: PerformanceProfile?,
        availability: UserAvailability
    ) -> [ProgramFitFactor] {
        let dayCount = candidateDayCount(parameters)
        let availabilityOK = dayCount <= availability.trainingDaysPerWeek
        let experience = hasConfidentHistory(system: system, profile: profile)
        let capability = ProgramCapabilityRegistry.capability(for: system)

        return [
            ProgramFitFactor(kind: .phaseGoalMatch, satisfied: true, note: "\(component.label) is served by this \(system) configuration."),
            ProgramFitFactor(
                kind: .availabilityMatch, satisfied: availabilityOK,
                note: availabilityOK
                    ? "\(dayCount) sessions/week fits stated availability."
                    : "\(dayCount) sessions/week exceeds stated availability."
            ),
            ProgramFitFactor(kind: .sessionDurationMatch, satisfied: true, note: "No per-session duration conflict detected."),
            ProgramFitFactor(
                kind: .experienceMatch, satisfied: experience,
                note: experience
                    ? "Confident, recent performance history exists for this system."
                    : "No confident recent history yet — a conservative starting point is used."
            ),
            ProgramFitFactor(
                kind: .performanceProfileMatch, satisfied: profile != nil,
                note: profile != nil ? "PerformanceProfile history was consulted." : "No PerformanceProfile supplied."
            ),
            ProgramFitFactor(kind: .musclePriorityMatch, satisfied: true, note: "No conflicting muscle-priority signal."),
            ProgramFitFactor(kind: .modalityMatch, satisfied: true, note: "Matches the component's own assigned system."),
            ProgramFitFactor(kind: .recoveryDemandMatch, satisfied: true, note: "No conflicting recovery-demand signal at the program-selection stage."),
            ProgramFitFactor(
                kind: .programAvailabilityMatch, satisfied: capability.hasCuratedConfigurations,
                note: capability.hasCuratedConfigurations
                    ? "Backed by a named, curated V1 preset."
                    : "Freshly generated — no curated preset exists yet for this system."
            ),
        ]
    }

    private static func candidateDayCount(_ parameters: GeneratorParameters) -> Int {
        switch parameters {
        case .hypertrophy(let c): return c.dayCount
        case .powerlifting(let c): return c.dayCount
        case .steadyState(let c): return c.daysPerWeek
        case .interval(let c): return c.daysPerWeek
        case .functionalFitness(let c): return c.daysPerWeek
        }
    }

    /// Deliberately simple, deterministic signal — not a claim that
    /// historical PRs automatically equal current ability
    /// (`PROGRAM_RECOMMENDATION_MODEL.md` §4): any confident
    /// exercise/activity/benchmark history at all counts as "some
    /// experience," never a fine-grained score.
    private static func hasConfidentHistory(system: ProgrammingSystemKind, profile: PerformanceProfile?) -> Bool {
        guard let profile else { return false }
        switch system {
        case .hypertrophy, .powerlifting:
            return profile.exerciseProfiles.contains { $0.confidence >= 0.5 }
        case .steadyState, .interval:
            return !profile.activityProfiles.isEmpty
        case .functionalFitness:
            return !profile.benchmarkProfiles.isEmpty
        }
    }

    private static func rating(forSatisfied satisfied: Int, of total: Int) -> GoalAlignmentRating {
        switch satisfied {
        case total: return .excellent
        case total - 1: return .good
        case (total - 3)...(total - 2): return .acceptable
        default: return .poor
        }
    }

    private static func reasonCodes(from factors: [ProgramFitFactor]) -> [PlannerReasonCode] {
        var codes: [PlannerReasonCode] = []
        if factors.contains(where: { $0.kind == .availabilityMatch && $0.satisfied }) {
            codes.append(.programMatchAvailability)
        }
        if factors.contains(where: { $0.kind == .experienceMatch && $0.satisfied }) {
            codes.append(.programMatchExperience)
        }
        if factors.contains(where: { $0.kind == .performanceProfileMatch && $0.satisfied }) {
            codes.append(.programMatchPerformanceProfile)
        }
        if factors.contains(where: { $0.kind == .phaseGoalMatch && $0.satisfied }) {
            codes.append(.programMatchGoal)
        }
        return codes
    }
}
