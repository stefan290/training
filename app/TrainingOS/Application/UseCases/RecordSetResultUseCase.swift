import Foundation
import SwiftData

/// Logs one set's actual outcome and folds it into the user's permanent
/// history. This is the only place a SetResult should be created — seed
/// data and (later) the live set-logging UI both call through here, so
/// there is one answer to "how does a logged set become a PR."
///
/// Business logic belongs here, in the application/use-case layer, not in
/// a SwiftUI View and not in a SwiftData model. Every relationship below is
/// established from exactly one side, via the owning model's `addX`
/// method — never by setting both sides manually. See CLAUDE.md and
/// DELETE_RULE_MATRIX.md.
enum RecordSetResultUseCase {
    @discardableResult
    static func recordSet(
        setIndex: Int,
        weight: Double,
        reps: Int?,
        targetRir: Int?,
        targetRirHigh: Int? = nil,
        actualRir: Int?,
        prBand: String?,
        scoringDirection: ScoringDirection,
        context resultContext: ResultContext,
        setPrescription: SetPrescription?,
        exercisePrescription: ExercisePrescription,
        exercise: Exercise,
        performanceProfile: PerformanceProfile,
        completedAt: Date,
        modelContext: ModelContext,
        distanceMeters: Double? = nil,
        durationSeconds: Int? = nil
    ) -> (result: SetResult, isFirstEverEntry: Bool) {
        let exerciseProfile = PerformanceProfileStore.exerciseProfile(
            for: exercise,
            in: performanceProfile,
            context: modelContext
        )

        let result = SetResult(
            setIndex: setIndex,
            weight: weight,
            reps: reps,
            targetRir: targetRir,
            targetRirHigh: targetRirHigh,
            actualRir: actualRir,
            completedAt: completedAt,
            prBand: prBand,
            distanceMeters: distanceMeters,
            durationSeconds: durationSeconds
        )
        modelContext.insert(result)

        setPrescription?.addResult(result)
        exercisePrescription.addLoggedSetResult(result)
        exerciseProfile.addSetResult(result)
        exerciseProfile.lastPerformedAt = completedAt

        // Dogfood Round 2 Continuation (Finding J): the PR mechanism below
        // is rep-band-keyed (`prBand`) and weight-scored — a real, tested
        // shape for rep-based strength work, never yet designed for a
        // distance-based result (a "heaviest carry" or "farthest carry"
        // PR is a genuinely different, un-built concept — no additional
        // carry progression was authorized this checkpoint). `reps == nil`
        // is the exact, honest signal this result isn't rep-based —
        // explicitly skipped, never coerced through the existing rep-band
        // PR path as if it were a zero-rep strength set.
        guard reps != nil else {
            return (result, false)
        }

        let existingBest = ScoringEngine.bestRecord(
            among: exerciseProfile.personalRecords,
            context: resultContext,
            repBand: prBand
        )
        // Stage 6B, `STAGE6A_DECISION_MEMO.md` §1b: a first-ever entry
        // still creates a real PersonalRecord below (unchanged, tested
        // behavior) — `isFirstEverEntry` only lets the caller choose
        // presentation copy ("First recorded" vs. "Personal record!")
        // without re-deriving this same lookup.
        let isFirstEverEntry = existingBest == nil
        if ScoringEngine.isNewPersonalRecord(
            candidateValue: weight,
            direction: scoringDirection,
            existingBest: existingBest
        ) {
            result.isPersonalRecord = true
            let record = PersonalRecord(
                value: weight,
                repBand: prBand,
                scoringDirection: scoringDirection,
                context: resultContext,
                achievedAt: completedAt
            )
            modelContext.insert(record)
            // sourceSetResult is a one-directional traceability pointer
            // (no inverse collection declared on SetResult), so a direct
            // assignment here carries no dual-mutation risk.
            record.sourceSetResult = result
            exerciseProfile.addPersonalRecord(record)
        }

        return (result, isFirstEverEntry)
    }
}
