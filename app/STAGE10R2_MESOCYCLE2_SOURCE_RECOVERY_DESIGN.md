# Stage 10R.2 — Mesocycle 2 Source Recovery: Evidence & Design

**Status: 10R.2A (source content) and 10R.2B (transition wiring)
IMPLEMENTED, tested, and accepted per the user's "no manual acceptance
loop" authorization.** See `STAGE10R2_MESOCYCLE2_IMPLEMENTATION_REPORT.md`
for the full implementation report. This document remains the evidence/
design record this implementation was built from.

Checkpoint `413eea4` (Stage 10R.1B-1D + Source RM Calibration + UX
correction) was confirmed protected before any implementation began:
branch `main`, local `HEAD` == `origin/main` == `413eea4`, working tree
clean (only untracked `.DS_Store`/`xcuserdata`), `413eea4` confirmed an
ancestor of `HEAD`.

All primary-source evidence below was extracted **fresh, directly from
the real Excel workbooks** (`/Users/stefankedling/Downloads/RP Diet/RP
Diet/...`) via `openpyxl`, not from old scratchpad text dumps (used only
as a cross-check). Every claim is cited to an exact file/sheet/cell or
formula. Anything not cited that way is explicitly labeled inference or
a TrainingOS product decision, never presented as source fact.

---

## 1. Source artifacts inventory

| Artifact | Family | Mesocycle 2 content | Provenance | Confidence |
|---|---|---|---|---|
| `.../Male physique template/Original templates/*.xlsx` (11 files: 3-day full body, 3-day arms&delts, 4-day full body, 4-day legs, 5-day arms&shoulders, 5-day full body ×2, 6-day arms&shoulders, 6-day back&chest ×2, 6-day full body) | A | **Yes** — every file has a `'Mesocycle 2 Metabolite Focus'` sheet | **PRIMARY** | High |
| `.../Powerlifting/RP-PowerliftingStr-4-Day.xlsx` | B | **No** — single `'c.) Mesocycle'` sheet only | **PRIMARY** | High |
| `.../Powerlifting/RP-PowerliftingHyp-5-Day.xlsx` | C | **No** — single `'c.) Mesocycle'` sheet only | **PRIMARY** | High |
| `.../Strength/Strength_Program_1.xlsx`, `Strength_Program_2.xlsx` | D (unshipped) | No — identical single-mesocycle 3-sheet shape | **PRIMARY**, contextual only | High |
| Scratchpad `3day_original_downloads.txt`/`3day_tables.txt`/`extracted/*` | A/B/C | Partial, Mesocycle-1-focused | Prior derived extraction, re-verified where reused | Superseded by fresh extraction above |
| `SOURCE_PROGRAM_MANIFEST.md`, `PROGRAM_LOGIC_SPEC.md`, `PROGRAMMING_SYSTEM_MODEL.md`, `STAGE3_DECISION_MEMO.md` | A | Prior recovery + **already-approved product decisions** | **DERIVED** (docs) but citing real cell formulas, and containing binding prior decisions (A1, A2) | High for cited formulas; decisions already resolved |
| `HypertrophyProgramGenerator.swift`, `HypertrophyProgramJourney.swift`, `HypertrophyConfiguration.swift` | A | Current implementation | **DERIVED** (code) — proves what exists, not what source says | N/A — implementation evidence only |

---

## 2. Mesocycle structure by family

### Family A (Hypertrophy) — HAS Mesocycle 2

Confirmed uniform across all 11 workbooks: sheet `'Mesocycle 2 Metabolite
Focus'`, header block byte-identical to Mesocycle 1 (same instructions,
same `Exercise/Sets/Weight/Rep Goal/Rep Results/*Rating` columns per
week, `Week 1..4` + `Week 5: Deload`). No transition-specific text
anywhere.

**3-Day Full Body deep dive** (the shipped reference config):

- Same day names as Mesocycle 1 (Push/Legs/Pull Emphasis), same 8
  categories per day, **plus one new mechanic: an explicit superset**,
  adding a 9th row per day. Example, Push Emphasis:
  - Row 11 `Horizontal Push` (standalone)
  - Row 12 `Chest Isolation or Triceps` — cell `A12: 'Super set this exercise'`
  - Row 13 `Incline Push or Front Delts` — cell `A13: 'with this one'` (superset partner)
  - Row 14 `Incline Push or Front Delts` (separate standalone occurrence — same category appears twice in the day, same pattern as Mesocycle 1's `.quads` double-occurrence)
  - Rows 15-19: Side Delts, Vertical Pull, Horizontal Pull, Hamstrings Isolation, Quads
  - Confirmed one superset pair per day (3 total for this config), same mechanic confirmed present in every other Family A workbook checked (5-day, 4-day-legs, 6-day-back&chest, 3-day-arms&delts) — **universal Mesocycle 2 mechanic, not config-specific.**
  - Both categories in the example pair (`Chest Isolation or Triceps`, `Incline Push or Front Delts`) already exist in the Mesocycle-1 `SourceHypertrophyCategory`/`sourceCategoryResolvedExerciseName` resolution table — no new category types appear likely, though full 3-day extraction of all pairs is still needed at implementation time to confirm this holds for every pair.

- **RM basis**: every row has its own `G`-column 10RM input cell.
  Exhaustive search (grep every formula for `!` cross-sheet refs or
  "Mesocycle" text; `wb.defined_names` checked — empty) found **zero**
  references from Mesocycle 2 to Mesocycle 1, in any of the 5 workbooks
  spot-checked. **Mesocycle 2 requires a completely fresh, independent
  10RM entry per exercise — nothing carries forward structurally.**

- **Load formula**: standalone/primary rows: Week 1 = `MROUND(G*0.75,
  5)` — **0.75, not Mesocycle 1's 0.85** (a real, confirmed difference).
  Superset partner rows: Week 1 = `MROUND(G*0.6, 5)` off the partner's
  **own** independently-entered RM (not a fraction of the primary's
  resolved weight) — this exactly matches the pre-existing, previously
  build-only-verified TrainingOS constant
  `HypertrophyProgramGenerator.metaboliteFocusPairedWeekOneFactor = 0.6`.
  Weekly multipliers weeks 2-4: `×1.05/1.075/1.1` off the resolved
  Week-1 value — **identical to Mesocycle 1**.
  (`4 day legs.xlsx` shows additional `0.85`/`1.0` factors, likely the
  already-known Heavy-Quads/Glutes exception carrying into Mesocycle 2 —
  flagged for implementation-time confirmation, not deep-dived here.)

- **Rep/RIR**: every row, every week — literal `'3/fail'` (weeks 1-2),
  `'2/fail'` (week 3), `'1/fail'` (week 4) — **identical schedule to
  Mesocycle 1**. Applying the already-accepted rule: RIR 3, 3, 2, 1. No
  semantic change for Mesocycle 2.

- **Set count / autoregulation**: same `*Rating` column mechanism, but
  **the pairing web differs from Mesocycle 1's**. Standalone rows pair
  cross-day exactly like Mesocycle 1. Superset partner rows do **not**
  reference their own baseline at all — traced directly: `O13 =
  I12+(M31)`, `O27 = I26+(M37)`, `O39 = I38+(S16)` — every partner row's
  set-progression formula instead reads the **primary partner's own**
  `I`-column baseline plus the same rating source the primary uses.
  Confirmed identical for all 3 pairs in the 3-Day Full Body workbook —
  a genuinely new mechanic (Mesocycle 1's paired accessory used a flat,
  never-autoregulated `[2,2,2,2]` schedule; Mesocycle 2's superset
  partner instead tracks the primary's own autoregulated count). Full
  24-slot pairing-table extraction (mirroring Slice 1B's table) was not
  completed in this pass — proven from 3 representative pairs; exhaustive
  per-slot extraction is mechanical, deferred to the implementation
  slice.

- **Deload**: identical mechanism to Mesocycle 1 (fixed 2-set constant,
  day-position weight split at the same `ceil(dayCount/2)` boundary,
  `'1/2 reps of Week 1'` text). **Superset partner rows have no deload
  columns at all** — completely blank cells, no formula, nothing. This
  exact fact is **already a resolved product decision**:
  `STAGE3_DECISION_MEMO.md` Decision A2 (resolved) — omit the superset
  partner during deload week, represented as `DeloadExerciseAction.omit`
  set explicitly on that one confirmed prescription, never a generic
  "blank cell means omit" rule. My independent re-extraction confirms
  the same blank-cell fact the decision was based on — **no new decision
  needed here, just implementation.**

### Family B (Powerlifting Strength) — NO Mesocycle 2

`RP-PowerliftingStr-4-Day.xlsx` contains exactly 3 sheets: `a.)
Instructions for Use`, `b.) Initial Data Entry Sheet`, `c.) Mesocycle`
(singular, no "1"/"2" suffix, Week 1 → Week 5: Deload only). **There is
nothing to recover for Mesocycle 2 in Family B — it does not exist in
the source.**

### Family C (Powerlifting Hypertrophy-block) — NO Mesocycle 2

`RP-PowerliftingHyp-5-Day.xlsx` has the identical single-mesocycle
3-sheet shape. **Same conclusion: no Mesocycle 2 exists for Family C.**

**Important side finding, unrelated to Mesocycle 2 but directly relevant
to "can Family C be faithfully implemented":** resolving Family C's
previously-flagged rep-goal placeholder required reading every row's
real category assignment, which proved the **already-shipped Family
B/C Mesocycle 1 content has fidelity gaps well beyond the one known
placeholder**:

- Family C's rep-goal placeholder is **now resolved**: the real
  non-deload schedule is `3/fail, 3/fail, 2/fail, 1/fail` (RIR 3,3,2,1
  — identical to Family A), not the shipped `.rir(8)` placeholder. One
  proven exception: row 41 (Friday's first exercise) is `.../2/fail`
  at week 4 too (stays RIR 2, never reaches RIR 1).
- A second, distinct prescription form exists at row 42 (Friday's
  second exercise): every week's cell literally reads `"1/2 Monday's"`
  (not "N/fail" at all) — a rep count computed weekly as half of a
  *different specific exercise's actual performed reps that same week*.
  **Conflict found, not resolved**: the sheet's own footnote (rows
  54-55) describes this as "1/2 Thursday's," but the cell text and the
  row's structural day-reference both point to Monday. Footnote and
  cell content disagree — flagged, not silently picked.
- Family C's real day/category structure is **completely different**
  from the shipped `PowerliftingProgramGenerator.generateFamilyC`
  (which models one exercise per day; source has 3 exercises per day on
  4 of 5 days, a wholly different category set — see the fork's full
  table, reproduced in §16 below).
- Family B's real day/category structure also differs substantially
  from shipped code (4 exercises/day on most days vs. today's 1), though
  the Triples-day pairing concept (Monday/Thursday) is loosely present.
- Set-count baselines vary per row (2/3/5, not shipped code's uniform 3)
  and reference a real, row-specific rating-pairing web, not today's
  generic self-contained autoregulation.

**This is a pre-existing Stage 4B content-fidelity gap, not something
Stage 10R.2 introduces.** It does not block Family A Mesocycle 2
recovery, which can proceed independently, but it means **Family C (and
to a lesser extent Family B) cannot currently be called faithfully
implemented at Mesocycle-1 level**, well beyond the single previously-
known placeholder. Recovering it properly is its own content-recovery
task on the scale of Family A's original Slice 1A/1B, out of scope for
this stage.

---

## 3. Mesocycle transition — recovered behavior

Applying the checklist from the request directly, backed by the
evidence above and the already-resolved `STAGE3_DECISION_MEMO.md`
Decision A1:

| # | Question | Answer | Basis |
|---|---|---|---|
| A | Fresh RM calibration required? | **Yes** | PRIMARY — zero cross-sheet references anywhere |
| B | Any value carried forward? | **No** | PRIMARY — same exhaustive search |
| C | Exercise continuity required? | **Unresolved** (structural continuity only — same category set; no semantic-continuity evidence) | PRIMARY (absence of evidence) |
| D | Exercise reselection expected? | Not stated either way | Source silent |
| E | Set-count reset? | **Yes** — new baseline sets, fresh autoregulation | PRIMARY — Mesocycle 2 has its own literal baseline cells and its own (different) pairing web |
| F | Load reset? | **Yes** — fresh RM × new factor (0.75/0.6) | PRIMARY |
| G | RIR reset? | N/A — RIR schedule (3,3,2,1) is identical, not something that "resets" | PRIMARY |
| H | Volume progression across the boundary? | No — no formula connects them | PRIMARY |
| I | Any use of Mesocycle 1 performance? | **No** | PRIMARY — exhaustive search, zero hits |
| J | User decision/input at the boundary? | **Yes, required** — a fresh RM entry per exercise (same `SourceRMCalibration` mechanism already built) | PRIMARY (fresh RM requirement) + existing architecture |
| K | Automatic transition vs. explicit user action? | **Explicit, user-initiated** — already a resolved TrainingOS design decision, not source-derived (source doesn't address app UX at all) | `PROGRAMMING_SYSTEM_MODEL.md` §5.1: `ProgramJourney.transitionTrigger: .userInitiated` — "V1: the user explicitly starts the next phase; no fixed-duration auto-advance" |

**Direct answer to the calibration-architecture question posed in the
request**: the source agrees with the already-accepted
`SourceRMCalibration` scoping (`ProgramInstance` + `Exercise` +
`RMType`, no silent inheritance). **No conflict, no architecture change
needed for this reason.** A new `ProgramInstance` for Mesocycle 2
already gets fresh-calibration-required behavior for free, with zero
code changes, because the scoping is already per-instance, not
per-user-per-exercise.

One documentation-currency note, not a conflict: `PROGRAMMING_SYSTEM_MODEL.md`
§5.1 describes the next phase's Week-1 RM as coming from "(a) a starting
recommendation the engine proposes using the user's `PerformanceProfile`,
or (b) a calibration flow." Only (b) was ever built (Stage 10R.1C/D); (a)
was aspirational design language, never implemented, and is inconsistent
with Stage 10R.1D's explicit "never estimate, never derive automatically"
rule for source-derived programs. This doc should be corrected at
implementation time to state only (b) applies for `.rmBased` source
families — flagged, not fixed in this pass (doc-only, no code claims
otherwise).

---

## 4. Exercise continuity — source evidence only

**STRUCTURAL CONTINUITY (proven)**: Mesocycle 2 uses the same day names
and largely the same category set as Mesocycle 1, in the same row
positions (plus the new superset-partner rows). This is directly
observable from the sheet layout.

**SEMANTIC CONTINUITY (not found)**: no formula, cell reference, or
instructional text anywhere ties a Mesocycle 2 row to the *specific*
exercise the athlete chose in Mesocycle 1. The source workbook doesn't
model "the athlete's Mesocycle 1 choice" as data at all — each mesocycle
sheet independently lists its own category rows with their own dropdown
validation, exactly like Mesocycle 1's own `sourceCategoryResolvedExerciseName`-style
resolution. **Whether the athlete is intended to keep the same movement
is genuinely unresolved by the source** — this is a real product
decision (§20).

---

## 5. RM calibration

- Required `RMType`: `.rm10` (same basis as Mesocycle 1's primary rows);
  superset partner rows also use `.rm10` off their own G-column cell.
- Manually entered, never derived: confirmed (no formula estimates it
  anywhere in any Family A workbook, consistent with the already-accepted
  permanent rule).
- No previous RM is displayed/referenced by any Mesocycle 2 formula.
- **The already-accepted rule stands, unmodified: no estimated 1RM, no
  RM-estimation formula, literal source RM inputs remain literal.**
  Nothing in the Mesocycle 2 evidence contradicts this.

---

## 6. Rep/RIR semantics

No change from the already-accepted Stage 10R.1D semantics. Every
Mesocycle 2 primary/standalone row and every superset partner row is
**RIR-only** (`"N/fail"` → `.rir(N)`), schedule `3, 3, 2, 1` across
weeks 1-4, identical to Mesocycle 1. No genuine rep range exists in any
Family A Mesocycle 2 sheet (same conclusion as Mesocycle 1 — none was
found). No fixed-rep prescription exists in Family A Mesocycle 2 at all
(unlike Family B's Triples, which is a Family B/Mesocycle-1-only
mechanic, and irrelevant here since Family B has no Mesocycle 2).

---

## 7. Load progression

| | Mesocycle 1 primary | Mesocycle 2 primary | Mesocycle 2 superset partner |
|---|---|---|---|
| Week 1 factor | 0.85 | **0.75** | **0.6** (off own RM) |
| Weeks 2-4 multipliers | ×1.05/1.075/1.1 | ×1.05/1.075/1.1 (identical) | ×1.05/1.075/1.1 (identical) |
| Rounding | `MROUND(_, 5)` → `EquipmentProfile.resolve` | same | same |
| Affected by Mesocycle 1 results? | N/A | **No** | No |
| Predetermined by source? | Yes | Yes | Yes |
| Differs by exercise/slot? | No (uniform factor) | No (uniform 0.75, except the flagged `4 day legs.xlsx` anomaly) | No (uniform 0.6) |

The requested future "load-first" TrainingOS overlay is explicitly
**not** addressed here, per instruction — this section is source
recovery only.

---

## 8. Set progression

- Baseline sets: literal per-row values in Mesocycle 2's own `I` column
  (not yet exhaustively extracted per-row for all 3 days — mechanical,
  deferred to implementation).
- Weekly changes: same `+rating`-based autoregulation formula shape as
  Mesocycle 1, `AutoregulatedSetCount`-equivalent.
- Feedback source: standalone rows pair cross-day like Mesocycle 1;
  superset partner rows pair to their **own primary's** baseline+rating,
  a new mechanic (§2).
- Mesocycle 1's ending volume does **not** carry over — no formula
  reference found.
- Deload set behavior: unchanged, fixed 2-set constant, same as
  Mesocycle 1; superset partner omitted entirely (Decision A2).

`AutoregulatedSetCount`'s existing shape (`baselineSets`,
`applyRatingOnFinalWeek`, `freezeAfterWeek`, `treatMissingRatingAsNoChange`)
already supports everything Mesocycle 2's standalone rows need
unchanged. The superset partner's "pair to the primary's own baseline"
mechanic needs a **new authoring-time reference target**, but this
already exists structurally: `PrescriptionTemplate.pairedSlot` already
supports "read this other row's rating," just needs to be set to the
primary partner (not a cross-day standalone slot) for these specific
rows. No new domain type needed.

---

## 9. Deload — additional evidence found

Mesocycle 2 archaeology adds no new evidence resolving the already-known
open question (which Week-1 set's actual performance a "half of Week 1"
deload instruction references when a row has multiple sets with
different logged reps). Deload week's own rep text is identical
(`'1/2 reps of Week 1'`), and the "Rep Goal"/"Rep Results" column
separation is identical to Mesocycle 1's. **Preserved as unresolved,
exactly as it already is** (`StrengthReasonCode.deloadRepsRequireLoggedPerformanceData`).
This does not block the rest of Mesocycle 2 recovery — it's already
architecturally isolated to `SourceCompatibleDeloadStrategy.resolveDeloadRepGoal`,
shared infrastructure Mesocycle 2 reuses unchanged.

---

## 10. Family C — confidence summary

- **PROVEN**: real rep-goal schedule (RIR 3,3,2,1, one Friday exception).
- **PROVEN**: shipped day/category structure is wrong (one exercise/day
  vs. real 3/day on 4 of 5 days).
- **PROVEN**: shipped set-count baselines/pairing web is wrong (uniform
  3 + no pairing vs. real per-row 2/3/5 + row-specific pairing).
- **UNRESOLVED**: row 42's Monday-vs-Thursday footnote conflict.
- **NOT FULLY ENUMERATED**: per-row RM type (5RM/8RM) across all ~15
  rows (column exists, varies, not exhaustively catalogued this pass).
- **Conclusion**: Family C cannot currently be called faithfully
  implemented, on multiple axes beyond the single previously-known
  placeholder. This is pre-existing (Stage 4B), not a Mesocycle-2-stage
  problem, and out of this stage's scope to fix — flagged for its own
  future recovery pass. Family C has **no Mesocycle 2** regardless.

---

## 11. `rollForward` implications

Read in full. Confirmed behavior: rolls every non-SteadyState component
of a `TrainingMix` forward **exactly one week**, within one already-
materializing `ProgramInstance`'s own weeks — reads real prior results
via `AutoregulationRatingResolver`/`ProgramWeekGrouping.nextWeekIndex`,
schedules+accepts via `SchedulingPipeline`/`AcceptScheduleProposalUseCase`.

**It has no concept of a mesocycle-boundary transition** (moving to a
different `ProgramDefinition`/`ProgramInstance` entirely) — that's a
structurally different operation, not something `rollForward` does or
was designed to do.

**Call sites**: exhaustively confirmed **zero production call sites** —
every reference is in `TrainingOSTests/` (`HypertrophyMesocycle1SourceProgressionTests.swift`,
`TacticalPlanningOrchestrationTests.swift`, `HypertrophyV2EndToEndTests.swift`
×9, `MixedModalityOrchestrationTests.swift`). This means **week-to-week
progression within Mesocycle 1 itself is already an unwired gap today**,
independent of Mesocycle 2 — Mesocycle 2 doesn't create this gap, it
just makes it more visible (a real user progressing through Mesocycle 1
week-to-week already needs this wired; Mesocycle 2 needs it too, for the
exact same reason, plus a *second*, structurally different mechanism for
the mesocycle-boundary transition itself).

**Where a production call would logically need to occur** (design note,
not an implementation): a trigger that detects "the current week's
Session(s) are complete, and I need the next week materialized" —
logically near `CompleteSessionUseCase`/`StartSessionUseCase` or a
dedicated weekly-rollover check, reading the instance's own
`AutoregulationRatingResolver` state exactly as `rollForward` already
expects.

**Lifecycle/idempotency risks**: `rollForward`'s own internal
`materializeOnceCalibrationComplete`-equivalent re-entrancy protection
was hardened in Stage 10R.1C for the *first-window* materialization path
specifically; `rollForward` itself was not audited for the same
duplicate-materialization risk class in this pass — flagged as a real
risk to check before any production wiring, not confirmed safe or
unsafe here.

**Calibration-gating interaction**: `rollForward`'s `strengthSlotContext`
already correctly reads `instance.sourceRMCalibration(for:rmType:)` for
`weekIndex == 0` (consistent with the accepted Stage 10R.1C/D design,
confirmed, no conflict) — but week-to-week rolls beyond week 0 don't
need a *new* calibration at all (RM stays fixed for the whole mesocycle,
per §5-7 above), so calibration gating is a first-window-only concern,
orthogonal to `rollForward`'s per-week job.

**Substitution interaction**: not specifically audited this pass — the
existing "GOING FORWARD" substitution hook
(`SubstituteExerciseUseCase.resolvedExercise`) already runs at
materialization time generically; `rollForward` should inherit this for
free since it materializes through the same path, but this needs direct
confirmation at implementation time, not assumed here.

**Not implemented in this pass, per explicit instruction.**

---

## 12. `ProgramInstance`/mesocycle domain model

**This question is already answered by an existing, approved product
decision** — `STAGE3_DECISION_MEMO.md` Decision A1 (resolved):
Mesocycle 2 is **a new, independent `ProgramDefinition`** (Metabolite
Focus content) + **a new `ProgramInstance`** (once the user starts it),
sequenced via the **already-existing** `TrainingPlan.orderedPhases` +
`TrainingPhase` machinery — explicitly **not** a new entity type, and
explicitly **not** a phase/component inside the same `ProgramInstance`.

Confirmed by direct code read: `HypertrophyProgramJourney.build`
(`TrainingOS/Application/UseCases/HypertrophyProgramJourney.swift`) is
**real, already-written, already-tested code that does exactly this** —
creates 3 independent `ProgramDefinition`/`TrainingPhase`/`ProgramInstance`
triples in sequence, attached to one `TrainingPlan`, deliberately not
inventing a separate `ProgramJourney` entity (its own doc comment: *"No
new 'ProgramJourney' entity exists — `TrainingPlan.orderedPhases`
(pre-existing since Stage 1) already provides the sequencing."*). **It
has zero production call sites** — proven only by tests
(`HypertrophyProgramJourneyTests.swift`, `HypertrophyBuiltInLibraryTests.swift`).

**Compared against the request's checklist**:
- Calibration scoping: already correct — `(ProgramInstance, Exercise,
  RMType)` naturally gives Mesocycle 2 fresh-calibration-required
  behavior with zero changes, since it's a new instance.
- Exercise continuity: naturally independent per instance (consistent
  with §4's finding that source doesn't require continuity either) —
  no change needed unless the product decision in §20 says otherwise.
- History: `PerformanceProfile`/`ExercisePerformanceProfile` are
  per-exercise, not per-instance — already correctly NOT reset by a new
  `ProgramInstance` (a new mesocycle doesn't erase the athlete's lifting
  history, consistent with CLAUDE.md rule 1).
- Progression: phase-local, per Decision A1 — `StrengthProgressionEngine`
  operates per-`ProgramDefinition`, already correct, no cross-phase
  formula needed or invented.
- Substitutions: `SlotSelectionOverride` is scoped how existing
  Mesocycle-1 code already scopes it — needs direct confirmation at
  implementation time that it's instance-scoped (expected, not verified
  in this pass), which would make it naturally fresh-per-mesocycle too.
- Scheduling: `TrainingPhase`/`ConcurrentScheduler` already support
  multiple sequential phases within one `TrainingPlan` (this is exactly
  what annual planning/Stage 7 already does for entirely different
  phases) — no new scheduling concept needed.

**Conclusion: the current architecture is sufficient. No domain-model
change is required.** The actual gap is narrower than a modeling
problem: (a) `HypertrophyProgramGenerator`'s day-focus-driven path
(the one the shipped 3-Day Full Body config uses) currently **hardcodes**
`primaryWeekOneFactor(for: .basicHypertrophy)` unconditionally inside
`makeSourceCategoryTemplate`, regardless of which `HypertrophyPhaseType`
is passed — confirmed verbatim in its own doc comment: *"this day-focus
path only ever generates Mesocycle 1's own content regardless of which
`HypertrophyPhaseType` a caller passes."* This must be corrected to
generate Mesocycle 2's real recovered content when `phaseType ==
.metaboliteFocus`. (b) `HypertrophyProgramJourney.build` has no
production call site or trigger. Both are content/wiring gaps, not
domain-model gaps.

---

## 13. UX at the mesocycle boundary

**SOURCE-REQUIRED USER INPUT** (from §3/§5 alone):
- A fresh 10RM value per exercise, entered manually or marked "test
  first" — the same `SourceRMCalibrationView` screen Mesocycle 1 already
  uses, reused as-is for the new `ProgramInstance`.
- Nothing else is source-required. The source has no opinion on exercise
  selection UX, no opinion on when the transition happens, no opinion on
  reviewing Mesocycle 1's results first.

**TRAININGOS UX CONVENIENCE (candidates, not source-required, listed for
the decision packet in §20, not decided here)**:
- Showing Mesocycle 1's final logged performance as labeled reference
  next to the new calibration input ("last time: X kg") — must never be
  silently treated as the new calibration value, consistent with the
  request's explicit constraint.
- A "Mesocycle 1 complete" summary/review screen before starting
  Mesocycle 2.
- Whether exercise selection is asked again explicitly, silently
  re-resolved via the same deterministic table, or offers to carry
  forward Mesocycle 1's substitutions as a convenience default (never
  silent — always visible/labeled if offered).
- The literal trigger UI: a button on `TrainingPhase`/plan screens ("Start
  Metabolite Focus") vs. an automatic prompt when Mesocycle 1's last
  week completes. The already-resolved `transitionTrigger: .userInitiated`
  design settles "not automatic," but not the exact screen/button.

None of this needs deciding in this stage per the "do not design
unnecessary screens" instruction — captured here only so the decision
packet in §20 is complete.

---

## 14. Warm-up

Not investigated for changes (out of scope, per instruction). Mesocycle
2 creates **no new direct dependency** on the known "primary block"
heuristic weakness — it's the same architecture, same bug class, applies
identically to any session regardless of which mesocycle it belongs to.

---

## 15. Mixed-modality scheduling

Not investigated for fixes (out of scope). The two existing
`TacticalPlacementBoundaryTests` `XCTSkip`s document a limitation in
deferred `.rmBased` materialization coordinating with already-scheduled
siblings under an at-capacity mixed-modality phase — the exact same
calibration-gating mechanism Mesocycle 2 will also use. **Mesocycle 2
does not worsen this** (same exposure Mesocycle 1 already has), but
inherits it identically whenever it's part of an at-capacity
mixed-modality phase. No new investigation needed beyond noting the
inheritance.

---

## 16. Source vs. current implementation matrix

### Family A — 3-Day Full Body (shipped reference config)

| Axis | Source behavior | Current TrainingOS | Match |
|---|---|---|---|
| Mesocycle identity | 3 phases, `HypertrophyPhaseType` (basic/metabolite/resensitization) | Enum exists, matches | **MATCH** |
| Duration | 4 progressive + 1 deload week, same as M1 | `lengthWeeks: 5` generic, correct if wired | **MATCH** (once wired) |
| Exercises | Same 8 categories + 1 superset-partner row/day | Day-focus path generates M1 content only regardless of `phaseType` | **MISMATCH** |
| RM calibration | Fresh, independent, per exercise | `SourceRMCalibration` already correctly scoped per-instance | **MATCH** (architecture); content not yet generated to require it correctly for M2 |
| RMType | `.rm10` for both primary and superset partner | N/A — not yet generated | **UNKNOWN until generated** |
| Sets | New baseline; superset partner pairs to primary's own baseline | Not yet generated; `pairedSlot` mechanism already supports the shape | **MISMATCH** (not implemented) |
| RIR | 3,3,2,1, identical to M1 | N/A — not yet generated correctly | **MISMATCH** (currently produces M1's values under M2 phaseType) |
| Reps | RIR-only, no fixed count, same as M1 | Same `RepPrescriptionKind` infra already handles this correctly once content is right | **MATCH** (infra); **MISMATCH** (content) |
| Load | 0.75 primary / 0.6 partner, weeks×1.05/1.075/1.1 | `metaboliteFocusPairedWeekOneFactor = 0.6` exists but unused by the day-focus path; 0.75 primary factor not present anywhere | **MISMATCH** |
| Progression | Phase-local, no cross-phase formula | Matches by construction (no cross-phase code exists) | **MATCH** |
| Deload | Same mechanic; superset partner omitted (Decision A2) | `DeloadExerciseAction.omit` mechanism exists, unused for M2 (not generated) | **MISMATCH** (not implemented) |
| Transition | User-initiated, independent phases, fresh calibration | `HypertrophyProgramJourney.build` exists, matches shape, zero production call site | **MISMATCH** (unwired) |
| Materialization | Per-phase, on start | `StartPhaseUseCase` exists and works per-instance already | **MATCH** (architecture) |
| Substitution | Not addressed by source (silent) | Existing `SlotSelectionOverride`/GOING-FORWARD mechanism, expected instance-scoped | **MATCH** (assumed; confirm at implementation time) |

### Family B / C

| Axis | Source behavior | Current TrainingOS | Match |
|---|---|---|---|
| Mesocycle 2 existence | **Does not exist** | N/A | **N/A — nothing to build** |
| (Mesocycle 1 fidelity, surfaced as a side finding) | Real day/category/set-baseline/pairing structure, proven | Shipped generator differs substantially on all three axes | **MISMATCH — pre-existing, out of scope for this stage** |

---

## 17. Proposed implementation slices

Slice boundaries chosen from the evidence above — each independently
committable, each leaves the app in a fully working, test-covered state.

**10R.2A — Mesocycle 2 content recovery (Family A, day-focus path only)**
- Purpose: make `generateDayFocusDriven` (and `makeSourceCategoryTemplate`)
  phase-aware, generating the real recovered Mesocycle 2 category
  list/superset structure/load factors/RIR schedule for `.metaboliteFocus`,
  instead of silently reusing Mesocycle 1's content.
- Files: `HypertrophyProgramGenerator.swift` (new `threeDayFullBodyMesocycle2MetaboliteFocus`
  content table + superset-aware `makeSourceCategoryTemplate`/`generateDayFocusDriven`
  branch), `HypertrophyProgramGenerator.currentVersion` bump.
- Invariants: Mesocycle 1 output byte-identical to today (regression);
  `.metaboliteFocus` never silently falls back to Mesocycle 1 content;
  superset partner never fabricates a deload prescription
  (`DeloadExerciseAction.omit`, per Decision A2); no rep range invented.
- Tests: exact Week 1 prescription (load, RIR, sets) for every category
  including both superset partners; deload correctly omits partners;
  full 24(or 27)-slot rating-pairing table proven, including the new
  partner-pairs-to-primary mechanic.
- Independently committable: yes.

**10R.2B — Mesocycle transition wiring**
- Purpose: give `HypertrophyProgramJourney.build` (or an equivalent
  narrower entry point) a real production call site and a UI trigger
  consistent with `transitionTrigger: .userInitiated`.
- Files: likely a new use case or an addition near `StartPhaseUseCase`/
  `TrainingPhase`, plus whatever UI screen/button triggers it (kept
  minimal per §13 — no unnecessary screens).
- Invariants: never auto-advances; never silently creates the next
  phase without explicit user action; Mesocycle 1's phase/instance/history
  is never mutated by starting Mesocycle 2 (CLAUDE.md rule 1); calibration
  gate applies identically to the new instance.
- Tests: starting Mesocycle 2 creates exactly one new `ProgramInstance`/
  `TrainingPhase`, leaves Mesocycle 1's untouched; blocked until fresh
  calibration is entered; idempotent (starting twice doesn't duplicate).
- Independently committable: yes, depends on 10R.2A for content but not
  for the transition mechanism itself (could be sequenced either order,
  but 2A first avoids wiring a trigger to placeholder content).

**10R.2C — `rollForward` production wiring** *(explicitly NOT this
stage, listed only because Mesocycle 2 makes it visible — deferred to
its own future stage per the user's explicit instruction not to fix it
here)*.

**10R.2D — Tests / full-suite verification** — folded into 2A/2B above
per this codebase's established practice (no separate test-only slice
needed); listed here only if the user prefers tests as their own
reviewable commit.

*(Deliberately no calibration-boundary slice — §12 already found no
domain-model change is needed; no separate "progression/materialization"
slice — same reasoning, `StrengthMaterializer`/`StrengthProgressionEngine`
already handle this generically once 10R.2A's content exists.)*

---

## 18. Test matrix

| Area | Test proves |
|---|---|
| Mesocycle 2 Week 1 content | Exact category list, exact superset pairs, exact load (0.75/0.6), exact RIR (3), exact baseline sets, for the real 3-Day Full Body config |
| RIR schedule | 3,3,2,1 across weeks, identical to Mesocycle 1 — no drift |
| Rating-pairing web | Both the cross-day pairing (unchanged rows) and the new partner-pairs-to-primary mechanic, per confirmed formula |
| Fresh calibration | A new `ProgramInstance` for Mesocycle 2 requires its own `SourceRMCalibration`; no value inherited from Mesocycle 1's instance |
| No accidental inheritance | Explicit negative test: entering Mesocycle 1's RM does NOT satisfy Mesocycle 2's requirement |
| Exercise resolution | Mesocycle 2's categories resolve via the same deterministic table as Mesocycle 1 (or the decided §20 policy) |
| Substitution | GOING-FORWARD substitution still works correctly scoped to the new instance |
| Fixed-rep vs. RIR-only | Still correctly distinguished (no Family A Mesocycle 2 row is fixed-rep; confirm none accidentally becomes one) |
| Actual reps = athlete output | Logging still never prefills from a fabricated target for Mesocycle 2 sets (reuses `StrengthExecutionView`/`StrengthSetPresentation` unchanged) |
| Week 1 → later-week progression | Multipliers apply correctly off Mesocycle 2's own resolved Week 1 |
| Mesocycle 1 → 2 transition | Starting Mesocycle 2 creates exactly one new instance/phase, doesn't touch Mesocycle 1's; blocked pre-calibration; idempotent |
| Persistence/relaunch | Mesocycle 2's calibration and materialized state survive relaunch (mirrors existing `SourceRMCalibrationOnDiskReproTests`) |
| Idempotent materialization | No duplicate sessions from re-triggering the transition or re-entering the calibration screen |
| Deload | Superset partner correctly omitted; primary rows deload exactly like Mesocycle 1's mechanism |
| Family B mixed RM bases | Unaffected — no Mesocycle 2 exists for Family B, existing Mesocycle-1-only tests remain the full coverage |
| Family C | No new tests — no Mesocycle 2 exists; existing (already-known-imperfect) coverage unchanged, not expanded in this stage |
| Stage 10R.1 regression | Full existing suite (813 tests) must remain green, unmodified in intent — Mesocycle 1 output byte-identical |

---

## Sections 19-20 continue in the chat report below (repository status
through decisions required) — reproduced there in full per the request's
required structure, not duplicated here at length.
