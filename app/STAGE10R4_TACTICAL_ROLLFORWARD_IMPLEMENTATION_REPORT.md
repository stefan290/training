# Stage 10R.4A + 10R.4B + 10R.4C — Implementation Report

Real, safe, user-initiated tactical week advancement for the 3-Day Full
Body Family A reference program's Mesocycle 1/2/3 — built on the
evidence and locked decisions in
`STAGE10R4_TACTICAL_ROLLFORWARD_DESIGN.md`. Automated coverage +
Simulator smoke passed; committed and pushed per the user's explicit
"no manual acceptance loop" authorization.

## PRODUCT CONSTITUTION CHECK

**SOURCE AUTHORITY**: Week N+1's prescriptions (load, RIR, set
autoregulation, superset mechanics, deload routing) — entirely unchanged
by this stage. Every value materialized via the new production trigger
is produced by the exact same, already-accepted
`StrengthProgressionEngine`/`SourceCompatibleDeloadStrategy`/
`AutoregulationRatingResolver` code Stage 10R.1-10R.3 already proved
correct — this stage changes WHEN that content is created, never WHAT
it contains.

**TRAININGOS ORCHESTRATION**: "week terminal" (every real Session in
the week has a terminal `SessionStatus`), the derived `isInstanceExhausted`/
`canAdvanceTacticalWeek` queries, and the explicit, user-initiated
"Start Week N+1" action are all pure lifecycle/orchestration
infrastructure — never a persisted status, never automatic.

**TRAININGOS PRODUCT POLICY**: `.skipped`/`.missed`/`.abandoned` all
count as terminal for tactical week-completion purposes (Locked Decision
3) — a deliberate policy choice, so a skipped or missed workout can
never permanently trap a user inside one week — while contributing zero
fabricated performance data (no `SetResult`, rating, or PR is ever
manufactured for an unperformed session; missing-input progression falls
back to the exact already-accepted engine/source behavior, e.g.
`treatMissingRatingAsNoChange`).

**STRATEGIC BOUNDARY**: weekly `AdvanceTacticalWeekUseCase` never
invokes `LongTermPlanner`, never regenerates the strategic plan, and
never starts a new mesocycle — `StartNextHypertrophyPhaseUseCase`
remains the sole, still-user-initiated mesocycle-transition entry
point, now correctly gated on real tactical exhaustion rather than
"has materialized at all."

## 1. Final terminal-week rule

A tactical week is terminal for `(ProgramInstance, weekIndex)` when it
has at least one real materialized `Session` and every one of them has a
terminal `SessionStatus` — `.completed`, `.skipped`, `.missed`, or
`.abandoned` (Locked Decision 1). `.scheduled`/`.inProgress` remaining
anywhere in that week keeps it non-terminal. A week with zero
materialized Sessions is never terminal — nothing to resolve yet.
Terminal status carries no implication about whether useful performance
data exists.

## 2. Derived tactical state model

New `TacticalWeekCompletion` engine (`TrainingOS/Engines/TacticalWeekCompletion.swift`)
— pure, derived, never a stored field (Locked Decision 4):
- `isWeekTerminal(for:weekIndex:)`
- `hasNextSourceWeek(for:afterWeekIndex:)` — reads `ProgramDefinition
  .orderedWeeks` generically, works identically for M1/M2's 5 weeks and
  M3's 3.
- `currentMaterializedWeekIndex(for:)` — `ProgramWeekGrouping
  .nextWeekIndex(for:) - 1`, the same "current tactical week" concept
  `PhaseDetailViewModel` already used, made reusable.
- `isInstanceExhausted(for:)` / `canAdvanceTacticalWeek(for: ProgramInstance)`
- `canAdvanceTacticalWeek(for: TrainingMix)` — the mixed-modality gate:
  requires every component `rollForward` would actually attempt to
  advance (has instance+definition, non-`.steadyState`) to itself be
  ready — **deliberately excluding already-exhausted components from
  that "must be ready" set**, so one component finishing its whole
  mesocycle early can never permanently block a sibling that still has
  more weeks. This one interpretive judgment call (documented in the
  type's own doc comment) is the only place this stage read Locked
  Decision 2's "every component the rollForward call will advance"
  clause with a specific, reasoned scoping rather than a literal
  every-component-in-the-mix reading — flagged here explicitly rather
  than silently assumed.

Scoping is always via real `ProgramInstance`/`TrainingMixComponent`
relationships, never date/title inference — `TrainingWeek` itself
remains template-scoped, confirmed not per-instance, exactly as the
audit found; no architecture blocker was hit.

## 3. Safe advancement use-case contract

New `AdvanceTacticalWeekUseCase.advance(phase:asOf:ownerUserID:
performanceProfile:availability:userProfile:materializationContext:context:)`
(`TrainingOS/Application/UseCases/AdvanceTacticalWeekUseCase.swift`) —
the ONLY caller of `RollTacticalWindowUseCase.rollForward` this stage
wires into production. Re-derives `TacticalWeekCompletion
.canAdvanceTacticalWeek(for: mix)` fresh from `context` at invocation
time, every time — never trusts a caller-supplied boolean. Returns
`.notEligible` (no-op, not an error) if the re-check fails, `.advanced`
on a real roll, `.nothingRolled` in the (currently unreachable given the
gate) case `rollForward` itself found nothing to do.

## 4. Idempotency behavior

Proven directly: `testRepeatedImmediateAdvanceDoesNotAdvanceTwice` —
two immediate, consecutive `advance` calls with no intervening
completion produce exactly one materialized week, the second call
returning `.notEligible`. This works because the gate is purely derived
from persisted `Session.status`: immediately after a real roll, the new
week's Sessions are freshly `.scheduled` (not terminal), so the
re-check naturally fails on the very next call — no separate "already
rolled" flag needed anywhere.

## 5. Bounds/final-week protection

Two independent layers, both proven: (1) the caller-side gate itself
never offers/permits an advance once `isInstanceExhausted` is true; (2)
defense-in-depth inside `RollTacticalWindowUseCase.rollForward` itself
— `guard weeks.indices.contains(weekIndex) else { continue }` replaces
the previous silent `isDeload = false` fallback, so even a hypothetical
future caller that skipped the safe wrapper would fail safely (that
component simply skipped) rather than fabricating a bogus week past the
definition's real final week. Proven for all 3 recovered phase shapes:
`testMesocycle1FinalDeloadTerminalNoWeekSix` (no Week 6 past M1's real
Week 5 deload), `testMesocycle2FinalDeloadTerminalNoWeekSix` (same for
M2), `testMesocycle3FinalDeloadTerminalAtWeekThreeNoWeekFour` (no Week 4
past M3's real Week 3 deload — 2 rolls total, not the M1/M2 shape's 4,
directly proving `rollForward` is not hardcoded to a 5-week structure).

## 6. Skipped/missed/abandoned behavior

`TacticalWeekCompletionTests` proves all 8 required cases directly:
completed+skipped+completed terminal, completed+missed+completed
terminal, all-other-terminal-plus-one-abandoned terminal, one
`.scheduled` remaining not terminal, one `.inProgress` remaining not
terminal, and — critically — that terminal-but-unperformed Sessions
carry zero `WorkoutBlock`/`ExercisePrescription`/`SetResult` (nothing
fabricated), confirmed by direct inspection of the fixtures themselves
(never populated) rather than by any special-case code in
`TacticalWeekCompletion`, which only ever reads `Session.status`. Every
skip-driven test in `AdvanceTacticalWeekUseCaseTests` (the large
majority) exercises this same policy in a real, end-to-end production
path.

## 7. Mixed-modality gate

`testMixGateWithheldWhenOneComponentNotTerminal`/
`testMixGateAvailableWhenEveryComponentTerminal` (unit-level) and
`testMixedModalityGateWithholdsUntilEveryComponentTerminalThenRollsCoherently`
(full integration, two real Hypertrophy-configured components) prove:
one component terminal + another not -> withheld, neither rolls; both
terminal -> one call rolls both coherently in the same
`SchedulingPipeline.propose` pass; a repeated call afterward does not
advance either a second time. `testExhaustedComponentDoesNotBlockAStillProgressingSibling`/
`testMixGateFalseWhenEveryComponentExhausted`/
`testSteadyStateComponentNeverGatesOrBlocksTheMix` prove the 3 edge
cases (§2's scoping decision, universal exhaustion, Steady State
correctly excluded).

## 8. Mesocycle 1 Week 1 -> deload proof

`testMesocycle1FinalDeloadTerminalNoWeekSix` (4 real rolls via
`AdvanceTacticalWeekUseCase`, exhaustion + no-Week-6 confirmed);
`testMesocycle1SourceLoadAndRIRPreservedAcrossRealAdvancement` (Week 2
load = Week-1 anchor × 1.05, RIR 3, matching Stage 10R.1's own recovered
values, produced via the real trigger rather than direct
`StrengthMaterializer` calls); and
`testMesocycle1RealWalkthroughFullyLoggedThroughExhaustion` — the one
fully-logged, real-`SetResult`, real-feedback, real-`CompleteSessionUseCase`
walkthrough from Week 1 through the deload and confirmed exhaustion,
proving the complete real production path end to end, including that
Week 1's real logged data survives every subsequent roll.

## 9. Mesocycle 2 Week 1 -> deload proof

`testMesocycle2FinalDeloadTerminalNoWeekSix` (4 rolls, exhaustion, no
Week 6) and `testMesocycle2SupersetMechanicsAndCalibrationReuseAcrossRealAdvancement`
— proves the real 9-slot Day 1 (including the superset partner)
materializes via the real trigger, M2's calibration entered once at
Week 1 remains valid through every later roll with zero re-prompt
(`RequiredSourceCalibrationsUseCase.stillRequired` empty throughout),
and the confirmed superset-partner deload omission (zero
`SetPrescription`s) is preserved at the real, trigger-materialized
deload week.

## 10. Mesocycle 3 Week 1 -> deload proof

`testMesocycle3FinalDeloadTerminalAtWeekThreeNoWeekFour` (2 rolls only
— the critical phase-length proof) and
`testMesocycle3NoSupersetsAndShorterProgressionPreservedAcrossRealAdvancement`
— proves the real 7-slot Push day (no "Chest Isolation or Triceps," no
superset partner), Week 2's `1.0 × 1.05` load/RIR-3, and the deload's
day-position weight split (day 0 full weight, day 2 halved), all via the
real trigger, all matching Stage 10R.3's own recovered values exactly.

## 11. Source-progression regression proof

Every walkthrough test above doubles as regression proof: load factors,
RIR schedules, set baselines, rating-pairing relationships, superset
mechanics, and deload routing are asserted directly against the exact
already-accepted Stage 10R.1-10R.3 values at each real-trigger-
materialized week — this stage changed WHEN the next week is created,
never WHAT it contains.

## 12. Substitution persistence

`testSubstitutionMadeInWeekTwoPersistsIntoWeekThree` — a real
`SubstituteExerciseUseCase.substituteGoingForward` call made after Week
2 materializes automatically applies to Week 3, materialized later via
`AdvanceTacticalWeekUseCase` — zero weekly-copy plumbing needed, exactly
as the audit predicted (`SlotSelectionOverride` is instance-wide by
construction).

## 13. Calibration persistence

Proven inline within `testMesocycle2SupersetMechanicsAndCalibrationReuseAcrossRealAdvancement`
— M2's calibration, entered once at fixture creation (Week 1), remains
valid and un-re-prompted through Weeks 2, 3, 4, and the deload, all
materialized via real rolls.

## 14. Readiness interaction

Preserved unchanged, per Locked Decision (Readiness section) — this
stage made no change to `AutoregulationRatingResolver.previousWeekSetCount`
or `SetPrescription.isAdaptedAway`, and the already-audited
`READINESS_PROGRESSION_CONTRACT.md` §3 decision (source-prescribed count
feeds next-week autoregulation, never the adapted/performed count)
continues to govern every real roll performed by
`AdvanceTacticalWeekUseCase`, since it delegates entirely to the
unmodified `RollTacticalWindowUseCase.strengthSlotContext`.
No dedicated new readiness-specific test was added — the mechanism
itself was not touched, and the audit's own finding (already resolved,
not ambiguous) meant there was no open question this stage needed to
close with new coverage.

## 15. Scheduler/date behavior

Unchanged: `ConcurrentScheduler`/`SchedulingPipeline` remain the sole
placement authority, invoked identically inside `rollForward` as before
this stage. `AdvanceTacticalWeekUseCase` adds no date logic of its own
— it only decides WHETHER to call `rollForward`, never how dates are
computed. **One real, non-obvious lesson learned during this stage's own
test-writing** (not a production defect): `rollForward`'s `asOf`
parameter must genuinely represent "now" relative to the week actually
being rolled — reusing a stale, unshifted `asOf` across successive
test-only calls caused the scheduler to see every rolled week compete
for the identical 7-day window, which is genuinely infeasible, not a
bug in the scheduler. Documented directly in the test file's own
`rollDate(afterWeekIndex:)` helper doc comment for future maintainers.

## 16. LongTermPlanner boundary

`testAdvancingDoesNotChangeThePlanOrPhaseCount` — confirms a real roll
never changes `TrainingPlan.orderedPhases.count` or the plan's identity.
No production code in `AdvanceTacticalWeekUseCase`/`TacticalWeekCompletion`
references `LongTermPlanner` at all.

## 17. Next-mesocycle gate fix

`PhaseDetailViewModel.canStartNextHypertrophyPhase` now requires
`TacticalWeekCompletion.isInstanceExhausted(for: primaryInstance)`
instead of merely `!primaryInstance.sessions.isEmpty` — closing the
premature-transition bug the Stage 10R.4 audit found (a user could
previously reach "Start Metabolite Focus" after only Week 1 existed).
Proven by 6 new tests: cannot start M2 while M1 weeks remain, can start
M2 once M1's final deload is terminal, cannot start M3 while M2 weeks
remain, can start M3 once M2's final deload is terminal, no further
mesocycle offered once M3 is exhausted (M3 has no successor in
`HypertrophyProgramJourney.orderedPhaseTypes`), and the previously-
existing real M1->M2 transition still works end to end after the gate
was tightened (`testUserInitiatedMesocycleTransitionStillWorksAfterGateTightening`).
`AdvanceTacticalWeekUseCase` itself is proven to never start a new
mesocycle regardless of repeated exhausted-state calls
(`testAdvanceTacticalWeekNeverStartsTheNextMesocycleItself`).

## 18. Status policy

No new persisted field anywhere — no `TrainingWeek.status`, no
automatic `ProgramInstance.status`/`TrainingPhase.status` mutation on
exhaustion (Locked Decision 4, honored exactly). The pre-existing
`TransitionPhaseUseCase` mechanism (Stage 7, annual-plan level) is
completely untouched — this stage neither calls it nor changes its
behavior.

## 19. UI behavior

`PhaseDetailView` only — no new screen. A new `advanceTacticalWeekCard`
(mirrors `startNextHypertrophyPhaseCard`'s exact shape) shows "Week N
complete. [Start Week N+1]" only when `viewModel.canAdvanceTacticalWeek`
is true; hidden otherwise (both for a non-terminal current week and for
an exhausted final week). Tapping it calls `viewModel.advanceTacticalWeek(modelContext:)`
then reloads — Today is never manually pushed new Sessions; it reads
the same persisted queries as always and naturally sees the newly-
scheduled ones.

## 20. Persistence/crash recovery

Workout completion and week advancement remain fully separate
persistence events — `AdvanceTacticalWeekUseCase` is never called from
`CompleteSessionUseCase`. Proven directly: `testTerminalWeekPersistsAcrossRelaunchAndStillRollsExactlyOnce`
(terminal state survives a simulated relaunch, still rolls exactly
once) and `testRolledWeekNotEligibleAgainUntilItBecomesTerminalAfterRelaunch`
(a freshly-rolled, non-terminal week correctly remains ineligible after
a simulated relaunch, not just within the same session). If
`AdvanceTacticalWeekUseCase.advance` were to fail partway, nothing prior
(completed sessions, logged results, feedback) is ever mutated by it —
it only ever reads until the moment it calls `rollForward`, and
`rollForward`'s own materialization is entirely additive (new rows), so
a failure leaves the prior week's data exactly as it was, and the user
can simply retry "Start Next Week."

## 21. Files changed

**Production**: `TrainingOS/Engines/TacticalWeekCompletion.swift` (new),
`TrainingOS/Application/UseCases/AdvanceTacticalWeekUseCase.swift`
(new), `TrainingOS/Application/UseCases/RollTacticalWindowUseCase.swift`
(defense-in-depth bounds guard), `TrainingOS/Application/ViewModels/PhaseDetailViewModel.swift`
(tightened `canStartNextHypertrophyPhase` gate, new
`canAdvanceTacticalWeek`/`nextTacticalWeekNumber` state, new
`advanceTacticalWeek` write method), `TrainingOS/UI/Plan/PhaseDetailView.swift`
(new `advanceTacticalWeekCard`), `TrainingOS.xcodeproj/project.pbxproj`
(4 new file registrations).
**Tests**: `TrainingOSTests/TacticalWeekCompletionTests.swift` (new, 17
tests), `TrainingOSTests/AdvanceTacticalWeekUseCaseTests.swift` (new, 22
tests), `TrainingOSTests/StartNextHypertrophyPhaseUseCaseTests.swift`
(2 existing tests extended to reach real tactical exhaustion before
asserting the now-tightened gate, plus a new shared `skipToExhaustion`
helper).

## 22. Targeted tests

39/39 new tests passed on their own targeted runs (17
`TacticalWeekCompletionTests` + 22 `AdvanceTacticalWeekUseCaseTests`),
plus the 2 updated `StartNextHypertrophyPhaseUseCaseTests`.

## 23. Full-suite result

**895/895 passed, 0 failures, 2 pre-existing documented skips**
(unrelated mixed-modality scheduling limitation — the
`TacticalPlacementBoundaryTests` skips assessed but deliberately not
fixed in this stage, per the audit's own narrow-blocker verdict). Run
twice consecutively with `-parallel-testing-enabled NO` to confirm
stability, after fixing one genuine test-authoring bug caught by the
full-suite run specifically (§27).

## 24. Simulator result

Fresh install (uninstall + install + launch) — no crash, no fatal/
terminate log entries, the app renders the seeded Mesocycle 1 Starting
Weights screen exactly as before this stage. **Honest limitation, same
as every prior stage**: no UI-tap automation available in this sandbox,
so the literal "Start Week 2" button tap could not be performed live.
In its place, `testPhaseDetailViewModelOffersTheRealTacticalWeekAdvance`
drives the exact `PhaseDetailViewModel` state the button reads, proving
the gating/labeling wiring is correct. **A further, narrower, explicitly
disclosed limitation found while building this specific test**: a full
round-trip test through `viewModel.advanceTacticalWeek` itself (which
hardcodes `asOf: Date()`, correct production behavior) cannot be
reproduced in a fast synchronous unit test, since real production relies
on real wall-clock days elapsing between phase start and the user's
later tap — a synthetic fixture cannot fake that elapsed time without
either injecting a clock (a production-code change not authorized this
stage) or literally waiting days. The identical underlying `rollForward`
mechanism this ViewModel method calls is already proven directly, with
an explicitly-controlled `asOf`, by every other test in
`AdvanceTacticalWeekUseCaseTests` — this is a testing-technique
limitation, not an unproven code path.

## 25. Commit hash

See the chat response accompanying this file's own commit (this
document is part of that same commit, so it cannot self-reference its
own resulting hash).

## 26. Push/clean-tree confirmation

Reported in the chat response.

## 27. Remaining known gaps / newly discovered items

- **A real test-authoring bug caught by the full-suite run, not the
  isolated per-file run**: `testSubstitutionMadeInWeekTwoPersistsIntoWeekThree`
  originally called `ExerciseCatalog.makeAndInsert` twice (once inside
  the shared fixture helper, once redundantly in the test body),
  creating duplicate `canonicalName`-unique `Exercise` rows that failed
  a SwiftData save-time validation intermittently depending on full-
  suite execution context. Fixed by removing the redundant call. Not a
  production defect — pure test hygiene, caught and fixed before commit.
- The two pre-existing `TacticalPlacementBoundaryTests` `XCTSkip`s
  remain, exactly as before — assessed (§8 of the design doc) but
  deliberately not fixed, confirmed not a blocker to this stage's own
  mixed-modality wiring.
- The deload "which Week-1 actual set result" ambiguity remains
  unresolved, unchanged, untouched by this stage.
- `RollTacticalWindowUseCase.rollForward`'s underlying per-mix batching
  contract is unchanged — the safety this stage adds is entirely at the
  caller-gate layer (§2's scoping decision), not a signature change.
- Family C, other Family A configurations, load-first, and warm-up
  remain entirely unaddressed, per explicit instruction.

## 28. Implications for the future load-first overlay

Nothing in this stage's design assumes `.rmBased` progression
specifically — `TacticalWeekCompletion`'s queries operate purely on
`Session.status` and `ProgramDefinition.orderedWeeks`, with zero
knowledge of which `LoadRule` a given week's slots use. A future
load-first overlay (whatever `LoadRule` case it introduces) would
automatically be covered by this same "week terminal -> user taps ->
`AdvanceTacticalWeekUseCase` re-derives and rolls" lifecycle with no
changes needed here — the only thing that would matter to
`TacticalWeekCompletion`/`AdvanceTacticalWeekUseCase` is real Session
statuses and real week counts, both of which any new progression scheme
would still produce identically. The one place a load-first overlay
would need its own attention is `RollTacticalWindowUseCase
.strengthSlotContext`'s own progression-input resolution (already
generic across `LoadRule` cases per the Stage 10R.4 audit's own finding)
— unaffected, and out of this stage's scope to modify.
