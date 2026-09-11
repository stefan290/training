# Concurrent Programming / TrainingMix Orchestration — V1 Readiness

Analysis only. No code changed, no architecture changes, no UI, no commit,
no push. Hypertrophy/Powerlifting/Running/Functional Fitness are closed and
untouched by this checkpoint.

## 1. Current Concurrent Architecture

A real, substantial cross-component scheduling system already exists and is
wired into production — this is NOT a stub or a design-doc-only concept.
`ConcurrentScheduler.schedule(_:constraints:)` (`TrainingOS/Engines/
ConcurrentScheduler.swift`, 617 lines) is a deterministic, two-phase
placement algorithm (guarantee each component's required minimum first,
then place any sessions beyond it) with a fully documented, fixed
conflict-resolution precedence (hard constraints → required-minimum urgency
→ primary-goal protection → component-priority ordinal → program order →
interference/recovery preference → preferred days → stable tie-break).
It is called via `SchedulingPipeline.propose` from both `StartPhaseUseCase
.start()`/`.materializeOnceCalibrationComplete()` (first window) and
`RollTacticalWindowUseCase.rollForward()` (subsequent weeks), and its output
(`ScheduleProposal`) is committed to real `Day`/`Session` state only via
`AcceptScheduleProposalUseCase.accept` — never mutates anything itself.

## 2. TrainingMix Exactness

`LongTermPlanner.buildCustomMix(selections:capacity:)` is the real,
production, non-ranked "Build My Own Mix" path (distinct from
`proposeTrainingMix`'s scored/ranked presets). It validates EVERY
non-zero selection's frequency against `ProgramCapabilityRegistry
.isFrequencySupported` BEFORE constructing anything, and rejects outright
(`.unsupportedFrequency`) rather than approximating — confirmed by direct
read, this is the same "never approximate" discipline already proven for
Hypertrophy/Powerlifting/Running this engagement.

**Critical finding:** `underlyingSystem(for style: TrainingStyle)` maps
`.running` (and `.cycling`) to `ProgrammingSystemKind.steadyState`, **not**
`.running`. The real, source-backed 5K/2-Day Running V1 (`RunningProgramGenerator`,
closed this session) is **not reachable through `buildCustomMix` at all** —
an athlete selecting "Running" in the real mix-builder gets a generic Zone-2
`.steadyState` component instead. This exactly matches and reconfirms the
`RUNNING_V1_ATHLETE_JOURNEY_GAP.md` finding from earlier this session (the
`.running` system is real and closed, but no athlete-facing selection path
reaches it). This is a pre-existing, disclosed gap, not newly introduced —
but it means every one of the user's own example mixes (A/B/C/D, all
containing "1 Running") currently resolves to `.steadyState`, not the real
Running V1 capability, when built via the one real explicit-selection path.

**RESOLVED in Concurrent Programming V1** (see `CONCURRENT_PROGRAMMING_V1.md`
§1-2): `TrainingStyle.running` now resolves to the real `.running` system
via `LongTermPlanner.underlyingSystem(for:)`, and `proposeProgram`'s
`.running` branch now returns the real `RunningBuiltInLibrary` candidate.
Also corrected here: those example mixes' "1 Running" was itself invalid
regardless of the routing bug — Running's real capability is exactly 2/week.

## 3. ProgramInstance Composition

Per component, `buildCustomMix` creates one `TrainingMixComponent`
(`programmingSystem`, `frequency`, `priority` — first selection `.primary`,
rest `.supporting`). `StartPhaseUseCase.start()` then creates one
`ProgramInstance` per component (via each system's own curated-config
resolution) and calls `RollTacticalWindowUseCase.materializeFirstWindow`
once per component, independently — there is no single "build the whole
week's Sessions in one pass" step; each component's own materializer runs
on its own, producing its own Sessions with "naive" dates, and only
afterward does `ConcurrentScheduler` re-place them onto real calendar days
together.

## 4. Scheduler Architecture

Real, two-phase, deterministic. `ScheduledProgramInput` bundles a component
with its already-materialized `Session`s; `SchedulingConstraints` bundles
`UserAvailability` + `SchedulingWindow` + `interferenceRules` +
`preOccupiedDates`. `ConcurrentScheduler.schedule` builds one single global
processing order across ALL components' sessions (never per-component in
isolation), assigns each a real day via hard-constraint filtering + a
lexicographic soft-score (avoid doubling → avoid interference → prefer
preferred day → prefer lightest double-partner → earliest day), and returns
a `ScheduleProposal` with typed `ScheduleIssue`s for every soft/hard
compromise. This directly answers most of the 14 scheduler questions below.

## 5. Existing Scheduling Rules

| Rule | Status |
|---|---|
| Spread sessions across available days | IMPLEMENTED (earliest-valid-day tie-break + origin-week floor) |
| Hard/easy alternation | NOT IMPLEMENTED (no session-role-aware alternation logic found) |
| Lower-body spacing | PARTIAL — generic `.lowerBodyLoad`/`.impactLoading` interference avoidance exists (`InterferenceAvoidanceRule.conservativeDefault`), not a dedicated "alternate lower-body days" rule |
| Same-day clustering avoidance | IMPLEMENTED (doubling is the LAST resort in the soft-score order) |
| Preference for recovered hard running | NOT IMPLEMENTED (no Running-specific signal reaches the scheduler — see §9) |
| Running before strength same day | NOT IMPLEMENTED (no same-day intra-day ordering rule beyond `sortIndexInDay`, which reflects placement order, not a "running first" policy) |
| Concentrate extra strength on hard/long run days | NOT IMPLEMENTED |
| Environment constraints | NOT enforced by the scheduler itself (see §11) |
| Preferred-day handling | IMPLEMENTED (`preferredDays`, `.preferredDayUsed`/`.preferenceCompromise` reason codes) |
| Tactical window rolling | IMPLEMENTED (`RollTacticalWindowUseCase.rollForward`, real week-by-week, Stage CP.2 producer/consumer pattern — see §6) |

## 6. Cross-Component Stress Metadata

**This is real and already wired, more completely than expected.**
`SessionStressComposer.compose(session)` derives a `TrainingStressProfile`
from a Session's blocks (worst-case per dimension, never averaged) and is
what `ConcurrentScheduler` itself reads for interference scoring. Separately,
`RollTacticalWindowUseCase.rollForward` implements a real two-pass
producer/consumer design (Stage CP.2): Hypertrophy/Powerlifting/Interval
materialize first each week and their real stress profiles become
`protectedSiblingStressProfilesThisWeek`; Functional Fitness (the one real
constraint-CONSUMING system today) reads that list and can shift its own
`intendedStimulus`→`finalStimulus` via `CrossModalityStimulusRepair`/
`FunctionalFitnessDecisionEngine`. **Disclosed, real limitation:** this
producer/consumer pass only runs from the first ROLLED-forward week onward
— Week 1 (`materializeFirstWindow`) has no cross-modality signal at all
(confirmed by the exact comment in `StartPhaseUseCase.swift`).

## 7. Hypertrophy Orchestration Readiness

**SUFFICIENT for V1, corrected from an initial hypothesis.** `StrengthTrainingStressMapper.map(prescriptions:)`
(new file confirmed this pass, called from `StrengthMaterializer.swift`)
produces a real `TrainingStressProfile` for every Hypertrophy `WorkoutBlock`
— `lowerBodyLoad`/`upperBodyLoad` are derived from whether the block's real
resolved exercises target `lowerBodyMuscleGroups`/`upperBodyMuscleGroups`
(a fixed `MuscleGroup` set), `overallIntensity`/`systemicDemand` from
resolved RIR + total set count. This is genuinely sufficient signal for a
scheduler to distinguish a lower-body-heavy Hypertrophy day from an
upper-body one.

## 8. Powerlifting Orchestration Readiness

**SUFFICIENT for V1** — identical mechanism to Hypertrophy (same
`StrengthMaterializer`/`StrengthTrainingStressMapper` for both families).
Heavy central lifts (Squat/Bench/Deadlift) correctly classify `.high`
intensity (RIR ≤1) driving `lowerBodyLoad`/`upperBodyLoad` per the real
resolved exercise's own muscle-group targets.

## 9. Running Orchestration Readiness

**PARTIAL — documented but not enforced.** `SteadyStateTrainingStressMapper`/
`IntervalTrainingStressMapper` populate real `TrainingStressProfile`s for
Running content (confirmed these exist and are the actual stress source for
`.steadyState`/`.interval` blocks). However, `RunningOrchestrationContract`
(built in R2 this session — quality/easy classification, the 4 RP
concurrent-guidance rules) is referenced in exactly ONE place in the entire
codebase: a doc-comment citation inside `RunningProgramGenerator.swift`.
**It is not read by `ConcurrentScheduler`, `TacticalWindowPolicy`, or any
real scheduling code.** None of the 5 RP pairing rules the user's message
lists (hard-running-recovered, avoid-after-hard-strength, running-first-
same-day, concentrate-extra-strength-on-hard-run-days, optional-work-only-
when-recovery-permits) are currently enforced anywhere. The generic
`InterferenceAvoidanceRule.conservativeDefault` (`.lowerBodyLoad`/
`.impactLoading` ≥ `.high`) is activity-agnostic and would coincidentally
catch SOME of these cases (e.g. a high-lowerBodyLoad hard run next to
heavy squats) but implements none of them as a deliberate rule.

## 10. Functional Fitness Orchestration Readiness

**SUFFICIENT for V1.** `FunctionalFitnessStressProfileMapper` (confirmed
existing, used elsewhere this session) populates real `TrainingStressProfile`s;
FF is additionally the only system with real, working CROSS-component
consumption today (§6) — already ahead of every other system in this
specific respect.

## 11. Training Environment Interaction

Environment compatibility is checked ONLY during each component's own
MATERIALIZATION (each materializer's own `TrainingEnvironmentCompatibilityRule`
check, confirmed this session for Running/FF/Hypertrophy/Powerlifting
individually) — `ConcurrentScheduler` itself has no environment awareness
at all; it only reasons about days/stress/availability. Two same-day
sessions CAN require different environments today (nothing prevents it;
nothing coordinates it either) — this is a real, disclosed gap: if two
components' sessions land on the same day requiring incompatible
environments, nothing in the scheduler notices. Environment incompatibility
during materialization FAILS the individual component's own materialization
(a typed error) — it is never silently substituted, but it also is not
scheduling-aware (a component can fail materialization entirely regardless
of what day it would have landed on). No central scheduling change is
needed for a narrow V1 as long as V1 doesn't require same-day
cross-environment reasoning — flagged as FOLLOW-UP, not BLOCKS V1.

## 12. Availability / Calendar Inputs

`UserAvailability` (`SchedulingTypes.swift`) is real and substantially
richer than a bare day-count:

| Field | Status |
|---|---|
| `trainingDaysPerWeek` | REAL AND CONSUMED (feasibility) |
| `availableWeekdays`/`unavailableWeekdays` | REAL AND CONSUMED (`isUsable`, hard constraint in `hardCheck`) |
| `minutesAvailablePerDay` | REAL AND CONSUMED (`insufficientTime` hard check against `minMinutesNeeded(for:)`) |
| `longerDayWeekdays` | REAL BUT NOT CONSUMED — declared, no read-site found in `ConcurrentScheduler` |
| `allowsDoubleSessions` | REAL AND CONSUMED (gates doubling alongside the component's own `allowsDoubleSessionPairing`) |
| `maxSessionsPerDay` | REAL AND CONSUMED (hard cap) |

## 13. Mid-Week Start Interaction

Already solved, and solved carefully (a real, documented past bug fix, not
a hypothetical). `materializeOnceCalibrationComplete`'s own comment
describes exactly the problem the user's message is asking about — an
earlier version tried one joint re-scheduling pass across all of a mix's
components and produced spurious `.infeasible` results; the shipped fix is
narrower: `SchedulingConstraints.preOccupiedDates` tells the scheduler which
real calendar days a SIBLING component's already-accepted sessions occupy,
without ever re-placing or re-evaluating those sessions. This generalizes
correctly to N components starting together — each `scheduleAndAccept` call
still runs one real `ConcurrentScheduler.schedule` pass per component-start
event, with siblings' real days treated as pre-occupied.

## 14. Missed Session Behavior

`SessionStatus` has real `.missed`/`.skipped`/`.abandoned` states (`Enums.swift`).
No evidence was found of any cross-component rescheduling trigger — a missed
session in one component does not appear to cause any other component's
schedule to be recomputed, and no later-session-sliding logic was found tied
to a missed status specifically (distinct from the deliberate, tested
mid-week-start/first-window mechanics in §13). This area needs a
narrower, dedicated follow-up investigation before being called SUFFICIENT
— classified PARTIAL/FOLLOW-UP rather than asserted as either fully working
or fully absent, given the time budget of this pass.

## 15. Same-Day Doubles

**Real, already implemented.** `allowsDoubleSessionPairing` (component-level)
+ `UserAvailability.allowsDoubleSessions` (athlete-level) — both must be true.
`sortIndexInDay` (real ordering within a day, set by `AcceptScheduleProposalUseCase`
from `SessionPlacement.sortIndexInDay`) represents sequence; no explicit
AM/PM concept exists (ordering is positional, not time-of-day). The
scheduler's own soft-score deliberately makes doubling the LAST resort
(`isDouble` is the first, most heavily weighted score field) and prefers
the lightest available stress partner (`partnerStressOrdinal`) when a
double is unavoidable — this is real, working stress-aware pairing.

## 16. Concurrent V1 Blockers (BLOCKS CONCURRENT V1)

1. **Running V1 is unreachable from the real mix-building path** (§2) —
   every example mix containing "Running" currently produces `.steadyState`,
   not the real 5K V1 capability. Any Concurrent V1 demo/test built on top
   of "Running" as one of its components is currently exercising the wrong
   system unless this is fixed first.
2. **No Running-specific concurrent guidance is enforced** (§9) — the 5
   RP pairing rules exist only as unconsumed metadata.
3. **No same-day cross-environment awareness** (§11) — two components could
   be scheduled the same day with incompatible environment requirements and
   nothing would notice until individual materialization failed.

## 17. Checkpoint Bugs

None found in the CLOSED engines or in `ConcurrentScheduler`/`RollTacticalWindowUseCase`
itself — everything read this pass behaved exactly as its own extensive
documentation claims, including a genuinely well-diagnosed historical bug
fix (§13) already shipped correctly.

## 18. Recommended Concurrent V1 Boundary

Narrower than the user's own example quality bar, because most of it is
ALREADY WORKING today: real deterministic scheduling, real cross-component
stress metadata (Hypertrophy/Powerlifting/Running/FF all populate
`TrainingStressProfile`), real doubles, real mid-week-start handling, and
real (if generic) interference avoidance already exist. The genuine V1 gap
is narrow: (a) make Running V1 reachable from `buildCustomMix`, (b) decide
whether any Running-specific pairing rule should be promoted from
documented-but-unused into a real, consumed `ConcurrentScheduler`/FF-style
rule, (c) resolve the same-day environment-collision gap explicitly (even
if the V1 answer is "not handled, disclosed"), (d) confirm/harden
missed-session behavior across components.

## 19. Exact Implementation Scope

1. Fix `LongTermPlanner.underlyingSystem(for:)`'s `.running` mapping (or add
   a new, explicit `TrainingStyle` distinguishing "Running (5K V1)" from
   generic steady-state cardio) so `buildCustomMix` can actually construct
   a real `.running` component — the single highest-leverage fix, since it
   currently silently substitutes a different system for every mix example
   in the user's own message.
2. Decide (product decision, not architecture) whether to promote 1-2 of
   the 5 documented Running pairing rules into `ConcurrentScheduler`'s real
   `interferenceRules`/scoring — smallest version: add a Running-specific
   `InterferenceAvoidanceRule` variant or reuse the existing generic one
   with Running's own `.systemicDemand`/`.lowerBodyLoad` already present.
3. Add an explicit same-day environment-compatibility check somewhere in
   the scheduling pipeline (even a post-hoc `ScheduleIssue` flag, not a
   redesign) — or explicitly document it as deferred, disclosed, not silent.
4. A focused pass confirming exact missed-session cross-component behavior
   (§14), since this pass could not fully resolve it.

## 20. Golden Scenario Test Plan

**CONCURRENT V1 CORRECTION (post-implementation):** every "1Run" example
below was itself semantically invalid — Running's real, closed capability
(`ProgramCapabilityRegistry.supportedFrequencies(for: .running)`, derived
from `RunningBuiltInLibrary.all`) supports EXACTLY 2 sessions/week, never
1. This section originally inherited that error uncorrected. The
implemented, source-valid scenarios (2 Running throughout, Powerlifting at
its real 4/5-day families, Hypertrophy never at an unsupported frequency
like 2) are specified and proven in `CONCURRENT_PROGRAMMING_V1.md` §12
(G1-G10) — that document is the authoritative scenario spec going forward;
the text below is left in place as a historical record of the pre-fix
readiness audit, not a corrected restatement.

- **G1** (3H+1FF+2Run, 6 days) — corrected from 1Run. Expected: real
  Hypertrophy/FF/Running sessions placed, no doubles, program order
  preserved per component; Running resolves to the real `.running` system,
  never `.steadyState` (§16.1's gap is now CLOSED, not merely flagged).
- **G2** (3H+2FF+2Run, 7 days) — corrected from 2H+2FF+1Run (2H is ALSO
  invalid: `HypertrophyBuiltInLibrary.all`'s curated day counts are
  exactly {3,4,5,6}, never 2). Expected — 7 sessions, no doubles required.
- **G3** (4H+2Run, 6 days) — corrected from 4H+1Run. Expected — session
  counts exactly 4 and 2. Forbidden: Hypertrophy's 4th session silently
  dropped for "balance."
- **G4** (3H+1FF+2Run, 4 days, doubles allowed vs. not) — corrected from
  1Run. With doubles disallowed, expect `.infeasible` (a real, typed
  `ScheduleAcceptanceError.infeasible`, thrown before anything is written)
  — never a silent frequency reduction. With doubles allowed, expect at
  least one real double-session day, exact mix preserved.
- **G5** (lower-body-heavy H near hard Running): expected — real
  `StrengthTrainingStressMapper`/Running stress profiles both populated;
  `InterferenceAvoidanceRule.conservativeDefault`'s `.lowerBodyLoad`
  threshold may or may not avoid adjacency (generic rule, not
  Running-aware) — this scenario's real purpose is to PROVE whether the
  generic rule alone is sufficient or whether §19 item 2 is required.
- **G6** (lower-body-heavy FF near hard Running): same mechanism as G5,
  via FF's own stress profile.
- **G7** (Powerlifting + Running conflict): must confirm whether
  Powerlifting's own frequency constraints (curated day counts only) even
  permit a valid mix before scheduling is reached at all — a capability
  rejection, not a scheduling one, if the requested Powerlifting frequency
  isn't one of the curated day counts.
- **G8** (environment-constrained week): expected — any component whose
  environment can't be satisfied fails its OWN materialization with a typed
  error (§11); the scheduler itself never silently reassigns environment.
- **G9** (mid-week plan acceptance): expected — `preOccupiedDates` correctly
  blocks sibling days (§13's already-shipped fix) — this is a regression
  check on existing behavior, not new design.
- **G10** (missed session inside a concurrent week): exact expected
  behavior is the open question §14/§19.4 must resolve before this
  scenario can be fully specified.

## 21. Explicit V2 Backlog

Post-scheduler negotiation/renegotiation on conflict (explicitly deferred
per `RollTacticalWindowUseCase`'s own CP.2 comment); richer Running-specific
scheduling rules beyond the generic interference set; same-day
cross-environment resolution beyond simple disclosure; AM/PM/time-of-day
double-session representation; `longerDayWeekdays` actually being consumed;
full missed-session cross-component recovery logic; HRV/sleep/subjective
readiness/adaptive fatigue modeling (explicitly out of V1 per the user's
own instruction).

## 22. Recommended Next Checkpoint

A narrow "Concurrent V1 Reachability + Running Fix" implementation
checkpoint: fix the `TrainingStyle.running` → `.steadyState` mapping gap
(§19.1) first (it invalidates every example mix in this very readiness
audit), then a small, explicit product decision on which (if any) Running
pairing rule graduates into real `ConcurrentScheduler` consumption (§19.2),
then the missed-session behavior confirmation (§19.4) — each individually
small, avoiding a broad scheduler rewrite, since the scheduler itself is
already real and largely correct.

---

CLOSED TRAINING ENGINES PRESERVED: YES
EXACT TRAININGMIX COMPOSITION UNDERSTOOD: YES
CURRENT SCHEDULER UNDERSTOOD: YES
CROSS-COMPONENT METADATA SUFFICIENT FOR V1: YES (for Hypertrophy/Powerlifting/Running/FF's own stress profiles — NO for Running-specific pairing-rule enforcement specifically, see §9/§16)
CONCURRENT V1 BLOCKERS IDENTIFIED: YES
READY FOR CONCURRENT V1 IMPLEMENTATION: YES (narrow scope per §19)
