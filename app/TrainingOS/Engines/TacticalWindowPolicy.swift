import Foundation

/// `TACTICAL_PLANNING_HANDOFF.md` §1 — a tactical window's length is
/// derived, in order, from program/mesocycle boundaries, the phase's own
/// remaining time, and any known upcoming transition date, falling back
/// to a configurable default only when none of those bound it. Pure and
/// deterministic: every date is caller-supplied, never read from the
/// system clock (mirrors `SchedulingWindow.startDate`'s own discipline).
enum TacticalWindowPolicy {
    /// TRAININGOS_DESIGNED, configurable — used only when the primary
    /// component's own system has no natural mesocycle block length.
    static let fallbackWindowWeeks = 4

    /// Every `StrengthProgressionEngine`/`PowerliftingProgramGenerator`
    /// -backed program already runs 4-week blocks with
    /// `TrainingWeek.isDeload` marking week 4 — a real, already-tested
    /// structural fact, not a new guess. SteadyState/Interval/Functional
    /// Fitness have no such fixed block (a single repeating week) and
    /// fall back to the configurable default instead.
    static func naturalBlockWeeks(for system: ProgrammingSystemKind?) -> Int? {
        switch system {
        case .hypertrophy, .powerlifting: return 4
        case .steadyState, .interval, .functionalFitness, .none: return nil
        }
    }

    /// The window length to actually use, in days (a whole number of
    /// weeks) — never longer than the phase has left, and never longer
    /// than any known upcoming transition date, regardless of how long
    /// the primary system's own natural block is. Performance-dependent
    /// progression for a week beyond this length is never fabricated —
    /// simply not generated until the next window (§1's own guarantee;
    /// this function only ever returns a boundary, never materializes
    /// anything past it).
    static func windowLengthInDays(
        primarySystem: ProgrammingSystemKind?,
        asOf: Date,
        phaseEndDate: Date?,
        upcomingTransitionDate: Date? = nil
    ) -> Int {
        var weeks = naturalBlockWeeks(for: primarySystem) ?? fallbackWindowWeeks

        if let phaseEndDate {
            weeks = min(weeks, max(1, wholeWeeksBetween(asOf, phaseEndDate)))
        }
        if let upcomingTransitionDate {
            weeks = min(weeks, max(1, wholeWeeksBetween(asOf, upcomingTransitionDate)))
        }
        return max(1, weeks) * 7
    }

    private static func wholeWeeksBetween(_ start: Date, _ end: Date) -> Int {
        guard end > start else { return 0 }
        let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
        return days / 7
    }

    /// `windowLengthInDays` only ever reflects the mix's *primary*
    /// component's own cadence — a mix's other components (e.g. a Steady
    /// State system, whose materializer produces its whole natural block
    /// in one call regardless of the primary system's block length) can
    /// legitimately materialize sessions further out than that. Widens
    /// the policy window just enough to cover every already-materialized
    /// session actually being scheduled — never shortens it, and never
    /// materializes or schedules anything itself; a pure recomputation
    /// over data the caller already has.
    static func effectiveWindowDays(policyWindowDays: Int, materializedDates: [Date], windowStartDate: Date) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: windowStartDate)
        let maxOffset = materializedDates
            .map { calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: $0)).day ?? 0 }
            .filter { $0 > 0 }
            .max() ?? 0
        guard maxOffset > 0 else { return policyWindowDays }
        let neededDays = ((maxOffset / 7) + 1) * 7
        return max(policyWindowDays, neededDays)
    }
}

/// `TACTICAL_PLANNING_HANDOFF.md` §2 — the two purely date-driven
/// triggers (`.windowApproachingEnd`/`.windowCompleted`). The other four
/// `TacticalWindowTrigger` cases are event-driven — the calling code
/// already knows a phase changed, a mix was swapped, a pause resumed, or
/// a revision was accepted, so there is nothing to "evaluate" for them;
/// this evaluator exists only for the two cases that depend on comparing
/// dates.
enum TacticalWindowTriggerEvaluator {
    /// TRAININGOS_DESIGNED, configurable — the illustrative 7-day
    /// scheduling-buffer default.
    static let defaultApproachingEndBufferDays = 7

    static func evaluate(
        currentWindowEndDate: Date?, asOf: Date, bufferDays: Int = defaultApproachingEndBufferDays
    ) -> TacticalWindowTrigger? {
        guard let end = currentWindowEndDate else { return nil }
        guard asOf < end else { return .windowCompleted }
        let daysRemaining = Calendar.current.dateComponents([.day], from: asOf, to: end).day ?? 0
        guard daysRemaining > bufferDays else { return .windowApproachingEnd }
        return nil
    }
}
