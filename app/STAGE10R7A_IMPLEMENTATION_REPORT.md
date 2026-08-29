# Stage 10R.7A Implementation Report — Strategic Phase Lifecycle Boundary Correction

**Status: ACCEPTED.** The one open blocker (item 21) is **RESOLVED** — see `STAGE10R7A_TX_ROOT_CAUSE_REPORT.md` for the full investigation and fix. Not committed, not pushed, 10R.7B not started, pending sign-off.

## Scope actually implemented

Per the approved D-10R7-1 through D-10R7-12 decisions:

1. **Hypertrophy mesocycle succession (M1→M2→M3) is program-level progression inside one strategic `TrainingPhase`, never strategic-phase creation.** `StartNextHypertrophyMesocycleUseCase` (renamed from `StartNextHypertrophyPhaseUseCase`) no longer creates a `TrainingPhase`/`TrainingMix`/`TrainingMixComponent` — it reassigns the existing Hypertrophy component's `.programInstance` pointer to a freshly-created `ProgramInstance`, locating the component via `previousPhase.selectedTrainingMix?.orderedComponents` (not `previousInstance.trainingMixComponents`, which goes stale once succession reassigns the pointer away).
2. **`TrainingPhase.primaryInstance`/`.secondaryInstances`** now prefer the mix component's current pointer over the phase's raw `programInstances` list, so a phase whose Hypertrophy component has succeeded to M2/M3 still resolves the *current* instance, not a stale historical one.
3. **`TrainingPhaseCompletion`** (new): pure, derived lifecycle queries — `hasNextHypertrophyMesocycle(for:)`, `isComponentProgramLifecycleTerminal(_:)`, `isPhaseTerminal(_:)`, `nextStrategicPhase(for:)`, `isFinalStrategicPhase(_:)`. No stored state, no new persisted concept.
4. **`PhaseDetailViewModel`'s `nextPhase == nil` gate removed** — this was the actual D-10R7-3 regression: a phase could have a real, pre-planned next strategic phase already sitting in `TrainingPlan.orderedPhases` and still correctly need to show "Start Metabolite Focus" (the next *mesocycle*, not the next *phase*) for its Hypertrophy component. Proven by `StrategicPhaseLifecycleTests.testCompletingMesocycleOneExposesStartMetaboliteFocusEvenThoughStrategicPhaseTwoAlreadyExists`.
5. **`TransitionPhaseUseCase`** runs the whole strategic transition against an isolated scratch `ModelContext` (autosave disabled) — the same proven pattern `AdvanceTacticalWeekUseCase` established in Stage 10R.6. On any failure the scratch context is discarded untouched; on success, one `save()` commits the outgoing phase's completion, the next phase's activation, and every immediately-materializable component's `ProgramInstance`/Sessions together, atomically. The caller's context is refreshed by re-fetching every touched phase/instance by `persistentModelID`.
6. **Calibration remains a valid, non-failing intermediate state** — unchanged. `StartPhaseUseCase.start` still never throws merely because a `.rmBased` component needs fresh `SourceRMCalibration`; it returns `componentsAwaitingCalibration` with the component's `ProgramInstance` already created and zero Sessions materialized, exactly as before.
7. **No strategic-transition UI was added** — explicitly out of scope per instruction.

## The one blocker: item 21 (RESOLVED)

`AnnualPlanSeedDateTests.testASecondSeedInvocationNeverDeletesTheFirstRunsData` failed reproducibly (3/3 runs, non-deterministic specific symptom) when this stage's implementation was first completed. The Stage 10R.7A-TX investigation (`STAGE10R7A_TX_ROOT_CAUSE_REPORT.md`) proved the failure had **nothing to do with `TransitionPhaseUseCase`'s scratch-context architecture** — it was a pre-existing SwiftData defect: `ExerciseCatalog.makeAndInsert`'s non-idempotent construction could create a second `Exercise` row colliding on `@Attribute(.unique) canonicalName`, and once referenced by the un-inversed `ExerciseSlot.resolvedExercise` relationship, SwiftData's own uniqueness-conflict merge corrupted an unrelated row instead of cleanly repairing it.

**Fix** (Stage 10R.7A-TX-FIX, full detail in the root-cause report's "Resolution" section): `ExerciseCatalog.makeAndInsert` → `resolveOrInsert` (fetch-by-`canonicalName` before constructing); `Exercise.resolvedSlots` inverse added (`.nullify`). Nothing in Stage 10R.7A's own lifecycle semantics changed.

## Test results after the fix

- Targeted (`ExerciseCatalogIdempotencyTests`, `RelationshipOwnershipTests`, `AnnualPlanSeedDateTests`, `StrategicPhaseLifecycleTests`): all pass.
- `AnnualPlanSeedDateTests.testASecondSeedInvocationNeverDeletesTheFirstRunsData` run 10 consecutive times: **10/10 passed**, zero occurrences of "bad fault," "missing delete propagation," "Multiple validation errors," "required value," or uniqueness-conflict log lines across all 10 runs.
- Full suite: **949 passed / 2 skipped / 0 failed** (up from 940/2/1 before the fix — 8 new regression tests added, the one blocker now passing).
- Fresh Simulator install + launch (erased container, real device-equivalent boot): app launched cleanly, seeded 38 Exercise rows (0 corrupted), 34 real `ExerciseSlot.resolvedExercise` relationships, 1 User/1 TrainingPlan/17 Sessions — no fatal errors, no CoreData corruption-signal log lines.
- Migration: a standalone script proved a real on-disk store written under the pre-fix schema opens cleanly under the post-fix schema with the new inverse correctly auto-populated — see the root-cause report's "Resolution" section for the full method and result.

## Files changed (this stage, cumulative including the TX fix)

`TrainingOS/Domain/Entities/TrainingPhase.swift`, `TrainingOS/Engines/TrainingPhaseCompletion.swift` (new), `TrainingOS/Application/UseCases/StartNextHypertrophyMesocycleUseCase.swift` (renamed), `TrainingOS/Application/UseCases/TransitionPhaseUseCase.swift`, `TrainingOS/Application/ViewModels/PhaseDetailViewModel.swift`, `TrainingOS/UI/Plan/PhaseDetailView.swift`, `TrainingOS/Application/Seed/SeedAnnualPlanJourney.swift`, `TrainingOS/Application/Seed/ExerciseCatalog.swift`, `TrainingOS/Domain/Entities/Exercise.swift`, `TrainingOS/Domain/Entities/ExerciseSlot.swift`, `DELETE_RULE_MATRIX.md`, plus corresponding test files (`StartNextHypertrophyMesocycleUseCaseTests.swift` renamed, `AdvanceTacticalWeekUseCaseTests.swift`, `PhaseTransitionOrchestrationTests.swift`, `StrategicPhaseLifecycleTests.swift` new, `ExerciseCatalogIdempotencyTests.swift` new, `RelationshipOwnershipTests.swift` extended) and every test file referencing `ExerciseCatalog.makeAndInsert` (mechanical rename to `resolveOrInsert`).

## STOP

Not committed. Not pushed. Stage 10R.7B not started.
