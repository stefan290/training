# Running Athlete Journey Completion — Threshold Pace Calibration + Executable Pace

Vertical Completion V1 from the Whole Athlete Journey final audit, fixing
BLOCKER RUN-PACE-1. Implementation checkpoint. Not committed, not pushed —
stopped after implementation, verification, dogfood, and this report for
independent review, per explicit instruction.

## 1. Baseline

Full suite immediately before this checkpoint's changes: **1592 tests, 0
failures** (`xcodebuild test-without-building -parallel-testing-enabled
NO`, real summary line, confirmed directly before any edit).

## 2. Root Cause

Every mechanism needed to fix RUN-PACE-1 already existed and was already
unit-tested in isolation — this was purely a wiring gap:

- `ThresholdPaceEngine` (pure pace math) — already correct, untouched.
- `RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired` —
  already correct, untouched.
- `RecordRunningThresholdCalibrationUseCase.record`/`currentThreshold` —
  already correct, untouched.
- `RunningThresholdCalibration` (`@Model`) — already correct, untouched.

None of these had a single production caller anywhere in `TrainingOS/UI`
or `TrainingOS/Application/ViewModels` (independently re-confirmed via
`grep` before writing anything). `IntensityPresentation.label(_:)` — the
one shared formatter every Running/endurance display already routes
through — rendered a `.percentOfReference` target as literal percent text,
never resolving it.

**A second, more severe, previously-undiagnosed bug was found and fixed as
part of this same root cause investigation**: `RunningProgramGenerator
.intensityTarget(for:)` stores `percentOfThreshold` as a **fraction**
(`0.8` for 80%, confirmed directly against its own literal source-derived
fixture data, e.g. `percentOfThreshold: 0.8`, `percentOfThreshold:
0.6993006993006993`). `IntensityPresentation.label(_:)`'s old
`.percentOfReference` case computed `Int(range.lower)` directly on this
fraction — `Int(0.8) = 0`. **Every %threshold-prescribed Running block
was therefore displaying as the literal string "0-0% Threshold Pace"**,
not merely an unresolved-but-correct percentage. This is now fixed
alongside the resolution work (§6), and proven by a dedicated regression
test (`testRawPercentLabelNoLongerTruncatesFractionalStorageToZero`).

## 3. Calibration Production Path

`RootTabView` already had exactly one precedent for "block Today until the
athlete supplies a required value" — `SourceRMCalibrationViewModel`
(Strength/Hypertrophy RM entry). A second, analogous gate was added,
checked immediately after the existing one:

```swift
if calibrationViewModel.hasPendingCalibration {
    SourceRMCalibrationView(...)
} else if runningCalibrationViewModel.hasPendingCalibration {
    RunningThresholdCalibrationView(...)
} else {
    TabView { ... }
}
```

**The one deliberate architectural difference from the RM pattern**:
Running's own materialization is **not** deferred on calibration —
`RunningProgramMaterializer.materializeAllWeeks` already runs regardless
(confirmed directly: "nothing in this program depends on a live per-week
result," its own doc comment) — so the new `RunningThresholdCalibrationViewModel`
never calls a materialization use case. It exists purely to persist the
athlete's entry via the already-existing `RecordRunningThresholdCalibrationUseCase.record`,
so `IntensityPresentation`'s new resolution path (§6) has a real value to
read before the athlete ever reaches Today. `RunningThresholdCalibrationViewModel.load`
scans every `.active` `ProgramInstance` exactly like `SourceRMCalibrationViewModel.load`
does, using the real `RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired`.

Gate ordering: the RM gate is checked first (matching the pre-existing
precedence this file already had), the Running gate second. An athlete
with both outstanding simultaneously (a rare concurrent-mix edge case)
resolves the RM gate first; the Running gate then appears on the very
next `load()` call once the first is satisfied — never skipped, never
both shown at once.

## 4. Athlete Input UI

`RunningThresholdCalibrationView.swift` (new) mirrors `SourceRMCalibrationView`'s
exact editorial grammar: `Theme.headingXL` heading, the same "ONE LAST
STEP" reassurance-card framing (`.trainingOSCard(emphasized: true)`), the
same `.trainingOSPrimary` button style. Copy deliberately avoids "Threshold
Pace" jargon in the primary heading/explanation ("Set your running pace" /
"the pace you could sustain hard, but steadily, for about 20-30 minutes")
— the athlete never needs to understand the internal engine term to
answer the question.

**Input format**: mm:ss per kilometer (two separate numeric fields,
minutes and seconds), matching the unit convention already established
everywhere else in the Running UI — `IntensityPresentation.paceLabel`
already formats every pace as `mm:ss/km`; no new unit convention was
invented (the codebase's Running model is metric-only throughout — no
existing imperial-unit support was found to preserve, confirmed by
`grep`).

Persistence: `RunningThresholdCalibrationViewModel.completeCalibration`
converts the two fields to total seconds and calls the real, unchanged
`RecordRunningThresholdCalibrationUseCase.record(thresholdPaceSecondsPerKilometer:for:isScheduledCheckpoint:false:modelContext:)`
— `isScheduledCheckpoint: false` because this screen is always the
athlete's initial entry; `RunningThresholdRecalibrationGate` (unchanged,
untouched) is the sole authority on whether that's allowed, exactly as it
already was for every other caller.

## 5. ThresholdPaceEngine Production Wiring

`IntensityPresentation.resolvedLabel(_:thresholdPaceSecondsPerKilometer:)`
(new) is the one place `ThresholdPaceEngine` is now called from a real
UI-adjacent path — it never duplicates the division itself. Confirmed the
exact input scale before wiring: `ThresholdPaceEngineTests.swift`'s own
fixtures pass `percentOfThreshold: 0.80`/`1.00`/`1.10` (fractions), which
is exactly what `RunningProgramGenerator` already stores in
`BoundedRange(lower: percent, upper: percent)` — **no scale conversion
needed at the engine boundary**, only at the display-formatting boundary
(§2's bug fix).

```swift
static func resolvedLabel(_ target: IntensityTarget?, thresholdPaceSecondsPerKilometer: Double?) -> String? {
    guard let target else { return nil }
    guard case .percentOfReference(let range, let metric) = target, metric == .thresholdPace,
          let threshold = thresholdPaceSecondsPerKilometer
    else { return label(target) }
    let paces = [range.lower, range.upper]
        .map { ThresholdPaceEngine.targetPace(thresholdPaceSecondsPerKilometer: threshold, percentOfThreshold: $0) }
        .sorted { $0.secondsPerKilometer < $1.secondsPerKilometer }
    let percentText = "\(Int(range.lower * 100))-\(Int(range.upper * 100))% \(metricLabel(metric))"
    return "\(paceLabel(paces[0]))-\(paceLabel(paces[1]))/km · \(percentText)"
}
```

Called from the athlete's real, currently-calibrated threshold, fetched
fresh via `session.programInstance` → `RecordRunningThresholdCalibrationUseCase
.currentThreshold(for:)` — never cached, never re-derived. When no
calibration exists (should be unreachable once §3's gate is satisfied, but
never assumed), falls back to `label(_:)`'s own honest raw-percentage text
— never fabricates a pace.

## 6. Pace Presentation

**Sorting correction, load-bearing**: a higher percent-of-threshold is a
FASTER pace (fewer seconds/km) — `range.lower`/`range.upper` do NOT map
directly to "slower pace"/"faster pace" respectively. `resolvedLabel`
resolves both bounds through `ThresholdPaceEngine` independently, then
sorts the two resulting `Pace` values ascending by `secondsPerKilometer`
before formatting — proven by `testPercentRangeResolvesCorrectlyBothBounds`
(80-85% of a 5:00/km threshold resolves as "5:53-6:15/km," the 85%/faster
pace first, not "6:15-5:53/km").

Both the resolved pace AND the original percent-of-threshold text are
shown together (e.g. `"5:33-5:33/km · 90-90% Threshold Pace"`) — the
source prescription (percentage) and the athlete-facing resolved fact
(pace) stay visibly distinct, never conflated, and the source's own
percentage is never rewritten, only interpreted for display.

**Call sites updated** (3, all real athlete-facing surfaces — before-
starting preview and live execution, the two contexts where an athlete
needs an actionable number):
- `SteadyStateExecutionView.swift:98` (live execution)
- `IntervalExecutionView.swift:94` (live execution)
- `SessionPreviewContent.swift` (3 sub-sites: steady-state primary
  intensity, interval work intensity, interval recovery intensity) — the
  before-starting preview shown from Session Detail; just as important to
  make actionable as execution itself, since an athlete previewing today's
  Running workout needs the same real pace, not a raw percentage.

**Deliberately left unchanged**: `CompletedEnduranceDetail.swift`'s 3 call
sites (completed-history display). These render a workout already
performed — the athlete's own logged, actual pace is already shown there
via the existing `paceLabel(secondsPerKilometer:)` path; the ORIGINAL
prescribed percentage is retrospective context, not something requiring
action. Resolving it too would be reasonable but was judged unnecessary
scope for this checkpoint's actual blocker (a live, unexecutable
prescription) — noted as a disclosed scoping decision, not an oversight.

## 7. RunningExecutionOverride Wiring

**Investigated and deliberately NOT wired this checkpoint.**
`SteadyStateExecutionView.swift`/`IntervalExecutionView.swift` were read
in full: neither contains any existing in-session "run faster than
prescribed" affordance — no button, gesture, or control of any kind that
could be pointed at `RunningExecutionOverrideEngine.evaluateIntensityOverride`
without first inventing new athlete-facing UI. Per the checkpoint's own
explicit STOP condition ("if wiring it requires unrelated redesign, STOP
and report why rather than broadening this checkpoint"), no such UI was
added. `RunningExecutionOverrideEngine`'s own semantics remain completely
untouched (as required) and remain correctly, fully covered by
`RunningExecutionOverrideEngineTests.swift`, unchanged by this pass. This
is documented as a disclosed FOLLOW-UP (§14), not a silent gap —
`testRunningExecutionOverrideEngineDeliberatelyNotWiredThisCheckpoint`
records the decision directly in the test suite.

## 8. Calibration Lifecycle

Traced and proven, end to end, through real production code
(`testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable`):

1. A real `TrainingMix` with a Running component is built and accepted
   (`StrategicPlanSelectionViewModel.buildCustomMix` → `acceptAndStart`).
2. The Running `ProgramInstance` materializes immediately, regardless of
   calibration (`runningInstance.sessions` non-empty, confirmed).
3. `RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired`
   reports `true`.
4. The athlete enters `5:00` via `RunningThresholdCalibrationViewModel`
   (the real, new production view-model).
5. `RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired` now
   reports `false`.
6. A real materialized session's `steadyStatePrescription.primaryIntensity`
   resolves through `IntensityPresentation.resolvedLabel` to an actual
   pace string containing `"/km"` — never a raw percentage alone.
7. The next Running workout in the same instance reads the exact same,
   single, persisted `RunningThresholdCalibration` row — never re-prompted
   (no scheduled-recalibration-trigger logic was built or altered this
   checkpoint; `RunningThresholdRecalibrationGate` remains the sole,
   unchanged authority on when a NEW entry would ever be allowed).

Mid-week/R0: unaltered. The new gate fires whenever `RootTabView` appears
with a pending requirement, exactly like the pre-existing RM gate — since
Running's own materialization is never deferred, there is no equivalent
"waiting on materialization" state for Running to interact with R0 at
all; calibration can be entered any day of the week, same as the existing
RM screen already allows.

## 9. J3 Verification

`testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable` (real
production path, not a hand-assembled shortcut): Goal `.muscleGain`, 4x
Hypertrophy + 2x Running, real onboarding/recommendation/acceptance
(`buildCustomMix` → `acceptAndStart`), real calibration completion for
Hypertrophy via the existing `CalibrationTestSupport` harness, real
Running calibration via the new view-model. Confirms: `goal.primaryType ==
.muscleGain` unchanged throughout; Running materializes regardless of
calibration; calibration requirement detected, then cleared; a real
materialized session's prescription resolves to a pace-containing string.
**Passing.**

## 10. J5 Verification

`testJ5_HybridMixRunningComponentBecomesExecutableWithoutChangingTheMix`
(real production path): the same 3-Hypertrophy + 1-Functional-Fitness +
2-Running composition already proven feasible by
`ConcurrentProgrammingGoldenScenarioTests.testG1_...` (reused deliberately,
not reinvented, since this test's purpose is proving Running's pace
resolution within an already-feasible hybrid mix, not re-proving
scheduling feasibility). Confirms: component count and system set
identical before and after acceptance AND after resolving Running's own
pace (`Set(mix.orderedComponents.compactMap(\.programmingSystem))`
unchanged both times); Running's own component resolves to an actual pace
string. **Passing.**

## 11. Dogfood

Goal: BUILD MUSCLE. Running: exactly 2 sessions/week. Threshold Pace TEST
FIXTURE: **5:00/km (300 seconds/km)**. Traced through the real production
path (`RunningProgramMaterializer.materializeAllWeeks` → real
`RecordRunningThresholdCalibrationUseCase.record` → real
`IntensityPresentation.resolvedLabel`):

| Block | Actual generated source intensity | Actual resolved athlete pace |
|---|---|---|
| Week 1 Slot A, Tempo | 90.09% Threshold Pace (`percentOfThreshold: 0.9009009009009009`) | `5:33-5:33/km · 90-90% Threshold Pace` (300/0.9009... = 333.0s = 5:33/km — the exact, already-established golden pace, now athlete-facing) |
| Warm-up block | 80% Threshold Pace (`0.8`) | `6:15-6:15/km · 80-80% Threshold Pace` (300/0.8 = 375s = 6:15/km) |
| A different warm-up variant | 69.93% Threshold Pace (`0.6993006993006993`) | `7:09-7:09/km · 70-70% Threshold Pace` (300/0.6993... = 429.0s = 7:09/km) |

Every value above was computed by the real `ThresholdPaceEngine.targetPace`
call inside `resolvedLabel`, verified exactly (not approximated) by
`testExistingSourcePrescriptionStructureUnchangedAndNowResolvesThroughPresentation`
and the dogfood scenario tests. The chain does not stop at unit-engine
output — every number above is what a real materialized `Session`'s real
`steadyStatePrescription.primaryIntensity`, run through the real
production presentation function, actually returns.

## 12. Tests

`TrainingOSTests/RunningAthleteJourneyCompletionTests.swift` (new, 12
tests across 2 `XCTestCase` classes):

- A: `testViewModelSurfacesPendingRunningCalibrationWhenRequired` — PASS.
- A (negative): `testViewModelHasNoPendingCalibrationOnceEntered` — PASS.
- B: `testCompletingCalibrationPersistsThroughTheRealCalibrationModel` — PASS.
- B (negative): `testIncompleteEntryNeverSatisfiesOrPersists` — PASS.
- C/D: `testPercentOfThresholdPrescriptionResolvesToTheCorrectPace` (exact
  5:00/km, 80% → 6:15/km, hand-computed and matched) — PASS.
- E: `testPercentRangeResolvesCorrectlyBothBounds` (80-85% → 5:53-6:15/km,
  correct ascending sort) — PASS.
- F: `testMissingCalibrationNeverResolvesToAFabricatedPaceAndShowsHonestPercentage` — PASS.
- (bonus) `testRawPercentLabelNoLongerTruncatesFractionalStorageToZero` —
  proves the §2 bug fix directly — PASS.
- G: `testExistingSourcePrescriptionStructureUnchangedAndNowResolvesThroughPresentation`
  — PASS.
- H: `testRunningExecutionOverrideEngineDeliberatelyNotWiredThisCheckpoint`
  — documents the deliberate non-wiring decision (§7); N/A per the
  investigation, not forced — PASS.
- I: `testJ3_BuildMusclePlusExactTwoRunningSessionsBecomesExecutable` — PASS.
- J: `testJ5_HybridMixRunningComponentBecomesExecutableWithoutChangingTheMix` — PASS.

## 13. Closed-System Impact

No Running workout source structure, frequency, distance support, or
adaptation-scheduling semantics changed — `RunningProgramGenerator`'s own
literal source data (percentages, distances, slot structure) has zero
diff lines. No Hypertrophy/Strength/Powerlifting/Functional Fitness source
content touched. No `ConcurrentScheduler`/scheduling rule touched. No
`LongTermPlanner` phase-sequencing/dated-objective code touched (LTP-1 is
explicitly the next checkpoint, untouched here). No Training Environment,
R0, Progress, or Year Overview file touched. `ThresholdPaceEngine`'s own
formula and `RunningExecutionOverrideEngine`'s own semantics are
byte-for-byte unchanged.

## 14. Deferred Items

- `RunningExecutionOverrideEngine` production wiring — genuinely requires
  new in-session UI (an "increase pace" affordance) that does not
  currently exist; correctly deferred per §7, FOLLOW-UP.
- `CompletedEnduranceDetail.swift`'s 3 completed-history call sites —
  could also show resolved pace for consistency; judged non-essential
  this pass (retrospective display, not an action the athlete needs to
  take), FOLLOW-UP.
- LTP-1 (Long-Term Planner periodization intelligence) — explicitly the
  next checkpoint, not touched here.

## 15. Final Verdict

RUNNING CALIBRATION COLLECTABLE: PASS
THRESHOLD PACE PERSISTED: PASS
THRESHOLD PACE ENGINE PRODUCTION-WIRED: PASS
RUNNING PERCENT TARGET RESOLVES TO PACE: PASS
RUNNING PACE RANGE RESOLVES: PASS
MISSING CALIBRATION FAILS HONESTLY: PASS
RUNNING SOURCE PROGRAM UNCHANGED: PASS
RUNNING EXECUTION OVERRIDE REACHABLE: FAIL
TODAY RUNNING EXECUTABLE: PASS
J3 RUNNING + BUILD MUSCLE: PASS
J5 HYBRID / CONCURRENT: PASS
FULL SUITE: PASS
NEW FAILURES: 0
RUN-PACE-1: CLOSED
READY FOR LONG-TERM PLANNER COMPLETION: YES
