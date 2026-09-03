import Foundation

/// The full "recipe" `FunctionalFitnessProgramGenerator` needs to produce
/// a template graph — the Functional Fitness sibling of
/// `HypertrophyProgramConfiguration`/`SteadyStateProgramConfiguration`/
/// `IntervalProgramConfiguration`. Deliberately just data: no rule logic
/// lives here.
struct FunctionalFitnessProgramConfiguration: Codable, Equatable {
    var daysPerWeek: Int
    var lengthWeeks: Int
    /// The program's target/desired stimulus (§2 Stage A) — the baseline
    /// every generated session aims for before any exposure-informed
    /// variance adjustment at materialization time.
    var targetStimulus: Stimulus
    var format: WorkoutFormat
    var sessionRole: SessionRole
    var varianceConstraints: VarianceConstraints
    /// §15/§42 — see `FunctionalFitnessPrescriptionTemplate.requiresRecentExposureToProgress`'s
    /// own doc comment.
    var requiresRecentExposureToProgress: Bool
    /// §20: compose a strength block ahead of the metcon block in the
    /// same Session, proving the existing generic Session/WorkoutBlock
    /// architecture needs no "CrossFitSession" special case.
    var includeStrengthBlock: Bool
    /// Stage FF.M1: threaded onto the generated `FunctionalFitnessPrescriptionTemplate`
    /// — `true` (default) defers movement-slot composition to materialization
    /// time; `false` pre-bakes slots from `targetStimulus` here at
    /// generation time exactly as before FF.M1 (for authored/benchmark-
    /// shaped content, or a test isolating a fixed slot set).
    var isDynamicallyComposed: Bool = true
}
