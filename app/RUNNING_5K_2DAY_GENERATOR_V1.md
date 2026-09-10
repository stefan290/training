# Running 5K / 2-Day Generator V1

Scope: a source-backed SPECIALIZED generator, not a discovery of universal
running-programming logic. Takes the recovered 5K/2-day program structure
(R1) and materializes it for a specific athlete using the generic Running
Foundation (R2). Broader running generalization (other frequencies, levels,
distances) is explicitly deferred — see §12.

## 1. Exact V1 capability

TrainingOS can materialize exactly one Running configuration today:

- **Goal/distance:** 5K
- **Frequency:** 2 runs/week
- **Structure:** the recovered 13-relative-week, 25-workout structure from
  `RP_5K_TrainingPeaks_Reference.xlsx`'s `Workout Blocks` sheet

Every other `(distance, daysPerWeek)` combination is explicitly refused —
never approximated to this one (§7).

## 2. Authority / provenance

RP documentation + the reconstructed observed RP 5K program remain
REFERENCE PROGRAMMING AUTHORITY (R1's own framing, unchanged). This
generator's `ProgramDefinition` is created with
`provenance: .sourced(file: "RP_5K_TrainingPeaks_Reference.xlsx", sheet:
"Workout Blocks", cell: "all rows")` — every one of the 145 source rows was
re-derived directly from the workbook this checkpoint (via `openpyxl`), not
copied from R1's prose summary, which only walks representative weeks.

## 3. Why 13 weeks, not the nominal 16

RP's own documentation refers to a nominal 16-week program (R1 §2/§3). The
recovered source evidence contains 12 paired training weeks + 1 race week =
13 relative weeks / 25 workouts. The missing ~3 weeks' content is unknown
and is NOT fabricated, extrapolated, or approximated with generic base
weeks — this is an explicit TrainingOS product decision (already
recommended by R1 §22 and confirmed by R3's source-gap analysis §10): **the
recovered 13-relative-week structure is the complete, supported TrainingOS
Running V1 program.** This document is the disclosure of that decision;
`RunningProgramGenerator`'s own doc comments repeat it at the point of
implementation.

## 4. Program Definition architecture

**Reused directly, no parallel architecture:**
- `ProgramDefinition`/`ProgramInstance`/`TrainingWeek` — the same entities
  every other system uses. `ProgramDefinition.runningConfiguration:
  RunningProgramConfiguration?` is the one new field (mirrors
  `hypertrophyConfiguration`/`steadyStateConfiguration`'s existing pattern
  exactly).
- `TemplateSession`/`WorkoutBlockTemplate`/`SteadyStatePrescriptionTemplate`/
  `IntervalPrescriptionTemplate` — the R2-extended template types (two
  additive fields each: `sourceLabel`, `executionNotes`).
- `ProgrammingSystemKind.running` — a 6th named system, added per
  `ENDURANCE_PROGRAMMING_MODEL.md` §9's own validated conclusion: a thin,
  named methodology composer over `.steadyState`/`.interval` content, never
  a competing engine. Adding it forced every exhaustive switch over
  `ProgrammingSystemKind`/`GeneratorParameters` in the codebase to update —
  every one of those updates is a **genuinely minimal, compiler-forced
  addition**, never new recommendation policy (§9 lists every touched file
  and exactly what each addition does).

**One deliberate architectural difference from every other system:**
Hypertrophy/SteadyState/Interval/Functional Fitness each have ONE recurring
weekly structure whose numbers progress by a rule (`TemplateSession
.activeFromWeek` means "joins the rotation at this week and recurs from
then on," read via `activeFromWeek <= weekIndex`). Running's recovered
structure is the opposite — R1 found the actual block/repeat SHAPE changes
every single relative week (warm-up block count 1→7, repeat-group count
0→3). Forcing this into "2 recurring sessions + per-week rule arrays" would
lose structure. Instead: **all 25 `TemplateSession`s are created, each
pinned to exactly the one relative week it belongs to** (`activeFromWeek`
set to that exact 0-indexed week). `RunningProgramMaterializer` reads this
with **exact equality** (`activeFromWeek == weekIndex`), never the generic
`<=` filter. No new schema field was needed — `activeFromWeek` is reused,
but interpreted differently, entirely scoped to this one new materializer;
no other materializer/preflight is ever invoked against a `.running`
definition (confirmed: `RollTacticalWindowUseCase` dispatches `.running` to
`RunningProgramMaterializer` alone, and `TacticalAdvancementPreflight`
explicitly excludes `.running` from its own `<=` computation, for the
identical reason it already excludes `.steadyState`).

**One additive engine field:** `IntervalProgressionRules`/
`IntervalPrescriptionTemplate` gained `weekOneRecoveryDistanceMeters:
Double?` + `IntervalProgressionEngine.resolveRecoveryDistance` — no
existing interval configuration before Running ever prescribed a recovery
leg by distance (only by duration); Running's recovery legs (e.g. the
"Easy .25 mi" partner of a "Hard" rep) are literal, unprogressed distances.

## 5. Athlete personalization boundary

**PROGRAM STRUCTURE vs. ATHLETE-SPECIFIC PRESCRIPTION, kept strictly
separate:**
- Every block in `RunningProgramGenerator`'s literal source data carries
  only a `%threshold` fraction (`IntensityTarget.percentOfReference(_,
  metric: .thresholdPace)`) or an RPE value — never an absolute pace, never
  any captured athlete's specific number. The captured reference athlete's
  5:00/km threshold appears nowhere in production code — only in R1's
  analysis and in test/dogfood fixtures.
- A real athlete's absolute target pace is computed ONLY at materialization
  time, via `ThresholdPaceEngine.targetPace` (R2), from that specific
  `ProgramInstance`'s own `RunningThresholdCalibration`.
- Proven directly: `RunningProgramMaterializerTests
  .testMaterializingWithADifferentThresholdProducesIndividualizedPacesOverTheSameStructure`
  materializes the same definition twice with two different thresholds and
  confirms identical `%threshold` fractions, different resolved absolute
  paces.

## 6. Capability gates

`ProgramCapabilityRegistry.isRunningConfigurationSupported(distance:
daysPerWeek:)` is the single source of truth — reads `RunningBuiltInLibrary
.all` directly (never a second hand-maintained allowlist), returns `true`
only for the exact `(distance, daysPerWeek)` combinations curated there
(today: exactly one, 5K + 2). `RunningProgramGenerator.generate` checks
this FIRST and throws `RunningGenerationError.unsupportedConfiguration`
before building anything — never silently substitutes the nearest
supported combination. See §7/§10 for the proof this never falls back.

## 7. Materialization

`RunningProgramMaterializer.materializeAllWeeks` — the Running sibling of
`SteadyStateMaterializer`, reusing the identical "materialize everything
upfront" architecture (nothing in this program depends on a live per-week
result). For each of the 13 weeks, selects the exact-pinned session(s) via
`activeFromWeek == weekIndex` (§4), builds real `Day`/`Session`/
`WorkoutBlock` rows, and resolves each block's `SteadyStatePrescription`/
`IntervalPrescription` via the EXISTING `SteadyStateProgressionEngine`/
`IntervalProgressionEngine` resolvers, called in a degenerate "week 0, no
progression" mode (every template's own week-one value already IS that
exact week's literal source number — there is nothing to progress). Every
existing environment-compatibility/activity-substitution check
(`TrainingEnvironmentCompatibilityRule`, `SubstituteActivityUseCase`) is
reused unchanged.

## 8. Threshold requirement

`RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for:
instance:)` — generic over any definition using `%threshold`-relative
intensity (never Running-specific by name, mirroring
`RequiredSourceCalibrationsUseCase`'s own genericity over `.rmBased`
rules). Returns `true` whenever the definition contains at least one
`%threshold` block and the instance has no `RunningThresholdCalibration`
yet. **No silent default threshold exists anywhere in production code** —
confirmed by direct inspection: the captured 5:00/km value appears only in
test/dogfood fixtures.

## 9. Scheduled recalibration

`TrainingWeek.isThresholdRecalibrationCheckpoint` (new, additive field,
inline-defaulted `= false` for correct SwiftData lightweight migration of
already-persisted rows — see §11's migration note) marks which relative
weeks are scheduled Threshold Pace Adjustment checkpoints.
`RunningProgramGenerator.thresholdRecalibrationCheckpointRelativeWeeks =
[5, 9]` — placed immediately after the two doubly-corroborated reduction
weeks (4 and 8). **This placement is a disclosed PROGRAMMING INFERENCE /
TRAININGOS PRODUCT DECISION, not a resolved SOURCE FACT** — R1 corroborated
two calendar-side checkpoints ("around Nov 2"/"...2 around Nov 30") but the
exact relative-week alignment between `Calendar Overview` and `Workout
Blocks` numbering is explicitly unresolved (R1 §17/§20). The flag only
marks WHERE a checkpoint exists; the new threshold VALUE is never computed
by this checkpoint or any other production code — enforcement runs through
R2's already-existing `RunningThresholdRecalibrationGate`/
`RecordRunningThresholdCalibrationUseCase`, which requires the athlete's
own entered number and rejects any out-of-schedule attempt.

## 10. Adaptation delegation to R2

No R2 rule is duplicated. Execution-override, in-workout-adaptation,
missed-session/re-entry, and pain-response rules apply to materialized
`SteadyStatePrescription`/`IntervalPrescription` rows exactly as R2 already
built them, regardless of which definition produced them — verified by
construction (this checkpoint added zero new copies of any R2 engine) and
by a direct test (`RunningProgramMaterializerTests
.testR2ExecutionOverrideEngineAppliesToAMaterializedEightyPercentBlock`).

## 11. Fidelity tests

44 new tests across 3 new files (`RunningProgramGeneratorTests` — 25,
`RunningCapabilityGateTests` — 9, `RunningProgramMaterializerTests` — 10),
on top of R2's own pre-existing 74 (unchanged except the 2 corrections
noted below), covering: exact week/workout counts; slot/ordering
fidelity; source labels (including the corrected 8th label, `.recovery` —
§13) and distances; all 13 `%threshold` values; RPE-only race prescription
with the verbatim pacing note; every repeat-group shape (4-repeat,
6-repeat, 3-distinct-groups, taper single-rep pairs); no absolute captured
pace anywhere in the definition; no TrainingPeaks Zone required; no
fabricated weeks or dates; the 6 required representative structural
shapes; the 4 capability-gate scenarios (5K+2 supported; 5K+1, 5K+3, and
every other frequency unsupported, with an explicit thrown error, never a
fallback); the two-threshold personalization proof; repeat/taper/race
survival through materialization; recalibration-checkpoint placement and
R2-gate enforcement; and R2 adaptation-engine applicability post-
materialization.

Also corrected during this checkpoint (concrete source contradictions
found by direct primary-source re-inspection, not a re-audit — disclosed
per this engagement's established discipline):
- **R1 §7 / R2 `RunningSourceLabel`**: an 8th real `Source Label` value,
  `"Recovery"`, found in relative weeks 5-8 (distinct from `Easy`) — R1 §7
  gained a disclosed addendum row; `RunningSourceLabel` gained `.recovery`
  (additive); `RunningPrescriptionRepresentationTests
  .testEveryObservedSourceLabelIsRepresentableAndNoUnsupportedPhysiologicalLabelExists`
  updated from 7 to 8 cases.
- **`ProgramCapabilityRegistryTests`**: `testOnlyHypertrophyAndPowerliftingHaveCuratedConfigurations`
  was rendered factually false by Running's new curated entry — renamed
  and corrected (`testCuratedConfigurationCoverageAcrossAllSixSystems`),
  `testAllFiveProgrammingSystemsAreAvailable` renamed/corrected to
  `testAllSixProgrammingSystemsAreAvailable`.

## 12. Intentionally unsupported configurations (fenced, not fabricated)

Refused by `ProgramCapabilityRegistry.isRunningConfigurationSupported`,
proven never to fall back to the nearest supported combination:
5K + 1/3/4/5/6+ runs/week; 10K/Half Marathon/Marathon at any frequency;
any generic running-fitness plan. `RunningDistance` is deliberately
single-case (`.fiveK`) this V1 — no unimplemented distance case exists to
even request.

## 13. Future expansion path (documented, not implemented)

**Running V2:** 3+ days/week; athlete-level structural adaptation
(starting-volume personalization by ability); additional reference
programming systems; generalized mesocycle rules — each requires new
source evidence per `RUNNING_GENERATOR_SOURCE_GAP_R3.md` §4-9, not a
TrainingOS-invented rule.

**Running V3+:** 10K/Half Marathon/Marathon; broader race-specific
programming — requires a purpose-built source per distance
(`RUNNING_GENERATOR_SOURCE_GAP_R3.md` §9).

Neither is a V1 defect — both are the explicit, disclosed boundary this
document describes.

## 14. Do-not-touch confirmation

Hypertrophy/Powerlifting/Functional-Fitness/Training-Environment/Exercise-
Library generator content and test fixtures: byte-for-byte unchanged.
Genuinely minimal, compiler-forced integration touches only (new
`ProgrammingSystemKind`/`GeneratorParameters` case added to every
exhaustive switch that required it): `LongTermPlanner.swift` (6 switches —
every `.running` branch either returns an empty candidate list, a neutral
classification matching Steady State/Interval, or a fully-working
generator call that is unreachable through this planner today, per §6's
own gate — never new recommendation policy), `RollTacticalWindowUseCase.swift`
(dispatches `.running` to `RunningProgramMaterializer`, exactly mirroring
`.steadyState`'s existing dispatch), `TacticalAdvancementPreflight.swift`
(excludes `.running` from its `activeFromWeek <=` computation, exactly
mirroring `.steadyState`'s existing exclusion), `TacticalWindowPolicy.swift`
(`.running` joins the existing "no fixed block, use the configurable
fallback" group), `HypertrophyFeedbackPrompts.swift` (`.running` joins the
existing default soreness-copy group), `PlanPresentation.swift` (one new
display-label case, "Running"). No Running UI was built. No commit, no
push, nothing staged.