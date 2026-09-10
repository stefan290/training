# RUNNING R1 — SOURCE RECOVERY & PROGRAMMING MODEL

**Scope of this checkpoint: ANALYSIS ONLY.** No Swift code, no Running Engine, no
TrainingOS data model changes were written or proposed as code in this checkpoint.
No commit was made. No file outside this single new markdown file was created or
modified.

**Authority model for this checkpoint (explicitly different from the Hypertrophy
repair):** for Hypertrophy, the original workbook was direct SOURCE AUTHORITY —
TrainingOS reproduced it. For Running, **RP documentation + the observed RP 5K
program together are REFERENCE PROGRAMMING AUTHORITY, not a static template.**
TrainingOS's eventual Running Engine must recover and generalize the *programming
model* that could plausibly have generated this one observed instance — it must
never simply replay this one plan. This distinction is stated explicitly by the
source material itself (`RP_5K_TrainingPeaks_Reference.xlsx`, `Handoff Notes`
sheet, row 3: *"Do not do: Do not reproduce this observed plan as the TrainingOS
Running Engine."*, row 4: *"Next analysis: Recover the programming model that
could generate the observed progression."*).

---

## 1. Executive Summary

RP's 5K running program, as reconstructed from RP's own documentation and one
captured TrainingPeaks instance, is a **13-relative-week (nominally 16-week, see
§2/§17 discrepancy) undulating-volume block-periodized plan** built from exactly
two weekly run slots (a "quality" run and a "steady/active" run), governed by a
single normalized intensity variable — **percent of threshold pace** — computed
by one linear formula, with a fixed non-linear pace→RPE handoff at the race itself.

Four load-bearing conclusions, each evidence-tagged:

- **[SOURCE FACT]** The percent-threshold-pace formula is
  `adjusted_pace_seconds = threshold_pace_seconds / percent_of_threshold`,
  confirmed by direct cell/formula inspection of
  `PercentThresholdPaceCalculator.xlsx` and independently cross-confirmed against
  `RP_5K_TrainingPeaks_Reference.xlsx`'s own prose restatement of the same rule.
- **[DERIVED FACT]** Every one of the 13 distinct paces appearing anywhere in the
  observed program's `Workout Blocks` sheet, when run back through that formula
  against the captured threshold (5:00/km = 300s), reproduces the sheet's own
  `Derived % Threshold` value exactly (0.60 through 1.099) — the workbook's
  self-reported derived values are internally consistent, not merely asserted.
  **[R1 CORRECTION]** originally miscounted as 14 in this report's first draft;
  independently re-counted directly against the workbook (both the `Intensity
  Map` sheet's own row count and a distinct-value count over `Workout Blocks`'
  `Source Pace min/km` column) — both give exactly 13. See §6 and the
  correction note below the table.
- **[DERIVED FACT]** The observed program shows a robust ~4-week reduced-volume
  cadence, corroborated by *two independent sheets* with different, non-aligned
  week-numbering schemes (`Workout Blocks`, relative weeks 4 & 8; `Calendar
  Overview`, calendar weeks 2/6/10/14) — the phase-offset between the two cannot
  be resolved from available evidence (§17), but the *periodicity* is doubly
  corroborated.
- **[PROGRAMMING INFERENCE]** The program manipulates **structural complexity**
  (interval count, repeat-group nesting) as a *second* progression axis, distinct
  from and layered on top of pace/%threshold — this only emerges from relative
  week 9 onward and is not present, even implicitly, in weeks 1-8.

The single largest open risk for R2: the observed dataset is **explicitly a
ChatGPT-mediated reconstruction from pasted/transcribed TrainingPeaks text, not a
raw system export** (Handoff Notes, row 2). Every "SOURCE FACT" label in this
report inherits that caveat and must be read as "faithfully transcribed by the
athlete/analyst," not "verified against TrainingPeaks' own database."

---

## 2. Sources Actually Inspected

Inventory was taken directly from `app/source_workbooks/` via `ls -la` — the
directive's own hints about file types (it suggested PDFs for the instructional
material) were **not** trusted and turned out to be wrong (the instructional
files are `.docx`, not `.pdf`). Full inventory: 25 files total. 15 are the
pre-existing Hypertrophy/Powerlifting workbooks from the prior Family A repair
(untouched, out of scope here) plus one `.DS_Store`. The 5 running-relevant files,
all directly opened and read in full:

| File | Type | Method | Result |
|---|---|---|---|
| `FAQ Endrance Running.docx` | docx | `textutil -convert txt` | 71 lines, read in full (verbatim, this checkpoint) |
| `How-To Int+5k Endurance Running.docx` | docx | `textutil -convert txt` | 21 lines, read in full (verbatim, this checkpoint) |
| `Program-Pairing Guide.docx` | docx | `textutil -convert txt` | 28 lines, read in full (verbatim, this checkpoint) |
| `PercentThresholdPaceCalculator.xlsx` | xlsx | `openpyxl`, direct cell/formula dump | 1 sheet, fully read |
| `RP_5K_TrainingPeaks_Reference.xlsx` | xlsx | `openpyxl`, direct cell/formula dump | 6 sheets, all fully read this checkpoint |

`python-docx` and `pdftotext` were both confirmed unavailable in this environment
before falling back to macOS's built-in `textutil`. This is a tooling note, not a
finding.

`RP_5K_TrainingPeaks_Reference.xlsx` sheets, all now fully read:
`Source & Inputs` (18 rows), `Calendar Overview` (16 rows), `Workout Blocks` (146
rows/145 workout blocks across 25 workouts), `Workout Index` (26 rows), `Intensity
Map` (14 rows), `Handoff Notes` (15 rows).

---

## 3. Missing Sources

Reported per the directive's requirement to flag, not silently absorb:

- **MISSING SOURCE: raw TrainingPeaks export/API data.** The reference workbook
  is an athlete-transcribed reconstruction (Handoff Notes row 2), not a system
  export. No calendar dates are attached to individual workouts by design
  (Handoff Notes row 10; Source & Inputs row 17).
- **MISSING SOURCE: historical threshold-pace values.** Only the current
  captured threshold (5:00/km) is known. TrainingPeaks' own history requires a
  Premium account, unavailable here (Source & Inputs row 16; Handoff Notes row 7).
  No inference about *how* threshold changed over the plan may be made.
- **MISSING SOURCE: RP's other Endurance Training Program tiers.** The FAQ
  repeatedly references "lower frequency Endurance Training Programs" (Pairing
  Guide line 14) and beginner/other-frequency plans (FAQ line 31) that are not
  present in `source_workbooks/` at all — only the 5K, apparently
  intermediate-or-higher frequency, tier is available (HowTo line 3: *"RP
  Endurance Training Programs Intermediate Level and Higher"*).
- **MISSING SOURCE: the remaining ~3 weeks of the nominal 16-week program.** See
  §17 — neither captured sheet reaches 16 weeks cleanly; which 3 weeks are
  missing, and from which end, is unresolved.
- **MISSING SOURCE: RP Endurance Sport Lifting Templates.** Referenced in the
  Pairing Guide (line 11) as "in production... Release will be 2019 at the
  earliest" — confirmed not to exist in this source set (expected; RP's own text
  says so).
- **MISSING SOURCE: any non-5K distance's RP program** (10K, half, marathon) —
  the FAQ discusses cross-using the 5K plan for other distances (lines 52-53) but
  no other distance's own plan is available to compare against.

---

## 4. Evidence Classification (used throughout)

- **SOURCE FACT** — literal text/value/structure found directly in an inspected
  file, cited by file + location.
- **DERIVED FACT** — not literally stated, but recoverable by direct, checkable
  computation from SOURCE FACTs (e.g., re-deriving %threshold from a pace and the
  known formula).
- **PROGRAMMING INFERENCE** — our interpretation of *why* the program is
  structured as observed; never asserted as something RP's text states unless a
  citation is given.
- **TRAININGOS PRODUCT DECISION** — a deliberate choice TrainingOS may make later
  when generalizing beyond what RP's material directly demonstrates. None are
  *made* in this checkpoint; candidates are flagged as such in §16-17.

---

## 5. Observed Program Reconstruction

**[SOURCE FACT]**, `Workout Index` sheet: the captured program is 25 workouts,
`W01`-`W25`. `W01`-`W24` pair up into 12 relative weeks, each with exactly two
slots: **Slot A** and **Slot B**. `W25` stands alone as **Relative Week 13**,
`Slot = "Race"`. Every row's own `Evidence` column reads *"SOURCE FACT (ordering);
character is organizational shorthand"* and every row's `Notes` column reads
*"Exact date intentionally unassigned."*

**[SOURCE FACT]**, `Workout Blocks` sheet, relative weeks 1-3 (W01-W06): Slot A
= 2 warm-up blocks + a "Tempo" block (constant Zone 5c pace) + an "Easy" block;
Slot B = 1 warm-up block + an "Active" block (constant Zone 4 pace) + a "Cool
Down" block. Distance is the only variable changing week to week in this window;
pace is held constant within each slot.

**[SOURCE FACT]**: a volume reduction is visible starting relative week 4
(W07-W08) and again at relative week 8 — both slots' distances drop versus the
immediately preceding week, then resume climbing above the prior peak the
following week.

**[SOURCE FACT]**, relative week 9 (W17) onward: workout *structure* changes,
not just distance/pace. Multi-stage warm-ups appear (up to 7 discrete warm-up
blocks in one workout, alternating zones — e.g. W23: Zone 3 → Zone 5c → Zone 3 →
Zone 5c → Zone 3 → Zone 5c → Zone 1), and an explicit **Repeat Group / Repeat
Count** mechanism appears in the sheet's own columns, pairing a "Hard" block with
a following "Easy" recovery block under a shared `Repeat Group` label (e.g. `R1`,
`R2`, `R3`) and a `Repeat Count`.

**[SOURCE FACT]** progression of that mechanism:
- Relative week 9 (W17): `Repeat Count = 4`.
- Relative week 10 (W19): `Repeat Count = 6`.
- Relative week 11 (W21, Slot A): the most structurally complex workout in the
  set — three distinct repeat groups in one session (a shorter/faster interval
  group, then a second, longer "Hard" rep at a slower-than-max but still Zone 5c
  pace, e.g. a single `2.00 mi` "Hard" block at 05:16/km, then a third group of
  `Repeat Count = 2`, 800m Hard/400m Easy pairs at 04:46/km).
- Relative week 11 (W22, Slot B): a single continuous "Active" block of `6.00
  mi` at Zone 4 (06:15/km) — the single largest continuous volume in the entire
  observed program, with no repeat structure at all.
- Relative week 12 (W23, Slot A): the multi-stage warm-up returns, but the
  interval work is now **single reps, not repeated groups** — `Repeat Count = 1`
  for both an 800m Hard rep (04:33/km, the single fastest pace in the whole
  dataset) and a 1.00 mi Hard rep (05:16/km) — i.e., peak *intensity* is
  preserved or increased, while repeat volume/complexity contracts sharply
  versus week 11.
- Relative week 12 (W24, Slot B): a single "Active" block of only `2.00 mi` at
  Zone 4 — a sharp cut versus W22's `6.00 mi` the week before.
- Relative Week 13 (W25, Race): **no pace, no %threshold, no TP Zone column is
  populated at all.** The only prescriptions are `RPE`. Warm-up = "Warm up Easy
  Walk/Slow-Jog," `.50 km`, `RPE 3`. The race itself = "Active," `5.00 km`,
  `RPE 6`, with a verbatim pacing-strategy note: *"Start conservatively; pick up
  effort ~1.5 mi; if strong at mile 2, increase effort to finish."*

This last point is a structural discontinuity, not a gradual taper of the same
variable: **the program's entire intensity-prescription mechanism (pace/%
threshold) is dropped for the race itself in favor of RPE + a verbal pacing
heuristic.** This is SOURCE FACT (directly read from the cells) — *why* RP does
this is not stated anywhere in the source text, so any rationale offered below is
explicitly labeled PROGRAMMING INFERENCE, never asserted as RP's own reasoning.

---

## 6. Intensity Model

**[SOURCE FACT]**, `PercentThresholdPaceCalculator.xlsx`, cell `F13`:
`=ROUNDDOWN(((C13*60+D13)/E13)/60,0)` (minutes, floor-rounded) and cell `G13`:
`=(((C13*60+D13)/E13))-(F13*60)` (remainder seconds), where `C13`/`D13` are
threshold minutes/seconds and `E13` is the prescribed fraction (e.g. `0.8` for
80%). Collapsing to seconds: **`adjusted_pace_seconds = threshold_pace_seconds /
percent_of_threshold`.**

**[SOURCE FACT]** cross-confirmation, `RP_5K_TrainingPeaks_Reference.xlsx`,
`Source & Inputs` row 7: *"Actual pace = threshold pace / prescribed fraction"* —
independently states the identical formula in prose, in a different file,
without reference to the calculator's cell formulas. Two independent
representations agree.

**[DERIVED FACT] — independently re-verified, not merely trusted**, against the
`Intensity Map` sheet (which the workbook itself flags per-row as *"Source
pace/zone = SOURCE FACT; percentage = DERIVED FACT"*), using captured threshold
= 300s:

| Source Pace | sec/km | Formula: 300/sec | Sheet's own value | Match |
|---|---|---|---|---|
| 08:20 | 500 | 0.600 | 0.6 | ✅ |
| 07:09 | 429 | 0.6993 | 0.6993006993... | ✅ |
| 06:40 | 400 | 0.750 | 0.75 | ✅ |
| 06:30 | 390 | 0.7692 | 0.7692307692... | ✅ |
| 06:15 | 375 | 0.800 | 0.8 | ✅ |
| 05:45 | 345 | 0.8696 | 0.8695652174... | ✅ |
| 05:33 | 333 | 0.9009 | 0.9009009009... | ✅ |
| 05:23 | 323 | 0.9288 | 0.9287925697... | ✅ |
| 05:16 | 316 | 0.9494 | 0.9493670886... | ✅ |
| 05:09 | 309 | 0.9709 | 0.9708737864... | ✅ |
| 05:00 | 300 | 1.000 | 1.0 | ✅ |
| 04:46 | 286 | 1.0490 | 1.0489510490... | ✅ |
| 04:33 | 273 | 1.0989 | 1.0989010989... | ✅ |

Every one of the 13 distinct paces used anywhere in `Workout Blocks` is
represented in `Intensity Map` and independently reproduces the sheet's own
`Derived % Threshold`, exactly. No discrepancy found. This is the strongest,
most independently-verifiable piece of evidence in the entire analysis.

**[R1 CORRECTION]**: this report's original draft stated "14 distinct paces" in
both this paragraph and the Executive Summary, while the table immediately
above it already displayed only 13 rows — an internal inconsistency flagged by
independent review. Re-verified directly against the live workbook this pass:
`python3`/`openpyxl` against `RP_5K_TrainingPeaks_Reference.xlsx` confirms the
`Intensity Map` sheet contains exactly 13 non-empty pace rows (08:20 through
04:33, the same 13 rows shown in the table above), and an independent
distinct-value count over `Workout Blocks`' own `Source Pace min/km` column
(146 rows) also yields exactly 13 distinct paces, the identical 13 values. The
two counts agree with each other and with the table. **Corrected count: 13, not
14.** No pace value is missing from the table — the table was already
complete; only the prose count was wrong.

**[SOURCE FACT]**, `Intensity Map` also gives the **observed pace→TrainingPeaks
Zone mapping** — but this is explicitly non-authoritative per the source's own
repeated caveats (Handoff Notes row 8, Source & Inputs row 18: *"TrainingPeaks
zone is display metadata, not treated as programming authority"*). It is reported
here only as descriptive context, never as a programming input:

| Zone | Pace range (sec/km) | % Threshold range |
|---|---|---|
| Zone 1 | 500 | 0.60 |
| Zone 2 | 429 | 0.70 |
| Zone 3 | 400 | 0.75 |
| Zone 4 | 375-390 | 0.77-0.80 |
| Zone 5b | 345 | 0.87 |
| Zone 5c | 273-333 | 0.90-1.10 |

**[SOURCE FACT]**, `HowTo.txt` line 9: *"On days that are prescribed at a
threshold percentage of 89% or less, please do not exceed these values for any
workout that has them prescribed, or you may risk injury."*

**[R1 CORRECTION — this rule was misclassified in the original draft of this
report.]** The original draft generalized this into a "hard sub-90% safety
ceiling," and Golden Scenario 8 (§19) incorrectly treated *any prescription
below 89%* as something to hard-block. Independent review correctly identified
that this is inconsistent with the observed program itself, which contains
multiple legitimate prescriptions well below 89% (≈60%, 70%, 75%, 77%, 80%,
87% — see §6's own Intensity Map table above: 0.6, 0.6993, 0.75, 0.7692, 0.8,
0.8696 are all real, used paces). Re-reading the source sentence directly: the
word "these values" refers back to *the specific prescribed percentage for
that day's workout*, not to a fixed 89%/90% threshold. The correct semantic
reading is:

- **PROGRAMMING VALIDITY**: any %threshold value the source data actually
  uses (60% through ~110%, per the Intensity Map) is valid programmed
  intensity. **≤89% is not a floor, not a minimum, and not something to block
  or avoid prescribing.**
- **ATHLETE EXECUTION OVERRIDE LIMIT**: when a workout/block is prescribed at
  ≤89% of threshold, the athlete must not *exceed that day's own prescribed
  intensity* during execution (e.g., turn a prescribed 80% effort into 85% or
  90% "because it feels easy"). The rule constrains real-time athlete
  behavior relative to the day's own prescription — it says nothing about
  which percentages the plan itself is allowed to program.

This is **not** a weakening of the safety rule — the rule is real, and it is a
genuine hard "do not exceed" (not a soft suggestion) for any day it applies to.
It is a correction of what the rule actually constrains: **the athlete's
in-session execution against that day's own prescribed intensity**, never
**the set of intensities TrainingOS is allowed to prescribe**. Every
downstream statement built on the original (incorrect) "sub-90% ceiling on
prescription" reading is corrected below (§17, §18, §19 Scenario 8, and the
verdict table row in §13, which remains accurate as originally written since
it only cites the rule's existence, not its scope).

**[SOURCE FACT]**, `HowTo.txt` line 13: *"There are scheduled Threshold Pace
Adjustment reminders within the plan... Don't adjust any other time."* — pace
recalibration is a **scheduled event**, not athlete-discretionary. Corroborated
independently by `Calendar Overview` rows 8 and 12 (*"Threshold Pace Adjustment
around Nov 2"*, *"Threshold Pace Adjustment 2 around Nov 30"* — a ~5 calendar-week
gap between the two observed instances). **[PROGRAMMING INFERENCE]**: recalibration
checkpoints recur roughly once per mesocycle, shortly after that mesocycle's
reduced-volume week (Nov 2 checkpoint is 1 calendar week after the "lighter week"
flagged at calendar-week 6; Nov 30 is 2 weeks after the "lighter week" at
calendar-week 10) — plausible but not confirmed by only 2 observed instances.

**[SOURCE FACT]**, `HowTo.txt` line 14: pace tolerance — *"If you're within
10-15 seconds per mile (faster or slower), you're probably doing just fine!"*

---

## 7. Workout Family Taxonomy (derived from the actual observed structures, not imposed)

Derived strictly from the `Source Label` values actually present in `Workout
Blocks` plus their structural role (never labels invented from generic running
vocabulary):

| Family (as labeled in source) | Structural role observed | Pace/Zone behavior | Repeat-capable? |
|---|---|---|---|
| **Warm up** | Precedes the working portion; 1-7 blocks observed | Ranges Zone 1→Zone 5c even within a single warm-up (striding pattern) | No (never itself repeated) |
| **Tempo** | Weeks 1-3 Slot A's sole quality content | Constant Zone 5c pace, distance-progressed | No — later superseded by "Hard" |
| **Active** | Slot B's sole content throughout; also used as the race's own label | Constant Zone 4 (weeks 1-12); RPE-only at race | No |
| **Easy** | Recovery between reps in a Repeat Group; also standalone post-work volume | Zone 1 or Zone 3 depending on role | Yes, as the partner block within a Repeat Group |
| **Hard** | Introduced relative week 9+; the interval/high-intensity element | Zone 5c, ≥90% and up to ~110% threshold | Yes — the primary Repeat Group driver |
| **Cool Down** | Terminal block of Slot B workouts | Zone 3 | No |
| **Warm up Easy Walk/Slow-Jog** | Race-day only variant of warm-up | RPE 3, no pace | No |
| **Recovery** *(R3 addendum — see below)* | The recovery leg between `Active` work bouts, relative weeks 5-8 (e.g. W09-W16) | Zone 3-4 | No (distinct from Easy's own Repeat-Group-partner role) |

**[R3 CORRECTION — addendum, not a rewrite of the above]**: this table
originally listed 7 families. During Running R3 implementation, a full,
literal re-transcription of all 145 `Workout Blocks` rows (not just the
representative weeks this section's prose walks through) found an 8th real
`Source Label` value, `"Recovery"`, used in relative weeks 5-8 as the
recovery leg between two `Active` work bouts within one Slot A workout
(e.g. W09: `Active 1.50mi @ 05:16` → `Recovery .50mi @ 06:15` → `Active
1.00mi @ 05:16` → `Recovery .50mi @ 06:40`) — structurally distinct from
`Easy` (which never appears in this specific role in weeks 5-8; `Easy`'s
own roles are the Repeat-Group partner block introduced from week 9
onward, and standalone post-work volume). This was missed by this
section's original analysis because it discusses representative weeks in
prose rather than a literal row-by-row transcription. The original 7-row
table above is left completely unchanged; only the 8th row and this note
are added. `RunningSourceLabel` (R2) is updated to add `.recovery`
accordingly (additive, non-breaking).

**[PROGRAMMING INFERENCE]**: the taxonomy is not "workout types" in a generic
sense (there is no source evidence for RP labels like "Base," "Threshold run,"
"VO2max run," "Long run," etc. — those words never appear as `Source Label`
values). The only true axis is **(a) which zone/pace-band a block occupies** and
**(b) whether it participates in a Repeat Group**. "Tempo" vs. "Hard" is a
*label change over time for functionally the same slot* (both are Slot A's sole
non-warm-up, non-recovery content), not two coexisting families — this is
evidence that the program's *label vocabulary itself evolves with training
phase*, which is a notable and non-obvious finding worth flagging for R2 as a
possible signal that RP's underlying template swaps its own workout-type
definitions mid-program rather than smoothly progressing a single named type.

---

## 8. Weekly Progression — the programming signal

What changes vs. what stays constant, week over week, **[SOURCE FACT + DERIVED FACT]**:

| Variable | Behavior across weeks 1-8 | Behavior across weeks 9-12 |
|---|---|---|
| Distance (Tempo/Active/Hard) | Increases progressively; occasional planned dip | Increases, then contracts specifically in the taper (wk 11→12) |
| Pace / %threshold within a labeled block | **Held constant** within each 1-3 week span, then step-changed | Held constant within a rep, changes only across the named Repeat Groups within one workout |
| Structural complexity (# distinct blocks, # Repeat Groups) | Flat (2-4 blocks/workout) | Rises sharply (up to 14 blocks/1 workout at wk11), then contracts (wk12) while single-rep intensity holds or rises |
| Warm-up elaborateness | 1-2 simple blocks | Up to 7 blocks, striding pattern | 
| Repeat Count | Not present | 4 → 6 → (multi-group, wk11) → 1 (wk12, single reps at peak pace) |

**[DERIVED FACT]**: the program manipulates **at least two independent axes**
simultaneously across its life: (1) a classic volume/intensity progression
(distance and pace), and (2) a **structural-complexity axis** (repeat groups,
warm-up staging) that only turns on in the back half of the plan. This second
axis is easy to miss if only distance/pace are tracked — it is a distinct,
non-redundant signal.

**[PROGRAMMING INFERENCE]**: this reads as a two-stage program — an initial
*volume-and-pace-only* stage (weeks 1-8, building an aerobic/tempo base) followed
by an *interval-introduction* stage (weeks 9-12, layering race-specific
structural complexity on top of the same intensity scale) before a final
single-rep peak/taper (transition into week 12) and a structurally unrelated
RPE-based race prescription (week 13). RP's own text never uses phase words like
"base" or "build" for this plan, so these are inference labels for our own
internal reasoning only, not terms to surface to users as if RP said them.

---

## 9. Phase / Mesocycle Model (minimum defensible version)

**[SOURCE FACT]**, `FAQ.txt` lines 7-9 establish that RP's own model *does* use
"mesocycle" as a real structural unit with an internal deload: *"One way to
shorten the overall duration of the program would be to cut out 1 working week
from every training mesocycle... Cutting out a deload week without also cutting
out the entire mesocycle that it's associated with is not recommended."* Line 28
similarly refers to *"the first 'working week' of training after the previous
deload week."* **These are RP's own words — "mesocycle" and "deload week" are
source vocabulary, not our invention.**

**[SOURCE FACT]**, `FAQ.txt` line 26 gives RP's own operational **definition**
of a deload week: *"deload weeks are those weeks in your training plan where the
total mileage run is markedly lower than the previous week, and often intensity
is lower as well."* This is directly usable — a deload/reduction week is
identifiable by a mileage drop, not by a label RP attaches externally.

**[DERIVED FACT]**, doubly corroborated periodicity: `Workout Blocks` shows
reductions at relative weeks 4 and 8 (4-week spacing). `Calendar Overview`
independently flags "lighter week" at calendar weeks 2, 6, 10, and a taper/rest
day at calendar week 14 (4-week spacing throughout). **Neither sheet's week
numbering can be proven to align with the other** (see §17's discrepancy), but
the *periodicity itself* — a reduced-volume week roughly every 4 weeks — is
supported independently twice, which is stronger evidence than either sheet
alone.

**Minimum defensible mesocycle model, with confidence:**
- **HIGH CONFIDENCE [DERIVED FACT]**: the program is organized into blocks of
  roughly 4 weeks, the last of which is a materially reduced-volume week.
- **MEDIUM CONFIDENCE [PROGRAMMING INFERENCE]**: there are 3 such 4-week
  mesocycles in the 12-week build portion of the observed data, followed by a
  distinct final block (relative weeks 11-13) that behaves differently (rising
  structural complexity → single-rep peak → RPE-only race) and should not be
  forced into the same "mesocycle" pattern.
- **NOT SUPPORTED — do not impose**: any RP-style phase *names* (Base,
  Threshold, VO2max, Peak). RP's own text never uses these words for this plan;
  only "mesocycle," "deload week," "training block," and "race week" appear as
  RP's own vocabulary (FAQ lines 7-9, 26-29).

---

## 10. Planned Reduction / Deload — distinguished from athlete-side disruption

**[SOURCE FACT]** RP's definition (FAQ line 26, quoted above) is *purely
volume-based and plan-relative* — a deload is defined by comparison to the
plan's own prior week, not by any athlete-reported state. This is the key
distinguishing test: **a planned reduction is a property of the calendar/plan
itself, verifiable from the prescription data alone; athlete fatigue, a missed
workout, or illness are athlete-side events that must never be confused with it,
and RP's own rules (§13) explicitly branch on which one occurred.**

**[SOURCE FACT]** observed planned reductions in this dataset: relative weeks 4
and 8 (`Workout Blocks`), and calendar weeks 2/6/10/14 (`Calendar Overview`,
independently).

**[PROGRAMMING INFERENCE]**: the final block's taper-like contraction (relative
week 12's cut from `6.00 mi`→`2.00 mi` in Slot B, and repeat-count collapse from
multi-group→single-rep in Slot A) is structurally a deload/reduction by RP's own
volume-based definition, even though nothing in the source explicitly labels it
"deload" — it satisfies RP's own test (markedly lower mileage than the previous
week) and should be treated as one.

---

## 11. Race-Specific Development & Taper

**[SOURCE FACT]**, relative week 11 (W21/W22) is the single highest-volume,
highest-structural-complexity week in the observed data (multi-group intervals
in Slot A, `6.00 mi` continuous Active in Slot B) — i.e., **peak load precedes
taper by exactly 2 relative weeks**, not immediately before the race.

**[SOURCE FACT]**, relative week 12 (W23/W24) sharply contracts volume in both
slots while *preserving or increasing* peak per-rep pace (the single fastest
pace in the whole dataset, 04:33/km, occurs here) — classic taper signature:
volume down, intensity touch preserved.

**[SOURCE FACT]**, `Calendar Overview` row 15: calendar week 14 is independently
described as *"taper/light optional work; mandatory day off Dec 27"* — a
**mandatory rest day is explicitly called out**, the only day in the entire
Calendar Overview sheet singled out this way.

**[SOURCE FACT]**, race week (W25 / calendar week "Dec 28" row): the
prescription abandons pace/%threshold entirely for RPE (§5). This is the
sharpest discontinuity in the whole intensity model.

**[PROGRAMMING INFERENCE]**: RP's taper is 2 weeks long (relative weeks 12-13),
preceded by a single peak week (11), and the switch to RPE for the race itself
is plausibly because race pacing is meant to respond to how the athlete actually
feels on the day (consistent with the pacing-strategy note: *"Start
conservatively; pick up effort ~1.5 mi; if strong at mile 2, increase effort to
finish"*) rather than because %threshold is somehow inapplicable on race day. **No
source text anywhere states this rationale explicitly — it is inference, not
confirmed.**

**[TRAININGOS PRODUCT DECISION candidate, not decided here]**: whether a
generalized Running Engine should model "race day" as always RPE-driven, or
whether that is specific to this one captured race's transcription, is
unresolved — flagged BLOCKING-FOR-R2 in §21.

---

## 12. Taper & Race Week — detail

Already covered substantively in §11. Additional specific citation: `FAQ.txt`
line 9 independently confirms the "race week is designed specifically" framing
at the whole-program level: *"The race week is designed specifically to
encourage recovery and peaking for your big day!"* — this is RP's own stated
purpose for race week, **SOURCE FACT**, and matches what is directly observed in
the data (§11).

---

## 13. RP Documented Adaptation Rules — verification table (exact citations)

Every row cross-checked against actual source text, not paraphrased from memory.
Verdict values: **SOURCE CONFIRMED** (text found, matches expectation),
**SOURCE PARTIALLY CONFIRMED** (related text found but narrower/broader than
expected), **NOT FOUND**, **CONTRADICTED**.

| Rule area | Verdict | Citation |
|---|---|---|
| Shortening the plan (cut 1 week/mesocycle, or remove a whole block) | SOURCE CONFIRMED | `FAQ.txt` lines 6-9 |
| Non-round distances (metric/imperial rounding) | SOURCE CONFIRMED | `FAQ.txt` line 11 |
| Treadmill incline compensation | SOURCE CONFIRMED | `FAQ.txt` lines 12-13 (0.5-1° incline) |
| Day-shifting within/across weeks | SOURCE CONFIRMED | `FAQ.txt` lines 14-15 |
| Lifting on non-prescribed days | SOURCE CONFIRMED | `FAQ.txt` lines 16-17; `Pairing.txt` lines 6, 9, 15-17 |
| Unit switching (metric/imperial) | SOURCE CONFIRMED | `FAQ.txt` lines 18-19 |
| Rep-failure protocol, split by intensity band | SOURCE CONFIRMED | `FAQ.txt` lines 20-21 (>101% vs. <100% threshold handled differently) |
| Injury-pain protocol | SOURCE CONFIRMED | `FAQ.txt` line 22 (explicit stepwise walk→jog→run re-entry with hard stop on any pain recurrence) |
| Missed single workout | SOURCE CONFIRMED | `FAQ.txt` lines 23-24 |
| Missed whole week (illness vs. travel, branched) | SOURCE CONFIRMED | `FAQ.txt` lines 25-27 (illness: repeat previous week unless it was a deload; travel/obligations: move forward, no repeat) |
| Missed multiple consecutive weeks | SOURCE CONFIRMED | `FAQ.txt` line 28 |
| Missed >1 month | SOURCE CONFIRMED | `FAQ.txt` line 29 |
| Extra session-count limits (lifting/other) | SOURCE CONFIRMED | `FAQ.txt` lines 30-31; `Pairing.txt` lines 24-27 (max +2 lifting days; -1 day minimal impact; -2+ risks weakness/injury) |
| Optional-workout guidance | SOURCE CONFIRMED | `FAQ.txt` lines 32-34 |
| Race on non-Saturday day-of-week | SOURCE CONFIRMED | `FAQ.txt` lines 35-44 (Sunday, Friday, mid-week each separately addressed) |
| Race-frequency limits | SOURCE CONFIRMED | `FAQ.txt` lines 45-48 (nominal 16-week cadence; "not meant to withstand more frequent racing than every 4-6 weeks"; general endurance-coaching guidance of ≤2 races/month even in-season, quoted as RP's own general recommendation, not 5K-plan-specific) |
| Goal-time-setting percentages | SOURCE CONFIRMED | `FAQ.txt` lines 49-51 (5-10%/yr new athletes, 1-3%/yr advanced, <1%/yr elite) |
| Cross-distance use of the 5K plan (10K, marathon) | SOURCE CONFIRMED | `FAQ.txt` lines 52-53 |
| Non-stackability of RP endurance programs | SOURCE CONFIRMED | `FAQ.txt` lines 54-56; `Pairing.txt` line 14 |
| Intensity-override rules (going faster than prescribed) | SOURCE CONFIRMED | `FAQ.txt` lines 57-59 (never on rep 1; never at ≤95% threshold or ≤RPE 6; conditionally allowed mid-set) |
| Worn-down-but-pushable rules, split by workout type | SOURCE CONFIRMED | `FAQ.txt` lines 60-64 (interval >100%/RPE7+: cut reps, don't slow; threshold 90-100%: hold ≥90% or shorten distance; marathon-pace 80-90%: walk-recover ≥800m; easy ≤80%: always fine to slow) |
| Can't-complete-workout fallback, threshold-pace-reduction guidance | SOURCE CONFIRMED | `FAQ.txt` lines 65-67 (slow paces 5-10% for the rest of that session; if a fluke, no further change; if far off with no extenuating circumstance, consider lowering threshold pace itself by 2-5%, via the TrainingPeaks zones profile setting) |
| 89%-threshold injury-risk hard rule | SOURCE CONFIRMED | `HowTo.txt` line 9 |
| Scheduled-only threshold recalibration | SOURCE CONFIRMED | `HowTo.txt` line 13; corroborated independently by `Calendar Overview` rows 8, 12 |
| Pace tolerance band | SOURCE CONFIRMED | `HowTo.txt` line 14 (±10-15 sec/mile) |

No rule in the directive's checklist came back NOT FOUND or CONTRADICTED —
RP's FAQ/HowTo documentation is unusually complete on exactly this set of
edge-case questions.

---

## 14. Missed Session / Illness / Re-entry (consolidated)

Already individually cited in §13; consolidated decision tree, **[SOURCE FACT]**
throughout, `FAQ.txt` lines 20-29:

1. **Can't complete a single rep** → branch on prescribed intensity: ≥101%
   threshold → finish rep at best-possible pace + extra rest before next rep;
   <100% threshold → stop, walk 1-3 min, resume only once confident.
2. **Pain during a rep** → stop immediately; graduated walk→jog→run re-test; any
   recurrence at any stage → full stop, seek medical advice.
3. **Miss one workout** → shift 1 day later if it doesn't compromise the next
   session, else skip entirely and continue as scheduled.
4. **Miss a whole week, illness** → repeat the previous week, *unless* the
   previous week was itself a deload week, in which case just resume with the
   missed week.
5. **Miss a whole week, travel/obligations** → move forward immediately, no
   repeat.
6. **Miss multiple consecutive weeks** → restart the current training block from
   the first working week after the prior deload (or from the very start, if the
   absence began before the first deload).
7. **Miss >1 month** → restart the entire plan, or move back ≥6 weeks and repeat.
8. **Can't complete a whole workout as prescribed** → slow all remaining paces
   5-10% for the rest of that session; if it seems like a fluke, no further
   change; if far off target with no extenuating circumstance, consider a 2-5%
   threshold-pace reduction via the athlete's own zones/pace profile setting.

---

## 15. Concurrent Training Guidance

**[SOURCE FACT]**, `Pairing.txt`:
- Lifting is sequenced **after** running on 2-a-day days (lines 6, 9, 15).
- If lifting must precede a running session and can't be separated by ≥6 hours,
  slow running paces 5-10% — "a last resort" (line 17).
- RP endurance programs are explicitly **not stackable** — never run two full
  programs concurrently; at most substitute one workout/week between two
  programs (`Pairing.txt` line 14, corroborated by `FAQ.txt` lines 54-56).
- Diet-template day categorization (NTD / Light / Moderate / Hard Day) is
  attached per-workout in "pre-activity comments" (line 21) — **[SOURCE FACT +
  explicit source caveat]**: `Handoff Notes` row 9 states *"RP Diet Template
  'Light Day' is not treated as physiological workout classification"* — i.e.,
  this label is a nutrition-planning artifact, not evidence about training
  intensity, and must not be conflated with the %threshold/zone data.
- Lifting-frequency modification: up to **+2** additional lifting days can
  usually be accommodated (added to the hardest/longest running days that don't
  already carry a lifting workout); **-1** lifting day has minimal running
  tradeoff; **-2 or more** risks weakness/injury (lines 24-26).

---

## 16. Frequency Generalization Limits

Classified per the directive's three-tier scheme. This checkpoint only examined
**one** frequency variant (the captured plan, 2 runs/week). No other RP running
frequency tier was available (see §3 MISSING SOURCE).

- **SUPPORTED**: the %threshold pace formula (§6) — nothing about it is
  frequency-specific; it is a pure pace/threshold-ratio calculation.
- **SUPPORTED**: the missed-workout/illness/re-entry decision tree (§14) — RP's
  own text states these rules in frequency-agnostic terms ("a workout," "a
  week"), not tied to a specific weekly session count.
- **SUPPORTED**: the concurrent-training/non-stackability rules (§15) — stated
  generally across "the Endurance Training Programs" as a family, not this plan
  specifically.
- **PLAUSIBLE-BUT-UNPROVEN**: the ~4-week mesocycle/deload cadence (§9) — only
  demonstrated at one frequency (2 runs/week); whether a 3, 4, 5, or 6-day
  variant uses the same 4-week cadence, a different cadence, or ties deload
  timing to something else (e.g. total weekly volume rather than elapsed weeks)
  cannot be determined from one data point.
- **PLAUSIBLE-BUT-UNPROVEN**: the two-axis progression model (volume/pace then
  structural complexity, §8) — plausible as a *general* RP running-programming
  pattern given how cleanly it appears here, but confirmed in exactly one
  instance.
- **INSUFFICIENT EVIDENCE**: how workout-family taxonomy (§7) would map onto a
  higher-frequency plan that might introduce additional slot types (e.g. a true
  long run distinct from "Active," or multiple hard days per week) — no
  evidence either way.
- **INSUFFICIENT EVIDENCE**: whether the race-week RPE-only discontinuity (§11)
  is general RP doctrine or specific to how this one race got transcribed into
  the reference workbook.

**Do not generalize beyond what is marked SUPPORTED above** without new source
evidence — this is the directive's explicit prohibition and is treated as a hard
constraint on this report's own conclusions, not just a caveat to mention.

---

## 17. Proposed TrainingOS Running Programming Model (conceptual only — not implemented)

This section is intentionally conceptual and implementation-independent; no
Swift types, no engine code. Each element is tagged.

**Core normalized intensity variable — SOURCE-SUPPORTED.** A running
prescription should carry threshold-relative intensity (`% of threshold pace`)
as its primary programmed variable, converted to an absolute pace via the single
recovered formula (§6). **[R1 CORRECTION]** The safety invariant is not a
sub-90% floor on what may be *prescribed* (the source program itself
legitimately prescribes intensities from ~60% to ~110%) — it is an
**execution-time ceiling**: whenever a block's prescribed intensity is ≤89% of
threshold, the athlete must not exceed that block's own prescribed intensity
during execution. A scheduled-only recalibration trigger (never ad hoc) remains
correctly stated as originally written.

**Two independent progression axes — SOURCE-SUPPORTED as a described pattern,
TRAININGOS-EXTENSION as a generalized mechanism.** (1) volume/pace progression
within a fixed workout structure, and (2) structural-complexity progression
(repeat-group count/nesting) introduced only in a later stage — modeling these
as two separately-tracked progression variables (not one blended "difficulty"
score) is directly supported by the observed data's own separation of these
signals, but generalizing this into a reusable mechanism for arbitrary athletes/
frequencies is a TrainingOS extension beyond what one instance proves.

**Mesocycle = N build weeks + 1 reduced-volume week, RP's own vocabulary —
SOURCE-SUPPORTED structurally, UNRESOLVED on exact N.** RP's own text uses
"mesocycle" and "deload week" (§9); this checkpoint's data supports N=4 in this
one instance but does not establish that 4 is fixed across frequencies/goals.

**Deload defined operationally (mileage-drop-relative-to-prior-week), not by an
external label — SOURCE-SUPPORTED.** This is RP's own definition (FAQ line 26)
and is directly reusable: a Running Engine can *detect* a reduction week from
its own generated volumes rather than needing a separate "is this a deload"
flag threaded through unrelated code.

**Taper as a distinct final block (peak → single-rep contraction → RPE-driven
race) — SOURCE-SUPPORTED as observed, PROGRAMMING INFERENCE on generalizing its
exact length.** 2-week taper length is what was observed once; whether this
scales with plan length is UNRESOLVED.

**Race-day RPE handoff — UNRESOLVED, flagged BLOCKING-FOR-R2 (§21).** Whether
generalized racing prescriptions should always drop to RPE, or whether this was
specific to the one transcribed race, needs either more source evidence or an
explicit TrainingOS product decision if no more evidence becomes available.

**Missed-session/concurrent-training rule set — SOURCE-SUPPORTED, and already
stated by RP in frequency-agnostic terms (§14, §15)** — directly reusable as
Running Engine business rules essentially as-is, independent of which specific
weekly program is being run.

---

## 18. Running Engine ↔ Orchestrator Contract (boundary only, no code)

Grounded in `Pairing.txt`'s own framing of what each side is responsible for:

- **Running Engine owns**: translating a prescribed %threshold into an absolute
  pace (§6's formula); enforcing the **[R1 CORRECTION]** per-block execution
  override ceiling (never let athlete-side execution exceed that block's own
  prescribed %threshold when it is ≤89%) — never a floor on what may be
  prescribed; detecting/labeling
  a reduction week from its own generated volumes (§9's operational deload
  test); the missed-session/illness/re-entry decision tree (§14) as it applies
  *to running sessions specifically*; the intensity-override and
  can't-complete-workout fallback rules (§13) for running sessions.
- **Orchestrator owns** (per RP's own stated division of concerns in
  `Pairing.txt`): sequencing lifting *after* running on shared days; deciding
  whether added/removed non-running sessions this week still respect the +2/-1
  session-count guidance (§15); non-stackability across concurrently-purchased
  RP-style programs (never running two full running programs at once — this is
  a cross-program constraint, not something the Running Engine alone can see);
  diet-template day categorization is explicitly **not** a Running Engine
  concern (Handoff Notes row 9 — it is nutrition planning, kept out of the
  physiological classification entirely).
- **Ambiguous / needs an explicit decision later**: whether the ~4-week
  mesocycle cadence and the race-day RPE handoff are Running-Engine-internal
  facts, or facts the Orchestrator needs visibility into for cross-modality
  scheduling (e.g. so a strength mesocycle can be phase-aligned with a running
  deload week) — this checkpoint surfaces the ambiguity but does not resolve it
  (see §21).

---

## 19. Golden Behavioral Scenarios (design only, conceptual, not implemented)

Each scenario states the situation, the expected Running-Engine behavior per
recovered source rules, and its evidence basis.

1. **Prescribed 85% threshold, athlete can't hold pace mid-rep.** Expect: switch
   to the 90-95%-threshold pace band if still >90% prescribed, or drop to a
   walk-recovery if <90% band and truly can't continue. *[SOURCE FACT, FAQ
   lines 61-63]*
2. **Prescribed 95% threshold interval, athlete feels strong on rep 1.** Expect:
   engine refuses the override — never on rep 1, never at ≤95%/≤RPE6. *[SOURCE
   FACT, FAQ lines 57-59]*
3. **Athlete misses one Tuesday run, no conflict with Wednesday's session.**
   Expect: shift to Wednesday, one day later. *[SOURCE FACT, FAQ line 24]*
4. **Athlete misses an entire week due to flu; prior week was NOT a deload.**
   Expect: repeat the prior week before resuming. *[SOURCE FACT, FAQ line 26]*
5. **Athlete misses an entire week due to flu; prior week WAS a deload.**
   Expect: resume directly with the missed week, no repeat. *[SOURCE FACT, FAQ
   line 26]*
6. **Athlete misses a week for travel (not illness).** Expect: move forward,
   never repeat, regardless of whether the prior week was a deload. *[SOURCE
   FACT, FAQ line 27]*
7. **Athlete requests to add 3 lifting days beyond the prescribed schedule.**
   Expect: flag as exceeding the recommended +2 max; surface a caution rather
   than silently accepting. *[SOURCE FACT, Pairing.txt line 26]*
8. **[R1 CORRECTION — this scenario was wrong in the original draft and is
   replaced below.]** Original (incorrect) scenario read: "A prescription would
   put an interval rep below 89% relative pace by accident... Expect: hard
   block." This was wrong — a prescription at or below 89% (e.g. 80%, 75%,
   60%) is ordinary, valid programming (§6), not something to block.
   **Corrected scenario**: a block is prescribed at 80% threshold (≤89%); the
   athlete, feeling strong, tries to run it at 85% instead. Expect: hard
   block/refusal of the override attempt — the athlete may not exceed *that
   block's own prescribed 80%* during execution. This is a strict "do not
   exceed," not a soft warning, but it constrains the athlete's real-time
   execution against the day's own prescription, never the act of prescribing
   ≤89% in the first place. *[SOURCE FACT, HowTo.txt line 9]*
9. **Athlete tries to recalibrate threshold mid-mesocycle, not at a scheduled
   checkpoint.** Expect: engine declines/defers — recalibration is
   scheduled-only. *[SOURCE FACT, HowTo.txt line 13]*
10. **Race is scheduled for a Sunday instead of the plan's native Saturday.**
    Expect: one of the three explicitly enumerated shift strategies (whole-week
    shift + Monday rest; Thu/Fri-only shift + Thursday rest; multi-week
    consistent shift). *[SOURCE FACT, FAQ lines 37-39]*
11. **Athlete wants to race again 2 weeks after finishing this plan.** Expect:
    surface the ≤4-6-week minimum-recovery guidance and the plan's own
    pre-season framing (not built for high racing frequency) rather than
    silently scheduling it. *[SOURCE FACT, FAQ line 48]*
12. **Reaching the transcribed race week itself (Relative Week 13).** Expect:
    the engine emits an RPE-only prescription with the pacing-strategy note,
    not a %threshold-derived pace — this is the one scenario resting on a
    single observed instance rather than a documented rule, so it should be
    implemented behind a flag that's easy to revisit once more race-week
    evidence exists. *[SOURCE FACT for the one instance; PROGRAMMING INFERENCE
    for generalizing it]*

---

## 20. Unknowns

Classified per the directive's three-tier scheme.

**BLOCKING-FOR-R2:**
- Whether the race-day RPE-only handoff (§11) is general RP doctrine or an
  artifact of this one transcription.
- The exact mapping (or lack thereof) between `Workout Blocks`' relative-week
  numbering and `Calendar Overview`'s calendar-week numbering, and which ~3
  weeks of the nominal 16-week program are simply missing from both captured
  views (§3, §21).
- Whether the 4-week mesocycle cadence is fixed by RP's programming logic or
  happens to be this athlete's/plan's particular value.

**NEEDED-BEFORE-BROADER-SUPPORT (i.e., before generalizing beyond 2-runs/week):**
- Any other RP running-frequency tier's actual workout structure (only referenced,
  never inspected — §3).
- Whether the two-axis (volume/pace vs. structural complexity) progression
  pattern holds at other frequencies or is specific to a 2-run/week cadence.
- Whether workout-family taxonomy (§7) needs new families at higher frequency
  (e.g. a dedicated long run distinct from "Active").

**SAFE-TO-DEFER:**
- The exact remainder-seconds rounding behavior of the pace calculator (floor
  vs. round vs. truncate on the seconds component) — minor, doesn't affect the
  primary minutes computation or any %threshold value actually observed.
- Full reconciliation of diet-template day categorization with training load —
  explicitly out of physiological scope per the source itself (Handoff Notes
  row 9).
- Any deeper mechanistic rationale for *why* RP chose a 4-week rather than
  3-week or 5-week mesocycle length — not needed to implement the rule
  correctly, only to explain it.

---

## 21. Risks of Over-Generalization

- **Risk**: treating this one plan's exact mesocycle length (4 weeks), taper
  length (2 weeks), or repeat-count progression (4→6) as universal constants
  rather than as observed values from a single instance. Mitigation: keep these
  as configurable/derivable parameters in any future engine design, not
  hardcoded literals, and revisit once a second frequency tier is inspected.
- **Risk**: silently reproducing the exact captured plan (25 workouts, this
  exact progression) as "the" TrainingOS 5K program — this is precisely what
  the source's own Handoff Notes explicitly forbid (row 3: *"Do not reproduce
  this observed plan as the TrainingOS Running Engine"*) and what this
  checkpoint's own directive forbids.
- **Risk**: treating RP's TrainingPeaks Zone labels (Zone 1-5c) as a
  programming input rather than descriptive metadata — the source itself
  repeatedly disclaims this (Source & Inputs row 18, Handoff Notes row 8); using
  zones as an engine input would misrepresent the actual authority chain, which
  runs through %threshold, not zone number.
- **Risk**: allowing an Orchestrator or Long-Term Planner to chain repeated 5K
  running programs beyond the ~4-6 week racing cadence RP itself says this plan
  wasn't designed for (FAQ line 48) — a Running Engine that lets an athlete
  chain 5K plans back-to-back without surfacing that caveat would be silently
  contradicting RP's own stated design intent.
- **Risk**: assuming the 3 "missing" weeks between the nominal 16-week program
  and the 13/15-week captured views are simply an easy lead-in or cool-down that
  can be safely ignored — there is no evidence for what they actually contain,
  and they could hold programming logic (e.g. an initial ramp mesocycle) not
  represented anywhere in this analysis.

---

## 22. Recommended R2 Scope

1. Resolve the 16-vs-13/15-week discrepancy — either locate the missing ~3
   weeks' source material, or make an explicit, documented TrainingOS product
   decision to treat the 13-relative-week captured structure as the full
   authoritative shape and record that decision (not silently assume it).
2. Obtain at least one additional RP running-frequency tier (even
   documentation-only, without a captured instance) to test which of §16's
   PLAUSIBLE-BUT-UNPROVEN claims actually generalize.
3. Decide, as an explicit TrainingOS product decision (not an inference), how
   race week should be modeled — RPE-only per this one instance, or a
   %threshold-compatible representation with RPE as an overlay — since this is
   the single highest-impact unresolved question in the whole model (§11, §20).
4. Only after 1-3: begin conceptual (still non-code) design of the actual
   Running Engine data model, informed by this report's §17-18, with explicit
   sign-off on which elements are SOURCE-SUPPORTED enough to implement directly
   vs. which require a documented TrainingOS product decision first.

---

## 23. R1 Correction Addendum (post-independent-review)

Added after independent review of this report. Does not reopen or reword any
already-correct R1 finding — it (a) corrects the two errors identified above
(89% rule scope, §6/§17/§18/§19-Scenario-8; pace count, §1/§6) and (b)
reclassifies which unresolved items from §20/§21 actually block which scope of
future work, per the review's explicit request. Nothing in §1-§22 above was
rewritten beyond the inline `**[R1 CORRECTION]**`-tagged edits already made at
each affected location.

### 23.1 Blocker reclassification

The three items originally listed as flat "BLOCKING-FOR-R2" (§20) and the
three originally listed as "NEEDED-BEFORE-BROADER-SUPPORT" remain genuinely
unresolved — nothing here resolves them. What changes is recognizing that none
of them block the source-supported *foundation* primitives, which do not
depend on any of these six open questions:

| Unresolved item | Classification |
|---|---|
| Race-day RPE-only generalization (§11, §17, §20) | BLOCKS 5K GENERATOR (the 5K program isn't complete without a race-week behavior) + BLOCKS BROADER RUNNING SUPPORT (whether it's universal RP doctrine) |
| 16-week vs. 13-relative-week discrepancy / missing ~3 weeks (§3, §20) | BLOCKS 5K GENERATOR only — a complete 5K program needs the full week count; foundation primitives don't |
| Exact universal mesocycle length (§9, §20) | BLOCKS BROADER RUNNING SUPPORT only — a 5K generator may directly use the one observed, source-supported N=4/3-mesocycle instance without needing to prove it's universal |
| Other RP frequency tiers' structure (§3, §16, §20) | BLOCKS BROADER RUNNING SUPPORT only |
| Two-axis progression model at other frequencies (§8, §16, §20) | BLOCKS BROADER RUNNING SUPPORT only |
| Workout-family taxonomy at higher frequency (§7, §16, §20) | BLOCKS BROADER RUNNING SUPPORT only |
| Pace-calculator seconds-rounding edge behavior (§20) | SAFE TO DEFER (unchanged) |
| Diet-template/training-load reconciliation (§15, §20) | SAFE TO DEFER (unchanged) |
| Rationale for why 4 weeks specifically (§20) | SAFE TO DEFER (unchanged) |

**None of the six unresolved items above are classified BLOCKS RUNNING
FOUNDATION.** Every primitive in the candidate foundation list below is
SOURCE-SUPPORTED (§16) independent of how race day, the missing weeks, or
universal mesocycle length are eventually decided.

### 23.2 Revised R2 foundation scope (supersedes none of §22, narrows its item 4)

R2 may proceed directly on the following, without waiting on any of the six
unresolved items above:

- Threshold-relative intensity representation (`% of threshold`) — §6.
- Threshold → target pace calculation, using the recovered formula — §6.
- Pace rounding behavior exactly as source-established (floor-minutes,
  remainder-seconds) — §6.
- `RunningBlock`/prescription structure capable of expressing a labeled block
  (Warm up / Tempo / Active / Easy / Hard / Cool Down / Warm up Easy
  Walk-Slow-Jog), a distance, and a %threshold-or-RPE intensity — §5, §7.
- Repeat-group representation (`Repeat Group` label + `Repeat Count`,
  pairing a working block with a recovery block) — §5.
- Source-label preservation (never collapsing "Tempo" and "Hard" into one
  internal type, since §7 shows the label itself is evidence of programming
  phase) — §7.
- Athlete execution-override rules, corrected per §6/§19 above — the ≤89%
  per-block execution ceiling, the never-override-rep-1/never-below-95%-or-
  RPE6 rule, and the intensity-band-specific "worn down but pushable" rules —
  §13, §14, §19.
- Scheduled-only threshold recalibration (never ad hoc) — §6.
- Missed-session, illness, and re-entry rules (§14) exactly as the decision
  tree states them.
- Can't-complete-workout fallback rules (§13, §14).
- Running-specific adaptation rules from the §13 verification table generally.
- Orchestration metadata/contract elements already source-supported in §18
  (lifting-after-running sequencing, non-stackability, +2/-1 session-count
  guidance, diet-day-label exclusion from physiological classification).

Explicitly NOT in R2 foundation scope (unchanged from §22/§21, restated here
for clarity per the review's request):

- A generalized arbitrary-frequency program generator.
- A universal mesocycle length.
- A universal taper length.
- Universal race-day RPE behavior.
- Fabricated content for the missing ~3 weeks.
- Unsupported 3/4/5/6-day running templates.

§22's own 4-item sequence (resolve week discrepancy → obtain another frequency
tier → decide race-week modeling → then design the engine data model) remains
the recommended path to a complete, generalized *5K generator* and to
*broader* running support. This addendum's foundation-scope list is narrower
and is what may proceed in parallel, immediately, without waiting on §22's
sequence — it does not replace §22, it identifies what doesn't need to wait
for it.

---

## Files created/changed

- **Created**: `app/RUNNING_PROGRAMMING_MODEL_R1.md` (this file). Nothing else.
- No Swift files touched. No `source_workbooks/` files modified (read-only
  inspection throughout, confirmed by file permissions/hashes unchanged).

```
$ git status --short
?? ../.DS_Store
?? .DS_Store
?? CP3_AND_TRAINING_ENVIRONMENT_AUDIT.md
?? POST_FFP1_FUNCTIONAL_FITNESS_GAP_AUDIT.md
?? TE1_TRAINING_ENVIRONMENT_FOUNDATION_DESIGN.md
?? TrainingOS.xcodeproj/project.xcworkspace/xcuserdata/
?? TrainingOS.xcodeproj/xcuserdata/
(+ this checkpoint adds: ?? RUNNING_PROGRAMMING_MODEL_R1.md)

$ git diff --stat
(empty — no tracked file was modified by this checkpoint)
```

All pre-existing untracked files above (`CP3_AND_TRAINING_ENVIRONMENT_AUDIT.md`,
etc.) predate this checkpoint and were not touched. No commit, no staging, no
push occurred.

---

## Verdict

**RUNNING R1 SOURCE RECOVERY: PASS**
**PROGRAMMING MODEL READY FOR REVIEW: YES**
