# Round 5: one context for acceptance, calibration and execution

Round 4's isolated acceptance context passed the retry check but regressed
Finding Q set logging and J3 running calibration. It also passed the original
reviewed mix graph into another context. Acceptance now uses the caller context
throughout, disables autosave during the synchronous attempt, and explicitly
restores the original Goal.plans inverse before and after rollback. Existing
plans and pre-acceptance user work are preserved. No inserted model is reused
on retry. The successful reviewed mix retains the caller context identity.

These are proposed repairs, NOT Mac-verified. Do not approve from static review.
Expected suite count remains 1914; existing assertions are strengthened.

1. Verify the exact published SHA in a separate worktree and DerivedData.
   Every build command must use an explicit absolute -project path.
   For test-without-building -xctestrun use the absolute artifact from that build
   (xcodebuild prohibits combining -xctestrun and -project).
2. Run independently first:
   - StrategicPlanSelectionTests/testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError
   - DogfoodRound2CompletionTests/testFindingQ_AllCalibrationsResolveIntoRealReachableSetExecutionNeverALoop
   - RunningAthleteJourneyCompletionScenarioTests/testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable
3. Run all StrategicPlanSelectionTests and the existing focused classes below,
   including J5, then the entire TrainingOSTests suite if focused checks pass.
4. Preserve existing stores. Check acceptance to Today, conditioning and CrossFit
   content, then calibration and logging a real set in the accepted plan, including
   relaunch and confirmation the result persists. Disclose any UI limitations.
5. Publish exact commands, raw logs, SHA, screenshots and database evidence.
   No code changes, no merge, no indefinite automation loops.

# Round 4: isolate failed acceptance from the caller's cached graph

The round-3 verification at ef52b47 reproduced a duplicate TrainingPlan on
failure followed by retry. Acceptance now stages against a separate
ModelContext with autosave disabled, using that context's own fetched Goal,
User, environment and exercise catalog. The reviewed, uninserted mix and exact
proposal phase values are preserved. Only one final save commits the plan and
first sessions. Failed work never attaches a plan to the caller's Goal.

The existing retry regression additionally saves the caller after failure and
after success, then checks fresh contexts and the persisted Goal.plans inverse.
No new test method is added: expected full suite count remains 1914.

Mac verification:
1. Confirm exact published SHA. Separate worktree and DerivedData. Include an
   explicit absolute -project path in EVERY xcodebuild command.
2. First run StrategicPlanSelectionTests/testFailedAcceptanceRollsBackPartialPlanAndRetryClearsError
   in isolation. Then all StrategicPlanSelectionTests, J5, and the existing
   focused classes below. Run the full TrainingOSTests suite if they pass.
3. Confirm fresh-context counts after caller saves: zero plans/phases/instances/
   sessions after failure; one plan, four sessions and one Goal.plans entry after
   retry. Verify successful first-attempt acceptance still reaches Today.
4. Recheck mixed Functional Strength/CrossFit WOD content and restart persistence.
   Preserve existing data. Disclose if logged result tables are empty.
5. Publish exact SHA, commands, raw logs and observed simulator results. No code
   changes or merge. Do not loop on inaccessible UI failure injection.

Xcode and SwiftData execution remain unverified in the Linux authoring environment.

# Round 3: CrossFit WOD and acceptance recovery

Independent round-2 evidence at `verify/codex-distinct-training-styles-8e8adc2`
confirmed functional strength conditioning, but an empty CrossFit WOD and a
failed acceptance leaving a partial active plan. CrossFit resistance-only
families now use the existing authored mixed work-capacity WOD shape; heavy
resistance assignments stay separate and unchanged. Acceptance saves existing
work first, rolls back unsaved partial acceptance on error, rebuilds the
review selection for retry, and requires the final save to succeed.

The J5 raw failure was `RPE 3-3`: it selected the first non-nil intensity from
an unordered relationship, including legitimate source RPE warmup/cooldown
blocks. The test now requires all threshold targets to resolve to pace and
RPE targets to remain RPE. No running prescription or calibration code changed.
An isolated repeated failure establishes reproducibility on that build, but
not causation by a change scoped to functional-strength recipes.

Mac verification required, no author Xcode pass claimed:
1. Build exact new PR head in separate worktree/DerivedData.
2. Run J5, StrategicPlanSelectionTests (including both new integration tests),
   and FunctionalFitnessProgramGeneratorTests, then all prior focused classes.
3. If those pass, run full suite. Expected count 1914; report actual result.
4. On a NEW proposed mix, inspect 3 Functional Strength with conditioning +
   1 CrossFit: first acceptance succeeds, confirmation exits, real WOD content
   persists after restart. Existing accepted historical sessions are not rewritten.
5. Exercise missing-environment failure and recovery: no partial active plan,
   selection retained, corrected retry succeeds without stale error or duplicates.
6. Preserve existing store and publish commands/raw logs/screenshots/exact SHA.
   No code changes, merge, data erase or indefinite automation retries.

# Distinct functional training forms

## Author status

Code and regression tests authored on Linux. Swift, Xcode, XCTest and the
simulator are unavailable here. No build or test pass is claimed by the author.
Base: PR #3, `38e7cdfe9d1b9f97ee6df6537c7fcb6496503703`.

## Follow-up: conditioning family correction

The verification of `82538a6` found a real failure in
`testFunctionalStrengthConditioningFitsSameBudgetWithProductionCatalog`:
`environmentIncompatible` with no missing equipment. The conditioning opt-in
had retained `resistanceDominant`, whose composer intentionally requests zero
conditioning roles. Functional Strength now resolves to
`mixedResistanceWorkCapacity` when conditioning is selected, reusing its
existing two-role finisher. Strength-only retains `resistanceDominant`.
No existing accepted sessions or results are rewritten.

Verify the new PR head, not `82538a6`. Run the previously failing test and
`testFunctionalStrengthResolvedFamilyMatchesConditioningChoiceWithAndWithoutHeavyAssignment`
first, then the focused classes and full suite below. The existing four-week
production-catalog test must produce real two-role conditioning in every
session, three resistance exercises and the 50-minute total. Complete the
previously unconfirmed live conditioning, CrossFit WOD, rest and restart
checks. Do not erase the existing-store simulator. Report UI blockers once.

## Revision: complete functional strength sessions (generator version 2)

The initial two-exercise implementation has been replaced for Functional
Strength. The target is 45 to 60 minutes for the whole session.

- Strength-only: four distinct loaded movement patterns, four sets each.
- With conditioning: three resistance patterns, followed by a 12-minute
  conditioning AMRAP. Conditioning replaces resistance content inside the same
  session budget; it is not added to the full strength-only session.
- Remaining heavy strength responsibilities use the existing generic heavy
  strength prescription in place of one resistance pattern, with no duplicate
  pattern. Other resistance work is TrainingOS-authored 8-12 reps at 3 RIR,
  four sets, calibrated with the existing RM10 policy and progressed from real
  results by the existing shared resistance resolver.
- Two minutes of recovery between sets are stored on the actual prescribed
  sets and shown during execution.
- The materialized Session stores a separate original time estimate, calculated
  from its actual materialized resistance set counts and conditioning format.
  The Session detail shows the target and estimate. Missing content does not
  acquire fictional minutes; estimates outside the target are explicitly shown.

Planning estimates use the existing five-minute WarmupPolicy target, 45 seconds
of work per set, actual between-set rest, and two minutes per exercise for
setup, transitions and lift preparation. These are explicit TrainingOS planning
assumptions, not a tempo instruction, physiological threshold, actual recorded
workout duration or a claim about Marcus Filly's programs. Default recipes
estimate 49 minutes without conditioning and 50 with it. Actual pace can vary.
Warmup still uses the existing relevant-movement generator; its target is not
forced by adding irrelevant filler.

The new authored 8-12 rep resistance content has its own fixed-set authority.
It does not use the legacy RIR-only FF deficit-fill ledger, which could shrink
an entire session to one or two exercises. Broader weekly volume coordination
with other selected programs remains unresolved and must not be claimed solved.
No accepted historical session is regenerated or modified by this change.

Additional additive schema fields: Session.functionalStrengthBudget and
SetPrescription.restAfterSetSeconds. Fresh-context persistence and actual
materialization across four weeks are included in the additional tests.

## Resulting behavior

Build My Own Mix offers Functional Strength and CrossFit as separate rows,
including both in one week. Functional Strength has an explicit Include
conditioning toggle, initially off. Each selected component stores its own
identity and conditioning choice. Ordering follows the visible row order,
replacing dictionary iteration for this editor's submitted selections.

Functional Strength generates an existing resistance main body in every
session, with existing loaded-pattern, assistance and progression authorities.
Its optional conditioning block follows that main body. Generic heavy strength
assignments retain their existing strength prescriptions. CrossFit retains its
existing authored variation and strength/skill emphasis, and includes a WOD
block even where a goal-biased legacy recipe would have omitted conditioning.
The new Functional Strength prescriptions and time assumptions are explicitly
TrainingOS-authored above, while legacy and CrossFit numeric policies remain
unchanged.

Heavy strength exposure allocation uses the whole functional component group,
then distributes assignments to each component's local session indices. Adding
both forms must not double the same remaining weekly exposure requirement.
The existing unsupported six-day functional frequency cannot be bypassed by
splitting it between the two new rows. The total functional frequency is at
most five, within overall availability.

New typed configurations save their resolved intents. Direct styled generator
calls without an authored weekly plan normalize to exact-week intents, so the
materializer cannot accidentally treat them as recurring templates.

Two optional SwiftData fields were added to TrainingMixComponent. Optional
Codable discriminators were added to ModalityPreference and the FF recipe.
Nil retains legacy identity and behavior. Old preferences, old program recipes,
accepted schedules, performance data and PR #3 recommendation snapshots are
not relabeled, deleted or reset. Functional Fitness remains a legacy enum case
for decoding and stored preferences, and is hidden from new style pickers.

## Boundaries

This implements distinct identity, explicit composition and executable block
structure. It is not a complete reproduction of Marcus Filly's paid programs,
and does not invent tempo timings, superset dosing or a new gymnastics skill
curriculum. Existing warmup and movement capability/scaling paths remain in use.
CrossFit does not force a separate gymnastics and strength block into every day.

Legacy recommended mixes remain labeled Functional Fitness and keep their
original recipe. New explicit choices are available through Build My Own Mix.
Style-scoped soft preferences are stored distinctly, but recommendation ranking
still largely compares programming systems. Further work must carry these
choices into automatic recommendations without silently rewriting history.

Heavy strength assignment is coordinated across both functional components.
The broader muscle-volume and conditioning ledgers have not been redesigned
here; complete coordination of every combination toward one goal remains the
next product milestone. Do not describe this checkpoint as the whole app done.

## Reference basis

Product direction: functional strength with optional conditioning; CrossFit as
a separate training choice. Public methodology references, checked 2026-10-06:

- https://functional-bodybuilding.com/pages/getting-started-with-persist-by-marcus-filly
- https://functional-bodybuilding.com/pages/persist
- https://www.crossfit.com/crossfit-methodology
- https://www.crossfit.com/essentials/what-is-a-crossfit-workout

These distinguish controlled resistance work from mixed-modal performance and
support a skill/strength/WOD emphasis without claiming every CrossFit workout
must contain every section. They are not sources for newly invented numbers.
The existing application's authored prescriptions supply all numeric dosing.

## Required Mac verification

1. Separate worktree at the published PR head, record exact full SHA. Separate
   DerivedData, one xcodebuild process at a time. Do not edit or merge.
2. Build for testing. Run these focused classes:
   - FunctionalFitnessProgramGeneratorTests (16 additional regression tests across the PR)
   - GoalTrainingStyleProductModelTests (updated expected label vocabulary)
   - ExplicitWeeklyCompositionTests
   - FunctionalFitnessMultiWeekV1Tests
   - TemplateGraphPersistenceTests
   - GeneralProgrammingAllocationArchitectureTests
   - CrossModalityFunctionalFitnessProgrammingTests
   - FunctionalFitnessPersistenceTests
   - DogfoodRound2CompletionTests
3. If focused tests pass, run full TrainingOSTests. Prior baseline 1896;
   16 additions imply 1912 unless repository changes independently.
4. Existing-store normal launch without erase or clean-state flags. Record
   before/after data counts and verify legacy plans still open. Disclose whether
   the store actually contains logged results. Do not claim logged-result
   migration evidence from a store whose result tables are empty.
5. Real UI smoke test: select Functional Strength without conditioning and
   confirm no WOD; select it with conditioning and confirm resistance before
   conditioning; select CrossFit and inspect its WOD; try a week containing
   both; reopen and confirm stored selections and sessions. Also perform the
   outstanding PR #3 Suggested/Why check if populated history is available.
   Distinguish direct observation from unit-test-backed evidence.
6. Publish exact commands, raw logs, screenshots and an honest report on a
   verification branch. If host automation blocks the UI, disclose it and stop
   retrying indefinitely. Do not change application code to manufacture a pass.


## Round 6: manually confirmed Start Today calibration loop

Round 5's accessibility-only explanation was incorrect. A real session moved
before ProgramInstance.startDate was excluded from week-zero backfill. Calibration
rows saved, but the active prescriptions stayed unresolved.

The resolver now includes the explicitly supplied execution session (only if it
belongs to the same instance), alongside the ordinary week-zero batch. Calendar
week grouping is unchanged. Submission checks that the original movement really
resolved, exposes a visible error on failure, and emits calibration diagnostics.

Use a separate worktree and DerivedData, with explicit absolute -project paths
(except commands using -xctestrun, which disallow -project).

1. Run DogfoodRound2CompletionTests/testStartTodayBeforeProgramStartCalibrationReachesExecutionAndPersists
   first. It moves the real session four days before instance.startDate using
   StartSessionOnDifferentDayUseCase, resolves all calibrations, logs a real set,
   and reads the saved state through a fresh context. It also checks visible error
   state for invalid input and clearing that error after success.
2. Run Finding Q, the failed-acceptance/retry test, J3 and J5; then all previous
   focused classes and the full suite. Expected total: 1915, report actual counts.
3. Upgrade the existing simulator installation WITHOUT deleting app or data.
   Reproduce on the previously stuck Functional Strength session. Enter each RM,
   confirm the prompt advances and disappears, and log a real set. Restart the
   app and directly confirm the saved set and resolved prescriptions remain.
4. Also check a session left at its original date and real CrossFit WOD content.
   Capture simulator ID, installed SHA, screenshots, database evidence and logs.
   Do not claim accessibility automation is the cause merely because entry fails.
5. Publish raw evidence and report, no code changes or merge. A passing suite is
   not a replacement for manually completing the previously blocked live flow.
