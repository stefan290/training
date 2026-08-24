import Foundation

/// Stage 10B.6: resolves real, exercise-scoped exposure history for
/// `DoubleProgressionEngine`/`HypertrophyV2ProgressionEngine` — the
/// double-progression sibling of `AutoregulationRatingResolver`. Pure
/// read; never mutates anything, never itself decides a weight.
///
/// **Scoped to the canonical Exercise, never to one `ProgramInstance`**
/// (`ExercisePerformanceProfile`'s own documented invariant: "everything
/// the app permanently knows about one user's history with one canonical
/// Exercise... across every program instance that ever touched it").
/// This is also the fix for the approved substitution rule
/// (`STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md` §15): a temporarily
/// substituted exercise's history never contaminates the original
/// exercise's, and vice versa, because history is looked up per Exercise,
/// never per slot/template.
///
/// **Readiness-adapted exposures are excluded, not force-classified**
/// (approved "READINESS INTERACTION" instruction: a readiness-modified
/// workout must never automatically count as a normal underperformance —
/// or, symmetrically, a normal strong performance — against the original
/// prescription). An exposure with an accepted `ReadinessAdaptationDecision`
/// is skipped entirely when walking history for load-progression
/// purposes; the walk continues past it to the next real, unadapted
/// exposure. A skipped workout (zero logged results) was never an
/// exposure at all and is likewise excluded.
enum DoubleProgressionHistoryResolver {
    /// One real, completed exposure's worth of data — everything
    /// `DoubleProgressionEngine`/`HypertrophyV2ProgressionEngine` needs
    /// from a single past occurrence of an exercise.
    struct Exposure {
        let targets: [SetTarget]
        let outcomes: [SetOutcome]
        let lastKnownWeight: Double
    }

    struct HistoryLookup {
        /// The most recent normal (unadapted, fully logged) exposure —
        /// `hasUsableHistory == (mostRecentNormal != nil)`.
        let mostRecentNormal: Exposure?
        /// The one immediately before `mostRecentNormal`, also normal —
        /// feeds the two-consecutive-miss REGRESS check only.
        let previousNormal: Exposure?
    }

    /// The real, chronological (newest-first), exercise-scoped lookup —
    /// walks `ExercisePerformanceProfile.orderedSetResults` (never one
    /// `ProgramInstance`), groups them back into the `ExercisePrescription`
    /// each belonged to, and skips any exposure that is not usable
    /// evidence: zero logged results, or an accepted readiness adaptation.
    /// A completed exposure whose every set carried
    /// `HypertrophyV2ProgressionEngine.deloadTargetRir` is also treated as
    /// non-normal (a discovered edge case, flagged in the implementation
    /// report, not one of the 10 originally approved decisions): a
    /// deload's own deliberately-easy RIR target should not read as
    /// "strong performance" feeding the very next mesocycle's starting
    /// weight.
    /// `excluding`: the current prescription being judged, when the
    /// caller's own logged results are already indexed into
    /// `performanceProfile` by the time it calls this (e.g.
    /// `CompleteSessionUseCase.progressionPreview` runs after
    /// `LogSetUseCase` has already made this same session's results
    /// durable) — without excluding it, "the previous exposure" would
    /// otherwise resolve to the exposure currently being judged, not the
    /// one before it. Real week-N+1 materialization has no such
    /// in-flight prescription and passes `nil`.
    static func lookup(for exercise: Exercise, performanceProfile: PerformanceProfile?, excluding currentPrescriptionID: UUID? = nil) -> HistoryLookup {
        let normal = recentNormalExposures(for: exercise, performanceProfile: performanceProfile, excluding: currentPrescriptionID, limit: 2)
        return HistoryLookup(mostRecentNormal: normal.first, previousNormal: normal.dropFirst().first)
    }

    private static func recentNormalExposures(
        for exercise: Exercise, performanceProfile: PerformanceProfile?, excluding currentPrescriptionID: UUID?, limit: Int
    ) -> [Exposure] {
        guard let profile = performanceProfile?.profile(for: exercise) else { return [] }

        var seenPrescriptionIDs = Set<UUID>()
        var prescriptionsNewestFirst: [ExercisePrescription] = []
        for result in profile.orderedSetResults.reversed() {
            guard let prescription = result.exercisePrescription, !seenPrescriptionIDs.contains(prescription.id) else { continue }
            guard prescription.id != currentPrescriptionID else { continue }
            seenPrescriptionIDs.insert(prescription.id)
            prescriptionsNewestFirst.append(prescription)
        }

        var normal: [Exposure] = []
        for prescription in prescriptionsNewestFirst {
            guard normal.count < limit else { break }
            guard !hadAcceptedReadinessAdaptation(prescription), !isLikelyDeloadExposure(prescription) else { continue }
            guard let exposure = exposure(from: prescription) else { continue }
            normal.append(exposure)
        }
        return normal
    }

    private static func hadAcceptedReadinessAdaptation(_ prescription: ExercisePrescription) -> Bool {
        prescription.readinessAdaptationDecisions.contains { $0.userResponse == .accepted }
    }

    private static func isLikelyDeloadExposure(_ prescription: ExercisePrescription) -> Bool {
        let targets = prescription.executableSetPrescriptions
        guard !targets.isEmpty else { return false }
        return targets.allSatisfy { $0.targetRir == HypertrophyV2ProgressionEngine.deloadTargetRir }
    }

    private static func exposure(from prescription: ExercisePrescription) -> Exposure? {
        let executable = prescription.executableSetPrescriptions
        let targets = executable.map { SetTarget(repRangeLow: $0.repRangeLow, repRangeHigh: $0.repRangeHigh, targetRir: $0.targetRir) }
        guard !targets.isEmpty else { return nil }
        let loggedResults = prescription.loggedSetResults.sorted { $0.setIndex < $1.setIndex }
        guard let lastWeight = loggedResults.last?.weight, loggedResults.count == targets.count else { return nil }
        let outcomes = loggedResults.map { SetOutcome(reps: $0.reps, actualRir: $0.actualRir) }
        return Exposure(targets: targets, outcomes: outcomes, lastKnownWeight: lastWeight)
    }
}
