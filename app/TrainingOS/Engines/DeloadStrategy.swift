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
    ) -> (weightKg: Double?, reasonCode: StrengthReasonCode)

    func resolveDeloadRepGoal(
        rules: StrengthProgressionRules,
        dayPositionInWeek: Int,
        dayCount: Int
    ) -> (repGoal: RepGoal?, reasonCode: StrengthReasonCode)

    func resolveDeloadSetCount(rules: StrengthProgressionRules) -> (sets: Int?, reasonCode: StrengthReasonCode)
}

/// Implements every source family's exact, validated deload behavior —
/// Family A's (`FAMILY_A_DELOAD_WEIGHT_ASYMMETRY`/`deloadRepInstruction`,
/// Stage 3 decisions A2-A4), Family B's (`FAMILY_B_DELOAD`, decision A4)
/// and Family C's (`FAMILY_C_DELOAD`, decision A4) — the only deload
/// strategy this pass implements. **Do not** add TrainingOS-native
/// deload rules here; a distinct `TrainingOSDeloadStrategy` conforming to
/// the same `DeloadStrategy` protocol is the correct place for those,
/// kept deliberately unbuilt until actually needed (per the standing
/// instruction not to expand scope speculatively).
struct SourceCompatibleDeloadStrategy: DeloadStrategy {
    /// `deloadWeightBySchedulePosition`. Default (no
    /// `deloadWeightPositionOverride`): full Week-1 weight for the first
    /// `ceil(dayCount / 2)` days of the week, half for the rest — Family
    /// A's exact, original formula (`FAMILY_A_DELOAD_WEIGHT_ASYMMETRY`).
    /// When the rule carries an override, its explicit boundary/factors
    /// are used instead — Family B's 0.7×/0.5× split (same boundary
    /// formula, different factors) and Family C's fixed-boundary-of-2,
    /// 1.0×(unchanged)/0.5× split (a *different* boundary the formula
    /// cannot derive) both require this. `dayPositionInWeek` is 0-based.
    /// `DeloadExerciseAction.omit` (the confirmed Family-A-Mesocycle-2
    /// superset-partner case, decision A2) skips the slot entirely rather
    /// than computing a value.
    func resolveDeloadWeight(
        rules: StrengthProgressionRules,
        dayPositionInWeek: Int,
        dayCount: Int,
        weekOneResolvedWeightKg: Double?,
        equipmentProfile: EquipmentProfile
    ) -> (weightKg: Double?, reasonCode: StrengthReasonCode) {
        guard rules.deloadWeightAction == .standard else {
            return (nil, .deloadWeightOmitted)
        }
        guard let weekOneResolvedWeightKg else {
            return (nil, .calibrationRequired)
        }
        let boundary: Int
        let fullFactor: Double
        let halfFactor: Double
        if let override = rules.deloadWeightPositionOverride {
            boundary = override.boundaryDayIndex
            fullFactor = override.fullPositionFactor
            halfFactor = override.halfPositionFactor
        } else {
            boundary = Int((Double(dayCount) / 2.0).rounded(.up))
            fullFactor = 1.0
            halfFactor = 0.5
        }
        let factor = dayPositionInWeek < boundary ? fullFactor : halfFactor
        let resolved = equipmentProfile.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg * factor))
        return (resolved, .deloadWeightPrescribed)
    }

    /// `deloadRepInstruction`: default (no `deloadRepPositionOverride`)
    /// applies `deloadRepFraction` uniformly regardless of day — Family
    /// A's exact original behavior. When the rule carries an override,
    /// Family B's day-dependent split (2/3 Monday/Tuesday, 1/2
    /// Thursday/Friday — genuinely different fractions by day, unlike
    /// Family A's single uniform value) is used instead. Always rounded
    /// **down** (Stage 3 decision A3 — locked, universal across every
    /// family, not configurable). `dayPositionInWeek`/`dayCount` default
    /// to values that are simply unused when there's no override, so
    /// every pre-existing Family A call site continues to compile and
    /// behave identically without passing them.
    /// **Stage 10R.1D correction:** the source's own deload-week "Rep
    /// Goal" cell ("1/2 reps of Week 1", "2/3 reps of Week 1") is proven
    /// — by the workbook's own separate "Rep Goal"/"Rep Results" column
    /// headers — to reference the athlete's ACTUAL logged Week-1
    /// performance, never the Week-1 template's authored target (a fixed
    /// rep count OR an RIR value; the source's own instruction text is
    /// identical either way). TrainingOS does not yet thread logged
    /// `SetResult`s into this resolver, and *which* Week-1 set to
    /// reference when several logged different rep counts has no
    /// source-provided answer (`STAGE10R1D_SOURCE_SEMANTICS_CORRECTION.md`'s
    /// deload archaeology: no formula, comment, validation, or
    /// instruction anywhere resolves it). Returning `nil` here — rather
    /// than halving the Week-1 template's rep goal, the pre-10R.1D
    /// defect — is deliberate: fabricating a number from the template
    /// would reintroduce that exact defect under a new name. Deload
    /// weight and set count are unaffected and fully resolved elsewhere.
    func resolveDeloadRepGoal(
        rules: StrengthProgressionRules,
        dayPositionInWeek: Int = 0,
        dayCount: Int = 1
    ) -> (repGoal: RepGoal?, reasonCode: StrengthReasonCode) {
        guard rules.deloadRepAction == .standard else {
            return (nil, .deloadRepOmitted)
        }
        guard rules.repGoalSchedule.first != nil else {
            return (nil, .calibrationRequired)
        }
        return (nil, .deloadRepsRequireLoggedPerformanceData)
    }

    /// Deload-week set count — `rules.deloadSetCount` (default `2`,
    /// Family A's own confirmed constant; see that property's doc comment
    /// for why Families B/C use the same default without independent
    /// source confirmation). Never autoregulated and never read from
    /// `setCountRule` at all, even for an otherwise-`.autoregulated` slot.
    /// Tied to `deloadWeightAction` (not a separate action flag): no
    /// source doc describes a slot that's omitted from deload weight/reps
    /// but still gets a set count.
    func resolveDeloadSetCount(rules: StrengthProgressionRules) -> (sets: Int?, reasonCode: StrengthReasonCode) {
        guard rules.deloadWeightAction == .standard else {
            return (nil, .deloadWeightOmitted)
        }
        return (rules.deloadSetCount, .deloadWeightPrescribed)
    }
}
