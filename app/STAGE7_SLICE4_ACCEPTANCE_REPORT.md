# Stage 7 (Tactical Planning Orchestration), Slice 4 — acceptance report

**Manually accepted** after five rounds of Simulator acceptance testing.
Slice 4's stated goal was a read-only Annual Plan / Current Phase / Week
UI; acceptance testing surfaced real scheduling and planning-architecture
defects along the way, each root-caused and fixed in place rather than
patched at the UI layer.

## 1. What Slice 4 delivers

- **Annual Plan** (`PlanView`) — Completed / Active / Upcoming phases,
  every card tappable regardless of configuration state.
- **Phase Detail** (`PhaseDetailView`/`PhaseDetailViewModel`) — branches
  on `phase.status`, never a parallel per-status mechanism. An active
  phase shows its real tactical window, recommended-vs-selected mix, and
  every accepted component's real program. A completed phase shows its
  historical mix, untouched. An **upcoming** phase shows a genuine
  strategic preview (§4 below) rather than a dead end.
- **Week** (`WeekView`/`WeekViewModel`) — Previous/This/Next Week
  navigation, with a center label derived purely from `weekOffset`
  (`0` → "This Week", `±1` → "Next"/"Previous Week", further away → the
  real calendar date range) so it can never misdescribe which week is on
  screen regardless of how the user navigated there. Strictly read-only:
  browsing never materializes or mutates anything.
- **Program Detail** (`ProgramDetailView`) — gained a `previewDefinition:`
  initializer so the same template-preview rendering already used for an
  active program's not-yet-materialized future week also serves an
  upcoming phase's recommended-but-not-yet-selected program, with no
  duplicated view logic.

## 2. Scheduling defects found and fixed during acceptance

Two real `ConcurrentScheduler` defects were found while verifying Week
against the real materialized schedule, both fixed as hard constraints
alongside the engine's existing ones (day-capacity, spacing, availability
— never a special case):

- **Origin-week compression**: a component whose materializer produces
  several weeks in one call (Steady State's whole natural block) had no
  floor keeping a later week's session from sliding into an earlier
  week's calendar days. Fixed via `originWeekFloorOffset`.
- **Training debt**: a session delayed out of a phase's shortened first
  calendar week (an unavoidable consequence of a mid-week phase start
  plus day-capacity limits, not a bug) could snap back to its own
  uncontested earliest offset the following week, clustering two
  sessions into one calendar week while an earlier one had none. Fixed
  via `spacingFloorOffset`, which propagates a first-week delay forward
  unchanged instead of letting it reset.

Both are covered by `TacticalPlacementBoundaryTests`/
`ConcurrentSchedulerTests`, including the exact partial-first-week policy
this surfaced: a phase's shortened first calendar week is allowed to
under-deliver the mix's nominal weekly frequency — TrainingOS never
forces same-day doubling or snaps phase start to the next Monday merely
to make the first calendar week look full.

## 3. `RollTacticalWindowUseCase` week-shift bug

`rollForward` computed `weekStartDate` itself, then passed it into
`FunctionalFitnessMaterializer`/`IntervalMaterializer.materializeWeek`,
both of which *also* apply their own internal week offset — silently
dating every rolled-forward week a full week later than intended.
`StrengthMaterializer` has no such internal offset, so its call site was
unaffected. Fixed by passing the un-shifted `instance.startDate` to the
two affected materializers.

## 4. Upcoming-phase strategic preview

`LongTermPlanner.PlanningContext` — a phase's previous/next sibling,
derived purely from `TrainingPlan.orderedPhases` at call time, never a
new persisted relationship. `PlanningContext.previousTrainingMix`
resolves the preceding phase's `.selected` mix if one exists, falling
back to its `.recommended` one — the same "selected always wins"
precedence already established for tactical scheduling, applied here to
strategic context instead.

`PhaseDetailViewModel` uses this (plus a disposable in-memory
`ModelContext`) to compute a live, read-only preview for any upcoming
phase with no stored mix of its own: recommended mix, per-component
recommended programs (tappable into their real template structure via
`ProgramDetailView(previewDefinition:)`), and the next phase. Recomputed
fresh on every load rather than cached, since the eventual real
recommendation may legitimately differ once the phase actually starts.
Verified never to create a `Session`/`ProgramInstance`/persisted
`TrainingMix`, never to alter the active phase, and idempotent across
repeated loads.

`preferredActivityType` was found to be a genuine missing-wiring bug — it
unconditionally returned `nil`, silently defaulting every Steady
State/Interval component to running regardless of the user's own stated
preference. `Goal.preferences.preferredModalities` already existed as a
fully generic mechanism (previously read by only one endurance-specific
call site); `preferredActivityType` now reads it for any
`ProgrammingSystemKind`, threaded through `proposeProgram`'s new optional
`goal:` parameter (default-`nil`, so every pre-existing call site kept
compiling unchanged).

## 5. Maintenance reduced-dose policy

`PHASE_PLANNING_RULES.md` §42 documents Maintenance's *strategic* role
(a genuinely lower-demand period between accumulation blocks) but never
its training *content* — before this slice, `.maintenance`, `.recovery`,
and `.transition` all shared one generic "2× Steady State, defaulting to
running" fallback. A full-repo search (docs, `PROGRAMMING_SOURCES.md`,
every `SessionFrequency`/`TrainingMixComponent` usage) confirmed no
sports-science-sourced reduction rule exists anywhere in this codebase —
the policy below is therefore explicitly TRAININGOS-DESIGNED, approved
by the product owner rather than invented silently.

`LongTermPlanner.maintenanceComponentDecisions` transforms the preceding
phase's resolved mix (never a generic template) component by component:

- **Primary/Secondary are always preserved**, reduced per system:
  - Resistance (hypertrophy/powerlifting): `≥3 → 2`, `2 → 2`, `1 → 1`
    (2/week is the maintenance floor for a quality that received
    meaningful prior emphasis; never reduced to zero).
  - Non-resistance: `≥4 → 2`, `2–3 → 1`, `1 → 1`.
- **Supporting is reduced more aggressively** and may be dropped:
  `≥2 → 1` (always kept, just reduced); `==1` is kept only when it is
  the mix's *sole* remaining Supporting component, otherwise omitted —
  the deterministic tie-break this slice needed beyond the approved
  policy's own wording, since stacking a second single-session
  Supporting component alongside an already-reduced one adds density
  without being anyone's sole remaining supporting quality.
- Never increases a frequency; never produces a target below an
  existing component's own `SessionFrequency.minimum` (respected, never
  overridden).
- `Recovery`/`Transition` remain on their own separate code path
  (`lowerDemandGenericMix`, called directly) and are provably unaffected
  by whatever the preceding phase's mix contains — they are distinct
  strategic purposes, not aliases of Maintenance, even though today they
  produce the same generic content.

Verified worked examples (both product-owner-approved):

- `5× Hypertrophy + 2× Conditioning → 2× Hypertrophy + 1× Conditioning`
- `3× Strength + 2× Functional Fitness + 1× Running → 2× Strength + 1×
  Functional Fitness` (Running dropped — the real seeded fixture's own
  outcome, since its Maintenance phase's immediate predecessor is the
  active phase, not the two-phases-back completed one)

Deliberately **not** built this slice: Transition's own documented
"blend outgoing/incoming" policy (§43 — `nextPhase` is available in
`PlanningContext` for this, unused by Maintenance), Recovery's own
distinct reduction policy, a readiness domain concept (none exists
anywhere in the app — the upcoming-phase caption was corrected to not
imply one), and any within-session volume/load/RIR reduction (strategic
frequency only; program generators are unchanged).

## 6. Test coverage added this slice

`TacticalPlacementBoundaryTests`, `WeekNavigationAndUpcomingPhasePreviewTests`,
`MaintenancePlanningContextTests` (planning context resolution,
selected-over-recommended precedence, the reduced-dose policy against
both worked examples plus the resistance-floor/non-resistance/minimum-
floor edge cases, Recovery/Transition non-interference, determinism, and
a permanent regression test against the real seeded fixture), plus
targeted additions to `ConcurrentSchedulerTests`/`AnnualPlanOrchestrationTests`.

**Full suite: 651 tests, 0 failures.**

## 7. Manual Simulator acceptance

Confirmed against a fresh install on the same device across the final
round: Week navigation labels correct in both directions and further
out; the seeded Maintenance preview correctly shows `2× Strength + 1×
Functional Fitness`; Maintenance remains genuinely `.planned` with no
materialized tactical window; recommended programs are visible and
individually inspectable without creating any `Session`/`ProgramInstance`;
the active phase's own real tactical data is unaffected by browsing
either Week or the upcoming phase.
