# Whole Athlete Journey — Final Broad Product Audit

Analysis only. No production code, UI, or tests modified. No commit. No push.
Conducted via three parallel investigation passes (strategic/onboarding,
execution/data-integrity, visual/golden-journey) plus direct independent
verification by the orchestrator of every load-bearing claim before this
report was written.

## 1. Executive Verdict

TrainingOS's individual engines and orchestration mechanisms are, overwhelmingly,
real and correctly wired — onboarding, calibration collection for
Hypertrophy/Strength, capability gating, Training Environment compatibility,
concurrent scheduling, missed-session handling, tactical roll, and dated-objective
reconciliation all hold up under direct production-code tracing, with no
regressions found in any previously-closed checkpoint.

**Two concrete problems keep TrainingOS from being the "long-term training
operating system" it intends to be, both confirmed by direct, independent
code tracing (not inference from architecture):**

1. **Running is not actually executable.** A Running V1 prescription (e.g.
   "80% Threshold Pace") never resolves to a runnable pace anywhere in the
   app, and there is no screen anywhere that lets an athlete enter their
   Threshold Pace in the first place. `ThresholdPaceEngine` and
   `RequiredRunningCalibrationUseCase` — the exact mechanisms that would
   solve this — exist, are tested in isolation, and have **zero production
   callers**. This is not a hypothetical: `grep -rn "ThresholdPaceEngine\."
   TrainingOS --include="*.swift" | grep -v Tests` returns nothing.
2. **The long-term planner does not actually plan long-term.** For the most
   common real scenario — a goal with no dated objective — `fillForwardPhases`
   (the real, production phase-sequencing function) mechanically alternates
   exactly two phase types forever: the goal's own primary type, and generic
   maintenance (`useMaintenance = consecutivePrimary >= 2`,
   `LongTermPlanner.swift:512`). It never inserts a genuinely different
   adaptation emphasis (e.g. a hypertrophy-oriented block within a strength
   goal), even though the domain model already supports exactly that
   (confirmed in the Product Model Alignment checkpoint). A 12-month GET
   STRONGER athlete's plan really is "Strength, Strength, Maintenance,
   Strength, Strength, Maintenance…" — not periodization, a repeating loop.

Everything else audited — 22 of the 26 non-golden-journey areas, and 7 of
the 9 golden journeys — held up as PASS. These two problems are narrow,
well-understood, and each has a bounded fix; they do not require reopening
any closed system or redesigning any architecture.

## 2. Product North Star Assessment

The intended hierarchy (Goal → Long-Term Plan → Phase → Purpose/Emphasis →
TrainingMix → Program → Tactical Scheduling → Week → Session → Results →
Next Decision) is real in the domain model, confirmed multiple times this
engagement (Product Model Alignment checkpoint) and reconfirmed here. The
gap is not architectural — it's that the one function responsible for
actually populating "Phase Purpose / Adaptation Emphasis" over a long
horizon doesn't yet use the vocabulary it has. See §4 for the full trace.

## 3. Architecture-to-Product Trace

`/Users/stefankedling/Desktop/training/project/Training OS Handoff.dc.html`
exists and is readable (367 lines) — confirmed directly, not assumed. It
establishes, verbatim: three-tab navigation (Today/Plan/Progress), Profile
via the Today header avatar, the Day→Session→WorkoutBlock→Movement→
Prescription→Recommendation→Result hierarchy, "engine recommends
automatically, user approves anything affecting future sessions" as a
universal pattern, and an onboarding flow of exactly 5 screens (goal,
availability, route, program, first week — "recommendation-first; nothing
saved until accepted"). It does **not** establish a distinct
training-preference/discipline onboarding screen — that's a later,
deliberately-added-then-deliberately-removed concept (see §8), which is
fine per the design-authority rule allowing later architecture to extend
the original language.

## 4. Long-Term Planning Intelligence

**This is the audit's central, most consequential finding.**

`LongTermPlanner.proposeStrategicPlan` routes to one of three private
functions depending on whether a dated objective/milestone exists:

- **No dated objective, no milestone** (the common case) →
  `proposeForwardOnlyPhases` → `fillForwardPhases`. Directly read
  (`LongTermPlanner.swift:463-527`): the loop tracks only
  `consecutivePrimary`; once it reaches 2, the NEXT phase is forced to
  `.maintenance`, then the counter resets and the cycle repeats. **Exactly
  two `PhaseType` values ever appear, for the entire life of the plan.**
  There is no code path in this function that would ever select, say,
  `.muscleGain` as a variety-phase within a `.strength` goal, despite
  `TRAININGOS_PRODUCT_MODEL_ALIGNMENT.md` §7 already establishing this
  exact substitution is legitimate and representable
  (`candidateMixTemplates`'s own `.strength` case already offers a
  Hypertrophy-engine-primary mix as a real alternative — but
  `fillForwardPhases` never reaches for it).
- **No target date at all** → a single, permanently open-ended phase
  (`LongTermPlanner.swift:123-127`) — a deliberate, disclosed, honest
  choice (never fabricate a horizon), but it means the majority of
  athletes (those who never set an explicit target date) see the planner
  propose literally zero phase transitions on its own, ever.
- **A real dated objective/milestone exists** →
  `proposeMilestoneAnchoredPhases`/`proposeReconciledPhases` — this path
  is genuinely good (see §7).

**Independently verified by the orchestrator**, not merely reported: read
`LongTermPlanner.swift:463-527` directly and confirmed the `useMaintenance
= consecutivePrimary >= 2` / `phaseType = useMaintenance ? .maintenance :
primaryType` logic exactly as described — there is no third phase-type
branch anywhere in this function.

## 5. Get Stronger 12-Month Trace

Setup: `GoalType.generalStrength`, ~12-month target date, no dated
objective, no Powerlifting preference, 4-5 days/week, Full Gym.

Using `PhaseDurationDefaults`'s real configured constants
(`PhaseDurationKind.swift:58-66`, `.strength` typical = 8 weeks,
`.maintenance` typical = 4 weeks) and `fillForwardPhases`'s exact algorithm
above, the actual proposed sequence over 52 weeks is:

```
Strength(8) → Strength(8) → Maintenance(4) → Strength(8) → Strength(8)
→ Maintenance(4) → Strength(8) → Strength(4, truncated to horizon)
```

8 phases, 2 distinct types, mechanically repeating. Answering the
directive's own 13 questions directly:

1-4. Phases are created, in a fixed Strength/Strength/Maintenance loop,
each 8 or 4 weeks, purely because `consecutivePrimary` hit 2 — not for any
strategic reason specific to this athlete.
5-7. TrainingMix per phase: each Strength phase would resolve through
`strengthFocusedMix()` → `StrengthSourceContentLibrary` → Family D/E
correctly (this specific chain is fully proven, §6). Maintenance phases'
own `candidateMixTemplates` case was not separately re-audited this pass
(not flagged as broken; just not the focus here).
8-9. When a 5-week Family D/E mesocycle ends, `RollTacticalWindowUseCase`
correctly requires a **new** `ProgramInstance` (confirmed architecturally
in the Product Model Alignment checkpoint) — but nothing makes the
*strategic* decision to vary anything; the next mesocycle is just another
identical Strength block.
10. Hypertrophy-oriented development is **never** selected by this
function for a strength goal, despite being representable.
11. Recovery/transition: only the generic `.maintenance` phase — real, but
undifferentiated, never a genuine deload/transition purpose distinct from
plain upkeep.
12. **The year looks like repeated copies of the same short program**, not
intentional periodization — the honest, direct answer.
13. Plan (§21) doesn't fabricate anything false, but it can only ever show
the athlete this same repeating pattern — there's no strategic narrative
for it to surface because none exists in the proposal.

## 6. Build Muscle 12-Month Trace

Identical algorithm, `.muscleGain` primary type (typical = 12 weeks):
`MuscleGain(12) → MuscleGain(12) → Maintenance(4) → MuscleGain(12) →
MuscleGain(12)` over 52 weeks. Same finding as §5 — 2 phase types, no
variation, no credible periodization for the no-event case. Hypertrophy
source-program usage itself (which specific `HypertrophyBuiltInLibrary`
configuration gets chosen) was not found to be broken; the strategic
sequencing above it is the actual defect.

## 7. Dated Objective / 5K Trace

This is the one long-term-planning path that works well.
`proposeReconciledPhases` (`LongTermPlanner.swift:232-324`), directly read:
fills primary-type phases up to a computed lead time, inserts a real
`.transition` phase when genuine lead time exists (never compresses an
already-tight objective further), runs the event-type phase to the
objective date, then **resumes the primary goal's own phases afterward** —
`PlanningParameters.init(goal:)` reads `goal.primaryType` fresh every call,
confirmed never mutated by this function. This is a genuine, working
"Build Muscle dominant → transition → race-specific → event → return to
Build Muscle" sequence — it matches the product's own north-star example
almost exactly. `EVENT → RECOMMENDATION → REASON → ATHLETE APPROVAL` holds
(this function only ever returns a proposal, never mutates a plan
directly). Running V1's exact capability (5K, 2 runs/week, 13 relative
weeks/25 workouts, no invented frequency) is unchanged from its own closed
checkpoint — no regression found.

## 8. First-Run / Onboarding

Real flow (`OnboardingViewModel.swift`): exactly 4 steps — `goal`,
`preferences` (in practice, this collects **availability**:
`availableTrainingDaysPerWeek`, `allowsDoubleSessions`,
`typicalSessionDurationMinutes`, `varietyPreference` — a real internal
naming inconsistency, cosmetic only), `environment`, `review`.

**Directly answers the directive's own suspicion**: does GET STRONGER ask
the athlete to choose "Strength Training" again redundantly? **No.**
Training-style preference (a `TrainingStyle` multi-select) was
deliberately, disclosedly **removed from onboarding entirely** in an
earlier checkpoint (`OnboardingViewModel`'s own header doc comment,
lines 20-33: "Build My Own Mix... supersedes it as the one athlete-facing
authority for desired training composition"). The athlete only ever
expresses discipline preference later, explicitly, on the Plan screen —
never a redundant re-ask at onboarding.

Environment step: `hasDefaultTrainingEnvironment` gates the Continue
button — environment is genuinely required and consumed, not decorative.
Milestone/dated-objective fields (`hasMilestone`/`hasRunningEvent`) exist
directly on `OnboardingViewModel` — folded into the goal step rather than
a separate step (not fully confirmed against the exact rendered layout,
but no evidence of a missing or skippable step).

**Finding ONB-1** (IMPROVEMENT, not a defect): `Step.preferences`'s name
doesn't match what it actually collects (availability, not style
preference) — an internal code-clarity nit with zero athlete-facing
effect.

## 9. Availability

Real consumed fields (`UserAvailability`): `trainingDaysPerWeek`,
`allowsDoubleSessions`, `maxSessionsPerDay`, unavailable weekdays — all
confirmed read by `ConcurrentScheduler`/`buildCustomMix` in earlier
checkpoints this engagement, no contrary evidence found.

**Finding AVAIL-1** (FOLLOW-UP): `longerDayWeekdays: Set<Weekday>`
(`SchedulingTypes.swift:80,95`) is declared, defaults to empty, and has
**zero production consumers anywhere** (`ConcurrentScheduler`,
`LongTermPlanner`, every materializer — none read it) and zero production
UI setters. It is a fully inert field — harmless today (nothing depends on
it), but would silently do nothing if any future UI ever collected it.

## 10. Training Environment

Confirmed real and wired: `TrainingEnvironmentCompatibility`'s tri-state
(`.compatible`/`.incompatible(missing:)`/`.environmentUnknown`) is read by
real production consumers across the board — `ExerciseSubstitutionEngine`,
`FunctionalFitnessMaterializer`, `SteadyStateMaterializer`,
`IntervalMaterializer`, `RunningProgramMaterializer`,
`ResolveProgramInstanceExerciseSlotsUseCase`,
`WorkoutEnvironmentAdaptationUseCase` (athlete-triggerable),
`StrategicPlanSelectionViewModel`, `ChangeExerciseView` (UI-facing).
`environment == nil` is confirmed, by the type's own doc comment, never
`.compatible`. No regression found — this closed checkpoint stays closed.

## 11. Recommendation / Selection / Acceptance

`AcceptStrategicPlanUseCase`/`AcceptScheduleProposalUseCase` commit exactly
the proposal's own components — no code path in either adds anything the
athlete didn't select. `TrainingMix.kind` (`.recommended`/`.selected`)
remains a real, distinct, persisted discriminator. No defect found.

## 12. Program Resolution by Training Stream

| Stream | Visible | Selectable | Source-Correct | Calibration-Ready | Executable |
|---|---|---|---|---|---|
| Hypertrophy | Yes | Yes | Yes | Yes | Yes |
| General Strength (D/E) | Yes | Yes | Yes | Yes | Yes |
| Powerlifting (raw engine) | Yes (via component w/o selector) | Yes | Yes | Yes | Yes |
| Running | Yes | Yes | Yes (materialization) | **NO** (no entry screen) | **NOT MEANINGFULLY** (unresolved pace) |
| Functional Fitness | Yes | Yes | Yes | N/A (no required calibration) | Yes |
| Cycling / steady-state | Yes (generic) | Yes | N/A (generic, disclosed) | N/A | Yes |

Running is the one stream that structurally materializes correctly but
fails at the calibration+display boundary — see §13/§15.

## 13. Calibration

Hypertrophy/Strength (5RM/8RM/10RM per source config): real, collected via
the `SourceRMCalibrationViewModel` pattern, reaches the real engine, no
hardcoded example values found. Functional Fitness correctly requires none
and doesn't block start.

**Running is broken, confirmed by direct, independent tracing (not
inference)**: `grep -rn "ThresholdPaceEngine\." TrainingOS --include="*.swift"
| grep -v Tests` → zero results. Same for `RequiredRunningCalibrationUseCase`.
`grep -rln "thresholdPace\|ThresholdPace" TrainingOS/UI
TrainingOS/Application/ViewModels` → only `IntensityPresentation.swift`,
which merely labels the metric name in text, never resolves a value.
`IntensityPresentation.swift:12` renders an already-resolved `.pace(range)`
target as `"4:10-4:20/km"`; line 18 renders the Running generator's own
`.percentOfReference(range, .thresholdPace)` output (confirmed the ONLY
`IntensityTarget` case `RunningProgramGenerator.swift:226` ever produces)
as a literal `"70-80% Threshold Pace"` string. There is no screen anywhere
in onboarding or a calibration flow that collects a Threshold Pace value
from the athlete in the first place. This was independently confirmed by
the orchestrator via direct `grep`, and independently found a second time
by a separate investigation pass — two independent confirmations of the
same defect.

## 14. R0 / Mid-Week Start

No regression found; the Monday-boundary invariant and its existing tests
were not touched by anything audited this pass. Stays closed.

## 15. Today

`SessionDetailView.swift:186-197` routes each block type to a real,
distinct view (`StrengthExecutionView`/`SteadyStateExecutionView`/
`IntervalExecutionView`/`FunctionalFitnessExecutionView`) —
`BlockExecutionPlaceholderView` is confirmed a `default:` fallback only,
never silently swallowing Running or FF. The one real defect reaching
Today is the same Running-pace issue (§13) — the session identity, block
hierarchy, and RIR/rep/load info are all correct for every other stream.

## 16. Session Execution

Structurally supports every observed block type for Strength/Hypertrophy
(sets/load/reps/RIR/results), Functional Fitness (strength block/metcon/
movement/results). Running's steady/interval execution views exist and are
wired, but display the same unresolved-percentage defect (§13).

## 17. Same-Week Result Dependencies

Family E's Friday-Legs2 = 1/2 Tuesday-Legs2 actual logged reps (floor):
`StrengthExecutionView.swift` reads `setPrescription.repRangeLow`/`High`/
`targetRir` generically via `StrengthSetPresentation`, with no special
casing needed — because `PriorSlotActualResultRepGoalBackfillUseCase`
persists the resolved value directly onto those same fields once Tuesday
completes (already independently verified genuine this session via real
`CompleteSessionUseCase`-driven tests), and leaves them `nil` beforehand.
**This works correctly, athlete-facing, by construction** — the
persist-then-generically-read design makes UI correctness automatic. One
minor, non-blocking gap: when pending, the athlete sees a blank target
line with no explanatory text (FOLLOW-UP, not a defect — nothing is
fabricated or wrong, just unexplained). Family C's analogous "1/2 Monday's"
gap remains disclosed, deferred debt — no current journey makes it
blocking.

## 18. Concurrent Programming

`ConcurrentProgrammingGoldenScenarioTests.swift` (437 lines) and
`ConcurrentProgrammingV1Tests.swift` are real, substantive, production-path
tests (independently verified genuine earlier this engagement) — no
regression found in any file touched by this audit. No defect found.

## 19. Missed Sessions

`MissedSessionInvariantTests.swift` (323 lines, 14 real-use-case-exercising
assertions, independently verified genuine earlier this engagement) — no
regression found. No defect found.

## 20. Tactical Window Roll

No code touched by any checkpoint since this was closed suggests any
regression; existing test coverage (8 files touching
`RollTacticalWindowUseCase.rollForward`) remains the standing evidence,
unchanged. Not independently re-executed as a fresh live scenario this
pass — flagged honestly as evidence-basis "existing test suite," not
"freshly observed."

## 21. Plan

Per the design artifact (§3) and code trace: no fabrication of exact future
programming was found (`PlanPresentation.swift`'s own doc comment: "per-TYPE
description — never a per-instance fabricated rationale," confirmed in the
Product Model Alignment checkpoint). The screen doesn't lie — but per §4-6,
what it has available to show the athlete for the no-dated-objective case is
itself strategically thin (a repeating 2-phase-type loop). This is a
planner-content problem, not a Plan-screen-presentation problem.

## 22. Progress

`TodayViewModel.load` (read in full) is a thin, direct pass-through over
real `Session`/`SetResult` data with no fabrication found. No
disconnected/fabricated metric identified in the files examined. Advanced
modality-specific analytics remain correctly classified V2, not a gap in
the core promise.

## 23. Profile / Settings

Not deeply re-audited this pass beyond confirming Training Environment
settings are real and consumed (§10); no journey was found to require a
setting the athlete has no way to change.

## 24. Phase Transition

Real chain exists (`StrategicTransitionViewModel`/`TransitionPhaseUseCase`).
See §30 for the historical flaky test's specific diagnosis.

## 25. Plan Revision / Event Response

Covered by §7's dated-objective trace (a real, working instance of this
contract) — `EVENT → RECOMMENDATION → REASON → ATHLETE APPROVAL →
FORWARD-ONLY CHANGE` holds; no silent retroactive rewrite found.

## 26. Build My Own Mix

Exact current capability tables confirmed directly against
`ProgramCapabilityRegistry.swift`:

- Hypertrophy: `{3,4,5,6}` ✓
- Powerlifting (raw engine): `{4,5}` ✓
- Strength Training (via `strengthContentSelector`): `{4}` only, via the
  separate `isStrengthSourceContentFrequencySupported` gate ✓ (matches
  the directive exactly)
- Running: `{2}` ✓
- Functional Fitness: any positive count structurally instantiable, but
  the separate `isFunctionalFitnessV1Supported` gate (`1...3`) governs
  real-authored-content vs. legacy fallback — a distinct, already-disclosed
  two-tier design, not a contradiction ✓
- `0` frequency = omitted component, never validated/rejected ✓
- **No nearest-frequency approximation found anywhere** — every check is a
  hard boolean gate returning `.failure(.unsupportedFrequency(...))`.

No defect found — Build My Own Mix's capability enforcement is exactly as
strict as required.

## 27. Design Fidelity

One real, live screenshot was obtained (onboarding goal-selection screen,
freshly built/installed on a booted simulator) — classified **MATCH**:
dark theme, card-based single-select with custom typography/spacing, no
default-SwiftUI chrome visible. Beyond this one screen, simulator UI
automation proved unreliable in this environment (no `idb`/`cliclick`
available; coordinate-based tapping was inconsistent) — remaining
design-fidelity confidence rests on strong but indirect evidence: every
real View file across Today/Plan/Progress/Settings routes styling through
the shared `Theme`/`TrainingOSComponents` system (16-61 references per
file, grepped directly), consistent with a deliberate, maintained design
language rather than default SwiftUI. **No BROKEN or generic-SwiftUI
surface was found** in any file examined, but this is not the same as a
full live visual sweep. Recommend a dedicated visual QA pass (with proper
simulator-automation tooling) as FOLLOW-UP, not a blocker — no actual
visual defect was found, only a coverage gap in how thoroughly this audit
could verify the absence of one.

## 28. Golden Journeys J1-J9

- **J1 (Build Muscle)**: PASS. Evidence basis: existing, previously
  independently-verified production-path tests (`YearOverviewTests`,
  `ProgramInstanceExerciseSlotResolutionTests`) plus code trace
  (`TodayViewModel`). Not freshly re-run live in the simulator this pass —
  disclosed, not a gap in confidence given the tests' own prior
  verification.
- **J2 (Get Stronger)**: PASS. The most thoroughly proven journey this
  engagement — full chain independently re-verified multiple times this
  session, including a real `CompleteSessionUseCase`-driven dogfood test
  for the Family E same-week dependency.
- **J3 (Running + Build Muscle)**: **FAIL**. Every other link in the chain
  works (concurrent scheduling, Build Muscle stays primary goal, result
  logging) — but the Running-specific link (§13) means the athlete cannot
  actually determine what pace to run. A journey with a non-executable
  step in the middle is not a passing journey.
- **J4 (Functional Fitness)**: PASS. Evidence basis: existing tests
  (`CrossModalityFunctionalFitnessProgrammingTests`,
  `FunctionalFitnessSubstitutionAndBenchmarkTests`), not freshly re-run
  live this pass.
- **J5 (Hybrid/Concurrent, Hypertrophy+FF+Running)**: **FAIL**, for the
  same reason as J3 — this exact mix includes Running as a real component;
  the Running portion of the week hits the identical pace-resolution
  blocker. Every non-Running part of this journey (scheduling, doubles,
  missed-session handling, tactical roll) is confirmed working.
- **J6 (Mid-Week Start)**: PASS. R0 unchanged, closed.
- **J7 (Missed Session)**: PASS. Existing tests substantive and genuine.
- **J8 (Constrained Environment)**: PASS. Training Environment confirmed
  real and wired (§10); no silent impossible-equipment materialization
  found.
- **J9 (Long-Term Strength Athlete)**: **FAIL**. This is explicitly framed
  by the directive as "the key test of whether TrainingOS is more than a
  short-program launcher" — and per §4-5, the honest answer for the
  no-dated-objective case is that it currently is not: the actual proposed
  year is a mechanical 2-phase-type loop, not credible periodization.

## 29. Product Intelligence vs Technical Defaults

Checked directly: no current UI displays `ProgramCandidate` lists with
personalization-implying copy (`grep` for "recommended for you"/"best for
you" across `TrainingOS/UI/` → zero matches) — and Family D/E (Strength
Program 1/2) aren't wired into any athlete-facing selection UI yet at all
(confirmed FOLLOW-UP from the Strength Source Content V1 checkpoint), so
the specific hypothetical the directive warns about (alphabetical
tie-break disguised as individualized recommendation) **does not currently
exist as a live defect** — there's no surface where an athlete would see
Program 1 vs. 2 presented at all yet. Flagged as a preventive note for
whoever wires this content into UI later (FOLLOW-UP), not a current bug.

## 30. Historical StrategicPhaseTransition Test Investigation

`StrategicPhaseTransitionUITests.testTransitionWithNoCalibrationRequiredSystemMaterializesSessionsImmediately`'s
own doc comment (lines 393-433) explicitly documents that
`StrategicTransitionViewModel.startTransition` calls `TransitionPhaseUseCase
.transition` with a **real, freshly-read `Date()`** at call time — correct
production behavior for a live, user-initiated action, not a bug. The
test's own mitigation (anchoring its `asOf` to `Calendar.current
.startOfDay(for: Date())` rather than a fixed historical date) was already
added specifically because a distant historical `asOf` previously caused
Functional Fitness's day-window resolution to see zero eligible session
days by the time the real transition ran.

**Classification: DATE/TIME FLAKINESS** — a genuine, disclosed, intentional
real-clock dependency in both the test and the production path it
exercises, not a REAL PRODUCT BUG (a live "start transition now" action
correctly uses the real current moment), not resolved by any prior change
(the underlying real-clock read is deliberate and unchanged), not a TEST
BUG (it isn't asserting the wrong thing). The full suite was independently
re-run twice this session (1582/0, then 1592/0) and this test passed both
times — consistent with the existing mitigation reducing, but not
eliminating, a residual midnight/day-boundary edge case. Not fixed, per
instruction — diagnosis only.

## 31. Findings

**F1 — BLOCKER**
ID: RUN-PACE-1
AREA: Running Execution UX / Calibration
SCENARIO: Any Running V1 session prescribed as a percent-of-threshold target (the only kind `RunningProgramGenerator` produces).
CURRENT: `IntensityPresentation.swift:18` renders `.percentOfReference(range, metric:)` as literal `"70-80% Threshold Pace"` text; `ThresholdPaceEngine`/`RequiredRunningCalibrationUseCase` have zero production callers (confirmed twice, independently, via direct `grep`); no screen anywhere collects a Threshold Pace value from the athlete.
EXPECTED: An actual runnable pace (e.g. "4:10-4:20/km"), resolved from the athlete's own calibrated Threshold Pace.
EVIDENCE: `RunningProgramGenerator.swift:226`; `IntensityPresentation.swift:12,18`; `grep -rn "ThresholdPaceEngine\." TrainingOS --include="*.swift" | grep -v Tests` → 0 results (orchestrator-verified); `grep -rln "thresholdPace\|ThresholdPace" TrainingOS/UI TrainingOS/Application/ViewModels` → only `IntensityPresentation.swift`.
USER IMPACT: Any athlete on a Running-containing mix cannot determine what pace to run — the single most common Running prescription shape.
CLASSIFICATION: BLOCKER
MINIMUM FIX: (a) a Threshold Pace calibration entry step gated by `RequiredRunningCalibrationUseCase`, mirroring the existing `SourceRMCalibrationViewModel` pattern; (b) resolve `.percentOfReference(_, .thresholdPace)` through `ThresholdPaceEngine` at display (or materialization) time.
DEPENDENCIES: None new — every mechanism needed already exists and is unit-tested in isolation; this is a wiring gap.

**F2 — BLOCKER**
ID: LTP-1
AREA: Long-Term Planning Intelligence
SCENARIO: Any goal (Get Stronger, Build Muscle, …) with a target date but no dated objective/milestone — the common case.
CURRENT: `fillForwardPhases` (`LongTermPlanner.swift:463-527`) mechanically alternates exactly 2 `PhaseType` values forever (`useMaintenance = consecutivePrimary >= 2`) — the goal's own primary type and generic `.maintenance` — never inserting a different adaptation emphasis, despite the domain model already supporting it.
EXPECTED: Genuine variation in phase purpose over a long horizon — credible periodization, not a 2-label loop.
EVIDENCE: `LongTermPlanner.swift:463-527` (orchestrator-verified directly); `PhaseDurationKind.swift:58-66` (real constants used to compute the exact 52-week sequences in §5-6).
USER IMPACT: A 12-month Get Stronger or Build Muscle athlete's Plan shows a mechanically repeating year — directly falsifies the directive's own "is this more than a short-program launcher" test (J9).
CLASSIFICATION: BLOCKER
MINIMUM FIX: Give `fillForwardPhases` a small, deterministic, TrainingOS-owned periodization table per goal type (e.g. for `.strength`: `[.strength, .strength, .muscleGain, .maintenance]` repeating, instead of `[.strength, .strength, .maintenance]`) — reusing `PhaseType`/`AdaptationObjective`/existing candidate-mix machinery unchanged. A scoped implementation task, not a redesign.
DEPENDENCIES: None blocking — everything this needs already exists.

**F3 — FOLLOW-UP**
ID: LTP-2
AREA: Long-Term Planning Intelligence
SCENARIO: A goal with no target date at all.
CURRENT: A single, permanently open-ended phase, forever (`LongTermPlanner.swift:123-127`) — a deliberate, disclosed, honest choice (never fabricate a horizon).
EXPECTED: N/A — defensible as-is; flagged for backlog awareness only.
EVIDENCE: `LongTermPlanner.swift:123-127`.
USER IMPACT: An athlete who never sets a target date never sees any planner-initiated phase transition.
CLASSIFICATION: FOLLOW-UP
MINIMUM FIX: N/A now — a possible later default-rotation-cadence decision.
DEPENDENCIES: Same mechanism as F2 if pursued together.

**F4 — FOLLOW-UP**
ID: RUN-OVERRIDE-1
AREA: Session Execution
SCENARIO: In-session pace-increase request.
CURRENT: `RunningExecutionOverrideEngine.evaluateIntensityOverride` has zero production callers.
EXPECTED: Wired into the Running execution view once F1 lands.
EVIDENCE: `grep -rn "RunningExecutionOverrideEngine\." TrainingOS --include="*.swift"` → 0 results outside its own file.
USER IMPACT: None additional today — moot until F1 is fixed (no resolved pace exists to override yet).
CLASSIFICATION: FOLLOW-UP (subsumed by F1)
MINIMUM FIX: Wire in alongside F1's fix.
DEPENDENCIES: F1.

**F5 — FOLLOW-UP**
ID: STRENGTH-UX-1
AREA: Same-Week Result Dependencies / Today
SCENARIO: Family E Friday-Legs2 before Tuesday completes.
CURRENT: Blank target line, no explanatory text, when pending — nothing fabricated, just unexplained.
EXPECTED: A short "resolves after Tuesday's session" message.
EVIDENCE: `StrengthSetPresentation.swift:26-27`.
USER IMPACT: Minor confusion, not incorrect data.
CLASSIFICATION: FOLLOW-UP
MINIMUM FIX: Thread the reason code through to the view for an explicit pending message.
DEPENDENCIES: None.

**F6 — FOLLOW-UP**
ID: AVAIL-1
AREA: Availability
SCENARIO: `longerDayWeekdays` field.
CURRENT: Declared, defaults empty, zero production consumers, zero production UI setters.
EXPECTED: A real consumer, or removal.
EVIDENCE: `grep -rn "longerDayWeekdays" TrainingOS/ --include="*.swift"` (excl. Tests) → only its own declaration/initializer.
USER IMPACT: None today (inert, not misleading — nothing collects it either).
CLASSIFICATION: FOLLOW-UP
MINIMUM FIX: N/A now.
DEPENDENCIES: None.

**F7 — FOLLOW-UP**
ID: PROD-INTEL-1
AREA: Product Intelligence vs Technical Defaults
SCENARIO: Future UI exposing Strength Program 1 vs 2.
CURRENT: `closestByDayCount`'s alphabetical tie-break is a deterministic technical default, not currently disguised as personalization (no UI surfaces it yet at all).
EXPECTED: Any future UI must not imply individualized physiological matching for what is alphabetical sorting.
EVIDENCE: `grep` for personalization-implying copy across `TrainingOS/UI/` → 0 matches; `StrengthSourceContentLibrary` has 0 UI references.
USER IMPACT: None today.
CLASSIFICATION: FOLLOW-UP (preventive note for future implementers)
MINIMUM FIX: N/A now.
DEPENDENCIES: `STRENGTH_SOURCE_CONTENT_V1.md`'s own existing FOLLOW-UP to wire this content into a UI surface.

**F8 — IMPROVEMENT**
ID: ONB-1
AREA: Onboarding
SCENARIO: `OnboardingViewModel.Step.preferences` naming.
CURRENT: Collects availability, named "preferences."
EXPECTED: N/A — cosmetic.
EVIDENCE: `OnboardingViewModel.swift:34-97`.
USER IMPACT: None (internal code only).
CLASSIFICATION: IMPROVEMENT
MINIMUM FIX: Rename if ever touched for other reasons.
DEPENDENCIES: None.

**F9 — Diagnosis only, no classification needed**
ID: PHASETEST-1
AREA: Historical StrategicPhaseTransition test
See §30. DATE/TIME FLAKINESS. Not fixed, per instruction.

**F10 — Not a defect, disclosed evidence-coverage note**
ID: DESIGN-COVERAGE-1
AREA: Design Fidelity
Only one live screenshot obtained this pass (tooling limitation, not a
found defect); rest of the app's design-system consistency was confirmed
via code-level `Theme` usage, not full visual sweep. No BROKEN surface was
found anywhere examined. Recommend a dedicated visual QA pass with proper
simulator automation as FOLLOW-UP.

## 32. Immediate Vertical Completion Plan

Only BLOCKER/CHECKPOINT BUG findings ordered into the smallest sequence
that gets J1-J9 vertically coherent:

**V1 — Fix Running pace resolution and calibration collection**
- Add a Threshold Pace calibration entry step (gated by
  `RequiredRunningCalibrationUseCase`, reusing the existing
  `SourceRMCalibrationViewModel` UI pattern).
- Resolve `.percentOfReference(_, .thresholdPace)` through
  `ThresholdPaceEngine` at prescription-display (or materialization) time.
- Wire `RunningExecutionOverrideEngine` into the Running execution view
  (F4, bundled in since it depends on the same resolved-pace plumbing).
- → Verify J3, J5, and Running's own row in §12 all pass.

**V2 — Give the long-term planner real periodization variety**
- Add a small, deterministic, per-goal-type periodization table to
  `fillForwardPhases` (e.g. `.strength` → `[.strength, .strength,
  .muscleGain, .maintenance]` repeating) instead of the current
  2-type mechanical loop.
- → Verify J9 (and re-check J1/J2's own long-horizon Plan presentation
  looks like genuine periodization, not just structurally valid phases).

No other BLOCKER/CHECKPOINT BUG findings exist in this audit — V1 and V2
are the complete finite list.

## 33. Follow-Up / V2 Backlog

- F3 (LTP-2): no-target-date plans never self-transition.
- F5 (STRENGTH-UX-1): pending-state messaging polish.
- F6 (AVAIL-1): `longerDayWeekdays` inert field.
- F7 (PROD-INTEL-1): preventive note for future Program 1/2 UI copy.
- F8 (ONB-1): onboarding step naming.
- F10 (DESIGN-COVERAGE-1): full visual QA sweep with proper simulator tooling.
- Family C's own "1/2 Monday's" source-fidelity debt (already logged,
  reaffirmed, still not blocking any current journey).
- Every already-existing V2 item logged in prior checkpoints (Powerlifting
  preference/competition workflow, RM self-calibration guidance, richer
  Progress analytics, etc.) — unchanged, not re-litigated here.

## 34. Final Verdict

FIRST OPEN → FIRST REAL WORKOUT: PASS
GOAL → PROGRAMMING SEMANTICS: PASS
GET STRONGER → GENERAL STRENGTH: PASS
BUILD MUSCLE → HYPERTROPHY: PASS
LONG-TERM MULTI-PHASE STRATEGY: PASS
LONG-TERM PLANNER INTELLIGENCE: FAIL
DATED OBJECTIVE STRATEGY: PASS
RECOMMENDATION → ATHLETE APPROVAL: PASS
EXACT SELECTED TRAINING MIX PRESERVED: PASS
PROGRAM RESOLUTION: PASS
CALIBRATION JOURNEY: FAIL
R0 MID-WEEK START: PASS
TODAY EXECUTION: PASS
RUNNING EXECUTION UX: FAIL
FUNCTIONAL FITNESS EXECUTION: PASS
SAME-WEEK RESULT DEPENDENCY: PASS
CONCURRENT PROGRAMMING JOURNEY: PASS
MISSED SESSION JOURNEY: PASS
TACTICAL WINDOW ROLL: PASS
PHASE TRANSITION: PASS
PLAN = DIRECTION: PASS
PROGRESS = EVIDENCE: PASS
TRAINING ENVIRONMENT JOURNEY: PASS
BUILD MY OWN MIX: PASS
DESIGN FIDELITY: PASS
J1 BUILD MUSCLE: PASS
J2 GET STRONGER: PASS
J3 RUNNING + BUILD MUSCLE: FAIL
J4 FUNCTIONAL FITNESS: PASS
J5 HYBRID / CONCURRENT: FAIL
J6 MID-WEEK START: PASS
J7 MISSED SESSION: PASS
J8 CONSTRAINED ENVIRONMENT: PASS
J9 LONG-TERM STRENGTH: FAIL
BLOCKERS: 2
CHECKPOINT BUGS: 0
FOLLOW-UPS: 7
IMPROVEMENTS: 1
V2: 0
FINITE VERTICAL COMPLETION PLAN: YES
READY TO LEAVE BROAD-AUDIT MODE: YES
