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
enum ConcurrentScheduler {
    /// Bump only when the placement algorithm changes in a way that
    /// could alter results for identical inputs — never for a pure
    /// refactor. An already-`AcceptScheduleProposalUseCase`-accepted
    /// Session's `schedulerVersion` must never be reinterpreted by a
    /// later version; see `Session.schedulerVersion`'s own doc comment.
    static let currentVersion = 1

    static func schedule(
        _ inputs: [ScheduledProgramInput],
        constraints: SchedulingConstraints
    ) -> ScheduleProposal {
        // Priority first (primary before secondary before supporting);
        // `sorted` is stable, so ties preserve the caller's own input
        // order — the one remaining degree of freedom is the caller's,
        // not this algorithm's.
        let ordered = flatten(inputs).sorted {
            priorityOrdinal($0.priority) < priorityOrdinal($1.priority)
        }

        let availabilityConstrained = (0..<constraints.window.numberOfDays).contains { offset in
            !constraints.availability.isUsable(weekday(for: constraints.window.date(forDayOffset: offset)))
        }

        var dayOccupants: [Int: [SchedulableSession]] = [:]
        var lastPlacedOffset: [ObjectIdentifier: Int] = [:]
        var placements: [SessionPlacement] = []
        var unplaced: [String: [SchedulableSession]] = [:]
        var warnings: [String] = []

        for item in ordered {
            let hardValidOffsets = (0..<constraints.window.numberOfDays).filter {
                isHardValid(offset: $0, item: item, dayOccupants: dayOccupants,
                            lastPlacedOffset: lastPlacedOffset, constraints: constraints)
            }

            guard !hardValidOffsets.isEmpty else {
                unplaced[item.componentLabel, default: []].append(item)
                continue
            }

            let scored = hardValidOffsets.map {
                (offset: $0, score: score(for: $0, item: item, dayOccupants: dayOccupants, constraints: constraints))
            }
            // `PlacementScore` is lexicographically ordered with day offset
            // as the final tie-break, so `min` here is unambiguous.
            let winner = scored.min { $0.score < $1.score }!
            let offset = winner.offset
            let date = constraints.window.date(forDayOffset: offset)
            let occupantsBefore = dayOccupants[offset] ?? []
            let isDouble = !occupantsBefore.isEmpty
            let dayWeekday = weekday(for: date)
            let isPreferredDay = item.preferredDays.contains(dayWeekday)

            var reasonCodes: [SchedulingReasonCode] = [.programOrderPreserved]
            if priorityOrdinal(item.priority) == 0 {
                reasonCodes.append(.primaryGoalPriority)
            }
            if item.requiredSpacingDays != nil, lastPlacedOffset[ObjectIdentifier(item.component)] != nil {
                reasonCodes.append(.recoverySpacing)
            }
            if isDouble {
                reasonCodes.append(.doubleSessionSelected)
                reasonCodes.append(.lowIntensityPairing)
            }
            if isPreferredDay {
                reasonCodes.append(.preferredDayUsed)
            }
            if availabilityConstrained {
                reasonCodes.append(.availabilityConstraint)
            }
            if winner.score.interferenceViolated != 0 {
                reasonCodes.append(.softConstraintViolated)
                warnings.append(
                    "Placed \(item.componentLabel) on \(date) despite an interference rule — "
                    + "no interference-clean day was available within the window."
                )
            } else if hardValidOffsets.contains(where: { candidate in
                candidate != offset
                    && score(for: candidate, item: item, dayOccupants: dayOccupants, constraints: constraints).interferenceViolated != 0
            }) {
                reasonCodes.append(.interferenceAvoided)
            }
            if !isPreferredDay, !item.preferredDays.isEmpty,
               !hardValidOffsets.contains(where: { item.preferredDays.contains(weekday(for: constraints.window.date(forDayOffset: $0))) }) {
                reasonCodes.append(.softConstraintViolated)
                warnings.append("\(item.componentLabel) had no preferred day available within the window; placed on \(date) instead.")
            }
            if item.component.trainingMix?.kind == .selected {
                reasonCodes.append(.userSelectedMix)
            }

            dayOccupants[offset, default: []].append(item)
            lastPlacedOffset[ObjectIdentifier(item.component)] = offset
            placements.append(SessionPlacement(
                session: item.session,
                componentLabel: item.componentLabel,
                date: date,
                sortIndexInDay: occupantsBefore.count,
                reasonCodes: reasonCodes,
                isDoubleSessionPairing: isDouble
            ))
        }

        let placedCountByLabel = Dictionary(grouping: placements, by: \.componentLabel).mapValues(\.count)
        let conflicts = unplaced.keys.sorted().map { label in
            buildConflict(label: label, items: unplaced[label] ?? [], placedCountByLabel: placedCountByLabel, constraints: constraints)
        }

        let feasibility: ScheduleFeasibility
        if !conflicts.isEmpty {
            feasibility = .infeasible
        } else if placements.contains(where: { $0.reasonCodes.contains(.softConstraintViolated) }) {
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
            warnings: warnings
        )
    }

    // MARK: - Flattening

    private static func flatten(_ inputs: [ScheduledProgramInput]) -> [SchedulableSession] {
        inputs.flatMap { input -> [SchedulableSession] in
            input.sessions.enumerated().map { index, session in
                SchedulableSession(
                    session: session,
                    component: input.component,
                    componentLabel: input.component.label,
                    priority: input.component.priority,
                    flexibility: input.component.flexibility,
                    allowsDoubleSessionPairing: input.component.allowsDoubleSessionPairing,
                    preferredDays: input.component.preferredDays,
                    requiredSpacingDays: input.component.requiredSpacingDays,
                    stressProfile: SessionStressComposer.compose(session),
                    componentSortIndex: index
                )
            }
        }
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

    // MARK: - Hard constraints

    private static func isHardValid(
        offset: Int,
        item: SchedulableSession,
        dayOccupants: [Int: [SchedulableSession]],
        lastPlacedOffset: [ObjectIdentifier: Int],
        constraints: SchedulingConstraints
    ) -> Bool {
        let date = constraints.window.date(forDayOffset: offset)
        guard constraints.availability.isUsable(weekday(for: date)) else { return false }

        let occupants = dayOccupants[offset] ?? []
        guard occupants.count < constraints.availability.maxSessionsPerDay else { return false }

        if !occupants.isEmpty {
            guard item.allowsDoubleSessionPairing, constraints.availability.allowsDoubleSessions else { return false }
            guard !occupants.contains(where: { ObjectIdentifier($0.component) == ObjectIdentifier(item.component) }) else { return false }
        }

        if let requiredSpacing = item.requiredSpacingDays,
           let last = lastPlacedOffset[ObjectIdentifier(item.component)] {
            guard offset - last >= requiredSpacing else { return false }
        }

        return true
    }

    // MARK: - Soft-constraint scoring

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

    // MARK: - Conflicts

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
}
