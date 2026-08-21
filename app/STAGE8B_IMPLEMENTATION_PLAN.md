# Stage 8B Implementation Plan — IMPLEMENTED AND MANUALLY ACCEPTED

Stage 8B is implemented, tested (26 new tests across
`ReadinessAdaptationTests`/`DebugAcceptanceFixturesUseCaseTests`, full
676-test suite green), built for Simulator, and **manually accepted by
the product owner**. This document is retained as the as-built
reference; see `STAGE8B_ACCEPTANCE_REPORT.md` for the final report, the
Functional Fitness audit result, the manual acceptance record, and the
one identified (deferred) UX cleanup item. Sections below are updated to
reflect what was actually shipped where it differs from the
pre-implementation plan.

## 1. Final scope — AS SHIPPED

**Shipped:**
- `ReadinessCheckIn` entity + the 4-tap fast path / conditional
  follow-up UX flow (`READINESS_MODEL.md`, `READINESS_UX_FLOW.md`).
- `EvaluateReadinessAdaptationUseCase` covering Level 0 (no change),
  Level 1 (explain/confirm — display only), Level 3 (substitute, both
  Strength/Hypertrophy via `SubstituteExerciseUseCase` and Functional
  Fitness via the new `SubstituteFunctionalFitnessMovementUseCase`),
  Level 4 (remove a block), Level 6 (recommend postpone/skip).
- `ReadinessAdaptationDecision` entity + the accept/keep-original
  recommendation screen (`ReadinessAdaptationProposalView`).
- One new `SubstitutionReason` case (`.readinessAdaptation`).
- `ReadinessSignalSource` / `ReadinessActionKind` typed pair.
- **Level 2, narrowed to exactly one mechanism:** set-count reduction by
  1, for Strength/Hypertrophy/Accessory exercises only, using the -1
  magnitude already established by `StrengthProgressionEngine
  .resolveSetCount`'s `.autoregulated` formula — not a new invented
  number. Load/rep-range/RIR adjustment and any Steady State/Interval/
  Functional Fitness demand reduction are **not** automatically produced
  by the evaluator — see §7/§13's open decision below.
- **Pain-with-no-valid-substitute fallback, refined during
  implementation:** a multi-exercise block falls back to reducing just
  the affected exercise's volume (Level 2), never removing sibling
  exercises' work; a single-exercise block still escalates to Level 4
  (remove it), since "reduce it" and "remove it" are the same choice
  there.

**Not in Stage 8B (deferred, seams preserved — see
`STAGE8A_DECISION_MEMO.md` "Preserve the seams"):** Level 5 (deferred to
a dedicated future stage), the `LongTermPlanner` materiality seam
(designed, not built), mobility warm-ups, manual/custom workout editing,
load-over-reps progression-engine redesign, Training Environment/Home
Gym, and — newly identified during implementation, not a silent gap —
**load/rep-range/RIR magnitude and any Steady State/Interval/Functional
Fitness internal-demand reduction**, flagged per §13/§7 below as needing
an explicit product/training-science decision before being automated.

## 2. Entities / schema changes

**New: `ReadinessCheckIn`** (`READINESS_MODEL.md` §4), one-to-zero-or-one
from `Session`:

```swift
@Model
final class ReadinessCheckIn {
    var id: UUID
    var recordedAt: Date
    var sleep: ReadinessLevel?
    var energy: ReadinessLevel?
    var overallRecovery: ReadinessLevel?
    var soreMuscleGroups: [MuscleGroup]
    var reportedPain: [MuscleGroup]
    var reportedStiffness: [MuscleGroup]
    var session: Session?
}

enum ReadinessLevel: String, Codable, CaseIterable {
    case poor, ok, good        // sleep/energy/recovery all share this 3-point shape
}
```

**New: `ReadinessAdaptationDecision`** (`READINESS_PROGRESSION_CONTRACT.md`
§2), a sibling to `PlannerDecision`, not an extension of it:

```swift
@Model
final class ReadinessAdaptationDecision {
    var id: UUID
    var decidedAt: Date
    var triggeringSignals: [ReadinessSignalSource]
    var actionTaken: ReadinessActionKind
    var originalValue: String
    var adaptedValue: String?
    var userResponse: UserAdaptationResponse
    var explanation: String
    var setPrescription: SetPrescription?
    var exercisePrescription: ExercisePrescription?
    var workoutBlock: WorkoutBlock?
    var readinessCheckIn: ReadinessCheckIn?
}

enum UserAdaptationResponse: String, Codable, CaseIterable {
    case accepted, rejectedKeptOriginal, rejectedChoseAlternative
}
```

**New enums** (`READINESS_DECISION_MODEL.md` §6):

```swift
enum ReadinessSignalSource: String, Codable, CaseIterable {
    case poorSleep, lowEnergy, poorOverallRecovery
    case localSoreness, pain, stiffness
}

enum ReadinessActionKind: String, Codable, CaseIterable {
    case noChangeConfirmed, loadReduced, volumeReduced
    case exerciseSubstituted, blockRemoved, postponeRecommended
}
```

**Existing type change:** `SubstitutionReason` gains one case,
`.readinessAdaptation`.

**No changes to:** `ProgramDefinition`, `TrainingWeek`, `SetPrescription`
(field values), `ExercisePerformanceProfile`, `PlannerDecision`,
`SessionStatus`. Nothing here alters the template graph or any existing
persisted performance data (CLAUDE.md rule 1/2).

## 3. Readiness UX flow (implementation summary — full detail in `READINESS_UX_FLOW.md`)

1. Tap Start → `ReadinessCheckInView` (fullScreenCover, mirrors
   `HypertrophyFeedbackView`'s presentation pattern).
2. Tier 0: sleep / energy / overall recovery (3 taps).
3. Tier 0.5 gateway: "Pain or stiffness today?" Yes/No (1 tap).
4. If No and all Tier 0 answers are ok/normal/fresh-or-better: submit
   immediately, no further screens (~10-15s, 4 taps total).
5. If Tier 0 recovery = sore, or gateway = Yes: targeted follow-up
   (session-scoped body-area picker; gateway path also asks pain vs.
   stiffness vs. both).
6. Submit → `RecordReadinessCheckInUseCase` persists `ReadinessCheckIn`
   immediately (CLAUDE.md rule 20 — durable before the recommendation
   screen even renders).
7. `EvaluateReadinessAdaptationUseCase.evaluate(session:checkIn:)` →
   `ReadinessAdaptationProposal` (not persisted unless accepted).
8. Empty proposal → straight to the existing Start transition, unchanged.
9. Non-empty proposal → recommendation screen, original vs. proposed
   shown per item, accept / keep original / choose valid alternative.
10. Only accepted items are applied, via existing this-session-only
    mutation mechanisms; then the existing `scheduled → inProgress`
    transition fires unchanged.
11. "Skip check-in" is available from step 2 onward at all times; skip
    proceeds directly to the unadapted prescription.

## 4. Adaptation decision hierarchy

Evaluated low-to-high, stopping at the first level that adequately
addresses every reported signal (`READINESS_DECISION_MODEL.md` §2):

| Level | Action | Stage 8B |
|---|---|---|
| 0 | No change | Ships |
| 1 | Explain/confirm | Ships |
| 2 | Adjust load/reps/RIR/set count | Ships **narrowed to set-count reduction only** (§7/§13) |
| 3 | Substitute exercise/activity | Ships (existing mechanism + new reason case; Functional Fitness gained the same mechanism via one new additive field, §2) |
| 4 | Reduce/remove a block | Ships (`WorkoutBlock.status = .skipped` + `ReadinessAdaptationDecision`; falls back to per-exercise volume reduction first on a multi-exercise block) |
| 5 | Convert to lower-demand methodology variant | Deferred to a dedicated future stage |
| 6 | Recommend postpone/skip | Ships (existing `SessionStatus` + reason) |

Per-modality behavior — see §8 below and `READINESS_DECISION_MODEL.md` §3.

## 5. Pain vs. stiffness representation

Three signals, never collapsed, never inferred from each other
(`READINESS_MODEL.md` §2):

- **Soreness** — `soreMuscleGroups`, normal training-recovery signal.
- **Pain** — `reportedPain`, potential movement-limitation signal,
  triggers conservative handling (substitution before load reduction).
- **Stiffness** — `reportedStiffness`, distinct from both; doesn't drive
  a different Stage 8B *action* than pain today, but is recorded
  separately because it's the intended future input to warm-up/mobility
  selection and its own line in longitudinal analysis.

The UI reaches pain and stiffness through one shared Tier 0.5 gateway
question, but writes to two separate fields the moment either is
selected — the UI grouping never collapses the domain-model distinction.

## 6. Historical intactness — original vs. adapted prescriptions

`SetPrescription`'s own target fields are **never overwritten** by an
adaptation. `ReadinessAdaptationDecision.originalValue` independently
preserves the pre-adaptation value; `adaptedValue` holds the proposed
value (nil if rejected). The four states (prescribed / readiness-adapted
/ user-overridden / actually performed) stay always distinguishable
(`READINESS_PROGRESSION_CONTRACT.md` §1). A same-day adaptation is an
overlay on an already-resolved prescription, never a re-invocation of
`StrengthProgressionEngine`/`SteadyStateProgressionEngine`/
`IntervalProgressionEngine`'s resolvers — week N+1 continues to chain
from week 1's own resolved value regardless of any same-day adaptation
(§3, confirmed by audit).

## 7. Result of the D9 progression/confidence audit (performed in Stage 8A, gating Level 2)

**Audited:** `RecordSetResultUseCase.swift`, `ExercisePerformanceProfile.swift`,
`PerformanceProfileStore.swift`, `DoubleProgressionEngine.swift`,
`CompleteSessionUseCase.swift`, `AutoregulationRatingResolver.swift`.

**Finding 1 — no risk where originally suspected:**
`ExercisePerformanceProfile.estimatedOneRepMax`/`.confidence` have zero
live-update call sites anywhere in the codebase (grep-confirmed); they're
set only at construction (`confidence: 0`). `RecordSetResultUseCase`
only appends a `SetResult`. So a lower-than-prescribed logged result is
**not** today read as a negative confidence signal — that mechanism
doesn't exist yet.

**Finding 2 — real, confirmed risk:** `CompleteSessionUseCase
.progressionPreview` (≈line 75) computes `lastWeight =
loggedResults.last?.weight` and feeds it into `DoubleProgressionEngine`
as `lastKnownWeight`, with no awareness of same-day readiness adaptation.
Worked example: programmed 100kg×6 → readiness-adapted to 95kg×6 →
performed 95kg×6 exactly as adapted → today's code would read
`lastWeight = 95kg` and suggest a next-session increase *from that
reduced baseline*, with no signal that 95kg was an intentional
adaptation rather than the athlete's ceiling.

**Finding 3 — analogous risk:** `AutoregulationRatingResolver
.previousWeekSetCount` reads the *prescribed* set count of the most
recently completed prescription. Safe only because nothing today
physically shrinks a `SetPrescription` list; a naive Level 2 set-count
reduction implemented by deleting rows would corrupt this.

**Fixes implemented, with one important semantic correction made before
coding (approved by the product owner):** an adapted-and-successfully-
completed session is **progression-neutral (HOLD)** — it neither
regresses (reduced-and-completed is not a failed attempt at the
original) nor progresses (it is never treated as proof the original was
itself performed). Concretely:
1. `progressionPreview` checks each prescription's
   `readinessAdaptationDecisions` for an accepted one; if the engine's
   own verdict on the executed targets would be `.loadIncrease`, it is
   overridden to the new `.readinessAdaptedHold` reason code, reporting
   the **held, original** weight — never the adapted number, never
   implying the original was completed. A genuine miss against the
   adapted targets is left completely unmodified.
2. `SetPrescription.isAdaptedAway: Bool` marks a reduced set — rows are
   never deleted. `AutoregulationRatingResolver.previousWeekSetCount`
   needed no code change: it already reads the unaffected
   `orderedSetPrescriptions.count`.

Full detail and the exact worked-example test coverage:
`READINESS_PROGRESSION_CONTRACT.md` §3.

## 8. Per-modality behavior under readiness adaptation — AS SHIPPED

- **Hypertrophy/Powerlifting/Accessory (Strength family)** — Levels 0/1/
  3/4/6 fully shipped; Level 2 shipped as set-count reduction only
  (§1/§7). Load/rep-range/RIR adjustment not automated (§13 below).
- **Functional Fitness — audit result (performed before implementing,
  per explicit instruction to STOP if new methodology were needed):**
  Levels 0/1/6 follow mechanically from existing architecture, same as
  every modality. **Level 3 required one small, purely mechanical
  addition** — `FunctionalFitnessMovement` had no `sourceExerciseSlot`/
  `substitutionUsed`/`substitutionReason` back-reference the way
  `ExercisePrescription` has had since Stage 6B; adding the identical
  fields (mirroring that established precedent exactly) and a new
  `SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly`
  closed the gap — this is engineering plumbing, not new training-science
  policy, so it was implemented. **Level 4** (remove the whole block) —
  ships, no new concept needed (`WorkoutBlock.status`/`BlockStatus`
  already modality-agnostic). **Level 2 does NOT ship for Functional
  Fitness** — reducing a scored metcon's internal demand (fewer rounds,
  lower reps, a lighter load on one movement mid-workout) requires
  deciding what a legitimate lower-demand variant of THAT stimulus means,
  which is the exact same kind of training-science policy question Level
  5 already raises, not a mechanical gap. **STOPPING on this specific
  part, as instructed** — see the open decision in §11. Confirmed by
  `ReadinessAdaptationTests.testFunctionalFitness_...`: a stiffness/
  soreness signal on a Functional Fitness movement produces no proposal
  in Stage 8B, rather than inventing one.
- **Steady State/Interval** — **not implemented in Stage 8B beyond the
  session-level Level 4/6 (remove the whole block / postpone).**
  Per-modality duration/intensity Level 2 overlay was originally
  design-scoped in Stage 8A but, on implementation, ran into the same
  §13 gate as Strength's load dimension: no existing, already-approved
  magnitude for "reduce today's duration/intensity by X" exists anywhere
  in this codebase. Narrowing this out (rather than inventing a number)
  keeps every shipped Level 2 behavior traceable to an already-approved
  formula. Flagged in §11/§13, not silently dropped.

Strict methodologies stay strict: `EvaluateReadinessAdaptationUseCase`
asks each block's `WorkoutBlockType` what it supports rather than
applying one generic edit everywhere (CLAUDE.md rule 7).

## 9. Tests Stage 8B will require

- Table-driven tests for every `ReadinessSignalSource`/`ReadinessActionKind`
  combination the evaluator actually produces (CLAUDE.md rule 4 — every
  reason code needs a test, including boundaries).
- Precedence-order tests: a signal addressable at Level 3 never escalates
  to Level 6 (§4/`READINESS_DECISION_MODEL.md` §2).
- D9 regression tests (explicit, required before Level 2 ships):
  - Adapted-and-successfully-completed (95kg×6 adapted, 95kg×6 performed)
    reads as confirmation of the *original* 100kg×6 prescription, not a
    new lower ceiling — `progressionPreview` output asserted directly.
  - Adapted-and-then-under-performed relative to the *adapted* target
    still reads as a genuine miss (the fix must not mask real
    underperformance, only intentional reduction).
  - `previousWeekSetCount` unaffected by a same-day adaptation that
    marks sets skipped rather than deleting them.
- Persistence-durability tests: `ReadinessCheckIn` persisted immediately
  on submit, independent of whether the recommendation screen is ever
  reached or the session is later abandoned (CLAUDE.md rule 20).
- History-intactness tests: original prescription value is still
  readable after an adaptation is accepted; rejecting a proposal leaves
  the original prescription completely unchanged.
- Skipped-vs-completed-with-no-signal distinguishability test
  (`READINESS_MODEL.md` §5) — a `nil` check-in and an all-good check-in
  must never be conflated by any downstream reader.
- Substitution-reason test: `.readinessAdaptation` correctly attaches,
  with the specific signal recoverable from
  `ReadinessAdaptationDecision.triggeringSignals`, not from
  `SubstitutionReason` itself.

## 10. Explicitly deferred future work (not Stage 8B, seams preserved)

- **Level 5** — lower-demand methodology variants; deferred to a
  dedicated future stage requiring its own per-programming-system policy
  decision.
- **`LongTermPlanner` materiality seam** — designed
  (`READINESS_DECISION_MODEL.md` §5), not built; no threshold chosen.
- **Mobility/warm-up selection** — `reportedStiffness` is captured now
  specifically to enable this later; no warm-up domain concept exists
  yet.
- **Manual/custom workout editing** — not built; readiness adaptation's
  scoping to the materialized `Session` graph (not to
  "came from a `ProgramDefinition`") keeps it reusable once this exists.
- **Load-over-reps progression-engine redesign** — belongs to the
  progression engines, not readiness; adaptation-as-overlay keeps it
  compatible.
- **Training Environment / Equipment Profile** — persistent environments
  (Commercial Gym, Home Gym, Hotel Gym, Travel/Minimal Equipment)
  describing available equipment, equipment capacity, and physical/
  environmental constraints, combining with strategic phase/program
  intent and readiness to produce an executable session. Not designed or
  built in Stage 8B. **Kept explicitly distinct from readiness:**
  readiness answers "what is appropriate for this user today"; training
  environment answers "what is physically executable at this location"
  — different constraint sources even when both resolve through the same
  substitution mechanism. Stage 8B keeps the seam open by (a) never
  widening `ReadinessAdaptationDecision` into a general session-local
  adaptation record — a future environment feature gets its own sibling
  provenance type — and (b) implementing the shared substitution/
  block-reduction/postpone mechanisms so they accept a provenance
  reference rather than assuming readiness is their only caller.
  `READINESS_DECISION_MODEL.md` §7.

## 11. Remaining product decisions (surfaced by implementation, per §13's STOP instruction)

None of these blocked shipping Stage 8B as scoped — each is a magnitude
or per-system policy question intentionally left unautomated rather than
answered by invention:

- **Load/rep-range/RIR adaptation magnitude (Strength family).** No
  existing, already-approved rule defines "how much" to reduce a weight
  or relax a rep/RIR target for a readiness signal — unlike set-count
  reduction, which reuses the existing -1 autoregulation formula. Needs
  an explicit number (or bounded mechanism) from you, or an explicit
  decision to leave this un-automated permanently and rely on
  substitution/set-count/postpone only.
- **Steady State/Interval Level 2 (duration/intensity overlay)
  magnitude.** Same gate — "reduce today's duration by how much" has no
  approved existing rule. Not implemented in Stage 8B; needs the same
  kind of decision as above, scoped to these two modalities.
- **Functional Fitness Level 2 (reduce a scored metcon's internal
  demand).** Requires deciding what a legitimate lower-demand variant of
  a given stimulus means — structurally the same question Level 5 (a
  dedicated future stage) already owns. Recommend folding this into that
  future stage's scope rather than deciding it piecemeal here.
- **The exact `LongTermPlanner` materiality threshold** — not needed for
  Stage 8B (nothing wired to it), only if/when that seam is ever pulled
  forward into a future stage.

None of the above are silent gaps: `EvaluateReadinessAdaptationUseCase`
simply produces no proposal for a signal it has no approved mechanism
for, and `ReadinessAdaptationTests` proves this explicitly for Functional
Fitness stiffness/soreness rather than leaving it untested.

---

**Stage 8B is implemented, tested, manually accepted, and closed.** See
`STAGE8B_ACCEPTANCE_REPORT.md` for the acceptance record and the one
deferred UX cleanup item. Stage 8 (Readiness & Workout Adaptation) is
complete; Stage 9 (Pre-Workout Warm-up/Mobility) is the next stage under
design — see `STAGE9_WARMUP_DESIGN.md`.
