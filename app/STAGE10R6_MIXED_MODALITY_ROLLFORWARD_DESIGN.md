# Stage 10R.6 — Mixed-Modality Tactical RollForward Correctness: Design / Audit

**Status: design APPROVED with locked decisions D-10R6-1 through
D-10R6-18 (below); IMPLEMENTED for 10R.6A/B/C — see
`STAGE10R6_MIXED_MODALITY_ROLLFORWARD_IMPLEMENTATION_REPORT.md` for the
full implementation report. 10R.6D (equipment-profile plumbing) was
DEFERRED by explicit product decision — see the report. Awaiting manual
acceptance before commit/push (not yet committed as of this writing).**
Checkpoint `80b2326` (Stage 10R.5) is the protected baseline this pass
builds on; nothing in it was touched.

This is TrainingOS orchestration/correctness work — the recovered 3-Day
Full Body Hypertrophy vertical (source content, load-first overlay, RM
calibration, substitutions, readiness, deload, mesocycle transitions) is
untouched by anything in this document and must remain so.

## LOCKED DECISIONS (post-approval addendum)

The audit below (§1-23) is the evidence base. The following decisions,
given by the product owner, supersede any option this document merely
compared without resolving, and are the actual implementation authority.
**Notably, they supersede §8's own "Recommendation: Model B" via
main-context `rollback()`** — that recommendation is retracted; see
D-10R6-2/D-10R6-3 and the implementation report's transaction-boundary
section for why a naive main-context rollback cannot satisfy D-10R6-4's
mandatory test, and what was built instead (an isolated scratch
`ModelContext`, never touching the caller's shared context at all).

- **D-10R6-1 (Advancement semantics)**: mixed-modality tactical
  advancement is logically ATOMIC — every eligible, non-exhausted,
  rollForward-managed component advances exactly one tactical week
  together, or none advance. Model C (independent component commits) is
  rejected.
- **D-10R6-2 (Implementation model)**: Model B in principle (allow normal
  incremental inserts; if every component succeeds, persist once; if any
  fails, discard the entire attempted advancement) — but `ModelContext
  .rollback()` must never be called on the application's shared,
  long-lived main context unless proven not to discard unrelated
  legitimate pending changes. That proof does not exist and cannot exist
  for a non-scoped `rollback()`, so main-context rollback is not used.
- **D-10R6-3 (Transaction boundary)**: the narrowest safe boundary is a
  dedicated scratch `ModelContext` constructed from the caller's own
  `context.container`, used for the entire attempt, saved exactly once on
  success and simply discarded (never saved) on any failure. Chosen over
  main-context rollback specifically because it is provably correct, not
  because it is the smallest diff.
- **D-10R6-4 (Required failure guarantee)**: an unrelated pending
  mutation U must survive a failed mixed-modality advance untouched;
  retrying after fixing the blocker must create exactly one Week N+1 for
  every eligible component. Proven by
  `MixedModalityTacticalAtomicityTests.testUnrelatedPendingMutationSurvivesAndRetryAfterFixingBlockerAdvancesExactlyOnceForEveryComponent`.
- **D-10R6-5 (Autosave)**: the scratch context has `autosaveEnabled =
  false` — no scene-phase/backgrounding/other SwiftData-internal trigger
  can persist a partial attempt through it; the caller's shared context is
  never mutated during the attempt at all, so its own autosave policy is
  irrelevant to this operation.
- **D-10R6-6 (Preflight)**: a cheap, read-only `TacticalAdvancementPreflight`
  re-checks the same deterministic "does required history exist"
  conditions the real materializers already enforce (FF exposure history,
  Interval previous-week outcome), before any mutation — never a second
  progression engine, never simulating Stage E (stimulus validation)
  twice.
- **D-10R6-7 (Functional Fitness)**: `FunctionalFitnessExposureHistoryBuilder`
  is now called for real, from both `materializeFirstWindow` and
  `rollForward`, computed fresh from the real `instance` in scope each
  time — not threaded through `TacticalMaterializationContext` as a
  static value (that field was removed; it was always empty and never
  read by any real caller).
- **D-10R6-8 (Interval)**: one new `IntervalWeekContextBuilder`, used from
  both `materializeFirstWindow` and `rollForward`, derives real
  `WeekContext` from persisted `IntervalResult`/`IntervalRepResult`
  history. `previousActualZone` is left `nil` always — see the
  implementation report's disclosed-limitation note.
- **D-10R6-9 (Parity)**: both paths call the exact same two resolvers;
  week 0 legitimately yields empty context/history through the same code
  path, not a special case.
- **D-10R6-10 (Steady-State)**: unchanged.
- **D-10R6-11/D-10R6-12 (Equipment profile)**: DEFERRED. The domain model
  has no persisted, authoritative equipment/training-environment concept
  (only `UserProfile.equipmentIncrements["barbell"]`-style coarse
  per-key increments) — nowhere near `EquipmentProfile`'s own shape
  (`equipmentType`/`roundingRule`/`bodyweightKg`), and `EquipmentProfile`
  is architecturally one value per whole week's materialization, not
  per-exercise. A partial fix (deriving only `smallestIncrementKg` from
  real data while keeping `equipmentType: .barbell` hardcoded) was
  explicitly rejected by the product owner as "turning an obvious
  placeholder into a more convincing but still incorrect representation."
  The existing hardcoded placeholder remains, unchanged, exactly where it
  was. See the implementation report.
- **D-10R6-13 (Calibration edge case)**: not touched, documented debt only.
- **D-10R6-14 (Scheduler)**: unchanged — `rollForward` still collects
  every component's newly-materialized sessions into one `inputs` array
  before a single `SchedulingPipeline.propose` call.
- **D-10R6-15/D-10R6-16/D-10R6-17 (Idempotency / exhausted components /
  readiness)**: unchanged, preserved — see the implementation report's
  regression results.
- **D-10R6-18 (Hypertrophy freeze)**: unchanged — all Stage 10R.1-10R.5
  tests remain green (933/935 total suite, 2 pre-existing skips, 0
  failures).

---

## 1. Production trace + modality context matrix

`RollTacticalWindowUseCase.swift` (read in full, both functions):

| Modality | `materializeFirstWindow` context | `rollForward` context | Correct? |
|---|---|---|---|
| Hypertrophy/Powerlifting | Real: `equipmentProfile` (from `TacticalMaterializationContext`), real `SourceRMCalibration`/`AutoregulationRatingResolver` reads | Same, real | **Yes** |
| Steady-State | `SteadyStateMaterializer.materializeAllWeeks` — whole multi-week block, one call | Excluded (`continue`) | **Yes, by design** — see §4 |
| Interval | `weekContext: { _ in .init() }` (empty) | `weekContext: { _ in .init() }` (empty) — **identical to first-window** | Correct at week 0 only (see §3); **wrong at week 1+** |
| Functional Fitness | `materializationContext.functionalFitnessCandidateExercises`/`.functionalFitnessExposureHistory` (passthrough) — but every real caller leaves both at their empty defaults | Same passthrough, same empty defaults | **Wrong at every call, including week 0** — see §2 |

**Key finding: there is no divergence between `materializeFirstWindow` and
`rollForward` for either broken modality** — both call the same empty/
under-supplied context construction. There is no "correct first-window
plumbing" to extract and reuse; both need new work (§17).

`equipmentProfile` reaching `StrengthMaterializer` is real end to end —
but the ONE real production caller that builds `TacticalMaterializationContext`
for `rollForward` (`PhaseDetailViewModel.advanceTacticalWeek`) constructs
it with a **hardcoded literal** `EquipmentProfile(equipmentType: .barbell,
smallestIncrementKg: 2.5)` (`PhaseDetailViewModel.swift:254`) — not a
real per-user value. `FunctionalFitnessMaterializer.materializeWeek`
itself takes no equipment parameter at all, so this specific hardcoding
doesn't corrupt FF content, but it does mean Hypertrophy's own real
production week-to-week rounding is currently keyed to a fake equipment
profile, not the user's real one (§11).

---

## 2. Functional Fitness — root cause

**Easy fix. Real, correct, already-tested infrastructure exists and has
zero production callers.**

`FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:)`
is a pure query over a `ProgramInstance`'s own completed sessions,
correctly excluding scheduled-but-untouched/skipped ones — its only
caller anywhere in the repo today is its own test.
`functionalFitnessCandidateExercises` has no dedicated resolver, but
`strengthCandidateExercises` doesn't either — every real call site
populates it via an unfiltered `fetch every Exercise` — so mirroring
that exact, already-accepted pattern for FF closes the candidate-pool
gap with zero new design questions.

**Root cause, precisely**: this is a call-site wiring omission
(`PhaseDetailViewModel.advanceTacticalWeek`/`.startNextHypertrophyPhase`,
`SourceRMCalibrationViewModel`) — not a missing capability.
`SeedAnnualPlanJourney.swift` is the only place that ever supplies FF
candidates today, and even there via a hand-picked literal list, never a
real query.

---

## 3. Interval — root cause

**Harder fix. No equivalent resolver exists anywhere; new production
code is required.**

`IntervalMaterializer.WeekContext`'s fields (`previousActualIntervalCount`/
`WorkDurationSeconds`/`WorkDistanceMeters`/`Zone`/`RecoveryDurationSeconds`,
`previousOutcome`) are all meant to be derived from the instance's own
most-recently-completed interval exposure — but no
"`IntervalWeekContextBuilder`"-shaped use case exists to derive them from
real persisted `IntervalResult`/`IntervalRepResult` data. Every existing
test hand-constructs `WeekContext` with literal values.

`IntervalMaterializer`'s own throw condition —
`rules.requiresSuccessfulCompletionToProgress, weekIndex > 0,
ctx.previousOutcome == nil` — **correctly excludes week 0** (there is
genuinely no prior week to reference yet), so the empty context at
`materializeFirstWindow` time is not a bug. The danger is real and live
only for `rollForward`'s calls at week 1+, for any interval template
that sets `requiresSuccessfulCompletionToProgress`. Left unfixed, such a
template throws on its first real roll — and per §7, that throw
currently aborts the ENTIRE mixed-modality advancement, not just the
Interval component.

---

## 4. Steady-State — verified correct, not a gap

Confirmed by full read of `SteadyStateMaterializer`/`SteadyStateProgressionEngine`:
every dimension (duration/distance/intensity) resolves as a pure
function of `weekIndex`/`isDeload` alone, with zero read of any live
rating, prior actual result, or autoregulation history anywhere. There
is no live per-week data Steady State could ever need that would make
its whole-block-up-front materialization, or its exclusion from
`rollForward`, incorrect. **Do not force it through weekly rollForward
for architectural symmetry — its current design is correct as-is.**

---

## 5. Hypertrophy regression — protected

Nothing in this design touches `StrengthMaterializer`, `LoadFirstOverlayEngine`,
`SourceRMCalibration`, substitution, readiness, source set autoregulation,
the M1/M2/M3 content tables, deload, or mesocycle transitions. The one
adjacent, pre-existing finding below is flagged for awareness, not fixed
here.

**New finding, out of this stage's fix scope but worth recording**: mid-
mesocycle substitution to a *different* exercise than the one calibrated
at week 0 is not currently checked — `AutoregulationRatingResolver
.weekZeroResolvedWeight`/`.previousWeekSetCount` are keyed by **template
ID**, not by the currently-resolved exercise, so a substitution silently
keeps reading the *original* exercise's week-0 resolved weight/history
rather than requiring or erroring on missing calibration for the *new*
exercise. This does not affect Family A's reference configuration in
practice and is **explicitly not in scope for Stage 10R.6** (per "do not
change substitutions") — recorded here only so it isn't lost.

---

## 6. Mix advancement invariant

**Recommended postcondition for a successful "Start Next Week":**

> Every component that was part of the eligible tactical boundary (i.e.,
> every non-`.steadyState`, non-exhausted component `TacticalWeekCompletion
> .canAdvanceTacticalWeek(for: mix)` required to be ready) has advanced
> **exactly one** tactical week, together, in the same operation — or
> **none of them have advanced at all**, and the operation reports
> failure with an explainable reason.

No component may advance zero weeks when it should, more than one week,
or independently into a tactical boundary a sibling component doesn't
share. This directly requires atomic advancement (§7/§8) — a
partial-success outcome cannot satisfy this invariant, since it would
leave siblings at different tactical weeks with no clean way for a
future "Start Next Week" tap to re-synchronize them (the gate requires
*all* eligible components ready at once, and a skewed mix could never
satisfy that again without manual intervention).

---

## 7. Atomicity / transaction audit — the central finding

Traced precisely, by direct code read:

- `rollForward`'s `for component in mix.orderedComponents` loop has **no
  `do/catch` anywhere**. A thrown materializer error (confirmed reachable
  for Interval, §3) unwinds straight out of `rollForward`, skipping every
  remaining component and the `SchedulingPipeline.propose`/
  `AcceptScheduleProposalUseCase.accept` calls entirely.
- `AdvanceTacticalWeekUseCase.advance` does not catch it either — it
  propagates to `PhaseDetailViewModel.advanceTacticalWeek`'s own
  `catch { return false }`, which swallows the error with **zero
  diagnostic** and **no rollback call**.
- The **only** explicit `context.save()` in this entire chain is
  `AdvanceTacticalWeekUseCase.advance`'s own line, reached only after
  `rollForward` returns successfully. `AcceptScheduleProposalUseCase
  .accept` never saves itself.
- Every materializer (`StrengthMaterializer`, `IntervalMaterializer`,
  `FunctionalFitnessMaterializer`) inserts objects into `context`
  **incrementally, throughout construction** — there is no existing
  seam separating "compute what the next week should contain" from
  "commit it."
- **Zero call sites for `modelContext.rollback()` exist anywhere in this
  codebase.**
- The main `ModelContext` has no explicit `autosaveEnabled` override —
  SwiftData's default (enabled) applies, and this is the same long-lived
  context injected app-wide.

### Concrete failure walkthrough (as requested)

Hypertrophy materializes Week 2 (real objects inserted into `context`,
not yet saved). Functional Fitness's materializer throws (today: because
it silently proceeds with an empty candidate pool and produces
degenerate/empty content rather than throwing — but once §2's fix lands
and adds real validation, a genuine throw becomes possible; Interval
already can throw today, §3). `rollForward` unwinds immediately. Interval
(the third, not-yet-reached component) never runs at all.

**What persists at that exact point**: Hypertrophy's Week 2 objects sit
in the shared main context's pending-insert set — not explicitly saved,
not discarded, not confined to any isolated scope. Because autosave
defaults to enabled and this is the app's single long-lived context,
those objects are vulnerable to being flushed to the on-disk store by a
*later*, independent autosave trigger (app backgrounding, scene-phase
change) that has nothing to do with this operation — **not merely a
theoretical risk given the current configuration**. Note: since
`rollForward`/`advance` are fully synchronous (no `await`/suspension
points), autosave cannot interleave *mid-loop* — the exposure window is
strictly *after* the failed call returns control to the UI, before any
retry or explicit save.

**Retry risk, concretely**: if the app is never backgrounded and the
partial in-memory state survives untouched, a same-session retry would
see Hypertrophy's Week 2 sessions as already-materialized (freshly
`.scheduled`, non-terminal) via `ProgramWeekGrouping.nextWeekIndex` —
`TacticalWeekCompletion.canAdvanceTacticalWeek` would then read
Hypertrophy as *not* ready to advance again, silently no-opping that
component on retry while the operation as a whole is still reported as
having failed — an already-skewed, hard-to-explain state. If instead an
autosave *did* flush Hypertrophy's Week 2 before relaunch, the skew
becomes **permanent**: Hypertrophy is now genuinely one tactical week
ahead of its siblings, with no existing mechanism to either roll the
others forward to match or roll Hypertrophy back.

**Feasibility of true atomic advancement**: not straightforward with the
materializers exactly as they are today (compute-and-insert are fused),
but **`ModelContext.rollback()` already exists as a built-in SwiftData
primitive and is entirely unused in this codebase** — see §8's
recommendation, which uses it directly rather than requiring materializer
restructuring.

**One precondition this design flags, not yet verified**: `rollback()`
discards *every* uncommitted change in the context back to the last
save — including anything unrelated that might coincidentally be pending
at the same moment. This is only safe if every other write path in the
app already saves immediately after each meaningful action (which
CLAUDE.md rule 20 and this project's own established discipline for
`LogSetUseCase`/`CompleteSessionUseCase`/etc. already require) — i.e.,
by the time `AdvanceTacticalWeekUseCase.advance` begins, the shared
context should hold no other unrelated pending inserts. This is a
reasonable assumption given the codebase's own established discipline,
but it is a real correctness dependency of the recommended design and
should be explicitly tested (§16, test J-adjacent), not silently trusted.

---

## 8. Failure models compared

| | Product semantics | Tactical coherence | Complexity | SwiftData feasibility | Crash recovery | Idempotency | Scheduler interaction | Retry behavior |
|---|---|---|---|---|---|---|---|---|
| **A — preflight/build-then-commit** | Matches invariant | Correct | High — requires restructuring every materializer to separate "build" from "insert" | Not directly supported; would need a parallel "candidate" representation per materializer | Clean (nothing inserted until every component's build succeeds) | Clean | Fine — one batched `propose` call as today, after all builds succeed | Clean — nothing to discard, simply retry |
| **B — allow normal incremental inserts, roll back the whole context on any failure** | Matches invariant | Correct | **Low** — no materializer changes; wrap the existing loop in `do/catch`, call `context.rollback()` on any throw, never call `.save()` on that path | **Directly supported** — `ModelContext.rollback()` already exists, unused, and does exactly this | Clean, PROVIDED the "one precondition" above holds (context has no other unrelated pending changes at operation start) | Clean | Fine — same single batched `propose` call, called only after every component's insert succeeded | Clean — `rollback()` leaves the context exactly as it was before the attempt |
| **C — per-component independent commit** | **Violates the invariant directly** (§6) | Broken — siblings can end up at different tactical weeks with no re-sync path | Low | Trivial (already close to current behavior) | Leaves permanently skewed state on partial failure | Broken — a partially-advanced mix can never cleanly satisfy `canAdvanceTacticalWeek` again | **Violates a hard constraint** (§13 — `ConcurrentScheduler` requires seeing every component's inputs in one batched call to correctly avoid cross-component day-collisions; two separate `propose` calls lose that guarantee) | Unsafe — a retry could double-schedule or leave the mix permanently inconsistent |

### Recommendation: **Model B**

Confirms your stated preference (atomic, "Start Next Week" is one
coordinated tactical week) and is verified technically feasible with the
**smallest possible change** — no materializer restructuring, reusing an
existing-but-unused SwiftData primitive. Model A achieves the same
semantics with materially higher implementation risk (every materializer
needs a build/commit split) for no additional correctness benefit over
B. Model C is rejected outright — it violates the invariant, breaks
idempotency, and violates the scheduler's own hard requirement (§13).

---

## 9. Preflight

`TacticalWeekCompletion.canAdvanceTacticalWeek` currently means, precisely,
"every real Session in the current tactical week is terminal" — a purely
session-status-based check. It does **not** mean "all information
required to materialize the next week exists." Today this gap is latent
(FF/Interval don't yet validate their inputs and don't yet throw
correctly), but once §2/§3's real fixes land, a genuinely empty FF
candidate pool or an undiscoverable Interval prior outcome become real,
if rare, possibilities.

**Recommendation**: do not introduce a full separate
`canMaterializeNextTacticalWeek` derived query that re-runs the entire
materialization logic speculatively — that duplicates real work and
still can't catch every failure mode (e.g., a scheduling conflict only
`ConcurrentScheduler` itself can detect). Instead:
1. A **cheap, targeted preflight check** for the common, predictable
   blockers only (e.g., "does this FF component have at least one
   candidate exercise at all") — enough to proactively disable the
   button for the obvious case, satisfying "do not hide a materialization
   prerequisite behind a runtime crash" for the cases that are cheap to
   check.
2. **Model B's atomic rollback as the safety net** for anything the
   cheap preflight doesn't catch (a genuine mid-materialization failure,
   a scheduling infeasibility, etc.) — the operation fails cleanly, atomically,
   with a reportable reason, rather than corrupting state.

This combination avoids both "silently materialize broken content" and
"duplicate the entire materialization pipeline just to predict its own
outcome."

---

## 10. Calibration blocking behavior

`RollTacticalWindowUseCase.rollForward` has **no calibration check at
all**, confirmed by direct read. This is **not currently a reachable live
bug for the normal case**: week N>0's progression inputs
(`AutoregulationRatingResolver.weekZeroResolvedWeight`/
`.previousWeekSetCount`) are keyed off week 0's own already-materialized,
already-calibration-gated resolved values — week N>0 is structurally
unreachable without week 0 (and therefore calibration) already having
succeeded. **Recommendation (Option A, per your stated preference,
confirmed correct given the architecture): no new calibration gate is
needed inside `rollForward` itself** — the existing week-0 gate already
makes this scenario impossible under normal flow, and adding a redundant
check would be defensive without a concrete threat model. If the
substitution-related edge case in §5 is ever addressed in a future
stage, it would be the more precise place to add a calibration check
(scoped to the newly-substituted exercise), not a blanket gate here.

---

## 11. Equipment / environment context

Confirmed real for Hypertrophy (`equipmentProfile` flows correctly into
`StrengthMaterializer` in both first-window and rollForward paths) —
**but the value itself is currently fake** at the one real production
call site: `PhaseDetailViewModel.advanceTacticalWeek` hardcodes
`EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)`
rather than reading a real per-user value. `FunctionalFitnessMaterializer`
takes no equipment parameter at all today, so this hardcoding doesn't
corrupt FF content specifically, but it does mean Hypertrophy's own real
rounding/increment behavior in production is currently keyed to a
placeholder, not the user's actual equipment. **Not solving Home Gym UX
here** (explicitly out of scope), but flagging that "materialize FF using
a fake/default candidate pool" (which this stage fixes) has a sibling
issue — "materialize Hypertrophy using a fake/default equipment profile"
— which is a real, adjacent, currently-live gap worth a decision (§23).

---

## 12. Readiness

Confirmed, by direct grep of `RollTacticalWindowUseCase.swift`,
`StrengthMaterializer.swift`, `FunctionalFitnessMaterializer.swift`,
`IntervalMaterializer.swift`: **zero references to readiness anywhere**.
Readiness remains exactly where the already-approved architecture puts
it — execution-time only. This design introduces no readiness
dependency into week materialization; nothing here should move it there.

---

## 13. Scheduling implications

`SchedulingPipeline.propose(mix:inputs:constraints:)` passes the **entire**
batch of every component's newly-materialized sessions into **one**
`ConcurrentScheduler.schedule` call. `ConcurrentScheduler`'s own
documented purpose is cross-component conflict resolution — hard
constraints, urgency, priority, interference/recovery preference, all
computed together over the full batch with one deterministic tie-break.
**This is a hard architectural constraint, not a preference**: any
failure model that would schedule successful components independently,
in separate `propose` calls, loses this cross-component visibility and
risks a real day-collision the current single-batched-call design
specifically prevents. This directly rules out Model C (§8) and confirms
Model B's design (one batched `propose` call, reached only after every
component's materializer succeeds) preserves scheduling correctness
exactly as today.

---

## 14. Idempotency

Model B preserves Stage 10R.4's existing guarantees unchanged: a
successful "Start Next Week" advances every eligible component exactly
once (the same batched insert + single save as today, just now wrapped
in try/rollback); an immediate second invocation sees every component's
new week already materialized (non-terminal) and reports `.notEligible`
for the whole mix, advancing nothing (same mechanism as today — the gate
is derived, not stored). A failed attempt followed by a retry is now
**also safe**: `context.rollback()` on the failure path guarantees the
failed attempt's partial inserts never persisted, so a retry starts from
the exact same, unadvanced state — no duplicate-Week-2 risk, closing the
gap identified in §7.

---

## 15. Exhausted-component behavior

Unchanged from Stage 10R.4's already-accepted design:
`TacticalWeekCompletion.canAdvanceTacticalWeek(for: mix)` already excludes
an exhausted component from the "must be ready" set (§2 of the Stage
10R.4 design), so Hypertrophy reaching exhaustion after Mesocycle 3 does
not block a still-progressing Running/Interval sibling. Model B's
atomicity applies only to the components that are actually **eligible
and attempted** in a given roll — an exhausted component is never part
of that attempt at all, so it is never at risk of being "rolled back"
into existing; nothing about this design reopens or changes that
already-accepted behavior.

---

## 16. Real mix scenarios (test matrix design, §16 of the request)

| # | Scenario | Expected outcome under Model B |
|---|---|---|
| A | Hypertrophy + Functional Fitness, both ready, FF context now real | Both advance exactly one week, together, one save |
| B | Hypertrophy + Interval, both ready, Interval context now real (no gated template) | Both advance together |
| C | Functional Fitness + Interval, both ready | Both advance together, no Hypertrophy involved |
| D | Hypertrophy + Functional Fitness + Interval, all ready | All three advance together, one batched schedule call |
| E | One exhausted (Hypertrophy, post-M3) + one progressing (Interval) | Only Interval is in the eligible set at all (§15); it advances alone; Hypertrophy is untouched, not "rolled back" |
| F | One component lacks required materialization context (e.g., FF has zero candidates) | Preflight (§9) disables the action entirely if detected cheaply; if not caught by preflight, the attempt fails atomically (rollback), **no component advances**, a reportable reason is returned |
| G | One component throws mid-materialization (e.g., a gated Interval template with no derivable prior outcome) | Atomic failure — rollback, no component advances, reportable reason |
| H | Failure (per G) followed immediate retry with no state change | Same failure again, still no component advances, still zero duplication |
| I | Successful roll followed by an immediate second tap | Second tap reports `.notEligible` for every component, nothing advances a second time |
| J | Mixed-modality scheduling collision (two components' sessions would compete for the same day under real availability constraints) | `ConcurrentScheduler` resolves it exactly as today, since it still sees the complete batch in one `propose` call — no new failure mode introduced by this design |
| K (added) | An unrelated, already-pending (but not-yet-saved) change exists in the shared context when a roll fails | Must NOT be discarded by the rollback — proves the "no other unrelated pending changes" precondition (§7) holds under real app write discipline |

---

## 17. First-window vs. rollForward parity

Already covered precisely in §1/§2/§3: there is no working pattern to
extract from `materializeFirstWindow` for either FF or Interval — both
functions currently under-supply context identically. The fix (a future
implementation stage, not this one) should build ONE shared context-
building seam per modality (an FF candidate/history resolver call, and a
new Interval `WeekContext` resolver) and have **both** `materializeFirstWindow`
and `rollForward` call the same seam — since week 0 for both modalities
genuinely needs "no prior week" semantics (empty context is correct
there) while week N>0 needs the real derivation, a single resolver
function that naturally returns an empty/default result when no prior
data exists (rather than two separately-maintained code paths) is the
right shape, avoiding exactly the "subtly different context construction"
the request warns against.

---

## 18. Required domain changes (for a future implementation stage — not built now)

1. A `do/catch` wrapper around `RollTacticalWindowUseCase.rollForward`'s
   per-component loop (or around the whole call in `AdvanceTacticalWeekUseCase.advance`)
   that calls `context.rollback()` on any thrown error and returns a
   typed failure result instead of propagating/swallowing silently.
2. A real `FunctionalFitnessCandidateExercises` resolver (mirroring the
   existing unfiltered-fetch pattern already used for strength) + wiring
   `FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:)`
   into every real `TacticalMaterializationContext` construction site.
3. A new `IntervalWeekContextBuilder`-shaped use case deriving `WeekContext`
   from an instance's own real, persisted `IntervalResult` history —
   genuinely new production code, not a wiring fix.
4. A real, per-user `EquipmentProfile` lookup replacing the hardcoded
   literal in `PhaseDetailViewModel.advanceTacticalWeek` (pending your
   decision, §23).
5. A cheap preflight check (§9) for the common, predictable blockers,
   surfaced as new derived state analogous to `canAdvanceTacticalWeek`.

**No changes** to any materializer's fundamental insert-as-you-build
shape, to `SetPrescription`/source content, to `LoadFirstOverlayEngine`,
to `SourceRMCalibration`, or to `ConcurrentScheduler`'s own algorithm.

---

## 19. Required production wiring (for the future implementation stage)

`PhaseDetailViewModel.advanceTacticalWeek` (and any other real caller of
`AdvanceTacticalWeekUseCase.advance`) needs to: (a) surface a real
failure reason rather than a bare `Bool`, (b) supply real FF/Interval
context via the new resolvers, (c) ideally supply a real equipment
profile. `AdvanceTacticalWeekUseCase.advance` needs the rollback-on-failure
wrapper.

---

## 20. Proposed implementation slices (for a future stage)

**10R.6A — Atomicity**: wrap `rollForward`'s invocation in a rollback-
on-failure guard inside `AdvanceTacticalWeekUseCase`; add the cheap
preflight check; add a typed failure result. Independently testable and
committable — this alone closes the atomicity/idempotency/retry-safety
gap even before FF/Interval content is fixed (an Interval throw would
now fail safely instead of corrupting state).

**10R.6B — Functional Fitness wiring**: wire the existing
`FunctionalFitnessExposureHistoryBuilder` + a real unfiltered-candidate
fetch into every real `TacticalMaterializationContext` construction site.

**10R.6C — Interval WeekContext resolver**: new `IntervalWeekContextBuilder`
deriving real `WeekContext` from persisted history; wire into both
`materializeFirstWindow` and `rollForward` via the same seam (§17).

*(Equipment-profile realism, §11/§23, is flagged as a decision point —
not pre-assigned to a slice until you decide whether it belongs in this
stage's scope or is deferred alongside Home Gym UX.)*

---

## 21. Test matrix

See §16's table — 11 scenarios (A-K), each with an explicit expected
outcome under Model B. Additional unit-level coverage needed for the
rollback wrapper itself (empty-context Interval throw → zero persisted
Sessions for ANY component in that mix, confirmed via a fresh-context
reload) and for the FF/Interval resolvers' own correctness once built
(out of this design's immediate scope, since those are 10R.6B/6C's own
implementation-stage test matrices).

---

## 22. Unresolved questions

1. Should the cheap preflight check (§9) be exhaustive enough to predict
   every possible materialization failure, or deliberately narrow (only
   the cheap, common cases), relying on Model B's rollback for
   everything else? This design recommends narrow + rollback-as-safety-net,
   but the exact boundary of "cheap enough to preflight" is a judgment
   call for whoever implements 10R.6A.
2. The mid-mesocycle substitution/calibration edge case (§5) — explicitly
   out of this stage's scope, but unresolved and worth a future decision.
3. Whether `context.rollback()`'s "discard everything uncommitted"
   semantics could ever legitimately conflict with unrelated pending
   state elsewhere in the app (§7's precondition) — this document
   asserts it's safe given the codebase's own established immediate-save
   discipline, but this has not been proven by a dedicated test yet
   (test K, §16).

## 23. Decisions genuinely required from you

1. **Confirm Model B (atomic advancement via `context.rollback()`)** as
   the implementation direction (§8) — this is the central technical
   decision of this audit.
2. **Confirm the preflight approach** (cheap targeted checks + rollback
   as the safety net, not a full speculative re-materialization) (§9).
3. **Decide whether to fix the hardcoded equipment profile** in
   `PhaseDetailViewModel.advanceTacticalWeek` as part of this same stage,
   or explicitly defer it alongside Home Gym UX (§11) — it's a real,
   live gap but arguably a different-shaped fix than the FF/Interval
   context work.
4. **Authorize (or decline) proceeding to implementation** of slices
   10R.6A/6B/6C (§20) in a future stage, once the above are settled.
