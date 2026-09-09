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
                // R6 Appearance Consistency Gate: `Theme.Color(light:dark:)`
                // is a dynamic `UIColor` keyed on `traits.userInterfaceStyle`
                // alone — with no override anywhere, every token silently
                // followed the HOST device's own system Light/Dark setting,
                // so the identical build rendered TrainingOS's approved dark
                // palette on a device set to system Dark and its untested
                // light-token fallback on a device set to system Light. The
                // approved artifact's own "Mode" token is explicit: "Dark
                // first / Light mode after review" — light mode is future
                // work, not a currently-supported, currently-reviewed
                // appearance. This is the one root/theme-boundary
                // authority: forcing dark here overrides every dynamic
                // token app-wide without touching a single screen, adding
                // per-view `.preferredColorScheme` calls, or duplicating any
                // color locally. Revisit only when Light Mode is actually
                // designed and reviewed (the artifact's own stated
                // trigger) — `Theme`'s light branch stays in place,
                // unused but not deleted, for that future work.
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}
