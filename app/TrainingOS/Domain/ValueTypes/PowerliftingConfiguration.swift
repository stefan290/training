import Foundation

/// Which RP Powerlifting source family a `PowerliftingProgramConfiguration`
/// generates — Family B ("RP Powerlifting Strength", mixed 5RM/8RM basis,
/// 4-day) or Family C ("RP Powerlifting Hypertrophy-block", uniform 10RM
/// basis, 5-day). Deliberately not called `.strength`/`.hypertrophyBlock`
/// — those names would collide conceptually with the unrelated
/// `HypertrophyProgrammingSystem` (Family A) and invite confusing the two
/// systems, which share an engine but are otherwise unrelated products.
enum PowerliftingFamily: String, Codable, CaseIterable {
    case b
    case c
}

/// The "recipe" `PowerliftingProgramGenerator` needs — deliberately
/// minimal, matching `HypertrophyProgramConfiguration`'s shape. `dayCount`
/// is a separate field rather than hardcoded per family because Family D
/// (`PROGRAM_LOGIC_SPEC.md` §5) is direct evidence this engine is meant
/// to be end-user-reconfigurable independent of its RM-basis/rating
/// engine — but V1's only 2 built-in configurations always pair each
/// family with its own native day count (B=4, C=5).
struct PowerliftingProgramConfiguration: Codable, Equatable {
    var family: PowerliftingFamily
    var dayCount: Int
}
