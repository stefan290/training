import XCTest
@testable import TrainingOS

/// Pure, deterministic tests for `SubstitutionCandidateRanking` — Part E's
/// Change Exercise flow: only slot-valid alternatives appear, ranked by
/// history tier (own history / related-exercise estimate / calibration
/// required), ties broken alphabetically so the same inputs always
/// produce the same order.
final class SubstitutionCandidateRankingTests: XCTestCase {
    private func exercise(
        _ name: String, targets: [MuscleGroup] = [.chest], equipment: String = "barbell", movementPattern: String = "push"
    ) -> Exercise {
        Exercise(canonicalName: name, modality: .strength, equipment: equipment, movementPattern: movementPattern, primaryTargets: targets)
    }

    private func profile(oneRepMax: Double, confidence: Double = 0.8) -> ExercisePerformanceProfile {
        ExercisePerformanceProfile(estimatedOneRepMax: oneRepMax, confidence: confidence)
    }

    func testIneligibleCandidatesAreExcluded() {
        let benchPress = exercise("Barbell Bench Press")
        let legPress = exercise("Leg Press", targets: [.quadriceps])
        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest])

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: benchPress, allExercises: [benchPress, legPress],
            curatedRelationships: [], profileLookup: { _ in nil }, environment: TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases))

        XCTAssertTrue(candidates.allSatisfy { $0.exercise.canonicalName != "Leg Press" })
    }

    func testCurrentExerciseIsNeverOfferedAsItsOwnAlternative() {
        let benchPress = exercise("Barbell Bench Press")
        let inclinePress = exercise("Incline Barbell Press")
        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest])

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: benchPress, allExercises: [benchPress, inclinePress],
            curatedRelationships: [], profileLookup: { _ in nil }, environment: TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases))

        XCTAssertFalse(candidates.contains { $0.exercise.canonicalName == "Barbell Bench Press" })
    }

    func testOwnHistoryTierRanksAboveCalibrationRequired() {
        let benchPress = exercise("Barbell Bench Press")
        let dumbbellPress = exercise("Dumbbell Bench Press")
        // Deliberately shares no target/equipment/movement-pattern with any
        // other candidate, so `ExerciseRelationshipResolver` finds no
        // fallback estimate source either — a genuine calibration-required
        // case, not just "no profile yet."
        let cableFly = exercise("Cable Fly", targets: [.biceps], equipment: "cable", movementPattern: "fly")
        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest, .biceps])
        let dumbbellProfile = profile(oneRepMax: 80)

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: benchPress, allExercises: [benchPress, dumbbellPress, cableFly],
            curatedRelationships: [],
            profileLookup: { $0.canonicalName == "Dumbbell Bench Press" ? dumbbellProfile : nil }, environment: TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases))

        XCTAssertEqual(candidates.first?.exercise.canonicalName, "Dumbbell Bench Press")
        XCTAssertEqual(candidates.first?.tier, .percentageOfEstimate)
        XCTAssertEqual(candidates.last?.exercise.canonicalName, "Cable Fly")
        XCTAssertEqual(candidates.last?.tier, .calibrationRequired)
    }

    func testCandidatesWithTheSameTierAreOrderedAlphabeticallyForDeterminism() {
        let benchPress = exercise("Barbell Bench Press")
        let zCandidate = exercise("Z Machine Press")
        let aCandidate = exercise("A Machine Press")
        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest])

        let candidates = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: benchPress, allExercises: [benchPress, zCandidate, aCandidate],
            curatedRelationships: [], profileLookup: { _ in nil }, environment: TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases))

        XCTAssertEqual(candidates.map(\.exercise.canonicalName), ["A Machine Press", "Z Machine Press"])
    }

    /// Two independent calls with identical inputs must produce the exact
    /// same order — no reliance on `Set`/dictionary iteration order or any
    /// other non-deterministic collection.
    func testRankingIsDeterministicAcrossRepeatedCalls() {
        let benchPress = exercise("Barbell Bench Press")
        let dumbbellPress = exercise("Dumbbell Bench Press")
        let cableFly = exercise("Cable Fly")
        let slot = ExerciseSlot(name: "Horizontal Push", allowedTargets: [.chest])

        let first = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: benchPress, allExercises: [benchPress, dumbbellPress, cableFly],
            curatedRelationships: [], profileLookup: { _ in nil }, environment: TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases))
        let second = SubstitutionCandidateRanking.rank(
            slot: slot, excluding: benchPress, allExercises: [benchPress, dumbbellPress, cableFly],
            curatedRelationships: [], profileLookup: { _ in nil }, environment: TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases))

        XCTAssertEqual(first.map(\.exercise.canonicalName), second.map(\.exercise.canonicalName))
    }
}
