# Stage 10R.2A + 10R.2B — Implementation Report

Mesocycle 2 ("Metabolite Focus") source content recovery and the real
Mesocycle 1 -> Mesocycle 2 transition, for Family A's 3-Day Full Body
reference program only. Built on the evidence in
`STAGE10R2_MESOCYCLE2_SOURCE_RECOVERY_DESIGN.md`. Automated coverage +
Simulator smoke passed; committed and pushed per the user's explicit
"no manual acceptance loop" authorization.

## PRODUCT CONSTITUTION CHECK

**SOURCE AUTHORITY** (literal, cited to the real workbook, never
inferred from Mesocycle 1): the Day 1/2/3 category sequences (27 slots),
the 3 superset pairs, every Week-1 baseline set count, the full 27-row
rating-pairing table (including the one confirmed non-uniform partner —
the Pull-day Biceps partner freezes after Week 2, the other two
cascade), the 0.75 primary / 0.60 superset-partner Week-1 load factors,
the unchanged 3/3/2/1 RIR schedule, and the superset partner's complete
omission from deload (blank source cells, not zero).

**TRAININGOS CONVENIENCE** (explicitly not claimed as source behavior):
visible, editable exercise carry-forward from Mesocycle 1's actual
resolved exercise to Mesocycle 2's same-category slot, and the
user-initiated "Start Metabolite Focus" transition action itself
(including its exact screen placement and button wording).

**NOT SOURCE BEHAVIOR**: the carry-forward *policy* (Locked Decision 1)
— the source workbook is silent on whether the athlete keeps the same
exercise across mesocycles; TrainingOS chose to remember it as a visible
default because the athlete asked for that, not because the source
requires it. A literal, authored `(previous slot) -> (next slot)`
mapping table implements this — never runtime name/occurrence inference,
which would have been ambiguous once the new superset rows shifted
occurrence positions.

**SOURCE PROGRESSION UNCHANGED**: no load-first overlay, no change to
`StrengthProgressionEngine`/`SourceCompatibleDeloadStrategy`/
`AutoregulationRatingResolver`. The superset partner's set count is
represented entirely through the *existing* `AutoregulatedSetCount`/
`pairedSlot` mechanism (pointed at the same external rating target its
own primary uses) — no new domain type, no new progression rule.

## 1-3. Mesocycle 2 source structure, Day 1/2/3 sequences, superset pairs

| Day | Categories (slot 0-8) | Superset pair |
|---|---|---|
| Push Emphasis | Horizontal Push, Chest Isolation or Triceps, **Incline Push or Front Delts (partner)**, Incline Push or Front Delts, Side Delts, Vertical Pull, Horizontal Pull, Hamstrings Isolation, Quads | slots 1+2 |
| Legs Emphasis | Quads, Quads, Hamstrings Hip Hinge, Side Delts, **Side Delts (partner)**, Vertical Pull, Horizontal Pull, Incline Push or Front Delts, Horizontal Push | slots 3+4 |
| Pull Emphasis | Vertical Pull, Horizontal Pull, Rear Delts or Side Delts, Biceps, **Biceps (partner)**, Horizontal Push, Incline Push, Glutes, Hamstrings Isolation | slots 3+4 |

## 4. Set baselines/pairings

Week-1 baseline sets: Push `[4,4,4,4,3,3,3,2,2]`, Legs `[4,4,4,3,3,3,3,2,2]`,
Pull `[4,4,4,3,3,3,3,2,2]` — all 27 confirmed against the real workbook,
not copied from Mesocycle 1. The full 27-entry rating-pairing table is
`HypertrophyProgramGenerator.threeDayFullBodyMesocycle2RatingPairings`.
Every superset partner's pairing target is the same external row its
own primary reads (proven, not assumed) — the Pull-day Biceps partner
is the one confirmed exception, pinned via `freezeAfterWeek: 1` after
Week 2 rather than cascading further.

## 5. Load/RIR behavior

Primary Week 1 = resolved fresh 10RM × 0.75; superset partner Week 1 =
its OWN resolved fresh 10RM × 0.60 (never a fraction of the primary's
weight — both use `.rmBased`, never `.linkedToPairedSlot`). Weeks 2-4:
the unchanged shared ×1.05/1.075/1.1 multipliers off each row's own
resolved Week-1 value, never chained week to week. RIR: 3, 3, 2, 1 —
identical to Mesocycle 1, RIR-only, never a fabricated fixed rep count.

## 6. Exercise carry-forward behavior

A literal, authored table maps each of Mesocycle 1's 24 real slots to
its Mesocycle 2 same-category counterpart (the 3 new superset-partner
slots have no Mesocycle-1 equivalent and are never mapped). At
transition time, the previous instance's actual resolved exercise
(override-aware, via `SubstituteExerciseUseCase.resolvedExercise`) is
checked against the new slot's constraints (`SubstitutionValidator.isValid`)
and pre-set only if compatible; everything else — including all 3 new
partner slots and any incompatible carry-forward — falls through to the
exact same deterministic resolution a brand-new instance already uses.
The athlete can still change any of it afterward through the ordinary,
unmodified GOING FORWARD substitution mechanism.

## 7. Calibration behavior

Mesocycle 2 is a genuinely new `ProgramInstance`; `SourceRMCalibration`'s
existing `(ProgramInstance, Exercise, RMType)` scoping means it requires
fresh calibration automatically, with zero code changes — proven by a
dedicated test that Mesocycle 1's own calibration never satisfies
Mesocycle 2's requirement. The existing "Set your starting weights"
screen (`SourceRMCalibrationViewModel`) picks up the new instance
generically, exactly as it already does for any `.active` instance.

## 8. Transition UX/wiring

A single button ("Start Metabolite Focus") on `PhaseDetailView`'s active-
phase content, visible only when the phase's primary Hypertrophy
instance has real materialized sessions and a next mesocycle type
exists and hasn't already been started. Tapping it calls the new
`StartNextHypertrophyPhaseUseCase.start`, which reuses
`HypertrophyProgramGenerator.generate`'s per-phase construction (the
same shape `HypertrophyProgramJourney.build`'s own loop body already
establishes — no duplicated orchestration), builds the new
`TrainingPhase`/`ProgramInstance`/`TrainingMix`/`TrainingMixComponent`,
runs carry-forward, and defers to the existing calibration-gated
materialization path. No new screen was built — the existing
calibration screen already shows each row's exercise name, satisfying
"review carried-forward selections" without new UI.

## 9. Idempotency/persistence behavior

A repeated call (or SwiftUI re-evaluation) returns the already-created
phase/instance rather than duplicating anything — checked by looking
for an existing phase in the plan whose primary instance already
matches the target phase type/day-count/split. Proven directly: calling
`start` twice yields the same instance ID and exactly one Metabolite
Focus phase in the plan. The transition, its carry-forward result, and
its calibration all survive a simulated relaunch (fresh `ModelContainer`
against the same store).

## 10. Files changed

**Production**: `HypertrophyProgramGenerator.swift` (phase-aware
`generateDayFocusDriven`/`makeSourceCategoryTemplate`, new Mesocycle 2
content + pairing tables, `HypertrophyGenerationError.phaseNotYetRecovered`),
new `StartNextHypertrophyPhaseUseCase.swift`, `PhaseDetailViewModel.swift`
(the one deliberate write + its supporting state), `PhaseDetailView.swift`
(the button).
**Tests**: `HypertrophyProgramJourneyTests.swift`,
`HypertrophyBuiltInLibraryTests.swift` (both updated for the now-honest
`.resensitization` throw for 3-Day Full Body), new
`HypertrophyMesocycle2SourceProgressionTests.swift` (13 tests), new
`StartNextHypertrophyPhaseUseCaseTests.swift` (9 tests).

## 11. Targeted tests

All new/updated tests passed on their own targeted runs before the full
suite: 13/13 (`HypertrophyMesocycle2SourceProgressionTests`), 9/9
(`StartNextHypertrophyPhaseUseCaseTests`, including the real production-
path integration test and the `PhaseDetailViewModel` wiring test), plus
the 2 updated existing tests.

## 12. Full-suite result

**835/835 passed, 0 failures, 2 pre-existing documented skips**
(unrelated mixed-modality scheduling limitation, unaffected by this
stage).

## 13. Simulator smoke result

Fresh install launches cleanly with the complete Stage 10R.2A/2B code —
no crash, the seeded Mesocycle 1 (3-Day Full Body, "Legs Emphasis," 8
exercises) renders correctly, identical to pre-stage behavior. **Honest
limitation, stated plainly**: this sandbox has no UI-tap automation
(confirmed multiple times this project — no idb/AXe, `osascript`'s
System Events click fails), so the actual button tap
("Start Metabolite Focus" -> Starting Weights for the new instance)
could not be performed live in the Simulator. In its place, a dedicated
test (`testPhaseDetailViewModelOffersAndPerformsTheRealTransition`)
drives the exact `PhaseDetailViewModel` method the button calls,
end to end through the real production path, proving the UI-adjacent
wiring itself (not just the underlying use case) — the closest honest
substitute available in this environment.

## 14/15. Commit hash / push / clean-tree confirmation

Reported in the chat response accompanying this file's own commit (this
document is part of that same commit, so it cannot self-reference its
own resulting hash).

## 16. Remaining known gaps

- `RollTacticalWindowUseCase.rollForward` still has no production call
  site — week-to-week progression within either mesocycle (not just the
  boundary between them) remains unwired, deferred per explicit
  instruction (10R.2C).
- Deload's "which Week-1 actual set result" ambiguity remains
  unresolved, unchanged, isolated to `SourceCompatibleDeloadStrategy`.
- Family C content fidelity (day/category structure, set baselines,
  rating-pairing web — all proven wrong, not just the known placeholder)
  remains unaddressed; Family C's Monday/Thursday footnote conflict
  remains unresolved.
- The two `TacticalPlacementBoundaryTests` `XCTSkip`s remain, unaffected
  by this stage.
- The warm-up "primary block" heuristic weakness remains separate,
  unaffected.
- The 10 other Family A configurations still have no Mesocycle 2
  content recovered — deliberately deferred per Locked Decision 3.

## 17. Mesocycle 3 implications

`HypertrophyGenerationError.phaseNotYetRecovered(phaseType: .resensitization)`
is now thrown explicitly whenever the day-focus path is asked for
Resensitization — a real, typed, honest failure rather than silently
reusing Mesocycle 1 or 2's content (the exact defect this stage
corrected for Mesocycle 2). `StartNextHypertrophyPhaseUseCase` already
generalizes to a 3rd phase with zero changes once real Mesocycle 3
content exists (it reads `HypertrophyProgramJourney.orderedPhaseTypes`
generically) — the only work a future Mesocycle 3 stage needs is source
content recovery and the corresponding `HypertrophyProgramGenerator`
tables, mirroring this stage's own pattern exactly. Not started, per
explicit instruction.
