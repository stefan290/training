import Foundation

/// Places already-materialized Sessions onto a tactical calendar window.
/// `ConcurrentScheduler` never generates training methodology, never
/// prescribes intensity and never picks exercises — every `Session` it
/// receives already exists, fully formed, produced by some
/// `ProgrammingSystem`'s materializer. Its only job is calendar placement:
/// ordering across systems, same-day pairing, recovery spacing and
/// conflict resolution.
///
/// Deterministic by construction: `schedule(_:constraints:)` never reads
/// the system clock (the caller supplies `SchedulingWindow.startDate`
/// explicitly), never uses randomness, and every tie-break below is a
/// fixed, documented rule — identical inputs always produce an identical
/// `ScheduleProposal`.
///
/// **Conflict resolution (hardening pass).** When two sessions could both
/// use the same day, this is the exact, fixed order used to decide who
/// gets it — never "whichever component was inserted first":
/// 1. Hard constraints (availability/spacing/capacity) — a session with
///    no hard-valid day at all is never a contender, full stop.
/// 2. Required-minimum urgency — every component's own required minimum
///    (or target, when no minimum was set) is placed, across ALL
///    components, before any component's sessions BEYOND its own
///    minimum are even attempted (`buildPhases` below).
/// 3. `TrainingPhase`/mix primary-goal protection — within either of the
///    phases above, a `.primary`-priority component's session is
///    processed ahead of any non-primary one.
/// 4. Component priority ordinal (`.primary` < `.secondary` < `.supporting`).
/// 5. Program-ordering — a component's own sessions are attempted in
///    their materialized order, `isKeySession` promoted first (see
///    `CONCURRENT_SCHEDULER.md`'s "key sessions" section).
/// 6. Interference/recovery preference — see `PlacementScore` below.
/// 7. User preferred days — see `PlacementScore` below.
/// 8. Stable deterministic tie-break — `componentLabel` alphabetically,
///    then the session's own position, never array/insertion order.
enum ConcurrentScheduler {
    /// Bump only when the placement algorithm changes in a way that
    /// could alter results for identical inputs — never for a pure
    /// refactor. An already-`AcceptScheduleProposalUseCase`-accepted
    /// Session's `schedulerVersion` must never be reinterpreted by a
    /// later version; see `Session.schedulerVersion`'s own doc comment.
    static let currentVersion = 2

    static func schedule(
        _ inputs: [ScheduledProgramInput],
        constraints: SchedulingConstraints
    ) -> ScheduleProposal {
        let (phase1, phase2) = buildPhases(inputs)

        let availabilityConstrained = (0..<constraints.window.numberOfDays).contains { offset in
            !constraints.availability.isUsable(weekday(for: constraints.window.date(forDayOffset: offset)))
        }

        var state = PlacementState()
        var placements: [SessionPlacement] = []
        var issues: [ScheduleIssue] = []
        var unplaced: [String: [SchedulableSession]] = [:]

        for (phaseIndex, phase) in [phase1, phase2].enumerated() {
            let isMinimumGuaranteePhase = phaseIndex == 0
            for (index, item) in phase.enumerated() {
                place(
                    item: item,
                    index: index,
                    phase: phase,
                    isMinimumGuaranteePhase: isMinimumGuaranteePhase,
                    constraints: constraints,
                    availabilityConstrained: availabilityConstrained,
                    state: &state,
                    placements: &placements,
                    issues: &issues,
                    unplaced: &unplaced
                )
            }
        }

        let placedCountByLabel = Dictionary(grouping: placements, by: \.componentLabel).mapValues(\.count)
        let conflicts = unplaced.keys.sorted().map { label in
            buildConflict(label: label, items: unplaced[label] ?? [], placedCountByLabel: placedCountByLabel, constraints: constraints)
        }
        issues.append(contentsOf: componentLevelIssues(unplaced: unplaced, placedCountByLabel: placedCountByLabel))

        let feasibility: ScheduleFeasibility
        if !conflicts.isEmpty {
            feasibility = .infeasible
        } else if issues.contains(where: { $0.severity == .soft }) {
            feasibility = .feasibleWithSoftViolations
        } else {
            feasibility = .feasible
        }

        return ScheduleProposal(
            schedulerVersion: currentVersion,
            window: constraints.window,
            placements: placements,
            conflicts: conflicts,
            feasibility: feasibility,
            issues: issues
        )
    }

    // MARK: - Mutable placement state

    /// Everything the placement loop mutates as it commits sessions,
    /// threaded through both phases so a phase-2 session correctly sees
    /// every phase-1 placement's occupancy/spacing effects.
    private struct PlacementState {
        var dayOccupants: [Int: [SchedulableSession]] = [:]
        var lastPlacedOffset: [ObjectIdentifier: Int] = [:]
    }

    // MARK: - Phase construction (factor 2: required-minimum urgency)

    /// Splits every component's own sessions into "counts toward its
    /// required minimum" (phase 1) and "beyond it" (phase 2), then sorts
    /// each phase into one single, deterministic global processing order
    /// (factors 3-5/8). Nothing here looks at calendar days yet — this is
    /// pure ordering, not placement.
    private static func buildPhases(_ inputs: [ScheduledProgramInput]) -> (phase1: [SchedulableSession], phase2: [SchedulableSession]) {
        var phase1: [SchedulableSession] = []
        var phase2: [SchedulableSession] = []

        for input in inputs {
            let component = input.component
            let ownOrder = input.sessions.enumerated()
                .map { index, session -> SchedulableSession in
                    let previousNaiveDate = index > 0 ? input.sessions[index - 1].day?.date : nil
                    return makeSchedulable(session, component, index, previousNaiveDate: previousNaiveDate)
                }
                .sorted { lhs, rhs in
                    // isKeySession promoted first (factor 5's one exception
                    // to plain sequence order); componentSortIndex breaks
                    // ties among sessions of equal importance.
                    if lhs.isKeySession != rhs.isKeySession { return lhs.isKeySession }
                    return lhs.componentSortIndex < rhs.componentSortIndex
                }
                // Re-stamp `componentSortIndex` to this importance-first
                // order. Without this, `processingOrder`'s own
                // same-component tie-break (which reads `componentSortIndex`)
                // would silently undo the promotion above and fall back to
                // plain materialized order — `componentSortIndex` from here
                // on means "this component's own effective claim order,"
                // not raw array position.
                .enumerated().map { newIndex, item -> SchedulableSession in
                    var restamped = item
                    restamped.componentSortIndex = newIndex
                    return restamped
                }

            let requiredCount = min(ownOrder.count, component.frequency.minimum ?? component.frequency.target)
            phase1.append(contentsOf: ownOrder.prefix(requiredCount))
            phase2.append(contentsOf: ownOrder.dropFirst(requiredCount))
        }

        phase1.sort(by: processingOrder)
        phase2.sort(by: processingOrder)
        return (phase1, phase2)
    }

    private static func makeSchedulable(
        _ session: Session, _ component: TrainingMixComponent, _ index: Int, previousNaiveDate: Date?
    ) -> SchedulableSession {
        let naiveGap: Int? = {
            guard let previousNaiveDate, let naiveDate = session.day?.date else { return nil }
            let calendar = Calendar.current
            let days = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: previousNaiveDate), to: calendar.startOfDay(for: naiveDate)
            ).day ?? 0
            return max(0, days)
        }()
        return SchedulableSession(
            session: session,
            component: component,
            componentLabel: component.label,
            priority: component.priority,
            flexibility: component.flexibility,
            allowsDoubleSessionPairing: component.allowsDoubleSessionPairing,
            preferredDays: component.preferredDays,
            requiredSpacingDays: component.requiredSpacingDays,
            stressProfile: SessionStressComposer.compose(session),
            componentSortIndex: index,
            isKeySession: session.isKeySession,
            naiveGapFromPreviousSameComponentSession: naiveGap
        )
    }

    /// The total order for factors 3/4/8: primary-goal protection, then
    /// component-priority ordinal, then a fully insertion-order-independent
    /// tie-break (`componentLabel`, then the session's own sequence
    /// position). Never references array position in the caller's
    /// `inputs` — that is precisely the "first-claim" bug this pass fixes.
    private static func processingOrder(_ a: SchedulableSession, _ b: SchedulableSession) -> Bool {
        let aIsPrimary = a.priority == .primary
        let bIsPrimary = b.priority == .primary
        if aIsPrimary != bIsPrimary { return aIsPrimary }

        let aTier = priorityOrdinal(a.priority)
        let bTier = priorityOrdinal(b.priority)
        if aTier != bTier { return aTier < bTier }

        if a.componentLabel != b.componentLabel { return a.componentLabel < b.componentLabel }
        return a.componentSortIndex < b.componentSortIndex
    }

    private static func priorityOrdinal(_ priority: GoalPriority) -> Int {
        switch priority {
        case .primary: return 0
        case .secondary: return 1
        case .supporting: return 2
        }
    }

    /// Maps a `Date` to this project's `Weekday` (Monday = 1 ... Sunday =
    /// 7), independent of `Calendar`'s own Sunday-first `.weekday`
    /// component convention.
    private static func weekday(for date: Date) -> Weekday {
        let raw = Calendar(identifier: .gregorian).component(.weekday, from: date)
        let mapped = raw == 1 ? 7 : raw - 1
        return Weekday(rawValue: mapped) ?? .monday
    }

    // MARK: - Placing one session

    private static func place(
        item: SchedulableSession,
        index: Int,
        phase: [SchedulableSession],
        isMinimumGuaranteePhase: Bool,
        constraints: SchedulingConstraints,
        availabilityConstrained: Bool,
        state: inout PlacementState,
        placements: inout [SessionPlacement],
        issues: inout [ScheduleIssue],
        unplaced: inout [String: [SchedulableSession]]
    ) {
        var hardValidOffsets: [Int] = []
        var invalidTally: [ScheduleIssueCode: Int] = [:]
        for offset in 0..<constraints.window.numberOfDays {
            switch hardCheck(offset: offset, item: item, state: state, constraints: constraints) {
            case .valid:
                hardValidOffsets.append(offset)
            case .invalid(let code):
                invalidTally[code, default: 0] += 1
            }
        }

        guard !hardValidOffsets.isEmpty else {
            unplaced[item.componentLabel, default: []].append(item)
            let code = representativeIssueCode(from: invalidTally)
            issues.append(ScheduleIssue(
                code: code,
                severity: .hard,
                componentLabel: item.componentLabel,
                session: item.session,
                reason: "\(item.componentLabel)'s \(item.session.name) could not be placed anywhere in the window (\(code.rawValue))."
            ))
            return
        }

        let scored = hardValidOffsets.map {
            (offset: $0, score: score(for: $0, item: item, dayOccupants: state.dayOccupants, constraints: constraints))
        }
        // `PlacementScore` is lexicographically ordered with day offset as
        // the final tie-break, so `min` here is unambiguous.
        let winner = scored.min { $0.score < $1.score }!
        let offset = winner.offset
        let date = constraints.window.date(forDayOffset: offset)
        let occupantsBefore = state.dayOccupants[offset] ?? []
        let isDouble = !occupantsBefore.isEmpty
        let dayWeekday = weekday(for: date)
        let isPreferredDay = item.preferredDays.contains(dayWeekday)
        let allHardValidDaysAlreadyOccupied = hardValidOffsets.allSatisfy { !(state.dayOccupants[$0] ?? []).isEmpty }

        var reasonCodes: [SchedulingReasonCode] = [.programOrderPreserved]
        if isMinimumGuaranteePhase {
            reasonCodes.append(.requiredFrequencyProtected)
        }
        if item.priority == .primary {
            // Factor 3 in action: only claim this when a genuine,
            // still-pending, different-component contender could ALSO
            // have used this exact day right now — never merely because
            // this component happened to be processed first.
            let hadGenuineContender = phase[(index + 1)...].contains { other in
                guard ObjectIdentifier(other.component) != ObjectIdentifier(item.component) else { return false }
                if case .valid = hardCheck(offset: offset, item: other, state: state, constraints: constraints) { return true }
                return false
            }
            if hadGenuineContender {
                reasonCodes.append(.primaryGoalPriority)
            }
        }
        if item.requiredSpacingDays != nil, state.lastPlacedOffset[ObjectIdentifier(item.component)] != nil {
            reasonCodes.append(.recoverySpacing)
        }
        if isDouble {
            reasonCodes.append(.doubleSessionSelected)
            reasonCodes.append(.lowIntensityPairing)
            if allHardValidDaysAlreadyOccupied {
                issues.append(ScheduleIssue(
                    code: .doubleSessionRequired,
                    severity: .soft,
                    componentLabel: item.componentLabel,
                    session: item.session,
                    reason: "\(item.componentLabel)'s \(item.session.name) could only be placed by doubling on \(date) — no free day existed."
                ))
            }
        }
        if isPreferredDay {
            reasonCodes.append(.preferredDayUsed)
        }
        if availabilityConstrained {
            reasonCodes.append(.availabilityConstraint)
        }
        if winner.score.interferenceViolated != 0 {
            reasonCodes.append(.softConstraintViolated)
            issues.append(ScheduleIssue(
                code: .interferenceConflict,
                severity: .soft,
                componentLabel: item.componentLabel,
                session: item.session,
                reason: "Placed \(item.componentLabel) on \(date) despite an interference rule — no interference-clean day was available within the window."
            ))
        } else if hardValidOffsets.contains(where: { candidate in
            candidate != offset
                && score(for: candidate, item: item, dayOccupants: state.dayOccupants, constraints: constraints).interferenceViolated != 0
        }) {
            reasonCodes.append(.interferenceAvoided)
        }
        if !isPreferredDay, !item.preferredDays.isEmpty,
           !hardValidOffsets.contains(where: { item.preferredDays.contains(weekday(for: constraints.window.date(forDayOffset: $0))) }) {
            reasonCodes.append(.softConstraintViolated)
            issues.append(ScheduleIssue(
                code: .preferenceCompromise,
                severity: .soft,
                componentLabel: item.componentLabel,
                session: item.session,
                reason: "\(item.componentLabel) had no preferred day available within the window; placed on \(date) instead."
            ))
        }
        if item.component.trainingMix?.kind == .selected {
            reasonCodes.append(.userSelectedMix)
        }

        state.dayOccupants[offset, default: []].append(item)
        state.lastPlacedOffset[ObjectIdentifier(item.component)] = offset
        placements.append(SessionPlacement(
            session: item.session,
            componentLabel: item.componentLabel,
            date: date,
            sortIndexInDay: occupantsBefore.count,
            reasonCodes: reasonCodes,
            isDoubleSessionPairing: isDouble
        ))
    }

    // MARK: - Hard constraints (factor 1)

    private enum HardCheckResult {
        case valid
        case invalid(ScheduleIssueCode)
    }

    /// TRAININGOS_DESIGNED conservative minute estimates for `DurationDomain`'s
    /// own short(<5)/medium(5-15)/long(>15min) categories — never a claim
    /// of exact duration, just enough to catch a day whose known minutes
    /// clearly can't fit even the shortest interpretation of the category.
    private static func minMinutesNeeded(for domain: DurationDomain) -> Int {
        switch domain {
        case .short: return 5
        case .medium: return 15
        case .long: return 30
        }
    }

    /// Structural floor: a session's own already-known, materializer-
    /// assigned naive date (`session.day?.date` — still intact at
    /// scheduling time, since `AcceptScheduleProposalUseCase.accept` only
    /// re-parents the Session onto its real scheduled Day AFTER a proposal
    /// is accepted, never before) tells us which week of the window it was
    /// originally generated for. A component whose materializer produces
    /// several weeks in one call (Steady State's whole natural block) must
    /// never have a later week's session slide into an earlier week just
    /// because an earlier day happens to be free — the always-decisive
    /// earliest-day tie-break (`PlacementScore.dayOffset`) may still pick
    /// the earliest available day *within* that same week. A `nil` naive
    /// date (no Day assigned yet) imposes no floor, unchanged from prior
    /// behavior.
    private static func originWeekFloorOffset(for session: Session, window: SchedulingWindow) -> Int {
        guard let naiveDate = session.day?.date else { return 0 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: window.startDate)
        let daysSinceStart = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: naiveDate)).day ?? 0
        guard daysSinceStart > 0 else { return 0 }
        return (daysSinceStart / 7) * 7
    }

    /// Prevents "training debt": if an earlier session of this same
    /// component was itself delayed past its own natural offset (e.g. it
    /// lost a day-capacity contest to a higher-priority component during
    /// a phase's shortened first week), this session must inherit that
    /// same delay rather than snapping back to its own uncontested
    /// earliest offset — otherwise two of the same component's sessions
    /// can cluster close together (silently overloading whichever
    /// calendar week absorbs both) while an earlier calendar week goes
    /// without. Returns 0 (no additional floor) for a component's first
    /// session, or when the naive materializer cadence between
    /// consecutive sessions isn't known.
    private static func spacingFloorOffset(for item: SchedulableSession, state: PlacementState) -> Int {
        guard let gap = item.naiveGapFromPreviousSameComponentSession,
              let previousOffset = state.lastPlacedOffset[ObjectIdentifier(item.component)] else { return 0 }
        return previousOffset + gap
    }

    private static func hardCheck(
        offset: Int,
        item: SchedulableSession,
        state: PlacementState,
        constraints: SchedulingConstraints
    ) -> HardCheckResult {
        let floor = max(originWeekFloorOffset(for: item.session, window: constraints.window), spacingFloorOffset(for: item, state: state))
        guard offset >= floor else {
            return .invalid(.earlierThanOriginWeek)
        }

        let date = constraints.window.date(forDayOffset: offset)
        let dayWeekday = weekday(for: date)
        guard constraints.availability.isUsable(dayWeekday) else { return .invalid(.unavailableDay) }

        let occupants = state.dayOccupants[offset] ?? []
        // R0 (mid-week start / no-double production bug fix): a day already
        // consumed by a SIBLING component's real, already-accepted Session
        // from an earlier, separate scheduling call
        // (`constraints.preOccupiedDates`) counts toward this same day's
        // capacity exactly like a real in-call occupant — this is what
        // stops a later `materializeOnceCalibrationComplete` call from
        // silently double-booking a day a prior call already filled.
        let hasExternalOccupant = constraints.preOccupiedDates.contains(Calendar.current.startOfDay(for: date))
        let effectiveOccupantCount = occupants.count + (hasExternalOccupant ? 1 : 0)
        guard effectiveOccupantCount < constraints.availability.maxSessionsPerDay else { return .invalid(.maxSessionsExceeded) }

        if effectiveOccupantCount > 0 {
            guard item.allowsDoubleSessionPairing, constraints.availability.allowsDoubleSessions else { return .invalid(.maxSessionsExceeded) }
            // An externally-occupied day is, by construction, always a
            // DIFFERENT component/instance (a sibling from an earlier,
            // separate materialization pass) — only a real in-call
            // occupant needs the same-component check below.
            guard !occupants.contains(where: { ObjectIdentifier($0.component) == ObjectIdentifier(item.component) }) else { return .invalid(.maxSessionsExceeded) }
        }

        if let minutesAvailable = constraints.availability.minutesAvailablePerDay[dayWeekday],
           minutesAvailable < minMinutesNeeded(for: item.stressProfile?.durationClassification ?? .short) {
            return .invalid(.insufficientTime)
        }

        if let requiredSpacing = item.requiredSpacingDays,
           let last = state.lastPlacedOffset[ObjectIdentifier(item.component)] {
            guard offset - last >= requiredSpacing else { return .invalid(.recoverySpacingCompromise) }
        }

        return .valid
    }

    private static let hardExclusionPrecedence: [ScheduleIssueCode] = [
        .earlierThanOriginWeek, .unavailableDay, .maxSessionsExceeded, .insufficientTime, .recoverySpacingCompromise,
    ]

    private static func representativeIssueCode(from tally: [ScheduleIssueCode: Int]) -> ScheduleIssueCode {
        let maxCount = tally.values.max() ?? 0
        return hardExclusionPrecedence.first { tally[$0] == maxCount } ?? .unavailableDay
    }

    // MARK: - Soft-constraint scoring (factors 6-7)

    /// Lexicographic placement score — lower is better on every field, in
    /// this fixed order: avoid doubling, avoid interference, prefer a
    /// preferred day, prefer the lightest available double-session
    /// partner, then the earliest day (the final, always-decisive
    /// tie-break).
    private struct PlacementScore: Comparable {
        var isDouble: Int
        var interferenceViolated: Int
        var notPreferredDay: Int
        var partnerStressOrdinal: Int
        var dayOffset: Int

        static func < (lhs: PlacementScore, rhs: PlacementScore) -> Bool {
            if lhs.isDouble != rhs.isDouble { return lhs.isDouble < rhs.isDouble }
            if lhs.interferenceViolated != rhs.interferenceViolated { return lhs.interferenceViolated < rhs.interferenceViolated }
            if lhs.notPreferredDay != rhs.notPreferredDay { return lhs.notPreferredDay < rhs.notPreferredDay }
            if lhs.partnerStressOrdinal != rhs.partnerStressOrdinal { return lhs.partnerStressOrdinal < rhs.partnerStressOrdinal }
            return lhs.dayOffset < rhs.dayOffset
        }
    }

    private static func score(
        for offset: Int,
        item: SchedulableSession,
        dayOccupants: [Int: [SchedulableSession]],
        constraints: SchedulingConstraints
    ) -> PlacementScore {
        let date = constraints.window.date(forDayOffset: offset)
        let occupants = dayOccupants[offset] ?? []
        let isDouble = !occupants.isEmpty
        let isPreferredDay = item.preferredDays.contains(weekday(for: date))

        let neighbors = (dayOccupants[offset - 1] ?? []) + (dayOccupants[offset + 1] ?? [])
        let interferenceViolated = (occupants + neighbors).contains { other in
            guard let mine = item.stressProfile, let theirs = other.stressProfile else { return false }
            return constraints.interferenceRules.contains { $0.triggers(mine, theirs) }
        }

        let partnerStressOrdinal = occupants.compactMap { $0.stressProfile.map(maxOrdinal) }.max() ?? 0

        return PlacementScore(
            isDouble: isDouble ? 1 : 0,
            interferenceViolated: interferenceViolated ? 1 : 0,
            notPreferredDay: isPreferredDay ? 0 : 1,
            partnerStressOrdinal: partnerStressOrdinal,
            dayOffset: offset
        )
    }

    private static func maxOrdinal(of profile: TrainingStressProfile) -> Int {
        [
            profile.overallIntensity, profile.systemicDemand, profile.lowerBodyLoad,
            profile.upperBodyLoad, profile.impactLoading, profile.metabolicDemand, profile.recoveryDemand,
        ].map(\.ordinal).max() ?? 0
    }

    // MARK: - Conflicts and component-level issues

    private static func buildConflict(
        label: String,
        items: [SchedulableSession],
        placedCountByLabel: [String: Int],
        constraints: SchedulingConstraints
    ) -> SchedulingConflict {
        guard let sample = items.first else {
            return SchedulingConflict(componentLabel: label, unplacedSessions: [], reason: "No sessions.", resolutionOptions: [])
        }

        var options: [ConflictResolutionOption] = []
        if !(sample.allowsDoubleSessionPairing && constraints.availability.allowsDoubleSessions) {
            options.append(.allowDoubleSessions(componentLabel: label))
        }
        if let excludedWeekday = Weekday.allCases.first(where: { !constraints.availability.isUsable($0) }) {
            options.append(.addAvailableDay(excludedWeekday))
        }
        if sample.flexibility != .required {
            let placed = placedCountByLabel[label] ?? 0
            if placed > 0 {
                options.append(.reduceFrequency(componentLabel: label, to: placed))
            }
            options.append(.shortenOrMoveFlexibleSession(componentLabel: label))
        }

        return SchedulingConflict(
            componentLabel: label,
            unplacedSessions: items,
            reason: "\(items.count) session(s) for \(label) could not be placed within the "
                + "\(constraints.window.numberOfDays)-day window given current availability and spacing constraints.",
            resolutionOptions: options
        )
    }

    /// Component-wide structured facts derived from which components have
    /// any unplaced sessions at all — distinct from the per-session hard
    /// exclusion issues already appended in `place(...)`.
    private static func componentLevelIssues(
        unplaced: [String: [SchedulableSession]],
        placedCountByLabel: [String: Int]
    ) -> [ScheduleIssue] {
        var issues: [ScheduleIssue] = []
        for (label, items) in unplaced.sorted(by: { $0.key < $1.key }) {
            guard let sample = items.first else { continue }
            let component = sample.component
            let placed = placedCountByLabel[label] ?? 0

            switch component.flexibility {
            case .required:
                issues.append(ScheduleIssue(
                    code: .requiredFrequencyUnsatisfied,
                    severity: .hard,
                    componentLabel: label,
                    reason: "\(label) is required but only placed \(placed) of \(component.frequency.minimum ?? component.frequency.target) needed sessions."
                ))
            case .preferred:
                issues.append(ScheduleIssue(
                    code: .preferredFrequencyUnsatisfied,
                    severity: .soft,
                    componentLabel: label,
                    reason: "\(label) is preferred but only placed \(placed) of \(component.frequency.minimum ?? component.frequency.target) needed sessions."
                ))
            case .optional:
                if placed == 0 {
                    issues.append(ScheduleIssue(
                        code: .optionalComponentUnscheduled,
                        severity: .soft,
                        componentLabel: label,
                        reason: "\(label) is optional and could not be scheduled at all within the window."
                    ))
                }
            }

            if component.priority == .primary {
                issues.append(ScheduleIssue(
                    code: .primaryGoalCompromise,
                    severity: .hard,
                    componentLabel: label,
                    reason: "\(label) is this mix's primary-priority component, but \(items.count) of its sessions could not be placed."
                ))
            }
        }
        return issues
    }
}
