# Training OS — architecture (foundation pass)

This document describes what exists after the Stage 1/2 foundation pass:
project setup, domain model, persistence, a minimal Progression Engine, and
a three-tab UI shell over seeded data. See the root `CLAUDE.md` for the
non-negotiable rules this structure exists to enforce, and
`project/Training OS Handoff.dc.html` for the full product specification.

## Folder structure

```
app/
  TrainingOS.xcodeproj/        Xcode project (app + test targets)
  TrainingOS/
    App/                       @main entry point, app-level wiring only
    Domain/
      Entities/                SwiftData @Model types — the persisted graph
      ValueTypes/               Enums and other plain value types
    Persistence/                ModelContainer/schema construction — the only
                                place a container is built
    Engines/                    Pure, dependency-free business rules
                                (ProgressionEngine, ScoringEngine)
    Application/
      UseCases/                 Orchestrates engines + persistence
                                (e.g. "record this set", "record this result")
      ViewModels/                @Observable types that query SwiftData and
                                expose display-ready state to Views
      Seed/                      Development dataset builders
    Integrations/                Reserved for HealthKit and other external
                                data sources — empty in this pass
    UI/                          SwiftUI Views and design tokens only
    Resources/                   Assets.xcassets
  TrainingOSTests/                XCTest target (app-hosted, see below)
```

### Why this split

Each layer has exactly one reason to change:

- **Domain** changes when the shape of the training model changes.
- **Engines** change when a progression/scoring rule changes. They know
  nothing about SwiftData or SwiftUI — inputs and outputs are plain Swift
  value types (`ProgressionInput`/`ProgressionOutput`,
  `SetTarget`/`SetOutcome`), so they're testable with zero setup and
  reusable if the persistence layer is ever replaced.
- **Application** changes when a workflow changes (how a logged set becomes
  a PR, what seed data proves). This is where SwiftData and the Engines
  meet — it decides *when* to call the engine and *what* to persist, but
  contains no progression math itself.
- **UI** changes when the screen changes. Views hold no business logic:
  they call a ViewModel's `load(modelContext:)` and render whatever comes
  back. If a View needs an `if` statement to decide a training rule, that
  logic is in the wrong layer.

## Domain boundaries

The domain graph follows the handoff's hierarchy exactly:
`Goal -> TrainingPlan -> TrainingPhase -> ProgramInstance -> Session ->
WorkoutBlock -> ExercisePrescription -> SetPrescription`, with
`ProgramDefinition -> TrainingWeek` as the separate, reusable methodology
side (never containing performance data), and `PerformanceProfile ->
ExercisePerformanceProfile -> SetResult/PersonalRecord` as the permanent,
program-independent history side.

Two invariants are enforced structurally, not just by convention:

1. **A ProgramDefinition/ProgramInstance can never hold performance data.**
   There is no field on either type that stores a result, and the
   relationship from `ProgramInstance` to `Session` is `.nullify`, not
   `.cascade` — deleting the instance clears the back-reference on its
   Sessions but leaves the Sessions (and everything they logged) intact.
2. **A SetResult always has a permanent home.** Every `SetResult` links to
   an `ExercisePerformanceProfile` via a `.cascade` relationship — the
   *only* cascade in the app that touches performance data, and it only
   fires if the whole `PerformanceProfile` (i.e. the user's account) is
   deleted. Every other path to a `SetResult` (`SetPrescription`,
   `ExercisePrescription`) is `.nullify`.

`PerformanceProfileContinuityTests.swift` asserts both directly, including
by literally deleting a `ProgramDefinition`/`ProgramInstance` mid-test and
checking the logged history survives. `DELETE_RULE_MATRIX.md` documents
every relationship's delete rule and why; `DeleteRuleMatrixTests.swift` is
its exhaustive test coverage.

## Relationship ownership convention

Every relationship is established from exactly one side, via a method on
the owning model — `Day.addSession(_:)`, `Session.addBlock(_:)`,
`WorkoutBlock.addPrescription(_:)` / `.attachResult(_:)`,
`ExercisePrescription.addSetPrescription(_:)` / `.addLoggedSetResult(_:)`,
`SetPrescription.addResult(_:)`, `ExercisePerformanceProfile.addSetResult(_:)`
/ `.addPersonalRecord(_:)`, `PerformanceProfile.addExerciseProfile(_:)`,
`Goal.addPlan(_:)`, `TrainingPlan.addPhase(_:)`,
`TrainingPhase.addProgramInstance(_:)`, `ProgramDefinition.addWeek(_:)`,
`ProgramInstance.addSession(_:)`, `User.attachProfile(_:)` /
`.attachPerformanceProfile(_:)` / `.addGoal(_:)`, `Exercise.addAlias(_:)`.

Stage 3C's new relationships follow the identical convention:
`WorkoutBlock.attachSteadyStatePrescription(_:)` / `.attachIntervalPrescription(_:)`
/ `.attachFunctionalFitnessPrescription(_:)` / `.attachSteadyStateResult(_:)`
/ `.attachIntervalResult(_:)` / `.attachFunctionalFitnessResult(_:)`,
`IntervalResult.addRepResult(_:)`, `FunctionalFitnessPrescription.addMovement(_:)`,
`FunctionalFitnessResult.addPerformedMovement(_:)`,
`ActivityPerformanceProfile.addSteadyStateResult(_:)` / `.addIntervalResult(_:)`
/ `.addPersonalRecord(_:)`, `BenchmarkPerformanceProfile.addResult(_:)` /
`.addPersonalRecord(_:)`, `PerformanceProfile.addActivityProfile(_:)` /
`.addBenchmarkProfile(_:)`, `TrainingPhase.addProgramInstance(_:)` (unchanged
signature; priority is set on the `ProgramInstance` itself before or after
calling it).

**Application code must never set both sides of a relationship manually**
(e.g. `block.session = session` *and* `session.blocks.append(block)`).
Each `addX` method mutates exactly one stored property; SwiftData
maintains the declared inverse. `RelationshipOwnershipTests.swift` checks
this holds — including through a save + fresh-`ModelContext` refetch, not
just in-memory — for every relationship that has one of these methods.

A few relationships are plain properties with no `@Relationship` annotation
on the *referencing* side (`ExercisePrescription.exercise`,
`PersonalRecord.sourceSetResult`/`.sourceWorkoutResult`,
`ProgramInstance.programDefinition`, `Recommendation.exercisePrescription`).
Application code still only ever sets one side for these — a direct
assignment is correct there, not an exception to the rule. But the first
Xcode verification pass found that two of them (`sourceSetResult`/
`sourceWorkoutResult` and `programDefinition`) needed a declared inverse
*somewhere* anyway — a plain to-one reference to a `@Model` type with no
inverse anywhere in the schema doesn't nullify cleanly on delete, it throws
a Core Data validation error. The inverse now lives on the referenced side
(`SetResult.personalRecord`/`WorkoutResult.personalRecord`,
`ProgramDefinition.instances`) purely so the delete rule has something to
run against; nothing reads those properties. See DELETE_RULE_MATRIX.md for
the full picture — `ExercisePrescription.exercise` and
`Recommendation.exercisePrescription` remain genuinely inverse-free
because nothing in this pass deletes a canonical Exercise or a
Recommendation's target out from under active data yet.

## Ordering strategy

Every relationship where product behavior depends on order has an explicit
`sortIndex: Int` (or, for `SetResult`, the pre-existing domain field
`completedAt`, which is real chronological data, not persistence
bookkeeping): `Session.sortIndex` (position within a Day),
`WorkoutBlock.sortIndex` (position within a Session),
`ExercisePrescription.sortIndex` (position within a Block),
`SetPrescription.sortIndex` (position within a movement),
`TrainingPhase.sortIndex` (position within a Plan), and
`TrainingWeek.sortIndex` (position within a ProgramDefinition).

Each `addX` method assigns `sortIndex` automatically (`children.count` at
append time), so callers never compute or pass one. Each parent exposes an
`orderedX` computed property (`orderedSessions`, `orderedBlocks`,
`orderedPrescriptions`, `orderedSetPrescriptions`, `orderedPhases`,
`orderedWeeks`) that sorts by `sortIndex` — **application code must always
read through these, never through the raw relationship array**, because
SwiftData does not guarantee a to-many relationship's collection order
survives a save/refetch cycle. `RelationshipOwnershipTests.swift` and
`PersistenceRoundTripTests.swift` both verify ordering specifically after a
save + fresh-context refetch, not just immediately after construction.

Reordering after the fact (e.g. drag-to-reschedule a Session, or a program
edit that reorders Blocks) is not implemented in this pass — `addX` always
appends at the end. That's a real gap, not a hidden one: revisit before
building any UI that lets a user reorder something.

## Persistence model

`Persistence/PersistenceController.swift` is the single place the SwiftData
`Schema` is declared and the only place a `ModelContainer` is constructed —
`makeAppContainer()` for the real on-disk store, `makeInMemoryContainer()`
for previews and tests. Nothing else should call `ModelContainer(...)`
directly; that keeps the schema from drifting between the app, previews and
tests.

ViewModels currently fetch broadly (`FetchDescriptor<T>()` with no
predicate) and filter/sort in plain Swift. This is a deliberate
simplification for seed-data scale, not a recommended pattern at real data
volumes — see "Known gaps" below.

## Source-of-truth rules

- **PerformanceProfile is the only source of truth for what a user has
  ever done.** UI, engines and future analytics should read from it, never
  reconstruct history by walking Sessions.
- **ProgramDefinition is the only source of truth for methodology**
  (weeks, deload placement, adherence mode). It is reusable across users
  and phases and must stay free of anything user-specific.
- **A Recommendation is a persisted opinion, not a fact.** It always
  carries a reason code and an inputs summary (handoff section 6: "a
  recommendation without inputs to display is a bug").

## How the engines interact

```
ExercisePrescription + SetPrescription[]        (target)
ExercisePerformanceProfile.setResults           (history)
                    |
                    v
        ProgressionInput (plain struct)
                    |
                    v
         ProgressionEngine.recommend(_:)   <-- pure, no persistence access
                    |
                    v
        ProgressionOutput (plain struct)
                    |
                    v
   Application layer decides whether to persist a Recommendation
```

`RecordSetResultUseCase` and `RecordWorkoutResultUseCase` are the only
places that create `SetResult`/`WorkoutResult` rows and decide whether they
set a `PersonalRecord`, via `ScoringEngine`. Both the seeded dataset and
(later) the live logging UI must go through these use cases — never insert
a `SetResult` directly from a View or from `SeedScenarios` ad hoc, or the
"one place decides how a set becomes a PR" guarantee breaks.

`DoubleProgressionEngine` is the only `ProgressionEngine` implementation in
this pass. It only produces `CALIBRATION_REQUIRED`, `LOAD_INCREASE`,
`REP_INCREASE` and `HOLD` — the remaining progression reason codes exist on
`ProgressionReasonCode` (so Recommendations that reference them later don't
need a schema change) but are not yet reachable from any engine.

## Stage 3C: generalized domain types across modalities

Stage 3B validated that Aerobic/Running/Interval/Functional-Fitness/
Concurrent-scheduling modalities need a generalized domain model; Stage 3C
implements the three changes that validation found necessary *before* any
concrete training engine gets built, plus their minimum supporting types.
Full rationale is in `STAGE3B_ARCHITECTURE_DECISIONS.md`; this section
documents what actually exists in code now, and full implementation
detail (migration impact, persistence decisions, tests) is
`STAGE3C_IMPLEMENTATION_REPORT.md`.

### Typed `BlockPrescription`/`BlockResult`

`WorkoutBlock` gained three new, additive, cascading prescription
relationships (`steadyStatePrescription`, `intervalPrescription`,
`functionalFitnessPrescription` — `Domain/Entities/`) and three new,
additive, **nullifying** result relationships (`steadyStateResult`,
`intervalResult`, `functionalFitnessResult`). `ExercisePrescription` and
`WorkoutResult` are completely unchanged. `WorkoutBlock.blockPrescription`/
`.blockResult` are computed properties that synthesize a
`BlockPrescription`/`BlockResult` enum (`Domain/ValueTypes/`) from
whichever typed relationship is actually populated — this is the "cleaner
boundary between persisted entities and domain value types" pattern:
persistence stores typed relationships per block type; application/engine
code reasons about one typed enum.

**The new result relationships are `.nullify`, not `.cascade`** — this is
the one place in this generalization where getting the delete rule wrong
would have silently reintroduced a permanence bug. See
`DELETE_RULE_MATRIX.md` and the doc comment on `WorkoutBlock.steadyStateResult`.

### `IntensityTarget` design (Stage 3C §6, documented here as required)

Stage 3B found intensity targets (HR zone, pace, power, RPE, cadence,
stroke rate, percent-of-reference) to be an open, growing set — a real
cross-modality proof surfaced a missing case (rowing's stroke rate) during
validation itself. The chosen design (`Domain/ValueTypes/IntensityTarget.swift`)
is a single `Codable`, `Equatable` enum with one case per target *kind*,
each carrying a small, named, unit-specific value type (`Pace`, `Power`,
`HeartRateZone`, `PowerZone`, or a plain `ClosedRange<Int/Double>` for
RPE/cadence/stroke-rate/percentages) — never a raw `Double` and never a
generic metrics dictionary. Adding a new case (the next modality's native
unit) is additive and safe: nothing in the codebase exhaustively switches
over `IntensityTarget` without a fallback, so a new case never breaks an
existing `switch`. This is the same reasoning that already governs
`ProgressionReasonCode` ("codes are additive: never rename or repurpose
one") and `WorkoutBlockType`, applied to a target-value type instead of an
identifier enum.

### `TrainingStressProfile`

A coarse, deterministic, hand-seeded classification (`overallIntensity`,
`systemicDemand`, `lowerBodyLoad`, `upperBodyLoad`, `impactLoading`,
`metabolicDemand`, `durationClassification`, `modality`, `recoveryDemand`
— all small closed enums, never a computed score) stored as an optional
attribute on `WorkoutBlock`. No automatic estimation exists or is planned
for this pass — every value in every test/seed scenario that sets one is
hand-authored. Exists solely so a future `ConcurrentScheduler` has a
uniform vocabulary to read regardless of which `ProgrammingSystem`
produced a block.

### `TrainingPhase`/`ProgramInstance` composition (the "ProgramJourney" generalization)

The phase-*sequencing* concept explored in Stage 3B docs needed no new
entity — `TrainingPlan.orderedPhases` already provides it. The one real
schema change Stage 3B's validation found necessary was **within** a
single phase: a `TrainingPhase` can now compose a primary system with zero
or more secondary Modules. This is `ProgramInstance.priority: GoalPriority`
(`.primary`/`.secondary`, defaulting to `.primary` so every pre-existing
call site is unaffected) plus two computed properties on `TrainingPhase`
(`primaryInstance`, `secondaryInstances`). No `HybridProgramDefinition` or
other special-case type was introduced; `TrainingPhase` still performs no
scheduling logic itself.

### Progression/decision-engine boundary

`Engines/BlockProgressionEngine.swift` generalizes `ProgressionEngine`'s
shape (current state + history → recommendation + reason code) to carry
`BlockPrescription`/`BlockResult` instead of strength-only types.
`DoubleProgressionEngine` itself is untouched; `StrengthBlockProgressionEngine`
is a thin adapter proving the generalized contract is satisfiable by the
existing logic without rewriting it. Functional Fitness's "next workout"
is not a parametric adjustment of the current one — Stage 3B's own
finding — so it gets a deliberately separate, higher-level contract,
`Engines/ProgrammingDecisionEngine.swift` (no concrete conformer in this
pass; the boundary is settled, the generator is not built).

### New `PerformanceProfile` siblings

`ActivityPerformanceProfile` (indexed by `ActivityType` + an optional
`performanceContext` string, e.g. "5K" vs. general Running) and
`BenchmarkPerformanceProfile` (indexed by a new `BenchmarkDefinition`
catalog entity, structurally identical to `Exercise`'s canonical-ID
pattern) are new siblings of `ExercisePerformanceProfile`, which is
completely unchanged. Both are permanent and program-independent in
exactly the same way, enforced by the same relationship shape
(`PersonalRecord` gained two more optional parent fields, mirroring its
existing three-parent `SetResult`-adjacent shape).

## Known gaps and deliberate simplifications

These are places the domain model or code takes a simplified shape on
purpose, called out here so they're a decision record, not a surprise:

- **DURATION_AT_HR and PACE_AT_HR_DESC scoring are not implemented.**
  `ScoringDirection` only models `higherIsBetter` / `lowerIsBetter` /
  `completionBased` / `none`. Steady-state and interval results are stored
  but never evaluated for a PR (`scoringDirection: .none`) because a
  correct comparison needs to normalize against heart rate, which is out
  of scope for this pass.
- **`WorkoutResult` is still one flexible model with optional fields per
  block type, for the Stage 1-2 `.amrap`/`.emom`/`.forTime`/`.steadyState`/
  `.intervals` scenarios that already shipped.** This is the gap Stage 3C
  actually revisited — see "Typed BlockPrescription/BlockResult" below —
  but the fix is additive (new sibling types for new blocks), not a
  rewrite of `WorkoutResult` or the scenarios already built on it.
- **Block-level parameters (time caps, EMOM interval length) are still
  flat optional fields on `WorkoutBlock`** for that same legacy path.
  `SteadyStatePrescription`/`IntervalPrescription`/
  `FunctionalFitnessPrescription` are the typed alternative for new blocks
  — again additive, not a replacement of the existing fields.
- **Fran is no longer modelled as a canonical Exercise — consolidated in
  Stage 4E.** This bullet used to document exactly that dual
  representation as a deliberately-deferred Stage 3C gap; it's resolved
  now. `SeedScenarios.forTimeBenchmarkSession` builds Fran through
  `FunctionalFitnessPrescription`/`FunctionalFitnessResult`/
  `BenchmarkDefinition`/`BenchmarkPerformanceProfile` exclusively — see
  `STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E §5 for the full migration
  account.
- **Ad hoc AMRAP/EMOM blocks don't carry a PersonalRecord.** Only a named,
  repeatable benchmark has a stable identity to compare against; a one-off
  12-minute AMRAP has nothing to be a "record" relative to yet. This is
  unchanged by Stage 3C's `BenchmarkDefinition` addition — a generated
  Functional Fitness workout is still not automatically a tracked
  benchmark (see "Typed BlockPrescription/BlockResult" below).
- **ViewModels fetch-all-and-filter in Swift** rather than using SwiftData
  `#Predicate` queries, to avoid depending on predicate-macro behavior with
  custom `Codable` enums that couldn't be verified against a real Xcode
  toolchain in this pass. Safe at seed-data scale; revisit with real
  `FetchDescriptor` predicates once datasets grow.
- **No custom fonts are bundled.** The handoff specifies Chivo and Roboto
  Mono; no font files were part of the export, so `UI/Theme/Theme.swift`
  falls back to the system font and system monospaced-digit font.
- **Light-mode `positive`/`attention` colors are assumed equal to dark
  mode.** The handoff's visual system section only restates
  ground/surface/primary/text/secondary for light mode.
- **This sandbox has no Xcode/Swift toolchain and never will** (Linux-only
  environment; SwiftData doesn't exist outside Apple platforms). Every
  pass authored here — including Stage 3C's domain generalization — is
  written and statically self-reviewed without a compiler: every `addX`/
  `attachX` call site cross-checked against its definition, every
  relationship's inverse traced by hand, the project file re-parsed and
  every file reference verified to resolve on disk after each
  regeneration. **The project itself has been compiled and tested for
  real**, though — via the product owner's local Mac, running a local
  Claude Code session against this same repository, per
  `LOCAL_XCODE_VERIFICATION.md`. That local loop is how every Swift change
  in this repository is actually verified; treat any change landed here
  without a corresponding local build/test report as unverified until one
  arrives, not as "probably fine because it was reviewed carefully."
  **Stage 4 onward is the exception**: it is implemented, built and
  tested directly against the real Xcode toolchain and SwiftData runtime,
  in the same local session that runs the app — not statically authored
  and verified later. See `STAGE4_IMPLEMENTATION_REPORT.md`.

## Template graph vs. execution graph (Stage 4)

A generated `ProgramDefinition` (e.g. `HypertrophyProgramGenerator`'s
output) has two distinct, non-overlapping graphs hanging off it, and code
must never conflate them:

- **Template graph** — the reusable methodology, generated once and
  treated as frozen: `ProgramDefinition -> TemplateSession ->
  WorkoutBlockTemplate -> PrescriptionTemplate -> ExerciseSlot`. Carries
  rule *parameters* only ("4x5-6 @ 2 RIR, load rule = X"), never a
  resolved number. `TemplateSession` attaches directly to
  `ProgramDefinition`, not to an individual `TrainingWeek` — the
  week-by-week progression already lives on `PrescriptionTemplate`'s rule
  arrays (`RMBasedLoad.laterWeekMultipliers`,
  `StrengthProgressionRules.repGoalSchedule`), and deload behavior is a
  rule (`deloadWeightAction`/`deloadRepAction`) keyed off
  `TrainingWeek.isDeload`, not a separately-templated week. Duplicating
  the session/block/prescription graph once per week would be redundant
  with that design — this was corrected during Stage 4A's own
  implementation before any generator code shipped against the wrong
  shape (see `STAGE4_IMPLEMENTATION_REPORT.md` §1). `TrainingWeek` itself
  is unchanged since Stage 1-2: a pure week marker
  (`sortIndex`/`isDeload`), never a content container.
- **Execution graph** — one user's dated reality, materialized from the
  template on demand: `ProgramInstance -> Day -> Session -> WorkoutBlock
  -> ExercisePrescription -> SetPrescription`. Carries resolved numbers
  ("92.5 kg for Stefan"), computed by a pure rule engine
  (`StrengthProgressionEngine`/`SourceCompatibleDeloadStrategy` — renamed
  from `HypertrophyProgressionEngine` in Stage 4B once Powerlifting
  started sharing it) from the template's rules plus runtime inputs the
  template cannot know
  (a tested RM, an `EquipmentProfile`, a live autoregulation rating).
  Materialization is inherently incremental, one week at a time — later
  weeks need the *actual* outcome of the previous week as input, which
  doesn't exist until a user has actually trained it
  (`StrengthMaterializer`'s own scope note).

A `ProgramDefinition`'s template graph, once any `ProgramInstance`
references it, is treated as frozen by convention: if generator logic
changes, it produces a new `ProgramDefinition`/`generatorVersion`, never
mutates an existing one in place (`ProgramDefinition.generatorVersion`'s
doc comment) — an old configuration must never silently start producing a
different program structure underneath an already-running instance.

## Steady-state template graph (Stage 4C)

`WorkoutBlockTemplate` carries one typed child relationship per
modality, exactly mirroring `WorkoutBlock`'s own execution-side shape:
`prescriptionTemplates` (strength, Stage 4A) and
`steadyStatePrescriptionTemplate` (endurance, Stage 4C addition — closes
the gap this file's Stage 4A section originally flagged as deferred).
`SteadyStatePrescriptionTemplate` stores `primaryIntensity`/
`secondaryIntensity` as direct top-level `IntensityTarget?` properties
(the shape already proven safe by Stage 3C's `SteadyStatePrescription`
itself) and flattens its progression rule
(`SteadyStateProgressionRules`) into scalar fields exactly like
`PrescriptionTemplate` already does for `StrengthProgressionRules` — see
`STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4C section §4 for why a
per-week `[IntensityTarget]` array was deliberately avoided rather than
assumed safe.

`SteadyStateMaterializer`, unlike `StrengthMaterializer`, materializes
every week of a `ProgramDefinition` in one call — every steady-state
dimension this pass implements (duration/distance/intensity-zone/
recovery) is a deterministic function of week index alone, with no live
per-week rating dependency the way strength's autoregulation has. This is
a genuine architectural difference between the two systems, not an
inconsistency.

Frequency progression (a program having more Sessions per week later in
a mesocycle) is modeled at the `TemplateSession` level
(`activeFromWeek: Int`), not inside any per-block engine — see
`TemplateSession.activeFromWeek`'s own doc comment for the explicit
"this is not a `BlockProgressionEngine` concern" boundary.

## Substitution architecture (Stage 4C, extended Stage 4D)

See `SUBSTITUTION_MODEL.md` for the full contract. In one sentence: a
template slot's default selection (`ExerciseSlot.resolvedExercise`/
`SteadyStatePrescriptionTemplate.preferredActivityType`/
`IntervalPrescriptionTemplate.preferredActivityType`) can be overridden
per `ProgramInstance` going forward
(`SlotSelectionOverride`/`ActivitySelectionOverride`, resolved by the
materializer at the moment it builds a new Session) or overridden for a
single already-materialized Session directly
(`ExercisePrescription.exercise`/`SteadyStatePrescription.activityType`/
`IntervalPrescription.activityType`, no new persisted type at all) —
never by mutating the template graph itself.

`ActivitySelectionOverride` is keyed to the owning `WorkoutBlockTemplate`
(a Stage 4D correction — originally keyed directly to
`SteadyStatePrescriptionTemplate`, before a second endurance template
type existed) rather than to either specific endurance template type,
via a small `ActivitySubstitutionTemplate` protocol
(`preferredActivityType`/`allowedActivityTypes`) both
`SteadyStatePrescriptionTemplate` and `IntervalPrescriptionTemplate`
conform to — one override mechanism serving both systems, not a
duplicate entity per system.

## Interval template graph (Stage 4D)

`WorkoutBlockTemplate` carries a third typed child relationship,
`intervalPrescriptionTemplate`, alongside `prescriptionTemplates`
(strength) and `steadyStatePrescriptionTemplate` (continuous endurance) —
the same "one typed relationship per modality" pattern extended once
more. `IntervalPrescriptionTemplate` stores `workIntensity`/
`recoveryIntensity` as direct top-level `IntensityTarget?` properties
(proven-safe) and flattens its progression rule
(`IntervalProgressionRules`, including its **ordered** `priority:
[IntervalProgressionStep]` list) into parallel primitive arrays rather
than storing an array of the struct directly — no existing test in this
codebase proves an array of a multi-field struct round-trips safely, so
this pass didn't assume it does.

Warm-up and cool-down reuse the ordinary ordered `WorkoutBlock`
architecture (`Session -> WarmUp Block -> Interval Block -> CoolDown
Block`), the warm-up/cool-down blocks themselves plain `.steadyState`
prescriptions — never a field buried inside the interval prescription
itself.

`IntervalMaterializer`, unlike `SteadyStateMaterializer`, always resolves
one week at a time: an interval template's rules may set
`requiresSuccessfulCompletionToProgress`, in which case the materializer
throws rather than fabricate a future week's progression from calendar
position alone.

## Functional Fitness template graph and pipeline (Stage 4E)

`WorkoutBlockTemplate` carries a fourth typed child relationship,
`functionalFitnessPrescriptionTemplate`. `FunctionalFitnessPrescriptionTemplate`
stores `stimulus: Stimulus` and `format: WorkoutFormat` as direct top-
level properties (proven persistence-safe since Stage 3C — see
`STAGE4_IMPLEMENTATION_REPORT.md`'s Stage 4E §1) and owns a cascade
collection of `FunctionalFitnessMovementSlotTemplate` rows — one per
`ModalityCount` entry in the target stimulus's `movementModalityMix`.

**Movement slots reuse `ExerciseSlot` directly**, generalized with two
new constraint dimensions (`allowedMovementFunctions: [MovementFunction]`,
`allowedModalities: [FunctionalModality]`) alongside the pre-existing
`allowedTargets: [MuscleGroup]`. `FunctionalFitnessMovementSlotTemplate`
is the Functional Fitness analogue of `PrescriptionTemplate` — it owns
one `ExerciseSlot` plus its own per-movement prescription target fields
(reps/calories/distance/load/minuteSlot/repScheme), exactly mirroring how
`PrescriptionTemplate` owns one `ExerciseSlot` plus strength-specific
rule fields. This means Functional Fitness movement-slot substitution
inherits `SubstitutionValidator`/`SlotSelectionOverride`/
`SubstituteExerciseUseCase` for free — see `SUBSTITUTION_MODEL.md`.

**The five-stage pipeline** (Stage A: target stimulus, B: format, C:
movement slots, D: concrete exercise selection, E: stimulus validation)
splits across generator and materializer the same way Stage 4D split
calendar-driven vs. performance-gated interval progression: Stages A/B
are configuration inputs, Stage C runs at generation time (producing the
persisted template), and Stages D/E run at `FunctionalFitnessMaterializer`
time, since they depend on live exposure history and available
candidates the generator can't know in advance. `FunctionalFitnessDecisionEngine`
(the first concrete `ProgrammingDecisionEngine` conformer) resolves
exposure-informed stimulus variance between Stage C and Stage D; see
`FUNCTIONAL_FITNESS_ENGINE.md` for the full pipeline contract.

## ConcurrentScheduler and Training Mix (Stage 4F)

Every prior Stage 4 system (`StrengthMaterializer` and its four siblings)
already places its own Sessions onto naive, sequential calendar dates —
each materializer's own doc comment says so explicitly ("calendar
placement is naive by design... real preferred-day/availability
placement is ConcurrentScheduler's job"). Stage 4F is that job, and nothing
more: it operates entirely on the **execution graph**, never the template
graph, and it consumes real, already-materialized `Session`s from one or
more `ProgramInstance`s — it does not generate methodology, does not
prescribe intensity, and does not pick exercises.

**`TrainingMix`/`TrainingMixComponent`** (new `@Model` types, cascade off
`TrainingPhase`) describe *what* to train — a typed composition of
components, each with its own priority/frequency/flexibility/scheduling
preferences — independent of *when* it lands on the calendar. A
`TrainingMix` never duplicates `ProgramInstance` data; `TrainingMixComponent.programInstance`
is optional precisely because a `.recommended` mix's components may
describe a composition before any instance exists for them. See
`TRAINING_MIX.md`.

**`ConcurrentScheduler`** (a pure, stateless enum in `Engines/`, matching
every other engine's "typed input in, typed output + reason codes out"
shape) answers *where* — it takes `[ScheduledProgramInput]` (a component
plus its own already-ordered Sessions) and `SchedulingConstraints`
(availability + a tactical window + soft interference rules) and returns
a `ScheduleProposal`: a transient, non-persisted value type, never a
mutation. The Engine-recommendation -> Explanation -> User-approval
pattern this project already uses elsewhere applies here too —
`AcceptScheduleProposalUseCase` is the only thing that turns an approved
proposal into real `Day`/`Session` state, by re-parenting Sessions the
materializer already created and stamping `Session.schedulerVersion`
(mirroring `ProgramDefinition.generatorVersion`'s "never reinterpret
already-accepted state" precedent). See `CONCURRENT_SCHEDULER.md` for the
full placement algorithm, its reason-code vocabulary, and its documented
limitations.

**`GoalAlignmentEvaluator`** scores a `(TrainingMix, ScheduleProposal)`
pair as a qualitative rating (`GoalAlignmentRating`) plus a fully
transparent list of boolean `GoalAlignmentFactor`s — never a fabricated
numeric percentage, matching `TrainingStressProfile`'s own "no fake
precision" design principle applied one layer up.

## Scheduler alignment and priority hardening (Stage 4G)

Before any Long-Term Planner work could start, two Stage 4F weak points
were hardened structurally rather than patched:

- **`ScheduleIssue`** (new `Domain/ValueTypes/ScheduleIssue.swift`) is a
  typed vocabulary (`ScheduleIssueCode`/`IssueSeverity`) for every
  compromise/failure a `ScheduleProposal` can contain.
  `ScheduleProposal.warnings` became a **computed** property
  (`issues.map(\.reason)`) instead of an independently-stored array — so
  `GoalAlignmentEvaluator` (rewritten this stage to read only `issues`/
  `placements`) cannot drift out of sync with display text, structurally,
  not by convention.
- **`ConcurrentScheduler`'s placement algorithm** was rewritten from a
  single priority-tier-sorted pass into a genuine two-phase,
  contention-aware algorithm (`buildPhases`/`processingOrder` in
  `Engines/ConcurrentScheduler.swift`) — required minimums are guaranteed
  across every component before any component's "extra" sessions are
  attempted, and `.primaryGoalPriority` is now tagged only when a real,
  still-pending, different-component session could also have used the
  winning day. `Session.isKeySession: Bool` (new field) lets one
  component's own sessions carry different importance (a running week's
  long run vs. an easy run) without a new planner.
- **`SchedulingPipeline`** (new `Engines/SchedulingPipeline.swift`) is the
  minimal planner-facing entry point — `propose(mix:inputs:constraints:)`
  bundles `schedule()` + `evaluate` into the one call a future planner
  needs, never exposing scheduler internals or `warnings`.

`ConcurrentScheduler.currentVersion` bumped to `2` — the algorithm change
could alter results for identical inputs (e.g. a mix with an explicit
`SessionFrequency.minimum` narrower than its target now schedules
differently), so an already-accepted Stage 4F `Session.schedulerVersion == 1`
must never be silently reinterpreted under the new logic. Full account:
`GOAL_ALIGNMENT.md`, `CONCURRENT_SCHEDULER.md` §4/§6/§14-16.
