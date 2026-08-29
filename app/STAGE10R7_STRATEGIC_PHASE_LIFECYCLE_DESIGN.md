# Stage 10R.7 — Strategic Phase Lifecycle: Audit / Design

**Status: audit/design only. Nothing implemented. Not committed, not
pushed.** Checkpoint `b5ba9fb` (Stage 10R.6) is the protected baseline;
nothing in it was touched. This document is read-only research —
no code changed while producing it.

Every claim below cites `file:line` against
`/Users/stefankedling/Desktop/training/app/`. Facts first, judgment calls
clearly marked as such, and every genuinely open question left open
rather than silently resolved.

---

## 1. Strategic hierarchy

`Goal → TrainingPlan → TrainingPhase → TrainingMix → TrainingMixComponent
→ ProgramInstance → (derived tactical weeks) → Session`

### Goal (`Domain/Entities/Goal.swift:14-70`)
- Fields: `id`, `ownerUserID`, `user`, `primaryType: GoalType`, `secondaryObjectives`, `targetDate`, `milestoneDate`, `bodyCompositionDirection`, `preferences`, `createdAt`, `status: GoalStatus`.
- Owned by `User` (`User.addGoal`, `User.swift:45`). Owns `TrainingPlan` via `plans` (cascade).
- `GoalStatus` (`Enums.swift:21-25`): `.active/.achieved/.abandoned`, defaults `.active` (`Goal.swift:50`).
- **No use case anywhere mutates `Goal.status` after construction** — `grep -rn "goal\.status\s*="` across the whole repo returns zero hits. `.achieved`/`.abandoned` are unreachable states today.
- Creation: only `SeedDataProvider.swift:71` and `SeedAnnualPlanJourney.swift:60`, both seed code, direct constructor calls (no "CreateGoalUseCase" exists).

### TrainingPlan (`Domain/Entities/TrainingPlan.swift:9-64`)
- Fields: `id`, `goal`, `status: PlanStatus`, `createdAt`, `supersedes`, `lineageID`. Computed: `orderedPhases` (sorted by `sortIndex`).
- `PlanStatus` (`Enums.swift:30-34`): `.draft/.active/.superseded`, defaults `.draft` (`TrainingPlan.swift:34`) but every real construction site passes `status: .active` explicitly (`AcceptStrategicPlanUseCase.swift:45`, `SeedDataProvider.swift:75`) — `.draft` is a reachable-in-theory, never-used-in-practice state.
- `.active → .superseded` only via `AcceptStrategicPlanUseCase.accept(..., supersedes:)` (`AcceptStrategicPlanUseCase.swift:42`) — opt-in, never exercised by any real caller.
- Creation/only caller: `AcceptStrategicPlanUseCase.accept`, itself called only from `SeedAnnualPlanJourney.swift:68`.

### TrainingPhase (`Domain/Entities/TrainingPhase.swift:29-138`)
- Fields: `id`, `plan`, `type: PhaseType`, `sortIndex`, `startDate`, `endDate`, `priorityRule`, `status: PhaseStatus`. Computed: `primaryInstance`, `secondaryInstances`, `selectedTrainingMix`, `recommendedTrainingMix`, `activeTrainingMix(asOf:)`.
- `PhaseStatus` (`Enums.swift:51-57`): `.planned/.active/.completed/.paused/.abandoned`, defaults `.planned`.
- Every real mutation, exhaustively:
  - `.planned → .active`: `StartPhaseUseCase.swift:126`, guarded on `phase.status == .planned` (line 105).
  - `.active → .completed`: `TransitionPhaseUseCase.swift:75`, guarded on `outgoingPhase.status == .active` (line 66).
  - `.planned → .abandoned`: `AcceptStrategicPlanUseCase.swift:40`, only for a superseded plan's still-planned future phases.
  - `.paused` is never set anywhere.
- Two structurally different "create a phase" mechanisms exist (see §5 — this is the crux of the whole audit):
  1. `AcceptStrategicPlanUseCase.swift:50-56` — creates **every** `ProposedPhase` from `LongTermPlanner.proposeStrategicPlan`/`.reviseStrategicPlan` up front, all `.planned`, in one loop, at strategic-plan-acceptance time.
  2. `StartNextHypertrophyPhaseUseCase.swift:91-93` — creates **one new** `TrainingPhase` (same `type` as its predecessor, `status: .active` immediately, no `.planned` interim), appended via `plan.addPhase` at whatever `sortIndex` the plan's current `phases.count` happens to be **at the moment the user taps the button** — not planned in advance.

### TrainingMix (`Domain/Entities/TrainingMix.swift:21-65`)
- Fields: `id`, `kind: TrainingMixKind (.recommended/.selected)`, `name`, `phase`, `validFrom`, `validUntil`, `preferenceStrength`. No separate status field — `kind` + validity window together encode lifecycle.
- `kind → .selected`: `StartPhaseUseCase.swift:116` (promotion the instant a phase actually starts with it — whether the top system recommendation or a user-chosen alternative). `validUntil` closed by `SwitchTrainingModalityUseCase.swift:36` on a mid-phase modality switch. Never deleted.

### TrainingMixComponent (`Domain/Entities/TrainingMixComponent.swift:29-83`)
- No status field at all — lifecycle is implicit in `programInstance == nil` (not yet instantiated) vs. set (instantiated), the latter only ever assigned directly (`StartPhaseUseCase.swift:149`, `StartNextHypertrophyPhaseUseCase.swift:136`), never through an "add" helper.
- Own `priority`/`frequency`/etc. fields duplicate similar concepts on `ProgramInstance` (e.g. both have a `priority`) — the type's own doc comment (lines 22-27) admits these are "an application-layer invariant, not enforced by a sync mechanism."

### ProgramInstance (`Domain/Entities/ProgramInstance.swift:10-175`)
- Fields include `status: PhaseStatus` — **reuses the exact same enum as `TrainingPhase`**, not a distinct type.
- Real mutations: set at construction (`.active` in `StartPhaseUseCase.swift:145`/`StartNextHypertrophyPhaseUseCase.swift:95`, `.planned` in `HypertrophyProgramJourney.swift:60`); the **only** post-construction mutation anywhere is `TransitionPhaseUseCase.swift:77`, which blanket-sets every one of the outgoing phase's instances to `.completed` as a side effect of the phase-level transition.
- **Tactical week-by-week progress is never reflected in this field at all** — `TacticalWeekCompletion.swift`'s own doc comment (lines 3-9) locks this down explicitly: "no automatic `ProgramInstance.status`/`TrainingPhase.status` mutation" from weekly rollforward. `ProgramWeekGrouping`/`TacticalWeekCompletion` derive everything (current week, exhaustion) purely from `Session.status` + `ProgramDefinition.orderedWeeks`, never from `ProgramInstance.status`.

### Session — governed entirely by `Day`/`WorkoutBlock`/`SessionStatus`; already exhaustively covered by Stage 10R.4-10R.6's own design docs, unchanged here.

---

## 2. Current real production lifecycle (what actually runs, end to end, for a real user today)

**None of it.** Every single step from `Goal` through `AcceptStrategicPlanUseCase` through the first `StartPhaseUseCase.start` call is reachable, in the shipped app, **only** via `SeedAnnualPlanJourney.seed(...)`, invoked unconditionally (no `#if DEBUG`) from `TrainingOSApp.init()` (`App/TrainingOSApp.swift:24-31`) the first time the store has zero `User` rows. There is no onboarding screen, no "create a goal" screen, no "accept this plan" screen anywhere in `TrainingOS/UI/`.

The only things a **real user action** can do after that one-time seed has run:
- `SourceRMCalibrationViewModel` → `StartPhaseUseCase.materializeOnceCalibrationComplete` (a narrower sibling of `.start`, calibration-gated) — reachable from the real "Set your starting weights" screen.
- `PhaseDetailViewModel.advanceTacticalWeek` → `AdvanceTacticalWeekUseCase.advance` — tactical week rollforward, Stage 10R.4-10R.6.
- `PhaseDetailViewModel.startNextHypertrophyPhase` → `StartNextHypertrophyPhaseUseCase.start` — mesocycle succession (see §5/§6).

`AcceptStrategicPlanUseCase.accept` and `TransitionPhaseUseCase.transition` — the two use cases that actually operate at the `TrainingPlan`/`TrainingPhase` level — have **zero** real UI callers. Each has exactly one call site in the entire repository, and it is the same file: `SeedAnnualPlanJourney.swift` (lines 68 and 158 respectively).

## 3. Seed-only lifecycle behavior

`SeedAnnualPlanJourney.seed` (`Application/Seed/SeedAnnualPlanJourney.swift`, 169 lines) does, in order:
1. Backdates `planAcceptedAt` 84 days (`.muscleGain`'s own 12-week `PhaseDurationDefaults`, not an arbitrary guess) so phase 1's real planner-computed `endDate` lands "today" (line 59).
2. Constructs `Goal` directly (line 60), `user.addGoal`.
3. `LongTermPlanner.proposeStrategicPlan` (line 67) → `AcceptStrategicPlanUseCase.accept` (line 68) — real production use cases, their only real callers.
4. Guards `plan.orderedPhases.count >= 4` (line 69) — a real, loud seed-time failure if the planner ever proposes fewer.
5. `StartPhaseUseCase.start` for phase 1 (lines 112-116) — real use case, real materialization.
6. Fabricates "a little logged history" by calling `RecordSetResultUseCase.recordSet` **directly** (line 124) rather than through `LogSetUseCase` (the type whose own doc comment says it is "the only entry point... should call — never `RecordSetResultUseCase` directly," `LogSetUseCase.swift:4-9`). No Session is ever driven to `.completed` via `CompleteSessionUseCase` in this step — only individual `SetResult`s are fabricated on top of otherwise-`.scheduled` sessions before the phase is later force-completed by `TransitionPhaseUseCase` anyway.
7. `LongTermPlanner.proposeTrainingMix` for phase 2, picks recommended + a different selected candidate, **directly sets `selected.mix.kind = .selected`** (line 156) — a raw field mutation, not through any use case.
8. `TransitionPhaseUseCase.transition(from: phase1, toNextPhaseWithMix: ...)` (lines 158-162) — real use case, its only real caller.
9. Leaves `phase3+` exactly `.planned`, nothing materialized — "no future fabrication," by design.

**Crucial scoping fact, confirmed by direct reading of the test suite that exercises this exact path** (`PhaseTransitionOrchestrationTests.swift:91-194`): `phase1` here is **the entire Hypertrophy phase treated as a single strategic unit** — `TransitionPhaseUseCase` completes `phase1.primaryInstance` (a single Mesocycle-1-configured `ProgramInstance`) directly, with no mesocycle-level progression through `StartNextHypertrophyPhaseUseCase` ever occurring first. **Neither the seed nor any test anywhere exercises `StartNextHypertrophyPhaseUseCase` and `TransitionPhaseUseCase` in combination on the same phase.** This interaction is completely untested — see §6 Example scenarios below.

`DebugAcceptanceFixturesUseCase` (`Application/Seed/DebugAcceptanceFixturesUseCase.swift`) is unrelated to the strategic lifecycle — it only adds ad-hoc, `programInstance: nil` Sessions for manual Today-screen testing, is `#if DEBUG`-gated at its call site (`UI/Today/TodayView.swift:62-77`), and never touches `Goal`/`TrainingPlan`/`TrainingPhase`.

## 4. `AcceptStrategicPlanUseCase` behavior

- **Inputs**: `StrategicPlanProposal` (goal + `[ProposedPhase]` + feasibility + explanation, non-persisted planner output), `context`, `decidedAt`, optional `supersedes`/`lineageID`/decision metadata.
- **Creates**: one `TrainingPlan`; **every** phase in `proposal.phases` as a `.planned` `TrainingPhase` in one loop (`AcceptStrategicPlanUseCase.swift:50-56`) — not just phase 1; one `PlannerDecision`. **No `TrainingMix`, no `ProgramInstance`, ever.**
- **Statuses set**: new plan `.active`; every new phase `.planned`; (if superseding) old plan `.superseded`, old plan's still-`.planned` phases `.abandoned`.
- **First tactical materialization**: none — that is always a separate, later `StartPhaseUseCase.start` call.
- **Calibration**: not referenced at all in this file.
- **Scheduling**: not referenced at all in this file.
- **Persistence**: never calls `context.save()` — left entirely to the caller (confirmed: `SeedAnnualPlanJourney` never explicitly saves either; relies on default SwiftData autosave).
- **Failure semantics**: exactly one throw point (`.infeasible`), and it is the *first* statement in the function — nothing has been inserted yet at that point, so there is no partial-insert failure mode intrinsic to this function today. An empty `proposal.phases` array is not guarded against; it silently produces a zero-phase plan.
- **Idempotency**: **none.** Calling `accept` twice for the same `Goal` (without `supersedes:`) creates two independent, both-`.active` `TrainingPlan`s attached to the same `Goal`. Nothing anywhere checks "does this goal already have an active plan."
- **Production-ready or test-only infrastructure?** Judgment call: this is well-built, already-tested engineering (`AnnualPlanOrchestrationTests.swift` exercises it directly), but it has never been exposed to a real, non-seed caller, has no idempotency guard, and never saves — it reads as **correct but unintegrated** infrastructure, not yet a finished production feature.

## 5. `TransitionPhaseUseCase` behavior — and its relationship to mesocycle transitions

`TransitionPhaseUseCase.transition(from:toNextPhaseWithMix:asOf:...)` (`TransitionPhaseUseCase.swift:48-97`, Stage 7):
1. Requires `outgoingPhase.status == .active`, else throws `.outgoingPhaseNotActive`.
2. Finds the next phase via `plan.orderedPhases[currentIndex + 1]` — **it does not create a `TrainingPhase`.** It requires one to already exist (i.e., it assumes `AcceptStrategicPlanUseCase` already ran and pre-created the whole sequence). Throws `.noNextPhaseInPlan` if none exists.
3. Sets `outgoingPhase.status = .completed` and **every one of its `programInstances[].status = .completed`**, unconditionally, at line 75-78 — **before** the line that can actually fail.
4. Inserts one `PlannerDecision`.
5. Calls `StartPhaseUseCase.start(phase: nextPhase, mix: nextMix, ...)` — the same entry point every phase start uses. `nextMix` must already be selected/constructed by the caller (this use case has no opinion on where that mix comes from).

**This is a real, currently-live atomicity gap, of exactly the shape Stage 10R.6 fixed at the tactical level, unfixed here at the strategic level**: steps 3 and 5 run directly against the caller's own context, with no isolation. If `StartPhaseUseCase.start` throws inside step 5 (e.g. `StartPhaseError.noExecutableComponents`), the function propagates that error — but the outgoing phase and every one of its instances are **already** marked `.completed`, permanently, in the caller's context. A caller that catches the error and, say, shows a retry UI would find: old phase completed, no new active phase, no executable Sessions for the user at all. **Confirmed live, not hypothetical** — nothing in the current implementation prevents this; it has simply never been exercised because `TransitionPhaseUseCase` has zero real callers today.

**Completion is not persisted/derived/inferred by anything else** — it is a single, explicit, direct field write, triggered only by this one use case being called. There is no mechanism today that decides *when* to call it. Nothing infers "should transition now" from dates or from `ProgramInstance` exhaustion — it is purely "whoever calls this use case has already decided the moment has come."

**Relationship to mesocycle transition (`StartNextHypertrophyPhaseUseCase`) — the central finding of this audit**: these are **two independent, non-communicating mechanisms that both create/mutate `TrainingPhase` rows in the same `TrainingPlan.orderedPhases` list**, and their interaction has never been tested:
- `TransitionPhaseUseCase` advances into an **already-existing, pre-planned** next phase (created by `AcceptStrategicPlanUseCase` up front).
- `StartNextHypertrophyPhaseUseCase` **creates a brand-new** `TrainingPhase` (same `type` as its predecessor) and appends it via `plan.addPhase` — which assigns `sortIndex = plan.phases.count` **at the moment of the button tap**, i.e. after whatever strategic phases already exist.

If a real strategic plan already has phase2 (a different, already-`.planned` `TrainingPhase`, e.g. a Fat Loss phase) sitting right after phase1 in `orderedPhases`, then the moment phase1's Mesocycle-1 instance becomes tactically exhausted, `PhaseDetailViewModel.canStartNextHypertrophyPhase`'s own gate (`nextPhase == nil`, `PhaseDetailViewModel.swift:173`) is **already false**, because `nextPhase` (`plan.orderedPhases[index+1]`) is already phase2 — **the "Start Metabolite Focus" button would never appear at all** in a plan that already has a real next strategic phase queued up. This gate was evidently designed and tested only against a plan shape where phase1 has no successor yet (see `PhaseDetailViewModel.swift:71-78`'s own comment: "the second half doubles as the idempotency signal") — it has never been exercised against a plan where `AcceptStrategicPlanUseCase` already pre-created a real phase2. **This is a genuine, unresolved design gap, not something this audit should silently patch.**

## 6. Exact phase-completion semantics today, worked examples

**Example A — Hypertrophy-only phase, one M1→M2→M3 sequence.** Not reachable as literally posed: in the current architecture, M1/M2/M3 are **three separate `TrainingPhase` rows** (per §1/§5), each created on demand by `StartNextHypertrophyPhaseUseCase`, not three mesocycles inside one `TrainingPhase`. So "the phase is complete" for M1's own `TrainingPhase` row is answered by `TacticalWeekCompletion.isInstanceExhausted(for: primaryInstance)` (final source-defined week terminal) — but that is a *derived tactical* fact, and nothing automatically calls `TransitionPhaseUseCase`/marks `TrainingPhase.status = .completed` for M1's row when it happens; the UI merely *offers* the "Start Metabolite Focus" button. M1's `TrainingPhase.status` stays `.active` forever unless a real strategic transition (not built here) later completes it.

**Example B — Mixed phase, Hypertrophy + Running (SteadyState), Hypertrophy finishes first.** `TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix)` (`TacticalWeekCompletion.swift:94-106`) already correctly withholds the mixed-modality tactical rollforward until every rollForward-managed component is ready — but SteadyState is explicitly *excluded* from that gate (materializes its whole block up front, Stage 10R.4/10R.6, D-10R6-10). Nothing today defines "is the whole `TrainingPhase` done" as a function of "all its components' `ProgramInstance`s are exhausted" — no code computes that at all. `TransitionPhaseUseCase` doesn't check instance exhaustion either; it only checks `outgoingPhase.status == .active`, i.e. it would happily complete a phase whose Running component still has scheduled, unexecuted Sessions if a caller told it to. **Confirmed: no existing behavior answers "is this phase actually done" for a mixed-modality phase — it is entirely undefined today**, not merely under-tested.

**Example C — SteadyState's whole-block materialization contributing to phase exhaustion.** SteadyState never re-materializes past its own generated block (Stage 10R.4's own documented limitation, `RollTacticalWindowUseCase.swift:74-81`) — once its Sessions are all terminal, there is genuinely nothing left to roll for it, so it can only ever "look done" once, never re-triggered. But there is still no code that reads this as an input to any phase-completion decision.

**Example D — Phase reaches its planned `endDate` boundary with incomplete Sessions.** No behavior exists for this at all. `TacticalWindowPolicy`/materializers never schedule *past* `phase.endDate` (Stage 10R.4/10R.5's own boundary tests, still green), but nothing watches wall-clock time relative to `endDate` and nothing forces a transition or flags the phase as behind. A phase can sit `.active`, past its own `endDate`, with unfinished Sessions, indefinitely — silently.

## 7. Next-phase activation behavior (what `TransitionPhaseUseCase` → `StartPhaseUseCase.start` actually does)

Traced directly from code, confirmed by `testPhaseTransitionCompletesOldPhaseStartsNextWithChangedModalityMixAndNeverMutatesHistory`: completes old phase + its instances; activates the next (already-`.planned`) phase (`.active`); instantiates every not-yet-instantiated component of the supplied `nextMix` into a brand-new `ProgramInstance` each (never continuing the old phase's instances — proven disjoint IDs); requests calibration only implicitly, by deferring materialization the same way `StartPhaseUseCase.start` always does for `.rmBased` families awaiting `SourceRMCalibration`; materializes week 0 for every immediately-executable component; schedules + accepts via the same `SchedulingPipeline`/`AcceptScheduleProposalUseCase` every other phase start uses; preserves the old phase's history byte-for-byte (proven: same `PerformanceProfile` id, same `SetResult`/`PersonalRecord` counts, same Session IDs/dates, same queryable `PlannerDecision`s). **`Today`/`PlanView` are not "updated" by anything here** — they simply re-query on next load, since nothing here is UI-aware.

## 8. Mixed-modality completion behavior

Answered directly by Example B above: undefined. `TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix)`'s mixed-modality gate exists at the *weekly rollforward* granularity only (Stage 10R.6); nothing analogous exists at the *phase-completion* granularity.

## 9. Phase-date-boundary behavior

Answered by Example D above: bounded materialization exists (nothing schedules past `endDate`), but no completion/transition trigger is tied to the boundary at all.

## 10. Next-phase activation, calibration handoff

`TransitionPhaseUseCase` → `StartPhaseUseCase.start` defers materialization for any `.rmBased` component still missing `SourceRMCalibration`, exactly like a first phase start (`StartPhaseUseCase.swift:174-187`), returning `componentsAwaitingCalibration`. **What happens to that returned value after a real (not-seed) call is undefined** — there is no ViewModel/View that currently reads `TransitionPhaseUseCase.Result.startResult.componentsAwaitingCalibration` and routes the user to the calibration screen, because nothing real calls `TransitionPhaseUseCase` yet. The calibration screen itself (`SourceRMCalibrationView`/`SourceRMCalibrationViewModel`) is real and works (Stage 10R.1C) for the *first-start* case; wiring it to a *transition* result is unbuilt.

## 11. Mixed-modality phase initialization

`StartPhaseUseCase.start` (called from `TransitionPhaseUseCase` exactly as from a first start) already loops every component of the supplied mix, uses `LongTermPlanner.proposeProgram` per component, and — since Stage 10R.6 — the Functional Fitness/Interval materializers it calls now use the real, repaired context plumbing (`FunctionalFitnessExposureHistoryBuilder`/`IntervalWeekContextBuilder`, always legitimately empty at week 0 for a brand-new instance). Scheduling happens as one coordinated `SchedulingPipeline.propose` call across every component materialized in that single `start()` invocation — confirmed directly by `testPhaseTransitionCompletesOldPhaseStartsNextWithChangedModalityMixAndNeverMutatesHistory`'s own assertion that all 3 of phase 2's varied-mix components instantiate together. No mismatch found here — this part is already correct and reuses Stage 10R.6's fixes automatically, since it's the same `StartPhaseUseCase`/`RollTacticalWindowUseCase` code path.

## 12. PlanView gaps

`PlanView`/`PlanViewModel` (`UI/Plan/PlanView.swift`, `Application/ViewModels/PlanViewModel.swift`):
- Loads the `.active` `Goal`'s `.active` `TrainingPlan`'s `orderedPhases`; renders **every** phase (planned, active, completed alike) as a `PhaseCard`, distinguishing only `.active` by tint color — `.completed`/`.abandoned`/`.paused` all render identically (secondary color, no distinct treatment).
- **No Goal-level or Plan-level completion/status is ever displayed** — `Goal.status`/`TrainingPlan.status` are read only to *select* which one to load, never shown.
- **Zero actions/buttons exist on this screen at all** — the only interaction is tapping a phase card to navigate into `PhaseDetailView`.
- Nothing here would currently show or gate a "your plan needs the next phase started" affordance even if `TransitionPhaseUseCase` were wired up.

## 13. PhaseDetailView gaps

Exactly two action buttons exist, both `.active`-phase-only: "Start Week {n}" (tactical rollforward) and "Start {mesocycle label}" (`StartNextHypertrophyPhaseUseCase`, gated on `nextPhase == nil` — see §5's central finding). **There is no button, anywhere, for "this TrainingPhase is done, move to the next TrainingPhase in the plan."** The only place `nextPhase` is shown is a read-only preview card (`nextPhaseCard`, no button) that can appear in both the active-phase and upcoming-phase views. `PhaseDetailViewModel`'s existing `upcomingPreviewMix`/`upcomingComponentPreviews` machinery (already built, `load`'s own doc comment: "purely informational, never a real ProgramInstance") is the closest existing thing to a "preview the next phase before accepting it" UI seam — it is read-only today.

## 14. Recommended strategic transition UX — judgment call, not yet locked

Given CLAUDE.md rule 17 ("a theoretically optimal program the user does not want is not practically optimal") and rule 14 (no silent replacement of user-selected modalities), plus the fact `TrainingMix.kind` already models `.recommended` vs `.selected` distinctly at the tactical level, my recommendation is: **strategic transitions should be explicit, user-initiated acceptance of a shown recommendation — never automatic, never silently applied.** This mirrors the *tactical* mix-selection precedent already established (`StartPhaseUseCase.swift:105-117`'s own "selected wins once it exists" doc comment) and needs no new concept invented, just extended one level up. This is a recommendation, not a locked decision — flagged explicitly in §25/§26 below for your confirmation.

## 15. Current strategic failure/partial-state risk

Documented in full in §5: `TransitionPhaseUseCase` mutates `outgoingPhase.status`/`programInstances[].status` to `.completed` **before** the one call that can fail (`StartPhaseUseCase.start`), with **zero isolation** — no scratch context, no atomicity, nothing resembling Stage 10R.6's precedent. A failure here today would strand the user with a permanently-completed old phase, no active phase, and no executable Sessions. This is real, present-tense risk in already-shipped (if unwired) code, not a hypothetical for a not-yet-built feature.

## 16. Recommended transaction invariant (proposed, not yet locked)

A successful strategic transition should leave: old phase `.completed` (and its instances), next phase `.active`, every immediately-materializable component's `ProgramInstance`/week-0 Sessions created, one coherent schedule, full history preserved (already proven true when it succeeds). A failed transition should leave the **previously valid strategic state completely intact** — old phase still `.active`, nothing new created. Given Stage 10R.6's scratch-context precedent is proven safe and the codebase already has the exact `ModelContext(container)` + re-fetch-by-ID pattern established, **reusing that same architecture here is the leading candidate** — but per your explicit instruction, this is not to be assumed without first checking whether the strategic transaction's shape (which spans `TrainingPhase`+`ProgramInstance`+`TrainingMix`+scheduling, not just tactical week materialization) has any additional wrinkle Stage 10R.6 didn't need to handle. One candidate wrinkle: if calibration is required for the next phase, is "phase active, awaiting calibration, zero materialized Sessions yet" an **accepted intermediate state** (mirroring `StartPhaseUseCase.Result.componentsAwaitingCalibration`'s existing precedent for a first phase start) or does the whole transition need to hold off until calibration is resolved? This needs a decision (see §26).

## 17. Final-phase behavior

No code answers "what happens after the last `TrainingPhase` in `orderedPhases` completes." `TransitionPhaseUseCase` itself already throws `.noNextPhaseInPlan` in exactly this situation (tested: `testTransitionThrowsWhenThereIsNoNextPhaseInThePlan`) — but nothing catches that and asks "should the `TrainingPlan`/`Goal` now be marked complete?"

## 18. `TrainingPlan`/`Goal` completion behavior

No use case exists for either. `PlanStatus`/`GoalStatus` both have never-reached "done" states (`.superseded` only reachable via explicit `supersedes:`, never used in practice; `.achieved` never reachable at all). No UI shows either concept (§12).

## 19. Onboarding handoff boundary (not building onboarding — just the seam)

The seam Stage 10R.7 should design toward, given everything above already fits: a real onboarding flow would need to (a) construct a real `Goal` from user input (no such construction path exists outside seed code today — this is new), (b) call the already-real, already-tested `LongTermPlanner.proposeStrategicPlan` + `AcceptStrategicPlanUseCase.accept` (already correct, just needs a real caller and an idempotency guard — see §4), (c) hand off into `StartPhaseUseCase.start` for phase 1 with a real, user-confirmed mix (the mix-selection UI itself doesn't exist yet either — `PhaseDetailViewModel.upcomingComponentPreviews` is the closest existing read-only analog). None of this needs to be built now; it needs to exist as a clean extension point.

## 20. Debug-seed dependencies that must eventually disappear

- `TrainingOSApp.init()`'s unconditional (non-`#if DEBUG`) `existingUserCount == 0` seed trigger (`App/TrainingOSApp.swift:24-31`) — a real onboarding flow needs a different "has this user gone through setup" signal, not "does any `User` row exist."
- Hardcoded demo `User(displayName: "Alex Rivera")` (`SeedDataProvider.swift:47`).
- Hardcoded `Goal(primaryType: .muscleGain, targetDate: +1 year)` (`SeedAnnualPlanJourney.swift:60-63`) — a real Goal must come from user input.
- Hardcoded `UserAvailability`/`EquipmentProfile` literals duplicated in `SeedAnnualPlanJourney.swift:74-75` and again in `PhaseDetailViewModel.swift:222,255` (the latter already flagged as a known domain gap by Stage 10R.6, D-10R6-11 — unrelated to onboarding but the same "no real per-user input yet" shape).
- Hardcoded candidate-exercise pools and a string-literal mix-name match (`"Focused Hypertrophy"`, `SeedAnnualPlanJourney.swift:109`) — fine for a seed demo, would need a real candidate-resolution/mix-selection UI for real users.
- `SeedAnnualPlanJourney`'s direct `RecordSetResultUseCase` calls (bypassing `LogSetUseCase`) and direct `TrainingMix.kind = .selected` field write (bypassing any use case) — harmless for a backdated demo, but confirm no real code path should ever do either of these directly.

## 21. Debug-seed dependencies — production wiring gap, restated

To be maximally explicit per your request: **every real Goal/TrainingPlan/TrainingPhase(1)/ProgramInstance(1) a real installed user currently sees originates from the one-time `SeedAnnualPlanJourney` run.** There is no first-run user flow independent of it today.

## 22. Recommended Model (A/B/C)

Compared against what already exists, not from a blank slate:

- **Model A — direct transition.** `TransitionPhaseUseCase` already *is* this model, code-complete, tested in isolation, zero UI wiring, one live atomicity gap (§5/§15).
- **Model B — propose → review → accept.** No infrastructure for this exists at the strategic level today (the tactical level's `TrainingMix.kind`/`.recommended` vs `.selected` distinction is the closest analog, and `PhaseDetailViewModel.upcomingComponentPreviews` is a read-only preview precedent, but nothing today lets a user "accept" a next-phase proposal as a discrete action).
- **Model C — plan-driven activation, next phase already exists in the accepted plan.** **This is what `TransitionPhaseUseCase` already assumes and requires** — it refuses to run if the next phase doesn't already exist (`.noNextPhaseInPlan`). `AcceptStrategicPlanUseCase` already pre-creates every phase up front, matching this model exactly.

**Recommendation: Model C for phase *existence*, with a Model B–shaped *user-facing acceptance step* layered on top of the already-existing Model-A-shaped `TransitionPhaseUseCase` mechanics** — i.e., don't choose one of these three as mutually exclusive; the existing code already committed to "phases are pre-planned" (Model C) at the data layer, and per §14's judgment call, the *transition action itself* should be an explicit, reviewable, user-accepted step (Model B's spirit) rather than silently automatic, even though the underlying mutation (`TransitionPhaseUseCase.transition`) is already a single, Model-A-shaped call once the user has decided. This is a recommendation for your decision, not a locked choice.

**Unresolved, load-bearing question this recommendation does NOT resolve**: how does `StartNextHypertrophyPhaseUseCase` (which creates NEW phases on the fly, Model-A-with-improvised-existence) coexist with Model C's "phases are already planned" assumption? See §5's central finding — this needs an explicit product decision, not an implementation-time guess.

## 23. Implementation slices (proposed, for a future stage — not built now)

1. Fix `TransitionPhaseUseCase`'s atomicity gap using Stage 10R.6's proven scratch-context pattern (or an equivalent proven-safe alternative) — the narrowest, most clearly-justified slice, independent of every other open question.
2. Resolve the `StartNextHypertrophyPhaseUseCase` vs. `TransitionPhaseUseCase`/pre-planned-phases conflict (§5) — a product decision must come first; implementation follows once locked.
3. Add an idempotency guard to `AcceptStrategicPlanUseCase` (no double-plan-per-goal).
4. Build the minimum PlanView/PhaseDetailView UI for "current phase is done → review/accept the next phase" (§14/Model recommendation), wired to `TransitionPhaseUseCase`.
5. Wire calibration hand-off after a real transition (§10).
6. (Separately, out of this stage per your instruction) real Goal-creation/onboarding, once the above seams are solid.

## 24. Proposed test matrix

The 17 items you specified in your request (hypertrophy-only phase completes; mixed phase waits for all required components; exhausted component doesn't block sibling; transition occurs exactly once; immediate double-tap idempotent; transition into calibration-gated phase; calibration completed → first window materializes; transition into mixed-modality phase; scheduler receives complete mix; failed next-phase init leaves old state intact; relaunch after success; relaunch after failure; final phase completion; StrategicPlan completion; Goal completion; source fidelity unaffected; Stage 10R.4-10R.6 tactical lifecycle unaffected) all remain the right list — **the audit did not surface a need to add or remove any of them**, only to note that items 2/3 ("mixed phase waits"/"exhausted component doesn't block") currently have **no code to test at all** (§6 Example B/§8 — this behavior doesn't exist yet, so these would be new-behavior tests, not regression tests), and items 13/14/15 (final phase/plan/goal completion) likewise test not-yet-existing behavior.

## 25. Unresolved questions (surfaced, not resolved)

1. **The central one**: how should `StartNextHypertrophyPhaseUseCase` (mesocycle succession, creates new phases ad hoc) and `TransitionPhaseUseCase`/pre-planned `orderedPhases` (strategic succession, requires phases to pre-exist) coexist in one plan? Today they silently conflict the moment a plan has more than one pre-planned phase (§5).
2. What defines "a mixed-modality `TrainingPhase` is complete" (Example B) — all components exhausted? Only required-priority components? Something else?
3. What happens when a phase passes its `endDate` with incomplete Sessions (Example D) — nothing today, but should Stage 10R.7 define anything, or explicitly defer this too?
4. Is "phase active, next-phase-materialization deferred awaiting calibration" an accepted intermediate strategic state, or must the whole transition wait for calibration to resolve first (§16)?
5. Where does "select the mix for the next phase" actually live — recommended-only, or does the user get to override, mirroring `PhaseDetailViewModel.upcomingComponentPreviews`'s existing read-only precedent?
6. Should `AcceptStrategicPlanUseCase`'s missing idempotency guard be fixed as part of this stage's foundational cleanup, or deferred alongside onboarding?

## 26. Decisions required from you

1. Confirm or correct the central finding in §5/§22/§25.1 (`StartNextHypertrophyPhaseUseCase` vs. pre-planned `orderedPhases`) — this blocks any implementation slice touching phase transitions.
2. Confirm the Model recommendation in §22 (Model C for existence + Model-B-shaped user acceptance over Model-A-shaped mechanics), or specify a different combination.
3. Confirm §14's UX judgment call (explicit, user-initiated acceptance, never automatic) as locked, or amend it.
4. Direct which implementation slice (§23) should be Stage 10R.8, if any — or whether more audit is needed first on any of the open questions in §25.
5. Confirm whether reusing Stage 10R.6's scratch-context transaction pattern for `TransitionPhaseUseCase` is pre-approved, or whether it needs its own from-scratch transaction-boundary audit given the larger blast radius (`TrainingPhase` + `ProgramInstance` + `TrainingMix` + scheduling, not just tactical materialization).

---

**STOP. Audit/design only. Nothing implemented. Not committed, not pushed.**
