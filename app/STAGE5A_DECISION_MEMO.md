# Stage 5A Decision Memo

**Stage 5B status: all eleven resolved decisions below were implemented
as resolved — none were revisited or reopened during implementation.**
See `STAGE5B_IMPLEMENTATION_REPORT.md` for the concrete code each
resolution produced, and for the small number of additional,
implementation-level simplifications that came up only once actual code
was written (each flagged at its call site, never silently decided —
CLAUDE.md rule 10).

Every place this pass's design documents (`LONG_TERM_PLANNER.md` and its
7 companions) made a judgment call, deferred a question, or found a real
gap — collected here so Stage 5B does not start on an unreviewed
assumption. Per this stage's own instruction: **do not silently choose
major strategic training policy.**

**Status: ALL ELEVEN Stage 5A decisions are RESOLVED** — the 4
product-policy decisions (§4) and the 7 engineering MUST RESOLVE items
(§1), across two review rounds. Zero blocking open items remain before
Stage 5B implementation. What's left (§3) is explicitly non-blocking,
configurable policy or backlog work, not a gate.

## 1. Engineering MUST RESOLVE items — ALL SEVEN RESOLVED

Architecture-shaping decisions touching core/foundational entities or
previously out-of-scope territory (CLAUDE.md rule 11) — each needed
explicit sign-off, not just an absence of objection. Original question
preserved for the record, followed by the resolution actually locked in.

1. **Goal extension (RESOLVED).** Original question: extend `Goal`
   directly, or introduce a new wrapping entity? **Decision: extend
   `Goal` compositionally** — never one giant object of unrelated
   nullable fields. One field is narrowly migrated
   (`secondaryTypes: [GoalType]` → `secondaryObjectives: [SecondaryObjective]`,
   adding a `.protected`/`.supporting` role tag); three fields are added
   (`milestoneDate: Date?`, `bodyCompositionDirection: BodyCompositionDirection?`,
   one bundled `preferences: GoalPreferences?` struct — not nine loose
   scalars). **No new `GoalType` cases were needed** — every required
   objective family (Muscle Gain, Fat Loss, Maintenance, Strength/
   Powerlifting, Running, Aerobic Development, Functional Fitness)
   already maps onto the existing enum; body-composition direction and
   training modality are kept as independent fields, never conflated.
   No new `@Model` entity. Full model: `STRATEGIC_PLAN_MODEL.md` §1.
2. **`PhaseDurationKind` (RESOLVED — architecture locked, numbers are
   not).** Original question: what shape does a phase's duration take?
   **Decision:** a 4-case value type — `.fixed(weeks:)`,
   `.range(typical:minimum:maximum:)`, `.untilDate(_:)`, `.untilMilestone`
   — richer than a single range, since "runs until a milestone" and "a
   program's own fixed block" are different *kinds* of duration, not
   different numbers. Planner-recommended vs. user-extended/shortened is
   `PlannerDecision` provenance, not a separate case. **The specific
   week-counts remain explicitly non-blocking, configurable
   TRAININGOS_DESIGNED fixtures** — sensible for Stage 5B's deterministic
   tests, never a physiology claim, tunable without touching this shape.
   Full model: `STRATEGIC_PLAN_MODEL.md` §4a.
3. **`PhaseType.hybrid` (RESOLVED — WITHDRAWN).** Original proposal: add
   a `.hybrid` case for phases mixing several modalities. **Decision: do
   not add it, on review.** A phase's strategic objective and its
   `TrainingMix`'s composition are separate concepts — a Muscle Gain
   phase using 3 Strength + 2 Functional Fitness + 1 Running is still
   entirely a Muscle Gain phase; "hybrid" describes the mix, never the
   objective. The original justification (the transition target state)
   is already `.transition`. Zero new `PhaseType` cases. If a genuinely
   new *objective* independent of any specific mix ever emerges, that is
   a distinct future question, not this one. Full model:
   `PHASE_PLANNING_RULES.md` §1.
4. **`ProgramCapabilityRegistry` (RESOLVED).** Original question: how
   does the planner avoid recommending something it can't execute?
   **Decision:** a new, required gate — `EXECUTABILITY/CAPABILITY CHECK`
   — runs *before* `GoalAlignment` in the locked pipeline. Three
   previously-conflated questions are now answered independently:
   `ProgrammingSystem` availability (all 5 exist), curated-preset
   availability (only Hypertrophy/Powerlifting today — a UX gap, not an
   executability one), and real instantiability right now (true for all
   5 systems, since every generator produces a real `ProgramDefinition`).
   `ProgramCandidate.programDefinition` is **non-optional** — a
   conceptually-good, not-yet-executable path is a `CapabilityGap`
   ("Unavailable / not currently executable"), never a `ProgramCandidate`,
   never a fabricated definition. Curating named presets for
   SteadyState/Interval/Functional Fitness remains open **as non-blocking
   backlog**, not a Stage 5B gate. Full model:
   `PROGRAM_RECOMMENDATION_MODEL.md` §5.
5. **Revision lineage (RESOLVED).** Original question: how does
   `TrainingPlan.supersedes` preserve historical truth? **Decision:**
   every re-plan — extend, shorten, milestone change, or a full
   long-term-goal change — creates a **new** `TrainingPlan` revision,
   never an in-place mutation (this generalizes the original "minor vs.
   major" split into one uniform mechanism). Two new fields:
   `supersedes: TrainingPlan?` (nullify, the immediately-prior revision)
   and `lineageID: UUID` (shared across ordinary revisions; a fresh UUID
   only when a genuinely new strategic intent begins, e.g. a full goal
   change). A revision's own `phases` holds only its new/future phases —
   completed phases and accepted tactical schedules stay permanently on
   whichever revision they actually happened under, never moved,
   duplicated, or rewritten. Full model: `PLAN_REVISION_MODEL.md` §4.
6. **`PlannerDecision` shape (RESOLVED).** Original question: is the
   original `{reasonCode, factors, explanation, decidedAt}` shape
   sufficient? **Decision: extended, not replaced** — added
   `decisionType` (a closed, 6-case enum scoping this to strategically-
   meaningful events only: phase selected, program/mix selected, user
   chose alternative, temporary preference applied, phase extended/
   shortened, roadmap revised — never a debug log of every low-level
   comparison), `source` (`systemRecommended`/`userSelected`/
   `userOverride`/`planRevision`), and `alternativesConsidered:
   [ConsideredAlternative]` (label + rating summary + rejection reason
   for what wasn't chosen). `goal`/`planRevision` back-references added
   alongside the existing `phase`/`trainingMix`/`programInstance`.
   `explanation` remains generated display copy, never business source
   of truth. Full model: `PLAN_REVISION_MODEL.md` §2.
7. **Rolling tactical window (RESOLVED — architecture locked, numbers
   are not).** Original question: when does the next window generate,
   and how far can it reach? **Decision:** tactical horizon is bounded,
   in order, by (a) the phase's primary component's own natural
   mesocycle block, (b) the current phase's own remaining time, (c) any
   known upcoming transition/milestone date, (d) a configurable fallback
   (illustrative: 4 weeks) only when no natural block exists — never a
   bare constant in isolation, and never reaching into what will become
   a different mix under the next phase. 6 explicit, deterministic
   triggers regenerate the window (approaching end, already completed,
   phase change, material mix/preference change, pause/resume, plan
   revision) — never a bare timer. A previously accepted window is a
   permanent historical snapshot. **The specific "7 days"/"4 weeks"
   numbers remain non-blocking, configurable policy.** Full model:
   `TACTICAL_PLANNING_HANDOFF.md` §1-2.

## 2. Safe assumptions (low-risk, reversible, used without separate approval)

- Program compatibility reuses `GoalAlignmentRating` rather than a new
  parallel rating enum (`PROGRAM_RECOMMENDATION_MODEL.md` §2).
- `ModalityPreference` reuses `ProgrammingSystemKind`+`ActivityType`
  directly rather than a new modality vocabulary
  (`STRATEGIC_PLAN_MODEL.md` §1d).
- `performanceGoals: [String]` (freeform labels) rather than a typed
  metric system, for V1 (`STRATEGIC_PLAN_MODEL.md` §1c).
- `[CandidateTrainingMix]`/`[ProgramCandidate]` cap at ~3 entries
  (`ADHERENCE_AWARE_PLANNING.md` §5c).
- One flat, additive `PlannerReasonCode` enum shared across every
  decision kind, rather than a separate enum per concern
  (`PLAN_REVISION_MODEL.md` §3).
- `Goal.preferences`'s availability fields stay coarse (day count,
  typical duration, doubles allowed) — the real, detailed
  `UserAvailability` remains supplied fresh at tactical time, never
  duplicated (`STRATEGIC_PLAN_MODEL.md` §1e).
- Every re-plan creates a new `TrainingPlan` revision (uniform mechanism,
  §1 item 5 above) — superseded from the original draft's "minor
  revisions mutate in place" position.

## 3. Deferred questions (explicitly not answered this pass — non-blocking)

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
  from existing relationships (`PLAN_REVISION_MODEL.md` §5), no UI or
  aggregation engine designed.
- **Exact phase-progress computation** ("week 6 of 12") for the current-
  phase UI contract — referenced conceptually
  (`TACTICAL_PLANNING_HANDOFF.md` §4) but the precise formula (calendar
  weeks vs. completed-session count vs. program-journey position) isn't
  chosen.
- **Curating a named V1 preset library for SteadyState/Interval/
  Functional Fitness** — real, valuable future work, explicitly tracked
  as backlog, not a Stage 5B blocker (`PROGRAM_RECOMMENDATION_MODEL.md`
  §5d).
- **The illustrative `PhaseDurationKind.range`/rolling-window numbers**
  (§1 items 2 and 7) — configurable by design, free to tune from real
  usage without any architecture change.

## 4. Product choices requiring explicit owner decision — ALL FOUR RESOLVED

Strategic/training-policy calls, distinct from the engineering questions
above — CLAUDE.md rule 10 territory ("do not invent ambiguous training
rules... flag it"). All four below were reviewed and decided by the
product owner in the first review round; the original question is
preserved for the record, followed by the resolution actually locked in.

1. **Protected-frequency floor policy (RESOLVED).** Original question:
   should "protected" components have a TRAININGOS_DESIGNED global
   minimum-frequency floor by modality, or be fully derived per-user
   with no floor at all? **Decision: neither, as posed.** The floor must
   always be phase/program-derived — never a global rule keyed on
   modality (e.g. never "every Fat Loss phase requires 3 strength
   sessions") — using the generic minimum/target/maximum hierarchy
   `SessionFrequency` already provides, sourced from `TrainingPhase`
   goal/priorities, the selected/recommended `ProgramConfiguration`, the
   component's own stated requirements, and validated methodology where
   available. Falling below the derived floor is a `GoalAlignment`
   compromise (Poor Fit), never an automatic `Infeasible`, unless the
   floor is a specific Strict program's own hard methodology requirement
   — then it's a structural incompatibility with *that* program choice.
   Sessions are never silently added back. Full model:
   `PHASE_PLANNING_RULES.md` §2a-2b, §8; `PROGRAM_RECOMMENDATION_MODEL.md`
   §7.
2. **Temporary-preference-block maximum duration (RESOLVED).** Original
   question: should a temporary block have a hard maximum duration?
   **Decision: no universal hard maximum.** A block always carries a
   start date, an intended review date/duration, and explicit temporary
   status (`validFrom`/`validUntil`/`validUntil != nil`) — a
   TrainingOS-recommended typical review window is configurable, not a
   hard physiological rule. Instead of a cap, a **materiality check**
   fires when a temporary block's cumulative duration/renewals would
   materially change the phase's character, surfacing "this now looks
   more like a phase change than a temporary block" with three explicit
   options (continue / convert the phase / re-plan the roadmap) — never
   silently converted, never silently reverted at plain expiry either.
   Full model: `ADHERENCE_AWARE_PLANNING.md` §2-2a.
3. **Can variety/adherence promote an alternative above the
   physiologically best recommendation (RESOLVED — reverses this
   document's original draft position).** **Decision: YES**, bounded by
   a two-stage model. Stage one: a goal-compatibility gate
   (`GoalAlignmentRating >= .acceptable`) — candidates that don't clear
   it can never be promoted, no matter how strongly preferred (this is
   what stops preference from erasing major goal incompatibility). Stage
   two: among gated-in candidates, a preference-aligned candidate may be
   promoted to `.recommended` when its alignment is within a bounded
   tier gap (default 1 tier) of the best. The best-`GoalAlignment`
   candidate is always still shown (`.bestGoalAlignment`), never hidden,
   when it's displaced from the top slot. New reason code
   `ADHERENCE_PREFERENCE_PROMOTED_ALTERNATIVE`. Deterministic and
   explainable throughout — no numeric percentages. Full model:
   `ADHERENCE_AWARE_PLANNING.md` §5-5d; `LONG_TERM_PLANNER.md` §2b.
4. **Poor Fit vs. Infeasible boundary (RESOLVED — narrow definition
   locked).** **Decision: `Infeasible` is narrow and mechanical** — a
   real hard-constraint impossibility only (6 required sessions/3
   available days with no doubles; a required duration that exceeds
   every window and can't split; two Strict programs' constraints
   conflicting; a required minimum that can't physically fit; a
   required non-substitutable prescription needing unavailable
   equipment/activity). **`Poor Fit` covers everything else** — a
   thematic, experience, or preference mismatch that's still fully
   executable (pure running during Muscle Gain; an advanced program
   picked by a beginner; low hypertrophy stimulus in a Muscle Gain
   phase) — and remains selectable. **Locked: neither rating may ever be
   used, now or later, to encode a safety/eligibility judgment**; a
   future validated safety concept must be a separate type. Full model:
   `PROGRAM_RECOMMENDATION_MODEL.md` §2a; `CLAUDE.md` rule 18.

## 5. The locked decision hierarchy (final)

Every ranking the planner produces — mixes, programs, or a revised
roadmap — flows through one fixed pipeline (full detail in
`LONG_TERM_PLANNER.md` §2, the single canonical statement of it):

```
LONG-TERM GOAL → STRATEGIC PLAN REVISION → TRAINING PHASE (objective, not modality)
  → CANDIDATE TRAINING MIXES → EXECUTABILITY/CAPABILITY CHECK → GOAL ALIGNMENT
  → PROGRAM/MIX QUALITY → ADHERENCE/USER PREFERENCE → RANKED RECOMMENDATION
  → USER SELECTION → PROGRAM GENERATORS/DEFINITIONS → ROLLING TACTICAL WINDOW
  → SCHEDULING PIPELINE → USER APPROVAL → EXECUTION/PERFORMANCE PROFILE
```

Two independent feasibility gates exist, never conflated (`LONG_TERM_PLANNER.md`
§2a): **executability** (can TrainingOS instantiate this at all — early)
and **scheduling feasibility** (can it be placed on the calendar given
real availability — late, inside Scheduling Pipeline, Stage 4G,
unchanged). Between them, `GoalAlignment` determines fit, a compatibility
gate determines promotion eligibility, and preference/adherence reorders
only among gated-in candidates. User choice remains final throughout.

## 6. Stage 5B test plan (§65 — specified now, written later)

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
    are byte-identical before/after, on whichever revision they belong to.
12. Phase shortening redistributes freed time per `PhaseDurationKind`
    without violating any phase's `minimum`.
13. An important-date (milestone) change re-runs backward planning from
    today as a new revision, preserving history.
14. A long-term-goal change starts a new lineage
    (`PLAN_REVISION_MODEL.md` §4c) — old revision `.superseded`, new
    revision `.active`, `lineageID` differs, `Goal.plans` holds both.
15. Program selected manually (Start From Program) evaluates with the
    same `ProgramFitFactor` machinery as a recommended candidate, after
    passing the same capability gate.
16. Recommended-program path (Guided Planning) produces a ranked
    `[ProgramCandidate]` (all executable) plus any `[CapabilityGap]`,
    with reason codes.
17. No historical `PerformanceProfile`/`ExercisePerformanceProfile`/
    `ActivityPerformanceProfile`/`BenchmarkPerformanceProfile` row is
    ever deleted or reset by any planner operation in this suite.
18. No test ever asserts an exact set/load/pace more than one tactical
    window ahead — a structural test of the boundary itself (grep-style
    check that materialization never runs past the current window).
19. Identical `Goal`/`asOf` inputs produce identical
    `StrategicPlanProposal`/`[CandidateTrainingMix]` output — determinism,
    matching every existing engine's own proof pattern.
20. Every `PlannerDecision` constructed anywhere in the suite has a
    non-empty `reasonCode`, `decisionType`, `source`, and `explanation` —
    structural, mirroring `Recommendation`'s "no reason code, no
    recommendation" invariant.
21. A `ProgramCandidate` is never constructed with an uninstantiable
    `programDefinition` — every candidate in every test is genuinely
    executable; a deliberately-unavailable system produces a
    `CapabilityGap`, never a candidate.

## 7. What this pass confirmed needs no change

Per the kickoff's own instruction (§66/§37): "do not duplicate existing
systems... if planner analysis reveals a genuine incompatibility, stop
and explain rather than workaround." None was found across either review
round. Specifically confirmed unchanged:
`HypertrophyProgramGenerator`/`PowerliftingProgramGenerator`/
`SteadyStateProgramGenerator`/`IntervalProgramGenerator`/
`FunctionalFitnessProgramGenerator` and their engines, `ConcurrentScheduler`,
`GoalAlignmentEvaluator`, `SchedulingPipeline`, `TrainingMix`/
`TrainingMixComponent`, `AcceptScheduleProposalUseCase`. Every new concept
across this pass's 8 documents is additive (a new optional/migrated
field, zero new `PhaseType`/`GoalType` cases, or a wholly new plain-value
type) — nothing existing is redefined.
