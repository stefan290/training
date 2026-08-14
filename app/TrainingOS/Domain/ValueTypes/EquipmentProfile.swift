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
}
