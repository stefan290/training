import Foundation

/// Stable identity for an endurance activity — deliberately separate from
/// `TrainingModality` (Enums.swift), which is a coarse UI grouping/coloring
/// tag that "never drives execution logic" by its own doc comment.
/// `ActivityType` is the opposite: it *is* execution-relevant (it selects
/// units — pace vs. power vs. stroke rate — and identifies
/// `ActivityPerformanceProfile` history). Two enums covering overlapping
/// ground would be a duplicate-identity smell; they cover genuinely
/// different concerns, so both stay. `.other` exists so the model never
/// blocks an activity it hasn't anticipated, mirroring `PhaseType.custom`'s
/// existing precedent in this codebase.
enum ActivityType: String, Codable, CaseIterable {
    case running
    case cycling
    case rowing
    case skiErg
    case other
}
