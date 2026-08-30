import Foundation

/// Stage CP.1: pure, deterministic mapping from a `WorkoutBlock`'s real,
/// already-resolved Strength/Hypertrophy/Powerlifting prescriptions to a
/// `TrainingStressProfile` — mirrors `FunctionalFitnessStressProfileMapper`'s
/// own discipline exactly (coarse categorical classification only, never a
/// fabricated numeric score).
///
/// **Hard invariant (the direct lesson of the Stage 10R.7A-TX-era design
/// review's §14 correction):** this mapper OBSERVES the resolved
/// prescription only. It never reinterprets, second-guesses, or
/// influences `StrengthProgressionEngine`/`LoadFirstOverlayEngine`/
/// `SourceCompatibleDeloadStrategy`'s own output — it has no `isDeload`
/// parameter and takes no deload-specific branch; a deload week's already-
/// reduced resolved weight/reps simply classify lower on their own merits,
/// through the exact same logic as any other week's resolved values. If a
/// future defect made this mapper need to branch on `isDeload` to produce
/// a correct answer, that would mean the classification was reading
/// something other than the resolved prescription — a bug to fix at the
/// call site, never a reason to add a deload branch here.
enum StrengthTrainingStressMapper {
    /// One already-resolved prescription within a single `WorkoutBlock` —
    /// exactly what `StrengthMaterializer` already computed for that slot
    /// this week (deload or not), never re-derived here. `setCount` is the
    /// real resolved count (0 for a rule-omitted slot).
    struct ResolvedPrescription {
        var exercise: Exercise
        var weightKg: Double?
        var repGoal: RepGoal?
        var setCount: Int
    }

    private static let lowerBodyMuscleGroups: Set<MuscleGroup> = [.quadriceps, .hamstrings, .glutes, .calves]
    private static let upperBodyMuscleGroups: Set<MuscleGroup> = [.chest, .back, .shoulders, .triceps, .biceps, .forearms, .lateralDelt, .rearDelt]

    /// `nil` only when `prescriptions` is empty — composing nothing
    /// produces nothing, never a fabricated all-`.none` profile (mirrors
    /// `SessionStressComposer.compose`'s identical discipline one level up).
    static func map(prescriptions: [ResolvedPrescription]) -> TrainingStressProfile? {
        guard !prescriptions.isEmpty else { return nil }

        // "The whole programmed block matters" — every dimension below
        // scans every prescription in the block, never just the first one
        // inspected, so a mixed full-body block correctly reflects BOTH
        // upper and lower load rather than whichever exercise happens to
        // be resolved first.
        let hasLowerBody = prescriptions.contains { hasAnyTarget($0.exercise, in: lowerBodyMuscleGroups) }
        let hasUpperBody = prescriptions.contains { hasAnyTarget($0.exercise, in: upperBodyMuscleGroups) }

        let overall = worstCase(prescriptions.map(intensityLevel))

        let totalSets = prescriptions.reduce(0) { $0 + $1.setCount }
        let volume = volumeLevel(forTotalSets: totalSets)

        // Systemic/metabolic demand: the worse of (effort intensity, total
        // volume) — a block with many moderate-effort sets can be just as
        // systemically demanding as a few very-hard ones; never averaged
        // into a fabricated middle value.
        let systemic = worstCase([overall, volume])

        return TrainingStressProfile(
            overallIntensity: overall,
            systemicDemand: systemic,
            lowerBodyLoad: hasLowerBody ? overall : .none,
            upperBodyLoad: hasUpperBody ? overall : .none,
            // Every exercise this catalog resolves Strength/Hypertrophy/
            // Powerlifting slots to is controlled barbell/dumbbell/machine
            // work — never a jump/plyometric variant. A real, justified
            // classification from what this catalog actually contains,
            // not a lazy default.
            impactLoading: .none,
            metabolicDemand: systemic,
            durationClassification: durationLevel(forTotalSets: totalSets),
            modality: nil,
            recoveryDemand: systemic
        )
    }

    private static func hasAnyTarget(_ exercise: Exercise, in groups: Set<MuscleGroup>) -> Bool {
        !Set(exercise.primaryTargets).isDisjoint(with: groups)
    }

    /// Effort tier for one resolved prescription. RIR is the most reliable
    /// available signal — a real, source-resolved effort target, already
    /// correctly reduced for a deload week by `SourceCompatibleDeloadStrategy`
    /// before this function ever sees it. A fixed-rep prescription with no
    /// RIR context (e.g. Powerlifting's literal "Triples"), or a
    /// prescription with no resolved load at all, is the genuinely-
    /// uncertain case: documented conservative `.moderate` when a load
    /// exists, `.low` only when there is genuinely no load to speak of —
    /// never `.none` for a real, resolved prescription (which would
    /// silently disable `InterferenceAvoidanceRule`'s protection).
    private static func intensityLevel(for prescription: ResolvedPrescription) -> LoadLevel {
        switch prescription.repGoal?.prescription {
        case .rir(let n):
            return n <= 1 ? .high : .moderate
        case .fixedReps, nil:
            return prescription.weightKg != nil ? .moderate : .low
        }
    }

    /// Coarse total-set-count buckets — TRAININGOS_DESIGNED thresholds,
    /// never presented as a sourced fact, same discipline as
    /// `FunctionalFitnessStimulusValidator`'s own hardcoded second-based
    /// duration thresholds.
    private static func volumeLevel(forTotalSets totalSets: Int) -> LoadLevel {
        switch totalSets {
        case 0: return .none
        case 1...3: return .low
        case 4...8: return .moderate
        default: return .high
        }
    }

    private static func durationLevel(forTotalSets totalSets: Int) -> DurationDomain {
        switch totalSets {
        case 0...6: return .short
        case 7...14: return .medium
        default: return .long
        }
    }

    private static func worstCase(_ levels: [LoadLevel]) -> LoadLevel {
        levels.max { $0.ordinal < $1.ordinal } ?? .none
    }
}
