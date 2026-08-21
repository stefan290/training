# Readiness / Progression Contract (Stage 8B — IMPLEMENTED)

How an adapted prescription feeds the existing progression engines
without being mistaken for unexplained performance regression, and what
must be persisted to keep that distinction real.

## 1. The four states that must always stay distinguishable

Per design question 10, exactly four states, never collapsed:

1. **Prescribed** — `SetPrescription`'s own original target fields, as
   materialized. Already exists, already correct, never touched.
2. **Readiness-adapted** — a *proposed* different target the user was
   shown before starting. Does not exist as a concept today.
3. **User-overridden** — the user rejected the proposal, or chose a
   different accepted alternative than the one recommended. Also does
   not exist today.
4. **Actually performed** — `SetResult`'s own logged fields. Already
   exists, already correct, never touched.

States 1 and 4 are already cleanly separated by the existing
`SetPrescription`/`SetResult` pair — the audit found this split "already
clean and enforced." **The gap is states 2 and 3**: nothing today marks
a prescription as having been adapted, from what, or why.

## 2. Proposed provenance record — a new sibling to `PlannerDecision`, not an extension of it

`PlannerDecision`'s back-references stop at `programInstance` — nothing
reaches `Session`/`WorkoutBlock`/`ExercisePrescription`/`SetPrescription`
level today, and its existing back-reference set is entirely
strategic-layer (`goal`/`planRevision`/`phase`/`trainingMix`/
`programInstance`). Rather than widen `PlannerDecision` itself into a
layer it was never scoped for, propose a small **sibling type** with the
identical discipline (reason code + factors + explanation, never a free
first-class prediction):

**As shipped** (`TrainingOS/Domain/Entities/ReadinessAdaptationDecision.swift`):

```swift
ReadinessAdaptationDecision
  id: UUID
  decidedAt: Date
  triggeringSignals: [ReadinessSignalSource]   // WHICH reported signal(s) -- can be >1 (READINESS_DECISION_MODEL.md §6)
  actionKind: ReadinessActionKind               // WHAT the decision did
  userResponse: UserAdaptationResponse          // .accepted / .rejectedKeptOriginal / .rejectedChoseAlternative
  explanation: String

  // Typed original/proposed pairs (D10) -- only the pair relevant to
  // actionKind is populated, never an opaque display string:
  originalSetCount: Int?
  proposedSetCount: Int?
  originalWeight: Double?    // schema-complete per D10; never auto-populated
  proposedWeight: Double?    // by the evaluator in Stage 8B -- see §3
  originalExercise: Exercise?
  proposedExercise: Exercise?

  // Back-references -- as many as relevant, mirrors PlannerDecision's own shape:
  exercisePrescription: ExercisePrescription?
  functionalFitnessMovement: FunctionalFitnessMovement?
  workoutBlock: WorkoutBlock?
  readinessCheckIn: ReadinessCheckIn?
```

Factored `triggeringSignals`/`actionKind` (not a single combined reason
code) per `READINESS_DECISION_MODEL.md` §6 — D10's longitudinal queries
need signal and action independently queryable, not combined into one
per-pairing case. Typed value pairs (not `originalValue: String`) per
D10's explicit instruction to avoid opaque display strings — display
copy (`explanation`) is generated FROM these fields, never the reverse.

**This entity is readiness-specific, by design, permanently — not a
general "session-local adaptation" record.** A future Training
Environment / Equipment Profile feature (deferred, see
`READINESS_DECISION_MODEL.md` §7) will need its own decision/provenance
type for equipment/environment-driven substitutions and reductions —
"what is appropriate for this user today" (readiness) and "what is
physically executable at this location" (environment) are different
constraint sources and must never be merged into one type just because
both can resolve through the same substitution mechanism
(`SubstituteExerciseUseCase.substituteThisSessionOnly` etc.). Stage 8B
must not couple that shared mechanism to `ReadinessAdaptationDecision`
specifically in a way a future environment-constraint decision couldn't
equally use.

This never overwrites `SetPrescription`'s own target fields — the
original values stay exactly as materialized; the *decision* about
whether/how they were adapted lives in this separate, always-additive
record. Matches this repo's own "propose an new domain concept as its
own type rather than overload an existing one" discipline (CLAUDE.md
rule 18's identical spirit, applied to a new type instead of an
existing one).

## 3. Feeding the progression engines — the adaptation is an overlay, never a re-resolution

`StrengthProgressionEngine.resolveWeight` for week N+1 always multiplies
**week 1's own resolved value**, never re-derives it from raw history
(confirmed by audit). A same-day readiness adaptation must therefore
never mutate what the resolver itself considers "the resolved value" for
that week — it only changes what's *shown and logged against* for this
one occurrence. Concretely: if week 3's prescription is adapted down for
today, week 4's multiplier still chains from week 1's original resolved
value, unaffected — exactly mirroring how `substituteThisSessionOnly`
already never touches the template graph or any future week.

**D9 audit — performed, resolved, confirmed real.** Traced the full call
graph before Stage 8A closed:

- `RecordSetResultUseCase.swift` (full file) — appends a `SetResult` and
  calls `PerformanceProfileStore`; contains **no** confidence or
  `estimatedOneRepMax` update logic at all.
- `ExercisePerformanceProfile.swift` — `estimatedOneRepMax`/`confidence`
  are set **only** in the type's own initializer; `addSetResult` only
  appends to the result history.
- `PerformanceProfileStore.swift` (full file) — get-or-create semantics
  only; `PerformanceProfileStore.exerciseProfile` creates a fresh profile
  with `confidence: 0` when none exists, never recomputes an existing
  one.
- Grep across `TrainingOS` for `\.estimatedOneRepMax = ` and
  `\.confidence = ` — **zero live-update call sites anywhere in the
  codebase.**

So a lower-than-prescribed logged weight is **not** today read as a
negative signal by `PerformanceProfile`/confidence logic — that specific
risk does not exist, because that logic doesn't exist yet at all.

**The real risk is elsewhere: `DoubleProgressionEngine` via
`CompleteSessionUseCase.progressionPreview`.**
`CompleteSessionUseCase.swift`, `progressionPreview(for:userProfile:)`
(≈lines 61-95) builds a `ProgressionInput` with
`lastKnownWeight: lastWeight`, where line ≈75 sets
`lastWeight = loggedResults.last?.weight` — **the actual just-performed
weight**, with zero awareness of whether today's prescription was
readiness-adapted. Concretely, in the D9 worked example — programmed
100kg×6, readiness-adapted to 95kg×6, performed 95kg×6 exactly as
adapted — `DoubleProgressionEngine` would currently read `lastWeight` as
95kg and generate its next-session suggestion as an increase *from that
reduced baseline*, with no record that 95kg was an intentional
adaptation rather than the athlete's own ceiling. This is a **real,
confirmed gap**, not the hypothetical the memo originally flagged it as.

A second, analogous risk was found in `AutoregulationRatingResolver
.previousWeekSetCount` (lines 24-28): it reads
`prescription.orderedSetPrescriptions.count` from the most recently
completed prescription — the *prescribed* count. This is safe **today**
only because nothing yet physically shrinks a `SetPrescription` list;
if a future Level 2 set-count reduction did so by removing rows (rather
than marking them skipped), this resolver would silently treat a
readiness-reduced set count as if it had always been the full prescribed
count for that week, corrupting the next week's autoregulation baseline.

**IMPORTANT CORRECTION to this contract's original phrasing (approved by
the product owner before implementation):** an adapted-and-successfully-
completed session must read as **progression-neutral (HOLD)**, never as
confirmation that the original prescription was itself completed.
"Reads as confirmation of the original prescription" (this document's
first draft) was ambiguous enough to be misread as "treat 95kg as if
100kg were lifted" — that is exactly as wrong as treating it as a
failure. The correct semantics:

> readiness-adapted AND successfully completed = neutral evidence about
> the unperformed original prescription. Preserve the pre-adaptation
> progression state; do not regress because only the adapted amount was
> logged; do not progress as though the original had actually been
> performed.

**Fixes implemented (both required before Level 2 shipped, D9):**

1. `CompleteSessionUseCase.progressionPreview` is adaptation-aware: for
   each prescription, it checks `prescription.readinessAdaptationDecisions`
   for one with `userResponse == .accepted`. If the engine's own verdict
   on the executed (adapted) targets would be `.loadIncrease`, the
   preview is overridden to a new, distinct reason code —
   `.readinessAdaptedHold` — reporting the recommended weight as the
   **held, unchanged, original** value (never the adapted number, never
   silently implying the original was completed). A genuine miss against
   the adapted targets (any non-`.loadIncrease` verdict — `.hold`, etc.)
   is left completely unmodified, so "existing methodology reacts
   conservatively as appropriate" is exactly the engine's own normal
   output, untouched.
2. Level 2 set-count reduction never physically removes a
   `SetPrescription` row — `SetPrescription.isAdaptedAway: Bool` marks it
   instead. `ExercisePrescription.orderedSetPrescriptions` (the true
   original list) is completely unaffected by this flag; a new computed
   `executableSetPrescriptions` (filtering out adapted-away sets) is what
   `progressionPreview` and the live execution/logging path read for
   "what to actually do today." `AutoregulationRatingResolver
   .previousWeekSetCount` therefore needed **no code change at all** — it
   already reads `orderedSetPrescriptions.count`, which continues to
   return the true original count by construction, never the
   readiness-reduced executable count.

Regression tests: `ReadinessAdaptationTests.swift` —
`testK`/`testM` (adapted-and-completed reads as `.readinessAdaptedHold`,
holds at the original value, per the worked 100kg→95kg→95kg example),
`testN` (adapted-but-still-missed reads as a genuine `.hold`, unmodified),
`testO` (no adaptation at all — byte-for-byte unchanged `.loadIncrease`
behavior), `testP` (the adapted-away set's true original count is proven
directly against the real `AutoregulationRatingResolver`).

## 4. Removed/skipped work must carry the same distinction

If a set/block is removed rather than reduced, the same rule applies:
`BlockCompletionContext.partial` (already exists) marks "less than the
full block happened"; a `ReadinessAdaptationDecision` attached to that
block is what distinguishes *why* — readiness-driven removal, vs. the
user simply failing to complete it, vs. an ordinary prescribed partial.
Nothing about the existing unexplained-partial/abandoned paths changes;
this only adds an *optional* explanation where one now exists.

## 5. Never fake completed prescription data

No part of this design ever synthesizes a `SetResult`/`SteadyStateResult`/
`IntervalResult`/`FunctionalFitnessResult` — those remain exclusively
created by the user actually performing and logging, through the
existing recording use cases, unchanged. An adaptation changes what is
*prescribed*, never what is *recorded as performed*.
