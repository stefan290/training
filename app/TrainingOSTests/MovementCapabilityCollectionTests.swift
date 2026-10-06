import XCTest
import SwiftData
@testable import TrainingOS

/// MUSCLE VERTICAL SLICE CONTINUATION, Sections 9-11: the real
/// movement-capability collection flow — `RecordMovementCapabilityUseCase`
/// (persistence), `MovementCapabilityCollectionViewModel` (load/edit/save),
/// and the closed loop proving what this flow persists is the SAME real
/// data `TechnicalCapacityDoseAuthority` already consumes (never a second,
/// disconnected capability concept).
@MainActor
final class MovementCapabilityCollectionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func makeUserWithProfile() -> User {
        AppRootStateResolver.ensureBaselineIdentity(context: context)
    }

    // MARK: - RecordMovementCapabilityUseCase

    func testRecordCreatesARealPersistedCapabilityRow() throws {
        let user = makeUserWithProfile()
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let performanceProfile = try XCTUnwrap(user.performanceProfile)

        let recorded = RecordMovementCapabilityUseCase.record(
            exercise: catalog.toesToBar, proficiency: .workoutReady,
            capacityType: .maxUnbrokenReps, capacityValue: 12,
            evidenceSource: .selfReported, performanceProfile: performanceProfile, context: context
        )
        try context.save()

        let reloaded = try XCTUnwrap(performanceProfile.movementCapability(for: catalog.toesToBar))
        XCTAssertEqual(reloaded.id, recorded.id)
        XCTAssertEqual(reloaded.proficiency, .workoutReady)
        XCTAssertEqual(reloaded.capacityType, .maxUnbrokenReps)
        XCTAssertEqual(reloaded.capacityValue, 12)
        XCTAssertEqual(reloaded.evidenceSource, .selfReported)
    }

    func testRecordTwiceUpdatesInPlaceNeverDuplicates() throws {
        let user = makeUserWithProfile()
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let performanceProfile = try XCTUnwrap(user.performanceProfile)

        RecordMovementCapabilityUseCase.record(
            exercise: catalog.pullUp, proficiency: .learning,
            capacityType: nil, capacityValue: nil,
            evidenceSource: .selfReported, performanceProfile: performanceProfile, context: context
        )
        RecordMovementCapabilityUseCase.record(
            exercise: catalog.pullUp, proficiency: .workoutReady,
            capacityType: .maxUnbrokenReps, capacityValue: 8,
            evidenceSource: .selfReported, performanceProfile: performanceProfile, context: context
        )
        try context.save()

        XCTAssertEqual(performanceProfile.movementCapabilities.filter { $0.exercise?.id == catalog.pullUp.id }.count, 1,
                       "a second real report for the same exercise must update in place, never stack a duplicate row")
        let current = try XCTUnwrap(performanceProfile.movementCapability(for: catalog.pullUp))
        XCTAssertEqual(current.proficiency, .workoutReady)
        XCTAssertEqual(current.capacityValue, 8)
    }

    // MARK: - ViewModel

    func testViewModelLoadsExactlyTheThreeGatedMovements() {
        _ = makeUserWithProfile()
        let viewModel = MovementCapabilityCollectionViewModel()
        viewModel.load(modelContext: context)

        XCTAssertEqual(Set(viewModel.rows.map(\.exercise.canonicalName)), ["Toes-to-Bar", "Pull-up", "Handstand Push-up"])
        XCTAssertTrue(viewModel.rows.allSatisfy { !$0.isWorkoutReady && $0.maxUnbrokenReps == nil }, "no prior report exists — every row starts honestly unset, never a guessed default")
    }

    func testViewModelSaveThenReloadRoundTripsRealPersistedState() throws {
        let user = makeUserWithProfile()
        let viewModel = MovementCapabilityCollectionViewModel()
        viewModel.load(modelContext: context)

        let toesToBarRow = try XCTUnwrap(viewModel.rows.first { $0.exercise.canonicalName == "Toes-to-Bar" })
        viewModel.setWorkoutReady(true, for: toesToBarRow.id)
        viewModel.setMaxUnbrokenReps(15, for: toesToBarRow.id)

        XCTAssertTrue(viewModel.save(modelContext: context))

        let reloaded = MovementCapabilityCollectionViewModel()
        reloaded.load(modelContext: context)
        let reloadedRow = try XCTUnwrap(reloaded.rows.first { $0.exercise.canonicalName == "Toes-to-Bar" })
        XCTAssertTrue(reloadedRow.isWorkoutReady)
        XCTAssertEqual(reloadedRow.maxUnbrokenReps, 15)

        let performanceProfile = try XCTUnwrap(user.performanceProfile)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let persisted = try XCTUnwrap(performanceProfile.movementCapability(for: catalog.toesToBar))
        XCTAssertEqual(persisted.proficiency, .workoutReady)
        XCTAssertEqual(persisted.capacityValue, 15)
    }

    func testUnreadyRowPersistsAsUnknownNeverAGuessedProficiency() throws {
        let user = makeUserWithProfile()
        let viewModel = MovementCapabilityCollectionViewModel()
        viewModel.load(modelContext: context)
        XCTAssertTrue(viewModel.save(modelContext: context))

        let performanceProfile = try XCTUnwrap(user.performanceProfile)
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let persisted = try XCTUnwrap(performanceProfile.movementCapability(for: catalog.pullUp))
        XCTAssertEqual(persisted.proficiency, .unknown)
        XCTAssertNil(persisted.capacityType)
        XCTAssertNil(persisted.capacityValue)
    }

    // MARK: - Closed loop: this flow's own persisted data is the SAME data
    // TechnicalCapacityDoseAuthority already reads — never a second,
    // disconnected capability concept.

    func testRecordedCapacityIsTheSameDataTechnicalCapacityDoseAuthorityReads() throws {
        let user = makeUserWithProfile()
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let performanceProfile = try XCTUnwrap(user.performanceProfile)

        RecordMovementCapabilityUseCase.record(
            exercise: catalog.toesToBar, proficiency: .workoutReady,
            capacityType: .maxUnbrokenReps, capacityValue: 7,
            evidenceSource: .selfReported, performanceProfile: performanceProfile, context: context
        )
        try context.save()

        // 7 -> ceiling 3 (`maxRepeatedDose(forCapacity:)`'s locked 6..<10 band)
        // — proves this checkpoint's real UI-entered value is genuinely
        // load-bearing for the exact production dosing authority, not a
        // second, parallel field nothing reads.
        let clamped = TechnicalCapacityDoseAuthority.clampedReps(12, for: catalog.toesToBar, performanceProfile: performanceProfile)
        XCTAssertEqual(clamped, 3, "the real UI-entered capacity value must reach the real production dosing authority")
    }
}
