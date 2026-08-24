# Stage 10B.6 — Hypertrophy Prescription Redesign

**STATUS: DESIGN APPROVED AND IMPLEMENTED** (see
`STAGE10B6_IMPLEMENTATION_REPORT.md` for the full implementation
report — architecture/schema changes, test results, Simulator state,
and remaining open items). This document is kept as the authoritative
design record; §26's items were resolved by the follow-up approval
message and are implemented as described. **Uncommitted, unpushed,
pending your manual acceptance** — Stage 10C has not started.

Original design-phase framing below, retained for context:

**STATUS (original): DESIGN ONLY. No production code changed.** This document
turns your 9 approved decisions into an implementation design. Stage
10B's Day A/B/C construction, exercise resolution, readiness, warm-up,
navigation, and live execution are untouched and remain manually
accepted. Stage 10B stays **uncommitted** pending your review of this
design.

---

## 1. Final diagnosis of legacy Family A

Family A (`repGoalSchedule = [(3,✓),(3,✓),(2,✓),(1,✓)]`,
`laterWeekMultipliers = [1.05,1.075,1.1]`, `primaryWeekOneFactor`) is a
**calendar-driven, non-performance-reactive, top-set/RM-testing ramp**:
reps fall, load rises on a fixed schedule, every progressive week is to
literal failure, culminating in a 1-rep near-max test. It is not, and
should not remain, TrainingOS's default Muscle Gain/Hypertrophy
philosophy (your Decision 1). It is a legitimate shape for a
**strength-biased/peaking family** — not deleted, not silently
repurposed, disposition below (§18).

## 2. Proposed replacement architecture

**Reuse the exact split pattern Stage 10B already established for slot
construction, applied now to numeric rules too:** the day-focus-driven
generation path (`generateDayFocusDriven`) gets its **own** new rule
set (a new `LoadRule` case + rep-range representation), while
`generateLegacyFixedPair` keeps Family A byte-for-byte unchanged — the
same "one split-first, nothing else touched" discipline already proven
in Stage 10B itself.

**Core architectural shift:** load progression stops being a
calendar-index formula and becomes **performance-driven double
progression**, reusing a mechanism that **already exists, is already
correct, and is already wired to real logged data** —
`DoubleProgressionEngine`/`CompleteSessionUseCase.progressionPreview`.
Today it's display-only. This design promotes its exact decision logic
into the real materialization path, so the "Next time" preview and the
actual next prescription become the same computation, not two
independently-drifting engines (directly closing Decision 7's "one
authoritative decision path" requirement).

**What's new:** one `LoadRule` case (`.doubleProgression`), one
extended `RepGoal` (now a genuine range + explicit target RIR), one
new attribution shape for autoregulation feedback (fixes the fan-out),
one calibration path for a truly new exercise, one fix to make the
deload week reachable. **What's reused unchanged:** `PrescriptionTemplate`,
`SlotRole`, `StrengthMaterializer`'s overall shape,
`AutoregulatedSetCount`/`AutoregulationRatingResolver`'s mechanism
(fixed to be correctly attributed, not replaced), `SourceCompatibleDeloadStrategy`'s
day-position-split shape, readiness's existing `isAdaptedAway`/executable-count
separation (already correct — see §14), `DoubleProgressionEngine` itself
(unchanged internals), `SetPrescription.repRangeLow/repRangeHigh`
(already-existing schema fields, finally used as a genuine range).

## 3. Exact rep-range representation

Extend `RepGoal` (used by the new rule set only — Family A/B/C's usage
of `RepGoal(reps:_, toFailure:_)` is completely unaffected, since both
new fields default to `nil`/absent):

```swift
struct RepGoal: Codable, Equatable {
    var reps: Int                  // unchanged — legacy families' single target
    var toFailure: Bool            // unchanged — legacy families' binary flag
    var repRangeHigh: Int?         // NEW. nil = legacy single-number behavior (repRangeHigh == reps)
    var targetRir: Int?            // NEW. nil = legacy mechanical toFailure->0 derivation applies
}
```

For the new Hypertrophy rule set, every `RepGoal` sets both new fields
explicitly (e.g. `RepGoal(reps: 5, repRangeHigh: 10, targetRir: 3)` for
primary week 1) and `toFailure` is simply unused/`false` (superseded by
the explicit `targetRir`). `StrengthMaterializer` already writes
`SetPrescription.repRangeLow`/`repRangeHigh` per set — it changes from
`repGoal.reps` (both bounds identical) to `repGoal.reps`/`repGoal.repRangeHigh ?? repGoal.reps`,
a two-line, additive change. `targetRir` resolution becomes
`repGoal.targetRir ?? (repGoal.toFailure ? 0 : nil)` — the old mechanical
rule stays the fallback, never removed.

**Proposed V1 ranges** (your own decision 3 sketch, validated below —
design ranges, not final numbers pending your sign-off in §26):

| Role | Range | Classification |
|---|---|---|
| Primary | 5–10 | TRAININGOS-DESIGNED, informed by external evidence (§19) |
| Secondary | 6–12 | TRAININGOS-DESIGNED |
| Accessory | 10–20 | TRAININGOS-DESIGNED |

**Validated against the actual seed catalog:** every currently-resolved
primary/secondary exercise (Barbell Bench Press, Back Squat, Romanian
Deadlift, Barbell Row, Front Squat, Leg Press, Leg Curl) is a normal
barbell/machine compound movement with no mechanical reason it couldn't
be trained for 5–12 reps — nothing in the catalog forces a low-rep-only
or high-rep-only pattern. Accessories (Barbell Curl, Cable Triceps
Pushdown, Dumbbell Lateral Raise, Calf Raise) are all standard isolation
movements commonly trained at 10-20 reps. No catalog-specific edge case
was found requiring a per-exercise override for V1.

**Movement-demand override — minimum viable, not built yet:** rather
than inventing dozens of exercise-specific rep categories, the smallest
useful escape hatch (if ever needed) is a single **optional** field on
`PrescriptionTemplate` (or, more generically, on `ExerciseSlot`, so it
travels with slot *intent* rather than the resolved exercise) —
`repRangeOverride: (low: Int, high: Int)?` — consulted before the
`SlotRole` default. **Not created in this pass**; no concrete case in
the current catalog needs it (see table above). Listed as available
infrastructure if a future exercise genuinely requires a different
range (e.g. a unilateral or highly technical movement), not built
speculatively.

## 4. Exact RIR trajectory

**Primary and secondary share the same week-by-week trajectory**
(keeping the distinction minimal per Decision 5 — the two roles now
differ in *rep range*, not in *how much fatigue is intended*):

| Week | Primary/secondary target RIR |
|---|---|
| 1 | 3 |
| 2 | 2 |
| 3 | 2 |
| 4 | 1 |
| 5 (deload) | ≥4, never to-failure — see §12 |

This matches your own sketch (early ~3, middle ~2, late ~1) with week 3
held at 2 rather than stepping to "1–2" — a concrete, unambiguous number
was needed for a deterministic engine; your own bracket already allowed
this. **Flagged for your confirmation, not unilaterally decided (§26).**

**Accessory: flat, not a trajectory.** `targetRir = 2` every week
(never 0/never true failure by default — matching Decision 5's "may
tolerate closer-to-failure work where appropriate" as a future option,
not a default). Accessories are lower systemic cost and don't need the
same early-mesocycle conservatism as heavy compounds; a flat target
keeps the rule count minimal.

**Back Squat/Romanian Deadlift/Bench Press/Barbell Row under this
design:** never reach RIR 0 in any progressive week. The closest
approach is RIR 1 in week 4 — genuinely close to failure (matching the
evidence in §19 that hypertrophy benefits from proximity to failure)
without ever requiring an actual maximal/failure attempt on a primary
compound lift, directly satisfying your explicit requirement.

## 5. Exact primary/secondary/accessory differences

| | Primary | Secondary | Accessory |
|---|---|---|---|
| Rep range | 5–10 | 6–12 | 10–20 |
| RIR trajectory | 3→2→2→1 | 3→2→2→1 (same) | flat 2 |
| Load rule | `.doubleProgression` | `.doubleProgression` (same) | `.doubleProgression` (own history) |
| Set count | `AutoregulatedSetCount(baselineSets: 3)`, **individually attributed** (§9), bounded baseline-1..baseline+2 | same mechanism, same baseline (3) — approved, no invented role split (§8) | fixed at baseline 2, e.g. `[2,2,2,2]` — never autoregulated (unchanged shape) |
| Autoregulation feedback | asked individually | asked individually | not asked (fixed schedule, no autoregulated lever to inform) |

This is the smallest change that makes `SlotRole` affect *prescription
meaning* (rep range, matching Decision 5's explicit requirement) without
inventing a compound/isolation domain concept — the differentiator is
purely "how wide a rep window, and (for accessory) whether it's
autoregulated at all," using `SlotRole` + the existing
`ExerciseSlot`/`Exercise` metadata already in place.

## 6. Exact progression algorithm — PERFORMANCE-QUALIFIED LOAD PROGRESSION (revised)

**Supersedes the earlier "reused verbatim" proposal.** Classic
ceiling-gated double progression (require every set to hit the top of
the range before any load increase) is rejected per your correction —
it is rep-first in practice despite the load-first product principle.
The replacement keeps `DoubleProgressionEngine` as the one engine
(§7 — extended, not replaced) but changes its internal decision rule to
**performance-qualified load progression**: an increase is justified
either by reaching the top of the range at the intended effort, *or* by
staying inside the range while performing with meaningfully more
reserve than the target RIR calls for. Full algorithm, decision table,
next-rep-target rule, and increment handling are in the new §6a-§6d
below — this is the one item that was still pending your approval
before implementation and is now resolved pending your sign-off on the
two flagged constants (§6d, §26).

### 6a. The rule, precisely

Given, per prescribed set: `repRangeLow`, `repRangeHigh`, `targetRir`
(the week's prescription) and the logged `reps`, `actualRir` (the real
result) — plus, only when available, the **immediately preceding**
exposure's own targets/results for the same slot (the "recent
performance" lookback your correction asked for):

```
0. hasUsableHistory == false, or no lastKnownWeight
   -> CALIBRATION REQUIRED

1. logged set count != prescribed set count (a set was skipped/miscounted)
   -> HOLD  (never guess from incomplete data)

2. For each set, define:
     metMinimum  = reps >= repRangeLow
     metCeiling  = reps >= repRangeHigh
     metRirFloor = actualRir == nil || actualRir >= targetRir
     rirSurplus  = (actualRir ?? targetRir) - targetRir          // 0 if RIR wasn't logged
     strong      = (metCeiling && metRirFloor)                   // classic path
                   || (metMinimum && rirSurplus >= RIR_SURPLUS_THRESHOLD)  // qualified path

3. IF every set is `strong`
   -> candidate for INCREASE, subject to the increment guard (§6d)
      - guard passes  -> INCREASE LOAD
      - guard fails   -> HOLD LOAD / PROGRESS REPS  (performance earned it;
                         the available increment just isn't usable yet)

4. ELSE IF every set met minimum reps AND met RIR floor (on track, just not "strong")
   -> HOLD LOAD / PROGRESS REPS

5. ELSE IF any set fell below repRangeLow (missed the range outright)
   -> look at the immediately preceding exposure for this same slot:
      - no prior exposure available, or prior exposure did NOT also miss the minimum
        -> HOLD  (one off day; not evidence of a bad prescription yet)
      - prior exposure ALSO had a set below repRangeLow (two in a row)
        -> REGRESS: lastKnownWeight - equipmentIncrement (rounded per §6d)

6. ELSE (met minimum reps everywhere, but at least one set needed more effort
   than the target RIR allowed — reps were only achieved by working harder
   than prescribed)
   -> HOLD  (this is not "on track"; do not count it toward a future increase,
      but a single occurrence does not regress the load either)
```

Steps 4 and 6 are deliberately different outputs (`HOLD LOAD / PROGRESS
REPS` vs. plain `HOLD`) even though both keep the same weight next
time — one is "on track as intended," the other is "hit the number but
it cost more than it should have; watch this."

### 6b. Decision table (primary example: range 5-10, target RIR 2)

| Case | Logged | Per-set check | Output |
|---|---|---|---|
| A | 10/10/10 @ 2 RIR | metCeiling+metRirFloor on every set → strong | **INCREASE LOAD** |
| B | 8/8/8 @ 2 RIR | metMinimum, not ceiling, rirSurplus=0 → not strong; on-track | **HOLD LOAD / PROGRESS REPS** |
| C | 8/8/8 @ 4 RIR | metMinimum, rirSurplus=2 ≥ threshold → strong (qualified path) | **INCREASE LOAD** |
| D | 6/6/6 @ 2 RIR | metMinimum, rirSurplus=0 → not strong; on-track | **HOLD LOAD / PROGRESS REPS** |
| E | 5/5/5 @ 1 RIR | metMinimum (5=low) but metRirFloor fails (1<2) → step 6 | **HOLD** |
| F | one set at 4 reps (< low of 5), first time this has happened | step 5, no confirmed repeat | **HOLD** |
| G | one prescribed set not logged (count mismatch) | step 1 | **HOLD** |
| H | 8/8/8 @ 4 RIR (strong, as C) but next increment is disproportionate at this weight | step 3, guard fails | **HOLD LOAD / PROGRESS REPS** |
| (new, not in your list) | any set < 5 reps, AND the prior exposure also had a set < 5 reps | step 5, confirmed repeat | **REGRESS** |

Case C is the concrete case your correction was aimed at: not the
classic 10/10/10, but genuinely qualifies as strong performance because
the athlete had far more in reserve than the plan called for.

### 6c. Next rep target after a load increase

**No schema change, no explicit reset.** The rep range and target RIR
stored on the template stay exactly `[5, 10]` / RIR-2 (or whatever the
week's own trajectory calls for) after an increase — the *same* window
is simply re-applied at the new, heavier weight. Since the same reps
are now harder to hit at a higher load, the athlete naturally lands
back toward the bottom of the range without the engine needing to
rewrite anything. This is the intended, self-correcting behavior of a
range-based (vs. single-number) prescription, and it is why the
representation is a range in the first place (§3).

### 6d. Available load increment — the guard, and the smallest real seam

**Confirmed by re-reading the actual increment architecture (not
assumed):** two increment mechanisms already exist and neither is
per-exercise:
- `UserProfile.equipmentIncrements: [String: Double]` — one flat kg
  amount **per equipment-type string** (`"barbell": 2.5, "dumbbell":
  2.0, "machine": 5.0`), keyed by `Exercise.equipment`. Already the
  exact value fed into `ProgressionInput.equipmentIncrement` today
  (`CompleteSessionUseCase.swift:87`). **No change needed here** — it
  is already the right granularity to distinguish "a dumbbell jump" from
  "a barbell jump."
- `EquipmentProfile` (`smallestIncrementKg`/`roundingRule`) — **one
  instance per phase/program**, not per exercise, used today only to
  *round* a resolved weight for Family A/B/C (`METRIC_LOAD_MODEL.md`'s
  documented "IdealLoad → EquipmentProfile.resolve() rounds exactly
  once" rule). Reused unchanged for the same purpose here.

**The guard uses data already present on `ProgressionInput` — zero new
fields required:**

```
proportionalRatio = equipmentIncrement / lastKnownWeight
guard passes  IF proportionalRatio <= MAX_PROPORTIONAL_INCREMENT_RATIO
guard fails   IF proportionalRatio >  MAX_PROPORTIONAL_INCREMENT_RATIO
```

10kg → 12kg dumbbells: ratio 0.20 (fails at a proposed 0.10 ceiling).
100kg → 102.5kg barbell: ratio 0.025 (passes easily). This is exactly
the "proportionally very different" distinction you described, computed
from two numbers the engine already receives — the smallest possible
seam, not a new equipment model.

**`DoubleProgressionEngine`'s output stays unrounded kg** (unchanged
discipline — `IdealLoad`'s own doc comment: rounding happens exactly
once, at the caller, never inside an engine). The real materialization
call site rounds the recommended weight through the phase's existing
`EquipmentProfile.resolve(_:)`, exactly mirroring how Family A/B/C
already round — no new rounding mechanism.

**Two constants this introduces, both TRAININGOS-DESIGNED, both
flagged for your confirmation in §26, not silently decided:**
- `RIR_SURPLUS_THRESHOLD = 2` — how much extra reserve counts as
  "meaningfully easier than prescribed."
- `MAX_PROPORTIONAL_INCREMENT_RATIO = 0.10` — the ceiling past which an
  available increment is treated as disproportionate at the current
  working weight.
- (REGRESS's step size reuses `equipmentIncrement` symmetrically — the
  same number used for increases — rather than a separate invented
  figure.)

## 7. Load-first semantics — wiring plus a rule revision, not a rewrite

**Recommendation: Option B-with-promotion, engine logic revised
per §6, not reused verbatim.** `DoubleProgressionEngine` is *extended*
— its decision body changes to the performance-qualified rule (§6),
its `ProgressionInput`/`ProgressionOutput`/`SetTarget`/`SetOutcome`
shapes and the `ProgressionEngine` protocol are untouched, and it stays
the one and only implementation the new Hypertrophy path consults
(Family A/B/C keep their own existing `.rmBased`/`.linkedToPairedSlot`
resolution via `StrengthProgressionEngine`, completely untouched).
Concretely:

1. Add a new `LoadRuleKind` case, `.doubleProgression` (no new payload
   fields needed — the decision only needs the SAME per-slot history
   already available via `ExercisePrescription`/`SetResult`).
2. `StrengthProgressionEngine.resolveWeight`'s `.doubleProgression`
   case delegates to `DoubleProgressionEngine.recommend(_:)`, given
   `targets`/`latestResults`/`lastKnownWeight` supplied by the **caller**
   (matching the existing "caller supplies what the template graph
   itself cannot know" contract `StrengthMaterializer.SlotContext`
   already uses for `rmKilograms`/`pairedSlotResolvedWeightKg`) — i.e.
   `RollTacticalWindowUseCase`'s `strengthSlotContext` gains a new
   branch that builds these three values from the **prior week's**
   materialized `ExercisePrescription`'s `executableSetPrescriptions`
   (as targets) and `loggedSetResults` (as outcomes) for that exact
   `PrescriptionTemplate`/slot — the same lookup shape
   `AutoregulationRatingResolver` already performs for set count.
3. `CompleteSessionUseCase.progressionPreview` is **not rewritten** —
   its existing call to the exact same `DoubleProgressionEngine` with
   the exact same real inputs (already reading `executableSetPrescriptions`/
   `loggedSetResults`, already handling readiness-adaptation neutrality
   correctly — see §14) becomes, by construction, a preview of the
   **same decision** the materializer will make when the next week is
   actually rolled — not a second, independently-computed opinion. One
   algorithm, two call sites, guaranteed identical because both are
   pure functions of the same real data.

This directly satisfies "no engine A decides prescription while engine
B displays a contradictory Next time" — there is only ever one engine
(`DoubleProgressionEngine`), consulted at two points in time with
converging inputs.

## 8. Set-count progression recommendation

**Challenge accepted, conclusion:** recommend **Option B — bounded
local autoregulation**, same as your stated preference, for these
reasons, having weighed the alternatives:

- **Option A (fully stable sets)** removes the one existing,
  already-working lever this codebase has for "this felt too
  hard/easy, adjust next time" — discarding a working mechanism to solve
  a problem (the fan-out) that's actually about *attribution*, not
  about the mechanism's existence.
- **Option C (planned ramp + local autoregulation)** adds a second,
  compounding volume driver on top of an already-richer Stage 10B
  session (typically 6-7 exercises/day already, per the earlier program-
  structure audit) — real risk of unintentionally escalating total
  weekly volume past what's recoverable, with no sourced ramp shape to
  justify the specific escalation rate. Rejected as unnecessary
  complexity given the richer session already provides substantial
  volume by exercise count alone.
- **Option B** keeps the exact existing mechanism
  (`AutoregulatedSetCount`, `max(0, previousWeekSetCount + rating)`),
  fixing only the attribution bug (§9) — smallest change, reuses
  proven architecture, matches your stated preference, and evidence
  (§19) treats total hard sets, not a specific week-to-week escalation
  formula, as what matters for hypertrophy — supporting "stable,
  locally-adjusted" over "a planned ramp."

**Bounds — approved (D-10B6-4):** `max(baseline - 1, min(baseline + 2,
previousWeekSetCount + rating))` — a floor of `baseline - 1` (not the
prior implicit 0) and a ceiling of `baseline + 2`, unless
`baseline - 1` would itself go non-positive, in which case the
existing `max(0, ...)` floor still applies (e.g. a baseline-2 accessory
never drops below 1 working set). This replaces the current unbounded
`max(0, previousWeekSetCount + rating)` — the one change to
`AutoregulatedSetCount`'s resolution this redesign requires.

**Baselines — approved (D-10B6-5), no invented role difference:**

| Role | Baseline working sets |
|---|---|
| Primary | 3 |
| Secondary | 3 |
| Accessory | 2 |

Primary and secondary share one baseline — their rep range and slot
priority already differentiate them; inventing a set-count difference
on top would be difference-for-its-own-sake. Revisit after real usage
data, not before.

## 9. Feedback architecture fix (the fan-out)

**Root cause recap:** `HypertrophyFeedbackPrompts.pending(for:)`
prompts only the slot that's the *target* of some other slot's
`pairedSlot` — under Stage 10B's day-focus construction, every
primary/secondary slot shares one canonical accessory as that target,
so one rating drives every primary/secondary slot's set count at once.

**Fix — attribution, not a new feedback system:**
1. Remove the day-focus path's shared-canonical-accessory `pairedSlot`
   assignment for autoregulation purposes (it was only ever there
   because `AutoregulationRatingResolver.rating(for:)` requires *some*
   `pairedSlot` to read from). Instead, **each primary/secondary
   template becomes its own autoregulation rating source** —
   concretely, `template.pairedSlot = template` (a slot rates itself),
   or (cleaner, avoiding a self-referential foreign key) add a
   dedicated boolean/marker so `AutoregulationRatingResolver.rating(for:)`
   can read the rating directly off the SAME `ExercisePrescription`
   it's resolving for, rather than indirecting through a different
   slot's history. Accessory slots need no rating source at all (fixed
   set schedule, never autoregulated).
2. `HypertrophyFeedbackPrompts.pending(for:)`'s eligibility predicate
   changes from "is the target of some other slot's `pairedSlot`" to
   "is itself a primary or secondary `SlotRole` with logged sets and no
   rating yet" — directly, simply, correctly attributed.
3. **Compact UI, per your explicit "not 7 questionnaires" constraint,
   with the grouping rule made explicit (approved: 2-4 is a UX target,
   not a correctness constraint):** `HypertrophyFeedbackView` becomes
   **one consolidated screen** (reusing the exact list-of-rows pattern
   `WarmupView` already established for a similar "several small items,
   one screen" need). **Grouping rule:** one row per slot that is (a)
   `SlotRole` primary or secondary, (b) has at least one logged set this
   session, and (c) has no rating recorded yet for this exposure — no
   row is ever merged with another to force a lower row count, and no
   real primary/secondary slot is silently dropped to stay under a
   target. A typical Stage 10B day produces 2-4 rows because that's how
   many primary/secondary slots the day actually has (accessories never
   appear — they're never autoregulated). A day genuinely constructed
   with five distinct primary/secondary slots produces five rows; the
   row count is a *consequence* of the day's real structure, never a
   ceiling enforced by merging distinct stimuli. Each row independently
   tappable, submitted together.

This is a UI/attribution fix only — no new persisted entity, reuses
`ExercisePrescription.autoregulationRating` exactly as it exists today.

## 10. Calibration / initial-load design

**Direct answer to your explicit challenge: e1RM is not needed as the
core load model for the new Hypertrophy rule family, and is dropped
from it.** `DoubleProgressionEngine`'s actual input is `lastKnownWeight`
— a real, previously-used absolute weight — never a percentage of a
tested max. The entire `estimatedOneRepMax`/`SubstitutionAwareRecommendation`
chain exists to answer "what % of RM should week 1 use," a question
the new model doesn't ask.

**Calibration design:**
- **If `ExercisePerformanceProfile`/prior `SetResult`s exist for this
  exercise:** use the most recent logged weight directly as
  `lastKnownWeight` for the new mesocycle's first exposure — no
  percentage conversion, no RM math. (This is a strict simplification
  of the existing week-0 `SubstitutionAwareRecommendation` call site —
  replace its %RM output with a direct "most recent working weight for
  this exercise" lookup for slots using the new load rule.)
- **If no history exists at all (truly first exposure):** this
  occurrence is explicitly a **calibration set** — the UI either (a)
  asks the user for a reasonable starting weight (their own estimate,
  never a tested 1RM), or (b) prescribes a conservative, clearly-labeled
  "calibration" load and simply records whatever the user actually
  lifts. Either way, **no number is invented by the engine** — the
  first logged `SetResult` becomes `lastKnownWeight` for the *next*
  occurrence, and `DoubleProgressionEngine` takes over from there.
  `.calibrationRequired` (an existing reason code) is the exact state
  this maps to — no new reason code needed.
- **`estimatedOneRepMax`/`confidence` are not removed** — Family A and
  Powerlifting (Family B/C) still use them unchanged. They simply gain
  no new production writer in this pass either; that remains a
  separate, not-yet-scoped feature (populating/updating e1RM for
  whichever families still need it) — explicitly out of this redesign's
  scope, listed as an open item in §26.

## 11. e1RM role — decided

**Reduced to legacy-only.** Kept, unmodified, for Family A (if/when it
becomes the strength-biased family, §18) and Powerlifting — both
genuinely use %RM-based `.rmBased` loading and need it. **Removed as a
dependency for the new Hypertrophy rule family entirely** — replaced by
direct "last logged weight" calibration (§10). Not deleted from the
schema (`ExercisePerformanceProfile.estimatedOneRepMax`/`confidence`
stay exactly as they are) — just no longer load-bearing for
Hypertrophy's new path.

## 12. Deload scheduling / reachability

**The reachability bug is a pure defect, fixed independent of any
numeric redesign** (your Decision 9's own framing): `RollTacticalWindowUseCase.rollForward`'s
two production call sites currently hardcode `isDeload: false`
regardless of `weekIndex`. Fix: read the actual `TrainingWeek.isDeload`
flag for the week being materialized (`definition.orderedWeeks[weekIndex].isDeload`)
instead of a hardcoded literal — a small, contained, low-risk change
that makes the already-generated 5th `TrainingWeek` row (already marked
`isDeload: true` by the generator, for every configuration, unchanged)
actually reachable for the first time.

**Mesocycle length: kept at 5 weeks (4 progressive + 1 deload),
unchanged.** Audited per your instruction not to assume this — the
existing `ProgramDefinition.lengthWeeks`/`TrainingWeek` generation loop
already supports any count structurally, but nothing in decisions 1-9
requires a different length, your own mesocycle sketch matches 5 weeks
exactly, and changing week count would ripple into
`TacticalWindowPolicy`/phase-duration assumptions used by every other
programming system — a bigger, unrelated change this redesign doesn't
need to make. Confirmable, not unilaterally closed (§26).

## 13. Deload prescription design — approved (D-10B6-8)

| | Primary/secondary | Accessory |
|---|---|---|
| Sets | `round(baseline * 0.5)`, minimum 1 (baseline 3 → 2 sets) | `round(baseline * 0.5)`, minimum 1 (baseline 2 → 1 set) |
| Reps | same range as week 4 (no separate deload range) | same range as its own week |
| RIR | **explicit target 4** — its own `RepGoal.targetRir`, never derived from `toFailure` | explicit target 4 |
| Load | **not an arbitrary fixed percentage** — resolved the same performance-qualified way as any other exposure (§6), just against the deload week's RIR-4/reduced-set targets. Since week 4's own logged performance is real, recent history, the deload weight is whatever `DoubleProgressionEngine` recommends for *this* week's (easier) targets — i.e., load naturally comes down because the target got easier (higher RIR, fewer sets), not because a percentage was subtracted. |

This reuses §6's algorithm as-is for the deload week — no separate
load formula, no arbitrary percentage. The **one open question**, per
your instruction to stop and surface rather than invent: the very
**first** deload exposure of a mesocycle has no "deload-shaped" history
to compare against (only accumulation-week history) — §6's rule already
handles this cleanly (it reasons from rep-range/RIR *targets* vs.
*actual* logged performance, not from "was the last exposure also a
deload"), so no new branch is actually needed; flagged in §26 only so
you can confirm that reasoning is sufficient rather than assuming it.
The existing `SourceCompatibleDeloadStrategy` (day-position 100%/50%
split, Family-A-shaped) is **not reused** for the new Hypertrophy
path — it stays exactly as-is for Family A/Powerlifting only, which is
what "must never inherit legacy `toFailure`" already implied once
`targetRir` is explicit and this path doesn't touch that strategy at
all.

Cross-reference: `READINESS_PROGRESSION_CONTRACT.md` already documents
the readiness/progression separation this section and §14 depend on —
worth aligning terminology with that existing document during
implementation rather than introducing new vocabulary for the same
concept.

**Trigger stays purely positional** (the `TrainingWeek.isDeload` flag,
generated once, unchanged) — readiness never triggers it, confirmed
already-separate architecture (§14).

## 14. Readiness interaction

**Already correctly separated — confirmed, not redesigned.** Two
independent facts, both already true in the current codebase and
preserved unchanged by this redesign:

1. `ReadinessAdaptationDecisionUseCase`'s `.setCountReduced` marks
   `isAdaptedAway` on specific `SetPrescription` rows — the original,
   full prescription list survives; `AutoregulationRatingResolver`
   already reads the **full** list for next week's set-count baseline,
   never the adapted-down count.
2. `CompleteSessionUseCase.progressionPreview` **already** treats an
   accepted readiness adaptation as neutral evidence for load
   progression specifically — its existing code explicitly overrides a
   would-be `.loadIncrease` verdict back to a documented "hold at
   pre-adaptation state" whenever the completed result followed an
   accepted adaptation, rather than letting a reduced/easier adapted
   session look like a real load-increase-worthy performance.

**This redesign inherits both guarantees for free**, since it promotes
this exact code path (§7) rather than replacing it. The one thing to
carry forward explicitly: the **same neutrality override** must apply
at the real materialization call site (§7 point 2), not just in the
display-only preview — currently only the preview has this override;
promoting the underlying decision into `RollTacticalWindowUseCase`
means this neutrality logic needs to be shared (extracted into one
function both call sites use), not reimplemented twice. Listed as an
implementation-slice requirement in §23, not a new design decision.

## 15. Substitution interaction — approved, made explicit

Rep range/RIR trajectory/load rule live on `PrescriptionTemplate` (per
slot), never on `Exercise` — substituting the resolved exercise (This
Session Only or Going Forward) changes which `Exercise` a slot resolves
to; it never touches the slot's own rules. **Progression history
belongs to the performed exercise, not the slot** (your explicit
correction): when Barbell Bench Press is substituted for Dumbbell Bench
Press, `lastKnownWeight`/`hasUsableHistory` for that exposure are looked
up against **Dumbbell Bench Press's own** logged history — never
carried over from Barbell Bench Press's. If Dumbbell Bench Press has no
history of its own, that exposure is a genuine calibration case (§10),
exactly as if it were a brand-new exercise — no estimate is transferred
between the two exercises. When the original exercise later returns,
its own prior history is untouched and still available (nothing was
overwritten or merged) — slot *intent* (the rep range/RIR/role) stays
constant across the substitution; performance *history* stays attached
to whichever concrete exercise actually produced it. This is exactly
the seam Home Gym will need later (§16) and is why history is keyed by
exercise, never by slot, in this design.

## 16. Home Gym future compatibility

No change to this seam. Rep range/RIR/load-rule are slot-level
concepts, entirely independent of which concrete exercise or equipment
environment a slot resolves against — exactly the same independence
Stage 10B's movement-intent seam (`allowedMovementFunctions`) already
relies on. A future Home Gym equipment filter narrows *which exercise*
resolves; it never needs to know about rep ranges or RIR at all.

## 17. Current-history / backward-compatibility implications

No real user data exists in production yet (confirmed in the prior
audit). Backward compatibility here means: any already-generated
`ProgramDefinition` (dev/seed data) keeps using whichever `LoadRule`/
`RepGoal` shape it was generated with — nothing retroactively
reinterprets an already-materialized week. A `generatorVersion` bump
(the same mechanism Stage 10B's own legacy/day-focus split already
uses) is the seam for the new rule set, exactly as before.

## 18. Legacy Family A disposition

**Decision: Option A — retained, explicitly renamed, not migrated or
deprecated in this pass.** Concretely:
- `HypertrophyProgramGenerator`'s existing constants
  (`laterWeekMultipliers`, `primaryWeekOneFactor`, `repGoalSchedule`,
  `pairedRepGoalSchedule`, `metaboliteFocusPairedWeekOneFactor`) and
  `generateLegacyFixedPair` stay **completely untouched** — every other
  curated Hypertrophy configuration (5 of 6) keeps this exact behavior,
  matching "do not alter Stage 10B Day A/B/C construction" and general
  minimal-footprint discipline.
- **Renaming is documentation-only in this pass**: doc comments on
  these constants gain an explicit note that this is "Family A —
  RM-testing/strength-biased ramp, no longer the default Hypertrophy
  philosophy as of Stage 10B.6; retained for a possible future
  strength-biased/peaking configuration" — no code moves, no new type
  created, nothing renamed at the symbol level yet (that would be
  Option B's job, explicitly deferred).
- **Not deprecated (Option C rejected for now)**: doing so would
  require auditing and replacing every existing test that asserts
  Family A's exact numbers — real work, not currently justified since
  nothing is being deleted.
- **Migrating into a real "strength-biased family" (Option B) is a
  distinct, future, not-yet-scoped stage** — noted as a natural next
  step but not part of this redesign.

## 19. External evidence table

Kept strictly separate from repository authority — every row below
informed a §3-§13 decision, none of it became a repository fact by
itself.

| Finding | Source | Classification of the resulting rule |
|---|---|---|
| Training within ~0-3 RIR of failure produces essentially the same hypertrophy as training to literal failure, with less fatigue; failure sets show only a "trivial advantage." | [Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy: A Systematic Review with Meta-analysis](https://pubmed.ncbi.nlm.nih.gov/36334240/) | Informed §4's RIR trajectory (never assuming 0 RIR is required) — TRAININGOS-DESIGNED exact numbers, evidence-informed |
| Hypertrophy improves somewhat closer to failure, but meaningfully drops off only beyond ~4-5 RIR; strength gains are similar across a wide RIR range. | [Exploring the Dose-Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy](https://pubmed.ncbi.nlm.nih.gov/38970765/) | Same — supports keeping RIR 1-3 rather than drifting toward failure or toward high-reserve training |
| Low-load training taken close to failure produces similar hypertrophy to high-load training; heavy loads matter more for maximal strength specifically. | [Strength and Hypertrophy Adaptations Between Low- vs. High-Load Resistance Training](https://pubmed.ncbi.nlm.nih.gov/28834797/) | Supports a genuine rep range (5-20 across roles) rather than one narrow band |
| Double progression is a recognized, practical method that avoids needing a tested 1RM; effort and volume (hard sets) matter more than the exact rep number; 6-20 reps is a broadly research-supported hypertrophy range. | [Double progression method / evidence summary — multiple sources including PMC10801605 narrative review](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10801605/) | Directly supports §7's algorithm choice and §11's e1RM removal |

**Explicit product choices made where evidence supports a range, not
one number:** exact rep-range boundaries (5-10/6-12/10-20) and exact RIR
numbers (3/2/2/1) are TRAININGOS-DESIGNED, chosen from within the
evidence-supported space, not scientifically mandated — flagged plainly
rather than dressed up as "the" research-backed number.

## 20. Rule provenance table (proposed new rules)

| Rule | Classification |
|---|---|
| Rep ranges 5-10 / 6-12 / 10-20 | TRAININGOS-DESIGNED, evidence-informed |
| RIR trajectory 3→2→2→1 (primary/secondary) | TRAININGOS-DESIGNED, evidence-informed |
| Accessory flat RIR 2 | TRAININGOS-DESIGNED |
| `.doubleProgression` load rule mechanics (revised per §6) | DERIVED (extends `DoubleProgressionEngine`'s existing shape; internal rule revised) |
| `RIR_SURPLUS_THRESHOLD = 2` (§6d) | TRAININGOS-DESIGNED, pending confirmation (§26) |
| `MAX_PROPORTIONAL_INCREMENT_RATIO = 0.10` (§6d) | TRAININGOS-DESIGNED, pending confirmation (§26) |
| Two-consecutive-miss REGRESS trigger; regress step = one `equipmentIncrement` | TRAININGOS-DESIGNED |
| Calibration = most-recent-logged-weight / user-entered estimate | TRAININGOS-DESIGNED |
| Set-count autoregulation mechanism | LEGACY (existing `AutoregulatedSetCount`, unchanged mechanism) — attribution fix is TRAININGOS-DESIGNED |
| Set-count bound baseline-1..baseline+2 (§8) | TRAININGOS-DESIGNED, approved |
| Deload set count = round(baseline*0.5), min 1; RIR target 4 | TRAININGOS-DESIGNED, approved |
| Deload load = performance-qualified resolution against deload targets (§13) | DERIVED (reuses §6 unchanged) |
| `RepGoal.repRangeHigh`/`targetRir` extension | DERIVED (schema extension of an existing type) |
| Family A itself (unchanged) | LEGACY |

## 21. Required schema/domain changes

- `RepGoal` (`TrainingOS/Domain/ValueTypes/StrengthProgressionRules.swift`):
  add `repRangeHigh: Int?`, `targetRir: Int?` — both optional, both
  additive, zero effect on existing storage/behavior when absent.
- `PrescriptionTemplate`: parallel flattened storage arrays for the two
  new `RepGoal` fields (matching the existing `repGoalReps`/
  `repGoalToFailure` pattern) — e.g. `repGoalRepsHigh: [Int]`,
  `repGoalTargetRir: [Int]` with a sentinel (e.g. `-1`) or an
  `hasExplicitRange`/`hasExplicitRir` parallel `[Bool]`, matching this
  file's own established "manually flattened tagged union" discipline.
  Exact sentinel-vs-parallel-bool choice left to implementation, not a
  product decision.
- `LoadRuleKind`: add `case doubleProgression` (no new stored payload
  fields required — resolution reads existing `ExercisePrescription`/
  `SetResult` history via the caller-supplied `SlotContext`, exactly
  like `.rmBased` already does for `rmKilograms`).
- `StrengthMaterializer.SlotContext`: add fields to carry the
  `.doubleProgression` inputs (`priorTargets: [SetTarget]?`,
  `priorResults: [SetOutcome]?`, `lastKnownWeight: Double?`) — additive,
  defaulted to `nil`, zero effect on Family A/B/C's existing usage.
- `ProgressionEngine.swift`'s `ProgressionInput` (not persisted —
  a plain in-memory engine input, confirmed via its own file; this is
  a code-shape change, not a `SwiftData` schema change): add two more
  optional fields, `previousTargets: [SetTarget]?` and
  `previousResults: [SetOutcome]?`, carrying the immediately preceding
  exposure's targets/results for the two-consecutive-miss REGRESS check
  (§6a step 5). Both `nil`-safe — when absent, REGRESS is simply
  unreachable and a repeat miss falls to plain `HOLD`, never regressing
  without evidence.
- `ProgressionReasonCode`: **no new case needed.** Confirmed by reading
  the actual enum — `.loadIncrease`, `.repIncrease`, `.hold`,
  `.calibrationRequired` already exist and map directly to `INCREASE
  LOAD`/`HOLD LOAD / PROGRESS REPS`/`HOLD`/`CALIBRATION REQUIRED`; and
  `.loadDecrease` — already declared, currently dormant/unreachable per
  the engine's own doc comment — is exactly `REGRESS`. The entire
  required output vocabulary already exists in this codebase.
- No new `@Model` entity. No new delete rule. No change to
  `ExercisePerformanceProfile`, `SetResult`, `PersonalRecord`.
- `AutoregulationRatingResolver`/day-focus generator: attribution fix
  per §9 — either a self-referential `pairedSlot` or a small marker;
  exact shape an implementation detail, not a schema-risk item (no new
  entity either way).

## 22. Migration implications

Same as §17 — no real users, no retroactive reinterpretation of
already-materialized weeks, `generatorVersion` bump for the new rule
set, Family A untouched for existing/legacy configurations.

## 23. Implementation slices (proposed order, not yet approved)

1. Schema: extend `RepGoal`, add `.doubleProgression` `LoadRuleKind`,
   extend `SlotContext` — no behavior change yet (everything still
   defaults to old behavior).
2. Deload reachability fix (§12) — independent, low-risk, no numeric
   redesign dependency; can ship alone if you want it decoupled.
3. Deload RIR decoupling (§13) — depends on slice 1's `targetRir`
   field.
4. New Hypertrophy rule set wired into `generateDayFocusDriven` only
   (rep ranges + RIR trajectory + `.doubleProgression`) — legacy path
   untouched.
5. `RollTacticalWindowUseCase`'s new `.doubleProgression` slot-context
   branch + shared readiness-neutrality extraction (§14).
6. Calibration path (§10) — first-exposure handling.
7. Feedback attribution fix + consolidated-screen UI (§9).
8. Set-count ceiling guard (§8).

## 24. Automated test plan

- Rep-range/RIR schema: round-trip persistence tests for the two new
  `RepGoal` fields, proving legacy `RepGoal`s (nil fields) are
  byte-identical in behavior to before.
- `.doubleProgression` resolution: load-increase / hold-below-range /
  hold-within-range / calibration-required cases, mirroring
  `DoubleProgressionEngine`'s own existing logic exactly (regression
  proof it wasn't altered).
- Deload reachability: a real `rollForward` call reaching `weekIndex==4`
  now produces `isDeload: true` behavior, not `.calibrationRequired`.
- Deload RIR: deload `SetPrescription.targetRir` is the new explicit
  value, never derived from the accumulation weeks' `toFailure`.
- Feedback attribution: rating one primary slot's own feedback no
  longer changes a sibling primary/secondary slot's next-week set
  count (direct regression test for the exact bug found in the prior
  audit).
- Readiness neutrality: an accepted adaptation still produces a
  "hold, neutral" verdict at the **real materialization** call site,
  not just the display preview.
- Calibration: first-ever exposure to an exercise produces
  `.calibrationRequired`/a labeled calibration set, never a fabricated
  weight; second exposure correctly uses the first's logged weight.
- Legacy/Family A/Powerlifting: full existing regression suite stays
  green, unmodified, proving zero behavior change outside the new rule
  set.
- Full suite green before any manual acceptance step.

## 25. Simulator acceptance plan

1. Generate a fresh Muscle Gain → 3-Day Full Body program; confirm Day
   A/B/C now show rep **ranges** (e.g. "5-10 reps") and non-zero RIR
   targets, not `3×3 @ 0 RIR`.
2. Log a full, on-target week 1 for one primary exercise; confirm week
   2's load increases by exactly one equipment increment, and the
   "Next time" preview shown at Finish matches what actually gets
   materialized.
3. Log a week where a set falls short of the rep range; confirm load
   holds, not increases.
4. Trigger the consolidated feedback screen; rate two different
   primary/secondary slots differently; confirm their next-week set
   counts diverge (the fan-out fix, directly observable).
5. Roll a program to week 5; confirm a visibly different deload week
   (lower effort, explicit non-failure RIR) actually appears, rather
   than a blank/broken week.
6. Trigger a readiness adaptation (pain/low energy), accept it, log the
   adapted session; confirm next week's load is unaffected (still
   reflects genuine prior performance, not the adapted-down session).

## 26. Remaining decisions requiring your approval

**Resolved by your D-10B6-1..10 approval message** (no longer open):
mesocycle length/shape, rep ranges, RIR trajectory, set-count bounds
(baseline-1/baseline+2) and baselines (3/3/2), feedback attribution
approach and grouping rule, calibration approach, e1RM scope, deload
set-count/RIR shape, Family A disposition (Option A), external-evidence
posture, readiness/substitution/Home-Gym principles.

**Still open — specific to the load-first rule resolved in this
message (§6), needing your explicit sign-off before implementation:**

1. **`RIR_SURPLUS_THRESHOLD = 2`** (§6d) — the amount of extra reserve
   beyond target RIR that qualifies as "meaningfully easier," making an
   otherwise-inside-range set count as strong performance. Confirm or
   adjust.
2. **`MAX_PROPORTIONAL_INCREMENT_RATIO = 0.10`** (§6d) — the ceiling
   ratio (increment ÷ current weight) past which an available increment
   is treated as disproportionate and the engine holds instead of
   forcing the jump. Confirm or adjust.
3. **REGRESS step size = one `equipmentIncrement`** (§6a step 5, same
   magnitude as an increase, just downward) — confirm this is
   sufficient, or specify a different (e.g. larger) step down.
4. **Two-consecutive-miss trigger for REGRESS** (§6a step 5) — confirm
   "two in a row" is the right bar, vs. a different count.
5. **Deload's first-exposure reasoning** (§13) — confirm that reusing
   §6's ordinary performance-qualified rule against the deload week's
   own (easier) targets is sufficient, with no separate "first deload
   exposure" special case.
6. **Attribution mechanism for self-rated slots** (§9/§21) — self-
   referential `pairedSlot` vs. a small dedicated marker; an
   implementation-detail choice that touches schema, flagged for
   awareness rather than a real decision.

**Do not implement any of the above yet. Do not commit. Do not push.
Do not start Stage 10C.**
