# Training OS

This repository has two unrelated parts:

- `README.md`, `chats/`, `project/` — the original Claude Design handoff
  bundle (prototypes + design rationale). Reference material for what the
  app should do. Do not edit it to make code easier to write; if the
  handoff and the code disagree, the handoff wins and the code changes.
- `app/` — the native iOS implementation (`TrainingOS.xcodeproj`,
  `TrainingOS/`, `TrainingOSTests/`). See `app/ARCHITECTURE.md` for how it's
  organized.

The rules below are project constraints for anyone (human or agent)
working in `app/`. They come directly from the approved product decisions
in `project/Training OS Handoff.dc.html` — they are not style preferences,
and violating one is a correctness bug even if the code compiles and the
UI looks right.

## Non-negotiable rules

1. **Never reset user performance when programs change.** Ending,
   replacing or deleting a ProgramDefinition or ProgramInstance must never
   delete, truncate or reset a SetResult, WorkoutResult, PersonalRecord or
   ExercisePerformanceProfile. If a change you're making would do that,
   the change is wrong, not the data model.
2. **ProgramDefinition never contains user performance.** No field on
   `ProgramDefinition` (or its templated `TrainingWeek`s) may hold a
   result, a PR, or anything derived from what a specific user did.
3. **Prescription, Recommendation and Actual Result are separate
   concepts**, never merged into one type: `SetPrescription` (target) vs.
   `SetResult`/`WorkoutResult` (actual) vs. `Recommendation` (engine
   output). The engine owns the target; the user owns the actual.
4. **Progression logic is deterministic and unit-tested.** Same inputs
   must always produce the same output and reason code. No randomness, no
   network calls, no reading the current date/time as an implicit input.
   Every new reason code needs a table-driven test, including boundaries.
5. **Business logic does not live in SwiftUI Views.** Views render
   ViewModel output. Querying, filtering, scoring and progression decisions
   belong in `Application/` or `Engines/`.
6. **Exercises use canonical, stable IDs.** All performance data
   references a canonical `Exercise`, never a raw source string. Renamed
   or re-imported exercise names must resolve to the same canonical ID.
7. **WorkoutBlock is the modality-agnostic execution unit.** Never branch
   UI or persistence code on "is this a strength session" — branch on the
   block's `WorkoutBlockType` instead. A Session is an ordered list of
   blocks of any type; that is normal, not a special case.
8. **Day -> Session -> ordered WorkoutBlocks is foundational.** A Day can
   hold zero or more Sessions; do not assume one Session per Day anywhere
   in the code.
9. **Preserve offline-first architecture.** Nothing required to run a
   Session, log a set, or compute a recommendation may require a network
   connection.
10. **Do not invent ambiguous training rules.** If the handoff doesn't
    specify a threshold, formula or default, don't guess one into
    persisted logic — flag it (a code comment, a test, or a question back
    to the product owner) rather than silently deciding.
11. **Do not silently expand V1 scope.** HealthKit, backend sync,
    authentication, spreadsheet import, the full planning engine, the full
    progression engine, adaptive scheduling, missed-session recovery,
    functional-fitness timers, and AI features are out of scope until
    explicitly requested. If a task seems to need one of these, stop and
    ask rather than building a partial version.
12. **Imported program source logic must remain traceable to its source.**
    When the import pipeline is built, every canonical prescription must
    be traceable back to the sheet/cell/range that produced it — do not
    build an import path that discards that trace.
13. **HealthKit is an integration layer, not the source of truth.** No
    session, block or recommendation may ever be blocked by a missing
    Health permission. Programs, sets, reps, weight, RIR, PRs, progression,
    phases and planning are always owned by this app's own store.
14. TrainingOS optimizes for long-term goal alignment subject to explicit
    user training preferences and adherence. User-selected training
    modalities must not be silently replaced by theoretically more
    optimal modalities.
15. ConcurrentScheduler schedules training; it does not create or
    progress training methodology.
16. **Scheduling/planning explanations are structured, never string-parsed.**
    `GoalAlignmentEvaluator` (and any future planner or UI) must read a
    `ScheduleIssue`'s typed `code`/`severity`/`componentLabel`/`session`
    fields, never `ScheduleProposal.warnings`. `warnings` is display copy
    computed FROM `issues` — parsing it back to infer meaning is a
    correctness bug even on the day it happens to still work, because
    rewording a message must never change what any business logic
    concludes.
17. A theoretically optimal program that the user does not want to
    perform is not considered practically optimal. The Long-Term
    Planner must support explicit user preference (variety, modality,
    temporary style switches, custom mixes) as first-class planning
    input — it must never attempt to predict motivation or adherence
    using an opaque model. Preference/adherence may promote an
    alternative above the physiologically best recommendation only
    among candidates that already clear an explicit goal-compatibility
    gate; it must never promote a candidate with major goal
    incompatibility, and the highest-alignment candidate must still be
    shown, never hidden, when a promotion displaces it.
18. **`Infeasible` and `Poor Fit` are never a safety judgment.**
    `ScheduleFeasibility.infeasible`/`GoalAlignmentRating.infeasible`
    mean only that required hard constraints cannot be satisfied;
    `.poor` means only a bad-but-executable goal/preference fit. Neither
    may be used, now or later, to encode a speculative training-science
    risk or eligibility judgment. If a validated safety/eligibility
    concept is ever added, it must be modeled as its own separate type —
    overloading either of these two into "potentially unsafe" is a
    correctness bug, not a shortcut.
19. **Long-Term Planning keeps four concepts distinct, never conflated:**
    (a) **phase objective vs. training modality** — `TrainingPhase.type`
    names a strategic adaptation goal; a `TrainingMix`'s composition
    (how many modalities it spans) is a separate, independent property,
    and a diverse mix never implies or requires a different phase
    objective; (b) **a conceptually good idea vs. a currently executable
    program** — `ProgramCapabilityRegistry` gates every recommendation;
    the planner must never fabricate a `ProgramDefinition` to satisfy its
    own recommendation, and an inexecutable path is surfaced as a
    `CapabilityGap`, never disguised as a normal option; (c) **a
    strategic plan vs. tactical workout materialization** — strategic
    phases span months, exact tactical prescriptions exist only for the
    current rolling window, and a future performance-dependent number is
    never fabricated ahead of the window it belongs to; (d) **a plan
    revision vs. rewriting history** — revising a plan always creates a
    new revision referencing what it replaced; a completed phase and an
    already-accepted tactical schedule are permanent historical
    snapshots that no later revision, of any size, may mutate.
20. **A successfully logged set/result must never depend on completing
    the whole Session to become durable.** Live workout execution
    persists promptly at each meaningful action (a logged set, a
    recorded endurance/interval/functional-fitness result, a
    substitution/scaling choice, a block or Session status change) —
    never deferred to a single final save at Session completion. A
    crash must lose at most one unconfirmed, not-yet-logged edit, never
    anything already confirmed. The final Session-completion save is the
    last consistency/commit point, not the first durability point.
21. **Timers derive truth from persisted wall-clock timestamps and
    explicit state transitions, never from in-memory tick counts.** A
    timer's displayed value is always a pure function of its persisted
    state (start time, pause state, accumulated pause, current
    unit index) and the current moment, recomputed at render time —
    never accumulated by counting timer fire events. Recovery after
    backgrounding, a force-quit, or a device restart must reproduce
    exactly the state a continuously-running clock would show, with no
    replay of transitions or cues that would have fired while closed.
