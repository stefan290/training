# Training Mix

Stage 4F's answer to "what should this phase's training actually consist
of, given both the goal and the person" — a typed, persisted composition
of training components, deliberately separate from *when* any of it lands
on the calendar (that's `CONCURRENT_SCHEDULER.md`'s job).

## 1. The product principle this model exists to serve

TrainingOS optimizes for the best plan the user will **actually follow**,
not merely the theoretically optimal one. That means training
preference and adherence have to be first-class planning inputs, not an
afterthought bolted onto a purely physiological recommendation. `TrainingMix`/
`TrainingMixComponent` are where that principle becomes schema: every
field on `TrainingMixComponent` (flexibility, preferred days, whether
doubles are allowed) is either a preference or a constraint the user
actually cares about, sitting right alongside the physiological
priority.

## 2. Recommended vs. Selected — one type, two kinds, never silently merged

`TrainingMix.kind: TrainingMixKind` is `.recommended` or `.selected`.
Both are real, comparable, persisted objects — never a UI-only concept,
and never collapsed into a single type with an "is this the real one"
flag. They may differ (a system might recommend 5 Hypertrophy + 2 Zone 2;
the user might select 3 Hypertrophy + 2 Functional Fitness + 1 Running
instead), and `TrainingPhase.selectedTrainingMix` is always what
`ConcurrentScheduler` actually schedules.

**The one rule this exists to enforce:** a user's `.selected` mix must
never be silently overwritten back to the `.recommended` one. Nothing in
this schema provides a path for that to happen automatically — replacing
a selection is always a distinct, explicit write, never a side effect of
recomputing a recommendation.

## 3. `TrainingMixComponent` — typed fields, never a dictionary

One component is one line of a mix: "Hypertrophy, 3/week, primary" or
"Functional Fitness, 2/week, supporting." Every field is deliberately its
own typed property, not an arbitrary key-value bag:

| Field | Type | Meaning |
|---|---|---|
| `label` | `String` | Human-readable name, known even before instantiation. |
| `programmingSystem` | `ProgrammingSystemKind?` | Which system this represents — a label, not a live reference. |
| `priority` | `GoalPriority` | `.primary` / `.secondary` / `.supporting` — see §5. |
| `frequency` | `SessionFrequency` | Target, with optional min/max — see §6. |
| `flexibility` | `ComponentFlexibility` | `.required` / `.preferred` / `.optional` — never inferred from modality. |
| `allowsDoubleSessionPairing` | `Bool` | This component's own opt-in to same-day pairing. |
| `preferredDays` | `[Weekday]` | Recurring weekly preference, not a specific date. |
| `requiredSpacingDays` | `Int?` | Minimum days between two of this component's own sessions, when the methodology needs it. |

## 4. Why `programInstance` is optional, and why `priority` is the component's own field

`TrainingMixComponent.programInstance: ProgramInstance?` is optional **by
design**, not an oversight: a `.recommended` mix's components describe a
proposed composition before any `ProgramInstance` exists for them at all
("Recommended: 5 Hypertrophy + 2 Zone 2" names no concrete instance).
Once a component is actually instantiated — a `.selected` mix, or an
accepted recommendation — `programInstance` is set to the real,
already-materialized instance a `ProgrammingSystem` generator produced.
`TrainingMixComponent` never duplicates that instance's own data; it only
adds the scheduling-relevant metadata `ProgramInstance` doesn't carry.

This creates one deliberate, accepted tension: `priority` lives on
`TrainingMixComponent` itself, not read from `programInstance.priority`,
because a not-yet-instantiated recommended component has no instance to
read from. Once linked, the two are expected to agree — an
application-layer invariant, not enforced by a sync mechanism. Building
that sync mechanism was explicitly out of scope for this pass; if the two
ever drift in practice, that's a signal for a future pass, not a bug in
this one.

## 5. Priority tiers — `GoalPriority`

`GoalPriority` (already existing since Stage 3C, extended this stage)
has three tiers: `.primary`, `.secondary`, `.supporting`. `.supporting`
is the Stage 4F addition — a phase's framing sometimes distinguishes more
than "the goal" and "the other thing alongside it" (e.g. Fat Loss "may
protect strength/muscle retention while allowing more conditioning
volume" — that's a third, lighter-touch tier, not a second `.secondary`).
Purely additive: a `String`-rawValue enum gaining a case breaks nothing
already persisted.

**Stage 4G confirmation:** `priority` (`GoalPriority`) and `flexibility`
(`ComponentFlexibility`) answer genuinely different questions — which
adaptation goal a component serves, vs. whether its own frequency can be
reduced under pressure — and this model already kept them as two
independent fields rather than one collapsed enum. The hardening pass's
conflict-resolution rewrite (`CONCURRENT_SCHEDULER.md` §4,
`GOAL_ALIGNMENT.md` §5) depends on exactly this separation: "required
minimum frequency" (driven by `flexibility`) and "primary-goal protection"
(driven by `priority`) are two distinct steps in the resolution order,
each reading its own field — collapsing them into one enum would have
lost the information needed to rank a `.primary`/`.optional` component
correctly against a `.secondary`/`.required` one.

## 6. Frequency — the smallest clean model

`SessionFrequency { target: Int, minimum: Int?, maximum: Int? }`. A fixed
count is `SessionFrequency(target: 3)`; a real range is
`SessionFrequency(target: 2, minimum: 1, maximum: 3)`. Nothing forces
every component to specify a range when a plain count is all that's
needed — the explicit instruction this shape satisfies.

## 7. `PreferenceStrength` — captured, not used to predict motivation

`TrainingMix.preferenceStrength: PreferenceStrength?` (`.systemRecommended`
/ `.userPrefers` / `.userStronglyPrefers`) is only meaningful on a
`.selected` mix. It is deliberately **not** read by `ConcurrentScheduler`'s
placement algorithm as a scoring input in this pass — turning it into an
active tie-breaker would mean algorithmically inferring how hard to try
to satisfy a preference, which is exactly the "predict motivation" trap
this stage was explicitly told not to build. It exists today as
structured, honest metadata for whatever future recommendation/analytics
work wants it — captured, not yet acted on.

## 8. Temporary mixes

`validFrom`/`validUntil` let a mix apply for a bounded window ("CrossFit
for the next 4 weeks") without touching the enclosing `TrainingPlan`/
`TrainingPhase` at all. The annual plan and every `PerformanceProfile`
remain exactly as they were; only which `TrainingMix` is currently active
changes. `nil` bounds mean "active until explicitly superseded" — the
common case.

## 9. Delete rules

See `DELETE_RULE_MATRIX.md`'s "Stage 4F additions" — both types cascade
freely (pure planning/preference metadata, never performance history);
`ProgramInstance -> TrainingMixComponent` nullifies, matching the
existing `sessions`/`SlotSelectionOverride` precedent for a to-one
reference into a deletable execution-side type.

## 10. What this model does not claim

- No recommendation engine. Nothing in this pass computes a `.recommended`
  `TrainingMix` from a goal automatically — that's the deferred Long-Term
  Planner's job. This stage only builds the type both a future
  recommender and a manual/test-authored mix would use identically.
- No adherence *prediction*. `PreferenceStrength` is captured input, not
  a modeled or inferred quantity.
- No numeric goal-fit score. See `CONCURRENT_SCHEDULER.md`'s
  `GoalAlignmentEvaluator` section — qualitative rating plus transparent
  factors, never a percentage.
