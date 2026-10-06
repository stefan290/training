import Foundation

/// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1 (Part III): the 3 real
/// goals this checkpoint gives Functional Fitness programming authority
/// for. Maps directly onto existing `PhaseType` cases — never a second
/// Goal/PhaseType, never an athlete-facing label.
enum FunctionalFitnessProgrammingGoal {
    case muscle
    case strength
    case conditioning

    static func from(phaseType: PhaseType?) -> FunctionalFitnessProgrammingGoal? {
        switch phaseType {
        case .muscleGain: return .muscle
        case .strength: return .strength
        case .fatLoss, .enduranceEvent: return .conditioning
        case .functionalFitness, .recovery, .transition, .maintenance, nil: return nil
        }
    }
}

/// GENERAL PROGRAMMING ALLOCATION ARCHITECTURE V1, generalized by
/// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1 from the original
/// Muscle-only `MuscleGainFFAllocationMagnitude`: how much of a
/// resistance/conditioning-requiring phase's weekly programming
/// requirement falls to Functional Fitness, given how much DEDICATED work
/// (real Hypertrophy/Powerlifting/Running/Cycling components) already
/// exists in the athlete's selected `TrainingMix` this week. A magnitude,
/// never a percentage — computed from real, already-counted
/// `TrainingMixComponent.frequency`/`.programmingSystem` data, never
/// invented. Internal programming authority only.
enum FunctionalFitnessAllocationMagnitude {
    /// Substantial dedicated work already exists elsewhere this week
    /// (e.g. 4 Hypertrophy + 1 FF) — FF contributes complementary
    /// stimulus without needing to carry primary responsibility.
    case low
    /// Dedicated Training Forms and FF share responsibility (e.g. 3
    /// Hypertrophy + 2 FF) — FF must provide meaningful, not merely
    /// complementary, volume.
    case medium
    /// No (or minimal) dedicated work exists elsewhere — FF alone
    /// carries the week's requirement (e.g. 3-5 FF alone).
    case high
}

/// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1 (Part IV): the 8-member
/// session family Functional Fitness can express ANY of the 3 goals
/// through — an internal generation-time signal only, never an
/// athlete-facing label, never a second Goal/PhaseType. Distributed
/// across a week's own FF sessions via the already-real
/// `FunctionalFitnessSessionIntent.sessionIndexInWeek`. Generalizes the
/// prior checkpoint's Muscle-only 3-member `FunctionalFitnessMuscleSessionPurpose`
/// (renamed here) to the full vocabulary Part IV specifies; the 3
/// original cases keep their exact prior meaning/behavior unchanged.
enum FunctionalFitnessSessionFamily: Codable, Equatable {
    /// Part IV.1 — primary resistance volume; optional low-cost work
    /// capacity. Conditioning genuinely NOT mandatory.
    case resistanceDominant
    /// Part IV.2 — high-quality heavy compound strength; low/moderate
    /// complementary assistance.
    case heavyStrength
    /// Part IV.3 — high-quality explosive work; volume stays low enough
    /// to preserve velocity/quality, never turned into fatigue work.
    case powerAthletic
    /// Part IV.4 — resistance stimulus + muscular work capacity; moderate
    /// loading, controlled fatigue. The exact shape the prior checkpoint
    /// already built/validated for 4H+1FF.
    case mixedResistanceWorkCapacity
    /// Part IV.5 — high-output short conditioning, approximate work
    /// domain <10 minutes.
    case shortMixedModal
    /// Part IV.6 — sustained mixed-modal conditioning, approximate work
    /// domain 10-20 minutes.
    case mediumMixedModal
    /// Part IV.7 — sustainable aerobic work, generally 20+ minutes or
    /// structured intervals clearly targeting aerobic sustainability.
    case aerobicEngine
    /// Part IV.8 — fill remaining weekly requirements with limited
    /// recovery cost: unilateral/accessory resistance, carries, trunk,
    /// skill, low-cost aerobic work.
    case lowerFatigueComplementary
}

enum FunctionalFitnessRequirementAllocator {
    /// Real, already-counted `TrainingMixComponent.frequency`/
    /// `.programmingSystem` data — never a percentage, never an invented
    /// score. `dedicatedSystems` is goal-specific: Muscle/Strength look at
    /// dedicated resistance work (Hypertrophy/Powerlifting); Conditioning
    /// looks at dedicated aerobic work (Running/Cycling) — per Part VI's
    /// own "FF responsibility is determined AFTER accounting for
    /// contributions from the other selected Training Forms." Thresholds
    /// match the product spec's own worked examples exactly (4H+1FF→low,
    /// 3H+2FF→medium, FF-alone→high); 1-3 always resolves `.medium` — a
    /// real, disclosed simplification for unlisted combinations.
    static func allocation(mix: TrainingMix, goal: FunctionalFitnessProgrammingGoal) -> FunctionalFitnessAllocationMagnitude {
        let dedicatedSystems: Set<ProgrammingSystemKind>
        switch goal {
        case .muscle, .strength: dedicatedSystems = [.hypertrophy, .powerlifting]
        case .conditioning: dedicatedSystems = [.running, .steadyState, .interval]
        }
        let dedicatedFrequency = mix.orderedComponents
            .filter { component in component.programmingSystem.map { dedicatedSystems.contains($0) } ?? false }
            .reduce(0) { $0 + $1.frequency.target }
        if dedicatedFrequency >= 4 { return .low }
        if dedicatedFrequency >= 1 { return .medium }
        return .high
    }

    /// Pure function: given the resolved goal/magnitude and this week's
    /// real FF session count/position (`sessionIndexInWeek`), returns the
    /// session's family — encoding Part V's EXACT project-lead-specified
    /// sequences per goal/frequency faithfully, never a re-derived
    /// approximation. Frequencies 1-5 are real, authored V1 authority;
    /// `sessionCount` values outside 1-5 are defensive-only (never
    /// reached — 6 is gated to a typed unsupported result before this is
    /// ever called, and `ProgramCapabilityRegistry.isFunctionalFitnessV1Supported`
    /// caps the whole path at 5).
    static func sessionFamily(
        goal: FunctionalFitnessProgrammingGoal, magnitude: FunctionalFitnessAllocationMagnitude,
        sessionCount: Int, sessionIndexInWeek: Int,
        runningContribution: RunningWeeklyContribution? = nil
    ) -> FunctionalFitnessSessionFamily {
        let base = Self.baseSessionFamily(goal: goal, magnitude: magnitude, sessionCount: sessionCount, sessionIndexInWeek: sessionIndexInWeek)
        // CONDITIONING V2 — RUNNING CONTRIBUTION + PRODUCTION PROOF,
        // Section 6: duplication policy. `nil` (every pre-existing call
        // site/test) preserves the exact prior sequence unchanged. When a
        // real Running contribution is supplied and this position would
        // otherwise duplicate an already-supplied SUSTAINED_AEROBIC
        // responsibility (`.aerobicEngine`), prefer the still-legitimate,
        // genuinely distinct `.lowerFatigueComplementary` remaining
        // responsibility instead — never automatically re-creating the
        // same adaptation merely because the FF frequency template
        // contains an `aerobicEngine` slot (Section 6's own example).
        if goal == .conditioning, base == .aerobicEngine, let runningContribution, runningContribution.includesSustainedAerobic {
            return .lowerFatigueComplementary
        }
        return base
    }

    private static func baseSessionFamily(
        goal: FunctionalFitnessProgrammingGoal, magnitude: FunctionalFitnessAllocationMagnitude,
        sessionCount: Int, sessionIndexInWeek: Int
    ) -> FunctionalFitnessSessionFamily {
        switch goal {
        case .muscle:
            switch sessionCount {
            case 1:
                return magnitude == .low ? .mixedResistanceWorkCapacity : .resistanceDominant
            case 2:
                return sessionIndexInWeek == 0 ? .resistanceDominant : .mixedResistanceWorkCapacity
            case 3:
                switch sessionIndexInWeek {
                case 0: return .resistanceDominant
                case 1: return .mixedResistanceWorkCapacity
                default: return .lowerFatigueComplementary
                }
            case 4:
                // Part V, 4 FF/week, MUSCLE-dominant.
                switch sessionIndexInWeek {
                case 0: return .resistanceDominant
                case 1: return .resistanceDominant
                case 2: return .mixedResistanceWorkCapacity
                default: return .lowerFatigueComplementary
                }
            default:
                // Part V, 5 FF/week, MUSCLE. "Do not create five
                // maximal-volume resistance sessions" / "five metcons" —
                // 3 resistance-dominant (distinct pattern emphasis, see
                // `addStrengthBlock`'s own relativeWeek/pattern rotation),
                // one mixed, one lower-fatigue.
                switch sessionIndexInWeek {
                case 0: return .resistanceDominant
                case 1: return .resistanceDominant
                case 2: return .mixedResistanceWorkCapacity
                case 3: return .resistanceDominant
                default: return .lowerFatigueComplementary
                }
            }
        case .strength:
            switch sessionCount {
            case 1:
                return .heavyStrength
            case 2:
                return sessionIndexInWeek == 0 ? .heavyStrength : .mixedResistanceWorkCapacity
            case 3:
                switch sessionIndexInWeek {
                case 0: return .heavyStrength
                case 1: return .heavyStrength
                default: return .powerAthletic
                }
            case 4:
                switch sessionIndexInWeek {
                case 0: return .heavyStrength
                case 1: return .heavyStrength
                case 2: return .heavyStrength
                default: return .powerAthletic
                }
            default:
                // 5 FF/week, STRENGTH: squat / press / power+assistance / hinge-pull / complementary.
                switch sessionIndexInWeek {
                case 0: return .heavyStrength
                case 1: return .heavyStrength
                case 2: return .powerAthletic
                case 3: return .heavyStrength
                default: return .lowerFatigueComplementary
                }
            }
        case .conditioning:
            switch sessionCount {
            case 1:
                return .mediumMixedModal
            case 2:
                return sessionIndexInWeek == 0 ? .shortMixedModal : .mediumMixedModal
            case 3:
                switch sessionIndexInWeek {
                case 0: return .shortMixedModal
                case 1: return .mediumMixedModal
                default: return .aerobicEngine
                }
            case 4:
                switch sessionIndexInWeek {
                case 0: return .shortMixedModal
                case 1: return .mediumMixedModal
                case 2: return .aerobicEngine
                default: return .lowerFatigueComplementary
                }
            default:
                // 5 FF/week, CONDITIONING: at least one short, one
                // medium, one aerobic, one additional distinct
                // interval/work-capacity stimulus, one complementary.
                switch sessionIndexInWeek {
                case 0: return .shortMixedModal
                case 1: return .mediumMixedModal
                case 2: return .aerobicEngine
                case 3: return .mixedResistanceWorkCapacity
                default: return .lowerFatigueComplementary
                }
            }
        }
    }

    /// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1 (Part V, 6 FF
    /// sessions/week): the real recovery/fatigue domain in this codebase
    /// (`ReadinessCheckIn`/`ReadinessAdaptationDecision`) is athlete-
    /// input-driven, never a predictive weekly-distribution model — it
    /// cannot truthfully enforce "at least one session must be
    /// lower-fatigue/low-intensity, vary intensity/modality, never six
    /// hard days" AHEAD of time, at planning time, the way this section
    /// requires. Rather than fake six-day authority, this is the
    /// project-lead-authorized escape hatch: 6 is a real, typed
    /// unsupported assignment, never silently approximated to 5.
    static let sixDayFFUnsupportedReason = "RECOVERY_MODEL_INSUFFICIENT_FOR_SIX_DAY_FF"

    /// FUNCTIONAL FITNESS V2 — RESISTANCE COMPLETION, Section 16: Family
    /// B ("Strength") was confirmed, via a real, deep source
    /// reconstruction (the Resistance Authority Resolution checkpoint's
    /// own Family B reconstruction — see that checkpoint's report), to
    /// be an authored program's intra-week frequency periodization
    /// (each main lift trained twice weekly, once near-maximal/RIR-based
    /// "ordinary," once lower-relative-intensity fixed-rep "Triples"),
    /// NOT a general, reusable, two-role adaptation-role authority a
    /// single standalone FF exposure could truthfully select between.
    /// TrainingOS therefore has no general Functional Fitness Strength
    /// prescription authority yet — the project-lead-authorized escape
    /// hatch here mirrors `sixDayFFUnsupportedReason` exactly: a real,
    /// typed, explicit refusal, never a silent substitution of
    /// Hypertrophy/Powerlifting/generic percentages/invented constants.
    static let generalFFStrengthUnsupportedReason = "GENERAL_FF_STRENGTH_AUTHORITY_NOT_IMPLEMENTED"

    /// GENERAL PROGRAMMING ALLOCATION ARCHITECTURE V1 §5/§10, Part II/VI
    /// of Functional Fitness Programming Authority V1: the real,
    /// currently-capable-of-resistance-stimulus `ProgrammingSystemKind`s.
    /// Running/Cycling/Steady State/Interval cannot provide required
    /// resistance exposure for a Muscle Gain or Strength phase. Used by
    /// `LongTermPlanner.buildCustomMix`'s mix-validation check.
    static let resistanceCapableSystems: Set<ProgrammingSystemKind> = [.hypertrophy, .powerlifting, .functionalFitness]

    /// Part III.C / Part VI: the real, currently-capable-of-aerobic-
    /// conditioning-stimulus systems for a Conditioning-priority phase.
    static let conditioningCapableSystems: Set<ProgrammingSystemKind> = [.running, .steadyState, .interval, .functionalFitness]

    /// PROGRAMMING AUTHORITY V1 — FINAL CLOSE-OUT, Part XV (project-lead
    /// authoritative rule): real, directly-verified finding, not an
    /// assumption — every source-backed resistance form this codebase
    /// currently supports already supplies BOTH knee-dominant (squat) and
    /// hip-dominant (hinge) loaded-pattern coverage on its own, by design:
    ///  - Hypertrophy: `HypertrophySplit`'s own doc comment states every
    ///    split (not only `.fullBody`) "trains everything else at
    ///    maintenance volume" — confirmed by reading that type directly.
    ///  - Powerlifting, and Strength Training (`StrengthSourceContentLibrary`
    ///    — literally `PowerliftingProgramGenerator` under family `.d`/`.e`):
    ///    every real curated week (read directly in `PowerliftingProgramGenerator`)
    ///    includes both a "Legs Move" category (`[.quadriceps, .glutes]`
    ///    — squat) and a "Deadlift Move"/"Hamstring Move" category
    ///    (`[.back, .hamstrings]` — hinge).
    /// Therefore, whenever a real dedicated resistance-capable source
    /// component (frequency >= 1) exists in the mix, Functional Fitness
    /// has ZERO missing-pattern responsibility under the Part XV rule —
    /// forcing squat/hinge into FF's own sessions on top of that would be
    /// exactly the "unnecessary duplicate exposure" the rule forbids. This
    /// is why the rule's "source already supplies squat but not hinge"
    /// scenario cannot be constructed from this codebase's REAL content
    /// today (disclosed in the close-out report, not silently assumed
    /// away) — every real source that supplies one pattern supplies both.
    static func sourceAlreadyProvidesBothLoadedPatterns(mix: TrainingMix?) -> Bool {
        guard let mix else { return false }
        return mix.orderedComponents.contains { component in
            (component.programmingSystem == .hypertrophy || component.programmingSystem == .powerlifting)
                && component.frequency.target > 0
        }
    }

    /// Part XV: the `FunctionalFitnessSessionFamily` cases capable of
    /// carrying a loaded squat/hinge/press/pull pattern at all —
    /// `.lowerFatigueComplementary`'s real main body is carry+trunk only
    /// (see `FunctionalFitnessProgramGenerator.addStrengthBlock`) and
    /// every conditioning-only family carries no strength block whatsoever.
    static let loadedPatternCapableFamilies: Set<FunctionalFitnessSessionFamily> = [
        .resistanceDominant, .mixedResistanceWorkCapacity, .heavyStrength, .powerAthletic,
    ]
}
