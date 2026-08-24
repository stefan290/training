# Stage 10B — Implementation Plan (One-Split-First: 3-Day Full Body Hypertrophy)

**STATUS: DRAFT — awaiting product owner approval. Nothing in this
document has been implemented.** This plan corrects and supersedes
`STAGE10A_PROGRAMMING_ENGINE_AUDIT.md` §8/§9's "2-4 slots" proposal per
that document's "Amendments" section and the 17-point product-decision
brief that produced it. Scope is deliberately narrow: **only the 3-Day
Full Body Hypertrophy configuration** (`HypertrophyBuiltInLibrary.all[0]`,
`dayCount: 3, split: .fullBody`). Every other `HypertrophySplit`/
`dayCount` combination, Powerlifting, and every other `ProgrammingSystemKind`
are untouched by this stage — see §17 for why the current placeholder
behavior for those is acceptable to leave as-is for now, and §18 for the
named follow-up stage that extends this model to them.

---

## 1. Files to change

**Modified:**
- `TrainingOS/Engines/HypertrophyProgramGenerator.swift` — the only file
  whose *logic* changes. `generate()`'s per-day loop, `makeSlotPair`
  (replaced by a variable-count slot-construction function), and the
  `dayIndex`-ignoring `primarySlotName`/`primaryTargets` helpers (replaced
  by a day-focus table, §4) all change. `laterWeekMultipliers`,
  `repGoalSchedule`, `pairedRepGoalSchedule`, `primaryWeekOneFactor`,
  `metaboliteFocusPairedWeekOneFactor` are all **reused unchanged** — see
  §10.
- `TrainingOS/Application/Seed/ExerciseCatalog.swift` — needs new seeded
  `Exercise` rows for muscle groups the current 27-exercise catalog has
  no isolation candidate for (biceps, triceps-as-isolation, delts-as-
  isolation, calves already covered, core has no strength-modality
  candidate). See §7's "candidate pool gap" and §19 decision D-10B-6 —
  **this is seed/content data, not a generator-architecture decision, but
  the generator cannot produce a sensible Day-C "arms accessory" without
  it.**

**New (test only):**
- `TrainingOSTests/HypertrophyDayFocusGenerationTests.swift` — all new
  Stage 10B tests (§15).

**Not touched by this stage** (confirmed by this plan, not assumed):
`ProgramDefinition`, `TrainingWeek`, `TemplateSession`, `WorkoutBlockTemplate`,
`ExerciseSlot`, `PrescriptionTemplate` (schema — see §2, one new field
only), `StrengthProgressionRules`/`StrengthProgressionEngine`,
`StrengthMaterializer`, `SubstituteExerciseUseCase`,
`SubstitutionValidator`, `HypertrophyBuiltInLibrary`,
`HypertrophyProgramConfiguration`, any Powerlifting/steady-state/interval/
Functional Fitness generator, `ConcurrentScheduler`, `ReadinessGateFlow`,
`GenerateWarmupSequenceUseCase`, `WarmupEmphasisDerivation`.

---

## 2. Domain-model changes

Exactly **one** new stored field, extending an existing type — no new
entity, no new relationship:

```swift
// PrescriptionTemplate.swift addition
var slotRole: SlotRole?          // new enum, new column — see §3
```

`SlotRole` is a plain `String`-backed enum (`Codable, CaseIterable`),
stored the same way `DeloadExerciseAction`/`RMType`/etc. already are on
this exact type (a flat scalar field, per the file's own "manually
flattened tagged union" discipline — `PrescriptionTemplate.swift`'s own
doc comment on why enums-with-payloads are never stored directly; `SlotRole`
carries no payload, so it stores exactly like `DeloadExerciseAction`
already does, no new risk). `nil` is legal (every pre-Stage-10B
`PrescriptionTemplate` row, including Powerlifting's) and means "no slot
role assigned" — not a hidden default of any specific role.

No change to `ExerciseSlot`, `TemplateSession.role` (`SessionRole`, a
*different*, coarser concept — see §4's explicit distinction), or any
`@Relationship`. No new delete rule required — `DELETE_RULE_MATRIX.md`
needs no new entry.

---

## 3. Chosen `SlotRole` representation, and why

**Decision: three cases — `primary`, `secondary`, `accessory` — not
`{primaryCompound, secondaryCompound, isolation}`.**

```swift
enum SlotRole: String, Codable, CaseIterable {
    case primary
    case secondary
    case accessory
}
```

**What job each value does** (per your instruction: "what job does this
slot perform," never biomechanics):
- `.primary` — this day's main emphasis muscle group(s) (Day A's
  quadriceps/chest/delts). Gets the existing autoregulated, RM-anchored
  numeric treatment (§10).
- `.secondary` — this day's supporting-but-still-substantial emphasis
  (Day A's back/hamstrings-glutes/arms as *secondary*, not accessory).
  Numerically, this reuses the **exact same rule shape as `.primary`**
  (§10) — the job difference is purely which muscle groups a slot
  targets and its position in the day's emphasis (used for ordering,
  §11, and coverage accounting, §6), not a distinct numeric treatment.
- `.accessory` — the existing paired/isolation slot (today's "Chest
  Isolation or Triceps"), reusing its exact existing rule shape
  unchanged (§10).

**Why not `{primaryCompound, secondaryCompound, isolation}`:** that
representation encodes a claim this codebase has no source for — that
"secondary" slots are structurally compound lifts as opposed to
isolation ones. Nothing in `PROGRAM_LOGIC_SPEC.md`/`FAMILY_A_*` constants
supports that split, and `Exercise` itself has no "is this exercise a
compound or isolation movement" field to check it against (only
`movementPattern: String`, a free-text label, and `primaryTargets:
[MuscleGroup]`). Naming the case `primaryCompound` would assert
biomechanical structure the generator cannot actually verify — exactly
the "don't encode biomechanics" instruction. `{primary, secondary,
accessory}` instead names **emphasis position within the day's own
`DayFocus`** (§4), which the generator *does* actually know (it's the
thing that produced the day-focus table in the first place) — a job
description, not a movement-science claim.

**Why three cases, not two:** Day A/B/C's descriptions each name three
distinct emphasis tiers ("primary=...", "secondary=...") plus the
existing accessory slot the current generator already has evidence
for (the paired isolation slot). Two cases (`primary`/`accessory`) would
force secondary-emphasis groups (Day A's back/hamstrings-glutes) into
either the primary numeric treatment (overstating their emphasis) or the
accessory numeric treatment (understating it, and contradicting your
explicit "primary slots may justify more work than accessory slots... do
not force identical sets/reps/RIR everywhere" instruction, since it would
flatten two genuinely different emphasis levels into one number). Four+
cases would need a numeric rule this repository has no source for (see
§10's explicit gap flag) — three is the minimum that matches what the
Day A/B/C brief actually specifies without inventing a rule.

---

## 4. The 3-Day Full Body day-focus model

Reusing your Day A/B/C definitions verbatim as the generator's day-focus
table — **programming intent, encoded as `[MuscleGroup]` lists per role
tier, never as hardcoded exercise names**:

```swift
struct DayFocus {
    var name: String                    // "Day A" / "Day B" / "Day C" — display only
    var primary: [MuscleGroup]
    var secondary: [MuscleGroup]
}

static let threeDayFullBodyRotation: [DayFocus] = [
    DayFocus(name: "Day A", primary: [.quadriceps, .chest, .shoulders],
             secondary: [.back, .hamstrings, .glutes, .biceps, .triceps]),
    DayFocus(name: "Day B", primary: [.back, .hamstrings, .glutes],
             secondary: [.chest, .quadriceps, .shoulders, .biceps, .triceps]),
    DayFocus(name: "Day C", primary: [.quadriceps, .hamstrings, .glutes, .chest, .back, .shoulders],
             secondary: [.biceps, .triceps]),
]
```

Day C's primary is deliberately a *broad, balanced* list (your own
description: "balanced full-body + delts + arms-accessory") rather than
2-3 groups like Day A/B — modeled as "primary = the day's structural
compound coverage across the whole body," "secondary = this day's arm
accessory-only emphasis," which is what "arms-accessory" describes. This
is the one place the day-focus table itself makes an interpretive
choice beyond your literal wording (deciding Day C's arm work is
`.secondary` rather than `.accessory`-tier) — flagged here rather than
silently assumed; §19 D-10B-1 asks you to confirm it.

**Relationship to `TemplateSession.role` (`SessionRole`):** unchanged
and unrelated — `SessionRole.hypertrophy` still marks *what kind of
training* the whole session is (vs. `.easy`/`.recovery`/etc., used by
other systems entirely). `DayFocus` is a new, Hypertrophy-generator-
internal concept describing *which muscle groups* that hypertrophy day
emphasizes — it answers a different question and lives at a different
layer (inside `HypertrophyProgramGenerator`, never on `TemplateSession`
itself, so no other consumer of `SessionRole` is affected).

`dayCount` still selects how many `DayFocus` entries are consumed
(`threeDayFullBodyRotation[dayIndex % threeDayFullBodyRotation.count]`)
— for `dayCount == 3` this is exactly one full, non-repeating rotation.
**This stage hardcodes the 3-day table only**; §17/§18 covers what
happens for other day counts.

---

## 5. Variable slot-construction mechanics (count is an output)

For each day, walk `DayFocus.primary` then `DayFocus.secondary` as an
**ordered list of muscle-group targets**, producing one slot per target
**unless a later target is already covered by an earlier slot's
`allowedTargets`** (the dedup rule below) — never a fixed slot count:

```
func buildSlots(for focus: DayFocus) -> [(role: SlotRole, targets: [MuscleGroup])] {
    var slots: [(SlotRole, [MuscleGroup])] = []
    var covered: Set<MuscleGroup> = []

    for group in focus.primary where !covered.contains(group) {
        slots.append((.primary, [group]))
        covered.insert(group)
    }
    for group in focus.secondary where !covered.contains(group) {
        slots.append((.secondary, [group]))
        covered.insert(group)
    }
    // Existing accessory slot, unchanged in kind (still exactly one,
    // still the paired-isolation slot) — see "why exactly one accessory
    // slot survives" below.
    slots.append((.accessory, existingAccessoryTargets(for: focus)))
    return slots
}
```

**Why this naturally produces ~5-7 slots for 3-Day Full Body, without a
hardcoded count:**
- Day A: primary has 3 distinct groups (quadriceps, chest, shoulders) →
  3 primary slots. Secondary has 5 groups (back, hamstrings, glutes,
  biceps, triceps), none already covered → 5 secondary slots. Plus 1
  accessory = **9 slots** — see the flag immediately below.
- This is *more* than your stated 5-7 expectation. The dedup-by-muscle-
  group rule alone is not sufficient to land in 5-7 for Day A/B (whose
  secondary lists are long) — **this is a real, surfaced gap, not
  silently resolved**: see §19 D-10B-2. The most defensible generic rule
  consistent with "count is an output, never a hardcoded input" is
  **one slot per distinct muscle group actually named in that day's
  `primary`+`secondary` union, minus groups already covered by an
  anatomically-broader earlier slot** — but this repository has no
  existing concept of "anatomically broader" (e.g. one compound lift
  covering both quadriceps and glutes already, so a later dedicated
  glutes slot is redundant) to consult. The current generator's own
  `primaryTargets` arrays already model exactly this kind of overlap
  (Back Squat-shaped slots target `[.quadriceps, .glutes]` together, one
  slot, two groups) — so the fix is **not a new rule, but reusing the
  existing "one slot's `allowedTargets` may legitimately name 2+ muscle
  groups at once" pattern already in `makeSlotPair`**, grouping
  Day A's secondary (back, hamstrings, glutes, biceps, triceps) into
  *compound-pattern-shaped* multi-target slots (e.g. one hinge-pattern
  slot targeting `[.back, .hamstrings, .glutes]`, one arms-accessory slot
  targeting `[.biceps, .triceps]`) rather than one slot per single
  muscle group. Doing this drops Day A to: 3 primary (single-group,
  matching your emphasis wording exactly) + 2 secondary (multi-group,
  covering the remaining 5 groups in 2 slots) + 1 accessory = **6
  slots** — inside your stated 5-7 range. Day B mirrors this (3 primary
  multi-group already as one hinge-pattern slot per your own wording +
  2 secondary + 1 accessory ≈ 5-6). Day C (broad primary, narrow
  secondary) naturally lands lower.
- **This grouping-into-compound-pattern-slots step is itself a
  TRAININGOS-DESIGNED interpretive rule, not sourced from any surviving
  program spec** (same discipline `HypertrophyProgramGenerator`'s own doc
  comment already applies to its current single slot pair) — surfaced
  explicitly as §19 D-10B-2, not silently decided here. The number "5-7"
  is confirmed as this stage's *expected outcome check* (§16), never
  encoded as a `maxSlots`/`minSlots` constant anywhere in the generator.

**Why exactly one accessory slot survives per day:** your brief doesn't
ask for the *existing* accessory-slot concept to be removed, only for
the *count of everything else* to stop being hardcoded at "1 primary +
1 accessory." The accessory slot keeps its current job (a fixed,
non-autoregulated, deload-omitted isolation slot) and its current
targets logic generalizes from "always chest/triceps" to "whichever
muscle groups aren't already the day's primary/secondary focus, chosen
from the fixed {chest, back, quadriceps, hamstrings, glutes, shoulders,
biceps, triceps, calves} set" (§6) — still exactly one slot, now
content-aware instead of hardcoded to one pair.

---

## 6. Muscle-group coverage: representation and validation

**Reasons over exactly the 9 groups you named**: `{chest, back,
quadriceps, hamstrings, glutes, shoulders (= "delts" — see naming note
below), biceps, triceps, calves}`. `MuscleGroup` has two further cases
(`.core`, `.forearms`) not in your list — **excluded from coverage
validation per your explicit enumeration**, not an oversight; noted so
a future reader doesn't assume they were forgotten.

*Naming note:* this codebase's `MuscleGroup` enum has no `.delts` case —
`.shoulders` is the existing, already-used equivalent (seeded exercises
already tag `Barbell Bench Press`-adjacent/`Wall Ball`/`Handstand
Push-up` etc. with `.shoulders`). Using the existing case rather than
adding a synonym, per CLAUDE.md rule 6's "canonical, stable" discipline
applied to the taxonomy itself, not just exercise IDs.

**Validation is structural, not physiological** — a pure function run
once at generation time (never persisted, never re-derived from live
history), checking exactly the four properties you named:

```swift
struct WeeklyCoverageReport {
    var neverAppearing: Set<MuscleGroup>          // must be empty
    var identicalConsecutiveDayPairs: [(dayA: Int, dayB: Int)]  // must be empty
    var perDayEmphasisChanges: Bool               // true if focus differs day to day
    var exposureCountByGroup: [MuscleGroup: Int]  // informational, not pass/fail
}

func validateWeeklyCoverage(days: [DayFocus]) -> WeeklyCoverageReport
```

Checks, exactly as specified:
1. **No muscle group disappears** — every one of the 9 groups appears in
   at least one day's `primary`+`secondary` union across the week.
2. **Per-day emphasis changes** — no two days share an identical
   `(primary, secondary)` pair (trivially true for the given Day
   A/B/C table; the check exists so a *future* day-focus table, e.g.
   Stage 10C's, can't silently regress to "same day repeated").
3. **No identical slot pair repeats** — no two `TemplateSession`s in the
   same week produce a slot whose `(role, allowedTargets)` is identical
   *and* whose position (which day) is otherwise interchangeable — in
   practice, subsumed by check 2 for this stage's fixed 3-day table, but
   implemented as its own assertion (not merely inferred from check 2)
   so it independently catches a bug in slot-construction (§5) even if
   the day-focus table itself is fine.
4. **Intentional weekly exposure** — `exposureCountByGroup` is computed
   and asserted non-zero for all 9 groups (folds into check 1) but is
   **not** bounded above by any MEV/MAV/MRV-style number — no
   "at most N times" ceiling exists anywhere in this check, per your
   explicit "no MEV/MAV/MRV or unsourced volume landmarks" instruction.

This runs **inside `HypertrophyProgramGenerator.generate()`**, as a
post-construction assertion (an `assertionFailure`/test-visible check in
DEBUG, not a thrown error in Release — generation must never crash a
user's program creation over a coverage gap; see §19 D-10B-3 for whether
you want stricter behavior). It is not stored on `ProgramDefinition` —
recomputing it from the frozen template graph is always possible and
cheap, matching `StrengthMaterializer`'s own "no stored `Recommendation`
reasoning, just re-run the pure function" precedent.

---

## 7. Exercise-selection mechanics

Unchanged mechanism, reused exactly: each new slot is an `ExerciseSlot`
with `allowedTargets` set to its muscle-group list (§5) — resolution to
a concrete `Exercise` still happens exactly where it already does today
(curated-library authoring time via a fixed `allowedExercises`/
`resolvedExercise`, or `SubstituteExerciseUseCase`/`SubstitutionValidator`
for instance-level changes). **No new selection algorithm** — this
stage only changes *how many* slots exist and *what* each one's
`allowedTargets` is, never *how* a slot becomes a concrete exercise.

**Candidate-pool gap, surfaced explicitly (not silently patched):** the
current seed `ExerciseCatalog` (27 exercises) has **zero** exercises
whose `primaryTargets` names `.biceps` or `.shoulders` alone as an
isolation target, and no strength-modality exercise targeting `.core`.
A Day A/B/C accessory or secondary slot targeting `[.biceps, .triceps]`
or `[.shoulders]` alone will have no curated candidate to resolve to
under the current catalog. This is **seed/content data**, not a
generator-architecture gap — but Stage 10B's own acceptance standard
(§16, "sensible selection... no identical placeholder pair") cannot be
met without it. §19 D-10B-6 asks you to confirm the specific new
exercises to add (this plan proposes, as a strawman needing your
confirmation, not a silent invention: Barbell Curl / Triceps Pushdown /
Lateral Raise — ordinary, unambiguous named lifts, not a training-science
judgment call, but still a content decision outside this plan's
authority to make unilaterally).

---

## 8. Exercise continuity — verified, not newly built

**Confirmed by direct code trace: the existing architecture already
guarantees this. No new mechanism is needed.**

- `HypertrophyProgramGenerator.generate()` builds the entire template
  graph — every `TemplateSession`/`WorkoutBlockTemplate`/
  `PrescriptionTemplate`/`ExerciseSlot` — **exactly once**, at
  `ProgramDefinition` creation time. Stage 10B's changes (§4/§5) only
  change what this one-time construction produces; they do not change
  *when* it runs or introduce a second construction path.
- `StrengthMaterializer.materializeWeek(...)` is called once per week
  and, for week N, iterates the **same, already-persisted**
  `templateSession.orderedBlockTemplates` → `orderedPrescriptionTemplates`
  → `.exerciseSlot` objects every time — it never creates a new
  `ExerciseSlot`, never re-derives `allowedTargets`, never re-runs slot
  construction.
- Each week's `ExercisePrescription` resolves its concrete `Exercise` via
  `SubstituteExerciseUseCase.resolvedExercise(for: slot, in: instance)`,
  defined as `instance.slotSelectionOverride(for: slot)?.selectedExercise
  ?? slot.resolvedExercise` — a pure lookup with **no randomness and no
  re-selection logic**. Absent an explicit `SlotSelectionOverride` (only
  ever written by `substituteGoingForward`, a user-initiated action),
  this returns the exact same `Exercise` every week, by construction.

**Conclusion:** Week 2 cannot "reroll" a Week-1-selected exercise under
Stage 10B, because nothing in Stage 10B touches the resolution call
site or introduces a new per-week slot-construction step. The only
paths that ever change which `Exercise` a slot resolves to are the three
you named as legitimate (`substituteThisSessionOnly` — one prescription,
one week, no persistence beyond that row; `substituteGoingForward` — an
explicit `SlotSelectionOverride`; a future readiness-driven or Home-Gym-
driven mechanism, neither of which exists yet and neither of which this
stage introduces). Documented here rather than building a redundant
continuity mechanism, per your explicit instruction.

---

## 9. Exercise ordering

No new mechanism: `WorkoutBlockTemplate.addPrescriptionTemplate(_:)`
already assigns `sortIndex` in call order (`prescriptionTemplates.count`
at insert time) — Stage 10B's slot-construction loop (§5) simply calls
it in **primary, then secondary, then accessory** order, reusing
`SlotRole`'s own tier ordering as the sort key. `StrengthMaterializer`
already resolves in `orderedPrescriptionTemplates` order (its own
load-dependency reordering for `linkedToPairedSlot` templates is a
separate, narrower concern — §10 — not an ordering change). No fatigue
model, no per-exercise cost function — exactly your instruction
("higher-priority-before-accessory... SlotRole + emphasis sufficient").

---

## 10. Reuse of existing prescriptions/progression — exact rule mapping

**No new numeric rule tier.** Mapped onto the two existing,
already-source-cited rule shapes in `StrengthProgressionRules.swift`/
`HypertrophyProgramGenerator.swift`:

| `SlotRole` | Load rule | Set-count rule | Rep-goal schedule | Deload |
|---|---|---|---|---|
| `.primary` | `.rmBased(rm10, weekOneFactor: primaryWeekOneFactor(for: phaseType), laterWeekMultipliers: [1.05, 1.075, 1.1])` — unchanged, including the `.legs`-split Heavy exception (reinterpreted below) | `.autoregulated(baselineSets: 3)` | `FAMILY_A_REP_GOAL_SCHEDULE` (3/3/2/1, all to-failure) — unchanged | standard |
| `.secondary` | **same as `.primary`, verbatim** — see justification below | **same as `.primary`, verbatim** | **same as `.primary`, verbatim** | standard |
| `.accessory` | `.linkedToPairedSlot(fractionOfSourceResult: 0.6)` (or the Metabolite Focus `.rmBased(rm10, weekOneFactor: 0.6, ...)` variant, unchanged) | `.fixed(setsByWeek: [2,2,2,2])` | `Array(repeating: RepGoal(reps: 12, toFailure: false), count: 4)` | `.omit`/`.omit` |

**Why `.secondary` reuses `.primary`'s rule verbatim, rather than a third
numeric tier:** this repository's authoritative source material
(`PROGRAM_LOGIC_SPEC.md`/`FAMILY_A_*` constants, restated in
`StrengthProgressionRules.swift`'s own doc comments) defines **exactly
two** numeric shapes for Family A: the autoregulated-RM-anchored
"primary" shape and the fixed-linked "paired/accessory" shape. **There is
no third, documented "secondary" numeric shape anywhere in the codebase
or its surviving source docs.** Inventing one (e.g. a distinct
`weekOneFactor`, a different `baselineSets`, a different rep-goal
schedule) would be exactly the "invent an ambiguous training rule"
CLAUDE.md rule 10 forbids. Per your own instruction ("if exact numbers
needed are NOT sourced, STOP and report rather than invent"), this is
surfaced as **§19 D-10B-4**, not silently decided — the plan's default
(reuse `.primary`'s rule) is the only defensible non-invented choice,
but you may prefer a different treatment (e.g. a reduced `baselineSets`
for `.secondary`) if you have a source this trace didn't find.

`.legs` split's Heavy Quads/Glutes exception (day-1 `weekOneFactor =
1.0`) is preserved but **reinterpreted structurally**: it no longer means
"day index 0 of a `.legs`-split program" (a coincidence of the old
single-slot-per-day model) but **"the slot whose `allowedTargets`
contains `{.quadriceps, .glutes}` and whose `SlotRole == .primary`"** —
the same exception, expressed as a content-based match instead of a
positional one, so it survives Stage 10B's day-focus rework without
being silently dropped or silently generalized to slots it never
applied to. This reinterpretation itself is a design decision, not a
mechanical refactor — flagged as **§19 D-10B-5**.

---

## 11. Substitution compatibility

No change required. `SubstitutionValidator.isValid(candidate:for:)`
already validates purely against `ExerciseSlot.allowedTargets`/
`allowedMovementFunctions`/`allowedModalities`/`allowedExercises` —
properties every Stage 10B slot still has, populated the same way.
`substituteThisSessionOnly`/`substituteGoingForward` and their tests
(`SubstitutionRegressionTests`) exercise the slot/prescription contract
generically, never the day-focus table or slot count — Stage 10B adds
more slots of the same kind, not a new kind of slot.

---

## 12. Readiness compatibility

No change required. `EvaluateReadinessAdaptationUseCase`/
`ReadinessAdaptationDecisionUseCase` operate on already-materialized
`Session`/`WorkoutBlock`/`ExercisePrescription` rows and the muscle
groups/pain-overlap logic already reads `Exercise.primaryTargets`
directly off whatever exercise is currently in place — they have no
dependency on how many slots produced that session or what `SlotRole`
they carry. A Stage 10B session with 6 exercises across 3 role tiers is
adapted upon exactly like today's 2-exercise session, just with more
candidates to potentially adapt.

---

## 13. Warm-up generation compatibility

No change required. `GenerateWarmupSequenceUseCase`'s `SessionDemand`
derivation already reads "the first in-scope block's exercises by
`sortIndex`" as primary and "the rest" as secondary — this is **already
a generic, count-agnostic read of `session.orderedBlocks`/
`orderedPrescriptions`**, not hardcoded to today's 2-exercise shape.
A Stage 10B 6-exercise session simply gives `WarmupEmphasisDerivation`
richer signal (more distinct muscle groups/movement functions to derive
`PreparationEmphasis` from), which — per Stage 9B's own refinement pass
— produces a *more* specific, not less specific, generated warm-up. No
regression risk identified; confirmed by inspection, verified for real
in §16's acceptance procedure.

---

## 14. Persistence / schema implications

One new optional column (`PrescriptionTemplate.slotRole: SlotRole?`).
SwiftData's lightweight migration handles a new optional scalar field on
an existing `@Model` without a custom migration plan (the same class of
change as every other optional field added to this type across Stages
3-8). No new `@Model` type, no new relationship, no new delete rule.

---

## 15. Migration implications

**Existing programs (already-generated `ProgramDefinition`s, including
every already-materialized `Session`/`ExercisePrescription`/`SetPrescription`
a real user has logged against) are never touched.**
`HypertrophyProgramGenerator.generate()` only runs when a *new*
`ProgramDefinition` is created — Stage 10B changes what that function
produces going forward, exactly like every prior generator-version bump
(`ProgramDefinition.generatorVersion`, already `1`, would become `2` for
programs generated under the new logic — the existing, already-proven
mechanism for "this definition's shape may differ from a same-name
definition generated under an older generator version," not a new
concept). Every already-persisted `PrescriptionTemplate` row simply has
`slotRole == nil` — legal, and never read by any pre-Stage-10B code path
(§2). No `SetResult`/`WorkoutResult`/`PersonalRecord`/
`ExercisePerformanceProfile` row is affected in any way (CLAUDE.md rule
1 — this stage creates no code path that could touch them; the entire
change is upstream of materialization, in template-graph generation
only).

---

## 16. Tests to add

`HypertrophyDayFocusGenerationTests.swift` (new), covering, table-driven
where applicable:

1. **Slot count/coverage per day** — generating a 3-Day Full Body program
   produces Day A/B/C sessions whose slots' `allowedTargets` unions
   cover exactly the groups named in §4's table (no group silently
   dropped, no group silently added).
2. **`SlotRole` assignment** — every generated slot carries the correct
   `.primary`/`.secondary`/`.accessory` role matching its position in
   the day-focus table.
3. **No identical slot pair repeats** — the 3 generated days produce 3
   distinct `(role, allowedTargets)` sets for at least their primary
   tier (fails if Day A and Day B accidentally produced the same primary
   slot).
4. **`validateWeeklyCoverage` correctness** — one test per one of the 9
   named muscle groups, proving each appears at least once across the
   3-day week; one test proving `.core`/`.forearms` are never asserted
   on (confirming they're excluded, not silently required).
5. **Heavy Quads/Glutes exception still fires**, matched by content
   (`allowedTargets == [.quadriceps, .glutes]` and `role == .primary`)
   rather than by day index — proves §10's reinterpretation.
6. **Exercise continuity across weeks** — materialize week 0 then week 1
   for a 3-Day Full Body instance; assert every slot resolves to the
   identical `Exercise` both weeks (the existing continuity guarantee,
   §8, exercised concretely under the new generator output — this is a
   regression proof, not new logic under test).
7. **Progression correctness carries over** — a `.primary`-role slot's
   week 2-4 weight/set/rep resolution matches
   `StrengthProgressionEngine`'s existing, already-tested output exactly
   (proves §10's rule-reuse claim rather than asserting it).
8. **Substitution still validates** — a Stage 10B-generated slot accepts
   a valid `substituteThisSessionOnly`/`substituteGoingForward` call and
   rejects an invalid one, exactly like existing `SubstitutionRegressionTests`
   assert for today's slots.
9. **Warm-up generation still produces a sequence** for a Stage 10B
   6-exercise session, and the sequence's derived emphasis is provably
   richer/more specific than the current 2-exercise session's (a direct
   regression-improvement check, not merely "doesn't crash").
10. **Deload week correctness** for `.secondary`-role slots — proves
    they deload identically to `.primary` (both use the standard,
    non-`.omit` action), distinguishing them from `.accessory`'s
    `.omit` behavior.

Existing suites requiring no change but re-run for regression:
`TemplateGraphPersistenceTests`, `StrengthMaterializerTests` (or
equivalent), `SubstitutionRegressionTests`, `WarmupGenerationTests`,
`ReadinessAdaptationTests`. Full suite must stay green (currently
699/699) before this stage is considered complete.

---

## 17. Simulator acceptance procedure

Exactly the standard you specified:

1. Generate a Muscle Gain → 3-Day Full Body Hypertrophy program via the
   real onboarding/program-selection flow (not a debug fixture) and view
   the full first week. Inspect Day A, Day B, Day C individually:
   different emphasis per day, sensible slot selection and ordering
   (primary-before-accessory), sufficient coverage (no muscle group
   visibly absent across the 3 days), no identical placeholder pair
   (today's "Chest Isolation or Triceps" appearing on every single day
   regardless of split must be visibly gone), stable structure (same
   session/block/slot count viewing the week twice).
2. Advance to week 2 (materializing it through the real flow) and
   confirm: every exercise selected in week 1 is still present in week 2
   (continuity, §8) and weight/reps/sets have progressed correctly per
   the existing, unchanged progression rules (§10) — spot-check at least
   one `.primary` and one `.secondary` slot's numbers against
   `StrengthProgressionEngine`'s known formula by hand.
3. Confirm readiness check-in, substitution (This Session Only and Going
   Forward), and warm-up generation all still function correctly against
   a Stage 10B-generated session, and that a session can still be
   started/logged/completed independent of any other session (no new
   cross-session coupling introduced).

---

## 18. Explicitly deferred to Stage 10C / 10D / Home Gym (not this stage)

Restated from your brief, plus the concrete scope source for 10C:

- **Stage 10C** extends the validated day-focus/`SlotRole`/coverage
  model to the other configurations `HypertrophyBuiltInLibrary`/
  `HypertrophySplit` **already claim to support**: `.legs` (4-Day
  Lower/Leg Focus), `.armsShoulders` (5-Day Upper/Arms Focus), and the
  remaining `.fullBody` day counts (4/5/6-day). **Confirmed by direct
  read of `HypertrophyBuiltInLibrary.swift`** — these are the only
  splits with an existing curated entry; nothing named "Upper/Lower" or
  "Push/Pull/Legs" currently exists as a `HypertrophySplit` case, so
  10C's scope is these 3 existing split values, not new ones invented
  for the purpose (matching your "use actual existing supported
  configurations as scope source" instruction). Whether Upper/Lower or
  Push/Pull/Legs are added as *new* `HypertrophySplit` cases is a
  separate, not-yet-requested scope-expansion decision (CLAUDE.md rule
  11), out of both 10B and 10C.
- **Stage 10D** — cross-modality/concurrent-training-aware content
  (avoiding duplicate stimulus against a same-window Functional
  Fitness/Powerlifting session), its own design pass, explicitly not a
  general fatigue model.
- **Home Gym** — no new type invented now (§15's "training intent
  independent of exact exercise" is already satisfied by
  `ExerciseSlot.allowedTargets`-based resolution; an equipment filter is
  a future, additive constraint on candidate selection, not a Stage 10B
  concern).
- MEV/MAV/MRV or any volume-landmark number, fatigue-cost/axial-fatigue/
  joint-stress scoring, recovery-resource modeling, automatic exercise
  rotation, specialization blocks, maintenance-specific volume rules,
  Home Gym equipment filtering, sophisticated cross-modality
  interference modeling, AI/LLM-based generation — none of these appear
  anywhere in this plan.

---

## 19. Remaining product/training-science decisions requiring your approval

- **D-10B-1** — Day C's arm work modeled as `.secondary` rather than
  `.accessory` tier (§4's interpretive note). Confirm or correct.
- **D-10B-2** — the compound-pattern multi-target-slot grouping rule
  that brings Day A/B down from 9 raw single-muscle-group slots to
  ~5-7 (§5) is TRAININGOS-DESIGNED, not source-cited. Confirm this
  grouping approach, or provide/require a different one.
- **D-10B-3** — should a generated program that fails
  `validateWeeklyCoverage` (§6) hard-fail generation (never persisted),
  or persist with a surfaced warning? No existing precedent in this
  codebase for either choice at generation time.
- **D-10B-4** — `.secondary`'s numeric rule reuses `.primary`'s verbatim
  (§10) because no distinct "secondary" rule is sourced anywhere.
  Confirm, or supply the distinct rule if one exists that this trace
  didn't find.
- **D-10B-5** — the `.legs` Heavy Quads/Glutes exception is
  reinterpreted from positional (day index 0) to content-based
  (`{.quadriceps, .glutes}` + `.primary`) matching (§10). Confirm this
  preserves the intended exception correctly.
- **D-10B-6** — new seed `Exercise` rows are needed for `.biceps`/
  `.shoulders`-isolation/`.core` candidates (§7). This plan proposes
  Barbell Curl / Triceps Pushdown / Lateral Raise as a strawman; confirm
  these specific additions (or supply different ones) before
  implementation, since seed-catalog content is not this plan's call to
  make unilaterally.

---

**Do not implement any of the above until this plan is explicitly
approved.**
