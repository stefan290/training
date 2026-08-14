import Foundation

/// The 6 curated Hypertrophy built-in configurations from
/// `V1_PROGRAM_LIBRARY.md` — plain `HypertrophyProgramConfiguration`
/// values, not separate engines (`HypertrophyProgramGenerator` handles
/// all 6 identically, parameterized by `dayCount`/`split`). The library's
/// 2 Powerlifting configurations (4-Day Powerlifting Strength, 5-Day
/// Powerlifting Hypertrophy) are Stage 4B, not listed here.
struct HypertrophyBuiltInConfiguration {
    var name: String
    var dayCount: Int
    var split: HypertrophySplit
}

enum HypertrophyBuiltInLibrary {
    static let all: [HypertrophyBuiltInConfiguration] = [
        HypertrophyBuiltInConfiguration(name: "3-Day Full Body Hypertrophy", dayCount: 3, split: .fullBody),
        HypertrophyBuiltInConfiguration(name: "4-Day Full Body Hypertrophy", dayCount: 4, split: .fullBody),
        HypertrophyBuiltInConfiguration(name: "5-Day Full Body Hypertrophy", dayCount: 5, split: .fullBody),
        HypertrophyBuiltInConfiguration(name: "5-Day Upper/Arms Focus", dayCount: 5, split: .armsShoulders),
        HypertrophyBuiltInConfiguration(name: "4-Day Lower/Leg Focus", dayCount: 4, split: .legs),
        HypertrophyBuiltInConfiguration(name: "6-Day High-Frequency Hypertrophy", dayCount: 6, split: .fullBody)
    ]
}
