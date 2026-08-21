# Stage 8B Acceptance Report

**STATUS: MANUALLY ACCEPTED by the product owner.** Implementation
complete, full regression suite green (676/676, final count after the
debug acceptance-fixture tests were added), verified on both
`iPhone 17` and `iPhone 17 Pro` Simulators (iOS 26.5). Manual acceptance
covered the readiness check-in flow, multiple simultaneous
recommendations, advisory (never automatic) adaptation, rejecting both
a session-level postpone recommendation and an exercise/block-level pain
recommendation — confirming the original Romanian Deadlift prescription
remained executable with its original sets/reps/load after rejection.
The product owner did not exhaustively run every acceptance fixture,
relying on the automated suite for the remaining permutations — an
explicit, accepted trade-off, not a gap in verification.

## UX cleanup identified during acceptance (non-blocking, deferred)

The live workout screen can surface developer-facing copy — "Change
Exercise unavailable — this movement wasn't materialized from a slot."
(`StrengthExecutionView.swift`/`ChangeExerciseView.swift`, both **pre-existing,
Stage 6B copy, not introduced by Stage 8B**). Not user-acceptable final
copy. Deliberately **not fixed as part of Stage 8B** — it's outside this
stage's changed-file set, and the product owner explicitly asked not to
expand Stage 8B into a UX-polish project. Tracked as backlog technical
debt: reword both strings to plain, non-technical language (e.g. "This
exercise doesn't support substitution right now") — a small, isolated,
low-risk follow-up whenever UI copy is next touched.

## Automated verification

- `ReadinessAdaptationTests.swift` — 22 tests, all passing, covering
  every lettered scenario (A-U) plus the Functional Fitness audit-scope
  proof.
- `DebugAcceptanceFixturesUseCaseTests.swift` — 4 tests, all passing,
  proving the debug-only manual-acceptance seeding utility is idempotent,
  session-independent, and never touches the real annual-plan journey.
- Full suite: **676 passed, 0 failed** (`xcodebuild test`, iPhone 17
  Simulator, iOS 26.5) — final count after manual acceptance.
- `xcodebuild build` — clean, no warnings introduced.
- App installs and launches cleanly on a fresh store on both `iPhone 17`
  and `iPhone 17 Pro` Simulators, including a proven terminate-then-relaunch
  reopen of the same persisted store (see "Known environment gotcha"
  below for the one stale-store incident encountered and resolved during
  this stage, entirely a Simulator-environment issue, not a code defect).

## Known environment gotcha (not a code defect)

If this Simulator previously ran an OLDER build of this app (any build
before this session), its on-disk store predates the new
`FunctionalFitnessMovement.substitutionUsed` field and SwiftData/Core
Data cannot lightweight-migrate it, crashing at launch
(`PersistenceController.makeAppContainer()`'s existing `fatalError`).
This is expected, ordinary schema-evolution behavior for a debug/dev
store with no migration plan (none exists anywhere in this codebase yet
— out of scope for Stage 8B). Fix, once, before testing:

```
xcrun simctl uninstall <device> com.macadegolf.trainingos
```

or erase the Simulator via Device → Erase All Content and Settings. This
is a one-time local step, not something Stage 8B needs to solve.

Confirmed twice during this stage: once when "iPhone 17" first carried a
pre-Stage-8B store, and once when a second device ("iPhone 17 Pro") that
had never been cleaned hit the identical failure — same root cause both
times, resolved the same way, no source change required either time.

**Backlog item (technical debt, not Stage 8B scope):** this project has
no SwiftData migration/versioning strategy at all. Acceptable for a
pre-release app with disposable Simulator/dev data, where the schema is
still changing rapidly — but this must be solved before any real user
installs a build carrying persisted training history across a schema
change. Flagging explicitly so it isn't rediscovered as a surprise later.

## Manual Simulator acceptance walkthrough

The app reseeds a single fresh "Alex Rivera" annual-plan journey on first
launch after the store is empty. As observed on this session's build,
**today's card is "Day 1 — Hypertrophy," 2 exercises: Barbell Bench
Press, Incline Dumbbell Press** (both target chest/triceps). Use "View
Week" from Today (or the Plan tab) to find other days for the scenarios
that need a different exercise composition (e.g. a lower-body/squat day,
or a second `.scheduled` session) — the exact day-to-day exercise list
will match whatever `SeedAnnualPlanJourney` places on the calendar around
today's real device date; none of it is hidden or test-only data.

**SCENARIO 1 — GOOD DAY**
1. Tap **Start** on today's session.
2. Sleep: Good · Energy: High · Overall recovery: Fresh.
3. Gateway "Pain or stiffness today?" → **No**.
4. Expected: no follow-up screen, no recommendation screen — the session
   starts immediately, exactly as it did before Stage 8B.

**SCENARIO 2 — LOW READINESS (reject, then accept on a different session)**
1. Start today's session again (or a different `.scheduled` session found
   via View Week, to test on a fresh occasion).
2. Energy: **Low** (leave Sleep/Overall recovery unanswered or OK).
3. Gateway → No.
4. Expected: a recommendation screen appears — "Keep the same load, but
   reduce [exercise] from N sets to N-1." Tap **Keep original**.
5. Reopen that same exercise (or inspect via the Plan/Session detail) —
   confirm the set count is unchanged from its original prescription.
6. Start a **different** `.scheduled` session (View Week → pick another
   day), report Energy: Low again, and this time tap **Accept**.
7. Confirm that session's affected exercise now shows one fewer
   executable set, while the app's own record of "originally prescribed"
   (visible via any prescription detail / completed-history screen once
   finished) still shows the full original count.

**SCENARIO 3 — LOCAL PAIN**
1. Find (via View Week) a session whose exercises target *different*
   muscle groups — e.g. a squat/lower-body exercise alongside an
   upper-body one. Today's own Day 1 card (bench + incline press, both
   chest/triceps) is not a good fit for this scenario since both
   exercises share the same target — pick a different day.
2. Start it. Gateway → **Yes**. Choose **Pain**, and select the body area
   matching only ONE of that session's exercises (e.g. quadriceps if a
   squat variant is present).
3. Expected: a substitution is proposed for the affected exercise only
   (or, if no compatible alternative exists in the catalog for that
   exact slot, a set-count reduction for that one exercise, or block
   removal if it's the block's only exercise — see
   `READINESS_DECISION_MODEL.md` §2's precedence rule). The unrelated
   exercise must show no proposal at all.

**SCENARIO 4 — STIFFNESS**
1. Start a session. Gateway → **Yes**. Choose **Stiffness** (not Pain),
   pick a body area.
2. Expected: recorded distinctly as stiffness (never merged with pain);
   language throughout is "discomfort/limitation/reported," never
   diagnostic ("you have...", "this is likely..."). Behavior follows the
   currently-supported policy: on a Strength/Hypertrophy exercise, a
   set-count reduction may be proposed (same as soreness); on a
   Functional Fitness movement, expect **no proposal at all** — Stage 8B
   has no implemented Level 2 mechanism for that modality (by design, not
   an oversight — see the Functional Fitness audit result).

**SCENARIO 5 — POSTPONE**
1. Start a session. Report Sleep: Poor, Energy: Low, Overall recovery:
   Sore (2+ of the 3 core signals poor).
2. Expected: the recommendation screen proposes **postpone/skip** for the
   whole session, clearly framed as a recommendation. Accept it.
3. Confirm: the session's own status becomes skipped; nothing on the
   Plan tab's phase/tactical-window view changes — no silent annual or
   tactical plan mutation.

**SCENARIO 6 — HISTORY**
1. Complete a session where you accepted a Level 2 (set-count) or Level 3
   (substitution) adaptation — log the real, reduced/substituted work and
   tap Finish.
2. Reopen it from Today ("View Workout") or via Progress/completed
   history.
3. Expected: the completed-history screen can account for what was
   originally prescribed, what was adapted, and what was actually
   performed — the three states are never collapsed into one number.

## Files changed

**New (Domain):** `ReadinessCheckIn.swift`,
`ReadinessAdaptationDecision.swift`, `ReadinessTypes.swift`,
`ReadinessAdaptationProposal.swift`.
**New (Application/UseCases):** `RecordReadinessCheckInUseCase.swift`,
`EvaluateReadinessAdaptationUseCase.swift`,
`ReadinessAdaptationDecisionUseCase.swift`,
`SubstituteFunctionalFitnessMovementUseCase.swift`.
**New (UI):** `ReadinessCheckInView.swift`,
`ReadinessAdaptationProposalView.swift`, `ReadinessGateFlow.swift`.
**New (Tests):** `ReadinessAdaptationTests.swift` (22 tests).
**Modified:** `Session.swift` (+`readinessCheckIn` relationship),
`SetPrescription.swift` (+`isAdaptedAway`), `ExercisePrescription.swift`
(+`executableSetPrescriptions`, +`readinessAdaptationDecisions` inverse),
`FunctionalFitnessMovement.swift` (+substitution plumbing,
+`readinessAdaptationDecisions` inverse), `WorkoutBlock.swift`
(+`readinessAdaptationDecisions` inverse), `ExerciseSlot.swift`
(+`materializedFunctionalFitnessMovements` inverse),
`SubstitutionReason.swift` (+`.readinessAdaptation`), `Enums.swift`
(+`ProgressionReasonCode.readinessAdaptedHold`),
`CompleteSessionUseCase.swift` (D9 adaptation-aware
`progressionPreview`), `PersistenceController.swift` (schema
registration), `TodayView.swift` (readiness gate wired before Start),
`TrainingOS.xcodeproj/project.pbxproj` (new file references + target
membership).
**Documentation:** `READINESS_PROGRESSION_CONTRACT.md`,
`STAGE8B_IMPLEMENTATION_PLAN.md`, `DELETE_RULE_MATRIX.md` updated to
match the as-shipped implementation; this report is new.

No change to `ProgramDefinition`, `TrainingWeek`, any template-graph
type, or any existing persisted performance data.
