# Concurrent Scheduler Model

Stage 3B architecture validation for combining outputs of multiple
`ProgrammingSystem`s (e.g. strength + aerobic, running + strength,
functional fitness + strength + aerobic) into one weekly schedule.
Proposed abstraction only — the brief is explicit that `ConcurrentScheduler`
must not be built in this pass. Source grounding is in
`PROGRAMMING_SOURCES.md` §5.

## 1. Responsibility boundary — composes, does not invent

Per Stage 3B §26, stated as a hard constraint, not a design preference:
**`ConcurrentScheduler` combines `ProgrammingSystem` outputs. It does not
itself invent training.**

```
protocol ConcurrentScheduler {
    func schedule(_ inputs: [ScheduledProgramInput], constraints: SchedulingConstraints) -> ScheduleResult
}

struct ScheduledProgramInput {
    let sessions: [Session]             // already fully produced by some ProgrammingSystem —
                                          // HypertrophyProgrammingSystem, AerobicBase/SteadyState/
                                          // Interval, or FunctionalFitnessProgrammingSystem
    let goalPriority: GoalPriority       // .primary | .secondary — see §2
    let trainingStressProfile: TrainingStressProfile   // see §2
}
```

The worked example from §26 of the brief, restated in this shape:
`HypertrophyProgrammingSystem` produces 5 strength `Session`s;
`SteadyStateProgrammingSystem` (Zone 2, per `ENDURANCE_PROGRAMMING_MODEL.md`
§2 — not a bespoke "AerobicBase" engine) produces 2 `Session`s;
`ConcurrentScheduler` places all 7 across the week's available `Day`s. The
scheduler never generates a `Session`'s internal content (blocks,
prescriptions) — it only decides **placement**, exactly as §26 specifies.
This keeps `ConcurrentScheduler` outside the boundary of every
`ProgrammingSystem`'s own responsibility, and outside `ProgramGenerator`'s
responsibility (`PROGRAM_GENERATOR_SPEC.md`) too — it operates strictly
*after* both have already produced complete `Session`s.

## 2. Scheduler inputs

Per Stage 3B §27, and directly informed by `PROGRAMMING_SOURCES.md` §5's
literature (modeled as **factors the scheduler weighs**, never as a fixed
rule — this is the architecture's direct answer to the brief's warning
against "cardio kills gains"-style universal laws):

```
struct SchedulingConstraints {
    let primaryPhaseGoal: TrainingGoal
    let secondaryGoal: TrainingGoal?
    let userTrainingDaysPerWeek: Int
    let timeAvailablePerDay: [Weekday: Duration]
    let allowsDoubleSessions: Bool
    let sessionDuration: [Session: Duration]              // estimated, from each Session's own blocks
}

struct TrainingStressProfile {
    let classification: TrainingStressClassification      // e.g. .highSystemic, .lowSystemic
    let modality: TrainingModality
    let lowerBodyLoad: LoadLevel                            // .none | .light | .moderate | .heavy —
                                                              // directly informed by Eddens 2018's
                                                              // lower-body-strength-specific finding,
                                                              // PROGRAMMING_SOURCES.md §5
    let systemicDemand: SystemicDemandLevel                 // reuses FunctionalFitnessProgrammingModel's
                                                              // Stimulus.systemicDemand shape (§1.1 there) —
                                                              // one shared vocabulary for "how much did
                                                              // this session cost the whole body," not a
                                                              // strength-only or endurance-only concept
    let intensity: IntensityLevel
    let recoveryRequirement: Duration?                      // informed by the (lower-confidence, per
                                                              // PROGRAMMING_SOURCES.md §5) same-day-
                                                              // stacking literature — modeled as a
                                                              // per-session hint the scheduler MAY use,
                                                              // never a hardcoded universal gap
}

enum GoalPriority { case primary, secondary }
```

`TrainingStressProfile` is deliberately the same shape whether the
originating `Session` came from `HypertrophyProgrammingSystem`,
`SteadyStateProgrammingSystem`, or `FunctionalFitnessProgrammingSystem` —
each system is responsible for stamping its own output with a
`TrainingStressProfile` (a small, mechanical mapping from what it already
knows about the session — e.g. a heavy squat day is `lowerBodyLoad: .heavy`,
a Zone 2 bike ride is `lowerBodyLoad: .light, systemicDemand: .low`), so
the scheduler consumes one uniform vocabulary regardless of modality,
without needing modality-specific scheduling logic.

## 3. Scheduler output

Per Stage 3B §28, explicit reason codes — **no opaque "AI optimized"
decision**, matching the same explainability invariant already locked for
`ProgressionEngine` (`CLAUDE.md` rule 4, "explainable reason codes"),
applied here to scheduling decisions instead of progression decisions:

```
struct ScheduleResult {
    let placements: [SessionPlacement]
}

struct SessionPlacement {
    let session: Session
    let day: Day
    let orderWithinDay: Int                    // supports same-day pairing —
                                                 // multiple Sessions can share a Day
    let reasonCodes: [SchedulingReasonCode]
}

enum SchedulingReasonCode {
    case doubleSessionSelected
    case lowIntensityPairing
    case interferenceAvoided
    case primaryGoalPriority
    case insufficientRecoveryWindow
    case userConstraintApplied
}
```

Every placement decision traces to at least one named reason code — the
four named explicitly in §28 (`DOUBLE_SESSION_SELECTED`,
`LOW_INTENSITY_PAIRING`, `INTERFERENCE_AVOIDED`, `PRIMARY_GOAL_PRIORITY`)
plus two this analysis found necessary while working through the three
proof cases below (`insufficientRecoveryWindow`, `userConstraintApplied`)
— the enum is open to more, per the same "every new reason code needs a
table-driven test" discipline already governing `ProgressionReasonCode`
(`CLAUDE.md` rule 4).

## 4. Hybrid proof case A — Muscle Gain primary, Aerobic Base secondary

**Input** (Stage 3B §29): `HypertrophyProgrammingSystem` 5-Day Hypertrophy
(primary) + `SteadyStateProgrammingSystem` 2×45min Zone 2 module
(secondary); 5 training days available; double sessions allowed.

**Schedule produced:** 5 strength `Session`s, one per available day
(`GoalPriority.primary`, `reasonCodes: [.primaryGoalPriority]`). The 2
Zone 2 sessions get paired same-day with 2 of the 5 strength sessions
(`allowsDoubleSessions: true` makes this legal), chosen preferentially on
days where the strength session's `TrainingStressProfile.lowerBodyLoad`
is `.light` or `.moderate` rather than `.heavy` — `reasonCodes:
[.doubleSessionSelected, .lowIntensityPairing]`. This is a direct,
structural application of `PROGRAMMING_SOURCES.md` §5's own finding
(same-session stacking is where interference is most consistently
observed) **without hardcoding a specific rule like "never pair with leg
day"** — the scheduler is choosing the *least-costly* available pairing
given whatever the week's actual `lowerBodyLoad` values are, not applying
a fixed exclusion list. **Proof succeeds:** a valid 5-day schedule with 7
total sessions is produced, with no invented training content — every
session's content came from one of the two `ProgrammingSystem`s.

## 5. Hybrid proof case B — Running primary, Strength secondary

**Input** (Stage 3B §30): Running Performance primary, 4 sessions/week;
Strength Maintenance secondary, 2 sessions/week; 5 days available.

**Purpose of this case:** prove the scheduler doesn't assume strength is
always primary. **Schedule produced:** the 4 `RunningProgrammingSystem`-
sourced sessions (via `IntervalProgrammingSystem`/`SteadyStateProgrammingSystem`,
per `ENDURANCE_PROGRAMMING_MODEL.md`) are placed with `GoalPriority.primary`
and get first claim on days/spacing (e.g. a hard Tempo/Threshold session
is never adjacent to another hard running session without a recovery day
between, an ordinary scheduling constraint independent of which goal is
primary). The 2 strength sessions are placed with `GoalPriority.secondary`
into the remaining capacity, with `reasonCodes: [.primaryGoalPriority]`
attached to the *running* placements (recording that running's placement
needs were satisfied first) and `reasonCodes: [.lowIntensityPairing]` or
plain placement (no conflict) on the strength sessions if they land on
non-adjacent days. **Proof succeeds, and confirms the architecture is
symmetric:** `SchedulingConstraints.primaryPhaseGoal`/`secondaryGoal` and
`GoalPriority` are goal-tagged, not system-tagged — nothing in
`ConcurrentScheduler`'s type signature or logic special-cases
`HypertrophyProgrammingSystem`/`PowerliftingProgrammingSystem` as "the
real training" with everything else as an add-on. The exact same
`schedule()` function handles both Case A and Case B by construction, not
by branching on which system produced which sessions.

## 6. Hybrid proof case C — Functional Fitness primary, Strength + Aerobic secondary

**Input** (Stage 3B §31): 3 Functional Fitness sessions (primary), 2
strength sessions, 1 aerobic session.

**Purpose of this case:** prove the scheduler can *distinguish* stress
types finely enough to be useful for future interference rules, not just
place sessions. Each Functional Fitness session's `TrainingStressProfile`
is derived from its own `Stimulus` (per
`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §1.1) — a heavy-loaded metcon
maps to `lowerBodyLoad: .heavy, systemicDemand: .high`; a
gymnastics-only, bodyweight metcon maps to `lowerBodyLoad: .light,
systemicDemand: .moderate`. The 2 strength sessions carry their own
profile from `HypertrophyProgrammingSystem`/`PowerliftingProgrammingSystem`
exactly as in Case A. The 1 aerobic session is `lowerBodyLoad: .light,
systemicDemand: .low`, per `ENDURANCE_PROGRAMMING_MODEL.md`. **Proof
succeeds:** the scheduler has enough information to avoid placing a
`lowerBodyLoad: .heavy` strength session immediately after a
`lowerBodyLoad: .heavy` metcon (`reasonCodes: [.interferenceAvoided]`),
and to freely pair the aerobic session with either (`reasonCodes:
[.doubleSessionSelected, .lowIntensityPairing]`) — **without the
scheduler needing any Functional-Fitness-specific code path.** It only
ever reads the uniform `TrainingStressProfile` vocabulary from §2,
regardless of which `ProgrammingSystem` produced the session.

## 7. What this document does not decide

- **The actual placement algorithm** (constraint solver, greedy heuristic,
  or something else) — explicitly deferred; this document validates the
  *input/output contract*, not the implementation, per the brief's
  explicit instruction not to build `ConcurrentScheduler` in this pass.
- **Specific numeric interference thresholds** (e.g. "how many hours of
  separation counts as `insufficientRecoveryWindow`") — per
  `PROGRAMMING_SOURCES.md` §5, the literature's own numeric claims here are
  the least-verified ones found in this research pass; encoding a specific
  number now would be exactly the "individual study finding as rigid
  universal law" the brief warned against.
- **Whether `SchedulingReasonCode` needs to be richer** than the six cases
  above — six is enough to prove the three required cases; more will
  surface once a real placement algorithm is designed.
