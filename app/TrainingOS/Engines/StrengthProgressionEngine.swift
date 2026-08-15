import Foundation

/// Pure, deterministic, side-effect-free rule arithmetic for one
/// `PrescriptionTemplate` slot at one specific week — same discipline as
/// `ProgressionEngine`/`BlockProgressionEngine`. No `SwiftData` import, no
/// `ModelContext`; every input is a plain value, every output is a plain
/// value plus a `StrengthReasonCode`. Resolving an entire mesocycle means
/// calling these functions once per week, **in week order**, threading
/// each week's resolved weight/set-count forward as the next week's input
/// — `METRIC_LOAD_MODEL.md`'s cascading-rounding rule means this cannot
/// be short-circuited by computing all weeks independently from the raw
/// RM. Shared by every `StrengthProgressionRules`-based family — Family A
/// (Hypertrophy, Stage 4A) and Families B/C (Powerlifting, Stage 4B);
/// renamed from `HypertrophyProgressionEngine` when Stage 4B confirmed it
/// needed no family-specific logic of its own, only additional rule
/// parameters (`STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4B section).
enum StrengthProgressionEngine {
    /// Resolves this slot's weight for one non-deload week.
    /// `weekIndex` is 0-based (0 = week 1). For `weekIndex == 0`,
    /// `rmKilograms`/`pairedSlotResolvedWeightKg` (whichever `loadRule`
    /// needs) must be supplied; for `weekIndex > 0`,
    /// `weekOneResolvedWeightKg` (this slot's own already-resolved Week-1
    /// value) must be supplied instead — the multiplier always applies to
    /// the resolved Week 1 value, never a recomputation from the raw RM
    /// (`FAMILY_A_WEEKLY_PROGRESSION`/`FAMILY_B_WEEKLY_PROGRESSION`/
    /// `FAMILY_C_WEEKLY_PROGRESSION`). `.linkedToPairedSlot` always reads
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
    ) -> (weightKg: Double?, reasonCode: StrengthReasonCode) {
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
    ///
    /// `isFinalWeek`/`frozenSetCount` default to values that reproduce
    /// Family A's exact original behavior (neither Family B's Week-4
    /// asymmetry nor Family C's freeze ever fires unless the rule itself
    /// carries `applyRatingOnFinalWeek: false` / a non-nil
    /// `freezeAfterWeek`) — existing Family A call sites need not change.
    /// `isFinalWeek` is caller-supplied rather than inferred from
    /// `weekIndex` because this engine has no built-in notion of how many
    /// progressive weeks a mesocycle has; every family implemented so far
    /// happens to use 4, but that is the caller's knowledge, not this
    /// function's assumption. `frozenSetCount` must be the exact value
    /// that was resolved at `weekIndex == freezeAfterWeek` — the caller is
    /// responsible for carrying it forward once frozen.
    static func resolveSetCount(
        rules: StrengthProgressionRules,
        weekIndex: Int,
        previousWeekSetCount: Int?,
        autoregulationRating: Int?,
        isFinalWeek: Bool = false,
        frozenSetCount: Int? = nil
    ) -> (sets: Int?, reasonCode: StrengthReasonCode) {
        switch rules.setCountRule {
        case .fixed(let setsByWeek):
            guard setsByWeek.indices.contains(weekIndex) else { return (nil, .calibrationRequired) }
            return (setsByWeek[weekIndex], .fixedSetSchedule)

        case .autoregulated(let config):
            if weekIndex == 0 {
                return (config.baselineSets, .fixedSetSchedule)
            }
            if let freezeAfterWeek = config.freezeAfterWeek, weekIndex > freezeAfterWeek {
                guard let frozenSetCount else { return (nil, .calibrationRequired) }
                return (frozenSetCount, .autoregulatedSetFrozen)
            }
            if isFinalWeek && !config.applyRatingOnFinalWeek {
                guard let previousWeekSetCount else { return (nil, .calibrationRequired) }
                return (previousWeekSetCount, .autoregulatedSetFinalWeekUnchanged)
            }
            guard let previousWeekSetCount, let autoregulationRating else {
                return (nil, .calibrationRequired)
            }
            let resolvedSets = max(0, previousWeekSetCount + autoregulationRating)
            let reasonCode: StrengthReasonCode = autoregulationRating > 0
                ? .autoregulatedSetIncrease
                : (autoregulationRating < 0 ? .autoregulatedSetDecrease : .autoregulatedSetHold)
            return (resolvedSets, reasonCode)
        }
    }

    /// Resolves this slot's rep goal for one non-deload week — a plain
    /// schedule lookup (`repGoalSchedule`), never computed.
    static func resolveRepGoal(rules: StrengthProgressionRules, weekIndex: Int) -> (repGoal: RepGoal?, reasonCode: StrengthReasonCode) {
        guard rules.repGoalSchedule.indices.contains(weekIndex) else { return (nil, .calibrationRequired) }
        return (rules.repGoalSchedule[weekIndex], .repGoalSchedule)
    }
}
