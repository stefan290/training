# Stage 3C Implementation Report

Implements the three MUST-before-Stage-4 changes from
`STAGE3B_ARCHITECTURE_DECISIONS.md` — generalized `TrainingPhase`
composition, typed `BlockPrescription`/`BlockResult`, and
`TrainingStressProfile` — plus their minimum supporting types. No
concrete `ProgrammingSystem` engine (Endurance/Functional
Fitness/Concurrent Scheduler) was implemented; this is domain-model-only,
per the standing instruction.

**Compilation status, stated plainly up front:** this sandbox has no
Xcode/Swift toolchain and cannot compile or run this code. Every file
below was written and statically self-reviewed as carefully as possible
without a compiler — every relationship's inverse traced by hand
(§4 below), every `init` checked against its stored properties, every
type reference checked against where it's declared, the `.pbxproj`
regenerated and every file reference verified to resolve on disk. **None
of that is a substitute for a real build.** Per the established workflow
(`LOCAL_XCODE_VERIFICATION.md`), the actual build → test → simulator loop
must run on the product owner's local Mac. See the closing section of
this report for exactly what to run there.

## 1. Model changes

### 1.1 New value types (`Domain/ValueTypes/`, all `Codable`/`Equatable`, none persisted directly)

| File | Contents |
|---|---|
| `ActivityType.swift` | `ActivityType` (running/cycling/rowing/skiErg/other) — deliberately separate from the pre-existing `TrainingModality` (a UI grouping tag); see doc comment. |
| `IntensityTarget.swift` | `Pace`, `Power` (named, `Comparable` value types), `HeartRateZone`, `PowerZone`, `ReferenceMetric`, and `IntensityTarget` itself — the typed, extensible intensity-target design required to be documented in `ARCHITECTURE.md` (done there). |
| `WorkoutFormat.swift` | `WorkoutFormat` (AMRAP/EMOM/For Time/Rounds For Time/Chipper/Ladder/Max Load/Max Reps/Intervals), `LadderDirection`. |
| `Stimulus.swift` | `DurationDomain`, `IntensityClassification`, `LoadingClassification`, `SkillDemand`, `SystemicDemandLevel`, `FunctionalModality`, `MovementFunction`, `ModalityCount`, `Stimulus`. |
| `ScoreTypes.swift` | `ScoreType`, `ScoreDirection` (always set explicitly, never inferred), `ScoreValue`. |
| `TrainingStressProfile.swift` | `TrainingStressProfile`, `LoadLevel`. |
| `SessionRole.swift` | `SessionRole` (12 cases per Stage 3C §19; not overfit to running/lifting — `.functionalFitness`/`.skill`/`.mixed` cover the rest). |
| `BlockPrescription.swift` | `BlockPrescription` — `.exercise([ExercisePrescription])`, `.steadyState`, `.intervals`, `.functionalFitness`. Not persisted; computed by `WorkoutBlock.blockPrescription`. |
| `BlockResult.swift` | `BlockResult` + `StrengthBlockResult`. Not persisted; computed by `WorkoutBlock.blockResult`. |
| `Enums.swift` (edited) | Added `WorkoutBlockType.functionalFitness` and `GoalPriority` (primary/secondary). |

### 1.2 New `@Model` entities (`Domain/Entities/`)

**Endurance:** `SteadyStatePrescription`, `IntervalPrescription`,
`SteadyStateResult`, `IntervalResult`, `IntervalRepResult`.

**Functional Fitness:** `FunctionalFitnessPrescription`,
`FunctionalFitnessMovement`, `FunctionalFitnessResult`,
`FunctionalFitnessPerformedMovement`, `BenchmarkDefinition`.

**Performance history:** `ActivityPerformanceProfile`,
`BenchmarkPerformanceProfile`.

### 1.3 Edited existing entities (all additive — no existing field removed or retyped)

- **`WorkoutBlock`** — 6 new relationships (3 prescriptions, `.cascade`; 3
  results, `.nullify` — see §3 below for why the rule differs), 1 new
  attribute (`trainingStressProfile`), 6 new `attachX` methods, 2 new
  computed properties (`blockPrescription`, `blockResult`).
- **`ProgramInstance`** — 1 new field (`priority: GoalPriority`, defaults
  `.primary`).
- **`TrainingPhase`** — 2 new computed properties (`primaryInstance`,
  `secondaryInstances`); no stored-property change.
- **`Session`** — 1 new field (`role: SessionRole?`).
- **`PerformanceProfile`** — 2 new relationships (`activityProfiles`,
  `benchmarkProfiles`), 2 new `addX` methods, 2 new lookup helpers
  (`activityProfile(for:context:)`, `benchmarkProfile(for:)`).
- **`PersonalRecord`** — 2 new optional parent fields
  (`activityPerformanceProfile`, `benchmarkPerformanceProfile`) and 1 new
  source-traceability field (`sourceFunctionalFitnessResult`), mirroring
  its existing shape exactly.
- **`PersistenceController`** — all 12 new `@Model` types registered in
  `schema`.
- **`PerformanceProfileStore`** — 2 new get-or-create helpers
  (`activityProfile`, `benchmarkProfile`), mirroring `exerciseProfile`.

### 1.4 New Engine files (`Engines/`)

- **`BlockProgressionEngine.swift`** — `ProgressionRecommendation` enum,
  `BlockProgressionInput`/`Output`, `BlockProgressionEngine` protocol, and
  `StrengthBlockProgressionEngine` — a thin adapter proving the
  generalized contract is satisfiable by the *existing*
  `DoubleProgressionEngine` without modifying it at all.
- **`ProgrammingDecisionEngine.swift`** — `VarianceExposureRecord`,
  `VarianceConstraints`, `ProgrammingDecisionInput`/`Output`,
  `ProgrammingDecisionEngine` protocol. **No concrete conformer** — this
  settles the contract boundary for Functional Fitness's non-parametric
  "next workout," per Stage 3C §24; the generator itself is out of scope.

## 2. Why `ExercisePrescription`/`WorkoutResult`/`DoubleProgressionEngine` are untouched

Every one of these three types could have been "generalized in place."
All three were left exactly as they were, for the same reason: every
Stage 1-2 seed scenario and every existing test constructs them directly,
and none of Stage 3C's requirements needed that to change —
`BlockPrescription.exercise`/`BlockResult.strength` wrap them without
requiring a single field to move. This is the direct, load-bearing
consequence of the brief's own instruction ("Preserve ExercisePrescription
... existing strength behavior and tests must continue to pass") applied
literally rather than loosely: **zero lines in `ExercisePrescription.swift`,
`SetPrescription.swift`, `SetResult.swift`, `WorkoutResult.swift`,
`ProgressionEngine.swift`, or `DoubleProgressionEngine.swift` changed.**

## 3. The delete-rule decision that mattered most

`WorkoutBlock`'s three new *result* relationships
(`steadyStateResult`/`intervalResult`/`functionalFitnessResult`) are
**`.nullify`**, deliberately not mirroring the legacy
`WorkoutBlock.result: WorkoutResult?` relationship, which is `.cascade`.

The legacy `WorkoutResult` was never meant to be a permanent record —
its important numbers get copied into `PersonalRecord` at creation time,
so cascading it away with its block was always safe. The three new result
types are different: they *are* the permanent record
(`ActivityPerformanceProfile`/`BenchmarkPerformanceProfile` hold them
directly, not a copy). Cascading them with their block would have
silently violated CLAUDE.md rule 1 ("never reset user performance when
programs change") for every non-strength result — deleting a Session
(e.g. a program edit) would have deleted a runner's logged interval
history along with it. This was caught during design, not by a failing
test; `ModalityContinuityTests.swift` now asserts it directly (§5 below).

## 4. Persistence decisions

- **19 new relationship pairs added; every one audited by hand for a
  declared inverse on both sides**, per the Stage 2-discovered rule that a
  plain to-one `@Model` reference with no inverse anywhere throws a Core
  Data validation error on delete instead of nullifying cleanly. One
  missing inverse was actually found and fixed during this pass's own
  audit (`BenchmarkPerformanceProfile.benchmark` had no inverse until
  `BenchmarkDefinition.performanceProfiles` was added specifically to
  provide one) — see `DELETE_RULE_MATRIX.md`'s Stage 3C section for the
  complete, audited list.
- **`FunctionalFitnessMovement.exercise` and
  `FunctionalFitnessPerformedMovement.performedExercise` remain
  un-inversed**, consistent with the pre-existing, documented
  `ExercisePrescription.exercise` risk — not a new problem, two more
  instances of an already-accepted one.
- **`IntensityTarget`/`WorkoutFormat`/`Stimulus`/`ScoreValue`/
  `TrainingStressProfile` are stored as `Codable` attributes**, not
  relationships — SwiftData supports this natively for `Codable`
  value types; none of them needed to become `@Model` types themselves.
- **The `BlockPrescription`/`BlockResult` enums are never persisted.**
  They're computed properties on `WorkoutBlock`, synthesized from
  whichever typed relationship is populated. This is the "cleaner
  boundary between persisted entities and domain value types" the brief
  explicitly anticipated as an acceptable adaptation.
- **`BlockProgressionOutput`/`ProgrammingDecisionOutput` never construct a
  new `@Model` prescription.** A pure, dependency-free engine (no
  `SwiftData` import, no `ModelContext`) cannot materialize a new
  persisted row — that's Application-layer work in every case observed,
  including strength today (`ARCHITECTURE.md`'s existing "How the engines
  interact" diagram). `BlockProgressionOutput.recommendation` is a plain
  value enum (`ProgressionRecommendation`); `ProgrammingDecisionOutput.nextStimulus`
  is a plain `Stimulus` value, not a materialized `FunctionalFitnessPrescription`
  — resolving a stimulus into concrete movements is
  `FunctionalFitnessProgrammingSystem`'s own later pipeline stage, not
  this engine's job. This is a genuine, load-bearing finding from this
  pass, not a simplification for convenience: generalizing "next
  prescription" to a full `BlockPrescription` would have forced every
  future engine to either depend on `SwiftData` or fabricate throwaway
  `@Model` instances outside a `ModelContext`, neither of which is
  acceptable.

## 5. Tests added

- **`ModalityArchitectureProofTests.swift`** — all 14 required scenarios
  (Stage 3C §27), each constructing the minimum graph and asserting
  `WorkoutBlock.blockPrescription`/`.blockResult` synthesize the expected
  case. Includes the three-modality 4×4 proof (running/cycling/rowing
  sharing one `IntervalPrescription` type, differing only in
  `activityType` and the `IntensityTarget` case) and the primary/secondary
  `TrainingPhase` proof in both directions (Hypertrophy-primary and
  Running-primary), confirming neither system is hardcoded as "the real
  one."
- **`ModalityPersistenceRoundTripTests.swift`** — create → save → fresh
  `ModelContext` → fetch → assert, for `SteadyStatePrescription`,
  `IntervalPrescription`+`IntervalResult`+`IntervalRepResult`,
  `FunctionalFitnessPrescription`+`Movement`+`Result`+`PerformedMovement`
  (including the scaling case: prescribed "Toes-to-Bar" survives
  unmutated alongside a performed "Knee Raises"), `BenchmarkDefinition`+
  `BenchmarkPerformanceProfile`, and `ActivityPerformanceProfile`'s
  context-distinction (general Running vs. "5K" are proven to be two
  different persisted rows).
- **`ModalityContinuityTests.swift`** — Running performance surviving
  Program A → Program B (logging into the same `ActivityPerformanceProfile`
  across a deleted-and-replaced program), benchmark history surviving a
  deleted program, and one direct re-confirmation that the pre-existing
  exercise-continuity path is undisturbed.

39 pre-existing tests (Stage 1-3) were not modified. 3 new test files, 21
new test methods.

## 6. Migration impact

Zero breaking changes to any existing type's public shape. The only
existing call sites affected are `WorkoutBlock.init` and
`ProgramInstance.init`, both of which gained one new parameter with a
default value — every existing call site (all of `SeedScenarios.swift`,
all pre-existing tests) compiles unchanged. `PersistenceController.schema`
grew by 12 entries; this is a schema addition, not a migration of
existing stored data (no shipped users, no on-disk data to migrate — the
same reasoning `PRESCRIPTION_RESULT_MODEL_REVIEW.md` §6 already noted).

## 7. Unresolved questions / deliberately deferred

- **Whether to migrate `SeedScenarios.forTimeBenchmarkSession` (Fran-as-
  Exercise) to the new `BenchmarkDefinition`.** Left as two parallel,
  independent representations — the old scenario proves nothing was
  broken; the new tests prove the new abstraction works. Consolidating
  them is a real, reasonable follow-up, not done here to avoid touching
  already-verified Stage 1-2 code without a specific instruction to do so.
- **`ExercisePrescription.repsPerRound`/`.targetDurationSeconds`** are now
  functionally redundant with `SteadyStatePrescription`/`IntervalPrescription`
  for *new* blocks, but were kept exactly as-is per the explicit
  instruction not to flatten `ExercisePrescription`. Flagged as a cleanup
  candidate for a future pass, not a defect now.
- **`FunctionalFitnessMovement.exercise`/`FunctionalFitnessPerformedMovement.performedExercise`
  being un-inversed** is a compounding of an already-accepted risk
  (`ExercisePrescription.exercise`), not a new one — worth revisiting all
  three together if a canonical-Exercise-deletion feature is ever built.
- **`BenchmarkDefinition` catalog-curation/authoring process** — the data
  shape is implemented and tested; who creates/approves new benchmark
  definitions (a curated list vs. user-authored) is a product decision,
  not resolved here, matching `STAGE3B_ARCHITECTURE_DECISIONS.md`'s own
  §9 risk note.
- **This entire pass is unverified by a real compiler.** Every risk above
  is a design/scope note; the actual, dominant open risk is that Xcode
  will find something this manual review didn't — exactly what happened
  in every prior phase of this project (the group-path bug, the
  `@MainActor` requirement, the undeclared-inverse crash, the over-broad
  test assertion). Nothing about this pass's size makes that less likely;
  if anything, more.

## 8. What must happen on the local Mac before this is "green"

1. Pull this branch.
2. Open `TrainingOS.xcodeproj`, build the `TrainingOS` target (⌘B).
3. Fix whatever the compiler finds — expect at least one issue, per every
   prior pass's actual experience; this report's §7 last bullet is not
   false modesty.
4. Run the full test suite (⌘U) — all pre-existing Stage 1-3 tests plus
   the 3 new Stage 3C files must pass.
5. Run the app in Simulator; confirm Today/Plan/Progress still render the
   existing seeded dataset (nothing in the seeded dataset itself changed,
   so this is a regression check on the schema migration, not a check for
   new UI content — there is none, by design, per §6 above).
6. Report back exactly what broke, if anything, the same way every prior
   phase has — this is the loop, not a one-shot expectation.
