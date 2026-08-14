# Stage 3 Decision Memo

This is a product-owner decision document, not new source analysis. Every
item below is derived from `OPEN_PROGRAMMING_QUESTIONS.md` (cited by its
§ number there) plus two items that instruction explicitly asked to be
addressed but weren't separately numbered there (Family C's Week-4
autoregulation freeze, and a dedicated pass for formulas that look like
spreadsheet-authoring artifacts rather than training rules). Nothing here
re-derives or re-guesses source behavior — where source behavior is
unresolved, that is stated plainly, and a recommendation is offered
*despite* the ambiguity, not by resolving it silently.

Throughout, **SOURCE BEHAVIOR** (what the spreadsheet literally does,
observable and citable) is kept typographically separate from **TRAININGOS
RECOMMENDED BEHAVIOR** (what this memo proposes TrainingOS actually do,
which may match, generalize, or deliberately diverge from the source).

## Classification legend

- **A — MUST RESOLVE BEFORE IMPLEMENTATION.** The engine cannot be built
  correctly without a decision; Stage 4 should not start on the affected
  rule/area until this is answered.
- **B — PRESERVE SOURCE BEHAVIOR FOR REGRESSION.** The source behavior is
  strange or undocumented, but is fully specified and mechanically
  reproducible as a parameter — no decision is required to *implement* it
  correctly, only to decide whether to *keep exposing* it as configured.
- **C — TRAININGOS SHOULD NORMALIZE.** The spreadsheet behavior is an
  implementation/authoring artifact, not a deliberate training rule, and
  should not be generalized into TrainingOS's rule vocabulary.
- **D — DEFER.** Not required for V1 engine implementation.

---

## Resolution status — A1–A6 (product-owner decisions received)

All six MUST-RESOLVE items have been decided. Each section below is
updated in place with a **DECISION (resolved)** block; the original
analysis, options, and initial recommendation are left intact underneath
so the reasoning trail stays visible, including where the final decision
modified rather than simply accepted the original recommendation.

| Item | Decision | Modifies original recommendation? |
|---|---|---|
| A1 — Mesocycle sequencing | Sequential `ProgramJourney`; phases stay rule-local; sequencing is a product interpretation, not a proven spreadsheet dependency; standalone phase use still permitted | **Yes** — original recommendation was independent programs + suggested-order copy only |
| A2 — Missing superset-partner deload row | Option A (omit), represented as explicit `DeloadExerciseAction.omit` on the confirmed prescription, not a generic blank-cell rule | No — matches original recommendation, adds representation requirement |
| A3 — Deload rep rounding direction | Round down (floor); e.g. `7 × 0.5 = 3.5 → 3` | No — matches original recommendation exactly |
| A4 — Deload weight/rep asymmetry | Preserve source behavior via `SourceCompatibleDeloadStrategy`, per family; explicitly not promoted to a universal `TrainingOSDeloadStrategy` | Partially — trusts the spreadsheet as recommended, adds the two-layer architectural split |
| A5 — `linkedResultReference` / slot-reference translation | Hybrid accepted: structural authoring-time reference (`pairedSlot`); movement/muscle metadata kept separate, never used for dependency resolution | No — matches original recommendation exactly |
| A6 — Dual-tagged exercise categories | Do not defer: real multi-target `ExerciseSlot.allowedTargets`, no special-case entity | **Yes** — original recommendation was to defer via hardcoding one exercise per slot for V1 |

---

## Section A — Must resolve before implementation

### A1. Mesocycle sequencing (Family A)

- **Question/ambiguity:** Are "Mesocycle 1: Basic Hypertrophy," "Mesocycle
  2: Metabolite Focus," and "Mesocycle 3: Resensitization" three phases a
  user runs sequentially within one program, or three independent,
  optionally-standalone templates?
- **Affected family:** A (all 11 workbooks).
- **SOURCE BEHAVIOR:** Each mesocycle sheet is fully self-contained, with
  its own blank RM-entry cell and its own copy of the exercise catalog.
  There is zero cross-sheet formula reference in any of the 11 workbooks
  (confirmed by whole-workbook grep for sheet-name references inside
  formula text — no hits outside the sheet-name headers themselves).
  Nothing carries load, exercise selection, or rating history from one
  phase to the next.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §2.2; confirmed
  independently by Agents A1 and A2 against `e1f8fb19-4_day_full_body.xlsx`
  and two other Family A files.
- **Why it matters:** This decides whether `ProgramInstance` needs a
  "next phase" transition concept at all for Family A. If sequential, the
  engine needs logic for when/how a user moves from Mesocycle 1 into
  Mesocycle 2 (does it require a fresh RM re-test? automatically? on a
  fixed calendar cadence?). If independent, no transition logic is needed
  — each mesocycle is just a separate `ProgramDefinition` a user can pick
  once.
- **Implementation options:**
  1. Treat all three as one `ProgramDefinition` with three `TrainingWeek`
     blocks in sequence, gated by an explicit user action (log a new RM)
     between blocks.
  2. Treat all three as three independent `ProgramDefinition`s (same
     `HypertrophyProgrammingSystem`, different `phaseSet` parameter of
     size 1), with no engine-level sequencing at all.
  3. Ship option 2 for V1, but add UI copy suggesting a recommended order,
     without encoding it as an engine invariant.
- **Recommended option:** 3. It requires the least speculative engine
  code and matches what the source data actually proves (independence),
  while not discarding the naming's obvious intent (a suggested order) —
  that intent lives in copy, not in code that would silently fail if the
  sequencing assumption turns out to be wrong.
- **Consequence of this option:** If the product owner later confirms
  strict sequencing is required, `ProgramInstance` needs a schema
  addition (a `predecessorInstance` or `phaseIndex` reference) — not a
  breaking change, but real added work deferred rather than avoided.
- **Regression compatibility:** No. Regression fixtures only exercise
  single-mesocycle formulas (`PROGRAM_REGRESSION_TEST_PLAN.md` §4); no
  fixture depends on cross-mesocycle sequencing, so either implementation
  choice is regression-neutral.

**DECISION (resolved):** Modifies the original recommendation. TrainingOS
supports the three phases as a sequence — Basic Hypertrophy → Metabolite
Focus → Resensitization — modeled as a `ProgramJourney` wrapping three
ordinary `ProgramDefinition` phases (`PROGRAMMING_SYSTEM_MODEL.md` §5.1),
rather than as three unrelated programs. **SOURCE-DERIVED BEHAVIOR:**
each phase's `ProgressionRule`s remain fully phase-local — no spreadsheet
cross-phase formula is invented; none exists to represent.
**TRAININGOS-DESIGNED BEHAVIOR:** the sequence itself, and the mechanism
for starting the next phase (a `PerformanceProfile`-based recommendation,
or a calibration flow when history is insufficient) — both are product
decisions layered on top of the source, not derived from it. A phase
remains independently usable without the journey wrapper. This is
explicitly documented as a TrainingOS product interpretation of the
phase naming/order, not a proven spreadsheet dependency — see
`PROGRAM_LOGIC_SPEC.md` §2.2 and `V1_PROGRAM_LIBRARY.md` §3.

### A2. Superset partner's missing deload-week row (Family A, Mesocycle 2)

- **Question/ambiguity:** Is the superset partner exercise skipped
  entirely during deload week, or should it follow the same deload rule
  as every other row (and the blank cell is just unfilled)?
- **Affected family:** A, Mesocycle 2 ("Metabolite Focus") only.
- **SOURCE BEHAVIOR:** The partner exercise's deload-week cell is
  completely blank — not a zero, not a formula referencing another cell,
  nothing.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §2.2.
- **Why it matters:** Without a ruling, there is no value the engine can
  compute for this cell during deload week for any Metabolite Focus
  program — this is a real gap, not an edge case that degrades
  gracefully.
- **Implementation options:**
  1. Skip the partner exercise entirely during deload week (treat the
     blank as "no prescription").
  2. Apply the same deload rule the primary exercise in the pair uses
     (full/half-weight-by-day-position, per `FAMILY_A_DELOAD_WEIGHT_ASYMMETRY`).
  3. Apply a fixed, separately-defined light deload treatment,
     independent of the primary exercise's rule.
- **Recommended option:** 1 (skip). A blank cell in every one of the
  affected rows, with no partial data anywhere suggesting a computed rule
  was intended, is weaker evidence for "the author forgot to fill this in"
  than for "this row genuinely has no deload prescription" — supersets
  are typically the first thing dropped in a lighter week in real
  coaching practice, which is at least a plausible, not fabricated,
  rationale.
- **Consequence of this option:** Users following Metabolite Focus phase
  will see one fewer exercise on deload week without an explicit
  explanation baked into the data — TrainingOS should surface this via
  UI copy ("superset partner rests during deload") rather than let it
  look like an omission.
- **Regression compatibility:** No fixture in `PROGRAM_REGRESSION_TEST_PLAN.md`
  exercises this cell (no real number to check against either way) — this
  choice cannot be regression-tested against source, only sanity-checked
  by product review.

**DECISION (resolved):** Option A confirmed — omit the superset partner
during deload week. **SOURCE-DERIVED BEHAVIOR:** the blank cell, confirmed
in every occurrence, with no partial data suggesting a computed rule.
**TRAININGOS-DESIGNED BEHAVIOR:** represented semantically as
`DeloadExerciseAction.omit`, set explicitly on this one confirmed
prescription — **not** implemented as a generic "blank spreadsheet cell
means omit" inference rule that could misfire elsewhere in the source set.
See `PROGRAMMING_SYSTEM_MODEL.md` §3.2 for the parameter and
`PROGRAM_REGRESSION_TEST_PLAN.md` §9.2 for the fixture (including the
negative-case fixture confirming the pair's *primary* exercise is
unaffected).

### A3. Deload rep-fraction rounding direction (all families)

- **Question/ambiguity:** Deload-week rep targets are always a literal
  fraction of Week 1 expressed as text ("1/2 reps of Week 1," "2/3 reps of
  Week 1"), never a computed number. When Week 1 was, say, 7 reps, what
  actual rep number should TrainingOS prescribe?
- **Affected family:** A, B, and C — universal, not family-specific.
- **SOURCE BEHAVIOR:** No workbook contains `ROUND`/`ROUNDDOWN`/`INT`/
  `FLOOR` anywhere (confirmed by whole-workbook grep, zero matches across
  all 15 files) — the source material defers this arithmetic to the human
  reading the sheet, in every family, with no exception.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §2.1
  (`FAMILY_A_REP_GOAL_SCHEDULE`); Agent B1 finding #10 (Family B); Family C
  §4 (`FAMILY_C_DELOAD`).
- **Why it matters:** This blocks deterministic computation of a real,
  displayable rep target for deload week in *every* program, in every
  family — it's shared infrastructure the engine needs regardless of which
  family it's evaluating.
- **Implementation options:**
  1. Round down (never prescribe more reps than the fraction technically
     allows).
  2. Round to nearest, half-up.
  3. Store the fraction and display it as a *range* (e.g. "3–4 reps")
     rather than force a single number.
- **Recommended option:** 1 (round down). Consistent with the
  conservative-by-default posture RP's own material takes elsewhere
  (deload weeks exist to reduce fatigue; erring toward less rather than
  more is lower-risk if this rule is ever wrong), and simpler to reason
  about / test than a range-display UI decision, which is itself a
  separate product question.
- **Consequence of this option:** A deload week's rep target could read
  as slightly conservative in edge cases (e.g. exactly half of an odd
  number) — acceptable, and reversible later without a schema change since
  this is pure display-layer arithmetic on a stored fraction, not a
  persisted computed value.
- **Regression compatibility:** No fixture in this source set has a real
  deload-week rep value to check against (rounding direction was never
  computed by the source itself) — this decision is untestable against
  source data by construction; only forward-looking unit tests can cover
  it.

**DECISION (resolved):** Round down (floor), exactly as recommended.
**SOURCE-DERIVED BEHAVIOR:** none — no workbook ever computes this number.
**TRAININGOS-DESIGNED BEHAVIOR:** `deloadRepInstruction.roundingDirection
= .down` universally, across all three families. Worked example: Week-1
reps `7` × fraction `1/2` = `3.5` → **TrainingOS prescription: 3 reps**.
Made deterministic and fixtured at `PROGRAM_REGRESSION_TEST_PLAN.md` §9.1
(three cases: a genuine round-down, a case that would coincidentally
match round-to-nearest to rule that out as the actual mechanism, and an
exact whole-number case as a no-op sanity check).

### A4. Deload weight/rep asymmetry per family, including a documented-vs-actual conflict (Families A, B, C)

- **Question/ambiguity:** Every family has a deload-week asymmetry (some
  days get a real reduction, others don't) that is internally consistent
  within that family but not explained anywhere, and for Family B directly
  contradicts that family's own official documentation. Which pattern, per
  family, is the "real" rule TrainingOS should encode?
- **Affected family:** A, B, and C, each with a *different* asymmetry
  shape.
- **SOURCE BEHAVIOR:**
  - Family A: full Week-1 weight for the first `ceil(dayCount/2)` days,
    half for the rest (`FAMILY_A_DELOAD_WEIGHT_ASYMMETRY`).
  - Family B: weight factor 0.7 (Mon/Tue) vs. 0.5 (Thu/Fri); **reps**
    "2/3 of Week 1" (Mon/Tue) vs. "1/2 of Week 1" (Thu/Fri) — but Family
    B's own HowTo PDF states reps are uniformly "2/3 of Week 1" with a
    worked example that only actually matches the Mon/Tue half of the
    spreadsheet.
  - Family C: weight unchanged (no reduction, Mon/Tue) vs. halved
    (Wed/Thu/Fri); the split is by weekday section, not lift type — Deadlift
    and Hamstring (both "main" lifts) fall on the *halved* side.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §2.1, §3
  (`FAMILY_B_DELOAD`), §4 (`FAMILY_C_DELOAD`), §6.3; Agent B1 finding #5.
- **Why it matters:** Deload is the single largest concentration of
  unresolved ambiguity across the entire source set, present in every
  family with no shared shape between them — this needs a per-family
  ruling before `deloadWeightBySchedulePosition` can be configured
  correctly for any of them, and a specific ruling for Family B on
  whether the spreadsheet or the PDF is authoritative.
- **Implementation options:**
  1. Trust the spreadsheet over the PDF wherever they conflict (the
     spreadsheet is the thing users actually train from; the PDF is
     descriptive prose that may itself be stale or simplified).
  2. Trust the PDF and treat the spreadsheet's Thu/Fri behavior as a bug
     to correct in TrainingOS's version.
  3. Preserve both behaviors as separate, explicitly-labeled configuration
     options and let a future regression/product review decide.
- **Recommended option:** 1 (trust the spreadsheet), for all three
  families. The spreadsheet is the executable artifact real users
  actually followed; a PDF claim that provably doesn't match its own
  worked example against the spreadsheet it's describing is weaker
  evidence than the spreadsheet itself, not stronger.
- **Consequence of this option:** TrainingOS's Family B deload reps will
  not match what a user who only read the official RP PDF would expect —
  worth a one-line product/support note if this is ever visible to
  end users comparing against RP's own material.
- **Regression compatibility:** Yes, and it's the reason this must be
  resolved before Stage 4: `PROGRAM_REGRESSION_TEST_PLAN.md` §3.3
  encodes exactly this Mon/Tue-vs-Thu/Fri weight split as a fixture (using
  the spreadsheet's literal `0.7`/`0.5` constants) — an evaluator that
  instead implemented the PDF's claimed uniform rule would fail that
  fixture.

**DECISION (resolved):** Preserve source behavior, but do not promote it
to universal TrainingOS methodology — this is a refinement, not a
rejection, of the original "trust the spreadsheet" recommendation.
**SOURCE-DERIVED BEHAVIOR:** each family's exact, literal asymmetry
(Family A's `ceil(dayCount/2)` boundary; Family B's Mon/Tue `0.7`/"2/3" vs.
Thu/Fri `0.5`/"1/2"; Family C's Mon/Tue unchanged/"1/2" vs. Wed–Fri
`×0.5`), trusting the spreadsheet over the PDF wherever they conflict.
**TRAININGOS-DESIGNED BEHAVIOR:** two conceptual layers behind one shared
`DeloadStrategy` interface — `SourceCompatibleDeloadStrategy` (one
parameterization per family, used by every source-derived
`ProgramDefinition` and validated by regression fixtures) and
`TrainingOSDeloadStrategy` (reserved, undefined, for
`ProgramGenerator`-authored programs with no source workbook behind them
— that methodology is a separate decision for when native generation is
built). One protocol, two strategies — no engine duplication. See
`PROGRAMMING_SYSTEM_MODEL.md` §6.1.

### A5. `linkedResultReference` / paired-slot translation (all families)

- **Question/ambiguity:** `autoregulatedSetCount` and `linkedResultReference`
  both need to name a *slot* declaratively ("the other slot in this day
  sharing category X," "the most recently completed prior session of this
  movement pattern") instead of a literal spreadsheet cell address. How
  should that reference actually be represented and resolved at runtime?
- **Affected family:** A, B, and C — every family uses cross-slot
  pairings, and no two files necessarily wire them the same way.
- **SOURCE BEHAVIOR:** Every pairing found in this analysis (Front
  Squat/High Bar Squat, OHP/Bench, Family A's "Chest Isolation or Triceps"
  paired with "Horizontal Push," Family C's Friday backoff exercise
  referencing Monday's actual logged reps) was identified by manually
  tracing one formula to one specific other cell. There is no general
  rule in the source material for how a slot names its pairing partner —
  each pairing was hand-authored, cell-by-cell, by whoever built that
  specific workbook.
- **Source location(s):** `PROGRAMMING_SYSTEM_MODEL.md` §3;
  `PROGRAM_LOGIC_SPEC.md` §2.1 (`FAMILY_A_SET_AUTOREGULATION`), §3
  (`FAMILY_B_AUTOREGULATION`), §4 (`FAMILY_C_AUTOREGULATION`).
- **Why it matters:** This is arguably the single riskiest piece of
  Stage 4 implementation: it's not a source ambiguity to rule on, it's a
  design surface with no source precedent to copy, and it's exercised by
  nearly every prescription in every family. Underestimating it risks a
  Stage 4 timeline surprise.
- **Implementation options:**
  1. A structural reference: "the Nth slot in the same day sharing
     category Y" — resolved once at `ProgramDefinition` authoring time,
     stored as a direct model reference (e.g. a pointer from one
     `ExercisePrescription` to another).
  2. A semantic reference: "the most recently completed session of
     movement-pattern Z" — resolved at runtime by querying
     `ProgramInstance` history, more flexible but requires
     movement-pattern tagging to exist and be reliable.
  3. A hybrid: structural reference as the primary mechanism (matches how
     every source file actually works — the pairing is fixed at
     authoring time, never dynamic), with movement-pattern tagging kept
     as exercise-library metadata for other uses (search, substitution)
     but not load-bearing for autoregulation.
- **Recommended option:** 3. No source file ever resolves a pairing
  dynamically at runtime — every pairing is fixed when the workbook was
  built. A direct, authoring-time model reference is simpler, matches the
  source's actual design, and avoids inventing a resolution algorithm the
  source never needed.
- **Consequence of this option:** `ExercisePrescription` needs a
  self-referential optional pointer (`pairedSlot: ExercisePrescription?`)
  in the domain model — a real, if small, schema addition Stage 1–2
  didn't anticipate.
- **Regression compatibility:** Yes — every autoregulation fixture in
  `PROGRAM_REGRESSION_TEST_PLAN.md` (§3.2, §4.2, §5.2) assumes the paired
  slot is resolvable; the evaluator can't pass any of them without some
  working implementation of this reference.

**DECISION (resolved):** Hybrid recommendation accepted, exactly as
proposed. **SOURCE-DERIVED BEHAVIOR:** none — no source file resolves a
pairing dynamically; every pairing was hand-wired at authoring time.
**TRAININGOS-DESIGNED BEHAVIOR:** a structural authoring-time reference
(`ExercisePrescription.pairedSlot`) is the actual runtime dependency
mechanism. Movement-pattern and muscle-group metadata remain available on
the Exercise Library for substitutions, exercise discovery, the
`ProgramGenerator`, related-exercise performance estimates, and
analytics — but are never consulted to resolve a dependency link at
runtime; that resolution is always the stored structural pointer, decided
once. See `PROGRAMMING_SYSTEM_MODEL.md` §5.2.

### A6. Dual-tagged exercise categories (Family A)

- **Question/ambiguity:** Categories like "Chest Isolation or Triceps" and
  "Rear or Side Delts" let the same slot resolve to either of two
  different target muscles depending on user choice. Is this one
  `ExerciseCategory` with two valid `primaryTarget` values, or two
  categories sharing a row in the source layout?
- **Affected family:** A (specifically the arms/shoulders and back/chest
  splits — both of which are in the recommended V1 configuration set,
  §2 below).
- **SOURCE BEHAVIOR:** The dropdown for these rows offers candidates from
  both muscle groups in one list; the source spreadsheet never
  disambiguates which target muscle governs at the category level — it's
  resolved implicitly by whichever specific exercise the user picks.
- **Source location(s):** `PROGRAM_GENERATOR_SPEC.md` §4.1;
  `PROGRAM_LOGIC_SPEC.md` §2.1.
- **Why it matters:** This is a schema decision for `ExerciseCategory`
  itself, made once, that every Family A `ProgramDefinition` depends on —
  not just a Generator concern. Two of the six recommended V1 curated
  configurations (§2 below) use splits containing this exact pattern, so
  it isn't a hypothetical future-generator problem; it affects what ships
  in V1's static library today.
- **Implementation options:**
  1. One `ExerciseCategory` with a list of valid `primaryTarget` values,
     resolved to a specific target once an exercise is chosen for the
     slot.
  2. Two separate `ExerciseCategory` rows that happen to render as one
     dropdown in the source layout — split them apart at import time.
  3. For V1's curated pre-built programs specifically, sidestep the
     schema question entirely: hardcode one specific exercise per slot
     (exactly as a human filling in the spreadsheet's dropdown would),
     and only resolve the schema question when the dynamic Generator
     (Stage 4+) actually needs it.
- **Recommended option:** 3 for V1 content, deferring options 1 vs. 2 to
  whenever the Generator's dynamic slot-resolution is actually built. A
  pre-built `ProgramDefinition` never needs to *decide* a category's
  target dynamically — it can just ship with one already chosen, exactly
  as the source spreadsheets' own authors would have needed to do to use
  the sheet at all.
- **Consequence of this option:** The real schema decision (1 vs. 2) is
  postponed, not avoided — Stage 4's Generator work cannot start until
  it's made, even though V1's curated library doesn't need it.
- **Regression compatibility:** No — no fixture in
  `PROGRAM_REGRESSION_TEST_PLAN.md` depends on category-level target
  resolution; only pre-picked exercises are ever asserted against.

**DECISION (resolved):** Overrides the original recommendation — do
**not** defer the schema question. **SOURCE-DERIVED BEHAVIOR:** the
dropdown offers both muscle groups together; the source never
disambiguates at the category level, only implicitly via whichever
exercise gets picked. **TRAININGOS-DESIGNED BEHAVIOR:** `ExerciseSlot`
carries a real `allowedTargets: [MuscleGroup]` list (one entry for an
ordinary slot, two for a dual-tagged one); choosing a concrete exercise
sets `resolvedTarget` from whichever allowed target it satisfies, but
`allowedTargets` itself is preserved on the slot even after resolution —
the original program intent (this slot was always meant to be flexible)
survives, rather than being discarded to avoid a schema decision. No new
special-case entity — this is a field addition to the existing
`ExerciseSlot` shape. V1's shipped configurations may still pre-select or
recommend one exercise per dual-tagged slot for convenience; that's a
UI/generator convenience layered on top of the schema, not a narrowing of
it. See `PROGRAM_GENERATOR_SPEC.md` §4, §4.1.

---

## Section B — Preserve source behavior for regression

### B1. "Resensitization" phase behavior vs. its name (Family A, Mesocycle 3)

- **Question/ambiguity:** The name implies a light reset; the formulas
  show the highest relative intensity of the three phases. Is this
  intentional?
- **Affected family:** A, Mesocycle 3 only.
- **SOURCE BEHAVIOR:** Week-1 load = 100% of 10RM (vs. 85%/75% for the
  other two phases), paired with the *lowest* volume (23 slots/week vs.
  26/30) and shortest duration (3 weeks vs. 5).
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §2.2.
- **Why it matters:** This doesn't block implementation — the formula is
  complete and unambiguous, so the *engine* can be built today regardless
  of what "Resensitization" is supposed to mean. What's unresolved is
  purely a copy/UX risk: if TrainingOS's marketing or in-app copy describes
  this phase using the word's ordinary connotation ("light," "easy," "a
  break"), it will contradict what the program actually prescribes.
- **Implementation options:**
  1. Implement the formula exactly as sourced; write UI/coaching copy
     that describes what it *actually does* ("short, high-intensity,
     lower-volume reset") rather than translating the filename.
  2. Implement the formula exactly as sourced, but soften it to match the
     name's usual meaning (e.g. reduce the 100% factor) — this would be
     inventing a rule the source doesn't support.
  3. Rename the phase in TrainingOS's UI to something that matches its
     actual behavior, decoupling the product-facing name from RP's
     original label.
- **Recommended option:** 1. **SOURCE BEHAVIOR** is preserved exactly
  (100%/short/low-volume) since it's fully specified and there is no
  evidence it's a mistake; **TRAININGOS RECOMMENDED BEHAVIOR** is to fix
  the *copy*, not the *formula* — the risk here is a UX mismatch, not an
  engine defect.
- **Consequence of this option:** Requires product/copy sign-off on the
  phase description before shipping, but no engine rework.
- **Regression compatibility:** No — the exact 100%/85%/75% factors are
  what a Family A regression fixture would assert regardless of which
  copy option is chosen (`PROGRAM_REGRESSION_TEST_PLAN.md` §4.1 uses the
  Mesocycle-1 factor; a Mesocycle-3 fixture would use 100% unchanged).

### B2. Legs-only "Heavy" ×1.0 exception (Family A)

- **Question/ambiguity:** Deliberate design ("compounds always load
  closer to true max regardless of split") or a copy/paste artifact
  limited to one file?
- **Affected family:** A, `legs` split only (the file recommended for V1's
  "4-Day Lower/Leg Focus" configuration, §2 below).
- **SOURCE BEHAVIOR:** `legs` split's Heavy Quads/Glutes category uses
  `×1.0` (full 10RM) as the Week-1 factor; every other split's own squat/
  deadlift-pattern rows — including full_body's — stay at the standard
  `×0.85`, confirmed absent even on the closest equivalent rows in the
  other three splits.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §2.3
  (`FAMILY_A_LEGS_HEAVY_EXCEPTION`); `PROGRAM_FAMILY_MATRIX.md` §1.
- **Why it matters:** This is fully specified and low-risk to reproduce
  exactly for the one file it's confirmed in — no decision is required to
  *implement* it, only to decide the *default* if this override is ever
  offered on other splits.
- **Implementation options:**
  1. Model as a named, opt-in `exerciseCategoryOverride`, defaulting
     **on** only for the `legs` split (exactly matching the one confirmed
     file), off everywhere else.
  2. Same override mechanism, but default **off** everywhere including
     `legs`, requiring an explicit choice to enable it even for the
     source-matching configuration.
  3. Hardcode `×1.0` directly into the `legs` split's `ProgramDefinition`
     with no generalized override mechanism at all.
- **Recommended option:** 1. **SOURCE BEHAVIOR**: `legs`-only, `×1.0`.
  **TRAININGOS RECOMMENDED BEHAVIOR**: reproduce that exactly as the
  default for the `legs` configuration, expose it as a named override
  (not a hardcoded literal) so a future product decision to extend or
  retract it doesn't require touching `ProgrammingSystem` code.
- **Consequence of this option:** If this later proves to be a copy/paste
  artifact rather than deliberate design, disabling it is a one-line
  parameter change, not a rule-type change — the override mechanism
  absorbs the uncertainty.
- **Regression compatibility:** Yes — `PROGRAM_LOGIC_SPEC.md` §2.3 cites
  the exact source cells (`bb847616` `J11`); a fixture built from this
  file must reproduce `×1.0`, not `×0.85`, on the Heavy Quads/Glutes rows.

### B3. Family B's Week-4 autoregulation asymmetry

- **Question/ambiguity:** Deliberate ("stop adjusting sets in the last
  loading week for the second half of the split") or a copy-paste
  leftover?
- **Affected family:** B only.
- **SOURCE BEHAVIOR:** Monday/Tuesday rows' Week-4 sets add the rating
  exactly as weeks 2–3 do; Thursday/Friday rows' Week 4 is a flat,
  unmodified copy of Week 3 with no rating term at all (`Q25: '=L25'`,
  confirmed by direct formula inspection).
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §3
  (`FAMILY_B_AUTOREGULATION`); `OPEN_PROGRAMMING_QUESTIONS.md` §13.
- **Why it matters:** Today this has zero observable effect (deload
  week's set count is a hardcoded constant regardless of what Week 4
  computed) — but if TrainingOS ever displays or coaches off a Week-4
  "current working set count" before deload, the two behaviors produce
  different numbers.
- **Implementation options:**
  1. Reproduce exactly: add a per-slot `applyRatingOnFinalWeek: Bool`
     parameter to `autoregulatedSetCount`, `true` for Mon/Tue rows,
     `false` for Thu/Fri rows, matching the source file precisely.
  2. Normalize to always apply the rating (treat Thu/Fri's omission as an
     authoring bug and correct it).
  3. Normalize to never apply it in Week 4 for any row (treat Mon/Tue's
     addition as the anomaly instead).
- **Recommended option:** 1. There's no basis to prefer "fix by adding"
  over "fix by removing" without a product ruling neither this analysis
  nor the source material can supply — parameterizing it costs one
  boolean field and preserves optionality; normalizing in either
  direction requires guessing which half of the asymmetry is the "real"
  rule, which is exactly the guess this analysis was told not to make.
- **Consequence of this option:** `autoregulatedSetCount`'s parameter
  surface grows by one field that, as of V1, has no visible effect for
  any shipped program (deload still overrides it) — acceptable, since it
  costs nothing to leave `false`/`true` as configured and revisit later.
- **Regression compatibility:** Yes if a Week-4 fixture is ever added for
  Family B's Thu/Fri rows specifically (not currently in
  `PROGRAM_REGRESSION_TEST_PLAN.md`, which only exercises Weeks 1–2 for
  this family) — flagged here as a fixture gap worth closing before
  shipping, not just a hypothetical.

### B4. Family C's Week-4 autoregulation freeze

- **Question/ambiguity:** Same category of question as B3, different
  mechanism — is freezing intentional?
- **Affected family:** C only.
- **SOURCE BEHAVIOR:** Thursday/Friday autoregulated rows freeze after
  Week 3 — Week 4 repeats Week 3's *value* exactly, ignoring Week 4's own
  rating input entirely (confirmed with a deliberately-supplied
  Week-4 rating in the regression fixture at
  `PROGRAM_REGRESSION_TEST_PLAN.md` §5.2, which the rule must still
  ignore).
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §4
  (`FAMILY_C_AUTOREGULATION`).
- **Why it matters:** Unlike B3, this one *is* already load-bearing for
  V1: the recommended "5-Day Powerlifting Hypertrophy" curated program
  (§2 below) is this exact file, so an evaluator that gets this wrong
  produces a visibly incorrect Week-4 set count for a real shipped
  program, not just a latent one.
- **Implementation options:**
  1. Reproduce exactly: a `freezeAfterWeek: Int?` parameter on
     `autoregulatedSetCount`, set to `3` for Thu/Fri rows in this file,
     `nil` elsewhere.
  2. Normalize: always apply the rating in Week 4 everywhere, treating
     the freeze as a bug.
- **Recommended option:** 1, for the same reason as B3 — this is
  different in *shape* from B3 (Family B drops the addition term but
  still updates the value from Week 3's rating; Family C freezes the
  *value itself*), so "families always do the same Week-4 thing" is
  demonstrably false and should not be assumed elsewhere. Preserve both
  shapes as distinct, explicit parameters rather than collapsing them
  into one mechanism.
- **Consequence of this option:** Confirms the risk noted in Section A5:
  a rule engine that infers Week-4 behavior by analogy between families
  will be wrong for at least one of them. This must ship correctly in V1,
  not deferred.
- **Regression compatibility:** Yes — directly, via
  `PROGRAM_REGRESSION_TEST_PLAN.md` §5.2, already called out there as
  "the one fixture in this whole plan that a rule engine can fail
  silently."

---

## Section C — TrainingOS should normalize

### C1. "Novice" is not a distinct programming ruleset

- **Question/ambiguity:** Is "novice" a real, distinct ruleset, or just a
  filename label?
- **Affected family:** A (5 files carry the "Novice" name).
- **SOURCE BEHAVIOR:** Every mechanism isolable from a day-count confound
  (rep ranges, RM basis, progression factors, autoregulation formula,
  rating scale, deload formulas, exercise catalog breadth) is identical
  between the one available Novice file and standard files. The words
  "novice"/"beginner" appear nowhere inside any sheet, only in the
  filename. Where a difference exists (sets/day), Novice is *higher*, the
  opposite of a volume-throttling design.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §2.5;
  `PROGRAM_FAMILY_MATRIX.md` §2; `OPEN_PROGRAMMING_QUESTIONS.md` §7.
- **Why it matters:** Building a distinct novice code path (a ruleset
  parameter, a special-cased entity, a separate `ProgrammingSystem`) based
  on a filename with no behavioral evidence behind it would be exactly the
  kind of invented rule this whole engagement was told to avoid.
- **Implementation options:**
  1. Add no novice-specific engine parameter at all; treat "novice" as
     pure UX (a recommended starting day-count, extra coaching copy, more
     calibration steps) with zero effect on `ProgrammingSystem` logic.
  2. Add a placeholder `experienceLevel`-gated parameter now, even without
     evidence, in case product direction wants one later.
  3. Wait for real evidence (a same-day-count novice/standard pair) before
     making any decision at all, including UX framing.
- **Recommended option:** 1. **SOURCE BEHAVIOR**: no distinction exists.
  **TRAININGOS RECOMMENDED BEHAVIOR**: keep `experienceLevel` as a
  `GeneratorInput` field (already specified in `PROGRAM_GENERATOR_SPEC.md`
  §2) wired only to non-engine decisions — day-count defaults, copy,
  calibration — never to a `ProgrammingSystem` rule parameter.
- **Consequence of this option:** If the product owner later supplies
  real evidence of a distinct novice ruleset, it's a new parameter added
  to an existing system, not new architecture — nothing here blocks that.
- **Regression compatibility:** N/A — no fixture distinguishes novice
  from standard, because no distinct behavior was found to fixture.

### C2. Inconsistent rounding increment (2.5 vs. 5) across and within files

- **Question/ambiguity:** Does the 2.5-vs-5 `MROUND` increment encode a
  meaningful signal (a unit, a day-count rule) that TrainingOS should
  reproduce?
- **Affected family:** All three — inconsistent even *within* a single
  Family A workbook (Mesocycle 1 uses 2.5, Mesocycles 2–3 use 5, in the
  same 4-day file).
- **SOURCE BEHAVIOR:** No file states a unit anywhere. The pattern holds
  reasonably consistently *by family* for B (always 2.5) and C (always 5)
  but not within Family A, and there's no day-count or split correlation
  that survives a cross-file check.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §6.2; `METRIC_LOAD_MODEL.md` §1.
- **Why it matters:** This is exactly the kind of value the brief warned
  against literally converting (handoff rule 5's own example: "round to
  5 lb" must not become "round to 2.26796 kg"). Treating it as load-bearing
  product logic would encode spreadsheet noise as a training rule.
- **Implementation options:**
  1. Discard the source increment entirely; rounding is always driven by
     the user's `EquipmentProfile.smallestIncrementKg`, never by anything
     read from source.
  2. Preserve the source increment as a per-`ProgramDefinition` default,
     letting it influence the resolved value.
- **Recommended option:** 1 — **already the architecture decided in
  `METRIC_LOAD_MODEL.md` §2–3**; this entry exists in this memo only to
  make explicit that the source's own inconsistency (§6.2) is the
  evidence *for* that decision, not a separate open question needing its
  own new ruling.
- **Consequence of this option:** None beyond what `METRIC_LOAD_MODEL.md`
  already specifies — no new work.
- **Regression compatibility:** Yes, already addressed —
  `PROGRAM_REGRESSION_TEST_PLAN.md` fixtures use the *source's own*
  increment only when reproducing a specific workbook's exact numbers for
  rule-fidelity testing (§4 of that document), never as a claim about
  what any real user's equipment should use.

### C3. Family C's dead, never-referenced rating-input columns

- **Question/ambiguity:** Both Upper-Body-Pull slots and both Shoulder
  slots have rating-input columns that no formula ever reads. Should
  TrainingOS's UI still present a rating prompt for these rows?
- **Affected family:** C only.
- **SOURCE BEHAVIOR:** These rows use a fixed schedule (2,2,3,3) regardless
  of any rating entered; Hamstring's own rating is likewise never used —
  its autoregulation is a verbatim copy of Deadlift's instead.
- **Source location(s):** `PROGRAM_LOGIC_SPEC.md` §4
  (`FAMILY_C_AUTOREGULATION`).
- **Why it matters:** These columns exist in the spreadsheet's layout
  (probably copied from a row that *does* use autoregulation) but do
  nothing — presenting a rating prompt in TrainingOS's UI for a set count
  that's actually fixed would create a false affordance: the user would
  be asked for input the engine silently discards.
- **Implementation options:**
  1. Don't expose a rating prompt for these slots at all — model them
     with `fixedSetSchedule`, not `autoregulatedSetCount`, matching what
     they *actually* do rather than what the source layout visually
     suggests.
  2. Expose the rating prompt anyway, for surface-level fidelity to the
     source layout, and silently discard the input.
- **Recommended option:** 1. **SOURCE BEHAVIOR**: a dead input that looks
  functional but isn't. **TRAININGOS RECOMMENDED BEHAVIOR**: don't
  reproduce the dead affordance — model these slots with the rule type
  that matches their real behavior (`fixedSetSchedule`), which is already
  in the vocabulary and requires no new work, just correct rule-type
  assignment per slot.
- **Consequence of this option:** None negative — this is a strictly
  better user experience than literal reproduction, with no loss of
  fidelity to actual program behavior (only to the spreadsheet's visual
  layout, which was never a product requirement).
- **Regression compatibility:** No — this only affects which rule type an
  evaluator is configured with for these specific slots; the *value*
  produced (2,2,3,3 regardless of input) is identical either way, so no
  fixture is affected.

---

## Section D — Defer (not required for V1 engine implementation)

| # | Item | One-line reason for deferral |
|---|---|---|
| D1 | §1 — Family A has no matching official documentation | The reconstructed ruleset is internally self-consistent and independently cross-validated across all 11 files by 5 separate agents; the *absence* of documentation elevates the importance of getting A1–A6 right by direct product ruling, but doesn't by itself block implementation. |
| D2 | §9 — No source material for endurance/functional-fitness modalities | V1 is hypertrophy + powerlifting-strength only; this is a future-source-material gap, not a decision available to make now. |
| D3 | §11 — Whether TrainingOS ever offers an lb display toggle | Pure display-layer/UX decision; internal storage is already locked to kg regardless of the answer. |
| D4 | §14 — `Strength_Program_1/2` authorship and timing | Doesn't change the architectural conclusion already reached (`PROGRAM_FAMILY_MATRIX.md` §3) that they're configuration evidence, not a new methodology — recorded only in case the product owner has independent provenance knowledge. |
| D5 | §15 — Family B's leftover/broken sheet-c data-validation ranges | Import-pipeline hygiene note; no automated spreadsheet-import pipeline is in V1 scope (`CLAUDE.md` rule 11). |

---

## Cross-reference: the eight "pay particular attention" items

| # | Instruction's item | Where addressed |
|---|---|---|
| 1 | Family A has no matching official documentation | D1 |
| 2 | Whether Family A's 3 mesocycle phases run sequentially or are alternatives | A1 |
| 3 | The deload-formula contradiction/asymmetry across families | A3 (rep-rounding, generic) + A4 (weight/rep asymmetry + PDF conflict, per-family) |
| 4 | Whether "Novice" is a distinct ruleset or just a configuration | C1 |
| 5 | Family B Week-4 autoregulation asymmetry | B3 |
| 6 | Family C Week-4 autoregulation freeze | B4 |
| 7 | `linkedResultReference` / slot-reference translation | A5 (plus A6 for the related but distinct dual-tagged-category schema question) |
| 8 | Source formulas that encode spreadsheet mechanics, not training rules | C2 (rounding-increment noise), C3 (dead rating-input columns), D5 (leftover sheet-c validation ranges) |

---

## Proposed V1 rule policy

How each discovered mechanic should actually be encoded, to prevent
Stage 4 from accidentally over-generalizing (treating a family-specific
quirk as universal) or under-generalizing (re-implementing the same rule
shape three times because it showed up in three files):

| Mechanic | Policy | Rationale |
|---|---|---|
| `rmBasedWeekOneLoad`, `fixedMultiplierOfWeekOne` | **Parameterized shared rule** | Identical shape and, for the multiplier table, identical *values* across all three families — this is the clearest case of one real shared rule, not three coincidentally similar ones. |
| `autoregulatedSetCount` core mechanism (baseline + prior rating) | **Parameterized shared rule** | Same formula shape everywhere; only baseline values and pairing targets differ, which are exactly what parameters are for. |
| `autoregulatedSetCount`'s Week-4 behavior (B3, B4) | **Family-specific exception** | Confirmed to differ in *shape*, not just value, between Family B and Family C (§B3/B4 above) — must not be inferred by analogy; each family's exact behavior ships as its own parameter setting, proven by its own regression fixture. |
| `deloadWeightBySchedulePosition` | **Family-specific exception**, via `SourceCompatibleDeloadStrategy` (A4, resolved) | Every family's day-boundary split is a different shape (A: `ceil(dayCount/2)`; B: fixed Mon/Tue-vs-Thu/Fri; C: fixed Mon/Tue-vs-Wed/Thu/Fri) — same rule *type*, but no shared default value is safe to assume for a new family. Not promoted to `TrainingOSDeloadStrategy`, which stays a separate, deferred rule. |
| `deloadRepInstruction` | **TrainingOS-normalized rule** (A3, resolved: always round down) | No longer deferred — `roundingDirection = .down` applies uniformly across all three families, independent of any per-family parameter. |
| `DeloadExerciseAction.omit` (A2, resolved) | **Family-specific exception** | Set explicitly per-slot from confirmed evidence (Family A Mesocycle 2's superset partner only) — not a generalized "blank cell" inference rule. |
| Rounding increment (`2.5`/`5`) read from source | **TrainingOS-normalized rule** (already decided) | Never inherited literally — always resolved through the user's own `EquipmentProfile`, per `METRIC_LOAD_MODEL.md`; this is C2's conclusion restated as policy. |
| Legs-only Heavy exception (B2) | **Exact source emulation**, exposed as an opt-in override | Ships exactly as sourced for the one confirmed file; not generalized to other splits by default. |
| Family C's dead rating-input columns (C3) | **TrainingOS-normalized rule** | Modeled with the rule type that matches actual behavior (`fixedSetSchedule`), not the rule type the spreadsheet's visual layout suggests. |
| Novice-specific behavior | **TrainingOS-normalized rule (i.e., don't implement one)** | No `ProgrammingSystem` parameter added; `experienceLevel` stays non-engine-facing per C1. |
| `linkedResultReference` slot-pairing mechanism | **Parameterized shared rule**, resolved via an authoring-time structural reference (A5, resolved) | Same resolution mechanism across every family's pairings — what differs per program is *which* slots are paired, which is exactly a `ProgramDefinition`-level configuration choice, not a new rule type. |
| Mesocycle sequencing (A1, resolved) | **TrainingOS-designed rule** — sequential `ProgramJourney`, phase-local spreadsheet rules unchanged | Each phase still ships as an independent, parameterized `ProgramDefinition`; `ProgramJourney` is an additive ordering layer, not new per-phase engine logic. See `PROGRAMMING_SYSTEM_MODEL.md` §5.1. |
| Endurance/functional-fitness mechanics | **Deferred rule** | No source material exists yet (D2); not a Stage 4 concern at all. |
| Dual-tagged exercise categories (A6, resolved) | **TrainingOS-designed rule** — real multi-target `ExerciseSlot.allowedTargets`, no special-case entity | Schema resolved now rather than deferred; V1's pre-built configurations may still pre-select one exercise per slot as a UI/generator convenience without narrowing what the schema records. |

---

## Second pass: V1 Program Library

`V1_PROGRAM_LIBRARY.md`'s original recommendation (3 curated pre-built
programs) was architecturally correct but too narrow for real product
use. This section proposes 8, still built on exactly the same 2
`ProgrammingSystem`s — **no new engine, no engine duplication** — by
choosing configurations the source material actually supports rather than
inventing new ones.

### Distinguishing the two levels

- **PROGRAMMING SYSTEM** = the methodology + rule vocabulary +
  parameter *space* (`HypertrophyProgrammingSystem`,
  `PowerliftingProgrammingSystem` — from `PROGRAMMING_SYSTEM_MODEL.md`
  §4). There are exactly two.
- **BUILT-IN PROGRAM CONFIGURATION** = one specific, named, ready-to-use
  point in that parameter space (a specific `dayCount` + `split` +
  phase, or a specific `rmBasisMode` + `dayCount`) — a `ProgramDefinition`
  a user can start today without touching the Generator. There can be as
  many of these as the source material supports, at zero engine cost per
  addition.

### Proposed 8 configurations

| # | Configuration name | Programming System | Parameters | Source workbook | Confirms |
|---|---|---|---|---|---|
| 1 | 3-Day Full Body Hypertrophy | Hypertrophy | `dayCount: 3, split: full_body` | `4847f523-3_day_full_body_Novice.xlsx` | Baseline shape at the smallest day-count. **Named without "Novice"** — per C1, that label has no behavioral basis; shipping it as "Novice" in the UI would misrepresent our own finding. |
| 2 | 4-Day Full Body Hypertrophy | Hypertrophy | `dayCount: 4, split: full_body` | `e1f8fb19-4_day_full_body.xlsx` | The already-analyzed reference file for every Family A rule in `PROGRAM_LOGIC_SPEC.md` §2 — the configuration with the most direct traceability. |
| 3 | 5-Day Full Body Hypertrophy | Hypertrophy | `dayCount: 5, split: full_body` | `1e3d5441-5_day_full_body.xlsx` | Mid-range day-count; `8ebd24ac-5_day_full_body_Novice.xlsx` is corroborating evidence this configuration's rules don't change with the "Novice" label, same reasoning as #1. |
| 4 | 5-Day Upper/Arms Focus | Hypertrophy | `dayCount: 5, split: arms_shoulders` | `f06502c6-5_day_arms__shoulders.xlsx` | The specialization-split case from the architectural proof table (`PROGRAMMING_SYSTEM_MODEL.md` §7) — also the configuration that exercises the dual-tagged-category question (A6). |
| 5 | 4-Day Lower/Leg Focus | Hypertrophy | `dayCount: 4, split: legs` | `bb847616-4_day_legs.xlsx` | The one file that exercises the Heavy-exception override (B2) — deliberately kept in the curated set specifically to ship a real example of the override mechanism, not just the baseline rule. |
| 6 | 6-Day High-Frequency Hypertrophy | Hypertrophy | `dayCount: 6, split: full_body` | `1eb44a1e-6_day_full_body.xlsx` | The highest day-count in the source set; full_body chosen over the 6-day split files (`f63aa557` back/chest, `2d17f31c`/`bf7f7b32` novice-labeled splits) so this configuration reads as "more frequency," not "more specialization," matching the proposed name. |
| 7 | 4-Day Powerlifting Strength | Powerlifting | `rmBasisMode: mixed5_8, dayCount: 4` | `f046f129-RPPowerliftingStr4Day.xlsx` | Carried over unchanged from the original recommendation — still the only file with real, non-blank author data, and the highest-confidence regression-verified configuration in the whole set. |
| 8 | 5-Day Powerlifting Hypertrophy | Powerlifting | `rmBasisMode: uniform10, dayCount: 5` | `6d06b9fd-RPPowerliftingHyp5Day.xlsx` | Carried over unchanged — exercises the Week-4 freeze (B4), a real behavior a shipped program must get right, not a latent one. |

**Two `ProgrammingSystem`s, eight configurations** — every row above is a
parameter choice on `HypertrophyProgrammingSystem` (rows 1–6) or
`PowerliftingProgrammingSystem` (rows 7–8), exactly the outcome
`PROGRAM_FAMILY_MATRIX.md`'s "3 families, not 15 programs" conclusion
predicts. No row required inventing a rule the source material doesn't
already contain.

### What's still true from the original recommendation

- All 6 Hypertrophy configurations ship as **Mesocycle 1 ("Basic
  Hypertrophy") only** for V1, per A1 — no sequencing feature is built
  until mesocycle sequencing is resolved. A product decision to also ship
  Mesocycle 2/3 as additional named configurations (e.g. "4-Day Full Body
  Hypertrophy — Metabolite Focus") is a small follow-on, not a new
  engine — explicitly not decided here, just noted as available at zero
  new-engine cost once A1 has an answer.
- The remaining Family A workbooks not listed above (`f63aa557`,
  `2d17f31c`, `bf7f7b32`, and the two "Novice"-labeled files not chosen as
  the representative for their day-count) stay in the Generator's
  parameter space, not shipped as separate configurations — still true
  from the original recommendation, just with 6 slots filled from that
  space instead of 1.
- `Strength_Program_1/2` (Family D) remain evidence-only, not shipped —
  unchanged.

`V1_PROGRAM_LIBRARY.md` has been revised in place to reflect this
8-configuration set in place of the original 3 (§§2–6 of that document).
The revision is still subject to this memo's review gate like everything
else here — it hasn't been assumed final just because the file was
updated.

---

Per your instruction: **no Stage 4 engine code, no `ProgrammingSystem`
implementation**, has been written. This memo, `V1_PROGRAM_LIBRARY.md`'s
pending revision, and everything else in this document set remain
analysis and decision-support artifacts. Stopping here for review.
