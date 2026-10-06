import Foundation

/// MUSCLE + 5FF FINAL CLOSURE, Sections 10-13 (project-owner decision,
/// verbatim text supplied directly): the real, typed conditioning-
/// composition coherence validator. Distinct from
/// `FunctionalFitnessStimulusValidator` (Stage E) — that type checks
/// whether the composed CONTAINER (format/modality-mix/score-type) still
/// matches the target `Stimulus` it was generated for; this type checks
/// whether the composed CONTENT is internally coherent (a fixed work
/// package that's actually substantial enough for its own duration
/// domain, a SUSTAINED_AEROBIC role that's genuinely duration-based, a
/// SHORT_HIGH_OUTPUT role that isn't secretly a low-intensity movement,
/// a repeated technical movement backed by real evidence, at least one
/// real executable unit, and an AMRAP whose repeatable unit is
/// physiologically sane to repeat). Never silently mutates a
/// composition — returns a typed result the caller acts on (Section 12).
enum FunctionalFitnessCompositionMagnitude: String, Codable, CaseIterable, Comparable {
    case trivial, small, moderate, substantial

    private var ordinal: Int {
        switch self {
        case .trivial: return 0
        case .small: return 1
        case .moderate: return 2
        case .substantial: return 3
        }
    }

    static func < (lhs: FunctionalFitnessCompositionMagnitude, rhs: FunctionalFitnessCompositionMagnitude) -> Bool {
        lhs.ordinal < rhs.ordinal
    }
}

/// Which real, already-composed fact this rule's rejection is about —
/// Section 12's "offendingDimension," read by any future caller/UI
/// instead of parsing a reason string.
enum FunctionalFitnessCompositionDimension: String, Codable {
    case durationDomainVsFormat
    case sustainedAerobicQuantity
    case shortHighOutputIntensity
    case repeatedTechnicalMovementEvidence
    case executableWorkPackage
    case amrapRepeatableUnitCompatibility
}

/// One case per Section 11 minimum-coherence rule (A-F), plus nothing
/// else — this is a closed, locked list exactly matching the order's own
/// lettered rules, never a broader "something about this composition
/// looks wrong" catch-all.
enum FunctionalFitnessCompositionReasonCode: String, Codable {
    /// Rule A: LONG duration domain + FOR_TIME + single trivial cyclical effort.
    case longDurationForTimeTrivialCyclicalEffort
    /// Rule B: SUSTAINED_AEROBIC + tiny fixed distance/calorie prescription.
    case sustainedAerobicTinyFixedQuantity
    /// Rule C: SHORT_HIGH_OUTPUT + LOW-intensity-only movement.
    case shortHighOutputLowIntensityMovement
    /// Rule D: repeated technical movement + insufficient capability/dose evidence.
    case repeatedTechnicalMovementInsufficientEvidence
    /// Rule E: format with no executable work package.
    case noExecutableWorkPackage
    /// Rule F: AMRAP whose repeatable unit is semantically incompatible with assigned stimulus.
    case amrapUnitIncompatibleWithStimulus
}

/// Section 12: the exact typed result shape the order asks for — never a
/// boolean, never a plain string. `.valid` also carries the real,
/// already-computed Section 10 magnitude classification, so a caller
/// that only needs magnitude (e.g. a future recomposition ladder
/// deciding how much to scale back) never has to re-derive it.
enum FunctionalFitnessCompositionValidationResult: Equatable {
    case valid(magnitude: FunctionalFitnessCompositionMagnitude)
    case invalid(reasonCode: FunctionalFitnessCompositionReasonCode, offendingDimension: FunctionalFitnessCompositionDimension)
}

enum FunctionalFitnessCompositionValidator {
    /// A composed movement, reduced to only the fields this validator
    /// needs — deliberately NOT `FunctionalFitnessMovement` itself, so
    /// this validator stays a pure function callable both against a
    /// real, already-persisted `@Model` and against a not-yet-persisted
    /// in-progress composition (Section 13's recomposition ladder needs
    /// to validate a CANDIDATE composition before ever persisting it).
    struct MovementInput: Equatable {
        var exercise: Exercise?
        var reps: Int?
        var distanceMeters: Double?
        var durationSeconds: Int?
        var calories: Int?
        var loadGuidanceTier: RelativeLoadTier?

        init(
            exercise: Exercise? = nil, reps: Int? = nil, distanceMeters: Double? = nil,
            durationSeconds: Int? = nil, calories: Int? = nil, loadGuidanceTier: RelativeLoadTier? = nil
        ) {
            self.exercise = exercise
            self.reps = reps
            self.distanceMeters = distanceMeters
            self.durationSeconds = durationSeconds
            self.calories = calories
            self.loadGuidanceTier = loadGuidanceTier
        }

        static func == (lhs: MovementInput, rhs: MovementInput) -> Bool {
            lhs.exercise?.id == rhs.exercise?.id && lhs.reps == rhs.reps && lhs.distanceMeters == rhs.distanceMeters
                && lhs.durationSeconds == rhs.durationSeconds && lhs.calories == rhs.calories && lhs.loadGuidanceTier == rhs.loadGuidanceTier
        }
    }

    /// Section 10: "use semantic workload units/bounds... does NOT need
    /// an exact predicted completion time... do not fabricate athlete
    /// speed." Classified PURELY from already-real, already-known
    /// structural facts the order itself names (movement count, whether
    /// the format's own shape repeats a round, and `.chipper`'s own
    /// standard, pre-existing meaning — "a large single-pass work
    /// package" — never an invented numeric time/rep/distance cutoff).
    ///
    /// **Honest scope note:** the TRIVIAL boundary below (exactly one
    /// movement, a format with no repeating-round shape) is the one this
    /// checkpoint's Rule A/B actually gate on, and is a genuine
    /// structural fact, not an invented threshold. The SMALL/MODERATE/
    /// SUBSTANTIAL boundary POSITIONS beyond that (e.g. "3 movements is
    /// MODERATE, not SUBSTANTIAL") are a reasonable, documented, good-
    /// faith structural mapping using the order's own named dimensions —
    /// not a locked, verbatim product decision, since the order
    /// deliberately gives no exact numeric boundary for them. No current
    /// rule (A-F) actually depends on distinguishing SMALL from MODERATE
    /// from SUBSTANTIAL; only TRIVIAL-vs-not matters for correctness
    /// today. If a future rule needs an exact SMALL/MODERATE/SUBSTANTIAL
    /// boundary, that is a genuine ambiguous-rule question for the
    /// project owner, not something to guess past.
    static func classifyMagnitude(format: WorkoutFormat, movements: [MovementInput]) -> FunctionalFitnessCompositionMagnitude {
        guard !movements.isEmpty else { return .trivial }

        let isChipper: Bool = { if case .chipper = format { return true }; return false }()
        let repeatsAsARound: Bool
        switch format {
        case .forTime, .maxLoad, .maxReps, .chipper:
            repeatsAsARound = false
        case .roundsForTime(let rounds, _):
            repeatsAsARound = rounds > 1
        case .ladder, .amrap, .emom, .intervals:
            repeatsAsARound = true
        }

        if movements.count == 1, !repeatsAsARound, !isChipper {
            return .trivial
        }
        if isChipper || movements.count >= 4 {
            return .substantial
        }
        if repeatsAsARound || movements.count == 3 {
            return .moderate
        }
        return .small
    }

    /// Section 11's exact 6 rules (A-F), checked in their own lettered
    /// order — deterministic, first-violation-wins, never a combined
    /// "worst of several" result (mirrors this codebase's established
    /// `ScheduleIssue`/`SchedulingReasonCode` precedent: one typed reason
    /// per outcome, never several stacked). `performanceProfile` is only
    /// consulted for Rule D — every other rule is a pure function of the
    /// composition's own structure.
    static func validate(
        format: WorkoutFormat,
        stimulus: Stimulus,
        movements: [MovementInput],
        performanceProfile: PerformanceProfile?
    ) -> FunctionalFitnessCompositionValidationResult {
        // Rule E: format with no executable work package. Checked first —
        // every other rule presumes at least one real, dosed movement
        // exists to reason about.
        let hasExecutableWork = movements.contains {
            $0.reps != nil || $0.distanceMeters != nil || $0.durationSeconds != nil || $0.calories != nil
        }
        guard hasExecutableWork else {
            return .invalid(reasonCode: .noExecutableWorkPackage, offendingDimension: .executableWorkPackage)
        }

        let magnitude = classifyMagnitude(format: format, movements: movements)

        // Rule A: LONG duration domain + FOR_TIME + single trivial
        // cyclical effort — the exact, confirmed "For Time cap 20min /
        // Easy Run 200m" defect, checked here as a typed, defensive
        // backstop even though Section 9's own fix already prevents a
        // properly-generated monostructural role from reaching this
        // shape (hand-authored/future-generator content could still).
        let isPlainForTime: Bool = { if case .forTime = format { return true }; return false }()
        if stimulus.targetDurationDomain == .long, isPlainForTime, magnitude == .trivial,
           let onlyMovement = movements.first, movements.count == 1,
           onlyMovement.exercise?.movementFunctions.contains(.monostructural) == true,
           onlyMovement.durationSeconds == nil {
            return .invalid(reasonCode: .longDurationForTimeTrivialCyclicalEffort, offendingDimension: .durationDomainVsFormat)
        }

        // Rule B: SUSTAINED_AEROBIC + tiny fixed distance/calorie
        // prescription. `.long` IS this codebase's real SUSTAINED_AEROBIC
        // domain (Section 9's own established authority: `.long` gets a
        // duration target, never a fixed distance/calorie one) — so ANY
        // monostructural role in this domain carrying a fixed quantity
        // instead of a duration is wrong regardless of how large or
        // small that quantity is; no numeric "tiny" threshold is needed,
        // since Section 9 already establishes the unit itself (duration,
        // not distance/calories) is the only truthful one here.
        if stimulus.targetDurationDomain == .long {
            let hasFixedQuantityMonostructural = movements.contains { movement in
                movement.exercise?.movementFunctions.contains(.monostructural) == true
                    && movement.durationSeconds == nil
                    && (movement.distanceMeters != nil || movement.calories != nil)
            }
            if hasFixedQuantityMonostructural {
                return .invalid(reasonCode: .sustainedAerobicTinyFixedQuantity, offendingDimension: .sustainedAerobicQuantity)
            }
        }

        // Rule C: SHORT_HIGH_OUTPUT + LOW-intensity-only movement —
        // already enforced at selection time
        // (`FunctionalFitnessPhaseBiasPolicy.applyWorkCapacityShape`/
        // `MovementRoleExerciseSelector`'s intensity-exclusion gate);
        // checked here too as the same typed, defensive backstop.
        // SHORT_HIGH_OUTPUT is this codebase's real short-domain,
        // high-intensity shape.
        if stimulus.targetDurationDomain == .short, stimulus.intensity == .high {
            let hasLowIntensityMovement = movements.contains { $0.exercise?.intendedIntensity == .low }
            if hasLowIntensityMovement {
                return .invalid(reasonCode: .shortHighOutputLowIntensityMovement, offendingDimension: .shortHighOutputIntensity)
            }
        }

        // Rule D: repeated technical movement + insufficient capability/
        // dose evidence. Reuses `TechnicalCapacityDoseAuthority`'s own
        // real, already-locked `repeatedDoseTrackedNames` set — the
        // SAME 7 movements that set already gates for. "Insufficient
        // evidence" means exactly what `clampedReps`'s own doc comment
        // already establishes: no real, usable capacity evidence exists
        // for this exercise (unknown/wrong-capacity-type/no recorded
        // value) — this rule does not invent a rep-count magnitude
        // threshold; ANY authored rep target for one of these 7 names,
        // with zero real evidence behind it, is exactly "insufficient
        // evidence," per the rule's own plain language.
        for movement in movements {
            guard let exercise = movement.exercise, let reps = movement.reps, reps > 0,
                  TechnicalCapacityDoseAuthority.repeatedDoseTrackedNames.contains(exercise.canonicalName)
            else { continue }
            let hasRealEvidence: Bool = {
                guard let capability = performanceProfile?.movementCapability(for: exercise),
                      let capacityType = capability.capacityType,
                      capacityType == .maxUnbrokenReps || capacityType == .maxReps,
                      capability.capacityValue != nil
                else { return false }
                return true
            }()
            if !hasRealEvidence {
                return .invalid(reasonCode: .repeatedTechnicalMovementInsufficientEvidence, offendingDimension: .repeatedTechnicalMovementEvidence)
            }
        }

        // Rule F: AMRAP whose repeatable unit is semantically
        // incompatible with the assigned stimulus. A movement whose own
        // authored relative-load guidance is `.heavy`
        // (`FunctionalFitnessLoadGuidance`'s own real, locked tier — e.g.
        // Deadlift) represents a near-max-effort lift, not a
        // fast-repeatable AMRAP unit; pairing the two is incoherent
        // regardless of anything else about the session. Reuses the
        // exact existing `.heavy` tier this codebase's target rule
        // already authors — never a new invented tag.
        if case .amrap = format {
            let hasHeavyUnit = movements.contains { $0.loadGuidanceTier == .heavy }
            if hasHeavyUnit {
                return .invalid(reasonCode: .amrapUnitIncompatibleWithStimulus, offendingDimension: .amrapRepeatableUnitCompatibility)
            }
        }

        return .valid(magnitude: magnitude)
    }
}
