# Program Logic Spec

Stage 3A source analysis. Every rule below was traced to a specific cell in a
specific workbook — see each rule's **Source**. Nothing here was guessed;
anything the source material didn't settle is in `OPEN_PROGRAMMING_QUESTIONS.md`,
not resolved here. All 18 supplied files were inspected (15 workbooks + 3 PDFs).

Weights below are reproduced exactly as the source spreadsheets compute
them — unit-agnostic multipliers of a user-entered RM, per handoff rule 5.
Treat every number as "× the input RM," not as a literal kg/lb figure.

## Contents

1. [Source inventory](#1-source-inventory)
2. [Family A — RP General Hypertrophy (11 workbooks)](#2-family-a--rp-general-hypertrophy-11-workbooks)
3. [Family B — RP Powerlifting Strength](#3-family-b--rp-powerlifting-strength)
4. [Family C — RP Powerlifting Hypertrophy-block](#4-family-c--rp-powerlifting-hypertrophy-block)
5. [Family D — Strength_Program_1 / Strength_Program_2](#5-family-d--strength_program_1--strength_program_2)
6. [Cross-family observations](#6-cross-family-observations)

---

## 1. Source inventory

| File | Family | Sheets | Size |
|---|---|---|---|
| e1f8fb19-4_day_full_body.xlsx | A | Mesocycle 1/2/3 | 207KB |
| 1e3d5441-5_day_full_body.xlsx | A | Mesocycle 1/2/3 | 213KB |
| 1eb44a1e-6_day_full_body.xlsx | A | Mesocycle 1/2/3 | 221KB |
| bb847616-4_day_legs.xlsx | A | Mesocycle 1/2/3 | 205KB |
| f06502c6-5_day_arms__shoulders.xlsx | A | Mesocycle 1/2/3 | 211KB |
| f63aa557-6_day_back__chest.xlsx | A | Mesocycle 1/2/3 | 219KB |
| 4847f523-3_day_full_body_Novice.xlsx | A (novice) | Mesocycle 1/2/3 | 185KB |
| 5ebc6e53-3_day_arms__delts_Novice.xlsx | A (novice) | Mesocycle 1/2/3 | 197KB |
| 8ebd24ac-5_day_full_body_Novice.xlsx | A (novice) | Mesocycle 1/2/3 | 209KB |
| 2d17f31c-6_day_arms__shoulders_novice.xlsx | A (novice) | Mesocycle 1/2/3 | 227KB |
| bf7f7b32-6_day_chest__back_novice.xlsx | A (novice) | Mesocycle 1/2/3 | 218KB |
| f046f129-RPPowerliftingStr4Day.xlsx | B | a/b/c | 20KB |
| 6d06b9fd-RPPowerliftingHyp5Day.xlsx | C | a/b/c | 20KB |
| 7da7a0ae-Strength_Program_1.xlsx | D | a/b/c | 20KB |
| 201e3cbc-Strength_Program_2.xlsx | D | a/b/c | 21KB |
| 096469a3-...HowTo.pdf | Documents Family B | — | — |
| 2dfa4597-RPHypertrophyTrainingTemplateFAQ.pdf | Documents Family C (see §6.1) | — | — |
| 8db6ca3f-RPHypertrophyTrainingTemplateHowTo.pdf | Documents Family C (see §6.1) | — | — |

**Critical finding, stated up front:** the two "Hypertrophy" PDFs are
titled generically but their *content* is specifically about the RP
**Powerlifting** Hypertrophy-block template (Family C) — they describe a
10RM-basis, squat/push/pull/assistance-slot, 4-and-5-day-only product. **No
official RP documentation exists in the supplied material for Family A**
(the 11 general hypertrophy workbooks, which are 3–5× larger and
structurally different — three named phases "Basic Hypertrophy,"
"Metabolite Focus," "Resensitization," and no separate instructions/data-entry
sheet). Family A's rules below are reconstructed entirely from spreadsheet
formulas and cell labels, with correspondingly more items flagged ambiguous.
See `OPEN_PROGRAMMING_QUESTIONS.md` §1.

---

## 2. Family A — RP General Hypertrophy (11 workbooks)

**Goal:** general muscle hypertrophy. **Experience level:** see §2.5 — the
"Novice" designation does not correspond to a distinct ruleset in these
files. **Frequency:** 3, 4, 5 or 6 days/week (one file per count, plus
splits — §2.4). **Duration:** each workbook is one self-contained,
three-phase program; see §2.2 for whether the phases chain together.

### 2.1 Shared structure (all 11 files)

Every file has exactly three sheets, always named `Mesocycle 1 Basic
Hypertrophy`, `Mesocycle 2 Metabolite Focus`, `Mesocycle 3 Resensitization`.
**There is no cross-sheet formula in any of the 11 workbooks** — each
mesocycle is fully self-contained with its own copy of the exercise
catalog and a blank RM-entry cell. Confirmed by whole-workbook grep for
sheet-name references inside formula text: zero hits outside the sheet-name
headers themselves. (Agents A1, A2.)

**Exercise selection.** One exercise per slot, chosen from a
category-scoped dropdown (`INDIRECT(D{row})` sourcing a per-category named
table), not typed freely — an "Other ___ move of choice" option exists for
manual entry. Categories are muscle/movement labels (e.g. "Incline Push,"
"Quads," "Vertical Pull").

**RM basis.** A single 10-rep-max (10RM) per exercise, entered once per
mesocycle (never carried over between mesocycles — see §2.2).

**Rule ID: FAMILY_A_WEEK1_BASELINE**
- Mesocycle 1 ("Basic Hypertrophy"): `week1Weight = MROUND(tenRM × 0.85, roundingUnit)`
- Mesocycle 2 ("Metabolite Focus"): `week1Weight = MROUND(tenRM × 0.75, roundingUnit)` for the primary exercise in a superset pair; `× 0.6` for the superset partner
- Mesocycle 3 ("Resensitization"): `week1Weight = MROUND(tenRM × 1.0, roundingUnit)` — **full 10RM, no discount at all**, the *highest* relative intensity of the three phases
- `roundingUnit` = 2.5 or 5 depending on file (see §6.2)
- **Source:** e.g. `e1f8fb19` sheet 'Mesocycle 1' `J11: '=MROUND(((G11)*0.85),2.5)'`; sheet 'Mesocycle 2' `J11: '=MROUND(((G11)*0.75),5)'`, `J13: '=MROUND(((G13)*0.6),5)'`; sheet 'Mesocycle 3' `J11: '=MROUND(((G11)),5)'`

**Rule ID: FAMILY_A_WEEKLY_PROGRESSION** — weeks 2–4 are all fixed
percentages of the *Week-1* weight (not compounding week-over-week):
`week2 = MROUND(week1 × 1.05, unit)`, `week3 = MROUND(week1 × 1.075, unit)`,
`week4 = MROUND(week1 × 1.1, unit)`. Identical across every exercise, every
split, every day-count, every novice/standard pair. Mesocycle 3 only has
one progression step (`week2 = week1 × 1.05`) because it's a 3-week block.
**Source:** `P11/V11/AB11` formulas, confirmed across dozens of rows by
Agents A1, A2, A3, A4, A5.

**Rule ID: FAMILY_A_REP_GOAL_SCHEDULE** — fixed text per week, identical
for every exercise regardless of compound vs. isolation: Week1=`3/fail`,
Week2=`3/fail`, Week3=`2/fail`, Week4=`1/fail`, deload=`1/2 reps of Week 1`
(text instruction, not a computed number — the app must compute this
itself; see `OPEN_PROGRAMMING_QUESTIONS.md` §5, **resolved as
STAGE3_DECISION_MEMO.md A3: round down/floor**). "X/fail" is RP's own
notation, undefined within any of the 11 sheets, interpreted as "stop X
reps short of technical failure."

**Rule ID: FAMILY_A_SET_AUTOREGULATION** — the core adaptive mechanism.
Week 1 sets are a hardcoded per-exercise constant (2, 3 or 6, by exercise
archetype — compounds=3, isolation=2, calves=6). From Week 2 on:
`weekN.sets = weekN-1.sets(sameSlot) + rating(mostRecentlyCompletedPairedSlot)`,
rating ∈ {1, 0, -1} via a labelled dropdown ("wasn't very sore" = 1,
"noticeably sore, tough but manageable" = 0, "very sore" = -1). The paired
slot is usually the same exercise trained again later that week, but for
some accessory rows it's a *different* exercise sharing the same
musculature (e.g. "Chest Isolation or Triceps" is paired with "Horizontal
Push," not with itself). **Source:** e.g. `O11: '=I11+(M35)'`,
`U11: '=O11+(S35)'`, `AA11: '=U11+(Y35)'`, confirmed identically for all 26
slots in Mesocycle 1, and the same shape (different cell addresses) in
Mesocycles 2 and 3 and across every day-count/split/novice variant checked.
Deload week sets are a fixed constant (2), never autoregulated.

**Rule ID: FAMILY_A_DELOAD_WEIGHT_ASYMMETRY** — a genuine, confirmed
inconsistency present identically in every one of the 11 files: deload-week
weight equals the *full* Week-1 weight for roughly the first half of the
week's training days, and *half* the Week-1 weight for the remaining days.
The split boundary tracks `ceil(dayCount / 2)` (e.g. 4-day: Days 1–2 full,
3–4 half; 6-day: Days 1–3 full, 4–6 half). No comment or label in any file
explains this. **Source:** `AH11: '=J11'` (full) vs. `AH30:
'=MROUND((J30*0.5),2.5)'` (half), confirmed by Agents A1, A2, A4, A5.
**Resolved (`STAGE3_DECISION_MEMO.md` A4):** reproduced exactly as sourced
via `SourceCompatibleDeloadStrategy` for Family-A-derived
`ProgramDefinition`s; not promoted to a general TrainingOS deload rule.

### 2.2 Mesocycle sequencing — source fact unchanged, architecture resolved

"Mesocycle 1/2/3" strongly implies a sequence, but **no formula or
in-workbook text proves it**. Each mesocycle's 10RM input is blank and
independent; nothing carries load, exercise selection, or rating history
from one phase to the next. This is consistent with either (a) three
sequential blocks a user runs back-to-back, retesting or re-estimating
10RM at the start of each, or (b) three independent, optionally-standalone
templates. This factual finding is unchanged — no cross-sheet formula
exists in the source, full stop.

**Resolved at the architecture level (`STAGE3_DECISION_MEMO.md` A1):**
TrainingOS models the three phases as a sequential *product-level*
journey (Basic Hypertrophy → Metabolite Focus → Resensitization) despite
this absence of proof — that sequencing is an explicit TrainingOS product
interpretation of the phase naming/order, not a claim that the source
spreadsheets supply a cross-phase formula. See `PROGRAMMING_SYSTEM_MODEL.md`
§5.1 for the resulting model.

Phase differences (once inside a phase, everything else about the engine
is identical):

| | Basic Hypertrophy | Metabolite Focus | Resensitization |
|---|---|---|---|
| Duration | 5 weeks (4 + deload) | 5 weeks (4 + deload) | **3 weeks** (2 + deload) |
| Week-1 intensity | 85% of 10RM | 75% (60% superset partner) | **100% of 10RM** |
| Superset mechanic | No | **Yes** — 1 pair/day | No |
| Exercise slots/week | 26 (4-day example) | 30 | 23 |
| Rounding unit (4-day example) | 2.5 | 5 | 5 |

The "Resensitization" name plausibly suggests a lighter reset, but the
formulas show the *opposite* of light weight (100% of 10RM, the highest of
the three) paired with *lower* volume and a much shorter duration. **Do not
assume the standard meaning of "resensitization" here — the data supports
"short, low-volume, higher-intensity reset," not "light and easy."**
Flagged for product-owner confirmation in `OPEN_PROGRAMMING_QUESTIONS.md` §3.

The superset mechanic (Metabolite Focus only): one exercise pair per
training day, second ("partner") exercise's future sets are driven by the
*primary* exercise's rating, not its own, and the partner has no deload-week
row at all (blank in every occurrence — see `OPEN_PROGRAMMING_QUESTIONS.md`
§4). **Resolved (`STAGE3_DECISION_MEMO.md` A2):** the partner exercise is
omitted during deload week, represented as an explicit
`DeloadExerciseAction.omit` value on that specific prescription — a named,
Family-A/Mesocycle-2-scoped rule, not a generic "blank source cell means
omit" inference applied elsewhere. See `PROGRAMMING_SYSTEM_MODEL.md` §3.

### 2.3 Splits (which muscles, which exercises)

Four splits observed: full_body, legs, arms/shoulders (+ delts variant),
back/chest. Confirmed (Agent A5): split changes *only* which
exercises/categories populate the day-blocks — the progression engine
(load factors, autoregulation formula, deload rule, rep-goal schedule) is
identical across splits, with one exception:

**Rule ID: FAMILY_A_LEGS_HEAVY_EXCEPTION** — the `legs` split defines a
"Heavy Quads"/"Heavy Glutes" category (squat, deadlift, walking lunge) that
uses `× 1.0` (not `× 0.85`) as the Week-1 baseline factor. No other split
uses this exception, even on its own squat/deadlift-pattern rows (which
stay at `× 0.85`). **Source:** `bb847616` `J11: '=MROUND(((G11)*1),2.5)'`
(Heavy Quads) vs. `J13: '=MROUND(((G13)*0.85),2.5)'` (Hamstrings, same
file). Whether this is deliberate ("compounds always load closer to true
max regardless of split") or a copy/paste inconsistency limited to this one
file is unresolved — see `OPEN_PROGRAMMING_QUESTIONS.md` §6.

Baseline set counts per muscle are shared reference data reused across
splits (e.g. calves = 6 sets baseline everywhere) — this is exercise
catalog data, not split-specific engine logic.

### 2.4 Day-count (3/4/5/6)

Confirmed (Agent A4): "day count" is the literal number of `Day N:` blocks
in the sheet, matching the filename exactly. Increasing day-count does
**not** pile on more total volume — it redistributes similar total volume
across more, shorter sessions (verified on quads: exactly 9 sets/week in
the 4-, 5-, and 6-day full_body files, despite different exercises and
placement). Exercise-slot count per week rises only modestly (26→28→30 for
the full_body Mesocycle 1 series) while slots-per-day *falls* (6–7/day at
4 days → flat 5/day at 6 days).

The weekly microcycle is always pinned to 7 real-world days:
`restDays = 7 − dayCount`, placed the same way every time — zero rest days
between the week's own adjacent training blocks, remaining rest inserted
between later blocks, and always exactly one rest day before the next
week's Day 1.

### 2.5 "Novice" — confirmed NOT a distinct ruleset

**This is the most important negative finding in this analysis.** Agent A3
compared the one available Novice file (3-day, full_body) against two
standard files (4-day and 5-day, full_body) and found the core engine
byte-for-byte identical: same rep-range schedule, same RM basis, same
progression factors, same autoregulation formula and rating scale, same
deload formulas (once day-count is accounted for), same full exercise
catalog with no pruning. The words "novice"/"beginner" appear nowhere
inside any sheet — only in the filename. In one measure (sets/day), Novice
is actually *higher* than the standard files, arguing against a
volume-throttling design.

**Caveat, stated plainly:** the only Novice file compared shares a day-count
(3) with no standard counterpart, so a day-count confound can't be fully
ruled out for every difference (rest-day generosity, day-split naming). But
every mechanism that *can* be isolated from day-count shows no novice
effect. **Do not build a "gentler novice ruleset" into the engine based on
these files** — see `OPEN_PROGRAMMING_QUESTIONS.md` §7 for what would be
needed to settle this properly (a same-day-count novice/standard pair).

---

## 3. Family B — RP Powerlifting Strength

**File:** `f046f129-RPPowerliftingStr4Day.xlsx`. **Goal:** powerlifting
*strength* specifically (RP's own documentation is explicit that this is
not for bodybuilding, strongman, hypertrophy, or meet peaking — see the
HowTo PDF). **Experience level:** RP states this is not for lifters with
under 6 months of training. **Frequency:** 4 days/week (Mon/Tue/Thu/Fri).
**Duration:** 4-week accumulation block + 1-week deload.

**Exercise selection:** category slots (Legs ×2, Push ×2, Deadlift,
Hamstring, Upper-Pull ×2, Shoulder ×2), each a dropdown from a fixed list
on sheet b, plus an "Other" free-text option.

**Rule ID: FAMILY_B_RM_BASIS** — RM type is a **hardcoded label per
slot**, not derived from which exercise is chosen: Legs1/2, Push1/2 and
Deadlift use 5RM; Hamstring and both Upper-Pull and Shoulder slots use
8RM. **Source:** sheet b `H3:H7 = '5RM'`, `H8:H12 = '8RM'`.

**Rule ID: FAMILY_B_WEEK1_BASELINE** — `week1Weight = MROUND(RM × factor,
2.5)`. `factor = 0.95` for ordinary "2/fail" sessions; `factor = 0.7` only
for the two sessions explicitly labelled "Triples" (Monday Bench, Thursday
Deadlift) — the factor depends on the session's *protocol label*, not on
RM type. Every day computes independently straight from its RM cell in
sheet b — days never chain off each other's computed weight. **Source:**
`C5: '=MROUND((...!G7)*0.95),2.5)'` vs. `C7:
'=MROUND((...!G5)*0.7),2.5)'`.

**Rule ID: FAMILY_B_WEEKLY_PROGRESSION** — same shape as Family A:
`week2/3/4 = MROUND(week1 × 1.05/1.075/1.1, 2.5)`.

**Rule ID: FAMILY_B_REP_GOAL** — flat for weeks 1–3 (`2/fail`), a single
step down at week 4 (`1/fail`) — not a continuous ramp. "Triples" sessions
never change.

**Rule ID: FAMILY_B_AUTOREGULATION** — sets for the *next chronological
session of the same movement pattern* = that pattern's current sets +
the rating from the pattern's most recently completed prior session. This
genuinely crosses specific exercises within a pattern: Front Squat's sets
are driven by High Bar Squat's rating, not its own, confirming the linkage
is pattern-level. **Only the 8 "central" barbell-lift rows autoregulate at
all.** The 8RM accessory rows (GHR, pull-ups, rows, upright row, lateral
raise) use a fixed, never-autoregulated schedule (2,2,3,3, deload 2).
**Source:** `G6: '=B6+(F35)'` (Front Squat driven by High Bar Squat's row).

**A second, separate week-4 asymmetry (distinct from Family C's freeze,
below):** Monday/Tuesday rows' Week-4 sets *do* add the rating
(`=priorWeek.sets + rating`, same shape as weeks 2–3); Thursday/Friday
rows' Week-4 sets are a flat copy of Week-3 with **no** addition term at
all (e.g. `Q25: '=L25'`, not `=L25+someRating`). This has no visible
behavioral effect today only because deload week's sets are a hardcoded
constant regardless — but it is a real, sourced formula difference, not
noise, and an evaluator that always applies the addition term uniformly
would be wrong for this file's Thu/Fri rows specifically. Unresolved
whether this is deliberate or a copy-paste leftover — see
`OPEN_PROGRAMMING_QUESTIONS.md` §13.

**Rule ID: FAMILY_B_DELOAD** — two independent formulas, both split by
half-of-week, with **no shared logic between them**:
- Weight: `deloadWeight = MROUND(week1Weight × factor, 2.5)`, `factor =
  0.7` for Monday/Tuesday sessions, `0.5` for Thursday/Friday sessions.
- Reps: a literal instruction string, never computed — **"2/3 reps of
  Week 1" for Monday/Tuesday, "1/2 reps of Week 1" for Thursday/Friday.**
  This directly contradicts the RP HowTo PDF's claim of a uniform "2/3 of
  week 1" deload rule (the PDF's own worked example, 7/5/4→4/3/2, matches
  2/3 — but that's only true for the Monday/Tuesday half of the week in
  the actual spreadsheet). See `OPEN_PROGRAMMING_QUESTIONS.md` §8.
  **Resolved (`STAGE3_DECISION_MEMO.md` A4):** the spreadsheet, not the
  PDF, is authoritative — this exact 0.7/0.5 weight split and 2/3/1/2 rep
  split is reproduced verbatim by `SourceCompatibleDeloadStrategy` for
  Family B. This is a source-fidelity decision only; it is explicitly
  **not** promoted to a universal TrainingOS deload rule — see
  `PROGRAMMING_SYSTEM_MODEL.md` §6.1.

**Rule ID: FAMILY_B_BODYWEIGHT** — pure user instruction (sheet b: "add
your bodyweight to moves that involve it... when looking at the workout,
subtract your bodyweight"). No formula performs this arithmetic anywhere;
the app must implement it explicitly if it wants to automate it.

**Rounding:** `MROUND(x, 2.5)` everywhere, no exceptions.

---

## 4. Family C — RP Powerlifting Hypertrophy-block

**File:** `6d06b9fd-RPPowerliftingHyp5Day.xlsx`. **Goal:** muscle size
specifically to support a subsequent powerlifting strength block (RP's
three-block sequence: hypertrophy → strength → peaking). **Frequency:** 5
days/week (Mon–Fri). **Duration:** 4-week block + deload.

Shares the same sheet architecture, exercise-category structure, and
general formula shapes as Family B — same engineering lineage, different
tuning:

**Rule ID: FAMILY_C_RM_BASIS** — a single 10RM for every slot (no 5RM/8RM
split, unlike Family B).

**Rule ID: FAMILY_C_WEEK1_BASELINE** — `week1Weight = MROUND(10RM × 0.95,
5)` for standard slots; Friday's second exercise is a deliberate lighter
"backoff" of the *same* Monday exercise at `× 0.85`.

**Rule ID: FAMILY_C_WEEKLY_PROGRESSION** — `week2/3/4 =
MROUND(week1Cell × 1.05/1.075/1.1, 5)`, always off the already-rounded
Week-1 *cell*. The RP FAQ's claim that "week 1→2 jumps more than other
weeks" is numerically true but is a mechanical consequence of this fixed
multiplier set (+5.0pp of week1, then +2.5pp, +2.5pp) — not, as the FAQ
prose implies, a specially-designed "neural adaptation" mechanism.

**Rule ID: FAMILY_C_AUTOREGULATION** — more surgical than "muscle group"
(RP's own wording): each row is wired to exactly *one* other specific
row's rating cell (never an aggregate). Confirmed dead inputs: both
Upper-Body-Pull slots and both Shoulder slots have rating *columns* that
are never referenced by any formula — fixed schedule (2,2,3,3) regardless.
Hamstring's own rating is never used either; its autoregulation is a
verbatim copy of Deadlift's. **A confirmed, undocumented asymmetry:**
Monday/Tuesday/Wednesday autoregulated rows keep incrementing through
week 4; Thursday/Friday rows freeze after week 3 (week 4 repeats week 3
exactly).

**Rule ID: FAMILY_C_DELOAD** — weight: Monday/Tuesday = **unchanged**
(deload weight = Week-1 weight, no reduction at all); Wednesday/Thursday/Friday
= halved (`× 0.5`). This split is by weekday section, not by lift type
(Deadlift and Hamstring — both "main" posterior-chain work — fall on the
*halved* side), which argues against a simple "keep the big lifts heavy"
theory. Reps: literal "1/2 reps of Week 1" text for every row except
Friday's backoff exercise, which is the sole exception at "Same reps as
Week 1" (no reduction). **Resolved (`STAGE3_DECISION_MEMO.md` A4):**
reproduced exactly as sourced via `SourceCompatibleDeloadStrategy`, not
generalized to other families or to natively-generated programs.

**Rounding:** `MROUND(x, 5)` everywhere.

---

## 5. Family D — Strength_Program_1 / Strength_Program_2

**Files:** `7da7a0ae-Strength_Program_1.xlsx`, `201e3cbc-Strength_Program_2.xlsx`.

**Identity (moderate-high confidence):** these are **user-customized
derivatives built on the Family B/C spreadsheet engine**, not unbranded
copies and not an unrelated methodology. Evidence:

- Program_1 uses Family B's exact 5RM/8RM basis, dropdown lists, and
  rating-scale wording; Program_2 uses Family C's exact 10RM basis and
  dropdown lists.
- A shared typo ("Barbel Overhead Triceps Extension") present in *both*
  Family B and Family C is corrected to "Barbell" **only** in Program_1 —
  proof of independent hand-editing, not mechanical copying.
- Program_2's explanatory footnote was copied from Family C's and the day
  name inside it was manually updated to match Program_2's own (different)
  schedule — direct evidence of deliberate derivation.
- Neither file's readable text names RP or any author anywhere.

**What actually changed vs. the RP originals:**
- Program_1 converts Family B's two light "Triples @0.7" back-off sessions
  (Monday Bench, Thursday Deadlift) into full-heavy 0.95 sessions, and
  relocates the light/Triples treatment to Friday's squat instead. It also
  adds an extra Front Squat session Family B doesn't have.
- Program_2 keeps **Program_1's** 4-day (Mon/Tue/Thu/Fri) layout and exact
  exercise-slot mapping — it does *not* adopt Family C's native 5-day
  (Mon–Fri) layout. So Program_1 and Program_2 are two RM-basis variants
  of *one* custom 4-day program, not a 4-day/5-day pair analogous to the
  official RP templates.
- Each Program's **deload rule** follows its RM-basis sibling exactly
  (Program_1 → Family B's 0.7/0.5 weight split; Program_2 → Family C's
  unchanged/0.5 split) even though its *day layout* follows Program_1 —
  i.e. the deload rule travelled with the RM-basis engine, the schedule
  didn't.

**Product implication:** treat Family D as *evidence*, not a fifth
methodology — proof that this engine is meant to be end-user-reconfigurable
(day mapping, deload-day assignment, exercise-slot mapping can all change
independently of the load/rating formulas). This directly supports
building one configurable `PowerliftingProgrammingSystem` rather than one
hardcoded program per file — see `PROGRAMMING_SYSTEM_MODEL.md`.

---

## 6. Cross-family observations

### 6.1 Documentation mapping (corrected)

| PDF | Actually documents |
|---|---|
| `Renaissance_Powerlifting_Training_Template_HowTo.pdf` | Family B (RP Powerlifting Strength) |
| `RPHypertrophyTrainingTemplateHowTo.pdf` | Family C (RP Powerlifting Hypertrophy-block) — content says "RP Powerlifting Hypertrophy Template" explicitly, despite the generic filename |
| `RPHypertrophyTrainingTemplateFAQ.pdf` | Family C — FAQ Q21 ("these first products are only 4 and 5 day options") matches exactly Family B (4-day) + Family C (5-day) |
| *(none supplied)* | **Family A — the 11 general hypertrophy workbooks have no matching official documentation in this source set.** |

### 6.2 Rounding increment is not a reliable signal of anything

Across every family, `MROUND` increments of 2.5 and 5 appear inconsistently:
by mesocycle within the same Family-A workbook (Mesocycle 1 uses 2.5,
Mesocycle 2/3 use 5, in the 4-day file), by file within Family A (4-day
files mostly use 2.5, 5/6-day files use 5, but this doesn't hold for every
file), and consistently by family for B (always 2.5) vs. C (always 5).
**Do not treat this as a unit signal (lb vs. kg) or a deliberate day-count
rule** — no file states a unit anywhere, and the pattern isn't clean enough
to be load-bearing product logic. See `METRIC_LOAD_MODEL.md` for how
TrainingOS should handle rounding instead (via `EquipmentProfile`, not by
inheriting the source increment literally).

### 6.3 Deload is the least consistent mechanic across every family

Every single family — A, B, and C — has a confirmed, undocumented
asymmetry in its deload week (some days get a real weight reduction,
others don't; reps are always instructed as text rather than computed).
This is the single largest concentration of ambiguity in the whole source
set — consolidated in `OPEN_PROGRAMMING_QUESTIONS.md` §8. **Resolved
(`STAGE3_DECISION_MEMO.md` A4):** each family's asymmetry is reproduced
exactly as sourced, per family, via `SourceCompatibleDeloadStrategy` — the
product-owner ruling was to trust the spreadsheet in every case, but
explicitly *not* to treat any of these three shapes as TrainingOS's
general deload methodology for natively-generated programs (that is
`TrainingOSDeloadStrategy`, intentionally undefined until the Generator is
built). Rep-rounding for all three families is `STAGE3_DECISION_MEMO.md`
A3 (round down), documented at each family's rep-goal rule above.

### 6.4 The `-1/0/1` rating scale's wording differs by goal, not by chance

Family A: soreness/difficulty framing ("wasn't very sore" / "noticeably
sore" / "very sore"). Family B: bar-speed/RPE framing ("moved fast and
felt light" / "moved slowly and felt heavy"). Family C: difficulty framing
similar to A but phrased differently ("pretty easy, no challenge" / "tough
but manageable" / "very tough, barely got them"). The underlying mechanic
(feed a −1/0/+1 into a future set-count formula) is identical; only the
label text and which specific rows it's wired to differ. TrainingOS's
reason-code layer should keep the mechanic generic and let the *rating
prompt copy* vary per programming system.
