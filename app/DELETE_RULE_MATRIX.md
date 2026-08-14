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
| n/a | `PersonalRecord.sourceSetResult` / `.sourceWorkoutResult` | plain optional reference, no inverse declared | default (`.nullify`) | Deleting the source SetResult/WorkoutResult nullifies these traceability pointers; the PersonalRecord itself is untouched. | `PersonalRecord` stores its `value`/`repBand`/`achievedAt`/etc. redundantly at creation time specifically so it never depends on its source surviving. See `DeleteRuleMatrixTests.testDeletingWorkoutResultPreservesItsPersonalRecord`. |

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

## One-directional references (no declared inverse, no dual-mutation risk)

These are plain optional properties with no `@Relationship` inverse
declared on the other side, so SwiftData has nothing to keep in sync and
there's no cascade/nullify question — deleting the referenced object just
leaves a dangling `nil` the next time it's read (default `.nullify`
behaviour for an unannotated to-one relationship):

- `ExercisePerformanceProfile.exercise`, `ExercisePrescription.exercise`
  (which canonical Exercise, informational)
- `ProgramInstance.programDefinition` (which methodology was used; a
  ProgramInstance has no reason to survive its ProgramDefinition, but
  nothing in this pass deletes ProgramDefinitions out from under active
  instances, so this is unexercised — flagged as a follow-up, not solved
  here)
- `Recommendation.exercisePrescription` (which movement this
  recommendation was about)
- `PersonalRecord.sourceSetResult`, `PersonalRecord.sourceWorkoutResult`
  (traceability only, covered above)

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
