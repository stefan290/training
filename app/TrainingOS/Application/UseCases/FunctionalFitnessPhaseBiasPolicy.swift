import Foundation

/// Dogfood Round 1 (Finding 3A): a real, explicit **TrainingOS PRODUCT
/// DECISION** — never attributed to RP, CrossFit, or any source workbook
/// — for how the CURRENT phase's own adaptation priority biases
/// Functional Fitness programming. Before this checkpoint,
/// `FunctionalFitnessAuthoredProgramLibrary`'s weekly plan was applied
/// identically regardless of which phase/mix requested it — a real,
/// traced gap: a Muscle Gain phase and a pure Recovery phase produced
/// byte-identical FF programming.
///
/// **FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1** generalizes this from
/// Muscle-only to all 3 project-lead-authorized goals (Muscle/Strength/
/// Conditioning — `FunctionalFitnessProgrammingGoal`), and from a single
/// session family to the full 8-member `FunctionalFitnessSessionFamily`
/// vocabulary, per the project-lead specification's own exact per-
/// frequency session sequences (Part V). The Muscle Gain case's exact
/// prior behavior for sessionCount 1-3 is preserved byte-for-byte — only
/// the 4/5-session sequences and the Strength/Conditioning cases are new.
///
/// **Only adjusts fields the real production pipeline already respects
/// end-to-end** — confirmed by direct trace of
/// `FunctionalFitnessMaterializer.materializeWeek`:
/// - `includeStrengthBlock` is read directly by `FunctionalFitnessProgramGenerator`
///   and produces a REAL second `WorkoutBlockTemplate` (`addStrengthBlock`).
/// - `stimulus.loading`/`.intensity`/`.systemicDemand` survive into
///   `FunctionalFitnessMaterializer`'s `finalStimulus` unchanged (only
///   `movementFunctions` gets overwritten there, by the composer's own
///   real-time composition).
/// - Deliberately does **not** touch `stimulus.movementFunctions`: the
///   composer ignores the authored value and recomputes it from real
///   environment eligibility/exposure rotation every time.
enum FunctionalFitnessPhaseBiasPolicy {
    /// `allocation` defaults to `.low` — the exact prior-checkpoint
    /// behavior — so every existing call site/test that doesn't pass it
    /// is completely unaffected. Only `LongTermPlanner
    /// .functionalFitnessParameterCandidates` (the one real production
    /// call site) passes the athlete's actual, real `TrainingMix`-derived
    /// magnitude.
    static func apply(
        _ weeklyPlan: [FunctionalFitnessSessionIntent], phaseType: PhaseType?,
        allocation: FunctionalFitnessAllocationMagnitude = .low,
        weekLevelPatternGuaranteeNeeded: Bool = false,
        genericStrengthAssignments: [Int: MovementFunction] = [:],
        runningContributionByRelativeWeek: [Int: RunningWeeklyContribution] = [:]
    ) -> [FunctionalFitnessSessionIntent] {
        guard let goal = FunctionalFitnessProgrammingGoal.from(phaseType: phaseType) else {
            return applyNonGoalPhase(weeklyPlan, phaseType: phaseType)
        }

        let sessionCount = (weeklyPlan.map(\.sessionIndexInWeek).max() ?? 0) + 1
        // CONDITIONING V2 — LIVE RUNNING CONTRIBUTION, Section 1/3: each
        // intent consults ONLY its own `relativeWeek`'s real source
        // contribution — never one whole-program aggregate applied
        // uniformly. A Running stimulus in week X can therefore never
        // suppress/retarget an FF responsibility in week Y (Section 1's
        // own explicit prohibition).
        let families: [FunctionalFitnessSessionFamily] = weeklyPlan.map { intent in
            FunctionalFitnessRequirementAllocator.sessionFamily(
                goal: goal, magnitude: allocation, sessionCount: sessionCount, sessionIndexInWeek: intent.sessionIndexInWeek,
                runningContribution: runningContributionByRelativeWeek[intent.relativeWeek]
            )
        }
        let patternOverrides: [MovementFunction?] = requiredLoadedPatternOverrides(
            weeklyPlan: weeklyPlan, families: families, goal: goal, weekLevelPatternGuaranteeNeeded: weekLevelPatternGuaranteeNeeded
        )

        return zip(zip(weeklyPlan, families), patternOverrides).map { pair, patternOverride in
            let (intent, family) = pair
            var biased = intent
            biased.sessionFamily = family
            biased.requiredLoadedPattern = patternOverride

            switch goal {
            case .muscle:
                biased.archetype = .functionalBodybuilding
                biased.includeStrengthBlock = true
                applyMuscleFamily(family, to: &biased, relativeWeek: intent.relativeWeek)
            case .strength:
                biased.archetype = .strengthPower
                // Every real Strength-goal session carries a real strength
                // main body — even its lightest fallback family
                // (`.mixedResistanceWorkCapacity`/`.lowerFatigueComplementary`
                // in the 5-session sequence) still authors real content
                // via `FunctionalFitnessProgramGenerator.addStrengthBlock`'s
                // `.strengthPower` branch (never an empty block).
                biased.includeStrengthBlock = true
                biased.genericStrengthAssignment = genericStrengthAssignments[intent.sessionIndexInWeek]
                applyStrengthFamily(family, to: &biased, relativeWeek: intent.relativeWeek)
            case .conditioning:
                // Part III.C: conditioning is FF's own primary purpose
                // here — no strength block at all (mirrors the existing
                // `.recovery`/`.maintenance` "conditioning-only" shape).
                // `.unbiased` archetype is deliberately correct, never a
                // gap: the composer's own default alternation (loaded/
                // gymnastics + monostructural fill, no forced lead, no
                // loaded-first bias) is exactly the "legitimate mixed-modal
                // programming... weightlifting, gymnastics, carries and
                // monostructural work" Part III.C asks for — nothing new
                // needed.
                biased.archetype = .unbiased
                biased.includeStrengthBlock = false
                applyConditioningFamily(family, to: &biased, relativeWeek: intent.relativeWeek)
            }
            return biased
        }
    }

    /// PROGRAMMING AUTHORITY V1 — FINAL CLOSE-OUT, Part XV (project-lead
    /// authoritative rule, verbatim): "If the athlete's complete selected
    /// training week contains TWO OR MORE resistance-capable sessions, the
    /// WEEK must contain legitimate exposure to BOTH [squat] and [hinge]...
    /// If the complete training week contains only ONE resistance-capable
    /// session: do NOT force both squat and hinge into that single
    /// session... mesocycle-level rotation is acceptable."
    ///
    /// `weekLevelPatternGuaranteeNeeded` is `false` for every pre-existing
    /// call site/test (this function then returns all-`nil`, meaning the
    /// existing `relativeWeek`-keyed rotation in
    /// `FunctionalFitnessProgramGenerator.addStrengthBlock` applies
    /// completely unchanged). The one real production call site
    /// (`LongTermPlanner.functionalFitnessParameterCandidates`) passes
    /// `true` only when `FunctionalFitnessRequirementAllocator
    /// .sourceAlreadyProvidesBothLoadedPatterns(mix:)` is `false` — i.e.
    /// only when NO real dedicated resistance source exists in the mix,
    /// so Functional Fitness alone carries this responsibility. When a
    /// real source already covers both patterns, this function is never
    /// asked to force anything (Part XV's own "avoid unnecessary
    /// duplicate exposure").
    ///
    /// Grouped by `relativeWeek` (never globally) because `weeklyPlan`
    /// here is the WHOLE multi-week authored plan, not one week — pattern
    /// coverage is a PER-WEEK requirement, not a once-ever one. Within
    /// each week group, the first two `sessionIndexInWeek`-ascending
    /// sessions whose family can carry a loaded pattern at all
    /// (`FunctionalFitnessRequirementAllocator.loadedPatternCapableFamilies`)
    /// are assigned squat/hinge — which of the two gets which alternates
    /// by `relativeWeek` parity, so the athlete does not always squat on
    /// the same relative session every single week (real week-to-week
    /// variety, still a pure/deterministic function of `relativeWeek`,
    /// order-independent by construction). Any additional loaded-pattern-
    /// capable session that same week (session index 2+) is left `nil` —
    /// the existing `relativeWeek`-keyed rotation already covers it, and
    /// the requirement is already fully satisfied by the first two, so
    /// forcing a third would be exactly the unnecessary duplication the
    /// rule forbids.
    private static func requiredLoadedPatternOverrides(
        weeklyPlan: [FunctionalFitnessSessionIntent], families: [FunctionalFitnessSessionFamily],
        goal: FunctionalFitnessProgrammingGoal, weekLevelPatternGuaranteeNeeded: Bool
    ) -> [MovementFunction?] {
        var overrides = [MovementFunction?](repeating: nil, count: weeklyPlan.count)
        guard weekLevelPatternGuaranteeNeeded, goal == .muscle || goal == .strength else { return overrides }

        let indicesByWeek = Dictionary(grouping: weeklyPlan.indices, by: { weeklyPlan[$0].relativeWeek })
        for (relativeWeek, indices) in indicesByWeek {
            let capableIndicesThisWeek = indices
                .filter { FunctionalFitnessRequirementAllocator.loadedPatternCapableFamilies.contains(families[$0]) }
                .sorted { weeklyPlan[$0].sessionIndexInWeek < weeklyPlan[$1].sessionIndexInWeek }
            // Proof E: fewer than 2 resistance-capable sessions this week
            // — never force both patterns into one session.
            guard capableIndicesThisWeek.count >= 2 else { continue }
            let (first, second) = relativeWeek % 2 == 0
                ? (MovementFunction.squatLoaded, MovementFunction.hingeLoaded)
                : (MovementFunction.hingeLoaded, MovementFunction.squatLoaded)
            overrides[capableIndicesThisWeek[0]] = first
            overrides[capableIndicesThisWeek[1]] = second
        }
        return overrides
    }

    /// Part IV.1/IV.4/IV.8, exact prior-checkpoint behavior preserved for
    /// `.resistanceDominant`/`.mixedResistanceWorkCapacity`/
    /// `.lowerFatigueComplementary` — the only 3 families Muscle ever
    /// resolves to (`FunctionalFitnessRequirementAllocator.sessionFamily`'s
    /// own `.muscle` branch never returns the other 5).
    private static func applyMuscleFamily(_ family: FunctionalFitnessSessionFamily, to biased: inout FunctionalFitnessSessionIntent, relativeWeek: Int) {
        switch family {
        case .resistanceDominant:
            // §13.A/§17: conditioning is NOT mandatory — the real main
            // body already carries this session's whole resistance
            // stimulus.
            biased.includeConditioningBlock = false
        case .mixedResistanceWorkCapacity:
            // PROGRAMMING MODEL CORRECTION: SHORT_HIGH_OUTPUT/`.roundsAndReps`
            // is the correct, already-validated pairing for the real,
            // small, repeatable 2-role conditioning composition
            // `FunctionalFitnessMaterializer.conditioningRoleCount`
            // produces for this family — never format-first.
            applyWorkCapacityShape(to: &biased, relativeWeek: relativeWeek)
        case .lowerFatigueComplementary:
            // FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1 real fix
            // (discovered via a real, reproduced Stage-E validation
            // failure at 5 FF sessions/week — see this checkpoint's own
            // report): this family is NOT a smaller copy of
            // `.mixedResistanceWorkCapacity`'s short-AMRAP shape — its
            // whole purpose (`FunctionalFitnessMaterializer
            // .conditioningRoleCount`'s own doc comment: "low-cost,
            // minimal conditioning contribution") is a genuinely EASY,
            // low-systemic-demand session, never a high-intensity work-
            // capacity piece. Giving it a real long, low-intensity
            // `.forTime` shape — rather than reusing the short AMRAP —
            // is both more semantically honest AND structurally
            // necessary: `FunctionalFitnessDecisionEngine
            // .adjustForSameWeekComplementarity`'s real, pre-existing
            // same-week nudge legitimately pushes an under-served
            // component toward `.aerobicCapacity` (`targetDurationDomain
            // = .long`) whenever this family's own baseline doesn't
            // already serve ANY of the component's real adaptation
            // objectives — which a short/low-demand baseline never does.
            // A `.long`-domain baseline serves `.aerobicCapacity`
            // directly, so the nudge's own "baseline already covers
            // something under-covered" bailout always applies here,
            // never silently drifting the format/domain pairing out of
            // sync with the FIXED format this checkpoint authors at
            // generation time.
            applyLowFatigueShape(to: &biased)
        default:
            break // never reached — defensive only.
        }
    }

    /// The real, small, repeatable 2-role work-capacity shape shared by
    /// every goal's `.mixedResistanceWorkCapacity` family — written once
    /// so Muscle/Strength/Conditioning can never silently diverge on it.
    /// `systemicDemand` is forced `.high` explicitly (never left to
    /// whatever the base authored plan's own slot happened to set) —
    /// this family's entire name/purpose IS work capacity, and forcing it
    /// here is what makes `FunctionalFitnessDecisionEngine
    /// .adjustForSameWeekComplementarity`'s real same-week nudge always
    /// find this session's own baseline already serving the FF
    /// component's `.workCapacity` objective, so it can never drift this
    /// FIXED-format session's domain out of sync with its own locked
    /// `.amrap(240)` format — the same real, reproduced failure class
    /// `.lowerFatigueComplementary`'s own dedicated shape below exists to
    /// prevent.
    static func applyWorkCapacityShape(to biased: inout FunctionalFitnessSessionIntent, relativeWeek: Int) {
        // CONDITIONING DOSE AUTHORITY V1, Section 2: the historical
        // unconditional `240` is gone — this is now the real
        // SHORT_HIGH_OUTPUT dose resolver's own 4/6/8-minute cycle.
        // `targetDurationDomain` is derived FROM the resolved concrete
        // duration (never hardcoded `.short`) so Stage-E validation
        // always agrees with whichever point in the cycle was selected —
        // 6/8-minute exposures honestly land in this codebase's real
        // `.medium` bucket (`FunctionalFitnessStimulusValidator
        // .durationDomain(forEstimatedSeconds:)`'s own <300s/300-900s/
        // >900s thresholds), which is not an error, just an honest
        // classification the fixed-`.short` hardcode used to hide.
        let capSeconds = ConditioningDoseAuthority.shortHighOutputCapSeconds(relativeWeek: relativeWeek)
        biased.format = .amrap(capSeconds: capSeconds)
        biased.stimulus.targetDurationDomain = FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: capSeconds)
        biased.stimulus.systemicDemand = .high
        // MUSCLE VERTICAL SLICE CONTINUATION, Sections 12-15
        // (Zone2-blocked-from-SHORT_HIGH_OUTPUT): this family's own
        // real dogfood defect — "Easy Run (Zone 2) · 200m" resolving
        // inside a 4-minute AMRAP — traced to this shared shape never
        // setting `stimulus.intensity` at all, so `MovementRoleExerciseSelector`'s
        // existing `requiredIntensity: finalStimulus.intensity` gate
        // (`FunctionalFitnessMaterializer`'s own real call site) never
        // received anything to exclude `Exercise.intendedIntensity ==
        // .low` candidates with. Conditioning's own `.shortMixedModal`
        // family already sets this explicitly (`applyConditioningFamily`
        // below); this shared shape — used by Muscle's
        // `mixedResistanceWorkCapacity` and Strength's fallback slot —
        // did not, which is exactly why the dogfood defect reproduced
        // on a Muscle-Gain athlete's AMRAP finisher, not a Conditioning
        // one.
        biased.stimulus.intensity = .high
        biased.stimulus.scoreType = .roundsAndReps
        biased.varianceConstraints.avoidRepeatingDurationDomainWithinSessions = nil
    }

    /// The real, genuinely-easy `.lowerFatigueComplementary` shape shared
    /// by every goal that reaches it — a real, sustained, low-intensity
    /// completion-target effort (never a high-intensity AMRAP), and
    /// `intensity`/`systemicDemand` are forced explicitly rather than left
    /// to whatever the base authored plan happened to set, so this
    /// family's own real "low fatigue" contract can never be silently
    /// violated by a future authored-library edit.
    private static func applyLowFatigueShape(to biased: inout FunctionalFitnessSessionIntent) {
        biased.includeConditioningBlock = true
        // MUSCLE + 5FF FINAL CLOSURE, Section 8/9 (project-owner
        // decision): this family's own `.long` domain can now compose a
        // real SUSTAINED_AEROBIC monostructural role
        // (`FunctionalFitnessMovementTargetRule.sustainedAerobicDurationSeconds`,
        // 30 min) — a 1200s (20 min) cap would then be SHORTER than the
        // real prescribed work itself, exactly the "trivial effort with a
        // grossly mismatched cap" incoherence Section 8 forbids, just in
        // the opposite direction (a cap too SHORT rather than too long).
        // Raised to match; a longer cap never makes a low-intensity,
        // low-systemic-demand completion-target effort incoherent for
        // this family's other (non-monostructural) compositions either.
        biased.format = .forTime(capSeconds: FunctionalFitnessMovementTargetRule.sustainedAerobicDurationSeconds)
        biased.stimulus.targetDurationDomain = .long
        biased.stimulus.intensity = .low
        biased.stimulus.systemicDemand = .low
        biased.stimulus.scoreType = .time
        biased.varianceConstraints.avoidRepeatingDurationDomainWithinSessions = nil
    }

    /// Part IV.2/IV.3/IV.8, Part III.B: Strength's own family shapes.
    /// `.heavyStrength`/`.powerAthletic` never carry mandatory
    /// conditioning ("heavy strength and competitive conditioning are
    /// separate programming decisions" — Part III.B); when they DO reach
    /// a conditioning-capable family (`.mixedResistanceWorkCapacity`/
    /// `.lowerFatigueComplementary`, real fallback slots in the 5-session
    /// Strength sequence), it uses the same real, already-validated
    /// short-AMRAP shape Muscle already proved.
    private static func applyStrengthFamily(_ family: FunctionalFitnessSessionFamily, to biased: inout FunctionalFitnessSessionIntent, relativeWeek: Int) {
        switch family {
        case .heavyStrength, .powerAthletic:
            biased.includeConditioningBlock = false
        case .mixedResistanceWorkCapacity:
            biased.includeConditioningBlock = true
            applyWorkCapacityShape(to: &biased, relativeWeek: relativeWeek)
        case .lowerFatigueComplementary:
            applyLowFatigueShape(to: &biased)
        default:
            break // never reached in the Strength allocator branch — defensive only.
        }
    }

    /// Part III.C/Part IX: Conditioning's own real time-domain-driven
    /// format authoring. Format/domain/scoreType are chosen TOGETHER
    /// (never independently — the same discipline established for Muscle
    /// Gain's own conditioning finisher), each a real, already-defined
    /// `FunctionalFitnessStimulusValidator.defaultScoreType(for:)`
    /// pairing — never invented.
    private static func applyConditioningFamily(_ family: FunctionalFitnessSessionFamily, to biased: inout FunctionalFitnessSessionIntent, relativeWeek: Int) {
        biased.includeConditioningBlock = true
        switch family {
        case .shortMixedModal:
            // CONDITIONING DOSE AUTHORITY V1: SHORT_HIGH_OUTPUT, same
            // real dose resolver as Muscle/Strength's `applyWorkCapacityShape`
            // — the historical unconditional `240` is gone. Part IV.5's
            // own language ("high-output short conditioning") justifies
            // forcing `intensity`/`systemicDemand` explicitly.
            let capSeconds = ConditioningDoseAuthority.shortHighOutputCapSeconds(relativeWeek: relativeWeek)
            biased.format = .amrap(capSeconds: capSeconds)
            biased.stimulus.targetDurationDomain = FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: capSeconds)
            biased.stimulus.intensity = .high
            biased.stimulus.systemicDemand = .high
            biased.stimulus.scoreType = .roundsAndReps
            biased.varianceConstraints.avoidRepeatingDurationDomainWithinSessions = nil
        case .lowerFatigueComplementary:
            applyLowFatigueShape(to: &biased)
        case .mediumMixedModal:
            // CONDITIONING DOSE AUTHORITY V1: MEDIUM_MIXED_MODAL — the
            // historical unconditional `900` is gone, replaced by the
            // real 10/12/15-minute dose resolver.
            let capSeconds = ConditioningDoseAuthority.mediumMixedModalCapSeconds(relativeWeek: relativeWeek)
            biased.format = .roundsForTime(rounds: 4, capSeconds: capSeconds)
            biased.stimulus.targetDurationDomain = FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: capSeconds)
            biased.stimulus.systemicDemand = .high
            biased.stimulus.scoreType = .time
            biased.varianceConstraints.avoidRepeatingDurationDomainWithinSessions = nil
        case .mixedResistanceWorkCapacity:
            // CONDITIONING DOSE AUTHORITY V1, Section 6/8/9: this real,
            // pre-existing family slot (the 5-session Conditioning
            // sequence's own "additional distinct interval/work-capacity
            // stimulus" — `FunctionalFitnessRequirementAllocator
            // .sessionFamily`'s own doc comment) previously shared
            // `.mediumMixedModal`'s exact roundsForTime shape — making 2
            // of 5 weekly sessions the same effective workout, exactly
            // the "not meaningfully distinct" defect Section 9 forbids.
            // REPEATED_HIGH_OUTPUT_INTERVALS (fixed 6x30s/90s, real
            // locked V1 prescription) is the genuinely distinct
            // interval/work-capacity responsibility this slot's own name
            // already promises — never EMOM, never AMRAP (Section 6).
            // The `sessionFamily` assignment itself is completely
            // unchanged; only this family's own CONDITIONING-goal dose
            // is newly differentiated from `.mediumMixedModal`'s.
            biased.format = .intervals(
                count: ConditioningDoseAuthority.repeatedHighOutputIntervalsCount,
                workSeconds: ConditioningDoseAuthority.repeatedHighOutputIntervalsWorkSeconds,
                restSeconds: ConditioningDoseAuthority.repeatedHighOutputIntervalsRestSeconds
            )
            let estimatedSeconds = ConditioningDoseAuthority.repeatedHighOutputIntervalsCount
                * (ConditioningDoseAuthority.repeatedHighOutputIntervalsWorkSeconds + ConditioningDoseAuthority.repeatedHighOutputIntervalsRestSeconds)
            biased.stimulus.targetDurationDomain = FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: estimatedSeconds)
            biased.stimulus.intensity = .high
            biased.stimulus.systemicDemand = .high
            biased.stimulus.scoreType = .completedIntervals
            biased.varianceConstraints.avoidRepeatingDurationDomainWithinSessions = nil
        case .aerobicEngine:
            // PROGRAMMING AUTHORITY V1 Part XXII/XXIII (real defect found
            // and fixed by an earlier checkpoint, preserved here):
            // `.moderate` systemicDemand, not `.high` — "aerobic base /
            // sustainable engine" is textually distinct from "short
            // high-output work" (Part VII/XXIII).
            //
            // CONDITIONING DOSE AUTHORITY V1, Section 4/5/8: this
            // family's own doc comment already names BOTH forms —
            // "sustainable aerobic work, generally 20+ minutes OR
            // structured intervals clearly targeting aerobic
            // sustainability" — SUSTAINED_AEROBIC (continuous) and
            // AEROBIC_INTERVALS are therefore both genuinely this
            // family's own responsibility, not a duplicate/parallel
            // concept. Alternated deterministically by `relativeWeek`
            // parity (even ⇒ continuous, odd ⇒ intervals) — real weekly
            // variance (Section 7), never random, and never requiring a
            // new hidden counter.
            biased.stimulus.systemicDemand = .moderate
            if relativeWeek % 2 == 0 {
                let capSeconds = ConditioningDoseAuthority.sustainedAerobicCapSeconds(relativeWeek: relativeWeek)
                biased.format = .forTime(capSeconds: capSeconds)
                biased.stimulus.targetDurationDomain = FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: capSeconds)
                biased.stimulus.scoreType = .time
            } else {
                let count = ConditioningDoseAuthority.aerobicIntervalsCount(relativeWeek: relativeWeek)
                biased.format = .intervals(
                    count: count,
                    workSeconds: ConditioningDoseAuthority.aerobicIntervalsWorkSeconds,
                    restSeconds: ConditioningDoseAuthority.aerobicIntervalsRestSeconds
                )
                let estimatedSeconds = count * (ConditioningDoseAuthority.aerobicIntervalsWorkSeconds + ConditioningDoseAuthority.aerobicIntervalsRestSeconds)
                biased.stimulus.targetDurationDomain = FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds: estimatedSeconds)
                biased.stimulus.scoreType = .completedIntervals
            }
            biased.varianceConstraints.avoidRepeatingDurationDomainWithinSessions = nil
        default:
            break // resistanceDominant/heavyStrength/powerAthletic never reached in the Conditioning allocator branch.
        }
    }

    /// Phases outside this checkpoint's 3-goal authority — exactly the
    /// prior checkpoint's own `.strength`/`.recovery`/`.maintenance`/
    /// unbiased-fallback behavior, preserved byte-for-byte (`.strength`
    /// is now handled above, inside the goal-aware branch, so it's
    /// removed from here).
    private static func applyNonGoalPhase(_ weeklyPlan: [FunctionalFitnessSessionIntent], phaseType: PhaseType?) -> [FunctionalFitnessSessionIntent] {
        switch phaseType {
        case .recovery, .maintenance:
            return weeklyPlan.map { intent in
                var biased = intent
                biased.includeStrengthBlock = false
                biased.archetype = .recoveryConditioning
                biased.stimulus.loading = .bodyweightOnly
                biased.stimulus.intensity = .low
                biased.stimulus.systemicDemand = .low
                return biased
            }
        case .functionalFitness, .transition, nil, .muscleGain, .fatLoss, .strength, .enduranceEvent:
            // `.muscleGain`/`.strength`/`.fatLoss`/`.enduranceEvent` are
            // all handled by the goal-aware branch above and never reach
            // here — listed only so this switch stays exhaustive.
            return weeklyPlan
        }
    }
}
