# Distinct functional training forms

## Author status

Code and regression tests authored on Linux. Swift, Xcode, XCTest and the
simulator are unavailable here. No build or test pass is claimed by the author.
Base: PR #3, `38e7cdfe9d1b9f97ee6df6537c7fcb6496503703`.

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
   - FunctionalFitnessProgramGeneratorTests (15 additional regression tests across both commits)
   - GoalTrainingStyleProductModelTests (updated expected label vocabulary)
   - ExplicitWeeklyCompositionTests
   - FunctionalFitnessMultiWeekV1Tests
   - TemplateGraphPersistenceTests
   - GeneralProgrammingAllocationArchitectureTests
   - CrossModalityFunctionalFitnessProgrammingTests
   - FunctionalFitnessPersistenceTests
   - DogfoodRound2CompletionTests
3. If focused tests pass, run full TrainingOSTests. Prior baseline 1896;
   15 additions imply 1911 unless repository changes independently.
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
