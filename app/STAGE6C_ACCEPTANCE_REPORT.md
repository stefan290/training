# Stage 6C acceptance report

Manual acceptance testing and execution UX hardening on top of Stage 6B
— proving TrainingOS works as an actual training application from
Strategic Plan through Session Preview, multi-exercise Workout
Execution, exercise-to-exercise navigation, Completion, and the weekly
training overview. No programming engine, planner, scheduler, or
substitution mechanism was redesigned; every fix is additive.

## 1. Observed manual failure

Starting the seeded "Lower A" Session opened Strength execution showing
only Back Squat. After logging all three sets, the screen correctly
recognized "All sets logged" but offered no Next Exercise, no block
completion, and no normal Finish Workout — only "Finish as Partial" from
Session Detail, even though the (apparently entire) prescribed work was
done. Change Exercise was visible but reported "This movement wasn't
materialized from a slot."

## 2. Root cause

Two independent, compounding causes, not one UI bug:

1. **Seed/materialization cause.** `SeedScenarios.twoSessionsSameDay`
   built "Lower A" as a single, hand-assembled `ExercisePrescription`
   (Back Squat, three `SetPrescription`s) directly on a `WorkoutBlock` —
   never through `ProgramDefinition` -> `ProgramInstance` -> a template
   graph -> `StrengthMaterializer`. No `ExerciseSlot` was ever created or
   referenced, so `ExercisePrescription.sourceExerciseSlot` was `nil` —
   Change Exercise's "unavailable" message was reporting a true fact
   about this specific seed data, not a bug in the substitution
   architecture.
2. **Execution/completion-state cause.** Independent of the seed data,
   `StrengthExecutionView` had no path forward once a movement's sets
   were all logged: no Next Exercise action (even the one-exercise case
   had nowhere to go), and — the more serious defect — nothing ever
   called `CompleteBlockUseCase.complete` when every prescribed set was
   logged, so a `WorkoutBlock` could satisfy 100% of its prescribed work
   and still sit at `.status == .active` forever, forcing
   `SessionDetailView`'s own "all blocks completed?" check to fail and
   only ever offer "Finish as Partial."

Both were real; fixing only the seed data would still have left a
single-exercise workout unable to complete normally, and fixing only the
completion bug would still have left multi-exercise navigation entirely
unproven.

## 3. Seed/materialization findings

Diagnosis, in the terms Part B asked for:

1. Lower A contained exactly **one** `WorkoutBlock`.
2. That block contained exactly **one** `ExercisePrescription` (Back
   Squat).
3. Yes, intentionally — by construction, not a filtered/truncated
   result of some other list.
4. **Assembled manually as seed/demo data** — direct `Session`/
   `WorkoutBlock`/`ExercisePrescription`/`SetPrescription` construction
   in `SeedScenarios.swift`, entirely bypassing the materializer
   pipeline.
5. **No** — `sourceExerciseSlot` didn't exist as a field until Stage 6B
   Slice 6, and even after it was added, nothing set it for this
   hand-assembled prescription.
6. Because `ExercisePrescription.sourceExerciseSlot == nil` — the exact,
   correctly-implemented condition `StrengthExecutionView`'s Change
   Exercise control already checked (Stage 6B Slice 6), reporting a true
   fact rather than malfunctioning.
7. **Both** — missing seed data (only one exercise existed to navigate
   between) **and** a genuine completion-state gap (no code anywhere
   called `CompleteBlockUseCase.complete` on set-completion), compounding
   into the observed failure.

## 4. Multi-exercise execution fix

`StrengthExecutionViewModel` gained: canonical-order-preserving
`movements`/`movementCount`; `StrengthExecutionViewModel.isComplete(_:)`
(derived, no new persisted entity); `isBlockComplete`;
`completedMovementCount`; `goToNextMovement`/`goToPreviousMovement`
(transient view index only, ordering always from
`WorkoutBlock.orderedPrescriptions`); and an `init` that resumes at the
first not-yet-complete movement, re-derived every time, never a
separately persisted "current exercise" field.

`StrengthExecutionView` gained: "Exercise N of M" + "K / M exercises
completed"; an "Exercise Complete / Next: <name>" state with a
prominent Next Exercise action; a "Strength block complete" state once
every movement is done; a Previous/Next Exercise bar always available so
an already-completed exercise can be inspected without corrupting
anything; and a truthful Change Exercise control (enabled only when
`sourceExerciseSlot != nil`, otherwise a plain explanatory line, never a
dead-end button).

## 5. Completion-state fix

`StrengthExecutionViewModel.logCurrentSet` now checks `isBlockComplete`
immediately after logging and, the instant it's true, calls
`CompleteBlockUseCase.complete(block, context: .full, ...)` itself — no
separate confirmation step the user has no way to give. This is the
direct fix for "all required work complete, block remains In Progress
indefinitely." `SessionDetailView`'s existing "all blocks completed?"
check (unchanged) now correctly resolves to "Finish Session" rather than
"Finish as Partial" the moment this holds.

## 6. Session Preview behavior

`SessionPreviewContent` (new, shared) renders every block's real,
persisted prescription — per-exercise sets/reps/RIR for Strength,
activity/duration/intensity for Steady State, interval structure for
Interval, format/movements/scoring for Functional Fitness — read-only,
with no `modelContext` and no use-case call anywhere in its body.
`SessionDetailView` shows it in place of the old compact per-block row
list whenever a Session is `.scheduled` (before Start) or opened
`readOnly` (from Week); the interactive per-block navigation list only
ever appears once a Session is actually `.inProgress` or beyond.

## 7. Week architecture

`WeekViewModel` fetches every `Day` in the store and filters, in Swift,
to the seven dates of the requested calendar week (`weekOffset`, 0 =
current) — the same "fetch broadly, filter locally" tradeoff
`TodayViewModel` already documents. `WeekView` renders each day's real
`Session`s (multiple Sessions per day shown independently, zero Sessions
rendered as a presentation-only "Rest Day" with no fake Session entity),
with Previous/Current/Next Week navigation. Tapping a Session opens the
same `SessionDetailView`, `readOnly` unless the day is today.

## 8. Tactical-window behavior

Browsing Week never creates a `Day`/`Session` or triggers
materialization — proven by
`WeekViewModelTests.testNavigatingOutsideTheTacticalWindowDoesNotFabricateSessions`/
`.testNavigatingForwardRepeatedlyNeverTriggersMaterialization` (Day/
Session counts in the store are asserted unchanged after jumping ~52
weeks forward and after ten consecutive "next week" taps). A week where
every one of its seven days is empty is presented as "Not yet planned"
rather than as seven ordinary rest days — the only way, without a new
domain concept, to distinguish "this week hasn't been materialized yet"
from "this is a normal week with rest days," which a partially-populated
week (some real Sessions, some empty days) still correctly shows as
ordinary rest days.

## 9. Substitution acceptance result

The realistic fixture includes one slot ("Unilateral/Machine Squat")
with two real `allowedExercises` (Leg Press default, Bulgarian Split
Squat alternative). Verified by `MultiExerciseExecutionTests`:
`SubstitutionCandidateRanking` surfaces the real alternative; **THIS
SESSION ONLY** changes only the intended `ExercisePrescription` (an
unrelated movement in the same block, and the slot's own template
default, are both untouched); **GOING FORWARD** writes a real
`SlotSelectionOverride` that `SubstituteExerciseUseCase.resolvedExercise`
correctly prefers, while the template default and the already-
materialized prescription remain exactly as they were. No new
substitution mechanism — the existing Stage 4C architecture, exercised
against real data for the first time.

## 10. Crash/relaunch result

`MultiExerciseExecutionTests.testRelaunchingResumesAtTheCorrectIncompleteExercise`
logs a completed exercise plus one set of the next, saves, fetches from
a completely fresh `ModelContext` (simulating relaunch), and confirms a
new `StrengthExecutionViewModel` resumes exactly at the right movement
and set index — `.testLoggedResultsSurviveRelaunch`/
`.testAlreadyCompletedSetsAreNotDuplicatedAfterResume` confirm no result
is lost or duplicated. No timer behavior was touched — `WorkoutTimer`'s
wall-clock-anchored, no-replay contract from Stage 6B is unchanged and
was not found to need any fix during this pass.

## 11. Tests added

**31 new tests**, two new files:

- `MultiExerciseExecutionTests.swift` (17) — canonical order; exercise/
  block completion derivation; block-never-completes-early; auto-
  completion through the real ViewModel path; Session
  full-vs-partial-finish semantics; multi-block "doesn't finish early";
  crash/relaunch resume + no duplication; Change Exercise truthfulness;
  real slot-based substitution (both scopes).
- `WeekViewModelTests.swift` (14) — current-week contents; multiple
  Sessions per day; zero-Session days; status label mapping; read-only
  inspection (no mutation, no results created); future detail for all
  four modalities; tactical-window boundary (no fabrication, no
  triggered materialization); multi-Session independence; live-store
  (not cached) reads.

## 12. Full test result

**505 / 505 passing** (up from Stage 6B's 474/475 baseline — see note
below on count variance), full suite, no regressions, no weakened or
deleted tests. Verified via `xcodebuild test` on `iPhone 17` / iOS 26.5
(`896F3964-F0BA-47DF-863D-7532BD478E11`). One baseline test
(`DomainModelScenarioTests.testZone2SessionIsSteadyStateWithDurationResultAndNoSetLogging`)
briefly regressed when a new future-Session seed fixture happened to
share its hardcoded name ("Zone 2 Run") with an existing historical
scenario, colliding in that test's own name-based lookup; fixed by
renaming the new fixture's Session ("Upcoming Zone 2") rather than
touching the pre-existing test.

## 13. Simulator result

Build installs and launches cleanly, no crash. Today was visually
confirmed showing "STRENGTH · 5 exercises" with a compact "Back Squat,
Romanian Deadlift, Leg Press, +2 more" preview and a "View Week" link —
the exact Part D fix. As with Stage 6B, **no scripted tap-through
automation was available in this environment** (confirmed absent again
this pass); Part AC/AD/AE's manual flow lists are validated here via the
31 new tests exercising the identical use-case/view-model call chains the
UI drives, not via recorded taps. This is a disclosed limitation, not a
claim of full interactive verification.

## 14. Screenshots captured

One: Today showing the fixed multi-exercise summary and View Week link
(included in the session transcript). The remaining Part AF list
(Week overview, future-Session preview, in-execution states, Change
Exercise, Completion Summary) could not be captured for the same
tap-automation reason as §13 — each of those states is instead covered
by an explicit automated test asserting the exact data/behavior that
screen renders.

## 15. Schema changes

**None.** Every fix this stage made is either new application/
presentation code (`StrengthExecutionViewModel`/`StrengthExecutionView`
additions, `SessionPreviewContent`, `WeekViewModel`/`WeekView`,
`SessionPresentation.weekStatusLabel`, `BlockPresentation.compactDetail`/
`.exerciseNames`) or new seed-data content (`ExerciseCatalog`'s five new
exercises, `SeedScenarios.materializedLowerASession`). No `@Model` type
gained, lost, or changed a persisted field.

## 16. Architectural deviations

**None from locked architecture.** One genuine, disclosed simplification
(not a deviation from anything locked): a week where all seven days are
empty is presented as "Not yet planned" via a heuristic
(`WeekViewModel.weekHasNoMaterializedData`), since no domain concept
distinguishes "unmaterialized" from "genuinely a full rest week" — see
§8. This is new, additive UI logic, not a change to how materialization,
scheduling, or the Long-Term Planner itself behaves.

## 17. Remaining known gaps

- **Strategic-future "planned but not materialized" hints** (Part S's
  "Planned: Hypertrophy, 4 sessions" example) are not implemented — an
  unmaterialized week shows a plain "Not yet planned" message rather
  than a `TrainingPhase`/`ProgramDefinition`-derived strategic summary.
  Building that correctly would mean new integration with the Long-Term
  Planner's own data model, which risks reaching beyond this stage's
  "do not change Long-Term Planner behavior" instruction without a
  specifically proven need — showing nothing is safer than showing
  something wrong.
- **Scripted Simulator UI automation** remains unavailable in this
  environment (§13) — carried over from Stage 6B, not new to this pass.
- **RepGoal has no low/high range and `StrengthMaterializer` never sets
  `targetRir`** — a pre-existing fact about the production Strength
  engine (not introduced or changed this stage), reflected honestly in
  the realistic acceptance fixture rather than patched around.
- Benchmark tagging at Functional Fitness Finish (Stage 6B's own known
  gap) is unchanged/still not built — out of this stage's scope.

## 18. Commit hash

See `git log` for the commit(s) concluding this stage; verified against
`origin/main` per §20 below before this report was finalized.

## Local / remote verification

```
git status
git rev-parse HEAD
git rev-parse origin/main
```

Baseline confirmed at the start of this stage: `HEAD` and `origin/main`
both at `2013a3364631348e92d814d57c1b1c57911704a4`, clean working tree.
Post-stage verification recorded at commit time below.
