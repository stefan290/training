# Stage 6B implementation report

Workout Execution + Daily Training UX, built across ten slices on top of
the approved Stage 6A design (`WORKOUT_EXECUTION.md`,
`SESSION_STATE_MACHINE.md`, `TIMER_ARCHITECTURE.md`,
`STRENGTH_EXECUTION_FLOW.md`, `ENDURANCE_EXECUTION_FLOW.md`,
`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md`, `WORKOUT_COMPLETION_PIPELINE.md`,
`STAGE6A_DECISION_MEMO.md`). Out of scope, as instructed: HealthKit,
Apple Watch, AI features, Long-Term Planner redesign.

## 1. Architecture

View -> ViewModel -> UseCase -> Domain/Persistence, unchanged from the
rest of the app. Two-layer use-case convention locked in Stage 6A and
followed throughout: low-level `RecordXResultUseCase`s stay pure
mutation (no `save()`, reused by seed data/tests unchanged); new
**orchestrating** use cases (`StartSessionUseCase`, `LogSetUseCase`,
`LogEnduranceResultUseCase`, `LogFunctionalFitnessResultUseCase`,
`ApplySubstitutionUseCase`, `CompleteBlockUseCase`,
`ChangeSessionStatusUseCase`, `CompleteSessionUseCase`,
`UpdateBlockTimerUseCase`) each wrap one (or a small group of) low-level
call(s) and save immediately. Views/ViewModels never call `save()` or a
low-level use case directly. Full detail in `ARCHITECTURE.md`'s Stage 6B
section.

## 2. Today UX

`TodayViewModel`/`TodayView`: every Session for the day is shown and
actioned independently — a finished morning Session shows "Completed"
while an evening Session still shows "Ready," never a whole-Day rollup.
Each card shows role/scheduled time/status/major blocks and a Start
action; a scheduled Session whose time has passed shows an explicit
"Start Anyway" / "Mark Missed" prompt instead (status written only on
tap, never inferred passively).

## 3. Strength/Powerlifting execution + substitution/calibration

`StrengthExecutionView`/`StrengthExecutionViewModel`: target sets-reps/
RIR/suggested load, a fixed previous-performance snapshot, current-set
logging (weight/reps/RIR, saved immediately), RIR quick-select
pre-selected to the target, and a configurable rest timer. Editing
load/reps before logging only changes the recorded actual result, never
the set's own prescription. Reused unmodified for Powerlifting — nothing
branches on programming methodology. Calibration: the first logged set
against any exercise already becomes that exercise's permanent history
immediately, via the existing `ExercisePerformanceProfile` mechanism — no
separate calibration subsystem was needed.

Change Exercise (`ChangeExerciseView`): only slot-valid alternatives,
ranked by history tier (own history / related-exercise estimate /
calibration required) via the new `SubstitutionCandidateRanking`, which
reuses the existing `SubstitutionValidator`/`SubstitutionAwareRecommendation`
engines — no new scoring mechanism. Today Only and Going Forward both
route through the existing `ApplySubstitutionUseCase`.

## 4. Steady State / Interval execution + substitution

`SteadyStateExecutionView`: a plain elapsed clock plus a completion form
covering whichever metrics the activity can supply
(duration/distance/avgHR/avgPower/RPE) — never blocked on HealthKit.

`IntervalExecutionView`: time-based intervals auto-progress Work ->
Recovery -> Work purely from elapsed wall-clock time via the new
`IntervalTimerResolution`; distance-based intervals are logged by hand,
one at a time. Each interval is persisted the instant it's known to be
done (`LogIntervalRepUseCase`), never held in memory until the whole
block finishes; `FinalizeIntervalResultUseCase` is the later, idempotent
consistency point.

Change Activity (`ChangeActivityView`) covers both prescription types,
reusing `SubstituteActivityUseCase`'s existing `IntensityTranslation` so
no incompatible numeric target ever carries across activities.

## 5. Functional Fitness execution

One `FunctionalFitnessExecutionView` covers every typed `WorkoutFormat`:
AMRAP (countdown + "+ROUND" tap target + end-of-time reps entry, no live
rep logging), EMOM (auto-advancing current/next station, no per-minute
tap), For Time/Chipper/Ladder (running clock to Finish/time cap), Rounds
For Time (round counter + running clock), Max Load/Max Reps (single-entry
forms), Intervals (reuses `IntervalTimerResolution` unchanged). Scoring
uses `Stimulus.scoreType` (always authored) plus the new, deterministic
`FunctionalFitnessScoring.scoreDirection(for:)` (never re-derives
`ScoreType`).

## 6. Timer implementation

One shared foundation, `WorkoutTimer` (`Engines/WorkoutTimer.swift`):
elapsed/remaining/expiry/pause/resume/`currentUnitIndex`, all pure
functions of a persisted `TimerState` and a caller-supplied "now" — no
tick counting, no replay of missed transitions. `IntervalTimerResolution`
generalizes `currentUnitIndex` to two alternating leg lengths (work vs.
recovery), which the original uniform-duration assumption can't express;
shared unchanged by Endurance Intervals and Functional Fitness's own
`.intervals` format. `UpdateBlockTimerUseCase` is the orchestrating,
save-owning layer (one save per transition, never per tick). Every
countdown/clock in the UI recomputes from `TimerState` + the current
render tick via `TimelineView` — never an accumulated counter.

## 7. Incremental persistence

Every meaningful confirmed action saves immediately: a logged set, a
substitution, a block/Session status change, a Session
start/pause/resume/completion. The one genuinely new persistence
pattern this stage needed: Interval's per-interval data (`LogIntervalRepUseCase`)
creates/appends to an `IntervalResult` as each work/recovery leg finishes,
rather than waiting for one final call with everything already
attached — the crash-safety guarantee ("lose at most one unconfirmed
edit, never anything already confirmed") otherwise wouldn't hold for a
long multi-interval session. `FinalizeIntervalResultUseCase` is the
final, idempotent consistency point on top of that already-durable data.

## 8. Partial/missed behavior

Finish-as-Partial auto-skips whatever blocks remain and is idempotent;
the already-completed sibling blocks are never touched
(`StageSixBEndToEndFlowTests.testFinishAsPartialSkipsUntouchedBlockAndNeverInventsItsResult`).
Per-modality partial-result progression is unchanged from Stage 6A's
audit: `DoubleProgressionEngine` already holds on a mismatched result
count; `IntervalProgressionEngine` already has graduated completion-
fraction handling; `SteadyStateProgressionEngine` doesn't consume actual
results at all; `FunctionalFitnessDecisionEngine` reasons over exposure
history unaffected by partial-vs-full. Missed-session marking
(`ChangeSessionStatusUseCase.markMissed`) is written only on explicit
user interaction with Today's prompt, never a background process, and
is entirely execution-side — no scheduling reflow is implemented or
implied.

## 9. Completion pipeline

`CompleteSessionUseCase` is the final consistency point, not the first
durability point, and is idempotent against a double-tapped Finish
(`OrchestratingUseCaseTests.testCompleteSessionCalledTwiceNeverReMutatesOrDuplicates`).
`CompletionSummaryView` shows completed work, PR/baseline highlights,
and the existing progression preview — no second progression mechanism,
no analytics beyond what was specified. `SessionExecutionState` (new,
in-memory, per-Session-visit) accumulates only PR/first-entry highlights
as they happen, since `isFirstEverEntry` is intentionally never
persisted and can't be reliably re-derived after the fact.

## 10. PR/baseline behavior

Unchanged data model: `ScoringEngine.isNewPersonalRecord`/`PersonalRecord`
are exactly as before. Every `LogXResultUseCase`/`RecordXResultUseCase`
now also returns `isFirstEverEntry` (`existingBest == nil`, computed
before the PR check) purely so the UI can say "Baseline established"
instead of "New personal record!" for a first-ever entry — the
underlying storage is identical either way.

## 11. PerformanceProfile integration

Every logged result folds into its permanent, program-independent home
exactly as before: `ExercisePerformanceProfile` (Strength),
`ActivityPerformanceProfile` (Steady State/Interval),
`BenchmarkPerformanceProfile` (a tagged Functional Fitness benchmark
attempt — see the known gap in §18). Nothing in this stage scopes any
performance data to a Session, a ProgramInstance, or a ProgramDefinition.

## 12. Tests added

475 tests total in the suite as of this report (up from the ~403
pre-Stage-6B baseline); every new persisted field has real SwiftData
round-trip coverage, not just Codable compilation trust. New this stage:
`ExecutionStatePersistenceTests` (schema round-trips, including the
Slice 6/7 slot/template-trace-back fields), `RecordEnduranceResultUseCaseTests`,
`WorkoutTimerTests` (17), `OrchestratingUseCaseTests` (19),
`SubstitutionCandidateRankingTests`, `IntervalTimerResolutionTests`,
`IntervalExecutionUseCaseTests`, `FunctionalFitnessScoringTests`,
`SessionExecutionStateTests`, `StageSixBEndToEndFlowTests` (full
multi-block Session lifecycle, Finish-as-Partial, Today-Only-substitution-
then-switch-back).

## 13. Total test count / result

**475 / 475 passing**, full suite, no regressions at any slice boundary.
Verified via `xcodebuild test` on `iPhone 17` / iOS 26.5
(`896F3964-F0BA-47DF-863D-7532BD478E11`).

## 14. Simulator flows tested

Build installs and launches cleanly on the Simulator with no crash.
Today's multi-session display was confirmed visually (two independent
Sessions, each with its own status/role/block summary/Start action).
**Full interactive tap-through of the flow list (start/log/background-
relaunch/substitute/finish-partial/resume/finish/second-session/
steady-state-completion/AMRAP-timer-result) was not performed as scripted
UI automation** — no `idb`/UI-automation tooling was available in this
environment (checked and confirmed absent), and `xcrun simctl` has no
tap/gesture primitive. In its place: `StageSixBEndToEndFlowTests` exercises
the identical use-case call chain the UI drives (start -> log Strength +
Steady State across two blocks -> Finish, Finish-as-Partial's
untouched-sibling guarantee, Today-Only-substitution-then-switch-back's
exercise-history isolation), plus the full 475-test suite covering every
timer/persistence/substitution/completion rule individually. This is a
disclosed limitation, not a silent gap.

## 15. Screenshots / deviations

One screenshot captured (Today, multi-session display, Slice 5) —
included in the session transcript. Design deviations from
`Training OS.dc.html`: none beyond what Stage 6A's own decision memo
already anticipated (large tap targets/readable numbers/one-handed
controls/sticky primary actions preferred over literal pixel-matching
where they'd conflict with gym usability, per the kickoff's own
instruction).

## 16. Persistence / schema changes

All additive, all covered by round-trip tests:

- `SessionCompletionContext`/`BlockCompletionContext`/`TimerState`
  (`Domain/ValueTypes/ExecutionState.swift`) on `Session`/`WorkoutBlock`.
- `ExercisePrescription.sourceExerciseSlot` (nullify inverse on
  `ExerciseSlot.materializedPrescriptions`).
- `SteadyStatePrescription.sourceWorkoutBlockTemplate`/
  `IntervalPrescription.sourceWorkoutBlockTemplate` (nullify inverses on
  `WorkoutBlockTemplate.materializedSteadyStatePrescriptions`/
  `.materializedIntervalPrescriptions`).
- `PersonalRecord.sourceSteadyStateResult`/`.sourceIntervalResult`
  (nullify, mirroring every other result type's existing pattern).

Full detail and rationale: `DELETE_RULE_MATRIX.md`'s Stage 6B section.

## 17. Architectural issues found (and resolved within scope)

Two genuine, load-bearing gaps surfaced only once live execution needed
them — both closed additively, never by redesigning anything:

1. **No path from a materialized prescription back to its template-graph
   slot.** `SubstituteExerciseUseCase`/`SubstituteActivityUseCase` both
   require the originating `ExerciseSlot`/`WorkoutBlockTemplate` as a
   parameter, but nothing on `ExercisePrescription`/
   `SteadyStatePrescription`/`IntervalPrescription` ever stored it — every
   prior call site (a materializer, or a test) already had it in hand.
   Fixed with three new, additive, `nil`-safe fields (§16).
2. **No authored `ScoreDirection` for a live, non-benchmark Functional
   Fitness result.** `FunctionalFitnessPrescription` carries a `Stimulus`
   (which does have `scoreType`) but no direction, and only
   `BenchmarkDefinition` authors one. Fixed with a small, deterministic,
   documented mapping (`FunctionalFitnessScoring`) rather than inventing
   a stored field or guessing per-instance.
3. **Interval's "log once at the end" contract couldn't satisfy
   incremental durability.** `RecordIntervalResultUseCase` expected a
   fully-built `IntervalResult` with every rep already attached; a real
   multi-interval session needs each rep durable as it happens. Fixed by
   splitting persistence into `LogIntervalRepUseCase` (per-rep, now) and
   `FinalizeIntervalResultUseCase` (session summary + PR detection,
   later, idempotent) — `RecordIntervalResultUseCase` itself is
   unchanged and still correct for any caller that already has the full
   result upfront.

## 18. Known gaps

- **Benchmark tagging at Finish is not built.** A generated Functional
  Fitness result always logs with `benchmark: nil` — correct and safe
  per the existing "never automatic" contract, but means no generated
  workout can yet show "New PR"/"First recorded" against a named
  benchmark from the live execution flow. Not a defect; a follow-up.
- **Scripted Simulator UI validation** was not possible in this
  environment (§14) — mitigated by end-to-end use-case-layer tests, not
  eliminated as a gap.
- **EMOM's "minutes completed" score** (`FunctionalFitnessScoring`
  path) counts every minute the clock entered, including one interrupted
  by an early Finish, as this pass's simplification — a true partial
  final minute isn't fractionally scored. Documented in
  `FunctionalFitnessExecutionViewModel`'s own code, not hidden.
- **A Day/seed-data observation, not a Stage 6B regression:** a
  from-scratch Simulator install on this machine showed "No sessions
  today" once the host clock crossed into a new calendar day mid-session;
  `SeedDataProvider`'s own date-relative seeding (pre-existing, Stage
  1/4F code) and `TodayViewModel`'s date-matching logic are both covered
  by the automated suite and believed correct — this reads as an
  install/timing artifact in the shared dev Simulator, not a defect
  introduced by this stage, but wasn't root-caused further given the
  scripted-UI-automation constraint above.

**Stage 6C addendum (historical clarification):** subsequent manual
Simulator acceptance testing found that the "Lower A" Session this
report's own §14 screenshot and §12 test suite validated against was a
single-exercise, hand-assembled `ExercisePrescription`, never
materialized through a slot — meaning multi-exercise navigation, block/
Session completion for a genuinely multi-exercise workout, and real
slot-based Change Exercise had never actually been proven end-to-end,
despite every individual piece (timer, persistence, substitution
validator) being correctly unit-tested in isolation. This was a real
acceptance gap this report did not catch, since its own 475-test suite
never exercised more than one exercise per block. Root cause, fix, and
new realistic acceptance fixture: `STAGE6C_ACCEPTANCE_REPORT.md`.

## 19. Commits / hashes

All ten slices plus their Xcode-project registrations, in order (this
branch, `main`):

```
fc0a0b3  feat: Stage 6B Slice 1 — execution state schema (completionContext, TimerState)
d822e93  feat: Stage 6B Slice 2 — endurance recording use cases + first-entry flag
d78f257  feat: Stage 6B Slice 3 — WorkoutTimer pure timer engine
5e80ebf  feat: Stage 6B Slice 4 — orchestrating, save-owning use cases
ee21804  feat: Stage 6B Slice 5 — Today screen + Session execution shell
7817cb3  feat: Stage 6B Slice 6 — Strength/Hypertrophy/Powerlifting execution + Change Exercise
27fc8fe  feat: Stage 6B Slice 7 — Steady State/Interval execution + Change Activity
50f84e6  feat: Stage 6B Slice 8 — Functional Fitness execution (all typed formats)
446edc9  chore: register Stage 6B Slice 1-8 source files in Xcode project
efe4d1a  feat: Stage 6B Slice 9 — completion screen + partial/missed wiring
e31af5b  chore: register Slice 9 source files in Xcode project
d99b66e  test: Stage 6B Slice 10 — end-to-end multi-block Session lifecycle tests
f28ae2d  chore: register Slice 10 test file in Xcode project
```

The pbxproj registration for Slices 1-8 is consolidated into one commit
(`446edc9`) rather than split per slice — the generated project file's
edits are cumulative and interleaved across slices, and hand-splitting
them risked corrupting it. Every commit's own source files build and
test green as of that commit's registration commit.

Documentation commit (this report + the ten updated design docs) follows
this batch; see git log for its hash.

## 20. Local / remote verification

Local: every commit above was built (`xcodebuild build`) and the full
suite run (`xcodebuild test`) at multiple checkpoints through the batch,
final state 475/475 passing, clean `git status` (only IDE-local
`xcuserdata` left untracked, correctly not committed). Remote: not yet
pushed — push is a separate, explicit step once this report is reviewed.
