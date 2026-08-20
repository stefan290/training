import SwiftUI
import SwiftData

@main
struct TrainingOSApp: App {
    let container: ModelContainer

    init() {
        let container = PersistenceController.makeAppContainer()
        self.container = container

        // Foundation-pass convenience: seed once on first launch so the
        // three root screens have something to show. This is a debug/dev
        // affordance, not a feature — remove once onboarding exists.
        //
        // Seeds only the shared prerequisites (`seedPrerequisites`, not
        // the full `seedAll`) plus ONE real, use-case-driven accepted
        // journey (`SeedAnnualPlanJourney`) — a single coherent training
        // universe for this user. `seedAll`'s own 8 hand-built demo
        // scenarios remain available to tests/previews that call it
        // directly, but are deliberately never mixed into the real app's
        // Today/Week alongside the accepted plan's own real Sessions
        // (Stage 7 Slice 4 acceptance finding).
        let descriptor = FetchDescriptor<User>()
        let existingUserCount = (try? container.mainContext.fetchCount(descriptor)) ?? 0
        if existingUserCount == 0 {
            let prerequisites = SeedDataProvider.seedPrerequisites(in: container.mainContext)
            try? SeedAnnualPlanJourney.seed(
                user: prerequisites.user, performanceProfile: prerequisites.performanceProfile,
                catalog: prerequisites.catalog, context: container.mainContext
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
