# Stage 10R.1 — Slice 1B Source Progression Design & Trace

**STATUS: APPROVED AND IMPLEMENTED.** This document was originally a
design/source-trace-only pass; the user reviewed it, approved all
decisions (see `STAGE10R1_SLICE1B_IMPLEMENTATION_REPORT.md`), and Slice
1B has now been implemented exactly as designed below, with one
additional discovered-and-fixed defect not anticipated by this design
pass (`AutoregulationRatingResolver`'s cross-day completion-ordering bug
— see the implementation report's item 14). Every formula below is
quoted directly from `3 day full body_Novice.xlsx`, "Mesocycle 1 Basic
Hypertrophy" sheet, re-extracted and re-verified during the design pass
(not re-cited from memory) — cell addresses given throughout. Not
committed, not pushed — awaiting manual acceptance per the user's
explicit instruction.

---

## Part 1 — Complete source algorithm, one representative slot

Representative slot: **row 11, "Horizontal Push"** (Day 1 "Push Emphasis").

### Load

| Step | Formula | Cell |
|---|---|---|
| 10RM input | user-entered | `G11` |
| Week 1 | `=MROUND(((G11)*0.85),5)` | `J11` |
| Week 2 | `=MROUND((J11*1.05),5)` | `P11` |
| Week 3 | `=MROUND((J11*1.075),5)` | `V11` |
| Week 4 | `=MROUND((J11*1.1),5)` | `AB11` |
| Deload | `=J11` (full weight — Day 1 is before the boundary) | `AH11` |

Worked numeric example, 10RM = 100: Week1 = MROUND(85,5) = **85**. Week2 =
MROUND(85×1.05,5) = MROUND(89.25,5) = **90**. Week3 =
MROUND(85×1.075,5) = MROUND(91.375,5) = **90**. Week4 =
MROUND(85×1.1,5) = MROUND(93.5,5) = **95**. Deload = **85** (unchanged,
full weight).

### Sets

| Step | Formula | Cell | Rating source |
|---|---|---|---|
| Week 1 (baseline) | `=3` (literal) | `I11` | — |
| Week 2 | `=I11+(M29)` | `O11` | row 29's Week-1 rating |
| Week 3 | `=O11+(S29)` | `U11` | row 29's Week-2 rating |
| Week 4 | `=U11+(Y29)` | `AA11` | row 29's Week-3 rating |
| Deload | `=2` (literal constant) | `AG11` | — |

### Rep/failure target

| Week | Value | Cell |
|---|---|---|
| 1 | `3/fail` | `K11` |
| 2 | `3/fail` | `Q11` |
| 3 | `2/fail` | `W11` |
| 4 | `1/fail` | `AC11` |
| Deload | `1/2 reps of Week 1` (text) | `AI11` |

No formula anywhere computes reps/failure — it is a fixed, literal
per-week schedule, identical for every one of the 24 slots (already
confirmed in Slice 1A's audit, re-confirmed here).

---

## Part 2 — Complete 24-slot rating relationship table

All cells re-verified directly against the extraction this pass (not
carried over from memory). "Source slot" = the row whose rating column
feeds the current slot's next-week set formula — **the same source row
for every week transition** (Week1→2 reads that row's Week-1 rating
column `M`; Week2→3 reads `S`; Week3→4 reads `Y`).

| # | Day | Category (source label) | Row | Rating source row | Source day | Source category | Cell evidence |
|---|---|---|---|---|---|---|---|
| 1 | Push Emphasis | Horizontal Push | 11 | 29 | Legs Emphasis | Horizontal Push | `O11='=I11+(M29)'` |
| 2 | Push Emphasis | Chest Isolation or Triceps | 12 | 29 | Legs Emphasis | Horizontal Push | `O12='=I12+(M29)'` |
| 3 | Push Emphasis | Incline Push or Front Delts | 13 | 28 | Legs Emphasis | Incline Push or Front Delts | `O13='=I12+(M31)'`* |
| 4 | Push Emphasis | Side Delts | 14 | 25 | Legs Emphasis | Side Delts | `O14='=I14+(M25)'` |
| 5 | Push Emphasis | Vertical Pull | 15 | 26 | Legs Emphasis | Vertical Pull | `O15='=I15+(M26)'` |
| 6 | Push Emphasis | Horizontal Pull | 16 | 27 | Legs Emphasis | Horizontal Pull | `O16='=I16+(M27)'` |
| 7 | Push Emphasis | Hamstrings Isolation | 17 | 24 | Legs Emphasis | Hamstrings Hip Hinge | `O17='=I17+(M24)'` |
| 8 | Push Emphasis | Quads | 18 | 22 | Legs Emphasis | Quads (1st) | `O18='=I18+(M22)'` |
| 9 | Legs Emphasis | Quads (1st) | 22 | 18 | Push Emphasis | Quads | `O22='=I22+(S18)'` |
| 10 | Legs Emphasis | Quads (2nd) | 23 | 18 | Push Emphasis | Quads | `O23='=I23+(S18)'` |
| 11 | Legs Emphasis | Hamstrings Hip Hinge | 24 | 40 | Pull Emphasis | Hamstrings Isolation | `O24='=I24+(M40)'` |
| 12 | Legs Emphasis | Side Delts | 25 | 35 | Pull Emphasis | Rear Delts or Side Delts | `O25='=I25+(M35)'` |
| 13 | Legs Emphasis | Vertical Pull | 26 | 33 | Pull Emphasis | Vertical Pull | `O26='=I26+(M33)'` |
| 14 | Legs Emphasis | Horizontal Pull | 27 | 34 | Pull Emphasis | Horizontal Pull | `O27='=I27+(M34)'` |
| 15 | Legs Emphasis | Incline Push or Front Delts | 28 | 38 | Pull Emphasis | Incline Push | `O28='=I28+(M38)'` |
| 16 | Legs Emphasis | Horizontal Push | 29 | 37 | Pull Emphasis | Horizontal Push | `O29='=I29+(M37)'` |
| 17 | Pull Emphasis | Vertical Pull | 33 | 15 | Push Emphasis | Vertical Pull | `O33='=I33+(S15)'` |
| 18 | Pull Emphasis | Horizontal Pull | 34 | 16 | Push Emphasis | Horizontal Pull | `O34='=I34+(S16)'` |
| 19 | Pull Emphasis | Rear Delts or Side Delts | 35 | 14 | Push Emphasis | Side Delts | `O35='=I35+(S14)'` |
| 20 | Pull Emphasis | Biceps | 36 | 15 | Push Emphasis | Vertical Pull | `O36='=I36+(S15)'` |
| 21 | Pull Emphasis | Horizontal Push | 37 | 11 | Push Emphasis | Horizontal Push | `O37='=I37+(S11)'` |
| 22 | Pull Emphasis | Incline Push | 38 | 11 | Push Emphasis | Horizontal Push | `O38='=I38+(S11)'` |
| 23 | Pull Emphasis | Glutes | 39 | 24 | Legs Emphasis | Hamstrings Hip Hinge | `O39='=I39+(S24)'` |
| 24 | Pull Emphasis | Hamstrings Isolation | 40 | 17 | Push Emphasis | Hamstrings Isolation | `O40='=I40+(S17)'` |

*Row 13 (Incline Push or Front Delts, the superset partner's Week-1 slot
in this Mesocycle's numbering — no, this file has no superset mechanic in
Mesocycle 1; row 13 is a plain slot) references row 28's rating column,
matching the general pattern.

### The general rule, proven, not assumed

Looking down the "rating source row" column: **every source row is fixed
for all three week-transitions of a given slot** (e.g. row 11 always
reads row 29 — `M29` for Week2, `S29` for Week3, `Y29` for Week4, never a
different row at a different week). This is confirmed for all 24 slots —
there is no case where the source row changes mid-mesocycle.

**This means the mechanism is a fixed, authoring-time row-to-row pointer
— identical in shape to the existing `PrescriptionTemplate.pairedSlot`
field — not a dynamically-resolved "search history for the most recent
occurrence."** The "chronological last-trained occurrence" phrase used in
the earlier audit describes *why* the spreadsheet's original author
likely chose these specific pairings (each source row usually is, in
real calendar terms, the most recently-completed occurrence of a related
movement pattern) — but the workbook itself does not compute that
relationship dynamically. It is baked into the formula, once, forever,
exactly as `STAGE3_DECISION_MEMO.md` A5 already concluded for the
general Family A mechanism ("every pairing was hand-authored, cell by
cell... a direct, authoring-time model reference is simpler, matches the
source's actual design"). This document's own trace **confirms** A5 was
correct, rather than assuming it.

---

## Part 3 — Exercise-selection interaction

**Answer: A — the relationship follows the source SLOT (row/category
position), never the specific selected exercise.**

The rating-source formula (`O11='=I11+(M29)'`) references a cell
address, which corresponds to a **row** — and a row is exactly one
category/day position (e.g. "row 29 = Legs Emphasis's Horizontal Push
slot"), completely independent of which literal exercise name a user
typed into column `C`/chose from the dropdown for that row. If a real
user changes their Week-1 Quads exercise from Front Squat to Leg Press
(both valid dropdown options for row 18/22/23), **the rating formulas
`O18`, `O22`, `O23`, etc. do not change at all** — they still reference
the same fixed rows. Exercise selection and the rating-pairing mechanism
are completely orthogonal in the source.

**Direct implication for the current TrainingOS architecture:** this is
*exactly* what `PrescriptionTemplate.pairedSlot: PrescriptionTemplate?`
already models — a structural pointer between two template rows,
independent of `ExerciseSlot.resolvedExercise`. No new mechanism is
needed for this; `pairedSlot` just needs to be *assigned correctly*
(per the Part 2 table above) instead of self-referencing.

---

## Part 4 — Source set progression, exact behavior and undefined cases

**Explicit source behavior:**
- `weekN.sets = week(N-1).sets(same row) + rating(source row, week N-1)`.
- Week 1 is always a fixed literal constant per row (3, or 2 for the
  8 lower-baseline slots) — never itself computed from a rating.
- The rating dropdown is constrained by the workbook's own data
  validation to exactly **`{1, 0, -1}`** (confirmed directly:
  `formula1=$C$85:$C$87` → `C85=1`, `C86=0`, `C87=-1`).
- Deload sets are a separate literal constant (`2`), never computed
  from any rating and never feeding anything else.

**Cases the workbook does NOT define (flagged, not resolved here):**
- **No floor or ceiling.** No formula anywhere wraps the addition in
  `MAX`/`MIN`. A hypothetical unbroken run of `-1` ratings has no
  source-defined floor (could mathematically reach 0 or below); no
  source-defined ceiling either. **Product decision needed**: whether
  TrainingOS should clamp (and to what) or faithfully leave this
  unbounded, matching the source exactly.
- **Blank rating.** Excel arithmetic treats a blank referenced cell as
  `0` — meaning an unrated week is *implicitly* treated as "felt fine,
  no change" by the source spreadsheet's own arithmetic, not as an error
  or an undefined state. This is a real, if accidental, source behavior
  distinct from `StrengthProgressionEngine`'s current
  `.calibrationRequired` guard (which treats a missing rating as "cannot
  resolve," not "treat as zero"). **Flagged for a decision**: replicate
  Excel's implicit-zero behavior, or keep the stricter
  `.calibrationRequired` guard (arguably the more defensible product
  choice, but it is a deliberate deviation from literal source behavior,
  not something to silently assume).
- **Skipped session.** The workbook has no concept of "skipped" at all —
  it is a static template, not an execution log. A real skipped week
  reduces, in source terms, to the same "blank rating" case above.
- **Exercise-selection changes.** Per Part 3, continuity is unaffected —
  the source never conditions the formula on which exercise is chosen.
- **Deload ratings.** Confirmed: the deload week's column block has no
  rating column at all (`AF9`-`AI9` headers are Exercise/Sets/Weight/Rep
  Goal only — no "*Rating" column, unlike every progressive week). Deload
  neither consumes nor produces a rating.
- **Next mesocycle's starting point.** Already established
  (`STAGE3_DECISION_MEMO.md` A1, re-confirmed structurally this pass — no
  cross-sheet formula reference exists anywhere in this workbook): each
  mesocycle's Week-1 RM cell is blank and independent. Nothing carries
  load, sets, or rating across a mesocycle boundary.

---

## Part 5 — Source load progression, rounding vs. TrainingOS equipment increments

**Confirmed: Week 2/3/4 all multiply the *resolved* (already-rounded)
Week-1 cell (`J{row}`), never chaining week-to-week.** `P11`, `V11`,
`AB11` are each `MROUND(J11 × multiplier, 5)` — none references `P11`
or `V11` as an input to the next week. This matches
`StrengthProgressionEngine.resolveWeight`'s `.rmBased` case **exactly**,
confirmed by direct re-read this pass: for `weekIndex > 0`, it computes
`equipmentProfile.resolve(IdealLoad(kilograms: weekOneResolvedWeightKg *
payload.laterWeekMultipliers[multiplierIndex]))` — i.e., it already takes
the **resolved** (rounded) Week-1 value and multiplies fresh each time,
never chaining. **This is not a coincidence: `StrengthProgressionEngine`
was built in Stage 4A specifically to reproduce this exact source
mechanism**, and it does so correctly.

**Rounding — the important difference to report, not silently paper
over:** the source's `MROUND(x, 5)` rounds to the nearest **5 of
whatever unit the sheet's author was using** — per `METRIC_LOAD_MODEL.md`
(already-resolved, pre-existing product decision), the source material is
authored in **pounds**, so "5" almost certainly means "5 lb," not "5 kg."
`StrengthProgressionEngine`/`EquipmentProfile.resolve()` does **not**
reproduce "5" as a literal kg rounding unit anywhere — it resolves
against the *user's own* `EquipmentProfile.smallestIncrementKg` (e.g.
2.5 kg for a standard barbell), per the already-locked
`METRIC_LOAD_MODEL.md` decision that literal source rounding constants
must never be carried into TrainingOS as a kg figure. **This existing
architecture is already correct and requires no change** — the source's
"5" is authoring-context noise (`STAGE3_DECISION_MEMO.md` C2), not a
value to reproduce literally. Restoring `.rmBased` for this slice does
**not** mean restoring "round to nearest 5" — it means restoring the
*shape* (fixed-Week-1-anchor, resolve-and-round-at-every-step), using the
real user's own equipment profile, exactly as `StrengthProgressionEngine`
already does.

---

## Part 6 — Deload, traced and compared against both existing implementations

Recovered directly (re-verified this pass, all 24 rows):
- **Weight:** full Week-1 weight (`AH{row}='=J{row}'`) for Day 1 and Day 2
  (`dayPositionInWeek` 0 and 1); `MROUND(J{row}×0.5, 5)` for Day 3
  (`dayPositionInWeek` 2). Boundary = `ceil(3/2) = 2`.
- **Reps:** `AI{row} = "1/2 reps of Week 1"` (text) for every row, no
  exception.
- **Sets:** `AG{row} = 2` (literal constant) for every row, no exception.
- **Rating:** none consumed or produced (Part 4).
- **Progression continuity:** deload always reads `J{row}` (Week 1's own
  resolved cell), never Week 4's value.

**Comparison:**
- **`SourceCompatibleDeloadStrategy`** (`DeloadStrategy.swift`, re-read in
  full this pass): `resolveDeloadWeight`'s default path computes
  `boundary = ceil(dayCount/2)`, `fullFactor = 1.0`, `halfFactor = 0.5`,
  applied to `weekOneResolvedWeightKg` — **an exact match**, confirmed
  line-by-line against the cells above, not merely by citation.
  `resolveDeloadRepGoal`'s default path applies `deloadRepFraction`
  (0.5) rounded **down** — **an exact match** to `STAGE3_DECISION_MEMO.md`
  A3 and the literal "1/2" text. `resolveDeloadSetCount` returns
  `rules.deloadSetCount` (default `2`) — **an exact match**.
- **Stage 10B.6's V2 deload path** (`HypertrophyV2ProgressionEngine`,
  reached via `.doubleProgression`): resolves deload through its own
  internal logic — confirmed in Slice 1A's audit to never invoke
  `SourceCompatibleDeloadStrategy` at all for this configuration, and
  (per `STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md`) uses a flat RIR
  ≥4, never-to-failure deload target, which has no source citation at
  all — this is TrainingOS-designed, not a reproduction of the cells
  above.

**Conclusion: `SourceCompatibleDeloadStrategy` already faithfully
reproduces the source exactly, verified directly, and needs no changes
whatsoever.** Slice 1B's job for deload is purely to route the 3-Day
configuration back to it, not to build or fix anything.

---

## Part 7 — Architecture mapping

| Concept | Classification | Reasoning |
|---|---|---|
| `LoadRuleKind.rmBased` | **REUSE AS-IS** | Confirmed exact match, Part 5/1 |
| `LoadRuleKind.doubleProgression` | **RETIRE FROM THIS SOURCE PATH** | Not source behavior; the type/mechanism itself is not deleted — it remains available for the future load-bias overlay stage |
| `StrengthProgressionEngine` | **REUSE AS-IS** | `resolveWeight`/`resolveSetCount`/`resolveRepGoal` all confirmed exact matches by direct re-read this pass |
| `HypertrophyV2ProgressionEngine` | **RETIRE FROM THIS SOURCE PATH** | Not source behavior for this program; kept as infrastructure for the future overlay |
| `DoubleProgressionEngine` | **RETIRE FROM THIS SOURCE PATH** | Same as above |
| `SourceCompatibleDeloadStrategy` | **REUSE AS-IS** | Confirmed exact match, Part 6 |
| `RepGoal` | **REUSE AS-IS (the `reps`/`toFailure` fields)** | `repRangeHigh`/`targetRir` (Stage 10B.6 additions) simply stay `nil` for this path — already-designed-additive, no schema change needed |
| `PrescriptionTemplate.pairedSlot` | **REWIRE** | The mechanism is exactly right (Part 3); the *assignment* must change from Stage 10B.6's self-reference to the real Part-2 table |
| `SetCountRule.autoregulated`/`AutoregulatedSetCount` | **REUSE AS-IS** | Already correctly models "baseline + prior-week rating from paired slot"; needs no change |
| `ExercisePrescription.appliedProgressionReasonCode` | **RETIRE FROM THIS SOURCE PATH (field stays, unused here)** | Typed to `ProgressionReasonCode` (`DoubleProgressionEngine`'s vocabulary) — confirmed by direct read of `ExercisePrescription.swift`. `StrengthProgressionEngine` produces `StrengthReasonCode` values instead, which have no field to persist into. See Part 8. |
| `SlotSelectionOverride` | **REUSE AS-IS** | Unrelated to progression; already generic |
| `ExercisePrescription`/`SetPrescription` | **REUSE AS-IS** | Generic execution-state entities, no change needed |
| `SetResult`/`WorkoutResult` | **REUSE AS-IS** | Unaffected — these record what actually happened, independent of which engine computed the target |
| `PerformanceProfile`/`ExercisePerformanceProfile` | **REUSE AS-IS** | `StrengthProgressionEngine`'s `.rmBased` path does not even consult these (its only history input is `weekOneResolvedWeightKg`, an explicit parameter) — simpler than `.doubleProgression`'s dependency on `DoubleProgressionHistoryResolver` |
| Autoregulation feedback storage (`RecordAutoregulationFeedbackUseCase`, rating on `ExercisePrescription`) | **REUSE AS-IS, REWIRE the read side** | The write path (a user submits −1/0/+1) is unaffected; the *read* side (`AutoregulationRatingResolver`) must read the correctly-paired slot per Part 2, not the self-paired slot Stage 10B.6 wired in |

No new entity type is required anywhere in this mapping.

---

## Part 8 — Provenance / auditability

Two different mechanisms end up carrying the explanatory burden:

1. **Load**: `StrengthReasonCode.rmBasedLoad` is already a real,
   descriptive reason code — but per Part 7, `ExercisePrescription` has
   no field typed to hold it today. Following the exact precedent
   `STAGE4_IMPLEMENTATION_REPORT.md` already established for Family A
   ("No `Recommendation` is persisted... the engine is pure and
   deterministic, any later audit can simply re-run it"), the
   recommended path is: **do not add a new persisted field for this
   slice** — the explanation ("82.5 kg because Week-1 anchor was 85 kg
   and Week-3's multiplier is 1.075, per the source formula") is always
   reproducible on demand by re-running `StrengthProgressionEngine
   .resolveWeight` with the same recorded `weekOneResolvedWeightKg`,
   which the materializer already threads through. This is flagged as a
   real decision, not silently assumed: if stored, inspectable
   provenance is wanted sooner, a small additive
   `appliedStrengthReasonCode: StrengthReasonCode?` field is the correct,
   low-risk shape — but that is a genuine scope decision for you, not
   something to add reflexively.
2. **Sets**: identical situation — `StrengthReasonCode.autoregulatedSetIncrease`/
   `.autoregulatedSetHold`/`.autoregulatedSetDecrease` already exist and
   are already descriptive ("3 sets this week because this slot had 2
   sets last week and the paired slot's rating was +1") — same
   re-run-on-demand answer, contingent on `pairedSlot` finally pointing
   at the correct row (Part 3/7).

**No black-box resolver is introduced by this design** — every number
remains explainable by re-running an existing, pure, already-tested
function against already-durable inputs (`SetResult`/`WorkoutResult`,
per CLAUDE.md rule 20's existing durability guarantee).

---

## Part 9 — Migration / existing ProgramInstances

- **New `ProgramInstance`s** created after Slice 1B ships: unaffected,
  get the restored `.rmBased` behavior automatically.
- **Already-materialized `ProgramDefinition`s** (any prior Simulator
  run, including anything seeded before this design lands): per the
  existing, already-proven `ProgramDefinition.generatorVersion`
  invariant, a generator change **never retroactively rewrites an
  already-persisted template graph** — an old definition's
  `PrescriptionTemplate` rows keep whatever `LoadRule`/`pairedSlot` they
  were generated with. This is the correct, safe default and requires no
  new migration code.
- **A genuine gap discovered by this trace, not by assumption:**
  `HypertrophyProgramGenerator.currentVersion` was **not** bumped by
  Slice 1A, even though Slice 1A changed what the generator produces for
  this configuration. This is a real, if narrow, inconsistency with the
  codebase's own stated convention (a meaningful shape change should be
  distinguishable via `generatorVersion` for any future code that might
  branch on it). **Recommendation, not yet implemented:** bump
  `currentVersion` once, as part of Slice 1B's own change (covering both
  Slice 1A's and 1B's cumulative content+progression changes together,
  since neither shipped a version bump yet) — flagged here for your
  decision, not silently corrected in this design-only pass.
- **In-progress/completed history**: `SetResult`/`WorkoutResult`/
  `PersonalRecord`/`ExercisePerformanceProfile` are never touched by a
  generator or rule-engine change (CLAUDE.md rule 1) — confirmed nothing
  in this design proposes writing to any of them differently.
- **Simulator/debug seeded data**: `SeedAnnualPlanJourney`'s existing
  seed will simply pick up the restored `.rmBased` behavior on its next
  fresh run, exactly like any other `ProgramInstance` — no special
  handling needed, since seeding always regenerates from scratch.

**Recommended safest behavior**: no migration code at all — rely on the
existing `generatorVersion`-frozen-template-graph invariant, and treat
"start a fresh instance" as the only way to observe the restored
behavior, exactly as Slice 1A already did.

---

## Part 10 — Proposed source-derived test matrix

All 20 requested categories, each anchored to a real, precomputed
number from Part 1's worked example (10RM = 100) or the Part 2 table:

1. Week-1 load: `MROUND(100×0.85,5) = 85`.
2. Week-2 load: `MROUND(85×1.05,5) = 90`.
3. Week-3 load: `MROUND(85×1.075,5) = 90`.
4. Week-4 load: `MROUND(85×1.1,5) = 95`.
5. Fixed-Week-1-anchor proof: assert Week-3/4 are computed from the
   stored Week-1 resolved value, not from Week-2's — construct a case
   where "chained" vs. "anchored" would diverge and confirm the anchored
   result.
6. Source rounding: assert `EquipmentProfile.resolve` is invoked at
   every week (not once at the end), using a *user* increment (e.g.
   2.5 kg), never the literal source "5".
7. Week-1 rep/failure target: `3/fail`.
8. Week-4 rep/failure target: `1/fail`.
9. `+1` rating: baseline 3 → Week 2 = 4.
10. `0` rating: Week 2 = 4 → Week 3 = 4.
11. `-1` rating: Week 3 = 4 → Week 4 = 3.
12. Chronological rating-source relationship: row 11 (Day 1) reads row
    29's (Day 2) rating for Week 2 — assert via `pairedSlot`.
13. Relationship across days: row 33 (Day 3) reads row 15's (Day 1)
    rating — a different-direction cross-day case than #12.
14. Same category appearing multiple times: Day 2's two "Quads" rows
    (22, 23) both read row 18's rating — assert both slots share the
    identical `pairedSlot` target without merging into one slot.
15. Source-approved exercise-selection interaction: changing the
    resolved exercise for a slot must never change its `pairedSlot`
    target (Part 3) — construct the case explicitly.
16. Deload first-half (Day 1/2) load: full Week-1 weight, unchanged.
17. Deload second-half (Day 3) load: `MROUND(85×0.5,5) = 40`* (*using
    this document's own 85 anchor — recompute exactly at implementation
    time, don't assume).
18. Deload sets: `2`, every slot.
19. Deload reps: `floor(3×0.5) = 1`.
20. Source path never invokes `DoubleProgressionEngine`/
    `HypertrophyV2ProgressionEngine` — assert by construction (e.g. a
    call-count/spy, or asserting `loadRule == .rmBased` and reason codes
    are `StrengthReasonCode`, never `ProgressionReasonCode`).

All fixtures CONSTRUCTED (RM=100, per this project's existing labeling
discipline) since the real workbook ships blank — same discipline
`PROGRAM_REGRESSION_TEST_PLAN.md` already established, just against a
now-primary-source-verified formula set rather than the secondary
analysis.

---

## Rule classification (global vs. program-specific), for future recovery

| Rule | Classification |
|---|---|
| `week1 = MROUND(10RM×factor, unit)` | **GLOBAL FAMILY-A SOURCE RULE** (factor varies by mesocycle, unit varies by file — parameters, not the rule shape) |
| `weekN = MROUND(week1×multiplier, unit)`, multipliers `1.05/1.075/1.1` | **GLOBAL FAMILY-A SOURCE RULE** (identical constants confirmed across every family in prior cross-family audits) |
| `sets = priorSets + pairedRow'sRating` | **GLOBAL FAMILY-A SOURCE RULE** (mechanism); **the specific pairing table (Part 2) is PROGRAM-SPECIFIC** — every day-count/split file has its own row layout and therefore its own pairing table |
| Rep-goal schedule `3/fail,3/fail,2/fail,1/fail` | **MESOCYCLE-SPECIFIC RULE** (Basic Hypertrophy's own; Metabolite Focus/Resensitization have different week-1 factors and, for Resensitization, a shorter 2-progressive-week structure) |
| Deload day-boundary `ceil(dayCount/2)`, 1.0/0.5 factors | **GLOBAL FAMILY-A SOURCE RULE** (already proven identical across every day-count in Stage 4A's own regression fixtures) |
| Which specific row pairs with which | **PROGRAM-SPECIFIC (per day-count/split file)** |
| Legs-split "Heavy" 1.0× override | **SLOT-SPECIFIC SOURCE OVERRIDE** (confirmed in Stage 10R's earlier audit: applies to specific rows on specific days within the `.legs` file only) |

This confirms Slice 1B's restored mechanism (`.rmBased` +
`StrengthProgressionEngine` + `SourceCompatibleDeloadStrategy` +
correctly-wired `pairedSlot`) generalizes cleanly to the other 10
Hypertrophy workbooks later — only the Part 2-style pairing table and
the Week-1/rep-goal parameters need to be re-derived per file, never the
engine.

---

## Proposed Slice 1B implementation scope (design only — not yet approved for build)

1. Change `makeSourceCategoryTemplate` (or its successor) to build
   `.rmBased(RMBasedLoad(rmType: .rm10, weekOneFactor: 0.85,
   laterWeekMultipliers: [1.05, 1.075, 1.1]))` instead of
   `.doubleProgression`, using the existing `repGoalSchedule` shape
   (`3/fail, 3/fail, 2/fail, 1/fail`) instead of
   `HypertrophyV2ProgressionEngine.makeRepGoalSchedule`.
2. Set `deloadWeightAction`/`deloadRepAction` to their existing defaults
   (`.standard`) so `SourceCompatibleDeloadStrategy` is reached —
   confirm no `deloadWeightPositionOverride`/`deloadRepPositionOverride`
   is needed (Family A's un-overridden `ceil(dayCount/2)` formula
   already matches this file exactly).
3. Replace the self-referencing `template.pairedSlot = template` loop
   with the exact 24-entry pairing table from Part 2.
4. Confirm `StrengthMaterializer` routes `.rmBased` templates through
   `StrengthProgressionEngine` (not `HypertrophyV2ProgressionEngine`) —
   per Stage 4A/4B, this should already be the existing, unmodified
   branch every other configuration already uses.
5. Bump `HypertrophyProgramGenerator.currentVersion` once (Part 9).
6. Rewrite `HypertrophyDayFocusGenerationTests.swift`'s progression
   assertions (currently asserting `.doubleProgression`/rep-range/RIR)
   to assert the restored `.rmBased`/rep-goal-schedule shape, and add
   the Part 10 test matrix.
7. Update every other test file Slice 1A already touched
   (`HypertrophyV2EndToEndTests.swift` in particular — its entire premise
   is testing `.doubleProgression`; this file's *content* helpers stay,
   but its progression assertions will need to change to `.rmBased`
   semantics, or the file's scope may need to be reconsidered — flagged
   as a real, non-trivial follow-on, not solved here).

**Explicitly not in scope for Slice 1B**: Mesocycle 2/3, any other
Hypertrophy configuration, the load-bias overlay design.

## Decisions required from you

1. Undefined source cases (Part 4): replicate Excel's implicit
   blank-rating-as-zero behavior, or keep the stricter
   `.calibrationRequired` guard? No floor/ceiling on sets exists in the
   source — leave unbounded (faithful) or add a TrainingOS floor
   (a deviation, would need explicit labeling)?
2. Provenance (Part 8): is re-run-on-demand explanation sufficient for
   now, or do you want a small additive `appliedStrengthReasonCode`
   field added as part of Slice 1B?
3. `generatorVersion` bump (Part 9): confirm doing this once, as part of
   Slice 1B, covering both Slice 1A's and 1B's cumulative changes.
4. Confirm the Part 2 pairing table is what should be implemented
   verbatim (it is a direct, re-verified transcription — no
   interpretation was applied), and confirm proceeding to implementation
   once reviewed.
