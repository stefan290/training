# Delete rule matrix

Every SwiftData relationship in `TrainingOS`, its delete rule, and why. The
guiding invariant, repeated because it is the reason most of this table is
`.nullify` instead of `.cascade`:

> Deleting programs or plan structure must never delete permanent user
> performance history.

Relationships are named `Parent.property -> Child` (the side carrying the
`@Relationship` annotation is the Parent). "Expected behaviour" describes
what happens when the **Parent** is deleted. Ownership is established from
the Parent's side only, via an `addX`/`attachX` method — see
`ARCHITECTURE.md` and `CLAUDE.md` rule set for why. Covered by
`RelationshipOwnershipTests.swift` and `DeleteRuleMatrixTests.swift`.

## Performance-critical relationships

These are the ones the invariant above is actually about.

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `ProgramInstance` | `Session` | `sessions: [Session]` | `.nullify` | Deleting a ProgramInstance leaves every Session it produced in place; each Session's `programInstance` becomes `nil`. | A Session is a historical record of what happened. It must outlive the instance that scheduled it — that's the whole point of separating instance from history. |
| `TrainingPhase` | `ProgramInstance` | `programInstances: [ProgramInstance]` | `.nullify` | Deleting a Phase leaves its ProgramInstances (and therefore their Sessions) in place; `instance.phase` becomes `nil`. | Ending or archiving a Phase must never take a program's execution history with it. |
| `ExercisePrescription` | `SetResult` | `loggedSetResults: [SetResult]` | `.nullify` | Deleting the session-context prescription (e.g. the block/session it lived in gets deleted) leaves the SetResult in place; `result.exercisePrescription` becomes `nil`. | A logged set's *permanent* home is `ExercisePerformanceProfile`, not the session that produced it. Losing session context is fine; losing the set itself is not. |
| `SetPrescription` | `SetResult` | `results: [SetResult]` | `.nullify` | Deleting the target (e.g. a program edit removes a prescribed set) leaves any SetResult that fulfilled it in place; `result.setPrescription` becomes `nil`. | The actual result is a fact about what happened; it doesn't stop being true if the plan that asked for it changes. |
| `ExercisePerformanceProfile` | `SetResult` | `setResults: [SetResult]` | `.cascade` | Deleting the whole permanent record deletes every SetResult inside it. | **The one legitimate cascade over performance data.** This only fires if `ExercisePerformanceProfile` itself is deleted, which in practice only happens by deleting the owning `PerformanceProfile` (i.e. the user's account). Nothing upstream of this (Session, Block, Prescription, ProgramInstance, ProgramDefinition, Phase, Plan) is allowed to reach this cascade. |
| `ExercisePerformanceProfile` | `PersonalRecord` | `personalRecords: [PersonalRecord]` | `.cascade` | Same as above — only cascades if the ExercisePerformanceProfile itself is deleted. | A PersonalRecord's home is the same permanent record its source SetResult/WorkoutResult belongs to; if that record's history is gone, the PR summarising it should go too. |
| `PerformanceProfile` | `ExercisePerformanceProfile` | `exerciseProfiles: [ExercisePerformanceProfile]` | `.cascade` | Deleting the PerformanceProfile deletes every ExercisePerformanceProfile (and transitively, every SetResult/PersonalRecord) inside it. | Intentional: this is account deletion, the one case where all training history legitimately goes away together. |
| `User` | `PerformanceProfile` | `performanceProfile: PerformanceProfile?` | `.cascade` | Deleting the User deletes their PerformanceProfile (and transitively everything above). | Same as above — this is the root of the "delete my account" cascade, not something that fires incidentally. |
| `SetResult` / `WorkoutResult` | `PersonalRecord` | `personalRecord: PersonalRecord?` (declared on the SetResult/WorkoutResult side; see the "One-directional references" section for why) | `.nullify` | Deleting the source SetResult/WorkoutResult nullifies `PersonalRecord.sourceSetResult`/`.sourceWorkoutResult`; the PersonalRecord itself is untouched. | `PersonalRecord` stores its `value`/`repBand`/`achievedAt`/etc. redundantly at creation time specifically so it never depends on its source surviving. See `DeleteRuleMatrixTests.testDeletingWorkoutResultPreservesItsPersonalRecord`. |

**Consequence, stated explicitly:** deleting a `ProgramDefinition` also
deletes its `TrainingWeek`s (`.cascade`, see below) — but a
`ProgramDefinition` has no relationship to `Session` or any performance
data at all, by construction (see `ProgramDefinition.swift`'s doc comment
and `PerformanceProfileContinuityTests.testProgramDefinitionExposesNoPerformanceLookingFields`).
There is nothing to nullify or cascade, because there is nothing there to
begin with.

## Structural relationships (plan/program/execution scaffolding)

These don't touch performance data directly, so cascade is the right,
unsurprising choice: deleting the parent should clean up child records that
have no independent meaning.

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `User` | `UserProfile` | `profile: UserProfile?` | `.cascade` | Deleting the user deletes their preferences. | Preferences have no meaning without an account. |
| `User` | `Goal` | `goals: [Goal]` | `.cascade` | Deleting the user deletes their goals. | Same reasoning. |
| `Goal` | `TrainingPlan` | `plans: [TrainingPlan]` | `.cascade` | Deleting a Goal deletes its Plans. | A Plan only exists to route toward its Goal. |
| `TrainingPlan` | `TrainingPhase` | `phases: [TrainingPhase]` | `.cascade` | Deleting a Plan deletes its Phases. | Phases are the Plan's structure, not independently meaningful — but see the row above: deleting a Phase does **not** cascade into its ProgramInstances. |
| `ProgramDefinition` | `TrainingWeek` | `weeks: [TrainingWeek]` | `.cascade` | Deleting a ProgramDefinition deletes its templated weeks. | Weeks are pure structure describing the methodology; they carry no performance data (see above), so nothing is lost by deleting them along with their definition. |
| `Day` | `Session` | `sessions: [Session]` | `.cascade` | Deleting a Day deletes its Sessions. | Tested explicitly rather than assumed safe — see `DeleteRuleMatrixTests.testDeletingSessionCascadesBlocksButPreservesSetResultsAndPersonalRecords`, which deletes a Session (one level down from Day) and confirms results/PRs still survive via the nullify chain below it. |
| `Session` | `WorkoutBlock` | `blocks: [WorkoutBlock]` | `.cascade` | Deleting a Session deletes its Blocks. | A Block has no meaning outside its Session. |
| `WorkoutBlock` | `ExercisePrescription` | `exercisePrescriptions: [ExercisePrescription]` | `.cascade` | Deleting a Block deletes its movements. | A movement's *prescription* is block-scoped structure; its *result*, if logged, is not — that's the `loggedSetResults` `.nullify` row above. |
| `WorkoutBlock` | `WorkoutResult` | `result: WorkoutResult?` | `.cascade` | Deleting a Block deletes its raw block-level result (AMRAP/EMOM/For Time/etc. payload). | The raw result is session-scoped. The *durable* summary of it, if it was a PR, already lives in `PersonalRecord` with its own copied value — see `sourceWorkoutResult` row above and its dedicated test. |
| `ExercisePrescription` | `SetPrescription` | `setPrescriptions: [SetPrescription]` | `.cascade` | Deleting a movement deletes its target sets. | Targets are pure prescription structure with no independent meaning once their movement is gone — the *results* against them survive via the `.nullify` row above. |
| `Exercise` | `ExerciseAlias` | `aliases: [ExerciseAlias]` | `.cascade` | Deleting a canonical Exercise deletes its known aliases. | An alias only means something relative to the exercise it resolves to. |

### Stage 4: template graph (structural, cascades like the rows above)

Pure methodology structure — see `ARCHITECTURE.md`'s "Template graph vs.
execution graph" section for why this is a separate tree from
`ProgramDefinition -> TrainingWeek` (which stays exactly as it was
through Stage 3) and from the execution rows above.

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `ProgramDefinition` | `TemplateSession` | `templateSessions: [TemplateSession]` | `.cascade` | Deleting a ProgramDefinition deletes its recurring weekly session structure. | A TemplateSession has no independent meaning outside its program. |
| `TemplateSession` | `WorkoutBlockTemplate` | `blockTemplates: [WorkoutBlockTemplate]` | `.cascade` | Deleting a session template deletes its block templates. | Same reasoning as `Session -> WorkoutBlock` above, one level up. |
| `WorkoutBlockTemplate` | `PrescriptionTemplate` | `prescriptionTemplates: [PrescriptionTemplate]` | `.cascade` | Deleting a block template deletes its slot templates. | Same reasoning as `WorkoutBlock -> ExercisePrescription` above. |
| `PrescriptionTemplate` | `ExerciseSlot` | `exerciseSlot: ExerciseSlot?` | `.cascade` | Deleting a slot template deletes its `ExerciseSlot`. | An `ExerciseSlot` has no independent meaning outside its template. |
| `PrescriptionTemplate` | `PrescriptionTemplate` (self) | `referencedAsPairedSlotBy: [PrescriptionTemplate]` (declared on the referenced side; the meaningful pointer, `pairedSlot: PrescriptionTemplate?`, is a plain property on the referencing side) | `.nullify` | Deleting a `PrescriptionTemplate` that another slot's `pairedSlot`/`linkedResultReference` points to nullifies the pointer; the referencing slot survives. | Same shape as `ProgramDefinition.instances`/`PersonalRecord.sourceWorkoutResult` below — an un-inversed to-one self-reference crashed instead of nullifying cleanly on delete (Stage 2's original finding, confirmed to still apply to self-referential relationships in Stage 4A's own tests: `TemplateGraphPersistenceTests.testDeletingPairedSlotNullifiesRatherThanCrashing`). `referencedAsPairedSlotBy` is never read by application code — it exists purely to give SwiftData a real inverse. |

## One-directional references

These were originally modelled as plain optional properties with no
matching `@Relationship` on either side. Two of the three groups below
turned out to need a declared inverse anyway — not for application code
(which still only ever touches one side, so there's no dual-mutation
risk), but because SwiftData's delete-rule machinery requires one. **Update
from the first Xcode verification pass:** a to-one `@Model` property with
*no* declared inverse anywhere in the schema does not safely default to a
clean `.nullify` at runtime on this SwiftData version — deleting the
referenced object produced a Core Data validation error (a still-required
attribute left `nil` on a phantom, never-saved object of the deleted
type) instead of a quiet nullify.

The working fix is *not* to annotate the referencing property itself —
that alone did nothing, because the delete rule that actually runs lives
on whichever side's relationship declaration pairs the two properties as
inverses of each other. Instead, each affected type now gets an
`@Relationship(deleteRule: .nullify, inverse: \Referencer.property)`
array/property declared on the **referenced** side, mirroring the
`ProgramDefinition.weeks` / `TrainingWeek.programDefinition` pattern used
everywhere else in this file. Nothing reads these new properties — they
exist purely so SwiftData has a real inverse to run the delete rule
against:

- `ProgramDefinition.instances: [ProgramInstance]` (`.nullify`, inverse
  `\ProgramInstance.programDefinition`) — exercised by
  `DeleteRuleMatrixTests.testDeletingProgramDefinitionPreservesPerformanceHistory`,
  which deletes a ProgramDefinition out from under an active
  ProgramInstance. No longer an unexercised follow-up.
- `WorkoutResult.personalRecord: PersonalRecord?` (`.nullify`, inverse
  `\PersonalRecord.sourceWorkoutResult`) and `SetResult.personalRecord:
  PersonalRecord?` (`.nullify`, inverse `\PersonalRecord.sourceSetResult`)
  — exercised by
  `DeleteRuleMatrixTests.testDeletingWorkoutResultPreservesItsPersonalRecord`.
- `ExercisePerformanceProfile.exercise`, `ExercisePrescription.exercise`
  (which canonical Exercise, informational) and
  `Recommendation.exercisePrescription` (which movement this
  recommendation was about) remain plain, un-inversed references —
  untouched by this pass since nothing deletes a canonical Exercise or an
  ExercisePrescription's owning Recommendation out from under active data
  yet. Same latent risk as above if that ever changes; flagged as a
  follow-up, not solved here.

## Stage 3C additions

Every relationship introduced by the typed `BlockPrescription`/
`BlockResult`/`PerformanceProfile`-sibling generalization
(`STAGE3C_IMPLEMENTATION_REPORT.md`). Same categories, same convention as
above — this section is additive, nothing above it changed.

### Performance-critical

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `WorkoutBlock` | `SteadyStateResult` | `steadyStateResult: SteadyStateResult?` | `.nullify` | Deleting the block leaves the result in place; `result.workoutBlock` becomes `nil`. | **Deliberately not the same rule as the legacy `WorkoutBlock.result` (`.cascade`).** This result has a permanent home (`ActivityPerformanceProfile`); cascading it with a session-context block would violate CLAUDE.md rule 1 for every non-strength result. |
| `WorkoutBlock` | `IntervalResult` | `intervalResult: IntervalResult?` | `.nullify` | Same reasoning as above. | Same reasoning as above. |
| `WorkoutBlock` | `FunctionalFitnessResult` | `functionalFitnessResult: FunctionalFitnessResult?` | `.nullify` | Same reasoning as above. | Same reasoning as above — this is also what makes benchmark history survive a program change. |
| `ActivityPerformanceProfile` | `SteadyStateResult` | `steadyStateResults: [SteadyStateResult]` | `.cascade` | Only fires if the whole `ActivityPerformanceProfile` is deleted. | Mirrors `ExercisePerformanceProfile.setResults` exactly — the one legitimate cascade over this permanent record, effectively account-deletion-only in practice. |
| `ActivityPerformanceProfile` | `IntervalResult` | `intervalResults: [IntervalResult]` | `.cascade` | Same as above. | Same as above. |
| `ActivityPerformanceProfile` | `PersonalRecord` | `personalRecords: [PersonalRecord]` | `.cascade` | Same as above. | Mirrors `ExercisePerformanceProfile.personalRecords`. |
| `BenchmarkPerformanceProfile` | `FunctionalFitnessResult` | `results: [FunctionalFitnessResult]` | `.cascade` | Same as above. | Mirrors `ExercisePerformanceProfile.setResults`. |
| `BenchmarkPerformanceProfile` | `PersonalRecord` | `personalRecords: [PersonalRecord]` | `.cascade` | Same as above. | Mirrors `ExercisePerformanceProfile.personalRecords`. |
| `PerformanceProfile` | `ActivityPerformanceProfile` | `activityProfiles: [ActivityPerformanceProfile]` | `.cascade` | Deleting the account deletes every activity profile. | Mirrors `PerformanceProfile.exerciseProfiles`. |
| `PerformanceProfile` | `BenchmarkPerformanceProfile` | `benchmarkProfiles: [BenchmarkPerformanceProfile]` | `.cascade` | Deleting the account deletes every benchmark profile. | Mirrors `PerformanceProfile.exerciseProfiles`. |
| `BenchmarkDefinition` | `FunctionalFitnessResult` | `results: [FunctionalFitnessResult]` | `.nullify` | Deleting a benchmark's *definition* (a methodology-like edit) leaves every historical attempt in place; `result.benchmark` becomes `nil`. | Mirrors `ProgramDefinition.instances` — editing/removing a methodology must never delete the performance history it produced. |
| `FunctionalFitnessResult` | `PersonalRecord` | `personalRecord: PersonalRecord?` | `.nullify` | Mirrors `WorkoutResult.personalRecord`/`SetResult.personalRecord` exactly. | Same reasoning, same required-inverse mechanics. |
| `FunctionalFitnessMovement` | `FunctionalFitnessPerformedMovement` | `performedAttempts: [FunctionalFitnessPerformedMovement]` | `.nullify` | Deleting the prescribed movement (e.g. its block/session is deleted) leaves the performed record in place, with `prescribedMovement` becoming `nil`; the performed data itself (`performedExercise`/`performedReps`/etc.) is unaffected, since it's copied onto the performed row directly. | Mirrors the SetResult/PersonalRecord "copy the value, keep the pointer as traceability only" pattern. |

### Structural (sub-detail of one permanent/structural record)

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `WorkoutBlock` | `SteadyStatePrescription` | `steadyStatePrescription: SteadyStatePrescription?` | `.cascade` | Deleting a block deletes its typed prescription. | Structure, no performance data — mirrors `WorkoutBlock.exercisePrescriptions`. |
| `WorkoutBlock` | `IntervalPrescription` | `intervalPrescription: IntervalPrescription?` | `.cascade` | Same as above. | Same as above. |
| `WorkoutBlock` | `FunctionalFitnessPrescription` | `functionalFitnessPrescription: FunctionalFitnessPrescription?` | `.cascade` | Same as above. | Same as above. |
| `FunctionalFitnessPrescription` | `FunctionalFitnessMovement` | `movements: [FunctionalFitnessMovement]` | `.cascade` | Deleting a prescription deletes its movement list. | Movements are pure prescription structure — the *performed* record (`FunctionalFitnessPerformedMovement`) lives elsewhere and survives independently (see above). |
| `IntervalResult` | `IntervalRepResult` | `repResults: [IntervalRepResult]` | `.cascade` | Deleting the whole permanent result deletes its per-interval detail rows. | A rep result has no independent meaning outside the session result it belongs to — this cascade is scoped to *this* result's own children, not to any upstream program/block deletion (which is `.nullify`, above). |
| `FunctionalFitnessResult` | `FunctionalFitnessPerformedMovement` | `performedMovements: [FunctionalFitnessPerformedMovement]` | `.cascade` | Same reasoning as `IntervalResult.repResults`. | Same reasoning. |

### One-directional references (declared purely for delete-rule safety)

- `BenchmarkDefinition.performanceProfiles: [BenchmarkPerformanceProfile]`
  (`.nullify`, inverse `\BenchmarkPerformanceProfile.benchmark`) — nothing
  in application code reads this; it exists only so
  `BenchmarkPerformanceProfile.benchmark` nullifies cleanly on delete
  instead of throwing, exactly the `ProgramDefinition.instances` fix from
  Stage 2, applied proactively here rather than discovered by a failing
  build.
- `FunctionalFitnessMovement.exercise`, `FunctionalFitnessPerformedMovement.performedExercise`
  remain plain, un-inversed references to `Exercise` — the same accepted,
  documented latent risk as `ExercisePrescription.exercise` above (nothing
  in this app deletes a canonical `Exercise` out from under active data
  yet). Not a new risk category; two more instances of an existing,
  already-flagged one.

## Summary: what survives what

- Deleting a **ProgramDefinition**: its TrainingWeeks go with it (they hold
  no performance data); every ProgramInstance built from it, and everything
  under those instances (Sessions, Blocks, SetResults, PersonalRecords),
  is untouched.
- Deleting a **ProgramInstance**: its Sessions survive with
  `programInstance == nil`; everything under those Sessions is untouched.
- Deleting a **Session**: its Blocks are deleted; the legacy `WorkoutResult`
  goes with them (unchanged, Stage 1-2 behaviour), but the Stage 3C typed
  `SteadyStateResult`/`IntervalResult`/`FunctionalFitnessResult` survive
  with `workoutBlock == nil` — this asymmetry is deliberate, not an
  oversight, see the Stage 3C table above. Any SetResults logged under it
  survive with `exercisePrescription == nil` (their permanent home is
  `ExercisePerformanceProfile`, unaffected); any PersonalRecord already
  derived from a since-deleted WorkoutResult/typed result survives with
  its source pointer set to `nil`.
- Deleting a **PersonalRecord** directly: removes only that record. Does
  not touch its source SetResult/WorkoutResult/FunctionalFitnessResult,
  the ExercisePerformanceProfile/ActivityPerformanceProfile/
  BenchmarkPerformanceProfile it belonged to, or any other PersonalRecord.
- Deleting a **BenchmarkDefinition**: its historical `FunctionalFitnessResult`
  attempts survive with `benchmark == nil`, same reasoning as deleting a
  ProgramDefinition.
- Deleting the **PerformanceProfile** (i.e. the account): everything under
  it is deleted, across all three profile types
  (Exercise/Activity/Benchmark). This is the only case where performance
  history is supposed to disappear.

## Stage 4C additions

Two new categories: the steady-state template graph (structural, same
shape as Stage 4A's strength template graph) and the substitution
persistence model (`SlotSelectionOverride`/`ActivitySelectionOverride`) —
see `SUBSTITUTION_MODEL.md`.

### Structural (steady-state template graph)

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `WorkoutBlockTemplate` | `SteadyStatePrescriptionTemplate` | `steadyStatePrescriptionTemplate: SteadyStatePrescriptionTemplate?` | `.cascade` | Deleting a block template deletes its steady-state rule template. | Mirrors `WorkoutBlockTemplate.prescriptionTemplates` exactly — a `SteadyStatePrescriptionTemplate` has no independent meaning outside its block template. |

### Substitution persistence (instance-specific state, not performance data)

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `ProgramInstance` | `SlotSelectionOverride` | `slotSelectionOverrides: [SlotSelectionOverride]` | `.cascade` | Deleting a ProgramInstance deletes its GOING FORWARD exercise overrides. | **Deliberately not `.nullify`** like `ProgramInstance.sessions` — an override is pure user-preference state about *that instance*, not performance history; there is nothing left worth preserving once the instance it was scoped to is gone. Confirmed by `SteadyStatePersistenceTests.testDeletingProgramInstanceCascadesItsSlotSelectionOverrides`. |
| `ProgramInstance` | `ActivitySelectionOverride` | `activitySelectionOverrides: [ActivitySelectionOverride]` | `.cascade` | Same as above. | Same as above — the endurance/activity sibling. |
| `ExerciseSlot` | `SlotSelectionOverride` | `slotSelectionOverrides: [SlotSelectionOverride]` (required inverse only; nothing reads it) | `.nullify` | Deleting an `ExerciseSlot` (which happens when its `ProgramDefinition` cascades away) nullifies `override.templateSlot` rather than crashing; the override row itself survives (still attached to its `ProgramInstance`) until that instance is separately deleted. | Same established "un-inversed to-one reference to a deletable type crashes instead of nullifying" fix as `PrescriptionTemplate.referencedAsPairedSlotBy` — proven directly by `SteadyStatePersistenceTests.testDeletingExerciseSlotNullifiesRatherThanCrashingSlotSelectionOverride`, not assumed safe by analogy. |
| `SteadyStatePrescriptionTemplate` | `ActivitySelectionOverride` | `activitySelectionOverrides: [ActivitySelectionOverride]` (required inverse only) | `.nullify` | Same reasoning as the `ExerciseSlot` row above. | Same reasoning — the endurance/activity sibling. |

### One-directional references (declared purely for delete-rule safety, or accepted as the existing deferred risk)

- `SlotSelectionOverride.selectedExercise`, `ExerciseRelationship.fromExercise`,
  `ExerciseRelationship.toExercise` remain plain, un-inversed references to
  `Exercise` — the same accepted, already-documented latent risk as
  `ExercisePrescription.exercise`/`FunctionalFitnessMovement.exercise`
  above (nothing in this app deletes a canonical `Exercise` out from under
  active data yet). Not a new risk category; three more instances of an
  existing, already-flagged one — deliberately handled identically rather
  than fixed in isolation for only the newest callers.

### Summary addition

- Deleting a **ProgramInstance** now also deletes its
  `SlotSelectionOverride`/`ActivitySelectionOverride` rows (cascade) —
  this is new relative to the pre-Stage-4C summary above, and is correct:
  these rows are instance-scoped preference state, not performance
  history, so they follow the instance rather than surviving it the way
  `Session`s do.
- Deleting a **ProgramDefinition** (and the `ExerciseSlot`/
  `SteadyStatePrescriptionTemplate` rows that cascade away with its
  template graph) nullifies any `SlotSelectionOverride`/
  `ActivitySelectionOverride` rows that pointed at those now-deleted
  template objects, without deleting the override rows themselves or the
  `ProgramInstance`s they belong to — consistent with CLAUDE.md rule 1.

## Stage 4D additions

One new structural relationship (the interval template graph, identical
shape to Stage 4C's steady-state one) and one **correction** to a Stage
4C relationship rather than a new one.

### Structural (interval template graph)

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `WorkoutBlockTemplate` | `IntervalPrescriptionTemplate` | `intervalPrescriptionTemplate: IntervalPrescriptionTemplate?` | `.cascade` | Deleting a block template deletes its interval rule template. | Mirrors `WorkoutBlockTemplate.steadyStatePrescriptionTemplate` exactly. |

### Correction: `ActivitySelectionOverride`'s required inverse moved

Stage 4C declared `ActivitySelectionOverride`'s required inverse
(`.nullify`) on `SteadyStatePrescriptionTemplate.activitySelectionOverrides`,
keyed by `templateSteadyState: SteadyStatePrescriptionTemplate?`. Stage
4D needed the identical GOING FORWARD mechanism for
`IntervalPrescriptionTemplate` too, and re-keyed the whole relationship
to the common `WorkoutBlockTemplate` parent instead of adding a second,
duplicate inverse-and-property pair for the interval type:

| Parent | Child | Relationship | Delete rule | Expected behaviour | Why |
|---|---|---|---|---|---|
| `WorkoutBlockTemplate` | `ActivitySelectionOverride` | `activitySelectionOverrides: [ActivitySelectionOverride]` (required inverse only; nothing reads it) | `.nullify` | Deleting a `WorkoutBlockTemplate` (which happens when its `ProgramDefinition` cascades away) nullifies `override.templateBlock` rather than crashing; the override row itself survives (still attached to its `ProgramInstance`) until that instance is separately deleted. | Same established "un-inversed to-one reference to a deletable type crashes instead of nullifying" fix as ever, now serving both endurance template types through one relationship. Re-proven directly at the new location by `IntervalPersistenceTests.testDeletingWorkoutBlockTemplateNullifiesRatherThanCrashingActivitySelectionOverride` — not assumed carried over from the Stage 4C test that exercised the old key. |

`ExerciseSlot.slotSelectionOverrides`/`SlotSelectionOverride.templateSlot`
(the strength side) are unaffected — this correction is scoped entirely
to the endurance/activity override.
