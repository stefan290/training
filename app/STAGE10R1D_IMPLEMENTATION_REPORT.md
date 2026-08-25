# Stage 10R.1D — Source Semantics Correction: Implementation Report

Corrects the shared "N/fail" prescription-semantics defect across Family
A, B, and C, plus a follow-up UX-only refinement. Both passes manually
accepted. Committed.

## Summary

The source's "N/fail" notation (e.g. "3/fail") is an effort/RIR target —
"stop with about N reps left in the tank" — never a fixed rep count
followed by a fabricated RIR of 0. Prior code (`RepGoal(reps: 3,
toFailure: true)`) forced every such row to display a fictitious "3
reps · 0 RIR." This stage introduces an explicit `RepPrescriptionKind`
enum (`.fixedReps(Int)` / `.rir(Int)`) so the two prescription kinds can
never be conflated again, corrects every Family A/B/C generator
construction, and removes every fabrication site downstream
(materialization, deload resolution, execution UI, "Next time"
progression preview).

## Phase A — archaeology findings

- **Deload's "X reps of Week 1" instruction** (e.g. "1/2 reps of Week
  1") is proven — by the workbook's own separate "Rep Goal"/"Rep
  Results" column headers — to reference the athlete's ACTUAL logged
  Week-1 performance, never the template's authored target. No formula,
  comment, validation, or instruction anywhere resolves *which* Week-1
  set to reference when a row's sets logged different rep counts (sets
  genuinely vary 2-4 per row). **Left unresolved, not implemented** —
  deload rep resolution now returns `nil` with an honest new reason code
  (`StrengthReasonCode.deloadRepsRequireLoggedPerformanceData`) rather
  than fabricating a number.
- No rep range exists anywhere in Family A's source content; a single,
  unlinked, generic legend exists in one Family B file only. Neither is
  treated as a per-slot enforced range.
- The RM calibration screen's "tested weight"/"perform a real attempt"
  copy was confirmed factually wrong — the source's own instructions
  explicitly invite estimation.

## Domain model

```swift
enum RepPrescriptionKind: Codable, Equatable {
    case fixedReps(Int)   // a genuine source fixed rep count (e.g. Powerlifting Triples: 3,3,3)
    case rir(Int)         // an effort/RIR target, no fixed rep count ("N/fail" -> RIR N)
}

struct RepGoal: Codable, Equatable {
    var prescription: RepPrescriptionKind
    var repRangeHigh: Int?   // Hypertrophy V2's range-companion only; nil for Family A/B/C
    var targetRir: Int?      // Hypertrophy V2's explicit-RIR companion only; nil for Family A/B/C
}
```

`SetPrescription.repRangeLow`/`repRangeHigh` are now `Int?` (were
non-optional) — `nil` for an RIR-only prescription or an unresolved
deload rep target, a real number only for a genuine fixed-rep
prescription. No sentinel value is used at the domain-model level.

## Family A/B/C corrections

| Family | Before | After |
|---|---|---|
| A (3-Day Full Body + legacy) primary | `RepGoal(reps:3/3/2/1, toFailure:true)` | `.rir(3), .rir(3), .rir(2), .rir(1)` |
| A paired accessory | `RepGoal(reps:12, toFailure:false)` | `.fixedReps(12)` — unchanged behavior |
| B ordinary rows | `RepGoal(reps:2/2/2/1, toFailure:true)` | `.rir(2), .rir(2), .rir(2), .rir(1)` |
| B Triples | `RepGoal(reps:3, toFailure:false)` | `.fixedReps(3)` — genuinely unchanged |
| C standard rows | `RepGoal(reps:8, toFailure:true)` (already flagged "placeholder, unconfirmed in source") | `.rir(8)` — mechanically migrated; content still unconfirmed |

Load progression, set autoregulation, rating pairing, deload weight, and
deload set count are byte-for-byte unchanged — proven by every
pre-existing test covering them passing unmodified.

## Newly discovered consequence

`DoubleProgressionEngine`'s "Next time" preview
(`CompleteSessionUseCase.progressionPreview`) cannot evaluate an
RIR-only prescription — its algorithm is "did reps clear a fixed rep
range," which no longer exists for these rows. Such exercises are now
cleanly skipped from the preview (never given a fabricated range-based
verdict) rather than the engine being redesigned, which is out of this
stage's scope. A future load-bias/progression-overlay design will need
to address this deliberately.

## UX-only follow-up (same checkpoint)

Manual acceptance of the corrected source semantics surfaced one UX gap:
the execution screen's "Reps: 0" looked like a fabricated zero-rep
prescription for an RIR-only set, and "RIR" (the actual-result selector)
read as if it might be the target. Corrected, presentation/input state
only — no business logic touched:

- **RIR-only prescription header** now adds a dynamic, plain-language
  guidance line under "Suggested load," e.g. *"Perform reps until you
  have about 3 reps in reserve"* (RIR 0 reads as *"Perform reps to
  failure — no reps in reserve"*). Never shown for a fixed-rep
  prescription. No fabricated rep range is ever introduced.
- **Actual-reps input** relabeled "Actual reps" and begins as an
  explicit "—" placeholder (never a visually-meaningful `0`) for an
  RIR-only or unresolved-deload set; a genuine fixed-rep prescription
  still prefills its target as before.
- **Actual-RIR selector** relabeled "Actual RIR," distinct from the
  header's own "RIR N" target text.

The formatting/guidance rules were extracted into a new pure type,
`StrengthSetPresentation` (`TrainingOS/Engines/StrengthSetPresentation.swift`),
mirroring `CompletedHistoryPresentation`'s existing precedent for
keeping decision logic out of the View itself and independently
testable without a UI-tap harness.

## Files changed

**Domain**: `StrengthProgressionRules.swift`, `PrescriptionTemplate.swift`,
`SetPrescription.swift`.
**Engines**: `DeloadStrategy.swift`, `BlockProgressionEngine.swift`,
`DoubleProgressionHistoryResolver.swift`, new `StrengthSetPresentation.swift`.
**Use cases**: `StrengthMaterializer.swift`, `HypertrophyProgramGenerator.swift`,
`PowerliftingProgramGenerator.swift`, `FunctionalFitnessProgramGenerator.swift`,
`FunctionalFitnessMaterializer.swift`, `HypertrophyV2ProgressionEngine.swift`,
`CompleteSessionUseCase.swift`, `SeedScenarios.swift`.
**UI**: `StrengthExecutionView.swift`, `TemplateSessionPreviewView.swift`,
`SourceRMCalibrationView.swift`.
**Tests**: 16 files migrated/corrected, plus new `StrengthSetPresentationTests.swift`
and new coverage in `MultiExerciseExecutionTests.swift`.

## Test results

Full suite: **813 tests, 813 passed, 0 failures, 2 skipped** (pre-existing,
documented `XCTSkip`s from an unrelated mixed-modality scheduling
limitation — see `STAGE10R1_SLICE1B_IMPLEMENTATION_REPORT.md`).

## Known remaining gaps (tracked, not addressed by this stage)

- `RollTacticalWindowUseCase.rollForward` has no production call site yet.
- Deload rep-result selection (which Week-1 set to reference) remains
  source-unresolved.
- Family C's non-deload rep-per-week content remains an unconfirmed
  placeholder.
- Two `TacticalPlacementBoundaryTests` `XCTSkip`s remain, from the
  at-capacity mixed-modality scheduling limitation.
- The warm-up "primary block" heuristic weakness (Push Emphasis example)
  remains a separate, un-fixed, documented bug.
