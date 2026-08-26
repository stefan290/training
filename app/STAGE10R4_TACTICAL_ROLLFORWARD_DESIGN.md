# Stage 10R.4 — Tactical RollForward / Week Advancement: Architecture & Production-Wiring Audit

**Status: audit/design ACCEPTED and IMPLEMENTED** (Stage 10R.4A+4B+4C —
see `STAGE10R4_TACTICAL_ROLLFORWARD_IMPLEMENTATION_REPORT.md` for the
full implementation report). Checkpoint `18cea3c` (Stage 10R.3A+3B) was
confirmed protected before this document's own audit/design pass began;
this document itself was written and accepted before any code changed.

All claims below are cited to exact file paths and, where load-bearing,
exact line numbers/quoted code, verified by direct reads of the real
files under `TrainingOS/` (not from memory of prior stages).

---

## 1. Lifecycle trace — where the current path stops

Real production path, in call order:

1. `StartPhaseUseCase.start()` (`StartPhaseUseCase.swift:94`) — activates
   a phase, creates one `ProgramInstance` per `TrainingMixComponent`,
   resolves exercise slots, calls `RollTacticalWindowUseCase
   .materializeFirstWindow` (line 189), or defers via
   `componentsAwaitingCalibration` when `.rmBased` calibration is
   missing.
2. `StartPhaseUseCase.materializeOnceCalibrationComplete` (line 226) —
   the deferred half, called once `SourceRMCalibrationViewModel` records
   calibration; calls `materializeFirstWindow` (line 249). Guards its
   own idempotency: `guard instance.sessions.isEmpty else { throw
   .noExecutableComponents }` (line 244) — the one existing precedent
   for the kind of guard `rollForward` itself lacks (see §3).
3. `RollTacticalWindowUseCase.materializeFirstWindow` (line 31) —
   materializes **only weekIndex 0** for `.hypertrophy`/`.powerlifting`/
   `.interval`/`.functionalFitness`; Steady State materializes its whole
   block up front (`SteadyStateMaterializer.materializeAllWeeks`).
4. `SchedulingPipeline.propose` + `AcceptScheduleProposalUseCase.accept`
   — schedules and persists week 0's sessions.
5. `StartSessionUseCase.start()` — sets `Session.status = .inProgress`,
   `startedAt`.
6. Live execution — `LogSetUseCase.logSet` saves each `SetResult`
   immediately (`try modelContext.save()`), independent of session
   completion — confirms CLAUDE.md rule 20 is honored here.
7. `SessionDetailView.beginFinish(context:)` (`SessionDetailView.swift:203`)
   — computes `HypertrophyFeedbackPrompts.pending(for: session)`
   (`HypertrophyFeedbackPrompts.swift:10-19`: every `ExercisePrescription`
   in this session that has a logged result, is referenced as
   another slot's `pairedSlot`, and has no rating yet). If prompts
   exist, presents `HypertrophyFeedbackView` as a `fullScreenCover`
   (lines 110-119) — **`finish(context:)` is not reachable until every
   prompt is answered.** Each answer calls `RecordAutoregulationFeedbackUseCase
   .recordRating` (saves immediately). Only once every prompt clears does
   `onDone` fire `finish(context:)`.
8. `SessionDetailView.finish()` (line 218) → `CompleteSessionUseCase
   .complete()` (`CompleteSessionUseCase.swift:21`) — marks pending/
   active blocks `.skipped`, sets `Session.status = .completed`,
   `completedAt`, `completionContext`, saves, then computes a read-only
   `progressionPreview` (Hypertrophy V2 `.doubleProgression` only).

**The lifecycle stops here.** Nothing after step 8 calls
`RollTacticalWindowUseCase.rollForward`, updates any week/instance
completion state, or triggers next-week materialization.

**Confirmed by exhaustive grep — zero production call sites for
`rollForward`.** Every reference:
- Declaration: `RollTacticalWindowUseCase.swift:83`.
- Doc-comment-only mentions (never called): `ProgramWeekGrouping.swift:13`,
  `ResolveProgramInstanceExerciseSlotsUseCase.swift:37`,
  `StartPhaseUseCase.swift:15,69`, `StrengthMaterializer.swift:63`,
  `TransitionPhaseUseCase.swift:16`, `RequiredSourceCalibrationsUseCase.swift:5`.
- **Test-only call sites** (5 files): `HypertrophyMesocycle1SourceProgressionTests.swift:292`,
  `HypertrophyV2EndToEndTests.swift:225` (+ 9 call sites via a test
  helper), `MixedModalityOrchestrationTests.swift:262,325`,
  `TacticalPlanningOrchestrationTests.swift:291,382`.
- `materializeFirstWindow` (the sibling function), by contrast, **has 2
  real production call sites**: `StartPhaseUseCase.swift:189,249`.

This confirms the user's premise precisely, and reframes the problem: it
is a **wiring/trigger-timing problem, not a missing-engine problem** —
see §10 below.

---

## 2. Definition of "week complete" — no authoritative definition exists

- `TrainingWeek` (`TrainingOS/Domain/Entities/TrainingWeek.swift`) is a
  **template-level** marker on `ProgramDefinition` — `id`,
  `programDefinition`, `sortIndex`, `isDeload` only. Its own doc comment
  states it is deliberately "not a session-structure container." No
  status field, no completion concept, and — critically — **not
  per-`ProgramInstance`**, so it structurally cannot represent "did THIS
  user complete THIS week."
- `Session.status` (`SessionStatus`, `Enums.swift:108-115`): `scheduled`,
  `inProgress`, `completed`, `skipped`, `missed`, `abandoned` — the only
  per-occasion completion signal that exists.
- **No code anywhere aggregates session statuses into a week-level
  concept.** Exhaustive grep for `weekComplete`/`isWeekComplete`/
  `allSessionsComplete`/`isWeekResolved` across `TrainingOS/` — zero
  matches.
- `ProgramWeekGrouping.nextWeekIndex(for:)` (`ProgramWeekGrouping.swift:16-22`)
  — the only "week" concept `rollForward` reads — is purely
  **materialization-existence-based**: `while !realSessions(in:
  forWeek:).isEmpty { week += 1 }`. A week whose sessions are all still
  `.scheduled` (never touched) is indistinguishable, by this function,
  from a week whose sessions are all `.completed` — both simply "have
  real Sessions," so both count as "already materialized, move past it."
  This function answers "which week is next to *materialize*," never
  "did the user finish what already exists."
- Rest days are not modeled as entities — implicit from the absence of a
  `Session` on a given `Day`.
- Mixed modality: no per-week aggregate reasons across components at
  all — everything is per-`ProgramInstance`/per-component (§8).

**This is a genuine, total gap, not a matter of interpretation.**

### Recommended definition (for your confirmation, not silently adopted)

**A week is "terminal" for a given `(ProgramInstance, weekIndex)` when
every real `Session` materialized in that week has a terminal
`SessionStatus`** — `.completed`, `.skipped`, `.missed`, or
`.abandoned` — i.e., none remain `.scheduled` or `.inProgress`.

Reasoning: `SESSION_STATE_MACHINE.md` (an existing, pre-Stage-10R.4
product decision, §7/line 311) already frames `.completed`/`.skipped`/
`.missed`/`.abandoned` collectively as terminal, "always inspectable
history" — this reuses that existing framing rather than inventing a
new one. It also naturally accommodates §7 (missed/skipped) without a
separate mechanism: an explicit skip/miss already moves a session out
of the way. **This is offered as a recommendation, not a silent
decision** — see §23 item 1.

Two rejected alternatives, for the record: (a) requiring literally every
session `.completed` (too strict — a single skip would block advancement
forever, contradicting `.skipped`'s own documented purpose as "a
structured fact, distinct from... never silently dropped from the
schedule"); (b) deriving completion purely from elapsed calendar time
(decouples advancement from real user action, risking exactly the
"future performance-dependent number... fabricated ahead of the window
it belongs to" CLAUDE.md rule 19c forbids).

---

## 3. RollTacticalWindowUseCase.rollForward — exact contract

Read in full (`RollTacticalWindowUseCase.swift:83-158`).

**INPUTS**: `mix: TrainingMix, asOf: Date, ownerUserID: UUID,
performanceProfile: PerformanceProfile?, availability: UserAvailability,
userProfile: UserProfile? = nil, materializationContext:
TacticalMaterializationContext, context: ModelContext`.

**PRECONDITIONS**: each component must have `programInstance` +
`programDefinition` set (else silently skipped via `continue`, never
errored); `system != .steadyState` (Steady State already materialized
its whole block up front, `continue`d).

**MUTATIONS**: for each eligible component, calls
`StrengthMaterializer`/`IntervalMaterializer`/`FunctionalFitnessMaterializer
.materializeWeek`, inserting new `Session`/`WorkoutBlock`/
`ExercisePrescription`/`SetPrescription` rows; then one shared
`SchedulingPipeline.propose` + `AcceptScheduleProposalUseCase.accept`
across every component that rolled this call.

**OUTPUTS**: `Result?` — `nil` if nothing rolled; else
`newSessionsByComponent: [UUID: [Session]]` + `scheduleProposal`.

**SIDE EFFECTS**: none beyond the mutations above.

**IDEMPOTENCY ASSUMPTIONS — the single most important finding of this
audit: there are none.** `rollForward` has no guard of any kind against
repeated invocation. Week selection (`ProgramWeekGrouping.nextWeekIndex`)
is a pure function of "which week has zero materialized sessions" — not
of completion. **Calling `rollForward` twice in a row, with no
intervening user action, does not return the same result or no-op — it
materializes week N+1 the first call, then week N+2 the second call,**
silently racing ahead. Whatever calls `rollForward` in production is
entirely responsible for calling it *at most once per real week
advancement*; the use case provides no protection of its own.

**Week/template resolution**: `weekIndex = ProgramWeekGrouping
.nextWeekIndex(for: instance)`; `weekStartDate = instance.startDate +
weekIndex*7` (Hypertrophy/Powerlifting only — Interval/Functional
Fitness derive their own offset internally, per the code's own comment
at lines 96-104, to avoid double-applying the week offset);
`isDeload = weeks.indices.contains(weekIndex) ? weeks[weekIndex]
.isDeload : false` (line 114) — reads the real, generated
`TrainingWeek.isDeload` flag generically, for whatever `orderedWeeks`
the definition actually has (see §15).

**Progression resolution — already fully wired, not a stub.**
`strengthSlotContext` (lines 168-234) reads every input live from
persisted state, with zero caller-supplied progression parameters:
`rmKilograms` from `instance.sourceRMCalibration` (week 0 only);
`weekOneResolvedWeightKg` from `AutoregulationRatingResolver
.weekZeroResolvedWeight` (scans `instance.sessions` for the earliest
materialized value for that template); `previousWeekSetCount` from
`AutoregulationRatingResolver.previousWeekSetCount` (most-recently-
completed prescription's own set count); `autoregulationRating` from
`AutoregulationRatingResolver.rating` (the paired slot's most-recently-
completed rating). **This means the only genuine input a production
caller must get right is *when* to call `rollForward` — not *what data*
to pass.**

**Modality scope**: operates **per-`TrainingMix`**, looping every
`orderedComponents` entry in one call and rolling **every** eligible
component whose own week is ready — there is no parameter to scope a
call to a single named component. All newly-materialized sessions across
however many components rolled *in this one call* are scheduled together
in one shared `SchedulingPipeline.propose` pass; already-accepted past/
future placements from earlier calls are never re-touched
(`AcceptScheduleProposalUseCase.accept` only mutates the sessions inside
`proposal.placements`, i.e. only this call's own `inputs`).

**Bounds gap, found during this audit, not previously flagged:** there
is no check that `weekIndex` is actually within the definition's real
week count. If `rollForward` were ever called once a `ProgramInstance`'s
final (deload) week is already materialized, `ProgramWeekGrouping
.nextWeekIndex` would return an out-of-range index; `weeks.indices
.contains(weekIndex)` at line 114 would be `false`, silently defaulting
`isDeload` to `false` rather than erroring; `StrengthMaterializer
.materializeWeek` would still build a full `Session`/`WorkoutBlock`/
`ExercisePrescription` graph (weight/set-count simply resolve to `nil`/
`.calibrationRequired` per slot, per `StrengthProgressionEngine
.resolveWeight`'s own bounds check on `laterWeekMultipliers`) — and
`rollForward`'s own `guard !sessions.isEmpty else { continue }` (line
146) does **not** catch this, since a (garbage) non-empty session list
is still produced. **Nothing today prevents rollForward from being
called past the final week of a ProgramInstance and fabricating a bogus
extra week.** See §5/§16/§18 for how the recommended trigger design
avoids ever reaching this state, and a small defense-in-depth addition
worth considering for `rollForward` itself.

---

## 4. Source-program week progression — proving the mechanism against the recovered reference program

The mechanism traced in §3 is already generic over week count and
content — this section proves it against the concrete, already-recovered
3-Day Full Body numbers (Stage 10R.1–10R.3), not new archaeology.

**Mesocycle 1 (Basic Hypertrophy, 5 weeks — 4 progressive + 1 deload,
`primaryWeekOneFactor = 0.85`, `laterWeekMultipliers = [1.05, 1.075,
1.1]`, `repGoalSchedule = [.rir(3), .rir(3), .rir(2), .rir(1)]`):**
`rollForward` called at Week 1 -> materializes Week 2 (`weekIndex=1`,
`isDeload=false`): weight = Week-1 anchor × 1.05, RIR 3, set count from
`AutoregulationRatingResolver.rating` off the paired slot's Week-1
rating (per the real, cell-cited 24-row pairing table). Week 2 -> Week 3
(`weekIndex=2`): × 1.075, RIR 2. Week 3 -> Week 4 (`weekIndex=3`): ×
1.1, RIR 1. Week 4 -> Week 5 (`weekIndex=4`, `isDeload=true`, since
`orderedWeeks[4].isDeload == true` for every generated M1 definition):
routes through `SourceCompatibleDeloadStrategy` instead of
`StrengthProgressionEngine`, unaffected by the multiplier array. Already
exercised end to end by the existing `HypertrophyV2EndToEndTests
.test7_WeekFourToWeekFiveRealReachableDeload` (a `.doubleProgression`
fixture, not Family A source content, but the identical `rollForward`/
`isDeload` mechanism) — confirms deload IS mechanically reachable via
`rollForward` today, just not for a Family A `.rmBased` fixture yet.

**Mesocycle 2 (Metabolite Focus, same 5-week shape, `0.75`/`0.6`
factors, the superset mechanic):** identical mechanism — the only
difference from M1 is content (27 slots, 3 superset partners), never the
progression *mechanism* `rollForward` drives. A superset partner's
`pairedSlot` already points at the same external target its primary
uses (Stage 10R.2A), so `AutoregulationRatingResolver.rating` resolves
it identically to any other row — no special-casing needed in
`rollForward` itself. Not yet exercised end to end through `rollForward`
for real M2 content (no such test exists today — flagged in §21 test
matrix).

**Mesocycle 3 (Resensitization, 3 weeks — 2 progressive + 1 deload,
`1.0`/`1.05` factors, `[.rir(3), .rir(3)]`, `resensitizationLaterWeekMultipliers
= [1.05]`):** `rollForward` at Week 1 -> Week 2 (`weekIndex=1`): weight
= Week-1 anchor × 1.05 (the ONLY entry in the shorter multiplier array —
`laterWeekMultipliers.indices.contains(0)` is `true` for a length-1
array, confirmed by direct read of `StrengthProgressionEngine
.resolveWeight`'s bounds check), RIR 3 (unchanged from Week 1, per the
`resensitizationRepGoalSchedule`). Week 2 -> Week 3
(`weekIndex=2`, `isDeload=true`, since `orderedWeeks[2].isDeload ==
true` for a generated M3 definition — `progressiveWeekCount(for:
.resensitization) == 2`, so index 2 is correctly the 3rd and final
week): deload, day-position weight split, unchanged mechanism.
**`rollForward`'s own code makes zero assumption about week count
anywhere** — `weeks.indices.contains(weekIndex)` and
`ProgramWeekGrouping.nextWeekIndex`'s existence-scan both work
identically for a 3-element `orderedWeeks` as a 5-element one. **Not yet
exercised by any existing test** — Stage 10R.3's own tests call
`StrengthMaterializer.materializeWeek` directly with explicit
`weekIndex`/`isDeload`, bypassing `rollForward`/`ProgramWeekGrouping`
entirely. This is a real, concrete gap for the test matrix (§21 item M3
row), not a known-good path — flagged explicitly rather than assumed.

**Conclusion: the rollForward mechanism must not assume every phase has
5 weeks — and it already doesn't.** The remaining risk is entirely
"nothing calls it, and nothing has proven M3 specifically goes through
it," not "the mechanism itself needs to change."

---

## 5. Mesocycle boundary is not week rollForward — confirmed, with one real gap

Confirmed architecturally distinct by direct read: `RollTacticalWindowUseCase
.swift` never references `StartNextHypertrophyPhaseUseCase`,
`TrainingPhase`, or constructs a `ProgramInstance`/`TrainingPhase`.
`rollForward` operates strictly on an already-existing `TrainingMix`'s
already-existing components' already-existing `ProgramInstance`s.

**The real gap is the reverse direction: today, nothing prevents a
premature mesocycle transition, independent of rollForward entirely.**
`PhaseDetailViewModel.canStartNextHypertrophyPhase`'s exact gate
(`PhaseDetailViewModel.swift:151-161`):

```swift
if phase.status == .active, nextPhase == nil,
   let primaryInstance = phase.primaryInstance, !primaryInstance.sessions.isEmpty,
   activeComponents.first(where: { $0.priority == .primary })?.programmingSystem == .hypertrophy,
   let configuration = primaryInstance.programDefinition?.hypertrophyConfiguration,
   let currentIndex = HypertrophyProgramJourney.orderedPhaseTypes.firstIndex(of: configuration.phaseType),
   HypertrophyProgramJourney.orderedPhaseTypes.indices.contains(currentIndex + 1) {
    canStartNextHypertrophyPhase = true
    ...
}
```

This depends only on `!primaryInstance.sessions.isEmpty` — "has
materialized at all" — never on whether the mesocycle's tactical
progression has actually been exhausted (reached and completed its own
deload week). **Under today's real, wired path, a user could tap "Start
Metabolite Focus" the moment Week 1 alone has materialized — Weeks 2
through deload never having existed at all.** This predates Stage 10R.4
and is independent of whether `rollForward` gets wired, but it becomes
directly relevant once tactical week advancement exists, because the
correct end-state behavior (§16) requires distinguishing "this
instance's tactical content is exhausted" from "this instance has
merely started."

**`rollForward` must never, under any design considered here, silently
create the next mesocycle's `ProgramInstance`/`TrainingPhase`.** The
recommended design (§6/§16) keeps `StartNextHypertrophyPhaseUseCase` as
the sole, still-`.userInitiated` mesocycle-transition entry point, and
only tightens *when* the option to invoke it is offered.

---

## 6. User-initiated vs. automatic week advancement

Comparing the four patterns against the audit's own findings:

**A. Automatic, on last required session completing.** Pro: seamless,
zero extra taps. Con: `rollForward` has **no idempotency guard** (§3) —
an automatic trigger fired from a completion callback risks re-firing
on re-render/re-entry unless it's *itself* gated by an idempotent check
(which then does all the real work anyway, making "automatic" purely
cosmetic). Also directly collides with the mixed-modality finding (§8):
`rollForward(mix:)` always rolls **every** eligible component together
— firing it the instant Hypertrophy's last session completes would also
silently roll Running/Functional-Fitness forward even if the user
hasn't touched those sessions yet, contradicting "next week reflects
real inputs."

**B. Mark week terminal, require an explicit "Start next week" tap.**
Pro: matches the codebase's own already-accepted precedent
(`STAGE3_DECISION_MEMO.md` Decision A1: mesocycle transitions are
`transitionTrigger: .userInitiated`, never automatic) extended one
level down; gives natural, cheap idempotency (mirrors
`canStartNextHypertrophyPhase`'s own "hidden after a successful
transition" pattern exactly — see §17); the gating check can require
**every** eligible component's current week to be terminal before the
action even appears, which means `rollForward`'s existing
whole-mix-at-once batching semantics become *safe to call unmodified* —
no signature change to `rollForward` needed. Con: one extra, explicit
tap.

**C. Materialize automatically, gate visibility via Today/calendar.**
Doesn't actually solve anything A doesn't already have to solve — the
underlying "when do we call rollForward" trigger question is identical
to A; this only changes what happens to the UI afterward. Added
complexity for no clear benefit over B.

**D. Hybrid — per-component automatic rolling, decoupled from the
whole mix.** Would require either splitting `rollForward`'s contract to
accept a single component (a real, non-trivial production change,
explicitly out of scope for this audit pass) or computing per-component
readiness before ever calling the existing whole-mix `rollForward` —
which reintroduces exactly the staggered-component risk the two
existing `TacticalPlacementBoundaryTests` skips already document as a
known, narrow scheduling gap (§8). Not recommended.

### Recommendation: **B**, with the gate defined as "every eligible
`TrainingMixComponent`'s current tactical week is terminal" (§2's
definition, applied per component, ANDed across the mix)

This is a recommendation for your confirmation, not a silent decision —
see §23 item 2. It requires no change to `rollForward`'s own signature;
the new work is entirely a caller-side gate plus one UI action,
mirroring the exact shape of Stage 10R.2B/10R.3B's own "Start [Phase]"
precedent.

---

## 7. Missed/skipped sessions — current handling, and the genuinely open policy question

Current handling (all confirmed by direct read):
- `ChangeSessionStatusUseCase.skip(_:)` — explicit "Skip / Can't train
  today," only valid from `.scheduled`, idempotent no-op otherwise.
  Called from `SessionDetailView.swift:145` and
  `ReadinessAdaptationDecisionUseCase.swift:68` (a readiness-driven skip,
  still an explicit decision path).
- `ChangeSessionStatusUseCase.markMissed(_:)` — "Written only when the
  user views and interacts with the missed-session prompt — never a
  background process, never auto-applied just because a date comparison
  is true" (its own doc comment, matching `SESSION_STATE_MACHINE.md`
  §7's identical framing). Called from `TodayViewModel.swift:49-52`.
- **No code anywhere treats `.skipped`/`.missed` as equivalent to
  `.completed` for any purpose** — because, per §2, no "week complete"
  concept exists yet for either status to feed into.

**The genuinely open policy question** (explicitly TrainingOS
orchestration policy, not a source-programming decision, and not
answerable from generic fitness knowledge): given the recommended
"terminal" definition in §2, a user who has Monday/Wednesday/Friday
sessions and never touches Wednesday (leaves it `.scheduled` forever)
would permanently block that week from ever becoming terminal, since
`.scheduled` is not terminal. Two sub-questions genuinely need your
decision:
1. Should the app ever proactively surface "you have an untouched past
   session — mark it skipped/missed?" (a `ProposeMissedSessionReflowUseCase`-
   shaped mechanism is referenced but explicitly noted "not yet built"
   in `SESSION_STATE_MACHINE.md` line 47) — or should this remain purely
   reactive (user notices, taps Skip themselves)?
2. Is "terminal" (my §2 recommendation) the right bar at all, or should
   `.skipped`/`.missed` sessions be excluded from the readiness gate
   entirely (i.e., only `.completed` sessions matter, and
   skipped/missed ones are simply invisible to the week-advancement
   check, one way or the other)? Functionally these two framings differ
   only in whether an all-skipped week can ever advance — worth deciding
   explicitly rather than letting the implementation default silently.

This is flagged as a decision required from you (§23 item 3), not
resolved here.

---

## 8. Mixed modality

`rollForward(mix:)` operates **per-`TrainingMix`**, not per-component
and not per-`TrainingWeek` (`TrainingWeek` has no cross-component
concept to begin with — it's scoped to one `ProgramDefinition`). Each
component computes its own `weekIndex` independently via its own
`instance` — two components can legitimately sit at different week
indices — but a single `rollForward` call attempts to roll **every**
eligible one together, and schedules whatever rolled together in one
shared `SchedulingPipeline.propose` pass. There is no parameter to scope
a call to one named component.

**Risk, concretely:** if a caller invoked `rollForward(mix:)` the moment
Hypertrophy's week becomes terminal, and Running's current week's
sessions also happen to already be materialized (regardless of whether
the user actually ran them — materialization ≠ completion, per §2),
`rollForward` would roll Running forward too, silently, as a side effect
of the caller only intending to advance Hypertrophy.

**The recommended §6 design sidesteps this entirely**, by construction:
gating the "Start next week" action on *every* eligible component being
independently terminal means that by the time the action is offered (and
`rollForward` is actually called), it is genuinely safe to roll the
whole mix together in one call — which is exactly what `rollForward`
already does. **No change to `rollForward`'s contract is required** to
make mixed-modality rollover safe under this design.

**`TacticalPlacementBoundaryTests`'s two `XCTSkip`s** (`TrainingOSTests
/TacticalPlacementBoundaryTests.swift:257,271`) — both skip for the
identical, already-documented reason (Stage 10R.1C): `.rmBased`
materialization is deferred behind the calibration gate
(`materializeOnceCalibrationComplete`), which runs in "a SEPARATE, LATER
call that deliberately does not re-schedule FF/Running's already-placed
sessions" — under a genuinely at-capacity mix, that gap can legitimately
double-book a day. **Verdict: a narrow, non-blocking gap for this
stage** — it only manifests when a mix is (a) mixed-modality, (b) at/near
calendar capacity, and (c) one component's materialization is staggered
behind a sibling's (the calibration-gated first-window case
specifically). The §6 recommended design's own "wait until every
component is independently ready before rolling any of them" discipline
actually **narrows** this risk for weekly rollForward (every eligible
component rolls together, in one scheduling pass, same as today's
`materializeFirstWindow` path once calibration completes) — it does not
worsen it. **Do not fix these skips in this stage** — flagged as
inherited, not newly introduced.

---

## 9. Dates/calendar scheduling

- Hypertrophy/Powerlifting: `weekStartDate = instance.startDate +
  weekIndex*7` (simple arithmetic, `RollTacticalWindowUseCase.swift:105`)
  — a *naive* starting guess, not the final placement.
- Interval/Functional Fitness: pass `instance.startDate` unshifted and
  derive their own offset internally (deliberate, documented, avoids
  double-applying the offset).
- **Final placement is NOT simple date-copying** — `ConcurrentScheduler
  .schedule` (invoked via `SchedulingPipeline.propose`, called
  immediately after materialization with `SchedulingConstraints
  (availability:, window: SchedulingWindow(startDate: asOf,
  numberOfDays: 7))`) is the real, deterministic placement authority,
  covering hard constraints, urgency, priority, interference/recovery
  preference, and user-preferred days (per its own extensive doc
  comment). Weekday-of-week preservation ("Push Emphasis was on Monday,
  keep it on Monday") is not separately tracked at the materializer
  level — it is entirely `ConcurrentScheduler`'s job, same as it already
  is for week 0.
- Already-accepted past/future placements are never retroactively
  moved: `AcceptScheduleProposalUseCase.accept` only mutates the
  sessions inside `proposal.placements` — i.e. only the current call's
  own freshly-materialized batch.
- **A gap worth flagging**: `rollForward` computes and discards
  `SchedulingPipeline.Result.alignment` (`GoalAlignmentEvaluator`'s
  output) — it never surfaces or acts on scheduling issues the way a
  UI-facing scheduling flow presumably should. Not a blocker for wiring
  rollForward (the pipeline's proposal is still accepted regardless),
  but worth deciding whether a production trigger should surface
  `alignment` issues to the user rather than silently discarding them —
  flagged, not decided here (this maps loosely to §23 but is minor
  enough not to warrant its own numbered decision item; noted for
  completeness).

**Conclusion: do not simply copy dates +7 — the architecture already has
a deliberate scheduler, and `rollForward` already defers to it
correctly.** No new scheduling logic is needed for Stage 10R.4's own
purposes.

---

## 10. Progression input availability — already fully wired

As established in §3, **every Hypertrophy progression input `rollForward`
needs is already durably persisted by the time a week's sessions exist,
and the use case's own `strengthSlotContext` already contains the exact
resolution code** — `SetResult` (via `LogSetUseCase`, saved
immediately), autoregulation rating (`AutoregulationRatingResolver
.rating`, already called), fixed pairing identity
(`PrescriptionTemplate.pairedSlot`, static), prior set count
(`AutoregulationRatingResolver.previousWeekSetCount`, already called),
Week-1 anchor (`AutoregulationRatingResolver.weekZeroResolvedWeight`,
already called, works for any week N since week 0's session is always
chronologically earliest), calibration (`instance.sourceRMCalibration`,
already called), exercise selection (`SubstituteExerciseUseCase
.resolvedExercise`, already called), generator version (frozen, not a
per-week input).

**Nothing here needs new plumbing.** This materially reframes the
project: Stage 10R.4 is a trigger-design and lifecycle-completion
problem, not a progression-engine-completeness problem.

---

## 11. Post-workout feedback ordering — no hazard exists for the real UI path

Traced exactly (§1 steps 7-8): `SessionDetailView.beginFinish` computes
`HypertrophyFeedbackPrompts.pending(for: session)` and, if non-empty,
blocks `finish(context:)` behind a `fullScreenCover` until every prompt
is answered — `CompleteSessionUseCase.complete()` (which sets
`Session.status = .completed`) is structurally unreachable from the
Finish button until then. `CompleteSessionUseCase.complete` itself never
touches `autoregulationRating` and has no ordering dependency of its
own — the guarantee lives entirely in `SessionDetailView`'s gating, not
the use case layer.

**Verdict: any trigger keyed off `Session.status == .completed` can
safely assume every rating that future progression depends on already
exists — for sessions completed through this real UI path.** No
alternate production entry point that calls `CompleteSessionUseCase
.complete` directly, bypassing `SessionDetailView`, was found in this
audit — worth a final confirming grep before this is treated as an
absolute invariant in implementation, but no evidence of one exists
today.

---

## 12. Readiness adaptation interaction — already resolved, not ambiguous

`SetPrescription.isAdaptedAway` (Stage 8B) marks a readiness-removed set
without deleting the row; `orderedSetPrescriptions` returns the full
original/source-prescribed set, `executableSetPrescriptions` filters
adapted-away rows for what's actually shown/logged today.
`AutoregulationRatingResolver.previousWeekSetCount` reads
`prescription.orderedSetPrescriptions.count` — **the full original
SOURCE-prescribed count, including any readiness-adapted-away sets,
never the executable/adapted count, and never the actually-performed
count.**

This is an already-audited, explicit product decision:
`READINESS_PROGRESSION_CONTRACT.md` §3 states this exactly, and further
flags (as a *separate*, already-known, still-open risk, unrelated to
Family A/B/C's `.rmBased` path) that `DoubleProgressionEngine`'s
`lastKnownWeight` resolution has an analogous but distinct concern —
that gap belongs to `CompleteSessionUseCase.progressionPreview`, not
`RollTacticalWindowUseCase`, and is explicitly out of this stage's scope
(noted for completeness, not something Stage 10R.4 should touch).

**Verdict: source prescription feeds next-week autoregulation, by
existing, already-audited design. No ambiguity to flag or resolve here.**

---

## 13. Substitution interaction — confirmed instance-wide

`SlotSelectionOverride` is scoped `(programInstance, templateSlot)` —
its own doc comment: "At most one row exists per `(programInstance,
templateSlot)` pair... instance-specific *state*... must never cause
`ProgramDefinition`... to be mutated." `SubstituteExerciseUseCase
.resolvedExercise(for:in:)` is `instance.slotSelectionOverride(for:
slot)?.selectedExercise ?? slot.resolvedExercise`, and `rollForward`'s
`strengthSlotContext` calls this exact function at every week, N=0
included. **A Week-2 substitution therefore automatically applies to
Week 3, 4, 5 of the same instance with zero additional plumbing** —
proven by the code path itself.

---

## 14. Calibration interaction — confirmed instance-wide, no re-entry needed

`SourceRMCalibration` is scoped `(programInstance, exercise, rmType)` —
doc comment: "never global per `Exercise`... the source itself requires
fresh input at each program/mesocycle boundary and never carries a value
forward automatically." `ProgramInstance.sourceRMCalibration(for:rmType:)`
is a simple lookup with no week/date filter. `RequiredSourceCalibrationsUseCase
.stillRequired` checks `instance.sourceRMCalibration(for:rmType:) == nil`
per pair — once Week 1's calibration exists, this returns empty for
every later week of the same instance. **Confirmed: fresh calibration is
correctly required only at new-`ProgramInstance` boundaries (mesocycle
transitions, already established Stage 10R.2/10R.3), never weekly.**

---

## 15. Deload reachability — mechanism generic; M1 exercised, M2/M3 not

`isDeload = weeks.indices.contains(weekIndex) ? weeks[weekIndex]
.isDeload : false` makes no assumption about week count anywhere in
`rollForward`. Confirmed reachable end-to-end for M1's shape (5 weeks,
deload index 4) via the existing `HypertrophyV2EndToEndTests
.test7_WeekFourToWeekFiveRealReachableDeload` (a `.doubleProgression`
fixture, but identical mechanism). M2 (5 weeks, deload index 4) and M3
(3 weeks, deload index 2) are mechanically identical paths, by direct
code inspection, but **neither has ever been exercised through
`rollForward` for real Family A source content** — a genuine test-matrix
gap (§21), not a known defect.

---

## 16. End-of-ProgramInstance state

`ProgramInstance.status: PhaseStatus` (`.planned/.active/.completed/
.paused/.abandoned`) already exists and is representable, but is applied
**inconsistently by two separate mechanisms**:

- `TransitionPhaseUseCase.transition()` (Stage 7, annual-plan-level) —
  the only place that ever sets `instance.status = .completed`
  (`TransitionPhaseUseCase.swift:75-78`, alongside `outgoingPhase.status
  = .completed`) — but this mechanism has **zero live UI call sites**
  (used only by `SeedAnnualPlanJourney.swift` and its own dedicated
  test).
- `StartNextHypertrophyPhaseUseCase.start()` — the mechanism actually
  wired to the real "Start [Phase]" button — **never touches
  `previousPhase.status`/`previousInstance.status` at all** (confirmed:
  zero `.status` references in the file). The outgoing phase/instance
  is left `.active` forever. **After a real Mesocycle 1 -> 2 transition
  today, both the old and new `TrainingPhase` end up simultaneously
  `.active`.**

### Recommended end-state design

1. **Do not persist a new mutation for "instance exhausted."** Add a
   pure, derived query (mirroring `ProgramWeekGrouping`'s own
   discipline) — e.g. `TacticalWeekCompletion.isInstanceExhausted(for:
   instance:) -> Bool`: true when the final week (`orderedWeeks.last`,
   i.e. the deload week) is terminal (§2) AND there is no further week
   to roll to. This is cheap, reliable, and avoids a new persisted-state
   migration risk.
2. **Tighten `PhaseDetailViewModel.canStartNextHypertrophyPhase`** to
   require `isInstanceExhausted` (or equivalent) rather than merely
   `!primaryInstance.sessions.isEmpty` — closing the premature-transition
   gap found in §5. This is a real, necessary change, not cosmetic: today
   a user can reach "Start Metabolite Focus" after only Week 1.
3. **`rollForward` must never automatically create the next
   `ProgramInstance`/`TrainingPhase`** — confirmed unchanged by this
   design; `StartNextHypertrophyPhaseUseCase` remains the sole,
   `.userInitiated` entry point.
4. **Whether `ProgramInstance.status`/`TrainingPhase.status` should ALSO
   be explicitly set to `.completed` once exhausted** (for consistency
   with `TransitionPhaseUseCase`'s existing precedent, and so any future
   query "give me all completed instances" doesn't fragment by which
   transition path was used) **is a genuine product decision, not
   silently resolved here** — see §23 item 4.

---

## 17. Idempotency / crash safety — design (not yet implemented)

Given `rollForward` itself has no guard (§3), idempotency must live
entirely in the caller-side gate recommended in §6:

- The gate (`canRollTacticalWeekForward` or equivalent, mirroring
  `canStartNextHypertrophyPhase`'s exact shape) is **purely derived**
  from persisted `Session.status`/materialization state at `load()`
  time — never a separate stored "already rolled" flag. Immediately
  after a successful `rollForward` call, the newly-materialized week's
  sessions are freshly `.scheduled` (not terminal), so the gate
  recomputes to `false` on the next `load()` — the same "hidden after a
  successful transition" self-correcting pattern
  `testPhaseDetailViewModelOffersAndPerformsTheRealTransition` already
  proves for the mesocycle-boundary case.
- **Trigger source, tolerant of repetition**: whether fired from a
  button tap, `onAppear`, or `RootTabView` reload, the gate's purely-
  derived nature means repeated evaluation is always safe — it only
  ever *offers* the action when genuinely still true, and the action
  itself only does real work once (since the underlying state it reads
  changes the moment it runs).
- **Crash between "week marked terminal" and "user taps Start next
  week"**: no risk — nothing has been mutated yet; the gate simply
  re-evaluates identically on relaunch.
- **Crash during `rollForward` itself** (mid-materialization, before
  `AcceptScheduleProposalUseCase.accept`'s save): relies on
  `ModelContext`'s existing save semantics — consistent with every
  other multi-step use case in this codebase (e.g.
  `StartNextHypertrophyPhaseUseCase`'s own idempotent `existingNextPhase`
  re-check already handles the equivalent "partially completed, retry"
  case for mesocycle transitions by recomputing from persisted state
  rather than assuming atomicity — the same discipline applies here: a
  genuinely half-materialized week, if it ever occurred, would need
  `rollForward`'s own week-selection (`ProgramWeekGrouping.nextWeekIndex`)
  to correctly treat "some sessions exist" as "already rolled" rather
  than re-rolling — which it already does, since it counts *any* real
  session in a week as evidence that week was materialized).
- **Recommended defense-in-depth addition to `rollForward` itself**
  (small, optional, worth including when implementation begins): an
  explicit bounds check — `guard weekIndex < weeks.count else {
  continue }` per component — replacing the current silent
  `isDeload = false` fallback, so that even a caller bug (calling
  `rollForward` past the final week) fails safely (skips that
  component) rather than fabricating a bogus extra week (§3's bounds
  gap). This does not change `rollForward`'s existing contract for any
  in-range call — purely additive safety.

---

## 18. Persistence transaction boundary — recommended ordering

Audited current ordering (§1/§11): individual `SetResult`s already save
incrementally per CLAUDE.md rule 20; autoregulation rating saves
immediately per answered prompt; `Session.status = .completed` saves
last, after every prompt clears. **This ordering already correctly
ensures no progression input can be lost by the time a session reaches
`.completed`.**

Recommended ordering for the NEW week-advancement step, layered on top
of the existing, already-correct completion save sequence:

1. *(unchanged)* Final `SetResult` persisted.
2. *(unchanged)* Feedback/autoregulation ratings persisted (blocking,
   before completion).
3. *(unchanged)* `Session.status = .completed` persisted.
4. *(new, read-only)* On next relevant view load, the derived
   "week terminal"/"every component ready" gate recomputes from steps
   1-3's already-persisted state — no new write here.
5. *(new)* User taps "Start next week" -> `rollForward` runs, inserting
   the new week's `Session`/`WorkoutBlock`/`ExercisePrescription`/
   `SetPrescription` graph.
6. *(existing, inside rollForward)* `AcceptScheduleProposalUseCase
   .accept` — the actual commit point for the newly materialized week.
7. *(new)* UI refreshes; the gate re-evaluates to `false` for the
   just-rolled component(s).

**No progression input can disappear if `rollForward` fails between
steps 4 and 6** — nothing prior was mutated by the new step, and
everything `rollForward` reads (steps 1-3's data) is already durable
before it ever runs. This is the key property the design achieves:
**the new trigger is purely additive on top of an already-safe
completion sequence**, never a prerequisite change to it.

---

## 19. UI implications — minimum viable surface

Derived from the lifecycle requirements above, not aesthetics:

- **One new piece of state**, mirroring `canStartNextHypertrophyPhase`/
  `nextHypertrophyPhaseTypeLabel` exactly: something like
  `canRollTacticalWeekForward: Bool` (true only when every eligible
  component's current week is terminal, per §2/§6).
- **One new explicit action**, mirroring the "Start [Phase]" button's
  exact shape: a "Start next week" (or similar) button that calls
  `RollTacticalWindowUseCase.rollForward` and refreshes.
- **Placement**: recommend `PhaseDetailView`, for architectural
  consistency with the already-accepted mesocycle-transition precedent
  it already owns (one screen owning "what's next" for the active
  phase). `TodayView` is a legitimate alternative (the user is already
  there right after finishing their last session of the week) — this is
  a genuine, minor UX call, not derived purely from lifecycle
  requirements, so it's listed as a lightweight decision point (§23
  item 5) rather than settled here.
- **No new screen, no new flow** beyond this one action — matches the
  "avoid unnecessary screens" instruction and the established Stage
  10R.2B/3B precedent of reusing the existing calibration screen rather
  than building a dedicated review step.

---

## 20. Source-vs-current gap matrix

| Behavior | Source/product intent | Current support | Match | Required change | Confidence |
|---|---|---|---|---|---|
| Week-to-week progression mechanism | Real source-week progression | `rollForward`'s `strengthSlotContext` — fully correct, fully wired | MATCH | None | High |
| Progression input persistence | Every input durable before next week | `SetResult`/rating/calibration/substitution all confirmed persisted | MATCH | None | High |
| "Week complete" concept | Some authoritative signal | None exists anywhere | MISSING | New pure derived query (§2) | High |
| Production trigger for `rollForward` | Some real call site | Zero — test-only | MISSING | New gate + UI action (§6/§19) | High |
| rollForward idempotency | Safe repeated invocation | None in the use case itself | MISSING (mitigated by caller-side gate) | Caller-side derived gate; optional defense-in-depth bounds check | High |
| Mixed-modality safety | No unintended cross-component rolls | Whole-mix batching, no per-component scope | MITIGATED BY DESIGN (§6/§8) | Gate on ALL components ready before calling | High |
| Deload reachability (M1) | Reachable via rollForward | Proven end-to-end (V2 fixture) | MATCH | None | High |
| Deload reachability (M2/M3) | Reachable via rollForward | Mechanically generic, never tested through rollForward | UNVERIFIED | New tests only (§21) | Medium (code is right; untested) |
| Mesocycle-boundary separation | rollForward never starts next mesocycle | Confirmed separate | MATCH | None | High |
| Premature mesocycle-transition offer | Should require exhausted instance | Only requires `!sessions.isEmpty` | MISMATCH | Tighten `canStartNextHypertrophyPhase` gate (§5/§16) | High |
| End-of-instance status | Consistent `.completed` signal | Two inconsistent mechanisms | MISMATCH | Product decision required (§23 item 4) | High |
| Scheduling/dates | Deliberate scheduler, not date-copying | `ConcurrentScheduler` already owns this, already deferred to correctly | MATCH | None | High |
| Readiness vs. progression input | Explicit, documented decision | Source count feeds progression, already audited | MATCH | None | High |
| Substitution across weeks | Persists automatically | Confirmed instance-wide | MATCH | None | High |
| Calibration across weeks | No re-entry needed | Confirmed instance-wide | MATCH | None | High |
| Missed/skipped policy for advancement | TrainingOS orchestration policy | Undecided | UNRESOLVED | Product decision required (§23 item 3) | N/A |
| LongTermPlanner boundary | Never re-invoked per week | Confirmed untouched by rollForward | MATCH | None | High |

---

## 21. Proposed implementation slices

**10R.4A — Week-completion query + tightened mesocycle-boundary gate**
- New pure query type (e.g. `TacticalWeekCompletion.swift`): `isWeekTerminal(instance:weekIndex:) -> Bool`,
  `isInstanceExhausted(instance:) -> Bool`.
- Tighten `PhaseDetailViewModel.canStartNextHypertrophyPhase` to depend
  on `isInstanceExhausted` instead of `!sessions.isEmpty`.
- Regression-critical: must not change behavior for any already-accepted
  M1->M2 test unless that test's own fixture genuinely reaches
  exhaustion (existing fixtures materialize only Week 1 — this slice
  will need to either extend a fixture to reach real exhaustion or
  introduce a new one; flagged for whoever implements this).
- Independently committable: yes.

**10R.4B — rollForward production trigger (single-modality first)**
- New `canRollTacticalWeekForward`/label state in `PhaseDetailViewModel`
  (or wherever §19's placement decision lands), gated on every eligible
  component's current week being terminal.
- New "Start next week" action calling `RollTacticalWindowUseCase
  .rollForward` and refreshing.
- Optional defense-in-depth bounds check inside `rollForward` itself
  (§17).
- Independently committable: yes, depends on 10R.4A for the query but
  not for rollForward itself (already exists, unmodified).

**10R.4C — mixed-modality verification**
- No new production code anticipated beyond what 10R.4B already
  provides (the "gate on every component" design already handles this
  by construction) — this slice is primarily test coverage proving the
  gate correctly withholds the action until every component is ready,
  and correctly rolls every ready component together.

*(No slice is proposed for the missed/skipped policy or the
end-of-instance `.status` question — both are genuine product decisions
that should be resolved before slicing that work.)*

---

## 22. Proposed test matrix

Adopting and refining the user's own A-T list:

| # | Test | Proves |
|---|---|---|
| A | M1 Week1 -> Week2 via real `rollForward` | Basic mechanism, real production path |
| B | Week2 source load correct | `weekOneResolvedWeightKg × 1.05` |
| C | Week2 RIR correct | `.rir(3)` unchanged from Week1's schedule position |
| D | +1 rating affects the correct paired slot | `AutoregulationRatingResolver.rating` reads the real paired template |
| E | 0 rating | No-change baseline behavior |
| F | -1 rating | Reduction behavior |
| G | Missing rating uses accepted source behavior | `treatMissingRatingAsNoChange` |
| H | Substitution persists across weekly rollForward | §13 |
| I | Calibration persists across weekly rollForward | §14 |
| J | No duplicate week on repeated `rollForward` call | Proves the CALLER-SIDE gate, not `rollForward` itself, since `rollForward` alone has none (§3) — test must exercise the real gate, not just call `rollForward` twice and expect it to no-op |
| K | Persistence/relaunch after completion-before-roll | §17 crash-safety |
| L | Persistence/relaunch after roll | §17 |
| M | M1 Week4 -> Week5 deload via real rollForward | §15, extends the existing V2-only precedent to real Family A content |
| N | M2 Week4 -> Week5 deload via real rollForward | §15, never yet exercised |
| O | M3 Week2 -> Week3 deload via real rollForward | §15, never yet exercised — the shorter-week-count case |
| P | Final deload does NOT start next mesocycle | §5/§16 |
| Q | User-initiated next-mesocycle transition still works after tightening the gate | §16 regression |
| R | Mixed-modality component isolation — Hypertrophy terminal but Running not yet -> gate withholds; both terminal -> both roll together | §6/§8 |
| S | Skipped/missed session counted per the approved policy (once decided, §7) | Depends on your §23 item 3 decision |
| T | Readiness-adapted session interaction | §12 — source count feeds progression regardless of adaptation |
| U (new) | `rollForward` called past the final week (defensive) does not fabricate a bogus week | §3/§17 bounds gap |
| V (new) | Premature "Start next mesocycle" offer is correctly withheld after only Week 1 materializes | §5/§16 regression for the tightened gate |

All 856 existing tests must remain green; item Q above is the specific
regression check for the one existing behavior this stage's own gate
tightening changes.

---

## 23. PRODUCT CONSTITUTION CHECK

**SOURCE AUTHORITY**: none of this stage touches source programming.
Every progression rule, load factor, RIR schedule, and deload mechanism
referenced above is unchanged, already-recovered Family A content
(Stage 10R.1-10R.3).

**TRAININGOS ORCHESTRATION** (this stage's actual subject matter): the
recommended "week terminal" definition (§2), the recommended
user-initiated trigger pattern (§6), the derived `isInstanceExhausted`
query and tightened mesocycle-boundary gate (§16), the idempotency-via-
derived-state design (§17), and the persistence ordering (§18) are all
orchestration/lifecycle infrastructure — never a change to what gets
prescribed, only to when/how the app advances between already-correct
prescriptions.

**TRAININGOS CONVENIENCE**: the specific UI placement recommendation
(`PhaseDetailView` over `TodayView`, §19) is a convenience-level choice,
not load-bearing to correctness — either placement satisfies the
underlying lifecycle contract equally.

**PRODUCT DECISION** (genuinely yours, not decided here): the missed/
skipped-session policy for week advancement (§7/§23 item 3); whether to
also explicitly persist `ProgramInstance.status = .completed` at
exhaustion (§16/§23 item 4); the UI placement of "Start next week"
(§19/§23 item 5); and confirmation of the recommended "week terminal"
definition (§2/§23 item 1) and trigger pattern (§6/§23 item 2).

**UNRESOLVED SOURCE BEHAVIOR**: none newly introduced by this stage —
the pre-existing "which Week-1 actual set result does deload reference"
ambiguity remains exactly as it was, untouched, since nothing in this
audit's recommended design requires resolving it (deload routing itself
is proven mechanically reachable regardless of that unresolved
question).

---

## 24. Do NOT touch (confirmed out of scope for this stage, unaffected by anything above)

`rollForward`'s own wiring is designed but not implemented in this pass.
No production code, tests, or documentation beyond this file were
modified. Explicitly not touched: `load-first`, warm-up heuristics,
Family C recovery, the two `TacticalPlacementBoundaryTests` skips (only
assessed, not fixed), any other Family A configuration, another source
program recovery, the deload actual-rep-result ambiguity.
