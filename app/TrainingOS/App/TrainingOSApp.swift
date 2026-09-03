import SwiftUI
import SwiftData

@main
struct TrainingOSApp: App {
    let container: ModelContainer

    init() {
        self.container = PersistenceController.makeAppContainer()
        // Stage V1.Checkpoint 1: production first launch no longer seeds a
        // demo Goal/Plan/Sessions — `AppRootView` routes a real athlete
        // through onboarding instead (`AppRootStateResolver`). The former
        // automatic `SeedAnnualPlanJourney` call (and the plain
        // `existingUserCount == 0` check it used) is exactly the fragile,
        // "any User row exists" predicate this checkpoint's own audit
        // flagged — `AppRootStateResolver.resolve` replaces it with the
        // real prerequisite check (`.active` Goal + default
        // `TrainingEnvironment`). `SeedDataProvider.seedAll`/
        // `SeedAnnualPlanJourney.seed` remain fully available to
        // tests/previews that call them directly — only this automatic
        // production invocation is removed.
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(container)
    }
}
