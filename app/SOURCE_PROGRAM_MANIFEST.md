# Source Program Manifest

**Authority: the real, original `.xlsx` workbooks, read directly from disk this
pass** (`~/Downloads/RP Diet/RP Diet/...` and its byte-identical mirror at
`~/Documents/Private files/Träning/RP Diet/...` — every "Original templates"
file used as the fidelity authority below was hash-verified identical across
both locations). This supersedes `PROGRAM_LOGIC_SPEC.md`/`STAGE3_DECISION_MEMO.md`/
`V1_PROGRAM_LIBRARY.md`/`PROGRAM_FAMILY_MATRIX.md` as the primary source of
truth wherever they conflict — those documents remain valuable secondary
analysis and are noted as CONFIRMED or CORRECTED against the real cells
throughout this manifest, never silently trusted over direct extraction.

This is the permanent map: **source program → TrainingOS representation →
current implementation status.** Update this file (don't replace it) as
recovery slices land.

---

## 1. Full workbook inventory

| # | Real filename | Family | SHA-256 (Downloads = Documents, verified identical) | Days/wk | TrainingOS built-in config | Current fidelity |
|---|---|---|---|---|---|---|
| 1 | `3 day full body_Novice.xlsx` | A | `9168c6e9...` | 3 | "3-Day Full Body Hypertrophy" | **NEITHER content nor progression faithful** — see §3 |
| 2 | `4 day full body.xlsx` | A | `e50c491d...` | 4 | "4-Day Full Body Hypertrophy" | Progression faithful; content placeholder (2 of 26 real slots) |
| 3 | `5 day full body.xlsx` | A | `e550fabd...` | 5 | "5-Day Full Body Hypertrophy" | Progression faithful; content placeholder (2 of 28 real slots) |
| 4 | `6 day full body.xlsx` | A | `1a5cf98a...` | 6 | "6-Day High-Frequency Hypertrophy" | Progression faithful; content placeholder (2 of 30 real slots) |
| 5 | `4 day legs.xlsx` | A | `a742fe85...` | 4 | "4-Day Lower/Leg Focus" | Progression faithful **except the Heavy-day override is unreachable**; content placeholder (2 of 24 real slots) |
| 6 | `5 day arms & shoulders.xlsx` | A | `105136b2...` | 5 | "5-Day Upper/Arms Focus" | Progression faithful; content placeholder (2 of 29 real slots); real file uses dual-tag category "Rear or Side Delts" |
| 7 | `6 day back & chest.xlsx` | A | `9aa99a25...` | 6 | *not shipped* (kept as generator parameter space per `V1_PROGRAM_LIBRARY.md` §4) | N/A |
| 8 | `3 day arms & delts_Novice.xlsx` | A (Novice) | `8e42fe65...` | 3 | *not shipped* | N/A |
| 9 | `5 day full body_Novice.xlsx` | A (Novice) | `73d6fdb7...` | 5 | *not shipped* (corroborating evidence only) | N/A |
| 10 | `6 day arms & shoulders_novice.xlsx` | A (Novice) | `cb4caa0e...` | 6 | *not shipped* | N/A |
| 11 | `6 day chest & back_novice.xlsx` | A (Novice) | `e1a5adca...` | 6 | *not shipped* | N/A |
| 12 | `RP-PowerliftingStr-4-Day.xlsx` | B | `bfa453e5...` | 4 | "4-Day Powerlifting Strength" | Progression faithful; content placeholder (4 of 15 real rows — **Shoulder category confirmed present in source, absent from generated output**) |
| 13 | `RP-PowerliftingHyp-5-Day.xlsx` | C | `7dc0840d...` | 5 | "5-Day Powerlifting Hypertrophy" | Progression faithful; content placeholder (6 of 16 real rows — **Hamstring category confirmed present in source, absent from generated output**) |
| 14 | `Strength_Program_1.xlsx` | D (derivative of B) | `ee02ef29...` | 4 (restructured) | *not shipped, evidence only* | N/A — confirmed blank template, never populated |
| 15 | `Strength_Program_2.xlsx` | D (derivative of C) | `5fdba791...` | 4 (Wed removed, restructured) | *not shipped, evidence only* | N/A — confirmed blank template, never populated |

**Out of scope, confirmed not training-program content** (present in the same
personal folders, correctly excluded per instruction): `RP Diet Meal Macro
Counter Template.xlsx`, `F_2_RP_.xlsx`, `N_F_3 (1).xlsx`, `rp strength detail
spreadsheet.xlsx` (and its "konfliktkopia" duplicate) — diet/macro-tracking
tools, not inspected further.

**Loose duplicate/conflict copies found alongside the two clean folders**
(`Male physique template/5 day arms, shoulders*.xlsx` variants directly under
`Male physique template/`, `Documents/.../4 day full body_aktuell.xlsx`, `5
day arms, shoulders (aktuell).xlsx`) — these are the user's own working-copy
conflicts/"current" edits, not part of the canonical Original-templates/
Finished-programs pair. Not used as authority; flagged here only so they are
not mistaken for a 16th distinct workbook later.

## 2. Original templates vs. Finished programs

Every "Finished programs" file that has an "Original templates" counterpart
is **byte-different but structurally identical** — same day labels, same
category sequence/order, same Week-1 sets, same load/rep/deload formulas.
The only difference is real, personally-entered 10RM values in column G (and,
in some files, real exercise picks in column C). Directly diffed for
`3 day full body_Novice.xlsx`: zero structural or formula differences found.
**No discrepancy to report** — Original templates and Finished programs
never disagree on program design in any file checked; only on which numbers
a real user typed in. Per instruction, Finished-programs values were used
only to observe formula behavior with real inputs, never as program-design
authority.

## 3. The 3-Day Full Body workbook — full recovered structure

**File:** `3 day full body_Novice.xlsx` (config #1, "3-Day Full Body
Hypertrophy"). Rounding unit: **5** throughout all three mesocycles (not
2.5 — rounding unit is confirmed file-specific, not day-count-derived: the
two 4-day files use 2.5, the 5-day/6-day/this-3-day file use 5).

### Mesocycle 1 — Basic Hypertrophy (weeks 1-4 + deload), factor 0.85

| Day | Emphasis | Categories in order (Week-1 sets) |
|---|---|---|
| 1 | Push Emphasis | Horizontal Push(3), Chest Isolation or Triceps(3), Incline Push or Front Delts(3), Side Delts(3), Vertical Pull(3), Horizontal Pull(3), Hamstrings Isolation(2), Quads(2) |
| 2 | Legs Emphasis | Quads(3), Quads(3), Hamstrings Hip Hinge(3), Side Delts(3), Vertical Pull(3), Horizontal Pull(3), Incline Push or Front Delts(2), Horizontal Push(2) |
| 3 | Pull Emphasis | Vertical Pull(3), Horizontal Pull(3), Rear Delts or Side Delts(3), Biceps(3), Horizontal Push(3), Incline Push(3), Glutes(2), Hamstrings Isolation(2) |

24 slots/week. Rep goal identical for every slot, every week: `3/fail,
3/fail, 2/fail, 1/fail` (no compound/isolation distinction at all — this is
universal across every Family A file audited, not specific to this one).
Weekly load: `week1 = MROUND(10RM×0.85, 5)`, `week2 = MROUND(week1×1.05, 5)`,
`week3 = MROUND(week1×1.075, 5)`, `week4 = MROUND(week1×1.1, 5)`. Set
autoregulation: Week-1 baseline fixed (3 for most categories, 2 for
Hamstrings Isolation/Quads/Glutes on their lower-priority days); from Week 2,
`sets = priorWeek.sets(sameSlot) + rating(pairedSlot)`. **Deload:** fixed 2
sets, `1/2 reps of Week 1` (floored), full weight for Days 1-2 (`ceil(3/2)=2`),
half weight for Day 3.

**The autoregulation pairing web is NOT "same exercise, next week" — it is
the most recently trained occurrence of a related category in true
chronological training order**, which can be same-week-earlier-day or
previous-week-later-day, and can be a same-named or a related-but-different
category. Recovered in full, cell-cited:

| Day 1 slot | Rating source | Day 2 slot | Rating source | Day 3 slot | Rating source |
|---|---|---|---|---|---|
| Horizontal Push | Day2 Horizontal Push (last slot) | Quads #1 | Day1 Quads | Vertical Pull | Day1 Vertical Pull |
| Chest Isolation or Triceps | Day2 Horizontal Push (same source as above) | Quads #2 | Day1 Quads (same source) | Horizontal Pull | Day1 Horizontal Pull |
| Incline Push or Front Delts | Day2 Incline Push or Front Delts | Hamstrings Hip Hinge | Day3 Hamstrings Isolation (prior week) | Rear Delts or Side Delts | Day1 Side Delts |
| Side Delts | Day2 Side Delts | Side Delts | Day3 Rear Delts or Side Delts (prior week) | Biceps | Day1 Vertical Pull |
| Vertical Pull | Day2 Vertical Pull | Vertical Pull | Day3 Vertical Pull (prior week) | Horizontal Push | Day1 Horizontal Push |
| Horizontal Pull | Day2 Horizontal Pull | Horizontal Pull | Day3 Horizontal Pull (prior week) | Incline Push | Day1 Horizontal Push (same source) |
| Hamstrings Isolation | Day2 Hamstrings Hip Hinge | Incline Push or Front Delts | Day3 Incline Push (prior week) | Glutes | Day2 Hamstrings Hip Hinge |
| Quads | Day2 Quads #1 | Horizontal Push | Day3 Horizontal Push (prior week) | Hamstrings Isolation | Day1 Hamstrings Isolation |

This chronological (not fixed-partner) pairing mechanism was **never
documented at this precision by the earlier Stage 3 analysis** — it described
the mechanism only generally ("usually the same exercise trained again later
that week").

### Mesocycle 2 — Metabolite Focus (weeks 1-4 + deload), factor 0.75 (0.6 superset partner)

27 slots/week (24 + 1 superset-partner row per day). **Superset mechanic,
recovered exactly:** each day has exactly one superset pair, marked in
column A ("Super set this exercise" / "with this one"). The partner row's
own **Sets** formula is slaved to the primary row's Sets cell (not its own),
carries an independent 0.6×10RM load, and has **no deload row at all**
(columns AF-AI blank) — confirming `STAGE3_DECISION_MEMO.md` A2 exactly.
Day 1's pair is cross-category (Chest Isolation or Triceps + Incline Push or
Front Delts partner); **Day 2 and Day 3's pairs are same-category-doubled**
(Side Delts + Side Delts partner; Biceps + Biceps partner) — a distinction
the recovered secondary docs never captured. Day 1 additionally has a
**second, independent** "Incline Push or Front Delts" slot (own sets, own
0.75 factor) distinct from the superset partner of the same name.

### Mesocycle 3 — Resensitization (week 1 + week 2 + deload, 3-week block), factor 1.0

22 slots/week (7+7+8) — no supersets. Confirmed `week1 = MROUND(10RM×1.0, 5)`
directly from the cells (`J11: '=MROUND(((G11)),5)'`) — full 10RM, matching
the documented "highest relative intensity of the three phases" finding
exactly.

## 4. Current TrainingOS vs. real source — 3-Day config

`HypertrophyProgramGenerator.generateDayFocusDriven` (the only path this
config uses) generates a TrainingOS-invented Day A/B/C rotation and, since
Stage 10B.6, a fully-replaced `.doubleProgression` progression system —
**neither the real 24-slot category sequence above nor the real `.rmBased`
progression formula is used for this configuration today.** This is the
most severe fidelity gap of any of the 15 workbooks.

## 5. Complete recovered exercise/category library (all 11 Hypertrophy workbooks)

**Confirmed: one single shared category/exercise database, byte-identical
across all 11 Family A workbooks** (verified via `extract_tables.py` on all
11 files — differences are only cell-range offsets and two display-label
spelling variants, never exercise/link content). 24 canonical categories,
each an Excel Table with an `[Exercise]`/`[Link]` column pair:

| Category (canonical Table name) | Exercise count | Representative exercises |
|---|---|---|
| Horizontal_Push | 7 | Medium/Wide/Close Grip Bench Press, Flat Dumbbell Bench Press, Flat Machine Bench Press, Pushup, Close Grip Pushup |
| Incline_Push | 6 | Incline Medium/Wide/Close Grip Bench Press, Low/High Incline Dumbbell Press, Incline Machine Bench Press |
| Front_Delts | 6 | Standing/Seated Barbell Shoulder Press, Seated Dumbbell Shoulder Press, High Incline Dumbbell Press, Shoulder Press Machine, Standing Dumbbell Shoulder Press |
| Incline_Push_or_Front_Delts (dual-tag) | 12 | Union of Incline_Push + Front_Delts |
| Chest_Isolation | 7 | Flat/Incline Dumbbell Flye, Cable Flye, High Cable Flye, Machine Chest Flye, Cable Incline Flye, Pec Dec Flye |
| Triceps | 13 | Skullcrusher, EZ/Barbell/Seated Overhead Tricep Extension, JM Press, Dips (+ Assisted), Cable Tricep/Rope Pushdown, Bar Skull |
| Chest_Isolation_or_Triceps (dual-tag) | 19 | Union of Chest_Isolation + Triceps |
| Horizontal_Triceps / Vertical_Triceps | 8 / 5 | Subsets of Triceps by pressing angle |
| Horizontal_Pull | 8 | Barbell Bent Over Row, Underhand EZ Bar Row, Row to Chest, 1-/2-Arm Dumbbell Row, Chest Supported Row, Row Machine, Cable Row |
| Vertical_Pull | 12 | Overhand/Parallel/Underhand/Wide-Grip Pullup (+ Assisted variants), Normal/Parallel/Underhand/Wide/Narrow Grip Pulldown |
| Side_Delts | 5 | Barbell/Dumbbell/Cable Upright Row, Dumbbell Side Lateral Raise, Thumbs Down Lateral Raise |
| Rear_Delts | 4 | Barbell/Dumbbell/Cable Facepull, Dumbbell Rear Lateral Raise |
| Rear_or_Side_Delts (dual-tag) | 9 | Union of Rear_Delts + Side_Delts |
| Traps | 4 | Barbell Shrug (+ Bent Over), Dumbbell Shrug (+ Bent Over) |
| Biceps | 11 | Barbell/EZ/Close Grip Barbell Curl, 2-Arm/Incline/Alternating Dumbbell Curl, Cable Curl, Dumbbell Twist/Spider Curl, Hammer Curl, Cable Rope Twist Curl |
| Quads | 7 | High Bar Squat, Close Stance/Machine Feet Forward Squat, Leg Press, Hack Squat, Front Squat (+ Alternate Grip) |
| Glutes | 8 | Barbell/Dumbbell Walking Lunge, Sumo Squat, Deficit/Sumo/Hex Bar Deadlift, "25's Deadlift", Deadlift |
| Hamstrings_Hip_Hinge | 4 | Stiff-Legged Deadlift, Low/High Bar Good Morning, 45 Degree Back Raise |
| Hamstrings_Isolation | 3 | Lying/Seated/Single-Leg Leg Curl |
| Calves | 4 | Calves on Calf Machine, Stair Calves, Calves on Leg Press, Smith Machine Calves |
| Abs | 7 | Machine Crunch, Slant Board/Reaching Sit-Up, V-Up, Modified Candlestick, Hanging Knee/Straight Leg Raise |

**No specialization split (arms&shoulders, back&chest) or Novice file
introduces a new category or exercise** — every one of the 11 files draws
from this exact same 24-category database; splits only change *which*
categories get weekly slots and how many, never the underlying exercise
pool.

**Two real naming inconsistencies confirmed directly in the source data
(not TrainingOS transcription errors)**, worth flagging for anyone building
an import pipeline later:
- Dual-tag display text varies: **"Rear or Side Delts"** (5-day arms&shoulders,
  5-day full body Novice) vs. **"Rear Delts or Side Delts"** (3-day full
  body, 3-day arms&delts Novice) — same category, different literal string.
- Category display-label pluralization varies **by file, not by Novice
  status**: both 6-day files (Novice and non-Novice) use singular ("Quad",
  "Glute", "Hamstring Hip Hinge"); every other day-count uses plural
  ("Quads", "Glutes", "Hamstrings Hip Hinge"). The underlying Excel Table
  object names stay canonical/plural in every file — safe to key off the
  Table name, never the display label.
- The Excel Table object itself is inconsistently cased in one place:
  `Incline_Push_or_front_Delts` (lowercase "front") vs. the display "Table
  name" cell `Incline_Push_or_Front_Delts` (capital F) — an authoring
  artifact inside the source workbooks themselves.

**Confirmed "Novice" is not a distinct ruleset**, directly re-verified this
pass (not merely re-citing the old finding): zero occurrences of
"novice"/"beginner" in any cell of any of the 4 Novice files checked, except
the filename; a direct cell-by-cell diff of `5 day full body_Novice.xlsx`
against its non-Novice sibling `5 day full body.xlsx` found **zero**
differences in day labels, category sequence, sets, load factor, rep goal,
or deload structure — the only difference is that the non-Novice copy has
real exercises pre-selected.

## 6. Family A per-workbook matrix (all 11, Mesocycle 1)

| Workbook | Days | Day names | Slots/wk | Factor/unit | Deload split | Notes |
|---|---|---|---|---|---|---|
| 3-day full body Novice | 3 | Push/Legs/Pull Emphasis | 24 | 0.85 / 5 | 2 full, 1 half | See §3 |
| 4-day full body | 4 | Upper/Lower/Upper/Lower (generic) | 26 | 0.85 / **2.5** | 2 full, 2 half | |
| 5-day full body | 5 | Chest Upper / Quads Legs / Back Upper / Glute-Ham Legs / Shoulders-Arms Upper | 28 | 0.85 / 5 | 3 full, 2 half | One data-entry defect found: `G32='?'` breaks that row's whole weight chain in the live file |
| 6-day full body | 6 | 6× "[Region] Focused [Upper/Lower]" | 30 | 0.85 / 5 | 3 full, 3 half | Only file with perfectly uniform 5 slots/day |
| 4-day legs | 4 | Heavy Quads / Heavy Glutes / High Rep Quads / High Rep Hams | 24 | 0.85, **1.0 on 3 specific slots** / 2.5 | 2 full, 2 half | See §7 — Heavy exception recovered precisely |
| 5-day arms & shoulders | 5 | Front/Side/Tri Upper, Legs+Chest, Rear/Side/Bi Upper, Legs+Back, Chest/Back+Shoulders/Arms | 29 | 0.85 / 5 | 3 full, 2 half | Uses "Rear or Side Delts" wording |
| 6-day back & chest | 6 | Alternating Chest/Back Focused Upper ×3 each | 31 | 0.85 / 5 | 3 full, 3 half | Singular category labels; dual-tag categories unused in this file |
| 3-day arms & delts Novice | 3 | Bicep Rear/Side Delt, Tricep/Front Delt, Arms | 24 | 0.85 / 5 | 2 full, 1 half | Uses "Rear Delts or Side Delts" wording (matches 3-day full body) |
| 5-day full body Novice | 5 | identical to 5-day full body | 28 | 0.85 / 5 | 3 full, 2 half | Confirmed byte-identical structure to non-Novice sibling (§5) |
| 6-day arms & shoulders Novice | 6 | Front/Side/Tri, Rear/Bi/Traps (repeated), Front/Tri | 32 | 0.85 / 5 | 3 full, 3 half | Singular labels, matches non-Novice 6-day pattern |
| 6-day chest & back Novice | 6 | near-exact twin of 6-day back & chest | 31 | 0.85 / 5 | 3 full, 3 half | Confirmed structurally identical to non-Novice sibling |

## 7. The "Heavy" exception — recovered precisely, corrected from prior documentation

Real mechanic, from `4 day legs.xlsx`: the 1.0× (vs. 0.85×) factor is **not**
a single "Heavy Quads/Glutes" category — it is a per-slot override applied
to specific rows on specific days:
- Day 1 "Heavy Quads": both **Quads** slots get 1.0×.
- Day 2 "Heavy Glutes": both **Glutes** slots get 1.0×, **and** the day's
  **Incline Push** slot also gets 1.0× (a compound-push slot, not named
  "glutes" at all).
- Day 3 "High Rep Quads" / Day 4 "High Rep Hams": **zero** slots get 1.0× —
  every slot stays at 0.85×.

There is **no separate "Heavy Quads"/"Heavy Glutes" category or exercise
table** in the source database — "Heavy Quads"/"Heavy Glutes" are day-label
text only; the underlying category rows are plain "Quads"/"Glutes"/"Incline
Push" from the shared 24-category database, just carrying a different
Week-1 load-factor formula on this specific day. **Current TrainingOS code's
single named `"Heavy Quads/Glutes"` slot exception is an approximation that
does not fully match this — it doesn't capture the third (Incline Push)
slot, and treats it as a distinct category rather than a per-slot factor
override on ordinary categories.**

## 8. Family B (RP-PowerliftingStr-4-Day) — recovered structure

10-category vocabulary confirmed (Legs×2/Push×2/Deadlift/Hamstring/Upper-Pull×2/
Shoulder×2, RM basis exactly as documented: Legs/Push/Deadlift=5RM,
Hamstring/Upper-Pull/Shoulder=8RM) — but the **real weekly row count is 15,
not 10**, because 6 of the 10 categories are trained twice/week on
different days:

| Day | Rows (category, protocol) |
|---|---|
| Monday | Deadlift, Legs1, Push1 (**Triples**, 0.7×), Hamstring |
| Tuesday | Legs2, Push2, UpperPull1, Shoulder1 |
| Thursday | Deadlift (**Triples**, 0.7×), UpperPull2, Shoulder2 |
| Friday | Push1, Legs2, UpperPull1, Shoulder1 |

Week-1 factor 0.95 (ordinary) / 0.7 (Triples), unit 2.5. Deload: Mon/Tue
0.7×/"2/3 reps of Week1", Thu/Fri 0.5×/"1/2 reps of Week1" — confirmed
verbatim. Week-4: Mon/Tue-side additive (`Q5='=L5+(P25)'`), Thu/Fri-side flat
copy (`Q25='=L25'`, the exact cell the secondary docs cited, re-confirmed
directly). **Both Shoulder slots are genuinely present in the source** —
the shipped app's 4-slot generation (Monday Bench/Tuesday Squat/Thursday
Deadlift/Friday Upper-Pull) omitting Shoulder entirely is confirmed as an
app-side content gap, not a source limitation. No named Excel Tables exist
in this workbook — category picklists are plain Data Validation ranges on
sheet `b`, already fully captured.

## 9. Family C (RP-PowerliftingHyp-5-Day) — recovered structure

Same 10-category vocabulary, single 10RM basis. **Real weekly row count is
16**, 6 categories trained twice:

| Day | Rows |
|---|---|
| Monday | Push1, Legs1, UpperPull1 |
| Tuesday | Legs1, Deadlift, Shoulder1 |
| Wednesday | Push2, UpperPull1, Shoulder1 |
| Thursday | Deadlift, Hamstring, Shoulder2 |
| Friday | Legs2, Push1 (**backoff**, 0.85×), UpperPull2, Shoulder2 |

Week-1 factor 0.95 (standard) / 0.85 (Friday backoff), unit 5. Deload:
Mon/Tue unchanged, Wed-Fri 0.5×. Week-4: Mon-Wed additive, Thu/Fri frozen
(flat copy) — confirmed the "asymmetry" (B) and "freeze" (C) are the exact
same underlying formula shape (a flat copy with no addition term) applied to
a different day grouping in each family, not two different mechanisms.
**Hamstring is genuinely present in the source** (Thursday) — the shipped
app's 6-slot generation entirely omitting it is confirmed an app-side gap.
A genuine authoring bug found in the live template itself: the Friday-backoff
footnote text says "1/2 Thursday's" reps, but the actual cell reads "1/2
Monday's" — the footnote and the formula disagree in RP's own stock file.

## 10. Family D — Strength_Program_1 / Strength_Program_2

Both confirmed **blank templates, never populated** with real RM values or
ratings (F/G columns empty on the data-entry sheet) — evidence of structural
customization only, not "real used programs." Real deltas found:

- **Strength_Program_1** (Family B derivative): removes both stock Triples
  rows (Monday Bench, Thursday Deadlift), relocates Triples onto Friday's
  Legs2 slot instead; adds a 4th Thursday row; changes deload rounding to
  nearest 5 (stock uses 2.5); the relocated Triples row's deload-rep text
  ("Same reps as Week 1") is Family-C phrasing, not Family B's own.
- **Strength_Program_2** (Family C derivative): removes Wednesday entirely,
  redistributes its categories onto the remaining 4 days; drops Hamstring
  entirely; changes weekly-week rounding to nearest 2.5 (stock uses 5); its
  Friday-backoff footnote is internally consistent (unlike stock Family C's
  bug, §9).

Confirms the "real user reconfigures the engine's parameters without
touching the load/rating formulas" evidence already used to justify one
shared `PowerliftingProgramGenerator` — re-verified directly, not merely
inherited from secondary docs.

## 11. Update discipline

Update this manifest (edit in place, don't replace) whenever a recovery
slice changes a configuration's fidelity status, whenever `ProgramProvenance`
is populated for a built-in, or whenever a new workbook is recovered. Keep
§1's table as the single at-a-glance status check for "is program X source-
faithful today."
