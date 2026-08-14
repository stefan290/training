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

## Summary: what survives what

- Deleting a **ProgramDefinition**: its TrainingWeeks go with it (they hold
  no performance data); every ProgramInstance built from it, and everything
  under those instances (Sessions, Blocks, SetResults, PersonalRecords),
  is untouched.
- Deleting a **ProgramInstance**: its Sessions survive with
  `programInstance == nil`; everything under those Sessions is untouched.
- Deleting a **Session**: its Blocks and their WorkoutResults are deleted;
  any SetResults logged under it survive with `exercisePrescription == nil`
  (their permanent home is `ExercisePerformanceProfile`, unaffected); any
  PersonalRecord already derived from a since-deleted WorkoutResult
  survives with `sourceWorkoutResult == nil`.
- Deleting a **PersonalRecord** directly: removes only that record. Does
  not touch its source SetResult/WorkoutResult, the ExercisePerformanceProfile
  it belonged to, or any other PersonalRecord.
- Deleting the **PerformanceProfile** (i.e. the account): everything under
  it is deleted. This is the only case where performance history is
  supposed to disappear.
