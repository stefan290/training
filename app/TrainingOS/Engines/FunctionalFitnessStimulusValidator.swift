import Foundation

/// Pure, deterministic Stage-E validation (§38) — checks a resolved
/// `FunctionalFitnessPrescriptionTemplate`-shaped workout against the
/// target `Stimulus` it was generated for. Never invents a number it
/// can't honestly derive (§39).
enum FunctionalFitnessStimulusValidator {
    /// TRAININGOS_DESIGNED duration-domain thresholds — the same
    /// short(<5min)/medium(5-15min)/long(>15min) boundary
    /// `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §1.1's own Stage 3B
    /// sketch already used, carried into this pass's actual
    /// implementation rather than invented fresh. Never presented as
    /// sourced.
    static func estimatedDurationSeconds(for format: WorkoutFormat) -> Int? {
        switch format {
        case .amrap(let capSeconds): return capSeconds
        case .emom(_, let totalSeconds): return totalSeconds
        case .forTime(let capSeconds): return capSeconds
        case .roundsForTime(_, let capSeconds): return capSeconds
        case .chipper(let capSeconds): return capSeconds
        case .ladder(_, let capSeconds): return capSeconds
        case .maxLoad: return nil
        case .maxReps(let capSeconds): return capSeconds
        case .intervals(let count, let workSeconds, let restSeconds): return count * (workSeconds + restSeconds)
        }
    }

    static func durationDomain(forEstimatedSeconds seconds: Int) -> DurationDomain {
        switch seconds {
        case ..<300: return .short
        case 300...900: return .medium
        default: return .long
        }
    }

    /// The format's own natural default `ScoreType` — a plausibility
    /// default, not a hard rule (a ladder is usually scored For Time, but
    /// could legitimately be scored another way).
    static func defaultScoreType(for format: WorkoutFormat) -> ScoreType {
        switch format {
        case .amrap: return .roundsAndReps
        case .emom: return .completedIntervals
        case .forTime, .roundsForTime, .chipper, .ladder: return .time
        case .maxLoad: return .load
        case .maxReps: return .repetitions
        case .intervals: return .completedIntervals
        }
    }

    static func validate(
        format: WorkoutFormat,
        resolvedModalities: Set<FunctionalModality>,
        resolvedLoadingRoles: [LoadingClassification],
        against target: Stimulus
    ) -> StimulusValidation {
        var notes: [String] = []

        let estimatedSeconds = estimatedDurationSeconds(for: format)
        let matchesDuration: Bool
        if let estimatedSeconds {
            let estimatedDomain = durationDomain(forEstimatedSeconds: estimatedSeconds)
            matchesDuration = estimatedDomain == target.targetDurationDomain
            if !matchesDuration {
                notes.append("Estimated duration (\(estimatedSeconds)s, \(estimatedDomain)) does not match the target duration domain (\(target.targetDurationDomain)).")
            }
        } else {
            matchesDuration = true
            notes.append("Format has no explicit cap; duration domain could not be validated (§39: not pretending an exact time is knowable).")
        }

        let targetModalities = Set(target.movementModalityMix.map(\.modality))
        let matchesModality = targetModalities.isEmpty || !resolvedModalities.isDisjoint(with: targetModalities)
        if !matchesModality {
            notes.append("Resolved movements' modalities (\(resolvedModalities)) share nothing with the target mix (\(targetModalities)).")
        }

        // No movement slot's loadingRole may directly contradict the
        // target's own loading classification — an unset loadingRole
        // never contradicts anything.
        let matchesLoading = resolvedLoadingRoles.allSatisfy { $0 == target.loading }
        if !matchesLoading {
            notes.append("At least one movement slot's loadingRole contradicts the target stimulus's loading classification (\(target.loading)).")
        }

        // No per-Exercise skill classification exists yet (§36: "document
        // as deferred rather than inventing user skill scores") — always
        // passes, with an explicit note rather than a silent skip.
        let matchesSkill = true
        notes.append("Skill-demand validation deferred: no per-Exercise skill classification exists yet (§36).")

        let matchesScoreType = defaultScoreType(for: format) == target.scoreType
        if !matchesScoreType {
            notes.append("Format's natural score type (\(defaultScoreType(for: format))) does not match the target stimulus's scoreType (\(target.scoreType)).")
        }

        let passes = matchesDuration && matchesModality && matchesLoading && matchesScoreType

        return StimulusValidation(
            estimatedDurationSeconds: estimatedSeconds,
            matchesDurationDomain: matchesDuration,
            matchesModalityMix: matchesModality,
            matchesLoadingClassification: matchesLoading,
            matchesSkillDemand: matchesSkill,
            matchesScoreType: matchesScoreType,
            passes: passes,
            notes: notes
        )
    }
}
