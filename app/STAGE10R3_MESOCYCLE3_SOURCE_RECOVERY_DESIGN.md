# Stage 10R.3 — Mesocycle 3 ("Resensitization") Source Recovery: Evidence & Design

**Status: evidence/design only. Nothing implemented. Not committed, not
pushed.** Checkpoint `4dca40f` (Stage 10R.2A+2B) confirmed protected
before any work began: branch `main`, local `HEAD` == `origin/main` ==
`4dca40f`, working tree clean (only untracked `.DS_Store`/`xcuserdata`),
`4dca40f` confirmed an ancestor of `HEAD`.

All primary-source evidence below was extracted fresh, directly from the
real Excel workbooks (`/Users/stefankedling/Downloads/RP Diet/RP
Diet/...`) via `openpyxl`. Every claim is cited to an exact
file/sheet/cell/formula or explicitly marked as inference/unresolved.

---

## 1. Source artifacts inspected

All 11 Family A workbooks (`3 day full body_Novice.xlsx`, `3 day arms &
delts_Novice.xlsx`, `4 day full body.xlsx`, `4 day legs.xlsx`, `5 day
arms & shoulders.xlsx`, `5 day full body_Novice.xlsx`, `5 day full
body.xlsx`, `6 day arms & shoulders_novice.xlsx`, `6 day back &
chest.xlsx`, `6 day chest & back_novice.xlsx`, `6 day full body.xlsx`)
— every one confirmed to contain a `'Mesocycle 3 Resensitization'`
sheet (`wb.sheetnames`). `3 day full body_Novice.xlsx` was deep-dived
row by row (the shipped reference config); the other 10 were surveyed
for cross-workbook comparison. Prior derived docs
(`STAGE10R2_MESOCYCLE2_SOURCE_RECOVERY_DESIGN.md`,
`STAGE10R2_MESOCYCLE2_IMPLEMENTATION_REPORT.md`) were checked and
contain zero prior Mesocycle-3 groundwork — this stage starts from raw
evidence, not from a stale plan.

---

## 2. Exact 3-Day Full Body Mesocycle 3 structure

**Sheet**: `'Mesocycle 3 Resensitization'`. Header rows (1-4) byte-
identical instructional text to Mesocycle 1/2. No sheet-specific text
describing what "Resensitization" means, and no cell comments anywhere
in the sheet — the phase's intent is not stated in the source at all,
only demonstrated by its numbers.

**Duration — a structural difference, confirmed, universal**: only 3
total weeks — `H8='Week 1'`, `N8='Week 2'`, `T8='Week 3: Deload'` — not
Mesocycle 1/2's 4 progressive + 1 deload. Confirmed identical in every
one of the 11 workbooks (identical week-header labels).

**Day 1 — Push Emphasis, rows 11-17 (7 categories, not 8)**:
Horizontal Push(3), Incline Push or Front Delts(3), Side Delts(2),
Vertical Pull(2), Horizontal Pull(2), Hamstrings Isolation(1), Quads(1).
**"Chest Isolation or Triceps" is absent** — confirmed missing versus
Mesocycle 1's 8-category Push day.

**Day 2 — Legs Emphasis, rows 21-27 (7 categories)**: Quads(3),
Hamstrings Hip Hinge(3), Side Delts(2), Vertical Pull(2), Horizontal
Pull(2), Incline Push or Front Delts(1), Horizontal Push(1).

**Day 3 — Pull Emphasis, rows 31-38 (8 categories)**: Vertical Pull(3),
Horizontal Pull(3), Rear Delts or Side Delts(3), Biceps(2), Horizontal
Push(2), Incline Push(2), Glutes(1), Hamstrings Isolation(1).

**Total: 22 categories** (7+7+8), versus Mesocycle 1's 24 and Mesocycle
2's 27. **No superset markers anywhere** — column A (where Mesocycle
2's `'Super set this exercise'`/`'with this one'` text lives) is
completely empty for every row, confirmed by exhaustive scan, and
confirmed absent identically in all 11 workbooks (not just this one) —
**Mesocycle 3 has no superset mechanic, positively established from
source, not merely absent from current TrainingOS code.**

**RM basis**: every row has its own independent `G`-column 10RM input
cell, same `.rm10` basis as Mesocycle 1/2.

**Load formulas** (universal across all 11 workbooks, zero row-level
exceptions found in any of them):
- Week 1: `J = MROUND(G, 5)` — **factor 1.0**, no reduction at all
  (versus Mesocycle 1's 0.85, Mesocycle 2's 0.75).
- Week 2: `P = MROUND(J*1.05, 5)` — a single `×1.05` step off the
  resolved Week-1 value. No Week 3/4 exists — only 2 progressive weeks.
- Deload (Week 3): `V = J` (Day 1/2, full weight, unchanged) or `V =
  MROUND(J*0.5, 5)` (Day 3, halved) — the same day-position-boundary
  mechanism as Mesocycle 1/2 (`ceil(dayCount/2)` boundary, here at day
  index 2 for the 3-day config), reapplied to this mesocycle's own
  Week-1 value.

**Rep/RIR**: every row, every week, every workbook — literal `'3/fail'`,
**identical for both progressive weeks** (no decline to 2/fail or
1/fail, since there are structurally only 2 progressive weeks to
decline across). Applying the already-locked rule: **RIR 3 throughout,
no RIR progression** — not a new semantic form, just a schedule with
only one value, universal across all 11 workbooks.

**Set-count / rating-pairing**: every row's formula is "own baseline +
an external row's rating" — the Mesocycle-2 "partner reads the
primary's own baseline" pattern does not appear anywhere. Full 22-row
`(dayIndex,slotIndex) -> (pairedDayIndex,pairedSlotIndex)` table
recovered (§7 below).

**Deload**: same mechanism as Mesocycle 1/2 (2-set constant, day-
position weight split, `'1/2 reps of Week 1'` text) — no partner-
omission logic needed, since no supersets exist to omit.

**Cross-sheet references**: exhaustive search — zero. No formula in any
of the 11 workbooks' Mesocycle 3 sheets references 'Mesocycle 1' or
'Mesocycle 2', and no cross-sheet `!` syntax or `defined_names` entries
exist. **Mesocycle 3 requires a completely fresh, independent 10RM
entry — identical conclusion to Mesocycle 1 -> 2, confirmed
independently rather than assumed to carry over.**

**One confirmed source inconsistency, not a blocker**: a few rows'
set-count formulas reference their target's Week-2 rating column (S)
where most reference Week-1 (M) — e.g. row 21 uses `S17` where its
peers use `M`-column references. This doesn't change which *row* is
targeted (unambiguous either way) and doesn't affect TrainingOS, since
the engine already reads "most recently logged rating" dynamically,
never a fixed literal cell (the same design established for Mesocycle
1). Flagged for completeness, not a decision point.

---

## 3. What "Resensitization" actually means (mechanically, not by name)

| Axis | Mesocycle 1 | Mesocycle 2 | Mesocycle 3 | Basis |
|---|---|---|---|---|
| Categories/day (3-Day Full Body) | 8 | 9 (8 + 1 partner) | **7/7/8 (22 total)** | PRIMARY — row count |
| "Chest Isolation or Triceps" present? | Yes | Yes | **No** | PRIMARY — absent from all 3 days |
| Supersets | No | **Yes** (3 pairs) | **No** | PRIMARY — positively absent |
| Progressive weeks | 4 | 4 | **2** | PRIMARY — sheet header |
| Total weeks (incl. deload) | 5 | 5 | **3** | PRIMARY |
| Week-1 load factor | 0.85 | 0.75 (0.6 partner) | **1.0** | PRIMARY — universal, no exceptions |
| Later-week multipliers | ×1.05/1.075/1.1 | ×1.05/1.075/1.1 | **×1.05 only** | PRIMARY |
| RIR schedule | 3,3,2,1 | 3,3,2,1 | **3,3** (flat) | PRIMARY |
| Fresh RM required | Yes | Yes | **Yes** | PRIMARY — zero cross-sheet refs, all 3 mesocycles |
| Deload mechanism | day-boundary split, 2 sets, half reps text | same | **same** | PRIMARY |

**SOURCE-PROVEN DIFFERENCE**: category count/composition, superset
presence, week count, load factor, multiplier count, RIR schedule
length. **NO EVIDENCE OF DIFFERENCE**: RM basis (`.rm10`), fresh-RM
requirement, deload mechanism shape, autoregulation/rating-pairing
mechanism itself (still present, just a new 22-row table).

Mechanically, "Resensitization" is: fewer exercises, no supersets, full
working weight from day one (no ramp-in), a short 2-week ramp instead of
4, and an early exit to deload — consistent with (but not derived from)
the RP-methodology idea of a short, lighter-volume "reset" phase after
sustained accumulation. This interpretation is offered only as
orientation, never as a source citation — everything actionable above is
cited to cells/formulas, not to this framing.

---

## 4. Mesocycle 2 -> 3 transition

Same conclusion as Mesocycle 1 -> 2, independently re-verified rather
than assumed: **exhaustive cross-sheet search found zero references**
from any Mesocycle 3 sheet to Mesocycle 1 or 2, in any of the 11
workbooks. Nothing carries across the boundary — not RM, not load, not
actual reps, not RIR, not set counts, not ratings, not autoregulation
state, not superset relationships (none exist to carry). **Mesocycle 3
requires a fresh, independent RM entry**, exactly like Mesocycle 2 did.

---

## 5. Rep/RIR semantics

No new notation form. Every row, every week: literal `'3/fail'`. Applying
the already-established rule (N/fail = RIR N): **RIR 3 for both
progressive weeks** — the schedule is simply length-2 instead of
length-4, not a new prescription kind. No rep range, no fixed-rep row,
no failure notation beyond the already-modeled `.rir(_:)` case. Nothing
new required from `RepPrescriptionKind`.

---

## 6. Load progression

Universal (all 11 workbooks, zero row-level exceptions): Week 1 =
`MROUND(RM, 5)` (factor 1.0), Week 2 = `MROUND(Week1Resolved × 1.05, 5)`.
No further progressive week exists. No row anywhere deviates from this
factor. Actual performance never changes load (no formula references a
logged result). This is a **shorter multiplier array**, not a different
mechanism — `laterWeekMultipliers` for Mesocycle 3 is `[1.05]` (length
1) versus Mesocycle 1/2's `[1.05, 1.075, 1.1]` (length 3).

---

## 7. Set progression / rating-pairing

Every row still autoregulates via "own baseline + an external row's
rating," exactly the Mesocycle-1 mechanism — never the Mesocycle-2
partner-follows-primary pattern (confirmed absent). Full recovered
22-row table (0-indexed, `(dayIndex,slotIndex)`, day 0=Push/1=Legs/2=Pull,
slot index = row position within that day, source row numbers cited):

```
(0,0)->(1,6)  row11->row27   (0,1)->(1,5)  row12->row26   (0,2)->(1,2)  row13->row23
(0,3)->(1,3)  row14->row24   (0,4)->(1,4)  row15->row25   (0,5)->(1,1)  row16->row22
(0,6)->(1,0)  row17->row21

(1,0)->(0,6)  row21->row17   (1,1)->(2,7)  row22->row38   (1,2)->(2,2)  row23->row33
(1,3)->(2,0)  row24->row31   (1,4)->(2,1)  row25->row32   (1,5)->(2,5)  row26->row36
(1,6)->(2,4)  row27->row35

(2,0)->(0,3)  row31->row14   (2,1)->(0,4)  row32->row15   (2,2)->(0,2)  row33->row13
(2,3)->(0,3)  row34->row14   (2,4)->(0,0)  row35->row11   (2,5)->(0,0)  row36->row11
(2,6)->(1,1)  row37->row22   (2,7)->(0,5)  row38->row16
```

**Correction found during implementation (10R.3A):** the tuple for row37
was originally transcribed as `(2,6)->(1,6)` during synthesis of the raw
fork output into this document — self-inconsistent with its own row
citation, since row22 falls in Legs Emphasis's row range (21-27) at
0-based offset 1, not 6. Re-derived from the row citation and cross-
checked against Mesocycle 1's identical-category precedent (Glutes rated
by Legs' Hamstrings Hip Hinge, `threeDayFullBodyMesocycle1RatingPairings`
row39<-row24): the correct target is `(1,1)` (Legs Hamstrings Hip Hinge),
not `(1,6)`. Fixed here and in the shipped
`threeDayFullBodyMesocycle3RatingPairings` table before implementation —
never shipped with the error.

No row's formula references a PRIMARY's own baseline (the Mesocycle-2
superset-partner shape) — confirmed absent for all 22 rows.

---

## 8. Superset/pairing findings

**No supersets exist in Mesocycle 3** — positively established: column A
(where the "Super set this exercise"/"with this one" markers live) is
empty for every one of the 22 rows in the 3-Day Full Body config, and
empty for every Mesocycle 3 sheet across all 11 Family A workbooks
checked. This is a genuine mesocycle-to-mesocycle mechanic change, not
an oversight: the Mesocycle-2 superset mechanic does not continue into
Mesocycle 3.

---

## 9. Deload / final-week behavior

Week 3 is the deload — same mechanism as Mesocycle 1/2 (2-set constant
via `deloadSetCount`, day-position weight split at the `ceil(dayCount/2)`
boundary, `'1/2 reps of Week 1'` literal text). No partner-omission logic
needed (nothing to omit). **The already-known "which Week-1 actual set
result?" ambiguity is not resolved by Mesocycle 3 evidence** — no new
information bears on it; preserved exactly as unresolved, per instruction.

---

## 10. Exercise continuity implications

The already-accepted Mesocycle 1 -> 2 policy (visible/editable carry-
forward, a TrainingOS convenience, never source behavior) is **partially
reusable, not directly**: Mesocycle 3 drops "Chest Isolation or
Triceps" entirely and has fewer total slots (22 vs 24), so a literal
authored mapping table (mirroring `threeDayFullBodyMesocycle1ToMesocycle2`'s
exact shape and discipline) is required, listing only the categories
that genuinely exist in *both* Mesocycle 2 and Mesocycle 3 — every
Mesocycle-2-only row (the 3 former superset partners, and anything tied
to "Chest Isolation or Triceps") is simply left unmapped, falling
through to the same deterministic resolution a fresh instance already
uses, exactly like Mesocycle 1 -> 2's own unmapped partner rows already
do. This is a mechanical table-authoring task, not a policy change —
the *policy itself* (accepted, not re-litigated here) transfers
unchanged; only its per-transition data table needs a new, separately-
authored version.

---

## 11. Domain-model audit

**No new entity, no distortion needed.** `SourceCategorySlot`
(`isSupersetPartner`/`freezeAfterWeek`, both already optional/defaulted)
already represents "no superset, no freeze" correctly by simply never
setting either flag for any of the 22 Mesocycle-3 rows — the type was
already general enough, not because Mesocycle 3 was anticipated, but
because Stage 10R.2A's design happened to make both fields opt-in.
`SourceRatingPairing` is already a flat, per-mesocycle-scoped table —
a new top-level array, zero type changes. `RepPrescriptionKind` needs
nothing new (§5). `SourceRMCalibration`'s `(instance, exercise, rmType)`
scoping needs nothing new (§4, §12). The one genuine representational
gap: **Mesocycle 3's shorter 2-progressive-week / 3-total-week shape is
not yet representable by the day-focus generator's construction loop**,
which currently hardcodes `4` progressive `TrainingWeek` markers + a
fixed `lengthWeeks: 5` regardless of phase (§12) — this is a real,
necessary code change, not a domain-model gap; the `TrainingWeek`/
`ProgramDefinition.lengthWeeks` types themselves already support any
week count.

---

## 12. Current implementation audit (post-4dca40f) — what's reuse vs. genuinely new

Read directly from the current codebase (not assumed):

- **`HypertrophyProgramGenerator.sourceContent(for:)`** (a typed switch
  over `HypertrophyPhaseType`): needs exactly one new case —
  `.resensitization` returning the new Mesocycle-3 tables instead of
  throwing `phaseNotYetRecovered`. `currentVersion` needs bumping
  (3 -> 4), per this file's own established versioning discipline.
- **`makeSourceCategoryTemplate`**: needs **no new superset-factor
  constant** — since every Mesocycle-3 row has `isSupersetPartner:
  false`, the existing `weekOneFactor = isSupersetPartner ?
  metaboliteFocusPairedWeekOneFactor : primaryWeekOneFactor(for:
  phaseType)` branch always takes the `primaryWeekOneFactor(for:
  .resensitization)` path — and that case **already exists**, a legacy-
  path leftover (`.resensitization: return 1.0`), previously unverified
  for the day-focus path specifically. **This stage's own archaeology
  now confirms that pre-existing `1.0` value is source-accurate** — a
  genuine, welcome coincidence, not something to trust blindly going in.
- **A genuinely new required change, not previously flagged by name**:
  `generateDayFocusDriven` currently hardcodes `for _ in 0..<4 {
  TrainingWeek(isDeload: false) }` (4 progressive weeks) plus one deload
  week, and `ProgramDefinition(lengthWeeks: 5, ...)`, **unconditionally,
  regardless of phase**. Mesocycle 3 needs exactly 2 progressive weeks +
  1 deload (`lengthWeeks: 3`) — this loop and literal must become
  phase-aware. `laterWeekMultipliers` also needs a Mesocycle-3-specific
  `[1.05]` array (length 1) rather than the shared 3-entry constant.
  Neither of these was called out by the implementation-audit fork
  (which focused on content/formula reuse, not the week-count
  construction loop) — found by direct reasoning through the generator's
  own mechanics against the now-known 2-week structure. **This is the
  single most important correction this design doc makes to the
  Stage 10R.2 implementation report's own closing claim.**
- **`StartNextHypertrophyPhaseUseCase`**: the next-phase-type
  determination (`HypertrophyProgramJourney.orderedPhaseTypes` lookup)
  and the idempotency guard (`existingNextPhase`) are already fully
  generic — confirmed by direct read, zero changes needed for a 3rd
  phase. **Two genuinely hardcoded spots do need new code**, correcting
  the Stage 10R.2 report's overstated "zero changes" claim: (a) the
  `provenance: .sourced(file:..., sheet: "Mesocycle 2 Metabolite
  Focus", ...)` literal inside `start()` is hardcoded to Mesocycle 2's
  sheet name and needs to become phase-aware; (b) `carryForwardExerciseSelections`
  references the M1->M2 mapping table (`threeDayFullBodyMesocycle1ToMesocycle2`)
  by name, not generically — a Mesocycle-2->3 transition needs either a
  new table + a phase-aware branch, or the function refactored to accept
  the mapping table as a parameter.
- **`HypertrophyProgramJourney.orderedPhaseTypes`**: already lists all 3
  phases; `build()`'s loop is already phase-count-agnostic. No changes.
- **`SourceRMCalibration`/`RequiredSourceCalibrationsUseCase`**: already
  fully generic per-instance; confirmed no changes needed (§4).
- **`PhaseDetailViewModel`/`PhaseDetailView`**: the gating logic
  (`canStartNextHypertrophyPhase`, `nextHypertrophyPhaseTypeLabel` via
  `phaseTypeDisplayName`, which already has a `.resensitization` case)
  is already fully generic — confirmed by direct read, zero changes
  needed. The button will correctly read "Start Resensitization"
  automatically once the use case itself supports the transition.
- **Existing tests**: `HypertrophyBuiltInLibraryTests
  .testEveryBuiltInConfigurationBuildsAFullThreePhaseJourney` currently
  asserts 3-Day Full Body specifically throws `phaseNotYetRecovered` for
  `.resensitization` — this is the one existing test that must change
  (from "asserts the throw" to "asserts the real 3-phase journey
  succeeds") once Mesocycle 3 content ships.

---

## 13. Cross-workbook Family A comparison

Every finding in §2 confirmed **UNIVERSAL** across all 11 workbooks
(2+1 week structure, 1.0 Week-1 factor, no supersets, flat 3/fail RIR,
fresh-RM requirement) — zero exceptions found in any workbook, for any
row.

**The previously-flagged `4 day legs.xlsx` "extra 0.85/1.0 factors"
anomaly is now fully resolved, and it does NOT concern Mesocycle 3**:
those factors live in `4 day legs.xlsx`'s **Mesocycle 2** sheet, which
has 4 named day-tiers — "Heavy Quads"/"Heavy Glutes" (factors 1.0/0.85,
no supersets) and "High Rep Quads"/"High Rep Hams" (factors 0.75/0.6,
**with real superset pairs**, matching the 3-Day Full Body Mesocycle-2
pattern exactly). This is a genuine, **SPLIT-SPECIFIC (`.legs` only)**
two-tier mechanic layered on top of Mesocycle 2's already-recovered
shape — plausibly related to the already-known Mesocycle-1 Heavy Quads/
Glutes exception, but not independently traced in this pass. In
Mesocycle 3, the same "Heavy"/"High Rep" row-label naming persists
structurally (same day grouping) but **every row uses the universal 1.0
factor regardless of the label, and no supersets exist in either
"High Rep" day** — by Mesocycle 3, the tiering has become a leftover
descriptive label with no remaining behavioral effect. **Not relevant to
the 3-Day Full Body implementation scope**, and not something this
stage needs to model.

No other cross-workbook exceptions or formula inconsistencies found,
beyond `4 day legs.xlsx`'s already-known coarser rounding increment
(2.5 vs. the reference config's implicit finer rounding) — a display/
equipment-profile-adjacent difference, not a load-factor difference,
and out of this stage's scope regardless.

---

## 14. Source-vs-current gap matrix

| Behavior | Source | Current TrainingOS | Match | Required change | Confidence | Source location |
|---|---|---|---|---|---|---|
| Phase existence | 3rd mesocycle, "Resensitization" | `HypertrophyPhaseType.resensitization` exists; day-focus path throws | PARTIAL | New `sourceContent` case | High | `wb.sheetnames`, all 11 files |
| Categories/day | 7/7/8 (22 total), no "Chest Isolation or Triceps" | No content exists | MISSING | New `SourceDay`/`SourceCategorySlot` table | High | rows 11-17/21-27/31-38 |
| Sets/row | literal, 22 values | none | MISSING | New table (§2) | High | `I`-column, each row |
| Load factor | 1.0 primary, universal | `primaryWeekOneFactor(.resensitization) == 1.0` already present (legacy leftover, now confirmed correct) | MATCH (coincidental, now verified) | None for the value itself; wiring still needed | High | `J`-column formulas, all 11 files |
| Later-week multipliers | `[1.05]` only | Shared `[1.05,1.075,1.1]` constant, wrong length for M3 | MISSING | New Mesocycle-3-specific array | High | `P`-column formula |
| RIR | 3,3 flat | `RepPrescriptionKind`/`.rir` infra already correct; no M3 schedule exists | PARTIAL (infra ready, content missing) | New schedule constant | High | `K/Q`-column text |
| Progression weeks | 2 progressive + 1 deload (3 total) | Generator hardcodes 4+1 unconditionally | MISSING | Phase-aware week-count loop + `lengthWeeks` | High | week headers, all 11 files |
| Rating pairing | 22-row table | none | MISSING | New table (§7) | High | set-count formulas |
| Supersets | **none** | `isSupersetPartner`/`freezeAfterWeek` fields already support "none" via defaults | MATCH | None | High | column A, all 11 files, exhaustive |
| Deload | unchanged mechanism | `SourceCompatibleDeloadStrategy` already generic, untouched | MATCH | None | High | deload columns |
| Exercise continuity | source silent; TrainingOS policy already accepted | M1->M2 table exists; no M2->M3 table | MISSING | New authored mapping table | N/A (policy) | — |
| Calibration | fresh RM, universal | Already fully generic per-instance | MATCH | None | High | cross-sheet search, all 11 files |
| Transition (phase sequencing) | N/A (TrainingOS product decision) | `orderedPhaseTypes`/idempotency guard already generic | MATCH | None | High | code read |
| Transition (provenance/carry-forward wiring) | N/A | Hardcoded to Mesocycle 2 specifically | MISSING | Phase-aware provenance + new carry-forward table/branch | High | code read |
| Persistence/idempotency | N/A | Already proven generic (M1->M2 tests) | MATCH (expected) | None, but needs its own M2->M3 test coverage | High | — |

---

## 15. Proposed implementation slices

**10R.3A — Mesocycle 3 source content + week-count generalization**
- Purpose: add the real recovered 22-row content/pairing tables; make
  `generateDayFocusDriven`'s `TrainingWeek`-count loop and
  `ProgramDefinition.lengthWeeks` phase-aware (2 progressive + 1 deload
  for `.resensitization`, unchanged 4+1 for the other two); add the
  Mesocycle-3-specific `laterWeekMultipliers` (`[1.05]`); wire the new
  `sourceContent(for:)` case; bump `currentVersion`.
- Invariants: Mesocycle 1/2 output byte-identical to today (regression);
  `.resensitization` never silently reuses another phase's content/week
  count (the exact class of bug this whole recovery effort exists to
  prevent); no rep range or fixed-rep prescription invented; no superset
  representation invented for a mesocycle that source proves has none.
- Tests: exact Day 1/2/3 sequences, exact 22-row baselines, exact
  22-row pairing table, exact 1.0/1.05 load behavior, exact flat-3 RIR,
  exact 3-total-week structure (`lengthWeeks == 3`, exactly 2 non-deload
  `TrainingWeek`s + 1 deload marker), deload unchanged.
- Independently committable: yes.

**10R.3B — Mesocycle 2 -> 3 transition wiring**
- Purpose: the two genuinely-required `StartNextHypertrophyPhaseUseCase`
  changes identified in §12 — a phase-aware `provenance` (not hardcoded
  to Mesocycle 2's sheet name), and a new Mesocycle-2 -> 3 carry-forward
  mapping table (or a refactor accepting the mapping table as a
  parameter, whichever proves smaller once written). Confirmed
  necessary by direct code read, not assumed reusable — the phase-type-
  determination and UI-gating logic genuinely need zero changes and are
  NOT part of this slice.
- Invariants: never mutates Mesocycle 1 or 2's historical state; never
  auto-advances; idempotent; a Mesocycle-2-only row (no Mesocycle-3
  equivalent) never carries forward as if it did.
- Tests: real Mesocycle 2 -> 3 transition, fresh calibration required
  and never satisfied by Mesocycle 1 or 2's own, carry-forward only for
  categories that exist in both, "Start Resensitization" label/gating
  correct, idempotent, persists across relaunch.
- Independently committable: yes, depends on 10R.3A for real content
  but not for the transition mechanism itself.

*(No calibration-boundary slice, no new domain-model slice — §11/§12
already found the existing architecture sufficient beyond the two named
gaps above.)*

---

## 16. Proposed test matrix

| Area | Test proves |
|---|---|
| Day 1/2/3 structure | Exact 7/7/8 category sequence, "Chest Isolation or Triceps" genuinely absent |
| Week-1 sets | Exact 22 literal baseline values |
| RM behavior | `.rm10`, fresh calibration, never satisfied by Mesocycle 1 or 2's own |
| Load factors | Week 1 = 1.0×RM; Week 2 = Week1×1.05; no Week 3/4 progressive step exists |
| Rep/RIR semantics | RIR 3 both progressive weeks, never a fabricated rep count, `RepPrescriptionKind.rir` reused unchanged |
| Progression/week count | `lengthWeeks == 3`; exactly 2 non-deload `TrainingWeek`s + 1 deload; materializing weekIndex 2 correctly fails/is inapplicable rather than silently producing a 3rd progressive week |
| Rating relationships | Exact 22-row pairing table |
| Pairing/superset behavior | Every Mesocycle-3 row has `isSupersetPartner == false`; no partner-style set-count formula anywhere |
| Final-week/deload | 2-set constant, day-boundary weight split, unchanged mechanism, no partner omission needed |
| Transition from real Mesocycle 2 | Real production path: calibrated M2 -> "Start Resensitization" -> fresh M3 calibration -> materialized Day 1 |
| Calibration isolation | Neither Mesocycle 1's nor Mesocycle 2's calibration satisfies Mesocycle 3's requirement |
| Exercise carry-forward implications | Categories present in both M2 and M3 carry forward when compatible; "Chest Isolation or Triceps" (M2-only) and former superset-partner rows never attempt to carry forward (correctly absent from the mapping table) |
| Idempotency | Repeated "Start Resensitization" never duplicates phase/instance |
| Persistence/relaunch | Transition + calibration survive a simulated relaunch |
| No duplicate sessions | Single materialization, no double-booking |
| Mesocycle 1 regression | Full existing suite stays green, byte-identical output |
| Mesocycle 2 regression | Full existing suite stays green, byte-identical output |

All 835 existing tests must remain green, unmodified in intent, except
the one named, deliberate update in §12
(`testEveryBuiltInConfigurationBuildsAFullThreePhaseJourney`).

---

## Sections 17-21 (checkpoint status, mismatches, decisions required, etc.)
reproduced in full in the chat report accompanying this document, per
the request's required structure — not duplicated here at length.
