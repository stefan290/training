import Foundation

/// Pure, deterministic, side-effect-free rule arithmetic for one
/// `PrescriptionTemplate` slot at one specific week — same discipline as
/// `ProgressionEngine`/`BlockProgressionEngine`. No `SwiftData` import, no
/// `ModelContext`; every input is a plain value, every output is a plain
/// value plus a `HypertrophyReasonCode`. Resolving an entire mesocycle
/// means calling these functions once per week, **in week order**,
/// threading each week's resolved weight/set-count forward as the next
/// week's input — `METRIC_LOAD_MODEL.md`'s cascading-rounding rule means
/// this cannot be short-circuited by computing all weeks independently
/// from the raw RM.
enum HypertrophyProgressionEngine {
    /// Resolves this slot's weight for one non-deload week.
    /// `weekIndex` is 0-based (0 = week 1). For `weekIndex == 0`,
    /// `rmKilograms`/`pairedSlotResolvedWeightKg` (whichever `loadRule`
    /// needs) must be supplied; for `weekIndex > 0`,
    /// `weekOneResolvedWeightKg` (this slot's own already-resolved Week-1
    /// value) must be supplied instead — the multiplier always applies to
    /// the resolved Week 1 value, never a recomputation from the raw RM
    /// (`FAMILY_A_WEEKLY_PROGRESSION`). `.linkedToPairedSlot` always reads
    /// the paired slot's *current week's* resolved value, every week, not
    /// just Week 1 — the fraction is constant, but the paired slot's own
    /// value already progresses week to week on its own rules.
    static func resolveWeight(
        rules: StrengthProgressionRules,
        weekIndex: Int,
        rmKilograms: Double?,
        weekOneResolvedWeightKg: Double?,
        pairedSlotResolvedWeightKg: Double?,
        equipmentProfile: EquipmentProfile
    ) -> (weightKg: Double?, reasonCode: HypertrophyReasonCode) {
        switch rules.loadRule {
        case .rmBased(let payload):
            if weekIndex == 0 {
                guard let rmKilograms else { return (nil, .calibrationRequired) }
                let resolved = equipmentProfile.resolve(IdealLoad(kilograms: rmKilograms * payload.weekOneFactor))
                return (resolved, .rmBasedLoad)
            }
            guard let weekOneResolvedWeightKg else { return (nil, .calibrationRequired) }
            let multiplierIndex = weekIndex - 1
            guard payload.laterWeekMultipliers.indices.contains(multiplierIndex) else { return (nil, .calibrationRequired) }
            let resolved = equipmentProfile.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * payload.laterWeekMultipliers[multiplierIndex]))
            return (resolved, .rmBasedLoad)

        case .linkedToPairedSlot(let fraction):
            guard let pairedSlotResolvedWeightKg else { return (nil, .calibrationRequired) }
            let resolved = equipmentProfile.resolve(IdealLoad(kilograms: pairedSlotResolvedWeightKg * fraction))
            return (resolved, .linkedToPairedSlotLoad)

        case .none:
            return (nil, .noLoadProgression)
        }
    }

    /// Resolves this slot's set count for one non-deload week.
    /// `autoregulatedSetCount`'s week-2-onward adjustment needs the
    /// *previous* week's set count for this same slot plus a live rating
    /// (-1/0/+1) sourced from the paired slot's logged feedback for that
    /// week — both runtime inputs, never stored on the rule itself (see
    /// `SetCountRule.autoregulated`'s doc comment).
    static func resolveSetCount(
        rules: StrengthProgressionRules,
        weekIndex: Int,
        previousWeekSetCount: Int?,
        autoregulationRating: Int?
    ) -> (sets: Int?, reasonCode: HypertrophyReasonCode) {
        switch rules.setCountRule {
        case .fixed(let setsByWeek):
            guard setsByWeek.indices.contains(weekIndex) else { return (nil, .calibrationRequired) }
            return (setsByWeek[weekIndex], .fixedSetSchedule)

        case .autoregulated(let baselineSets):
            if weekIndex == 0 {
                return (baselineSets, .fixedSetSchedule)
            }
            guard let previousWeekSetCount, let autoregulationRating else {
                return (nil, .calibrationRequired)
            }
            let resolvedSets = max(0, previousWeekSetCount + autoregulationRating)
            let reasonCode: HypertrophyReasonCode = autoregulationRating > 0
                ? .autoregulatedSetIncrease
                : (autoregulationRating < 0 ? .autoregulatedSetDecrease : .autoregulatedSetHold)
            return (resolvedSets, reasonCode)
        }
    }

    /// Resolves this slot's rep goal for one non-deload week — a plain
    /// schedule lookup (`repGoalSchedule`), never computed.
    static func resolveRepGoal(rules: StrengthProgressionRules, weekIndex: Int) -> (repGoal: RepGoal?, reasonCode: HypertrophyReasonCode) {
        guard rules.repGoalSchedule.indices.contains(weekIndex) else { return (nil, .calibrationRequired) }
        return (rules.repGoalSchedule[weekIndex], .repGoalSchedule)
    }
}
