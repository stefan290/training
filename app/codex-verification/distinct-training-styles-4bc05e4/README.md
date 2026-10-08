# Independent verification: codex/distinct-functional-training-styles (PR #4, round 4)

**Verified commit:** `4bc05e4a84240e4d17419cc055efc214ab0361d8`
**Base stated by the author:** `ef52b47d603ca4d7aa4cc0a02ef69017935ef18c` (round 3, previously
verified as NOT fully passing — see `verify/codex-distinct-training-styles-ef52b47`).

Per `app/DISTINCT_TRAINING_STYLES_VERIFICATION.md`'s new "Round 4: isolate failed acceptance
from the caller's cached graph" section, this round targets round 3's own remaining bug: a
retry after a failed "Accept & Start Training" created a duplicate `TrainingPlan`. The fix
(read directly, `git diff ef52b47..4bc05e4`) changes exactly one file,
`StrategicPlanSelectionViewModel.swift`: acceptance now stages the whole
accept→materialize→start sequence against a **separate, isolated `ModelContext`**
(`ModelContext(modelContext.container)`, autosave disabled) using that context's own freshly
fetched `Goal`. Only one final `transaction.save()` commits the plan; on any failure,
`stagedContext.rollback()` discards only that isolated context's own uncommitted graph, never
touching the caller's `modelContext`. On success, the caller's own `goal` is refreshed via a
fresh fetch so the UI's "already accepted" display stays in sync.

## Method

Every `xcodebuild` command in this package includes an explicit absolute `-project` path, per
this round's explicit instruction — the round-3 package disclosed a process error where two
builds silently resolved from the wrong checkout because no `-project`/cwd was pinned. The one
necessary exception: `xcodebuild test-without-building -xctestrun <path>` **rejects** `-project`
outright (`"Cannot use -xctestrun with -project, -workspace or -scheme options"` — confirmed
directly, see `02-isolated-duplicate-plan-test.log`'s first, failed attempt before the command
was corrected). This is not a gap: the `.xctestrun` file is itself an absolute path to the
exact test bundle `01-build-for-testing.log` (which does use `-project`) produced, so no
ambiguity is possible for those invocations regardless. A dedicated `git worktree` was used
throughout (main working copy never touched), a dedicated separate `-derivedDataPath`, exactly
one `xcodebuild` process at a time. No application code was changed. No merge was performed.

## 1. Build for testing

Command: `00-build-for-testing-command.txt` (includes `-project`). Raw log:
`01-build-for-testing.log`. **Result: `** TEST BUILD SUCCEEDED **`, exit 0.**

## 2. Isolated priority test — the round-3 bug, run first as instructed

Command: `02-isolated-duplicate-plan-test-command.txt`. Raw log:
`03-isolated-duplicate-plan-test.log`.

**`StrategicPlanSelectionTests.testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError` —
now passes** (`Executed 1 test, with 0 failures`). This is the exact test that failed in round 3
with `XCTAssertEqual failed: ("2") is not equal to ("1")`. The isolated-transaction-context fix
resolves it.

## 3. All StrategicPlanSelectionTests + J5

Command: `04-full-strategicplan-and-j5-command.txt`. Raw log:
`05-full-strategicplan-and-j5.log`.

**`Executed 28 tests, with 0 failures (0 unexpected)`** — all 27 `StrategicPlanSelectionTests`
(including both new integration tests this round's diff adds: fresh-context counts after a
caller save, and the persisted `Goal.plans` inverse) plus
`RunningAthleteJourneyCompletionScenarioTests.testJ5_...` all pass clean.

## 4. Remaining focused classes — two genuine, new regressions found

Command: `06-remaining-focused-tests-command.txt`. Raw log: `07-remaining-focused-tests.log`.

`FunctionalFitnessProgramGeneratorTests`, `GoalTrainingStyleProductModelTests`,
`ExplicitWeeklyCompositionTests`, `FunctionalFitnessMultiWeekV1Tests`,
`TemplateGraphPersistenceTests`, `GeneralProgrammingAllocationArchitectureTests`,
`CrossModalityFunctionalFitnessProgrammingTests`, `FunctionalFitnessPersistenceTests`,
`DogfoodRound2CompletionTests`.

**`Executed 277 tests, with 2 failures (0 unexpected)`.** One of those 2 is a new regression;
the other (below) surfaced again in the full suite and is reported there with its full detail.

**`DogfoodRound2CompletionTests.testFindingQ_AllCalibrationsResolveIntoRealReachableSetExecutionNeverALoop`
— genuine new regression.** Confirmed absent in round 3 (`verify/codex-distinct-training-styles-ef52b47`'s
own full-suite log: this exact test passed there). Confirmed reproducible in complete isolation
(`08-isolate-findingq-command.txt` / `09-isolate-findingq.log`, same failures). Root cause,
directly visible in the raw log, not guessed:

```
SwiftData.DefaultStore save failed: Multiple validation errors — ExercisePerformanceProfile
is missing required values (id, confidence; exercise is nil), even though it already carries
a real linked PersonalRecord and SetResult.
testFindingQ...:1216: XCTAssertNotNil failed - a real result must be logged and returned
testFindingQ...:1218: XCTAssertEqual failed: ("pending") is not equal to ("active")
```

This test's own flow builds a mix, accepts it, resolves every required calibration, then logs
the first real set through `execVM.logCurrentSet(..., modelContext: context)` — using the
test's **own harness `context`**, the same context the mix/goal were originally built against,
**not** the isolated `transaction` context this round's fix introduces inside `acceptAndStart`.
The save that fails is this later, separate logging call, not anything inside `acceptAndStart`
itself.

## 5. Full `TrainingOSTests` suite

Command: `10-full-suite-command.txt`. Raw log: `11-full-suite.log`.

**`Executed 1914 tests, with 4 failures (0 unexpected)`** — exactly matching the doc's own
stated expectation that the total remains 1914 (no new test methods added this round). The 4
assertion failures are **only 2 distinct failing test methods** (2 assertions fail inside each):

1. `DogfoodRound2CompletionTests.testFindingQ_AllCalibrationsResolveIntoRealReachableSetExecutionNeverALoop`
   — described above.
2. **A second, new regression**, same symptom class:
   `RunningAthleteJourneyCompletionScenarioTests.testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable`.
   Confirmed absent in round 3 (passed in that round's full-suite log). Confirmed reproducible
   in isolation (`12-isolate-j3-command.txt` / `13-isolate-j3.log`):

   ```
   RunningAthleteJourneyCompletionTests.swift:285: XCTAssertFalse failed
     (RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired still true
      after RunningThresholdCalibrationViewModel.completeCalibration(modelContext: context))
   RunningAthleteJourneyCompletionTests.swift:294: XCTAssertTrue failed -
     must contain an actual resolved pace, not only a raw percentage —
     got "RPE 3-3" (full-suite run) / "80-80% Threshold Pace" (isolated run)
   ```

   Same underlying shape as Finding Q above: `runningInstance`/`runningDefinition` are reached
   via `mix.orderedComponents` (resolved before `acceptAndStart` ran), and the calibration is
   submitted via the test's own `context` — not the isolated `transaction` the fix now uses
   internally. The exact fallback label differs slightly between the isolated run and the
   full-suite run (RPE vs. a raw percentage), which is itself worth disclosing honestly: the
   underlying condition (calibration not recognized as resolved, pace not reached) reproduces
   identically either way, but the specific string shown depends on what intensity state existed
   before.

**Both new failures point at the same class of issue**: code that reads or writes through the
original caller `ModelContext` shortly after `acceptAndStart` succeeds — reached via object
references (`mix`, its components, their `programInstance`/`sessions`) obtained *before*
`acceptAndStart` ran — does not reliably observe the real, now-isolated-transaction-committed
object graph. This is offered as the most likely explanation based on what the diff and the two
failures' own log evidence show, not asserted as a proven root cause; it was not investigated
further, per the standing "verify, don't fix" instruction.

## 6. Existing-store, non-destructive install — normal launch, no erase/clean-state

Reused the same real pre-existing simulator from every prior round (`iPhone 17 Pro`, UDID
`A18AB0FB-...`). Pre-install baseline (`14-pre-install-baseline.txt`): 5 sessions, 18
prescriptions, 8 days, 1 program instance, 1 goal, 0 set results — same honest caveat as every
prior checkpoint: no store on this machine has ever had a logged result. Built with an explicit
`-project` path (`15-app-build-existing-device-command.txt` / `16-app-build-existing-device.log`,
`** BUILD SUCCEEDED **`, confirmed via `strings` on the installed binary to contain "Functional
Strength"/"CrossFit" before proceeding). Installed via `xcrun simctl install` — never `erase`
(`17-install.log`). Post-install row counts (`18-post-install-check.txt`): identical to the
baseline. Launched normally, no `-FFDogfoodCleanState` (`19-launch-result.log`, real new PID, no
crash). Screenshot (`screenshots/01-existing-store-launch.png`) shows the real pre-existing
"Rest day / Part of your Muscle Gain phase" content.

## 7. Live simulator UI walkthrough (device `896F3964-F0BA-47DF-863D-7532BD478E11`, "iPhone 17")

Built with an explicit `-project` path (`20-app-build-fresh-device-command.txt` /
`21-app-build-fresh-device.log`, confirmed via `strings`). Fresh clean-state onboarding (Build
Muscle, 7 days/week, Full Gym environment), then Build My Own Mix: both "Functional Strength"
and "CrossFit" rows present and correctly labeled (`screenshots/11-build-own-mix.png`) — set
Functional Strength to 3, toggled conditioning on, added 1 CrossFit
(`screenshots/12-mix-set.png`), "Use This Mix" confirmed (`screenshots/13-used-mix.png`).

**A real, disclosed macOS accessibility-bridge instability occurred mid-walkthrough** (the same
category previously disclosed in the round-2 PR #4 package): the automation bridge to the
Simulator window intermittently reported 0 windows even though the simulator device and app
process remained fully healthy (confirmed via `xcrun simctl list devices booted` and direct
screenshots throughout). Recovered each time via `tell application "Simulator" to activate`
(sometimes requiring a prior `pkill`/relaunch of the GUI, confirmed via `simctl list devices
booted` that devices stayed booted and no data was at risk throughout). No onboarding progress
was lost; this cost wall-clock time, not test validity.

### 7a. First-attempt acceptance succeeds; no duplicate plan — directly confirmed, convergent with Section 2

Database checked immediately before tapping Accept: 0 sessions, 0 training plans. Tapped
"Accept & Start Training" **once** — succeeded immediately, no retry needed. Database
immediately after: **4 sessions, 2 program instances (one per component definition, expected),
exactly 1 `TrainingPlan`** (`screenshots/14-after-accept.png`). The screen transitioned to the
real Today tab on its own — "Your plan starts Monday, 12 October" with a working "View Week"
link — with no stale error and no restart needed. This directly corroborates, on a live single
successful attempt, what Section 2's isolated retry-after-failure test proves more rigorously:
this round's fix does not produce a duplicate plan.

### 7b. CrossFit WOD — real content, confirmed and persisting after restart

Navigated Today → View Week → Next Week → Week 1. Thursday's session (CrossFit's own instance)
shows "CONDITIONING AMRAP 4min" (`screenshots/15-week1.png`). Opened directly
(`screenshots/16-crossfit-wod.png`): 2 resistance exercises (Back Squat, Barbell Bench Press)
plus a real WOD — "AMRAP 4min · Row Erg 200m · Deadlift 8 reps." Restarted the app (terminate +
launch, no clean-state flag, confirmed via a genuinely new PID). Today correctly showed the same
plan state again (`screenshots/17-after-restart.png`), and direct SQLite inspection confirmed
all 4 `functionalFitness`-type `WorkoutBlock`s (the three Functional Strength conditioning
blocks and CrossFit's own WOD) remain linked to their own populated
`FunctionalFitnessPrescription` rows, unchanged, after the restart.

### 7c. Missing-environment failure + retry — not reproducible live, same disclosed limitation as round 3

As in round 3, there is no UI path to remove the only built-in "Full Gym" training environment
to force the exact failure condition `testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError`
constructs directly in Swift. Not retried indefinitely; Section 2's isolated, now-passing test
is the rigorous evidence for this exact scenario.

## Conclusion

**Does not cleanly pass.** The round-3 bug this round explicitly targeted — a duplicate
`TrainingPlan` on retry after a failed acceptance — is **genuinely fixed**: the dedicated
regression test passes in isolation, and a live single successful acceptance attempt shows
exactly 1 `TrainingPlan` with no duplication, corroborating evidence from two independent
sources. CrossFit's WOD and restart persistence remain correct, as in round 3. Successful
first-attempt acceptance reaches Today cleanly.

**Two new, genuine, reproducible regressions were introduced by this round's fix**, both in
the `RunningAthleteJourneyCompletionTests`/`DogfoodRound2CompletionTests` test files, both
confirmed absent in round 3 and confirmed non-flaky in isolation:
`testFindingQ_AllCalibrationsResolveIntoRealReachableSetExecutionNeverALoop` and
`testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable`. Both share the same
underlying symptom shape — a SwiftData validation/consistency failure when code outside
`acceptAndStart` continues to read or write through the original caller `ModelContext` shortly
after acceptance now runs in a separate, isolated transaction context — offered as the most
likely explanation from the direct log evidence, not asserted as a proven mechanism.

Full suite: 1914 executed (exact match to the doc's stated expectation), 4 assertion failures
across these 2 distinct test methods, no others.

Every `xcodebuild` invocation in this package passes an explicit absolute `-project` path,
except the `test-without-building -xctestrun` calls, which `xcodebuild` itself refuses to accept
alongside `-project` — disclosed directly rather than silently worked around.

No application code was changed to produce this package. No merge was performed. No existing
training data, on either simulator used, was erased.
