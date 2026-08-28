import Foundation

/// Stage 10R.5: walks a `ProgramInstance`'s own history for one
/// `Exercise` to produce the ordered, most-recent-first ELIGIBLE
/// exposures `LoadFirstOverlayEngine.recommend` needs — mirrors
/// `DoubleProgressionHistoryResolver`'s already-approved walk/grouping/
/// exclusion architecture (Stage 10B.6), with the corrected extraction
/// predicate (RIR-based, not rep-range-required) and the real Family A
/// deload signal (`appliedLoadReasonCode`, not a V2-specific constant).
///
/// **Scoping, per D-10R5-12/13**: exercise-specific AND instance-scoped
/// — never reaches into a prior `ProgramInstance` (a substitution or a
/// new mesocycle both correctly start with zero evidence, with no
/// special-casing needed beyond this scope itself), and never transfers
/// evidence from a different `Exercise`.
///
/// **Exclusion, per D-10R5-10/11/14**: an exposure is simply omitted —
/// never inserted as a neutral placeholder — when it is a deload week,
/// has an accepted `ReadinessAdaptationDecision`, or has any valid
/// prescribed set missing a logged actual RIR (incomplete data is
/// ineligible, never interpreted as either easy or hard). This is what
/// makes D-10R5-5's "an ineligible exposure must not erase an
/// already-established hard streak" rule true for free: the two most
/// recent entries in this resolver's own output are always the two most
/// recent REAL exposures, regardless of how many ineligible ones sit
/// between them in real time.
enum LoadFirstExposureResolver {
    struct Exposure {
        /// `actualRir - targetRir` per valid (non-`isAdaptedAway`)
        /// prescribed set that has a logged actual RIR — the complete
        /// vector, never pre-reduced.
        var setSurpluses: [Int]
        /// The weight actually used for this exposure — the overlay's
        /// own frozen recommendation if one was ever computed for it,
        /// else the source's own resolved value. This is what
        /// `LoadFirstOverlayEngine.recommend`'s `previousEffectiveWeight`
        /// reads for a HOLD/regress decision (D-10R5-5: hold at the
        /// previous actual/effective reference weight, never a fresh
        /// source value).
        var effectiveWeightUsed: Double
    }

    /// `current` is excluded by identity so a not-yet-logged exposure
    /// never accidentally counts as its own history.
    static func recentEligibleExposures(
        for exercise: Exercise,
        in instance: ProgramInstance,
        excluding current: ExercisePrescription,
        limit: Int
    ) -> [Exposure] {
        let candidates = instance.sessions
            .flatMap(\.orderedBlocks)
            .flatMap(\.orderedPrescriptions)
            .filter { $0.exercise?.id == exercise.id && $0.id != current.id }
            .sorted { prescriptionDate($0) > prescriptionDate($1) }

        var results: [Exposure] = []
        for prescription in candidates {
            guard results.count < limit else { break }
            guard let exposure = exposure(from: prescription) else { continue }
            results.append(exposure)
        }
        return results
    }

    private static func prescriptionDate(_ prescription: ExercisePrescription) -> Date {
        prescription.workoutBlock?.session?.day?.date ?? .distantPast
    }

    /// `nil` when `prescription` is not a real, eligible exposure at all
    /// (deload week, readiness-adapted, or any valid set incomplete) —
    /// see this type's own doc comment for exactly what "eligible" means
    /// and why.
    private static func exposure(from prescription: ExercisePrescription) -> Exposure? {
        if let code = prescription.appliedLoadReasonCode, LoadFirstOverlayEngine.deloadReasonCodes.contains(code) {
            return nil
        }
        if prescription.readinessAdaptationDecisions.contains(where: { $0.userResponse == .accepted }) {
            return nil
        }

        let validSets = prescription.orderedSetPrescriptions.filter { !$0.isAdaptedAway }
        guard !validSets.isEmpty else { return nil }

        var surpluses: [Int] = []
        for setPrescription in validSets {
            guard let targetRir = setPrescription.targetRir else { return nil }
            guard let result = prescription.loggedSetResults.first(where: { $0.setPrescription?.id == setPrescription.id }) else { return nil }
            guard let actualRir = result.actualRir else { return nil }
            surpluses.append(actualRir - targetRir)
        }

        let effectiveWeight = prescription.loadOverlayRecommendedWeight ?? validSets.first?.targetWeight ?? 0
        return Exposure(setSurpluses: surpluses, effectiveWeightUsed: effectiveWeight)
    }
}
