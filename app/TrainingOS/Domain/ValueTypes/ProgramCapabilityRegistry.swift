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
    case running(RunningProgramConfiguration)

    var system: ProgrammingSystemKind {
        switch self {
        case .hypertrophy: return .hypertrophy
        case .powerlifting: return .powerlifting
        case .steadyState: return .steadyState
        case .interval: return .interval
        case .functionalFitness: return .functionalFitness
        case .running: return .running
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
    /// Stage 10B addition (D-10B-3): the parameters were well-formed and
    /// `canInstantiate` said yes, but the generator's own internal
    /// structural-coverage check (`HypertrophyProgramGenerator`'s
    /// `validateWeeklyCoverage`) failed while actually building the
    /// template graph — never persisted (see
    /// `HypertrophyGenerationError`'s doc comment). Distinct from
    /// `parametersNotInstantiable`, which is about the *input* shape;
    /// this is about the generator's own output failing its own
    /// contract, a genuinely different failure mode.
    case generationFailed
    /// Source Authority Repair (4/5/6-Day Hypertrophy): the parameters
    /// are structurally valid and `canInstantiate` says yes — a
    /// `ProgramDefinition` genuinely can be built — but its per-day
    /// exercise-slot content is not yet verified against the real,
    /// original source workbook (`ProgramCapabilityRegistry
    /// .isHypertrophySourceVerified`). Distinct from
    /// `parametersNotInstantiable` (an input-shape problem) and
    /// `generationFailed` (the generator's own structural-coverage check
    /// failing): this is a content-fidelity problem discovered by
    /// comparing generated output against `source_workbooks/` /
    /// `SOURCE_PROGRAM_MANIFEST.md`, not a structural one. TrainingOS
    /// must never recommend — and `LongTermPlanner.hypertrophyParameterCandidates`
    /// must never return — a curated configuration in this state; it is
    /// surfaced here as a real `CapabilityGap` instead, exactly like any
    /// other "conceptually good, not currently executable" path, never
    /// silently substituted for the nearest verified frequency.
    case sourceContentUnverified
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
        case .running: curatedCount = RunningBuiltInLibrary.all.count
        case .steadyState, .interval, .functionalFitness: curatedCount = 0
        }
        return ProgramSystemCapability(
            system: system,
            hasGenerator: true,
            hasCuratedConfigurations: curatedCount > 0,
            curatedConfigurationCount: curatedCount
        )
    }

    /// V1 "Explicit Weekly Composition" checkpoint: the exact real weekly
    /// session counts a curated source definition exists for TODAY — read
    /// directly from the same curated libraries `capability(for:)` above
    /// already counts, never a second hand-maintained list. `nil` means
    /// "no curated-frequency restriction" (Functional Fitness/Steady
    /// State/Interval already accept any positive `daysPerWeek` directly
    /// — `PROGRAM_RECOMMENDATION_MODEL.md` §5d). This is intentionally A
    /// STRICTER query than `canInstantiate`/`closestByDayCount`: those
    /// exist to let a `.recommended` candidate template still resolve to
    /// its nearest curated definition (every existing template already
    /// authors an exact-or-deliberately-close target, so this never
    /// changes their behavior); this query exists so a `.selected`,
    /// athlete-built custom composition can be rejected OUTRIGHT for an
    /// unsupported frequency, never silently approximated to the nearest
    /// curated definition (the CRITICAL SOURCE-AUTHORITY CORRECTION this
    /// checkpoint locks — see `LongTermPlanner.buildCustomMix`).
    static func supportedFrequencies(for system: ProgrammingSystemKind) -> [Int]? {
        switch system {
        case .hypertrophy:
            return Array(Set(HypertrophyBuiltInLibrary.all.map(\.dayCount))).sorted()
        case .powerlifting:
            return Array(Set(PowerliftingBuiltInLibrary.all.map(\.configuration.dayCount))).sorted()
        case .running:
            return Array(Set(RunningBuiltInLibrary.all.map(\.configuration.daysPerWeek))).sorted()
        case .steadyState, .interval, .functionalFitness:
            return nil
        }
    }

    /// Running R3 CAPABILITY GATE: whether TrainingOS can materialize the
    /// exact `(distance, daysPerWeek)` combination requested — deliberately
    /// its OWN function, not folded into `isFrequencySupported` (that
    /// query is frequency-only and would silently ignore `distance`,
    /// which is exactly the "silently approximate an unsupported
    /// configuration" failure mode this gate exists to prevent). V1
    /// supports exactly one combination — 5K + 2 days/week — read
    /// directly from `RunningBuiltInLibrary.all`, never a second
    /// hand-maintained allowlist, mirroring `isHypertrophySourceVerified`'s
    /// own fail-closed, explicit-match discipline: a newly-added
    /// `RunningBuiltInLibrary` entry becomes supported automatically (this
    /// reads the library, not a separate list), but nothing is ever
    /// approximated to the nearest curated combination. Callers (the
    /// generator, any future recommendation surface) must treat a `false`
    /// result as "refuse outright," never as "fall back to the nearest
    /// supported entry."
    static func isRunningConfigurationSupported(distance: RunningDistance, daysPerWeek: Int) -> Bool {
        RunningBuiltInLibrary.all.contains {
            $0.configuration.distance == distance && $0.configuration.daysPerWeek == daysPerWeek
        }
    }

    /// `frequency <= 0` is never supported for any system — "zero
    /// sessions of this style" is expressed by omitting the component
    /// entirely, never by a component with a non-positive target.
    static func isFrequencySupported(_ frequency: Int, for system: ProgrammingSystemKind) -> Bool {
        guard frequency > 0 else { return false }
        guard let supported = supportedFrequencies(for: system) else { return true }
        return supported.contains(frequency)
    }

    /// Source Authority Repair (4/5/6-Day Hypertrophy): whether a curated
    /// Hypertrophy `(dayCount, split)` configuration's per-day exercise-
    /// slot CONTENT has been verified against the real, original source
    /// workbook — never whether it merely instantiates structurally
    /// (`canInstantiate` already answers that). `SOURCE_PROGRAM_MANIFEST.md`
    /// §1/§4/§6 is the audit trail this reads its verdict from; keep this
    /// list in exact sync with that manifest's "CURRENT IMPLEMENTATION
    /// STATUS" column whenever a new configuration is migrated — never
    /// mark a configuration verified here without the manifest and the
    /// generator's own real `SourceDay` migration agreeing. Today this is
    /// TRUE for ALL FOUR Family A Full Body configurations, now that
    /// Source Authority Repair Phase C has recovered 6-Day (the last
    /// remaining one) — every day/mesocycle of 3/4/5/6-Day Full Body is
    /// now cell-verified against its own real workbook, matching
    /// `HypertrophyProgramGenerator.generateDayFocusDriven`'s own
    /// `dayCount == 3 || 4 || 5 || 6, split == .fullBody` routing
    /// condition exactly. The two remaining curated
    /// `HypertrophyBuiltInLibrary` entries this checkpoint deliberately
    /// did NOT touch — "4-Day Lower/Leg Focus" (`.legs`) and "5-Day
    /// Upper/Arms Focus" (`.armsShoulders`) — still run
    /// `generateLegacyFixedPair` and correctly report unverified; their
    /// recovery is separate, out-of-scope work (this repair's own scope
    /// control is explicit: Full Body only). This is fail-closed by
    /// design: a newly-added curated entry defaults to unverified until
    /// explicitly listed here, never the reverse. **Still purely
    /// declarative** — not yet read by `LongTermPlanner` (a separate,
    /// later fidelity-gate-activation checkpoint, not this pass).
    static func isHypertrophySourceVerified(dayCount: Int, split: HypertrophySplit) -> Bool {
        (dayCount == 3 || dayCount == 4 || dayCount == 5 || dayCount == 6) && split == .fullBody
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
        case .running(let configuration):
            // Structural validity only (mirrors every other case) — the
            // narrower "is this EXACT combination the one V1 supports"
            // question is `isRunningConfigurationSupported`'s job, checked
            // separately by `RunningProgramGenerator.generate` itself,
            // exactly like `isHypertrophySourceVerified` stays a distinct
            // query from `canInstantiate`.
            return configuration.daysPerWeek > 0
        }
    }
}
