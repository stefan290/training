import Foundation

/// The structural container for a Functional Fitness block — deliberately
/// a separate type from `Stimulus` (Stimulus.swift). Two workouts sharing a
/// `WorkoutFormat` (e.g. two AMRAPs) can have completely different
/// stimuli; conflating the two into one type would make that
/// impossible to represent, per `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §2.
///
/// **Never stored directly as a raw `@Model` property.** A real SwiftData
/// crash was reproduced this pass (`Could not cast value of type
/// 'Swift.Optional<Any>' to 'TrainingOS.WorkoutFormat'`) when a store
/// contains multiple `FunctionalFitnessPrescription` rows carrying
/// genuinely different `WorkoutFormat` cases — including at least one
/// case with a `nil` optional payload (`.forTime`/`.roundsForTime`/
/// `.chipper`/`.ladder`'s own `capSeconds: Int?`) — across a real,
/// multi-week materialized graph, fetched from a fresh `ModelContext`.
/// Isolated single-row round trips of the same cases (including `nil`
/// ones) do NOT reproduce it; nor do multiple sibling
/// `FunctionalFitnessPrescriptionTemplate`/bare `FunctionalFitnessPrescription`
/// rows without the full materialized graph — the failure is specific to
/// SwiftData's own automatic per-case column reconstruction going wrong
/// under that fuller, real-world shape. (Confirmed via direct inspection
/// of the real on-disk store: SwiftData already auto-flattens this type's
/// associated values into one column per case-parameter — e.g.
/// `ZCAPSECONDS`/`ZCAPSECONDS1`.../`ZCAPSECONDS5` for the 6 cases that
/// each have their own `capSeconds`-shaped parameter — so this is a
/// decode-time reconstruction bug in SwiftData's own synthesis, not a
/// missing-storage-representation problem; exactly the same class of
/// failure this codebase already found and fixed once for `LoadRule`/
/// `SetCountRule`, see `StrengthProgressionRules.swift`'s own doc
/// comments — "two rows in the same store, differing only in which case
/// they hold, silently decoded the second row's case as `nil`." Root
/// cause not further isolated inside SwiftData itself; the fix here is
/// the same structural one already proven for that precedent: never let
/// SwiftData synthesize the case reconstruction at all.)
///
/// **The fix**: every `@Model` type that previously stored `format:
/// WorkoutFormat` directly (`FunctionalFitnessPrescriptionTemplate`,
/// `FunctionalFitnessPrescription`, `BenchmarkDefinition`) now stores a
/// manually flattened tagged union instead — `WorkoutFormatKind` plus one
/// flat, top-level scalar property per distinct parameter shape — with a
/// computed `var format: WorkoutFormat` bridging property that packs/
/// unpacks it, via the shared `WorkoutFormatCoding` helper below so the
/// packing/unpacking logic itself is written exactly once. See each of
/// those 3 files' own doc comments for the exact flattened field list.
enum WorkoutFormat: Codable, Equatable {
    case amrap(capSeconds: Int)
    case emom(intervalSeconds: Int, totalSeconds: Int)
    case forTime(capSeconds: Int?)
    case roundsForTime(rounds: Int, capSeconds: Int?)
    case chipper(capSeconds: Int?)
    case ladder(direction: LadderDirection, capSeconds: Int?)
    case maxLoad
    case maxReps(capSeconds: Int)
    case intervals(count: Int, workSeconds: Int, restSeconds: Int)
}

enum LadderDirection: String, Codable, CaseIterable {
    case ascending
    case descending
}

/// `WorkoutFormat`'s persisted discriminator — plain `String` rawValue,
/// no associated values, the same shape as `LoadRuleKind`/`SetCountRuleKind`.
enum WorkoutFormatKind: String, Codable, CaseIterable {
    case amrap
    case emom
    case forTime
    case roundsForTime
    case chipper
    case ladder
    case maxLoad
    case maxReps
    case intervals
}

/// The shared pack/unpack logic every `@Model` type storing a flattened
/// `WorkoutFormat` uses — written once here rather than duplicated 3
/// times across `FunctionalFitnessPrescriptionTemplate`/
/// `FunctionalFitnessPrescription`/`BenchmarkDefinition`. A plain value
/// type, never itself persisted.
enum WorkoutFormatCoding {
    /// One flat scalar field per distinct associated-value SHAPE
    /// (`capSeconds` is genuinely shared across `.amrap`/`.forTime`/
    /// `.roundsForTime`/`.chipper`/`.ladder`/`.maxReps` — they never
    /// coexist on the same row, so one field suffices; no need for 6
    /// separate columns the way SwiftData's own buggy automatic synthesis
    /// used).
    struct Flat: Equatable {
        var kind: WorkoutFormatKind
        var capSeconds: Int?
        var rounds: Int?
        var intervalSeconds: Int?
        var totalSeconds: Int?
        var direction: LadderDirection?
        var count: Int?
        var workSeconds: Int?
        var restSeconds: Int?

        static let empty = Flat(kind: .maxLoad, capSeconds: nil, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
    }

    static func flatten(_ format: WorkoutFormat) -> Flat {
        switch format {
        case .amrap(let capSeconds):
            return Flat(kind: .amrap, capSeconds: capSeconds, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
        case .emom(let intervalSeconds, let totalSeconds):
            return Flat(kind: .emom, capSeconds: nil, rounds: nil, intervalSeconds: intervalSeconds, totalSeconds: totalSeconds, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
        case .forTime(let capSeconds):
            return Flat(kind: .forTime, capSeconds: capSeconds, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
        case .roundsForTime(let rounds, let capSeconds):
            return Flat(kind: .roundsForTime, capSeconds: capSeconds, rounds: rounds, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
        case .chipper(let capSeconds):
            return Flat(kind: .chipper, capSeconds: capSeconds, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
        case .ladder(let direction, let capSeconds):
            return Flat(kind: .ladder, capSeconds: capSeconds, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: direction, count: nil, workSeconds: nil, restSeconds: nil)
        case .maxLoad:
            return Flat(kind: .maxLoad, capSeconds: nil, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
        case .maxReps(let capSeconds):
            return Flat(kind: .maxReps, capSeconds: capSeconds, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: nil, workSeconds: nil, restSeconds: nil)
        case .intervals(let count, let workSeconds, let restSeconds):
            return Flat(kind: .intervals, capSeconds: nil, rounds: nil, intervalSeconds: nil, totalSeconds: nil, direction: nil, count: count, workSeconds: workSeconds, restSeconds: restSeconds)
        }
    }

    /// `capSeconds`/other fields default to `0` only for the cases whose
    /// own associated value is a non-optional `Int` (`.amrap`/`.maxReps`,
    /// and `.emom`/`.intervals`'s own required fields) — this can only
    /// happen for a row that was somehow never given a real value through
    /// `flatten(_:)` (i.e. never constructed via the `format` setter),
    /// which no real code path does; it is a defensive fallback, never a
    /// legitimate domain default.
    static func reconstruct(_ flat: Flat) -> WorkoutFormat {
        switch flat.kind {
        case .amrap: return .amrap(capSeconds: flat.capSeconds ?? 0)
        case .emom: return .emom(intervalSeconds: flat.intervalSeconds ?? 0, totalSeconds: flat.totalSeconds ?? 0)
        case .forTime: return .forTime(capSeconds: flat.capSeconds)
        case .roundsForTime: return .roundsForTime(rounds: flat.rounds ?? 0, capSeconds: flat.capSeconds)
        case .chipper: return .chipper(capSeconds: flat.capSeconds)
        case .ladder: return .ladder(direction: flat.direction ?? .ascending, capSeconds: flat.capSeconds)
        case .maxLoad: return .maxLoad
        case .maxReps: return .maxReps(capSeconds: flat.capSeconds ?? 0)
        case .intervals: return .intervals(count: flat.count ?? 0, workSeconds: flat.workSeconds ?? 0, restSeconds: flat.restSeconds ?? 0)
        }
    }
}
