# Metric Load Model

TrainingOS is metric-native. This document specifies how a source
program's load logic (found to be unit-agnostic multipliers of an RM —
see `PROGRAM_LOGIC_SPEC.md` §6.2) becomes a real, achievable kg load for a
specific user's equipment, and why the source spreadsheets' own rounding
behavior is *not* simply carried forward.

## 1. The problem, precisely

Every source workbook computes a load as `RM × factor`, then rounds via
`MROUND(value, incrementConstant)`, where `incrementConstant` is 2.5 or 5
depending on the file (`PROGRAM_LOGIC_SPEC.md` §6.2). No file states a
unit. In practice, RP's own worked example in the FAQ (bodyweight "150lb,"
plates "45lb") confirms the source material is authored in **pounds**, and
2.5/5 read as plausible microplate/standard-plate increments in that
system. TrainingOS must never treat `2.5` or `5` as meaningful in
isolation, and must never convert the *increment* directly to kg (handoff
rule 5's own example: "round to nearest 5 lb" must **not** become "round to
nearest 2.26796 kg" — that number is not achievable on any real bar).

## 2. Two separate concerns, two separate steps

**`IdealLoad`** — what the methodology's formula says the number *should*
be, computed losslessly as a fraction/percentage of an RM. This is pure
arithmetic on a `ProgressionRule` (see `PROGRAMMING_SYSTEM_MODEL.md` §3) —
no rounding, no equipment awareness. `IdealLoad` is a plain `Double`, in
kg, always.

**`EquipmentProfile.resolve(idealLoad:)`** — what the user can *actually*
load onto their specific equipment. This is the only place rounding
happens for a real user, and it depends on what they have, not on what the
source spreadsheet assumed:

```
struct EquipmentProfile {
    let equipmentType: EquipmentType   // .barbell, .dumbbell, .machine, .cable, .bodyweightPlusExternal
    let smallestIncrementKg: Double    // e.g. barbell with 1.25 kg plates/side -> 2.5 kg total
    let roundingRule: RoundingRule     // .nearest (default), .down (never prescribe more than estimated), .up

    func resolve(idealLoadKg: Double) -> Double
}
```

Per handoff rule 6 (already locked from Stage 1–2): `IdealLoad` and its
`EquipmentProfile`-resolved value are computed by two different concerns
and must never be conflated into one stored number — `IdealLoad` lives on
the `Recommendation`, the resolved value is what actually gets prescribed
in the `SetPrescription`.

### Worked example (matches the Stage 3A brief's own numbers exactly)

| Step | Value |
|---|---|
| Source value | 180 lb |
| Raw unit conversion (`× 0.45359237`) | 81.646266... kg |
| `IdealLoad` (unrounded) | 81.646266 kg |
| `EquipmentProfile`: barbell, 2.5 kg achievable increment | `resolve(81.646266) = round(81.646266 / 2.5) × 2.5 = round(32.658...) × 2.5 = 33 × 2.5` |
| **Resolved training load** | **82.5 kg** |

`1 lb = 0.45359237 kg` is used *only* when translating a source example
into a regression fixture (per §4) — never as a live conversion inside the
app, since TrainingOS never stores or displays pounds internally in V1
(no lb/kg toggle is in scope for this pass; see
`OPEN_PROGRAMMING_QUESTIONS.md` §11).

## 3. Where source rounding goes instead

The source spreadsheets round *at every week*, because each week's formula
literally references the *already-rounded* Week-1 cell, not a hypothetical
unrounded value (`PROGRAM_LOGIC_SPEC.md` §2.1, §3, §4 — `weekN =
MROUND(week1Cell × multiplier, unit)`). Silently switching to
"compute everything unrounded, round once at the end" would produce
different numbers than the source in edge cases, which breaks regression
fidelity (`PROGRAM_REGRESSION_TEST_PLAN.md`).

**Resolution:** `EquipmentProfile.resolve()` runs at *every* step the
source spreadsheet rounds at (Week 1, then each subsequent week off the
resolved Week-1 value), not only once at the end for display. This
preserves the source's algorithm *shape* (round-then-build-on-the-rounded-
value) while making the rounding increment a property of the **user's real
equipment**, not a guessed generic plate size. A regression fixture that
wants to reproduce a source spreadsheet's exact numbers configures an
`EquipmentProfile` using that spreadsheet's own increment *converted
faithfully into the same unit system the fixture's inputs are in* (i.e., a
lb-based fixture uses a 2.5 lb or 5 lb `EquipmentProfile` for that
assertion only — see §4) — this validates the *rule logic* is faithful,
completely independent of what any real TrainingOS user's actual
`EquipmentProfile` looks like.

## 4. Regression-fixture units

Per handoff rule 5: percentages/factors are copied unchanged from source
(`0.85`, `1.05`, etc. — these are dimensionless and need no conversion).
Only literal weight values (RM inputs, expected outputs) need unit
handling, and only for the purpose of proving the *rule* matches the
source — see `PROGRAM_REGRESSION_TEST_PLAN.md` for the fixture format.
Fixtures store the source's original lb-based RM inputs and expected
outputs verbatim (traceable back to the workbook), plus the same fixture
re-expressed with a kg-native `EquipmentProfile` to prove the formula
produces a *sensible*, achievable kg result — not to prove numeric
equality with a unit-converted lb figure, which handoff rule 5 explicitly
prohibits treating as meaningful.

## 5. Bodyweight-plus-external-load exercises

Families B and C (`PROGRAM_LOGIC_SPEC.md` §3, §4) handle bodyweight
exercises (pull-ups, dips, GHRs) by pure user instruction: the RM entry is
told to *include* bodyweight, and the user manually subtracts their own
bodyweight from the computed result to know what to add via belt/dumbbell.
No formula in any source file performs this arithmetic.

TrainingOS should not perpetuate the manual-subtraction burden. Proposed
`EquipmentProfile` extension for this case:

```
case bodyweightPlusExternal(externalIncrementKg: Double)
```

`resolve(idealLoadKg:)` for this case takes the *total* ideal load
(bodyweight-inclusive, matching how the RM was entered — keep this
consistent with the source convention so imported programs need no
reinterpretation), subtracts the user's current logged bodyweight (from
`PerformanceProfile`/HealthKit once that integration exists — not in this
pass), and rounds *only the external portion* to the achievable increment.
The user-facing prescription should show the added-load number directly
(e.g. "+25 kg"), not the bodyweight-inclusive total, eliminating the
manual step every source file currently requires. This is a genuine
product improvement over the source material, not a literal reproduction
of it — flagged here as a deliberate deviation, not an oversight.

## 6. What this section does not decide

- Whether TrainingOS ever offers an lb *display* unit (distinct from
  internal storage, which is always kg) — out of scope, `OPEN_PROGRAMMING_QUESTIONS.md` §11.
- The exact default `EquipmentProfile` catalog (which increments to ship
  for "commercial gym barbell," "home gym dumbbells," etc.) — a product/UX
  decision, not something the source spreadsheets inform, since they never
  address it either.
