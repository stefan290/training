import Foundation

/// Stage 10B.6: the authoritative resolution engine for the new
/// Hypertrophy V2 rule family (`LoadRuleKind.doubleProgression`,
/// `SlotRole`-driven rep ranges) — the day-focus generator's numeric
/// counterpart to `StrengthProgressionEngine`, deliberately a separate
/// engine rather than a new branch inside that shared one: Family A/B/C's
/// `.rmBased`/`.linkedToPairedSlot`/`SourceCompatibleDeloadStrategy`
/// mechanics stay completely untouched, and V2's own set-count bounds/
/// deload shape never risk leaking into them. See
/// `STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md` for the approved
/// design this implements.
///
/// **One authoritative decision path:** `resolveWeight` below delegates
/// entirely to `DoubleProgressionEngine`/`DoubleProgressionHistoryResolver`
/// — the exact same call `CompleteSessionUseCase.progressionPreview`
/// makes for its "Next time" display. Never a second, independently
/// computed opinion.
enum HypertrophyV2ProgressionEngine {
    /// Approved (D-10B6-5): baseline working sets per role. Primary and
    /// secondary intentionally share one baseline — their rep range and
    /// slot priority already differentiate them; no role-specific set
    /// count is invented on top.
    static func baselineSets(for role: SlotRole) -> Int {
        switch role {
        case .primary, .secondary: return 3
        case .accessory: return 2
        }
    }

    /// Approved (D-10B6-2): role-based rep ranges — TRAININGOS-DESIGNED,
    /// evidence-informed, not claimed uniquely optimal.
    static func repRange(for role: SlotRole) -> (low: Int, high: Int) {
        switch role {
        case .primary: return (5, 10)
        case .secondary: return (6, 12)
        case .accessory: return (10, 20)
        }
    }

    /// Approved (D-10B6-1): week-by-week target RIR for primary/secondary,
    /// index 0 = week 1. Accessory uses a flat target every week instead —
    /// never automatically progressed toward failure.
    static let primarySecondaryRirTrajectory: [Int] = [3, 2, 2, 1]
    static let accessoryTargetRir = 2
    /// Approved (D-10B6-8): deload's own explicit target — never derived
    /// from the accumulation weeks' RIR or `toFailure`.
    static let deloadTargetRir = 4

    /// Builds the 4 progressive weeks' `RepGoal`s for a freshly generated
    /// template — a generation-time helper only; materialization reads
    /// the already-persisted schedule back via `resolveRepGoal` below.
    static func makeRepGoalSchedule(for role: SlotRole) -> [RepGoal] {
        let range = repRange(for: role)
        let trajectory = role == .accessory ? Array(repeating: accessoryTargetRir, count: 4) : primarySecondaryRirTrajectory
        return trajectory.map { rir in RepGoal(reps: range.low, toFailure: false, repRangeHigh: range.high, targetRir: rir) }
    }

    // MARK: - Materialization-time resolution

    struct WeightResolution {
        var weightKg: Double?
        var reasonCode: ProgressionReasonCode
        var inputsSummary: String
    }

    /// This week's target rep range/RIR. Progressive weeks read straight
    /// off the template's own stored schedule (index 0 = week 1); the
    /// deload week reuses week 4's rep range with its own explicit RIR
    /// target — never the inherited `toFailure`/RIR-0 the legacy deload
    /// strategy would apply (D-10B6-8).
    static func resolveRepGoal(rules: StrengthProgressionRules, weekIndex: Int, isDeload: Bool) -> RepGoal? {
        guard !isDeload else {
            guard let lastProgressive = rules.repGoalSchedule.last else { return nil }
            return RepGoal(reps: lastProgressive.reps, toFailure: false, repRangeHigh: lastProgressive.repRangeHigh, targetRir: deloadTargetRir)
        }
        guard rules.repGoalSchedule.indices.contains(weekIndex) else { return nil }
        return rules.repGoalSchedule[weekIndex]
    }

    /// Bounded local autoregulation (D-10B6-4): `baseline-1...baseline+2`,
    /// never unbounded upward or downward to zero. Deload ignores the
    /// rating entirely — a fixed `round(baseline*0.5)`, minimum 1
    /// (D-10B6-8), regardless of what the rating would otherwise say.
    static func resolveSetCount(
        role: SlotRole, rules: StrengthProgressionRules, isDeload: Bool,
        previousWeekSetCount: Int?, autoregulationRating: Int?
    ) -> Int {
        let baseline = baselineSets(for: role)
        if isDeload {
            return max(1, Int((Double(baseline) * 0.5).rounded()))
        }
        switch rules.setCountRule {
        case .fixed(let setsByWeek):
            return setsByWeek.first ?? baseline
        case .autoregulated:
            let previous = previousWeekSetCount ?? baseline
            let rating = autoregulationRating ?? 0
            return max(baseline - 1, min(baseline + 2, previous + rating))
        }
    }

    /// The single authoritative weight decision. Looks up real,
    /// exercise-scoped history (never one `ProgramInstance`, never one
    /// `ProgramDefinition`'s own week-1 RM factor) and delegates to
    /// `DoubleProgressionEngine` — the same engine, same call shape,
    /// `CompleteSessionUseCase.progressionPreview` already uses. Reached
    /// identically for week 1 and for the deload week: the deload's own
    /// easier rep/RIR ask is applied by `resolveRepGoal`/`resolveSetCount`
    /// above, never by this function — the weight itself is simply
    /// whatever the athlete's actual recent performance earns, which is
    /// the approved "no arbitrary percentage reduction" design (D-10B6-8).
    static func resolveWeight(
        exercise: Exercise, performanceProfile: PerformanceProfile?, equipmentIncrement: Double
    ) -> WeightResolution {
        let lookup = DoubleProgressionHistoryResolver.lookup(for: exercise, performanceProfile: performanceProfile)
        guard let mostRecent = lookup.mostRecentNormal else {
            return WeightResolution(
                weightKg: nil, reasonCode: .calibrationRequired,
                inputsSummary: "No usable history for this exercise. Opening with a calibration set instead of a guessed load."
            )
        }
        let output = DoubleProgressionEngine().recommend(ProgressionInput(
            targets: mostRecent.targets, latestResults: mostRecent.outcomes, hasUsableHistory: true,
            equipmentIncrement: equipmentIncrement, lastKnownWeight: mostRecent.lastKnownWeight,
            previousTargets: lookup.previousNormal?.targets, previousResults: lookup.previousNormal?.outcomes
        ))
        return WeightResolution(weightKg: output.recommendedWeight, reasonCode: output.reasonCode, inputsSummary: output.inputsSummary)
    }
}
