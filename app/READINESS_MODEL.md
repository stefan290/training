# Readiness Model (Stage 8A design — not yet implemented)

Defines what a pre-workout readiness check-in captures, how it's scaled,
and how it's persisted. No SwiftData entity described here exists yet —
this document specifies the intended shape for Stage 8B's approval.

## 0. What already exists (do not duplicate)

A full-repo audit found **zero** existing readiness/fatigue/soreness/pain
concept anywhere in `PerformanceProfile`, `Domain/ValueTypes/`, or
elsewhere (grep for `soreness|fatigue|readiness|RPE|stiffness|pain|injury`
returns no real hits). The closest existing things, and why none of them
already are a readiness model:

- **`ExercisePrescription.autoregulationRating`** (`Int?`, -1/0/+1) —
  collected via `HypertrophyFeedbackView` **after** sets are logged,
  feeding only **next week's** set count (`StrengthProgressionEngine
  .resolveSetCount`'s `.autoregulated` case). Post-hoc, not pre-workout;
  feeds progression, not same-day execution.
- **`SteadyStateResult.rpe`/`IntervalResult.rpe`** (1-10) — entered via a
  `Stepper` **after finishing**. Also post-hoc.
- **`SessionCompletionContext`/`BlockCompletionContext`** (`.full`/
  `.partial`) — "how much was done," an execution-outcome fact, not a
  pre-workout input.

None of these can be reused as a pre-workout signal; they answer a
different question at a different time. The readiness model below is
genuinely new, but reuses the *shape* of existing patterns wherever one
already fits (see §4).

## 1. What is asked — three tiers, not one flat questionnaire

**REVISED per D2 approval-with-modification:** stiffness is no longer
folded into "overall recovery." Pain and stiffness are semantically
distinct signals in the domain model (§2), even though the UI reaches
both through one shared gateway question, to keep the fast path fast.

**Tier 0 — always asked, ~3 taps, no free text:**
- Sleep (poor / ok / good)
- Energy (low / normal / high)
- Overall recovery (fresh / normal / sore) — general, whole-body training
  soreness only; carries no pain or stiffness information

**Tier 0.5 — one fast gateway, always asked, single tap:**
- **"Pain or stiffness today?"** — Yes / No.
- **No** → continue immediately. This is what keeps the common day at
  4 taps total (~10-15 seconds), not a growing list of always-asked
  questions per new signal.
- **Yes** → Tier 1 opens (below). Still fast, still scoped to today's
  own session — never a general medical intake.

**Tier 1 — conditional, shown only when Tier 0.5 = Yes:**
- A choice of **which kind**: *pain/injury* and/or *stiffness/mobility
  limitation* (not mutually exclusive — a user can report both) —
  these remain two distinct, separately-recorded reports even though one
  gateway question surfaced both (§2).
- For whichever kind(s) are chosen: **affected body area(s)**, selected
  from muscle groups **today's own already-materialized session actually
  trains** (cross-referenced via each block's `ExercisePrescription
  .exercise.primaryTargets`/`MuscleGroup` — never a generic full-body
  map; see §5).
- **Local soreness** (distinct from the Tier 0.5 gateway) still surfaces
  separately if Tier 0's overall-recovery answer is "sore," using the
  same session-scoped body-area picker — soreness never needs the pain/
  stiffness gateway to be reached, and vice versa.

This shape keeps the common (nothing wrong) day at 4 single taps —
3 Tier-0 answers + 1 "No" on the gateway — while still reaching pain
and stiffness as genuinely separate, specific reports the moment
either is actually relevant. No severity slider, no free text, no
medical intake anywhere in this flow.

## 2. Soreness vs. pain vs. stiffness — three distinct signals, never merged

**REVISED per D2:** three signals, not two, all independently
representable in the domain model:

- **Soreness** (Tier 0 "overall recovery" + its own local follow-up) is a
  *normal training-recovery* signal — expected, self-resolving, and
  handled the same way regardless of cause.
- **Pain/discomfort** is a *potential movement-limitation* signal — it
  triggers more conservative handling (substitution before load
  reduction — see `READINESS_DECISION_MODEL.md`) and **is never
  auto-inferred from a soreness or stiffness answer**.
- **Stiffness/mobility limitation** is distinct from both — it does not
  today drive a different Stage 8B adaptation than pain does (both are
  handled conservatively), but it is recorded as its own tagged signal
  specifically because it's expected to drive *different* future
  behavior: warm-up/mobility selection, and its own line in longitudinal
  analysis ("recurring stiffness in the same area" is a different
  finding than "recurring pain there"). Collapsing it into pain or
  soreness now would make that future distinction unrecoverable without
  a data migration — exactly what D10 requires avoiding.

A user reporting "sore" chest from Monday's session must never be
silently treated as if they'd reported shoulder pain or shoulder
stiffness, and none of the three ever gets inferred from either of the
other two. Distinct fields, distinct reason-code inputs (`READINESS_DECISION_MODEL.md`
§6), never collapsed into one scale, regardless of how the UI groups
the initial ask.

The app records what the user reports and picks a more conservative
action from it — **it never claims to diagnose an injury.** No medical
taxonomy, no severity/diagnosis vocabulary is introduced; only the
existing `MuscleGroup`/`MovementFunction` vocabulary is used to say
*which already-known exercise tag* the report concerns.

## 3. Scale

All three Tier-0 inputs and the pain toggle use a plain 3-value ordinal
(never a 1-10 slider, never free text) — reusing the exact shape
`HypertrophyFeedbackCopy.options` already established for autoregulation
feedback (-1/0/+1), for interaction-pattern consistency, not because a
3-point scale is scientifically special. **TRAININGOS-DESIGNED, not a
validated instrument** — same discipline this repo already applies to
every other illustrative default (`PhaseDurationDefaults`,
`TacticalWindowPolicy.fallbackWindowWeeks`, etc.).

Local soreness/pain are not scaled at all beyond "reported" — they are a
*which body area* selection (multi-select from today's own session
targets), not a severity score. Severity language ("how much does it
hurt") is exactly the medical-questionnaire territory §2/§3 of the
brief explicitly says to avoid.

## 4. Persistence — a new, transient, per-Session entity

Proposed (not yet created): `ReadinessCheckIn`, one-to-zero-or-one from
`Session` (`Session.readinessCheckIn: ReadinessCheckIn?`), mirroring
exactly how `SessionCompletionContext` already hangs an optional,
execution-time fact off `Session` without becoming a new `SessionStatus`
case.

```
ReadinessCheckIn (proposed, Stage 8B)
  id: UUID
  recordedAt: Date
  sleep: ReadinessLevel?            // .poor/.ok/.good, nil = not answered
  energy: ReadinessLevel?
  overallRecovery: ReadinessLevel?
  soreMuscleGroups: [MuscleGroup]   // empty = none reported, distinct from "not asked"
  reportedPain: [MuscleGroup]       // empty = none reported -- kept SEPARATE from stiffness (D2)
  reportedStiffness: [MuscleGroup]  // empty = none reported -- kept SEPARATE from pain (D2)
  session: Session?
```

**REVISED per D2:** `reportedPain` and `reportedStiffness` are two
separate arrays, not one combined "pain or stiffness" field — this is
the exact schema expression of "must remain semantically distinct even
if the UI combines their initial gateway." The UI's single Yes/No
gateway question controls whether Tier 1 opens at all; once open, it
writes into whichever of these two fields (or both) the user actually
selects. Neither field is ever populated by inference from the other,
from `soreMuscleGroups`, or from `overallRecovery`.

**Why a new entity, not new fields directly on `Session`:** `Session` is
already documented (`WORKOUT_EXECUTION.md`) as "materialized historical
snapshot + own bookkeeping" — a readiness report is a distinct kind of
fact (what the user *said*, not what the session *is*), and keeping it
as its own type means it can be `nil`-absent cleanly, extended later
without widening `Session` itself, and reasoned about independently in
tests (matching the existing `PlannerDecision`-as-its-own-type
precedent rather than bloating an owning entity with parallel optional
fields).

**Why per-Session, not per-block/modality:** see design question 4 in
`STAGE8A_DECISION_MEMO.md` — decided here as per-Session, flagged there
for explicit confirmation since it's a real product choice, not a
foregone technical conclusion.

## 5. Missing vs. neutral — never conflated

Readiness is optional (design question 13) end to end:

- **Skipped entirely** → `ReadinessCheckIn` is `nil` on the Session, or
  every field on a recorded-but-empty check-in is `nil`/empty. This must
  render and reason identically to "nothing to say here" — never
  defaulted to `.ok`/"fine," which is a real, distinct, reportable
  answer a user can actually choose.
- **Answered "ok"/"good"/"fine"** → a genuine value, persisted as such.

Any adaptation-decision logic that reads a `nil` field must treat it as
"no signal available," never silently substitute a neutral value in its
place — this is what keeps a later explanation ("you reported low
energy") honest; it must never be shown when the user reported nothing
at all.

## 6. Transient vs. historical

A `ReadinessCheckIn` is a **permanent record of what was reported that
day** (like a `SetResult` — never deleted, never overwritten after the
fact per §7 below) but is **not** aggregated into `PerformanceProfile`
and does **not** feed `LongTermPlanner` automatically in Stage 8B — no
threshold, no automatic strategic-plan change (D10). Stage 8 (per the
brief's own point 6) solves same-day adaptation only.

**D10 requirement — persisted in analyzable form now, even though no
analysis is built yet.** Every field above is a typed, closed value
(`ReadinessLevel` ordinal, `MuscleGroup` array) rather than free text or
a derived/computed summary — this is precisely what lets future
longitudinal queries (repeated poor sleep, repeated low energy,
recurring pain or stiffness *in the same area*, etc.) run directly
against this history later **without a schema migration or any
reconstruction of missing information**. A seam for *cumulative*
readiness evidence eventually surfacing to the strategic layer is
designed in `READINESS_DECISION_MODEL.md` §5 — deliberately still
design-only, no threshold chosen, nothing wired to `LongTermPlanner` in
Stage 8B.

## 7. Can the user change their answer after starting?

No new mutation path is designed for editing a `ReadinessCheckIn` once
the resulting adaptation proposal has been acted on (accepted, rejected,
or the session started) — matching the existing "a completed/logged fact
is a historical snapshot" discipline applied everywhere else in this
app. If the user's condition changes mid-session (design question 12),
that's a *new* signal for a *new* moment, not a retroactive edit — Stage
8B should treat it as an in-session pause/adjustment interaction, out of
this design's scope unless you want it pulled in explicitly.
