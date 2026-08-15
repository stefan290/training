import Foundation

/// The 2 curated Powerlifting built-in configurations from
/// `V1_PROGRAM_LIBRARY.md` (#7-8) — plain `PowerliftingProgramConfiguration`
/// values, not separate engines; both instantiate through the same
/// `PowerliftingProgramGenerator`, parameterized by `family`/`dayCount`,
/// exactly as `HypertrophyBuiltInLibrary`'s 6 configurations share
/// `HypertrophyProgramGenerator`.
struct PowerliftingBuiltInConfiguration {
    var name: String
    var configuration: PowerliftingProgramConfiguration
}

enum PowerliftingBuiltInLibrary {
    static let all: [PowerliftingBuiltInConfiguration] = [
        PowerliftingBuiltInConfiguration(
            name: "4-Day Powerlifting Strength",
            configuration: PowerliftingProgramConfiguration(family: .b, dayCount: 4)
        ),
        PowerliftingBuiltInConfiguration(
            name: "5-Day Powerlifting Hypertrophy",
            configuration: PowerliftingProgramConfiguration(family: .c, dayCount: 5)
        )
    ]
}
