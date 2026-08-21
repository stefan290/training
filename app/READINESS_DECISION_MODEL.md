# Readiness Decision Model (Stage 8A design — not yet implemented)

The adaptation hierarchy, what the current architecture can already
support at each level, per-modality differences, and the reason-code
design. Per the brief: **not all levels are assumed for V1** — this is
an audit-then-recommend document, not a claim that everything below
ships in Stage 8B.

## 1. The hierarchy, audited against current architecture

| Level | Action | Supported today? |
|---|---|---|
| 0 | No change | Yes — trivially, it's the default |
| 1 | Explain/confirm prescription | Yes — pure display of already-materialized data, no domain change |
| 2 | Adjust load/reps/RIR/set count within the prescription | **Partially.** The *computation* exists (`StrengthProgressionEngine`'s resolvers are pure functions of inputs already available); the *safe, this-session-only mutation path* does not — see §3 and `READINESS_PROGRESSION_CONTRACT.md` |
| 3 | Substitute an exercise/activity | **Yes, fully**, via `substituteThisSessionOnly` on `SubstituteExerciseUseCase`/`SubstituteActivityUseCase` — already built, already tested. Needs one new `SubstitutionReason` case only |
| 4 | Reduce/remove a block or exercise | **Yes, in scope for 8B** — `BlockCompletionContext.partial` already models "less than the full block happened"; a readiness-triggered removal attaches a reason to this already-existing completion concept. Confirmed implementable without inventing new programming science: omitting a whole block/exercise for today never has to answer "what does a lower-demand *variant* of this methodology mean" (that's Level 5's question, not this one) |
| 5 | Convert session to a lower-demand *methodology* variant | **No** — this is a genuinely new, per-programming-system training-science question (analogous to Stage 7's Maintenance dose-reduction decision), not an engineering gap. **DEFERRED TO A DEDICATED FUTURE STAGE**, not indefinitely — see §4 |
| 6 | Recommend postpone/skip | **Yes, fully** — `SessionStatus.skipped`/`.missed` already exist; only needs a reason surfaced through the existing flow |

**Approved Stage 8B scope (D6):** Levels 0, 1, 3, 4, 6 ship directly.
Level 2 ships **only after** the `READINESS_PROGRESSION_CONTRACT.md` §3
audit's two confirmed fix points are addressed (this audit is now done —
see that document). **Level 5 is out of Stage 8B, classified as
DEFERRED TO A DEDICATED FUTURE STAGE** — not because the capability is
undesirable (a "shorter/lower-demand version of today's workout" is
explicitly recognized as an important future capability), but because it
requires an explicit per-programming-system policy decision this stage
must not invent. See §4.

## 2. Precedence — least disruptive that adequately addresses the signal

Evaluation always proceeds low-to-high and **stops at the first level
that adequately addresses every reported signal** — it never jumps to a
more disruptive action when a less disruptive one already covers it.
Concretely: reported pain in one specific area that only affects one
exercise resolves at Level 3 (substitute that one exercise), never
escalates to Level 6 (skip the whole session) merely because *something*
was reported. Escalation only happens when a lower level genuinely
cannot address the signal (e.g. pain reported in a body area touched by
*every* exercise in the session, or overall recovery poor enough that no
single substitution/reduction addresses it) — this is a deterministic,
rule-based evaluation order, never a black-box score.

## 3. Per-modality differences — the adaptation layer asks, never assumes

`EvaluateReadinessAdaptationUseCase` queries each block's own
`ProgrammingSystemKind` for what it supports, rather than applying one
generic edit everywhere:

- **Hypertrophy/Powerlifting** — Level 2 is the most natural fit here:
  `SetPrescription.targetWeight`/`repRangeLow/High`/`targetRir` and
  `ExercisePrescription`'s own set count are all individually addressable
  fields already. A reduced-load or reduced-set-count adaptation reads
  cleanly onto this system's existing shape.
- **Steady State** — prescriptions are duration/distance/intensity, not
  sets. A Level-2-equivalent here means reducing today's duration/
  intensity target. Critically, this must be a same-day-only overlay
  and must **never** feed back into `SteadyStateProgressionEngine`'s own
  `weekIndex`-driven resolution, which is deliberately *not*
  feedback-dependent by design (confirmed: no live-feedback parameter
  exists in this engine at all) — the adaptation layer must respect that
  boundary, not quietly punch a hole in it.
- **Interval** — same shape as Steady State, plus one wrinkle: when
  `requiresSuccessfulCompletionToProgress` is set, a readiness-adapted
  (intentionally reduced) session must be marked so it is **not**
  mistaken for a failed-to-complete outcome by that gate. This needs the
  same adaptation-provenance flag `READINESS_PROGRESSION_CONTRACT.md`
  proposes.
- **Functional Fitness** — no dedicated progression engine was found in
  this audit. Its existing Rx-vs-Scaled execution-context distinction is
  a promising, already-built hook for a readiness-driven scaling
  decision, but this needs its own focused audit before Stage 8B commits
  to a specific mechanism — flagged, not resolved here.

Strict methodologies stay strict: nothing here overrides a programming
system's own rules about what varies and what doesn't. If a system
reports "no Level 2 support," the adaptation layer's next option is
Level 3, never a forced edit the system itself doesn't expose.

## 4. Level 5 — deferred to a dedicated future stage, not shelved

"Convert to a lower-demand version of the same methodology" requires
answering, per system, "what does a lower-demand Hypertrophy/Strength/
Functional Fitness/Steady State session actually mean" — fewer
exercises? A flat set reduction across the board? A different session
template entirely? This is not an engineering question; it's the exact
shape of training-science policy decision Stage 7 hit with Maintenance's
dose-reduction rule, and per this repo's own discipline (CLAUDE.md rule
10), it should not be answered inside a readiness feature without an
explicit decision. **Classification: deferred to a dedicated future
stage** — the feature is wanted, the decision just doesn't belong here.

**Preserving the seam for later (explicit requirement):** when Level 5
is eventually designed, it should reuse the same `ReadinessAdaptationDecision`
provenance entity (`READINESS_PROGRESSION_CONTRACT.md` §2) and the same
signal-source/action-kind reason-code shape (§6 below) that Levels 2-4
already use — nothing about Stage 8B's design should force a second,
incompatible decision-record type for Level 5 later. Concretely: adding
a new `ReadinessActionKind` case (e.g. `.sessionConvertedToLowerDemand`)
to the existing enum, once the per-system policy exists, is the expected
extension path — not a new parallel mechanism.

## 5. The seam toward the strategic layer — designed, not built

Repeated poor readiness should eventually be visible to `LongTermPlanner`
without today's single check-in ever rewriting the annual plan, current
phase, `TrainingMix`, or any `ProgramInstance`. This repo already has the
*exact* pattern for "cumulative signal surfaces a prompt at the next
natural checkpoint, never a same-day silent change":
`ADHERENCE_AWARE_PLANNING.md` §2a's materiality check — a temporary
mix's cumulative duration crossing a threshold surfaces a distinct,
`PlannerDecision`-backed, three-option prompt (`TEMPORARY_PREFERENCE_MATERIALITY_THRESHOLD`)
at the next tactical-window generation, never an automatic conversion.

Proposed (design only, not built): a new permitted input added to §4's
"adherence-signal boundary" list — accumulated `ReadinessCheckIn` history
(e.g. "poor overall-recovery reported in N of the last M sessions") — is
an **observable completion fact**, same category as the existing
`Session.status`/`SlotSelectionOverride` history/`ScheduleIssue`
accumulation already on that permitted list. It would surface via the
same materiality-check mechanism, with its own new reason code and its
own threshold (a TRAININGOS-DESIGNED number, flagged for explicit
decision, not invented here). **Not built in Stage 8B** unless you want
it pulled forward — this section exists so the seam is designed rather
than bolted on awkwardly later.

## 6. Reason codes — factored as signal source × action taken

**REVISED from the original single combinatorial enum**
(`painTriggeredExerciseSubstitution`-shaped cases), which would need a
new case for every new (signal, action) pairing and cannot answer D10's
longitudinal questions ("recurring pain" vs. "recurring stiffness" vs.
"how many substitutions happened for any reason") independently of each
other. Two small, orthogonal, additive enums instead — both mirror
`PlannerReasonCode`'s existing discipline (closed, `CaseIterable`, never
string-parsed):

```swift
/// WHICH reported signal(s) drove a decision — independently queryable
/// for longitudinal analysis (D10), and where pain/stiffness/soreness
/// stay the three distinct things D2 requires.
enum ReadinessSignalSource: String, Codable, CaseIterable {
    case poorSleep
    case lowEnergy
    case poorOverallRecovery
    case localSoreness
    case pain
    case stiffness
}

/// WHAT the decision actually did — independent of why.
enum ReadinessActionKind: String, Codable, CaseIterable {
    case noChangeConfirmed
    case loadReduced
    case volumeReduced           // sets/reps/duration/distance reduced
    case exerciseSubstituted
    case blockRemoved
    case postponeRecommended
    // .sessionConvertedToLowerDemand reserved for Level 5's future stage — see §4
}
```

`ReadinessAdaptationDecision` (`READINESS_PROGRESSION_CONTRACT.md` §2)
carries `triggeringSignals: [ReadinessSignalSource]` (more than one can
contribute — e.g. low energy *and* poor overall recovery both pointing
to the same volume reduction) plus one `actionTaken: ReadinessActionKind`.
This directly supports every longitudinal question D10 lists ("recurring
pain in the same area," "repeated low energy," "repeated readiness
adaptations") as an independent query over these two fields, without
needing a combinatorial case per pairing and without redesigning
anything later.

Illustrative, not final — Stage 8B should only add the cases an actual
implemented decision needs, per CLAUDE.md rule 10 ("every new reason
code needs a table-driven test").

## 7. Readiness is not the only source of session-local adaptation (explicit future constraint)

**Deferred future feature, not built in Stage 8B, but the architecture
below must not assume it away:** TrainingOS will later support a
persistent **Training Environment / Equipment Profile** (Commercial Gym,
Home Gym, Hotel Gym, Travel/Minimal Equipment — available equipment,
equipment capacity, physical/environmental constraints like ceiling
height or no-overhead-movement). The eventual behavior is
**strategic phase/program intent + today's training environment +
readiness → executable session** — three independent inputs, not two.

**IMPORTANT ARCHITECTURAL DISTINCTION, load-bearing for Stage 8B:**
Readiness answers *"what is appropriate for this user today?"*
Training Environment answers *"what is physically executable at this
location?"* These are different sources of constraint even when both
resolve to the same mechanism (exercise substitution) — a shoulder-pain
substitution and a no-barbell-available substitution are not the same
kind of fact, even though both might swap out the same exercise slot.

**What this means for Stage 8B's design, concretely:**
- `ReadinessAdaptationDecision` (`READINESS_PROGRESSION_CONTRACT.md` §2)
  stays **readiness-specific** — it must never be widened into a general
  "session-local adaptation" record that also carries environment/
  equipment reasons. A future environment constraint gets its **own**
  sibling provenance type (e.g. `EnvironmentAdaptationDecision`),
  following the exact same "new concept, new type" discipline already
  applied to `ReadinessAdaptationDecision` itself relative to
  `PlannerDecision` (CLAUDE.md rule 18's spirit).
- The **shared substitution/exercise-resolution mechanism**
  (`SubstituteExerciseUseCase.substituteThisSessionOnly`/
  `SubstituteActivityUseCase.substituteThisSessionOnly`,
  `SubstitutionValidator`, `ExerciseSlot`) must remain a genuinely shared
  resource, not something Stage 8B quietly couples to readiness alone.
  Level 3's implementation must not hard-code an assumption that the
  only caller of this-session-only substitution is a readiness decision
  — the mechanism accepts a reason/provenance reference from whichever
  decision triggered it (today: `ReadinessAdaptationDecision`; later:
  an environment-constraint decision too) rather than being named or
  shaped around readiness specifically.
- Level 4 (reduce/remove a block) and Level 6 (postpone/skip) similarly
  must not be wired as if a readiness signal is the only possible reason
  a block gets reduced or a session postponed — an unavailable-equipment
  case is a different source arriving at the same action, and the
  provenance record (not the action mechanism) is what tells them apart.

**Not decided or built here:** what an `EnvironmentAdaptationDecision`
looks like, how equipment capacity maps to `ExerciseSlot.allowedTargets`,
or how a low-ceiling constraint gets evaluated. Those are a future
stage's own design work. Stage 8B's obligation is narrower and
mechanical: don't build the readiness path in a way that has to be torn
up to make room for a second, structurally similar constraint source
later.
