# TrainingOS — Dogfood Round 1 — Completion Report

**Status: IMPLEMENTED, TESTED, INDEPENDENTLY-REVIEWED CORRECTIONS APPLIED. NOT COMMITTED, NOT PUSHED** (per explicit instruction — stopping here for independent review).

Source of this checkpoint: 5 concrete product problems Stefan found running a **real, manual** dogfood journey in the Simulator — Goal: Build Muscle, 5 sessions/week, Full Gym; TrainingOS recommended 4x Hypertrophy + 1x Zone 2 Conditioning; Stefan selected 4x Hypertrophy + 1x Functional Fitness instead.

Full test suite: **1649 tests, 0 failures** (baseline 1625/0 before this checkpoint; +24 new focused tests across the original pass and the Final Close corrections below; 0 regressions). Every existing test that assumed pre-checkpoint behavior was updated to assert the new, correct behavior — never weakened, never deleted without replacement.

---

## FINAL CLOSE — Independent Review Corrections (this pass)

Independent review examined the completion report and implementation evidence and found **three narrow, real defects** in the original pass. All three are now fixed, tested, and re-verified. No other area of this checkpoint (rolling long-term planning, `StrategicPeriodizationPolicy`, the week-number fix, FF phase bias, Functional Bodybuilding session structure, the future-session start override, the conditioning/Running follow-up) was reopened.

### Correction 1 — Finding 1: calibration must use the real equipment profile
**Defect:** `StrengthExecutionViewModel.submitCalibration` (and the other 3 real calibration call sites) passed a hardcoded `EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)` unconditionally — invalid for a dumbbell/machine/cable exercise.
**Root cause, traced (not assumed):** every real call site in the entire codebase — not just this checkpoint's own code — used this identical hardcoded profile; there was no pre-existing per-exercise equipment differentiation anywhere to "restore." The real, already-existing authority for per-equipment increments is `UserProfile.equipmentIncrements: [String: Double]` (already keyed by the exact same strings as `Exercise.equipment` — `["barbell": 2.5, "dumbbell": 2.0, "machine": 5.0]`), previously consulted only by Hypertrophy V2's double-progression path.
**Fix:** new `EquipmentProfile.resolved(for:userProfile:)` + `EquipmentType.resolved(fromExerciseEquipment:)` (in `EquipmentProfile.swift` — the existing domain type, never a second equipment model) derive the real `EquipmentType` from the resolved `Exercise.equipment` and the real increment from `UserProfile.equipmentIncrements`, falling back to the exact same TRAININGOS_DESIGNED default (barbell/2.5kg) only when neither resolves — never worse than before. `ResolveCalibrationDependentPrescriptionsUseCase.resolve` now takes `userProfile` instead of a single `equipmentProfile`, and resolves equipment **per prescription**, from that prescription's own real exercise (a paired-slot dependent can legitimately be on different equipment than the exercise actually being calibrated). All 4 real call sites updated.
**Also fixed:** the in-session calibration prompt's copy now names the specific source-required RM type ("What's your 10RM?" / "This program calls for a real 10RM...") via a new shared `PlanPresentation.rmTypeLabel`, instead of a generic "starting weight — an estimate is fine." The separate, optional "Estimate Now" screen is unchanged/preserved.

### Correction 2 — Finding 3C: unknown capability must never auto-prescribe
**Defect:** the materializer preferred an ordinary candidate but **fell back to the advanced (`requiresDemonstratedCapability`) one** when it was the sole eligible candidate — violating "unknown capability must never become an automatic unscaled advanced prescription."
**Also found during this correction (self-discovered, disclosed):** the original fix had been applied to the wrong resolution site. `FunctionalFitnessMaterializer` has TWO resolution paths — the real, always-used production path (`materializeDynamicBlock`, `isDynamicallyComposed: true`, which every real generated FF program uses) and a legacy/seed-only path (`isDynamicallyComposed: false`, "no real content today" per its own doc comment). The original correction touched only the legacy path. This pass fixes the REAL path.
**Fix:** in `materializeDynamicBlock`'s real least-exposed-rotation resolution, a real GOING FORWARD preference (informed athlete choice) still wins outright and unconditionally; otherwise the rotation is restricted to non-`requiresDemonstratedCapability` candidates, and **only when every remaining eligible candidate requires demonstrated capability** does it throw a new, precise, typed `FunctionalFitnessMaterializationError.capabilityUnknown(slot:exercise:)` rather than silently prescribing the advanced movement. The legacy path keeps the identical invariant for consistency. Explicit semantic correction applied: `Exercise.requiresDemonstratedCapability` describes only the exercise, never the athlete — no real athlete-capability state exists anywhere in this app, so "unknown" is the only honest reading, and no such state is falsely claimed anywhere.

### Correction 3 — Finding 3D: every loaded FF movement needs load/intensity guidance
**Defect:** `FunctionalFitnessMovementTargetRule` resolved reps/distance for loaded metcon movements but never any indication of how heavy.
**Fix, never a %1RM formula:** new `RelativeLoadTier` (`light`/`moderate`/`heavy`) + `FunctionalFitnessLoadGuidance` (tier, opening-round reserve-reps target, sustainable/unbroken intent) — real, authored **TrainingOS PRODUCT DECISION** programming data, extending `FunctionalFitnessMovementTargetRule`'s own existing locked-per-exercise-value table (Wall Ball/Thruster/Deadlift/Kettlebell Swing/Dumbbell Snatch/Back Squat each get a real, differentiated value). Persisted as 3 new flat fields on `FunctionalFitnessMovement` (never both a numeric load and relative guidance at once — a real hand-authored numeric load always wins outright). `SubstituteFunctionalFitnessMovementUseCase` recomputes it for the new exercise on every legal substitution, under the identical precedence. `BlockPresentation.loadGuidanceLine` renders it, and `FunctionalFitnessExecutionView`'s real "Each round" movements card now shows it beneath every movement line.

**Tests added for these 3 corrections:** 10 new focused tests (`testFinding1_*` ×6, `testFinding3D_*` ×4) plus 2 rewritten `testFinding3C_*` tests (now proven against the real `materializeDynamicBlock` production path) and 1 new `testFinding3C_ManualGoingForwardPreferenceForAdvancedMovementStillWins` — all in `DogfoodRound1CompletionTests.swift`. Full suite re-verified at 1649/0.

---

## Finding 1 — Deferred / In-Session Calibration

**Classification:** BUG (confirmed) — "I'd rather test this properly first" was a lie; choosing it could never let the athlete proceed.

**Observed symptom:** The Starting Weights screen's secondary affordance looked like a real alternative path but silently did nothing — calibration still blocked Plan/Session creation entirely.

**Root cause (traced, not assumed):** `StartPhaseUseCase.start` deferred materializing an entire `.rmBased` component (Hypertrophy/Powerlifting) until `RequiredSourceCalibrationsUseCase.stillRequired` was empty, and `RootTabView` blocked the *whole app* behind `SourceRMCalibrationViewModel.hasPendingCalibration` in the meantime. The domain model already had the right representation for the honest "awaiting calibration" state — `StrengthProgressionEngine.resolveWeight` already returns `(nil, .calibrationRequired)` for a missing RM, and `SetPrescription.targetWeight` was already `Optional` — it was simply never reached in production because of this gate.

**Implementation:**
- `StartPhaseUseCase.start` no longer defers materialization on missing calibration — every component's real Sessions/blocks/prescriptions materialize immediately. An affected `.rmBased` slot's reps/sets are fully prescribed; only its **weight** stays honestly `nil` with `appliedLoadReasonCode == .calibrationRequired`.
- New `ResolveCalibrationDependentPrescriptionsUseCase`: records the calibration and resolves every already-materialized dependent prescription this week (direct `.rmBased` matches, plus `.linkedToPairedSlot` dependents via a small fixed-point pass) — via the *exact same* `StrengthProgressionEngine.resolveWeight` formula the materializer itself uses. Never a second/approximated formula.
- `StrengthExecutionView`/`StrengthExecutionViewModel`: a new in-session calibration prompt appears *before* working sets for any movement whose weight is unresolved ("test in first session" — path B). Entering a real value resolves it in place.
- `SourceRMCalibrationViewModel`/`SourceRMCalibrationView`: rewritten as a genuinely optional, non-blocking "estimate now" screen (path A) — submitting whatever's filled in no longer requires every row, and it no longer gates anything.
- `RootTabView`: the blocking full-screen calibration gate is removed. A small dismissible banner offers the optional screen; Today/Plan/Progress are always reachable. (Running's own separate, pre-existing calibration gate — a deliberate, different design — is untouched, per explicit scope.)
- `StartPhaseUseCase` also had to be restructured to preserve its exact pre-existing two-pass *scheduling* behavior (non-`.rmBased` components scheduled first, `.rmBased` second against `preOccupiedDates`) even though materialization is no longer staged — a single combined scheduling pass measurably produced *worse* packing in a tight-week/doubles scenario (`ConcurrentScheduler` is a greedy, non-backtracking placer). This was necessary to avoid a real regression in the Concurrent Programming golden scenarios (G4A/G4B), not a Finding-1 requirement in itself.

**Product behavior after fix:** An athlete can start training immediately regardless of unresolved calibration. Each unresolved exercise asks once, in its own first real session, before its working sets — never a fabricated placeholder, never a silent estimate.

**Tests:** `SourceRMCalibrationTests` (rewritten), `ProgramInstanceExerciseSlotResolutionTests` (rewritten), `StrategicPhaseLifecycleTests` (updated), `DogfoodReleaseReadinessJourneyTests` (updated), `ConcurrentProgrammingGoldenScenarioTests` G4A/G4B (updated for the new single-call two-pass shape); **Final Close correction:** `testFinding1_DifferentEquipmentTypesProduceDifferentRounding`, `testFinding1_UnrecognizedEquipmentDegradesToExistingDefault`, `testFinding1_InSessionCalibrationUsesTheRealEquipmentProfileNotHardcodedBarbell`, `testFinding1_CorrectRMTypeIsPresentedToTheAthlete`, `testFinding1_SourceFormulaRemainsUnchanged`, `testFinding1_NoFabricatedCalibrationLoad` — all passing.

**Remaining limitation:** None material to Finding 1's own scope. (Finding 3D below covers the separate, still-open question of *Functional Fitness* metcon loads.)

**Final Close correction applied:** the in-session/estimate-now equipment profile was hardcoded barbell/2.5kg — see "FINAL CLOSE — Independent Review Corrections" above for the full fix (real per-exercise `EquipmentType`/`UserProfile.equipmentIncrements` resolution) and the correct RM-type athlete-facing copy.

---

## Finding 2 — Long-Term Plan Absent Without Target Date

**Classification:** BUG (confirmed via fresh trace, not assumed).

**Observed symptom:** A normal, no-milestone Build Muscle goal's Plan showed a current phase and "No later phase is planned yet."

**Root cause (traced):** `LongTermPlanner.proposeForwardOnlyPhases`'s `targetDate == nil` branch returned exactly **one** `ProposedPhase` (`endDate: nil`) — this single phase became the plan's entire `orderedPhases`. The milestone/reconciled paths don't have this gap; they already fill multiple future phases via `fillForwardPhases`, which already fully delegates to `StrategicPeriodizationPolicy`.

**Implementation:** The no-target-date branch now calls a new `rollingOpenEndedHorizon`, which fills exactly one full `StrategicPeriodizationPolicy` cycle's worth of phases (the natural, already-designed boundary for "how far ahead this policy has a real opinion") using the *same* per-phase construction `fillForwardPhases` already uses (extracted into a shared `nextProposedPhase` helper — zero duplicated logic). The horizon's **last** phase stays `endDate: nil` (open-ended) — the precision hierarchy (current phase precise → near-future phases estimated → later direction open) falls directly out of reusing existing, already-understood semantics, no new field invented.

**Product-decision consequence, explicitly confirmed with Stefan before implementing:** Reusing `StrategicPeriodizationPolicy`'s cycle *unmodified* for the no-target-date path means a Get Stronger goal's own current phase can legitimately be Muscle Development (the cycle's `cyclePosition == 0`) — identical to the already-accepted behavior for the target-date path (Golden A). Per Stefan's explicit decision: **unify**, do not special-case the current phase to always equal the goal's primary type. To make this legible to the athlete, `AcceptStrategicPlanUseCase` now writes one real per-phase `PlannerDecision` (reusing the pre-existing, previously-unpopulated `PhaseDetailViewModel.phaseExplanation` hook) explaining the connection back to the goal whenever a phase carries `.developmentPhaseSupportsPrimaryGoal`.

**Product behavior after fix:** Every open-ended goal gets a real rolling strategic horizon. Build Muscle: `[Muscle Gain, Muscle Gain, Maintenance]` (last open-ended). Get Stronger: `[Muscle Development, Strength, Strength, Maintenance]` (last open-ended), with the Muscle Development phase's detail screen explaining why it exists.

**Tests:** `LongTermPlannerStrategicPlanTests`, `OnboardingTests`, `YearOverviewTests`, `OnboardingPlanSelectionReconciliationTests` (all updated), `GoalTrainingStyleProductModelTests` (3 tests re-targeted to construct a `.strength`-typed preview phase directly, since they test strength-phase mix-ranking, not onboarding sequencing), plus new `DogfoodRound1CompletionTests` golden-cycle proofs.

**Remaining limitation:** None.

---

## Finding 2B — "Week 2 of 4" on Day One

**Classification:** BUG (traced and proven, not assumed — could have been correct semantics; it was not).

**Observed symptom:** A newly-accepted plan showed "Week 2 of 4" the same day it was accepted.

**Root cause:** `PlanViewModel.weekPosition`/`PhaseDetailViewModel.load` both computed the displayed week from `ProgramWeekGrouping.nextWeekIndex(for:)` — "how many weeks are fully materialized" (correct for `RollTacticalWindowUseCase.rollForward`'s own "which week to materialize next" question) — but treated it as if it were *already* the 0-indexed current week, then added +1 for 1-indexed display. The real 0-indexed current week is one less (`nextWeekIndex - 1`), which already existed, tested, as `TacticalWeekCompletion.currentMaterializedWeekIndex`. This is a systematic off-by-one, not a day-1-only artifact — it's simply invisible after week 0 because every later week's materialization happens in lockstep with the athlete's own "Start Week N" tap; week 0 alone is pre-materialized automatically at phase acceptance, one step ahead of that pattern.

**Implementation:** Both call sites now read `TacticalWeekCompletion.currentMaterializedWeekIndex(for:) ?? 0` instead of `nextWeekIndex` directly. Zero change to `rollForward`, `ProgramWeekGrouping`, or the R0 Monday-boundary invariant.

**Product behavior after fix:** A freshly-started phase shows "Week 1 of N" on day one, as it should.

**Tests:** `DogfoodRound1CompletionTests.testFinding2B_FreshlyStartedPhaseShowsWeekOneNotWeekTwoOnDayOne`.

**Remaining limitation:** None.

---

## Finding 3 — Functional Fitness Programming Model

**Classification:** Real, substantial gaps in some sub-areas; genuinely more mature than the pre-existing (stale) FF gap audit suggested in others — re-traced directly against current code, not assumed from that document.

**Important correction to my own initial grounding:** a prior audit (`POST_FFP1_FUNCTIONAL_FITNESS_GAP_AUDIT.md`, present untracked in the repo) claimed FF programming is "one single, structurally coherent workout shape" with "the SOLE real construction site." Direct trace proved this stale — a later "FF Multi-Week V1" stage (already shipped, already tested, `FunctionalFitnessAuthoredProgramLibrary`) already provides real week-to-week format/stimulus variety and a genuine, already-wired `includeStrengthBlock` mechanism that materializes a real second `WorkoutBlockTemplate`. I re-derived Finding 3's actual gaps from this real current state, not the stale document.

### 3A — Phase bias
**Root cause:** `functionalFitnessParameterCandidates(component:)` took no phase/goal input at all — the identical authored weekly plan applied regardless of which phase requested it.
**Implementation:** New `FunctionalFitnessPhaseBiasPolicy` (explicitly labeled a **TrainingOS PRODUCT DECISION**, never attributed to any source), driven by `component.trainingMix?.phase?.type` (no new parameter threading needed). Biases only fields *proven, by direct trace of `FunctionalFitnessMaterializer`, to survive to the real materialized session*: `includeStrengthBlock`, `loading`, `intensity`, `systemicDemand`. Deliberately does **not** bias `stimulus.movementFunctions` — tracing `FunctionalFitnessMaterializer.materializeWeek` proved `FunctionalFitnessMovementComposer` overwrites that field from real-time environment eligibility/exposure rotation regardless of the authored value, so biasing it would be fake precision with zero athlete-visible effect.
- Muscle Gain / Strength phase → every week gets a real strength/accessory block (Functional Bodybuilding bias).
- Recovery / Maintenance phase → no strength block, `bodyweightOnly` loading, `low` intensity/systemic demand (down-regulation).
- Functional Fitness phase / others → unchanged (already the appropriate shape, or not this checkpoint's focus).

### 3B — Complete session
Substantially already real via the pre-existing `includeStrengthBlock` mechanism (a genuine second block, not a placeholder) — 3A's fix makes it apply *consistently* for phases that should always want it, rather than only on some pre-authored weeks.

### 3C — Capability-aware
**Root cause:** the FF candidate-exercise resolution had zero capability signal — confirmed the catalog really does seed "Chest-to-Bar Pull-up"/"Handstand Push-up" as equally-eligible candidates for an ordinary `.gymnasticsPull`/`.gymnasticsPush` slot, exactly matching Stefan's real observed session.
**Implementation:** New `Exercise.requiresDemonstratedCapability: Bool` (default `false`, purely additive) — the minimal capability model requested, reusing zero new questionnaire machinery, and explicitly describing only the EXERCISE, never a claim about the athlete (no real athlete-capability state exists anywhere in this app). Marked `true` only for Chest-to-Bar Pull-up and Handstand Push-up.
**Final Close correction:** the original pass allowed an automatic fallback to the advanced exercise when it was the sole eligible candidate, and had fixed the wrong (legacy, non-production) resolution site. Both corrected — see "FINAL CLOSE — Independent Review Corrections" above. The real production path (`FunctionalFitnessMaterializer.materializeDynamicBlock`) now excludes `requiresDemonstratedCapability` candidates from the automatic least-exposed rotation entirely, throwing a typed `capabilityUnknown` error rather than ever auto-prescribing one; a real GOING FORWARD athlete preference still wins unconditionally, and manual Change Exercise selection remains available.

### 3D — Loads/scaling complete
**Closed, corrected.** The Functional Bodybuilding strength block's load is fully real (via Finding 1's calibration integration — it is `.rmBased`). The FF/metcon block's own loaded movements now carry a real, authored **TrainingOS PRODUCT DECISION** relative load/intensity guidance (`RelativeLoadTier` + reserve-reps + sustainable-pace intent) wherever no legitimate numeric load exists — never a %1RM formula (CLAUDE.md rule 10 remains respected; no validated one exists). See "FINAL CLOSE — Independent Review Corrections" above for the full domain model, materialization wiring, and athlete-facing rendering in `FunctionalFitnessExecutionView`.

### 3E — Functional Bodybuilding as a distinct expression
**Root cause:** the pre-existing strength block was a single hardcoded "Squat, 5x5 @ 0.8×5RM" — structurally real, but not actually a *Functional Bodybuilding* expression (identical to a mini strength test) and never varied.
**Implementation:** `FunctionalFitnessProgramGenerator.addStrengthBlock` now rotates through 4 real patterns (Squat/Hinge/Press/Pull) across the week index, at a genuinely different, moderate rep scheme (10RM-based, 0.65× factor, 4×10 — never the 5-rep strength-test scheme), each slot explicitly named "Functional Bodybuilding — «pattern»". A TrainingOS product decision, explicitly labeled as such.

**Tests:** `DogfoodRound1CompletionTests` — `testFinding3A_*` (3), `testFinding3E_*` (1); full existing FF suite (`FunctionalFitnessProgramGeneratorTests`, `FunctionalFitnessMultiWeekV1Tests`, `FunctionalFitnessMovementDiversityTests`, `FunctionalFitnessSubstitutionAndBenchmarkTests`, `CrossModalityFunctionalFitnessProgrammingTests`, `FunctionalFitnessGoingForwardPreferenceTests` — 110 tests) re-verified with zero regressions. **Final Close correction tests:** `testFinding3C_AdvancedGymnasticsMovementIsNeverTheAutomaticPick` (rewritten against the real production path), `testFinding3C_SoleAdvancedCandidateFailsHonestlyRatherThanAutoPrescribing`, `testFinding3C_ManualGoingForwardPreferenceForAdvancedMovementStillWins`, `testFinding3D_EveryLoadedMovementHasNumericOrRelativeLoadGuidance`, `testFinding3D_RelativeLoadGuidanceSurvivesMaterialization`, `testFinding3D_ExecutionUIRendersLoadGuidanceLine`, `testFinding3D_MuscleGainFunctionalBodybuildingBiasAndConditioningBothRemain`.

**Remaining limitations (disclosed, not silently accepted):**
- `requiresDemonstratedCapability` is set at catalog-seed time only; an *already-seeded* pre-existing install's Chest-to-Bar Pull-up/Handstand Push-up rows will not retroactively gain the flag without a fresh seed (a disclosed, zero-risk limitation for a fresh/dogfood install — matches every other purely-additive field in this codebase's convention).
- Movement-function diversity beyond what the composer already provides (still 6 of 15 `MovementFunction` cases reachable) was not expanded — out of this checkpoint's scope, and no longer blocked by anything this checkpoint touched.
- The relative-load guidance table (Finding 3D) covers every exercise currently reachable by production FF generation (Back Squat, Wall Ball, Thruster, Deadlift, Kettlebell Swing, Dumbbell Snatch); a future new loaded exercise added to the catalog would need its own row added to the same locked table — the same maintenance shape the reps table already required before this fix, not a new burden.

---

## Finding 4 — Start a Different Day's Session

**Classification:** Missing capability (confirmed) — Stefan could inspect a future session but never start it.

**Root cause:** `SessionDetailView`'s `.futurePreview` display mode (a session opened from Plan/Week, `readOnly: true`) never offered any action at all. `TodayViewModel` only ever loaded/started sessions scheduled for literally today.

**Implementation:** New `StartSessionOnDifferentDayUseCase.startToday` — re-parents the *same* Session onto today's real `Day` (fetch-or-create) using the exact re-parenting mechanism `AcceptScheduleProposalUseCase` already performs for ordinary scheduling (`oldDay.sessions.removeAll` + `Day.addSession`, nullify not cascade), then starts it via the existing, unmodified `StartSessionUseCase`. Never a new rescheduling engine — explicitly out of scope, and not needed: only the ONE moved session is touched; the rest of the week is untouched. Wired as a "Start Today Instead" button in `SessionDetailView`'s `.futurePreview` branch (hidden when the session is already scheduled for today).

**Product behavior after fix:** The athlete can execute any real, already-materialized session on the day they actually choose to do it — never duplicated, never left looking unperformed on its original day, source/program identity and future WorkoutResult fully preserved.

**Tests:** `DogfoodRound1CompletionTests.testFinding4_*` (3 tests: move-and-start, already-today rejection, already-in-progress rejection).

**Remaining limitation:** None within this checkpoint's stated minimum ("athlete can override the scheduled day and execute the existing real session without corrupting state"). A smarter rebalancing of the *rest* of the week is explicitly deferred, per instruction.

---

## Finding 5 — Conditioning Activity / Running Gap

**Classification:** Documented only, per explicit instruction — not implemented.

Build My Own Mix cannot select "1x Running" because Running V1 legitimately requires exactly 2 sessions/week. This must never be "fixed" by changing Running V1's own capability from 2 to 1 — that would conflate two different concepts. **Follow-up, not built here:** a generic "Aerobic/Conditioning Component" (activity type: Running/Cycling/Rowing + a prescription like Zone 2), distinct from "Running as a programmed training discipline" (the real Running engine, its own frequency/progression/calibration). Recorded here as the only trace of this finding — no code touched.

---

## Cross-Cutting Verification

- **Source/authority hierarchy preserved:** the new `StrategicPeriodizationPolicy`/`FunctionalFitnessPhaseBiasPolicy`/`FunctionalFitnessProgramGenerator.addStrengthBlock`/`FunctionalFitnessLoadGuidance` changes are explicitly labeled TrainingOS PRODUCT DECISIONS in their own doc comments — never attributed to RP, CrossFit, or any source workbook.
- **Full test suite:** 1649 tests, 0 failures (was 1625/0; +24 new across both passes, 0 regressions), run via `xcodebuild test-without-building ... -parallel-testing-enabled NO`.
- **Real build/install/launch verification:** `xcodebuild build` succeeded for the real app target; installed and launched on a booted `iPhone 17` Simulator from a clean uninstall — confirmed the Goal screen shows no pre-selected goal and Continue stays disabled until one is chosen (screenshot captured, see below).
- **Screenshot disclosure (honest, not overclaimed):** one real screenshot was captured (clean-install launch → onboarding Goal screen). Deep, multi-step UI-flow screenshots for the 6 specific new states (calibration banner, in-session calibration prompt, Plan rolling horizon + phase explanation, "Start Today Instead" button, phase-biased FF session, Functional Bodybuilding block) were **not** captured — reliable automated tap-driven navigation through this SwiftUI app requires a UI-automation driver (XCUITest/idb) not set up in this sandbox, the identical, already-disclosed gap from the prior Dogfood Release Readiness V1 checkpoint, which Stefan explicitly accepted resolving via real-device dogfood rather than further sandbox-automation investment.
- **No commit, no push** — stopped here per explicit instruction.

---

## Verdict

```
TRAININGOS — DOGFOOD ROUND 1 — VERDICT

FINDING 1 (Deferred/In-Session Calibration):        CLOSED — real fix, tested (equipment-profile correction applied)
FINDING 2 (Long-Term Plan Absent, No Target Date):  CLOSED — real fix, tested
FINDING 2B (Week 2 of 4 on Day One):                CLOSED — real fix, tested
FINDING 3A (FF Phase Bias):                         CLOSED — real fix, tested
FINDING 3B (FF Complete Session):                   CLOSED — already substantially real; now consistent
FINDING 3C (FF Capability-Aware):                   CLOSED — corrected: real production path now gates
                                                      unknown capability out of automatic selection entirely
FINDING 3D (FF Loads/Scaling Complete):              CLOSED — real, authored relative load/intensity
                                                      guidance now closes the gap; no %1RM formula invented
FINDING 3E (Functional Bodybuilding Distinct):       CLOSED — real fix, tested
FINDING 4 (Start a Different Day's Session):        CLOSED — real fix, tested
FINDING 5 (Conditioning Activity Gap):               DOCUMENTED ONLY — not implemented, per instruction

FULL TEST SUITE:            1649 tests, 0 failures (baseline 1625/0, +24 new, 0 regressions)
BUILD:                      SUCCEEDED (real app target + test target)
REAL INSTALL/LAUNCH CHECK:  PASS (clean install, booted Simulator, no crash — prior pass)
SCREENSHOTS CAPTURED:       1 of 6 requested UI states (launch only) — gap disclosed, not overclaimed
GIT STATUS:                 NOT COMMITTED, NOT PUSHED (per instruction)
FILES CHANGED (cumulative, both passes): 29 modified, 6 new (production) + 1 new (tests)

FINAL CLOSE CORRECTIONS (this pass):
  - Finding 1: real per-exercise EquipmentType/UserProfile.equipmentIncrements
    resolution replaces the hardcoded barbell/2.5kg profile; correct RM-type
    copy shown to the athlete.
  - Finding 3C: real production path (materializeDynamicBlock) now excludes
    unknown-capability exercises from automatic selection entirely, never
    falling back to them even as the sole eligible candidate; a real going-
    forward athlete preference still wins; manual selection preserved.
  - Finding 3D: real, authored TrainingOS PRODUCT DECISION relative load/
    intensity guidance closes the loaded-metcon-movement gap without
    inventing a numeric formula; rendered in FunctionalFitnessExecutionView.

PRODUCT DECISIONS REQUIRING STEFAN'S OWN REVIEW (already applied per his explicit direction):
  - Finding 2 "unify": a no-target-date Get Stronger goal's current phase may
    legitimately be Muscle Development, identical to the target-date path.
  - Finding 3D's relative-load tiers/reserve-reps/sustainable-intent values
    are TrainingOS's own authored product content, not derived from any
    source workbook — worth Stefan's own sanity check against real dogfood
    feel.

READY FOR STEFAN TO RESUME MANUAL DOGFOODING: YES
```
