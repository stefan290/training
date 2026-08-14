# Open Programming Questions

Every ambiguity found during Stage 3A source analysis that was **not**
guessed into a resolved rule, per the brief's explicit instruction ("Do not
guess unclear logic. Flag ambiguity explicitly"). Each item names the
documents that already reference it, the evidence, and what would be
needed to resolve it. Nothing in this document blocks the rest of Stage
3A's deliverables — it is the deliverable for everything that couldn't be
settled from source material alone.

## 1. Family A has no matching official documentation

Referenced from: `PROGRAM_LOGIC_SPEC.md` §1.

All 3 supplied PDFs document Family B/C (the Powerlifting Strength and
Hypertrophy-block templates). None of the 11 Family A ("general
hypertrophy") workbooks — the largest group in the source set — has any
matching official RP documentation. Every Family A rule in this analysis
was reconstructed purely from formulas and cell labels, with correspondingly
higher risk that an undocumented intent was missed. **Needed to resolve:**
either RP's own general-hypertrophy documentation (if it exists and wasn't
included), or explicit product-owner sign-off that the reconstructed rules
in `PROGRAM_LOGIC_SPEC.md` §2 are an acceptable substitute for authored
documentation.

## 2. Mesocycle sequencing is unproven

**RESOLVED at the architecture level — `STAGE3_DECISION_MEMO.md` A1.**
The source finding below is unchanged (no formula proves sequencing); the
product decision was to model the three phases as a sequential
`ProgramJourney` anyway, as an explicit product interpretation of the
naming/order rather than a claim about the source data. See
`PROGRAMMING_SYSTEM_MODEL.md` §5.1.

Referenced from: `PROGRAM_LOGIC_SPEC.md` §2.2, `PROGRAMMING_SYSTEM_MODEL.md` §4.

Family A's three sheets are named "Mesocycle 1/2/3," strongly implying a
sequence, but no formula, named range, or cross-sheet reference proves
one — each mesocycle's RM input is independent and blank. Two readings are
equally consistent with the evidence: (a) three sequential blocks meant to
run back-to-back with RM re-tested at the start of each, or (b) three
independent, optionally-standalone templates a user could pick just one
of. **Needed to resolve:** a product-owner ruling, or source material that
states the intended sequencing explicitly (a coach's guide, an app store
listing, marketing copy — anything outside the spreadsheets themselves).
This gates whether `ProgramInstance` needs a "next phase" transition
concept for Family A at all.

## 3. "Resensitization" doesn't mean what the name implies

Referenced from: `PROGRAM_LOGIC_SPEC.md` §2.2.

Mesocycle 3 is named "Resensitization," which reads as a deliberately light
reset. The formulas show the opposite: 100% of 10RM (the *highest*
relative intensity of the three phases, vs. 85%/75% for the other two),
paired with the *lowest* volume and shortest duration (3 weeks vs. 5).
**Needed to resolve:** confirm with the product owner (or RP's own
marketing/methodology material, if available) whether "short, low-volume,
high-intensity reset" is the intended design, or whether this file's
labeling/formulas are internally inconsistent and one of them is wrong.
Do not build a "light and easy" Resensitization mode into TrainingOS based
on the name alone.

## 4. The Metabolite-Focus superset partner has no deload row

**RESOLVED — `STAGE3_DECISION_MEMO.md` A2.** Decision: Option A — the
partner exercise is omitted during deload week, represented as an
explicit `DeloadExerciseAction.omit` on that specific, confirmed
prescription (not a generic "blank source cell means omit" rule). See
`PROGRAMMING_SYSTEM_MODEL.md` §3.2 and `PROGRAM_REGRESSION_TEST_PLAN.md`
§9.2.

Referenced from: `PROGRAM_LOGIC_SPEC.md` §2.2.

Mesocycle 2's superset partner exercise (the exercise whose sets are
driven by the *primary* exercise's rating, not its own) has a blank
deload-week row entirely — not a zero, not a formula, nothing. Unresolved
whether this means the partner exercise is skipped entirely during deload
week, or whether the blank is simply an unfilled cell and it should follow
the same rule as every other row. **Needed to resolve:** a product-owner
ruling on deload behavior for superset partners specifically.

## 5. Deload rep counts are text instructions, not computed values

**RESOLVED — `STAGE3_DECISION_MEMO.md` A3.** Decision: round down
(floor). Example: Week-1 reps 7 × deload fraction 1/2 = 3.5 →
**TrainingOS prescription: 3 reps**. See
`PROGRAMMING_SYSTEM_MODEL.md` §3 (`deloadRepInstruction.roundingDirection`)
and `PROGRAM_REGRESSION_TEST_PLAN.md` §9.1 for the fixtured cases.

Referenced from: `PROGRAM_LOGIC_SPEC.md` §2.1 (`FAMILY_A_REP_GOAL_SCHEDULE`),
`PROGRAM_REGRESSION_TEST_PLAN.md` §7.

Every family expresses deload-week reps as a literal string ("1/2 reps of
Week 1," "2/3 reps of Week 1") rather than a formula. No workbook contains
`ROUND`/`ROUNDDOWN`/`INT`/`FLOOR` anywhere (confirmed by whole-workbook
grep) — the source material itself defers the actual arithmetic (What is
half of 7 reps? Rounded which way?) to the human reading the sheet.
**Needed to resolve:** TrainingOS needs an explicit rounding-direction
ruling (round up, round down, or round-to-nearest) before deload week can
be computed automatically for any family — this is a genuine gap in the
source logic, not something inferable from it.

## 6. The legs-only "Heavy" 1.0× exception — deliberate or a copy/paste artifact?

Referenced from: `PROGRAM_LOGIC_SPEC.md` §2.3 (`FAMILY_A_LEGS_HEAVY_EXCEPTION`),
`PROGRAM_FAMILY_MATRIX.md` §1.

Only the `legs` split's squat/deadlift/walking-lunge category uses `×1.0`
(full 10RM) as the Week-1 baseline factor, instead of the `×0.85` every
other split uses on its own squat/deadlift-pattern rows — including
full_body, which also contains squat and deadlift rows. **Needed to
resolve:** confirm whether "compound barbell lifts always load closer to
true max, regardless of split" is the intended design (in which case the
other three splits' squat/deadlift rows are the anomaly, not `legs`), or
whether `legs` alone picked up a one-off copy/paste change that should be
`×0.85` like everywhere else. Model as an explicit, named, opt-in
exercise-category override either way (`PROGRAM_FAMILY_MATRIX.md` §1) —
this question is about the *default*, not the mechanism.

## 7. Novice vs. standard needs a same-day-count comparison pair

Referenced from: `PROGRAM_LOGIC_SPEC.md` §2.5, `PROGRAM_FAMILY_MATRIX.md` §2.

The only available Novice file is 3-day full_body, with no 3-day standard
counterpart to compare against directly — every comparison made had to
cross a day-count boundary (3-day Novice vs. 4-/5-day standard), so a
day-count confound can't be fully ruled out for differences that happen to
correlate with day-count (rest-day generosity, day-split naming). Every
mechanism that *could* be isolated from day-count (rep ranges, RM basis,
progression factors, autoregulation formula, deload formulas, exercise
catalog breadth) showed no novice-specific effect. **Needed to resolve:**
a same-day-count novice/standard pair (e.g. two 4-day full_body files, one
labeled Novice) — not supplied in this source set. Until then, do not
implement a distinct novice ruleset.

## 8. Deload weight/rep asymmetry contradicts Family B/C's own documentation

**RESOLVED — `STAGE3_DECISION_MEMO.md` A4.** Decision: trust the
spreadsheet over the PDF wherever they conflict, for every family — but
preserve this only as `SourceCompatibleDeloadStrategy` for source-derived
`ProgramDefinition`s, explicitly *not* as TrainingOS's own general deload
methodology (`TrainingOSDeloadStrategy`, intentionally left undefined
until the Generator is built). See `PROGRAMMING_SYSTEM_MODEL.md` §6.1.

Referenced from: `PROGRAM_LOGIC_SPEC.md` §3 (`FAMILY_B_DELOAD`), §4
(`FAMILY_C_DELOAD`), §6.3.

Family B's own HowTo PDF states deload reps are uniformly "2/3 of Week 1,"
with a worked example (7/5/4 → 4/3/2) that does match 2/3 — but the actual
spreadsheet only uses 2/3 for the Monday/Tuesday half of the week; Thursday
/Friday sessions use 1/2, not 2/3. Family C's spreadsheet independently
shows a *different* asymmetry in its deload *weight* rule (Monday/Tuesday
unchanged, Wednesday–Friday halved) that doesn't cleanly align with either
a lift-type split or a simple first-half/second-half split by count. Every
family (A, B, and C) has some undocumented deload asymmetry — this is the
single largest concentration of unresolved product ambiguity in the whole
source set. **Needed to resolve:** explicit product-owner rulings, per
family, on which half of each week's asymmetry is the *intended* rule
(and whether the PDF or the spreadsheet is authoritative where they
conflict) before `ProgramEngine` can implement any family's deload
deterministically.

## 9. No source material for endurance or functional-fitness modalities

Referenced from: `PROGRAM_FAMILY_MATRIX.md` §4, `PROGRAM_GENERATOR_SPEC.md` §5.

All 15 workbooks are hypertrophy or powerlifting-strength. Nothing supplied
addresses aerobic base, running, VO2/interval work, or
functional-fitness/CrossFit-style programming (round-based scoring, time
caps, pace zones). This is a real product-scope gap, not a modeling
question — `TrainingModality`/`WorkoutBlockType` (Stage 1–2) already
anticipate these modalities structurally, but no `ProgrammingSystem` can
be specified for them without source material to analyze. **Needed to
resolve:** separate source material (a different methodology's
spreadsheets/documentation, or direct product-owner specification) before
any endurance/functional-fitness `ProgressionRule` types get defined.

## 10. Slot-reference translation (cell address → domain reference) risk

**RESOLVED — `STAGE3_DECISION_MEMO.md` A5.** Decision: a structural,
authoring-time reference (`ExercisePrescription.pairedSlot`), not a
runtime history query. Movement-pattern/muscle-group metadata stays
available separately for substitutions, discovery, the Generator, and
analytics, but never determines this dependency link at runtime. See
`PROGRAMMING_SYSTEM_MODEL.md` §5.2.

Referenced from: `PROGRAMMING_SYSTEM_MODEL.md` §3, §8.

`autoregulatedSetCount` and `linkedResultReference` both need to name a
*slot* declaratively (e.g. "the other slot in this day sharing category X,"
or "the most recently completed prior session of this movement pattern")
rather than a literal spreadsheet cell address like `F35`. Every
cross-exercise pairing found in this analysis (Front Squat/High Bar Squat,
OHP/Bench, the Friday backoff exercise referencing Monday's) was
identified by manually tracing a specific formula to a specific other
cell — there is no general rule in the source material for *how* a slot
names its pairing partner declaratively; each pairing was hand-authored by
whoever built that specific workbook. **Needed to resolve:** this is
primarily an implementation-design question for Stage 4, not a source
ambiguity — flagged here because it's the least mechanical part of turning
`PROGRAM_LOGIC_SPEC.md`'s findings into working code, and underestimating
it risks a Stage 4 timeline surprise.

## 11. Whether TrainingOS ever offers an lb display toggle

Referenced from: `METRIC_LOAD_MODEL.md` §2, §6.

TrainingOS is metric-native internally (locked, Stage 1–2). Out of scope
for this pass is whether V1 (or any later version) offers a *display-only*
pounds toggle for users who think in lb, distinct from internal storage
(always kg). The source material itself is authored in lb (confirmed via
RP's own FAQ worked example), so this will be a real user-facing question
once real imported/generated programs exist. **Needed to resolve:** a
product/UX decision, not a data question — `EquipmentProfile`'s design
(§2 of `METRIC_LOAD_MODEL.md`) already keeps this a display-layer decision
that wouldn't require a schema change either way.

## 12. Dual-tagged exercise categories

**RESOLVED — `STAGE3_DECISION_MEMO.md` A6.** Decision: do not defer.
`ExerciseSlot` carries a real `allowedTargets: [MuscleGroup]` list; no new
special-case entity. Once a concrete exercise is chosen, `resolvedTarget`
records which allowed target it satisfies. V1's shipped configurations may
still pre-select one exercise per slot for convenience, but the schema
itself preserves the slot's original multi-target intent. See
`PROGRAM_GENERATOR_SPEC.md` §4.

Referenced from: `PROGRAM_GENERATOR_SPEC.md` §4.1.

Some Family A hypertrophy categories are dual-tagged in the source
material itself (e.g. "Chest Isolation or Triceps," "Rear or Side Delts")
— the same slot can resolve to either of two different target muscles
depending on which the user picks. Unresolved whether this should be
modeled as one `ExerciseCategory` with two valid `primaryTarget` values
selected at resolution time, or as two separate categories that happen to
share a row in the source spreadsheet's layout. **Needed to resolve:** a
product decision on `ExerciseCategory`'s shape — this affects the exercise
library schema, not just the generator, so it should be settled before
Stage 4 builds either.

## 13. Family B's own Week-4 autoregulation asymmetry (Mon/Tue vs. Thu/Fri)

Referenced from: `PROGRAM_LOGIC_SPEC.md` §3 (`FAMILY_B_AUTOREGULATION`).

Distinct from Family C's documented Week-4 freeze (§5.2 of
`PROGRAM_REGRESSION_TEST_PLAN.md`): in Family B, Monday/Tuesday rows' Week-4
sets add the rating exactly as weeks 2–3 do, but Thursday/Friday rows' Week
4 is a flat, unmodified copy of Week 3 (`Q25: '=L25'`, no rating term at
all — confirmed by direct formula inspection, not inferred). Today this has
no observable effect, because deload week's set count is a hardcoded
constant regardless of what Week 4 computed. **Needed to resolve:**
whether this is a deliberate design choice (e.g. "stop adjusting sets in
the last loading week for the second half of the split") or a copy-paste
leftover from an earlier version of the template — the two families having
*different* week-4 quirks (Family B: Thu/Fri stops adding; Family C: Thu/Fri
freezes at week-3's *value*) makes "this is just how RP always does it"
an unsafe assumption. Needs a product-owner ruling before an evaluator
encodes either behavior as intentional.

## 14. Strength_Program_1/2 authorship and timing are undeterminable from the files

Referenced from: `PROGRAM_LOGIC_SPEC.md` §5.

Confirmed with moderate-high confidence that `Strength_Program_1`/`2` are
user-customized derivatives of Family B/C, not a fifth methodology — but
*who* made the edits (the end user themself, a coach, a distributor) and
*when* (recently, or copied from an even older ancestor workbook that
already had these tweaks) cannot be determined: the supplied file dumps
carry no author/company XLSX metadata, tab colors, or comments. Two
smaller sub-questions ride along with this: (a) three RPPowerliftingStr4Day
-only guidance notes (`<10 sets(no abs)=light`, `5-10 reps first set`,
`3-8 reps first set`) are absent from all three other files, including its
own sibling `RPPowerliftingHyp5Day` — cause unknown; (b) the specific
set/rep-count tuning differences between Program_1 and Program_2 on their
shared training days (e.g. Tuesday 5 vs. 6 sets, Thursday 3 vs. 4) look
like intentional volume tuning per RM-basis but this is not confirmed by
anything in the files themselves. **Needed to resolve:** none of this
blocks the architectural conclusion (`PROGRAM_FAMILY_MATRIX.md` §3,
Family D row) — it's recorded here only in case the product owner has
independent knowledge of these files' provenance (e.g. they were supplied
by a specific customer or partner) that would change how much weight to
give them as configuration evidence.

## 15. Sheet-c leftover data-validation ranges on the Family B workbook

Referenced from: this document only (not yet carried into
`PROGRAM_LOGIC_SPEC.md` — recorded here since it doesn't affect any rule,
only what to *ignore* when Stage 4 reads this file's raw structure).

`f046f129-RPPowerliftingStr4Day.xlsx` sheet `c` has data-validation dropdown
ranges at `I41`, `I42:I43`, `I44:I45` that point at shifted, unrelated
sheet-`c` content — consistent with a copy/paste leftover from sheet `b`'s
real exercise-picker ranges, not a functioning picker on the Mesocycle
sheet itself. Separately, no `{-1, 0, 1}`-restricting data validation was
actually captured on the real rating input cells (`F5`, `K5`, etc.) in this
dump — the constraint may exist uncaptured by the extraction method used,
or may be enforced only by convention/legend text, not a real Excel
validation rule. **Needed to resolve:** nothing product-facing — this is a
note for whoever eventually builds an automated import pipeline for these
files, so they don't mistake `I41`-style ranges for a real exercise-slot
definition.
