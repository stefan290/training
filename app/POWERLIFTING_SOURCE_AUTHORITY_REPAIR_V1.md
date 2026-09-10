# Powerlifting Source Authority Repair V1

Source Authority Repair for `PowerliftingProgramGenerator`'s Family B and
Family C — migrating both from a one-representative-slot-per-day proof of
mechanics to their complete, real 15-row/16-row structures. Original
workbooks (`RP-PowerliftingStr-4-Day.xlsx`, `RP-PowerliftingHyp-5-Day.xlsx`)
were re-opened and re-verified directly this pass (formulas, not just
displayed values) — not merely inherited from
`PROGRAM_LOGIC_SPEC.md`/`SOURCE_PROGRAM_MANIFEST.md`, though every fixture
below agrees with both.

## 1. V1 capability

Family B ("RP Powerlifting Strength"): 4 sessions/week, 5-week mesocycle
(4 work + 1 deload), mixed 5RM/8RM, complete 15-row structure. Family C
("RP Powerlifting Hypertrophy-block"): 5 sessions/week, same mesocycle
length, uniform 10RM, complete 16-row structure. Family D
(`Strength_Program_1.xlsx`/`Strength_Program_2.xlsx`) remains excluded —
confirmed blank, never-populated derivatives, not a distinct program.
Peaking-phase content and RM self-calibration adjustment logic remain
explicitly deferred (§15).

## 2. Source authority

Both canonical workbooks were re-opened directly this pass via
`openpyxl` (`data_only=False` for formulas, `data_only=True` for the one
filled example's computed values). Where `PROGRAM_LOGIC_SPEC.md`/
`SOURCE_PROGRAM_MANIFEST.md` already documented a rule, this pass
independently re-confirmed it against the live cells before relying on it;
nothing was accepted from secondary documentation alone.

## 3. Family B complete structure

15 rows across 4 days (re-verified against `RP-PowerliftingStr-4-Day.xlsx`,
a filled real example used as an exact numeric golden fixture):

| Day | Category | RM | Week-1 factor | Protocol |
|---|---|---|---|---|
| Monday | Deadlift | 5RM | 0.95 | ordinary |
| Monday | Legs1 | 5RM | 0.95 | ordinary |
| Monday | Push1 | 5RM | **0.7** | **Triples** |
| Monday | Hamstring | 8RM | 0.95 | ordinary, fixed sets |
| Tuesday | Legs2 | 5RM | 0.95 | ordinary |
| Tuesday | Push2 | 5RM | 0.95 | ordinary |
| Tuesday | UpperPull1 | 8RM | 0.95 | ordinary, fixed sets |
| Tuesday | Shoulder1 | 8RM | 0.95 | ordinary, fixed sets |
| Thursday | Deadlift | 5RM | **0.7** | **Triples**, frozen wk4 |
| Thursday | UpperPull2 | 8RM | 0.95 | ordinary, fixed sets |
| Thursday | Shoulder2 | 8RM | 0.95 | ordinary, fixed sets |
| Friday | Push1 | 5RM | 0.95 | ordinary, frozen wk4 |
| Friday | Legs2 | 5RM | 0.95 | ordinary, frozen wk4 |
| Friday | UpperPull1 | 8RM | 0.95 | ordinary, fixed sets |
| Friday | Shoulder1 | 8RM | 0.95 | ordinary, fixed sets |

Rounding: `MROUND(x, 2.5)` for working weeks (see §12 for the caveat on
how this is actually enforced). Shoulder — entirely missing in the prior
version — is now present on both its real days.

## 4. Family C complete structure

16 rows across 5 days (re-verified against `RP-PowerliftingHyp-5-Day.xlsx`):

| Day | Category | Week-1 factor | Autoregulation |
|---|---|---|---|
| Monday | Push1 | 0.95 | continues |
| Monday | Legs1 | 0.95 | continues |
| Monday | UpperPull1 | 0.95 | fixed sets |
| Tuesday | Legs1 | 0.95 | continues |
| Tuesday | Deadlift | 0.95 | continues |
| Tuesday | Shoulder1 | 0.95 | fixed sets |
| Wednesday | Push2 | 0.95 | continues |
| Wednesday | UpperPull1 | 0.95 | fixed sets |
| Wednesday | Shoulder1 | 0.95 | fixed sets |
| Thursday | Deadlift | 0.95 | **frozen wk4** |
| Thursday | Hamstring | 0.95 | **frozen wk4** (copy of Deadlift's rating) |
| Thursday | Shoulder2 | 0.95 | fixed sets |
| Friday | Legs2 | 0.95 | **frozen wk4** |
| Friday | Push1 (**backoff**, 0.85×) | linked | **frozen wk4** |
| Friday | UpperPull2 | 0.95 | fixed sets |
| Friday | Shoulder2 | 0.95 | fixed sets |

Rounding: `MROUND(x, 5)` in the source (see §12). Hamstring — entirely
missing in the prior version — is now present.

Two DIFFERENT day-groupings exist and are kept deliberately distinct:
autoregulation-freeze boundary (Mon/Tue/Wed continue, Thu/Fri freeze) vs.
deload-weight boundary (Mon/Tue unchanged, **Wed**/Thu/Fri halved) —
Wednesday falls on opposite sides of these two boundaries, confirmed
directly from the workbook's own Wednesday deload formula
(`=MROUND(D×0.5,5)`).

## 5. Calibration semantics

Reused unchanged: `RMType.rm5`/`.rm8`/`.rm10`, `SourceRMCalibration`
scoped to `(programInstance, exercise, rmType)`. No new calibration
architecture. Source explicitly frames RM values as estimates, never
required tested maxes (already the case pre-repair; unchanged).

## 6. Progression semantics

`RMBasedLoad(rmType:weekOneFactor:laterWeekMultipliers:)`, multipliers
`[1.05, 1.075, 1.1]` shared across families and rows. All 15 Family B
rows' Week-1-through-Week-4 weights were verified this pass against the
filled canonical workbook's own computed values (see
`PowerliftingSourceFidelityTests.testFamilyBWeekOneFactorAndGoldenWeeklyProgression`)
— every one matches exactly.

## 7. Autoregulation graph

Every row's rating source (`pairedSlot`) was re-derived directly from the
live workbook's own formulas — not inferred from category names — and is
asserted row-by-row in
`PowerliftingSourceFidelityTests.testFamilyBCompleteCrossDayAutoregulationGraph`/
`testFamilyCCompleteCrossDayAutoregulationGraph`. Confirmed non-obvious
findings: Family B's Push1/Push2 form a 3-way chain (Monday-Push1 →
Friday-Push1 → Tuesday-Push2 → back to Friday-Push1), not a simple mutual
pair; Family C's Hamstring row shares Tuesday-Deadlift's rating verbatim
rather than having its own; 8RM/10RM-equivalent accessory rows never
autoregulate at all (confirmed genuinely dead rating inputs in the
source) and remain `.fixed([2,2,3,3])`.

## 8. Triples

Fixed 3-rep protocol, only on the two source-defined rows (Monday-Push1,
Thursday-Deadlift for Family B). Never reinterpreted as generic strength
work — `RepGoal.fixedReps(3)` for all 4 weeks, never `.rir`.

## 9. Family C backoff

Load: `.linkedToPairedSlot(fractionOfSourceResult: 0.85/0.95)`, paired to
Monday-Push1 — confirmed directly from the live workbook's own formula
(`D42` reads Monday's RM cell). Deload reps unchanged (`deloadRepFraction:
1.0`), the sole exception among Family C's rows.

## 10. Source authoring inconsistency (Friday backoff)

The live `RP-PowerliftingHyp-5-Day.xlsx` sheet's own footnote (row 54)
says `"1/2 Thursday's"`, but the sheet's own executable formula and
rep-goal cells (row 42) both literally read `"1/2 Monday's"`. The formula
is executable source truth and wins — TrainingOS pairs the backoff to
Monday, not Thursday, exactly as before this pass. Explicit regression
coverage:
`PowerliftingSourceFidelityTests.testFamilyCBackoffPairsToMondayNotThursdayDespiteTheSourceFootnote`.

## 11. Deload behavior

Family B: Monday/Tuesday 0.7×weight + "2/3 reps"; Thursday/Friday
0.5×weight + "1/2 reps." Family C: Monday/Tuesday unchanged weight;
Wednesday/Thursday/Friday 0.5×weight + "1/2 reps" (backoff exception:
reps unchanged). Both re-verified directly against the live workbooks
this pass, both already correctly modeled via
`DeloadPositionOverride(boundaryDayIndex:fullPositionFactor:halfPositionFactor:)`.

## 12. KNOWN CONFLICT — dual-reference fix (resolved)

`PrescriptionTemplate.pairedSlot` is a single reference historically used
for BOTH `LoadRule.linkedToPairedSlot` resolution AND
`SetCountRule.autoregulated`'s rating source
(`AutoregulationRatingResolver.rating(for:in:)` read the identical field
`StrengthMaterializer` reads for load). Family C's Friday backoff row
genuinely needs two DIFFERENT targets simultaneously in the real source:
load ← Monday-Push1's resolved weight; set-count rating ← Wednesday-
Push2's rating — re-confirmed directly against the live
`RP-PowerliftingHyp-5-Day.xlsx` twice now (`D42`/`H42` reference different
rows both times).

**History, preserved rather than erased:** the initial implementation
exposed this one-reference domain limitation and disclosed the resulting
mismatch (the backoff's rating incorrectly also read Monday) as a tracked
V1 simplification, rather than silently hiding it.

**Final V1 fix (this pass):** added
`PrescriptionTemplate.autoregulationReferenceSlot` — a second, purely
additive, optional cross-slot reference (with its own required
`.nullify` inverse, mirroring `pairedSlot`'s own). `nil` for every row
except this one (Family A, Family B, and every other Family C row are
completely unaffected — confirmed by
`testExistingSinglePairedSlotBehaviorUnaffectedForEveryOtherRow`).
`AutoregulationRatingResolver.rating(for:in:)` now resolves
`autoregulationReferenceSlot ?? pairedSlot`, so the backoff row's load
still correctly reads Monday while its autoregulation rating now
correctly reads Wednesday — reproducing the executable source exactly,
proven via RESOLVED behavior (real completed prescriptions carrying
different ratings on Monday vs. Wednesday), not merely stored slot IDs:
`testFamilyCBackoffLoadReadsMondayRatingReadsWednesdayResolved`,
`testFamilyCBackoffRatingUnaffectedByChangingMondayAlone`,
`testFamilyCBackoffRatingChangesWhenWednesdayChanges`. **No known
deliberate divergence from the recovered Family C executable source
behavior remains.**

**A second, related disclosed finding:** the source's own `MROUND(...,
2.5)` (Family B) vs. `MROUND(..., 5)` (Family C) rounding-unit difference
is a real, confirmed SOURCE FACT, but `StrengthProgressionRules` itself
carries no rounding-increment field at all — rounding is entirely
`EquipmentProfile.resolve()`'s job, supplied by whatever caller
materializes the program. This means the 2.5-vs-5 distinction is **not
currently enforced as a per-family generator invariant** — it only
manifests if a caller happens to supply matching per-family equipment
profiles, and nothing in current production code selects an
`EquipmentProfile` by `PowerliftingFamily`. Flagged as an unresolved
source-fidelity gap, not fabricated around. Test coverage:
`testEquipmentProfileRoundingMechanismItselfWorksForBothIncrements`
(proves the rounding mechanism itself is correct; does not claim the
generator enforces per-family rounding, because it doesn't).

## 13. Fidelity fixture strategy

One canonical per-family row table (`PowerliftingSourceFidelityTests.swift`)
compared programmatically against the generated graph, rather than dozens
of loosely-related hand assertions — mirroring the Hypertrophy Family A
golden-fixture pattern. Family B's fixture additionally includes the
filled canonical workbook's own real, computed Week-1-through-4 numbers
for all 15 rows, checked via direct `StrengthProgressionEngine` calls.

## 14. Dogfood result

`testDogfoodFamilyBWeekZeroMaterializationMatchesGoldenFixture`: a real
`StrengthMaterializer.materializeWeek` call (week 0, not a bypass) against
the generated Family B definition, using the filled workbook's own 10 real
RM calibration inputs, produces 4 real `Session`s containing all 15 real
`ExercisePrescription`s, whose materialized weight and set count match the
golden fixture exactly for every single row. This is the strongest proof
in this checkpoint: the full generator → template graph → materializer
pipeline reproduces the real source spreadsheet's own computed numbers,
not just structurally-plausible ones.

Family C has no filled numeric example to dogfood against numerically;
its structural completeness (all 16 rows, correct freeze/backoff/deload
wiring) is proven instead (§4, §13).

## 15. Explicit V2/source-dependent backlog

- ~~Resolve the KNOWN CONFLICT (§12)~~ — **done this pass** via
  `PrescriptionTemplate.autoregulationReferenceSlot`.
- Wire per-family `EquipmentProfile` rounding (§12) so Family B/C actually
  round to their own real source increments in production, not just
  whatever a caller happens to supply.
- RM self-calibration adjustment guidance (bump weight if first-week reps
  fall outside a target band) — explicitly deferred this pass, not
  implemented, not blocking.
- Peaking-phase content — genuinely missing source (RP's own admission
  it wasn't shipped); do not fabricate.
- Wire `isPowerliftingSourceVerified` into `LongTermPlanner` — deferred
  until this migration is proven regression-free in real use, mirroring
  Hypertrophy's own phased-activation discipline.
