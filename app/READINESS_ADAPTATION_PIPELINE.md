# Readiness Adaptation Pipeline (Stage 8A design — not yet implemented)

Exact flow from tapping Start to an adapted (or unchanged) prescription,
and which existing components own which step. No new mechanism is
introduced where an existing one already fits.

## 0. Where this attaches to the existing state machine

`SESSION_STATE_MACHINE.md` §3: `scheduled --[Start]--> inProgress` is a
direct transition today — no pre-session state exists, and this design
**does not add one**. Instead, the check-in + adaptation flow is a
**view-layer gate shown before the existing start-transition call
fires** — the exact same shape `SessionDetailView.swift` already uses at
the *other* end of a session (its `.fullScreenCover` presenting
`HypertrophyFeedbackView` before `finish(context:)` actually runs). This
is Type-A reuse of an established pattern, not a new domain-layer
concept: `SessionStatus` keeps its existing 6 cases, unchanged.

## 1. Pipeline

```
1. User taps "Start" on a scheduled Session (TodayView/WeekView, unchanged entry point)
2. NEW: ReadinessCheckInView presented (fullScreenCover-shaped, matching
   HypertrophyFeedbackView's own precedent) — Tier 0 (3 taps), then the
   Tier 0.5 gateway ("Pain or stiffness today?", 1 tap), then Tier 1 only
   if the gateway is answered Yes (`READINESS_MODEL.md` §1) — pain and
   stiffness are captured as two separate reports even though one
   gateway question surfaces both (D2)
3. User submits (or explicitly skips) -> ReadinessCheckIn persisted
   (or left absent) on the Session, via a new, small use case:
   RecordReadinessCheckInUseCase.record(session:checkIn:modelContext:)
   -- mirrors RecordAutoregulationFeedbackUseCase's own
   "persist immediately, single save()" discipline (CLAUDE.md rule 20)
4. NEW: EvaluateReadinessAdaptationUseCase.evaluate(session:checkIn:) 
   -> ReadinessAdaptationProposal (never persisted unless accepted --
   mirrors the existing propose-never-mutate shape already used by
   CandidateTrainingMix / ScheduleProposal / GeneratorParameters candidates)
5. IF the proposal is empty (Level 0, no meaningful signal): skip
   straight to step 7 -- no recommendation screen shown at all. This is
   the "minimal friction on a normal day" requirement, not an
   afterthought.
6. IF the proposal is non-empty: present it (READINESS_UX_FLOW.md) --
   user accepts / keeps original / (where a valid alternative exists)
   chooses a different one, per item
7. Apply ONLY what the user accepted, via EXISTING mutation mechanisms
   (see §2) -- then the existing Start transition fires exactly as it
   does today (scheduled -> inProgress), unchanged.
8. Workout executes normally. Every result the user logs is attributed
   against whichever prescription is now in effect (adapted or
   original) -- see READINESS_PROGRESSION_CONTRACT.md for how this stays
   distinguishable from an unexplained deviation.
```

## 2. Ownership boundaries — who is allowed to change what

Per `WORKOUT_EXECUTION.md`'s existing data-ownership table (`ProgramDefinition`
holds methodology and is never touched here; `ProgramInstance` holds this
user's execution context/overrides; materialized `Session`/`WorkoutBlock`/
`*Prescription` is a historical snapshot execution code may not mutate to
reflect what happened, with exactly one named exception today —
this-session-only substitution):

| Adaptation action | Existing owner | New wiring needed |
|---|---|---|
| Explain/confirm prescription (Level 1) | Display only, reads already-materialized data | None |
| Substitute exercise/activity (Level 3) | `SubstituteExerciseUseCase.substituteThisSessionOnly` / `SubstituteActivityUseCase.substituteThisSessionOnly` — **already exists, already tested** | One new `SubstitutionReason` case |
| Adjust load/reps/RIR/set count (Level 2) | No existing "this-session-only" mutation path for `SetPrescription`/`ExercisePrescription` numeric fields — today only "substitute the exercise" has this scope, not "adjust its targets" | New, additive schema (`READINESS_PROGRESSION_CONTRACT.md`) + new use case |
| Skip a block (Level 4) | `BlockCompletionContext.partial` already exists as a concept ("how much was done" independent of "is it finished") — reusable for "this block was skipped for a reported reason" | A reason attached to an already-possible partial completion, not a new completion concept |
| Recommend skip/postpone (Level 6) | `SessionStatus.skipped`/`.missed` already exist | A reason surfaced through the existing missed-session flow |

`EvaluateReadinessAdaptationUseCase` **asks each block's own programming
system what it can support** (Level 2's exact shape differs by system —
see `READINESS_DECISION_MODEL.md` §3) rather than hard-coding one
generic edit for every modality — this directly answers the brief's
"ask the underlying programming system what is allowed rather than
blindly editing prescriptions."

**Level 5 is intentionally absent from this table** — "convert to a
lower-demand methodology variant" is deferred to a dedicated future
stage, not built here (`READINESS_DECISION_MODEL.md` §4). This pipeline
and the `ReadinessAdaptationDecision` record it produces (§6 of that
document) are designed so Level 5, when it ships later, is a new row in
this same table and a new `ReadinessActionKind` case — not a second
pipeline or a second provenance mechanism.

**Readiness is not assumed to be the only source of session-local
adaptation (explicit future constraint, `READINESS_DECISION_MODEL.md`
§7).** A future Training Environment / Equipment Profile feature
(deferred, not built in Stage 8B) will need this exact table's "Existing
owner" column again — the same `SubstituteExerciseUseCase
.substituteThisSessionOnly`, `BlockCompletionContext.partial`, and
`SessionStatus.skipped`/`.missed` mechanisms — driven by an equipment/
environment constraint rather than a readiness signal. Stage 8B's
implementation of this pipeline must call these mechanisms in a way that
accepts a provenance reference (today: a `ReadinessAdaptationDecision`)
rather than being hard-wired to assume readiness is the only possible
caller — so a later environment-constraint pipeline can reuse the same
"existing owner" row with its own sibling provenance type, without
retrofitting this one.

## 3. What this pipeline never does

- Never re-runs `StrengthProgressionEngine`/`SteadyStateProgressionEngine`/
  `IntervalProgressionEngine`'s own week-level resolution — those stay
  exactly what they are today (materialization-time, per-week). A
  same-day adaptation is an *overlay* on top of an already-resolved
  prescription, never a re-invocation of the resolver with different
  inputs.
- Never touches `ProgramDefinition`, `TemplateSession`, or any other
  part of the template graph — an adaptation is scoped to the one
  already-materialized `Session`, exactly like `substituteThisSessionOnly`
  already is.
- Never advances or blocks the tactical window, phase, or strategic plan
  — `LongTermPlanner`/`TacticalWindowPolicy` are untouched by anything in
  this pipeline (see `READINESS_DECISION_MODEL.md` §5 for the one
  explicitly-designed, explicitly-deferred seam toward that layer).
- Never fabricates a `SetResult`/`SteadyStateResult`/etc. — only real
  recording use cases, called by the user actually performing and
  logging, ever create one, unchanged.
