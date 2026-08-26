# Stage 10R.3A + 10R.3B — Implementation Report

Mesocycle 3 ("Resensitization") source content recovery and the real
Mesocycle 2 -> Mesocycle 3 transition, for Family A's 3-Day Full Body
reference program only. Built on the evidence in
`STAGE10R3_MESOCYCLE3_SOURCE_RECOVERY_DESIGN.md`. Automated coverage +
Simulator smoke passed; committed and pushed per the user's explicit
"no manual acceptance loop" authorization.

## PRODUCT CONSTITUTION CHECK

**SOURCE AUTHORITY** (literal, cited to the real workbook, universal
across all 11 Family A workbooks, never inferred from Mesocycle 1/2):
the Day 1/2/3 category sequences (22 slots, "Chest Isolation or
Triceps" absent), every Week-1 baseline set count, the full 22-row
rating-pairing table, the 1.0 Week-1 / ×1.05 Week-2 load factors, the
flat 3/fail (RIR 3) rep/RIR schedule for both progressive weeks, the
**absence** of any superset mechanic, and the 2-progressive-week +
1-deload (3 total week) structure.

**TRAININGOS CONVENIENCE** (explicitly not claimed as source behavior):
visible, editable exercise carry-forward from Mesocycle 2's actual
resolved exercise to Mesocycle 3's same-category slot (via a newly
authored `threeDayFullBodyMesocycle2ToMesocycle3` table, mirroring
Stage 10R.2B's own carry-forward discipline exactly), and the
user-initiated "Start Resensitization" transition action (reusing the
existing `PhaseDetailView` button/`PhaseDetailViewModel` wiring
verbatim — no new screen).

**NOT SOURCE BEHAVIOR**: the carry-forward *policy* itself (already
accepted in Stage 10R.2, not re-litigated here) — the source workbook is
silent on exercise continuity across mesocycles. Its Mesocycle-2 -> 3
*data table* is new (Mesocycle 3 has fewer/different slots than
Mesocycle 2 — 22 vs 27), but the policy it implements is unchanged.

**SOURCE PROGRESSION UNCHANGED**: no load-first overlay, no change to
`StrengthProgressionEngine`/`SourceCompatibleDeloadStrategy`/
`AutoregulationRatingResolver`. Mesocycle 3's absence of supersets is
represented entirely by every row simply never setting
`isSupersetPartner`/`freezeAfterWeek` — no new domain type, no new
progression rule, no special-cased "no supersets" branch anywhere.

## 1-3. Mesocycle 3 source structure, Day 1/2/3 sequences, week structure

| Day | Categories (slot 0-6/7) |
|---|---|
| Push Emphasis (7) | Horizontal Push, Incline Push or Front Delts, Side Delts, Vertical Pull, Horizontal Pull, Hamstrings Isolation, Quads |
| Legs Emphasis (7) | Quads, Hamstrings Hip Hinge, Side Delts, Vertical Pull, Horizontal Pull, Incline Push or Front Delts, Horizontal Push |
| Pull Emphasis (8) | Vertical Pull, Horizontal Pull, Rear Delts or Side Delts, Biceps, Horizontal Push, Incline Push, Glutes, Hamstrings Isolation |

22 total slots (7+7+8) — confirmed against the real workbook, not
copied from Mesocycle 1/2; "Chest Isolation or Triceps" is confirmed
absent from all 3 days. **3 total weeks** (Week 1, Week 2, Week 3:
Deload) — not Mesocycle 1/2's 4 progressive + 1 deload — confirmed
universal across all 11 Family A workbooks (identical week-header
labels in every sheet).

## 4. Set baselines/pairings

Week-1 baseline sets: Push `[3,3,2,2,2,1,1]`, Legs `[3,3,2,2,2,1,1]`,
Pull `[3,3,3,2,2,2,1,1]` — all 22 confirmed against the real workbook.
The full 22-entry rating-pairing table is
`HypertrophyProgramGenerator.threeDayFullBodyMesocycle3RatingPairings`.
**A synthesis error caught before implementation:** the design
document's row37 entry was originally transcribed as `(2,6)->(1,6)`,
self-inconsistent with its own `row37->row22` citation (row22 falls at
Legs 0-based offset 1, not 6); corrected to `(2,6)->(1,1)` using the row
citation and Mesocycle 1's own identical-category precedent (Glutes
rated by Legs' Hamstrings Hip Hinge) before any code was written — see
design doc §7's correction note and the implementation code comment at
the same table entry. No other inconsistency found across the other 21
rows.

## 5. Load/RIR behavior

Week 1 = resolved fresh 10RM × 1.0 (no reduction, confirmed universal
across all 11 Family A workbooks, zero row-level exceptions). Week 2 =
Week 1's resolved value × 1.05 (a single step — no Week 3/4 progressive
step exists, since Mesocycle 3 has only 2 progressive weeks). RIR: 3, 3
— flat, never a fabricated rep count, using the existing `.rir(_:)`
case unchanged.

## 6. No supersets — proof

Every one of the 22 Mesocycle 3 rows is generated with
`isSupersetPartner: false` (the table's own default — never explicitly
set to `true` anywhere in `threeDayFullBodyMesocycle3Resensitization`),
so `makeSourceCategoryTemplate`'s existing `isSupersetPartner ?
metaboliteFocusPairedWeekOneFactor : primaryWeekOneFactor(for:
phaseType)` branch always resolves to the primary 1.0 factor — no new
"no supersets" special case was needed anywhere in the generator.
`testZeroSupersetsAnywhereInMesocycle3` proves this directly: every row
uses `weekOneFactor == 1.0`, `deloadWeightAction/deloadRepAction ==
.standard` (never `.omit`), and `freezeAfterWeek == nil`.

## 7. Deload routing

Mesocycle 3 routes through the same, unmodified
`SourceCompatibleDeloadStrategy` — day-position weight split (full
weight days 0-1, halved day 2 for the 3-day config), 2-set constant,
"1/2 reps of Week 1" text. The pre-existing "which Week-1 actual set
result does deload reference?" ambiguity is unchanged, unresolved — no
Mesocycle 3 evidence bore on it, so no resolution was invented.

## 8. Mesocycle 2 -> 3 exercise carry-forward behavior

A new, literal, authored table
(`StartNextHypertrophyPhaseUseCase.threeDayFullBodyMesocycle2ToMesocycle3`)
maps each of Mesocycle 2's real slots that has a genuine Mesocycle 3
counterpart to that slot — never the M1->M2 table reused. Every
Mesocycle-2-only row (the 3 former superset partners, "Chest Isolation
or Triceps," and the 2nd Legs-day Quads occurrence — Mesocycle 3 has
only 1) has no mapping entry and falls through to the same
deterministic resolution a fresh instance already uses. Selected at
transition time by `carryForwardMapping(fromPreviousPhaseType:)`, keyed
on the *previous* phase's type (whose slot layout the mapping's `from`
side indexes into).

## 9. Transition/provenance changes

**Both genuine gaps identified in the Stage 10R.3 archaeology were
closed, correcting the Stage 10R.2 report's overstated "zero changes"
claim** (see that report's own §17 correction note):

1. `provenance` inside `StartNextHypertrophyPhaseUseCase.start()` is now
   resolved via a new `sourceProvenance(for:)` helper, keyed on the
   *next* phase's type, rather than a literal hardcoded to Mesocycle 2's
   sheet name — proven directly by
   `testMesocycle3ProvenanceCitesItsOwnSheetNotMesocycleTwos`.
2. The carry-forward table selection is now phase-aware (§8 above).

Phase-sequencing (`HypertrophyProgramJourney.orderedPhaseTypes`-driven
next-phase lookup) and the idempotency guard (`existingNextPhase`)
needed genuinely zero changes — confirmed by direct read and unchanged
in this stage's diff. User-initiated transition, idempotency,
persistence, no duplicate `ProgramInstance`, no duplicate Sessions, and
existing phase sequencing are all preserved.

## 10. Phase-aware generator changes

`HypertrophyProgramGenerator`'s day-focus path (`generateDayFocusDriven`)
previously hardcoded 4 progressive `TrainingWeek`s + 1 deload and
`lengthWeeks: 5` **regardless of phase** — a real, necessary correction
identified during this stage's own implementation reasoning (not
explicitly named by any of the Stage 10R.3 archaeology forks, which
focused on content/formula recovery rather than the week-count
construction loop). Now phase-aware via a new
`progressiveWeekCount(for:)` helper (`4` for Mesocycle 1/2, unchanged;
`2` for Mesocycle 3), with `lengthWeeks` computed as `progressiveWeeks +
1`. Two further phase-aware helpers, `dayFocusRepGoalSchedule(for:)` and
`dayFocusLaterWeekMultipliers(for:)`, select between the existing
Mesocycle 1/2 constants and new, shorter Mesocycle-3-only constants
(`resensitizationRepGoalSchedule` — `[.rir(3), .rir(3)]` — and
`resensitizationLaterWeekMultipliers` — `[1.05]`) — Mesocycle 3 needs
its own arrays because its progression is genuinely shorter, not a
truncated version of Mesocycle 1/2's. Mesocycle 1/2 continue to use the
original, unmodified `repGoalSchedule`/`laterWeekMultipliers` constants
directly. `currentVersion` bumped 3 -> 4. The legacy fixed-pair path
(every non-3-Day-Full-Body configuration) is completely untouched.

## 11. Files changed

**Production**: `HypertrophyProgramGenerator.swift` (phase-aware week
construction/`sourceContent`/rep-goal-schedule/multiplier selection, new
Mesocycle 3 content + pairing tables, `currentVersion` bump),
`StartNextHypertrophyPhaseUseCase.swift` (phase-aware `sourceProvenance(for:)`,
new `threeDayFullBodyMesocycle2ToMesocycle3` carry-forward table,
`carryForwardMapping(fromPreviousPhaseType:)` selector).
**Tests**: `HypertrophyBuiltInLibraryTests.swift` (updated —
`testEveryBuiltInConfigurationBuildsAFullThreePhaseJourney` no longer
special-cases 3-Day Full Body's throw, since all 6 configurations now
build a full 3-phase journey), new
`HypertrophyMesocycle3SourceProgressionTests.swift` (13 tests),
`StartNextHypertrophyPhaseUseCaseTests.swift` (+8 tests: fresh
calibration isolation, provenance, carry-forward mapping, dropped-row
non-leakage, idempotency, persistence, the real production lifecycle,
and a `PhaseDetailViewModel`-level UI-wiring test).
**Documentation**: this file; `STAGE10R2_MESOCYCLE2_IMPLEMENTATION_REPORT.md`
§17 corrected in place (§15 of the original request).

## 12. Targeted test result

All new/updated tests passed on their own targeted runs before the full
suite: 13/13 (`HypertrophyMesocycle3SourceProgressionTests`), 17/17
(`StartNextHypertrophyPhaseUseCaseTests`, including the real
production-path integration test and both `PhaseDetailViewModel` wiring
tests), plus `HypertrophyBuiltInLibraryTests`,
`HypertrophyMesocycle2SourceProgressionTests`,
`HypertrophyProgramJourneyTests`, and `HypertrophyProgramGeneratorTests`
(61 tests total across the targeted run) — all green, confirming
Mesocycle 1/2 regression protection alongside the new Mesocycle 3
coverage.

## 13. Full-suite result

**856/856 passed, 0 failures, 2 pre-existing documented skips**
(unrelated mixed-modality scheduling limitation, unaffected by this
stage). Run with `-parallel-testing-enabled NO` per this project's own
established Simulator-flakiness fix.

## 14. Simulator result

Fresh install (uninstall + install + launch) with the complete Stage
10R.3A/3B code — no crash, no fatal/terminate entries in the device log,
the app renders the seeded Mesocycle 1 Starting Weights screen exactly
as before this stage. **Honest limitation, stated plainly (same as every
prior stage this project has completed):** this sandbox has no UI-tap
automation, so the literal "Start Resensitization" button tap could not
be performed live in the Simulator. In its place,
`testPhaseDetailViewModelOffersAndPerformsTheRealMesocycleTwoToThreeTransition`
drives the exact `PhaseDetailViewModel` method the button calls, end to
end through the real production path from a real calibrated Mesocycle
2, proving the label reads "Start Resensitization" (not a stale
Mesocycle-2-era label), that tapping it performs the real transition,
and that it correctly hides itself afterward — the same honest
substitute pattern Stage 10R.2B already established.

## 15. Documentation correction

`STAGE10R2_MESOCYCLE2_IMPLEMENTATION_REPORT.md` §17 corrected in place
(not rewritten/deleted) — its closing claim that
`StartNextHypertrophyPhaseUseCase` "already generalizes to a 3rd phase
with zero changes" is now marked as overstated, with an explicit
breakdown of what was actually generic (phase sequencing, UI gating)
versus what genuinely needed new code in this stage (provenance,
carry-forward table selection). The original sentence is preserved
inline (not deleted) so the correction is traceable to what it corrects.

## 16. Commit hash / push / clean-tree confirmation

See the chat response accompanying this file's own commit (this
document is part of that same commit, so it cannot self-reference its
own resulting hash).

## 17. New defects or source conflicts discovered

1. **Design-doc self-inconsistency in the rating-pairing table** (§4
   above) — a transcription error caught and corrected before any code
   was written; never shipped.
2. **The week-count construction loop was not phase-aware** before this
   stage (§10 above) — a real gap in the *implementation*, not the
   source evidence, found by direct reasoning about the generator's own
   mechanics against the newly-confirmed 2-progressive-week structure.
3. **The Stage 10R.2 report's "zero changes" claim was overstated** (§9
   above, §15) — corrected in place rather than silently left standing.

No new source ambiguity was found in Mesocycle 3 itself — its own
structure, load, RIR, set baselines, and rating-pairing table are all
fully source-proven with no unresolved question.

## 18. Remaining known gaps (unchanged by this stage, out of scope)

- `RollTacticalWindowUseCase.rollForward` still has no production call
  site — unaffected by this stage.
- Deload's "which Week-1 actual set result" ambiguity remains
  unresolved (§7).
- Family C content fidelity remains unaddressed.
- The 10 other Family A configurations still have no Mesocycle 3
  content recovered — deliberately deferred per the user's explicit
  scope instruction (3-Day Full Body only).
- The warm-up "primary block" heuristic weakness remains separate,
  unaffected.
- The Hypertrophy source-defined lifecycle for 3-Day Full Body (Family
  A's reference program) is now complete across all 3 mesocycles — the
  next natural follow-up, if wanted, is extending this same recovery
  discipline to another Family A configuration or to Family B/C, neither
  of which this stage touches.
