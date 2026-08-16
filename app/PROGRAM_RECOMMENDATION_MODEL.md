# Program Recommendation Model

How `LongTermPlanner` recommends a concrete `ProgramDefinition`/generator
configuration for each `TrainingMixComponent`, how it rates a user's own
choice, and why it never touches a program's internal methodology to do
either.

## 1. `ProgramCandidate` — the recommendation unit

```swift
struct ProgramCandidate {
    var componentLabel: String              // which TrainingMixComponent this fills
    var programmingSystem: ProgrammingSystemKind
    var programDefinition: ProgramDefinition?  // nil when only a generator
                                                // configuration is being proposed,
                                                // not yet materialized — see §5
    var fitRating: GoalAlignmentRating      // REUSED, not reinvented — see §2
    var factors: [ProgramFitFactor]
    var reasonCodes: [PlannerReasonCode]    // PLAN_REVISION_MODEL.md §3
}

struct ProgramFitFactor {
    var kind: ProgramFitFactorKind
    var satisfied: Bool
    var note: String                        // display copy only — CLAUDE.md rule 16
                                             // applies here exactly as it does to
                                             // GoalAlignmentFactor
}
```

`LongTermPlanner.proposeProgram` (`LONG_TERM_PLANNER.md` §5) returns
`[ProgramCandidate]`, ranked by `fitRating` — never a single forced
choice. 2-3 meaningful candidates is the target density, matching
`ADHERENCE_AWARE_PLANNING.md` §5's "2-3 paths, not dozens" rule applied
one level down, from mixes to programs.

## 2. Compatibility rating — reusing `GoalAlignmentRating`, not a new vocabulary

§18 asks for "Excellent Fit / Good Fit / Acceptable / Poor Fit." Rather
than invent a second qualitative-rating enum next to Stage 4G's
`GoalAlignmentRating` (`.infeasible`/`.poor`/`.acceptable`/`.good`/
`.excellent`), this document reuses it directly — a UI is free to render
`.excellent` as "Excellent Fit" without the domain model carrying two
words for the same five-tier concept. This is the direct continuation of
§23/§25's own instruction not to reimplement alignment scoring, applied
to programs instead of mixes: same tiers, same "never a fabricated
percentage" discipline, same transparent-factors shape.

### 2a. `Infeasible` vs. `Poor Fit` — the exact boundary (Decision 4, LOCKED)

This distinction is locked and does not get revisited without an
explicit new decision:

**`Infeasible`** means the plan cannot be executed while satisfying
required hard constraints — a narrow, mechanical definition, identical in
spirit to `ScheduleFeasibility.infeasible`. Examples:

- 6 required sessions requested against 3 available days with doubles
  disallowed.
- A required session's duration exceeds every available time window and
  cannot be split.
- Two `Strict` programs' own constraints cannot simultaneously be
  satisfied (`PHASE_PLANNING_RULES.md` §8's structural-incompatibility
  case).
- A protected/required component's derived minimum frequency cannot
  physically fit the available days at all.
- A required, non-substitutable prescription depends on equipment/an
  activity type the user does not have access to.

**`Poor Fit`** means the plan *can* be executed but aligns poorly with
the user's goal, experience, preferences, or current performance
context. Examples: pure running programming selected during a
Muscle-Gain-primary phase; an advanced 6-day Powerlifting program
selected by a user with little relevant history; a Muscle Gain phase
mix whose actual hypertrophy stimulus is very low. **Poor Fit always
remains selectable** unless a *separately-defined* hard constraint (the
`Infeasible` list above) also applies — a poor thematic or experience
match is never, by itself, a reason to block a choice.

**Neither rating is ever a safety judgment.** `Infeasible`/`Poor Fit`
mean exactly what they say — scheduling impossibility and goal-fit
quality respectively — and nothing else. TrainingOS does not currently
implement, and this pass does not invent, any speculative training-
science risk threshold (e.g. "this program is too advanced to be safe
for this user"). If a validated safety/eligibility concept is added in a
future stage, it must be modeled as a **separate, distinct concept**,
never folded into `GoalAlignmentRating`/`ScheduleFeasibility` — see
CLAUDE.md rule 18.

## 3. `ProgramFitFactorKind` — the 9 factors §17 names

Each a plain boolean-satisfied + note, mirroring `GoalAlignmentFactor`'s
exact shape:

| Factor | Reads |
|---|---|
| `phaseGoalMatch` | Does this program's typical stimulus match the phase's primary/protected objective (§2 of `PHASE_PLANNING_RULES.md`)? |
| `availabilityMatch` | Does the program's day count fit `UserAvailability`/the goal's coarse availability fields? |
| `sessionDurationMatch` | Does a typical session fit `typicalSessionDurationMinutes`/`minutesAvailablePerDay`? |
| `experienceMatch` | Does the program's demand suit the user's apparent experience level (derived, never asked as a blunt "beginner/advanced" label — see §4 below)? |
| `performanceProfileMatch` | Does existing `ExercisePerformanceProfile`/`ActivityPerformanceProfile`/`BenchmarkPerformanceProfile` history support this program's assumptions (§6 below)? |
| `musclePriorityMatch` | Does the program's split/emphasis serve `LongTermGoal.priorityMuscleGroups`? |
| `modalityMatch` | Does the program's `ProgrammingSystemKind`/`ActivityType` match preferred (and avoid disliked) modalities? |
| `recoveryDemandMatch` | Is the program's aggregate `TrainingStressProfile` demand compatible with the phase's other protected/supporting components, given real recovery capacity? |
| `programAvailabilityMatch` | Does a real, curated `ProgramDefinition`/generator configuration actually exist for this system in this phase context at all — see §5's V1 coverage gap. |

Reason codes (§17's own instruction: "return reason codes... do not use
'AI thinks this program is best'") come from the shared `PlannerReasonCode`
vocabulary — `PLAN_REVISION_MODEL.md` §3 lists the program-recommendation-
specific codes (`PROGRAM_MATCH_AVAILABILITY`, `PROGRAM_MATCH_EXPERIENCE`,
`USER_SELECTED_ALTERNATIVE`, etc.).

## 4. "Experience" is derived, never a self-reported label

No new "experience level" field is proposed. §26 explicitly warns
against letting a historical PR automatically equal current ability, and
`ExercisePerformanceProfile.confidence`/`.lastPerformedAt` already model
exactly the recency/confidence discount this requires. `experienceMatch`
reads existing profile richness (how much confident, recent history
exists across relevant exercises/activities) rather than a static
"beginner/intermediate/advanced" tag a user would have to self-assess —
avoiding both a new field and an unreliable self-report.

## 5. The real coverage gap: only Hypertrophy/Powerlifting have a curated V1 library

`V1_PROGRAM_LIBRARY.md` curates 8 named, shippable configurations —
**all Hypertrophy or Powerlifting.** SteadyState, Interval and Functional
Fitness have real, tested generators (`SteadyStateProgramGenerator`,
`IntervalProgramGenerator`, `FunctionalFitnessProgramGenerator`) but no
equivalent "pick one of these named, curated configurations" list — a
program recommendation for a Fat Loss/Aerobic Development/Running/
Functional Fitness component can only propose a **generator parameter
set** (e.g. "SteadyState, Zone 2 emphasis, 45min base duration"), not a
named product-level configuration the way "5-Day Full Body Hypertrophy"
is named. `programAvailabilityMatch` exists specifically to surface this
distinction to a UI rather than hide it — a candidate backed by a real
V1-curated config should visibly outrank one backed by a bare generator
default. This gap is **MUST RESOLVE** in `STAGE5A_DECISION_MEMO.md`:
Stage 5B program recommendation for non-strength phases is only as good
as whatever curation (or lack of it) exists by then.

## 6. Never rewriting methodology to fit a phase

§19's example: a user selects RP-style Hypertrophy 5-Day during a Fat
Loss phase. The program's own `ProgramDefinition`/`StrengthProgressionEngine`
output is **not** transformed — same rule progression, same load/rep
scheme, computed exactly as it would be in a Muscle Gain phase. What
changes is everything *around* it:

- The component's `GoalPriority` becomes `.secondary`+`.required`
  ("protected," `PHASE_PLANNING_RULES.md` §2) rather than `.primary`.
- A conditioning component is layered in at `.primary` to actually serve
  the Fat Loss goal.
- `ConcurrentScheduler`'s existing interference/recovery-spacing
  constraints (unchanged, Stage 4F/4G) handle scheduling around the
  combined demand.
- If the combined demand becomes unmanageable (e.g. `interferenceAndRecoveryCompromise`
  stays unsatisfied across repeated tactical windows), the planner may
  **recommend** a different program — never silently substitute one.

This is `ConcurrentScheduler`'s own scope boundary (CLAUDE.md rule 15)
restated one layer up: the planner picks *which* programs compose a
phase and *how they're prioritized*; it never reaches into a
`ProgrammingSystem`'s own engine.

## 7. Strict vs. Adaptive

`ProgramInstance.adherenceModeOverride: AdherenceMode?` (`.strict`/
`.adaptive`, existing since Stage 1-2) is read, never written, by
`LongTermPlanner`. A `.strict` program's methodology is never modified by
planner logic, ever — the planner may change what's scheduled *around*
it (§6) but never its own progression. `.adaptive`'s "future allowed
modifications under explicit rules" remain exactly as undefined as they
already were (CLAUDE.md rule 11's "the full progression engine... is out
of scope until explicitly requested") — this pass adds no new adaptive
behavior, it only confirms the planner must check this field before ever
proposing to touch a program's internals, which today means: never.

**When a Strict program's own structure becomes a hard floor
(Decision 1).** A `Strict` program's generated session count is not a
suggestion — dropping one of "5-Day Full Body Hypertrophy"'s five weekly
sessions would no longer be that program, faithfully executed. This
generated count (already inferrable from the `ProgramDefinition`'s own
materialized `TemplateSession`s — no new field required) *is* the
program's implicit minimum-frequency requirement, feeding directly into
`PHASE_PLANNING_RULES.md` §2b step 4 ("validated methodology, where
available"). When the user's stated availability/mix genuinely cannot
give a selected Strict program's component enough room to run at its own
required count, that specific `(program, availability, mix)` combination
is `Infeasible` (§2a) — not a Poor Fit, and not a reason to silently
lighten the program's own structure.

## 8. Two selection paths, one evaluation

**Planner-recommended program** (default Guided Planning path,
`LONG_TERM_PLANNER.md` §4): `proposeProgram` ranks candidates, user
picks one (or accepts the top-ranked default).

**User chooses an existing `ProgramDefinition`** (Start From Program,
same section): the chosen program is evaluated with the *same*
`ProgramFitFactor`/`fitRating` machinery as any recommended candidate —
never a separate, looser path. A poor-fitting user choice still shows
its real `fitRating` and factors (§18/§2a: never blocked unless it meets
the narrow, mechanical `.infeasible` definition — never merely a poor
thematic or experience fit) so the planner can "evaluate and build
surrounding modules/mix" (§56) around it honestly.
