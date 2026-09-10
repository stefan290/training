import Foundation

/// The race distance a Running program targets. **Deliberately single-case
/// for V1** (`.fiveK` only) — R3's own source-gap analysis
/// (`RUNNING_GENERATOR_SOURCE_GAP_R3.md` §9) found no source evidence for
/// how RP's 10K/Half/Marathon programming differs from the 5K program
/// actually recovered, so this type intentionally does not add
/// unimplemented `.tenK`/`.halfMarathon`/`.marathon` cases yet — adding a
/// case with no real generator content behind it would misrepresent
/// capability. A dedicated type (not a raw string) is what "leaves room"
/// for V2/V3 distance expansion (`RUNNING_5K_2DAY_GENERATOR_V1.md`'s
/// backlog): a future distance is a new case here plus new source-backed
/// generator content, never a string comparison.
enum RunningDistance: String, Codable, CaseIterable {
    case fiveK
}

/// The full "recipe" `RunningProgramGenerator` needs to produce a template
/// graph — the Running sibling of `HypertrophyProgramConfiguration`/
/// `SteadyStateProgramConfiguration`. Deliberately just data: no rule
/// logic lives here. **V1 supports exactly one value of this struct**
/// (5K, 2 days/week) — `ProgramCapabilityRegistry.isRunningConfigurationSupported`
/// is the single source of truth for which combinations are real; this
/// struct itself places no restriction on construction (mirroring how
/// `HypertrophyProgramConfiguration`/`SteadyStateProgramConfiguration` are
/// plain data too) so the capability gate stays the one place that can
/// reject an unsupported combination, never a duplicated check here.
struct RunningProgramConfiguration: Codable, Equatable {
    var distance: RunningDistance
    var daysPerWeek: Int
}
