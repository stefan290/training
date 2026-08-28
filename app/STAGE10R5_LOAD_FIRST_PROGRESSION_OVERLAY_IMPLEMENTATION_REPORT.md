# Stage 10R.5 — Load-First Progression Overlay: Implementation Report

**Status: implementation complete, automated tests green, Simulator
smoke clean. NOT YET COMMITTED, NOT YET PUSHED** — awaiting manual
acceptance per explicit instruction.

## 1. Final implemented algorithm

Model 2 — Performance-Qualified Source Schedule (D-10R5-1): the
source's own next-scheduled load (`SetPrescription.targetWeight`,
untouched) is always the default; `LoadFirstOverlayEngine.recommend`
decides accept / accelerate one increment / hold at the previous
reference weight / regress one increment, per the locked decision table.

## 2. Exact easy/matched/hard classification

`LoadFirstOverlayEngine.classify(surpluses:)` — the complete per-set
`actualRir - targetRir` vector, never pre-averaged:
- **CONSISTENTLY EASY**: every valid set's surplus ≥ 0 AND the average
  surplus ≥ +2. One set below target vetoes this outright (`5/5/2` at
  target 3 → NOT easy, per D-10R5-3's own example — verified by
  `testOneSetBelowTargetVetoesConsistentlyEasy`).
- **TOO HARD**: the worst (minimum) set's surplus ≤ −2.
- **MATCHED**: every valid set's surplus exactly 0.
- **INCONSISTENT**: everything else (some real variability, nothing
  alarming) — treated the same as MATCHED for output purposes (hold,
  `.holdMatchedTarget`).

## 3. Source-vs-overlay load calculation

`SetPrescription.targetWeight` is read directly for `sourceWeight` and
is **never mutated anywhere in this stage** — confirmed by
`testSourceAndLoadFocusedCoexistAndSourceWeightNeverMutated` (two
sibling instances of the identical source program, one SOURCE one
LOAD_FOCUSED, both produce byte-identical `SetPrescription.targetWeight`
values at every week). The `finalWeight` the execution UI shows is
computed by `LoadFirstOverlayEngine.recommend` and — only once, the
first time it's needed for a given exposure — frozen onto
`ExercisePrescription.loadOverlayRecommendedWeight` alongside
`appliedLoadOverlayReasonCode`.

## 4. Increment guard

`LoadFirstOverlayEngine.maxProportionalIncrementRatio = 0.10`, reused
directly from Stage 10B.6. Behavior is DEFER, not discard: an otherwise-
qualifying increase whose smallest available increment exceeds 10% of
the current weight holds this exposure (`.holdIncrementTooLarge`) — the
underlying evidence is not erased, it simply isn't acted on yet. Proven
by `testDisproportionateIncrementHoldsWithoutDiscardingEvidence`
(20kg + 2.5kg = 12.5%, held) vs. `testProportionateIncrementIsNotBlocked`
(100kg + 2.5kg = 2.5%, applied).

## 5. Regression/streak behavior

No persisted counter anywhere — the "streak" is purely derived by
looking at the resolver's own most-recent-2-eligible-exposures list.
First hard exposure → hold at the previous reference weight (never the
source's fresh value). Second CONSECUTIVE eligible hard exposure →
regress one increment from that same reference weight. Any eligible
non-hard exposure resets the streak (proven by
`testHardStreakResetsAfterAnEligibleNonHardExposure`). An ineligible
(missing/skipped/readiness/deload) exposure is invisible to the streak
entirely — it neither advances nor resets it, since the resolver simply
omits it from its output rather than inserting a neutral placeholder.

## 6. Readiness behavior

Unchanged reuse of the already-approved `READINESS_PROGRESSION_CONTRACT.md`
§3 rule: any exposure with an accepted `ReadinessAdaptationDecision` is
excluded entirely from the resolver's output (`.readinessExcluded` when
this is the only/most-recent relevant history) — proven by
`testReadinessAdaptedExposureIsExcluded`.

## 7. Missing/skipped behavior

An exposure with any valid prescribed set missing a logged actual RIR
(skipped/missed/abandoned session, or a genuinely partial log) is
entirely excluded from the resolver's output — `.holdInsufficientData`,
never interpreted as either easy or hard. Proven by
`testExposureWithNoLoggedResultsIsInvisibleToTheResolver` and
`testPartiallyLoggedExposureIsAlsoInvisible`.

## 8. Deload behavior

Two independent layers, both proven: (a) the current exposure's own
`isDeloadWeek` flag (read from `appliedLoadReasonCode`'s deload-prefixed
cases) forces `.deloadSourceAuthority` unconditionally, regardless of
how easy the (excluded) history looks
(`testDeloadWeekIsSourceAuthorityRegardlessOfHistory`); (b) a deload
exposure is entirely excluded from ever appearing in a LATER week's
resolved history (`testDeloadExposureIsExcluded`) — a deload's
deliberately-easy performance can never leak forward as "load too light."

## 9. Substitution behavior

Evidence is scoped by real `Exercise` identity — a substitution
(different `Exercise`) naturally produces zero shared history, proven
directly by `testDifferentExerciseHasNoSharedEvidence`. No bridging
mechanism was added or reused; `SubstitutionAwareRecommendation`'s
half-confidence cross-exercise estimate was confirmed (Stage 10R.5
design pass) to be already fully isolated from `.rmBased`/
`SourceRMCalibration`, and this stage never touches it.

## 10. Mesocycle reset behavior

Evidence is additionally scoped to one `ProgramInstance` — a new
mesocycle's instance naturally has zero shared history with the prior
one, proven by `testDifferentProgramInstanceHasNoSharedEvidence`.
`SourceRMCalibration` is never auto-populated or adjusted by the overlay
at any point — proven end to end by
`testCalibrationNeverAutomaticallyChangedByTheOverlay` (a real easy
exposure, a real roll to Week 2, a real overlay computation, then an
assertion that the calibration value is byte-identical to what was
entered). Model 3 (automatic anchor recalibration) was not built, per
explicit rejection.

## 11. Feature-mode storage/default/override

`UserProfile.preferredProgressionStyle: ProgressionStyle` (default
`.loadFocused`, D-10R5-16) + `ProgramInstance.progressionStyleOverride:
ProgressionStyle?` (nil = defer to the profile default) +
`ProgramInstance.effectiveProgressionStyle(userProfile:)`. Proven:
`testProfileDefaultIsLoadFocusedWhenNoOverrideIsSet` and
`testInstanceOverrideAlwaysWinsOverProfileDefault` (both directions).
`.source` remains permanently selectable and is exercised by its own
dedicated test (`testSourceModeNeverComputesAnOverlayRecommendation`).

## 12. Provenance model

New, standalone `LoadOverlayReasonCode` — exactly the 8 cases locked in
D-10R5-17 — never extends `StrengthReasonCode` or reuses
`ProgressionReasonCode`. Lives as a third, independently-typed field
(`ExercisePrescription.appliedLoadOverlayReasonCode`) alongside the two
pre-existing reason-code tracks, exactly mirroring that established
"multiple typed reason-code tracks on one prescription" pattern.

## 13. Historical recommendation behavior

Computed live at the moment the execution layer first needs it, then
frozen (`loadOverlayRecommendedWeight`/`appliedLoadOverlayReasonCode`)
and never recomputed again for that same exposure. Proven — properly,
not by manually corrupting the frozen field, but by genuinely advancing
to a real, dramatically different Week 2 exposure and confirming Week
1's own already-frozen record is completely untouched by it
(`testCompletedExposureProvenanceIsFrozenNotRecomputed`).

## 14. Execution-UI integration

Traced and wired exactly per the pre-implementation architecture trace:
`StrengthExecutionViewModel.effectiveTargetWeight(modelContext:)` is the
one new seam. `StrengthExecutionView` no longer reads
`setPrescription.targetWeight` directly for either the "Suggested load"
display or the editable weight field's prefill — both now read a new
`@State private var effectiveTargetWeight: Double?`, computed once per
movement in `resetInputsForCurrentSet()` (never inside `body` itself,
since the computation has a real side effect — freezing the
recommendation — and SwiftUI body evaluation must stay side-effect-free).

## 15. Files/types changed

**New production files**: `TrainingOS/Domain/ValueTypes/ProgressionStyle.swift`,
`TrainingOS/Domain/ValueTypes/LoadOverlayReasonCode.swift`,
`TrainingOS/Engines/LoadFirstOverlayEngine.swift`,
`TrainingOS/Engines/LoadFirstExposureResolver.swift`,
`TrainingOS/Engines/LoadFirstEligibility.swift`.
**Modified production files**: `TrainingOS/Domain/Entities/UserProfile.swift`
(+`preferredProgressionStyle`), `TrainingOS/Domain/Entities/ProgramInstance.swift`
(+`progressionStyleOverride`, +`effectiveProgressionStyle(userProfile:)`),
`TrainingOS/Domain/Entities/ExercisePrescription.swift`
(+`appliedLoadOverlayReasonCode`, +`loadOverlayRecommendedWeight`),
`TrainingOS/Application/ViewModels/StrengthExecutionViewModel.swift`
(+`effectiveTargetWeight(modelContext:)`), `TrainingOS/UI/Session/StrengthExecutionView.swift`
(both `targetWeight` read sites redirected), `TrainingOS.xcodeproj/project.pbxproj`.
**New test files**: `TrainingOSTests/LoadFirstOverlayEngineTests.swift` (17
tests), `TrainingOSTests/LoadFirstExposureResolverTests.swift` (8 tests),
`TrainingOSTests/LoadFirstProgressionIntegrationTests.swift` (7 tests).
**No changes** to `StrengthMaterializer`, `RollTacticalWindowUseCase`,
`AdvanceTacticalWeekUseCase`, `TacticalWeekCompletion`,
`SourceRMCalibration`, any Family A source content table, or any
existing test file.

## 16. Targeted tests

32/32 new tests passed (17 engine + 8 resolver + 7 integration), each
run in isolation before the full suite.

## 17. Full-suite result

**927/927 passed, 0 failures, 2 pre-existing documented skips**
(unrelated mixed-modality scheduling limitation). Run twice consecutively
to confirm stability — both runs identical.

## 18. Source-regression proof

Every pre-existing Stage 10R.1–10R.3 source-fidelity test remains green,
unmodified. `testSourceAndLoadFocusedCoexistAndSourceWeightNeverMutated`
additionally proves this stage's own claim directly: the source's Week 2
`targetWeight` is byte-identical whether an instance is in SOURCE or
LOAD_FOCUSED mode.

## 19. Tactical-rollForward regression proof

Every pre-existing Stage 10R.4 test (`TacticalWeekCompletionTests`,
`AdvanceTacticalWeekUseCaseTests`, `StartNextHypertrophyPhaseUseCaseTests`)
remains green, unmodified. This stage's own integration tests drive real
`AdvanceTacticalWeekUseCase.advance` calls as part of their fixtures,
additionally proving the two systems compose correctly together.

## 20. Simulator state

Fresh install (uninstall + install + launch) — no crash, no fatal/
terminate log entries, renders the same seeded Mesocycle 1 Starting
Weights screen as every prior stage. **What to inspect manually, since
this sandbox has no UI-tap automation**:
1. Complete Starting Weights normally and reach Today.
2. Open a Hypertrophy session's execution screen — with fresh seed data
   (zero training history), "Suggested load" will show the SOURCE's own
   Week 1 value with `.holdInsufficientData` internally (correct,
   expected LOAD_FOCUSED behavior on a first-ever exposure — not a bug).
3. To actually witness a real adjustment: log a full session with
   actual RIR noticeably above target (e.g. target RIR 3, log actual RIR
   5 on every set), finish the session, then use the "Start Week 2"
   action (Stage 10R.4) once the whole week is resolved. Week 2's
   execution screen for that same exercise should show a suggested load
   one equipment increment above the source's own Week 2 number, with
   the domain's `SetPrescription.targetWeight` for that same slot still
   showing the original, unmodified source value if inspected directly.

## 21. Newly discovered conflict or ambiguity

None that blocked implementation. One genuine test-authoring mistake
caught and fixed before the final run (not a production defect): two
integration tests initially never marked the OTHER sessions in a
tactical week as terminal before calling `AdvanceTacticalWeekUseCase
.advance`, so the week never actually rolled — fixed by adding a shared
`completeWeek(in:weekIndex:loggedSession:)` test helper that completes
the exercise under test and skips the rest, matching real production
discipline. Also caught and fixed the same duplicate-`ExerciseCatalog`-insert
class of bug seen in Stage 10R.4 (two fixtures in one test each
inserting the catalog) — guarded with an existence check.

## 22. Deferred

Model 3 (adaptive anchor recalibration) — explicitly rejected for
automatic behavior this stage, per D-10R5-13. A future "your recent
training suggests retesting this RM" hint-text UX remains a possible
later idea, not built. Execution-UI redesign beyond the two
`targetWeight` read-site changes was explicitly out of scope and not
attempted. Extending eligibility beyond the recovered 3-Day Full Body
Family A path (other Family A configs, Family B/C, Running, Functional
Fitness) remains untouched, per D-10R5-20.
