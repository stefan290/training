# Stage 5A Decision Memo

Every place this pass's design documents (`LONG_TERM_PLANNER.md` and its
6 companions) made a judgment call, deferred a question, or found a real
gap — collected here so Stage 5B does not start on an unreviewed
assumption. Per this stage's own instruction: **do not silently choose
major strategic training policy.**

## 1. MUST RESOLVE before Stage 5B implementation

These are architecture-shaping decisions this document recommends an
answer for, but which touch core/foundational entities or previously
out-of-scope territory (CLAUDE.md rule 11) — they need explicit sign-off,
not just an absence of objection.

1. **Extend `Goal` directly, or introduce a new wrapping type for
   `LongTermGoal`'s richer fields?** Recommendation:
   extend `Goal` (`STRATEGIC_PLAN_MODEL.md` §1) — same additive-field
   pattern as every prior stage's schema evolution, no duplicate-entity
   smell. Risk: `Goal` is a Stage-1 foundational entity; confirm before
   touching it.
2. **The illustrative `PhaseDurationPolicy` numbers
   (`STRATEGIC_PLAN_MODEL.md` §4a) are entirely TRAININGOS_DESIGNED —
   no source research was performed this pass.** They need either
   explicit product-owner sign-off as reasonable defaults, or a research
   pass (mirroring how Stage 4C/4D verified endurance protocols) before
   any real user sees a plan built from them.
3. **Add `PhaseType.hybrid`.** Purely additive, but it's the one new
   case on a core enum this pass recommends (`PHASE_PLANNING_RULES.md`
   §1) — confirm "Aerobic Development"/"Running Performance" really
   should stay expressed via `enduranceEvent` + mix composition rather
   than getting their own cases too.
4. **No curated V1 program library exists for SteadyState, Interval, or
   Functional Fitness** — only Hypertrophy/Powerlifting have the 8
   named, shippable configurations `V1_PROGRAM_LIBRARY.md` curates
   (`PROGRAM_RECOMMENDATION_MODEL.md` §5). Any Fat Loss/Aerobic
   Development/Running/Functional Fitness phase's program recommendation
   quality is capped by this gap until it's closed — decide whether
   Stage 5B blocks on curating that library first, or ships with
   generator-parameter-only recommendations for those systems and
   flags it visibly (`programAvailabilityMatch`) in the meantime.
5. **`TrainingPlan.supersedes: TrainingPlan?`** (`PLAN_REVISION_MODEL.md`
   §5) is a new field on a core entity, needed for the major-revision
   (long-term-goal-change) path. Confirm the nullify-delete-rule shape
   before it's built.
6. **`PlannerDecision`'s persistence shape** — multiple optional
   one-to-one back-references (`phase`/`trainingMix`/`programInstance`),
   mirroring `WorkoutBlock`'s established pattern
   (`PLAN_REVISION_MODEL.md` §2). Confirm this is preferred over
   alternatives (e.g. a generic subject-description string) before
   building it — it's the one new `@Model` type this whole design
   depends on for explainability.
7. **Rolling-window trigger defaults** — the 7-day scheduling buffer and
   "tactical horizon = primary component's natural block length,
   fallback 4 weeks" rule (`TACTICAL_PLANNING_HANDOFF.md` §1-2) are
   proposed, not validated against any real usage pattern.

## 2. Safe assumptions (low-risk, reversible, used without separate approval)

- Program compatibility reuses `GoalAlignmentRating` rather than a new
  parallel rating enum (`PROGRAM_RECOMMENDATION_MODEL.md` §2).
- `ModalityPreference` reuses `ProgrammingSystemKind`+`ActivityType`
  directly rather than a new modality vocabulary
  (`STRATEGIC_PLAN_MODEL.md` §1b).
- `performanceGoals: [String]` (freeform labels) rather than a typed
  metric system, for V1 (`STRATEGIC_PLAN_MODEL.md` §1a).
- `[CandidateTrainingMix]`/`[ProgramCandidate]` cap at ~3 entries
  (`ADHERENCE_AWARE_PLANNING.md` §5).
- One flat, additive `PlannerReasonCode` enum shared across every
  decision kind, rather than a separate enum per concern
  (`PLAN_REVISION_MODEL.md` §3).
- `LongTermGoal`'s availability fields stay coarse (day count, typical
  duration, doubles allowed) — the real, detailed `UserAvailability`
  remains supplied fresh at tactical time, never duplicated
  (`STRATEGIC_PLAN_MODEL.md` §1c).
- Minor revisions (extend/shorten within the same goal) mutate the
  current plan in place; only a long-term-goal change supersedes the
  whole plan (`PLAN_REVISION_MODEL.md` §4 vs. §5).

## 3. Deferred questions (explicitly not answered this pass)

- **Typed `PerformanceGoal`** (structured target metric, not a label) —
  real value, real design work, not attempted this pass.
- **`AdherenceMode.adaptive`'s actual future modification rules** —
  still entirely undefined; this pass only confirms the planner must
  check the mode and never touch a `.strict` program, per CLAUDE.md rule
  11's continuing deferral of the "full progression engine" concept.
- **Any machine-learning/behavioral-prediction component** — explicitly
  out of scope indefinitely, not just for Stage 5A/5B
  (`ADHERENCE_AWARE_PLANNING.md` §4).
- **A planned-vs-actual analytics surface** — confirmed representable
  from existing relationships (`PLAN_REVISION_MODEL.md` §6), no UI or
  aggregation engine designed.
- **Exact phase-progress computation** ("week 6 of 12") for the current-
  phase UI contract — referenced conceptually
  (`TACTICAL_PLANNING_HANDOFF.md` §4) but the precise formula (calendar
  weeks vs. completed-session count vs. program-journey position) isn't
  chosen.

## 4. Product choices requiring explicit owner decision

Strategic/training-policy calls, distinct from the engineering questions
above — CLAUDE.md rule 10 territory ("do not invent ambiguous training
rules... flag it").

1. **Should "protected" muscle-retention components have a
   TRAININGOS_DESIGNED minimum-frequency floor** (e.g. "never below 2x/
   week regardless of phase") **or be fully derived per-user with no
   floor at all?** This document's examples assume the latter (the
   floor is whatever `SessionFrequency.minimum` the recommendation
   logic computes, no separate hardcoded floor) — worth explicit
   confirmation before it becomes precedent.
2. **Should a temporary preference block have a maximum allowed
   duration** (e.g. capped at 8 weeks before the planner insists on a
   full phase reconsideration instead of "just extend the temporary
   window again")? Not addressed in `ADHERENCE_AWARE_PLANNING.md` §2 —
   currently unbounded.
3. **Should `.recommended` always mean strictly-highest-`GoalAlignment`,
   with variety preference only ever affecting the *second* slot
   (`.bestVarietyAlternative`)** — or should a strong `varietyPreference`
   ever be allowed to promote a slightly-lower-alignment, higher-variety
   mix to the top `.recommended` position itself? This document assumes
   the former (`.recommended` is never variety-adjusted) — flagged
   because it directly affects how "optimal" is defined in the UI's most
   prominent slot.
4. **Where exactly does "structurally impossible or unsafe" (§18) stop
   and "just a poor fit" begin**, for blocking a user's own program
   choice? This document treats it as identical to
   `GoalAlignmentRating.infeasible`/`ScheduleFeasibility.infeasible`
   (a real scheduling/availability impossibility) — confirm no
   additional "unsafe" category (e.g. an experience-mismatch severe
   enough to block outright) is wanted.

## 5. Stage 5B test plan (§65 — specified now, written later)

None of these exist yet; this is the list Stage 5B's own test-writing
task should work from, matching each to the proof case that motivates it:

1. 12-month Muscle Gain → summer Fat Loss plan produces the expected
   phase sequence (`STRATEGIC_PLAN_MODEL.md` §4, kickoff §44).
2. Target-date backward planning anchors the Fat Loss phase's completion
   at/before `milestoneDate` (§5, §44).
3. 5-day availability produces a mix whose total frequency fits within 5.
4. 6-day availability produces a materially different (not just
   padded) mix.
5. Recommended Hypertrophy mix matches the expected composition for a
   pure Muscle Gain goal with no variety preference.
6. User-selected hybrid mix (3 Strength + 2 Functional Fitness + 1 Run)
   is scheduled as-is, never silently reverted (kickoff §46).
7. A 4-week Functional Fitness temporary preference block schedules
   correctly and offers all 3 return options at expiry, auto-reverting
   never (kickoff §45).
8. Running-focus switch preserves strength history and offers a
   maintenance-tier strength component (kickoff §47).
9. Cycling-focus switch behaves identically to running via
   `ModalityPreference.activityType`, proving no running-specific
   hardcoding (kickoff §48).
10. Powerlifting-focus switch during a Muscle Gain year evaluates
    strength/hypertrophy tradeoff and never resets prior hypertrophy
    history (kickoff §49).
11. Phase extension recalculates only future phases; completed phases
    are byte-identical before/after.
12. Phase shortening redistributes freed time per
    `PhaseDurationPolicy` without violating any phase's `minimumWeeks`.
13. An important-date (milestone) change re-runs backward planning from
    today, preserving history.
14. A long-term-goal change supersedes the plan (`PLAN_REVISION_MODEL.md`
    §5) — old plan `.superseded`, new plan `.active`, `Goal.plans` holds
    both.
15. Program selected manually (Start From Program) evaluates with the
    same `ProgramFitFactor` machinery as a recommended candidate.
16. Recommended-program path (Guided Planning) produces a ranked
    `[ProgramCandidate]` with reason codes.
17. No historical `PerformanceProfile`/`ExercisePerformanceProfile`/
    `ActivityPerformanceProfile`/`BenchmarkPerformanceProfile` row is
    ever deleted or reset by any planner operation in this suite.
18. No test ever asserts an exact set/load/pace more than one tactical
    window ahead — a structural test of the boundary itself (grep-style
    check that materialization never runs past the current window).
19. Identical `LongTermGoal`/`asOf` inputs produce identical
    `StrategicPlanProposal`/`[CandidateTrainingMix]` output — determinism,
    matching every existing engine's own proof pattern.
20. Every `PlannerDecision` constructed anywhere in the suite has a
    non-empty `reasonCode` and `explanation` — structural, mirroring
    `Recommendation`'s "no reason code, no recommendation" invariant.

## 6. What this pass confirmed needs no change

Per the kickoff's own instruction (§66/§37): "do not duplicate existing
systems... if planner analysis reveals a genuine incompatibility, stop
and explain rather than workaround." None was found. Specifically
confirmed unchanged: `HypertrophyProgramGenerator`/`PowerliftingProgramGenerator`/
`SteadyStateProgramGenerator`/`IntervalProgramGenerator`/
`FunctionalFitnessProgramGenerator` and their engines, `ConcurrentScheduler`,
`GoalAlignmentEvaluator`, `SchedulingPipeline`, `TrainingMix`/
`TrainingMixComponent`, `AcceptScheduleProposalUseCase`. Every new concept
in this pass's 7 documents is additive (a new optional field, a new
enum case, or a wholly new plain-value type) — nothing existing is
redefined.
