import Foundation

/// The single curated Running V1 built-in configuration — the Running
/// sibling of `HypertrophyBuiltInLibrary`/`PowerliftingBuiltInLibrary`,
/// but deliberately one entry, not several: R3's own product decision is
/// that V1 supports exactly 5K + 2 days/week, nothing else
/// (`RUNNING_5K_2DAY_GENERATOR_V1.md`). Adding a second entry here without
/// first adding real, source-backed generator content for it would be
/// exactly the "silently expand capability beyond what's verified"
/// mistake this engagement has corrected before (Family A's Source
/// Authority Repair) — never do it speculatively.
struct RunningBuiltInConfiguration {
    var name: String
    var configuration: RunningProgramConfiguration
}

enum RunningBuiltInLibrary {
    static let all: [RunningBuiltInConfiguration] = [
        RunningBuiltInConfiguration(
            name: "5K / 2-Day Running (Source-Backed V1)",
            configuration: RunningProgramConfiguration(distance: .fiveK, daysPerWeek: 2)
        )
    ]
}
