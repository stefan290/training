# Stage 10R — Source Program Library Recovery & Architecture Realignment

**STATUS: AUDIT / DESIGN ONLY. No production code, no test, no seed
data, and no prior Stage 10 artifact has been modified, reverted, or
deleted while producing this document.** This document and
`TRAININGOS_PRODUCT_CONSTITUTION.md` are the two deliverables requested;
neither is committed. See the 18-item final report at the end for the
required summary, then this stage stops for approval.

---

## 1. Source artifact search — what actually exists in this repository

**Excel/CSV files:** zero. Confirmed by both a full-tree `find` for
`*.xlsx`/`*.xls`/`*.csv` (empty) and `git log --all --diff-filter=A
--name-only` across every commit in the repository's history for the
same extensions (empty). No Excel or CSV file has ever been added to
this git repository, at any point in its history.

**But the source library was real and was analyzed — just not in this
repo as binaries.** `app/PROGRAM_LOGIC_SPEC.md` (517 lines) is a Stage
3A deliverable that documents, with per-cell formula citations, **15
Excel workbooks + 3 PDFs**, each with a specific original filename
(hex-prefixed, e.g. `e1f8fb19-4_day_full_body.xlsx`,
`f046f129-RPPowerliftingStr4Day.xlsx`), sheet names, and file sizes
(§1 of that document, reproduced in full in §2 below). This is not
plausible-sounding invented content: it cites specific cell addresses
and formula text (`J11: '=MROUND(((G11)*0.85),2.5)'`), cross-validates
findings across "Agents A1–A5"/"Agent B1" (a prior multi-agent
analysis pass), and explicitly separates **SOURCE BEHAVIOR** from
**TRAININGOS-DESIGNED BEHAVIOR** throughout (a discipline also used in
`PROGRAMMING_SOURCES.md`). The conclusion: **the 15 workbooks were
supplied to, and analyzed by, an earlier stage of this project — almost
certainly uploaded directly into that stage's own working session rather
than committed to this git repository as files.** The raw binaries are
gone (not deleted from git history — never present in git history at
all); the recovered **rule analysis** survives in full, exhaustive,
citation-backed detail. This is the single most important correction to
this fork's earlier working hypothesis (recorded in this session's own
prior turns): it is **false** that no real source-program library ever
existed. It is **true** that no Excel/CSV binary survives in this repo.

Supporting documents in the same lineage, all real, all present:
`OPEN_PROGRAMMING_QUESTIONS.md` (303 lines, every ambiguity Stage 3A
found and did NOT guess), `STAGE3_DECISION_MEMO.md` (821 lines, the
product owner's own resolutions A1–A6 plus B/C/D classifications),
`PROGRAM_FAMILY_MATRIX.md`, `PROGRAM_GENERATOR_SPEC.md`,
`PROGRAMMING_SYSTEM_MODEL.md`, `PROGRAM_REGRESSION_TEST_PLAN.md`,
`V1_PROGRAM_LIBRARY.md`, `METRIC_LOAD_MODEL.md` — all exist as real
files at `app/*.md` (confirmed via `find . -maxdepth 1 -iname "*.md"`;
full list of ~70 filenames referenced from Swift doc comments was
cross-checked and every Stage 3/4-era name resolves to a real file — no
phantom citations found among the load-bearing ones).

`chats/chat1.md` and `project/*.dc.html` (the design-handoff bundle) are
a **different, earlier artifact** — UI/UX design-conversation transcripts
and Claude Design canvas prototypes describing a **hypothetical future**
"import a spreadsheet" onboarding feature (their own "Path B" language),
illustrated with fictional demo numbers. They are not evidence for or
against the real Excel library — they predate or run parallel to it and
should not be confused with `PROGRAM_LOGIC_SPEC.md`'s real analysis.

**Git deletion history:** no `.xlsx`/`.xls`/`.csv` file, and no
`*_SPEC.md`/`*_LIBRARY.md`/`*_QUESTIONS.md`/`*_MEMO.md`-named file, was
ever added-then-deleted in this repository's git history (`git log
--diff-filter=D --name-only --all` grepped for those patterns: no hits
inside this specific naming family). Everything Stage 3A/3B/4 produced
is still present and still committed. There is no lost-then-recovered
content to reconcile — the content was never lost from git; it was
simply never fully **consumed** by later generator code (see §11, §17).

## 2. Full program library matrix

| Program | Family | Days/wk | Source file | Split/exercises | Sets/Reps/RIR model | Progression model | Deload model | Current representation | Executable today? | Used by real production? | Faithful? |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 4-Day Full Body | A | 4 | `e1f8fb19-4_day_full_body.xlsx` | full_body, category dropdowns | 3 sets compound/2 isolation/6 calves; rep goal `3/fail→3/fail→2/fail→1/fail` | `rmBased` 0.85×10RM wk1, ×1.05/1.075/1.1 wk2-4 | full wk1-2, half wk3-4 (`ceil(4/2)=2`) | **Load/progression: yes**, via `HypertrophyProgramGenerator`+`StrengthProgressionEngine` (config "4-Day Full Body Hypertrophy"). **Session structure: no** — generator emits 1 primary + 1 fixed "Chest Isolation or Triceps" accessory slot/day, never the source's 6-7 category slots/day | Partially | Yes (built-in library) | **Partially** — load math faithful, content structure not |
| 5-Day Full Body | A | 5 | `1e3d5441-5_day_full_body.xlsx` | full_body | same shape | same shape | full wk1-3, half wk4-5 (`ceil(5/2)=3`) | Same partial pattern | Partially | Yes | Partially |
| 6-Day Full Body | A | 6 | `1eb44a1e-6_day_full_body.xlsx` | full_body | same shape | same shape | `ceil(6/2)=3` full/half | Same partial pattern | Partially | Yes | Partially |
| 4-Day Legs | A | 4 | `bb847616-4_day_legs.xlsx` | legs, `FAMILY_A_LEGS_HEAVY_EXCEPTION` (×1.0 not ×0.85 on Heavy Quads/Glutes) | same shape | same shape + legs exception | same | Config exists ("4-Day Lower/Leg Focus") but generator's fixed accessory slot is still "Chest Isolation or Triceps," **not** a legs-appropriate accessory — the one file specifically chosen to exercise the legs-heavy override never actually surfaces a legs day in production | No (structurally) | Yes (built-in library, mis-executing) | **No** — this is the worst fidelity gap in the matrix |
| 5-Day Arms/Shoulders | A | 5 | `f06502c6-5_day_arms__shoulders.xlsx` | arms_shoulders, dual-tagged categories (A6) | same shape | same shape | same | Config exists ("5-Day Upper/Arms Focus") but produces Overhead-Press+Chest/Triceps every day — never resolves the dual-tagged Rear/Side-Delt category at all | No | Yes | No |
| 6-Day Back/Chest | A | 6 | `f63aa557-6_day_back__chest.xlsx` | back_chest | same shape | same shape | same | **Not shipped as a configuration at all** (V1_PROGRAM_LIBRARY.md §4: kept as "generator parameter space," never built) | No | No | N/A — never attempted |
| 3-Day Full Body (Novice-named) | A | 3 | `4847f523-3_day_full_body_Novice.xlsx` | full_body | same shape | same shape | `ceil(3/2)=2` full/1 half | Config "3-Day Full Body Hypertrophy" (name deliberately drops "Novice" per C1 finding: no behavioral difference exists) — this is the ONE config Stage 10B/10B.6/10C.1 richened via the V2 day-focus/SlotRole path | Partially (V2 path has real multi-slot days, still not the source's actual category list) | Yes, primary production path | Partially |
| 3-Day Arms/Delts (Novice) | A | 3 | `5ebc6e53-3_day_arms__delts_Novice.xlsx` | arms_delts | same shape | same shape | same | Not shipped | No | No | N/A |
| 5-Day Full Body (Novice) | A | 5 | `8ebd24ac-5_day_full_body_Novice.xlsx` | full_body | same shape | same shape | same | Corroborating evidence only (C1) — not separately shipped | No | No | N/A |
| 6-Day Arms/Shoulders (Novice) | A | 6 | `2d17f31c-6_day_arms__shoulders_novice.xlsx` | arms_shoulders | same shape | same shape | same | Not shipped | No | No | N/A |
| 6-Day Chest/Back (Novice) | A | 6 | `bf7f7b32-6_day_chest__back_novice.xlsx` | chest_back | same shape | same shape | same | Not shipped | No | No | N/A |
| RP Powerlifting Strength 4-Day | B | 4 | `f046f129-RPPowerliftingStr4Day.xlsx` | Legs×2/Push×2/Deadlift/Hamstring/Upper-Pull×2/Shoulder×2, 5RM/8RM split | `rmBased` 0.95×RM (0.7× "Triples" days) | ×1.05/1.075/1.1 | 0.7(Mon/Tue)/0.5(Thu/Fri) weight, "2/3"/"1/2" reps, B3 Week-4 asymmetry | Config "4-Day Powerlifting Strength" exists via a separate Stage 4B Powerlifting path (not `HypertrophyBuiltInLibrary`) | Believed yes (not re-verified this pass — see §13) | Believed yes | Believed yes, not re-verified this pass |
| RP Powerlifting Hypertrophy-block 5-Day | C | 5 | `6d06b9fd-RPPowerliftingHyp5Day.xlsx` | 10RM uniform, squat/push/pull/assistance | `rmBased` 0.95×10RM (0.85× Friday backoff) | ×1.05/1.075/1.1 off rounded wk1 cell | Mon/Tue unchanged, Wed-Fri ×0.5; B4 Week-4 freeze | Config "5-Day Powerlifting Hypertrophy" exists | Believed yes | Believed yes | Believed yes, not re-verified this pass |
| Strength_Program_1 | D | 4 | `7da7a0ae-Strength_Program_1.xlsx` | Family B lineage, user-edited | Family B's 5RM/8RM | Family B shape | Family B's 0.7/0.5 | **Not shipped** — evidence-only, per `V1_PROGRAM_LIBRARY.md` §4 | No | No | N/A (never claimed to be a shippable program) |
| Strength_Program_2 | D | 4 (adopts Program_1's layout) | `201e3cbc-Strength_Program_2.xlsx` | Family C lineage, user-edited | Family C's 10RM | Family C shape | Family C's unchanged/0.5 | Not shipped | No | No | N/A |

**Totals:** 15 source workbooks supplied (11 Family A, 1 Family B, 1
Family C, 2 Family D), backed by 3 PDFs (2 mapping to Family C, 1 to
Family B; none for Family A — §6.1 of `PROGRAM_LOGIC_SPEC.md`). Of the
11 Family A workbooks, 6 became shipped configurations (per
`V1_PROGRAM_LIBRARY.md`'s own second-pass revision); of those 6, only 1
(3-Day Full Body) received any of Stage 10's richer session-content work,
and even that richening did not consult the recovered per-category
structure documented in `PROGRAM_LOGIC_SPEC.md` §2.3-2.4 (see §11, §17).

## 3. Progression formulas, recovered verbatim

Quoted directly from `PROGRAM_LOGIC_SPEC.md` (source citations preserved
exactly as that document states them):

**Family A — `FAMILY_A_WEEK1_BASELINE`:**
- Mesocycle 1 ("Basic Hypertrophy"): `week1Weight = MROUND(tenRM × 0.85, roundingUnit)`
- Mesocycle 2 ("Metabolite Focus"): `week1Weight = MROUND(tenRM × 0.75, roundingUnit)` primary; `× 0.6` superset partner
- Mesocycle 3 ("Resensitization"): `week1Weight = MROUND(tenRM × 1.0, roundingUnit)` — full 10RM, the *highest* of the three
- Cited cells: `e1f8fb19` sheet 'Mesocycle 1' `J11: '=MROUND(((G11)*0.85),2.5)'`; 'Mesocycle 2' `J11: '=MROUND(((G11)*0.75),5)'`, `J13: '=MROUND(((G13)*0.6),5)'`; 'Mesocycle 3' `J11: '=MROUND(((G11)),5)'`

**Family A — `FAMILY_A_WEEKLY_PROGRESSION`:** `week2 = MROUND(week1×1.05, unit)`, `week3 = MROUND(week1×1.075, unit)`, `week4 = MROUND(week1×1.1, unit)` — off the fixed Week-1 value, not compounding. Mesocycle 3 has only one step (`week2=week1×1.05`, 3-week block).

**Family A — `FAMILY_A_REP_GOAL_SCHEDULE`:** `3/fail, 3/fail, 2/fail, 1/fail`, deload `1/2 reps of Week 1` (text, rounded down per `STAGE3_DECISION_MEMO.md` A3).

**Family A — `FAMILY_A_SET_AUTOREGULATION`:** Week 1 baseline is a fixed
per-archetype constant (compounds=3, isolation=2, calves=6). From Week 2:
`weekN.sets = weekN-1.sets(sameSlot) + rating(mostRecentlyCompletedPairedSlot)`,
rating ∈ {-1,0,1}. Deload sets = fixed constant 2, never autoregulated.
Cited: `O11: '=I11+(M35)'`, `U11: '=O11+(S35)'`, `AA11: '=U11+(Y35)'`.

**Family A — `FAMILY_A_DELOAD_WEIGHT_ASYMMETRY`:** full Week-1 weight for
`ceil(dayCount/2)` days, half for the rest. Cited: `AH11: '=J11'` vs.
`AH30: '=MROUND((J30*0.5),2.5)'`.

**Family B — `FAMILY_B_WEEK1_BASELINE`:** `week1 = MROUND(RM×0.95, 2.5)`
ordinary; `×0.7` for "Triples" sessions (Monday Bench, Thursday
Deadlift) specifically. RM basis is a hardcoded per-slot label (5RM:
Legs1/2, Push1/2, Deadlift; 8RM: Hamstring, Upper-Pull×2, Shoulder×2),
**not derived from which exercise is chosen.**

**Family B — `FAMILY_B_AUTOREGULATION`:** genuinely cross-exercise —
Front Squat's sets are driven by High Bar Squat's rating, confirming
pattern-level (not exercise-level) linkage. Only 8 "central" barbell
rows autoregulate; 8RM accessory rows use a fixed, never-autoregulated
schedule (2,2,3,3, deload 2). Week-4 asymmetry (B3): Mon/Tue rows add
the rating as usual; Thu/Fri rows are a flat copy of Week 3
(`Q25: '=L25'`, no addition term).

**Family B — `FAMILY_B_DELOAD`:** weight `×0.7` (Mon/Tue) / `×0.5`
(Thu/Fri); reps "2/3 of Week 1" (Mon/Tue) / "1/2 of Week 1" (Thu/Fri) —
**directly contradicting Family B's own HowTo PDF**, which claims a
uniform "2/3 of Week 1." Resolved (`STAGE3_DECISION_MEMO.md` A4): trust
the spreadsheet.

**Family C — `FAMILY_C_WEEK1_BASELINE`:** `week1 = MROUND(10RM×0.95, 5)`
standard; Friday's second exercise is a deliberate `×0.85` "backoff" of
Monday's same movement.

**Family C — `FAMILY_C_AUTOREGULATION`:** wired one-row-to-one-row, never
an aggregate. Confirmed dead columns: both Upper-Pull and both Shoulder
slots have rating inputs no formula ever reads (fixed 2,2,3,3
regardless); Hamstring's own rating is unused, its autoregulation copies
Deadlift's. Week-4 freeze (B4): Thu/Fri rows repeat Week-3's *value*
exactly, ignoring Week-4's own rating input.

**Family C — `FAMILY_C_DELOAD`:** weight unchanged Mon/Tue, `×0.5`
Wed/Thu/Fri (Deadlift and Hamstring — both "main lifts" — fall on the
halved side, ruling out a simple "keep the big lifts heavy" theory).

No workbook, in any family, contains `ROUND`/`ROUNDDOWN`/`INT`/`FLOOR`
anywhere — deload rep counts are always a literal instruction string
("1/2 reps of Week 1"), never computed (`OPEN_PROGRAMMING_QUESTIONS.md`
§5). Rounding increments (2.5 vs. 5) are confirmed **not** a reliable
unit or day-count signal — inconsistent even within a single Family A
workbook.

## 4. Load-vs-rep audit: Hypertrophy source vs. the load-bias preference

**What the source requires before load increases (Family A):** load
increase is purely calendar/week-driven, never rep-outcome-driven. Every
exercise in every workbook gets `week1×1.05/1.075/1.1` on a fixed
week-index schedule regardless of what reps were actually achieved.
**Sets**, not load, are the source's actual performance-responsive lever
(`FAMILY_A_SET_AUTOREGULATION`'s rating-driven set-count formula). Reps
are a fixed target schedule (`3/fail, 3/fail, 2/fail, 1/fail`) that never
changes based on prior performance either — "X/fail" bakes in
autoregulation implicitly (train to X reps short of failure, whatever
weight that requires), so the source's real autoregulation signal is:
**how it felt** (the -1/0/+1 rating) → **how many sets** next time, at a
load that's fixed by the calendar.

**The approved load-bias preference** (CLAUDE.md context, restated in
`TRAININGOS_PRODUCT_CONSTITUTION.md` §3) asks instead: when performance
clearly supports it, increase **load** rather than chasing the top of a
rep range. This is a genuinely different lever than anything Family A's
source formulas touch — the source never conditions load on rep
performance at all, so there is no source rule to "preserve" here in the
literal sense; there's a source rule (calendar-only, set-count-adaptive)
that the load-bias preference deliberately **adds a new, load-directed
lever on top of, not in place of**.

**Minimum modification needed (not implemented in this stage):**
introduce a load-progression path that is **gated by** genuine
performance signal (e.g. hitting/exceeding the rep-goal ceiling with
RIR to spare) as an **alternative or supplement** to the fixed
calendar-percentage schedule — while leaving the source's own
calendar-percentage schedule intact as the default/fallback path for
programs where no clear over-performance signal exists, and leaving
`FAMILY_A_SET_AUTOREGULATION`'s set-count mechanism completely
untouched (it is a different lever and the source's real autoregulation
system — replacing it with a load-driven system would be exactly the
"discard the source progression system" outcome the product owner
explicitly rejected). Stage 10B.6's `DoubleProgressionEngine` already
implements almost exactly this shape (performance-qualified load
increase, ≤10% proportional cap, two-consecutive-miss regression) —
see §12/§17 for the classification.

**CONFIRMED, not merely flagged (direct code read this pass,
`StrengthProgressionEngine.swift` + `StrengthProgressionRules.swift` +
`HypertrophyProgramGenerator.swift`'s `makeDayFocusTemplate`): for the
3-Day Full Body configuration specifically, `DoubleProgressionEngine` is
wired as a full replacement, not an overlay.** Every primary/secondary/
accessory `PrescriptionTemplate` this path creates sets
`loadRule: .doubleProgression` unconditionally — there is no fallback
branch to `.rmBased` at any performance level, and no code path re-enters
`StrengthProgressionEngine`'s calendar schedule once `.doubleProgression`
is selected. `StrengthProgressionEngine.resolveWeight`'s own
`.doubleProgression` case carries this exact doc comment: *"never
actually reached — `StrengthMaterializer` branches on `loadRule ==
.doubleProgression` before ever calling into this engine."* The same is
true of rep goals (V2's `RepGoal` rows never set `toFailure`, replacing
Family A's `3/fail→1/fail` schedule outright rather than gating an
alternative alongside it) and of deload (`StrengthMaterializer`'s
`.doubleProgression` branch resolves deload through
`HypertrophyV2ProgressionEngine`'s own logic, never through
`SourceCompatibleDeloadStrategy`, even though that strategy's Family-A
day-boundary asymmetry is fully correct and already implemented). **This
is not an open question requiring further code investigation — it is
confirmed: the source's calendar-based path has no execution path left
for this configuration at all**, matching
`STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md` §1's own stated intent
("[Family A] is not, and should not remain, TrainingOS's default...
philosophy") — that document's authors knew and intended a replacement,
not an overlay; the gap was that "replace" was never checked against
"is this actually TrainingOS's to replace," which is this whole
document's finding.

## 5. Exercise library reconstruction — an honest, bounded answer

**This cannot be reduced to a fixed number, and reporting one would be
inventing precision the source does not have.** Family A/B/C do not
specify closed exercise lists — every slot is a **category** (e.g.
"Incline Push," "Quads," "Vertical Pull," "Heavy Quads/Glutes," "Chest
Isolation or Triceps") backed by a per-category dropdown of named
exercises **plus an explicit "Other ___ move of choice" free-text
option** (`PROGRAM_LOGIC_SPEC.md` §2.1). The source's own exercise
universe is open-ended by design — a real user could type in any
exercise name for many slots. What **is** recoverable and finite:

- The **category names** per split (documented, not exhaustively
  enumerated in `PROGRAM_LOGIC_SPEC.md` beyond illustrative examples —
  the raw dropdown contents themselves were not transcribed into any
  surviving document).
- The **muscle/movement intent** per category (e.g. "Heavy Quads/Glutes"
  = squat/deadlift/walking-lunge pattern).
- The **slot count per day per split per day-count** (§2.4: exact,
  e.g. quads = 9 sets/week held constant across 4/5/6-day full_body
  variants; 26→28→30 total slots/week as day-count rises 4→5→6;
  slots/day falls 6-7→5 as day-count rises).

**Conclusion:** "how many unique exercises existed across the original
supplied programs" (the user's final-report item 4) does not have a
single correct number — the honest answer is "an open dropdown-plus-
free-text set per category, whose literal contents were never
transcribed into any surviving document." What *can* be answered
precisely is the **category structure** (§2.3-2.4), which is exactly
the layer `HypertrophyProgramGenerator` never consumed (§11).

## 6. Exercise catalog discrepancy — exact counts A-G

| Label | Quantity | Value | Confidence |
|---|---|---|---|
| A | Unique strength/hypertrophy exercises in original supplied library | **Not a fixed number — see §5.** The source is category-based with open free-text entry, not a finite named list. | N/A by construction, not a gap in this audit |
| B | Canonical `Exercise` rows before Stage 10C.1 | 31 | High (Stage 10C.1's own audit, confirmed: 37 − 6 new = 31) |
| C | Canonical `Exercise` rows now | **37** | Confirmed directly this pass (`grep -c` on `ExerciseCatalog.swift`'s `make(...)` calls) |
| D | `strengthCandidates` entries before Stage 10C.1 | 12 | High (8 original + 4 Stage 10B additions, per `SeedAnnualPlanJourney.swift`'s own doc comments) |
| E | `strengthCandidates` entries now | **23** | Confirmed directly this pass (counted the literal array in `SeedAnnualPlanJourney.swift`: 8 + 4 + 5 + 6 = 23) |
| F | Original exercises currently usable by authored/source programs | **Not computable — no authored/source `ProgramDefinition` exists that resolves against original category names at all (§11); the generator never encodes the source's categories, so "usable by the source program" isn't a question the current architecture can even ask.** | N/A — this is itself a finding, not a missing number |
| G | Original exercises currently usable by generic semantic resolution | 37 (the full catalog is exposed to `SubstitutionValidator`'s target/movement-function matching in principle) but only 23 are actually curated into any real candidate pool (`strengthCandidates`) that production code passes to slot resolution — see §9 | Confirmed |

**Why B→C and D→E grew:** Stage 10C.1 added 6 new exercises to fill
semantic gaps (`overheadPress`, `legExtension`, `cableChestFly`,
`facePull`, `latPulldown`, `seatedCableRow` — vertical-push/quad-
isolation/chest-isolation/rear-delt/loaded-vertical-pull/second-
horizontal-pull) and promoted 5 already-cataloged-but-uncurated
exercises into the real candidate pool (`bulgarianSplitSquat`,
`conventionalDeadlift`, `seatedLegCurl`, `seatedCalfRaise`, `pullUp`).
**None of this growth was driven by reading `PROGRAM_LOGIC_SPEC.md`'s
recovered category list** — it was driven by Stage 10B/10B.6's own
richer-session design needing more slot-fillable exercises for its
**invented** day-rotation, not by reconciling against the source's
actual categories. This is a real, if incidental, alignment risk: the
catalog grew for the right general reason (richer sessions need more
exercises) via the wrong process (invented day-structure) rather than
the right one (recovered source category structure).

## 7. Stage 10C.1's 6 new exercises vs. source category match

| New exercise | Source category match | Assessment |
|---|---|---|
| Barbell Overhead Press | No exact Family A category confirmed in surviving docs, but Family B/C's "Shoulder" 8RM-basis slots (`FAMILY_B_RM_BASIS`) are plausibly an overhead-press-family movement | Related, not exact — surviving docs don't name the specific exercise |
| Leg Extension | Not named in any surviving Family A/B/C document; plausibly fits a generic "Quads" isolation category | Related, unconfirmed |
| Cable Chest Fly | Not named; plausibly fits "Chest Isolation" categories described in Family A | Related, unconfirmed |
| Face Pull | Not named; plausibly fits a "Rear Delt" side of Family A's dual-tagged "Rear or Side Delts" category (A6) | Related, unconfirmed |
| Lat Pulldown | Not named; plausibly fits Family A/B/C "Upper-Pull"/"Vertical Pull" categories | Related, unconfirmed |
| Seated Cable Row | Not named; plausibly fits "Upper-Pull"/horizontal-pull categories | Related, unconfirmed |

**No accidental duplicate canonical concepts were found** — each of the
6 targets a distinct movement-function gap (`verticalPushLoaded`,
quad isolation, chest isolation, rear-delt, `verticalPullLoaded`,
`horizontalPullLoaded`) that Stage 10C.1's own semantic audit already
verified didn't collide with an existing exercise (`CatalogSemantic
FoundationTests.swift`, confirmed this pass by direct read — e.g. the
explicit regression test proving Overhead Press does **not** satisfy
the existing "Horizontal Push" slot grouping). The honest caveat: this
non-duplication check was done against **other current catalog
exercises**, not against the source library's actual category dropdown
contents (which, per §5, were never transcribed) — so "no duplicate of
a source exercise" cannot be fully confirmed, only "no duplicate of an
existing catalog exercise."

## 8. Provenance of the 5 promoted exercises

`bulgarianSplitSquat`, `conventionalDeadlift`, `seatedLegCurl`,
`seatedCalfRaise`, `pullUp` all already existed in `ExerciseCatalog`
(part of the pre-Stage-10C.1 31) and were already slot-capable
(`SubstitutionValidator`-compatible) but were never added to
`SeedAnnualPlanJourney.strengthCandidates` before Stage 10C.1.

**Classification: incomplete ingestion, not deliberate policy.** No
document in this repository (`PROGRAM_LOGIC_SPEC.md`,
`STAGE10A_PROGRAMMING_ENGINE_AUDIT.md`, or any earlier Stage doc) states
a reason these 5 were excluded from the candidate pool while their
catalog-mates were included. The most direct evidence: `SeedAnnualPlan
Journey.swift`'s own doc comment for the Stage 10C.1 block explicitly
frames the promotion as "already existed in the catalog, already
slot-capable, just never curated into a real candidate pool before" —
i.e., an acknowledged gap being closed, not a reversal of a deliberate
earlier exclusion. This is consistent with `strengthCandidates` having
been assembled incrementally, stage by stage, as specific slot gaps were
noticed, rather than derived once from a complete accounting of
catalog-vs-candidate-pool coverage.

## 9. `SeedAnnualPlanJourney.strengthCandidates` — what it actually is

Traced directly this pass (`SeedAnnualPlanJourney.swift`, full read).
It is a **hardcoded Swift array literal**, built inline inside the
seed-journey function, passed as one field
(`strengthCandidateExercises`) of a `TacticalMaterializationContext`
value, which is threaded through `StartPhaseUseCase.start`/
`TransitionPhaseUseCase.transition` into whatever generator/materializer
those use cases call. It is **not** a persisted model, not a
product-owner-curated table, and not derived from any source-program
category.

**What it actually is:** seed-demo infrastructure that has become the
**only real candidate-pool wiring anywhere in the app** — confirmed no
separate interactive onboarding UI or persisted candidate-pool entity
exists (no other call site constructs a `TacticalMaterializationContext`
with a different `strengthCandidateExercises` value; this was not
separately re-grepped exhaustively this pass, but no such call site
surfaced across the earlier session's extensive tracing, and none of
the read production/test files this pass touched constructed one
independently).

**This is a real architectural risk, not yet fully confirmed as an
active bug:** since first-launch seeding is the app's only executed
path to a populated candidate pool, and no separate "real" onboarding
flow exists to supply a user-specific or program-specific candidate
list, `strengthCandidates`' curation choices (which 23 of the 37 catalog
exercises are even reachable by slot resolution in practice) are
currently doing double duty as both "demo fixture" and "the actual
production candidate source." Recommendation for a future slice (not
this stage): give this list an explicit, separately-named, non-seed
home (e.g. a `DefaultStrengthCandidatePool` value type) so its role stops
being ambiguous between demo-data and production-source-of-truth.

## 10. Ingestion pipeline trace per modality

| Modality | Source → Domain path | Classification | Evidence |
|---|---|---|---|
| Hypertrophy (Family A) | Excel formulas → `PROGRAM_LOGIC_SPEC.md` rule-ID analysis → `StrengthProgressionRules`/`StrengthProgressionEngine` (load/set/rep math) — **but** category/day structure → **never transcribed, never implemented**; `HypertrophyProgramGenerator` instead hand-authors a fixed 2-slot-per-day shape | **Partially imported.** Progression math: faithfully imported. Session content/structure: abstracted into a generator placeholder that was never reconciled against the recovered source structure | `PROGRAM_LOGIC_SPEC.md` §2, `STAGE10A_PROGRAMMING_ENGINE_AUDIT.md` §4 |
| Strength/Powerlifting (Family B) | Excel formulas → `PROGRAM_LOGIC_SPEC.md` §3 → `StrengthProgressionRules` (shared engine, different parameters) | Believed faithfully imported for progression math; session/category structure not re-verified this pass — flag for a dedicated Family B/C pass (§13) | `PROGRAM_LOGIC_SPEC.md` §3, Stage 4B implementation-update note at the bottom of that file |
| Powerlifting Hypertrophy-block (Family C) | Same lineage as B | Same caveat as B | `PROGRAM_LOGIC_SPEC.md` §4 |
| Functional Fitness | Web research (CrossFit's own published programming methodology) → `PROGRAMMING_SOURCES.md` §4, explicitly classified per-row as SOURCE-DERIVED/TRAININGOS-INTERPRETATION/TRAININGOS-DESIGNED | Not from the Excel library at all — separate, self-declared provenance, already honestly labeled | `PROGRAMMING_SOURCES.md` §4 |
| Running | NHS "Couch to 5K" → `PROGRAMMING_SOURCES.md` §1 | Not from the Excel library — separate, self-declared provenance | `PROGRAMMING_SOURCES.md` §1 |
| Aerobic/Cycling | British Cycling structured plans → `PROGRAMMING_SOURCES.md` §2 | Same | `PROGRAMMING_SOURCES.md` §2 |
| VO2max/Interval | Helgerud et al. 2007 → `PROGRAMMING_SOURCES.md` §3 | Same | `PROGRAMMING_SOURCES.md` §3 |

`PROGRAM_LOGIC_SPEC.md`'s own "Stage 4A implementation update" and
"Stage 4B implementation update" sections (its final two sections,
lines 477-514) explicitly confirm: `StrengthProgressionEngine`/
`SourceCompatibleDeloadStrategy` were Xcode-validated against real
fixtures for **every progression/deload rule type** documented for
Families A/B/C. This pass re-read `StrengthProgressionEngine.swift` in
full and confirms its `resolveWeight`/`resolveSetCount`/`resolveRepGoal`
functions structurally match every formula quoted in §3 above
(`rmBased` with `weekOneFactor`/`laterWeekMultipliers`,
`linkedToPairedSlot` fraction, `autoregulated` with
`freezeAfterWeek`/`applyRatingOnFinalWeek` flags matching B3/B4 exactly).
**The progression-math ingestion is genuinely faithful and well-tested.**
The gap is entirely upstream of it, at the content/category-selection
layer feeding `PrescriptionTemplate`s into that engine.

## 11. Family A full audit + Family A current implementation trace

**Source (recovered):** 11 workbooks, 3-6 days/week, 4 splits
(full_body/legs/arms_shoulders/back_chest), 3 phases per workbook
(Basic Hypertrophy/Metabolite Focus/Resensitization), 23-30
exercise-slots/week depending on day-count, category-based exercise
selection (open dropdown + free text), the progression/deload/
autoregulation formulas in §3.

**Current implementation (`HypertrophyProgramGenerator.generate()`,
traced directly this pass and independently in `STAGE10A_PROGRAMMING_
ENGINE_AUDIT.md` §4):** every day of every configuration gets exactly
2 `PrescriptionTemplate`s — one "primary" slot whose target depends
**only** on `configuration.split` (never on which day of the week it
is), and one "paired accessory" slot that is **always** "Chest
Isolation or Triceps," **regardless of split**. `dayIndex` is a
parameter of `primarySlotName`/`primaryTargets` that is never actually
read inside their switch statements (confirmed independently by this
pass's own re-read of the Stage 10A audit's line-cited claim). The
observed "3×3@0RIR, same 2 exercises every day" behavior the product
owner originally flagged is **not** a corrupted extraction of one
unusual source program — it is a **generator design decision made at
Stage 4A/4B time**, one that never attempted to encode per-day category
rotation at all, for **any** Family A file, because the generator's
own doc comment states "no source workbook survives in this
repository" — a claim that is **materially misleading**: the workbook
*binary* doesn't survive, but the workbook's **recovered category/
day-count/slot-count structure** (§2.3-2.4 of `PROGRAM_LOGIC_SPEC.md`)
absolutely does survive, in detail, and was simply never read back into
the generator when it was built.

**Root cause, stated plainly:** Family A's *load math* was implemented
faithfully from the recovered analysis (§10). Family A's *session
content* was never implemented from that same recovered analysis — it
was implemented as an intentionally-scoped placeholder, honestly labeled
as such at the time (`STAGE4_IMPLEMENTATION_REPORT.md`'s own framing,
not re-read verbatim this pass but consistent with the generator's doc
comment and the Stage 10A audit's characterization of it as a
"self-documented Stage 4 placeholder"). The placeholder was never
revisited against the recovered source before Stage 10B/10B.6/10C.1
began building **new, invented** richer-session content on top of it.

## 12. Hypertrophy: source vs. legacy (Family A generator) vs. Stage 10B.6 V2

| Feature | Source (Family A) | Current Legacy (`generateLegacyFixedPair`) | Stage 10B.6 V2 (`generateDayFocusDriven`, 3-Day Full Body only) | Classification |
|---|---|---|---|---|
| Exercises/day | 6-7 (4-day) down to 5 (6-day), varying by category per day | 2, fixed, identical every day | More than 2 (day-focus-driven, richer), but content invented, not sourced from §2.3-2.4's categories | **REWORK-TO-MATCH-SOURCE** — V2's day-focus structure is the right *shape* of fix but the wrong *content source* |
| Muscle-group rotation across the week | Real, category-driven, varies by split | None — same 2 targets every day, every split | Yes — a real per-day rotation exists, but it's TrainingOS-invented (Stage 10A's own approved "closed, TRAININGOS-DESIGNED per-split day rotation," never claimed to be source-derived) | **KEEP-BUT-DO-NOT-PRESENT-AS-SOURCE-FIDELITY** — legitimate TrainingOS orchestration/execution intelligence (Layer 2/3) if honestly labeled as such, not Layer 1 |
| Load progression (0.85/1.05/1.075/1.1) | Yes, exact | Yes, exact (`StrengthProgressionEngine`) | Not used for the V2 3-Day config's `.doubleProgression` slots — routed to a different engine entirely | **KEEP-generic-infrastructure** for legacy; V2's substitution of a different mechanism is the crux of §4's audit |
| Set autoregulation (rating → set count) | Yes, paired-slot, per-family shape | Yes, exact (`autoregulatedSetCount`) | Not consumed by V2's `.doubleProgression` slots | **KEEP-generic-infrastructure** |
| Deload (weight/rep asymmetry by day position) | Yes, per-family shape | Yes, via `SourceCompatibleDeloadStrategy` | **Confirmed by direct code read this pass: does NOT apply.** `StrengthMaterializer`'s `.doubleProgression` branch resolves deload through `HypertrophyV2ProgressionEngine`'s own logic; `SourceCompatibleDeloadStrategy` is never invoked for this configuration | **REWORK** for configuration #1 specifically; **KEEP-generic-infrastructure** for every other configuration, which still calls `SourceCompatibleDeloadStrategy` correctly |
| Load progression trigger | Calendar-only (fixed week index) | Calendar-only, matches source | **Performance-qualified** (`DoubleProgressionEngine`: RIR-surplus≥2 or rep-ceiling hit, ≤10% cap, 2-consecutive-miss regression) — **confirmed by direct code read this pass to be the ONLY path for this config; `.rmBased` is never reached** | **REWORK** — this is the approved load-bias preference's intended *lever*, but it has been wired as configuration #1's sole progression mechanism, not an optional overlay on top of `StrengthProgressionEngine`'s intact sourced path. Needs rewiring per §16 Slice 10R.1/10R.4, not merely "keeping as-is if positioned correctly" — it is currently NOT positioned correctly |
| Rep-range model | Fixed schedule per week (`3/fail`→`1/fail`) | Matches source (`repGoalSchedule`) | A rep-range ceiling/floor model (new to V2) | **REWORK** — confirmed by direct code read (V2's `RepGoal` rows never set `toFailure`; there is no fallback to Family A's fixed schedule) that this has fully replaced, not supplemented, the source's schedule for configuration #1 |
| Calibration/deload-reachability | Not modeled in source explicitly beyond fixed schedule | N/A | Stage 10B.6-specific addition | **KEEP-TRAININGOS-EXECUTION-INTELLIGENCE**, provided it doesn't override source rep/load targets when a program IS a faithfully-sourced Family A instance |
| Custom 5-Day design (`STAGE10C2_5DAY_HYPERTROPHY_PROGRAM_DESIGN.md`) | N/A — no such source program was ever supplied under this name | N/A | Never implemented; design-only, never committed | **DEPRECATE** — this document's entire premise (TrainingOS inventing a new named 5-day program from scratch) directly contradicts the product owner's Phase-9 correction. It should not be revived. It need not be deleted (it documents real design reasoning that might inform *other* work), but it must never become production code as written. |

**Direct answer to the "is Family A generically 3×3@0RIR" question:**
No single source workbook is "corrupted" here — every Family A workbook
genuinely uses the sets/rep-goal/RIR shape §3 describes (3 sets
compound / 2 isolation / 6 calves at Week 1, `X/fail` rep goals). The
**day-count and exercise-variety collapse** is a **TrainingOS
implementation gap**, not a source-fidelity problem and not "one
unusual source program elevated to generic authority" — every Family A
file would have produced the same 2-slot-per-day collapse if it had been
the one chosen, because the collapse lives in the **generator**, not in
any one file's data.

## 13. Strength (Family B) — source vs. current, this pass

Family B's progression math (§3) is structurally identical in shape to
Family A's — same `rmBased`/`autoregulated` rule types, different
parameters, per `StrengthProgressionEngine`'s own doc comment ("Shared
by every `StrengthProgressionRules`-based family"). This pass confirmed
the engine code supports Family B's specific shapes (`freezeAfterWeek`,
`applyRatingOnFinalWeek` flags exist and match B3/B4 exactly). **Not
independently re-verified this pass:** whether the "4-Day Powerlifting
Strength" built-in configuration's actual `ProgramDefinition` content
(which specific exercises/categories, session-day layout) faithfully
reflects Family B's Legs×2/Push×2/Deadlift/Hamstring/Upper-Pull×2/
Shoulder×2 category structure, or whether it suffers a content-collapse
similar to Family A's. This is flagged as an open item for a dedicated
follow-up (not scoped into this pass given the size of the Hypertrophy
findings alone) — **do not assume Family B/C are faithful just because
their progression engine is shared and tested; the same content-vs-math
split found in Family A could recur here and was not ruled out.**

## 14. Powerlifting (Family C) — source vs. current, this pass

Same caveat as §13: progression-math faithfulness is architecturally
plausible (shared engine, B4's Week-4 freeze flag exists and is
described as matching this family exactly) but the **actual shipped
session content** for "5-Day Powerlifting Hypertrophy" was not
independently re-traced this pass. Flagged as an open item, same
priority as §13.

## 15. Functional Fitness provenance

Confirmed via `PROGRAMMING_SOURCES.md` §4: sourced from CrossFit's own
published programming methodology ("Programming Basics Part 1/2," the
2003 "Theoretical Template," and CrossFit's own essentials pages),
verified via search-snippet extraction (not a direct fetch — explicitly
flagged as one level removed from primary-source verification in that
document's own research-method note). Explicit SOURCE-DERIVED items:
the three-modality vocabulary (metcon/gymnastics/weightlifting), the
stimulus-then-format-then-analyze structure, "planned variance, not
randomness." Explicit TRAININGOS-DESIGNED items: no random-WOD
generator (aligned with, not contradicting, the source), the specific
`FunctionalFitnessProgrammingSystem` five-stage pipeline and stimulus
value-object field list (a structured **interpretation** of the source's
conceptual distinction, not a table CrossFit itself publishes). This is
**not** part of the original 15-workbook Excel library and was never
claimed to be — its provenance is already honestly self-documented; no
redesign is indicated or being proposed here.

## 16. Running provenance

Confirmed via `PROGRAMMING_SOURCES.md` §1: sourced from the NHS "Couch
to 5K" plan (9-week duration, 3 sessions/week, week-by-week walk/run
structure), same verification caveat (snippet-extracted, not directly
fetched). Explicitly **not** part of the Excel library. No redesign
indicated or being proposed here.

## 17. Classification of all recent Stage 10 work

| Component | Classification | Rationale |
|---|---|---|
| `SlotRole` (primary/secondary/accessory) | **KEEP-GENERIC-INFRASTRUCTURE** | A role concept is needed regardless of whether session content ends up source-faithful or TrainingOS-designed; doesn't itself encode any specific program's content |
| Richer Day A/B/C day-focus structure (Stage 10B) | **REWORK** | Right shape (per-day variety), wrong content source (invented rotation instead of recovered §2.3-2.4 categories) |
| Custom 5-Day program design (Stage 10C.2) | **DEPRECATE-LATER** (do not implement as written; keep the document as design-reasoning reference only) | Directly the kind of invented program the product owner's correction rejects |
| Rep-range model (min/max reps, not fixed X/fail schedule) | **KEEP-BUT-REMOVE-FROM-PROGRAM-AUTHORITY for Family-A-sourced programs**, pending confirmation it doesn't silently override the source's fixed weekly schedule | Needs direct code check not completed this pass (§12) |
| RIR model | **KEEP-GENERIC-INFRASTRUCTURE** | RIR is already how the source itself expresses effort ("X/fail" ≈ RIR-X); a typed RIR field is a faithful *representation* improvement, not a content replacement |
| Performance-qualified progression (`DoubleProgressionEngine`) | **REWORK (rewire as an optional overlay); the underlying engine itself is KEEP-generic-infrastructure** | Confirmed by direct code read (not merely flagged): configuration #1's `.doubleProgression` path has fully replaced `StrengthProgressionEngine`'s calendar-based path, not added to it — `.rmBased` is provably unreachable for this config. The engine's own decision logic (performance-qualified load increase) is sound and worth keeping; it must be rewired to gate an addition on top of the sourced schedule, not stand alone as the config's only progression mechanism |
| `DoubleProgressionHistoryResolver` | **KEEP-GENERIC-INFRASTRUCTURE** | Exercise-specific history lookup is reusable infrastructure regardless of which progression lever consumes it |
| Local set autoregulation / feedback attribution | **KEEP-GENERIC-INFRASTRUCTURE** | Generalizes the source's own paired-slot rating mechanism; doesn't replace it |
| Calibration / deload reachability | **KEEP-TRAININGOS-EXECUTION-INTELLIGENCE** | Layer 3 concern (today's execution), doesn't touch Layer 1 content, provided it never silently overrides a source program's own deload week |
| Catalog expansion (31→37 exercises) | **KEEP-GENERIC-INFRASTRUCTURE** | More slot-fillable exercises are useful regardless of which program structure eventually consumes them; the *process* that added them (§6) should change going forward, not the exercises themselves |
| `ExerciseAlias` | **KEEP-GENERIC-INFRASTRUCTURE** | Canonical-ID stability (CLAUDE.md rule 6) is required regardless of program source |
| `ExerciseRelationship` | **KEEP-GENERIC-INFRASTRUCTURE** | Substitution/relatedness metadata is exactly what's needed to faithfully substitute *within* a source program's exercise category, not a replacement for that category |
| `EquipmentRequirement` | **KEEP-GENERIC-INFRASTRUCTURE (future Home Gym)** | Explicitly named as needed future infrastructure in the product owner's own Home Gym contract (§5 of the Constitution) |
| Movement-function semantics, lateralDelt/rearDelt, horizontal/vertical pull split | **KEEP-GENERIC-INFRASTRUCTURE** | Directly useful for correctly resolving a source program's dual-tagged categories (A6) once that content is actually implemented — this is exactly "supports the source," not "replaces it" |
| Readiness integration | **KEEP-TRAININGOS-EXECUTION-INTELLIGENCE** | Matches the Readiness Contract (Constitution §6) as designed |
| Warm-up integration | **KEEP-TRAININGOS-EXECUTION-INTELLIGENCE** | Matches the Warm-up Contract (Constitution §7) as designed |
| Substitution semantics (`SubstitutionValidator`) | **KEEP-GENERIC-INFRASTRUCTURE** | Matches the Substitution Contract (Constitution §4) as designed — any-overlap matching on typed targets/movement-functions is a faithful mechanism for "preserve stimulus, allow genuine unavailability substitution" |

**No component audited here needs to be deleted.** Every one is either
already-correct generic infrastructure, or a reasonable mechanism
(day-focus rotation, performance-qualified progression) that needs its
**content source** corrected, not its **existence** rejected.

## 18. Proposed source-of-truth architecture

```
Authoritative Program Source (recovered PROGRAM_LOGIC_SPEC.md analysis,
  or any future re-supplied source material)
  → Canonical ProgramDefinition (Layer 1 content: session/category
      structure, sets/reps/RIR, progression formulas, deload rules —
      faithfully transcribed, not invented)
  → Program Metadata (modality, frequency, goal-compatibility,
      experience-level, equipment-requirements, source-provenance —
      e.g. "Family A, e1f8fb19-4_day_full_body.xlsx")
  → Annual/Phase Planner SELECTS a Program (LongTermPlanner — Layer 2)
  → ProgramInstance (materialized, per-user)
  → TrainingOS Orchestration (concurrent scheduling, priority,
      interference, recovery, missed sessions — Layer 2)
  → TrainingOS Execution (readiness, substitutions, Home-Gym-later,
      warm-up, logging — Layer 3)
  → Source-Compatible Progression (StrengthProgressionEngine +
      optionally DoubleProgressionEngine as an approved overlay lever,
      per §4/§17)
  → Performance History
```

**Compared to what exists today:** every box below "Canonical
ProgramDefinition" already exists and is real, tested production code
(confirmed independently by this pass and by the earlier
`STAGE10A_PROGRAMMING_ENGINE_AUDIT.md` trace). The **only** missing/
broken box is "Canonical ProgramDefinition" itself for Hypertrophy —
`HypertrophyProgramGenerator` currently produces a placeholder instead
of a faithful transcription of the recovered category/day structure.
**Minimum realignment recommended:** do not build a new pipeline; fix
the one box. Concretely: give `HypertrophyProgramGenerator` (or a new,
narrowly-scoped sibling) a per-split, per-day-count **category table**
transcribed directly from `PROGRAM_LOGIC_SPEC.md` §2.3-2.4 (which
categories appear on which day, in what order, at what set-count), with
each category resolved to a concrete exercise via the existing
`SubstitutionValidator`/`ExerciseSlot.allowedTargets` mechanism exactly
as it already works today — no new resolution mechanism needed, only
new, source-derived **input data** to that mechanism.

## 19. "TrainingOS MAY" vs. "TrainingOS SHOULD NOT AUTOMATICALLY"

**TrainingOS MAY, without further approval, because these are Layer
2/3 by definition:**
- Select which authoritative program(s) anchor a phase, given goal/
  frequency/preference inputs.
- Schedule/place sessions on the calendar, manage spacing/interference
  across concurrent modalities.
- Substitute one exercise for another **within the same category/
  role/intent** the source program already defines for that slot.
- Reduce/postpone/modify **today's** execution for readiness reasons.
- Generate a warm-up from the actual selected workout.
- Add an **optional, clearly-labeled** performance-qualified load-bias
  overlay on top of a source program's own progression, provided the
  source's own progression path still exists and still runs when the
  overlay's gating condition isn't met.

**TrainingOS SHOULD NOT, without an explicit new product decision:**
- Invent a new named program (any day-count, any split) not traceable
  to a recovered source category structure or an explicit future
  re-supply of source material.
- Replace a source program's fixed rep-goal/set-autoregulation/deload
  schedule with a different mechanism, even a "better" one, for a
  program whose provenance is a specific source workbook.
- Let a "richer session" initiative add exercises/days/categories that
  aren't traceable to that program's own recovered structure.
- Silently expand which exercises satisfy a slot beyond what the
  source category's evident intent (or an explicit, reviewed
  substitution contract) allows.
- Let Layer 3 adaptation (readiness/warm-up/Home-Gym) change what
  Layer 1 content the user is nominally on, beyond today's single
  session.

## 20. Can the planner actually select between authored source programs today?

**No — it selects generated configurations, not source programs, and
this is worth stating plainly.** `LongTermPlanner.proposeTrainingMix`/
`closestByDayCount` selects among `HypertrophyBuiltInLibrary.all`'s 6
entries by day-count proximity — each entry is a `{name, dayCount,
split}` triple that, via `HypertrophyProgramGenerator`, currently
produces the **same generic 2-slot content regardless of which source
workbook it's nominally named after** (§11/§12). So today, "select an
appropriate 3-day Hypertrophy program" **does** route to the correctly-
named configuration (e.g. "3-Day Full Body Hypertrophy," which does
trace to `4847f523-3_day_full_body_Novice.xlsx`), but what actually gets
materialized is generic content, not that workbook's real structure —
the **selection** layer is sound; the **content behind the selection**
is the gap this document is about. This was not changed this pass; §18
proposes the fix.

## 21. Future architecture for concurrent training — flagged, not designed

Confirmed already-existing infrastructure this pass did not need to
re-derive: `ConcurrentScheduler`'s modality-blind placement (spacing,
`allowsDoubleSessionPairing`, `InterferenceAvoidanceRule
.conservativeDefault` gated on `lowerBodyLoad`/`impactLoading`
reaching `.high` — `PROGRAMMING_SOURCES.md` §5/Stage 4F note). What is
**not** yet designed, and is explicitly flagged as a **major future
stage after source-program recovery**, not scoped into this audit: an
anchor-modality/supporting-modality model where a Hypertrophy program
selected as a phase's anchor retains its own progression fidelity while
Functional Fitness/Running sessions are explicitly reduced/placed around
it (missed-session recovery, fatigue-aware supporting-volume reduction,
maintaining the anchor's own progression across a missed week). No
design work for this was performed in this stage — it is out of scope
per the stop condition, and depends on §18's content-recovery fix
landing first (there is little value designing anchor/supporting
interaction around Hypertrophy content that isn't yet faithful to any
real anchor program).

## 22. This is not "revert everything" — restated

Per §17, the overwhelming majority of Stage 10's infrastructure (slot
roles, RIR typing, exercise semantics, equipment typing, readiness,
warm-up, performance history, autoregulation/history-resolution
plumbing) is exactly the kind of generic execution/orchestration
intelligence the product needs to faithfully **express** the recovered
source programs once §18's content fix lands. The corrective action
this stage recommends is narrow: stop inventing new program **content**
(day rotations, a custom 5-Day design), and instead feed the *existing*
generation mechanism with the *already-recovered* source structure. This
is explicitly a "repurpose the generic infrastructure to serve the
source, don't rebuild it" outcome, not a rewrite.

## 23. Minimum recovery plan (slices, not a rewrite)

**Slice 1 — Reconnect source category structure into `HypertrophyProgram
Generator` for the one currently-richened config (3-Day Full Body).**
Purpose: make the single production path that already has richer-session
work (Stage 10B.6's V2) trace to `PROGRAM_LOGIC_SPEC.md`'s actual
recovered category list for that workbook (`4847f523-3_day_full_body_
Novice.xlsx`) instead of an invented rotation. Files/types affected:
`HypertrophyProgramGenerator.swift` (its day-focus table), possibly a
new small data file for the category table itself. Production behavior
changed: the 3-Day config's day-to-day exercise/category selection.
Source-program behavior restored: real per-day category variety
matching the actual workbook. Tests required: new fixtures asserting
the category sequence per day matches the recovered structure; existing
`HypertrophyDayFocusGenerationTests`/`HypertrophyBuiltInLibraryTests`
will need deliberate, reviewed updates (flagged, not silently changed).
Manual acceptance required: yes, Simulator walkthrough of a fresh 3-Day
program comparing against the recovered category table.

**Slice 2 — Extend the same reconnection to the other 5 shipped
Hypertrophy configurations** (4/5/6-Day Full Body, 5-Day Upper/Arms,
4-Day Lower/Leg), each against its own cited workbook. Purpose/behavior/
tests: same shape as Slice 1, one config at a time, each independently
acceptable — the same incremental discipline already used for Stage
8B/9B. The 4-Day Legs config specifically should restore the
`FAMILY_A_LEGS_HEAVY_EXCEPTION` override, currently unreachable.

**Slice 3 — Audit Family B/C content fidelity** (this pass's §13/§14
open item): trace whether "4-Day Powerlifting Strength"/"5-Day
Powerlifting Hypertrophy" suffer the same content-collapse as
Hypertrophy did, before assuming they're fine just because their
progression engine is shared.

**Slice 4 — Reposition `DoubleProgressionEngine` explicitly as an
optional overlay lever** (§4/§12/§17's open concern), with an explicit
product decision on exactly which condition gates it and confirmation
that Family-A-sourced programs still have a working, intact
calendar-based fallback path when the overlay's condition isn't met.

**Slice 5 — Disable or clearly quarantine `STAGE10C2_5DAY_HYPERTROPHY_
PROGRAM_DESIGN.md`'s premise** from ever becoming a shipped
configuration; no code change needed since it was never implemented —
this is a documentation/process action (e.g. a header note on that file
marking it superseded-by-product-direction), not a deletion.

**Slice 6 — Give `strengthCandidates` (§9) an explicit, non-seed home**,
so the only real candidate-pool wiring in the app stops being ambiguous
between "demo fixture" and "production source of truth."

None of these slices require deleting or rebuilding a working system;
every one re-points an existing mechanism at already-recovered source
data, or narrows an already-built lever's scope.

## 24. Deliverables

This document and `TRAININGOS_PRODUCT_CONSTITUTION.md` are both written
to `app/`, both currently uncommitted, per the explicit stop condition.

---

# Final 18-item report

1. **How many original programs were supplied, by modality:** 15 Excel
   workbooks total — 11 Hypertrophy (Family A), 1 Powerlifting Strength
   (Family B), 1 Powerlifting Hypertrophy-block (Family C), plus 2
   user-customized derivatives (Family D, evidence-only, never shipped).
   Backed by 3 PDFs (2 for Family C, 1 for Family B; none for Family A).
2. **Which original programs still exist faithfully in TrainingOS:**
   None are fully faithful in session content. **5 of the 6** shipped
   Hypertrophy configurations (all except 3-Day Full Body) and both
   shipped Powerlifting configurations are faithful in their
   **progression/deload/autoregulation math** (Xcode-validated against
   real fixtures at Stage 4A/4B, and confirmed by direct code re-read
   this pass to still route through `StrengthProgressionEngine`/
   `SourceCompatibleDeloadStrategy` unmodified). **The 3-Day Full Body
   configuration is faithful in NEITHER session content NOR progression
   math** — its entire load/rep/RIR/deload rule vocabulary was replaced
   by Stage 10B.6's `DoubleProgressionEngine` path, confirmed by direct
   code read (§4, §12) to have no fallback to the sourced engine at all.
   This is the single most severe finding in this document: it is the
   one configuration where TrainingOS-invented rules are running in
   place of, not alongside, a real, named, sourced program.
3. **Which are partially represented or lost:** 10 of the 11 Family A
   workbooks are partially represented (math yes, content no); the
   3-Day Full Body workbook is the one exception — **math no** (fully
   replaced by Stage 10B.6, confirmed by code, not merely content-thin
   like the rest) **and content no** (day-focus content is real but
   TrainingOS-invented, not sourced from §2.3-2.4's recovered
   categories). The 6 Family A workbooks never chosen as a shipped
   configuration exist only as unconsumed "generator parameter space."
   Family B/C's content-fidelity was not independently re-verified this
   pass (flagged, not resolved) but their progression math was
   confirmed unchanged. Family D was never shipped, by design, and is
   evidence-only. Nothing is "lost" in the git-history sense — nothing
   was deleted; the content was simply never implemented from the
   analysis that recovered it, and for the 3-Day config specifically,
   an already-working sourced implementation was later replaced.
4. **How many unique exercises existed across the original supplied
   programs:** Not a fixed number — the source uses open category
   dropdowns plus free-text "Other" entries, not a finite named list.
   Reporting a specific count would be inventing precision the source
   doesn't have.
5. **Why the current Exercise catalog/`strengthCandidates` became much
   smaller than the source-program exercise universe:** Because the
   source universe is open-ended (see #4) and TrainingOS's catalog
   (37 exercises, 23 curated candidates) was built incrementally by
   Stage 1→10C.1 to fill specific slot-resolution gaps as they were
   noticed — not derived from, or reconciled against, the source's
   actual category list at any point.
6. **Whether Stage 10C.1 accidentally duplicated any original
   exercises:** No duplicate of an *existing catalog* exercise was
   found (confirmed via direct re-read of `CatalogSemanticFoundation
   Tests.swift`'s own regression coverage). Duplication against the
   *source's own* category dropdown contents cannot be fully ruled out,
   because that dropdown content was never transcribed into any
   surviving document.
7. **What `strengthCandidates` actually is, and whether it's become an
   inappropriate source of truth:** A hardcoded Swift array inside
   `SeedAnnualPlanJourney`, originally seed/demo infrastructure, that
   has become the **only real candidate-pool wiring in the app** because
   no separate onboarding/production candidate-pool mechanism exists.
   This is a real architectural risk (not yet confirmed as an active
   bug) — recommended fix is Slice 6 (§23), giving it an explicit
   non-seed home.
8. **The exact original progression formulas, especially for
   Hypertrophy:** Recovered and quoted verbatim in §3, with exact cell
   citations (e.g. `J11: '=MROUND(((G11)*0.85),2.5)'`).
9. **How source progression differs from Family A (legacy generator)
   and Stage 10B.6 V2:** The legacy generator's `StrengthProgression
   Engine` matches source progression math exactly (confirmed by direct
   code comparison this pass). Stage 10B.6 V2's `DoubleProgressionEngine`
   introduces a genuinely new lever (performance-qualified load
   increase) that the source never has — this is the approved load-bias
   preference in spirit, but **confirmed by direct code read (not an open
   item) to be wired as a full replacement of Family A's load rule, rep
   schedule, RIR philosophy, AND deload mechanism for the 3-Day config**,
   with no fallback path to the sourced engine at all.
10. **How to preserve the load-first progression preference while
    remaining faithful to source-program philosophy:** Keep
    `StrengthProgressionEngine`'s calendar-based path as the default/
    fallback for source-derived programs; gate `DoubleProgressionEngine`
    as an explicit, narrow overlay that only fires on a clear
    over-performance signal, never as the sole progression mechanism
    for a Family-A-sourced program (§4, §23 Slice 4) — this requires
    active rework of configuration #1's current wiring, not just a
    confirmation check, since the replacement is already confirmed to
    have happened.
11. **Which Stage 10 components should be kept unchanged:** `SlotRole`,
    RIR typing, `ExerciseAlias`/`ExerciseRelationship`,
    `EquipmentRequirement`, movement-function semantics
    (lateral/rear-delt, horizontal/vertical pull-push splits),
    readiness integration, warm-up integration, substitution semantics,
    `DoubleProgressionHistoryResolver`, autoregulation/feedback
    plumbing — all classified KEEP in §17.
12. **Which should be repurposed as generic infrastructure:** The day-
    focus/`SlotRole`-driven N-slot generation mechanism itself (the
    *shape* of Stage 10B's fix) — repurpose it to be fed by recovered
    source category tables instead of an invented rotation (§18, §23
    Slice 1-2).
13. **Which conflict with the clarified product intent:** The invented
    per-split day-rotation content (not the mechanism, the content), and
    the entire premise of `STAGE10C2_5DAY_HYPERTROPHY_PROGRAM_DESIGN.md`
    (a wholly TrainingOS-invented named program) — both classified
    REWORK/DEPRECATE in §17.
14. **Provenance/status of Functional Fitness programming:** Sourced
    from CrossFit's own published methodology, already honestly
    self-labeled SOURCE-DERIVED/INTERPRETATION/DESIGNED in
    `PROGRAMMING_SOURCES.md` §4. Not part of the Excel library, never
    claimed to be. No redesign needed or proposed.
15. **Provenance/status of Running programming:** Sourced from NHS
    Couch to 5K, same honest self-labeling in `PROGRAMMING_SOURCES.md`
    §1. Not part of the Excel library. No redesign needed or proposed.
16. **The correct architecture going forward:** Unchanged from top to
    bottom except one box — see §18's diagram. Every layer from
    `ProgramInstance` down through execution/progression/history is
    already real and correct; only "Canonical `ProgramDefinition`" for
    Hypertrophy needs its content source corrected.
17. **The minimum recovery plan required, without throwing away good
    infrastructure:** Six slices (§23) — reconnect source category
    structure for the 3-Day config first, then the other 5; audit
    Family B/C content fidelity; reposition the load-bias overlay
    explicitly; quarantine the 5-Day custom design; give
    `strengthCandidates` a non-seed home. No deletion or rebuild of any
    working system.
18. **Decisions needed from the user before implementation:**
    - Approve Slice 1 (reconnect the 3-Day Full Body config to its
      real recovered category structure) as the next implementation
      stage, or reorder/rescope the six slices.
    - Confirm whether `DoubleProgressionEngine` should be rewired as an
      explicit opt-in overlay now, or left as-is pending Slice 3/4's
      Family B/C findings first.
    - Confirm the disposition of `STAGE10C2_5DAY_HYPERTROPHY_PROGRAM_
      DESIGN.md` (quarantine-with-header-note vs. delete vs. leave
      untouched).
    - Confirm whether Family B/C's content-fidelity audit (§13/§14,
      genuinely not yet done) should be the very next investigation
      stage, before any Hypertrophy implementation slice begins.

**This stage stops here for approval. No further implementation,
commit, or push will happen without explicit direction.**
