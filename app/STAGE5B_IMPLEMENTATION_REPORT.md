# Stage 5B Implementation Report

Implementation of the Long-Term Planner per the fully-approved Stage 5A
architecture (`LONG_TERM_PLANNER.md` and its 8 companion documents,
`STAGE5A_DECISION_MEMO.md`: all 11 decisions resolved, zero blocking
MUST RESOLVE items). This report covers what was built, exactly as
implemented — not a restatement of the design docs, which remain the
authoritative source for *why* each shape was chosen.

## 1. Architecture

`LongTermPlanner` (`Application/UseCases/LongTermPlanner.swift`) is a
single `enum` namespace holding four proposal-producing, non-mutating
functions plus their private helpers — `proposeProgram`,
`proposeTrainingMix`, `proposeStrategicPlan`, `reviseStrategicPlan` —
mirroring `ConcurrentScheduler`/`GoalAlignmentEvaluator`'s existing
"pure function(s), typed input, typed output, reason codes" shape.
It lives in `Application/UseCases/`, not `Engines/`, because
`proposeProgram` calls the existing generators, which insert a real
`ProgramDefinition` into a `ModelContext` — the one place this pass
needs a context at all. `proposeTrainingMix`/`proposeStrategicPlan`/
`reviseStrategicPlan` take no `ModelContext` and mutate nothing.

Two new engines were added alongside it, both pure and context-free like
`GoalAlignmentEvaluator`: `TemporaryPreferenceEvaluator` (expiry/
materiality detection) and `TacticalWindowPolicy` (window sizing +
date-driven regeneration triggers).

Three new, explicit acceptance use cases turn a proposal into persisted
state, continuing the Engine-recommendation → Explanation → User-approval
pattern `AcceptScheduleProposalUseCase` already established:
`AcceptStrategicPlanUseCase` (phases + revision lineage + `PlannerDecision`)
and `SwitchTrainingModalityUseCase` (temporary/stable mix switching +
`PlannerDecision`). No proposal function mutates a `TrainingPlan`/
`TrainingPhase`/`TrainingMix` directly; only these two use cases do.

## 2. Goal / objective composition

`Goal` gained `secondaryObjectives: [SecondaryObjective]` (replacing
`secondaryTypes: [GoalType]`, a strict superset — `secondaryTypes` had
zero other call sites, confirmed by grep before renaming), plus
`milestoneDate: Date?`, `bodyCompositionDirection: BodyCompositionDirection?`,
and `preferences: GoalPreferences?`. `GoalPreferences` bundles 8 fields
(preferred/disliked modalities, variety preference, priority muscle
groups, freeform performance-goal labels, and 3 coarse availability
fields) into one optional struct — never 9 loose scalars, never required.
No new `GoalType`/`PhaseType` case was added anywhere in this stage.

## 3. StrategicPlan / revision model

`StrategicPlan` is not a new entity — it is `TrainingPlan`, exactly as
`STRATEGIC_PLAN_MODEL.md` §2 specified. `TrainingPlan` gained
`supersedes: TrainingPlan?` (nullify) and `lineageID: UUID` (defaults to
a fresh UUID unless explicitly continued). `StrategicPlanProposal`/
`ProposedPhase`/`StrategicPlanFeasibility` are new, plain, non-persisted
value types (`Domain/ValueTypes/StrategicPlanProposal.swift`) — the
transient shape every other proposal type in this codebase already uses.

## 4. TrainingPhase generation

`LongTermPlanner.proposeStrategicPlan(goal:asOf:)` forward-fills phases
serving `goal.primaryType` when there is no `milestoneDate`, and
backward-anchors a milestone-appropriate phase (via
`milestonePhaseType(direction:primaryType:)`, mapping `.loseFat`/
`.recomposition` → Fat Loss, `.gainMuscle` → Muscle Gain, `.maintain`/`nil`
→ the plan's own primary type) when there is one, inserting a Transition
phase immediately before it only when the milestone phase's type differs
from the primary type. `PhaseType.hybrid` was never added, confirmed by
`grep`. The internal core (`proposePhases(_:asOf:)`, operating on a small
`PlanningParameters` struct rather than a live `Goal`) is shared between
`proposeStrategicPlan` and `reviseStrategicPlan`, so both paths produce
identical phase-generation behavior by construction, not by convention.

## 5. Duration policy behavior

`PhaseDurationKind` (`.fixed`/`.range`/`.untilDate`/`.untilMilestone`) and
`PhaseDurationDefaults` (a static, caller-overridable table, mirroring
`InterferenceAvoidanceRule.conservativeDefault`'s exact pattern) exist
exactly per `STRATEGIC_PLAN_MODEL.md` §4a, including its illustrative
fixture numbers verbatim (Muscle Gain 12/6/20 weeks, Fat Loss 8/4/12,
Maintenance 4/2/8, Recovery 2/1/4, Transition 2/1/3, Strength 8/4/12,
Functional Fitness 8/4/12 — `enduranceEvent` deliberately absent, falling
back to a generic 8/4/12 fixture when a caller needs a week count for it
at all). A Maintenance phase is inserted into a forward-fill after every
2 consecutive same-type phases — a deterministic cadence rule, never a
fixed annual cadence — proven by
`testMaintenanceCadenceInsertsAfterTwoConsecutivePrimaryPhases`.

## 6. Candidate mix generation

`LongTermPlanner.proposeTrainingMix(phase:goal:)` builds 1-2 deterministic,
illustrative `TrainingMix` templates per `PhaseType` (Muscle Gain's two
candidates are `ADHERENCE_AWARE_PLANNING.md` §5d's exact worked example —
5-Day Hypertrophy + 2 Zone 2 vs. 3 Strength + 2 Functional Fitness + 1
Run), computes each candidate's `GoalAlignment` against a representative,
never-persisted `ScheduleProposal` (synthetic `Session`s sized to each
component's `frequency.target`, matching the existing
`ConcurrentSchedulerTests` convention of constructing plain `Session`s
directly rather than running a full generator/materializer chain), then
ranks via `rankCandidateMixes`.

## 7. Capability registry integration

`ProgramCapabilityRegistry.availableProgrammingSystems()`/`.capability(for:)`/
`.canInstantiate(_:)` gate both `proposeProgram` (structural
per-configuration validity) and `proposeTrainingMix`/`rankCandidateMixes`
(coarse per-system availability) before any `GoalAlignment`/fit-factor
scoring happens. A candidate that fails either check never becomes a
`ProgramCandidate`/gate-eligible `CandidateTrainingMix` — it becomes a
`CapabilityGap` or is silently dropped before ranking, per
`LONG_TERM_PLANNER.md` §2a's two-distinct-gates architecture.

## 8. GoalAlignmentEvaluator usage

Reused completely unmodified. Every `alignment: GoalAlignment` in
`CandidateTrainingMix` comes from `GoalAlignmentEvaluator.evaluate(mix:proposal:)`
called via `SchedulingPipeline.propose(mix:inputs:constraints:)` — the
exact same call every `ConcurrentSchedulerTests`/`SchedulerHardeningTests`
case already exercises. No second alignment/scoring system was
introduced anywhere in this stage.

## 9. Adherence-aware ranking

`LongTermPlanner.rankCandidateMixes` implements `ADHERENCE_AWARE_PLANNING.md`
§5a/§5b exactly: a compatibility gate (`GoalAlignmentRating >= .acceptable`),
then bounded promotion (`maxPromotableTierGap = 1`) among gate-eligible,
preference-aligned candidates only. Both constants are `static let`s on
`LongTermPlanner`, TRAININGOS_DESIGNED and trivially overridable later.
Preference-alignment is a plain 3-part boolean (zero disliked-modality
overlap, at least one preferred-modality overlap, and — only under
`varietyPreference == .high` — strictly more distinct `ProgrammingSystemKind`s
than the best-aligned candidate), never a fabricated score.

## 10. Recommended-vs-user-selected behavior

`CandidateMixRole` (`.recommended`/`.bestGoalAlignment`/
`.bestVarietyAlternative`/`.userPreferenceAlternative`) is assigned by
`rankCandidateMixes`; a promoted candidate always keeps
`.bestGoalAlignment` visible on whichever candidate it displaced, tagged
with reason code `ADHERENCE_PREFERENCE_PROMOTED_ALTERNATIVE`. A `.poor`-
or `.infeasible`-rated candidate can never carry `.recommended`, proven by
`testPoorCandidateNeverPromotedRegardlessOfPreferenceAlignment`.
`TrainingPhase.activeTrainingMix(asOf:)` (new, purely additive — the
existing `selectedTrainingMix` computed property is untouched) lets
`SwitchTrainingModalityUseCase` disambiguate among more than one
`.selected` mix once a temporary override coexists with a stable one; a
user's own selection is never silently reverted anywhere in this stage.

## 11. Temporary preference blocks

`TemporaryPreferenceEvaluator.isExpired`/`.hasCrossedMaterialityThreshold`
implement `ADHERENCE_AWARE_PLANNING.md` §2/§2a's two distinct checks
(plain `validUntil` expiry vs. the materiality threshold — half the
enclosing phase's typical duration, or more than one consecutive renewal).
`SwitchTrainingModalityUseCase.apply` implements the mechanical half of
the three-option resolution (attach a new `.selected` mix, close the
previous one's window) — proven against all four required modality
switches (Functional Fitness, Running, Cycling, Powerlifting), each
verified to leave the annual `TrainingPlan`/`TrainingPhase` and every
`PerformanceProfile`/`ExercisePerformanceProfile` completely untouched.
Deciding *which* mix object each of the three options supplies (return to
recommended / continue / re-plan) is a caller/UI concern, out of scope
without UI expansion — the tests exercise all three paths by constructing
the right mix at the call site, exactly as a future UI layer would.

## 12. Program recommendation

`LongTermPlanner.proposeProgram(component:profile:availability:context:)`
is unchanged from its original Slice 5 shape: capability-checks, then
materializes a real `ProgramDefinition` per candidate (curated V1 library
match for Hypertrophy/Powerlifting, freshly-derived configuration for
SteadyState/Interval/Functional Fitness), scores 9 `ProgramFitFactor`s,
and ranks deterministically. No changes were made to this function during
later slices.

## 13. Start-From-Program behavior

Not built as a separate code path in this stage, per `LONG_TERM_PLANNER.md`
§4's own finding: "Start From Program is Guided Planning with one
component's selection already fixed before the recommendation step runs."
No second pipeline exists to build or maintain; `proposeProgram`/
`proposeTrainingMix` already support a caller fixing one component ahead
of time by simply not calling `proposeProgram` for that component and
instead supplying its already-chosen `ProgramInstance` directly. Building
an actual onboarding/browse UI around this was explicitly out of scope.

## 14. Tactical handoff

`TacticalWindowPolicy.windowLengthInDays` implements `TACTICAL_PLANNING_HANDOFF.md`
§1's ordered bounds (mesocycle block → phase remaining time → known
transition date → configurable 4-week fallback) — Hypertrophy/Powerlifting
resolve their real 4-week block (`TrainingWeek.isDeload` week-4 convention);
SteadyState/Interval/Functional Fitness fall back to the configurable
default. `TacticalWindowTriggerEvaluator.evaluate` implements the two
date-driven regeneration triggers (`.windowApproachingEnd`/
`.windowCompleted`, a 7-day configurable buffer); the other four
`TacticalWindowTrigger` cases are event-driven and fired by whichever use
case already knows the event happened, never re-detected. No
performance-dependent prescription is ever fabricated ahead of a window's
own boundary — this stage never materializes Sessions past what
`windowLengthInDays` returns, by construction (no materialization code
was written at all; only the boundary is computed).

## 15. PlannerDecision implementation

`PlannerDecision`/`PlannerDecisionType`/`DecisionSource`/
`ConsideredAlternative`/`PlannerReasonCode` (23 cases, all of
`PLAN_REVISION_MODEL.md` §3's vocabulary) exist exactly as specified.
Persisted only at acceptance time: `AcceptStrategicPlanUseCase` logs
exactly one `PlannerDecision` per accepted plan/revision;
`SwitchTrainingModalityUseCase` logs exactly one per mix switch. No
per-comparison scheduler internal is ever logged here — that stays on
`ScheduleIssue`, unduplicated.

## 16. Revision / history behavior

`AcceptStrategicPlanUseCase.accept` implements `PLAN_REVISION_MODEL.md`
§4a exactly: a superseded plan's still-`.planned` phases become
`.abandoned` (never deleted), the superseded plan's own status becomes
`.superseded`, and any phase already `.completed` is never touched by any
code path in this stage — proven directly by
`testSupersedingAPlanNeverMutatesCompletedHistoryAndAbandonsPlannedPhases`
and `testFullRevisionCycleNeverMutatesTheCompletedPhaseOrPerformanceHistory`.
A minor revision (`extendPhase`/`shortenPhase`/`changeMilestoneDate`)
keeps the same `lineageID`; a long-term-goal change
(`changeLongTermGoal`) is expected to be accepted with a fresh
`lineageID` (caller passes `lineageID: nil`) while `supersedes` still
points at the prior revision — proven by
`testChangingLongTermGoalProducesANewLineageOnAcceptance`.

**Documented simplification:** `reviseStrategicPlan`'s `.extendPhase`/
`.shortenPhase` target the plan's nearest not-yet-started (`.planned`)
phase, not an already-`.active` phase's own future boundary in place.
`PLAN_REVISION_MODEL.md` §1's one narrow exception (resizing an active
phase's own remaining boundary without abandoning it) requires mutating
a row that belongs to a *different* revision than the one being
produced — flagged in `LongTermPlanner.swift`'s own doc comment as a
deliberately deferred nuance (CLAUDE.md rule 10), not silently assumed.
Shortening's fuller "a later Maintenance/Recovery phase absorbs freed
time first" redistribution (`PHASE_PLANNING_RULES.md` §5) is likewise
deferred in favor of a simpler, correct "shift everything later by the
same delta" baseline, flagged at the same call site.

## 17. Persistence / schema changes

- `Goal`: `secondaryTypes: [GoalType]` → `secondaryObjectives: [SecondaryObjective]`; `+milestoneDate`, `+bodyCompositionDirection`, `+preferences`.
- `TrainingPlan`: `+supersedes: TrainingPlan?`, `+lineageID: UUID`.
- `PersistenceController`: `PlannerDecision.self` added to the schema.
- New `@Model` entity: `PlannerDecision`.
- New value types (none persisted independently — all embedded on the
  above or transient): `SecondaryObjective`, `SecondaryObjectiveRole`,
  `BodyCompositionDirection`, `ModalityPreference`, `VarietyPreference`,
  `GoalPreferences`, `PlannerDecisionType`, `DecisionSource`,
  `ConsideredAlternative`, `PlannerReasonCode`, `PhaseDurationKind`,
  `GeneratorParameters`, `ProgramSystemCapability`, `CapabilityGapReason`,
  `CapabilityGap`, `ProgramFitFactorKind`, `ProgramFitFactor`,
  `ProgramCandidate`, `CandidateMixRole`, `CandidateTrainingMix`,
  `StrategicPlanFeasibility`, `ProposedPhase`, `StrategicPlanProposal`,
  `TacticalWindowTrigger`.
- New, purely additive method: `TrainingPhase.activeTrainingMix(asOf:)`.
- No existing field's meaning changed; no existing relationship's delete
  rule changed. `DELETE_RULE_MATRIX.md` §"Stage 5B additions" documents
  the one new relationship (`TrainingPlan.supersedes`, nullify) and
  confirms `PlannerDecision`'s back-references need no delete rule at
  all (plain, un-annotated optional properties, deliberately).

## 18. Tests added

77 new tests across 8 new test files, plus additions to the existing
Stage 5B persistence file:

| File | Count | Covers |
|---|---|---|
| `LongTermPlannerPersistenceTests.swift` | 10 | Goal/plan/PlannerDecision/TrainingMix/TrainingPhase round-trips |
| `ProgramCapabilityRegistryTests.swift` | 4 | Capability/instantiability gating |
| `LongTermPlannerProgramRecommendationTests.swift` | 7 | `proposeProgram` per system, capability gaps, determinism |
| `LongTermPlannerTrainingMixRankingTests.swift` | 13 | Two-stage ranking (5a/5b/5c), `proposeTrainingMix` per phase type |
| `LongTermPlannerStrategicPlanTests.swift` | 13 | Forward-fill, milestone anchoring, transition insertion, feasibility, acceptance |
| `LongTermPlannerRevisionTests.swift` | 8 | Extend/shorten/milestone-change/goal-change, lineage, history preservation |
| `TemporaryPreferenceAndModalitySwitchTests.swift` | 11 | Expiry/materiality detection, all 4 required modality switches, the 3 resolution paths |
| `TacticalWindowPolicyTests.swift` | 12 | Window sizing bounds, both date-driven triggers |

## 19. Full test count / result

**387/387 passing** (310 pre-Stage-5B baseline + 77 new). Zero failures,
zero skipped, across the full `TrainingOSTests` target on the real local
Xcode toolchain (`xcodebuild test`, iPhone 17 Simulator, iOS 26.5).

## 20. Simulator result

Schema changed (`PlannerDecision` added, `Goal`/`TrainingPlan` gained
fields), so the app was uninstalled and freshly installed on the
Simulator before final verification. Launched successfully (PID stayed
alive, no crash); the Today screen renders real seed data correctly
(two scheduled sessions: Lower A/Back Squat at 07:00, Evening Zone 2/Easy
Run at 18:00), confirmed via screenshot. No UI code was touched this
stage, so Plan/Progress were not separately re-verified beyond their own
existing, still-passing ViewModel test coverage.

## 21. Architectural issues found

None. Every stage of the existing pipeline from Program Generators onward
(`SchedulingPipeline`, `ConcurrentScheduler`, `GoalAlignmentEvaluator`)
worked exactly as documented with zero modification — confirmed, not
assumed, by having `proposeTrainingMix` call `SchedulingPipeline.propose`
directly and by having every generator call inside `proposeProgram` go
through the real, unmodified `HypertrophyProgramGenerator`/etc.

## 22. Known gaps / deferred work

- Resizing an already-`.active` phase's own remaining boundary in place
  (§16 above) — deferred, flagged at its call site.
- Shortening's "a later Maintenance/Recovery phase absorbs freed time
  first" redistribution detail (§16) — deferred in favor of a simpler,
  correct uniform-shift baseline.
- `TrainingMixComponent` has no `activityType` field, so
  `ModalityPreference.activityType`-level preference matching (e.g.
  "prefers cycling, not just any SteadyState") is honored only at the
  system level (`ProgrammingSystemKind`), not the activity level, in
  ranking; it is still used for display labeling in the Endurance Event
  candidate templates.
- `TACTICAL_PLANNING_HANDOFF.md` §3 ("starting a new phase" orchestration)
  and §4 (UI data contracts) were not built — no full tactical
  materialization pipeline or UI was in scope this stage.
- The 3-option resolution prompts for temporary-preference expiry/
  materiality (§11) are mechanically supported end-to-end but not wired
  into any UI or orchestrating use case that decides *when* to surface
  them — that requires the tactical-window-generation call site
  (§14's triggers feed it) that this stage intentionally did not build.
- HealthKit, backend sync, authentication, spreadsheet import, the full
  planning engine beyond what's described above, adaptive scheduling,
  missed-session recovery UI, functional-fitness timers, and AI features
  remain entirely out of scope, unchanged from prior stages.

## 23. Commit hashes

Recorded in the accompanying chat message after the final commit and
push (this document is written and committed together with the code it
describes, so the commit's own hash cannot be self-referenced inside
it).

## 24. Local/remote verification

Verified after push — `git rev-parse HEAD` and `git rev-parse origin/main`
confirmed equal, and `git status` confirmed a clean tree aside from the
normal local `xcuserdata`/workspace-state directories every prior stage
has also left untracked. See the accompanying chat message for the exact
hash and status output.
