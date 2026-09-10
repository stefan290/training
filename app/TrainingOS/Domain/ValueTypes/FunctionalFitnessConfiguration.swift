import Foundation

/// FF Multi-Week V1: one deliberately-authored session's own intent within
/// a 4-week program — the flat, self-describing shape (`relativeWeek`
/// tags each entry, mirroring `RunningSourceWorkout`'s own proven-safe
/// pattern) that lets `FunctionalFitnessProgramConfiguration.weeklyPlan`
/// hold real week-to-week and session-to-session VARIATION without a
/// nested `[[T]]` array — this codebase's own `TemplateGraphPersistenceTests`
/// history (Bug 2/3) is why a flat array of a self-contained struct is
/// used instead of nesting arrays of arrays.
///
/// **What this authors vs. what stays dynamic:** an intent fixes WHAT the
/// session needs to do (stimulus, format, whether it carries a strength
/// block, its own variance window) — it never fixes WHICH exercises fill
/// it. `FunctionalFitnessMovementComposer`/`FunctionalFitnessMaterializer`
/// still resolve concrete movements/exercises at real materialization
/// time, exactly as before this addition (see
/// `FUNCTIONAL_FITNESS_MULTI_WEEK_V1.md` §9).
struct FunctionalFitnessSessionIntent: Codable, Equatable {
    /// 0-indexed relative week this session belongs to — the FF sibling
    /// of `RunningSourceWorkout.relativeWeek`, consumed the same way:
    /// `FunctionalFitnessProgramGenerator` sets the resulting
    /// `TemplateSession.activeFromWeek` to exactly this value, and
    /// `FunctionalFitnessMaterializer` reads it with EXACT equality (not
    /// the generic recurring `<=` filter) when a `weeklyPlan` is present —
    /// mirroring `RunningProgramMaterializer`'s already-shipped precedent
    /// exactly, for the identical reason: this session's content is a
    /// literal, authored, one-off week, not a numeric progression on a
    /// recurring shape.
    var relativeWeek: Int
    /// 0-indexed position among this week's own sessions — ordering only
    /// (naming/day-slot), never itself a source of variation.
    var sessionIndexInWeek: Int
    var stimulus: Stimulus
    var format: WorkoutFormat
    var includeStrengthBlock: Bool
    /// Real, non-nil constraint windows (unlike the dormant
    /// `VarianceConstraints()` the pre-V1 single-stimulus candidate used)
    /// — activates `FunctionalFitnessDecisionEngine`'s existing, already-
    /// tested variance checks for this specific session.
    var varianceConstraints: VarianceConstraints
    /// Reuses an EXISTING `SessionRole` case — never a new enum case.
    /// `.mixed` for strength+conditioning composition, `.skill` for
    /// skill-emphasis conditioning, `.functionalFitness` for the general/
    /// performance-leaning case.
    var sessionRole: SessionRole
}

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

    /// FF Multi-Week V1 addition: `nil` (every pre-existing caller/test,
    /// completely unaffected) means the original single-recurring-
    /// stimulus behavior above — one `TemplateSession` per `dayIndex`,
    /// recurring across all `lengthWeeks` weeks with the identical
    /// `targetStimulus`/`format`/`varianceConstraints`/`includeStrengthBlock`
    /// every week. Non-`nil` means a deliberately-authored, real 4-week
    /// program: `FunctionalFitnessProgramGenerator` builds one distinct
    /// `TemplateSession` per `FunctionalFitnessSessionIntent` instead,
    /// each using ITS OWN stimulus/format/strength-block/variance-window,
    /// pinned to its own exact relative week. `daysPerWeek`/`targetStimulus`/
    /// `format`/`varianceConstraints`/`includeStrengthBlock` above are
    /// simply ignored by the generator when this is non-`nil` (kept on
    /// the type only so decoding an old, already-persisted single-
    /// stimulus configuration remains lossless).
    var weeklyPlan: [FunctionalFitnessSessionIntent]? = nil
}
