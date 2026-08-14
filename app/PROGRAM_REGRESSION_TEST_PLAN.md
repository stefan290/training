# Program Regression Test Plan

Specification of the fixture set that will prove a future `ProgressionRule`
evaluator (`PROGRAMMING_SYSTEM_MODEL.md` §3) reproduces the source
spreadsheets' numbers exactly, using **multiple workbooks across multiple
families** — not one example. No evaluator exists yet; this document
defines the target test data and the shape of the tests, gated on the same
review as the rest of Stage 3A.

## 1. Provenance labeling — a mandatory distinction

Not all 15 workbooks contain usable example numbers. Direct inspection of
every source file's cached formula values (`data_only=True` pass) found:

- **`f046f129-RPPowerliftingStr4Day.xlsx` (Family B) is the only workbook
  shipped with real, filled-in example data.** Sheet `b` has non-zero RM
  entries (`G4=80, G5=60, G7=90, G9=78`) and sheet `c` has real rating
  values (`B5=2, B6=2, B7=2, F25=1, F34=1, F35=1, K35=1`), so every
  downstream formula in that file has a genuine, author-verified cached
  value.
- **Every Family A workbook (all 11) and the Family C workbook
  (`6d06b9fd-RPPowerliftingHyp5Day.xlsx`) ship as blank templates.** Their
  RM-input cells (e.g. `G11`, `D5/I5/N5/S5`) are empty, so every formula
  that depends on them caches to `0`. There is no real example to extract
  — confirmed by direct grep of the cached-value dump, not inferred.

Every fixture below is tagged **SOURCED** (input and expected output both
come from a workbook's own cached values — proves the formula *and* a real
number) or **CONSTRUCTED** (the formula is sourced and cited exactly as in
`PROGRAM_LOGIC_SPEC.md`; the input value is a chosen illustrative number
because the workbook has none — proves the formula only). Shipping a
CONSTRUCTED fixture mislabeled as SOURCED would be exactly the kind of
fabricated verification result this whole engagement has been told to
avoid; the label must stay attached to the fixture permanently, including
in whatever test file eventually encodes it.

## 2. Fixture format

Each fixture specifies: the `ProgressionRule` type under test (from
`PROGRAMMING_SYSTEM_MODEL.md` §3), its inputs, its expected output, and its
source citation (workbook, sheet, cell) — the same Rule-ID/Source
provenance discipline as `PROGRAM_LOGIC_SPEC.md`.

## 3. Family B fixtures — SOURCED (real workbook data)

### 3.1 Load-progression chain — `rmBasedWeekOneLoad` + `fixedMultiplierOfWeekOne`

Deadlift, 5RM basis, standard (non-Triples) session.

| Step | Rule | Formula | Source cell | Value |
|---|---|---|---|---|
| Input | — | 5RM entered by user | sheet b `G7` | **90** |
| Week 1 | `rmBasedWeekOneLoad` (factor 0.95) | `MROUND(G7×0.95, 2.5)` | `C5` | **85** |
| Week 2 | `fixedMultiplierOfWeekOne` (×1.05) | `MROUND(C5×1.05, 2.5)` | `H5` | **90** |
| Week 3 | `fixedMultiplierOfWeekOne` (×1.075) | `MROUND(C5×1.075, 2.5)` | `M5` | **92.5** |
| Week 4 | `fixedMultiplierOfWeekOne` (×1.1) | `MROUND(C5×1.1, 2.5)` | `R5` | **92.5** |
| Deload | `deloadWeightBySchedulePosition` (factor 0.7) | `MROUND(C5×0.7, 2.5)` | `W5` | **60** |

Every weekly value is independently derived from the rounded **Week-1**
cell, not compounded week-over-week — the evaluator must reference the
stored Week-1 result, not recompute `RM × cumulative factor`, or Week 3/4
will silently drift from these numbers on files where MROUND's rounding
direction flips (see `METRIC_LOAD_MODEL.md` §3 for why this matters).

The deload factor here is `0.7`, which per `FAMILY_B_DELOAD` is the
Monday/Tuesday-half-of-week value — that fact comes directly from the `0.7`
literal in the `W5` formula itself, not from an assumption about which day
Deadlift falls on.

### 3.2 Autoregulation chain — `autoregulatedSetCount`

Front Squat's Week-2 sets, driven by High Bar Squat's Week-1 rating (a
cross-exercise pairing within the Legs pattern — confirms the rule
operates on a *declared pairing*, not "the same exercise's own history").

| Input | Source cell | Value |
|---|---|---|
| Front Squat Week-1 baseline sets | `B6` | **2** |
| High Bar Squat Week-1 rating | `F35` | **1** |
| **Front Squat Week-2 sets** (`=B6+F35`) | `G6` | **3** |

A second link in the same chain, from the same file, using a *different*
paired slot to prove the rule generalizes to more than one pairing: Front
Squat's Week-1 rating was independently confirmed at `F34=1`, and the
`b5/b6/b7=2` baselines confirm all three "central" Legs/Push rows share
the same `2`-set Week-1 baseline before autoregulation diverges them.

### 3.3 Deload day-boundary split — `deloadWeightBySchedulePosition`

Confirmed directly from distinct literal constants in the same workbook
(no computation needed beyond citing both cells): Monday/Tuesday sessions
use `factor = 0.7` (`W5`, §3.1 above); Thursday/Friday sessions use
`factor = 0.5` (cited in `PROGRAM_LOGIC_SPEC.md` §3, `FAMILY_B_DELOAD`).
Applied to the same Week-1 baseline of 85 this would give Thu/Fri deload =
`MROUND(85×0.5, 2.5) = 42.5` — this specific number is **CONSTRUCTED**
(no Thu/Fri row's cached value was independently pulled for this exact
exercise), included only to give the evaluator a same-Week-1-input,
different-schedule-position pair to test against 3.1's SOURCED value.

## 4. Family A fixtures — CONSTRUCTED (workbook ships blank)

Input RM chosen as **100** throughout, purely for arithmetic convenience —
this is not a realistic training number and must not be read as one. All
formulas below are quoted verbatim from `PROGRAM_LOGIC_SPEC.md` §2.1;
only the RM input is invented.

### 4.1 Load-progression chain — Mesocycle 1 ("Basic Hypertrophy"), 2.5 rounding unit

| Step | Formula (source: `e1f8fb19` `J11/P11/V11/AB11`) | Value |
|---|---|---|
| Input (10RM) | — | 100 |
| Week 1 (`×0.85`) | `MROUND(100×0.85, 2.5)` | **85** |
| Week 2 (`×1.05` of week1) | `MROUND(85×1.05, 2.5)` | **90** |
| Week 3 (`×1.075` of week1) | `MROUND(85×1.075, 2.5)` | **92.5** |
| Week 4 (`×1.1` of week1) | `MROUND(85×1.1, 2.5)` | **92.5** |

Identical output shape to the Family B SOURCED fixture (3.1) from the same
input and rounding unit — this is the cross-family proof point: two
families' independently-sourced formulas produce the exact same numbers
given the exact same input, because `fixedMultiplierOfWeekOne`'s parameter
values (`1.05/1.075/1.1`) are genuinely shared, not coincidentally similar.

### 4.2 Autoregulation chain, including a rating decrease — `autoregulatedSetCount`

Compounds baseline = 3 sets (`PROGRAM_LOGIC_SPEC.md` §2.1). Chosen ratings
`[1, 0, -1]` deliberately include a negative rating, which no Family B
SOURCED fixture exercises (the real workbook's captured ratings happened
to all be `1`):

| Week | Rating applied | Formula | Sets |
|---|---|---|---|
| 1 (baseline) | — | constant | **3** |
| 2 | `+1` ("wasn't very sore") | `week1.sets + rating` | **4** |
| 3 | `0` ("tough but manageable") | `week2.sets + rating` | **4** |
| 4 | `-1` ("very sore") | `week3.sets + rating` | **3** |

Proves the evaluator subtracts as well as adds — a rule that only ever
clamps at a floor of the baseline, or never decreases, would pass every
Family B SOURCED fixture (all ratings `1`) and still be wrong.

### 4.3 Deload weight day-boundary asymmetry — `deloadWeightBySchedulePosition`

4-day file, boundary at `ceil(4/2) = 2`: Days 1–2 full weight, Days 3–4
half. Using Week 1 = 85 from §4.1: Day-1/2 deload = **85** (unchanged, per
`AH11: '=J11'`); Day-3/4 deload = `MROUND(85×0.5, 2.5)` = **42.5** (per
`AH30: '=MROUND((J30×0.5),2.5)'`). Structurally identical rule shape to
Family B's 3.3, different boundary function (`ceil(dayCount/2)` vs. a fixed
Mon/Tue-vs-Thu/Fri split) — both must be representable as the same
`deloadWeightBySchedulePosition` rule type with different `positions`
parameters, not two different rule types.

## 5. Family C fixtures — CONSTRUCTED (workbook ships blank)

Input 10RM chosen as **100**, rounding unit 5 (per `FAMILY_C_WEEK1_BASELINE`).

### 5.1 Load-progression chain + Friday backoff — `rmBasedWeekOneLoad` + `linkedResultReference`

| Step | Formula | Value |
|---|---|---|
| Standard Week 1 (`×0.95`) | `MROUND(100×0.95, 5)` | **95** |
| Standard Week 2 (`×1.05` of week1) | `MROUND(95×1.05, 5)` | **100** |
| Standard Week 3 (`×1.075` of week1) | `MROUND(95×1.075, 5)` | **100** |
| Standard Week 4 (`×1.1` of week1) | `MROUND(95×1.1, 5)` | **105** |
| Friday backoff Week 1 (`×0.85` of the *same* Monday exercise) | `MROUND(100×0.85, 5)` | **85** |

The rounding-unit difference (5, not 2.5) changes Week-3's rounded result
relative to §4.1's Family A fixture even though the multiplier (`1.075`)
is identical — a correctness-relevant detail an evaluator that hardcodes
"round to 2.5" anywhere would get wrong for this family.

### 5.2 Week-4 freeze asymmetry — `autoregulatedSetCount` (the case that breaks a naive evaluator)

Thursday/Friday autoregulated rows freeze after Week 3 — Week 4 repeats
Week 3's value exactly, **ignoring** Week 4's own rating input entirely.
Baseline = 3, ratings `[1, 0, -1]` (last one deliberately supplied to prove
it's ignored, not just unused by coincidence):

| Week | Rating supplied | Rule applied | Sets |
|---|---|---|---|
| 1 (baseline) | — | constant | **3** |
| 2 | `+1` | `week1.sets + rating` | **4** |
| 3 | `0` | `week2.sets + rating` | **4** |
| 4 | `-1` (present, but must be ignored) | **frozen — copies week3 verbatim** | **4** |

This is the one fixture in this whole plan that a rule engine can fail
*silently*: an evaluator that always applies `autoregulatedSetCount`
uniformly would compute Week 4 = `4 + (-1) = 3`, not `4` — the wrong
answer would still look plausible. This must ship as an explicit
scheduled-freeze parameter on the rule (a `freezeAfterWeek` field, or an
equivalent per-slot override), not something the evaluator infers.

### 5.3 Deload weight — day-section split, not lift-type split

Monday/Tuesday deload weight = **unchanged** (= Week-1 weight, `95`, no
factor at all — not merely a factor of `1.0`, since `FAMILY_C_DELOAD`'s
Monday/Tuesday cells are a direct copy of the Week-1 cell with no `MROUND`
factor applied); Wednesday/Thursday/Friday = `MROUND(95×0.5, 5)` = **50**.
Deadlift and Hamstring (both posterior-chain "main lifts," a category a
naive rule might special-case as "always keep heavy") fall on the
**halved** side because they're scheduled Wed–Fri, not because of what
they train — the rule must key strictly off schedule position, never off
exercise category or pattern, or this fixture's Deadlift/Hamstring rows
will be computed wrong even though Family B's superficially similar rule
would pass.

## 6. Cross-family abstraction proof

Per the brief's explicit requirement ("use multiple workbooks... do not
validate only one example"), the same six fixture groups above collapse
onto the same four `ProgressionRule` types with only parameter differences
— this is the regression-level evidence for the architectural proof table
in `PROGRAMMING_SYSTEM_MODEL.md` §7:

| Rule type | Family B fixture | Family A fixture | Family C fixture | Only difference is parameters? |
|---|---|---|---|---|
| `rmBasedWeekOneLoad` | §3.1 (factor 0.95, unit 2.5) | §4.1 (factor 0.85, unit 2.5) | §5.1 (factor 0.95, unit 5) | Yes |
| `fixedMultiplierOfWeekOne` | §3.1 (1.05/1.075/1.1) | §4.1 (1.05/1.075/1.1 — identical) | §5.1 (1.05/1.075/1.1 — identical) | Yes |
| `autoregulatedSetCount` | §3.2 (no freeze, all-positive ratings) | §4.2 (no freeze, mixed-sign ratings) | §5.2 (Thu/Fri freeze parameter engaged) | Yes — freeze is a parameter, not a new type |
| `deloadWeightBySchedulePosition` | §3.3 (Mon/Tue 0.7, Thu/Fri 0.5) | §4.3 (Day≤2 unchanged, Day>2 ×0.5) | §5.3 (Mon/Tue unchanged, Wed–Fri ×0.5) | Yes |

No fixture in any family required a rule type, a branch, or a special case
absent from the other two families — confirming the vocabulary in
`PROGRAMMING_SYSTEM_MODEL.md` §3 is sufficient, not aspirational.

## 7. Explicitly not covered by this fixture set

- **Deload rep counts.** Every family expresses these as literal text
  ("1/2 reps of Week 1," "2/3 reps of Week 1"), never a computed cell —
  there is no source cached value to regress against until
  `OPEN_PROGRAMMING_QUESTIONS.md` §5 gets a product ruling on how
  TrainingOS computes an actual rep target from that text.
- **Mesocycle-to-mesocycle chaining** (Family A) — no fixture is possible
  because no formula reads across sheets (`PROGRAM_LOGIC_SPEC.md` §2.2);
  nothing to regress against until `OPEN_PROGRAMMING_QUESTIONS.md` §2 is
  resolved.
- **Novice-specific behavior** — no fixture, because no distinct behavior
  was found to exist (`PROGRAM_FAMILY_MATRIX.md` §2).
- **Unit conversion correctness** — covered separately by
  `METRIC_LOAD_MODEL.md` §2's worked lb→kg→`EquipmentProfile` example, not
  duplicated here; this plan's fixtures are deliberately unit-agnostic
  scalars (`PROGRAM_LOGIC_SPEC.md`'s own framing: "treat every number as
  × the input RM," never a literal kg/lb figure) to isolate rule-logic
  correctness from equipment-rounding correctness.

## 8. Intended test-harness shape (spec only, not implemented)

Each fixture becomes one XCTest case once `Engines/` gains rule
evaluators (Stage 4), structured as:

```
struct RegressionFixture {
    let ruleType: ProgressionRuleType
    let parameters: [String: Double]      // e.g. factor, roundingUnit, multipliers
    let inputs: [String: Double]          // e.g. rm, baselineSets, priorRating
    let expected: Double
    let provenance: Provenance            // .sourced(file:, sheet:, cell:) | .constructed(reason:)
}
```

A single parametrized test function iterates every fixture in this
document (grouped by family, per §6's table) and asserts
`evaluator.evaluate(rule, inputs) == expected`. `provenance` is asserted to
be present and correctly tagged on every fixture as part of the test
itself — a SOURCED fixture whose `file`/`sheet`/`cell` fields are empty, or
a CONSTRUCTED fixture missing its `reason`, should fail the harness, not
just the documentation review. Not implemented in this pass — this section
exists so Stage 4 has an agreed target shape rather than an open question.
