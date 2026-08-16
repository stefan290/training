import Foundation

/// One system's own generator-parameter shape, wrapped so
/// `ProgramCapabilityRegistry.canInstantiate` can validate any of the 5
/// systems through one function without losing per-system detail. Never
/// persisted — a pure in-memory query input, so the established
/// "enum-with-payload nested in a persisted wrapping struct" hazard
/// (Stage 4A Bug 2/3) does not apply here at all.
enum GeneratorParameters {
    case hypertrophy(HypertrophyProgramConfiguration)
    case powerlifting(PowerliftingProgramConfiguration)
    case steadyState(SteadyStateProgramConfiguration)
    case interval(IntervalProgramConfiguration)
    case functionalFitness(FunctionalFitnessProgramConfiguration)

    var system: ProgrammingSystemKind {
        switch self {
        case .hypertrophy: return .hypertrophy
        case .powerlifting: return .powerlifting
        case .steadyState: return .steadyState
        case .interval: return .interval
        case .functionalFitness: return .functionalFitness
        }
    }
}

/// What TrainingOS can say about one `ProgrammingSystemKind` today.
struct ProgramSystemCapability: Equatable {
    var system: ProgrammingSystemKind
    /// True for all 5 systems today — reserved for a future system added
    /// without its engine yet (`PROGRAM_RECOMMENDATION_MODEL.md` §5a).
    var hasGenerator: Bool
    /// True only for `.hypertrophy`/`.powerlifting` today
    /// (`V1_PROGRAM_LIBRARY.md`'s 8 curated configurations) — a
    /// curation/UX gap, never an executability one.
    var hasCuratedConfigurations: Bool
    var curatedConfigurationCount: Int
}

enum CapabilityGapReason: String, Codable, CaseIterable {
    /// Never true today — reserved for a future system added without
    /// its engine yet.
    case noGeneratorForSystem
    /// True today for `.steadyState`/`.interval`/`.functionalFitness` —
    /// a curation gap, not an executability one; `canInstantiate` still
    /// returns `true` for well-formed parameters on these systems.
    case noCuratedConfiguration
    /// The parameters themselves don't resolve to a valid configuration
    /// (e.g. a non-positive day count).
    case parametersNotInstantiable
}

/// A conceptually-good path the planner considered but TrainingOS cannot
/// currently start — surfaced separately from `ProgramCandidate`, never
/// disguised as one. `PROGRAM_RECOMMENDATION_MODEL.md` §5b.
struct CapabilityGap {
    var desiredDescription: String
    var reason: CapabilityGapReason
    var suggestedExecutableAlternative: ProgramCandidate?

    init(desiredDescription: String, reason: CapabilityGapReason, suggestedExecutableAlternative: ProgramCandidate? = nil) {
        self.desiredDescription = desiredDescription
        self.reason = reason
        self.suggestedExecutableAlternative = suggestedExecutableAlternative
    }
}

/// Read-only, deterministic query surface over what TrainingOS can
/// actually instantiate today — never guessed or hard-coded by display
/// name. A query layer over already-existing generators/
/// `V1_PROGRAM_LIBRARY.md`'s curated list, not a new source of truth.
/// `PROGRAM_RECOMMENDATION_MODEL.md` §5.
enum ProgramCapabilityRegistry {
    /// All 5 systems have real, tested engines + generators today.
    static func availableProgrammingSystems() -> Set<ProgrammingSystemKind> {
        Set(ProgrammingSystemKind.allCases)
    }

    static func capability(for system: ProgrammingSystemKind) -> ProgramSystemCapability {
        let curatedCount: Int
        switch system {
        case .hypertrophy: curatedCount = 6
        case .powerlifting: curatedCount = 2
        case .steadyState, .interval, .functionalFitness: curatedCount = 0
        }
        return ProgramSystemCapability(
            system: system,
            hasGenerator: true,
            hasCuratedConfigurations: curatedCount > 0,
            curatedConfigurationCount: curatedCount
        )
    }

    /// Structural validity of the parameters themselves — "can a real
    /// `ProgramDefinition` be produced from this, right now" — never a
    /// scheduling-feasibility check (that's `ConcurrentScheduler`'s own,
    /// separate, later gate — `LONG_TERM_PLANNER.md` §2a).
    static func canInstantiate(_ parameters: GeneratorParameters) -> Bool {
        guard availableProgrammingSystems().contains(parameters.system) else { return false }
        switch parameters {
        case .hypertrophy(let configuration):
            return configuration.dayCount > 0
        case .powerlifting(let configuration):
            return configuration.dayCount > 0
        case .steadyState(let configuration):
            return configuration.daysPerWeek > 0 && configuration.lengthWeeks > 0
        case .interval(let configuration):
            return configuration.daysPerWeek > 0 && configuration.lengthWeeks > 0
        case .functionalFitness(let configuration):
            return configuration.daysPerWeek > 0 && configuration.lengthWeeks > 0
        }
    }
}
