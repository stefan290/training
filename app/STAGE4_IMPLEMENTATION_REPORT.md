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

## Stage 4D: IntervalProgrammingSystem

One objective: `IntervalProgrammingSystem`, generic across Running,
Cycling, Rowing and SkiErg — no per-modality engine. Baseline: commit
`6101da5` (Stage 4C, approved), 192/192 tests passing.

### 1. What Stage 3C already built

Same pattern as Stage 4C's own discovery: most of the execution-layer
plumbing already existed. `IntervalPrescription` (`activityType`,
`intervalCount`, work duration/distance, work intensity, recovery
duration/distance, recovery intensity) and `IntervalResult`/
`IntervalRepResult` (per-interval-inspectable, never a session-average-
only value) were both built in Stage 3C and needed zero changes to
satisfy Stage 4D §4-6/§8/§12. `IntensityTarget` already had every case
Stage 3B's own validation pass found necessary (`.heartRatePercent` for
Helgerud's "90-95% HRmax," `.strokeRate` for rowing) — no new case was
added. What was missing, exactly mirroring Stage 4C's own finding, was
the **template-graph equivalent**: `IntervalPrescriptionTemplate`.

### 2. IntervalProgrammingSystem architecture

One `IntervalProgramGenerator`/`IntervalProgressionEngine` for every
modality (§1) — nothing branches on `ActivityType`. New
`IntervalPrescriptionTemplate` gives `WorkoutBlockTemplate` a third typed
child relationship, alongside `prescriptionTemplates` (strength) and
`steadyStatePrescriptionTemplate` (endurance, continuous) from Stage
4A/4C.

**Time-based vs. distance-based work** (§3, §9-10, §36): `IntervalWorkBasis`
(`.duration`/`.distance`) selects which of `weekOneWorkDurationSeconds`/
`weekOneWorkDistanceMeters` is set — never both, matching
`IntervalPrescription`'s own pre-existing doc comment exactly.
`IntervalProgramGeneratorTests` proves both bases produce a template with
the other dimension `nil`, not a dummy zero.

**Warm-up/cool-down use the existing ordered `WorkoutBlock` architecture**
(§7): `Session -> WarmUp Block -> Interval Block -> CoolDown Block`, the
warm-up/cool-down blocks typed `.steadyState` (reusing Stage 4C's type,
not a third "warm-up prescription" shape) at a low, unprogressed Zone 1
target.

**Progression strategies** (§13-14, §37): interval count, work duration,
work distance, intensity (heart-rate-zone stepping, reusing
`IntensityZoneProgression` unchanged from `SteadyStateProgressionRules`),
and recovery-duration reduction — each independently selectable, and
**ordered** via `IntervalProgressionRules.priority: [IntervalProgressionStep]`,
directly satisfying §14's explicit requirement ("do NOT automatically
increase count + duration + intensity and reduce recovery at the same
time"): an earlier step in the list fully consumes its own
`weeksToCeiling` worth of elapsed weeks before a later step starts
advancing at all. Proven with the kickoff's own example ("1. increase
interval count until ceiling, then 2. increase work duration") in
`IntervalProgressionEngineTests.testProgressionPriorityAdvancesEarlierStepFullyBeforeLaterStepStarts`,
precomputed by hand before being asserted.

**A design wrinkle found and fixed during this pass, before any test was
written against the wrong behavior:** reason codes were initially derived
from "has this dimension's cumulative progression count become nonzero,"
which incorrectly reported `.intervalCountIncrease` for every week after
a dimension had already hit its priority ceiling (the number itself was
unchanged, but the reason code still claimed it was increasing). Fixed by
comparing the *actual resolved value* for the current week against the
same computation one week earlier — the engine's `changed(current:previous:)`
helper — so a dimension that maxed out weeks ago correctly reports
`.noProgressionConfigured` ("no change this week"), not a false-positive
increase. Caught by `testProgressionPriorityAdvancesEarlierStepFullyBeforeLaterStepStarts`
itself on first run, fixed before any other test was written against the
same (wrong) assumption.

**Completion criteria and failure outcomes** (§16-17): `IntervalCompletionCriteria`
— configured completion-fraction thresholds (never inferred) plus an
explicitly-configured `reductionStrategy` (`.reduceIntensity` or
`.reduceIntervalCount`) for a severely failed session, so "which lever
gets pulled on a bad session" is always traceable to configuration, never
a runtime guess. `IntervalProgressionEngine.evaluateSessionOutcome` maps
a session's actual completed/total fraction (and worst RPE) to one of
`.progress`/`.hold`/`.repeatSession`/`.reduceIntensity`/`.reduceIntervalCount`/
`.calibrationRequired` — `totalCount == 0` (nothing logged at all) always
yields `.calibrationRequired`, never an invented fraction.

**Performance-driven vs. calendar-driven progression** (§15/§33):
`IntervalProgressionRules.requiresSuccessfulCompletionToProgress` — when
`false` (a fixed protocol like Helgerud's 4×4, which the source study
never varies), every week resolves as a pure function of week index
alone. When `true`, `IntervalMaterializer.materializeWeek` **throws**
`IntervalMaterializationError.previousOutcomeRequired` if asked to
resolve week N+1 without week N's actual outcome — a loud programmer
error, not a silent calendar-progression fallback, directly enforcing
"do not invent future outcomes."

**No trailing recovery/taper week is fabricated** (unlike Strength/
SteadyState) — no source material or kickoff instruction asks for an
interval-specific taper week, and CLAUDE.md rule 10 rules out inventing
one; a caller who wants one can still append a `TrainingWeek(isDeload:
true)` manually.

### 3. Verified source-derived fixture: Helgerud et al. 2007 4×4

`PROGRAMMING_SOURCES.md` §3 already documented (from Stage 3B) the exact
source figures — "4 intervals of 4 min running at 90-95% HRmax, each
followed by 3 min active recovery at 70% HRmax," verified via cross-
checked secondary sources quoting the abstract. This pass did not
re-attempt live retrieval (Stage 3B's own documented retrieval
limitations still stand) — it consumed the already-verified citation into
a real, tested fixture for the first time:
`IntervalProgressionEngineTests.testHelgerud4x4NeverProgressesAcrossAnyWeek`/
`.testHelgerud4x4StructureIsIdenticalAcrossRunningCyclingAndRowingWithModalityAppropriateIntensity`
(§19-20). The fixture's `priority: []` is itself the citation-honoring
detail — the source study fixes this protocol, and representing it as
progressing would misrepresent the source, exactly as
`ENDURANCE_PROGRAMMING_MODEL.md` §3.1 already required.

**Cross-modality proof (§20):** the identical `IntervalProgressionRules`
(4 intervals, 240s work, 180s recovery, never progressing) backs Running
(`.heartRatePercent(0.90...0.95)`, matching the source study's own unit),
Cycling (`.powerZone(.four)`) and Rowing (`.strokeRate(28...32)`) — only
the `IntensityTarget` idiom changes per modality, proving no per-modality
engine duplication is needed.

### 4. TrainingOS-designed rules

Every numeric default in `IntervalProgramGenerator` (10 min warm-up, 5 min
cool-down, 4×4min/180s-recovery duration-basis default, 5×1km/120s-
recovery distance-basis default, count-then-duration priority ordering)
is explicitly `ProgramProvenance.constructed`/TRAININGOS_DESIGNED, clearly
labeled in the generator's own doc comment, never presented as sourced —
distinct from the one verified Helgerud fixture above, which is
constructed directly in a test, not through this generator (the source
study's fixed protocol would be misrepresented by running it through a
generator whose whole purpose is producing *progressing* templates).

### 5. ActivityPerformanceProfile integration

Required no new production code, mirroring Stage 4C's own finding exactly
— `ActivityPerformanceProfile` already has no relationship to
`ProgramInstance`/`ProgramDefinition`. `IntervalSubstitutionAndHistoryTests`
proves: interval history survives replacing one `ProgramInstance` with
another; Rowing and Cycling interval histories never merge; distinct
performance contexts ("Threshold" vs. "VO2") stay separate; and —a
genuinely new proof this stage adds — **SteadyState history and Interval
history coexist for the same `ActivityType` without overwriting one
another**, since both hang off the same `ActivityPerformanceProfile` in
two independent arrays (`steadyStateResults`/`intervalResults`).

### 6. Substitution integration — one architectural correction

Stage 4C's `ActivitySelectionOverride` was keyed directly to
`SteadyStatePrescriptionTemplate`, the only endurance template type that
existed at the time. Stage 4D needed the same GOING FORWARD mechanism for
`IntervalPrescriptionTemplate` too. Rather than build a second, near-
duplicate `IntervalActivitySelectionOverride` entity (an "avoid duplicate
truth" violation this codebase has repeatedly flagged as a smell),
**`ActivitySelectionOverride` was re-keyed to the owning
`WorkoutBlockTemplate`** — the one object both endurance template types
already hang off of — via a new `ActivitySubstitutionTemplate` protocol
(`preferredActivityType`/`allowedActivityTypes`) both
`SteadyStatePrescriptionTemplate` and `IntervalPrescriptionTemplate`
conform to. Made before any Stage 4D generator/materializer code was
written against the old shape — the same Stage 4A/4B discipline of
correcting a schema mistake before it ships, not working around it. Two
existing Stage 4C test call sites were updated accordingly; both re-pass
unchanged in substance. `SubstituteActivityUseCase`'s `isValid`/
`substituteGoingForward`/`resolvedActivityType` became generic over
`ActivitySubstitutionTemplate`; `substituteThisSessionOnly` gained an
`IntervalPrescription` overload alongside the existing `SteadyStatePrescription`
one (their intensity fields differ in name —
`workIntensity`/`recoveryIntensity` vs. `primaryIntensity`/
`secondaryIntensity` — so one shared function would need awkward
branching; two small overloads sharing the same validation/translation
calls was the cleaner fit).

`IntervalPrescription` gained `substitutionUsed`/`substitutionReason`
fields, mirroring `SteadyStatePrescription`'s Stage 4C addition exactly —
THIS SESSION ONLY substitution's entire persisted footprint, no new
entity. `IntensityTranslation` (Stage 4C, unchanged) already covers
interval substitution correctly: a Bike watt target does not survive a
substitution to Row (§25/§39.33, proven directly by
`testBikeWattsAreNotCopiedIntoRowTarget`); a physiological target would
survive unchanged if one were used instead.

### 7. Recommendation/calibration behavior

No new recommendation vocabulary was needed — `IntervalReasonCode`
(new, this stage's engine-internal reason codes for count/duration/
distance/intensity/recovery changes and HOLD/REPEAT/REDUCE*/
CALIBRATION_REQUIRED) and the pre-existing `SubstitutionAwareRecommendation`/
`ProgressionReasonCode` (Stage 4C, unchanged) together cover everything
§18/§30 ask for — `ACTIVITY_HISTORY_USED` maps onto
`SubstitutionAwareRecommendation`'s existing exact-history path, reused
rather than duplicated.

### 8. Template/materializer changes

New: `IntervalPrescriptionTemplate` (flattened tagged-union storage,
including a flattened `priority: [IntervalProgressionStep]` — stored as
three parallel primitive arrays, not an array of the struct directly,
since no existing test in this codebase proves an array of a multi-field
struct round-trips safely; see §9). `IntervalProgramGenerator`,
`IntervalMaterializer` (new Application/UseCases). `WorkoutBlockTemplate`
gained `intervalPrescriptionTemplate` (cascade) and
`activitySelectionOverrides` (moved here from
`SteadyStatePrescriptionTemplate`, nullify). `ProgramDefinition` gained
`intervalConfiguration`.

`IntervalMaterializer.materializeWeek` resolves one week at a time,
always — unlike `SteadyStateMaterializer` (which resolves every week
immediately since none of its dimensions depend on a live result), an
interval template's rules *may* set
`requiresSuccessfulCompletionToProgress`, so this materializer can't
assume otherwise. A caller whose rules never set that flag can still call
it once per week in a simple loop with `previousOutcome: nil` throughout,
producing an identical result to materializing every week up front.

### 9. Persistence changes

New `@Model` type: `IntervalPrescriptionTemplate` (registered in
`PersistenceController.schema`). New fields: `IntervalPrescription.substitutionUsed`/
`.substitutionReason`, `ProgramDefinition.intervalConfiguration`,
`WorkoutBlockTemplate.intervalPrescriptionTemplate`/
`.activitySelectionOverrides`. Changed: `ActivitySelectionOverride.templateSteadyState`
-> `.templateBlock: WorkoutBlockTemplate?` (§6's correction).
`SteadyStatePersistenceTests`'s existing round-trip test for
`ActivitySelectionOverride` was updated to construct a `WorkoutBlockTemplate`
and assert through it — documented here as the "exact approved
architectural reason" §41 requires, not a silent behavior change: the
override's semantics are identical, only its template-object key moved.
Every new persisted shape got its own round-trip test, including the
critical sibling-row-heterogeneity diagnostic for the new flattened
`priority` array storage
(`IntervalPersistenceTests.testTwoSiblingRowsWithDifferentPriorityListsBothSurviveRoundTrip`)
and a repeat of the nullify-not-crash proof at `ActivitySelectionOverride`'s
new key (`testDeletingWorkoutBlockTemplateNullifiesRatherThanCrashingActivitySelectionOverride`).
See `DELETE_RULE_MATRIX.md`'s "Stage 4D additions" section for full
delete-rule reasoning.

### 10. Test count and result

236 tests total (192 Stage 4A/4B/4C baseline + 44 new Stage 4D tests). All
236 pass on the real Xcode toolchain, including all 192 pre-existing
tests unchanged — none weakened; the 2 call-site updates in
`SteadyStatePersistenceTests`/`SubstitutionTests` required by §6's
correction are documented above, not silent.

New Stage 4D test files: `IntervalPersistenceTests` (9, including the
priority-array sibling-row diagnostic and two nullify/cascade proofs at
the corrected `ActivitySelectionOverride` key), `IntervalProgressionEngineTests`
(18, covering every progression dimension, explicit priority ordering,
completion-criteria thresholds, failure outcomes, determinism, and the
Helgerud fixture + cross-modality proof), `IntervalProgramGeneratorTests`
(7, both work bases, warm-up/cool-down structure, no fabricated recovery
week, materializer progression, and the performance-gate-throws proof),
`IntervalSubstitutionAndHistoryTests` (10, today-only/going-forward
interval substitution, running-rejects-cycling, no-blind-watt-transfer,
history survival/coexistence, and the SteadyState+Interval `TrainingPlan`
composition proof).

### 11. Simulator

Rebuilt and relaunched on an iPhone 17 (iOS 26.5) simulator after the
schema change (1 new `@Model` type, several new/changed fields). App
launched and stayed running — no `ModelContainer` crash; Today renders
identically to every prior pass ("No sessions today" — Stage 4D added no
seeded content and no UI/ViewModel code, matching every prior stage's
identical precedent).

### 12. What Stage 4D does not claim

- A curated interval built-in library (no `V1_PROGRAM_LIBRARY.md` entry
  names one, exactly as Stage 4C's steady-state generator also found).
- A full `RunningProgrammingSystem`/Couch-to-5K/5K/10K/marathon plan —
  explicitly deferred (§23/§45); only the composability of SteadyState +
  Interval phases into one `TrainingPlan` (no new entity type) is proven.
- Functional Fitness (AMRAP/EMOM/WOD generator, benchmark catalog) —
  explicitly Stage 4E scope, not started (§46).
- A curated `ExerciseRelationship`-style benchmark curation for repeated
  interval tests (§29) — deferred, matching Stage 4C's identical
  deferral for exercises.
- An interval-specific taper/recovery week — deliberately not fabricated
  (§2 above).

### 13. Architectural judgment: no flaw found, one correction made

Per the kickoff's explicit instruction to stop and explain before working
around any exposed flaw: Stage 4D required one genuine, well-justified
correction (§6 — re-keying `ActivitySelectionOverride` to
`WorkoutBlockTemplate`), made proactively before any code depended on the
old shape, not a workaround for a flaw discovered late. The template
graph and materializer pattern themselves needed no conceptual change —
`IntervalPrescriptionTemplate`/`IntervalMaterializer` are structurally
identical to their SteadyState siblings, differing only in which rule
vocabulary and which per-week resolution functions they call.

### 14. Commit

See the final commit hash reported alongside this document. Local and
remote verified to match; working tree clean apart from local Xcode user
data.

## Stage 4C: SteadyStateProgrammingSystem + Substitution Foundation

Two objectives, per the kickoff: (1) `SteadyStateProgrammingSystem`, and
(2) the substitution architecture — explicitly "a domain/programming
requirement, not merely a future UI feature." Baseline: commit `729faa7`
(Stage 4B, approved), 144/144 tests passing.

### 1. Architecture review before adding anything (§56-58)

Read the full existing template graph, `ExerciseSlot`, `ProgramInstance`,
`Session`/`WorkoutBlock`, and every performance-profile entity before
writing a line of new schema. Found:

- Most of Part A's execution-layer plumbing already exists from Stage 3C
  (`SteadyStatePrescription`/`SteadyStateResult`, `ActivityType`,
  `ActivityPerformanceProfile`, the persistence-safe `IntensityTarget`)
  and needed no changes — only the **template-graph equivalent** was
  missing, exactly as `WorkoutBlockTemplate`'s own Stage 4A doc comment
  said it would be ("steady-state/interval/functional-fitness template
  equivalents are a Stage 4C/D/E extension, not built here").
- Functional Fitness scaling (§38-39) is already fully solved by
  `FunctionalFitnessPerformedMovement.prescribedMovement`/`.performedExercise`
  — no new code needed, only a confirming test.
- `ProgressionReasonCode.calibrationRequired`/`.substitutionEstimate` were
  declared in Stage 1-2 as "intentionally unreachable... until a later
  pass" — this is that pass; reused rather than duplicated under new
  names.
- `ExerciseSlot.allowedTargets` had no way to be checked against a
  candidate `Exercise` at all — `Exercise` had no target field. Closed by
  adding `Exercise.primaryTargets: [MuscleGroup]`, additive, defaulted to
  `[]` for every pre-existing exercise.

No architectural flaw was found in the generic template/materialization
model itself — see §8 below for the explicit statement Stage 4C's own
discipline requires.

### 2. SteadyStateProgrammingSystem architecture

One `SteadyStateProgramGenerator`/`SteadyStateProgressionEngine` for
every aerobic modality (§1) — nothing branches on `ActivityType`.
`SteadyStatePrescriptionTemplate` (new, template-graph analogue of
`SteadyStatePrescription`) attaches to `WorkoutBlockTemplate` via a new
sibling relationship (`steadyStatePrescriptionTemplate`), exactly
mirroring how `WorkoutBlock` already carries one typed relationship per
modality. `ProgramDefinition` gained `steadyStateConfiguration:
SteadyStateProgramConfiguration?`, the sibling of
`hypertrophyConfiguration`/`powerliftingConfiguration`.

**Supported modalities:** Running, Cycling, Rowing, SkiErg (`ActivityType`,
unchanged from Stage 3C) — proven via
`SteadyStateProgramGeneratorTests.testGeneratorProducesAZone2FortyFiveMinuteTemplateForEachRequiredModality`,
which builds all four through the identical generator call and asserts
identical resolved output. Adding a fifth modality is a new
`ActivityType` case, nothing more — no engine/generator change.

**Progression strategies implemented** (§7, `SteadyStateProgressionEngine`):
duration, distance, intensity-zone (heart-rate-zone stepping only — see
§4 below for why), and recovery-week reduction — each independently
selectable via `SteadyStateProgressionDimension`, never assumed
("do not assume duration always progresses" is directly tested:
`testDurationDoesNotProgressWhenTheChosenDimensionIsDistance`).
**Frequency progression** is modeled at the correct architecture level
(§7-8): a new `TemplateSession.activeFromWeek: Int = 0` field (shared,
generic — not steady-state-specific), consulted by the materializer when
building a given week (`orderedTemplateSessions.filter { $0.activeFromWeek
<= weekIndex }`), never by `BlockProgressionEngine`. Recovery-week
reduction reuses `TrainingWeek.isDeload` exactly as Family A/B/C already
do — no new "recovery" flag.

**Frequency progression is deliberately not baked into the generator's
own built-in numbers** — no source material specifies *when* a program
should add a session, and inventing a specific week would be exactly the
"ambiguous training rule" CLAUDE.md rule 10 rules out. The capability is
proven directly at the engine/materializer level instead
(`SteadyStateProgramGeneratorTests.testTemplateSessionActiveFromWeekControlsWhichWeeksAMaterializedSessionAppearsIn`),
not fabricated into a numbered built-in.

### 3. Source-derived vs. TrainingOS-designed (§10)

Every numeric default in `SteadyStateProgramGenerator` (45 min base
duration, +5 min/week, 8 km base distance, +1 km/week, Zone 2 -> Zone 4
stepping, 0.7x recovery-week fractions) is explicitly
`ProgramProvenance.constructed` and documented in the generator's own doc
comment as TRAININGOS_DESIGNED — never presented as sourced. Stage 3B
already found real retrieval limitations verifying British Cycling/NHS/
research-literature protocols; this pass did not re-attempt live
verification, per the kickoff's own instruction to implement the generic
capability with clearly-labeled TrainingOS-designed test configurations
rather than convert an unverified search snippet into production
methodology. No V1_PROGRAM_LIBRARY.md entry names a curated steady-state
built-in, so none was fabricated here — a reasonable follow-up once real
program content exists, not attempted with false confidence.

### 4. Persistence-safety decisions (§4, extending Stage 4A/4B's discipline)

- `SteadyStatePrescriptionTemplate.primaryIntensity`/`.secondaryIntensity`
  are stored as **direct top-level `IntensityTarget?` properties** — the
  one shape Stage 3C/4A already proved safe (`SteadyStatePrescription`
  itself, `TemplateGraphPersistenceTests`'s own diagnostics). Re-confirmed
  directly for the new type, not assumed by analogy:
  `SteadyStatePersistenceTests.testTwoSiblingRowsWithDifferentProgressionDimensionsBothSurviveRoundTrip`
  round-trips two sibling rows with heterogeneous rule shapes.
- Duration/distance progression schedules are plain `[Int]`/`[Double]`
  arrays — already-proven-safe (arrays of primitives, same shape as
  `RMBasedLoad.laterWeekMultipliers`).
- **Intensity progression is deliberately restricted to heart-rate-zone
  stepping**, expressed as three flat scalar fields
  (`intensityZoneProgressionStartZone/StepPerWeek/MaxZone`), not a
  per-week `[IntensityTarget]` array. No existing test in this codebase
  proves an array of an enum-with-payload round-trips safely — rather
  than assume it does (the exact mistake Stage 4A's Bug 2/3 warned
  against repeating), this pass avoided the untested shape entirely.
  Every other `IntensityTarget` case holds one static value for the whole
  block when intensity isn't the chosen progression dimension.

### 5. ActivityPerformanceProfile integration (§12-14)

Required essentially no new production code — `ActivityPerformanceProfile`
(Stage 3C) already has no relationship to `ProgramInstance`/
`ProgramDefinition` at all, so "survives a program change" was already
structurally true; this pass's job was proving it end-to-end against the
*new* generator/materializer, not building new plumbing.
`ActivityPerformanceProfileIntegrationTests` proves: Cycling history
survives replacing one `ProgramInstance` with another built from a fresh
`ProgramDefinition`; Rowing and Cycling never merge; a named
`performanceContext` ("5K") stays distinct from the general activity
profile; `BenchmarkPerformanceProfile` remains a structurally separate
entity from `ActivityPerformanceProfile`.

### 6. Substitution architecture — the five-stage pipeline

Full contract in the new `SUBSTITUTION_MODEL.md`; summary here.

```
Template Slot -> ProgramInstance Selection -> Materialized Prescription -> Actual Performance -> PerformanceProfile
```

**THIS SESSION ONLY** (§18) needs no new persisted type at all — it's a
direct edit of an already-materialized `ExercisePrescription.exercise`/
`SteadyStatePrescription.activityType` (plus new `.substitutionUsed`/
`.substitutionReason` fields on the latter, mirroring the former's
pre-existing ones), exactly the shape
`FunctionalFitnessPerformedMovement.performedExercise` already
established. **GOING FORWARD** (§18) is a new `ProgramInstance`-scoped
entity per domain — `SlotSelectionOverride` (strength, points at an
`ExerciseSlot`) and `ActivitySelectionOverride` (endurance, points at a
`SteadyStatePrescriptionTemplate`) — deliberately two small single-purpose
types rather than the kickoff's own suggested one-entity-with-a-scope-field
sketch, which would have needed nullable dual-purpose columns (§57's
"nullable mega-entity" smell) since the two scopes reference genuinely
different aggregate roots. `SUBSTITUTION_MODEL.md` §3 explains this
deviation and why the kickoff's explicit "requirements over the suggested
type" license was used.

`StrengthMaterializer`/`SteadyStateMaterializer` were updated to resolve
through `SubstituteExerciseUseCase.resolvedExercise(for:in:)`/
`SubstituteActivityUseCase.resolvedActivityType(for:in:)` instead of
reading `slot.resolvedExercise`/`template.preferredActivityType`
directly — this is the entire GOING FORWARD hook (§30).

**Substitution validity** (§27): `SubstitutionValidator.isValid` checks
only `ExerciseSlot.allowedExercises`/`.allowedTargets` (via the new
`Exercise.primaryTargets` field), deterministic and explainable, never a
name/string heuristic. `SubstituteActivityUseCase.isValid` checks
`SteadyStatePrescriptionTemplate.allowedActivityTypes` the same way — a
running-specific template sets this to exactly `[.running]`, never empty.

**Exercise relationships** (§26): `ExerciseRelationship` (new, curated —
only `.directSubstitute`/`.similarMovement`) plus
`ExerciseRelationshipResolver`, which merges curated rows with
relationships *derivable* from `Exercise`'s own fields
(`.sameMovementPattern`/`.samePrimaryTarget`/`.sameEquipmentFamily`) —
the latter three are never persisted as rows, since doing so would be the
"avoid duplicate truth" smell applied to already-computable facts.

**Recommendation after substitution** (§25/§29/§44):
`SubstitutionAwareRecommendation` escalates exact-own-history (existing
`.percentageOfEstimate`) -> related-exercise estimate at a flat,
explicitly-labeled 0.5 confidence discount (`.substitutionEstimate`) ->
`.calibrationRequired`, never inventing a load. Reuses
`ProgressionReasonCode` rather than a new parallel vocabulary — see
`SUBSTITUTION_MODEL.md` §5 for why `SubstitutionReason` (why the user
substituted) and `ProgressionReasonCode` (how the number was derived) are
kept as two separate, purpose-fit vocabularies rather than merged into
one.

**Endurance substitution** (§34-37): `SubstituteActivityUseCase` mirrors
`SubstituteExerciseUseCase` exactly. `IntensityTranslation` (new) is the
§37 requirement made concrete: a physiological target (HR zone/percent,
RPE) survives an activity substitution unchanged; an equipment-specific
target (pace, power, cadence, stroke rate) drops to `nil` — proven
directly with the exact scenario the kickoff names,
`testEquipmentSpecificIntensityDoesNotTransferAcrossActivitySubstitution`
(a Bike power range does not survive a substitution to Rowing).

**Historical stability** (§30/§42): every substitution test that adds a
GOING FORWARD override first materializes and marks a Session
`.completed`, *then* substitutes, then asserts the already-materialized
row is unchanged — not merely "future sessions get the new value," but
explicitly "past sessions provably don't."

### 7. What Stage 4C does not claim

- A curated steady-state built-in library (no V1_PROGRAM_LIBRARY.md entry
  names one) — the generic capability and all 4 required modalities are
  proven; a specific named product configuration is a content task.
- `THIS_PHASE` substitution scope — designed for extensibility, not built.
- A full substitution UI — explicitly Stage 5+ scope.
- A biomechanical intensity-translation or related-exercise-estimate
  model — both are deliberately simple, clearly-labeled placeholders (a
  flat confidence discount; drop-to-nil for equipment-specific targets),
  not physiology models CLAUDE.md rule 10 would rule out inventing.
- SteadyState materialization of a live per-week rating — moot here,
  since every steady-state dimension this pass implements is a
  deterministic function of week index alone (§8 elaborates).

### 8. Architectural judgment: no flaw found in the template/materialization model

Per the kickoff's explicit instruction to stop and explain before working
around any exposed flaw: Stage 4C required one genuinely new structural
element — `WorkoutBlockTemplate` gaining a second typed child
relationship (`steadyStatePrescriptionTemplate`, alongside
`prescriptionTemplates`) — but this is not a redesign, it's the same
"one typed relationship per modality" pattern `WorkoutBlock` itself
already uses on the execution side, applied one layer up as Stage 4A's
own doc comment always said it eventually would be. The materializer
pattern (template -> per-week resolution -> dated rows) needed no
conceptual change at all; `SteadyStateMaterializer` is structurally
identical to `StrengthMaterializer`, just able to resolve every week
immediately because none of its dimensions need a live per-week rating —
a genuine, notable difference from strength's necessarily-partial scope,
not an architectural gap.

The substitution requirement (Part B) needed one new additive concept —
a `ProgramInstance`-scoped override, resolved at materialization time —
which slots into the *existing* materializer call site
(`slotContext`-style resolution was already the established pattern for
"runtime input the template can't know"; substitution is simply one more
such input) without requiring any change to the template graph itself.

### 9. Persistence/schema changes

New `@Model` types: `SteadyStatePrescriptionTemplate`,
`ExerciseRelationship`, `SlotSelectionOverride`,
`ActivitySelectionOverride` (all registered in
`PersistenceController.schema`). New fields: `Exercise.primaryTargets`,
`ExercisePrescription.substitutionReason`,
`SteadyStatePrescription.substitutionUsed`/`.substitutionReason`,
`TemplateSession.activeFromWeek`, `WorkoutBlockTemplate.steadyStatePrescriptionTemplate`,
`ProgramDefinition.steadyStateConfiguration`,
`ProgramInstance.slotSelectionOverrides`/`.activitySelectionOverrides`,
`ExerciseSlot.slotSelectionOverrides` (required inverse). Every addition
is additive with a safe default — no existing row's meaning changes. See
`DELETE_RULE_MATRIX.md`'s new "Stage 4C additions" section for the full
delete-rule reasoning.

### 10. Test count and result

192 tests total (144 Stage 4A/4B baseline + 48 new Stage 4C tests). All
192 pass on the real Xcode toolchain, including all 144 pre-existing
tests unchanged — none weakened.

New Stage 4C test files: `SteadyStatePersistenceTests` (9, including the
critical sibling-row-heterogeneity diagnostic and two nullify/cascade
delete-rule proofs), `SteadyStateProgressionEngineTests` (14, covering
every progression dimension, recovery reduction, determinism, and
`IntensityTranslation`), `SteadyStateProgramGeneratorTests` (8, four
modalities + frequency progression + full-suite materialization),
`ActivityPerformanceProfileIntegrationTests` (4), `SubstitutionTests`
(13, strength today-only/going-forward/historical-stability/performance-
profile-separation, slot validity, endurance substitution, Functional
Fitness compatibility).

### 11. Simulator

Rebuilt and relaunched on an iPhone 17 (iOS 26.5) simulator after the
schema change (4 new `@Model` types, multiple new fields on existing
types). App launched and stayed running — no `ModelContainer` crash;
Today renders identically to every prior pass ("No sessions today" —
Stage 4C added no seeded content and no UI/ViewModel code, matching Stage
4A §9/4B §10's identical precedent).

### 12. Commit

See the final commit hash reported alongside this document. Local and
remote verified to match; working tree clean apart from local Xcode user
data.

## Stage 4E: FunctionalFitnessProgrammingSystem

One deterministic `FunctionalFitnessProgrammingSystem` — explicitly not a
random WOD generator, built on the stimulus-first pipeline
(`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md`) rather than double
progression. Baseline: commit `c2efa33` (Stage 4D, approved), 236/236
tests passing. Full contract in the new `FUNCTIONAL_FITNESS_ENGINE.md`;
this section summarizes what changed and why.

### 1. What Stage 3C already built

The largest share of this stage's execution-layer plumbing already
existed: `FunctionalFitnessPrescription`/`FunctionalFitnessMovement`
(Stage 3C's own "ResolvedMovement" concept), `FunctionalFitnessResult`/
`FunctionalFitnessPerformedMovement` (prescribed-vs-performed already
separated), `BenchmarkDefinition`/`BenchmarkPerformanceProfile`,
`Stimulus`/`WorkoutFormat`/`ScoreType`/`ScoreDirection`/`ScoreValue`,
`MovementFunction`/`FunctionalModality`, `TrainingStressProfile`, and the
`ProgrammingDecisionEngine` protocol scaffold (with `VarianceExposureRecord`/
`VarianceConstraints`/`ProgrammingDecisionInput`/`ProgrammingDecisionOutput`
already defined, "no concrete conformer exists in this pass"). What was
missing, exactly mirroring every prior Stage 4 system's own finding, was
the **template-graph equivalent** and the **concrete decision engine**.

**A genuinely useful finding from this review:** `Stimulus`/`WorkoutFormat`
have been round-tripping through SwiftData directly (no flattening) since
Stage 3C — `FunctionalFitnessPrescription.stimulus`/`.format` and
`BenchmarkDefinition.stimulus`/`.format` already store them this way,
exercised by pre-existing passing tests. This retroactively confirms an
array of a multi-field struct (`Stimulus.movementModalityMix: [ModalityCount]`)
*can* round-trip safely in this codebase — evidence Stage 4D's own
`IntervalProgressionStep` flattening caution didn't have available at the
time. `FunctionalFitnessPrescriptionTemplate` stores `stimulus`/`format`
directly on this existing evidence, not a fresh untested assumption.

### 2. FunctionalFitnessProgrammingSystem architecture

`FunctionalFitnessPrescriptionTemplate` (new) is `WorkoutBlockTemplate`'s
fourth typed child, alongside strength/steady-state/interval. The five-
stage pipeline (§2 of the kickoff) splits across generator and
materializer exactly like Stage 4D split calendar-driven vs. performance-
gated progression:

- **Stage A (target stimulus)** and **Stage B (format)** are supplied
  directly by the caller's `FunctionalFitnessProgramConfiguration` — a
  real "given a training goal, choose a stimulus" decision is content
  authoring, out of this pass's scope (§34).
- **Stage C (movement slots)** runs at generation time:
  `FunctionalFitnessProgramGenerator` derives one
  `FunctionalFitnessMovementSlotTemplate` per `ModalityCount` entry in
  the target stimulus's `movementModalityMix` (a triplet's 3 counts
  become 3 slots), each constrained by `allowedModalities`/
  `allowedMovementFunctions` — never a hard-coded exercise list.
- **Stage D (concrete exercise selection)** and **Stage E (stimulus
  validation)** run at `FunctionalFitnessMaterializer` time, not
  generation time — they depend on live exposure history and available
  candidates the generator can't know in advance, mirroring exactly how
  Stage 4A deferred strength's concrete-exercise resolution to
  materialization.

**Movement slots reuse `ExerciseSlot` directly, not a parallel FF-specific
slot type.** `ExerciseSlot` gained `allowedMovementFunctions: [MovementFunction]`/
`allowedModalities: [FunctionalModality]` (Stage 4E addition, alongside
the existing `allowedTargets: [MuscleGroup]`) and a second owning parent
(`FunctionalFitnessMovementSlotTemplate`, mirroring `PrescriptionTemplate`'s
existing ownership shape) — meaning Functional Fitness movement slots
inherit `SubstitutionValidator`, `SlotSelectionOverride`, and
`SubstituteExerciseUseCase` for free, rather than a second, parallel
substitution system. `SubstitutionValidator.isValid` was generalized to
check all three dimensions (AND across dimensions, OR within one
dimension's array; `allowedExercises`, when set, still short-circuits
everything else unchanged since Stage 4C) — every pre-existing strength-
slot test still passes unchanged, since the two new dimensions default to
empty.

**`Exercise` gained typed movement metadata** — `movementFunctions:
[MovementFunction]`, `functionalModality: FunctionalModality?` — closing
the same "canonical Exercise metadata, never parsed exercise names" gap
`primaryTargets` closed for strength in Stage 4C. `MovementFunction`
itself gained 3 cases (`.carry`, `.locomotion`, `.trunk`) the kickoff's
§7 explicitly named but the original 7-case enum had no way to represent
— purely additive, no persistence risk.

**Format vs. stimulus independence (§6)** is enforced by construction,
not just convention: `FunctionalFitnessPrescriptionTemplate` stores both
as two independent fields with no subtyping relationship, proven directly
(`testSameFormatWithDifferentStimuliAreNotConflated`) — two AMRAPs with
identical format but opposite intensity/loading are never treated as "the
same kind of workout."

### 3. ProgrammingDecisionEngine — the first concrete conformer

**Stage 4E correction:** `ProgrammingDecisionOutput.reasonCode` was typed
`ProgressionReasonCode` (a reasonable Stage 3C placeholder — "no concrete
conformer exists in this pass"). `ProgressionReasonCode` is strength's own
"why did the load change" vocabulary; reusing it for "why did the next
stimulus balance duration vs. modality" would be the exact wrong-
vocabulary-reused-for-a-different-concept mismatch Stage 4C's
`SubstitutionReason`/`ProgressionReasonCode` split already corrected once.
Retyped to the new `FunctionalFitnessReasonCode` — painless, since nothing
produced or consumed a `ProgrammingDecisionOutput` before this pass.

`FunctionalFitnessDecisionEngine` (new, `Engines/`) implements the
protocol: checks exactly 4 dimensions (duration domain, loading,
modality mix, movement function) in a **fixed, documented priority
order**, adjusting only the first one it finds violated per call —
directly mirroring Stage 4D's progression-priority discipline ("do not
change several things at once"). Each violated dimension rotates to a
deterministic alternative (duration/loading: the next value in the
enum's own declared order; modality/movement-function: the least-exposed
candidate across all of `exposureHistory`, added to the target) — never
a random pick among candidates (§29). `VarianceConstraints` gained 2
fields (`avoidRepeatingDurationDomainWithinSessions`/
`avoidRepeatingLoadingWithinSessions`), additive alongside the original 2.

`FunctionalFitnessExposureHistoryBuilder` (new, `Application/UseCases/`,
touches `@Model` types so it's not part of the pure `Engines/` layer)
builds `[VarianceExposureRecord]` from a `ProgramInstance`'s actual
history: only a `Session` with `status == .completed` *and* a
`WorkoutBlock` carrying both a real `FunctionalFitnessResult` and its
originating `FunctionalFitnessPrescription` contributes — a scheduled-
but-skipped Session contributes nothing, directly satisfying §27/§50.36.

### 4. Scoring architecture

No new scoring vocabulary — `ScoreType`/`ScoreDirection`/`ScoreValue`
(Stage 3C) already cover every case §12 requires, always set explicitly
at construction (no default, no inference from format name).
`RecordFunctionalFitnessResultUseCase` (new) is the sole path from a
`FunctionalFitnessResult` to a `PersonalRecord` — `comparableValue(for:)`
turns a structured `ScoreValue` into one comparable `Double` purely for
`ScoringEngine`'s existing higher/lower-is-better comparison (never for
display; the structured value is what's actually stored), with a
TRAININGOS_DESIGNED `.roundsAndReps` proxy (`rounds * 100_000 +
partialReps` — more rounds always beats fewer, more partial reps wins
within the same round count). `mapToScoringDirection(_:)` bridges the
Stage 3C `ScoreDirection` (2 cases) onto the pre-existing `ScoringDirection`
(4 cases) `ScoringEngine`/`PersonalRecord` already use.

### 5. Benchmark architecture and the Fran consolidation (§22/§55)

**Resolved before any other Stage 4E work**, per the kickoff's own
instruction. Two parallel Fran representations existed:

1. **Legacy** (Stage 1-2): "Fran" modelled as a canonical `Exercise`
   (`ExerciseCatalog.fran`), scored through `RecordWorkoutResultUseCase`'s
   `benchmarkExercise`/`prCandidateValue` parameters, folding a PR into
   `ExercisePerformanceProfile` — the exact same entity type Bench Press's
   PRs live in.
2. **Canonical** (Stage 3C): `BenchmarkDefinition`/`BenchmarkPerformanceProfile`
   plus the typed `FunctionalFitnessPrescription`/`FunctionalFitnessResult`
   path.

**The canonical (2) representation was kept; (1) was removed, not left
dead.** `ExerciseCatalog.fran` is gone. `RecordWorkoutResultUseCase` lost
its `benchmarkExercise`/`prCandidateValue` parameters entirely (its only
real caller was the Fran scenario, migrated in the same pass — the 5
other call sites already always passed `nil` for both). A new
`RecordFunctionalFitnessResultUseCase` is the sole path to a benchmark
`PersonalRecord` going forward. `SeedScenarios.forTimeBenchmarkSession`
now builds Fran through `FunctionalFitnessPrescription`/
`FunctionalFitnessMovement`/`FunctionalFitnessResult`/`BenchmarkDefinition`
end to end. Three existing tests that asserted against the legacy path
were migrated to the canonical one, proving the *same* delete-rule
invariants (a PersonalRecord survives the deletion of the result that
produced it; explicit PersonalRecord deletion touches nothing else) at
their new, correct location:
`DeleteRuleMatrixTests.testDeletingWorkoutResultPreservesItsPersonalRecord`
-> `.testDeletingFunctionalFitnessResultPreservesItsPersonalRecord`,
`.testExplicitPersonalRecordDeletionOnlyRemovesThatRecord` (same name,
migrated body), and `DomainModelScenarioTests.testForTimeBenchmarkRecordsRxTimeAndCreatesAPersonalRecord`
(same name, migrated body) — documented here as the exact approved
architectural reason §53 requires, not a silent behavior change.
`FunctionalFitnessSubstitutionAndBenchmarkTests.testExactlyOneCanonicalFranRepresentationExistsAfterSeeding`
proves the migration directly: no `Exercise` named "Fran" exists in the
seeded catalog, and exactly one `BenchmarkDefinition` with
`canonicalID == "benchmark.fran"` does.

`BenchmarkDefinition`'s own shape (stable `canonicalID`, `stimulus`,
`format`, `scoreType`/`scoreDirection`) already satisfied §21's
requirements unchanged; no versioning field was added since nothing in
this pass changes an existing benchmark's prescription in place (§43's
"new version where required" principle extends to benchmarks too, just
not yet exercised).

### 6. Scaling and substitution

Functional Fitness scaling (Toes-to-Bar prescribed, Knee Raises
performed) was already fully correct since Stage 3C
(`FunctionalFitnessPerformedMovement.prescribedMovement`/`.performedExercise`)
— re-confirmed with a Stage-4E-scoped test, no new code. GOING FORWARD
movement-slot substitution is new *behavior*, though zero new
*mechanism* — it's `SubstituteExerciseUseCase`/`SlotSelectionOverride`
applied to an `ExerciseSlot` now reachable through a
`FunctionalFitnessMovementSlotTemplate` parent, proven end-to-end
(`testGoingForwardMovementSlotSubstitutionNeverMutatesProgramDefinitionAndHistoricalSessionStaysStable`):
the template graph is never mutated, a completed historical Session is
unaffected, and the next materialized week picks up the substitution.

### 7. PerformanceProfile integration

No fourth profile type — Functional Fitness uses `ExercisePerformanceProfile`
(a specific movement performed, e.g. Thrusters logged with real load,
context-scoped by whichever block it came from), `ActivityPerformanceProfile`
(monostructural activity history — Stage 4C/4D's system, untouched),
and `BenchmarkPerformanceProfile` (repeatable benchmarks) — exactly as
§32 specifies, satisfied entirely by pre-existing Stage 3C/4C
infrastructure.

### 8. TrainingStressProfile

`FunctionalFitnessStressProfileMapper` (new, `Engines/`, pure) maps a
resolved `Stimulus` to a `TrainingStressProfile` — coarse, deterministic,
explicitly documented as *not* a physiological formula (mirroring
`TrainingStressProfile`'s own doc comment). `lowerBodyLoad`/`upperBodyLoad`
derive from which movement functions are present (squat/hinge -> lower,
press/pull -> upper), scaled by the stimulus's own `loading` classification;
`impactLoading` is set only when a locomotion/monostructural function is
present (a coarse, explicitly-labeled simplification); `metabolicDemand`/
`recoveryDemand` mirror `intensity`/`systemicDemand` respectively, since
this pass has no independent signal to distinguish them.
`durationClassification` passes `targetDurationDomain` straight through
(no re-classification — `Stimulus` and `TrainingStressProfile` already
share the exact same `DurationDomain` type).

### 9. Source-derived vs. TrainingOS-designed rules

No new source-derived numeric fixture was added this stage — Stage 3B's
own CrossFit-sourced material (`PROGRAMMING_SOURCES.md` §4, the "goal/
stimulus → program → analyze" sequence) already grounds the five-stage
pipeline's *shape*, cited unchanged. Every number this stage introduces
is explicitly TRAININGOS_DESIGNED and labeled as such:
`FunctionalFitnessStimulusValidator`'s short(<5min)/medium(5-15min)/
long(>15min) duration-domain thresholds (carried from
`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §1.1's own Stage 3B sketch,
not invented fresh), the `.roundsAndReps` PR-comparison proxy, and the
strength+metcon composition's fixed 5×5 placeholder numbers. No
proprietary CrossFit workout catalog was imported (§45) — the curated
movement catalog (§35, `ExerciseCatalog`'s Stage 4E additions) is a small,
generic, well-known-movement set, and every generated program is an
original configuration of the deterministic system, never a copied named
workout beyond Fran itself (already a widely-known, non-proprietary
reference benchmark, exactly as Stage 3C originally used it).

### 10. Persistence/schema changes

New `@Model` types: `FunctionalFitnessPrescriptionTemplate`,
`FunctionalFitnessMovementSlotTemplate` (both registered in
`PersistenceController.schema`). New fields: `Exercise.movementFunctions`/
`.functionalModality`, `ExerciseSlot.allowedMovementFunctions`/
`.allowedModalities`/`.sortIndex`/`.owningFunctionalFitnessSlot`,
`WorkoutBlockTemplate.functionalFitnessPrescriptionTemplate`,
`ProgramDefinition.functionalFitnessConfiguration`. Changed:
`RecordWorkoutResultUseCase`'s signature (benchmark-folding parameters
removed, §5). `MovementFunction` gained 3 cases. See
`DELETE_RULE_MATRIX.md`'s new "Stage 4E additions" section for full
delete-rule reasoning.

### 11. Test count and result

276 tests total (236 Stage 4A-4D baseline + 40 new Stage 4E tests). All
276 pass on the real Xcode toolchain, including all 236 pre-existing
tests unchanged in substance — the 3 Fran-migration test updates are
documented in §5 above, not silent.

New Stage 4E test files: `FunctionalFitnessPersistenceTests` (6,
including the sibling-row-heterogeneity diagnostic for direct `Stimulus`/
`WorkoutFormat` storage and for the new `Exercise.functionalModality`
field, plus a cascade-delete proof for the new template relationship),
`FunctionalFitnessProgramGeneratorTests` (11, all 10 required format
shapes plus the format-vs-stimulus independence proof),
`FunctionalFitnessDecisionEngineTests` (9, missing-duration/missing-
modality/movement-pattern-overuse detection, fixed-priority-order
adjustment, determinism, insufficient-history-never-false-triggers, and
the skipped-session-exposure proof), `FunctionalFitnessScoringAndStressProfileTests`
(9, every required scoring direction plus 3 stress-profile
distinctness proofs), `FunctionalFitnessSubstitutionAndBenchmarkTests`
(5, benchmark identity/history/Rx-Scaled-independence, the Fran-
consolidation confirmation, scaling, and going-forward movement
substitution).

### 12. Simulator

Rebuilt and relaunched on an iPhone 17 (iOS 26.5) simulator after the
schema change (2 new `@Model` types, several new/changed fields, and the
Fran seed-scenario migration). App launched and stayed running — no
`ModelContainer` crash; Today renders identically to every prior pass.

### 13. What Stage 4E does not claim

- A curated Functional Fitness built-in library — no `V1_PROGRAM_LIBRARY.md`
  entry names one, matching every prior Stage 4 generator's identical
  finding.
- A full CrossFit-style programming methodology or a general skill-level
  gating system — §36's skill-demand-vs-user-level check is explicitly
  deferred (no per-Exercise skill classification exists; `FunctionalFitnessStimulusValidator`
  documents this gap rather than inventing a score).
- `FunctionalFitnessReasonCode.functionalSkillExposure`/`.functionalVarianceBalance`
  are declared for vocabulary completeness (matching `IntervalReasonCode`'s
  own "reserved code" precedent) but never produced by this pass's engine.
- ConcurrentScheduler integration (Stage 4F) — Functional Fitness emits
  Sessions/WorkoutBlocks/TrainingStressProfile the future scheduler can
  consume, but nothing here schedules across systems.
- Any UI (AMRAP/EMOM timer, benchmark UI) — explicitly out of scope (§58).

### 14. Architectural judgment: no flaw found, one consolidation resolved

Per the kickoff's explicit instruction to stop and explain before working
around any exposed flaw: this stage's one required structural resolution
(the Fran consolidation, §5) was an explicitly pre-identified, deferred
decision from Stage 3C, not a newly-discovered flaw — resolving it was
this stage's own explicit charter (§22/§55), not a deviation from plan.
The template graph and materializer pattern needed no conceptual change;
`FunctionalFitnessPrescriptionTemplate`/`FunctionalFitnessMaterializer`
are structurally consistent with every other Stage 4 system, differing
only in reusing `ExerciseSlot` (generalized with 2 new constraint
dimensions) instead of introducing a parallel slot type for movement
requirements.

### 15. Commit

See the final commit hash reported alongside this document. Local and
remote verified to match; working tree clean apart from local Xcode user
data.
