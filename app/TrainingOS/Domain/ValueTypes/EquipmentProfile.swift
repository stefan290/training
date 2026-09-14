import Foundation

/// The engine's pure arithmetic result for a load recommendation —
/// always kilograms, always unrounded. `METRIC_LOAD_MODEL.md`'s
/// "IdealLoad -> EquipmentProfile.resolve()" split: rounding to a real,
/// loadable number happens exactly once, in `EquipmentProfile.resolve(_:)`,
/// never here. Not `Codable` and never persisted — a fresh value computed
/// per recommendation, the same way `ProgressionOutput`/`BlockProgressionOutput`
/// are plain, non-persisted engine outputs.
struct IdealLoad: Equatable {
    var kilograms: Double
}

/// What kind of equipment a resolved load is loadable on — determines
/// whether the whole value rounds (`.barbell`/`.dumbbell`/`.machine`/
/// `.cable`) or only the external portion does (`.bodyweightPlusExternal`,
/// e.g. a weighted pull-up).
enum EquipmentType: String, Codable, CaseIterable {
    case barbell
    case dumbbell
    case machine
    case cable
    case bodyweightPlusExternal
}

/// Which direction `EquipmentProfile.resolve(_:)` rounds to the nearest
/// loadable increment. `.nearest` is the sensible default for ordinary
/// equipment; `.down`/`.up` exist for equipment/contexts that must never
/// overshoot or undershoot a prescribed load.
enum RoundingRule: String, Codable, CaseIterable {
    case nearest
    case down
    case up
}

/// The only place a load actually gets rounded — real user equipment,
/// never the rule/engine layer (`METRIC_LOAD_MODEL.md`). Source
/// spreadsheets round at *every* week off the already-rounded prior week,
/// not once at the end; callers must mirror that (resolve Week 1, then
/// resolve each later week off the *resolved* Week-1 value) or fixture
/// numbers will silently drift.
struct EquipmentProfile: Codable, Equatable {
    var equipmentType: EquipmentType
    var smallestIncrementKg: Double
    var roundingRule: RoundingRule
    /// Only meaningful for `.bodyweightPlusExternal`: the athlete's own
    /// bodyweight, subtracted before rounding so the increment is only
    /// ever applied to the *loadable* external portion (rounding a
    /// bodyweight-inclusive number to a plate increment would produce a
    /// value nobody could actually load).
    var bodyweightKg: Double?

    init(
        equipmentType: EquipmentType,
        smallestIncrementKg: Double,
        roundingRule: RoundingRule = .nearest,
        bodyweightKg: Double? = nil
    ) {
        self.equipmentType = equipmentType
        self.smallestIncrementKg = smallestIncrementKg
        self.roundingRule = roundingRule
        self.bodyweightKg = bodyweightKg
    }

    /// Resolves an unrounded `IdealLoad` to the nearest number this
    /// equipment can actually be loaded to. `smallestIncrementKg <= 0` is
    /// treated as "no rounding" (returns the ideal load unchanged) rather
    /// than dividing by zero — a caller bug, not a crash.
    func resolve(_ idealLoad: IdealLoad) -> Double {
        guard smallestIncrementKg > 0 else { return idealLoad.kilograms }
        switch equipmentType {
        case .bodyweightPlusExternal:
            let bodyweight = bodyweightKg ?? 0
            let externalPortion = max(0, idealLoad.kilograms - bodyweight)
            return bodyweight + Self.round(externalPortion, to: smallestIncrementKg, rule: roundingRule)
        case .barbell, .dumbbell, .machine, .cable:
            return Self.round(idealLoad.kilograms, to: smallestIncrementKg, rule: roundingRule)
        }
    }

    private static func round(_ value: Double, to increment: Double, rule: RoundingRule) -> Double {
        let steps = value / increment
        switch rule {
        case .nearest:
            return steps.rounded() * increment
        case .down:
            return steps.rounded(.down) * increment
        case .up:
            return steps.rounded(.up) * increment
        }
    }

    /// Dogfood Round 1 — Final Close (Finding 1 correction): the real,
    /// per-exercise equipment/increment authority — never a blanket
    /// barbell assumption applied to every exercise regardless of what it
    /// actually is. `equipmentType` is derived from this exact `Exercise`'s
    /// own already-canonical `equipment` field (Exercise Library V1 —
    /// the same identity every other real domain read already trusts);
    /// the increment comes from `UserProfile.equipmentIncrements[exercise
    /// .equipment]` when a real per-user value exists — the exact same
    /// increment authority `RollTacticalWindowUseCase.strengthSlotContext`/
    /// `HypertrophyV2ProgressionEngine` already consult for this same
    /// user. Falls back to this codebase's own existing TRAININGOS_DESIGNED
    /// default (barbell, 2.5 kg) only when neither is resolvable — the
    /// identical fallback every other real call site already used before
    /// this fix, never a new/different one. This is not a second
    /// equipment model: only the pre-existing `EquipmentType`/
    /// `EquipmentProfile` vocabulary, now actually driven by the real
    /// exercise instead of a hardcoded guess.
    static func resolved(for exercise: Exercise, userProfile: UserProfile?) -> EquipmentProfile {
        let equipmentType = EquipmentType.resolved(fromExerciseEquipment: exercise.equipment)
        let increment = userProfile?.equipmentIncrements[exercise.equipment] ?? 2.5
        // No persisted athlete-bodyweight field exists anywhere in this
        // app yet (a separate, unbuilt feature — confirmed by direct
        // search) — `bodyweightKg` stays `nil` here exactly as every
        // other real caller already leaves it; `resolve(_:)`'s own
        // documented `bodyweightKg ?? 0` handling degrades gracefully,
        // never crashes, for the rare `.bodyweightPlusExternal` case.
        return EquipmentProfile(equipmentType: equipmentType, smallestIncrementKg: increment)
    }
}

extension EquipmentType {
    /// Maps `Exercise.equipment`'s existing free-text identity (already
    /// real, already populated by `ExerciseCatalog` for every strength
    /// exercise — "barbell"/"dumbbell"/"machine"/"cable"/"bodyweight") to
    /// this domain's own `EquipmentType` — never a guess invented here,
    /// just a direct correspondence between two already-existing
    /// vocabularies. An unrecognized/not-yet-mapped equipment string degrades to
    /// `.barbell` — the exact same TRAININGOS_DESIGNED default this
    /// codebase's every other real call site already used unconditionally
    /// before this fix, so an exercise this mapping doesn't yet cover is
    /// never worse off than before.
    static func resolved(fromExerciseEquipment equipment: String) -> EquipmentType {
        switch equipment {
        case "barbell": return .barbell
        case "dumbbell": return .dumbbell
        case "machine": return .machine
        case "cable": return .cable
        case "bodyweight": return .bodyweightPlusExternal
        default: return .barbell
        }
    }
}
