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
        let descriptor = FetchDescriptor<User>()
        let existingUserCount = (try? container.mainContext.fetchCount(descriptor)) ?? 0
        if existingUserCount == 0 {
            SeedDataProvider.seedAll(in: container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
        }
        .modelContainer(container)
    }
}
