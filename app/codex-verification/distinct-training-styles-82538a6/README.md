# Independent verification: codex/distinct-functional-training-styles (PR #4)

**Verified commit:** `82538a6b882ded9c02ae2f3402f4cea2728ca7dc`
("Build complete functional strength sessions within a 45 to 60 minute budget")
**PR:** https://github.com/stefan290/training/pull/4 — confirmed this is the
PR's current head at the time of verification (not the original, replaced
two-exercise version).

Per `app/DISTINCT_TRAINING_STYLES_VERIFICATION.md` (committed at the
verified commit): author status explicitly states no build/test pass was
claimed (Linux authoring environment).

## Overall result: ⚠️ Does NOT fully pass — one real, confirmed defect

**One genuine test failure found and confirmed reproducible:**

```
TrainingOSTests/FunctionalFitnessProgramGeneratorTests.swift:367: error:
-[TrainingOSTests.FunctionalFitnessProgramGeneratorTests
testFunctionalStrengthConditioningFitsSameBudgetWithProductionCatalog] :
failed: caught error: "environmentIncompatible(slot: "Functional Fitness
Session", missingEquipment: [])"
```

This is a real assertion failure from a real test in the PR's own new
regression suite, run against the PR's own unmodified code — not an
artifact of my environment. The test uses
`TrainingEnvironmentTestSupport.full(context:)` (intended to supply every
equipment type) and still throws `environmentIncompatible` with an
**empty** `missingEquipment` list — itself a secondary oddity worth
Codex's attention (an "incompatible" error whose own payload reports
nothing missing suggests the error may be constructed/thrown from the
wrong branch, not just a genuine equipment gap).

**This is reported to Codex to fix — not fixed here. No code was changed.**

## 1. Build for testing

Command: `00-build-for-testing-command.txt`. Raw log: `01-build-for-testing.log`.
**Result: `** TEST BUILD SUCCEEDED **`.**

## 2. Focused tests (9 classes required by the verification doc)

Command: `02-focused-tests-command.txt`. Raw log: `03-focused-tests.log`.

| Test class | Result |
|---|---|
| `CrossModalityFunctionalFitnessProgrammingTests` | passed |
| `DogfoodRound2CompletionTests` | passed |
| `ExplicitWeeklyCompositionTests` | passed |
| `FunctionalFitnessMultiWeekV1Tests` | passed |
| `FunctionalFitnessPersistenceTests` | passed |
| `FunctionalFitnessProgramGeneratorTests` | **FAILED** (1 of its tests — see above) |
| `GeneralProgrammingAllocationArchitectureTests` | passed |
| `GoalTrainingStyleProductModelTests` | passed |
| `TemplateGraphPersistenceTests` | passed |

**Aggregate: 276 tests executed, 1 failure.**

## 3. Full `TrainingOSTests` suite (run anyway, for the requested count/deviation report)

Command: `04-full-suite-command.txt`. Raw log: `05-full-suite.log`.
**Result: `Executed 1911 tests, with 1 failure (1 unexpected)`.**

- Expected count per the doc (1896 baseline + 15 additions): **1911 — exact match.**
- Deviation: **1 failure** — the same single test above; no other failures
  anywhere in the full suite.

## 4. Existing-store normal launch (no erase, no clean-state)

Device: `iPhone 17 Pro`, UDID `A18AB0FB-...` — the same genuine
pre-existing store (2026-09-22 vintage) used for the PR #3 verification.

- Pre-install baseline: `07-pre-install-baseline.txt` — 5 sessions, 18
  prescriptions, 8 days, 1 program instance, 1 goal, **0 of every result
  type** (`ZSETRESULT`, `ZWORKOUTRESULT`, `ZFUNCTIONALFITNESSRESULT`,
  `ZPERSONALRECORD`).
- **Honest disclosure, as the doc explicitly requires: this store does
  not and never has contained logged results.** No claim is made that
  logged-result migration was proven — only that pre-existing
  materialized schedule data (sessions/prescriptions/days) survives.
- Post-install (`09-post-install-check.txt`): identical counts — no data
  lost or altered by the install itself.
- Real launch, no `-FFDogfoodCleanState`: `10-launch-result.log` — real
  PID, no crash.
- `screenshots/11-post-launch.png`: shows real pre-existing content
  ("Muscle Gain phase", banner referencing real existing prescriptions).
- Later in this session, this device's legacy plan (`Week 1 — Session 2,
  In Progress, Recovery, Strength, 4 exercises`) was independently
  re-confirmed intact and openable after a device reboot cycle (see
  Section 6) — further, incidental confirmation of data durability.

**Conclusion: existing-store migration is clean for the data that
actually exists on this store (schedule/prescription data). No claim is
made about logged-result migration specifically, since none exists here
to test.**

## 5. Real UI smoke test — mixed results, honestly reported

### ✅ Directly observed and confirmed

- **Build My Own Mix shows Functional Strength and CrossFit as genuinely
  separate, independently-countable rows** —
  `screenshots/19-build-own-mix.png`. Confirmed directly, not inferred.
- **"Include conditioning in Functional Strength" toggle exists, starts
  OFF** — `screenshots/39-fs3.png` (before toggle) /
  `screenshots/40-toggled.png` (after).
- **Functional Strength WITHOUT conditioning → exactly 4 distinct
  exercises, no WOD**: Back Squat, Barbell Hip Thrust, Barbell Bench
  Press, Barbell Row — each `4 × 8-12 @ 3 RIR` —
  `screenshots/25-session1.png`. Matches the doc's "four distinct loaded
  movement patterns, four sets each" exactly.
- **Time estimate for that exact session**: *"Target 45 to 60 min.
  Estimated 49 min including warmup, set rest and transitions."* — same
  screenshot. **Matches the doc's claimed 49-minute default exactly,
  word-for-word consistent with its stated planning assumptions
  (warmup + set rest + transitions).**
- **A mix combining both forms in one week is genuinely selectable**:
  "3× Functional Strength + 1× CrossFit" was accepted as "Your Selected
  Mix" — `screenshots/43-used-mix2.png`.
- **Existing-store data (a different, earlier plan) survived an
  unplanned device reboot cycle intact** — session/prescription/day
  counts identical before and after (see Section 6) — incidental extra
  confirmation of durability, beyond what was asked.

### ❌ Not confirmed live (disclosed, not fabricated)

- **Functional Strength WITH conditioning**: 3 exercises + 12-minute AMRAP
  + ~50-minute estimate. The mix was successfully configured (3×
  Functional Strength, conditioning toggle ON) but the subsequent
  "Accept & Start Training" step could not be driven to completion by
  host-side UI automation for this specific mix (see Section 7). The
  **automated test suite's own coverage of this exact scenario is the
  one that is failing** (`testFunctionalStrengthConditioningFitsSameBudgetWithProductionCatalog`)
  — so this is not just an automation gap, it is a genuinely open
  question pending Codex's fix.
- **CrossFit's own WOD content**: not reached live, same blocker.
- **Rest shown during live strength execution**: not reached (would
  require completing calibration/logging a set, which the PR #3
  follow-up already showed is fragile to drive via on-screen-keypad
  automation; not re-attempted here given the explicit instruction not
  to loop indefinitely on blocked automation).
- **Selections/sessions persisting after an app restart**: not directly
  re-confirmed for a *new* PR #4-style mix in this session (the
  automation instability intervened first); however, Section 6's
  incidental legacy-plan survival across a full device reboot is strong
  circumstantial evidence this works, and `FunctionalFitnessPersistenceTests`
  (one of the 9 required focused classes) passed clean, directly testing
  exactly this.
- **PR #3's own outstanding Suggested/Why check**: not attempted this
  pass (still blocked by the same lack of pre-existing logged history
  described in the PR #3 verification; not re-attempted given the
  automation instability encountered this session).

## 6. Incidental finding: macOS accessibility-automation instability

Partway through live UI testing, killing/restarting the macOS
`Simulator.app` GUI process (to recover from an unrelated window-handle
issue) caused both booted simulator devices to shut down. **This did
NOT erase or corrupt any app data** — confirmed directly: the existing
store's row counts (sessions, prescriptions, days, program instance,
goal) were byte-for-byte identical before and after, just reassigned to
a new internal container UUID (a known quirk of this Xcode/Simulator
version's container bookkeeping, observed and confirmed non-destructive
three times now across this and the prior PR #3 verification). Both
devices were re-booted and the apps relaunched successfully.

Later, the macOS Accessibility bridge (`System Events` controlling
`Simulator.app`) became unresponsive in a way simple relaunches could
not reliably fix (`windows.length` intermittently returning `0` while
the simulator device itself remained fully healthy, confirmed via direct
`simctl io screenshot`, which does not depend on the accessibility
layer). Per the explicit instruction not to repeat blocked UI automation
in an infinite loop, further live-tap-driven checks (Section 5's
unconfirmed items) were stopped rather than retried indefinitely.

## 7. What this means for "leave the app open on a functional strength session"

Given (a) a real, confirmed test failure exists in the PR's own
suite, and (b) the macOS automation bridge used to drive the simulator
became unreliable late in this session, I am **not** declaring this
verification passed, and am **not** leaving the simulator in a "ready to
try" state implying success. The screenshot in `screenshots/25-session1.png`
is real, genuine, directly-observed evidence of the without-conditioning
case working exactly as specified — if you want to interact with it
live, a fresh clean-state run through Build Muscle → Build My Own Mix →
Functional Strength (count only, conditioning off) → Accept & Start
Training → View Week → Next Week → Session 1 reliably reproduces it,
exactly as captured here.

## Conclusion

Build succeeds. Full suite count is exactly as predicted (1911), with
exactly one real, confirmed, reportable failure — not fixed here, per
instructions. The without-conditioning Functional Strength case is
directly, visually confirmed correct on every claimed dimension (4
exercises, 49-minute estimate, separate CrossFit row, conditioning
toggle). The with-conditioning and CrossFit-WOD cases remain unconfirmed
live, for disclosed reasons (the same defect under test, plus a genuine
automation-environment limitation) — not fabricated, not silently
assumed. No code changed. No merge performed.
