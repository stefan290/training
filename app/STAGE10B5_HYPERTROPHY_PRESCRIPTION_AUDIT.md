# Stage 10B.5 — Hypertrophy Prescription Engine Audit

**STATUS: DESIGN / EVIDENCE ONLY. Nothing in the prescription engine has
been changed.** `FAMILY_A_REP_GOAL_SCHEDULE`, RIR targets, baseline set
counts, load progression, deload behavior, and Stage 10B's program
construction are all exactly as they were when you approved Stage 10B's
execution/program-structure acceptance. This document traces and
evaluates; it does not implement.

Stage 10B remains **uncommitted**. Manual acceptance already recorded as
passed: Day A/B/C program structure, readiness, warm-up, post-warm-up
navigation, live workout execution. This audit is the last open item
before that checkpoint can be frozen.

---

## 1. Executive summary

Three findings dominate everything else in this audit, roughly in order
of how surprising they are:

1. **The numbers you're seeing (`3×3 @ 0 RIR`) are not a bug, a
   placeholder, or something Stage 10B invented.** They are the
   deterministic, unchanged output of a Stage 4A rule set
   (`FAMILY_A_REP_GOAL_SCHEDULE`) whose own source workbook does not
   survive in this repository. Reused verbatim by both the legacy
   2-exercise path and Stage 10B's day-focus path.
2. **The mesocycle those numbers belong to is, as implemented, a
   4-week ramp toward a near-1RM test, not an ongoing hypertrophy
   accumulation block** — reps step down (3→3→2→1) while load steps up
   (0.85→0.893→0.914→0.935× RM) every single week, **always to actual
   failure**, for every primary and secondary movement. There is no week
   in this design that looks like typical moderate-rep hypertrophy work.
3. **Two things needed to make this system "feel like getting stronger
   while building muscle" are currently either dormant or unreachable in
   production, independent of whatever the numbers should be:** (a)
   `ExercisePerformanceProfile.estimatedOneRepMax` — the value that seeds
   every load calculation — is **never written by any production code
   path**, only by seed/test fixtures; a real user has no way today to
   ever get a starting number. (b) The deload week (week 5 of the
   5-week `TrainingWeek` block) is **never reached with `isDeload: true`
   by the real week-rolling path** (`RollTacticalWindowUseCase.rollForward`
   hardcodes `isDeload: false`) — if a real mesocycle ever reaches week
   index 4, primary/secondary slots get no resolvable weight or rep
   goal at all (`.calibrationRequired`, silently), not a deload.

Separately, Stage 10B's own richer session shape genuinely does expose
a real autoregulation flaw: `HypertrophyFeedbackPrompts.pending(for:)`
only ever asks about **the one exercise every primary/secondary slot's
`pairedSlot` points at** (the day's single canonical accessory slot) —
so one soreness rating now silently drives the next week's set count
for every other primary/secondary movement that day, a fan-out that
didn't exist under the legacy 1-primary-slot design.

None of this is fixed in this pass. §16 lists correction options; §20
lists exactly the decisions that are yours to make before any of them
gets implemented.

---

## 2. Current prescription pipeline (traced end to end)

```
ExerciseSlot (allowedTargets/allowedMovementFunctions)
  │
  ├─ HypertrophyProgramGenerator.generate()          [template-graph construction, once]
  │     assigns: LoadRule, SetCountRule, RepGoal×4, DeloadExerciseAction, pairedSlot
  │     -> PrescriptionTemplate (frozen, reused unchanged every week)
  │
  ├─ ResolveProgramInstanceExerciseSlotsUseCase.resolve()   [once, at instance creation]
  │     ExerciseSlot -> concrete Exercise (deterministic, first-eligible-by-name)
  │
  ├─ StartPhaseUseCase.start() -> RollTacticalWindowUseCase.materializeFirstWindow()
  │     week 0 ONLY. isDeload: false (hardcoded).
  │     rmKilograms <- SubstitutionAwareRecommendation.resolve()
  │                     <- ExercisePerformanceProfile.estimatedOneRepMax  [NEVER WRITTEN IN PRODUCTION — see §7]
  │
  ├─ StrengthMaterializer.materializeWeek()          [called once per week, real dated rows]
  │     -> StrengthProgressionEngine.resolveWeight/resolveSetCount/resolveRepGoal
  │     -> ExercisePrescription + SetPrescription (targetWeight/repRange/targetRir)
  │
  ├─ [User executes the Session] -> StrengthExecutionView -> RecordSetResultUseCase.recordSet()
  │     writes: SetResult, PersonalRecord, ExercisePerformanceProfile.lastPerformedAt
  │     does NOT write: estimatedOneRepMax, confidence
  │
  ├─ [Optional] HypertrophyFeedbackView -> RecordAutoregulationFeedbackUseCase.recordRating()
  │     writes: ExercisePrescription.autoregulationRating (-1/0/+1)
  │     ONLY prompted for the slot every OTHER slot's pairedSlot points at — see §11
  │
  ├─ CompleteSessionUseCase.complete()
  │     -> DoubleProgressionEngine.recommend()  [display-only preview — see §7, dead end]
  │     -> CompletionSummary.progressionPreview  [never read by the materializer]
  │
  └─ RollTacticalWindowUseCase.rollForward()         [week N>0, real production rolling]
        weekIndex <- ProgramWeekGrouping.nextWeekIndex(for: instance)
        isDeload: false (hardcoded — see §13)
        weekOneResolvedWeightKg <- AutoregulationRatingResolver.weekZeroResolvedWeight()  [week 0's number, not week N-1's]
        previousWeekSetCount    <- AutoregulationRatingResolver.previousWeekSetCount()    [reads orderedSetPrescriptions, NOT executableSetPrescriptions]
        autoregulationRating    <- AutoregulationRatingResolver.rating()                  [reads the SHARED canonical accessory's rating — see §11]
        -> StrengthMaterializer.materializeWeek()  [loop closes back to itself]
```

Readiness (`EvaluateReadinessAdaptationUseCase`/`ReadinessAdaptationDecisionUseCase`)
sits entirely to the side of this loop — it mutates `isAdaptedAway` on
already-materialized `SetPrescription` rows for *today's* Session only,
and is never read by `AutoregulationRatingResolver` (confirmed by code,
not just by doc comment — see §12).

---

## 3. Rule provenance table

| Rule / constant | Value | Classification | Notes |
|---|---|---|---|
| `laterWeekMultipliers` | `[1.05, 1.075, 1.1]` | **B** — extracted legacy constant | `FAMILY_A_WEEKLY_PROGRESSION`; source workbook lost |
| `primaryWeekOneFactor` per phase | 0.85 / 0.75 / 1.0 | **B** | `FAMILY_A_WEEK1_BASELINE` |
| `repGoalSchedule` (primary/secondary) | `[(3,✓),(3,✓),(2,✓),(1,✓)]` | **B** | `FAMILY_A_REP_GOAL_SCHEDULE`; all 4 entries marked to-failure |
| `pairedRepGoalSchedule` (accessory) | `(12,✗)` × 4 | **B** | flat, never to-failure |
| `AutoregulatedSetCount(baselineSets: 3)` | 3 | **B** | Family A's documented baseline |
| `metaboliteFocusPairedWeekOneFactor` (0.6) | 0.6 | **B** for Metabolite Focus; **C** for its Stage 10B reuse | see next row |
| Stage 10B: ALL accessory slots use 0.6 `.rmBased`, every phase | 0.6 | **C** — implementation decision (D-10B-4), explicitly flagged in `STAGE10B_IMPLEMENTATION_REPORT.md` | reuses a sourced number outside its original documented scope |
| Stage 10B: autoregulation rating fan-out (shared canonical accessory) | — | **C** — implementation decision, flagged | see §6/§11 |
| Stage 10B: primary == secondary numeric rule | — | **C** — product decision D-10B-4, explicit | "no distinct secondary rule is sourced" |
| `toFailure == true` → `targetRir = 0` | 0 | **D** — mechanical/derived (Stage 6D) | not an independent number; a translation rule |
| `deloadRepFraction` default | 0.5 | **B** | "1/2 reps of Week 1," documented |
| Deload boundary/factors (no override) | `ceil(dayCount/2)`, 1.0×/0.5× | **B** | Family A's own unparameterized shape |
| `deloadSetCount` default | 2 | **B** for Family A; explicitly **C**/unconfirmed if ever reused for B/C | own doc comment flags this |
| `ExercisePerformanceProfile.estimatedOneRepMax` | — | **F** — dormant in production | only ever set via `init()`; no write site exists anywhere in `TrainingOS/Application`, `/Engines`, `/Domain` outside the initializer; seed/test fixtures are the only callers that ever populate it |
| Deload week materialization (`isDeload: true` path) | — | **F** — dead in the real rolling path | `RollTacticalWindowUseCase`'s only two production call sites hardcode `isDeload: false`; only test/seed fixtures ever exercise the deload branch |
| `DoubleProgressionEngine` | — | **F** for Hypertrophy's actual future prescriptions | fully implemented, reads real logged results, but wired only into a **display-only** `CompletionSummary.progressionPreview` — never read by any materializer |
| `HypertrophyFeedbackPrompts.pending(for:)` | — | **B**/**D** mechanism, **exposes a real gap under Stage 10B** | filters on `referencedAsPairedSlotBy` non-empty — correct as designed for 1 accessory : 1 primary; now 1 accessory : N primary/secondary |
| Stage 10B calf placement (Day A + C, 2×/week) | — | **C** — your own explicit product decision (Blocker 1 resolution) | not legacy, not sourced, an approved design decision |
| Stage 10B movement-function slot-intent constraints | — | **C** — reuses existing `MovementFunction`/`allowedMovementFunctions` seam | Blocker 2 resolution, no new field |
| Exercise-specific rep/load behavior | — | **F** — does not exist | see §10; the engine has no concept of it at all |

None of the **B** rows should be read as "therefore correct" — they're
sourced in the sense that this codebase already committed to them
before Stage 10B existed, not in the sense that anyone has re-verified
them against the original Family A material (which, again, doesn't
survive here).

---

## 4. Full Family A mesocycle — as implemented, primary vs. secondary vs. accessory shown separately

**Primary and secondary are numerically identical — shown together
below; the difference is stated explicitly.**

| Week | Load (primary/secondary, Basic Hypertrophy) | Sets (primary/secondary) | Reps (primary/secondary) | RIR (primary/secondary) |
|---|---|---|---|---|
| 1 | `RM × 0.85` | 3 (baseline) | 3 | **0 (to failure)** |
| 2 | `week1_resolved × 1.05` | `3 + rating` (rating from the shared canonical accessory — §11) | 3 | **0** |
| 3 | `week1_resolved × 1.075` | `week2_sets + rating` | 2 | **0** |
| 4 | `week1_resolved × 1.1` | `week3_sets + rating` | 1 | **0** |
| 5 (deload, template) | `week1_resolved × 1.0` (days 1–⌈n/2⌉) / `× 0.5` (remaining days) | fixed `2` | `floor(week1_reps × 0.5)` → **1**, still `toFailure: true` | **0**, unreached in production — see §13 |

| Week | Load (accessory) | Sets (accessory) | Reps (accessory) | RIR (accessory) |
|---|---|---|---|---|
| 1–4 | `0.6 × RM` independently tested (Stage 10B) / `0.6 × primary's own resolved weight` (legacy, Metabolite Focus excepted) | fixed `2` every week | fixed `12` | **not to failure** (`targetRir = nil`) |
| 5 (deload, template) | omitted entirely (`deloadWeightAction: .omit`) | omitted | omitted | — |

**"If secondary currently just inherits primary, show that explicitly"
— it does, completely.** `makeDayFocusTemplate(role:targets:configuration:)`
has one shared branch for `case .primary, .secondary:` — same
`RMBasedLoad`, same `AutoregulatedSetCount`, same `repGoalSchedule`.
Nothing in the type system or the generator distinguishes them
numerically; `SlotRole` currently only affects *which slots exist and
in what order*, never *how hard they're prescribed*.

---

## 5. What Family A appears to be designed for

Read strictly off the implemented rules, week over week:

- **Reps go down** (3 → 3 → 2 → 1) while **load goes up** (+5% → +7.5% →
  +10%, compounding off a fixed week-1 anchor) — and **every single
  week is to actual failure** for primary/secondary. That combination —
  fewer reps, heavier weight, always maximal effort, culminating in a
  literal 1-rep-to-failure test in week 4 — is the shape of a **top-set/
  RM-testing ramp**, not hypertrophy accumulation. A genuine hypertrophy
  accumulation block would typically hold reps in a moderate band across
  most sets and vary proximity-to-failure across the week/mesocycle, not
  drive every single working set to failure while also cutting reps to
  one.
- **Accessory work is the opposite pattern**: fixed volume (2×12),
  fixed load percentage, never to failure — closer to a genuine
  hypertrophy/pump-style accessory prescription, but static across all
  4 weeks (no progression signal at all beyond the load's own %RM
  scaling with the primary's week-to-week multiplier under the legacy
  `linkedToPairedSlot` design; Stage 10B's independent `.rmBased`
  version doesn't even get that — it just runs the same 1.05/1.075/1.1
  ramp off its own 0.6×RM anchor).
- **It is internally inconsistent as a single "Hypertrophy" system**:
  the primary/secondary movements — the ones actually named "Horizontal
  Push," "Squat Pattern," etc., carrying most of the session's stimulus
  — behave like a strength-peaking/RM-testing block; the accessories
  behave like a moderate-rep hypertrophy block. Naming the whole
  generator/programming system "Hypertrophy" describes neither half
  precisely, and describes the primary/secondary half least of all.

**Week-by-week narrative** (primary/secondary): Week 1 — heavy-ish
(85% of tested max), very low reps (3), pushed to a real failure point;
the user's very first exposure to this exercise this mesocycle is a
near-maximal effort. Week 2 — load rises another 5%, reps unchanged,
still to failure — objectively harder than week 1. Week 3 — load rises
further, reps drop to 2, still to failure. Week 4 — load peaks at 93.5%
of the *original* tested max (not re-tested), for a single rep, to
failure — this is functionally a 1RM attempt, not a training set. Week
5 (deload, as designed but unreached in production — §13) backs load
off to 100%/50% of week 1's number for 1 rep at "to failure" — a
contradiction in the template itself (§15, item 2): a deload week whose
rep target is still marked to-failure.

---

## 6. Set progression — exact mechanics, and the Stage 10B fan-out flaw

`AutoregulatedSetCount(baselineSets: 3)`:
- **Week 0**: always exactly `baselineSets` (3), unconditionally.
- **Week N>0**: `max(0, previousWeekSetCount + autoregulationRating)`,
  where `autoregulationRating ∈ {-1, 0, +1}` (UI-enforced, not
  schema-enforced — `RecordAutoregulationFeedbackUseCase` accepts any
  `Int`).

**Examples** (starting from week 1's baseline of 3):
- Excellent recovery / easy session → user rates `+1` → week 2 gets 4
  sets.
- Appropriate difficulty → rates `0` → week 2 stays at 3.
- Excessive difficulty → rates `-1` → week 2 drops to 2.
- Poor readiness → readiness adaptation may reduce *today's* executable
  sets (`isAdaptedAway` on the last N `SetPrescription` rows), but this
  is invisible to `previousWeekSetCount` (§12) — next week's baseline is
  computed from the **original**, non-adapted count.
- Partial completion / skipped sets → nothing in this mechanism reads
  what was actually *completed* vs. *prescribed* — only the explicit
  `-1/0/+1` rating, submitted separately via `HypertrophyFeedbackView`,
  matters. A user who silently skips a set without ever submitting a
  rating leaves `autoregulationRating == nil`, and `resolveSetCount`
  returns `.calibrationRequired` (no set count at all) for the next
  week, for **every slot whose `pairedSlot` points at that unrated
  exercise** — see below.

**Scope: exercise-specific slot, but the rating SOURCE is shared.**
Volume progression is: session-local set counts, computed **weekly**,
per-**slot** (each `PrescriptionTemplate` has its own running set
count) — but the **feedback input** driving that per-slot computation
is not per-slot. `HypertrophyFeedbackPrompts.pending(for:)` only
surfaces a rating prompt for the one `ExercisePrescription` whose
template is *itself* the target of some other template's `pairedSlot`
(`template.referencedAsPairedSlotBy` non-empty). Under Stage 10B's
day-focus construction, **every** primary/secondary template's
`pairedSlot` points at the **same one** canonical accessory template
(the day's first accessory slot — biceps, by construction order). That
means:

- Only **one exercise per day** (the canonical accessory) is ever asked
  "how did this feel?"
- That single rating is read by `AutoregulationRatingResolver.rating(for:)`
  for **every** primary/secondary template that day (Squat, Horizontal
  Push, Hinge Pattern, Back — 4–6 slots), because they all share the
  same `pairedSlot` reference.
- **A user who rates the biceps accessory "very sore" gets Back Squat's,
  Bench Press's, Romanian Deadlift's, and Barbell Row's set counts all
  reduced together next week — regardless of how those specific lifts
  actually felt**, and the reverse: those 4 lifts are never individually
  askable at all.

**This is confirmed to be a real flaw the richer Stage 10B session shape
exposes, not merely a hypothetical.** Under the legacy 1-primary+
1-accessory design, this exact same fan-out mechanism was 1:1 by
construction — asking about the one accessory *was* asking about the
one thing whose feedback mattered. Stage 10B's variable slot count
turned a correct 1:1 design into an incorrect 1:N one without any
change to the feedback-collection mechanism itself.

---

## 7. Rep progression

Governed entirely by `rules.repGoalSchedule[weekIndex]` — a flat,
per-slot-role array, indexed by week only. No exercise-specific, no
performance-specific, no readiness-specific variation exists in this
lookup. Primary/secondary: `3, 3, 2, 1` (all to-failure). Accessory:
`12, 12, 12, 12` (never to-failure). There is no mechanism anywhere that
would let, say, Romanian Deadlift use a different rep target than Back
Squat, even though both currently sit in the "primary"/"secondary" role
on different days.

---

## 8. Load progression — audited against the stated product principle

**Product principle under audit:** *"For hypertrophy progression,
prioritize visible LOAD progression over merely accumulating more reps
when both are reasonable... the user should feel that they are getting
stronger while building muscle."*

**What actually determines the next prescription, concretely** (Bench
Press, user completes 100kg for the prescribed reps at target RIR):

**Nothing about what the user did changes next week's number.** Next
week's weight is `week1_resolved_weight × laterWeekMultipliers[weekIndex-1]`
— a fixed schedule, computed **before** the user ever performs week 1,
and never re-derived from any logged `SetResult`. Whether the user
crushed week 1 or barely survived it, week 2's load is the same
formula-driven number either way (`StrengthProgressionEngine.resolveWeight`'s
`.rmBased` branch for `weekIndex > 0` takes only `weekOneResolvedWeightKg`
— confirmed, no branch reads `latestResults`/actual performance at all).

So, directly: **TrainingOS does not "add reps first" or "add weight
first" or "combine these" in response to performance, for load.** It
follows a **fixed weekly percentage schedule**, full stop, for load.
The only performance-reactive lever that exists at all is **set count**
(§6), and even that reacts to an explicit user rating, not to the
logged reps/weight/RIR directly.

**A separate, real, working, performance-reactive engine exists**
(`DoubleProgressionEngine` — add weight if every set hit the top of its
rep range at/above target RIR; hold if any set missed the bottom;
otherwise expect reps to advance) — but it is wired **only** into
`CompleteSessionUseCase`'s `progressionPreview`, which the codebase's
own doc comment states explicitly is never written back to any
`SetPrescription`. It produces a **message shown after finishing a
session** ("next time, try X") that has **zero effect** on what
actually gets prescribed. Two independent progression narratives exist
side by side without ever talking to each other.

**Direct answer to the audited principle: no, the current engine does
not deliver "visible load progression that responds to what you
actually did."** It delivers *scheduled* load progression that happens
to go up every week regardless of performance — which will *look like*
progression on screen, but isn't contingent on genuinely getting
stronger, and provides no mechanism to hold, back off, or accelerate
based on what actually happened.

---

## 9. RIR / failure logic — audited directly, not softened

**What `toFailure` means, exactly:** `RepGoal.toFailure: Bool`. When
`true`, `StrengthMaterializer` sets `SetPrescription.targetRir = 0`
directly — "to failure is definitionally RIR 0," per this codebase's
own Stage 6D doc comment. This is a **hard, direct, mechanical
translation** — there is no softening, no per-exercise override, no
"unless this is a compound lift" branch anywhere in the materializer or
generator. It's the same 0 for every slot whose `repGoalSchedule` entry
says `toFailure: true`.

**Every week's target for primary/secondary, verified against the
schedule:** week 1 → RIR 0, week 2 → RIR 0, week 3 → RIR 0, week 4 →
RIR 0. **All four progressive weeks.** The deload week's *template*
also carries `toFailure: true` through unchanged (§4/§13) — the deload
mechanism reduces reps and (partially) load, but never touches the
failure flag, so even the deload prescription still reads "1 rep, to
failure" in the source rules, though it's currently unreachable in
production regardless (§13).

**Yes — under the current, unmodified rules, Back Squat, Romanian
Deadlift, Bench Press, and Barbell Row are genuinely prescribed to 0
RIR (true failure) every week, under normal healthy readiness, with no
readiness-driven exception.** Readiness/adaptation can reduce *set
count* or substitute the exercise entirely if pain is reported (§12),
but nothing in `EvaluateReadinessAdaptationUseCase` ever touches
`targetRir`. A perfectly healthy, well-rested user following this
program as designed trains every primary/secondary compound lift to
literal failure, every single week, for the entire 4-week block.

Autoregulation (§6) never modifies RIR either — it only ever adjusts
set *count*. Accessories are the sole exception, and only because their
`repGoalSchedule` never sets `toFailure: true` in the first place — not
because of any readiness or autoregulation logic.

---

## 10. Primary vs. secondary vs. accessory — is the current 3-role split sufficient?

**As implemented, primary and secondary are prescribed identically in
every numeric respect.** The only place the distinction currently has
teeth is construction-time: which muscle groups populate the tier, and
therefore slot ordering (§9 of the implementation plan) and coverage
accounting (§6 of that plan). Nothing about *how hard* a secondary slot
is trained differs from a primary one.

**Is that defensible?** Partially, and only by accident of what Family
A's rules already are: since there is no sourced, distinct numeric
rule for "secondary" anywhere in this codebase's surviving material,
reusing primary's rule verbatim is the only non-invented choice
available under CLAUDE.md rule 10 — this was already decided (D-10B-4)
and is not being reopened here. But that's a statement about what's
*permissible without inventing a number*, not a statement about whether
identical prescriptions are *actually the right design* for a role
you've explicitly said should mean "important supporting movement"
rather than "the day's main event." As implemented, `SlotRole` answers
"what order does this get trained in and how is weekly coverage
counted" — it does not yet answer "how much should this specific
movement cost the user today," which is presumably closer to what
"secondary" is meant to convey.

**Accessory is more clearly differentiated** — different load
mechanism, different (fixed) set/rep shape, never to failure — but that
differentiation is Family A's own long-standing accessory/paired-slot
design, not something Stage 10B added; Stage 10B only generalized *how
many* accessory slots exist per day.

**What distinction would actually be useful**, without introducing
compound/isolation as a required domain concept: the smallest
change that would let primary/secondary diverge *without* inventing new
numbers is letting **set count** (not load, not reps, not RIR) differ —
e.g. primary keeps `baselineSets: 3`, secondary uses a smaller
baseline. This has no sourced number to cite either, so it would need
to go through the same "flag, don't invent" discipline as everything
else in this document — listed as an option in §16, not a
recommendation.

---

## 11. Exercise-specific rep behavior

**Confirmed: this concept does not exist anywhere in the current
engine.** Rep behavior is **program-family-and-slot-role-wide**, full
stop — never exercise-specific, never movement-pattern-specific, never
user-performance-specific. `RepGoal`/`repGoalSchedule` live on
`PrescriptionTemplate` (one per slot, generated once), not on `Exercise`
itself, and nothing reads `Exercise.movementPattern`/`primaryTargets`/
`movementFunctions` when resolving a rep target. Concretely: Back
Squat, Romanian Deadlift, Bench Press, and Barbell Row — four
biomechanically different lifts — all currently receive the identical
`3,3,2,1`-to-failure schedule purely because they all happen to occupy
a "primary" or "secondary" slot. Lateral Raise, Barbell Curl, Cable
Triceps Pushdown, and Calf Raise all currently receive the identical
`12,12,12,12`-non-failure schedule purely because they occupy
"accessory" slots — despite being four exercises many practitioners
would treat differently (e.g. calf raises are frequently trained at
higher reps than curls).

**Minimum abstraction required, if this is judged too blunt (design
question, not a recommendation to build it):** the smallest generic
concept that could express "this specific exercise/movement pattern
prefers a different rep zone than its slot role's default" without
inventing a full training-science ontology would be a single optional
override — e.g. an `Exercise`-level or `ExerciseSlot`-level rep-range
hint that the generator consults *before* falling back to the slot
role's own schedule. This is listed as an option in §16 and a decision
in §20 — not something this audit is recommending be built.

---

## 12. Feedback / autoregulation — mechanism, and where it actually reaches

Fully covered in §6 for the mechanism itself. Restated for this
section's specific focus: **feedback collection is real, persisted, and
narrow** — one `-1/0/+1` rating per eligible prescription, collected
via `HypertrophyFeedbackView` right before `CompleteSessionUseCase`
finalizes the Session (skippable in the sense that a Session with no
pending prompts — `HypertrophyFeedbackPrompts.pending(for:)` empty —
skips straight to `finish` with no screen shown at all; not skippable
once shown, no explicit "skip" affordance was found in
`HypertrophyFeedbackView` itself). It writes exactly one field
(`ExercisePrescription.autoregulationRating`) and nothing else.

---

## 13. Readiness vs. programming — is the separation actually preserved?

**Yes, confirmed by code, not merely by doc comment.**
`ReadinessAdaptationDecisionUseCase.accept`'s `.setCountReduced` branch
marks the **last N** `SetPrescription` rows `isAdaptedAway = true` —
it never deletes rows, never touches `orderedSetPrescriptions` (the
full original list survives, per CLAUDE.md rule 1's own discipline).
Separately, `AutoregulationRatingResolver.previousWeekSetCount(for:in:)`
reads `prescription.orderedSetPrescriptions.count` — **the full,
non-adapted-away-filtered list**, never `executableSetPrescriptions.count`.
This means a same-day readiness-driven reduction is structurally
invisible to next week's autoregulated baseline. A poor readiness day
reduces *today's* executable work and nothing else; it cannot, by this
mechanism, silently rewrite next week's programming. This is the
correct separation your product principle asks for, and it already
holds.

**Concretely, by scenario:**
- **Normal readiness** (all-good check-in, or skipped): no proposal is
  generated (`EvaluateReadinessAdaptationUseCase.evaluate` returns an
  empty proposal); today's prescription runs exactly as materialized;
  next week's set-count baseline comes only from the explicit
  post-session rating (§6), untouched by today's readiness.
- **Low energy** (a single poor Tier-0 signal): proposes a `-1`-set
  reduction on eligible exercises (session count > 1); if accepted,
  reduces *today's* executable sets only, per the mechanism above; next
  week's autoregulation baseline is unaffected.
- **Pain/stiffness** near a trained muscle group: proposes substitution
  (if a valid, non-painful alternative exists for the slot) or a
  volume reduction / block removal (§ per the existing Stage 8B
  escalation ladder) — again, session-local; never touches
  `estimatedOneRepMax`, never touches next week's `repGoalSchedule`
  index, never touches `laterWeekMultipliers`.

The one thing this section flags for your awareness, not as a
violation: because `estimatedOneRepMax` is never updated by anything
(§7 finding), there is currently *no* mechanism, readiness-driven or
otherwise, by which a bad week (or a great one) ever changes the load
side of the ongoing formula at all, across mesocycles or within one.
The separation you're asking about is preserved for the wrong reason,
in a sense — programming isn't being protected from readiness so much
as it isn't listening to anything at all once week 1's number is set.

---

## 14. Deload

**Exact behavior, per role, when the deload branch actually runs**
(confirmed only reachable via test/seed fixtures — see below):

| | Primary/secondary | Accessory |
|---|---|---|
| Sets | fixed `2` (`deloadSetCount`, never autoregulated) | omitted (`deloadWeightAction: .omit` / `deloadRepAction: .omit`) |
| Reps | `floor(week1_reps × 0.5)` = `floor(3 × 0.5)` = **1** | omitted |
| Load | `week1_resolved × 1.0` for the first `⌈dayCount/2⌉` days, `× 0.5` for the rest | omitted |
| RIR | still `toFailure: true` from week 1's own rep goal → **still RIR 0** | omitted |
| Exercise continuity | unaffected — same slot, same resolved exercise, no reroll | unaffected |

**What triggers the deload, as designed:** purely positional — a fixed
5th `TrainingWeek` marked `isDeload: true` at generation time. Not
readiness-driven, not performance-driven, not a planner decision — a
static schedule position.

**What actually happens in production today:** `RollTacticalWindowUseCase`'s
only two call sites that materialize a week (`materializeFirstWindow`
for week 0, `rollForward` for week N>0) both hardcode `isDeload: false`.
Neither reads the `TrainingWeek.isDeload` flag the generator itself
already set on the 5th week. **If a real `ProgramInstance` is rolled
forward to `weekIndex == 4`, it runs the non-deload branch of
`StrengthMaterializer.materializeWeek`**, which calls
`StrengthProgressionEngine.resolveWeight(weekIndex: 4, ...)`. That
function's `.rmBased` case computes `multiplierIndex = weekIndex - 1 = 3`
against `laterWeekMultipliers` (3 elements, valid indices 0–2) — index 3
is out of bounds, so it returns `(nil, .calibrationRequired)`.
`resolveRepGoal` independently checks `repGoalSchedule.indices.contains(4)`
against a 4-element array — also out of bounds, also
`.calibrationRequired`. **Week 5 of a real Hypertrophy mesocycle, if
reached via the real rolling path, currently produces no resolvable
weight and no resolvable rep goal for any primary/secondary slot** —
not a deload, an empty/broken week. (Set count would still resolve,
since `.autoregulated` doesn't index against a fixed-length array.)

I have not independently confirmed whether the tactical-window/phase
transition logic actually lets a single `ProgramInstance` reach week
index 4 in normal operation before rolling into a new phase/instance —
that would need its own trace of `TacticalWindowPolicy`/phase-transition
timing, which is outside this audit's traced scope. Flagged as
something to confirm before treating this as either "never happens in
practice" or "definitely happens" — right now it's a **reachable code
path with a confirmed bad outcome**, not a hypothetical.

**Is deload behavior coherent with the richer Stage 10B program?**
Independent of the above reachability bug: the deload *template* itself
(when it does run, e.g. in tests) still marks reps `toFailure: true`
(§4) — a genuine inconsistency in the sourced rule itself, not
something Stage 10B introduced, but worth noting since Stage 10B's
richer sessions make more slots hit this same inconsistency
simultaneously (4-6 primary/secondary slots all "deloading to 1 rep to
failure" instead of 1).

---

## 15. Worked Stage 10B Day A mesocycle

Exercises are the **actual generated resolution** confirmed in
`STAGE10B_IMPLEMENTATION_REPORT.md` against the real seed catalog:
Barbell Bench Press (Horizontal Push, primary), Back Squat (Quadriceps,
primary), Romanian Deadlift (Hinge Pattern, secondary), Barbell Row
(Back, secondary), Barbell Curl / Cable Triceps Pushdown / Calf Raise
(accessory). RM input used for illustration: 100kg for every
primary/secondary movement (matching the report's own worked example).

| Week | Bench Press | Back Squat | Romanian Deadlift | Barbell Row | Barbell Curl | Cable Triceps Pushdown | Calf Raise |
|---|---|---|---|---|---|---|---|
| 1 | 3×3 @85.0kg, RIR0 | 3×3 @85.0kg, RIR0 | 3×3 @85.0kg, RIR0 | 3×3 @85.0kg, RIR0 | 2×12 @60.0kg | 2×12 @60.0kg | 2×12 @60.0kg |
| 2 | 3or4×3 @89.25kg, RIR0 | same | same | same | 2×12 @63.0kg | 2×12 @63.0kg | 2×12 @63.0kg |
| 3 | ...×2 @91.4kg, RIR0 | same | same | same | 2×12 @64.5kg | 2×12 @64.5kg | 2×12 @64.5kg |
| 4 | ...×1 @93.5kg, RIR0 | same | same | same | 2×12 @66.0kg | 2×12 @66.0kg | 2×12 @66.0kg |
| 5 | **`.calibrationRequired` — no weight, no rep goal (§13/14)** | same | same | same | omitted | omitted | omitted |

(Week 2-4 set counts for the 4 primary/secondary movements all move
together, because all 4 share the exact same autoregulation rating
source — the biceps accessory slot, per §6's fan-out finding. Load
numbers for weeks 2-4 use the exact `×1.05/×1.075/×1.1` multipliers off
week 1's own resolved 85.0kg.)

**Behavior I consider suspicious or unsupported, concretely visible in
this table:**
1. Four biomechanically different, high-skill compound lifts (a
   horizontal press, a squat, a hip hinge, a horizontal pull) converge
   on the exact same load-and-rep trajectory, purely because they share
   a slot-role tier — not because anyone decided that's correct for
   each of them specifically (§10/§11).
2. Every one of those four lifts is prescribed to literal failure, four
   weeks running, with no de-load relief until a week that currently
   never resolves (§13/§14).
3. One soreness rating on the biceps curl silently sets next week's set
   count for all four compound lifts (§6).
4. Week 4's number (93.5kg for a 1-rep, to-failure set) is presented
   with the same visual confidence (`3×3 @ 0 RIR`-style formatting) as
   week 1's — nothing in the UI or the underlying data currently flags
   "this is effectively a 1RM test," which materially changes how a
   user should approach it versus a normal working set.
5. Week 5 silently produces no prescription at all for these four
   lifts if actually reached (§13).

---

## 16. Minimum viable correction options (not implemented, not recommended over each other)

Presented as a menu — none of these are being applied in this pass.

- **A. Do nothing to the numbers; fix only the two dormant/broken
  mechanisms** (populate `estimatedOneRepMax` from somewhere real; make
  `rollForward` respect `TrainingWeek.isDeload`). Leaves the
  RM-testing-ramp character of Family A completely intact, but at least
  makes the currently-inert half of the system actually run.
- **B. Change only the autoregulation feedback-source wiring** (e.g.
  ask about the day's genuinely hardest primary lift instead of a fixed
  canonical accessory, or ask about each slot independently) — narrowly
  fixes the Stage 10B fan-out (§6) without touching load/rep/RIR numbers
  at all.
- **C. Add a rep-range/RIR-trajectory concept sourced from real Family
  A material**, if it can be found/reconstructed, rather than external
  evidence — closest to "resolve the audit's central question
  correctly" but depends on a source this repository doesn't currently
  have.
- **D. Adopt an explicitly-labeled TRAININGOS-DESIGNED replacement**
  for Family A's primary/secondary numbers, informed by (not copied
  from) the external evidence in §17 — the option that most directly
  answers your stated principle ("visible load progression... feel
  stronger while building muscle") but requires you to explicitly
  approve inventing numbers this repository doesn't source, which is
  exactly what CLAUDE.md rule 10 asks me to stop and flag rather than
  decide.
- **E. Leave Family A's numbers alone but add a small, generic
  slot-role-or-exercise-level override seam** (§10/§11) so a *future*
  decision can differentiate primary/secondary/exercise-specific
  behavior without another audit — infrastructure only, no new
  numbers.

These are not mutually exclusive.

---

## 17. External evidence — kept explicitly separate from repository authority

**Three things, kept separate as instructed:**

**(1) What TrainingOS currently implements:** primary/secondary trained
to literal failure (0 RIR) every week for 4 weeks, reps stepping down
3→3→2→1, load stepping up ~5%/7.5%/10% per week off a fixed week-1
anchor (§4-§9 above).

**(2) What the lost/legacy Family A rules imply:** a top-set/RM-testing
ramp, not stated anywhere in this repository as an explicit hypertrophy
philosophy — it's simply what the surviving numbers produce (§5).

**(3) What external evidence suggests** (I do have web search access
this pass; used it narrowly, for exactly this question, and report only
what came back — no invented citations):

- A systematic review with meta-analysis on proximity-to-failure and
  hypertrophy found "a trivial advantage for resistance training
  performed to set failure versus non-failure," and that "stopping 1 to
  3 reps short of failure produced essentially the same muscle growth
  as grinding to failure, with less fatigue." ([Influence of Resistance
  Training Proximity-to-Failure on Skeletal Muscle Hypertrophy: A
  Systematic Review with Meta-analysis](https://pubmed.ncbi.nlm.nih.gov/36334240/))
- A more recent dose-response meta-regression found strength gains
  similar across a wide range of RIR, while hypertrophy improves
  somewhat as sets get closer to failure, with a meaningful hypertrophy
  drop-off only beyond roughly 4-5 reps short of failure — i.e. training
  to *exactly* 0 RIR every set is not shown to be necessary for
  hypertrophy outcomes, only "reasonably close." ([Exploring the
  Dose-Response Relationship Between Estimated Resistance Training
  Proximity to Failure, Strength Gain, and Muscle Hypertrophy: A Series
  of Meta-Regressions](https://pubmed.ncbi.nlm.nih.gov/38970765/))
- Schoenfeld & Grgic's loading meta-analysis: low-load training taken
  to failure produces similar whole-muscle hypertrophy to high-load
  training, with the important caveat that the *low-load* condition
  still needs to be taken close to failure to match — and that maximal
  *strength* (not hypertrophy) is where heavy, low-rep, near-1RM work
  earns its keep. ([Strength and Hypertrophy Adaptations Between Low-
  vs. High-Load Resistance Training: A Systematic Review and
  Meta-analysis](https://pubmed.ncbi.nlm.nih.gov/28834797/))

Read together, external evidence doesn't say Family A's ramp is
"wrong" for producing *some* stimulus — near-failure heavy work is a
legitimate part of the literature. It does suggest the specific shape
here (reps collapsing to 1 by week 4, at failure, every single week,
with no rep-range variety and no accumulation phase at moderate reps)
reads more like a strength/peaking block borrowed wholesale into a
system labeled "Hypertrophy," than like what the cited hypertrophy
literature would call a hypertrophy-optimized loading scheme.

**This external evidence must not, and has not, become production
logic in this pass.** It's presented only to help you judge whether
options C/D in §16 are worth pursuing, and in what direction.

---

## 18. Risks of changing the model

- **Breaking the only currently-tested numeric contract.** Every
  existing test that asserts `weekOneFactor`, `laterWeekMultipliers`,
  or `repGoalSchedule` values (across `HypertrophyProgramGeneratorTests`,
  `StrengthMaterializerTests`, `HypertrophyDayFocusGenerationTests`, and
  more) would need deliberate, reviewed updates — changing these
  numbers is not a small diff even before considering training-science
  correctness.
- **Silently changing history.** CLAUDE.md rule 1/19d-style discipline
  applies: any change must never reinterpret already-materialized,
  already-logged weeks for real users — a formula change must only
  ever apply going forward.
- **Fixing the dormant mechanisms (§7/§13) without also revisiting the
  numbers could make things *worse* in a visible way**: if
  `estimatedOneRepMax` starts actually getting populated/updated, and
  `rollForward` starts actually respecting `isDeload`, users will begin
  *actually experiencing* the literal-failure-every-week ramp this audit
  describes, for the first time, in a way the current (partially inert)
  system never let anyone feel. Sequencing matters — §20 asks you to
  decide which fix goes first.
- **Overcorrecting into an invented, unsourced replacement** (option D)
  risks exactly the "generic internet-style 3×8-12" outcome you
  explicitly said you don't want, if it's not designed carefully and
  labeled honestly as TRAININGOS-DESIGNED rather than as if it were
  recovered Family A material.

## 19. Migration / backward-compatibility implications

No real user data exists yet in production (confirmed throughout this
project: this app has no shipped users, only seed/dev fixtures) — so
"migration" here means: any numeric change only needs to not corrupt
already-logged Simulator/dev history, and per CLAUDE.md rule 1 must
never retroactively rewrite an already-materialized week's
`SetPrescription` rows. A `generatorVersion` bump (the existing,
already-proven mechanism used for Stage 10B's own day-focus/legacy
split) is the natural seam for introducing a new numeric model
alongside the old one without touching already-generated
`ProgramDefinition`s.

## 20. Exact product/training-science decisions required from you

1. **Is the top-set/RM-testing-ramp character of Family A (§5) actually
   the intended TrainingOS hypertrophy philosophy**, or should it be
   replaced? (Determines whether §16 option A/B or C/D/E is even in
   scope.)
2. **Should primary and secondary ever diverge numerically** — and if
   so, is a set-count-only distinction (§10) the right minimal lever, or
   do you want something else?
3. **Should exercise-specific rep behavior be introduced** (§11), and if
   so, at what granularity — per-`Exercise`, per-movement-pattern, or
   left as a future decision?
4. **How should the autoregulation feedback-source fan-out (§6) be
   resolved** — ask about every primary/secondary slot independently
   (more prompts), pick a different single representative slot per day,
   or something else?
5. **Should `estimatedOneRepMax` ever be populated from real logged
   performance**, and if so, by what mechanism (a dedicated calibration
   flow, an estimation formula off logged sets, a manual entry, or
   something else) — this is a decision this audit explicitly did not
   make.
6. **Should the deload week's reachability bug (§13/§14) be fixed as a
   pure bug-fix** (make `rollForward` respect `isDeload`, no numeric
   change), independent of whatever else changes about the numbers
   themselves?
7. **Should the deload week's `toFailure: true` carry-through (§4/§14)
   be treated as its own defect**, independent of the broader RIR
   question in decision 1?
8. **How much weight should the external evidence in §17 actually
   carry** — informative context only, or license to design a
   TRAININGOS-DESIGNED replacement explicitly departing from Family A's
   surviving numbers?
9. **Sequencing** (§18): if multiple fixes are approved, which order —
   dormant-mechanism fixes first, numeric-model fixes first, or
   together in one pass?

**Do not implement any of the above. Do not commit. Do not push. Do
not start Stage 10C.** Waiting for your direction on the decisions
above.
