import Foundation
import SwiftData
@testable import TrainingOS

/// Stage TE.1: shared test fixtures. `full(context:)` is a comprehensive
/// "fully-equipped gym" environment (every real `EquipmentRequirement`
/// case), inserted into the caller's own `ModelContext` — the test-suite
/// default so every pre-existing test that never cared about equipment
/// compatibility keeps its exact prior behavior (a real, resolved
/// environment satisfies every candidate, exactly as "no environment
/// check existed yet" did before TE.1). Tests that specifically exercise
/// environment compatibility build their own narrower `TrainingEnvironment`
/// instead of using this fixture.
enum TrainingEnvironmentTestSupport {
    /// Idempotent per `context`: the FIRST call for a given context
    /// inserts and saves one real "Test Full Gym" row; every later call
    /// against that SAME context reuses that already-committed row
    /// instead of inserting (and saving) another one.
    ///
    /// Both halves of this matter. The save is required because several
    /// real production call sites (`AdvanceTacticalWeekUseCase`/
    /// `TransitionPhaseUseCase`) re-fetch `TacticalMaterializationContext
    /// .trainingEnvironment` by persistent ID into an isolated scratch
    /// `ModelContext(container)`, which only ever sees already-COMMITTED
    /// store state — the same "already a real, persisted row" contract
    /// those use cases already require of their candidate `Exercise`
    /// arrays (fetched from the store, never freshly constructed
    /// in-line). The idempotency is required because a real test can
    /// call this helper AGAIN later in the same method, after inserting
    /// its own unrelated, deliberately-still-pending mutation to prove
    /// atomicity (`D-10R6-4`'s "unrelated pending mutation survives"
    /// guarantee) — an unconditional save on every call would silently
    /// commit that unrelated mutation too, corrupting the exact
    /// invariant those tests exist to prove. Reusing the same row (never
    /// re-saving once it already exists) avoids that entirely.
    @discardableResult
    static func full(context: ModelContext) -> TrainingEnvironment {
        let existing = (try? context.fetch(FetchDescriptor<TrainingEnvironment>(predicate: #Predicate { $0.name == "Test Full Gym" })))?.first
        if let existing { return existing }
        let environment = TrainingEnvironment(name: "Test Full Gym", availableEquipment: EquipmentRequirement.allCases)
        context.insert(environment)
        try? context.save()
        return environment
    }
}
