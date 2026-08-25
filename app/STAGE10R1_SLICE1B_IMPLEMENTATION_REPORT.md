# Stage 10R.1 — Slice 1B Implementation Report

**Scope: 3-Day Full Body Hypertrophy, Mesocycle 1 "Basic Hypertrophy,"
SOURCE PROGRESSION + AUTOREGULATION ONLY.** Mesocycle 2/3, the load-first
overlay, and every other Hypertrophy configuration/family remain
untouched. Not committed, not pushed — awaiting manual acceptance.

## Product Constitution Check

1. **What source behavior is authoritative?** The literal, cell-cited
   Mesocycle 1 load formula (`week1 = MROUND(10RM*0.85,5)`, weeks 2-4 =
   the resolved week-1 value × 1.05/1.075/1.1), the literal fixed
   rep/failure schedule (`3/fail,3/fail,2/fail,1/fail`), the literal
   `nextSets = previousSets + pairedRow'sRating` set-autoregulation
   formula, and the literal, cell-cited 24-slot rating-pairing web — all
   recovered and cited in `STAGE10R1_SLICE1B_SOURCE_PROGRESSION_DESIGN.md`.
2. **What TrainingOS infrastructure was reused, not rebuilt?**
   `StrengthProgressionEngine` (`.rmBased`/autoregulated-set-count/
   rep-goal resolution), `SourceCompatibleDeloadStrategy`,
   `PrescriptionTemplate.pairedSlot`, `AutoregulationRatingResolver`,
   `RollTacticalWindowUseCase.strengthSlotContext`'s existing generic
   (non-`.doubleProgression`) branch — **none of these required new
   mechanisms**, only correct wiring/routing for this program, exactly as
   the design pass concluded.
3. **What was retired, and what was kept?** `.doubleProgression`/
   `HypertrophyV2ProgressionEngine`/`DoubleProgressionEngine` lose
   *routing authority* for this specific program's templates only — the
   types themselves are untouched and still compile/run (kept as
   infrastructure for a future load-bias overlay stage, per the user's
   explicit instruction). No file was deleted.
4. **Why this does not silently expand scope?** Mesocycle 2/3 remain
   unimplemented (the day-focus generator still only ever emits Mesocycle
   1's content, regardless of `configuration.phaseType`). The load-first
   overlay was not touched. No other Hypertrophy configuration's
   generator path was touched.
5. **Why the one discovered defect fix (item 14) is in scope.** Restoring
   the real cross-day rating web is Slice 1B's core, explicitly-approved
   deliverable (Decision D) — more than half of the 24 real pairings are
   cross-day. `AutoregulationRatingResolver`'s pre-existing
   "most-recently-completed" lookup had a latent ordering bug that made
   cross-day pairing silently resolve to "no rating" (never surfaced
   before, since every pre-existing pairing was same-day or self-paired).
   Fixing it was necessary to make the approved design's core requirement
   actually work — it is a correctness fix to an existing mechanism's
   candidate-selection logic, not a new training rule, and it changes no
   external behavior for any already-passing scenario (confirmed: the
   full pre-existing suite, including the specific
   `HypertrophyFeedbackTests` fixture that exercises the pre-completion
   case, still passes).

## What changed

- **`TrainingOS/Application/UseCases/HypertrophyProgramGenerator.swift`**
  — `currentVersion` bumped `1 -> 2` (covers Slice 1A's content change and
  Slice 1B's progression change together, since neither shipped a bump
  yet). Added `SourceRatingPairing` struct and
  `threeDayFullBodyMesocycle1RatingPairings: [SourceRatingPairing]` — the
  literal, cell-cited 24-entry pairing table. `generateDayFocusDriven`
  rewritten to build all 24 templates into a day/slot-indexed grid, then
  wire every `pairedSlot` from the real table (replacing Slice 1A's
  temporary self-reference). `makeSourceCategoryTemplate` rewritten to
  build `.rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85,
  laterWeekMultipliers: [1.05,1.075,1.1]))` and the literal
  `repGoalSchedule` (both already-existing top-level constants on this
  type) instead of `.doubleProgression` +
  `HypertrophyV2ProgressionEngine.makeRepGoalSchedule`, and sets
  `AutoregulatedSetCount(baselineSets:, treatMissingRatingAsNoChange:
  true)`.
- **`TrainingOS/Domain/ValueTypes/StrengthProgressionRules.swift`** —
  added `AutoregulatedSetCount.treatMissingRatingAsNoChange: Bool`
  (default `false`, preserving every pre-existing caller's exact
  original behavior).
- **`TrainingOS/Domain/Entities/PrescriptionTemplate.swift`** — added the
  matching flat persisted field
  (`setCountRuleTreatMissingRatingAsNoChange`, default `false`) and wired
  it through the `setCountRule` getter/setter.
- **`TrainingOS/Engines/StrengthProgressionEngine.swift`** —
  `resolveSetCount`'s `.autoregulated` case: a `nil` `autoregulationRating`
  now resolves to an effective rating of `0` ("no change") when
  `config.treatMissingRatingAsNoChange` is `true`, instead of
  unconditionally returning `.calibrationRequired`. The pre-existing
  `max(0, ...)` floor (preventing a negative literal set count) is
  untouched — it pre-dates this slice and is not a
  TrainingOS-designed training-policy minimum.
- **`TrainingOS/Engines/AutoregulationRatingResolver.swift`** — **the one
  discovered defect fix**: `mostRecentlyCompletedPrescription` now ranks
  an actually-completed prescription (`session.completedAt != nil`) above
  any not-yet-completed one outright, before falling back to date
  comparison. See item 14 below for the full root-cause trace.
- **`TrainingOS.xcodeproj/project.pbxproj`** — registered the new test
  file (see below).
- **Test files updated for the routing change** (day names/content
  unchanged, progression assertions updated from `.doubleProgression`/V2
  shape to `.rmBased`/source shape): `HypertrophyDayFocusGenerationTests.swift`
  (baseline-sets equality updated for the new flag; retired
  self-attribution test replaced with a real-pairing-table test and an
  exercise-resolution-independence test; retired V2-shape test replaced
  with an `.rmBased`-shape test; `.calibrationRequired` test updated to
  call `StrengthProgressionEngine` directly), `HypertrophyV2EndToEndTests.swift`
  (its fixture now builds a standalone, hand-authored `.doubleProgression`
  template graph directly — no generator emits that rule any longer for
  any configuration — so the engine itself stays covered by a genuine
  integration-shaped test without depending on a retired routing path),
  `SessionAutoAdvanceTests.swift` (removed its now-always-unreachable
  `.doubleProgression` slot-context branch), `TacticalPlanningOrchestrationTests.swift`
  (updated its real-production-path assertions from the V2 5-10/RIR-3
  shape to the restored literal 3/fail-derived-RIR-0 shape).
- **New: `TrainingOSTests/HypertrophyMesocycle1SourceProgressionTests.swift`**
  — the Part 10 source-derived test matrix (20+ cases): load week 1-4 +
  fixed-anchor proof + equipment-increment rounding, the literal rep
  schedule, autoregulated sets (+1/0/-1/blank-as-no-change/blank-still-
  requires-calibration-elsewhere), the real cross-day pairing table
  proven end to end through the actual `RollTacticalWindowUseCase`
  production path (not just template-level equality), deload
  (first-half/second-half weight, fixed set count, halved-and-floored
  reps, no rating dependency), and routing (`.rmBased` only, reason codes
  are `StrengthReasonCode`, `appliedProgressionReasonCode` stays `nil`).

## 1. Exact source load implementation

`.rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85,
laterWeekMultipliers: [1.05, 1.075, 1.1]))`, resolved by the existing,
unmodified `StrengthProgressionEngine.resolveWeight` — Week 1 =
`equipmentProfile.resolve(rm * 0.85)`; Weeks 2-4 =
`equipmentProfile.resolve(weekOneResolvedWeightKg * multiplier)`, always
off the stored Week-1 anchor, never chained. Rounding goes through the
user's own `EquipmentProfile` increment (e.g. 2.5 kg), never the
source's literal pound-flavored "5."

## 2. Exact source rep/failure implementation

The literal, fixed `repGoalSchedule` (already an existing top-level
constant): `3/fail, 3/fail, 2/fail, 1/fail` — identical for all 24 slots,
never a Stage 10B.6 rep range/RIR trajectory.

## 3. Exact source set-autoregulation implementation

`.autoregulated(AutoregulatedSetCount(baselineSets:, treatMissingRatingAsNoChange: true))`,
resolved by `StrengthProgressionEngine.resolveSetCount`: `sets = previousSets
+ rating`, rating read from `pairedSlot`'s most recently completed
instance via `AutoregulationRatingResolver`, `nil` rating treated as `0`
for this program specifically (Decision A) — every other caller's
`.calibrationRequired`-on-missing-rating behavior is untouched (default
`false`).

## 4. Pairing implementation

`HypertrophyProgramGenerator.threeDayFullBodyMesocycle1RatingPairings` —
the literal 24-entry table transcribed from the workbook (Part 2 of the
design doc), wired onto every `PrescriptionTemplate.pairedSlot` after all
24 templates are built. Proven both at the template level
(`HypertrophyDayFocusGenerationTests`) and end to end through real
materialization/rollForward (`HypertrophyMesocycle1SourceProgressionTests`).
Confirmed orthogonal to exercise resolution (changing which exercise a
category resolves to never changes its pairing).

## 5. Blank-rating behavior

A `nil` autoregulation rating resolves to `0` ("no change") for this
program's templates (`treatMissingRatingAsNoChange: true`), reproducing
the source workbook's own Excel arithmetic. Every other `.autoregulated`
caller in the codebase keeps the original `.calibrationRequired`
behavior — confirmed by a dedicated test
(`testBlankRatingStillRequiresCalibrationForEveryOtherCaller`) and by the
full pre-existing suite staying green.

## 6. Deload routing

Unchanged: `SourceCompatibleDeloadStrategy`, reached automatically the
moment `loadRule` is anything other than `.doubleProgression` (this
program's templates now always are `.rmBased`) — no new deload code.
Verified directly: full Week-1 weight for the first `ceil(dayCount/2)`
days, half for the rest, 2 sets always, `floor(weekOneReps * 0.5)`, no
rating consumed or produced.

## 7. `generatorVersion` behavior

Bumped once, `1 -> 2`, covering Slice 1A's content change and Slice 1B's
progression change together (Decision C). Existing `ProgramDefinition`s
keep whichever version they were generated under and are never mutated;
only a newly-generated definition receives version 2.

## 8. Stage 10B.6 routing removed from this source path

`.doubleProgression`/`HypertrophyV2ProgressionEngine`/
`DoubleProgressionEngine`/the V2 rep-range/RIR trajectory/the V2 RIR-4
deload no longer have routing authority for any 3-Day Full Body
Hypertrophy template — no generator anywhere in the codebase emits
`.doubleProgression` any longer. The code itself is untouched and still
compiles/runs (`HypertrophyV2EndToEndTests.swift` now exercises it via a
standalone hand-built fixture, proving it still works as infrastructure).

## 9. Files changed

Listed in full under "What changed" above — 4 production files edited, 1
xcodeproj registration, 4 test files edited, 1 new test file (with
xcodeproj registration), 2 documentation files.

## 10. Source-derived tests

All 20+ Part-10 matrix items implemented in
`HypertrophyMesocycle1SourceProgressionTests.swift`, plus 3 tests
added/rewritten in `HypertrophyDayFocusGenerationTests.swift`
(source-compatible shape, real pairing table, exercise-resolution
independence). All passing.

## 11. Full-suite result

**787/787 passing, 0 failures**, real `xcodebuild test` (not a
syntax-only check), confirmed twice — once before and once after the
`AutoregulationRatingResolver` fix (which itself was needed to make one
of the new tests pass, and was independently confirmed not to regress
any pre-existing test, including the specific fixture exercising the
pre-completion-rating case it touches).

## 12. Production-path proof

`HypertrophyMesocycle1SourceProgressionTests.testRealCrossDayPairingDrivesTheNextWeeksSetCountEndToEnd`
drives the actual `RollTacticalWindowUseCase.materializeFirstWindow`/
`rollForward` path (not a hand-injected `ProgramInstance`): rates Push
Emphasis's real Quads slot, logs and completes every real session, rolls
forward one real week, and confirms Legs Emphasis's two real Quads slots
(a cross-day, one-to-many pairing straight from the recovered table) both
pick up exactly that rating — proving the restored source progression
and the real pairing web both work through the same entry points a real
user goes through, not a synthetic shortcut.

## 13. Simulator state

Fresh install + launch on iPhone 17 Pro
(`A18AB0FB-82F2-4F51-ABFC-7BF232DC3340`), real production path
(`DebugAcceptanceFixturesUseCase`/Today). Today shows **"Push Emphasis,"
Hypertrophy, Ready, 8 exercises, "Barbell Bench Press, Cable Chest Fly,
Barbell Ove[rhead Press]..."** — structurally identical to Slice 1A's own
evidence, now running the restored `.rmBased` source progression
underneath (confirmed by the passing test suite, not visible on this
screen). Left on this screen, Start not tapped, per your instruction.
Loads are not visible on this screen because this fresh debug seed path
carries no prior `PerformanceProfile` history for these exercises (the
same pre-existing state Slice 1A's own Simulator evidence showed) — I
did **not** modify `SeedAnnualPlanJourney`/`DebugAcceptanceFixturesUseCase`
to inject synthetic RM history, since that is itself a nontrivial change
to already-reviewed seed/demo code outside this slice's stated scope; the
"controlled acceptance fixture with known 10RM values" request was
explicitly conditional ("if practical") and I judged expanding the
already-large edit surface of already-reviewed seed code the wrong
tradeoff without asking first. This sandbox still has no permitted
UI-tap mechanism into the Simulator (same disclosed limitation as Slice
1A), so I could not tap Start/navigate further; the code-verified
evidence (full passing suite, including the real-production-path
end-to-end test above) is the primary proof for the progression restore
itself.

## 14. Source edge case discovered during implementation

**`AutoregulationRatingResolver.mostRecentlyCompletedPrescription` had a
latent, previously-unexercised ordering bug**, found while implementing
the real cross-day pairing web. Within one `StrengthMaterializer
.materializeWeek(weekIndex: N)` call, `orderedTemplateSessions` are
processed one day at a time; each day's fresh week-N `ExercisePrescription`
is inserted into `instance.sessions` immediately, before later days in
the same call are processed. The resolver's ranking function
(`completionDate`) fell back to `session?.day?.date` when
`completedAt` was `nil` — so an earlier-processed day's own brand-new,
not-yet-completed week-N prescription (whose `day.date` is naturally
later than any actually-completed prior week) could out-rank the
genuinely most-recently-*completed* prescription from a later-processed
day, for exactly the templates that pair cross-day. This never surfaced
before Slice 1B because every pairing that existed until now was either
same-day (Family A/B/C's primary/paired-accessory) or self-paired (Stage
10B.6) — in both cases the rating source's own current-week prescription
is never created before the reader's own is, so the ambiguity never
arose. More than half of the real 24-entry table is cross-day, so this
had to be found and fixed for Slice 1B to work at all; fixed by making an
actually-completed candidate always outrank an uncompleted one,
regardless of date (rather than excluding uncompleted candidates
outright, which would have broken the pre-existing, intentional
rate-before-formally-completing case `HypertrophyFeedbackTests` already
covers). Confirmed via the full suite that this fix changes no
pre-existing test's outcome.

## Decisions already made (not re-litigated here)

Per your approval: Decision A (blank rating = 0, this program only),
Decision A2 (no invented set floor/ceiling beyond the pre-existing
technical `max(0,...)` floor), Decision B (no new persisted reason-code
field — the existing `appliedLoadReasonCode`/`appliedSetCountReasonCode`/
`appliedRepGoalReasonCode` fields, already `StrengthReasonCode?` and
already populated by the unmodified `StrengthMaterializer`, already
represent this truthfully — no gap existed here, contrary to the design
doc's earlier speculation, which was based on an incomplete grep),
Decision C (one `generatorVersion` bump), Decision D (the literal 24-slot
table, exercise-resolution-orthogonal).

---

Per your stop condition: load-first, Mesocycle 2, Mesocycle 3, and every
other Hypertrophy/Family B/C program remain untouched. Nothing has been
committed or pushed. Waiting for manual acceptance.
