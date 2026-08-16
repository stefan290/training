# Workout Completion Pipeline

Stage 6A: what actually happens, and in what order, when a Session
finishes — full or partial — plus the one real schema gap this pass
found. **Design pass — nothing here is implemented yet.**

## 1. The key finding: most of "completion" already happens live, per set/result

`RecordSetResultUseCase.recordSet` and `RecordFunctionalFitnessResultUseCase.recordResult`
are already called **the moment each set/result is logged**, not batched
up and flushed at Session end — each one already, today:

- Gets-or-creates the right permanent profile
  (`ExercisePerformanceProfile`/`ActivityPerformanceProfile`/
  `BenchmarkPerformanceProfile`) via `PerformanceProfileStore`.
- Attaches the result and stamps `lastPerformedAt`.
- Runs `ScoringEngine` PR detection and creates a `PersonalRecord` when
  warranted.

So `CompleteSessionUseCase` (Stage 6B, not yet built) is **not** where
performance history gets written — that already happened, set by set,
before Finish is ever tapped. What it actually needs to do, once, is
much smaller than "commit everything":

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
   which results were logged this session, which (if any) were new
   PRs — annotated with the first-entry distinction
   (`FUNCTIONAL_FITNESS_EXECUTION_FLOW.md` §8) — and the progression
   preview, so the completion screen renders from one call's output
   rather than re-querying five different places.
5. The **caller** (a ViewModel action) issues exactly one
   `try modelContext.save()` after this call returns — the same
   convention every existing `RecordXResultUseCase` already follows
   (none of them call `save()` themselves). This one `save()` is the
   transaction boundary the kickoff's §26 asks for: everything from
   step 1-2 above either commits together or (on a thrown/interrupted
   save) rolls back together, and it never partially double-writes
   because nothing in steps 1-4 was ever written twice — status fields
   are simple assignments, not increments or appends.

**Nothing in `CompleteSessionUseCase` re-records a `SetResult`/
`SteadyStateResult`/`IntervalResult`/`FunctionalFitnessResult`** — those
already exist by the time Finish is tapped. This is the answer to §26's
"avoid partial double-writing": there is only one writer per fact
(the per-set/per-result recording use case), and completion never
duplicates it.

## 2. The one real gap: `RecordSteadyStateResultUseCase`/`RecordIntervalResultUseCase` don't exist yet

Confirmed by grep: only test code attaches `SteadyStateResult`/
`IntervalResult` (`WorkoutBlock.attachSteadyStateResult`/
`.attachIntervalResult`, directly, with no `PerformanceProfile`
fold-in). Stage 6B must add both, mirroring `RecordSetResultUseCase`'s
exact shape:

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
    ) -> SteadyStateResult
    // get-or-create ActivityPerformanceProfile, attach, stamp lastPerformedAt,
    // ScoringEngine PR check exactly like RecordSetResultUseCase.
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
    ) -> IntervalResult
}
```

Both belong in `Application/UseCases/`, both are the **only** place
`ENDURANCE_EXECUTION_FLOW.md`'s Finish action should call into — never a
direct `attachSteadyStateResult`/`attachIntervalResult` call from a
ViewModel.

## 3. Progression preview — read-only, never a re-materialization

"What changes next time" (§31, completion screen) calls the existing
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
  already wrote them live. Stage 6 does not duplicate or trigger that
  regeneration itself.
- Displayed per exercise/activity as a plain reason-coded row
  (`ProgressionReasonCode` + the recommended value), matching frame 12's
  "What changes next time" list exactly — never implementation jargon,
  always the same reason-code-to-plain-language mapping the Why sheet
  already uses.

## 4. Completion screen contents (design source, frame 12)

Assembled entirely from `CompletionSummary` (§1) plus the Session's own
already-materialized data — no new persisted "completion record" type:

```
Session complete
<Session.name>
<elapsed> · <block count> · <working set count>     (computed from orderedBlocks)

[if a genuine PR]  Personal record
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

## 5. Partial completion (§27) — same pipeline, smaller input

A "Finish partial" completion runs **exactly** §1's pipeline, with
`context: .partial` — no separate code path. The `CompletionSummary`
naturally reflects fewer blocks/results because that's genuinely what
happened; nothing about the pipeline branches on partial vs. full beyond
step 1 (marking the remaining blocks `.skipped` instead of leaving them
untouched) and the stored `completionContext`. Progression preview (§3)
only ever covers exercises that actually got a result this session —
an exercise whose block was skipped entirely simply has nothing to
preview, not a fabricated "no change" row.

**Stage 6 does not invent progression policy for a partial session** —
per the kickoff's explicit instruction, it exposes the structured
`completionContext`/per-exercise result set to whatever calls
`ProgressionEngine` next; if a future pass wants the engine itself to
treat a partial session's results differently (e.g. discount a single
logged set vs. a full prescribed set), that is a new, explicit engine
decision, not something this pipeline silently encodes today by, say,
omitting the preview or applying a discount factor.

## 6. Feeding downstream consumers (§26's remaining bullets)

All of these already work by construction, once §1/§2 above are wired —
none need new plumbing beyond what's described:

- **`ProgressionEngine`**: reads `ExercisePerformanceProfile`/
  `ActivityPerformanceProfile` history, already updated live (§1).
- **`FunctionalFitnessProgrammingSystem`/`FunctionalFitnessDecisionEngine`**:
  `FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:)`
  already filters on `Session.status == .completed` — a `.partial`
  completion still satisfies `== .completed` (§1 of
  `SESSION_STATE_MACHINE.md`: partial is a `completionContext`, not a
  different `status`), so a partially-completed Functional Fitness block
  that nonetheless has a real `FunctionalFitnessResult` attached
  correctly contributes to variance-exposure history the moment §1 runs;
  a block left `.skipped` (never attempted) correctly contributes
  nothing, exactly matching the builder's own "never assume a scheduled
  workout that was skipped counts as completed exposure" rule.
- **Tactical/planner adherence**: `LongTermPlanner`/`PHASE_PLANNING_RULES.md`'s
  missed-progress signal already reads `Session.status` — `.completed`
  (full or partial) vs. `.abandoned`/`.missed` is exactly the
  distinction it needs, already available with no new reading code.

## 7. What this pipeline explicitly does not do

- Does not call `context.save()` itself (§1 — the caller's job, once).
- Does not re-run or duplicate any per-set/per-result recording.
- Does not write a new `SetPrescription`/materialize a future Session
  (§3 — that stays Stage 5's tactical-regeneration concern).
- Does not fabricate a result for a block that was never attempted
  (`.skipped` blocks contribute nothing to `CompletionSummary` beyond
  their own status).
- Does not decide *when* a tactical window regenerates — that remains
  `TacticalWindowTriggerEvaluator`'s existing, separate concern
  (`TACTICAL_PLANNING_HANDOFF.md` §2's event-driven trigger,
  `.mixOrPreferenceChanged`-style — a Session completing is not itself
  one of the six named triggers, and this pass does not add a seventh
  without product sign-off; flagged in the decision memo §10 as a
  genuinely open question worth asking the product owner, since "does
  finishing today's session ever need a fresh tactical window" seems
  plausible but is not in the locked trigger list).
