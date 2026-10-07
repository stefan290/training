# Independent verification: codex/distinct-functional-training-styles (PR #4, round 2 — fixed)

**Verified commit:** `8e8adc2c16f5b0712d8e93c30c993dd3b8a32106`
**Base stated by the author:** `82538a6b882ded9c02ae2f3402f4cea2728ca7dc` (round-1 head, previously
verified as NOT fully passing — see `verify/codex-distinct-training-styles-82538a6`).

Per `app/DISTINCT_TRAINING_STYLES_VERIFICATION.md`'s "Follow-up: conditioning family correction"
section (committed at this verified commit), the fix changes exactly one line in
`FunctionalFitnessConfiguration.swift`: when conditioning is included, Functional Strength now
resolves `sessionFamily` to `.mixedResistanceWorkCapacity` instead of `.resistanceDominant`
(which composes zero conditioning roles). This package is that fix's independent,
real-build/real-test/real-simulator verification.

## Method

Same discipline as every prior PR verification in this series: a dedicated `git worktree`
checked out at the exact commit above (main working copy never touched), a dedicated separate
`-derivedDataPath`, exactly one `xcodebuild` process at a time. No application code was changed.
No merge was performed.

## 1. Build for testing

Command: `00-build-for-testing-command.txt`. Raw log: `01-build-for-testing.log`.
**Result: `** TEST BUILD SUCCEEDED **`, exit 0.**

## 2. Priority tests (the two tests the follow-up explicitly asks to run first)

Command: `02-priority-tests-command.txt`. Raw log: `03-priority-tests.log`.

| Test | Result |
|---|---|
| `FunctionalFitnessProgramGeneratorTests.testFunctionalStrengthConditioningFitsSameBudgetWithProductionCatalog` (the round-1 failure) | **passes** |
| `FunctionalFitnessProgramGeneratorTests.testFunctionalStrengthResolvedFamilyMatchesConditioningChoiceWithAndWithoutHeavyAssignment` (new regression test for this fix) | **passes** |

**`Executed 2 tests, with 0 failures (0 unexpected)`.** The round-1-reported bug is fixed at
the unit-test level, and the new regression test the fix adds is itself genuine and passing.

## 3. Focused tests (the 9 classes required by the verification doc)

Command: `04-focused-tests-command.txt`. Raw log: `05-focused-tests.log`.

All 9 required classes (`FunctionalFitnessProgramGeneratorTests`, `GoalTrainingStyleProductModelTests`,
`ExplicitWeeklyCompositionTests`, `FunctionalFitnessMultiWeekV1Tests`, `TemplateGraphPersistenceTests`,
`GeneralProgrammingAllocationArchitectureTests`, `CrossModalityFunctionalFitnessProgrammingTests`,
`FunctionalFitnessPersistenceTests`, `DogfoodRound2CompletionTests`) ran.

**Aggregate: 277 tests executed, 0 failures (0 unexpected).**

## 4. Full `TrainingOSTests` suite

Command: `06-full-suite-command.txt`. Raw log: `07-full-suite.log`.

**`Executed 1912 tests, with 1 failure (0 unexpected)`** — exactly matching the doc's own
predicted total (1896 + 16 additions = 1912).

**The one failure is a genuine, newly-introduced regression, not a flake and not the
round-1 bug recurring:**

```
RunningAthleteJourneyCompletionScenarioTests.testJ5_HybridMixRunningComponentBecomesExecutableWithoutChangingTheMix
/.../app/TrainingOSTests/RunningAthleteJourneyCompletionTests.swift:336: error:
XCTAssertTrue failed - Running component must resolve to an actual pace within the hybrid
mix — got: RPE 3-3
```

This test builds a hybrid mix using the **legacy** `.functionalFitness` discriminator
(`[(.hypertrophy, 3), (.functionalFitness, 1), (.running, 2)]`, not the new
`.functionalStrength`/`.crossFit` split), accepts it, and asserts the Running component
resolves a real "/km" pace via the calibration/threshold flow. It fails because the Running
component now resolves to an RPE target instead of a pace.

Verified not to be test-order pollution or flakiness: re-run in complete isolation
(`08-isolate-running-test-command.txt` / `09-isolate-running-test.log`) — **same failure,
same assertion, same line.**

Verified to be newly introduced by this exact fix, not a pre-existing gap: grepped both
prior full-suite logs already on disk from this verification series —
`codex-verify-pr3-logs/05-full-suite.log` (commit `38e7cdf`, PR #3) and
`codex-verify-pr4-logs/05-full-suite.log` (commit `82538a6`, PR #4 round 1) — this exact test
name appears and **passes** in both. The one-line conditioning-family fix in this PR has a
real, confirmed side effect on the separate legacy hybrid-mix path that reuses
`.functionalFitness` as one of its mix components.

This is reported here precisely so Codex can fix it; it was not investigated further and no
code was changed.

## 5. Existing-store, non-destructive install — normal launch, no erase/clean-state

Reused the same real pre-existing simulator from the PR #3 verification (`iPhone 17 Pro`,
UDID `A18AB0FB-...`, app data originally from 2026-09-22, carried forward unmodified through
every subsequent PR verification in this series).

Pre-install baseline, captured directly from the on-disk SQLite store (read-only):
`10-pre-install-baseline.txt` — 5 sessions, 18 prescriptions, 8 days, 1 program instance, 1
goal, 0 of every result type (`ZSETRESULT`/`ZWORKOUTRESULT`/`ZFUNCTIONALFITNESSRESULT`/
`ZPERSONALRECORD`). Same honest caveat as every prior checkpoint in this series: no store on
this machine has ever had a real logged result, so no claim is made about logged-result
migration specifically — only about full non-destructive schema/data preservation, which this
directly tests.

Built the full `TrainingOS.app` from the verified commit (`11-app-build.log`,
`** BUILD SUCCEEDED **`). Installed via `xcrun simctl install` — never `erase`, never a clean
reinstall (`12-install.log`). Post-install row counts (`13-post-install-check.txt`): 5
sessions, 18 prescriptions, 8 days, 1 program instance, 1 goal, 0 set results — **identical to
the pre-install baseline.** Launched normally, no `-FFDogfoodCleanState` argument
(`14-launch-result.log`, real PID, no crash).

**Conclusion: this commit's additive schema changes open the pre-existing store without data
loss, without a migration crash, and without resetting it.**

## 6. Live simulator UI walkthrough (device `896F3964-F0BA-47DF-863D-7532BD478E11`, "iPhone 17")

A separate, fresh device was used for the live Build-My-Own-Mix walkthrough (app built and
installed via `18-app-build-device2.log`, `** BUILD SUCCEEDED **`), driven via macOS
accessibility automation (`osascript`/JXA against the Simulator window's real accessibility
tree) — no code changes, no new XCTest, a real interactive walkthrough.

Screenshots referenced below are in `screenshots/`, numbered in the order they were taken.

### 6a. Onboarding -> Build My Own Mix -> 3x Functional Strength (conditioning ON) + 1x CrossFit

Fresh clean-state onboarding, then Build My Own Mix: set Functional Strength to 3
(`screenshots/26-fs3.png`), toggled "Include conditioning in Functional Strength" ON
(`screenshots/27-toggled.png`), added 1 CrossFit (`screenshots/28-crossfit1.png`). "Use This
Mix" confirmed (`screenshots/29-used-mix.png`, "Your Selected Mix: 3× Functional Strength + 1×
CrossFit").

**"Accept & Start Training" first attempt reported success in the accessibility layer but a
direct SQLite query (`SELECT COUNT(*) FROM ZSESSION`) showed 0 — genuinely did not
materialize.** A retry (re-pressing the exact button, confirmed `enabled=true` first)
**did** materialize: the same query then returned 4 (`screenshots/30-accepted.png`). This
false-positive-then-real-success pattern on the first "Accept & Start Training" press matches
what was separately observed and disclosed in the round-1 PR #4 verification for the same
button/mix combination — not a new issue, but reconfirmed, and not fixed here (out of scope,
reported for awareness).

**A second, distinct, and new issue was found here:** after the successful retry, the screen
remained on the same "Your Plan" confirmation view, still showing the leftover error text
"Your plan could not be started. Nothing was changed." *alongside* a fully-functional "Accept &
Start Training" button — even though the database already showed 4 real sessions across 2
active `ProgramInstance`s (one per component: "1-Day CrossFit" and "3-Day Functional
Strength" — this split into two instances for one mix is itself correct/expected, not a bug).
`/tmp/jxa_click.sh "View Week"` returned `NOT FOUND` on this exact screen
(`screenshots/32-recheck.png`), because "View Week" is a Today-tab affordance, not present on
this confirmation screen — not itself a bug, just a screen-state mismatch in this report's own
earlier navigation assumption. **The stale error banner co-existing with a real, successful
acceptance is a genuine UI-state bug**: a user would have no way to tell, from this screen
alone, that their plan actually started. A full app restart (terminate + launch, no
clean-state flag — confirmed via a new PID) resolved it: Today then correctly showed "Your
plan starts Monday, 12 October" with a working "View Week" link (`screenshots/35-after-restart.png`).

### 6b. Functional Strength with conditioning — direct content confirmation

Navigated Today -> View Week -> Next Week -> Week 1. All three Functional Strength sessions
(Mon/Tue/Wed) show identically: **"FUNCTIONAL BODYBUILDING, 3 exercises"** followed by
**"CONDITIONING, AMRAP 12min"** (`screenshots/37-week1.png`). Opened one directly
(`screenshots/38-fs-session-detail.png`):

- **"Target 45 to 60 min. Estimated 50 min including warmup, set rest and transitions."** —
  matches the doc's own stated "50 with it [conditioning]" exactly.
- **3 resistance exercises, each `4 × 8–12 @ 3 RIR`**: Back Squat, Barbell Hip Thrust, Barbell
  Bench Press — matches "three resistance patterns... 8-12 reps at 3 RIR, four sets" exactly.
- **Conditioning block after the resistance body**: "AMRAP 12min · Row Erg 200m · Pull-up 8
  reps" — resistance-before-conditioning order confirmed directly, not inferred.

Started this session ("Start Today Instead", confirmed via DB: Session moved to a new real Day
row for today, 2026-10-07, flipped to `inProgress` with a real `startedAt` timestamp). Entered
the live Back Squat execution screen (`screenshots/43` onward):

- **"Rest 2 min between sets" is shown directly on the live execution screen**, under "Set 1
  of 4 · 8–12 reps · RIR 3" (`screenshots/43-block-tap.png`, confirmed again in
  `screenshots/46`/`48`/`51`) — directly confirms "two minutes of recovery between sets are
  stored on the actual prescribed sets and shown during execution."
- Logging an actual set (to observe a live post-set rest-timer countdown, beyond the static
  "Rest 2 min" label already confirmed above) was blocked by the same host-automation
  limitation already disclosed in the PR #3 verification report: the "Confirm & Continue"
  button on the one-time 10RM calibration prompt reports a successful press
  (`enabled=true`) but the text field clears without the screen advancing, on 2 separate
  attempts with 2 different click strategies (fuzzy text match and exact-description AXPress).
  This is a host accessibility-automation flakiness, not re-attempted further per the explicit
  instruction not to loop indefinitely on blocked UI automation — the static rest-duration
  display above is the direct confirmation obtained instead.

### 6c. CrossFit — a genuine, directly-confirmed content gap

Opened the CrossFit session (Monday's other "Week 1 — Session 1", `screenshots/50-crossfit-session.png`):

- A **HYPERTROPHY** block with 2 exercises (Back Squat, Barbell Bench Press) — present and
  correct.
- A **FUNCTIONAL FITNESS** block (the WOD slot) showing **"No prescription."**

This is not a display artifact. Direct SQLite inspection of the same store confirms it: this
session's `WorkoutBlock` of type `functionalFitness` (`Z_PK=3`) has **no** corresponding row in
`ZFUNCTIONALFITNESSPRESCRIPTION` at all — the three `FunctionalFitnessPrescription` rows that
do exist in this store all belong to the three Functional Strength sessions' conditioning
blocks, not to CrossFit's own block.

**This directly contradicts the verification doc's own stated behavior**: "CrossFit retains
its existing authored variation and strength/skill emphasis, and includes a WOD block even
where a goal-biased legacy recipe would have omitted conditioning." In this exact mix (3×
Functional Strength + 1× CrossFit, built via Build My Own Mix), the materialized CrossFit
session's WOD block is empty. Reported here precisely, with both the UI screenshot and the
underlying row-level DB evidence, so Codex can locate and fix it; not investigated further and
no code was changed.

### 6d. Persistence after restart

Confirmed twice, independently, via two separate full app restarts (terminate + launch, no
clean-state flag, each confirmed via a genuinely new PID):

1. After "Accept & Start Training" succeeded, a restart correctly showed the accepted plan on
   Today (`screenshots/35-after-restart.png`) — the mix selection and the training-year phase
   data survived.
2. After starting the Functional Strength session via "Start Today Instead" (which the Today
   tab did not immediately reflect without a restart — the same general class of
   stale-view-after-mutation issue as 6a, reported for awareness, not separately re-described),
   a restart correctly showed "Week 1 — Session 1 · In Progress · Resume"
   (`screenshots/41-today-after-restart2.png`), and resuming it landed back on the exact same
   session state (0/3 exercises completed, both blocks still Pending) with no data loss.

Final live app state was deliberately left open on this in-progress Functional Strength
session's block list (`screenshots/51-final-state.png`) for the requested user testing.

## Conclusion

**Does not cleanly pass**, but the originally-reported round-1 bug is genuinely fixed, and most
of what was still unconfirmed in round 1 is now directly confirmed:

- Build: succeeds.
- The two priority tests (the round-1 failure + the new family-resolution regression test):
  both pass.
- Focused tests (9 classes, 277 total): all pass.
- Full suite (1912, matching the doc's predicted total exactly): **1 new, confirmed,
  non-flaky regression** — `RunningAthleteJourneyCompletionScenarioTests.testJ5_HybridMixRunningComponentBecomesExecutableWithoutChangingTheMix`,
  a real side effect of this fix on the separate legacy hybrid-mix path.
- Existing-store non-destructive install/launch: confirmed clean, no data loss.
- Functional Strength with conditioning: **directly confirmed** — correct 3-exercise +
  12-minute-AMRAP structure, correct 50-minute estimate, correct exercise prescriptions,
  resistance-before-conditioning order, and "Rest 2 min between sets" shown live during
  execution.
- CrossFit: **a genuine, directly-confirmed bug** — its WOD block is empty ("No prescription")
  in this exact mix, contradicting the doc's own stated behavior. Confirmed both visually and
  at the database row level.
- Persistence after restart: confirmed, twice, independently.
- A stale-UI-state issue was also found and disclosed (6a): a successful plan acceptance can
  leave the confirmation screen showing a leftover failure message until the app is restarted.

No code was changed to produce this package. No merge was performed.
