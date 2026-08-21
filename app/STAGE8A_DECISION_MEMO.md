# Stage 8A Decision Memo

**STATUS: APPROVED, WITH AMENDMENTS, by the product owner.** This memo
now records the *final approved* state for each decision, not the
original pre-approval recommendations — where the approved decision
differs from what was originally recommended here, that's called out
explicitly. `READINESS_MODEL.md`, `READINESS_DECISION_MODEL.md`,
`READINESS_ADAPTATION_PIPELINE.md`, `READINESS_PROGRESSION_CONTRACT.md`
and `READINESS_UX_FLOW.md` have all been updated to match. Stage 8B
implementation has **not** started — see `STAGE8B_IMPLEMENTATION_PLAN.md`
for the resulting plan, which is itself still awaiting a separate,
explicit go-ahead before any code is written.

## Decisions — final approved state

**1 (D1). Which check-in inputs are always asked vs. combined?**
**Approved as originally recommended:** 3 always-asked Tier-0 inputs
(sleep, energy, overall recovery — "overall recovery" means general
whole-body training soreness only, no pain/stiffness information).
**Amended (D2) on how pain/stiffness are reached:** stiffness is
**not** folded into "overall recovery" — see item 2 below.

**2 (D2 — AMENDED). How pain/stiffness are reached, and kept distinct.**
**Not** folded into "overall recovery." Pain/injury and stiffness/
mobility limitation are **two separate, always-distinguishable signals
in the domain model** — `reportedPain: [MuscleGroup]` and
`reportedStiffness: [MuscleGroup]`, two arrays, never one combined field
— because they're expected to drive different future behavior
(substitution vs. warm-up/mobility selection vs. longitudinal analysis).
The fast path stays 4 taps: 3 Tier-0 answers + one Tier 0.5 gateway tap
("Pain or stiffness today?" Yes/No). Only a "Yes" opens Tier 1, where the
user identifies which kind(s) (not mutually exclusive) and the affected
body area(s). See `READINESS_MODEL.md` §1/§2/§4,
`READINESS_UX_FLOW.md` §1-2.

**3 (D3). The 3-point ordinal scale.**
**Approved as recommended:** reuses the exact shape
`HypertrophyFeedbackCopy.options` already established (-1/0/+1) for
interaction-pattern consistency, tap-based, no sliders.
TRAININGOS-DESIGNED, not a validated instrument, same as every other
illustrative default in this repo.

**4 (D1). Readiness assessed per-Session, not per-block/modality.**
**Approved as recommended:** per-Session. A mixed-modality session (e.g.
Strength + Functional Fitness same day) still gets one check-in, whose
Tier-1 local-soreness follow-up already scopes itself to whichever
muscle groups that day's specific blocks touch — per-block would
multiply the already-tight time budget without a clear benefit, and
would need per-block-type branching UI logic that CLAUDE.md rule 7
explicitly warns against.

**5 (D4). New entity: `ReadinessCheckIn`.**
**Approved.** Shape in `READINESS_MODEL.md` §4 — a new, additive
SwiftData entity, one-to-zero-or-one from `Session`. A skipped check-in
must remain distinguishable from a completed one where every signal was
good (§5 of that document).

**6 (D8). New entity: `ReadinessAdaptationDecision`.**
**Approved.** Shape in `READINESS_PROGRESSION_CONTRACT.md` §2 — its own
dedicated entity, a sibling to `PlannerDecision`, not an extension of it.
Must preserve full explainability: for every material readiness
adaptation, the chain original prescription → readiness signal →
adaptation decision → adapted prescription → accept/reject → actual
performed result must be reconstructable, and history is never
overwritten.

**7 (D7). New `SubstitutionReason` case for readiness-triggered substitution.**
**Approved as recommended:** one new shared case (e.g.
`.readinessAdaptation`). The *specific* trigger (pain vs. stiffness vs.
soreness, and which body area) lives on the readiness/adaptation
decision record (`ReadinessAdaptationDecision.triggeringSignals`, §6
below), not by exploding `SubstitutionReason` into many cases.

**8 (D9). Level 2 (load/rep/RIR/set adjustment) provenance-vs-progression safety.**
**Audit performed and resolved — required before Level 2, approved
gate.** Full trace of `RecordSetResultUseCase`, `ExercisePerformanceProfile`,
`PerformanceProfileStore`, `DoubleProgressionEngine`, and
`CompleteSessionUseCase.progressionPreview` found: `PerformanceProfile`'s
own confidence/`estimatedOneRepMax` fields have **no live-update logic
anywhere** (set only at construction) — that specific risk doesn't exist.
The **real, confirmed** risk is `CompleteSessionUseCase.progressionPreview`
(≈line 75) basing its next-weight suggestion on `loggedResults.last?.weight`
— the actual just-performed weight — with no awareness of whether
today's prescription was readiness-adapted, plus an analogous risk in
`AutoregulationRatingResolver.previousWeekSetCount` if a future Level 2
set-count reduction ever physically shrinks `SetPrescription` rows. Full
detail and the two required fixes: `READINESS_PROGRESSION_CONTRACT.md`
§3. **Level 2 may not ship until both fixes are implemented and tested.**

**9 (D6 — AMENDED). Which levels ship in Stage 8B.**
Levels 0, 1, 3, 6 ship directly; **4 ships directly too** (not merely "as
a small additive reason" — `BlockCompletionContext.partial` already
models it cleanly, confirmed implementable without inventing new
programming science); 2 ships only once item 8's two fixes are in place.
**Level 5 is explicitly NOT deferred indefinitely** — it is classified as
**DEFERRED TO A DEDICATED FUTURE STAGE**: a "shorter/lower-demand version
of today's workout" is recognized as an important future capability: the
reason for deferral is that it needs an explicit per-programming-system
policy decision (what a legitimate lower-demand variant means per
system) that must not be invented inside Stage 8. See
`READINESS_DECISION_MODEL.md` §4 for the seam Stage 8B preserves so
Level 5 reuses the same architecture later.

**10 (D10 — AMENDED). The materiality seam toward `LongTermPlanner`.**
**No automatic threshold in Stage 8B** — Stage 8B does not implement
anything like "N poor sessions out of M changes the annual plan," and a
single poor-readiness day must never silently rewrite the strategic
plan. **What Stage 8B must do instead:** persist readiness and
adaptation history in a fully typed, closed-vocabulary form (never free
text, never a derived/pre-aggregated summary) so that future
longitudinal analysis — repeated poor sleep, low energy, poor recovery,
recurring pain or stiffness in the same area, repeated adaptations,
repeated skipped/postponed sessions — is possible **without a schema
migration or reconstructing missing history**. The seam toward
`LongTermPlanner` itself (what threshold, what prompt) stays
design-only, reusing `ADHERENCE_AWARE_PLANNING.md` §2a's materiality-check
pattern when it is eventually built. `READINESS_MODEL.md` §6,
`READINESS_DECISION_MODEL.md` §5.

**11 (D5). "Feeling great" must never authorize exceeding the plan.**
**Approved, no ambiguity:** a high readiness report can only ever affirm
the existing prescription (Level 0/1) — it never triggers Level 2+ in
the *upward* direction. Readiness may confirm, explain, reduce,
substitute, remove, or postpone — it must never become a second upward
progression engine. Progression engines remain the sole owner of planned
progression (item 12 below).

## Scoping confirmations (not really open questions, but stated for completeness)

**12. Load-over-reps progression principle** — belongs to the
progression engines themselves (`StrengthProgressionEngine`'s own
weight/rep resolution), not readiness. A separate future stage (a
progression-engine revision), explicitly not Stage 8 or this memo's
concern. Readiness adaptation's design keeps this compatible: adaptation
is always an overlay on an already-resolved value, never a
re-resolution, so a future load-over-reps redesign slots under it
unchanged.

**13. ~5-minute mobility warm-up** — not built in Stage 8A/8B, confirmed
out of scope. Architectural relationship, made explicit per the "preserve
the seams" requirement below: the newly-distinct `reportedStiffness`
signal (item 2) exists specifically so it can later inform warm-up
exercise selection once a warm-up feature exists — no warm-up domain
concept exists anywhere today (`TIMER_ARCHITECTURE.md` has no pre-workout
phase at all), so there's nothing to wire yet, but nothing in Stage 8B's
schema blocks wiring it in later without a migration.

**14. Manual/custom workout editing** — not built in Stage 8A/8B,
confirmed out of scope. Compatibility note, per "preserve the seams"
below: it should reuse the same "this-session-only,
template-graph-untouched" mutation scope, and the same
`ReadinessAdaptationDecision` architecture, that substitution and
(proposed) Level 2 adaptation already share — so the app doesn't end up
with two incompatible ways to edit a materialized session, and readiness
adaptation works identically whether the session came from a program or
was manually built.

## Product principle (stated by the product owner, governs Stage 8B UX)

Stage 8 should feel like TrainingOS intelligently helping execute
**today's plan**, not filling out a health questionnaire. Normal flow:
Start workout → very fast readiness check → usually "everything looks
good" → workout starts. Interaction expands only when something
meaningful is reported (low energy → possible small demand reduction;
shoulder pain → possible suitable substitution; significant general
fatigue → possible reduction or postpone). The system always explains
WHAT it changed and WHY, and the user always remains in control of
accepting the adaptation. This principle is what §1's fast path and §3's
"always show original + proposed, always require explicit accept" are
built to satisfy.

## Preserve the seams (explicit requirement — Stage 8B must not block these later)

Out of scope for Stage 8B, but Stage 8B's design must not architecturally
block any of these:

- **~5-minute session-specific mobility warm-ups** — enabled by keeping
  `reportedStiffness` a distinct, queryable signal now (item 13).
- **Load-over-reps progression redesign** — enabled by adaptation always
  being an overlay, never a re-resolution (item 12).
- **Manual/custom workouts** — enabled by readiness adaptation being
  scoped to the materialized `Session`/`WorkoutBlock` graph, not to
  "came from a `ProgramDefinition`" (item 14).
- **Level 5 lower-demand methodology variants** — enabled by
  `ReadinessAdaptationDecision`'s signal-source/action-kind shape being
  designed to accept a new `ReadinessActionKind` case later, reusing the
  same pipeline and provenance record rather than a parallel mechanism
  (item 9, `READINESS_DECISION_MODEL.md` §4).
- **Automatic strategic-plan changes from repeated readiness** — enabled
  by persisting readiness/adaptation history in fully typed, closed,
  query-ready form now, even though no analysis runs on it yet (item 10).
- **Training Environment / Equipment Profile** (new — see item 15
  below): enabled by keeping `ReadinessAdaptationDecision`
  readiness-specific and never coupling the shared substitution/
  block-reduction/postpone mechanisms exclusively to it, so a future
  environment-constraint decision can reuse the same mechanisms through
  its own sibling provenance type.

**15. Training Environment / Equipment Profile** — not built in Stage
8A/8B, confirmed out of scope. TrainingOS will later support persistent
environments (Commercial Gym, Home Gym, Hotel Gym, Travel/Minimal
Equipment) describing available equipment, equipment capacity, and
physical/environmental constraints (ceiling height, no overhead
movements, floor space, etc.), combining with strategic phase/program
intent and readiness to produce an executable session. **Architectural
distinction that governs Stage 8B:** readiness answers "what is
appropriate for this user today"; training environment answers "what is
physically executable at this location" — different constraint sources,
even when both resolve through the same exercise-substitution mechanism.
`ReadinessAdaptationDecision` stays readiness-specific; a future
environment feature gets its own sibling decision/provenance type, never
an extension of it. Full detail: `READINESS_DECISION_MODEL.md` §7.

## The 17 design questions — direct answers

1. **What readiness concepts already exist?** None. Closest analogs
   (`autoregulationRating`, `SteadyStateResult.rpe`/`IntervalResult.rpe`)
   are post-hoc, feed only future-week progression, not same-day
   execution — see `READINESS_MODEL.md` §0.
2. **What new persisted data is actually necessary?** Two new entities
   (`ReadinessCheckIn`, `ReadinessAdaptationDecision`), one new
   `SubstitutionReason` case, two new factored reason-code enums
   (`ReadinessSignalSource`, `ReadinessActionKind` —
   `READINESS_DECISION_MODEL.md` §6) — see items 5-7 above.
3. **Where does readiness attach?** A new entity, one-to-zero-or-one
   from `Session` — see item 4/`READINESS_MODEL.md` §4.
4. **Once per session or per block/modality?** Once per Session — item 3.
5. **How does local soreness/pain identify body areas?** Reuses the
   existing `MuscleGroup`/`MovementFunction` vocabulary via
   `Exercise.primaryTargets`, scoped to what today's own session
   actually trains — no new anatomical taxonomy. `READINESS_MODEL.md` §1/§5.
6. **Interaction with exercise substitution?** Fully reuses
   `substituteThisSessionOnly` on the existing use cases — Level 3 is
   the one level requiring zero new mutation mechanism, only a new
   reason case.
7. **Which engines can already support load/set/RIR adaptation?** The
   *computation* exists in `StrengthProgressionEngine`'s pure resolvers;
   the *safe mutation path* does not — see `READINESS_DECISION_MODEL.md`
   §3 and item 8 above.
8. **Which adaptations require new training-science policy?** Level 5
   only (item 9). Levels 0-4 and 6 are engineering/provenance work
   against already-decided methodology, not new policy.
9. **How do we prevent readiness from corrupting progression history?**
   Adaptation is an overlay, never a re-resolution — week N+1 always
   chains from week 1's original resolved value, unaffected by a same-day
   adaptation. See `READINESS_PROGRESSION_CONTRACT.md` §3 for the
   confirmed D9 audit and its two required fixes (item 8 above).
10. **Prescribed vs. adapted vs. overridden vs. performed?** Four
    always-distinguishable states — `READINESS_PROGRESSION_CONTRACT.md` §1.
11. **App closes after readiness but before/during workout?** The
    persisted `ReadinessCheckIn` (step 3 of the pipeline) is durable
    immediately, before the recommendation screen or the start
    transition — a crash loses at most the in-progress recommendation
    review, never the reported readiness itself (CLAUDE.md rule 20).
12. **Can the user change readiness answers after starting?** No edit
    path is designed — a changed condition mid-session is a new signal
    for a new moment, not a retroactive edit. `READINESS_MODEL.md` §7.
13. **Should readiness be optional?** Yes, always — `READINESS_UX_FLOW.md` §4.
14. **How should "I feel great" affect training?** Never authorizes
    exceeding the plan — item 10.
15. **How does repeated poor readiness surface to `LongTermPlanner`?**
    Not automatically, ever, in Stage 8B (D10) — history is persisted in
    analysis-ready form now; the seam itself stays designed, not built.
    Item 10.
16. **Per-modality behavior?** `READINESS_DECISION_MODEL.md` §3 — full
    breakdown for Hypertrophy/Strength, Steady State, Interval,
    Functional Fitness.
17. **8B vs. deferred?** See "Approved Stage 8B implementation boundary"
    below, and `STAGE8B_IMPLEMENTATION_PLAN.md` for the full plan.

## Approved Stage 8B implementation boundary

**In scope for 8B:** `ReadinessCheckIn` entity + the 4-tap fast/targeted
UX flow (Tier 0 + Tier 0.5 gateway + conditional Tier 1, D2),
`EvaluateReadinessAdaptationUseCase` for Levels 0/1/3/4/6, one new
`SubstitutionReason` case, the factored `ReadinessSignalSource`/
`ReadinessActionKind` reason-code pair, and Level 2 gated on the two
required fixes from the (now-completed) D9 audit
(`READINESS_PROGRESSION_CONTRACT.md` §3).

**Deferred, explicitly, past 8B (seams preserved, not blocked — see
"Preserve the seams" above):** Level 5, deferred to a dedicated future
stage, not shelved; the materiality seam to `LongTermPlanner` (designed,
history persisted in a form that supports it, not built); warm-up;
manual/custom workout editing; load-over-reps progression-engine work.

Implementation itself requires a separate, explicit go-ahead — see
`STAGE8B_IMPLEMENTATION_PLAN.md`.

## Files added this stage

`READINESS_MODEL.md`, `READINESS_ADAPTATION_PIPELINE.md`,
`READINESS_DECISION_MODEL.md`, `READINESS_PROGRESSION_CONTRACT.md`,
`READINESS_UX_FLOW.md`, `STAGE8A_DECISION_MEMO.md`,
`STAGE8B_IMPLEMENTATION_PLAN.md` — all new, all at the repo root
alongside the existing Stage 5-7 design docs. No existing file was
modified. No SwiftData entity, use case, or UI was added — Stage 8A is
documentation only, as instructed. `ARCHITECTURE.md` was not touched:
nothing in it currently claims readiness support, so there's nothing
inaccurate to correct, and adding a "proposed, not built" section there
would duplicate what these seven documents already say more precisely.

## Test impact

None. No code changed. The full suite (651 tests, last verified at the
Stage 7 close) is unaffected by this stage.
