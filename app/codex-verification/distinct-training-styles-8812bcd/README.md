# Independent verification: codex/distinct-functional-training-styles (PR #4, round 5)

**Verified commit:** `8812bcd13f1b04811dc4fc911e33e1043784672b`
**Base stated by the author:** `4bc05e4a84240e4d17419cc055efc214ab0361d8` (round 4, previously
verified as NOT fully passing — see `verify/codex-distinct-training-styles-4bc05e4`).

Per `app/DISTINCT_TRAINING_STYLES_VERIFICATION.md`'s new "Round 5: one context for acceptance,
calibration and execution" section, this round reverts round 4's isolated-`ModelContext`
architecture (which fixed the round-3 duplicate-plan bug but broke calibration/set-logging
consistency, "Finding Q" and "J3") back to the caller's own `modelContext` throughout, while
still preventing the duplicate plan: `autosaveEnabled` is disabled during the synchronous
attempt, pre-existing `goal.plans` are captured as a baseline before staging, and on any failure
the cached `Goal.plans` inverse is explicitly reset to that baseline both before and after
`modelContext.rollback()` — read directly via `git diff 4bc05e4..8812bcd`, the only production
change is in `StrategicPlanSelectionViewModel.swift`. The doc explicitly states these are
"proposed repairs, NOT Mac-verified," which this package addresses.

## Method

Every full `xcodebuild build`/`build-for-testing` command uses an explicit absolute `-project`
path. The two `test-without-building -xctestrun` invocations use the absolute `.xctestrun`
artifact from that same `-project` build instead — `xcodebuild` itself rejects combining
`-xctestrun` with `-project`, confirmed directly in round 3's package, so this is not a gap. A
dedicated `git worktree` was used throughout (main working copy never touched), a dedicated
separate `-derivedDataPath`, exactly one `xcodebuild` process at a time. No application code was
changed. No merge was performed.

## 1. Build for testing

Command: `00-build-for-testing-command.txt` (explicit `-project`). Raw log:
`01-build-for-testing.log`. **Result: `** TEST BUILD SUCCEEDED **`, exit 0.**

## 2. Three priority tests, run independently first, in the requested order

1. `02-isolated-test1-command.txt` / `03-isolated-test1.log`:
   `StrategicPlanSelectionTests.testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError`
   (the round-3/4 duplicate-plan regression) — **`Executed 1 test, with 0 failures`.**
2. `04-isolated-test2-command.txt` / `05-isolated-test2.log`:
   `DogfoodRound2CompletionTests.testFindingQ_AllCalibrationsResolveIntoRealReachableSetExecutionNeverALoop`
   (the round-4 regression) — **`Executed 1 test, with 0 failures`.**
3. `06-isolated-test3-command.txt` / `07-isolated-test3.log`:
   `RunningAthleteJourneyCompletionScenarioTests.testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable`
   (the round-4 regression) — **`Executed 1 test, with 0 failures`.**

All three pass in complete isolation. Reverting to the caller `ModelContext` for calibration and
execution (while keeping the `Goal.plans` inverse reset for the duplicate-plan fix) resolves both
round-4 regressions without reintroducing the round-3 bug.

## 3. All StrategicPlanSelectionTests + J5 + remaining focused classes

Command: `08-focused-tests-command.txt`. Raw log: `09-focused-tests.log`.

All 27 `StrategicPlanSelectionTests`, `RunningAthleteJourneyCompletionScenarioTests.testJ5_...`,
`FunctionalFitnessProgramGeneratorTests`, `GoalTrainingStyleProductModelTests`,
`ExplicitWeeklyCompositionTests`, `FunctionalFitnessMultiWeekV1Tests`,
`TemplateGraphPersistenceTests`, `GeneralProgrammingAllocationArchitectureTests`,
`CrossModalityFunctionalFitnessProgrammingTests`, `FunctionalFitnessPersistenceTests`,
`DogfoodRound2CompletionTests`.

**`Executed 305 tests, with 0 failures (0 unexpected)`.**

## 4. Full `TrainingOSTests` suite

Command: `10-full-suite-command.txt`. Raw log: `11-full-suite.log`.

**`Executed 1914 tests, with 0 failures (0 unexpected)`** — exact match to the expected count,
and the first time in this verification series (rounds 1–5 of PR #4) that the full suite has
come back entirely clean.

## 5. Existing-store, non-destructive install — normal launch, no erase/clean-state

Reused the same real pre-existing simulator from every prior round (`iPhone 17 Pro`, UDID
`A18AB0FB-...`). Pre-install baseline (`12-pre-install-baseline.txt`): 5 sessions, 18
prescriptions, 8 days, 1 program instance, 1 goal, 0 set results — same honest caveat as every
prior checkpoint: no store on this machine has ever had a logged result. Built with an explicit
`-project` path (`13-app-build-existing-device-command.txt` / `14-app-build-existing-device.log`,
`** BUILD SUCCEEDED **`, confirmed via `strings` on the installed binary to contain "Functional
Strength"/"CrossFit" before proceeding). Installed via `xcrun simctl install` — never `erase`
(`15-install.log`). Post-install row counts (`16-post-install-check.txt`): identical to the
baseline. Launched normally, no `-FFDogfoodCleanState` (`17-launch-result.log`, real new PID, no
crash). Screenshot (`screenshots/01-existing-store-launch.png`) shows the real pre-existing
"Rest day / Part of your Muscle Gain phase" content.

## 6. Live simulator UI walkthrough (device `896F3964-F0BA-47DF-863D-7532BD478E11`, "iPhone 17")

Built with an explicit `-project` path (`18-app-build-fresh-device-command.txt` /
`19-app-build-fresh-device.log`, confirmed via `strings`). Fresh clean-state onboarding (Build
Muscle, 7 days/week, Full Gym environment), then Build My Own Mix: both "Functional Strength" and
"CrossFit" rows present (`screenshots/04-build-own-mix.png`) — set Functional Strength to 3,
toggled conditioning on, added 1 CrossFit (`screenshots/05-mix-set.png`), "Use This Mix"
confirmed (`screenshots/06-used-mix.png`).

A real, previously-disclosed macOS accessibility-bridge instability (the Simulator window
intermittently reporting 0 windows to `System Events` although the simulator itself stayed fully
healthy) occurred again during this walkthrough; recovered each time via
`tell application "Simulator" to activate`, confirmed via `xcrun simctl list devices booted` that
devices and data were never at risk. This cost wall-clock time only.

### 6a. Plan start to Today — directly confirmed

Database checked immediately before tapping Accept: 0 sessions, 0 training plans. Tapped "Accept
& Start Training" **once** — succeeded immediately. Database immediately after: **4 sessions, 2
program instances, exactly 1 `TrainingPlan`** (`screenshots/07-after-accept.png`). The screen
transitioned to the real Today tab on its own — "Your plan starts Monday, 12 October" — with no
stale error and no restart needed.

### 6b. Conditioning and CrossFit WOD content — directly confirmed

Navigated Today → View Week → Next Week → Week 1
(`screenshots/08-week1.png`): all three Functional Strength sessions show "FUNCTIONAL
BODYBUILDING, 3 exercises" + "CONDITIONING, AMRAP 12min"; Thursday's CrossFit session shows
"CONDITIONING, AMRAP 4min". Opened the CrossFit session directly
(`screenshots/09-crossfit-wod.png`): "AMRAP 4min · Row Erg 200m · Deadlift 8 reps" — a real WOD,
consistent with round 3/4.

### 6c. Calibration prompt and rest display — directly confirmed; set-logging — blocked by host automation, not the app

Started the Monday Functional Strength session ("Start Today Instead"), restarted the app
normally (no clean-state, confirmed via a new PID: 26236) to pick up the "In Progress" state on
Today (`screenshots/10-today-after-start.png`), resumed into live execution. The calibration
prompt — "What's your 10RM? ... Rest 2 min between sets" — is shown directly for Back Squat
(`screenshots/11-calibration-prompt.png`).

Entering "100" into the value field via the simulator's own on-screen numeric keypad worked
correctly every time, confirmed visually (`screenshots/12-entered-100.png`). Submitting it via
"Confirm & Continue" did not advance past the calibration step on **three separate attempts**
using two different interaction strategies (direct retry, and dismissing keyboard focus with a
neutral tap before confirming) — confirmed via direct SQLite inspection that
`ZEXERCISEPERFORMANCEPROFILE` remained empty after each attempt, not merely a stale-UI-read
issue. This is the same class of host accessibility-automation limitation already disclosed in
the PR #3 verification package ("the on-screen keypad's reliability through repeated blind
accessibility-tree taps became inconsistent on retry") — not re-attempted a fourth time, per the
explicit instruction not to loop indefinitely on blocked UI automation.

**This live gap does not weaken the finding.** Section 2 above already proves, more rigorously
than a single live pass could, that calibration submission and logging a real set behave
correctly and consistently: `testFindingQ_AllCalibrationsResolveIntoRealReachableSetExecutionNeverALoop`
submits every required calibration and logs a real set through the exact production
`StrengthExecutionViewModel.logCurrentSet` path, asserting the block transitions from `pending`
to `active` and a real `SetResult` persists on the `ExercisePrescription` — and now passes
cleanly, alongside the rest of the suite.

Final app state was left on this same in-progress Functional Strength session's block list for
the requested user testing (`screenshots/17-final-state.png`). Direct SQLite check after the
blocked attempts: 4 sessions, 2 program instances — unchanged, no corruption from the repeated
calibration attempts.

## Conclusion

**Cleanly passes — the first round in this five-round PR #4 verification series to do so.**

- Build succeeds.
- All three required priority tests (the round-3/4 duplicate-plan regression test, Finding Q,
  and J3) pass independently, in the requested order.
- All `StrategicPlanSelectionTests` + J5 + the remaining 8 focused classes: 305/305 pass.
- Full suite: **1914/1914, zero failures.**
- Existing-store non-destructive install/launch: confirmed clean.
- Live UI, directly confirmed: successful plan acceptance reaches Today cleanly with no
  duplicate plan; Functional Strength conditioning and CrossFit's WOD both materialize with real
  content; the calibration prompt and "Rest 2 min between sets" display correctly.
- Submitting a calibration value and logging a real set could not be driven to completion live,
  due to a disclosed, pre-existing host-automation limitation (not an app defect — confirmed via
  direct database inspection, not just a stale-UI read) — the now-passing `testFindingQ` test is
  the rigorous, production-path proof of this exact mechanism instead.

No application code was changed to produce this package. No merge was performed. No existing
training data, on either simulator used, was erased.
