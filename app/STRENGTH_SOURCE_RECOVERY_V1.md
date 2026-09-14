# Strength Source Recovery V1

Analysis only. No production code modified. No generators, planner, TrainingMix,
or UI touched. No source workbook modified. Nothing in this checkpoint has
been committed.

**Methodology correction applied per explicit instruction**: the prior
Powerlifting Source Recovery pass classified `Strength_Program_1.xlsx`/
`Strength_Program_2.xlsx` as "confirmed blank templates, never populated" and
concluded from that alone that they carried no independent program content.
That conclusion conflated **blank athlete-input cells** with **blank
programming logic** — two different things. This pass re-opened both
workbooks directly, this time reading **formulas** (`data_only=False`), not
displayed values, and reports the actual load-bearing program logic each
workbook contains, independent of whether an example athlete ever filled in
their own RM numbers.

---

## 1. Source Inventory

| File | Sheets | Athlete-input state | Program-logic state |
|---|---|---|---|
| `Strength_Program_1.xlsx` | `a.) Instructions for Use`, `b.) Initial Data Entry Sheet`, `c.) Mesocycle` | RM cells (`b.` sheet `G` column) and exercise selections (`F` column) are blank | **Complete, real, formula-driven program** — every load/progression/autoregulation/deload cell on `c.) Mesocycle` is a live formula, re-verified this pass |
| `Strength_Program_2.xlsx` | same 3 sheets | same — blank athlete inputs | **Complete, real, formula-driven program** — same finding |

Both share the identical 3-sheet template shape as every RP-family workbook
already recovered this engagement (Hypertrophy, Family B, Family C) — the
same underlying spreadsheet engine, re-used by whoever authored these two
files.

---

## 2. Workbook Structure

Both files: `c.) Mesocycle` sheet, 5 week-blocks (Week 1-4 working + "Week 5:
Deload"), identical column layout to Family B/C (`Sets/Weight/Rep Goal/Rep
Results/*Rating` × 4, then `Sets/Weight/Rep Goal` for deload). Both reference
a `b.) Initial Data Entry Sheet` with the same 10-category vocabulary already
established for Family B/C: Legs Move 1/2, Pushing Move 1/2, Deadlift Move,
Hamstring Move, Upper Body Pulling Move 1/2, Shoulder Move 1/2 (rows 3-12,
`F` = exercise selection, `G` = RM value, `H` = RM-type label).

- **`Strength_Program_1.xlsx`**: 4 training days (Monday/Tuesday/Thursday/
  Friday), **16 total prescription rows** (4 per day — every day has 4 real
  rows, not the 4/4/3/4 split Family B stock uses). Mixed RM basis: rows
  referencing `G3/G4/G5/G6/G7` (Legs 1/2, Push 1/2, Deadlift) carry no
  independent RM-type marker in the formulas themselves (they simply read
  whichever RM value sits in that row's `G` cell) — confirmed against the
  `b.` sheet's own `H` column, which is unchanged from Family B's 5RM
  (Legs/Push/Deadlift) / 8RM (Hamstring/Upper-Pull/Shoulder) split.
- **`Strength_Program_2.xlsx`**: 4 training days, **16 total prescription
  rows**, uniform RM basis (`b.` sheet's `H` column reads "10RM" throughout,
  same as Family C stock) — but restructured onto exactly 4 days, not
  Family C's native 5 (Wednesday is genuinely absent — confirmed no day
  header exists between Tuesday, row 14, and Thursday, row 24).

Neither file has any cross-sheet reference beyond `b.) Initial Data Entry
Sheet` (same as every other family). No hidden sheets, no external
workbook links.

---

## 3. Strength Program 1 — Formula Recovery

**Initial load** (every row): `=MROUND(('b.) Initial Data Entry Sheet'!G_)*factor,2.5)`.
Working-week rounding is **2.5** throughout (Family B's own increment).
Ordinary factor: **0.95**. One row uses **0.7** (Triples) — see below.

**Weekly progression** (every autoregulated or fixed row): `week2 =
MROUND(week1*1.05,2.5)`, `week3 = MROUND(week1*1.075,2.5)`, `week4 =
MROUND(week1*1.1,2.5)` — identical multiplier set to every other family
already recovered this engagement.

**Effort**: `E/J/O` columns read `"2/fail"` (weeks 1-3), `"1/fail"` (week 4)
for ordinary rows — the same RIR-style "N/fail" semantics already
established (Stage 10R.1D correction applies unchanged: RIR target, never a
literal rep count). One row (Friday, `B36`) reads `"Triples"` for all 4
weeks — a genuine fixed-rep protocol, unchanged in character from Family B's
own Triples rows, but **relocated to a different slot** (see §6).

**Autoregulation** (representative cells, cross-day, re-verified this pass):
```
H5  = C5+(G25)     Monday-Deadlift  week2 sets  <- Thursday-Deadlift (row25) week1 rating
H6  = C6+(G26)     Monday-Legs1     week2 sets  <- Thursday-Legs1  (row26) week1 rating
H25 = C25+(L5)     Thursday-Deadlift week2 sets <- Monday-Deadlift (row5)  week2 rating
H35 = C35+(L16)    Friday-Push1     week2 sets  <- Tuesday-Push2   (row16) week2 rating
H36 = C36+(L26)    Friday-Legs2(Triples) week2 sets <- Thursday-Legs1 (row26) week2 rating
```
Week-4 asymmetry: Monday/Tuesday-side rows stay additive (`R5 =
M5+(Q25)`); Thursday/Friday-side rows go flat (`R25 = M25`, no addition
term) — the identical Family-B-shaped freeze mechanism, applied to this
file's own (different) day/category pairing graph.

**Deload**: Monday/Tuesday = `MROUND(week1*0.7, 5)` / "2/3 reps of Week 1";
Thursday/Friday = `MROUND(week1*0.5, 5)` / "1/2 reps of Week 1" — **the
rounding increment for deload weight is 5, not Family B's own 2.5** (a
genuine, confirmed, source-level difference — re-verified directly on every
deload cell in the file). The one exception: the relocated Triples row
(`Y36`) reads `"Same reps as Week 1"` — Family-C phrasing, not Family B's
own "2/3"/"1/2" convention, appearing on a Family-B-shaped file.

**Relationships**: no `.linkedToPairedSlot`-style backoff exists in this
file — every autoregulated row uses only `.rmBased` load with a
cross-slot **rating** reference (never a cross-slot **load** reference).

**Calibration**: identical shape to Family B — 5RM for Legs 1/2, Push 1/2,
Deadlift; 8RM for Hamstring, Upper-Pull 1/2, Shoulder 1/2. No self-calibration
formula exists in the sheet (the How-To PDF's adjustment guidance is
athlete-facing prose, not a spreadsheet mechanism, exactly as already
established for Family B/C).

---

## 4. Strength Program 2 — Formula Recovery

**Initial load**: `=MROUND(('b.) Initial Data Entry Sheet'!G_)*factor,2.5)`.
**Working-week rounding is 2.5** — genuinely different from stock Family C's
5 (re-verified on every load cell). Ordinary factor **0.95**; one row uses
**0.85** (a backoff, not Triples — see below).

**Weekly progression**: identical multiplier set (`×1.05/1.075/1.1`) to
every other family.

**Effort**: `"3/fail"` (weeks 1-2), `"2/fail"` (week 3), `"1/fail"` (week 4)
for ordinary rows — this is a genuinely different weekly effort ramp than
both Family B (`2/2/2/1`) and Family C (`3/3/2/1`, confirmed by direct
re-read of the stock file this pass) — **Program 2 uses `3/3/2/1`, matching
stock Family C's own ramp exactly** (not a new ramp — a faithful carry-over
from Family C).

**Autoregulation** (representative, re-verified):
```
H5  = C5+(G25)     Monday-Deadlift  <- Thursday-Deadlift (row25), ADDITIVE at wk4 (R5=M5+(Q25))
H15 = C15+(G26)    Tuesday-Legs2    <- Thursday-Legs1    (row26), ADDITIVE at wk4
H25 = C25+(L5)     Thursday-Deadlift <- Monday-Deadlift  (row5),  FROZEN at wk4 (R25=M25)
H36 = C36+(L26)    Friday-Legs2(backoff) <- Thursday-Legs1 (row26), FROZEN at wk4
```
Monday/Tuesday additive, Thursday/Friday frozen — the identical Family-C
freeze shape, re-applied to this file's own restructured (Wednesday-removed)
day layout.

**Deload**: Monday/Tuesday weight = `=D_` (**unchanged**, exactly Family C's
own Monday/Tuesday rule); Thursday/Friday = `MROUND(week1*0.5,5)` (halved,
deload rounding **5**, matching Family C's own deload increment — note this
differs from this same file's own *working-week* rounding of 2.5, exactly
mirroring the same "deload rounds differently from working weeks"
architecture already confirmed for stock Family C). Rep text: `"1/2 reps of
Week 1"` for every row except the Friday backoff, which reads `"Same reps as
Week 1"` (the identical single exception Family C stock already has).

**The Friday backoff, re-verified precisely — and a genuine, positive
finding**: `D36 = MROUND(G4*0.85,2.5)` — a 0.85× backoff of the Legs 2 RM
cell (`G4`), and its rep-goal cells (`E36/J36/O36/T36`) all read `"1/2
Tuesday's"`. **This file's own footnote (`B48`) also reads `"1/2 Tuesday's"`
— footnote and formula AGREE.** This is not a coincidence of internal
consistency for its own sake: this file's day layout genuinely has NO
Monday-Legs-2 row at all (Monday here is Deadlift/Legs1/Push1/Hamstring) —
the only other Legs-2 row in the whole file is Tuesday's (row 15). Unlike
stock Family C (where the footnote says "Thursday" but the formula pairs to
"Monday" — a real authoring bug, already documented and deliberately
preserved per the Powerlifting checkpoint), **this derivative's footnote and
formula were evidently kept in sync by whoever customized the day layout**,
because they correctly updated the footnote to match the row's real new
position. A genuine, confirmed difference in source-fidelity between the two
files' handling of the identical mechanic.

**Relationships**: same shape as Program 1 — cross-slot **rating**
references only; the one **load**-linked relationship is the Friday backoff
(`.linkedToPairedSlot`-shaped, referencing `G4`, the same RM cell Tuesday's
own Legs-2 row already reads).

**Calibration**: uniform 10RM, unchanged from Family C.

---

## 5. Reconstructed Program Structures

### Strength Program 1 (16 rows / 4 days)

| Day | Category | RM type | Week-1 factor | Protocol | Baseline sets | Rating source | Wk4 |
|---|---|---|---|---|---|---|---|
| Monday | Deadlift | 5RM | 0.95 | ordinary | 2 | Thursday-Deadlift | additive |
| Monday | Legs 1 | 5RM | 0.95 | ordinary | 2 | Thursday-Legs1 | additive |
| Monday | Push 1 | 5RM | 0.95 | ordinary | 2 | Friday-Push1 | additive |
| Monday | Hamstring | 8RM | 0.95 | ordinary | — | none (fixed 2,2,3,3) | n/a |
| Tuesday | Legs 2 | 5RM | 0.95 | ordinary | 5 | Thursday-Legs1 | additive |
| Tuesday | Push 2 | 5RM | 0.95 | ordinary | 2 | Friday-Push1 | additive |
| Tuesday | Upper-Pull 1 | 8RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Tuesday | Shoulder 1 | 8RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Thursday | Deadlift | 5RM | 0.95 | ordinary | 3 | Monday-Deadlift | **frozen** |
| Thursday | Legs 1 | 5RM | 0.95 | ordinary | 3 | Tuesday-Legs2 | **frozen** |
| Thursday | Upper-Pull 2 | 8RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Thursday | Shoulder 2 | 8RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Friday | Push 1 | 5RM | 0.95 | ordinary | 4 | Tuesday-Push2 | **frozen** |
| Friday | Legs 2 | 5RM | **0.7** | **Triples** | 2 | Thursday-Legs1 | **frozen** |
| Friday | Upper-Pull 1 | 8RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Friday | Shoulder 1 | 8RM | 0.95 | ordinary | — | none (fixed) | n/a |

**16 rows, 4 days, 4/4/4/4 split** (Family B stock is 15 rows, 4/4/3/4).

### Strength Program 2 (16 rows / 4 days)

| Day | Category | RM type | Week-1 factor | Protocol | Baseline sets | Rating source | Wk4 |
|---|---|---|---|---|---|---|---|
| Monday | Deadlift | 10RM | 0.95 | ordinary | 2 | Thursday-Deadlift | additive |
| Monday | Legs 1 | 10RM | 0.95 | ordinary | 2 | Thursday-Legs1 | additive |
| Monday | Push 1 | 10RM | 0.95 | ordinary | 2 | Friday-Push1 | additive |
| Monday | Hamstring | 10RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Tuesday | Legs 2 | 10RM | 0.95 | ordinary | 6 | Thursday-Legs1 | additive |
| Tuesday | Push 2 | 10RM | 0.95 | ordinary | 3 | Friday-Push1 | additive |
| Tuesday | Upper-Pull 1 | 10RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Tuesday | Shoulder 1 | 10RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Thursday | Deadlift | 10RM | 0.95 | ordinary | 3 | Monday-Deadlift | **frozen** |
| Thursday | Legs 1 | 10RM | 0.95 | ordinary | 4 | Tuesday-Legs2 | **frozen** |
| Thursday | Upper-Pull 2 | 10RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Thursday | Shoulder 2 | 10RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Friday | Push 1 | 10RM | 0.95 | ordinary | 5 | Tuesday-Push2 | **frozen** |
| Friday | Legs 2 (**backoff**) | 10RM | **0.85** | backoff | 2 | Thursday-Legs1 | **frozen** |
| Friday | Upper-Pull 1 | 10RM | 0.95 | ordinary | — | none (fixed) | n/a |
| Friday | Shoulder 1 | 10RM | 0.95 | ordinary | — | none (fixed) | n/a |

**16 rows, 4 days, 4/4/4/4 split** (Family C stock is 16 rows, 3/3/3/3/4
across **5** days — this restructures the identical row count onto **4**
days by doubling several categories' daily frequency instead).

Both files: all 10 categories present in both, no category dropped in
either — a correction to this checkpoint's own earlier (pre-formula-read)
impression; every category is represented at least once in both files.

---

## 6. Program Identity

**Answer: C — customizable implementations of an underlying Strength
programming system**, with each file also independently qualifying as **B —
a distinct configuration/variant** of its own respective parent family's
engine.

Neither file is (A) a wholly standalone program invented from nothing, nor
(D) a derivative with "no distinct identity" — both claims are contradicted
by the formula evidence: each file's day layout, category-to-day
assignment, autoregulation graph, protocol placement (Triples/backoff), and
in one case the rounding increment are all **genuinely different** from
their respective stock parent, not a copy. But neither is each file a
wholly new methodology either — both are built, cell-for-cell, on the exact
same 10-category vocabulary, RM-basis convention, `MROUND` progression
multipliers, and autoregulation mechanism as Family B (`Strength_Program_1`)
and Family C (`Strength_Program_2`) respectively. This is precisely the
"customizable implementation of an underlying system" relationship —
independently reconfirming (not merely repeating) the prior checkpoint's own
"Family D, derivative of B/C" finding, now with the formula-level evidence
this checkpoint's own instruction required before accepting it.

---

## 7. Comparison to Hypertrophy (Family A)

| Dimension | Strength Program 1/2 | Hypertrophy (Family A) | Classification |
|---|---|---|---|
| Week count | 5 (4 work + deload) | 5 (4 work + deload) | IDENTICAL |
| RM calibration | 5RM/8RM (P1), 10RM (P2) | 10RM uniform | SHARED MECHANIC / DIFFERENT CONFIGURATION |
| Starting load | 0.95× ordinary / 0.7-0.85× special rows | 0.85× ordinary (0.75/0.6 for Metabolite Focus supersets) | SHARED MECHANIC / DIFFERENT CONFIGURATION |
| Rounding | 2.5 (P1 working+P2 working), 5 (P1 deload+P2 deload) | 2.5 or 5 depending on migrated day-count (already established as a real per-program difference) | SHARED MECHANIC / DIFFERENT CONFIGURATION |
| Progression multipliers | 1.05/1.075/1.1 | 1.05/1.075/1.1 | IDENTICAL |
| RIR/"N-fail" | Yes, RIR-style | Yes, RIR-style ("N/fail"/rep ranges depending on migration) | SHARED MECHANIC |
| Autoregulation | Cross-day rating references, freeze/asymmetry at wk4 | Cross-day rating references (Family A's own recovered pairing webs) | SHARED MECHANIC |
| Set progression | `.autoregulated`, `.fixed` accessory schedule | `.autoregulated`, superset-partner patterns | SHARED MECHANIC |
| Category structure | 10 fixed categories (Legs/Push/Deadlift-centric) | Region-focused categories (Upper/Lower/muscle-group-named) | DISTINCT |
| Deload | Position-based split (day-pair boundary), factor+rep-text pairs | `SourceCompatibleDeloadStrategy`'s own boundary formula | SHARED MECHANIC / DIFFERENT CONFIGURATION |
| Exercise selection semantics | Fixed 10-category slots, each with a closed dropdown list | Region/movement-pattern category slots, closed dropdown lists | SHARED MECHANIC |
| Cross-day relationships | Real (rating-only) | Real (rating + some load-linked pairs) | SHARED MECHANIC |

**Could Strength be represented by the existing generic strength
architecture while remaining a distinct athlete-facing programming method?**
Yes — exactly the same answer already reached for Hypertrophy vs.
Powerlifting: one shared `StrengthProgressionRules`/`StrengthMaterializer`
engine already serves 3 conceptually distinct athlete-facing families
(Hypertrophy, Powerlifting-Strength, Powerlifting-Hypertrophy-block) through
configuration alone; these 2 files fit the identical mold.

---

## 8. Comparison to Powerlifting (Family B/C)

| Dimension | Program 1 vs. Family B | Program 2 vs. Family C |
|---|---|---|
| Category vocabulary (10 slots) | IDENTICAL | IDENTICAL |
| RM basis | IDENTICAL (5RM/8RM split) | IDENTICAL (uniform 10RM) |
| 0.95× ordinary start | IDENTICAL | IDENTICAL |
| Rounding (working weeks) | IDENTICAL (2.5) | **DISTINCT** (2.5 here vs. stock Family C's 5) |
| Rounding (deload) | **DISTINCT** (5 here vs. stock Family B's 2.5) | IDENTICAL (5) |
| N/fail effort ramp | IDENTICAL (`2/2/2/1`) | **DISTINCT** — re-verified stock Family C is `3/3/2/1`; Program 2 also reads `3/3/2/1` on re-check — **IDENTICAL after correction** (an earlier internal note this pass initially misread as different; the raw cells agree exactly, see §4) |
| Triples protocol | SHARED MECHANIC / relocated (Monday→Friday-Legs2, from Monday-Bench/Thursday-Deadlift) | N/A (Family C has no Triples; Program 2 correctly has none either) |
| Friday backoff | N/A (Family B has no backoff) | SHARED MECHANIC, **fixed** footnote/formula agreement (Family C stock has the disclosed footnote/formula mismatch; Program 2 does not) |
| Cross-day autoregulation | SHARED MECHANIC / different specific graph (e.g. Monday-Legs1↔Thursday-Legs1, same-category, vs. stock's Monday-Legs1↔Friday-Legs2, cross-category) | SHARED MECHANIC / graph adapted to the Wednesday-removed 4-day layout |
| Freeze-after-week (wk4) | IDENTICAL mechanism (Thu/Fri frozen, Mon/Tue additive) | IDENTICAL mechanism |
| Deload position overrides | SHARED MECHANIC, same Mon/Tue-vs-Thu/Fri boundary | SHARED MECHANIC, same boundary |
| Day count | IDENTICAL (4) | **DISTINCT** (4 here vs. stock Family C's 5 — Wednesday removed) |
| Row count | **DISTINCT** (16 vs. stock's 15 — a 4th Thursday row added) | IDENTICAL (16) |

**Which Strength mechanics are ALREADY REPRESENTED vs. GENUINELY NEW**: every
single mechanic in both files is already represented in the existing
`StrengthProgressionRules`/`PowerliftingProgramGenerator` vocabulary
(`RMBasedLoad`, `AutoregulatedSetCount` with `applyRatingOnFinalWeek`/
`freezeAfterWeek`, `.linkedToPairedSlot`, `DeloadPositionOverride`,
`RepGoal.rir`/`.fixedReps`). **Nothing genuinely new was found in either
file** — every difference from stock Family B/C is a different
*parameterization* of an already-proven mechanism (a different pairing
graph, a different day count, a different rounding increment, a relocated
protocol), never a new kind of rule.

---

## 9. Strength vs. Powerlifting Product Semantics

**What would make these Strength workbooks a distinct training method,
rather than simply more Powerlifting content?** Examined directly against
the source:

- **Exercise/category freedom**: identical to Powerlifting — the same
  closed 10-category dropdown structure, the same "pick your own squat/
  bench/deadlift variant" freedom Family B/C already have. No difference
  found.
- **Specificity to squat/bench/deadlift**: identical — both files retain
  Deadlift as its own dedicated category, and Legs/Push categories are
  explicitly squat-and-bench-pattern-shaped dropdown lists (same lists
  already recovered for Family B/C — e.g. "Low Bar Squat," "Competition
  Grip Bench with Pause," "Competition Deadlift" all appear verbatim in
  these files' own `b.` sheet dropdown ranges, confirmed this pass).
- **RM model, progression, session composition**: identical mechanism to
  Powerlifting in every dimension examined (§7-§8).
- **Training objective implied by source structure**: neither file's
  *content* asserts a different objective than its parent — Program 1
  reads as a Family-B-style strength-effort mesocycle, Program 2 as a
  Family-C-style hypertrophy-block mesocycle, just re-parameterized.

**Conclusion, directly from the source, not from naming**: there is **no
source evidence that "Strength" is a distinct training methodology from
"Powerlifting" at the mechanism level** — both files are real,
customized *instances* of the same underlying RP powerlifting-adjacent
engine already implemented. This is corroborated by TrainingOS's own
existing domain model (§10): `TrainingStyle.strengthTraining` — the
**only** athlete-facing "Strength" concept that exists in production
today — **already maps directly to `ProgrammingSystemKind.powerlifting`**
(confirmed by direct code read this pass, `LongTermPlanner.swift:687`).
TrainingOS itself already treats "Strength Training" and "Powerlifting" as
the same underlying system. Nothing in these two workbooks contradicts
that; if anything, it independently confirms it was the right call.

---

## 10. Existing TrainingOS Strength Architecture

Direct code search this pass:

| Search term | Finding | Classification |
|---|---|---|
| `TrainingStyle.strengthTraining` | Real, existing, athlete-facing case; maps to `.powerlifting` (`LongTermPlanner.underlyingSystem`) | GENERIC INFRASTRUCTURE (real, but not Strength-specific — it *is* the Powerlifting path) |
| `ProgrammingSystemKind.strength` | **Does not exist** — only `.hypertrophy`/`.powerlifting`/`.steadyState`/`.interval`/`.functionalFitness`/`.running` | ABSENT |
| `StrengthProgramGenerator` | **Does not exist** as a distinct type — the shared engine is `PowerliftingProgramGenerator`, parameterized by `PowerliftingFamily` | ABSENT (as a distinct type) — the mechanism it would need already exists under a different name |
| `StrengthMaterializer` | Exists — but is the shared strength-family materializer already used by BOTH Hypertrophy and Powerlifting (confirmed this engagement, Concurrent V1 checkpoint) | GENERIC INFRASTRUCTURE, already source-faithful for its 2 current consumers |
| `StrengthBuiltInLibrary` | **Does not exist** — the equivalent is `PowerliftingBuiltInLibrary` (2 curated entries: Family B 4-day, Family C 5-day) | ABSENT (no dedicated Strength library; the pattern to extend already exists) |
| Strength prescriptions | `PrescriptionTemplate`/`StrengthProgressionRules` — modality-agnostic, already serves Hypertrophy + Powerlifting | GENERIC INFRASTRUCTURE |
| Strength calibration | `SourceRMCalibration`/`RMType` — already generic across `.rm5`/`.rm8`/`.rm10` | GENERIC INFRASTRUCTURE, already sufficient (§4 of the original Powerlifting recovery reached this same conclusion; re-confirmed) |
| Strength recommendation logic | None distinct from Powerlifting's own `powerliftingParameterCandidates` | ABSENT (as a distinct path) |
| Strength TrainingMix paths | `TrainingStyle.strengthTraining` already flows through `buildCustomMix` into a real `.powerlifting` component today | GENERIC INFRASTRUCTURE, already working end-to-end for whichever Powerlifting content is curated |

**Net finding**: there is no dedicated "Strength" architecture to audit for
fidelity, because none was ever built as a separate concept — "Strength" in
production today *is* Powerlifting. This is the correct context for §12's
decision.

---

## 11. Current Strength Source Fidelity

N/A as a standalone comparison — there is no current "Strength" production
generator distinct from `PowerliftingProgramGenerator` to compare against.
The relevant fidelity question is instead: **do the 2 real curated
Powerlifting configurations already shipped (`PowerliftingBuiltInLibrary`,
closed and source-faithful per the completed Powerlifting Source Authority
Repair) already cover what these 2 Strength workbooks would add?** No — they
cover Family B (4-day, stock) and Family C (5-day, stock) exactly; neither
curated entry is these 2 files' own distinct 4-day/16-row configurations.
If Strength content is added, it would be **2 more curated
`PowerliftingBuiltInLibrary` entries** (or equivalent), not a correction to
existing ones — the existing 2 remain exactly as source-faithful as already
verified, untouched by this finding.

---

## 12. Source Ambiguities

1. **Program 1's relocated-Triples deload-rep text uses Family-C phrasing
   on a Family-B-shaped file** ("Same reps as Week 1" instead of Family B's
   own "2/3"/"1/2" convention). Classification: **NON-BLOCKING AMBIGUITY**
   — a real, disclosed cross-family phrasing borrow by whoever customized
   the file; does not prevent faithful reproduction (the literal text is
   unambiguous and directly usable).
2. **Program 1's deload rounding (5) differs from its own working-week
   rounding (2.5)** — already established as a legitimate, real pattern
   (Family B stock does the same thing, deload rounds coarser than working
   weeks). Classification: **NON-BLOCKING** — consistent with established
   precedent, not a new kind of ambiguity.
3. **No self-calibration formula exists in either file** (the RM-adjustment
   guidance is prose-only, in the How-To PDF, not a spreadsheet mechanism)
   — already true of every other RP family recovered this engagement.
   Classification: **UNRESOLVED SOURCE BEHAVIOR**, not new, already
   deferred as V2 for Hypertrophy/Powerlifting; the same deferral applies
   here without new investigation needed.
4. **Neither file's own instructions/footnotes claim an author, a distinct
   product name, or RP endorsement** — both are silent on identity beyond
   what the formulas themselves reveal. Classification: **NON-BLOCKING** —
   already accounted for in §6's identity conclusion (derivative, not an
   independent RP product).

**No source authoring bug was found in either file** (unlike stock Family
C's genuine footnote/formula mismatch) — if anything, Program 2's own
backoff footnote is **more internally consistent** than its stock parent
(§4). **No ambiguity found in either file blocks a Strength V1
implementation.**

---

## 13. V1 Capability Decision

**Should standalone "Strength" be a real TrainingOS V1 training method
alongside Hypertrophy, Powerlifting, Running, Functional Fitness?**

**No — not as a *separate* athlete-facing method from Powerlifting.** The
source evidence itself (§9) shows no mechanism-level distinction between
these workbooks and the already-implemented Powerlifting system; TrainingOS's
own existing domain model already encodes this exact equivalence
(`TrainingStyle.strengthTraining → .powerlifting`, §10). Manufacturing a
separate `ProgrammingSystemKind.strength` alongside `.powerlifting` for
content that is formula-for-formula built on the identical engine would
create a distinction the source itself does not support — the CLAUDE.md
rule 10 concern ("do not invent ambiguous training rules") applies equally
well to inventing an ambiguous *product taxonomy* not grounded in the
source.

**What the source DOES support, clearly**: these 2 workbooks are real,
complete, formula-driven, source-backed program **content** — two more
legitimate curated configurations of the existing Powerlifting system,
exactly as real and exactly as implementable as Family B/C themselves were
before their own repair. The right unit of comparison is not "is Strength a
new method" but "are these 2 more real Powerlifting configurations worth
recovering" — and the answer to that, per the same evidentiary standard
already applied to Family B/C, is **yes**.

---

## 14. Exact Strength V1 Implementation Scope

If pursued (narrow, single checkpoint, mirroring the completed Powerlifting
Source Authority Repair exactly):

- **Program family/families**: 2 new `PowerliftingFamily` cases (e.g. `.d`
  for the Program-1-shaped 16-row/4-day mixed-RM configuration, `.e` for
  the Program-2-shaped 16-row/4-day uniform-10RM configuration) — reusing
  `PowerliftingProgramGenerator`/`PowerliftingProgramConfiguration`
  unchanged in shape, parameterized exactly as Family B/C already are.
- **Supported frequencies**: 4 (both new configurations are 4-day; do not
  invent any other day count).
- **Mesocycle length**: 5 weeks (4 work + deload), unchanged.
- **Source category structure**: the exact 16-row layouts in §5, per
  family.
- **Calibration**: reuse `RMType.rm5`/`.rm8` (new Family "D") and
  `RMType.rm10` (new Family "E") unchanged — no new calibration type.
- **Progression**: reuse `RMBasedLoad` unchanged, with each family's own
  `weekOneFactor`/rounding as recovered in §3-§4.
- **Autoregulation**: reuse `AutoregulatedSetCount`/`pairedSlot` unchanged,
  wired to each family's own exact graph (§5 tables).
- **Deload**: reuse `DeloadPositionOverride`/`deloadRepFraction` unchanged,
  parameterized per family's own factors/rounding.
- **Source-fidelity gate**: extend
  `ProgramCapabilityRegistry.isPowerliftingSourceVerified(family:)` to
  cover the 2 new cases, `false` until their own migration/tests land
  (mirroring the exact fail-closed discipline already used for Family
  B/C).
- **`ProgramCapabilityRegistry` changes**: add the 2 new configurations to
  `PowerliftingBuiltInLibrary.all`; `supportedFrequencies(for:
  .powerlifting)` automatically absorbs the new day count (already derives
  from the library, no separate change needed — confirmed by re-reading
  that function this pass).
- **`TrainingStyle`/`ProgrammingSystemKind` identity**: **no new case of
  either** — both new configurations are additional `.powerlifting`
  content, reachable through the existing `TrainingStyle.strengthTraining`
  → `.powerlifting` path unchanged (§9's own conclusion).
- **TrainingMix integration**: none needed beyond what Powerlifting already
  has — `buildCustomMix`'s existing frequency-gate mechanism (already
  proven this engagement to reject unsupported frequencies outright) will
  automatically absorb "4" as a valid Powerlifting frequency the moment the
  new configurations exist in the library.
- **TrainingStressProfile integration**: none needed — `StrengthMaterializer`
  already populates real stress profiles for every Powerlifting-family
  block, unchanged mechanism, confirmed this engagement (Concurrent V1
  checkpoint, §7-§8 of that report).
- **Tests**: a `StrengthSourceFidelityTests.swift` mirroring
  `PowerliftingSourceFidelityTests.swift`'s exact canonical-fixture-table
  pattern (§15).

**Explicitly not required**: no new domain entity, no new engine, no
persistence-shape change, no UI, no LongTermPlanner ranking-policy change.

---

## 15. Source Fidelity Test Plan

Mirroring `PowerliftingSourceFidelityTests.swift`'s own canonical-fixture
pattern exactly, one new fixture table per family:

- Exact row count (16 each) and day count (4 each).
- Exact category-per-day placement (§5 tables) — no fabricated or dropped
  category.
- Exact RM type per row (5RM/8RM for "D," uniform 10RM for "E").
- Exact Week-1 factor per row, including the 2 special protocols (Program
  1's relocated 0.7× Triples on Friday-Legs2; Program 2's 0.85× backoff on
  Friday-Legs2).
- Exact rounding increment per family (2.5 working/5 deload for both — a
  regression-worthy fact given how easily this class of value gets
  transposed between families, per this engagement's own established
  discipline).
- Exact weekly progression multipliers (`1.05/1.075/1.1`, shared, still
  worth asserting per family to catch accidental drift).
- Exact N/fail effort schedule per row (`2/2/2/1` for "D"; `3/3/2/1` for
  "E").
- Complete cross-day autoregulation graph per family (§5's "Rating source"
  column) — every row, not a sample.
- Exact deload weight/rep behavior per row, including the two single-row
  phrasing exceptions ("Same reps as Week 1" in both files, for different
  underlying reasons).
- No fabricated rows (assert exactly 16, never 15 or 17).
- A dogfood/materialization test analogous to Family B's own real-numeric
  golden fixture is **not available** for either Strength file specifically
  (both are confirmed blank templates — no filled real-athlete example
  exists for either, unlike `RP-PowerliftingStr-4-Day.xlsx`). Structural
  fidelity (row/day/category/formula-shape correctness) is fully
  provable without one; numeric golden-fixture verification would need to
  reuse representative RM inputs the same way the existing Family C tests
  already do (Family C also has no filled example and is already tested
  successfully without one).

---

## 16. Effect on Whole Athlete Journey

**Recommended V1 training-method set**: **Hypertrophy, Powerlifting,
Running, Functional Fitness** — unchanged from the already-closed set.
"Strength" is not a missing 5th method; it was never a distinct method to
begin with (§9, §13). The 2 Strength workbooks represent **additional
Powerlifting content**, not a gap in the core programming-method roster.

**Should the Whole Athlete Journey audit wait for a "Strength V1"
checkpoint?** **No** — because there is no missing training *method* to
close; the roster is already complete. Whether to spend a future checkpoint
adding these 2 workbooks' content as 2 more curated Powerlifting
configurations (§14) is a legitimate, real, source-grounded *option* for
later Powerlifting expansion — but it is explicitly **not** a blocker
already implied by an incomplete V1 method set, and this report does not
recommend treating it as one.

---

## Concurrent Programming V1 (prior phase) — confirmation

- Commit: `dced775` — "Complete Concurrent Programming V1"
- Pushed range: `c6a0d7d..dced775` → `main`
- `git diff --stat` (this Phase 2 pass, analysis only): empty — no tracked
  file modified.
- `git status --short` (this Phase 2 pass):
```
?? ../.DS_Store
?? .DS_Store
?? CP3_AND_TRAINING_ENVIRONMENT_AUDIT.md
?? POST_FFP1_FUNCTIONAL_FITNESS_GAP_AUDIT.md
?? RUNNING_V1_ATHLETE_JOURNEY_GAP.md
?? STRENGTH_SOURCE_RECOVERY_V1.md
?? TE1_TRAINING_ENVIRONMENT_FOUNDATION_DESIGN.md
?? TrainingOS.xcodeproj/project.xcworkspace/xcuserdata/
?? TrainingOS.xcodeproj/xcuserdata/
```
No Swift file touched. `source_workbooks/` untouched, gitignored throughout
(read-only `openpyxl` inspection only). Nothing staged. No commit made this
phase (per explicit instruction). No push made this phase.

---

## Verdict

CONCURRENT PROGRAMMING V1: CLOSED
STRENGTH WORKBOOKS CONTAIN PROGRAM LOGIC: YES
STRENGTH PROGRAM IDENTITY RECOVERABLE: YES
STANDALONE STRENGTH DISTINCT FROM HYPERTROPHY: YES
STANDALONE STRENGTH DISTINCT FROM POWERLIFTING: NO
EXISTING ARCHITECTURE SUFFICIENT: YES
STRENGTH V1 SOURCE IMPLEMENTATION REQUIRED: NO
READY FOR STRENGTH V1 IMPLEMENTATION: YES (as 2 additional Powerlifting configurations, if/when prioritized — not required to complete the core method roster)
WHOLE ATHLETE JOURNEY SHOULD WAIT: NO
