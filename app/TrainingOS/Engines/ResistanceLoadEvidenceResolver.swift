import Foundation

/// FF RESISTANCE CROSS-WEEK LOAD RESOLUTION (Sections 1-9, 22): the one
/// general, week-agnostic seam through which every FF-owned resistance
/// role (Muscle's Hypertrophy-authority role, Generic FF Strength) resolves
/// its suggested load — at week 0 and every later rolled-forward week
/// alike. The same function serves both; week 0 simply finds no prior
/// exposure yet, so precedence falls straight through to the existing
/// bootstrap/calibration path unchanged.
///
/// Never reachable from any source-backed (Hypertrophy/Strength/
/// Powerlifting) generator — those keep their own unmodified
/// `RollTacticalWindowUseCase.strengthSlotContext`/`resolveWeight` path
/// (Section 17/18's absolute non-override). Materialization and
/// completion preview share this policy.
enum ResistanceLoadEvidenceResolver {
    enum Resolution {
        case suggested(weightKg: Double, reasonCode: StrengthReasonCode)
        case calibrationRequired
    }

    /// Precedence (Section 6): (1) a valid, EARLIER, completed exposure's
    /// real result-driven recommendation for this EXACT exercise (Section
    /// 7/30 — no cross-exercise, no cross-equipment-variant transfer, since
    /// lookup is keyed by `Exercise` identity via `PerformanceProfile
    /// .profile(for:)`, never a pattern/category match); (2) the existing,
    /// unmodified RM-calibration bootstrap
    /// (`StrengthProgressionEngine.resolveWeight`, same arithmetic used at
    /// week 0 today); (3) calibration-required. `INSUFFICIENT_EVIDENCE`
    /// (Section 27/29) falls through to (2) rather than being treated as a
    /// real recommendation — an incomplete/abandoned exposure must never
    /// drive progression, but it also must not block falling back to
    /// truthful bootstrap evidence.
    static func resolve(
        exercise: Exercise,
        rules: StrengthProgressionRules,
        performanceProfile: PerformanceProfile?,
        instance: ProgramInstance,
        userProfile: UserProfile?,
        before date: Date
    ) -> Resolution {
        guard case .rmBased(let payload) = rules.loadRule else { return .calibrationRequired }
        let equipmentProfile = EquipmentProfile.resolved(for: exercise, userProfile: userProfile)

        if let performanceProfile,
           let exerciseProfile = performanceProfile.profile(for: exercise),
           let exposure = mostRecentCompletedExposure(in: exerciseProfile, before: date),
           let recommendation = recommendation(for: exposure, equipmentProfile: equipmentProfile),
           recommendation.evaluation != .insufficientEvidence {
            return .suggested(weightKg: recommendation.weightKg, reasonCode: recommendation.reasonCode)
        }

        if let calibration = instance.sourceRMCalibration(for: exercise, rmType: payload.rmType) {
            let result = StrengthProgressionEngine.resolveWeight(
                rules: rules, weekIndex: 0, rmKilograms: calibration.kilograms,
                weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: equipmentProfile
            )
            if let weightKg = result.weightKg {
                return .suggested(weightKg: weightKg, reasonCode: result.reasonCode)
            }
        }

        return .calibrationRequired
    }

    /// Shared by next-week materialization and the completion preview.
    /// Keeps the existing FF policy, set filtering and equipment rounding
    /// identical in both places. No prescription or result is modified.
    struct Recommendation {
        let evaluation: ExposureEvaluation
        let weightKg: Double
        let reasonCode: StrengthReasonCode
    }

    static func recommendation(
        for results: [SetResult], equipmentProfile: EquipmentProfile
    ) -> Recommendation? {
        let exposure = results.filter { $0.setPrescription?.isWarmup != true }
        guard let reference = exposure.first,
              let prescribedCount = reference.exercisePrescription?.orderedSetPrescriptions.filter({ !$0.isWarmup }).count,
              let lastSetIndex = exposure.map(\.setIndex).max(),
              let terminalWeight = exposure.first(where: { $0.setIndex == lastSetIndex })?.weight
        else { return nil }
        let evaluation = ResultDrivenProgressionEngine.evaluate(
            prescribedSetCount: prescribedCount,
            repRangeLow: reference.setPrescription?.repRangeLow,
            repRangeHigh: reference.setPrescription?.repRangeHigh,
            targetRir: reference.setPrescription?.targetRir,
            targetRirHigh: reference.setPrescription?.targetRirHigh,
            workingSets: exposure.map {
                .init(setIndex: $0.setIndex, weight: $0.weight, reps: $0.reps, actualRir: $0.actualRir)
            }
        )
        let (weightKg, reasonCode) = ResultDrivenProgressionEngine.nextSuggestedLoad(
            evaluation: evaluation, actualLoad: terminalWeight, equipmentProfile: equipmentProfile
        )
        return Recommendation(evaluation: evaluation, weightKg: weightKg, reasonCode: reasonCode)
    }

    /// Section 4/13/14/20: one EXPOSURE is every real non-warmup working
    /// set logged under the same `ExercisePrescription` — the natural
    /// one-role-in-one-session grouping this codebase already materializes.
    /// Filtering to `completedAt < date` first, then taking the LAST such
    /// result's own `exercisePrescription`, finds the most recent EARLIER
    /// exposure without needing a separate session/date index — an
    /// unperformed (no `SetResult` yet) future session can never appear
    /// here, so same-week phantom progression is structurally impossible
    /// (Section 14/20): a session with no logged results contributes
    /// nothing to `orderedSetResults`.
    private static func mostRecentCompletedExposure(
        in exerciseProfile: ExercisePerformanceProfile, before date: Date
    ) -> [SetResult]? {
        let priorWorkingResults = exerciseProfile.orderedSetResults.filter {
            $0.completedAt < date && $0.setPrescription?.isWarmup != true
        }
        guard let mostRecentPrescriptionID = priorWorkingResults.last?.exercisePrescription?.id else { return nil }
        let exposure = priorWorkingResults.filter { $0.exercisePrescription?.id == mostRecentPrescriptionID }
        return exposure.isEmpty ? nil : exposure
    }
}
