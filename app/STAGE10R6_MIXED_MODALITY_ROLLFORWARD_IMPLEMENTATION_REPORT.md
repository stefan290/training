# Stage 10R.6 — Mixed-Modality Tactical RollForward Correctness: Implementation Report

**Status: 10R.6A/B/C implemented and tested. 10R.6D deferred by explicit
product decision (known domain gap, documented below, not fixed).
Not committed, not pushed.** Baseline: checkpoint `80b2326` (Stage
10R.5). See `STAGE10R6_MIXED_MODALITY_ROLLFORWARD_DESIGN.md` for the full
audit and the LOCKED DECISIONS (D-10R6-1 through D-10R6-18) this report
implements.

---

## 1. Final transaction architecture

`AdvanceTacticalWeekUseCase.advance` (the only production entry point to
`RollTacticalWindowUseCase.rollForward`) now works as follows:

1. Cheap, read-only eligibility check on the caller's own context: `mix`
   resolved from `phase`, `TacticalWeekCompletion.canAdvanceTacticalWeek(for:
   mix)`. Nothing mutated yet.
2. **Preflight** (`TacticalAdvancementPreflight.check(mix:)`) — still
   read-only. If any eligible, non-exhausted component has a
   deterministically missing prerequisite (FF exposure history required
   but absent; Interval previous-week outcome required but absent), the
   preflight error is thrown here, before any component is touched.
3. **Scratch context**: `let scratchContext = ModelContext(context.container)`,
   `scratchContext.autosaveEnabled = false`. `phase` and `mix` are
   re-fetched by `persistentModelID` *inside* this scratch context
   (`scratchPhase`/`scratchMix`) — the entire rest of the operation reads
   and writes exclusively through this context, never the caller's.
   Eligibility is re-verified once more against `scratchMix`, belt and
   suspenders.
4. `RollTacticalWindowUseCase.rollForward(mix: scratchMix, ..., context:
   scratchContext)` runs — every component's materializer call, and the
   single `SchedulingPipeline.propose`/`AcceptScheduleProposalUseCase.accept`
   call, all against `scratchContext`.
5. **On any throw** (a preflight-missed materializer error, e.g. Stage E
   stimulus validation): the function propagates the error immediately.
   `scratchContext` is never saved and simply falls out of scope. Nothing
   it inserted was ever visible to any other context, and it is discarded
   wholesale — not `rollback()`, just never persisted.
6. **On success**: `scratchContext.save()` — one call, the entire
   mixed-modality batch (every component's new week's Sessions/Days/
   Blocks/Prescriptions, plus the merged schedule) committed together as
   a single, atomic SwiftData transaction.
7. **Caller-side freshness**: for every `ProgramInstance` that actually
   rolled (collected from `scratchMix.orderedComponents.compactMap
   { $0.programInstance?.persistentModelID }`), the caller's own `context`
   explicitly re-fetches that instance by ID. This refreshes its cached
   `.sessions` in place (proven safe — see §2).

## 2. Why unrelated pending state is safe

The scratch context is constructed fresh for this one call and discarded
identically for every failure path. It never shares in-memory pending
state with the caller's context — SwiftData's identity map is
per-`ModelContext`, not per-container. Empirically verified (five
standalone `swift` scripts run against a throwaway `ModelContainer`
before writing any production code):

- A sibling context's uncommitted work is invisible to another context
  holding the same objects, until that sibling explicitly saves *and* the
  other context explicitly re-fetches the specific object by ID.
- Re-fetching a *root* object refreshes that object's own scalar/
  to-one properties, but does **not** cascade freshness to an
  *already-cached, nested* relationship collection reached through it —
  that nested object must be independently, directly re-fetched by its
  own ID (proven with a GrandParent→Parent→Child chain: refetching
  GrandParent left `.parent.children` stale; refetching Parent directly
  did not).
- `ModelContext.processPendingChanges()` does **not** solve the
  nested-staleness problem either (tested directly, confirmed
  insufficient).

This is why `AdvanceTacticalWeekUseCase.advance` re-fetches each affected
`ProgramInstance` *directly*, not merely the root `phase` — `ProgramInstance
→ sessions` is exactly a one-level relationship (directly analogous to
the Parent→Child probe, which *did* refresh correctly on direct refetch),
so this fix is sufficient and mechanical: nothing reassigns
`TrainingMixComponent.programInstance` or `TrainingPhase.primaryInstance`
during a roll — only new `Session`s are added under an *existing,
unchanged* `ProgramInstance` — so there is no deeper nested-staleness
chain to worry about here.

The mandatory scenario (D-10R6-4) is proven directly:
`MixedModalityTacticalAtomicityTests
.testUnrelatedPendingMutationSurvivesAndRetryAfterFixingBlockerAdvancesExactlyOnceForEveryComponent`
inserts an unrelated, unsaved `Goal` (U) on the caller's context, then
drives a real `AdvanceTacticalWeekUseCase.advance` call where Hypertrophy
materializes successfully into the scratch context and Functional Fitness
then throws (`FunctionalFitnessMaterializationError.stimulusValidationFailed`,
forced via an empty candidate pool — a genuine, preflight-blind Stage E
failure, not a preflight result). After the throw: U still exists,
unchanged, in the caller's context (`context.hasChanges` still true, U
still fetchable by ID); neither component's tactical week advanced
(`currentMaterializedWeekIndex` still 0 for both, no Week 2 sessions for
either). Retrying with the blocker fixed produces exactly one Week 2 for
every eligible component, and U is still there, still untouched.

## 3. Autosave behavior

`PersistenceController.makeAppContainer()`/`makeInMemoryContainer()` set
no explicit `autosaveEnabled` override, so the app's real, long-lived
`container.mainContext` retains SwiftData's default (`true`). This is
irrelevant to correctness here because **the caller's shared context is
never mutated during a tactical advance at all** — every insert happens
against the scratch context, which itself has `autosaveEnabled = false`
explicitly set. There is no window, at any point during the attempt, in
which either context holds a partially-materialized mixed-modality week
that any autosave trigger (scene-phase change, backgrounding, an
unrelated `.save()` elsewhere) could persist. The only thing that can
ever commit the scratch context's contents is this method's own single,
explicit `scratchContext.save()` call after every component has already
succeeded.

## 4. Atomic advancement invariant

Proven directly: `testSuccessfulAdvanceRollsHypertrophyAndFunctionalFitnessTogetherInOneCall`
(both components roll in one call, one scheduling pass — every new
session for both components has a real `Day`, i.e. was placed by the same
`SchedulingPipeline.propose` call), plus the failure/retry scenario in
§2 above (all-or-nothing, proven both ways). Existing
`AdvanceTacticalWeekUseCaseTests.testMixedModalityGateWithholdsUntilEveryComponentTerminalThenRollsCoherently`
(unchanged, still green) continues to prove the withholding half of the
same invariant for two Hypertrophy-shaped components.

## 5. Preflight behavior

`TacticalAdvancementPreflight.check(mix:)` iterates every eligible,
non-exhausted, rollForward-managed component. For `.functionalFitness`,
if any active block template requires recent exposure and
`FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:
instance)` is empty, it returns
`.functionalFitnessExposureHistoryUnresolvable(componentID:)`. For
`.interval`, checked **per block template** (not "any one resolves"
— a mix of gated and ungated blocks in the same instance must not let one
resolvable block mask another genuinely unresolvable one): if a block
template requires the previous week's successful-completion outcome and
`IntervalWeekContextBuilder`'s resolved context has `previousOutcome ==
nil`, it returns `.intervalWeekContextUnresolvable(componentID:)`.
Neither branch re-runs the real materializer or simulates Stage
D/E — Functional Fitness's stimulus validation is deliberately *not*
preflighted (per D-10R6-6, "do not simulate the entire materialization
process twice"); a stimulus-validation failure is still caught safely by
the atomic scratch-context discard, just not pre-empted.

Proven: `testPreflightBlocksFunctionalFitnessAdvanceBeforeAnyComponentIsMutated`
and `testPreflightBlocksIntervalAdvanceBeforeAnyComponentIsMutated` — in
both, a sibling Hypertrophy component that would have succeeded on its
own is confirmed to have zero new sessions after the blocked attempt,
proving the block happens before *any* component is touched, not just the
gated one.

## 6. Functional Fitness context implementation

`RollTacticalWindowUseCase` (both `materializeFirstWindow` and
`rollForward`) now computes `exposureHistory` inline, at the point of the
FF materializer call, as
`FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:
instance)` — the real `instance` in scope for that specific component,
every time. `TacticalMaterializationContext.functionalFitnessExposureHistory`
was **removed** — it was a static field that no real caller ever
populated (confirmed: zero non-default references anywhere in the
codebase before this change) and could not have correctly represented
per-instance, per-call-time history in a mixed-modality loop anyway.
`FunctionalFitnessExposureHistoryBuilder` itself is untouched — this
stage only wires an already-correct, already-tested engine into the real
path for the first time.

`functionalFitnessCandidateExercises` (a genuinely global, caller-scoped
pool, unlike per-instance exposure history) was already correctly
threaded through `TacticalMaterializationContext` — but two of the three
real production call sites (`PhaseDetailViewModel.advanceTacticalWeek`/
`.startNextHypertrophyPhase`) never populated it, defaulting to `[]`.
Both now pass the same real, unfiltered `Exercise` fetch already used for
`strengthCandidateExercises` — "the same authoritative unfiltered-fetch
pattern already proven for Strength" (D-10R6-7). `SeedAnnualPlanJourney`
already did this correctly and needed no change.

Proven: `testFunctionalFitnessExposureHistoryIsRealAndGatesCorrectly`
— week 0 legitimately empty; skipped (not completed) still empty and
still gates; a genuinely completed session with a real
`FunctionalFitnessResult` produces real, non-fabricated history
(`history.count == 1`, exactly the one real result) and unblocks the real
advance.

## 7. Interval resolver implementation

New file `TrainingOS/Application/UseCases/IntervalWeekContextBuilder.swift`.
`IntervalWeekContextBuilder.build(instance:weekIndex:) ->
(WorkoutBlockTemplate) -> IntervalMaterializer.WeekContext` — for
`weekIndex == 0`, always returns an empty `WeekContext` (nothing precedes
it). For `weekIndex > 0`, it finds `weekIndex - 1`'s real materialized
`WorkoutBlock` for the *same* `WorkoutBlockTemplate` (matched via
`IntervalPrescription.sourceWorkoutBlockTemplate`, already an existing,
tested field), and if that block has a real `IntervalResult` with at
least one real `IntervalRepResult`, derives:

- `previousActualIntervalCount` = the real count of logged reps.
- `previousActualWorkDurationSeconds`/`WorkDistanceMeters`/
  `RecoveryDurationSeconds` = the average of each rep's own real actual
  value (a genuine summary statistic over real data, not fabricated).
- `previousOutcome` = `IntervalProgressionEngine.evaluateSessionOutcome`
  (already existing, already tested, previously unused in production)
  called with the real completed/total counts and the real session-level
  RPE.

**Disclosed, deliberate gap**: `previousActualZone` is always `nil`.
`IntervalRepResult` only ever records a raw `averageHeartRate` (bpm); no
persisted per-user bpm→`HeartRateZone` mapping exists anywhere in the
domain model, and inventing one (an arbitrary threshold table) would be
exactly the "ambiguous training rule" CLAUDE.md rule 10 forbids, and
exactly what D-10R6-8 says not to do. `IntervalProgressionEngine
.resolveIntensity` already has a fully defined, pre-existing fallback for
a `nil` zone (falls back to the configured `startZone`/calendar
progression), so this is a safe, load-bearing gap, not a fabrication —
documented as known debt, same discipline as the equipment gap.

Proven: `testIntervalWeekContextEmptyAtWeekZeroAndRealAtWeekOnePlus` —
week 0's resolved context has `previousOutcome == nil`; after a real
completed week 0 (4/4 reps, all `wasCompletedAsPrescribed`, no RPE
ceiling configured → `.progress`), the real advance materializes week 1
with `intervalCount == 5` — a genuinely derived, non-fabricated
progression (the configured priority step's `+1` applied to the real
`.progress` outcome), not a frozen or hand-computed value.

## 8. First-window/rollForward parity

Both `materializeFirstWindow` and `rollForward` call the exact same two
functions (`FunctionalFitnessExposureHistoryBuilder.build`,
`IntervalWeekContextBuilder.build`) with the real `instance`/`weekIndex`
in scope — no divergent implementation. Proven directly:
`testInitialMaterializationUsesTheSameFunctionalFitnessAndIntervalPolicyAsRollForward`
confirms both a gated FF component and a gated Interval component
materialize their real week 0 without throwing, despite
`requiresRecentExposureToProgress`/`requiresSuccessfulCompletionToProgress`
both being `true` — parity with `rollForward`'s own week-0 legitimacy.

## 9. Equipment-profile plumbing — DEFERRED (D-10R6-11/D-10R6-12)

**What exists today**: `UserProfile.equipmentIncrements: [String: Double]`
— a flat map keyed by `Exercise.equipment`'s raw string (e.g.
`"barbell": 2.5`), already correctly consumed in three places for the
HypertrophyV2 double-progression path (`userProfile?.equipmentIncrements
[exercise.equipment] ?? 2.5`).

**What is missing**: anything matching `EquipmentProfile`'s own shape —
a real `EquipmentType` (which physical equipment family a slot/exercise
actually uses), a real `RoundingRule`, a real `bodyweightKg` for
`.bodyweightPlusExternal`. No `@Model` type, no field on `UserProfile` or
any other persisted entity, stores any of these. Additionally,
`EquipmentProfile` is architecturally **one value for an entire week's
materialization**, not resolved per exercise/per slot — a pre-existing
simplification this stage was explicitly told not to redesign.

**Why the partial fix was rejected**: deriving only `smallestIncrementKg`
from `userProfile.equipmentIncrements["barbell"]` while keeping
`equipmentType: .barbell`/`.roundingRule: .nearest`/`bodyweightKg: nil`
hardcoded would still construct an `EquipmentProfile` that falsely claims
the user's actual equipment/training environment is known — it replaces
one fabricated number with a different, real number, inside a
still-fabricated structure. Per explicit product decision, that is worse
than the current obvious placeholder, not better: "it would turn an
obvious placeholder into a more convincing but still incorrect
representation."

**What remains, unchanged**: `PhaseDetailViewModel.advanceTacticalWeek`/
`.startNextHypertrophyPhase` both still construct
`EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)`
exactly as before Stage 10R.6 — now with an explicit code comment marking
it as a known domain gap and pointing at this report. No new hardcoded
default was introduced, and the value was not "improved."

**Does this affect 10R.6A/B/C correctness?** No. `EquipmentProfile` is
used only for weight-rounding math inside Strength's `.rmBased`/
`.linkedToPairedSlot` load rules and deload — it has zero interaction
with the atomic transaction boundary, the Functional Fitness exposure
history, or the Interval `WeekContext` resolver. Regression guard:
`testAdvanceStillUsesExactlyTheCallerSuppliedEquipmentProfileNoNewInferenceIntroduced`
proves a deliberately distinctive, caller-supplied `EquipmentProfile`
(`.dumbbell`, 1.0kg increment — not the usual default) still flows
through `rollForward` completely unchanged end to end, with no new
equipment inference, no per-exercise lookup, and no silent substitution
introduced by this stage's changes.

**Future domain capability required to remove this gap** (not designed
or built now, per explicit instruction): a real Training Environment /
Equipment Profile domain model — user-selectable environments
(Commercial Gym / Home Gym / Travel / Minimal Equipment), each with a
real equipment inventory and loading constraints (barbell + plates +
smallest achievable increment, available dumbbell weights, kettlebells,
cable stack, machines, pull-up bar, rack, bench, bands, cardio equipment,
bodyweight availability), consumed by exercise resolution/substitution
alongside slot intent and the selected exercise — a real domain model,
not another dictionary of magic keys.

## 10. Scheduler behavior

Unchanged in spirit, still one call per attempt:
`RollTacticalWindowUseCase.rollForward` still collects every eligible
component's newly-materialized sessions into one `[ScheduledProgramInput]`
array across its per-component loop, then calls
`SchedulingPipeline.propose(mix:inputs:constraints:)` exactly once with
the complete batch, then `AcceptScheduleProposalUseCase.accept` once. The
only thing Stage 10R.6A changed is *which* `ModelContext` this all runs
against (the scratch context) — never per-component independent
scheduling. Proven: every new session for both components in
`testSuccessfulAdvanceRollsHypertrophyAndFunctionalFitnessTogetherInOneCall`
has a real `Day` (i.e., was placed), confirming one shared scheduling
pass saw both components' output together.

## 11. Failure rollback behavior

No `rollback()` call anywhere in the codebase (still zero call sites,
confirmed both before and after this stage). On failure, the scratch
context — which by construction holds nothing but this one attempt's own
mutations — is simply never saved and falls out of scope. This is
strictly safer than a scoped rollback would be, because there is nothing
in it to selectively undo in the first place.

## 12. Retry behavior

Proven directly in
`testUnrelatedPendingMutationSurvivesAndRetryAfterFixingBlockerAdvancesExactlyOnceForEveryComponent`
— after a failed attempt, retrying `AdvanceTacticalWeekUseCase.advance`
with the blocker fixed (real FF candidates supplied) produces `.advanced`
and exactly one Week 2 for every eligible component (Hypertrophy: 3 real
sessions; Functional Fitness: 1), not a duplicate or partial set.

## 13. Idempotency behavior

Unchanged, preserved. `AdvanceTacticalWeekUseCase.advance` still
re-derives eligibility fresh at invocation time via
`TacticalWeekCompletion.canAdvanceTacticalWeek` (now checked twice — once
against the caller's context, once again against the scratch context's
freshly-fetched `scratchMix`, belt and suspenders). Every existing
idempotency test in `AdvanceTacticalWeekUseCaseTests`
(`testRepeatedImmediateAdvanceDoesNotAdvanceTwice`, the full
`testMixedModalityGateWithholds...` repeated-call assertion, etc.)
remains green with zero modification.

## 14. Exhausted-component behavior

Unchanged, preserved — `TacticalAdvancementPreflight` and
`RollTacticalWindowUseCase.rollForward` both still exclude an already-
exhausted component from the eligible set the same way they always did
(`TacticalWeekCompletion.isInstanceExhausted`/the definition-bounds
`continue` guard); an exhausted component is never resurrected and never
blocks a still-progressing sibling. No new code touches this path.

## 15. Calibration-edge-case status

Not touched, per D-10R6-13 — no code path introduced or modified by
10R.6A/B/C reaches the mid-mesocycle-substitution → uncalibrated-exercise
edge case differently than before. Still documented debt only.

## 16. Files/types changed

**New files:**
- `TrainingOS/Application/UseCases/IntervalWeekContextBuilder.swift`
- `TrainingOS/Application/UseCases/TacticalAdvancementPreflight.swift`
- `TrainingOSTests/MixedModalityTacticalAtomicityTests.swift`

**Modified:**
- `TrainingOS/Application/UseCases/AdvanceTacticalWeekUseCase.swift` —
  isolated scratch-context transaction boundary, preflight call,
  caller-side re-fetch of affected `ProgramInstance`s.
- `TrainingOS/Application/UseCases/RollTacticalWindowUseCase.swift` —
  both `materializeFirstWindow` and `rollForward` now compute real FF
  exposure history and real Interval `WeekContext` inline via the new
  builders, instead of `{ _ in .init() }`/a static context field.
- `TrainingOS/Application/UseCases/StartPhaseUseCase.swift` —
  `TacticalMaterializationContext.functionalFitnessExposureHistory`
  removed (dead field, never populated by any real caller).
- `TrainingOS/Application/ViewModels/PhaseDetailViewModel.swift` — both
  write methods now pass real `functionalFitnessCandidateExercises`
  (reusing the same unfiltered `Exercise` fetch as
  `strengthCandidateExercises`); equipment placeholder left unchanged
  with an explicit known-gap comment.
- `TrainingOS.xcodeproj/project.pbxproj` — registers the three new files.

**Untouched, verified:** `IntervalMaterializer.swift`,
`FunctionalFitnessMaterializer.swift`,
`FunctionalFitnessExposureHistoryBuilder.swift`,
`SteadyStateMaterializer.swift`, `TacticalWeekCompletion.swift`,
`ProgramWeekGrouping.swift`, `SchedulingPipeline.swift`,
`ConcurrentScheduler.swift`, `PersistenceController.swift`.

## 17. Targeted tests

`MixedModalityTacticalAtomicityTests` (8 new tests, all passing):
successful multi-component advance in one call; preflight blocks FF
before any mutation; preflight blocks Interval before any mutation; the
full D-10R6-4 scenario (U survives a genuine mid-loop FF throw, retry
advances exactly once for every component); real FF exposure history
gates and unblocks correctly; real Interval `WeekContext` is empty only
at week 0 and derives a real `.progress` outcome at week 1+;
first-window/rollForward parity for both gated systems; no new equipment
inference introduced.

## 18. Full-suite result

`xcodebuild test` (iPhone 17 Simulator, iOS 26.5): **933 passed, 2
skipped (pre-existing), 0 failed**, total 935.

## 19. Stage 10R.1-10R.5 regression result

Explicitly re-ran as a targeted group before the full suite:
`AdvanceTacticalWeekUseCaseTests`, `MixedModalityOrchestrationTests`,
`TacticalPlacementBoundaryTests`, `TacticalPlanningOrchestrationTests`,
`StartNextHypertrophyPhaseUseCaseTests`, `HypertrophyProgramJourneyTests`,
`HypertrophyProgramGeneratorTests`, `HypertrophyBuiltInLibraryTests`,
`PhaseTransitionOrchestrationTests`, `SourceRMCalibrationTests`,
`LoadFirstProgressionIntegrationTests`, `StrengthMaterializerTests`,
`PlanHierarchyTests`, `ProgramInstanceExerciseSlotResolutionTests` — all
green, zero modification to any of their assertions. The full-suite run
confirms this across the entire remaining suite (`EquipmentProfileTests`,
`PowerliftingRegressionTests`, `LoadFirstOverlayEngineTests`, etc.) too.

## 20. Simulator result

Fresh build, install, and launch on iPhone 17 Simulator (iOS 26.5):
app launched successfully, confirmed running via `launchctl list`, and a
screenshot shows the real Today screen with real seeded data (Day 1,
Aerobic Base, Steady State 45 min) — `SeedAnnualPlanJourney`, one of the
real production call sites whose `TacticalMaterializationContext`
construction this stage touched (the removed `functionalFitnessExposureHistory`
field), still runs correctly end to end.

## 21. Newly discovered blocker/ambiguity

The equipment-profile domain gap (§9) — already known from the audit,
now formally confirmed and resolved by explicit product decision
(deferred, not fixed). No other new blocker was discovered.

## 22. Deferred

- 10R.6D (equipment-profile plumbing) — deferred by explicit product
  decision, documented as known debt (§9).
- The calibration mid-mesocycle-substitution edge case (D-10R6-13) — not
  touched, still documented debt only.
- `previousActualZone` in `IntervalWeekContextBuilder` — always `nil`,
  disclosed limitation (§7), pending a future bpm→zone domain concept
  that does not yet exist.
- Every item explicitly out of scope per the original audit request
  (Home Gym UX, equipment-management screens, new substitution rules,
  strategic-phase-transition changes, LongTermPlanner redesign, readiness
  changes) — untouched, as instructed.

---

**STOP. Not committed. Not pushed. Stage 10R.7 not begun.**
