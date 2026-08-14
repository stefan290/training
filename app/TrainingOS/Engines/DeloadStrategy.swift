import Foundation

/// The contract for computing a deload week's weight and rep goal from a
/// slot's rules. Deliberately a protocol, not a single concrete function —
/// Stage 3 decision A4 requires source-derived programs' deload behavior
/// to be preserved exactly per family, even where it looks inconsistent,
/// while a future `TrainingOSDeloadStrategy` (TrainingOS-native programs'
/// own deload rules, not implemented in this pass) must never be
/// conflated with or silently promoted from what a source spreadsheet
/// happened to do.
protocol DeloadStrategy {
    func resolveDeloadWeight(
        rules: StrengthProgressionRules,
        dayPositionInWeek: Int,
        dayCount: Int,
        weekOneResolvedWeightKg: Double?,
        equipmentProfile: EquipmentProfile
    ) -> (weightKg: Double?, reasonCode: HypertrophyReasonCode)

    func resolveDeloadRepGoal(rules: StrengthProgressionRules) -> (repGoal: RepGoal?, reasonCode: HypertrophyReasonCode)

    func resolveDeloadSetCount(rules: StrengthProgressionRules) -> (sets: Int?, reasonCode: HypertrophyReasonCode)
}

/// Implements Family A's exact, validated deload behavior
/// (`FAMILY_A_DELOAD_WEIGHT_ASYMMETRY`/`deloadRepInstruction`, Stage 3
/// decisions A2-A4) — the only deload strategy this pass implements.
/// **Do not** add TrainingOS-native deload rules here; a distinct
/// `TrainingOSDeloadStrategy` conforming to the same `DeloadStrategy`
/// protocol is the correct place for those, kept deliberately unbuilt
/// until actually needed (per the standing instruction not to expand
/// scope speculatively).
struct SourceCompatibleDeloadStrategy: DeloadStrategy {
    /// `deloadWeightBySchedulePosition`: full Week-1 weight for the first
    /// `ceil(dayCount / 2)` days of the week, half for the rest
    /// (`FAMILY_A_DELOAD_WEIGHT_ASYMMETRY`). `dayPositionInWeek` is
    /// 0-based. `DeloadExerciseAction.omit` (the confirmed
    /// Family-A-Mesocycle-2 superset-partner case, decision A2) skips the
    /// slot entirely rather than computing a value.
    func resolveDeloadWeight(
        rules: StrengthProgressionRules,
        dayPositionInWeek: Int,
        dayCount: Int,
        weekOneResolvedWeightKg: Double?,
        equipmentProfile: EquipmentProfile
    ) -> (weightKg: Double?, reasonCode: HypertrophyReasonCode) {
        guard rules.deloadWeightAction == .standard else {
            return (nil, .deloadWeightOmitted)
        }
        guard let weekOneResolvedWeightKg else {
            return (nil, .calibrationRequired)
        }
        let fullWeightDayBoundary = Int((Double(dayCount) / 2.0).rounded(.up))
        let isFullWeightDay = dayPositionInWeek < fullWeightDayBoundary
        let factor = isFullWeightDay ? 1.0 : 0.5
        let resolved = equipmentProfile.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * factor))
        return (resolved, .deloadWeightPrescribed)
    }

    /// `deloadRepInstruction`: `deloadRepFraction` of week 1's rep goal,
    /// always rounded **down** (Stage 3 decision A3 — locked, universal
    /// across every family, not configurable).
    func resolveDeloadRepGoal(rules: StrengthProgressionRules) -> (repGoal: RepGoal?, reasonCode: HypertrophyReasonCode) {
        guard rules.deloadRepAction == .standard else {
            return (nil, .deloadRepOmitted)
        }
        guard let weekOneGoal = rules.repGoalSchedule.first else {
            return (nil, .calibrationRequired)
        }
        let deloadReps = Int((Double(weekOneGoal.reps) * rules.deloadRepFraction).rounded(.down))
        return (RepGoal(reps: deloadReps, toFailure: weekOneGoal.toFailure), .deloadRepPrescribed)
    }

    /// Deload-week sets are a hardcoded constant — `2`, per Family A's
    /// own data — never autoregulated and never read from
    /// `setCountRule` at all, even for an otherwise-`.autoregulated` slot.
    /// Tied to `deloadWeightAction` (not a separate action flag): no
    /// source doc describes a slot that's omitted from deload weight/reps
    /// but still gets a set count.
    func resolveDeloadSetCount(rules: StrengthProgressionRules) -> (sets: Int?, reasonCode: HypertrophyReasonCode) {
        guard rules.deloadWeightAction == .standard else {
            return (nil, .deloadWeightOmitted)
        }
        return (2, .deloadWeightPrescribed)
    }
}
