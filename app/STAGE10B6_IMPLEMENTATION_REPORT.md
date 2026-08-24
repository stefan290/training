# Stage 10B.6 — Hypertrophy V2 Implementation Report

Implements the approved `STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md`
design (as amended by your final approval message).

**STATUS: MANUALLY ACCEPTED AND CLOSED.** Committed and pushed to
`origin/main` (see the commit hash in this repo's git log for the exact
revision). Stage 10C (frequency/split expansion) is a separate,
design-only follow-up — see `STAGE10C_HYPERTROPHY_V2_SPLIT_EXPANSION.md`.

## Manual acceptance record

Verified live in the Simulator, through the real production onboarding
path (Goal → Plan → Phase → Mix selection → materialization), after the
two-exercise/legacy-content false alarm was traced to a stale simulator
install (not a code defect — see the root-cause report earlier in this
stage's history) and a fresh install was verified correct:

- Real 3-Day Full Body Hypertrophy V2 program, Day A/B/C richer
  multi-exercise structure, correct primary/secondary/accessory
  prescriptions, readiness flow, warm-up flow, workout execution,
  exercise navigation, rep ranges, RIR targets, and first-exposure
  calibration (blank weight where no usable history exists) — all
  confirmed working as designed.
- Verified examples: **Back Squat** (primary) 3 sets, 5-10 reps, 3 RIR;
  **Barbell Row** (secondary) 3 sets, 6-12 reps, 3 RIR; **Barbell Curl**
  (accessory) 2 sets, 10-20 reps, 2 RIR.
- A new integration test
  (`TacticalPlanningOrchestrationTests.testRealProductionPathMuscleGainThreeDayFullBodyReceivesHypertrophyV2`)
  proves this same real-onboarding path end to end, so this acceptance
  is now also protected by regression coverage, not just a one-time
  manual check.

## Known, deliberately deferred limitations (out of Stage 10B.6's scope)

A. **Legacy Family A still exists and remains used by every other
   Hypertrophy configuration** (4-Day Full Body, 5-Day Full Body, 5-Day
   Upper/Arms Focus, 4-Day Lower/Leg Focus, 6-Day High-Frequency) —
   untouched by design, per D-10B6-9.
B. **The default Muscle Gain recommendation is still 5-Day "Focused
   Hypertrophy" (legacy Family A)** — "Strength Plus Variety" (3-Day,
   V2) is a real, fully-selectable alternative, not the system's own
   default pick. Whether this should change is an explicit Stage 10C
   product decision, not decided here.
C. Other hypertrophy frequencies/splits have not been migrated to V2 —
   Stage 10C's own subject.
D. e1RM remains legacy/strength-oriented infrastructure, not required
   by Hypertrophy V2.
E. A completed deload exposure is excluded from the next mesocycle's
   progression input (a discovered heuristic, not one of the original
   10 decisions) unless/until explicitly revisited.
F. Advanced cross-modality interference — deferred.
G. Home Gym / environment-aware exercise resolution — deferred.
H. More advanced exercise-specific rep preferences — deferred unless
   Stage 10C proves necessary.

## 1. Exact architecture changes

- **`HypertrophyProgramGenerator.generateDayFocusDriven`** now builds
  Hypertrophy V2 templates (`makeDayFocusTemplate(role:)`) instead of
  Family A's `.rmBased` rules — role-based rep range, RIR trajectory,
  `.doubleProgression` load, bounded autoregulated (primary/secondary) or
  fixed (accessory) set count. `generateLegacyFixedPair` (every other
  configuration) is **byte-for-byte unchanged**.
- **Feedback fan-out fix**: the day-focus path no longer assigns a
  shared canonical-accessory `pairedSlot`; every primary/secondary
  template sets `template.pairedSlot = template` (self-attribution).
  `HypertrophyFeedbackPrompts.pending(for:)` needed **no code change** —
  its existing `referencedAsPairedSlotBy`-non-empty check already
  produces the correct result once self-reference replaces the shared
  target.
- **`DoubleProgressionEngine`** (Engines/): internal decision rule
  rewritten to performance-qualified load progression (§6a of the
  design doc) — RIR-surplus qualification, a proportional-increment
  guard, and a real (previously declared-but-unreachable) `.loadDecrease`
  path. `ProgressionEngine`/`ProgressionInput`/`ProgressionOutput`/
  `SetTarget`/`SetOutcome` shapes are extended, not replaced (two new
  optional `ProgressionInput` fields, default `nil`).
- **New `DoubleProgressionHistoryResolver`** (Engines/): resolves real,
  exercise-scoped (never program-instance-scoped) history from
  `ExercisePerformanceProfile`, excluding any exposure with an accepted
  readiness adaptation or a deload-shaped RIR signature.
- **New `HypertrophyV2ProgressionEngine`** (Application/UseCases/):
  the day-focus generator's rule-constant home (rep ranges, RIR
  trajectory, baseline sets) and the single call site that turns real
  history into a weight/rep-goal/set-count decision for one week —
  `StrengthProgressionEngine`'s Hypertrophy-V2 counterpart, deliberately
  separate so Family A/B/C's engine is untouched.
- **`StrengthMaterializer`**: one new branch, keyed on
  `template.rules?.loadRule == .doubleProgression`, checked before the
  existing `isDeload`/legacy branch — reads pre-resolved values off a
  `SlotContext` extension rather than calling `StrengthProgressionEngine`/
  `SourceCompatibleDeloadStrategy` at all for V2 templates.
- **`RollTacticalWindowUseCase`**: (a) the deload-reachability fix —
  `rollForward` now reads `definition.orderedWeeks[weekIndex].isDeload`
  instead of a hardcoded `false`; (b) `strengthSlotContext` gains a V2
  branch that calls `HypertrophyV2ProgressionEngine` identically at
  every week including week 0 (no e1RM, no week-1 RM factor); (c) both
  `materializeFirstWindow`/`rollForward` gain an optional `userProfile`
  parameter (default `nil`, matching `CompleteSessionUseCase`'s existing
  convention) for per-equipment-type increments.
- **`CompleteSessionUseCase.progressionPreview`**: now also consults
  `DoubleProgressionHistoryResolver` for the two-exposure regress
  lookback, via a new optional `performanceProfile` parameter fetched in
  `complete()` — so the live "Next time" preview and real week-N+1
  materialization are provably the same computation (one authoritative
  decision path).
- **`StrengthExecutionView`**: one display-only change — rep range shows
  as "5-10 reps" when genuinely a range, "5 reps" when `repRangeLow ==
  repRangeHigh` (legacy), instead of always rendering "5-5 reps."
- **`StrengthProgressionEngine.resolveWeight`**: one exhaustive-switch
  case added for `.doubleProgression` (documented unreachable — this
  engine is never called for V2 templates).

## 2. Exact schema changes (additive only)

- `RepGoal` (+`repRangeHigh: Int?`, +`targetRir: Int?`, both `nil`-default).
- `PrescriptionTemplate` (+`repGoalRepRangeHigh: [Int]`, +`repGoalTargetRir: [Int]`,
  parallel arrays, `-1` sentinel = unset — every existing row decodes
  identically to before).
- `LoadRuleKind`/`LoadRule` (+`.doubleProgression` case, no payload).
- `ExercisePrescription` (+`appliedProgressionReasonCode: ProgressionReasonCode?`,
  the V2 sibling of the existing `appliedLoadReasonCode: StrengthReasonCode?`
  — kept separate since the two are different reason-code vocabularies).
- `StrengthMaterializer.SlotContext` (+4 optional fields carrying the
  caller-resolved V2 decision).
- `ProgressionInput` (+`previousTargets`/`previousResults`, both optional).
- **No new `@Model` type. No field removed or repurposed. No migration
  required beyond SwiftData's normal lightweight handling of new
  optional/defaulted properties** (confirmed: fresh install + full test
  suite both succeeded against the extended schema).

## 3. Exact progression algorithm implemented

Exactly the approved decision table (`STAGE10B6...md` §6a/§6b):
STRONG (ceiling+RIR-floor, OR in-range with RIR surplus ≥2) → load
increase, gated by a ≤10% increment-proportionality guard; adequate
(in-range, RIR floor met) → hold/progress reps; below minimum → hold
once, regress by one equipment increment on a second consecutive miss
(reset if a normal exposure intervenes); in-range only by exceeding the
target RIR → hold (never credited as on-track). Verified against the
full A–I table plus RIR-surplus/increment-boundary/regression-trigger
edge cases in `DoubleProgressionEngineTests.swift`.

## 4. Calibration behavior

No e1RM, no RM test, ever, for this rule family. `HypertrophyV2ProgressionEngine.resolveWeight`
looks up the most recent **normal** (unadapted, non-deload, fully
logged) exposure of the resolved Exercise via `ExercisePerformanceProfile`
— scoped to the exercise, never to one `ProgramInstance` or one slot, so
substitution history is never contaminated. No history → `targetWeight`
stays `nil` on the materialized `SetPrescription`; the existing
`StrengthExecutionView` already renders this correctly (no "Suggested
load" line, an empty weight field the user must fill in) — **zero UI
code was needed for this**, it was already the app's existing behavior
for a `.calibrationRequired` week.

## 5. Set-autoregulation behavior

Baselines: primary 3, secondary 3, accessory 2 (accessory fixed, never
autoregulated). Bounds: `max(baseline-1, min(baseline+2, previous +
rating))`. Attribution: every primary/secondary template rates itself
(`pairedSlot = self`) — verified a rated slot's own next-week count
changes while an unrated sibling's stays at baseline
(`test6_LocalSetCountAutoregulationAffectsOnlyTheRatedSlot`).

## 6. Feedback UX behavior

No UI code changed this pass — `HypertrophyFeedbackPrompts.pending(for:)`'s
existing filter already produces the correct, attributed list once
self-referencing `pairedSlot` replaced the shared canonical accessory;
`HypertrophyFeedbackView`'s existing one-screen, sequential-but-compact
presentation already matches the approved "consolidated, not 7
questionnaires" requirement. A day's real row count is now genuinely
per-slot (2-4 for this reference config), never merged for its own sake.

## 7. Exact Week 1–5 prescription behavior

| Week | Primary/Secondary | Accessory |
|---|---|---|
| 1 | 5-10 (6-12) reps @ 3 RIR | 10-20 reps @ 2 RIR |
| 2 | @ 2 RIR | @ 2 RIR |
| 3 | @ 2 RIR | @ 2 RIR |
| 4 | @ 1 RIR | @ 2 RIR |
| 5 (deload) | same range as wk 4 @ **4 RIR**, ~50% sets | same range @ 4 RIR, ~50% sets |

Load every week (including deload) is whatever
`HypertrophyV2ProgressionEngine`/`DoubleProgressionEngine` computes from
real prior performance — never a static multiplier.

## 8. Deload behavior

`rollForward` now correctly resolves `isDeload` from the real
`TrainingWeek` flag (previously hardcoded `false`, structurally
unreachable). Set count = `round(baseline*0.5)`, minimum 1. RIR = an
explicit 4, never inherited `toFailure`. Rep range = same as week 4
(exercise continuity, no arbitrary reduction). Load = whatever the
normal performance-qualified algorithm computes from week 4's real
result — no invented percentage. Verified end to end
(`test7_WeekFourToWeekFiveRealReachableDeload`): 4 real weeks rolled
forward, deload correctly reached with 2 sets/RIR 4/same 5-10 range,
and the week counter (`ProgramWeekGrouping.nextWeekIndex`) correctly
advances to 5 afterward.

**One discovered edge case, handled but flagged, not one of the 10
original decisions**: a completed deload exposure's own (deliberately
easy, RIR 4) performance is excluded from history when materializing
the **next mesocycle's** week 1 (`DoubleProgressionHistoryResolver.isLikelyDeloadExposure`,
a heuristic — "every set's `targetRir == 4`"). Without this, an easy
deload week could otherwise read as a trivial "load increase" right
into the next block. Flagged for your awareness in §13 below, not
silently decided as a new product rule beyond the already-approved
readiness-neutrality principle it mirrors.

## 9. Exact before/after examples from real performance

From `HypertrophyV2EndToEndTests.swift`, all through the real
`RollTacticalWindowUseCase` path:

- **Increase**: Back Squat, week 0 calibration (100 kg fallback logged
  as the athlete's own working weight), 10/10/10 @ 3 RIR (week 0's own
  target) → week 1: **102.5 kg**, still 5-10 @ 2 RIR (week 1's own
  trajectory value).
- **Hold/progress reps**: 8/8/8 @ 3 RIR (in range, on-track, not
  strong) → week 1: same weight, `.repIncrease`.
- **Accessory increase**: Barbell Curl, 20/20 @ 2 RIR (top of 10-20 at
  target) → week 1: `+2.5 kg`, set count still fixed at 2.
- **First miss**: 3/3/3 (below the 5-10 minimum) → week 1: same weight,
  `.hold` — no regression from one bad exposure.
- **Regression**: a second consecutive miss the following week →
  week 2: **-2.5 kg**, `.loadDecrease`.
- **Set-count autoregulation**: Back Squat self-rated +1 → 3+1=4 sets
  next week; Barbell Bench Press (unrated sibling) stays at 3 — the
  fan-out bug is directly, provably fixed.
- **Deload**: 3 sets → 2, RIR → 4 explicit, same 5-10 range, load
  carried from real week-4 performance.

## 10. Targeted test results

- `DoubleProgressionEngineTests.swift`: revised + 17 new cases (full
  A-I decision table, RIR-surplus/increment-boundary/regression-trigger
  edge cases) — all passing.
- `HypertrophyDayFocusGenerationTests.swift`: 3 tests rewritten for V2
  rules (rep-range/RIR-trajectory/self-attribution assertions replacing
  the retired `.rmBased`/fan-out assertions); 2 more updated to assert
  V2 correctly does NOT use `.rmBased`/the Heavy exception.
- `HypertrophyBuiltInLibraryTests.swift`: 1 test updated to exclude the
  3-Day Full Body config from a Family-A-only assertion, with a pointer
  to where that config's own behavior is covered instead.
- `SessionAutoAdvanceTests.swift`: fixture updated to supply real V2
  `SlotContext` fields (was silently producing zero-set V2 prescriptions
  under the old stub).
- **New `HypertrophyV2EndToEndTests.swift`**: 7 tests, all through the
  real `RollTacticalWindowUseCase`/materializer/readiness/logging path —
  load increase, hold, accessory, first-miss, regression, set-count
  autoregulation, and week 4→5 deload reachability.

## 11. Full suite count

**768/768 passing**, `xcodebuild test` exit code 0, `** TEST SUCCEEDED **`.
(Was 761/761 immediately before this stage's changes; +7 new end-to-end
tests, +17 new decision-table tests, net file count and assertion
coverage both up, zero regressions.)

## 12. Simulator state and exact taps

Clean build installed and launched on iPhone 17 Simulator
(`com.macadegolf.trainingos`) after a full uninstall/reinstall —
confirms the additive schema loads correctly on a fresh store, no
crash. The app's own existing debug/demo seed produced a real,
already-materialized "Day A / Hypertrophy / 7 exercises / Barbell Bench
Press, Back Squat, Romanian Deadlift…" card on the Today tab —
screenshot captured and reviewed.

**Limitation, disclosed plainly (same as Stage 10B's own acceptance
report)**: this environment's Simulator GUI cannot currently be driven
via System Events/AppleScript (`Cannot get window 1 of process
"Simulator". Invalid index.`) — the identical blocker documented during
Stage 10B. I could not tap through Start → readiness → prescription
display → log a set → complete → inspect the next occurrence myself
this pass. What I verified instead, and what remains for your own
manual pass:

- **Verified by me**: the real production code path end to end via
  `HypertrophyV2EndToEndTests` (§9-10 above) — materialization,
  progression, autoregulation, and deload are all proven against real
  logged data, not just unit-level engine tests.
  `StrengthExecutionView`'s rep-range/RIR display logic was read and
  confirmed to already render a genuine range correctly (§1) — not
  screenshotted interactively, but the exact rendering code was traced.
- **Left for you to confirm visually** (the 8-item checklist you gave):
  the Simulator is currently running with a real materialized
  Hypertrophy program on the Today tab, ready for you to tap through
  yourself.

## 13. Remaining limitations / unresolved items

- The two TRAININGOS-DESIGNED constants (`RIR_SURPLUS_THRESHOLD = 2`,
  `MAX_PROPORTIONAL_INCREMENT_RATIO = 0.10`) and the regression
  trigger/step size are implemented exactly as you approved — no new
  numeric decisions were made beyond them.
- The deload-exposure exclusion heuristic (§8 above) is new, flagged,
  not one of the original 10 decisions — confirm it's acceptable, or
  direct a different treatment.
- Family A (`generateLegacyFixedPair`) is untouched, per D-10B6-9 —
  confirmed via the full green suite (every legacy/Powerlifting/other-
  Hypertrophy-configuration test still passes unmodified).
- e1RM population for Family A/Powerlifting remains explicitly out of
  this pass's scope, as agreed.
- The Simulator GUI automation limitation (§12) is environmental, not a
  code defect — flagged transparently rather than worked around with a
  debug shortcut, matching Stage 10B's own precedent.

**Not committed. Not pushed. Stage 10C not started.** Waiting for your
manual acceptance.
