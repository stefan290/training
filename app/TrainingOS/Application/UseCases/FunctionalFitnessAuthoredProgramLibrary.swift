import Foundation

/// FF Multi-Week V1: the TrainingOS-authored 4-week `weeklyPlan` content
/// for each of the 3 supported frequencies (1/2/3 sessions per week).
///
/// **This is authored programming, not recovered source** — unlike
/// Hypertrophy/Powerlifting/Running, there is no workbook to reproduce.
/// Every dimension used below (`DurationDomain`/`IntensityClassification`/
/// `LoadingClassification`/`MovementFunction`/`ModalityCount`/`WorkoutFormat`/
/// `ScoreType`/`includeStrengthBlock`) is EXISTING FF vocabulary — nothing
/// new is introduced, and only the 6 non-deferred `MovementFunction` cases
/// (`squatLoaded`/`hingeLoaded`/`pressLoaded`/`gymnasticsPull`/
/// `gymnasticsPush`/`monostructural`) are used, since the other 9 remain
/// explicitly deferred (`FunctionalFitnessMovementComposer` never produces
/// them).
///
/// **Every entry's `scoreType` matches `FunctionalFitnessStimulusValidator
/// .defaultScoreType(for:)` for its own `format` exactly, and every
/// format's estimated duration (where it has an explicit cap) falls
/// within its own declared `targetDurationDomain`'s range** — verified by
/// direct calculation against that validator's own real logic, not
/// assumed; getting either wrong fails real Stage-E materialization,
/// which the dogfood/materialization tests exercise for real.
///
/// **V1 principle (see `FUNCTIONAL_FITNESS_MULTI_WEEK_V1.md` §2/§6):**
/// this authors deliberate VARIATION, BALANCE, and COHERENCE across a real
/// 4-week program — never a claim of progressive overload. No two
/// same-week sessions share the same role/emphasis; no two same-slot
/// sessions across adjacent weeks repeat the identical duration domain,
/// loading, or format. Every entry sets real, non-nil `VarianceConstraints`
/// windows so `FunctionalFitnessDecisionEngine`'s existing variance checks
/// are genuinely active, not dormant.
///
/// **Every entry's `movementModalityMix` deliberately lists all 3
/// modalities (weightlifting/gymnastics/metabolicConditioning), regardless
/// of session emphasis — confirmed by direct read of
/// `FunctionalFitnessMovementComposer.composeSession` that dynamic
/// composition (`isDynamicallyComposed: true`, used throughout) draws
/// its actual roles from real-time exercise ELIGIBILITY/exposure
/// rotation, never from this authored field's specific counts; Stage E's
/// own `FunctionalFitnessStimulusValidator` only requires the ACTUALLY
/// resolved modalities to be non-disjoint with the target mix, never an
/// exact match.** Authoring a narrower mix here (e.g. weightlifting-only
/// for a "structured" session) would not change what the composer
/// produces and would only make real Stage-E validation spuriously fail
/// once the composer's real output included gymnastics/conditioning too
/// — confirmed the hard way this pass. Session-to-session/week-to-week
/// EMPHASIS is instead expressed through `loading`/`intensity`/
/// `targetDurationDomain`/`format`/`skillDemand`/`systemicDemand`/
/// `includeStrengthBlock` — every one of which the composer/validator DO
/// respect — never through constraining which modalities the dynamic
/// composer is allowed to touch.
///
/// Movement/exercise selection is deliberately NEVER authored here — every
/// intent below states WHAT the session needs (stimulus/format/strength-
/// block/variance), never WHICH exercises fill it; `FunctionalFitnessMovementComposer`/
/// `FunctionalFitnessMaterializer` resolve HOW at real materialization
/// time, exactly as before this file existed.
enum FunctionalFitnessAuthoredProgramLibrary {
    /// Real, non-nil, shared across every authored intent below — the
    /// direct fix for the pre-V1 dormant `VarianceConstraints()`.
    private static let standardVariance = VarianceConstraints(
        avoidRepeatingModalityMixWithinSessions: 2,
        avoidRepeatingMovementFunctionWithinSessions: 2,
        avoidRepeatingDurationDomainWithinSessions: 2,
        avoidRepeatingLoadingWithinSessions: 2
    )

    // MARK: - 1 session/week: one deliberate general-purpose session per
    // week, genuinely varied week to week (duration domain, loading,
    // intensity, format, and strength-block inclusion all change).

    static let oneSessionPerWeek: [FunctionalFitnessSessionIntent] = [
        // Week 1: roundsForTime, no explicit cap (duration domain
        // unvalidated/auto-pass) — scoreType .time (format default).
        FunctionalFitnessSessionIntent(
            relativeWeek: 0, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
                movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
            ),
            format: .roundsForTime(rounds: 5, capSeconds: 600), // medium (300-900s), avoids a stored-nil optional associated value
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 2: amrap, 240s cap (short, <300s) — scoreType .roundsAndReps.
        FunctionalFitnessSessionIntent(
            relativeWeek: 1, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .high, loading: .light,
                movementFunctions: [.gymnasticsPush, .monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps
            ),
            format: .amrap(capSeconds: 240),
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        // Week 3: forTime, 1800s cap (long, >900s) — scoreType .time.
        FunctionalFitnessSessionIntent(
            relativeWeek: 2, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .long, intensity: .low, loading: .bodyweightOnly,
                movementFunctions: [.monostructural, .gymnasticsPull],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .moderate, scoreType: .time
            ),
            format: .forTime(capSeconds: 1800),
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 4: intervals, 4x(120+60)=720s (medium, 300-900s) —
        // scoreType .completedIntervals.
        FunctionalFitnessSessionIntent(
            relativeWeek: 3, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
                movementFunctions: [.hingeLoaded, .monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .moderate, systemicDemand: .moderate, scoreType: .completedIntervals
            ),
            format: .intervals(count: 4, workSeconds: 120, restSeconds: 60),
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
    ]

    // MARK: - 2 sessions/week: Session A = structured (strength+
    // conditioning, weightlifting-emphasis), Session B = performance/
    // mixed-modal (no strength block, higher intensity/systemic demand) —
    // deliberately complementary every week, both varied week to week.

    static let twoSessionsPerWeek: [FunctionalFitnessSessionIntent] = [
        // Week 1
        FunctionalFitnessSessionIntent(
            relativeWeek: 0, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
                movementFunctions: [.squatLoaded, .pressLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .load
            ),
            format: .maxLoad, // no explicit duration cap — auto-passes duration validation
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 0, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .high, loading: .light,
                movementFunctions: [.gymnasticsPull, .monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .roundsAndReps
            ),
            format: .amrap(capSeconds: 240), // short
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 2
        FunctionalFitnessSessionIntent(
            relativeWeek: 1, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .heavy,
                movementFunctions: [.hingeLoaded, .pressLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .time
            ),
            format: .forTime(capSeconds: 600), // medium (300-900s), avoids a stored-nil optional associated value
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 1, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .long, intensity: .moderate, loading: .bodyweightOnly,
                movementFunctions: [.monostructural, .gymnasticsPush],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .moderate, systemicDemand: .high, scoreType: .time
            ),
            format: .chipper(capSeconds: 1500), // long
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 3
        FunctionalFitnessSessionIntent(
            relativeWeek: 2, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .moderate, loading: .moderate,
                movementFunctions: [.squatLoaded, .hingeLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .repetitions
            ),
            format: .maxReps(capSeconds: 240), // short
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 2, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .high, loading: .light,
                movementFunctions: [.gymnasticsPull, .gymnasticsPush, .monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .high, systemicDemand: .high, scoreType: .time
            ),
            format: .roundsForTime(rounds: 4, capSeconds: 600), // medium (300-900s), avoids a stored-nil optional associated value
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 4
        FunctionalFitnessSessionIntent(
            relativeWeek: 3, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
                movementFunctions: [.pressLoaded, .hingeLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .time
            ),
            format: .ladder(direction: .ascending, capSeconds: 600), // medium (300-900s), avoids a stored-nil optional associated value
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 3, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .long, intensity: .low, loading: .bodyweightOnly,
                movementFunctions: [.monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .moderate, scoreType: .time
            ),
            format: .forTime(capSeconds: 2400), // long
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
    ]

    // MARK: - 3 sessions/week: Session A = structured (strength+
    // conditioning), Session B = skill+conditioning (gymnastics emphasis,
    // higher skill demand), Session C = mixed-modal/performance
    // (monostructural-heavy conditioning) — 3 distinct roles every week.

    static let threeSessionsPerWeek: [FunctionalFitnessSessionIntent] = [
        // Week 1
        FunctionalFitnessSessionIntent(
            relativeWeek: 0, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .heavy,
                movementFunctions: [.squatLoaded, .pressLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .load
            ),
            format: .maxLoad, // no cap
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 0, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .moderate, loading: .bodyweightOnly,
                movementFunctions: [.gymnasticsPull, .gymnasticsPush],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .high, systemicDemand: .moderate, scoreType: .completedIntervals
            ),
            format: .emom(intervalSeconds: 60, totalSeconds: 240), // short
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .skill
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 0, sessionIndexInWeek: 2,
            stimulus: Stimulus(
                targetDurationDomain: .long, intensity: .high, loading: .light,
                movementFunctions: [.monostructural, .hingeLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .high, scoreType: .time
            ),
            format: .chipper(capSeconds: 1800), // long
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 2
        FunctionalFitnessSessionIntent(
            relativeWeek: 1, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .moderate, loading: .heavy,
                movementFunctions: [.hingeLoaded, .squatLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .repetitions
            ),
            format: .maxReps(capSeconds: 240), // short
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 1, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .light,
                movementFunctions: [.gymnasticsPush, .monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .high, systemicDemand: .moderate, scoreType: .time
            ),
            format: .roundsForTime(rounds: 4, capSeconds: 600), // medium (300-900s), avoids a stored-nil optional associated value
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .skill
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 1, sessionIndexInWeek: 2,
            stimulus: Stimulus(
                targetDurationDomain: .long, intensity: .low, loading: .bodyweightOnly,
                movementFunctions: [.monostructural],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .moderate, scoreType: .time
            ),
            format: .forTime(capSeconds: 2100), // long
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 3
        FunctionalFitnessSessionIntent(
            relativeWeek: 2, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .moderate,
                movementFunctions: [.pressLoaded, .squatLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .time
            ),
            format: .ladder(direction: .descending, capSeconds: 600), // medium (300-900s), avoids a stored-nil optional associated value
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 2, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .short, intensity: .high, loading: .bodyweightOnly,
                movementFunctions: [.gymnasticsPull, .gymnasticsPush],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .high, systemicDemand: .moderate, scoreType: .completedIntervals
            ),
            format: .emom(intervalSeconds: 45, totalSeconds: 240), // short
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .skill
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 2, sessionIndexInWeek: 2,
            stimulus: Stimulus(
                targetDurationDomain: .long, intensity: .moderate, loading: .light,
                movementFunctions: [.monostructural, .hingeLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .high, scoreType: .completedIntervals
            ),
            format: .intervals(count: 6, workSeconds: 240, restSeconds: 90), // 6*330=1980s, long
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
        // Week 4
        FunctionalFitnessSessionIntent(
            relativeWeek: 3, sessionIndexInWeek: 0,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .heavy,
                movementFunctions: [.squatLoaded, .hingeLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .low, scoreType: .load
            ),
            format: .maxLoad, // no cap
            includeStrengthBlock: true, varianceConstraints: standardVariance, sessionRole: .mixed
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 3, sessionIndexInWeek: 1,
            stimulus: Stimulus(
                targetDurationDomain: .medium, intensity: .moderate, loading: .bodyweightOnly,
                movementFunctions: [.gymnasticsPush, .gymnasticsPull],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .high, systemicDemand: .moderate, scoreType: .roundsAndReps
            ),
            format: .amrap(capSeconds: 720), // medium (300-900s)
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .skill
        ),
        FunctionalFitnessSessionIntent(
            relativeWeek: 3, sessionIndexInWeek: 2,
            stimulus: Stimulus(
                targetDurationDomain: .long, intensity: .high, loading: .light,
                movementFunctions: [.monostructural, .pressLoaded],
                movementModalityMix: [
                    ModalityCount(modality: .weightlifting, count: 1),
                    ModalityCount(modality: .gymnastics, count: 1),
                    ModalityCount(modality: .metabolicConditioning, count: 1),
                ],
                skillDemand: .low, systemicDemand: .high, scoreType: .time
            ),
            format: .forTime(capSeconds: 2700), // long
            includeStrengthBlock: false, varianceConstraints: standardVariance, sessionRole: .functionalFitness
        ),
    ]

    /// `nil` for any unsupported frequency — never approximated to the
    /// nearest supported one (mirrors `RunningBuiltInLibrary`'s own
    /// fail-closed discipline).
    static func weeklyPlan(forSessionsPerWeek count: Int) -> [FunctionalFitnessSessionIntent]? {
        switch count {
        case 1: return oneSessionPerWeek
        case 2: return twoSessionsPerWeek
        case 3: return threeSessionsPerWeek
        default: return nil
        }
    }
}
