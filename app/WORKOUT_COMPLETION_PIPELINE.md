# Workout Completion Pipeline

Stage 6A: what actually happens, and in what order, when a Session
finishes — full or partial — plus the save-boundary convention that
makes logged work crash-safe throughout, not only at the end.
**Design pass — nothing here is implemented yet.**

**Status: RESOLVED.** §1's save-boundary convention supersedes this
document's original "one save() at Session completion" proposal — see
`STAGE6A_DECISION_MEMO.md` §1d for the decision record.

## 1. Save-boundary convention — incremental durability, resolved

**A successfully logged set/result must never depend on completing the
whole Session to become durable.** A single final `save()` is not the
only persistence boundary.

**Who saves, and when** — one orchestrating use case per meaningful
user action, each owning its own `save()` as its final step:

| Meaningful action | Orchestrating use case | Wraps (pure mutation, no `save()`) |
|---|---|---|
| Log a strength set | `LogSetUseCase` | `RecordSetResultUseCase` |
| Log an endurance/interval result | `LogEnduranceResultUseCase` | `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase` (§2 — new this stage) |
| Log a Functional Fitness result | `LogFunctionalFitnessResultUseCase` | `RecordFunctionalFitnessResultUseCase` (existing) |
| Apply a substitution/scaling choice | `ApplySubstitutionUseCase` | `SubstituteExerciseUseCase`/`SubstituteActivityUseCase` (existing) |
| A block's status changes (start/complete/skip) | `CompleteBlockUseCase` (and its block-start equivalent) | Direct `WorkoutBlock.status`/`.completionContext` mutation |
| A Session's status changes (start/finish-as-partial/finish-full) | `ChangeSessionStatusUseCase` / `CompleteSessionUseCase` | Direct `Session.status`/`.completionContext`/`.completedAt` mutation |

**Why this shape, not the original "use cases never save" convention
carried over unchanged:** every existing `RecordXResultUseCase` (Stage
1-5) is reused outside live execution too (seed data, tests, future
import) — those callers legitimately want to batch several inserts
before one `save()`, so the low-level recording use cases correctly stay
pure mutation. Live, interactive execution is different: a real person
is tapping through a workout in real time, with real crash exposure
(backgrounding, a call, a dying battery) between actions — so Stage 6
introduces a **second, thin layer** of execution-specific orchestrating
use cases that each wrap exactly one low-level mutation and immediately
follow it with `try modelContext.save()`. ViewModels call only the
orchestrating layer; they never call a low-level `RecordXResultUseCase`
directly, and they never call `save()` themselves.

**What never triggers a save:**
- Every UI tick (a timer's periodic redraw — `TIMER_ARCHITECTURE.md` §2/§5).
- Transient, unconfirmed input (a stepper mid-adjustment, text being
  typed into a note field before it's submitted) — only a *confirmed*
  action saves.

**`CompleteSessionUseCase`'s own save is the final consistency/commit
point, not the first durability point** — every result row logged
earlier in the session, every block-status change, every substitution
choice is already durable by the time Finish is tapped. What
`CompleteSessionUseCase` still needs to do and save, once:

```
CompleteSessionUseCase.complete(
    session: Session,
    context: SessionCompletionContext,   // .full or .partial (SESSION_STATE_MACHINE.md §2)
    asOf: Date,
    modelContext: ModelContext
) -> CompletionSummary
```

1. For every block still `.pending`/`.active` (only possible when
   `context == .partial`): set `status = .skipped` — never silently
   left in a stale in-progress state.
2. `session.status = .completed`; `session.completionContext = context`;
   `session.completedAt = asOf`.
3. Compute the **progression preview** (§3) for each exercise/activity
   touched this session — read-only, nothing written back to any
   `SetPrescription`.
4. Return a `CompletionSummary` (plain value, not persisted) bundling:
   which results were logged this session, which (if any) were new PRs
   — each annotated with whether it was a genuine improvement or a
   first-ever entry (§4 — the resolved PR-presentation distinction) —
   and the progression preview, so the completion screen renders from
   one call's output rather than re-querying five different places.
5. `try modelContext.save()` — `CompleteSessionUseCase`'s own final
   step, not the caller's.

**Nothing in `CompleteSessionUseCase` re-records a `SetResult`/
`SteadyStateResult`/`IntervalResult`/`FunctionalFitnessResult`** — those
already exist, already durable, by the time Finish is tapped. This is
the answer to "avoid partial double-writing": there is exactly one
writer per fact (the per-action orchestrating use case), and completion
never duplicates it — it only performs the small amount of session-level
bookkeeping that couldn't have happened any earlier.

## 2. The one real gap: `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase` don't exist yet

Confirmed by grep: only test code attaches `SteadyStateResult`/
`IntervalResult` (`WorkoutBlock.attachSteadyStateResult`/
`.attachIntervalResult`, directly, with no `PerformanceProfile`
fold-in). Stage 6B must add both, mirroring `RecordSetResultUseCase`'s
exact shape — as pure, non-saving mutation, matching the low-level
convention in §1's table:

```swift
enum RecordSteadyStateResultUseCase {
    static func recordResult(
        _ result: SteadyStateResult,
        for workoutBlock: WorkoutBlock,
        activityType: ActivityType,
        performanceContext: String?,
        scoringDirection: ScoringDirection,   // duration-at-intensity's own direction — see §5
        performanceProfile: PerformanceProfile,
        modelContext: ModelContext
    ) -> (result: SteadyStateResult, isFirstEverEntry: Bool)
    // get-or-create ActivityPerformanceProfile, attach, stamp lastPerformedAt,
    // ScoringEngine PR check exactly like RecordSetResultUseCase.
    // isFirstEverEntry == (existingBest == nil at the moment of comparison) — §4.
}

enum RecordIntervalResultUseCase {
    static func recordResult(
        _ result: IntervalResult,
        for workoutBlock: WorkoutBlock,
        activityType: ActivityType,
        performanceContext: String?,
        scoringDirection: ScoringDirection,
        performanceProfile: PerformanceProfile,
        modelContext: ModelContext
    ) -> (result: IntervalResult, isFirstEverEntry: Bool)
}
```

Both belong in `Application/UseCases/`, both are the **only** place
`LogEnduranceResultUseCase` (§1) should call into — never a direct
`attachSteadyStateResult`/`attachIntervalResult` call from a ViewModel.

**Existing recording use cases also widen their return value** the same
way, non-breaking (an additional tuple member / return field): `RecordSetResultUseCase.recordSet`
and `RecordFunctionalFitnessResultUseCase.recordResult` additionally
report whether the just-recorded result's `existingBest` (computed
internally, already, before deciding `isPersonalRecord`) was `nil` —
this is what powers §4's first-entry-vs-genuine-PR presentation split,
with zero change to the underlying `PersonalRecord`/`isPersonalRecord`
data.

## 3. Progression preview — read-only, never a re-materialization

"What changes next time" (completion screen) calls the existing
`ProgressionEngine`/`DoubleProgressionEngine` exactly as
`STRENGTH_EXECUTION_FLOW.md` §2 does for the suggested-load display —
same engine, same `ProgressionInput`/`ProgressionOutput` shape, just
fed this session's own just-logged results as `latestResults` instead
of the prior session's. The output is **shown, never written**:

- No new `SetPrescription` is created or edited.
- The *next* tactical window's real, materialized prescriptions are
  computed later, by the existing materializer/tactical-regeneration
  path (`TacticalWindowPolicy`/`TACTICAL_PLANNING_HANDOFF.md`, Stage 5,
  already built) — which will see this session's results already sitting
  in `ExercisePerformanceProfile` whenever it next runs, because §1
  already wrote them live, incrementally, as each set was logged. Stage
  6 does not duplicate or trigger that regeneration itself.
- Displayed per exercise/activity as a plain reason-coded row
  (`ProgressionReasonCode` + the recommended value), matching frame 12's
  "What changes next time" list exactly — never implementation jargon,
  always the same reason-code-to-plain-language mapping the Why sheet
  already uses.

## 4. Completion screen contents (design source, frame 12) — resolved PR presentation

Assembled entirely from `CompletionSummary` (§1) plus the Session's own
already-materialized data — no new persisted "completion record" type:

```
Session complete
<Session.name>
<elapsed> · <block count> · <working set count>     (computed from orderedBlocks)

[if isFirstEverEntry]   First recorded result
                        <Exercise/Benchmark> · <value>
                        (neutral copy — a baseline, not a celebration)

[if a genuine PR, existingBest != nil]   Personal record
                        <Exercise/Benchmark> · <value>
                        <plain-language comparison to the previous best>

What changes next time                               (§3, read-only preview)
  <Exercise>   <ProgressionReasonCode, plain language>   <recommended value>
  ...

[if HealthKit write enabled]  Saved to Apple Health   (toggle, informational)

<phase/week context>  Week N of <Phase> · M of K sessions done   (read from
                        TrainingPhase/TrainingMixComponent, already existing)

[ Done ]   [ Add note ]
```

The underlying data (`PersonalRecord`/`isPersonalRecord`) is identical
in both branches — `isFirstEverEntry` (§2) only decides which of the two
copy blocks renders. `ScoringEngine`'s Rx/Scaled compatibility rule
(§7 of `FUNCTIONAL_FITNESS_EXECUTION_FLOW.md`) governs which prior
results even count as "the previous best" in either branch, unchanged.

## 5. Partial completion — same pipeline, resolved per-modality progression boundary

A "Finish as Partial" completion runs **exactly** §1's pipeline, with
`context: .partial` — no separate code path, and each affected block
gets its own `completionContext` (`.full`/`.partial`, `SESSION_STATE_MACHINE.md`
§2) set the moment it's individually finished. `CompletionSummary`
naturally reflects fewer blocks/results because that's genuinely what
happened.

**Execution never computes a progression outcome itself — it only
reports actual results honestly, and each `ProgrammingSystem`'s own
engine already has (or structurally doesn't need) a conservative
default for incomplete input:**

| System | Existing mechanism | Behavior on partial input |
|---|---|---|
| Strength | `DoubleProgressionEngine.recommend` | Already returns `.hold` the instant `targets.count != latestResults.count` — a partial strength block already gets the conservative outcome, no new code. |
| Interval | `IntervalProgressionEngine.evaluateSessionOutcome(completedCount:totalCount:worstRpe:)` | Already graduated and deterministic: a completion fraction maps to `.progress`/`.hold`/`.repeatSession`/`.reduceIntensity`/`.reduceIntervalCount`; `totalCount == 0` (nothing attempted) already yields `.calibrationRequired`. Execution's only job is reporting accurate `completedCount`/`totalCount`/`worstRpe`. |
| Steady state | `SteadyStateProgressionEngine`'s resolve functions | Do not consume actual results at all — next week's duration/distance/intensity is already a pure function of configured rules + week index. A partial steady-state session has no bearing on this engine's contract; there is nothing to make conservative because nothing here reads "how much happened" in the first place. |
| Functional Fitness | `FunctionalFitnessDecisionEngine` + `FunctionalFitnessExposureHistoryBuilder` | Reasons over exposure history (already filtered to `Session.status == .completed`, unaffected by full-vs-partial), not a completion fraction — a partial FF result is still a real stimulus exposure and correctly continues to count toward variance-balancing decisions. |

No new `ProgressionInput` field, no new engine parameter, no new reason
code is introduced by partial-session support — every system's existing
"insufficient information" branch already satisfies "default to a
conservative outcome rather than pretending the Session was fully
completed." An exercise/activity whose block was `.skipped` entirely
(never attempted) simply has nothing to preview at all — never a
fabricated "no change" row.

## 6. Feeding downstream consumers

All of these already work by construction, once §1/§2 above are wired —
none need new plumbing beyond what's described:

- **`ProgressionEngine`**: reads `ExercisePerformanceProfile`/
  `ActivityPerformanceProfile` history, already updated live (§1).
- **`FunctionalFitnessProgrammingSystem`/`FunctionalFitnessDecisionEngine`**:
  `FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:)`
  already filters on `Session.status == .completed` — a `.partial`
  completion still satisfies `== .completed` (`completionContext` is a
  separate field, never a different `status`), so a partially-completed
  Functional Fitness block that nonetheless has a real
  `FunctionalFitnessResult` attached correctly contributes to
  variance-exposure history the moment §1 runs; a block left `.skipped`
  (never attempted) correctly contributes nothing.
- **Tactical/planner adherence**: `LongTermPlanner`/`PHASE_PLANNING_RULES.md`'s
  missed-progress signal already reads `Session.status` — `.completed`
  (full or partial) vs. `.missed`/`.skipped` is exactly the distinction
  it needs, already available with no new reading code.
- **Missed-session recording**: execution's role is limited to writing
  `.skipped`/`.missed` (`SESSION_STATE_MACHINE.md` §7) — it never
  computes a reflow proposal itself; that stays
  `SchedulingPipeline`/`LongTermPlanner`'s job entirely.

## 7. What this pipeline explicitly does not do

- Does not defer every write to one final `save()` — §1's incremental
  convention is the resolved model; `CompleteSessionUseCase`'s own
  `save()` is the last commit, not the only one.
- Does not re-run or duplicate any per-set/per-result recording.
- Does not write a new `SetPrescription`/materialize a future Session
  (§3 — that stays Stage 5's tactical-regeneration concern).
- Does not fabricate a result for a block that was never attempted
  (`.skipped` blocks contribute nothing to `CompletionSummary` beyond
  their own status).
- Does not compute a progression outcome itself for a partial result —
  it reports facts; the relevant `ProgrammingSystem`'s own engine
  decides (§5).
- Does not decide *when* a tactical window regenerates — that remains
  `TacticalWindowTriggerEvaluator`'s existing, separate concern. A
  Session completing is not itself one of the six locked
  `TacticalWindowTrigger` cases, and this pass does not add a seventh
  without product sign-off (still deferred, `STAGE6A_DECISION_MEMO.md` §4).
- Does not implement missed-session reflow logic (§6's last bullet).
