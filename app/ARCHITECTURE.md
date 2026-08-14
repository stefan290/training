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

**Application code must never set both sides of a relationship manually**
(e.g. `block.session = session` *and* `session.blocks.append(block)`).
Each `addX` method mutates exactly one stored property; SwiftData
maintains the declared inverse. `RelationshipOwnershipTests.swift` checks
this holds — including through a save + fresh-`ModelContext` refetch, not
just in-memory — for every relationship that has one of these methods.

A few relationships are plain one-directional references with no declared
inverse (`ExercisePrescription.exercise`, `PersonalRecord.sourceSetResult`/
`.sourceWorkoutResult`, `ProgramInstance.programDefinition`,
`Recommendation.exercisePrescription`). These have nothing to keep in sync,
so a direct assignment is correct there, not an exception to the rule.

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

## Known gaps and deliberate simplifications

These are places the domain model or code takes a simplified shape on
purpose, called out here so they're a decision record, not a surprise:

- **DURATION_AT_HR and PACE_AT_HR_DESC scoring are not implemented.**
  `ScoringDirection` only models `higherIsBetter` / `lowerIsBetter` /
  `completionBased` / `none`. Steady-state and interval results are stored
  but never evaluated for a PR (`scoringDirection: .none`) because a
  correct comparison needs to normalize against heart rate, which is out
  of scope for this pass.
- **WorkoutResult is one flexible model with optional fields per block
  type**, not a subclass per type. SwiftData has no first-class
  polymorphism and the per-type field set is small; revisit if it grows.
- **Block-level parameters (time caps, EMOM interval length) are flat
  optional fields on WorkoutBlock**, not a nested value type, for the same
  reason.
- **Fran (and benchmarks generally) are modelled as a canonical Exercise**,
  not a dedicated `Benchmark` entity — there was no `Benchmark` type in the
  Stage 2 entity list. Its rep scheme is simplified to one `repsPerRound`
  figure per movement rather than the real 21-15-9 descending ladder.
- **Ad hoc AMRAP/EMOM blocks don't carry a PersonalRecord.** Only a named,
  repeatable benchmark (Fran) has a stable identity to compare against;
  a one-off 12-minute AMRAP has nothing to be a "record" relative to yet.
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
- **This project has still not been compiled.** Both the foundation pass
  and this validation pass were authored without access to Xcode or a
  Swift toolchain (Linux-only environment; SwiftData itself doesn't exist
  outside Apple platforms, so no amount of local tooling would have let
  this compile here regardless). Everything in this pass — the
  relationship refactor, the delete rules, the new tests — was reviewed as
  carefully as static reading allows: every `addX` call site was
  cross-checked against its definition, every relationship's inverse was
  traced by hand, and the project file was re-parsed and inspected after
  generation. None of that is a substitute for a real build. See
  `LOCAL_XCODE_VERIFICATION.md` for exact steps and what "green" means.
