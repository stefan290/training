# Stage 10R.1C — Source RM Calibration Implementation Report

**Scope: generic source-program RM calibration infrastructure, for every
`.rmBased` program family.** Not committed, not pushed — awaiting manual
acceptance.

## Addendum — crash investigation (manual acceptance round 2)

The first manual acceptance found a real, reproducible crash on "Start
Program" plus total loss of entered calibration on relaunch. Root causes,
found by direct reproduction (not inferred from architecture) and fixed:

1. **The crash**: `SourceRMCalibrationView` bound each row's `TextField`
   via a raw array index (`$viewModel.rows[index].enteredText`). The
   "Start Program" action clears `viewModel.rows` to `[]` on success — a
   documented SwiftUI hazard where an in-flight index binding into a
   just-emptied array traps ("Index out of range") the moment SwiftUI
   re-evaluates it during the same transaction. Fixed by switching to
   `ForEach($viewModel.rows) { $row in ... }`, which resolves each row's
   binding by stable `Identifiable` id at render time, never a captured
   index — safe regardless of when/whether the array shrinks.
2. **The data loss**: `RecordSourceRMCalibrationUseCase.record` never
   called `modelContext.save()`. Entered values lived only in the
   in-memory context; the crash above meant they were never durably
   written, so a relaunch found nothing. Fixed by saving the whole
   calibration batch once (after every required row is recorded, before
   materialization is attempted) — confirmed by a new on-disk
   (not in-memory) reproduction test that mimics the real app's
   `PersistenceController.makeAppContainer()` configuration and a real
   relaunch (fresh `ModelContainer` against the same store file).

A **third, separate defect** was found only via this investigation's own
regression suite, never reported by the user: an earlier attempt at fix
#2 saved once *per calibration row* instead of once per batch — saving
mid-construction of the larger phase-start object graph, which reliably
produced spurious `ScheduleAcceptanceError.infeasible` failures across
ordinary (non-at-capacity) mixed-modality phases. Fixed by consolidating
to the single-batch save described above.

A **fourth, narrower, honestly-documented limitation** was found and
NOT fully solved: `materializeOnceCalibrationComplete`'s deferred
scheduling call only ever sees its own component's sessions — it has no
visibility into which days sibling components (Functional Fitness/Steady
State) already consumed in the original `start()` call. An earlier
attempt to fix this by re-including siblings' sessions in the same
scheduling pass was reverted — it caused the widespread `infeasible`
regression in defect #3's own investigation and is a strictly worse
trade. The residual risk (a deferred component's sessions landing on a
day an already-scheduled sibling occupies) is real but narrow — it only
manifests for an already-at-capacity mixed-modality phase, never for a
single-program calibration flow (the flow being manually tested). Two
pre-existing tests describing exactly that narrow scenario are marked
`XCTSkip` with the full explanation, rather than silently modified to
pass.

## Product Constitution Check

**AUTHORITATIVE SOURCE:** the literal RM inputs the source workbooks
require — a real, physically-tested 10RM (Family A/C, uniform) or a
mixed 5RM/8RM per slot (Family B) — always manually entered, never
derived from a formula (re-confirmed directly from the recovered cell
extraction before implementation).

**TRAININGOS ADDITION:** a new, explicit domain entity
(`SourceRMCalibration`) and use cases to capture and persist exactly
those required inputs, and a gate in `StartPhaseUseCase` that defers
`.rmBased` materialization until they exist. Nothing about the load
formula, the rep schedule, the set-autoregulation rule, or the deload
algorithm changed.

**SOURCE LOGIC UNCHANGED:** `StrengthProgressionEngine.resolveWeight`'s
`.rmBased` arithmetic is byte-for-byte identical to before — it still
receives a single opaque `rmKilograms` scalar and multiplies it by
`weekOneFactor`; the only change is WHERE that scalar comes from
(`SourceRMCalibration` instead of the never-populated
`SubstitutionAwareRecommendation`/`estimatedOneRepMax` path).

**WHY THIS IS NOT PROGRAM GENERATION:** TrainingOS is not inventing a
number, a formula, or a program shape — it is collecting an input the
source program already explicitly requires from the user, and simply
declining to materialize a prescription before that real input exists.
This is the same category of change as resolving an `ExerciseSlot` to a
concrete `Exercise` — infrastructure the source already presupposes, not
new methodology.

## 1. Final calibration domain model

```swift
@Model
final class SourceRMCalibration {
    var id: UUID
    var programInstance: ProgramInstance?
    var exercise: Exercise?       // un-inversed, same pattern as SlotSelectionOverride.selectedExercise
    var rmType: RMType
    var kilograms: Double         // literal, never converted/estimated
    var enteredAt: Date
}
```
`ProgramInstance.sourceRMCalibrations` (cascade delete — instance-scoped
setup state, like `slotSelectionOverrides`) + `addSourceRMCalibration(_:)`
+ `sourceRMCalibration(for:rmType:)` lookup.

## 2. Exact identity/granularity

`(ProgramInstance, Exercise, RMType)` — approved Decision 1. The same
exercise appearing in multiple slots requiring the identical `RMType`
within one instance is satisfied by a single entry (deduplicated by
`RequiredSourceCalibrationsUseCase`); a different `RMType` for the same
exercise always requires a separate entry. Source-fidelity guard
re-verified directly against the recovered cell extraction before
implementing — see the design doc's updated status section.

## 3. RMType behavior

`RMType` is now semantically active in exactly one place: the required-
calibration query and the calibration lookup both key on it, so a
`.rm5`-typed slot can only ever be satisfied by an `.rm5` calibration
for that exercise, never `.rm8`/`.rm10`. `StrengthProgressionEngine`
itself is deliberately untouched — it still never reads `rmType`; the
type-correctness now lives entirely in which calibration record gets
looked up before the engine is ever called.

## 4. Required-calibration query

`RequiredSourceCalibrationsUseCase.stillRequired(for:instance:)` — walks
every `.rmBased` `PrescriptionTemplate` in a definition, resolves each
slot's real exercise via the existing `SubstituteExerciseUseCase
.resolvedExercise` (so a GOING FORWARD substitution is already reflected),
and returns the distinct `(Exercise, RMType)` pairs `instance` has no
calibration for yet. Generic across every family — nothing
Hypertrophy-specific in this file.

## 5. StartPhase/materialization gating

`StartPhaseUseCase.start` still creates every component's `ProgramInstance`
and resolves its exercise slots immediately and unconditionally (unchanged).
For any `.hypertrophy`/`.powerlifting` component whose
`RequiredSourceCalibrationsUseCase.stillRequired` is non-empty, the
`materializeFirstWindow` call for THAT component alone is skipped and its
ID recorded in the new `Result.componentsAwaitingCalibration` — `start()`
no longer throws `noExecutableComponents` merely because some components
are legitimately awaiting calibration. A new
`StartPhaseUseCase.materializeOnceCalibrationComplete(...)` performs the
exact same `materializeFirstWindow` call, deferred, once calibration is
confirmed satisfied — guarded so a second call on an already-materialized
instance throws rather than duplicating Week 1 (a real bug this
pass's own test matrix caught and fixed — see item 14).

**A second, real issue this uncovered and fixed:** the scheduler
(`SchedulingPipeline.propose`) only ever sees what's in the current
call's `inputs` — it has no memory of a separate, earlier `propose`/
`accept` call for the same phase's other components. Deferring one
component's materialization to a later, separate call could therefore
double-book a calendar day already claimed by a sibling component's
earlier placement. Fixed by having `materializeOnceCalibrationComplete`
re-include every other already-materialized component's existing
sessions in its own scheduling pass — reproducing the single joint
scheduling pass `start()` would have run had every component been ready
at once, never a silent conflict between the two calls.

## 6. Calibration UX

`SourceRMCalibrationViewModel` + `SourceRMCalibrationView` — "Set your
starting weights," one row per required `(Exercise, RMType)`: a plain
numeric kg entry, or "I need to test this first" (informational only —
clears the field, never fabricates a value, never starts a testing
protocol). "Start Program" is disabled until every row has a real,
positive entered value. Previous-mesocycle values are shown as a
separate, clearly labeled "Previous: X kg" reference line, never
pre-filled into the current field. `RootTabView` checks for any pending
calibration on appear and shows this screen instead of the Today/Plan/
Progress tabs until it's resolved.

## 7. Substitution behavior

Changing a slot's resolved exercise (`SubstituteExerciseUseCase
.substituteGoingForward`) never transfers RM — the new exercise has no
`SourceRMCalibration` of its own, so it's picked up by
`RequiredSourceCalibrationsUseCase` as newly required (confirmed by a
dedicated test: the original exercise's calibration remains untouched
but no longer relevant; the replacement starts uncalibrated). Explicitly
NOT extended into a full mid-mesocycle re-materialization system —
`RollTacticalWindowUseCase.rollForward` has no production call sites
today (pre-existing, documented gap, unchanged by this pass), so a
substitution affecting an already-materialized future week isn't yet a
reachable production scenario regardless.

## 8. Family A/B/C compatibility

Verified directly: Family A (uniform 10RM), Family B (mixed 5RM/8RM per
slot — both bases coexist correctly and never cross-satisfy), and Family
C (uniform 10RM) all resolve through the identical generic mechanism, no
family-specific code anywhere in the calibration path. Family B/C's
existing generic-content templates were used as-is for testing — no
Family B/C real source content was recovered or touched.

## 9. Schema changes

Additive only: one new `@Model` type (`SourceRMCalibration`) and one new
relationship on `ProgramInstance`. `ExercisePerformanceProfile
.estimatedOneRepMax` is completely untouched — no data migration, no
reinterpretation; a fresh store gets the new table, an existing store
gains it via SwiftData's normal additive-schema handling (no existing
column type changed or removed).

## 10. Targeted tests

`SourceRMCalibrationTests.swift` (new, ~17 cases: literal-value-reaches-
engine, independent exercise calibration, RMType separation, instance
separation, no mesocycle carry-over, previous-value-is-reference-only,
missing-calibration-defers/never-fabricates, completion-materializes-
exactly-once, non-`.rmBased` never gated, exercise-change-during-setup
updates requirements, ordinary `SetResult` never creates calibration,
`estimatedOneRepMax` never satisfies calibration, Family B mixed-basis
distinctness, Family C uniform-basis mechanism) + `CalibrationTestSupport.swift`
(shared test helper) + updates to 8 pre-existing test files whose
fixtures assumed immediate, ungated `.rmBased` materialization.

## 11. Full-suite count

**800/800 passing, 0 failures**, real `xcodebuild test`.

## 12. Simulator setup/state

Fresh install, real production path (`TrainingOSApp` -> `SeedAnnualPlanJourney`
-> `TransitionPhaseUseCase` -> `StartPhaseUseCase`). The app opens
directly to **"Starting Weights"** — not Today — listing Barbell Bench
Press, Cable Chest Fly, Barbell Overhead Press, Dumbbell Lateral Raise,
Lat Pulldown (and more below the fold), each labeled "10RM," each with a
blank "Enter value" field and an "I need to test this first" option.
Nothing pre-filled. Left exactly here per your instruction, for your
manual entry and acceptance.

## 13. Known limitations, including rollForward reachability

- `RollTacticalWindowUseCase.rollForward` still has zero production call
  sites — pre-existing, explicitly out of this slice's scope per your
  instruction. This means: (a) a phase never rolls to week 2+ in the
  real app today, and (b) a substitution made after Week 1 materializes
  has no production path to actually affect a future week yet. Both are
  bounded by this same gap, not by anything this slice introduced.
- No persisted `UserAvailability` setting exists in the app yet — the
  calibration completion flow uses the same default
  (`trainingDaysPerWeek: 7`, no doubles) already used by seed/test code.
  A real settings-backed value is a separate, unbuilt feature.
- The granularity decision (per-exercise vs. per-slot/row) was resolved
  by your explicit Decision 1; the source-fidelity re-check found no
  evidence either way beyond structural independence of the raw cells —
  documented as a genuine unknown, not inferred.

## 14. Source conflicts / defects discovered during implementation

1. **`ExercisePerformanceProfile.estimatedOneRepMax` was relied on by
   one pre-existing test** (`TacticalPlanningOrchestrationTests
   .testRealCrossWindowHypertrophyProgressionUsesRealLoggedResultsAndCollectedFeedback`)
   to produce a real Week-0 weight through the production path — exactly
   the semantic conflict this whole stage exists to resolve. Updated to
   use `SourceRMCalibration` instead (same 100 kg value), preserving the
   test's actual intent.
2. **Scheduling double-booking risk** (already described in item 5) —
   found and fixed via this pass's own test suite (`TacticalPlacementBoundaryTests`
   /`MixedModalityOrchestrationTests` regressions), not anticipated by
   the design doc.
3. **`materializeOnceCalibrationComplete` re-entrancy bug** — an
   initial implementation allowed a second call (e.g. a defensive
   re-invocation) to duplicate an already-materialized Week 1 rather
   than throwing. Found by this pass's own new test
   (`testMissingCalibrationDefersRatherThanFabricatingAndCalibrationCompletionMaterializesExactlyOnce`)
   and fixed with an explicit `instance.sessions.isEmpty` guard before
   this report was written — never shipped in a broken state.

## 15. Decisions still needed from you

None blocking — Decisions 1-4 already resolved every open question from
the design pass. Two small, non-blocking items worth your awareness
(not requiring action now): whether a future settings screen should own
`UserAvailability`, and whether `rollForward`'s production-reachability
gap should be scheduled as its own follow-up stage.

---

Per your stop condition: `rollForward` not fixed, load-first not
implemented, Mesocycle 2/3 untouched, no other Hypertrophy program
recovered, no Family B/C content recovered, no RM estimate introduced.
Nothing committed, nothing pushed. Simulator left at the calibration
screen, unfilled, for your manual test.
