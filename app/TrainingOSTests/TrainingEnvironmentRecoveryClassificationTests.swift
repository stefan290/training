import XCTest
import SwiftData
@testable import TrainingOS

/// TE.1 final UX closure: proves the widened recovery-affordance
/// classification (`TrainingEnvironmentRecoverableError`) correctly
/// exposes a "Configure Training Environment" recovery for BOTH
/// `.trainingEnvironmentRequired` and `.environmentIncompatible`, while
/// keeping the two failure meanings themselves distinct — never
/// collapsing "nothing configured" and "known configuration, missing
/// capability" into one case — and never granting the recovery
/// affordance to an unrelated failure. Also proves the
/// `ChangeExerciseView`-equivalent probe (same
/// `SubstitutionValidator.matchesSemanticConstraints` helper the view
/// itself calls) correctly distinguishes "equipment is the reason
/// nothing shows" from "nothing would show regardless of equipment."
@MainActor
final class TrainingEnvironmentRecoveryClassificationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    // MARK: A/B/D — recovery classification per case, and the two failures stay distinct

    func testTrainingEnvironmentRequiredIsRecoverableAndStillReportsAsTheNarrowerCaseToo() {
        let error = ExerciseSlotResolutionError.trainingEnvironmentRequired
        XCTAssertTrue(error.needsTrainingEnvironmentConfiguration, "no configuration at all must remain recoverable through Training Environment configuration")
        XCTAssertTrue(error.isTrainingEnvironmentRequired, "regression: the narrower, pre-existing classification must still fire for this case")
    }

    func testEnvironmentIncompatibleIsNowRecoverableButStaysDistinctFromTrainingEnvironmentRequired() {
        let error = ExerciseSlotResolutionError.environmentIncompatible(slot: "Squat Pattern", missingEquipment: [.barbell])
        XCTAssertTrue(error.needsTrainingEnvironmentConfiguration, "a known environment missing required equipment must be recoverable through the same Training Environment configuration destination")
        XCTAssertFalse(error.isTrainingEnvironmentRequired, "environmentIncompatible must never be reported as trainingEnvironmentRequired — the two failure meanings are distinct even though they share a recovery destination")
        XCTAssertNotEqual(error, .trainingEnvironmentRequired, "the two cases must remain distinct values, never conflated by the widened recovery check")
    }

    func testEnvironmentIncompatibleAcrossAllFourRealErrorEnumsIsRecoverable() {
        XCTAssertTrue(ExerciseSlotResolutionError.environmentIncompatible(slot: "s", missingEquipment: [.barbell]).needsTrainingEnvironmentConfiguration)
        XCTAssertTrue(FunctionalFitnessMaterializationError.environmentIncompatible(slot: "s", missingEquipment: [.pullUpBar]).needsTrainingEnvironmentConfiguration)
        XCTAssertTrue(SteadyStateMaterializationError.environmentIncompatible(activityType: .cycling, missingEquipment: [.bike]).needsTrainingEnvironmentConfiguration)
        XCTAssertTrue(IntervalMaterializationError.environmentIncompatible(activityType: .rowing, missingEquipment: [.rower]).needsTrainingEnvironmentConfiguration)
    }

    // MARK: C — an unrelated failure must not expose Training Environment recovery

    func testAnUnrelatedFunctionalFitnessFailureDoesNotExposeTrainingEnvironmentRecovery() {
        XCTAssertFalse(FunctionalFitnessMaterializationError.previousExposureRequired.needsTrainingEnvironmentConfiguration, "a failure unrelated to equipment/environment must never show the Training Environment recovery affordance")
        let stimulusFailure = FunctionalFitnessMaterializationError.stimulusValidationFailed(
            StimulusValidation(
                estimatedDurationSeconds: nil, matchesDurationDomain: false, matchesModalityMix: false,
                matchesLoadingClassification: false, matchesSkillDemand: false, matchesScoreType: false,
                passes: false, notes: ["test"]
            )
        )
        XCTAssertFalse(stimulusFailure.needsTrainingEnvironmentConfiguration)
    }

    func testAnUnrelatedIntervalFailureDoesNotExposeTrainingEnvironmentRecovery() {
        XCTAssertFalse(IntervalMaterializationError.previousOutcomeRequired.needsTrainingEnvironmentConfiguration)
    }

    // MARK: trainingEnvironmentRecoveryMessage — presentation stays distinct too

    func testRecoveryMessageDistinguishesNoConfigurationFromMissingEquipment() {
        let noConfigMessage = trainingEnvironmentRecoveryMessage(for: ExerciseSlotResolutionError.trainingEnvironmentRequired)
        let missingEquipmentMessage = trainingEnvironmentRecoveryMessage(for: ExerciseSlotResolutionError.environmentIncompatible(slot: "Squat Pattern", missingEquipment: [.barbell]))
        XCTAssertNotNil(noConfigMessage)
        XCTAssertNotNil(missingEquipmentMessage)
        XCTAssertNotEqual(noConfigMessage, missingEquipmentMessage, "the two user-facing messages must remain distinct presentation, not a single generic string")
        XCTAssertTrue(missingEquipmentMessage!.contains("Barbell") || missingEquipmentMessage!.lowercased().contains("barbell"), "the reported missing equipment should be named, not left generic")
    }

    func testRecoveryMessageIsNilForAnUnrelatedError() {
        XCTAssertNil(trainingEnvironmentRecoveryMessage(for: FunctionalFitnessMaterializationError.previousExposureRequired))
    }

    // MARK: E/F — the ChangeExerciseView-equivalent probe

    /// Mirrors exactly what `ChangeExerciseView.loadCandidates()` computes:
    /// `SubstitutionValidator.matchesSemanticConstraints` (environment-
    /// ignorant) vs. `SubstitutionValidator.isValid` (environment-aware).
    func testSemanticCandidatesThatAreAllEquipmentInvalidWouldExposeTrainingEnvironmentRecovery() {
        let slot = ExerciseSlot(name: "Squat Pattern", allowedMovementFunctions: [.squatLoaded])
        let barbellBackSquat = Exercise(canonicalName: "TE.1 Recovery Back Squat", modality: .strength, equipment: "barbell", movementPattern: "squat", movementFunctions: [.squatLoaded], requiredEquipment: [.barbell, .rack])
        let bodyweightOnlyEnvironment = TrainingEnvironment(name: "Bodyweight Only", availableEquipment: [])

        let semanticallyEligible = [barbellBackSquat].filter { SubstitutionValidator.matchesSemanticConstraints(candidate: $0, for: slot) }
        let environmentAwareEligible = [barbellBackSquat].filter { SubstitutionValidator.isValid(candidate: $0, for: slot, environment: bodyweightOnlyEnvironment) }

        XCTAssertFalse(semanticallyEligible.isEmpty, "a real alternative exists for this slot")
        XCTAssertTrue(environmentAwareEligible.isEmpty, "but none of them are usable in this environment — candidates.isEmpty in the view")
        // The view's own recovery flag is exactly: environment configured, candidates empty, semanticallyEligible non-empty.
        let wouldShowRecovery = environmentAwareEligible.isEmpty && !semanticallyEligible.isEmpty
        XCTAssertTrue(wouldShowRecovery, "an equipment-caused empty list must expose the Training Environment recovery affordance")
    }

    func testZeroSemanticCandidatesRegardlessOfEquipmentDoesNotFalselyExposeTrainingEnvironmentRecovery() {
        let squatSlot = ExerciseSlot(name: "Squat Pattern", allowedMovementFunctions: [.squatLoaded])
        // Deliberately the wrong movement function entirely — no amount of
        // equipment could ever make this candidate fit this slot.
        let unrelatedRow = Exercise(canonicalName: "TE.1 Recovery Unrelated Row", modality: .strength, equipment: "barbell", movementPattern: "row", movementFunctions: [.horizontalPullLoaded], requiredEquipment: [])
        let fullyEquippedEnvironment = TrainingEnvironment(name: "Full", availableEquipment: EquipmentRequirement.allCases)

        let semanticallyEligible = [unrelatedRow].filter { SubstitutionValidator.matchesSemanticConstraints(candidate: $0, for: squatSlot) }
        let environmentAwareEligible = [unrelatedRow].filter { SubstitutionValidator.isValid(candidate: $0, for: squatSlot, environment: fullyEquippedEnvironment) }

        XCTAssertTrue(semanticallyEligible.isEmpty, "no candidate fits this slot at all, regardless of equipment")
        XCTAssertTrue(environmentAwareEligible.isEmpty)
        let wouldShowRecovery = environmentAwareEligible.isEmpty && !semanticallyEligible.isEmpty
        XCTAssertFalse(wouldShowRecovery, "an empty list caused by a genuine absence of any matching candidate must NOT be mislabeled as an environment/equipment problem")
    }
}
