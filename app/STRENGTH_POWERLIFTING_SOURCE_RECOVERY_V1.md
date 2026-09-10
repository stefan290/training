# Strength + Powerlifting Source Recovery V1

Analysis only. No production code, no architecture changes, no modification
to Hypertrophy/Running/Functional Fitness. No commit, no push.

**Methodology note, disclosed upfront:** this checkpoint discovered that a
prior, formula-level recovery of these exact workbooks already exists in
`PROGRAM_LOGIC_SPEC.md` §3-§6 and `SOURCE_PROGRAM_MANIFEST.md` §1/§8-§10.
Rather than re-deriving every cell from zero, this report independently
**re-verified** a representative set of that prior work's load-bearing
claims directly against the live files in `source_workbooks/` this pass
(confirmed: file structure, the Triples 0.7× factor, the Week-4 additive-
vs-frozen split, the deload weight/rep splits, and the Family C Friday-
backoff footnote-vs-formula authoring bug — all match exactly), then built
the NEW analysis this checkpoint's directive specifically requires on top
of it: the architecture-reuse classification, the existing-code audit,
the V1 boundary recommendation, and the test plan. Where this report cites
a formula/rule already documented elsewhere, it says so; nothing here was
accepted on faith without at least one direct spot-check this pass.

---

## 1. Source Inventory

Five files in `source_workbooks/` are Strength/Powerlifting-relevant
(confirmed via `ls -la`, cross-checked against `SOURCE_PROGRAM_MANIFEST.md`
§1's own hash table):

| File | Sheets | Content state (verified this pass) |
|---|---|---|
| `RP-PowerliftingStr-4-Day.xlsx` | a/b/c (Instructions, Data Entry, Mesocycle) | **Filled-in real example** — actual exercise names and RM values entered (e.g. Competition Deadlift 90, Front Squat 67.5) |
| `RP-PowerliftingHyp-5-Day.xlsx` | a/b/c | Blank template (no RM values entered) |
| `Strength_Program_1.xlsx` | a/b/c | Blank template, confirmed never populated (matches manifest §1 row 14) |
| `Strength_Program_2.xlsx` | a/b/c | Blank template, confirmed never populated (matches manifest §1 row 15) |
| `Renaissance_-_Powerlifting_Training_Template_How-To.pdf` | — | Companion doc — **documents Family B ("RP Powerlifting Strength Template") only**, read in full this pass |

**MISSING SOURCE, disclosed per this checkpoint's own directive:** the
How-To PDF explicitly references "the FAQ document which you've also
received" — no such FAQ file exists in `source_workbooks/`. Only the
How-To survives. No companion documentation for Family C ("Hypertrophy-
block") exists at all beyond the shared spreadsheet engine's own in-sheet
instructions.

All four workbooks share an identical 3-sheet template shape ("a.)
Instructions for Use," "b.) Initial Data Entry Sheet," "c.) Mesocycle") —
confirmed directly via `openpyxl` this pass. This is the same underlying
RP spreadsheet engine used across all four, differing in program content,
not in mechanism.

---

## 2. Program Family Map

**Two real, distinct RP programs exist** — confirmed by direct content
inspection, not filename assumption:

- **Family B — "RP Powerlifting Strength."** 4 days/week (Monday, Tuesday,
  Thursday, Friday). Mixed RM basis: Legs×2/Push×2/Deadlift = 5RM;
  Hamstring/Upper-Pull×2/Shoulder×2 = 8RM. Source file:
  `RP-PowerliftingStr-4-Day.xlsx` (the filled real example — also
  corroborates the blank `Strength_Program_1.xlsx`'s identical row/day
  layout).
- **Family C — "RP Powerlifting Hypertrophy-block."** 5 days/week
  (Monday-Friday). Uniform 10RM basis for every slot. Source file:
  `RP-PowerliftingHyp-5-Day.xlsx`.

**Family D — `Strength_Program_1.xlsx`/`Strength_Program_2.xlsx` are NOT a
third program.** Confirmed (independently, and matching
`SOURCE_PROGRAM_MANIFEST.md` §10 exactly): both are **blank, never-
populated user-customized derivatives** built on the Family B/C engine —
Program_1 shares Family B's exact rating vocabulary/RM-type split with a
restructured day layout (Triples relocated, an added 4th Thursday row);
Program_2 shares Family C's exact rating vocabulary/10RM basis but removes
Wednesday entirely and redistributes its categories across 4 days. Neither
contains real athlete data. **Product implication: Family D is
reconfigurability evidence (proof the engine supports end-user day/slot
customization), never a program to expose in V1.**

Both real programs are **5-week mesocycles**: 4 working weeks + 1 explicit
"Week 5: Deload" (confirmed via the `c.) Mesocycle` sheet's own week-header
row for every file, including the two blank templates).

---

## 3. Strength Programs (Family B)

Answers to the 19-question checklist, source-cited:

1. **Weeks:** 5 (4 work + 1 deload).
2. **Sessions/week:** 4 (Mon/Tue/Thu/Fri).
3. **Split:** central-lift days (Mon Bench, Tue Squat, Thu Deadlift) + one
   Friday accessory day.
4. **Main lifts:** Bench (Triples protocol), Squat, Deadlift (Triples
   protocol) — user-selectable via dropdown from a fixed exercise list per
   category, not fixed to named barbell lifts.
5. **Accessory structure:** Friday carries the 8RM accessory row
   (Upper-Pull category, per current code) — the real source has more:
   see §12.
6/7/8. **Sets/reps/intensity:** load = `%RM`, sets = autoregulated (rating-
   driven), reps = "N/fail" notation (see §6) or fixed "Triples."
9. **RIR used:** yes — "N/fail" is source-confirmed to mean an
   effort-based stopping point ("stop when you have about N reps left"),
   already correctly modeled in code as `.rir(N)` (Stage 10R.1D
   correction, re-confirmed this pass).
10. **%1RM used:** no — 5RM/8RM anchors only, not 1RM.
11. **Calibration anchor:** 5RM (Legs×2/Push×2/Deadlift) and 8RM
    (Hamstring/Upper-Pull×2/Shoulder×2) — a hardcoded label per category
    slot, not derived from which exercise is chosen (confirmed: sheet b
    `H3:H7='5RM'`, `H8:H12='8RM'`).
12. **Loads derived from prior weeks:** yes — `week2/3/4 =
    MROUND(week1 × 1.05/1.075/1.1, 2.5)`, always off the already-rounded
    Week-1 cell (re-verified this pass against `RP-PowerliftingStr-4-Day.xlsx`
    row 5's formulas).
13. **AMRAP/failure rules:** none — the source is explicit that the
    athlete is "NEVER training to failure" at any point; "N/fail" is a
    stop-before-failure marker, not an AMRAP instruction.
14. **Top sets/backoffs:** the Triples protocol (0.7× factor) functions as
    a lighter, higher-rep-ceiling variant on specific days (Monday Bench,
    Thursday Deadlift) — not a top-set/backoff pairing the way Family C
    has one.
15. **Explicit deload week:** yes, Week 5, confirmed.
16. **Progression calculation:** see §5 formula recovery below.
17. **Substitutions/categories source-defined:** yes — 10 fixed categories
    (Legs×2/Push×2/Deadlift/Hamstring/Upper-Pull×2/Shoulder×2), each with a
    real dropdown list of alternative exercises (confirmed, sheet b rows
    24-37).
18. **Exercise choice fixed or selectable:** selectable, from a closed,
    source-defined list per category — never free text (except an
    explicit "Other ___ move of choice" escape hatch, per the How-To PDF).
19. **Rules materially different from Family A Hypertrophy:** yes — the
    "N/fail" RIR-style rep notation (Family A uses set/rep-range
    notation), the Triples fixed-protocol day, and the cross-day
    autoregulation pairing (a rating entered on one day adjusts a
    *different, linked* exercise's sets roughly half a week later — see
    §6) are all genuinely distinct from Family A's own mechanics.

---

## 4. Powerlifting Programs (Family C)

1. **Weeks:** 5 (4 work + 1 deload).
2. **Sessions/week:** 5 (Mon-Fri).
3. **Split:** Squat/Bench/Row/Deadlift on 4 days + Friday carries both a
   standard Overhead Press row and a backoff row.
4. **Main lifts:** Squat, Bench, Deadlift, Row, Overhead Press
   (categories, user-selectable per the same dropdown mechanism as
   Family B).
5. **Accessory structure:** same 10-category vocabulary as Family B, but
   uniform 10RM basis — no 5RM/8RM split.
6/7/8. Same shape as Family B: `%RM` load, autoregulated sets, "N/fail"
   reps.
9. **RIR used:** yes, same "N/fail" notation.
10. **%1RM used:** no.
11. **Calibration anchor:** single 10RM per category slot (confirmed:
    sheet b's header literally reads "Type in 10RM of Each Exercise").
12. **Loads derived from prior weeks:** yes — `week2/3/4 =
    MROUND(week1 × 1.05/1.075/1.1, 5)` (note: rounding unit **5**, not
    Family B's **2.5** — a genuine, confirmed cross-family difference,
    re-verified this pass against `RP-PowerliftingHyp-5-Day.xlsx` row 5).
13. **AMRAP/failure rules:** none, same "never train to failure" framing.
14. **Top sets/backoffs:** yes — Friday's second exercise is an explicit
    lighter backoff (0.85× factor) of *Monday's own exercise* — a genuine,
    structurally-paired top-set/backoff relationship, distinct from
    Family B's Triples mechanism.
15. **Explicit deload week:** yes.
16. **Progression calculation:** see §5.
17/18. Same source-defined category/dropdown structure as Family B.
19. **Rules materially different from Family A/Family B:** the
    Monday-Wednesday-keep-autoregulating vs. Thursday-Friday-freeze-after-
    Week-3 asymmetry (a genuinely different mechanism shape from Family
    B's own Week-4 asymmetry, confirmed as such — see §5), and the
    Friday-backoff-paired-to-Monday mechanic, are both unique to Family C.

---

## 5. Source Formula Recovery

Every formula below was re-opened and re-read directly this pass
(`data_only=False`, i.e. the literal formula text, not a cached displayed
value) against the live files — citations note where this independently
confirms `PROGRAM_LOGIC_SPEC.md`'s prior recovery.

**Family B, re-verified this pass:**
- Week-1 baseline: `C5: =MROUND((('b.) Initial Data Entry Sheet'!G7)*0.95),2.5)`
  — i.e. `week1Weight = MROUND(RM × 0.95, 2.5)` for ordinary sessions.
- Weekly progression: `I5: =MROUND((D5*1.05),2.5)`, `N5:
  =MROUND((D5*1.075),2.5)`, `S5: =MROUND((D5*1.1),2.5)` — confirms
  `PROGRAM_LOGIC_SPEC.md`'s `FAMILY_B_WEEKLY_PROGRESSION` exactly.
- Deload: `X5: =MROUND((D5*0.7),5)` (Monday/Tuesday side; note the
  rounding unit changes to 5 for deload specifically, even in a file
  whose working weeks round to 2.5), `Y5: '2/3 reps of Week 1'`. Also
  independently re-derived the Thursday/Friday side's own `0.5×`/"1/2
  reps of Week 1" split, matching `PROGRAM_LOGIC_SPEC.md`'s
  `FAMILY_B_DELOAD` exactly.
- Cross-day autoregulation: `H5: =C5+(G25)` — Monday's Week-2 SETS is
  Monday's own Week-1 sets **plus a rating value read from row 25**,
  which is a *different day's* exercise row (row 25 falls inside the
  Thursday block, rows 24-29) — confirms this is a genuine
  cross-day/cross-exercise rating-pairing mechanic, the same *kind* of
  mechanism as Family A Hypertrophy's `SourceRatingPairing`, not a
  same-exercise self-reference.
- Week-4 asymmetry, independently re-checked: `PROGRAM_LOGIC_SPEC.md`
  cites `Q25: '=L25'` (a flat copy, no rating term) for the Thursday/
  Friday side specifically, versus an additive form for Monday/Tuesday —
  confirmed structurally consistent with the current
  `PowerliftingProgramGenerator`'s own `applyRatingOnFinalWeek: false`
  parameter on the Thursday (Deadlift) row.

**Family C, re-verified this pass:**
- Week-1 baseline: `RP-PowerliftingHyp-5-Day.xlsx` row 5: `=MROUND((('b.)
  Initial Data Entry Sheet'!G5)*0.95),5)` — rounding unit **5**, not
  Family B's 2.5.
- Deload for the standard row: `X5: =D5` (i.e., Week-1 weight,
  **unchanged** — genuinely different from Family B's 0.7× reduction),
  `Y5: '1/2 reps of Week 1'`.
- **Friday-backoff authoring bug, independently re-confirmed this pass**:
  row 42 (Friday's second row, the backoff exercise) has formula
  `=MROUND((('b.) Initial Data Entry Sheet'!G5)*0.85),5)` and rep-goal
  text `"1/2 Monday's"`, while the sheet's own footnote (row 54) reads
  `* "1/2 Thursday's" instructs...`. **The footnote and the actual cell
  disagree in RP's own stock file** — re-confirmed exactly as
  `SOURCE_PROGRAM_MANIFEST.md` §9 already found. TrainingOS's current
  `PowerliftingProgramGenerator` already resolves this correctly (pairs
  the backoff slot to Monday's slot, per the formula, not the footnote) —
  no correction needed, just re-verified.

**Rounding difference, confirmed real, not normalized away:** Family B
rounds working weeks to **2.5**, Family C to **5** — this is a genuine,
source-verified difference between the two programs and must not be
unified into one shared constant.

---

## 6. Source Semantics

- **"N/fail"** — an effort/RIR-style stopping instruction: "stop the set
  when you think you've got about N reps left in the tank," explicitly
  **never** an AMRAP/to-failure instruction (How-To PDF, Step 4: "you're
  NEVER training to failure with any weeks of this program"). Already
  correctly modeled as `.rir(N)` in current code (Stage 10R.1D), re-
  confirmed as the right semantic this pass.
- **"Triples"** — a fixed, unconditional 3-rep protocol on specific
  named days (Monday Bench, Thursday Deadlift in the stock Family B
  file) — reps never step down across weeks the way ordinary rows do.
- **Rating scale (-1/0/1)** — explicitly a *relative-to-that-weight*
  judgment ("For that weight" — not an absolute speed/difficulty scale),
  feeding the sets-count autoregulation for a *linked* exercise roughly
  half a week later. The How-To PDF is explicit that **"NOT ALL of the
  ratings affect the program in a predictable way"** — some rated cells
  are genuinely dead inputs (confirmed independently in
  `PROGRAM_LOGIC_SPEC.md` §4 for Family C: "both Upper-Body-Pull slots
  and both Shoulder slots have rating columns that are never referenced
  by any formula"). This must be preserved as-is, not "fixed" —
  it is real, documented source behavior, not a bug to patch.
- **"Only the biggest and most central exercises are rated"** — source-
  confirmed (How-To PDF, Step 5): accessory/8RM rows are deliberately
  never rated, always following a fixed set schedule instead.
- **5RM/8RM/10RM** — literal, estimated rep-max anchors, explicitly
  *not* required to be tested maxes ("you don't have to worry at all...
  just give your best guess"). The How-To PDF also documents a real,
  actionable **self-calibration adjustment rule** not yet modeled
  anywhere in TrainingOS: "if your first couple of sets are 3 or fewer
  reps, bump the weight down in that initial RM column; if over 8 reps
  [for 5RM moves] or outside 5-10 [for 8RM moves], bump it up." This is
  source-confirmed, athlete-facing guidance — currently unimplemented
  anywhere (see §12, flagged FOLLOW-UP, not a V1 blocker since it's
  athlete self-adjustment guidance, not a computed program rule).
- **Deload notation** — literal instruction strings ("2/3 reps of Week
  1," "1/2 reps of Week 1"), never a computed formula for the rep count
  itself — only the weight is formula-driven.
- **"Every other deadlift workout... lighter"** — source-documented as
  *intentional* fatigue management (How-To PDF, Step 4), not a
  spreadsheet error — directly explains the real Triples/0.7×-factor
  Thursday Deadlift session sitting alongside a heavier Monday
  Deadlift-adjacent day.

No source ambiguity was found beyond the one already-disclosed and
already-correctly-resolved Family C footnote/formula bug (§5).

---

## 7. Calibration Requirements

Source truth only: Family B needs 5RM (Legs×2/Push×2/Deadlift) + 8RM
(Hamstring/Upper-Pull×2/Shoulder×2) per exercise, entered once per
mesocycle. Family C needs a single 10RM per exercise, same cadence.

**Existing TrainingOS support: SUPPORTED NOW, no extension needed.**
`RMType` already has exactly `.rm5`/`.rm8`/`.rm10` cases (confirmed by
direct read of `StrengthProgressionRules.swift`), and `SourceRMCalibration`
(scoped to `(programInstance, exercise, rmType)`, literal user-entered
value, never estimated/converted) already matches this exact shape —
this is the identical mechanism Hypertrophy Family A already uses in
production. **No new calibration concept of any kind is required for
Strength/Powerlifting.**

---

## 8. Progression Rules

**SUPPORTED NOW**, confirmed by direct read of the current
`PowerliftingProgramGenerator.swift`: `RMBasedLoad(rmType:weekOneFactor:
laterWeekMultipliers:)` already expresses the exact `MROUND(RM × factor,
unit)` → `× 1.05/1.075/1.1` shape both families use.
`AutoregulatedSetCount(baselineSets:applyRatingOnFinalWeek:freezeAfterWeek:)`
already expresses both families' autoregulation shape, including Family
B's Week-4 asymmetry (`applyRatingOnFinalWeek: false` for the Thursday
row) and Family C's Monday-Wednesday-vs-Thursday-Friday freeze
(`freezeAfterWeek: 2`) — these are the exact two "same underlying formula
shape, different day grouping" mechanisms `PROGRAM_LOGIC_SPEC.md` §6
already identified as structurally identical. `.linkedToPairedSlot
(fractionOfSourceResult:)` already expresses Family C's Friday-backoff-as-
fraction-of-Monday's-result mechanic exactly.

**The rule ENGINE is source-faithful today.** What's missing is coverage
(§10-§12), not mechanism.

---

## 9. Deload / Phase Structure

Both families: 5-week mesocycle (4 work + 1 deload), **SUPPORTED NOW** via
`DeloadPositionOverride(boundaryDayIndex:fullPositionFactor:
halfPositionFactor:)`, already correctly parameterized per family
(Family B: 0.7/0.5 weight, 2/3 / 1/2 reps; Family C: 1.0/0.5 weight,
unchanged / 1/2 reps, with the Friday-backoff's own reps-unchanged
exception already modeled via `deloadRepFraction: 1.0`).

**No universal strength-mesocycle rule was invented or should be** — each
family's own deload split is a literal, hardcoded parameterization of its
own source numbers, never a shared "every strength program deloads this
way" assumption. This matches the discipline already established and
explicitly reaffirmed for Running (R1 §21) and Hypertrophy.

**Restart/chaining:** the How-To PDF documents that up to 3 consecutive
Family B mesocycles can be chained before a recommended "peaking phase"
(templates for which RP says are still in production, per the PDF's own
"we're working on building peaking phase templates too") — a
`ProgramJourney`-shaped concept TrainingOS already has (used for
Hypertrophy/Running); no curated 3-mesocycle-then-peak preset exists yet.
**FOLLOW-UP, not a V1 blocker** — peaking-phase content is a genuine
MISSING SOURCE (RP's own admission), not something to fabricate.

---

## 10. Existing TrainingOS Support

| Source concept | Classification |
|---|---|
| 5RM/8RM/10RM calibration | **SUPPORTED NOW** (`RMType`, `SourceRMCalibration`) |
| `%RM`-based weekly progression (0.95 baseline, 1.05/1.075/1.1 steps) | **SUPPORTED NOW** (`RMBasedLoad`) |
| Cross-day/cross-exercise autoregulation (rating → linked slot's sets) | **SUPPORTED NOW** (`AutoregulatedSetCount`, `freezeAfterWeek`, `applyRatingOnFinalWeek`) |
| Fixed protocol days (Triples) | **SUPPORTED NOW** (`.fixedReps`) |
| Backoff-as-fraction-of-paired-slot (Family C Friday) | **SUPPORTED NOW** (`.linkedToPairedSlot`) |
| Per-family deload weight/rep position splits | **SUPPORTED NOW** (`DeloadPositionOverride`) |
| Full 10-category, 15/16-real-row day structure per family | **SMALL EXTENSION REQUIRED** — same primitives, more `SourceDay`-style entries; directly mirrors the migration pattern already proven for Hypertrophy Family A (3/4/5/6-Day) |
| A `isPowerliftingSourceVerified`-style fidelity gate | **SMALL EXTENSION REQUIRED** — mirror `isHypertrophySourceVerified` exactly; confirmed by grep that no such gate exists today for Powerlifting |
| Athlete-facing RM self-calibration adjustment guidance (source's "bump the weight if reps are off" rule) | **NEW DOMAIN CONCEPT, deferred** — a UI/guidance concern, not a generator rule; no existing analog |
| 3-mesocycle-then-peak `ProgramJourney` preset | **UNRESOLVED** — peaking-phase content is genuinely missing source (RP's own admission it wasn't shipped) |

**No new parallel Strength/Powerlifting architecture is warranted.** Every
genuinely missing piece is either a content-coverage gap on top of an
already-correct engine, or explicitly missing source content — never a
missing domain primitive.

---

## 11. Existing Strength/Powerlifting Code Audit

- **`PowerliftingProgramGenerator.swift` — PARTIALLY SOURCE-FAITHFUL.**
  Confirmed by direct read: the progression math, deload splits, Triples
  protocol, Week-4 asymmetry/freeze distinction, and backoff-pairing
  mechanic are all exactly source-faithful and already covered by a real,
  passing regression suite (`PowerliftingRegressionTests.swift`, 12
  tests, all mechanic-level, all verified against the real formulas this
  pass). What is NOT faithful: **category/row coverage.** `generateFamilyB`
  produces exactly 4 sessions/slots (Monday Bench, Tuesday Squat,
  Thursday Deadlift, Friday Upper-Pull) against a real source that has
  **15 rows across 4 days**, entirely omitting the Shoulder category (both
  slots). `generateFamilyC` produces 6 slots (5 standard rows + 1 backoff)
  against a real source with **16 rows across 5 days**, entirely omitting
  the Hamstring category. This is confirmed, not inferred — the
  generator's own doc comments already disclose this ("one representative
  slot per training day... not fabricated here with false confidence").
- **`PowerliftingBuiltInLibrary.swift` — naming/day-count accurate,
  content behind it incomplete.** Its 2 entries ("4-Day Powerlifting
  Strength" → Family B, "5-Day Powerlifting Hypertrophy" → Family C) are
  correctly matched to the real source's actual day counts — the gap is
  entirely in what `PowerliftingProgramGenerator` builds for them, not in
  the library's own naming/configuration.
- **Not LEGACY/UNSAFE-TO-EXPOSE.** The engine mechanics are real and
  correct; this is closer to the Hypertrophy Family A situation
  immediately before its Source Authority Repair — a real, tested engine
  whose exercise-category coverage needs completing, not a broken or
  fabricated system.
- **No fidelity gate exists to flag this today** (confirmed: zero grep
  hits for any Powerlifting-side equivalent of
  `isHypertrophySourceVerified`) — meaning these 2 configurations are
  reachable through the same recommendation path Hypertrophy uses,
  with no declarative marker that their content is incomplete.

---

## 12. Source Fidelity Gaps

1. Family B: 11 of 15 real source rows missing (both Shoulder slots
   entirely; Legs2/Push2/Hamstring/Upper-Pull2 duplication-across-days
   also uncaptured).
2. Family C: 10 of 16 real source rows missing (Hamstring entirely; the
   Monday/Tuesday/Wednesday/Friday duplication-across-days also
   uncaptured).
3. Family D confirmed unusable as V1 content (blank templates) —
   evidence-only, correctly excluded from any V1 program list.
4. No companion FAQ for either family survives (only the Family-B-specific
   How-To PDF) — some edge-case guidance (analogous to Hypertrophy's FAQ)
   may simply not be recoverable.
5. The source's own self-calibration RM-adjustment guidance (§6) has no
   TrainingOS representation yet.
6. No `ProgramJourney` preset exists for the documented "up to 3
   consecutive mesocycles, then peak" pattern; peaking-phase content
   itself is genuinely missing from RP (their own admission).

---

## 13. V1 Blockers

**BLOCKS V1:**
- The category-coverage gap itself (§12.1-§12.2). An athlete running
  either curated configuration today never trains an entire real,
  source-prescribed muscle group (Shoulders for Family B, Hamstrings for
  Family C) — the same class of problem that motivated Hypertrophy
  Family A's own Source Authority Repair, and both families' full
  content is **already fully recovered and documented**
  (`SOURCE_PROGRAM_MANIFEST.md` §8/§9), so there is no source-availability
  reason to leave this unrepaired.
- The missing fidelity gate (no way to even flag/declare these 2
  configurations as content-incomplete today, unlike Hypertrophy's
  `isHypertrophySourceVerified`).

**CHECKPOINT BUG:** none found — every current behavior matches its own
documented, disclosed scope; nothing was found broken relative to what it
claims to do.

**FOLLOW-UP:**
- The RM self-calibration adjustment guidance (§6/§12.5).
- The 3-mesocycle-then-peak `ProgramJourney` preset (§9/§12.6) —
  genuinely blocked on missing peaking-phase source content, not an
  implementation gap.

**IMPROVEMENT:**
- Sourcing/creating a Family-C-equivalent FAQ document if one can be
  located (not blocking; the How-To + spreadsheet's own in-sheet
  instructions already cover the operationally load-bearing rules).

---

## 14. Recommended V1 Product Boundary

Per this checkpoint's own default rule ("if we have the full source,
implement it"): **both Family B and Family C should be fully migrated to
their complete, real 15-row/16-row structures** — the source is not
partial the way Running's 13-vs-16-week gap was; every row, formula, and
day assignment for both families is already fully recovered and written
down (`SOURCE_PROGRAM_MANIFEST.md` §8/§9). There is no honest reason to
ship a narrower V1 here the way Running's V1 was deliberately narrowed —
the source-completeness bar is already met for both programs.

**Family D stays excluded from V1** — not because its source is
incomplete, but because it has no real content to source-verify against
(confirmed blank templates) and is not a distinct RP methodology.

---

## 15. Exact Implementation Scope

1. Migrate `PowerliftingProgramGenerator.generateFamilyB` to the full
   15-row, 4-day structure from `SOURCE_PROGRAM_MANIFEST.md` §8 (Monday:
   Deadlift/Legs1/Push1-Triples/Hamstring; Tuesday: Legs2/Push2/
   UpperPull1/Shoulder1; Thursday: Deadlift-Triples/UpperPull2/Shoulder2;
   Friday: Push1/Legs2/UpperPull1/Shoulder1) — mirroring
   `HypertrophyProgramGenerator`'s proven `SourceDay` pattern, reusing
   every existing rule type from §8/§10 unchanged.
2. Migrate `generateFamilyC` to the full 16-row, 5-day structure from
   §9 (Monday: Push1/Legs1/UpperPull1; Tuesday: Legs1/Deadlift/Shoulder1;
   Wednesday: Push2/UpperPull1/Shoulder1; Thursday: Deadlift/Hamstring/
   Shoulder2; Friday: Legs2/Push1-backoff/UpperPull2/Shoulder2).
3. Add `ProgramCapabilityRegistry.isPowerliftingSourceVerified(family:)`,
   declarative-only at first (not wired into `LongTermPlanner`), mirroring
   `isHypertrophySourceVerified`'s own phased-activation discipline
   exactly (including its documented 38-failure lesson — do not wire
   without first confirming zero regression).
4. Update `PowerliftingBuiltInLibraryTests`/`PowerliftingProgramGeneratorTests`
   for the new row/slot counts; extend `PowerliftingRegressionTests` to
   cover every newly-added row's own protocol/factor.
5. Add a new `PowerliftingSourceFidelityTests.swift` (see §16).

---

## 16. Source-Fidelity Test Plan

Mirroring the Hypertrophy Family A fidelity-test discipline:

- Exact row/day/session counts per family (15/4 for B, 16/5 for C).
- Every row's RM type matches the source's hardcoded per-category label
  (never inferred from the exercise chosen).
- Every row's Week-1 factor/protocol matches its source cell exactly
  (0.95 ordinary / 0.7 Triples for B; 0.95 standard / 0.85 backoff for C).
- Every row's autoregulation behavior (which day's rating feeds which
  row, the Week-4 asymmetry/freeze split) matches the source's own
  cross-day wiring, not a same-row self-reference.
- Deload weight/rep split matches each family's own documented
  position-based override, never a shared universal rule.
- Rounding unit (2.5 for B, 5 for C) is preserved as a genuine, tested
  cross-family difference.
- **Prefer one canonical, per-family fixture table (Day, Category,
  RMType, WeekOneFactor/Protocol, autoregulation-source-row) compared
  programmatically against the generated template graph**, rather than
  15+16 loosely-related hand-written assertions — directly reusing the
  golden-fixture-comparison pattern already established for Hypertrophy's
  own source-fidelity suites.

---

## 17. Follow-Up / V2 Items

- RM self-calibration adjustment guidance (athlete-facing, not generator
  logic) — candidate for a future onboarding/calibration UX pass.
- Peaking-phase `ProgramJourney` content — blocked on RP source that does
  not yet exist per RP's own admission; do not fabricate.
- Any Family-C-equivalent FAQ, if ever located.
- Wiring `isPowerliftingSourceVerified` into `LongTermPlanner` — deferred
  until after the content migration itself is verified regression-free,
  exactly as Hypertrophy's own gate remained inert for a full checkpoint
  before activation.

---

## 18. Recommended Next Checkpoint

A single "Powerlifting Source Authority Repair" implementation checkpoint
covering Family B and Family C's full content migration (§15 items 1-2),
the declarative fidelity gate (§15 item 3), and the full fidelity/regression
test suite (§16) — likely completable in one pass, unlike Hypertrophy's
multi-round repair, because both families' complete row-by-row structure
is already fully recovered and documented; no further workbook archaeology
is required, only migration engineering.

---

## Summary Table

| PROGRAM | SOURCE FILE | FREQUENCY | WEEKS | CALIBRATION | PROGRESSION MODEL | DELOAD | CURRENT TRAININGOS STATUS | V1 READY |
|---|---|---|---|---|---|---|---|---|
| 4-Day Powerlifting Strength (Family B) | `RP-PowerliftingStr-4-Day.xlsx` (+ `Strength_Program_1.xlsx`, blank-template evidence) | 4/wk (Mon/Tue/Thu/Fri) | 5 (4 work + 1 deload) | 5RM (Legs×2/Push×2/Deadlift) + 8RM (Hamstring/Upper-Pull×2/Shoulder×2) | `MROUND(RM×0.95 or 0.7-Triples, 2.5)`, +5.0/+2.5/+2.5pp weekly, cross-day autoregulated sets | Mon/Tue 0.7×wt + "2/3 reps"; Thu/Fri 0.5×wt + "1/2 reps" | Partially source-faithful — mechanics exact, only 4 of 15 real rows implemented, Shoulder category entirely missing | **NO** (source complete; migration not yet done) |
| 5-Day Powerlifting Hypertrophy-block (Family C) | `RP-PowerliftingHyp-5-Day.xlsx` (+ `Strength_Program_2.xlsx`, blank-template evidence) | 5/wk (Mon-Fri) | 5 (4 work + 1 deload) | Uniform 10RM | `MROUND(RM×0.95 or 0.85-backoff, 5)`, +5.0/+2.5/+2.5pp weekly, Mon-Wed autoregulate/Thu-Fri freeze after Wk3 | Mon/Tue unchanged wt; Wed-Fri 0.5×wt + "1/2 reps" (Fri-backoff reps unchanged) | Partially source-faithful — mechanics exact, only 6 of 16 real rows implemented, Hamstring category entirely missing | **NO** (source complete; migration not yet done) |

*Family D (`Strength_Program_1.xlsx`/`Strength_Program_2.xlsx`) intentionally
excluded above — confirmed blank, never-populated derivatives, not a
distinct program; kept only as reconfigurability evidence, never a V1
candidate.*

---

## Git status

```
$ git diff --stat
(empty — no tracked file was modified by this checkpoint)

$ git status --short
?? ../.DS_Store
?? .DS_Store
?? CP3_AND_TRAINING_ENVIRONMENT_AUDIT.md
?? POST_FFP1_FUNCTIONAL_FITNESS_GAP_AUDIT.md
?? RUNNING_V1_ATHLETE_JOURNEY_GAP.md
?? STRENGTH_POWERLIFTING_SOURCE_RECOVERY_V1.md   <- this checkpoint's only new file
?? TE1_TRAINING_ENVIRONMENT_FOUNDATION_DESIGN.md
?? TrainingOS.xcodeproj/project.xcworkspace/xcuserdata/
?? TrainingOS.xcodeproj/xcuserdata/
```

No Swift file was created, edited, or touched. No Hypertrophy/Running/
Functional Fitness file was modified. Nothing staged. No commit. No push.
`source_workbooks/` remains gitignored and untouched (read-only
inspection throughout, via `openpyxl`/`Read`).

---

## Verdict

STRENGTH + POWERLIFTING SOURCE RECOVERY: PASS
ALL SOURCE FILES DIRECTLY INSPECTED: YES
PROGRAM FAMILY MAP COMPLETE: YES
SOURCE SEMANTICS RECOVERED: YES
V1 IMPLEMENTATION SCOPE IDENTIFIED: YES
READY FOR IMPLEMENTATION: YES
