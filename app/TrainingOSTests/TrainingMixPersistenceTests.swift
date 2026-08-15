import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 4F: create -> save -> fresh ModelContext -> fetch -> semantic
/// equality for `TrainingMix`/`TrainingMixComponent`, plus the delete-rule
/// proofs CLAUDE.md rule 1/2 require — a `TrainingMix` is pure
/// planning/preference metadata, so it may cascade freely, but nothing
/// about it may ever reach into `SetResult`/`PersonalRecord`/
/// `PerformanceProfile`, and deleting one must never touch those.
@MainActor
final class TrainingMixPersistenceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func freshContext() -> ModelContext {
        ModelContext(container)
    }

    func testTrainingMixWithComponentsSurvivesRoundTrip() throws {
        let mixID = UUID()
        let mix = TrainingMix(id: mixID, kind: .selected, name: "Muscle Gain Hybrid", preferenceStrength: .userStronglyPrefers)
        context.insert(mix)

        let strengthComponent = TrainingMixComponent(
            label: "Strength",
            programmingSystem: .hypertrophy,
            priority: .primary,
            frequency: SessionFrequency(target: 3, minimum: 2, maximum: 4),
            flexibility: .required,
            allowsDoubleSessionPairing: false,
            preferredDays: [.monday, .thursday],
            requiredSpacingDays: 2
        )
        context.insert(strengthComponent)
        mix.addComponent(strengthComponent)

        let supportComponent = TrainingMixComponent(
            label: "Functional Fitness",
            programmingSystem: .functionalFitness,
            priority: .supporting,
            frequency: SessionFrequency(target: 2)
        )
        context.insert(supportComponent)
        mix.addComponent(supportComponent)

        try context.save()

        let fetchContext = freshContext()
        let reloaded = try XCTUnwrap(fetchContext.fetch(FetchDescriptor<TrainingMix>(predicate: #Predicate { $0.id == mixID })).first)

        XCTAssertEqual(reloaded.kind, .selected)
        XCTAssertEqual(reloaded.preferenceStrength, .userStronglyPrefers)
        XCTAssertEqual(reloaded.orderedComponents.map(\.label), ["Strength", "Functional Fitness"])

        let reloadedStrength = try XCTUnwrap(reloaded.orderedComponents.first)
        XCTAssertEqual(reloadedStrength.priority, .primary)
        XCTAssertEqual(reloadedStrength.frequency, SessionFrequency(target: 3, minimum: 2, maximum: 4))
        XCTAssertEqual(reloadedStrength.flexibility, .required)
        XCTAssertFalse(reloadedStrength.allowsDoubleSessionPairing)
        XCTAssertEqual(reloadedStrength.preferredDays, [.monday, .thursday])
        XCTAssertEqual(reloadedStrength.requiredSpacingDays, 2)
        XCTAssertEqual(reloadedStrength.programmingSystem, .hypertrophy)

        let reloadedSupport = reloaded.orderedComponents[1]
        XCTAssertEqual(reloadedSupport.priority, .supporting)
        XCTAssertNil(reloadedSupport.requiredSpacingDays)
    }

    func testDeletingATrainingMixCascadesToItsComponents() throws {
        let mix = TrainingMix(kind: .recommended, name: "Mix")
        context.insert(mix)
        let component = TrainingMixComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        mix.addComponent(component)
        try context.save()

        let componentID = component.id
        context.delete(mix)
        try context.save()

        let survivors = try context.fetch(FetchDescriptor<TrainingMixComponent>(predicate: #Predicate { $0.id == componentID }))
        XCTAssertTrue(survivors.isEmpty, "a TrainingMixComponent has no meaning once its TrainingMix is gone")
    }

    func testDeletingATrainingPhaseCascadesItsTrainingMixesButNeverItsProgramInstances() throws {
        let phase = TrainingPhase(type: .muscleGain, startDate: Date(), priorityRule: .strength)
        context.insert(phase)

        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        phase.addTrainingMix(mix)

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        phase.addProgramInstance(instance)
        try context.save()

        let mixID = mix.id
        let instanceID = instance.id
        context.delete(phase)
        try context.save()

        XCTAssertTrue(try context.fetch(FetchDescriptor<TrainingMix>(predicate: #Predicate { $0.id == mixID })).isEmpty)
        // CLAUDE.md rule 1: ending/deleting a Phase must never delete the
        // ProgramInstance (or its history) that ran inside it.
        let survivingInstance = try XCTUnwrap(context.fetch(FetchDescriptor<ProgramInstance>(predicate: #Predicate { $0.id == instanceID })).first)
        XCTAssertNil(survivingInstance.phase)
    }

    func testDeletingAProgramInstanceNullifiesItsTrainingMixComponentRatherThanDeletingIt() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let component = TrainingMixComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 3))
        context.insert(component)
        mix.addComponent(component)

        let instance = ProgramInstance(ownerUserID: UUID())
        context.insert(instance)
        component.programInstance = instance
        try context.save()

        let componentID = component.id
        context.delete(instance)
        try context.save()

        let survivingComponent = try XCTUnwrap(context.fetch(FetchDescriptor<TrainingMixComponent>(predicate: #Predicate { $0.id == componentID })).first)
        XCTAssertNil(survivingComponent.programInstance, "nullified, not deleted, along with the instance it once pointed to")
    }

    func testPhaseExposesSelectedAndRecommendedMixesSeparately() throws {
        let phase = TrainingPhase(type: .muscleGain, startDate: Date(), priorityRule: .strength)
        context.insert(phase)

        let recommended = TrainingMix(kind: .recommended, name: "Recommended")
        context.insert(recommended)
        phase.addTrainingMix(recommended)

        let selected = TrainingMix(kind: .selected, name: "Selected")
        context.insert(selected)
        phase.addTrainingMix(selected)

        XCTAssertEqual(phase.recommendedTrainingMix?.name, "Recommended")
        XCTAssertEqual(phase.selectedTrainingMix?.name, "Selected")
    }

    func testGoalPrioritySupportingCaseRoundTrips() throws {
        let componentID = UUID()
        let component = TrainingMixComponent(id: componentID, label: "Conditioning", priority: .supporting, frequency: SessionFrequency(target: 1))
        context.insert(component)
        try context.save()

        let reloaded = try XCTUnwrap(freshContext().fetch(FetchDescriptor<TrainingMixComponent>(predicate: #Predicate { $0.id == componentID })).first)
        XCTAssertEqual(reloaded.priority, .supporting)
    }
}
