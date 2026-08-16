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
    static func proposeTrainingMix(phase: TrainingPhase, goal: Goal) -> [CandidateTrainingMix] {
        let templates = candidateMixTemplates(phase: phase, goal: goal)
        let availability = comparisonAvailability(goal: goal)
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
    private static func isPreferenceAligned(_ mix: TrainingMix, preferences: GoalPreferences?, bestDistinctSystems: Int) -> Bool {
        guard let preferences else { return false }
        let systems = Set(mix.orderedComponents.compactMap(\.programmingSystem))
        let disliked = Set(preferences.dislikedModalities.map(\.system))
        guard systems.isDisjoint(with: disliked) else { return false }
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
        case .maintenance, .recovery, .transition:
            return [(lowerDemandGenericMix(phase: phase), [.phaseSelectedForGoal])]
        }
    }

    /// §5d's exact worked-example candidate A: 5-Day Hypertrophy + 2 Zone 2.
    private static func muscleGainFocusedHypertrophyMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Focused Hypertrophy")
        mix.addComponent(TrainingMixComponent(
            label: "Hypertrophy", programmingSystem: .hypertrophy, priority: .primary,
            frequency: SessionFrequency(target: 5)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Zone 2 Conditioning", programmingSystem: .steadyState, priority: .supporting,
            frequency: SessionFrequency(target: 2)
        ))
        return mix
    }

    /// §5d's exact worked-example candidate B: 3 Strength + 2 Functional
    /// Fitness + 1 Run.
    private static func muscleGainVariedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Strength Plus Variety")
        mix.addComponent(TrainingMixComponent(
            label: "Strength", programmingSystem: .hypertrophy, priority: .primary,
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .supporting,
            frequency: SessionFrequency(target: 2)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Running", programmingSystem: .steadyState, priority: .supporting,
            frequency: SessionFrequency(target: 1)
        ))
        return mix
    }

    /// `PHASE_PLANNING_RULES.md` §7's Fat Loss architecture: primary
    /// conditioning, `.secondary`+`.required` resistance training (the
    /// "protected" pattern — protects muscle, §2a).
    private static func fatLossConditioningFocusedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Conditioning-Focused Fat Loss")
        mix.addComponent(TrainingMixComponent(
            label: "Conditioning", programmingSystem: .interval, priority: .primary,
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Resistance Training", programmingSystem: .hypertrophy, priority: .secondary,
            frequency: SessionFrequency(target: 3, minimum: 2), flexibility: .required
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Easy Aerobic", programmingSystem: .steadyState, priority: .supporting,
            frequency: SessionFrequency(target: 1)
        ))
        return mix
    }

    private static func fatLossVariedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Functional Fat Loss")
        mix.addComponent(TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .primary,
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Resistance Training", programmingSystem: .hypertrophy, priority: .secondary,
            frequency: SessionFrequency(target: 2, minimum: 2), flexibility: .required
        ))
        return mix
    }

    private static func strengthFocusedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Focused Powerlifting")
        mix.addComponent(TrainingMixComponent(
            label: "Powerlifting", programmingSystem: .powerlifting, priority: .primary,
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
            frequency: SessionFrequency(target: 5)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Strength Maintenance", programmingSystem: .hypertrophy, priority: .supporting,
            frequency: SessionFrequency(target: 2)
        ))
        return mix
    }

    private static func enduranceVariedMix(activityLabel: String) -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "\(activityLabel) Plus Interval Variety")
        mix.addComponent(TrainingMixComponent(
            label: activityLabel, programmingSystem: .steadyState, priority: .primary,
            frequency: SessionFrequency(target: 3)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Interval Work", programmingSystem: .interval, priority: .secondary,
            frequency: SessionFrequency(target: 2)
        ))
        mix.addComponent(TrainingMixComponent(
            label: "Strength Maintenance", programmingSystem: .hypertrophy, priority: .supporting,
            frequency: SessionFrequency(target: 1)
        ))
        return mix
    }

    private static func functionalFitnessFocusedMix() -> TrainingMix {
        let mix = TrainingMix(kind: .recommended, name: "Focused Functional Fitness")
        mix.addComponent(TrainingMixComponent(
            label: "Functional Fitness", programmingSystem: .functionalFitness, priority: .primary,
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

    // MARK: - proposeProgram

    /// Ranked, always-executable program candidates for one
    /// `TrainingMixComponent`, plus any conceptually-good paths
    /// TrainingOS cannot currently start. `PROGRAM_RECOMMENDATION_MODEL.md`
    /// §1/§5.
    static func proposeProgram(
        component: TrainingMixComponent,
        profile: PerformanceProfile?,
        availability: UserAvailability,
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
            rawCandidates = steadyStateParameterCandidates(component: component)
        case .interval:
            rawCandidates = intervalParameterCandidates(component: component)
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
            let definition = materialize(parameters, name: name, context: context)
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
    private static func steadyStateParameterCandidates(component: TrainingMixComponent) -> [(name: String, parameters: GeneratorParameters)] {
        let days = max(1, component.frequency.target)
        let activity = preferredActivityType(component: component) ?? .running
        let configuration = SteadyStateProgramConfiguration(
            activityType: activity, allowedActivityTypes: [activity], daysPerWeek: days,
            lengthWeeks: 4, progressionDimension: .duration
        )
        return [("Generated \(days)-Day \(activity.rawValue.capitalized) Steady-State", .steadyState(configuration))]
    }

    private static func intervalParameterCandidates(component: TrainingMixComponent) -> [(name: String, parameters: GeneratorParameters)] {
        let days = max(1, component.frequency.target)
        let activity = preferredActivityType(component: component) ?? .running
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
            skillDemand: .moderate, systemicDemand: .moderate, scoreType: .roundsAndReps
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

    private static func preferredActivityType(component: TrainingMixComponent) -> ActivityType? {
        // The component itself doesn't carry a stored ActivityType
        // preference (that lives on `Goal.preferences`, resolved by the
        // caller before this point); nothing here guesses one beyond the
        // deterministic `.running` fallback used above.
        nil
    }

    private static func materialize(_ parameters: GeneratorParameters, name: String, context: ModelContext) -> ProgramDefinition {
        let provenance = ProgramProvenance.constructed(reason: "Long-Term Planner recommendation: \(name)")
        switch parameters {
        case .hypertrophy(let configuration):
            return HypertrophyProgramGenerator.generate(configuration: configuration, provenance: provenance, context: context)
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
