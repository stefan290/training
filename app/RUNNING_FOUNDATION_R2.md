# RUNNING R2 — Source-Grounded Running Foundation

Scope: domain primitives, calculations, execution rules, adaptation rules,
recalibration representation, and orchestration-facing metadata for
Running — NOT a program generator, NOT a UI checkpoint, NOT a
`LongTermPlanner`/`TrainingMix`/Functional Fitness/Hypertrophy change. This
document is the required deliverable of that checkpoint; it does not modify
`RUNNING_PROGRAMMING_MODEL_R1.md` (no concrete implementation contradiction
with the primary source was found).

## 1. Architecture chosen

TrainingOS already has a full, generic endurance/interval architecture from
an earlier stage (`ENDURANCE_PROGRAMMING_MODEL.md`,
`PRESCRIPTION_RESULT_MODEL_REVIEW.md`): `ActivityType.running`,
`IntensityTarget` (with `.percentOfReference(_, metric: .thresholdPace)`,
`.pace`, `.rpe` already present), `SteadyStatePrescription`,
`IntervalPrescription`, `WorkoutBlockType.steadyState`/`.intervals`,
`SessionRole`, and `TrainingStressProfile`. Per
`ENDURANCE_PROGRAMMING_MODEL.md` §9 ("no competing `ProgressionRule`
vocabulary, no competing `WorkoutBlock` type, no competing prescription/
result shape"), this checkpoint **reuses that architecture directly** rather
than building a parallel Running-only stack:

- A running Tempo/Active/Easy/Cool Down/Warm-up block is an ordinary
  `SteadyStatePrescription` with `activityType = .running`.
- A running Repeat Group (source: `R1`/`R2`/`R3`) is an ordinary
  `IntervalPrescription`.
- A multi-repeat-group session (source: relative week 11, three distinct
  repeat groups in one workout) is **multiple ordered `.intervals`
  `WorkoutBlock`s in one `Session`** — `WorkoutBlock.sortIndex` (assigned by
  `Session.addBlock`) already expresses "R1 then R2 then R3." Verified
  directly against the source data before concluding this: no repeat group
  in the observed sessions needs to interleave with another in a way a
  linear block list cannot express.
- Quality/easy classification reuses `SessionRole` (already has `.tempo`/
  `.threshold`/`.interval` vs. `.easy`/`.recovery`/`.aerobicBase`/`.long`) —
  no new field.
- "Recovery sensitivity" for orchestration reuses `TrainingStressProfile
  .recoveryDemand` directly — no new field.

**Genuinely new** (no existing type covered this): threshold-relative pace
math, athlete execution-override rules, in-workout adaptation rules,
missed-session/re-entry rules, pain-response state, and scheduled threshold
recalibration. Each follows the codebase's own established pattern for this
kind of thing — a `Domain/ValueTypes/*Types.swift` file with a closed,
`Codable` reason-code/decision enum, paired with a pure, stateless
`Engines/*Engine.swift` type (no `SwiftData`, no randomness, no date-reading)
returning `(value, reasonCode)` tuples — exactly mirroring
`StrengthProgressionEngine`/`SteadyStateProgressionEngine`/
`IntervalProgressionEngine`.

## 2. Files changed

**New (13 production files):**
- `TrainingOS/Domain/ValueTypes/RunningSourceLabel.swift`
- `TrainingOS/Domain/ValueTypes/RunningExecutionOverrideTypes.swift`
- `TrainingOS/Domain/ValueTypes/RunningAdaptationTypes.swift`
- `TrainingOS/Domain/ValueTypes/RunningPainResponseTypes.swift`
- `TrainingOS/Domain/ValueTypes/RunningReEntryTypes.swift`
- `TrainingOS/Domain/ValueTypes/RunningThresholdRecalibrationTypes.swift`
- `TrainingOS/Domain/ValueTypes/RunningOrchestrationTypes.swift`
- `TrainingOS/Domain/Entities/RunningThresholdCalibration.swift`
- `TrainingOS/Engines/ThresholdPaceEngine.swift`
- `TrainingOS/Engines/RunningExecutionOverrideEngine.swift`
- `TrainingOS/Engines/RunningAdaptationEngine.swift`
- `TrainingOS/Engines/RunningReEntryEngine.swift`
- `TrainingOS/Application/UseCases/RecordRunningThresholdCalibrationUseCase.swift`

**Modified (additive only):**
- `TrainingOS/Domain/Entities/SteadyStatePrescription.swift` — `+sourceLabel: RunningSourceLabel?`, `+executionNotes: String?`.
- `TrainingOS/Domain/Entities/IntervalPrescription.swift` — same two fields.
- `TrainingOS/Domain/Entities/ProgramInstance.swift` — `+runningThresholdCalibrations` relationship (cascade, mirrors `sourceRMCalibrations`) + `addRunningThresholdCalibration`.
- `TrainingOS/Persistence/PersistenceController.swift` — `+RunningThresholdCalibration.self` in the schema.
- `TrainingOS.xcodeproj/project.pbxproj` — file registrations only.

**New (9 test files, 74 tests):**
`ThresholdPaceEngineTests.swift`, `RunningExecutionOverrideEngineTests.swift`,
`RunningPrescriptionRepresentationTests.swift`,
`RunningAdaptationEngineTests.swift`, `RunningPainResponseEngineTests.swift`,
`RunningReEntryEngineTests.swift`, `RunningThresholdRecalibrationTests.swift`,
`RunningOrchestrationContractTests.swift`,
`RunningFoundationDogfoodTests.swift`.

No file under `source_workbooks/` was modified; the directory remains
gitignored and untracked throughout.

## 3. Source-backed invariants

- `adjusted_pace_seconds = threshold_pace_seconds / percent_of_threshold`
  (`ThresholdPaceEngine`), no athlete threshold ever hardcoded.
- No floor/ceiling on `percentOfThreshold` — the source legitimately
  prescribes ~60%–~110%.
- The ≤89% rule is an **athlete execution override limit relative to that
  block's own prescribed intensity**, never a restriction on what may be
  prescribed (the corrected R1 finding, applied throughout).
- Rep-1 override, ≤95%-threshold override, and ≤RPE6 override are all flat
  refusals, independent of the 89% rule.
- Threshold recalibration is scheduled-event-gated only (`Don't adjust any
  other time`) — never computed, never silently applied.
- Missed-session/illness/travel/multi-week/>1-month re-entry rules match
  FAQ's decision tree exactly, including returning **both** valid options
  for the >1-month case rather than inventing a tie-breaker.
- The pain-response ladder (stop → walk → jog slowly → jog faster → full
  pace) forces an immediate, permanent stop on any recurrence, at any
  stage.

## 4. Advisory vs. mandatory (R2.10)

Every cross-domain rule found in `Program-Pairing Guide.docx`/FAQ's
stacking discussion is classified `.advisory`, cited in
`RunningOrchestrationContract` and tested in
`RunningOrchestrationContractTests.testNoCrossDomainRuleIsClassifiedMandatoryGivenSourceHedgeLanguageAndExplicitOverridePaths`:
lifting sequenced after running, lifting-before-running pace reduction,
non-stackability, and lifting-frequency-modification limits. Every one of
these is phrased with a hedge ("recommended"/"should"/"not
recommended"/"usually") AND paired with an explicit override path RP itself
states — none is an absolute prohibition, so none is `.mandatory`.

## 5. Evidence boundaries

- **Genuine source ambiguity, not invented:** the `[100%, 101%)` rep-failure
  band. FAQ gives an unconditional rule for "≥101%" and a separate one for
  "<100%," and never addresses this half-open gap.
  `RunningRepFailureAction.sourceAmbiguousBandNotAddressed` represents this
  honestly instead of guessing.
- Race-day RPE-only generalization, the 16-vs-13-week discrepancy, and
  universal mesocycle length remain **explicitly unresolved**, per R1 — none
  were needed by, or resolved by, this checkpoint's foundation primitives.

## 6. Types introduced

See §1/§2. Every new reason-code enum is `Codable, CaseIterable` and every
new engine is a stateless `enum` namespace (no instance state, no
`SwiftData` import) — same discipline as every existing progression engine.

## 7. Integration points

`WorkoutBlock`/`Session`/`ProgramInstance` (reused as-is), `IntensityTarget`
(reused as-is), `TrainingStressProfile`/`SessionRole` (reused for
orchestration metadata). `RunningThresholdCalibration` follows
`SourceRMCalibration`'s exact established pattern (own entity, cascade off
`ProgramInstance`, literal user-entered value, CLAUDE.md rule 2 compliant —
never a field on `ProgramDefinition`).

## 8. Tests

74 new tests across 9 files, covering every category A-S from the
directive plus every listed regression (80%/60%/110% valid; 80→85%
override rejected; no TrainingPeaks Zone required; source labels survive
round-trip; no unsupported physiological label exists). All pass.

## 9. Intentionally unresolved behavior

The `[100%, 101%)` rep-failure band (see §5) — flagged, not guessed.

## 10. Exact deferred generator questions (R2.11, untouched)

General 5K generator; 16-vs-13-week resolution; fabricated missing weeks;
3/4/5/6-run-per-week generation; higher-frequency taxonomy; universal
4-week mesocycle/deload/taper/race-day-RPE rules; 10K/half/marathon
generators; automatic starting-volume selection; race-time prediction;
automatic threshold-reassessment algorithm; Running UI; any
`LongTermPlanner`/`TrainingMix`/Functional Fitness/Hypertrophy change.
