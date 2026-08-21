# Stage 9 — Pre-Workout Warm-up / Mobility

**STATUS: MANUALLY ACCEPTED. Stage 9B is closed.** D-W1 through D-W6
approved with clarifications; implementation completed a ranking
refinement pass after the first manual acceptance attempt (see
`STAGE9B_IMPLEMENTATION_REPORT.md`'s "Manual acceptance record" for the
accepted cases and known, non-blocking refinement opportunities).

**Approved decisions, with clarifications:**
- **D-W1 (approved):** plain lightweight checklist, no second persisted
  timer system. Skip/self-pace/Start-Workout-anytime all always available.
- **D-W2 (approved, revised model):** `WarmupMovement.exercise: Exercise?`.
  When set, the Exercise remains the sole source of truth for target
  metadata — never duplicated onto `WarmupMovement`. No new abstract
  `Movement` base type in Stage 9B.
- **D-W3 (approved, with an important clarification):** relevance and
  safety outrank hitting 5 minutes. Preference order: (1) highly
  relevant session-specific preparation, (2) readiness/stiffness-biased
  preparation, (3) safe general preparation genuinely useful for this
  session, (4) a shorter warm-up. Never pad with irrelevant filler, and
  never violate pain exclusion to fill the budget.
- **D-W4 (approved):** target 300s, per-item cap 60s, `secondsPerRep` 3s,
  max item safety cap 8 — defined **centrally** as one policy/config
  source, never scattered as magic numbers, and changeable later without
  a schema change. 300s is nominal, not a required minimum.
- **D-W5 (approved):** `.jumping` (if still the smallest clean addition
  after implementation audit) + a small closed `PreparationEmphasis`
  enum. **`PreparationEmphasis` is derived automatically from existing
  exercise/session metadata** — only `WarmupMovement` catalog rows
  explicitly declare what preparation quality they themselves provide;
  no second manually-maintained taxonomy across every `Exercise`.
- **D-W6 (approved):** warm-up completion never gates
  `CompleteSessionUseCase`/`SessionStatus`/`SessionCompletionContext`/
  any progression engine. A side-channel, not a requirement.

**Ramp-up sets confirmed out of Stage 9:** general pre-workout
preparation (this stage) and exercise-specific ramp-up sets
(`SetPrescription.isWarmup`, dormant, unset anywhere today) are separate
concepts. Stage 9B does not touch `SetPrescription.isWarmup` — that field
is preserved as-is for a later `StrengthMaterializer`/strength-execution
enhancement, recorded as explicit deferred future work.

Reconciles with the authoritative roadmap: `STAGE8A_DECISION_MEMO.md`'s
"Preserve the seams" section already named this exact capability as
deferred future work and specifically required Stage 8B to keep
`ReadinessCheckIn.reportedStiffness` a distinct, queryable signal *so
that* a future warm-up feature could use it without a migration. This
document is that future stage — it is not a new, unplanned direction;
it is the seam Stage 8B already built being used for its intended
purpose.

## 0. What already exists (do not duplicate)

- **`WorkoutBlockType.warmup`** already exists and is already used —
  `IntervalProgramGenerator` materializes a same-activity, easy-effort
  `.warmup` block ahead of an interval block (`ScoringDirection.none`,
  never a PR). This is a **different, already-solved problem**: "ease
  into today's cardio activity," same modality, template-authored,
  materialized once at generation time. It is not reused as the
  mechanism here and is not replaced by this design — Steady
  State/Interval/Running keep exactly what they have.
- **`SetPrescription.isWarmup`** already exists — a per-set ramp-up flag
  *within* a Strength/Hypertrophy exercise (lighter ramp sets before
  working sets). Unrelated vocabulary collision only — flagging so
  naming in Stage 9B doesn't conflate "ramp-up set" with "pre-session
  mobility sequence." This design's new types are named `Warmup*`
  deliberately close to that term, so the doc comments must be explicit
  about the distinction when built. **Confirmed by grep: this field is
  never set to `true` anywhere in the codebase today** — it's a dormant
  schema hook, not a built feature. **Exercise-specific ramp-up sets
  belong entirely to the existing strength execution system** (wherever
  `StrengthMaterializer`/a future enhancement populates `isWarmup` rows),
  **not to Stage 9.** General mobility/preparation (this document) and
  exercise-specific ramp-up sets (a heavier bar working up to a top set)
  are different products solving different problems; Stage 9 must not
  touch `SetPrescription.isWarmup` or attempt to generate ramp sets.
- **No existing concept** of a pre-session mobility/preparation
  sequence, a curated mobility movement catalog, or a "prepare for
  today's session" screen. `TIMER_ARCHITECTURE.md` covers only
  in-workout clocks (rest/AMRAP/EMOM/interval) — no pre-workout phase
  exists there to extend or conflict with.
- **Directly reusable, unchanged:** `MuscleGroup` (11 cases),
  `MovementFunction` (10 cases) — the exact vocabulary `ExerciseSlot`
  already uses to match candidates to slots. `ReadinessCheckIn
  .reportedPain`/`.reportedStiffness`/`.soreMuscleGroups` — already
  typed, already queryable, already exactly what Stage 8A promised this
  stage. `ReadinessAdaptationDecision` and Stage 8B's own
  "adaptation is an overlay on the live prescription, never a separate
  copy" architecture — a substituted `ExercisePrescription.exercise` or
  a `.skipped` `WorkoutBlock` already **is** the final executable
  workout; there is nothing extra to project.

## 1. Product flow

```
tap Start
→ ReadinessGateFlow (existing, UNCHANGED)
    → check-in → evaluate → accept/reject proposals
→ final executable workout now exists (already-mutated Session/blocks)
→ NEW: warm-up step, only for eligible modalities (§6)
    → generated ~5-minute sequence shown
    → user works through it OR taps Start Workout / Skip Warm-up at any point
→ existing StartSessionUseCase.start (UNCHANGED) fires exactly as today
```

The warm-up step is a **new terminal step appended to the existing
`ReadinessGateFlow` sequence**, not a parallel or separate gate — it
runs after adaptation resolves and before the flow's existing
`onFinished()` call (which is what triggers the real Start transition).
This is the same "view-layer gate before the existing transition fires"
shape `READINESS_ADAPTATION_PIPELINE.md` §0 already established for
readiness itself — Type-A reuse of an already-approved pattern, not a
new mechanism.

## 2. Domain model — answers to the 9 architecture questions

**Q1 — Entity kind? REVISED after challenge (see Part 2 of the decision
memo for full reasoning).** A new, small, dedicated `WarmupMovement`
catalog entity — **not** a reuse of `Exercise` as its primary identity —
but **with an optional reference to an existing `Exercise`**
(`WarmupMovement.exercise: Exercise?`) for the real overlap case (a
bodyweight squat, push-up, glute bridge, or light rowing genuinely is
both a warm-up movement and a thing someone might separately program/
track). When linked, `WarmupMovement` reads `targetMuscleGroups`/
`targetMovementFunctions` FROM that `Exercise` rather than duplicating
them — its own inline tag fields are populated only for pure mobility
drills with no `Exercise` equivalent (cat-cow, 90/90 hip rotation, band
pull-apart). This avoids a duplicate, driftable source of truth for the
overlap set while keeping `WarmupMovement`'s own identity clean and
never performance-tracked — `Exercise`'s PR/`ExercisePerformanceProfile`
machinery is entirely unaffected either way, since `WarmupMovement`
still never itself becomes loggable.

**Q2 — Matching metadata? REVISED after challenge.** `MuscleGroup` +
`MovementFunction` alone are **not sufficient** — concretely
insufficient for overhead-vs-horizontal-pressing mobility needs, ankle/
hip joint-mobility needs a squat depth requires, and jumping/plyometric
prep (no existing `MovementFunction` case covers it at all). The
smallest useful extension, not a new mobility taxonomy: (a) one new case
added to the existing `MovementFunction` enum, `.jumping` — a trivial,
justified in-place extension; (b) one new, small, closed,
**warm-up-only** enum, `PreparationEmphasis` (~5-6 cases — see Part 2 §2
for the exact list), populated **automatically** on the workout side by
a small deterministic derivation function from the session's own
already-existing `MuscleGroup`/`MovementFunction` data — never a third
tag manually re-authored on every `Exercise`. **Implementation
dependency found during this audit:** the seeded catalog's
`MovementFunction` tagging is inconsistent today — Stage 4E's
Functional-Fitness-oriented exercises (Back Squat, Thruster, Pull-up,
etc.) have it populated; the Stage 6C/6D plain-Strength additions
(Romanian Deadlift, Leg Press, Front Squat, Calf Raise, etc.) do not.
The derivation function must lean primarily on `MuscleGroup` (always
populated) and treat `MovementFunction` as a refinement signal only
when present, or Stage 9B should backfill it — flagged for Stage 9B,
not solved here.

**Q3 — Persisted as part of the Session?** Yes. New `WarmupSequence`
(one-to-zero-or-one from `Session`, cascade-deleted with it — identical
shape to `ReadinessCheckIn`) holding ordered `WarmupSequenceItem`s
(movement reference + prescribed duration/reps/sides + `wasCompleted:
Bool`). Persisted **immediately upon generation**, before the user acts
on it (CLAUDE.md rule 20 — the generated recommendation is itself a
meaningful, explainable fact worth keeping, exactly like
`ReadinessCheckIn` is durable before its own recommendation screen).
Skipping never deletes the row — it leaves items `wasCompleted == false`
— so completed-history can truthfully answer both "what was recommended"
and "what was actually done," the same two-truths discipline Stage 8B
just established for readiness.

**Q4 — How stiffness/pain influence generation? REVISED to make the
budget relationship explicit (Part 2 §4 has the full reasoning).**
- **Stiffness** (`reportedStiffness`, by `MuscleGroup`) — **re-ranks
  priority within the same fixed time budget (§7); it never appends
  extra items or extends the total window.** A stiff-tagged candidate
  moves to the front of the ranked list, which means it's more likely
  to survive the budget cut — and a lower-priority generic item is what
  gets squeezed out instead, not added on top. A 5-minute warm-up with
  reported stiffness is still a 5-minute warm-up, just a differently
  weighted one.
- **Pain** (`reportedPain`) — any `WarmupMovement` whose own
  `targetMuscleGroups` intersects a reported pain area is **excluded
  outright from the candidate pool before ranking even happens**, using
  the exact same "candidate's own targets disjoint from the pain areas"
  rule `EvaluateReadinessAdaptationUseCase.validSubstitute` already
  applies for Level 3 substitution — reused, not reinvented. This is
  read directly from the `ReadinessCheckIn`'s own typed fields; the
  generator never needs to re-consult `ReadinessAdaptationDecision`
  internals to know what to avoid, because the check-in's own signal
  already fully determines it, and because generation already reads the
  post-adaptation executable workout (Q5), the two effects compound
  correctly on their own. **A shrunk candidate pool is allowed to
  produce a shorter-than-5-minute sequence** — the time budget is a
  ceiling/target, never a floor that forces back-filling with an
  unsafe or irrelevant item just to hit a number.

**Q5 — Using the accepted adaptation, not the original prescription?**
Free by construction. Stage 8B's Level 3 substitution mutates
`ExercisePrescription.exercise`/`FunctionalFitnessMovement.exercise` **in
place** (never a separate "adapted copy"), and Level 4 removal sets
`WorkoutBlock.status = .skipped` in place. So "the final executable
workout" simply **is** `session.orderedBlocks` at the moment warm-up
generation runs — there is no second projection to build. The only
requirement this imposes: **generation must run strictly after the
`ReadinessAdaptationProposalView` step**, reading
`session.orderedBlocks.filter { $0.status != .skipped }` and each
block's *current* exercise/movements — never the original
`sourcePrescriptionTemplate`/`sourceExerciseSlot`'s own default.

**Q6 — Per modality?**
- Hypertrophy/Strength/Powerlifting/Accessory — generate from the union
  of `MuscleGroup`/`MovementFunction` implied by that block's
  *currently-assigned* exercises.
- Functional Fitness — same, reading
  `FunctionalFitnessMovement.exercise?.primaryTargets`/`.movementFunctions`
  across the session's blocks (post-substitution).
- **Steady State/Interval/Running — explicitly excluded**, per your
  instruction. Their own existing `.warmup` block mechanism (§0) is
  untouched and unreplaced; this system offers nothing for a
  Steady-State/Interval-only Session.
- Mixed sessions (e.g. a Strength block plus a Steady-State block) —
  generate from whichever blocks are in-scope; the Steady-State block's
  own warm-up (if any) is independent and unaffected.

**Q7 — Keeping it ~5 minutes without an optimizer? REVISED to state the
actual algorithm (Part 2 §3 has the full worked reasoning) — never "pick
five movements":**

1. Every `WarmupMovement` resolves to an `estimatedSeconds`: either its
   own `defaultDurationSeconds`, or `defaultReps × secondsPerRep ×
   (hasSides ? 2 : 1)` using one fixed, TRAININGOS-DESIGNED constant
   (`secondsPerRep`, e.g. 3s) — the same "reuse one illustrative default
   everywhere" discipline as the 3-point readiness scale.
2. Build the full eligible candidate pool (post pain-exclusion),
   ranked in a fixed, deterministic priority order: stiffness-flagged
   first, then the session's primary/highest-priority blocks' own
   targets, then general/other.
3. Walk the ranked list, greedily accumulating `estimatedSeconds` into a
   running total. **Stop** once the running total reaches the target
   window (e.g. 300s) or a fixed max-item safety cap (e.g. 8) is hit —
   whichever comes first. No item already accumulated is ever removed
   to "fit better."
4. Every individual candidate's own `estimatedSeconds` is itself capped
   (e.g. 60s max) so one long single item can never itself blow the
   whole budget.

This is a single greedy accumulate-until-budget pass — O(n), fully
deterministic, trivially unit-testable — never a knapsack/optimization
solve. The final total may land slightly under or over the exact target
(e.g. 4:10-5:20), which is the correct, honest meaning of
"approximately five minutes," not an exact-300-seconds guarantee.

**Q8 — Deterministic vs. generated?** All of it is deterministic,
rule-based selection over typed inputs — no ML, no randomness, no
network, same discipline as `EvaluateReadinessAdaptationUseCase`/
`FunctionalFitnessDecisionEngine`. "Generated"/"recommended" describes
the product framing (advisory, skippable), not a non-deterministic
mechanism — identical session + identical readiness always produces
the identical sequence.

**Q9 — Effect on workout completion/history?** None, matching your own
stated instinct exactly. `CompleteSessionUseCase`, `SessionStatus`,
`SessionCompletionContext` are completely untouched by warm-up state.
`WarmupSequence`'s own completion flags are read only by the
completed-history view, purely informational, never a gate.

## 3. Persistence / schema (for Stage 9B — not created yet)

```
WarmupMovement (new, seeded catalog — like ExerciseCatalog)
  id: UUID
  name: String
  exercise: Exercise?                       // REVISED (Q1): optional link for movements
                                             // that legitimately are also a tracked Exercise;
                                             // targets/functions below are read FROM exercise
                                             // when set, and only authored inline when nil.
  targetMuscleGroups: [MuscleGroup]          // authoritative only when exercise == nil
  targetMovementFunctions: [MovementFunction] // authoritative only when exercise == nil
  emphasis: [PreparationEmphasis]            // NEW (Q2) — see Part 2 §2 for the case list
  instructionText: String
  defaultDurationSeconds: Int?     // one of these two is set, never both
  defaultReps: Int?
  hasSides: Bool                   // e.g. "10 each side"
  requiresEquipment: Bool          // favors minimal-equipment; see §6 (Home Gym)

WarmupSequence (new, Session-owned, cascade — mirrors ReadinessCheckIn)
  id: UUID
  generatedAt: Date
  wasSkippedEntirely: Bool
  session: Session?   // plain inverse; owning relationship on Session.warmupSequence

WarmupSequenceItem (new, WarmupSequence-owned, cascade)
  id: UUID
  sortIndex: Int
  movement: WarmupMovement?
  prescribedDurationSeconds: Int?
  prescribedReps: Int?
  wasCompleted: Bool
```

Every new to-one reference to a deletable type needs the same required
inverse this codebase always adds for delete-rule safety
(`DELETE_RULE_MATRIX.md`'s established "un-inversed to-one reference
crashes instead of nullifying" fix) — `Session.warmupSequence`
(`.cascade`), `WarmupSequence.items` (`.cascade`), and a
`WarmupMovement.usedInSequenceItems` required-inverse array (`.nullify`,
nothing reads it) mirroring `ExerciseSlot.materializedPrescriptions`
exactly. No change to `ProgramDefinition`/`TrainingWeek`/any template
graph type, and no change to `ReadinessCheckIn`/`ReadinessAdaptationDecision`.

## 4. UI flow

Reuses `ReadinessGateFlow`'s exact shape (single `fullScreenCover`, a
small internal step enum, one `onFinished` callback) — add one more
step, shown after adaptation resolves (or immediately after check-in if
Level 0):

```
Warm-up · ~5 min
[ordered list/carousel of items — name, duration or reps×sides, one-line instruction]
Skip Warm-up          Start Workout
```

No video/illustration this slice (explicitly out of scope, per your
instruction not to overbuild media infrastructure). Whether items need
individual timers is an open decision (§7, D-W1) — the minimal version
is a plain checklist the user taps through or ignores entirely; "Start
Workout" is always one tap away, exactly mirroring
`READINESS_UX_FLOW.md`'s own "keep original is always one tap away"
rule for the adaptation screen.

## 5. Edge cases

- **No movement matches any needed tag** (a rare `MuscleGroup`/session
  shape the catalog doesn't cover) — falls back to a small
  general/full-body tier rather than an empty screen. Exact fallback
  content is a Stage 9B decision, not invented here.
- **Nothing left to train** (e.g. the session's only block was Level-4
  removed) — no warm-up shown at all; nothing to prepare for.
- **Postpone/skip accepted (Level 6)** — no warm-up shown; the session
  isn't happening today.
- **Backgrounded/force-quit mid-warm-up** — the persisted
  `WarmupSequence` and its completion flags are what's read on
  reopening; the SAME sequence is shown again, never regenerated
  differently for the same Session (determinism + never losing
  confirmed progress, CLAUDE.md rule 20/21's spirit).
- **Steady-State/Interval/Running-only Session** — warm-up step doesn't
  appear at all; flow goes straight from adaptation resolution to Start,
  unchanged from today.

## 6. Home Gym / equipment-constraint compatibility (not built, kept in mind)

`WarmupMovement.requiresEquipment: Bool` defaults every seeded warm-up
movement toward minimal-equipment preparation (bodyweight, bands,
floor space) — favoring practicality per your instruction, without
building any environment/equipment-profile model this slice.

**REVISED — the seam made explicit as a real input shape, not just a
field:** the generator's own entry point takes a single
`WarmupGenerationContext`:

```swift
struct WarmupGenerationContext {
    let executableWorkout: Session          // post-adaptation, always required
    let readiness: ReadinessCheckIn?         // nil if skipped
    let environmentConstraint: EnvironmentConstraint?  // ALWAYS nil in Stage 9B — reserved
}
```

`environmentConstraint` is declared and threaded through the function
signature now, always `nil` in Stage 9B, with no `EnvironmentConstraint`
type defined yet (not invented here — Home Gym's own future design owns
that). This is the same "preserve the seam, don't build the feature"
discipline Stage 8A applied to Training Environment
(`READINESS_DECISION_MODEL.md` §7) — a future Home Gym stage adds one
real filter step (drop `requiresEquipment == true` candidates the
constraint doesn't satisfy) at the exact point candidates are already
filtered by pain, without changing the function's shape or callers.

## 7. Explicit product decisions needing your approval

**D-W1 — Per-item timing UI vs. plain static checklist for v1.**
Recommendation: plain checklist (tap to mark done, or ignore and hit
Start Workout) — no `TimerState`-driven per-item countdown this slice.
Simpler, matches "don't overbuild," and avoids a second timer surface
this early. Add real per-item timing later only if you find the plain
checklist insufficient in practice.

**D-W2 — `WarmupMovement` as its own new `@Model` catalog entity, with
an optional link to `Exercise` for the overlap case.** Recommendation:
yes, as revised in §2 Q1/§3 — not a reuse of `Exercise` as primary
identity, not inline/hardcoded Swift data, but not a fully duplicate
catalog either.

**D-W3 — Fallback behavior when no catalog movement matches a needed
tag.** Recommendation: a small pre-authored general/full-body fallback
tier, never an empty screen. Needs your sign-off since "what belongs in
that generic tier" is itself a minor content decision.

**D-W4 — Exact item-count/duration constants.** Recommendation:
6 items, ~40s each (~4 minutes) or a mix of timed/rep-based items landing
near 5 minutes — TRAININGOS-DESIGNED, needs your explicit sign-off same
as every other illustrative default in this repo, not something to
silently pick and ship.

**D-W5 — Approve the small taxonomy extension: one new
`MovementFunction` case (`.jumping`) plus one new closed
`PreparationEmphasis` enum (~5-6 cases), derived automatically rather
than manually re-tagged.** Revised from "no new taxonomy needed" after
testing the assumption against real matching needs (Part 2 §2) — this
is the smallest extension that closes the gaps found, not a mobility
ontology.

**D-W6 — Confirm warm-up completion never gates Session completion.**
Stated as your own instinct already; asking for formal sign-off since
it's foundational to §2 Q9 and the test strategy below.

## 8. Test strategy (for Stage 9B)

- Deterministic-generation tests: identical session + identical
  readiness → identical sequence, table-driven per modality.
- Pain-exclusion tests: never includes a movement targeting a reported
  pain area.
- Stiffness-priority tests: a stiff area's movements are included/
  prioritized.
- **Adaptation-awareness tests** (the most important ones, directly
  mirroring `ReadinessAdaptationTests`'s own discipline): after an
  accepted Level 3 substitution, warm-up reflects the *new* exercise's
  targets, never the original's; after an accepted Level 4 removal,
  that block's targets are excluded from generation entirely.
- Persistence/relaunch tests: `WarmupSequence` and its item completion
  flags survive a fresh `ModelContext` reload.
- **Completion-independence test**: complete a Session with an
  unfinished or entirely-skipped warm-up; assert
  `CompleteSessionUseCase` behavior is completely unaffected.
- Modality-exclusion test: a Steady-State/Interval/Running-only Session
  never produces a `WarmupSequence` at all.
- Delete-rule tests for the three new relationships, mirroring
  `DeleteRuleMatrixTests`'s existing coverage pattern.
- **Budget-algorithm tests (new, per the Q7 revision):** total estimated
  seconds never exceeds the target window by more than one item's own
  capped duration; a shrunk (pain-excluded) candidate pool is allowed to
  produce a shorter total rather than back-filling; reps×sides always
  convert to seconds via the one fixed `secondsPerRep` constant.
- **Stiffness-reprioritization test (new, per the Q4 revision):** a
  stiffness-flagged item appearing earlier in the ranked order can
  displace a lower-priority item out of the budget entirely — proving
  re-ranking, not appending.
- **`Exercise`-linked movement test (new, per the Q1 revision):** a
  `WarmupMovement` with `exercise != nil` reads its targets from that
  `Exercise`, never from its own (unset) inline tag fields.

## 9. Migration implications

Three new `@Model` types add three new tables. Per the backlog item
already recorded in `STAGE8B_ACCEPTANCE_REPORT.md`: this project has no
migration/versioning strategy at all yet, so — exactly as with Stage
8B's own schema additions — any Simulator/device carrying an
older store will need a clean reinstall when Stage 9B ships. Acceptable
for the current pre-release lifecycle; reiterating rather than solving
here. Recommend batching a real migration strategy as its own task
before either this or Stage 8B's debt reaches a real user.

## 10. Proposed implementation slices

- **Stage 9A (this document)** — design only. Complete.
- **Stage 9B** — `WarmupMovement` catalog + seed data; `WarmupSequence`/
  `WarmupSequenceItem` entities; a pure, deterministic
  `GenerateWarmupSequenceUseCase`; the checklist UI wired into the
  existing pre-Start flow (`ReadinessGateFlow` gains a step); tests per
  §8; `DELETE_RULE_MATRIX.md` update; manual Simulator acceptance —
  same shape as Stage 8B's own single-slice implementation.

---

**This is a design proposal only. Nothing in this document has been
implemented.** Awaiting your decisions on D-W1 through D-W6 (and any
other feedback) before Stage 9B implementation begins.
