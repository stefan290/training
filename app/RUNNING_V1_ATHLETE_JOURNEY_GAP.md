# RUNNING V1 — Athlete Journey Gap Analysis

Analysis only. No code changed. No git operations performed by this checkpoint.

## 1. Real production path traced

`StrategicPlanSelectionViewModel`/`View` → `LongTermPlanner.proposeTrainingMix`
(ranked presets) or `LongTermPlanner.buildCustomMix` (explicit "Build My Own
Mix") → `TrainingMix` with `TrainingMixComponent`s → `LongTermPlanner
.proposeProgram` (per component) → `ProgramCandidate`/`CapabilityGap` →
accept/start → `StartPhaseUseCase`/`RollTacticalWindowUseCase` → real
`Session`s → `TodayView` → `SessionDetailView` → per-block execution view
(`SteadyStateExecutionView`/`IntervalExecutionView`/etc.) → `RecordSteadyStateResultUseCase`/
`RecordIntervalResultUseCase` → `CompleteSessionUseCase` → `ProgressView`.

## 2. What already works

- **G (execution UI) — already generic, no Running-specific work needed
  for structure/labels/RPE:** `SessionDetailView.swift:186-193` dispatches
  `.steadyState`→`SteadyStateExecutionView`, `.intervals`→
  `IntervalExecutionView` purely on `WorkoutBlockType`, with zero
  activity-type branching. `IntensityPresentation.swift` already renders
  `.percentOfReference(_, metric:)` (line 17: `"\(lower)-\(upper)%
  \(metricLabel(metric))"`, `metricLabel(.thresholdPace)` → `"Threshold
  Pace"`) and `.rpe` generically. `session.orderedBlocks` is iterated in
  full (`SessionDetailView.swift:78`), so a multi-repeat-group Running
  session (multiple `.intervals` blocks in one `Session`, per R3's own
  architecture) renders block-by-block exactly like any other multi-block
  session — no new UI needed for this.
- **H (logging) — already generic:** `RecordSteadyStateResultUseCase.swift`/
  `RecordIntervalResultUseCase.swift` exist, branch on nothing
  Running-specific; `IntervalExecutionView.swift:91,123,163` already
  renders "Interval X of Y" generically.
- **I (completion/tactical advancement) — verified safe, not broken:**
  `CompleteSessionUseCase.swift` has zero modality/activity branching at
  all (grep confirmed). `TacticalAdvancementPreflight.swift` already
  excludes `.running` from its `activeFromWeek <=` computation (added in
  R3, independently verified that session) for the same reason
  `.steadyState` is excluded — Running's whole 13 weeks materialize
  upfront (`RunningProgramMaterializer.materializeAllWeeks`), so
  "advancing" is correctly a no-op, not a silent break.
- **Today (F) — appears generic:** `TodayView.swift` filters sessions by
  id/status, not by modality or `ProgrammingSystemKind` (no such branch
  found) — a materialized Running `Session` should surface exactly like
  any other.

## 3. Athlete-journey blockers (BLOCKS ATHLETE JOURNEY)

1. **No path from any goal/onboarding/mix-selection flow ever reaches
   `RunningProgramGenerator`.** Confirmed by direct grep: outside this
   Running system's own files and tests, `RunningProgramGenerator`/
   `RunningBuiltInLibrary` are referenced ONLY inside `LongTermPlanner
   .proposeProgram`'s `.running` case (`LongTermPlanner.swift:1721-1731`),
   which returns `rawCandidates = []` unconditionally — a dead branch by
   the checkpoint's own explicit design. **A. Answer: the athlete cannot
   currently select or request Running at all**, through any UI path.
2. **The existing "Running" concept in the app is a different, older,
   disconnected one.** `LongTermPlanner.underlyingSystem(for:
   TrainingStyle.running)` (`LongTermPlanner.swift:684-691`) maps the
   athlete-facing "Running" style choice (in `buildCustomMix`, the
   explicit "Build My Own Mix" flow) to `ProgrammingSystemKind.steadyState`
   — generic Zone-2-style continuous cardio, activity-locked to running via
   `ModalityPreference` — never to the new `.running` system this
   engagement built. **B. Answer: no.** There is no "5K"/race-distance
   objective concept anywhere in `Goal`/`LongTermGoalTypes.swift` at all
   (confirmed: zero matches for any race/distance-goal vocabulary outside
   the Running R1-R3 files themselves), so a 5K dated objective cannot
   exist as an input, let alone route anywhere.
3. **No threshold-pace entry UI exists.** `RunningThresholdCalibration`/
   `RecordRunningThresholdCalibrationUseCase` (R2) have zero UI callers —
   confirmed by grep across `TrainingOS/UI/`. The strength-side precedent,
   `SourceRMCalibrationView.swift` (163 lines), has no running equivalent.
   **D. Answer: nowhere — the capability exists only at the domain layer.**
4. **The calibration-required gate is never invoked.** `RequiredRunningCalibrationUseCase
   .isThresholdCalibrationRequired` (R3) has zero callers anywhere in
   production code (confirmed by grep — only its own test file references
   it). **E. Answer: nothing happens — a Running session could currently
   be presented and executed with no threshold entered at all**, showing a
   bare, unresolved "80-80% Threshold Pace" label with no way to convert it
   to an actionable pace.
5. **No production code path ever calls `ThresholdPaceEngine`.** Confirmed
   by grep: the only non-test reference to `ThresholdPaceEngine` is inside
   `RunningProgramGenerator.swift`'s own doc comment, describing an intent
   that was never implemented — `RunningProgramMaterializer.swift` copies
   `steadyTemplate.primaryIntensity`/`intervalTemplate.workIntensity`
   straight through as the unresolved `.percentOfReference` fraction, and
   `IntensityPresentation.label` only ever prints that fraction as a
   percentage. **An athlete would see "80-80% Threshold Pace" on screen,
   never "6:15/km"** — R2's entire threshold-personalization feature is
   currently invisible/unusable at the UI layer, which directly
   contradicts this program's own stated purpose (materialize the SAME
   structure with DIFFERENT athlete-specific paces).

## 4. Checkpoint bugs (CHECKPOINT BUG)

None found that constitute an actual defect in what R1/R2/R3 claimed to
deliver — every gap above is a genuine, disclosed integration gap (the
capability was explicitly scoped as domain-only, R3's own DO-NOT-TOUCH list
excluded UI), not a broken promise. No regression, no incorrect behavior
inside the already-verified R1/R2/R3 scope was found during this trace.

## 5. Follow-ups (FOLLOW-UP)

- **J: Progress does not yet surface endurance/activity history.**
  `ProgressView.swift`/`ProgressPresentation.swift` read
  `BenchmarkPerformanceProfile`/`PersonalRecord` (strength/functional-fitness
  shaped) with zero reference to `ActivityPerformanceProfile` anywhere.
  This predates Running entirely (Bike/Row already have this same gap) —
  not a Running-specific defect, but real: after completing a Running
  session, nothing in Progress shows it as evidence yet.
- Multi-repeat-group session presentation is structurally correct (block-
  by-block) but was never visually verified for Running's own densest case
  (3 repeat groups in one session, R1's week 11) — worth a dogfood
  screenshot pass once the athlete-facing gaps below are closed, not a
  blocker on its own.

**IMPROVEMENT (not a follow-up, no journey impact):**
`IntensityPresentation.label`'s `.percentOfReference` branch could
eventually show BOTH the percentage and the resolved pace once threshold
resolution exists (not required for V1's minimum honest journey — showing
a resolved pace alone is sufficient).

## 6. Minimum next implementation scope

Only items in §3 (BLOCKS ATHLETE JOURNEY) belong in the next checkpoint —
§5/"IMPROVEMENT" do not:

1. **A real selection entry point.** Smallest honest integration: do NOT
   reopen `LongTermPlanner`'s general ranked-recommendation policy
   (`proposeTrainingMix`/`proposeProgram`'s scoring). `buildCustomMix`
   already proves an explicit, athlete-driven, non-ranked construction path
   exists and is architecturally separate from scored recommendations —
   the smallest change is adding a genuinely new explicit choice there
   (not reusing the existing `.running` `TrainingStyle`, which already
   means something else) that maps to `ProgrammingSystemKind.running` and,
   when selected, calls `RunningProgramGenerator`/`RunningBuiltInLibrary`
   directly — mirroring how `buildCustomMix` already bypasses
   `candidateMixTemplates` for exactly this "not a scored recommendation"
   reason.
2. **Threshold-pace entry UI**, mirroring `SourceRMCalibrationView`'s
   existing approved pattern, gated by `RequiredRunningCalibrationUseCase
   .isThresholdCalibrationRequired` actually being called at the
   appropriate point before a Running session is presented for execution
   (the exact strength-side precedent: `RequiredSourceCalibrationsUseCase
   .stillRequired` gating `RollTacticalWindowUseCase
   .materializeFirstWindow`).
3. **Wire `ThresholdPaceEngine` into the real display/execution path** so
   an athlete ever sees an actual pace, not a bare percentage — the
   natural minimal integration point is `IntensityPresentation` itself
   (already the single shared display layer for both execution screens),
   extended to resolve `.percentOfReference(_, .thresholdPace)` against
   the instance's current `RunningThresholdCalibration` when one is
   available.

## 7. UI surfaces affected

- **Program/mix selection** — extends `StrategicPlanSelectionView`'s
  existing "Build My Own Mix" surface (already the approved, existing
  design pattern for explicit, non-ranked selection) with one more
  explicit choice; does not touch the ranked/recommended card UI at all.
- **Threshold calibration** — extends the existing `SourceRMCalibrationView`
  pattern (Today = action, gated entry before execution) with a Running
  equivalent; same visual language, same "explicit athlete input required
  before proceeding" flow, never a silent default.
- **Session execution (`SteadyStateExecutionView`/`IntervalExecutionView`/
  `IntensityPresentation`)** — no new view needed; one shared display
  function (`IntensityPresentation.label`) gains threshold-resolution
  awareness.
- **Today/Plan/Progress** — no changes required for the athlete to
  complete the journey; Progress's endurance-history gap (§5) is
  pre-existing and out of this scope.

## 8. Explicitly out-of-scope items

Everything from the FINALIZE checkpoint's own §2 backlog (Running V2: 3+
days/week, other athlete levels, structural adaptation, starting-volume
personalization, additional reference sources, generalized mesocycle/
deload/taper; Running V3: 10K/Half/Marathon) — none of it is touched or
implied by anything in this gap analysis. Also out of scope: redesigning
Today/Plan/Progress, reopening any closed visual checkpoint, Progress's
pre-existing endurance-history gap (§5, not Running-specific).

## 9. Recommended next checkpoint

A narrow "Running V1 Athlete-Reachability" implementation checkpoint
covering exactly the 3 items in §6 — one new explicit selection path (not
a new recommendation policy), one calibration-entry screen (mirroring
`SourceRMCalibrationView`), and one resolution fix in
`IntensityPresentation` — with its own dogfood proof that an athlete can
go from selecting Running through logging a real session with a real,
personalized pace displayed on screen.

---

RUNNING V1 CHECKPOINT: CLOSED
ATHLETE JOURNEY COMPLETE TODAY: NO
NEXT IMPLEMENTATION SCOPE IDENTIFIED: YES
