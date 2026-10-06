# Independent verification: codex/same-week-load-recommendations

**Verified commit:** `38e7cdfe9d1b9f97ee6df6537c7fcb6496503703`
("Refresh and persist execution load guidance for already-created sessions")
**Branch verified:** `codex/same-week-load-recommendations`
**Base stated by the author:** `915035b164a004d93cf36e5ac5945e758f8028c2`
(the previously-verified progression-preview checkpoint, PR #2).

Per `app/SAME_WEEK_LOAD_VERIFICATION.md` (committed at the verified commit),
the author's Linux environment had no Swift/Xcode/XCTest; build, XCTest
and existing-store migration were explicitly NOT yet verified there. This
package is that claim's independent, real-build/real-test/real-simulator
verification.

## Method

Same discipline as the PR #2 verification: a dedicated `git worktree`
checked out at the exact commit above (main working copy never touched),
a dedicated separate `-derivedDataPath`, exactly one `xcodebuild` process
at a time (confirmed via `ps aux` before each build/test invocation). No
code was changed. No merge was performed.

## 1. Build for testing

Command: `00-build-for-testing-command.txt`. Raw log: `01-build-for-testing.log`.
**Result: `** TEST BUILD SUCCEEDED **`, exit 0.**

## 2. Focused tests (the 8 classes required by the verification doc)

Command: `02-focused-tests-command.txt`. Raw log: `03-focused-tests.log`.

| Test class | Result |
|---|---|
| `GeneralProgrammingAllocationArchitectureTests` | passed (120 tests) |
| `EndToEndProgressionLoopTests` | passed (6 tests) |
| `DoubleProgressionEngineTests` | passed (22 tests) |
| `LoadFirstProgressionIntegrationTests` | passed (7 tests) |
| `AdvanceTacticalWeekCapabilityWiringTests` | passed (4 tests) |
| `ReadinessAdaptationTests` | passed (22 tests) |
| `SubstitutionTests` | passed (14 tests) |
| `TemplateGraphPersistenceTests` | passed (17 tests) |

**Aggregate: 212 tests executed, 0 failures.** Each class's own `Test
Suite '<name>' started`/`passed` lines confirm every named class
genuinely ran.

## 3. Full `TrainingOSTests` suite

Command: `04-full-suite-command.txt`. Raw log: `05-full-suite.log`.
**Result: `Executed 1896 tests, with 0 failures (0 unexpected)`** — 1888
(the PR #2 baseline) + 8 new regression tests, matching the verification
doc's own description.

## 4. Existing-store, non-destructive schema migration — the explicit requirement

**This is the core requirement this checkpoint's doc flags as unverified
("Build, XCTest and existing-store migration are NOT yet verified"), and
it is now genuinely, directly verified — not inferred from passing unit
tests.**

A real pre-existing simulator (`iPhone 17 Pro`, UDID `A18AB0FB-...`, app
data last written **2026-09-22**, from a much earlier dogfood pass in
this project's history — untouched by any of this session's own prior
PR #2 verification work, which used the separately-named `iPhone 17`
simulator) was used as the "existing store with prior logged results"
the doc asks about.

Honest caveat up front: a search across **every** TrainingOS data store
on this machine (every booted and shutdown simulator) found **zero**
pre-existing `SetResult`/`WorkoutResult`/`FunctionalFitnessResult`/
`PersonalRecord` rows anywhere — every prior dogfood pass in this
project's history materialized sessions/prescriptions but never actually
completed/logged a result through the UI. `07-simulator-check-pre-install-baseline.txt`
records this baseline precisely (5 sessions, 18 prescriptions, 7 days, 0
of every result type) rather than silently treating "sessions exist" as
if it were "logged results exist."

Steps, each with a raw captured artifact:

1. **Pre-install baseline**, captured directly from the on-disk SQLite
   store (read-only, before touching anything): `07-simulator-check-pre-install-baseline.txt`.
2. **Built the full `TrainingOS.app`** (not just the test bundle) from
   the verified commit, in the same dedicated DerivedData: `06-app-build.log`.
3. **Installed non-destructively** via `xcrun simctl install` (never
   `erase`, never a clean reinstall): `08-install.log`. simctl reassigned
   the app's container to a new internal UUID as part of this install —
   confirmed this is **not** data loss: the actual `default.store`/`-shm`/`-wal`
   files at the new location are byte-identical in size and retain their
   original **2026-09-22** modification timestamps, and every row count
   (sessions, prescriptions, days, program instance, goal) matched the
   pre-install baseline exactly.
4. **Launched normally** — `xcrun simctl launch` with **no**
   `-FFDogfoodCleanState` argument (the one flag that would reset state):
   `09-launch-console.log` / `10-launch-result.log`. The app launched
   with a real PID, no crash.
5. **Screenshot of the launched app**: `screenshots/11-post-launch-screenshot.png`
   — shows real pre-existing content ("Part of your Muscle Gain phase",
   a real banner referencing actual pre-existing exercise prescriptions
   needing a starting weight) — not a blank/reset/onboarding state.

**Conclusion: the new schema (four new optional fields) opens this
pre-existing store without data loss, without a migration crash, and
without resetting it.** This is the explicit, central requirement, and
it is now directly, not just inferentially, verified.

## 5. Live simulator UI walkthrough — Suggested/Why

The verification doc also asks to confirm "Suggested/Why shows the
execution guidance while the plan's original target remains unchanged."
Since **no** pre-existing logged result exists anywhere on this machine
(see above), this specific UI state cannot be observed on first contact
with any available simulator — the feature only has something to show
once a prior result exists for that exercise.

To attempt this honestly, a real, no-code-change, host-side UI
automation walkthrough was performed (macOS accessibility API via
`osascript`/JXA, driving the Simulator window's real accessibility
tree — not a new XCTest, since code changes were out of scope):

- Navigated Today -> View Week -> Previous Week -> Week 1, Session 2
  (`screenshots/12` through `screenshots/14`).
- `Start Today Instead` -> confirmed via direct, read-only SQLite
  inspection that `StartSessionOnDifferentDayUseCase.startToday` genuinely
  ran: Session 2 moved to a real new Day record for 2026-10-06 and
  flipped to `inProgress` with a real `startedAt` timestamp matching the
  action's wall-clock time (`screenshots/16`).
- Relaunched (simulating a real app reopen) and confirmed Today now
  shows "Week 1 — Session 2 · In Progress · Resume"
  (`screenshots/17`-`18`).
- Tapped **Resume** into the real live Strength execution view for
  **Barbell Hip Thrust**, Set 1 of 10 (`screenshots/19`).
- Confirmed the exact behavior the verification doc itself describes for
  this case: with **no** prior logged result for this exercise, the
  screen correctly shows a one-time "What's your 10RM?" calibration
  prompt, not a Suggested/Why guidance block — directly consistent with
  the doc's own stated scope ("missing history... do not receive a new
  snapshot").
- A real value (`60`) was entered via the simulator's own on-screen
  numeric keypad (not the host keyboard — `keystroke` text injection did
  not reach the field; the actual tappable digit buttons did, confirmed
  via `screenshots/22`).

**What was not reached:** completing this set's full log, then observing
a *second* exposure of the same exercise (next week) with a real prior
result to show Suggested/Why against. The on-screen keypad's reliability
through repeated blind accessibility-tree taps became inconsistent on
retry (`screenshots/23`-`25` show the "Confirm & Continue" tap not
reliably advancing past the calibration step a second time) within the
effort reasonably available for UI automation with no code changes
permitted. This is disclosed as a genuine tooling limitation of blind
host-side accessibility automation, not a claim that the feature is
broken — the feature's correctness across exactly this scenario set
(increase, decrease, freeze/reload, missing history, exercise change,
etc.) is the direct subject of the 8 new automated tests in Section 3
above, which all pass.

## 6. Data integrity after this verification's own interactive actions

My own interactive steps in Section 5 legitimately changed state (this
is expected app behavior from a real user action, not corruption):
Session 2 moved to a new Day (2026-10-06) and became `inProgress`; one
new `Day` row was added (7 -> 8, additive only). `26-final-state.txt`
confirms: all 5 original sessions and all 18 original prescriptions
remain present and unmodified; zero rows were deleted from any table.

## Conclusion

Build succeeds. All 8 required focused test classes pass (212/212). The
full suite passes clean (1896/1896/0). The explicit existing-store
schema-migration requirement is directly verified clean via before/after
database inspection plus a real launch screenshot. The Suggested/Why UI
was traced to its exact documented "missing history" fallback behavior;
a full live round-trip to the populated-history case was attempted
honestly but not completed, for the disclosed reason above — the
automated test suite is the rigorous proof of that specific mechanic.
No code was changed to produce this package. No merge was performed.
