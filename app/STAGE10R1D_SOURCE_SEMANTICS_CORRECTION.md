# Stage 10R.1D — Source Semantics Correction (Report Only, No Implementation)

**STATUS: REPORT ONLY.** No code changed. This documents a corrected
understanding of the source notation and the resulting architecture
implications, per your explicit instruction not to implement yet.

## Independent verification attempted first

Before accepting the correction, I checked whether I could verify it
against the raw workbook data I already hold (not the companion
instructions, which I don't have access to). Two findings:

1. **No instructional text exists inside any of the 15 xlsx files.** I
   re-searched the full raw cell extraction for "RIR," "reps in
   reserve," "reps from failure," "good rep," "technique" — zero
   matches, in any workbook. The workbooks are pure data/formula sheets;
   they never explain what their own notation means. I cannot confirm
   or refute Rule 1 directly from the workbook text itself — it
   genuinely requires the companion material you've recovered.
2. **However, I found direct, independent workbook evidence supporting
   Rule 2's core claim** (that the rep-goal field has more than one
   semantic form) — this I can verify myself: `powerlifting_str4day`'s
   Triples rows carry a literal, explicit fixed-rep-per-set list in a
   separate cell (`J7: VALUE='3,3,3'`), structurally distinct from the
   "N/fail" notation used on every ordinary row (`D8: VALUE='2/fail'`).
   The workbook author clearly used two different notations for two
   different concepts. This does not, by itself, prove "/fail" means
   "reps from failure" specifically, but it independently confirms the
   underlying structural claim your correction rests on: "/fail" and a
   literal rep count are NOT the same kind of field, and the current
   TrainingOS model collapses them into one.

Per the "PERMANENT SOURCE INTERPRETATION RULE": I found no case where
literal workbook data *contradicts* the corrected semantics — only a
case (above) that independently corroborates part of it. Proceeding to
accept the correction as authoritative, as instructed, while being
explicit about what I could and couldn't verify myself.

**This also applies beyond Family A.** Both Family B (`powerlifting_str4day`)
and Family C (`powerlifting_hyp5day`) use the identical "N/fail" notation
(`1/fail`, `2/fail`, `3/fail` — confirmed directly in both files). This
correction is therefore NOT scoped to the 3-Day Full Body Hypertrophy
config alone — it applies to every Family A/B/C `.rmBased` slot already
implemented, including the legacy 5-day path and Powerlifting.

## Corrected source semantics (restating your rules with my analysis)

1. **`N/fail` = RIR N**, not "N reps then continue to failure." Stop the
   set with approximately N good-technique reps still available.
   Confirmed self-consistent with the recovered Mesocycle 1 schedule
   (`3/fail, 3/fail, 2/fail, 1/fail`): this now reads as RIR 3 → RIR 3 →
   RIR 2 → RIR 1 — a standard, textbook autoregulated-effort ramp
   (constant-then-intensifying proximity to failure across the block),
   which is a far more coherent progression story than "always train to
   literal failure, only the target rep count shrinks" (the old
   reading, which never had a clear mechanism for "why would week 1 not
   just also be lower-rep-to-failure").
2. **The rep-goal field has ≥2 distinct semantic kinds**: a literal fixed
   rep count (e.g. Powerlifting's `3,3,3` Triples rows) and an
   effort/RIR target (`N/fail`). Independently confirmed above. The
   current `RepGoal(reps:Int, toFailure:Bool, repRangeHigh:Int?,
   targetRir:Int?)` shape cannot honestly represent both without forcing
   a fabricated `reps` value onto the RIR case.
3. **Actual performed reps are an output of (load, RIR target,
   athlete-on-the-day), never a predetermined input** for an `N/fail`
   slot. The current implementation writes the literal "3" straight into
   `SetPrescription.repRangeLow`/`repRangeHigh`, displaying it in the UI
   as if it were the prescribed target — this is exactly the
   "fake fixed rep target" Rule 3 names.
4. **10RM is a real-or-estimated reference value, not a mandated formal
   test.** The calibration screen I built (Stage 10R.1C) currently says
   "This program requires your current **tested** weight" and offers "I
   need to **test this first** — perform a real 10-rep-max **attempt**"
   — this language overstates what the source requires and is a real,
   separate defect to fix (see Part 4 below).
5. **A Week-1 load-calibration band exists**: after the first working
   set(s), ≤6 reps achieved at the prescribed RIR → the entered/reference
   10RM was too heavy (lower it); >12 reps → too light (raise it);
   otherwise the anchor is workable, and later-week fatigue-driven rep
   drops don't by themselves trigger recalibration. This is a genuinely
   new mechanism — nothing in the current architecture reads "actual
   reps just performed" to suggest a 10RM correction.
6. **Load-first design must be grounded in how the source already
   separates** 10RM anchor → % load formula → RIR-based effort target →
   actual performed reps (output) → post-session rating → next-week set
   count, before designing any TrainingOS-side load bias.
7. **Warm-up is confirmed already correct** — see Part 6. No action
   needed here.

## Part 1 — What existing (already-accepted) work is wrong

This is not a new-feature question; it's a **correctness defect in
already-manually-accepted work**:

- **Stage 10R.1 Slice 1B** (`HypertrophyProgramGenerator.repGoalSchedule`):
  `[RepGoal(reps:3,toFailure:true), RepGoal(reps:3,toFailure:true),
  RepGoal(reps:2,toFailure:true), RepGoal(reps:1,toFailure:true)]`. Under
  the corrected reading this should represent RIR 3/3/2/1, not "3/3/2/1
  reps, then continue to true failure." `StrengthMaterializer`'s
  `targetRir = repGoal?.targetRir ?? (toFailure ? 0 : nil)` then derives
  **RIR 0** for every week — which is the specific, concrete wrong
  number your manual test actually saw on screen ("Set 1 of 3 · 3 reps ·
  0 RIR" — you accepted this screen at the time, reasonably, since
  nothing available then contradicted it).
- **Same defect, same shape, in the legacy 5-day Family A path and both
  Powerlifting families** — they share the identical `RepGoal(reps:N,
  toFailure:true)` pattern for every "N/fail" slot (confirmed via direct
  code read: `PowerliftingProgramGenerator.swift` builds its `ordinaryRepGoal`
  from the same shape). This was wrong before Stage 10R.1 too — Stage
  10R.1 didn't introduce it, but it inherited it uncorrected.
- **Stage 10R.1C calibration UX copy** (`SourceRMCalibrationView.swift`):
  "requires your current **tested** weight," "perform a real 10-rep-max
  **attempt**" — overstates the source's actual requirement (Rule 4).

## Part 2 — Domain model options for the RepGoal correction

`RepGoal` currently requires a non-optional `reps: Int`, read directly
into `SetPrescription.repRangeLow`/`repRangeHigh` — the exact UI-visible
field. Three ways to resolve the "reps is not always a real prescriptive
target" problem, none implemented yet:

**A. Make `RepGoal.reps` optional**, add a `repMode: FixedReps |
EffortTarget` (or reuse `targetRir` as the discriminator: non-nil →
effort-target, nil → fixed-reps). Smallest structural change, but every
existing reader of `.reps` (Family A/B/C legacy, `StrengthMaterializer`,
any UI code) needs an audit for "what happens when this is nil now,"
since today it's guaranteed non-nil.

**B. A new, explicit enum** (`RepPrescriptionKind: .fixedReps(Int) |
.effortTarget(rir: Int)`), replacing or living alongside `RepGoal`.
Cleanest semantically (matches Rule 2's "do not collapse" instruction
literally), largest migration surface — every `repGoalSchedule: [RepGoal]`
call site across Family A/B/C generators and `StrengthMaterializer`'s
`SetPrescription` construction would need updating.

**C. Keep `RepGoal` shape, stop writing a fabricated `reps` value for
effort-target slots** — set `reps`/`repRangeHigh` to `nil`-equivalent
(would still require making the field optional, so this collapses into
option A) or to some other UI-safe representation (e.g. `repRangeLow: 0`
+ a real `targetRir`, with the UI taught to render "RIR 3" and omit the
rep count when `reps == 0`/absent) — a smaller change than A/B but risks
exactly the "silent sentinel" pattern this codebase's own conventions
warn against (`RepGoal`'s own doc comment already uses `-1` as a "not
set" sentinel for `repRangeHigh`/`targetRir` on the PERSISTED, flattened
`PrescriptionTemplate` fields — a precedent exists, but it's explicitly
described there as a persistence-layer trick, not a domain-model
pattern to lean on further).

I have not chosen between these — this needs your decision (Part 8).

## Part 3 — The deload rep-count question this correction exposes

Deload's own label, `"1/2 reps of Week 1"`, is presently read as
`floor(repGoalSchedule[0].reps * deloadRepFraction)` — i.e., half of the
literal "3" Week-1 wrote into `reps`. Once Week 1 is correctly modeled
as an effort target (no fixed rep count), **this formula has nothing to
halve** — "Week 1's reps" no longer exists as a static number in the
template.

Two readings, genuinely ambiguous, not resolved by anything I can see in
the workbook cells or your correction:

- **(a)** "Week 1 reps" means the user's *actual, logged* Week-1
  performance for that slot — deload becomes a literal fixed-rep target
  derived from real history (a genuinely new mechanism: nothing today
  threads "actual reps just performed" into any later calculation except
  autoregulated *set count*, never *rep count*).
- **(b)** The deload week was always meant as its own independent, small
  fixed-rep prescription and "Week 1" in the label is just informal
  shorthand for "the same working-weight reference," not a literal
  half-of-actual-performance formula.

Per CLAUDE.md rule 10 and your own "do not invent, flag it" instruction:
**I am flagging this, not deciding it.** `SourceCompatibleDeloadStrategy`
itself is unaffected either way (it already only reads
`rules.repGoalSchedule.first?.reps`, a template-level value, not history)
— but which value that field should actually hold, once Week 1 is no
longer a fixed-rep field, is an open product question.

## Part 4 — RM calibration UX correction (Rule 4)

Two concrete, small copy/product changes, not implemented yet:

- Replace "requires your current **tested** weight" with something like
  "enter your current 10RM — a recent test or a realistic estimate is
  fine."
- Replace "I need to test this first" / "perform a real 10-rep-max
  **attempt**" with softer, accurate language — e.g. "I don't know this
  yet" / "You can estimate based on recent training, or test it before
  your next session." The underlying behavior (never fabricate a value,
  never proceed without one) stays exactly as designed — only the
  *framing* was wrong, not the "don't guess for the user" principle.
- **Do NOT build an automatic estimator** — Rule 4 explicitly reaffirms
  this ("do not algorithmically estimate it... without a separate
  product decision"), consistent with Stage 10R.1C's own explicit scope
  boundary. Nothing about this correction reopens that door.

## Part 5 — Load-first design grounding (Rule 6), for future design work

Not designed yet — flagging the shape the eventual design pass needs to
reconcile, now that the effort-target semantics are corrected:

The source's actual mechanism, once corrected, is: **10RM anchor
(tested-or-estimated) → fixed % load per week (already source-faithful,
unaffected by this correction) → effort target expressed as RIR (now
corrected) → real performed reps as an output → post-session set-count
rating → next week's set count (already source-faithful) → Week-1
load-recalibration band (Part 1 Rule 5, not yet modeled).**

A future "bias toward load" overlay needs to decide which of these knobs
it touches — e.g. does it lower the RIR target (push closer to failure
sooner) to indirectly favor heavier working loads, or does it modify the
% load formula itself, or does it change how autoregulated set count
responds? This is exactly the kind of design question Stage 10R.1's
original scope deferred ("the load-bias overlay is a separate stage");
this correction doesn't change that deferral, it just means whenever
that design pass happens, it needs to reason about RIR (not fixed reps)
as the source's real effort lever.

## Part 6 — Warm-up (Rule 7): already correct, confirmed by direct code read

Verified directly (not assumed): `GenerateWarmupSequenceUseCase` already
derives its selection from the *current session's actual resolved
exercises* — their real `primaryTargets`/`movementFunctions` feed
`WarmupEmphasisDerivation.derive`, which computes what today's session
specifically needs, ranked against a tagged `WarmupMovement` catalog;
generic/fallback candidates are explicitly excluded whenever a real
session-specific match exists (`STAGE9_WARMUP_DESIGN.md`, already
manually accepted, decision D-W3/Q5). This already matches Rule 7's
requirement ("MAY generate a warm-up as execution intelligence... derived
from today's actual source session") — no gap found, no action needed.

## Part 7 — Scope confirmation

Per your instruction, **nothing has been implemented**. This document is
report-only. No `RepGoal`/generator/materializer/UI code has been
touched. `STAGE10R1C`'s calibration architecture (domain model,
persistence, gating) is unaffected by this correction — only its UX
copy (Part 4) needs revision, and only once you confirm.

## Part 8 — Decisions needed from you

1. Which `RepGoal` domain-model option (Part 2: A/B/C) to implement.
2. How to resolve the deload rep-count ambiguity (Part 3: reading (a)
   vs. (b), or another reading you can confirm from the companion
   material that I don't have visibility into).
3. Whether to correct the legacy 5-day Family A and Powerlifting
   (Family B/C) `.rmBased` paths in the SAME implementation pass as the
   3-Day Full Body correction, or scope this pass narrowly to the
   already-recovered/accepted 3-Day Full Body content first (matching
   this project's "don't generalize too early" discipline) and flag the
   others as a known, tracked follow-up.
4. Whether the Week-1 load-recalibration band (Part 1 Rule 5) should be
   designed now as part of this correction, or deferred as its own,
   separately-scoped future slice (it's a genuinely new mechanism, not
   a bug fix to existing code).
5. Confirmation on the RM-calibration copy changes (Part 4) — these seem
   low-risk/low-ambiguity, but I'm not implementing anything without
   your explicit go-ahead per this message's instruction.

---

## Addendum — re-investigation from primary sources (round 2)

Re-verified directly against the raw xlsx extractions (not inferred):

**Deload "1/2 reps of Week 1"**: confirmed a literal text string in
every row of every Family A/B/C workbook checked, never a formula. BUT:
the sheet's own column headers (row 9) are `'Exercise','Sets','Weight',
'Rep Goal','Rep Results','*Rating'`, repeated per week — **"Rep Goal"
and "Rep Results" are two distinct, separately-headed columns.** "Rep
Goal" always holds the "N/fail" text (never a number, can't be halved
arithmetically). "Rep Results" is a blank, athlete-fill-in column for
actual performance — the only numeric record of Week 1 anywhere in the
sheet. This makes "half of Rep Results" the only reading that's
arithmetically possible, even though no formula proves it outright.
Treated below as source-indicated, not a product choice, with the
residual work being a data-flow/persistence question, not a semantic
one.

**Rep ranges**: NOT found anywhere in any of the 11 Family A
(Hypertrophy) workbooks. Found only once, in Family B
(`powerlifting_str4day.xlsx`), as a generic, unlinked legend ("5-10 reps
for first set," "3-8 reps for first set") not tied via any formula to a
specific category/exercise/mesocycle — a "what to expect" key, not an
enforced per-slot range. Family C has no such legend either. **For the
already-recovered 3-Day Full Body Hypertrophy content specifically, the
source defines no rep range at all** — the only per-week target is the
RIR value itself.

**RM estimate — direct primary-source confirmation found**: both
Powerlifting workbooks contain a real embedded "a.) Instructions for
Use" sheet (Family A has no such sheet). Verbatim: *"fill in your 10 rep
maxes for the exercises you selected by typing them in. If you don't
know the exact values, do your best to estimate them."* Also: *"fill
out the rating scale... so that your **volume** can be auto-adjusted to
your responses"* — confirms the rating mechanism targets **set count**,
never rep count, matching the existing, unchanged `AutoregulatedSetCount`
mechanism.

**Warm-up**: confirmed a genuine bug, not source behavior and not
working as designed. `SessionDemand` treats an entire `WorkoutBlock` as
"primary" — and because every real session in this app is one
`WorkoutBlock` holding all of that day's exercises, EVERY exercise
(Bench Press through Front Squat) is dumped into "primary"
undifferentiated. All four derived emphases tie at the same priority,
and ties break alphabetically — which is exactly the observed
lower-body/generic-first output. This affects every session in the app
today, not just this one example.

Full details of both rounds of investigation were delivered directly in
chat, per your request, since this file was reported as unavailable in
your review conversation.

Per your instruction: still report only. Nothing implemented, no tests
changed, no commit, no push.
