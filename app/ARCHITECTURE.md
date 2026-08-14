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
- **Fran (and benchmarks generally) are still modelled as a canonical
  Exercise in the Stage 1-2 seed scenario** (`SeedScenarios.forTimeBenchmarkSession`)
  — left exactly as it was. A real `BenchmarkDefinition` entity now exists
  (Stage 3C) and is used by the new architecture-proof/round-trip tests,
  but the existing scenario was not migrated to it; see
  `STAGE3C_IMPLEMENTATION_REPORT.md` for why both are left in place rather
  than consolidated in this pass.
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
