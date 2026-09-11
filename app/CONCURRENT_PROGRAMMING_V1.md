# Concurrent Programming V1 — Running Reachability + Structural Orchestration

Implementation checkpoint closing the gaps found by
`CONCURRENT_PROGRAMMING_V1_READINESS.md`. Scope: (1) make the real,
closed Running 5K/2-Day V1 reachable from `TrainingMix`/`buildCustomMix`
with its exact frequency preserved, never approximated; (2) add two
deterministic, structural RP-derived Running pairing rules to the
existing, accepted `ConcurrentScheduler`; (3) prove both work identically
in the first tactical week and in rolled-forward weeks; (4) characterize
and lock the missed-session invariant; (5) prove all of the above with
real, production-path tests using source-valid frequencies only. No
modality engine's source content, frequencies, or recommendation policy
changed.

## 1. Exact TrainingMix Semantics

`TrainingMixComponent.frequency` is `SessionFrequency { target, minimum,
maximum }` (`TrainingMixTypes.swift:50`). `target` means literal calendar
sessions/week — confirmed by every materializer/generator consumer
(`StrengthMaterializer`, `RunningProgramGenerator`'s day-count matching,
`ConcurrentScheduler.buildPhases`'s `component.frequency.minimum ??
component.frequency.target` required-count derivation). There is no
separate "intensity" or "volume" meaning layered onto it. This resolution
was load-bearing: every fix below depends on `frequency.target` meaning
exactly "N real Sessions this component must produce per week."

## 2. Real Running Reachability

Two distinct, separately-diagnosed defects, both fixed:

**(a) Identity.** `LongTermPlanner.underlyingSystem(for: .running)`
previously returned `.steadyState` (generic Zone 2), not the real,
closed, source-backed `ProgrammingSystemKind.running` (5K/2-Day V1,
built in the earlier "Running R3" checkpoint). Fixed in
`LongTermPlanner.swift` — `.running` now maps to `.running`. `.cycling`
is unchanged (still `.steadyState`; Cycling has no real closed system of
its own, out of scope here).

**(b) Candidate construction.** Even after (a), `LongTermPlanner
.proposeProgram`'s `.running` branch had a hardcoded `rawCandidates = []`
— a deliberate placeholder from the Running R3 checkpoint, whose own
doc comment anticipated "RunningProgramGenerator/RunningBuiltInLibrary
are invoked directly by whatever future flow starts a Running program."
This checkpoint IS that flow. Added `runningParameterCandidates
(component:)`, mirroring the existing `hypertrophyParameterCandidates`/
`functionalFitnessParameterCandidates` pattern exactly: filters
`RunningBuiltInLibrary.all` (one entry: 5K, 2 days/week) to the entry
whose `daysPerWeek` equals the component's own `frequency.target`, never
approximating to the nearest available entry.

Both fixes were required together — (a) alone still produced zero
Running Sessions (discovered empirically via a failing test, not
assumed), because `proposeProgram` is the actual candidate-construction
step `StartPhaseUseCase.start()` calls per component.

Proven end-to-end (`ConcurrentProgrammingGoldenScenarioTests.testG1...`,
`testG3...`, `testG7...`, `testG9...`): `buildCustomMix` → real
`.running` `TrainingMixComponent` → `StartPhaseUseCase.start` →
`LongTermPlanner.proposeProgram` → real `RunningProgramGenerator
.generate` → real `RunningProgramMaterializer.materializeAllWeeks` →
real, source-backed `Session`s (13-relative-week structure, real
`SessionRole`s) → `ConcurrentScheduler`. No mock/steadyState substitution
at any point in this chain.

## 3. Running V1 Frequency Boundary

`ProgramCapabilityRegistry.supportedFrequencies(for: .running)` already
correctly derives `[2]` from `RunningBuiltInLibrary.all` — no new
capability-gate code was needed for frequency validation itself, exactly
as anticipated. `buildCustomMix` already called this gate before this
checkpoint; the only defect was that the STYLE resolved to the wrong
SYSTEM (§2a), which meant the frequency gate was checking `.steadyState`
(unrestricted) instead of `.running` (restricted to 2). Fixing (2a) alone
makes the EXISTING gate correctly reject 1, 3, 4, 5 — proven in
`ConcurrentProgrammingV1Tests.testBuildCustomMixAcceptsExactlyTwoRunningAndRejectsEveryOtherFrequency`
and `testProposeProgramNeverProducesARunningCandidateForAnUnsupportedFrequency`.

## 4. Scheduler Architecture Reused, Not Replaced

`ConcurrentScheduler`'s two-phase (required-minimum-first, then
beyond-minimum), 8-factor deterministic placement algorithm is untouched
in shape. Both new rules are purely additive:

- Rule 1 (hard-Running recovery protection) adds one new field,
  `runningRecoveryViolated`, to the existing lexicographic
  `PlacementScore` comparator (`isDouble, interferenceViolated,
  runningRecoveryViolated, notPreferredDay, partnerStressOrdinal,
  dayOffset`) — a pure re-ranking signal among already hard-valid days,
  never a new hard constraint.
- Rule 2 (same-day Running-first ordering) is a new, isolated
  post-processing pass (`applyRunningFirstSameDayOrdering`) that runs
  once after all placement is finished, touching only
  `SessionPlacement.sortIndexInDay` — never which day anything lands on,
  never cross-day feasibility.

No existing scoring factor, hard-check, or conflict-building function was
modified.

## 5. Cross-Component Stress Signals Reused

Both new rules reuse the existing, already-populated
`TrainingStressProfile`/`SessionStressComposer.compose(_:)` machinery —
already wired for Hypertrophy/Powerlifting (`StrengthTrainingStressMapper`),
Running (`SteadyStateTrainingStressMapper`/`IntervalTrainingStressMapper`),
and Functional Fitness (`FunctionalFitnessStressProfileMapper`). No new
stress vocabulary, no new mapper. `LoadLevel.ordinal` (`.none`=0 ...
`.high`=3) is reused for the `>= .high` threshold checks both rules use.

## 6. Hard-Running Recovery Preference (Rule 1)

**What it does:** a hard/quality Running session (`RunningOrchestrationContract
.qualityClassification(for: role) == .quality` — reused directly from the
Running R2 checkpoint, never a duplicate `RunningIntensity` vocabulary)
is penalized in `PlacementScore` on any day whose immediately PRECEDING
day already holds a sibling session with `lowerBodyLoad >= .high` or
`recoveryDemand >= .high` (`hasHighPrecedingStress`, excluding the
Running component's own other sessions). This is DIRECTIONAL (only
checks the day before, unlike the generic, symmetric
`InterferenceAvoidanceRule`) and SOFT — it only re-ranks among
`hardValidOffsets`; it never removes a day from consideration, so it can
never make an otherwise-valid exact mix infeasible.

**Why not just the generic interference rule:** `InterferenceAvoidanceRule
.conservativeDefault` (`lowerBodyLoad >= .high`, `impactLoading >= .high`,
both symmetric/bidirectional) already produces separation in SOME cases,
but only when both sessions independently trip the same threshold in
both directions equally, and it has no concept of "which specific pairing
(hard Running preceded by high lower-body stress) matters structurally."
`ConcurrentProgrammingV1Tests.testHardRunningPrefersNonAdjacentDayAfterHighLowerBodyStress`
was verified — by temporarily disabling Rule 1's contribution to
`PlacementScore` and re-running — to depend on the new rule specifically:
with the rule disabled, the test fails (adjacency occurs); with it
enabled, the test passes. This proves the separation happens BECAUSE the
new rule exists, not accidentally from pre-existing scoring weights.

**Never overrides an unavoidable exact mix:**
`testHardRunningRuleNeverForcesInfeasibilityWhenNoAlternativeExists`
proves a 2-day window with only one possible day per session still
places both sessions (`.feasible`, count == 2) even though adjacency is
unavoidable.

## 7. Same-Day Running Ordering (Rule 2)

**What it does:** `applyRunningFirstSameDayOrdering` reorders same-day
placements (via `sortIndexInDay` only) so Running precedes: (a) any
Hypertrophy or Powerlifting session unconditionally, and (b) a Functional
Fitness session ONLY when that specific session's own real, composed
`TrainingStressProfile` reads `.high` on `lowerBodyLoad`, `upperBodyLoad`,
or `systemicDemand` — never a blanket "all FF is strength" assumption.
Every other same-day pairing (Running + a non-strength-classified FF
session, Running + Running on a double) keeps the existing deterministic
tie-break (alphabetical component label, then position) untouched.

**Verification of genuineness:** by temporarily disabling the
`applyRunningFirstSameDayOrdering` call and re-running
`testRunningPrecedesHypertrophyOnADoubleDay`,
`testRunningPrecedesPowerliftingOnADoubleDay`, and
`testRunningPrecedesAStrengthClassifiedFunctionalFitnessSession`, all
three fail (existing tie-break puts Running second) — confirming the
rule, not incidental ordering, produces the required precedence.
`testRunningDoesNotAutomaticallyPrecedeANonStrengthFunctionalFitnessSession`
proves the FF-non-strength case correctly falls through to the existing,
unmodified tie-break.

## 8. Week-1 Behavior (No Cross-Modality Gap for These Rules)

The readiness audit's Week-1 concern was specific to Stage CP.2's
FF-only intended→final stimulus repair (`protectedSiblingStressProfilesThisWeek`,
built only from `rollForward`'s producer pass, empty at Week 1). Both new
Running rules read only `stressProfile`/`component.programmingSystem`/
`session.role` — fields already fully populated on every `Session` at
MATERIALIZATION time by `SessionStressComposer.compose`, regardless of
whether that materialization happened via `StartPhaseUseCase
.materializeFirstWindow` (Week 1) or `RollTacticalWindowUseCase
.rollForward` (later weeks). `ConcurrentScheduler.schedule` itself takes
no week index at all — it is a pure function of `([ScheduledProgramInput],
SchedulingConstraints)`. `testSchedulerRulesAreIdenticalRegardlessOfWhichMaterializationCallProducedTheInputs`
proves identical inputs produce byte-identical placement/feasibility
results regardless of which call site is imagined to have produced them.
**No fix was required** — this is a real, structural difference from
CP.2's FF-specific gap, not an oversight; both new rules were correctly
scoped to information available at any materialization time.

## 9. Doubles

Both rules interact with existing double-session placement (`isDouble` in
`PlacementScore`, ranked ABOVE `runningRecoveryViolated`) unchanged — a
double is still chosen first per the existing precedence; the new
recovery-preference field only breaks ties AMONG already-decided
double/non-double candidates of equal standing on every field ranked
above it. `G4B` (`ConcurrentProgrammingGoldenScenarioTests`) proves a
real doubles-enabled fewer-days scenario preserves the exact 3H+1FF+2Run
mix via deterministic double placement.

## 10. Missed-Session Invariant (Characterized, Then Locked — No Code Change)

**Characterization findings** (from reading `ProgramWeekGrouping
.nextWeekIndex` and `RollTacticalWindowUseCase.rollForward`/
`materializeFirstWindow` directly, confirmed by `MissedSessionInvariantTests`):

1. Is the missed session automatically moved? **No.** `rollForward` never
   re-touches an already-materialized/placed `Session`; a `.missed`
   Session keeps its original `.day`/date and `.status` forever.
2. Are later sessions moved? **No.** Nothing in `nextWeekIndex`/
   `rollForward` reads `Session.status` at all — "which week is next" is
   determined purely by whether real Sessions exist for a date bucket,
   never by their completion state.
3. Is the remaining concurrent week recomputed? **No** — no recomputation
   mechanism exists; each `rollForward` call only ever materializes the
   NEXT not-yet-materialized week.
4. Does the next tactical window change? **No** — `nextWeekIndex` is
   unaffected by missed/completed/skipped status.
5. Can a missed session create new cross-component recovery conflicts?
   **No** — Stage CP.2's producer/consumer stress signal
   (`protectedSiblingStressProfilesThisWeek`) is built ONLY from
   sessions materialized in the SAME `rollForward` call (the current
   week being rolled), never from a prior week's sessions regardless of
   their status.
6. Does any component frequency silently change? **No** — `frequency`
   lives on `TrainingMixComponent`, never touched by session status.
7. Does source-backed session order change? **No** — the next real week
   materializes with the same content/order it always would.

**Product rule:** current, unmodified production behavior ALREADY
satisfies the V1 invariant ("a missed session must not silently rewrite
the athlete's plan"). No code change was made — `MissedSessionInvariantTests.swift`
locks this behavior with 4 real, production-path tests (missed
Hypertrophy, missed Functional Fitness, missed hard Running, and a
direct proof that a missed session never alters a same-week sibling's
cross-component stress reasoning).

## 11. Mid-Week Start (Unchanged, Reproven With Running)

The closed R0 fix (`SchedulingConstraints.preOccupiedDates`; a brand-new
plan's first source-backed tactical week may only ever be a genuine full
calendar week) is untouched. `G9` proves the identical guarantee now
holds for a mix that includes real Running: a Friday acceptance produces
ZERO source-backed Sessions (Hypertrophy or Running) before the
following Monday, and Running's real full cadence begins Monday onward
exactly like every other component.

## 12. Exact-Mix Guarantees — Golden Scenarios (G1-G10)

All source-valid (Running always 2; Powerlifting always 4 or 5; every
frequency checked against the real `ProgramCapabilityRegistry`).

- **G1** (3H+1FF+2Run, 6 days) — `ConcurrentProgrammingGoldenScenarioTests
  .testG1...`: exactly 3 Hypertrophy, 1 FF, 2 real Running sessions in
  week 0; Running resolves to `.running` (never `.steadyState`); the real
  13-relative-week `ProgramDefinition`; real materialized Sessions
  preserve the source template's own session order.
- **G2** (3H+2FF+2Run, 7 days — corrected from the readiness audit's
  invalid "2H+2FF+2Run": Hypertrophy has no 2-day curated configuration)
  — `testG2...`: exact session counts 3/2/(2 in week 0).
- **G3** (4H+2Run, 6 days) — `testG3...`: exact counts 4 and 2.
- **G4A** (3H+1FF+2Run, 4 usable days/week, doubles disabled) —
  `testG4A...`: an explicit `ScheduleAcceptanceError.infeasible` is
  thrown once Hypertrophy's deferred 3 sessions cannot fit the days left
  free by its already-scheduled siblings within a tight one-week window;
  nothing is silently dropped (Hypertrophy's real Sessions are
  materialized with content, just never `schedulerVersion`-stamped/
  accepted); every component's `frequency.target` is untouched.
- **G4B** (same, doubles enabled) — `testG4B...`: the exact 3/1/2 mix is
  fully preserved via at least one real, deterministic double-session
  day.
- **G5/G6** (hard Running vs. lower-body-heavy Hypertrophy/Functional
  Fitness) — proven at the `ConcurrentScheduler` unit level in
  `ConcurrentProgrammingV1Tests` (`testHardRunningPrefersNonAdjacentDayAfterHighLowerBodyStress`
  covers the Hypertrophy case with an explicit disable/re-enable
  falsification proof per §6; `testRunningPrecedesAStrengthClassifiedFunctionalFitnessSession`
  and its non-strength counterpart cover the FF case for Rule 2's own
  gating condition). Chosen at the unit level deliberately, since it lets
  both the "protected" and "unavoidable adjacency" branches be
  constructed precisely and cheaply, and lets the falsification check
  (disable the rule, confirm the test fails) run directly against the
  exact mechanism under test.
- **G7** (Powerlifting 4-day family + Running 2, 6 days) —
  `testG7...`: the real 4-day Powerlifting family (never an invented
  2-day family); Running's exact frequency preserved; an empirical check
  (not merely an assumption) that no hard Running session in the real
  materialized week landed immediately after a real high-lowerBodyLoad
  Powerlifting day.
- **G8** (Week 1 vs. rolled-forward parity) —
  `testSchedulerRulesAreIdenticalRegardlessOfWhichMaterializationCallProducedTheInputs`
  (§8).
- **G9** (mid-week start, Running-inclusive) — §11.
- **G10** (missed session) — §10, `MissedSessionInvariantTests`.

## 13. Typed Infeasibility / Compromise Behavior

Unchanged mechanism: `ScheduleFeasibility.infeasible` (hard constraints
unsatisfiable — `AcceptScheduleProposalUseCase.accept` throws
`ScheduleAcceptanceError.infeasible` before writing anything, proven in
G4A) vs. `.feasibleWithSoftViolations` (every session placed, at least
one soft constraint — preferred day, generic interference — gave way,
surfaced via typed `ScheduleIssue`). Neither new Running rule emits its
own `ScheduleIssue`: Rule 1 is a pure ranking signal (never surfaced as a
distinct issue code — consistent with it being a preference, not a
violation worth its own typed disclosure at this checkpoint); Rule 2 only
reorders within a day, which has no existing "ordering compromise" issue
concept to begin with. Both were deliberately scoped this way per the
directive: soft preferences that never manufacture new infeasibility.

## 14. Training Environment Boundary

**SCHEDULER-LEVEL CROSS-ENVIRONMENT COORDINATION: FOLLOW-UP.** No central
scheduler environment work was done in this checkpoint. Existing
per-component materialization remains authoritative and fail-fast for
environment resolution; this is unchanged and is not classified as a
Concurrent V1 blocker, per the directive's own instruction.

## 15. V2 / Follow-Up Backlog

Explicitly NOT built in this checkpoint (carried over from the readiness
audit, unchanged unless noted):

- Post-scheduler negotiation/renegotiation on conflict.
- The remaining 3-4 RP concurrent-training pairing rules beyond the two
  built here (concentrating extra strength on hard/long run days,
  optional-work recovery adaptation, broader run/strength priority
  negotiation).
- Same-day cross-environment resolution beyond simple disclosure.
- AM/PM/time-of-day double-session representation; `longerDayWeekdays`
  actually being consumed by any rule.
- Adaptive/full missed-session recovery scheduling (explicitly rejected
  as V1 scope — §10's invariant is the intended, permanent V1 behavior,
  not a placeholder).
- HRV/sleep/subjective readiness/adaptive fatigue modeling.
- A `RunningRecoveryCompromise`-style typed `ScheduleIssue` for Rule 1,
  if product later decides the soft preference should be visibly
  disclosed when it cannot be honored (deliberately NOT added now — no
  such disclosure was requested, and inventing one would be scope
  creep beyond the directive).
- Scheduler-level cross-environment coordination (§14).
