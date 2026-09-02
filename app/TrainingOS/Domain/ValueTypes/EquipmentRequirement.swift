import Foundation

/// Stage 10C.1: what physical equipment an `Exercise` actually requires
/// to be performed — e.g. Barbell Bench Press needs `[.barbell, .rack,
/// .bench]`, Back Squat needs `[.barbell, .rack]`. Deliberately a
/// **separate concept** from `Exercise.equipment: String`, which stays
/// completely unchanged and keeps its own existing job: a single,
/// loose "loading family" tag consumed by `UserProfile.equipmentIncrements`
/// (e.g. `"barbell"`/`"dumbbell"`/`"machine"`) to pick a rounding
/// increment. That field answers "how is this exercise loaded"; this
/// type answers "what do I need to actually do this exercise" — two
/// different questions this codebase had conflated into one loose
/// string, confirmed by Stage 10C.1's own audit to have no other real
/// consumer worth disturbing. Purely additive: `Exercise.requiredEquipment`
/// defaults to `[]` (no per-exercise data lost, no migration risk),
/// and nothing yet reads this array — it exists so a **future** Home
/// Gym feature never has to retrofit every exercise's schema again,
/// not because anything consumes it in this pass.
///
/// Deliberately a flat, small, "what do I need in the room" vocabulary
/// — never equipment *quantities*, *locations*, or environmental
/// constraints (ceiling height, floor space) — those remain explicitly
/// deferred to whenever Home Gym itself is actually scoped
/// (`STAGE10C1_EXERCISE_CATALOG_AUDIT.md` §7).
enum EquipmentRequirement: String, Codable, CaseIterable {
    case barbell
    case rack
    case bench
    case dumbbells
    /// A dedicated cable-and-weight-stack station (Lat Pulldown, Cable
    /// Triceps Pushdown, Cable Chest Fly, Face Pull, Seated Cable Row) —
    /// kept distinct from `.machine` below because "do you have a cable
    /// station" and "do you have a leg press machine" are different
    /// real-world questions a future Home Gym feature will need to ask
    /// separately.
    case cableStation
    /// A selectorized machine that isn't cable-based (Leg Press, Leg
    /// Curl, Leg Extension, Calf Raise machines).
    case machine
    case pullUpBar
    case kettlebell
    case medicineBall
    case bodyweight
    case bike
    case rower
    case skiErg
}

/// Stage TE.1: the first real consumer of this vocabulary — user-facing
/// text for the Training Environment settings screen and typed
/// materialization-failure messaging. No second display-name taxonomy.
extension EquipmentRequirement {
    var displayName: String {
        switch self {
        case .barbell: return "Barbell"
        case .rack: return "Squat Rack"
        case .bench: return "Bench"
        case .dumbbells: return "Dumbbells"
        case .cableStation: return "Cable Station"
        case .machine: return "Machine"
        case .pullUpBar: return "Pull-up Bar"
        case .kettlebell: return "Kettlebell"
        case .medicineBall: return "Medicine Ball"
        case .bodyweight: return "Bodyweight Only"
        case .bike: return "Assault Bike"
        case .rower: return "Rower"
        case .skiErg: return "SkiErg"
        }
    }
}
