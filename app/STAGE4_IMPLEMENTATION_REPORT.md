# Stage 4 Implementation Report

## Stage 4A: HypertrophyProgrammingSystem

Implements the first concrete, deterministic TrainingOS programming
system on top of the validated Stage 3 architecture — one engine +
`ProgramConfiguration`, per the kickoff instruction, covering all 6
curated V1 built-in configurations. Stages 4B-4F (Powerlifting,
SteadyState, Interval, FunctionalFitness, ConcurrentScheduler) are not
started; per the kickoff's own instruction ("do not attempt all six in
one large untested diff"), Stage 4A was built, tested, and validated on
the real Xcode toolchain before writing a single line of any other
system.

Baseline: commit `700abb7d0700634ededa99a44f0e8e4f0d87d1f2` (Stage 3
gate, approved). All work below was built, tested and validated on the
local Xcode toolchain directly — unlike Stage 3C, there was no
non-macOS-environment handoff step this time.

## 1. The architecture decision that came before any rule code

The product owner's kickoff resolved the one open architectural question
Stage 3 left behind (flagged by this pass's own pre-implementation
research, not previously documented anywhere): **a persisted, generator-
produced template graph**, distinct from the dated execution graph:

```
ProgramDefinition
  -> TrainingWeek[]            (week markers only: sortIndex, isDeload)
  -> TemplateSession[]         (the ONE recurring weekly structure)
       -> WorkoutBlockTemplate[]
            -> PrescriptionTemplate[]
                 -> ExerciseSlot
```

**Correction made during this pass's own implementation, before it
shipped:** the initial schema (matching the kickoff's own sketch) nested
`TemplateSession` under `TrainingWeek`, implying one copy of the session
structure per week. This directly contradicted the rule design itself —
`RMBasedLoad.laterWeekMultipliers`/`StrengthProgressionRules.repGoalSchedule`
already express a whole mesocycle's week-by-week progression as arrays on
a *single* `PrescriptionTemplate`, and deload behavior is a rule
(`deloadWeightAction`/`deloadRepAction`), not a separately-templated week.
`TemplateSession` was moved to attach directly to `ProgramDefinition`
(one recurring weekly structure, not one per week) before any generator
code was written against the wrong shape; `TrainingWeek` reverted to
exactly its Stage 1-3 shape (`sortIndex`/`isDeload`, no content). See
`TrainingWeek.swift`'s doc comment.

Execution-side materialization uses the pre-existing
`ProgramInstance -> Day -> Session -> WorkoutBlock -> ExercisePrescription
-> SetPrescription` graph unchanged.

## 2. New value types (`Domain/ValueTypes/`)

| File | Contents |
|---|---|
| `StrengthProgressionRules.swift` | `RMType`, `RMBasedLoad`, `RepGoal`, `LoadRule`, `SetCountRule`, `DeloadExerciseAction`, `StrengthProgressionRules`, `LoadRuleKind`, `SetCountRuleKind`, `HypertrophyReasonCode` |
| `MuscleGroup.swift` | `MuscleGroup` — `ExerciseSlot.allowedTargets`' tag set (decision A6) |
| `HypertrophyConfiguration.swift` | `HypertrophySplit`, `HypertrophyPhaseType`, `HypertrophyProgramConfiguration` |
| `ProgramProvenance.swift` | `ProgrammingSystemKind`, `ProgramProvenance` |
| `EquipmentProfile.swift` | `IdealLoad`, `EquipmentType`, `RoundingRule`, `EquipmentProfile` — the metric-native load model (§4) |

## 3. New persisted entities (`Domain/Entities/`)

`ExerciseSlot`, `PrescriptionTemplate`, `WorkoutBlockTemplate`,
`TemplateSession` — all registered in `PersistenceController.schema`.
`ProgramDefinition` gained `programmingSystem`, `generatorVersion`,
`provenance`, `hypertrophyConfiguration`, `templateSessions`; `TrainingWeek`
is unchanged from Stage 1-3 (see §1).

## 4. A second and third distinct SwiftData persistence bug, found and fixed

Stage 4 explicitly warned "remember the Stage 3C `ClosedRange` failure;
do not assume Codable types are persistence-safe" — this pass needed that
warning twice more, both caught by `TemplateGraphPersistenceTests`
*before* any generator/engine code was written on top of the broken
shape:

**Bug 2 — an enum case with 3+ associated values crashes
`Decodable.init(from:)`.** `LoadRule.rmBased(rmType:weekOneFactor:laterWeekMultipliers:)`
(3 associated values) crashed with a Swift dynamic-cast failure inside
SwiftData's synthesized decoder, regardless of the individual value
types. Fixed by bundling the 3 values into one `RMBasedLoad` struct
(reducing the case to 1 associated value — a struct payload, not the
count of underlying fields, is what SwiftData actually persists).
`ProgramProvenance.sourced(file:sheet:cell:)`'s 3 `String` associated
values did *not* trigger this, so arity alone isn't the whole story;
bundling multi-value cases into one struct payload is the safe pattern
either way.

**Bug 3 — nesting an enum-with-payload inside a wrapping struct crashes
the persisted-property getter, and (more seriously) two sibling rows of
the same `@Model` type holding *different* cases of the same
enum-with-payload property silently decode the second row's value as
`nil`.** Diagnostic tests isolated this precisely:
`TemplateGraphPersistenceTests.testDiagnosticTwoSiblingRowsWithDifferentLoadRuleCases`
reproduced it with two bare `PrescriptionTemplate` rows (no relationships
at all) holding `.none` and `.linkedToPairedSlot` respectively — the
second row's `loadRule` decoded as `nil`.
`testDiagnosticTwoSiblingSteadyStatePrescriptionsWithDifferentIntensityTargetCases`
confirmed the pre-existing, already-Xcode-validated Stage 3C
`SteadyStatePrescription.primaryIntensity: IntensityTarget?` field is
**not** affected (two rows with `.heartRateZone`/`.powerZone` round-trip
correctly) — this is not a general regression, it is specific to storing
an enum-with-payload *nested inside a wrapping struct field*
(`StrengthProgressionRules.loadRule`), not as a *direct* top-level
`@Model` property (`IntensityTarget`/`ScoreValue`'s proven-safe shape).

Fixed by abandoning the wrapping-struct-as-persisted-property shape
entirely: `LoadRule`/`SetCountRule` are never stored directly on
`PrescriptionTemplate`. Instead, `PrescriptionTemplate` stores a manually
flattened tagged union — `loadRuleKind: LoadRuleKind?` (a plain rawValue
enum, no associated values) plus one flat scalar/array field per case's
parameter (`loadRuleRMType`, `loadRuleWeekOneFactor`,
`loadRuleLaterWeekMultipliers`, `loadRuleFractionOfSourceResult`, and the
`setCountRule`/`repGoalSchedule` equivalents) — the same shape already
used everywhere else in this codebase for anything that varies per row
(e.g. `WorkoutResult`'s per-block-type optional fields). Computed
`loadRule`/`setCountRule`/`repGoalSchedule`/`rules` properties on
`PrescriptionTemplate` provide the same ergonomic `StrengthProgressionRules`
bundle to calling code; nothing outside `PrescriptionTemplate.swift`
needed to change.

**A pure-Swift pitfall found while fixing the above, unrelated to
SwiftData:** `LoadRuleKind` has its own case named `none`; switching over
`LoadRuleKind?` with a bare `case .none:` is ambiguous with
`Optional.none` (nil) and produces a non-exhaustive-switch compile error.
Fixed with `if let kind = loadRuleKind { switch kind { ... } }` instead of
switching the optional directly. The same ambiguity bit a test assertion
too — `XCTAssertEqual(x.loadRule, .none)` against a `LoadRule?`-typed
expression silently asserts against `nil`, not `LoadRule.none`; fixed by
writing `LoadRule.none` explicitly wherever this pattern appears.

**Net effect on `DELETE_RULE_MATRIX.md`'s risk framing:** the "no source
workbook exists, only documented rules" risk from Stage 3C is unrelated;
this is a new, distinct finding about SwiftData's Codable-enum
persistence that future stages (Powerlifting shares `LoadRule`/
`SetCountRule` directly, so it's already immune; SteadyState/Interval/
FunctionalFitness introduce their own rule vocabularies) must repeat this
same diagnostic discipline for, not assume solved by the `BoundedRange`
fix alone.

## 5. Metric-native load handling (§11)

`IdealLoad` (plain, unrounded kg) -> `EquipmentProfile.resolve(_:)` (the
only place rounding happens). Verified against the worked example (180 lb
-> 81.646266 kg -> 82.5 kg at a 2.5 kg increment) and the cascading-
rounding rule (`METRIC_LOAD_MODEL.md`'s explicit warning: each week
resolves off the *previous week's resolved* value, not a fresh
computation from the raw RM) — proven directly against Family A's own
numbers (Week 1=85, Week 2=90, Week 3=92.5, Week 4=92.5,
`EquipmentProfileTests.testWeeklyResolutionCascadesOffTheResolvedWeekOneValue`).
`.bodyweightPlusExternal` rounds only the external portion, adding
bodyweight back unrounded.

## 6. Family A rule engine (`Engines/`)

`HypertrophyProgressionEngine` (pure, no SwiftData) implements
`rmBasedWeekOneLoad`+`fixedMultiplierOfWeekOne` (combined into one
`LoadRule.rmBased` rule — `PROGRAM_LOGIC_SPEC.md` documents them as two
named rule types, but Family A's own data always pairs a Week-1 factor
with the identical 3-multiplier later-week schedule, so one rule
parameterized by both is the correct generalization, not two coupled
rules that must always be used together), `autoregulatedSetCount`,
`fixedSetSchedule`, `repGoalSchedule`, and `linkedResultReference`
(`.linkedToPairedSlot`, always reading the paired slot's *current week's*
resolved value, not just Week 1's).

`SourceCompatibleDeloadStrategy` (conforming to a `DeloadStrategy`
protocol, per decision A4) implements `deloadWeightBySchedulePosition`
(day-boundary asymmetry), `deloadRepInstruction` (always floors — proven
with a non-Family-A 2/3 fraction specifically, to rule out a
round-to-nearest coincidence, per `PROGRAM_REGRESSION_TEST_PLAN.md` §9.1's
own stated purpose), and one rule this pass's research surfaced that
wasn't in the kickoff's rule-type list: **deload-week sets are a
hardcoded constant (2), never autoregulated, regardless of the slot's
normal `setCountRule`** — `resolveDeloadSetCount`, tested against both a
`.fixed` and an `.autoregulated` slot to confirm neither's normal rule
leaks through during deload. A `TrainingOSDeloadStrategy` conforming to
the same protocol is deliberately not built (decision A4) — reserved for
whenever a TrainingOS-native (non-source-derived) deload rule is actually
needed.

All regression fixtures required by the kickoff (§10) are implemented as
table-driven unit tests, all **CONSTRUCTED** (RM=100) per
`PROGRAM_REGRESSION_TEST_PLAN.md` — confirmed by this pass's own
exhaustive repository search that **no real Family A source workbook
exists anywhere in this repository** (no `.xlsx`/`.xls`/`.csv`/`.pdf`
files, no "Family A"/"MROUND"/workbook references outside the already-
analyzed markdown docs). `PROGRAM_LOGIC_SPEC.md`'s own cell-citation
format is preserved in every fixture's doc comment even though the cited
workbook itself doesn't survive:

- Load progression (Week1=85, Week2=90, Week3=92.5, Week4=92.5)
- Autoregulation with a negative rating (baseline 3 -> +1 -> 0 -> -1 -> 3,4,4,3)
- Deload weight day-boundary asymmetry (4-day: days 1-2 full, days 3-4 half)
- Deload rep rounding, always floor (7×½=3, 5×⅔=3, 8×½=4)
- Superset-partner omit + the required negative case (the pair's primary
  still computes a normal deload value, proving the evaluator doesn't
  omit the whole day-pair)

## 7. Generator, materializer, journey, built-ins (Application/UseCases)

- **`HypertrophyProgramGenerator`** — configuration -> persisted template
  graph, once. **Scope, stated plainly (matching the STAGE3C report's own
  candor about what a pass does and doesn't claim):** proves the rule
  engine mechanics — day-count parameterization, phase-specific week-1
  factors, the confirmed Heavy-Quads/Glutes exception, autoregulation,
  `linkedResultReference`, the deload marker — with **one representative
  primary + paired-accessory slot pair per training day**. It does not
  claim a complete, realistic per-day exercise selection for every
  day-count/split combination — no source workbook survives to derive
  that content from, and fabricating it with false confidence would
  violate the standing "do not invent ambiguous training rules" rule.
  Flagged as a follow-up for whoever has access to the actual Family A
  program content, not solved here.
- **`HypertrophyMaterializer`** — template -> one week's real
  `Day`/`Session`/`WorkoutBlock`/`ExercisePrescription`/`SetPrescription`
  rows. **Scope, stated plainly:** only week 0 (self-contained, needs
  only a tested RM) and the deload week (given week 0's already-resolved
  values) are implemented. Weeks 1-3 need the *actual* outcome of the
  previous week (a live autoregulation rating, the previous week's actual
  set count) as runtime input — data that doesn't exist until a user has
  actually trained that week. Materializing it upfront would mean
  fabricating a rating, which Stage 4's own "do not guess aggressively"
  instruction (§36) rules out. A real app calls `materializeWeek` again
  for week N once week N-1's actual results are known, using the exact
  same per-slot engine calls already built — no new engine work needed to
  extend this later.
  **A real bug caught by this file's own tests:** `pairedSlot` is a
  reference to another `PrescriptionTemplate` (despite the name, not to
  an `ExerciseSlot`) — the first materializer draft looked up a paired
  slot's resolved weight in a dictionary keyed by `ExerciseSlot.id`,
  silently returning `nil` and producing `calibrationRequired` instead of
  the linked weight. Fixed with a second, internal-only map keyed by
  `PrescriptionTemplate.id`; the public, caller-facing
  `resolvedWeightsBySlotID` (keyed by `ExerciseSlot.id`, the identity a
  caller actually has) is unaffected.
  **No `Recommendation` is persisted** — `Recommendation.reasonCode` is
  typed to `ProgressionReasonCode` (`DoubleProgressionEngine`'s
  vocabulary); mapping `HypertrophyReasonCode` onto it would misrepresent
  which engine produced the value. Resolved values are written directly
  onto `SetPrescription.targetWeight`/`repRange*` instead, exactly like
  Stage 1-2's hand-authored seed data, since the engine is pure and
  deterministic (any later audit can simply re-run it). A typed
  `Recommendation.hypertrophyReasonCode` sibling field is a reasonable
  follow-up if stored "why" auditability is specifically needed, not a
  defect of this pass.
- **`HypertrophyProgramJourney`** — Basic Hypertrophy -> Metabolite Focus
  -> Resensitization, 3 independent `ProgramDefinition`/`TrainingPhase`/
  `ProgramInstance` triples via `TrainingPlan.orderedPhases` (no new
  entity — decision A1, confirmed already resolved by Stage 3B; see
  `TrainingPhase.swift`'s "ProgramJourney note"). Each phase independently
  startable — proven directly by materializing only the *second* phase
  and confirming the other two remain un-materialized, not merely
  asserted.
- **`HypertrophyBuiltInLibrary`** — the 6 curated V1 hypertrophy
  configurations from `V1_PROGRAM_LIBRARY.md` (3/4/5/6-day full body,
  5-day upper/arms focus, 4-day lower/leg focus), plain configuration
  values instantiated through the one shared generator — no per-config
  engine. Powerlifting's 2 built-ins are Stage 4B.

## 8. Test count and result

115 tests across 17 test files (62 pre-existing — 39 Stage 1-3 + 22
Stage 3C + 1 `TrainingStressProfile` addition from the Stage 3C
Xcode-validation pass — + 53 new Stage 4A tests across 7 new test
files). All 115 pass on the real Xcode toolchain — this was never
validated in a non-macOS environment first; every test file was built
and run against the actual compiler and SwiftData runtime from the
start.

New Stage 4A test files: `TemplateGraphPersistenceTests` (8 tests,
including 3 diagnostic tests that isolated the SwiftData bugs in §4),
`EquipmentProfileTests` (8), `HypertrophyProgramGeneratorTests` (10),
`HypertrophyProgressionEngineTests` (14, covering every regression
fixture in §6), `HypertrophyMaterializerTests` (5),
`HypertrophyProgramJourneyTests` (4), `HypertrophyBuiltInLibraryTests` (4).

## 9. Simulator

Built and launched on an iPhone 17 (iOS 26.5) simulator. No crash — the
`ModelContainer` opened successfully with all new Stage 4A `@Model` types
registered in the schema alongside every Stage 1-3C type. Today renders
identically to every prior pass ("Lower A" 07:00, "Evening Zone 2" 18:00)
— Stage 4A added no seeded content and touched no UI/ViewModel code, so
this is purely the schema-migration regression check the kickoff
requires (§41), not a check for new UI (there is none, by design).

## 10. What Stage 4A does not claim

- A complete, realistic per-day/per-split exercise catalog for every one
  of the 6 built-in configurations (§7's `HypertrophyProgramGenerator`
  scope note).
- Materialization of weeks 1-3 (needs real, not-yet-existing user
  training outcomes as input — §7's `HypertrophyMaterializer` scope
  note).
- A stored, typed `Recommendation` for Hypertrophy's engine outputs
  (§7's materializer note).
- Any UI surfacing of Hypertrophy programs — Stage 4A is domain-model
  and engine layer only, matching the standing "no UI expansion" scope
  boundary.
- Powerlifting, SteadyState, Interval, FunctionalFitness, or
  ConcurrentScheduler (Stages 4B-4F) — not started.

## 11. Commit

See the final commit hash reported alongside this document. Local and
remote verified to match; working tree clean apart from local Xcode user
data, matching every prior pass's report format.

## Stage 4B: PowerliftingProgrammingSystem

Reuses the Stage 4A template-graph architecture unchanged. Per the
kickoff's own instruction, Family B ("RP Powerlifting Strength") and
Family C ("RP Powerlifting Hypertrophy-block") are two
`PowerliftingProgramConfiguration` parameterizations of one
`PowerliftingProgramGenerator` + the shared `StrengthProgressionRules`
rule vocabulary — no per-family engine.

### 1. Shared rule vocabulary extended, additively

`StrengthProgressionRules` (renamed from the Stage 4A `Hypertrophy*`
naming — see §2) gained four purely-additive fields, all defaulted so
every existing Family A fixture is untouched:

- `AutoregulatedSetCount` struct — bundles `baselineSets` with
  `applyRatingOnFinalWeek: Bool = true` (Family B's Week-4 asymmetry:
  the final week's rating is ignored, the previous week's set count
  carries forward unchanged) and `freezeAfterWeek: Int? = nil` (Family
  C's Week-4 freeze: autoregulation stops entirely after a given week,
  every later week — including Week 4 — holds that week's frozen value
  regardless of any rating supplied). These are genuinely different
  mechanisms, not the same behavior under two names — proven directly by
  `PowerliftingRegressionTests.testFamilyBAsymmetryAndFamilyCFreezeAreDistinctMechanisms`.
- `StrengthReasonCode` (renamed from `HypertrophyReasonCode`) gained
  `.autoregulatedSetFinalWeekUnchanged` and `.autoregulatedSetFrozen`.
- `DeloadPositionOverride` struct — `boundaryDayIndex`,
  `fullPositionFactor`, `halfPositionFactor`. Family A's deload day-split
  was previously hardcoded to `ceil(dayCount/2)+1`/0.7/0.5 inside
  `DeloadStrategy` itself; Family B needs the *same shape* of split
  (boundary + full/half factor) but with a different boundary (fixed at
  2, not derived from `dayCount`) and, for reps, a different pair of
  factors (2/3 and 1/2, not a single flat fraction). Generalized into a
  configurable override on `StrengthProgressionRules`
  (`deloadWeightPositionOverride`, `deloadRepPositionOverride`), both
  `nil` by default — `nil` reproduces Family A's original hardcoded
  formula exactly, so no existing test needed to change.
- `deloadSetCount: Int = 2` — made configurable per-rule rather than a
  hardcoded engine constant, defaulted to Family A's confirmed value.
  **Flagged, not invented:** neither Family B nor Family C's source
  material documents a deload set count at all (only weight and reps);
  this default is carried forward without independent confirmation, and
  is called out again in `PowerliftingProgramGenerator`'s own doc
  comment.

### 2. Rename: `Hypertrophy*` shared engine/materializer -> `Strength*`

`HypertrophyProgressionEngine` -> `StrengthProgressionEngine`,
`HypertrophyMaterializer` -> `StrengthMaterializer` (and their test
files) — both were already family-agnostic pure functions operating on
`StrengthProgressionRules`; the old names implied Family-A-only scope
that no longer matched what the code does now that Family B/C share the
same engine. `HypertrophyProgramGenerator`/`HypertrophyProgramJourney`/
`HypertrophyBuiltInLibrary` keep their names — those really are
Hypertrophy-specific (day-count/split/phase configuration, the 3-phase
journey), unlike the engine and materializer underneath them.

### 3. `PrescriptionTemplate` flat-storage extension

Following the Stage 4A Bug-3 pattern exactly (§4 above — no enum-with-
payload may be stored nested inside a wrapping struct field on a
`@Model`), the new rule fields were added as more flat scalar fields
alongside the existing tagged-union storage:
`setCountRuleApplyRatingOnFinalWeek: Bool = true`,
`setCountRuleFreezeAfterWeek: Int?`, `deloadWeightPositionOverride:
DeloadPositionOverride?`, `deloadRepPositionOverride:
DeloadPositionOverride?`, `deloadSetCount: Int = 2` — `DeloadPositionOverride`
itself is a plain struct of primitives (no nested enum), the
proven-safe shape from Stage 4A's own finding. Round-trip proven with
**two sibling rows holding different `AutoregulatedSetCount`/
`DeloadPositionOverride` values** specifically
(`TemplateGraphPersistenceTests.testStageFourBDeloadOverridesAndAutoregulationExtensionsSurviveRoundTrip`)
— the exact shape (sibling-row heterogeneity) that exposed Bug 3 in the
first place, so this is not assumed safe by analogy, it's re-tested.

### 4. `DeloadStrategy` generalized for day-position overrides

`resolveDeloadWeight`/`resolveDeloadRepGoal` check
`rules.deload*PositionOverride` first and fall back to the original
Family-A-hardcoded formula only when `nil` — Family A's own tests pass
unchanged. `resolveSetCount` gained `isFinalWeek`/`frozenSetCount`
parameters: freeze check first (`weekIndex > freezeAfterWeek` ->
`frozenSetCount`, `.autoregulatedSetFrozen`), then the final-week
exception (`isFinalWeek && !applyRatingOnFinalWeek` -> previous week's
value unchanged, `.autoregulatedSetFinalWeekUnchanged`), else the
existing rating-addition logic.

### 5. `PowerliftingProgramGenerator` (`Application/UseCases/`)

One generator, two private family-specific functions
(`generateFamilyB`/`generateFamilyC`), both building local closures/
variables only — no static mutable state (an early draft used
`static var` for Family C's cross-day Friday-backoff-to-Monday-squat
pairing; recognized as fragile before ever building or testing it, and
rewritten with local variables/closures within `generateFamilyC` itself).

- **Family B** (4 representative slots): Monday "Bench (Triples)" (5RM,
  0.7 factor, flat 3-rep non-toFailure schedule, `applyRatingOnFinalWeek:
  true`), Tuesday "Squat" (5RM, 0.95, stepping rep schedule,
  `applyRatingOnFinalWeek: true`), Thursday "Deadlift (Triples)" (5RM,
  0.7, flat reps, `applyRatingOnFinalWeek: false` — the Week-4 asymmetry),
  Friday "Upper-Pull" (8RM, `.fixed([2,2,3,3])`, never autoregulated).
  Both Triples rows and both ordinary rows share the same deload
  position-override pair (boundary 2, weight 0.7/0.5, reps 2/3 · 1/2).
- **Family C** (6 slots across 5 days): Monday "Squat"/Tuesday "Bench"/
  Wednesday "Row" (10RM, 0.95, `AutoregulatedSetCount(baselineSets: 3)`,
  no freeze), Thursday "Deadlift"/Friday "Overhead Press"
  (`freezeAfterWeek: 2`), plus Friday "Squat Backoff"
  (`.linkedToPairedSlot(fractionOfSourceResult: 0.85/0.95)`, structurally
  paired to Monday's slot via `pairedSlot`, `deloadRepFraction: 1.0` —
  the sole no-reduction exception among Family C's deload reps). All
  rows share `deloadWeightPositionOverride` (boundary 2, 1.0/0.5 — no
  reduction Mon/Tue, halved Wed-Fri).
- **Flagged, not invented (per the generator's own doc comment):**
  neither family's exact 10-slot (Family B) / full day-by-day (Family C)
  exercise catalog survives in the source material beyond the explicitly
  cited day names — this pass proves the *rule engine mechanics* with
  one representative slot per day, matching `HypertrophyProgramGenerator`'s
  identical, already-accepted scope statement. Family C's non-deload
  rep-per-week schedule is also undocumented anywhere in the surviving
  material; a flat 8-reps-every-week placeholder is used, explicitly
  flagged in the source as unconfirmed.

### 6. Regression fixtures proving Family B/C distinctness (`PowerliftingRegressionTests`, 12 tests)

Engine-level (not generator/materializer-level), all **CONSTRUCTED**
(RM=100), each numeric fixture precomputed in Python before being
written as a Swift assertion (the Stage 3C-era 52.5-vs-50 mistake
discipline, applied again here):

- Mixed 5RM/8RM basis and uniform 10RM basis resolve independently
  through the same engine call.
- Triples protocol: week-1 factor 0.7 (-> 70) distinct from the ordinary
  0.95 factor (-> 95); rep goal flat across all 4 weeks.
- Family B Week-4 asymmetry: baseline 3 -> 4 -> 4 -> **4** even when
  Week 4 is deliberately supplied a rating of +1 that would otherwise
  raise it to 5 — proves the rating is ignored, not merely untested.
- Family C Week-4 freeze: baseline 2 -> 3 -> 4 -> **4** even when Week 4
  is deliberately supplied a *negative* rating — rules out the freeze
  being mistaken for "the rating happened to be 0."
- Explicit side-by-side proof (`testFamilyBAsymmetryAndFamilyCFreezeAreDistinctMechanisms`)
  that the two Week-4 shapes are structurally different configurations,
  not the same behavior under two names.
- Family C backoff: Monday resolves to 95, Friday backoff resolves to
  85 as a fraction (0.85/0.95) of Monday's *resolved* value, not an
  independent computation.
- Family B deload: both the Triples row (70 -> 50/35 by day position)
  and the ordinary row (95 -> 67.5/47.5) exercise the real 2/3 · 1/2 rep
  split and 0.7 · 0.5 weight split, both position sides.
- Family C deload: weight unchanged Monday/Tuesday, halved from
  Wednesday on; reps uniformly halved for every row **except** the
  Friday backoff, whose reps are the sole unchanged exception — tested
  as an explicit negative case against an ordinary row, not just
  asserted for the backoff alone.
- Metric-native / no-lb-rounding-leakage: the same rule resolves to a
  different final number purely from swapping the `EquipmentProfile`
  increment (2.5 kg vs 5 kg vs 0.25 kg), proving no rule stores or
  assumes a rounding increment itself.

### 7. `PowerliftingBuiltInLibrary` (`Application/UseCases/`, 3 tests)

The 2 curated V1 configurations from `V1_PROGRAM_LIBRARY.md` (#7-8):
"4-Day Powerlifting Strength" (Family B, `dayCount: 4`) and "5-Day
Powerlifting Hypertrophy" (Family C, `dayCount: 5`) — plain
`PowerliftingProgramConfiguration` values instantiated through the one
shared generator, mirroring `HypertrophyBuiltInLibrary`'s pattern
exactly. Tests confirm both instantiate correctly, produce genuinely
different day structures (4 vs. 5 named sessions), and each carries the
correct `programmingSystem`/`powerliftingConfiguration`.

### 8. Architectural judgment: no flaw found in the template graph or materializer

Per the kickoff's explicit instruction to stop and explain before
working around any exposed flaw: Family B/C required extending the
*rule vocabulary* (new `StrengthProgressionRules` fields, all additive)
and the *pure deload-strategy functions* (position-override lookups
that fall back to the original formula), but the template graph itself
(`ProgramDefinition -> TemplateSession -> WorkoutBlockTemplate ->
PrescriptionTemplate -> ExerciseSlot`) and the materialization mechanism
needed no structural change at all — `PowerliftingProgramGenerator`
builds the identical entity graph shape `HypertrophyProgramGenerator`
does, just with different rule parameters. This is not a flaw in the
generic architecture; it's the additive-configuration outcome Stage 4A
was validated to support.

### 9. Test count and result

144 tests total (115 Stage 4A baseline + 29 new Stage 4B tests). All 144
pass on the real Xcode toolchain, including all 115 pre-existing tests
unchanged — none weakened.

New/changed Stage 4B test files: `PowerliftingProgramGeneratorTests`
(13, structural: day names/counts, RM-type mixing, Triples factor+rep
goal, Week-4 asymmetry-vs-freeze distinction, Friday accessory fixed
schedule, deload day-split overrides, backoff structural pairing,
round-trip persistence), `PowerliftingRegressionTests` (12, engine-level
numeric — §6 above), `PowerliftingBuiltInLibraryTests` (3),
`TemplateGraphPersistenceTests` (+1: sibling-row round-trip for the new
`AutoregulatedSetCount`/`DeloadPositionOverride` fields, now 9 total).
`StrengthProgressionEngineTests`/`StrengthMaterializerTests` (renamed
from their Stage 4A `Hypertrophy*` names, contents unchanged).

### 10. Simulator

Rebuilt and relaunched on an iPhone 17 (iOS 26.5) simulator after the
schema change (`ProgramDefinition.powerliftingConfiguration` and
`PrescriptionTemplate`'s new fields). App launched and stayed running
(no crash); Today renders identically to every prior pass ("No sessions
today" — Stage 4B added no seeded `ProgramInstance` content and touched
no UI/ViewModel code, exactly Stage 4A's §9 precedent repeated).

### 11. What Stage 4B does not claim

- A complete, realistic per-day exercise catalog for Family B's full
  10-slot layout or Family C's full day-by-day content beyond the
  explicitly cited day names (§5's generator scope note).
- Family C's non-deload rep-per-week schedule — undocumented in the
  surviving source material; a flagged placeholder is used.
- Either family's deload set count — undocumented for both families;
  Family A's confirmed value (2) is carried forward as a default,
  flagged as unconfirmed.
- Materialization of weeks 1-3, a stored typed `Recommendation`, or any
  UI surfacing — identical, still-standing scope boundaries from Stage
  4A §10.
- SteadyState, Interval, FunctionalFitness, or ConcurrentScheduler
  (Stages 4C-4F) — not started.

### 12. Commit

See the final commit hash reported alongside this document. Local and
remote verified to match; working tree clean apart from local Xcode user
data.
