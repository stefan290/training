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
        reps: Int,
        targetRir: Int?,
        actualRir: Int?,
        prBand: String?,
        scoringDirection: ScoringDirection,
        context resultContext: ResultContext,
        setPrescription: SetPrescription?,
        exercisePrescription: ExercisePrescription,
        exercise: Exercise,
        performanceProfile: PerformanceProfile,
        completedAt: Date,
        modelContext: ModelContext
    ) -> SetResult {
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
            actualRir: actualRir,
            completedAt: completedAt,
            prBand: prBand
        )
        modelContext.insert(result)

        setPrescription?.addResult(result)
        exercisePrescription.addLoggedSetResult(result)
        exerciseProfile.addSetResult(result)
        exerciseProfile.lastPerformedAt = completedAt

        let existingBest = ScoringEngine.bestRecord(
            among: exerciseProfile.personalRecords,
            context: resultContext,
            repBand: prBand
        )
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

        return result
    }
}
