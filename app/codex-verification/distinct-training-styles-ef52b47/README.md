# Independent verification: codex/distinct-functional-training-styles (PR #4, round 3)

**Verified commit:** `ef52b47d603ca4d7aa4cc0a02ef69017935ef18c`
**Base stated by the author:** `8e8adc2c16f5b0712d8e93c30c993dd3b8a32106` (round 2, previously
verified as NOT fully passing — see `verify/codex-distinct-training-styles-8e8adc2`).

Per `app/DISTINCT_TRAINING_STYLES_VERIFICATION.md`'s new "Round 3: CrossFit WOD and acceptance
recovery" section (committed at this verified commit), this round targets the two problems the
round-2 package found: CrossFit's WOD block materializing empty, and a failed "Accept & Start
Training" leaving the confirmation screen stuck on a stale error alongside a partially-active
plan. This package is that fix's independent, real-build/real-test/real-simulator verification.

The actual diff between `8e8adc2` and `ef52b47` is three production files
(`FunctionalFitnessConfiguration.swift`, `FunctionalFitnessPhaseBiasPolicy.swift`,
`StrategicPlanSelectionViewModel.swift`) plus two test files. Read directly before testing:
CrossFit now re-maps `resistanceDominant`/`heavyStrength`/`powerAthletic` families to
`mixedResistanceWorkCapacity` and applies the existing work-capacity WOD shape generator.
Acceptance now explicitly saves existing work first, and on any later failure calls
`modelContext.rollback()` and rebuilds the review selection for retry, with the final save
changed from `try?` (silently swallowed) to `try` (now participates in the catch/rollback path).

## A process error caught and corrected before any findings were recorded

While building the live-UI-walkthrough app binary and the existing-store binary, the two
`xcodebuild build -scheme TrainingOS -destination id=...` commands were issued without an
explicit `-project` path. Because of how this session's shell cwd persists between tool calls,
both commands silently resolved the project from `/Users/stefankedling/Desktop/training/app`
(the **main working-copy checkout**, commit `a61d823`, which predates PR #4 entirely) instead of
this round's isolated worktree. The symptom was caught immediately: the installed app's Build My
Own Mix screen showed only a single legacy "Functional Fitness" row, not the expected separate
"Functional Strength"/"CrossFit" rows. Before concluding this was a regression, the installed
binary was inspected directly — `strings` on `TrainingOS.debug.dylib` found no "Functional
Strength" or "CrossFit" literals at all, proving the wrong checkout had been compiled. Both
builds were redone with an explicit `-project <worktree>/TrainingOS.xcodeproj` path, confirmed via
`strings` to contain the correct literals before any further verification proceeded. All
test-only steps (`xcodebuild test-without-building -xctestrun ...`) were unaffected by this
error — they reference the already-built `.xctestrun` artifact from the one build-for-testing
step that did correctly `cd` into the worktree first, and every failing/passing test's file path
in the logs below is the worktree's own path, confirmed. Only the two full `.app` builds (and
everything built on top of them) were redone; the corrected logs are the `*-REDO*` files below,
and are the only app-build artifacts included in this package.

## Method

Same discipline as every prior PR verification in this series: a dedicated `git worktree` checked
out at the exact commit above (main working copy never touched, confirmed exactly by the process
error above), a dedicated separate `-derivedDataPath`, exactly one `xcodebuild` process at a time.
No application code was changed. No merge was performed.

## 1. Build for testing

Command: `00-build-for-testing-command.txt`. Raw log: `01-build-for-testing.log`.
**Result: `** TEST BUILD SUCCEEDED **`, exit 0.**

## 2. Priority tests (J5, StrategicPlanSelectionTests, FunctionalFitnessProgramGeneratorTests)

Command: `02-priority-tests-command.txt`. Raw log: `03-priority-tests.log`.

**`Executed 55 tests, with 1 failure (0 unexpected)`.**

- `RunningAthleteJourneyCompletionScenarioTests.testJ5_HybridMixRunningComponentBecomesExecutableWithoutChangingTheMix`
  (the round-2 regression) — **passes.** The fix described in the doc (require every threshold
  target to resolve to pace and every RPE target to remain RPE, rather than picking the first
  intensity from an unordered relationship) is confirmed correct at the test level.
- `FunctionalFitnessProgramGeneratorTests` (27 tests) — **all pass.**
- `StrategicPlanSelectionTests` (27 tests) — **26 pass, 1 fails:**

**`testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError` — a genuine, reproducible bug,
not fixed by this commit:**

```
StrategicPlanSelectionTests.swift:581: error: XCTAssertEqual failed: ("2") is not equal to ("1")
```

Read directly (`StrategicPlanSelectionTests.swift:560-585`): the test builds a 3×Functional
Strength + 1×CrossFit mix, removes the athlete's training environment to force
`acceptAndStart` to fail, confirms the failure rolls back cleanly (`TrainingPlan`/`Session`/
`ProgramInstance` counts all empty — these three assertions **pass**), restores the
environment, retries `acceptAndStart` — which itself succeeds (`didSucceed == true`,
`errorMessage == nil`, confirmed) — and then asserts exactly 1 `TrainingPlan` exists. The actual
count is 2: **the retry after a rolled-back failure creates a duplicate `TrainingPlan`
alongside the one from the successful attempt**, rather than cleanly producing just one. This is
precisely the scenario the round-3 doc's own point 5 asks to verify ("corrected retry succeeds
without stale error **or duplicates**") and precisely what this task's own instruction asked to
confirm — the duplicate does occur, at the `TrainingPlan` level, confirmed reproducible in
complete isolation (`03b-isolate-duplicate-plan-test-command.txt` / `03c-isolate-duplicate-plan-test.log`,
same exact assertion, same count, re-run alone with no other tests sharing state).

## 3. Remaining 8 focused classes

Command: `04-remaining-focused-tests-command.txt`. Raw log: `05-remaining-focused-tests.log`.

`GoalTrainingStyleProductModelTests`, `ExplicitWeeklyCompositionTests`,
`FunctionalFitnessMultiWeekV1Tests`, `TemplateGraphPersistenceTests`,
`GeneralProgrammingAllocationArchitectureTests`, `CrossModalityFunctionalFitnessProgrammingTests`,
`FunctionalFitnessPersistenceTests`, `DogfoodRound2CompletionTests`.

**`Executed 250 tests, with 0 failures (0 unexpected)`.**

## 4. Full `TrainingOSTests` suite

Command: `06-full-suite-command.txt`. Raw log: `07-full-suite.log`.

**`Executed 1914 tests, with 1 failure (0 unexpected)`** — exactly matching the doc's own
predicted total. **The single failure is the same `testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError`
reported above — no other test fails anywhere in the suite.** In particular, confirmed clean this
round: the J5 Running regression from round 2 is gone, and the CrossFit/conditioning-family fix
from round 2 remains clean.

## 5. Existing-store, non-destructive install — normal launch, no erase/clean-state

Reused the same real pre-existing simulator from the PR #3/round-2 verifications (`iPhone 17 Pro`,
UDID `A18AB0FB-...`, app data originally from 2026-09-22, carried forward unmodified).

Pre-install baseline (`08-pre-install-baseline.txt`): 5 sessions, 18 prescriptions, 8 days, 1
program instance, 1 goal, 0 set results — same honest caveat as every prior checkpoint: no store
on this machine has ever had a logged result, so no claim is made about logged-result migration
specifically. Built the full `TrainingOS.app` from the verified commit with an explicit
`-project` path (`09b-app-build-existing-device-REDO.log`, `** BUILD SUCCEEDED **`, confirmed via
`strings` to contain "Functional Strength"/"CrossFit"). Installed via `xcrun simctl install` —
never `erase` (`10b-install-REDO.log`). Post-install row counts
(`11b-post-install-check-REDO.txt`): identical to the pre-install baseline. Launched normally, no
`-FFDogfoodCleanState` (`12b-launch-result-REDO.log`, real new PID, no crash).
Screenshot (`screenshots/13b-existing-store-launch-REDO.png`) shows the real pre-existing
"Rest day / Part of your Muscle Gain phase" content, not a reset/onboarding state.

**Conclusion: this commit's changes open the pre-existing store without data loss, without a
migration crash, and without resetting it.**

## 6. Live simulator UI walkthrough (device `896F3964-F0BA-47DF-863D-7532BD478E11`, "iPhone 17")

Fresh clean-state onboarding (Build Muscle, 7 days/week, Full Gym environment) on the correctly
rebuilt binary (`14b-app-build-fresh-device-REDO.log`, confirmed via `strings`), then Build My Own
Mix: both "Functional Strength" and "CrossFit" rows present and correctly labeled
(`screenshots/17b-build-own-mix-REDO.png`) — set Functional Strength to 3
(`screenshots/18b-fs3.png`), toggled conditioning on, added 1 CrossFit
(`screenshots/19b-mix-set.png`), "Use This Mix" confirmed ("3× Functional Strength + 1×
CrossFit", `screenshots/20b-used-mix.png`).

### 6a. First acceptance succeeds; confirmation screen exits cleanly — the round-2 bug is fixed

Database checked immediately before tapping Accept: 0 sessions, 0 program instances. Tapped
"Accept & Start Training" **once** — no retry needed this time (unlike both round 1 and round 2,
where the first tap silently failed and a second press was required). Database immediately after:
**4 sessions, 2 program instances (one per component definition — "3-Day Functional Strength" and
"1-Day CrossFit" — this split is expected, not a bug), exactly 1 `TrainingPlan`**
(`screenshots/21b-after-accept.png`). Critically, **the screen transitioned to the real Today tab
on its own** — "Your plan starts Monday, 12 October" with a working "View Week" link
(`screenshots/21b-after-accept.png` itself already shows Today, not a stuck confirmation screen) —
with **no app restart needed** to clear it, unlike round 2 where the same confirmation screen was
found still showing a stale "Your plan could not be started" error after a successful accept.
This directly confirms the acceptance-recovery fix for the success path.

### 6b. CrossFit — a real WOD, directly confirmed, both on screen and at the database row level

Navigated Today → View Week → Next Week → Week 1. Thursday's session (CrossFit's own "Week 1 —
Session 1", a separate `ProgramInstance` from the three Functional Strength sessions) now shows
**"CONDITIONING AMRAP 4min"**, not round 2's "No prescription"
(`screenshots/22b-week1.png`). Opened it directly (`screenshots/23b-crossfit-wod.png`):

- 2 resistance exercises (Back Squat, Barbell Bench Press) under "FUNCTIONAL BODYBUILDING" — the
  generic heavy-strength assignment, present and correct.
- **A real WOD**: "AMRAP 4min · Row Erg 200m · Deadlift 8 reps."

Confirmed this is not a display artifact: direct SQLite inspection shows the session's
`functionalFitness`-type `WorkoutBlock` (`Z_PK=8`) is linked to a real
`FunctionalFitnessPrescription` row (`Z_PK=2`, `archetype=functionalBodybuilding`,
`workoutFormatCapSeconds=240` — matching the displayed "AMRAP 4min" exactly). Every
`functionalFitness`-type block across all 4 materialized sessions in this mix (both the three
Functional Strength conditioning blocks and CrossFit's own WOD block) now has its own populated
prescription row — the round-2 gap (CrossFit's own block having no prescription row at all) does
not reproduce here.

### 6c. Persistence after restart

Terminated and relaunched normally (no clean-state flag, confirmed via a genuinely new PID:
82828). Today correctly showed "Your plan starts Monday, 12 October" again
(`screenshots/24b-after-restart.png`) — no data loss. Re-queried the same CrossFit WOD block
directly from SQLite after the restart: still 4 sessions total, block 8 still linked to the same
prescription row 2 (`archetype=functionalBodybuilding`, `workoutFormatCapSeconds=240`) — **the
real WOD content persists byte-for-byte across a full app restart**, not just within the same
process.

### 6d. Missing-environment failure + retry (the duplicate-plan check) — not reproducible live, but already proven

The doc's own point 5 and this task's own instruction ask to confirm a failed acceptance (missing
training environment) followed by a corrected retry produces no stale error and no duplicate
plan. Checked Profile → Training Environment: the only environment is "Full Gym," marked
`BUILT-IN`, with no delete/remove affordance in this screen
(`screenshots/26b-training-env.png`) — there is no real UI path to put a fresh athlete into a
"zero training environments" state the way `testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError`
does by directly nilling `user.profile?.defaultTrainingEnvironment` in Swift. This was not forced
through any other workaround (would have required a code change or direct store edit, both out of
scope), and was not retried indefinitely per the standing instruction not to loop on blocked UI
automation. **This live gap does not weaken the finding** — Section 2 above already proves the
exact scenario fails, reproducibly and in isolation, at the unit-test level, which is the more
rigorous and more precise evidence for this exact mechanism than a single live UI pass could have
been anyway.

## Conclusion

**Does not cleanly pass.** Both round-2 problems this round explicitly targeted are **genuinely
fixed and directly confirmed**: CrossFit now materializes a real WOD (confirmed on screen, at the
database row level, and across a restart), and a successful "Accept & Start Training" now exits
the confirmation screen cleanly with no stale error and no restart required. The J5 Running
regression from round 2 is also confirmed fixed (passes in priority tests and the full suite).

**One genuine, reproducible, non-flaky regression remains**, found by this commit's own new test:
`testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError` fails because retrying acceptance
after a rolled-back failure creates a duplicate `TrainingPlan` (2 instead of 1), confirmed
reproducible in complete isolation. This is exactly the "no duplicate plans on failed start +
retry" requirement this round's own doc and this verification's own instructions ask to confirm,
and it is not yet satisfied. No other test in the 1914-test suite fails.

A process error on the verifier's own side (two `xcodebuild` invocations resolving to the wrong
checkout) was caught via direct binary inspection before any conclusion was drawn from it, and
fully corrected; see the dedicated section above. No code was changed to produce this package. No
merge was performed. No existing training data, on either simulator used, was erased.
