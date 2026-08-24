# Stage 10A — Programming Engine Audit (DESIGN / GAP ANALYSIS ONLY — nothing implemented)

**STATUS: APPROVED IN PRINCIPLE by the product owner**, with one
material correction to §8/§9's original framing — see "Amendments"
immediately below. The central finding (§1) and the "extend, don't
replace" direction are approved as written. §8's original "2-4 slots"
proposal is **rejected** and superseded. See `STAGE10B_IMPLEMENTATION_PLAN.md`
for the resulting, approved implementation plan.

## Amendments (product owner correction to the original §8/§9 proposal)

The original minimum-viable-engine proposal (§8/§9 below) framed slot
*count* as a near-primary design parameter ("2-4 slots per day"). This
was rejected as risking "replacing one placeholder with a slightly
larger placeholder." **Corrected direction, now authoritative:**

- Session content must be **derived from training intent** (an explicit
  per-day emphasis: primary muscle groups + secondary exposure), **not**
  from a fixed slot-count rule. Exercise count is an **output** of
  resolving that intent against existing muscle-group targets, never an
  input constant.
- `SlotRole` is approved but reconsidered — see
  `STAGE10B_IMPLEMENTATION_PLAN.md` §3 for the chosen 3-value
  representation (`primary`/`secondary`/`accessory`) and why the
  originally-proposed `.compound`/`.accessory` pair was too crude to
  express "which muscle groups get this day's primary emphasis."
- Weekly muscle-group coverage validation is **not deferred** — it ships
  in Stage 10B itself, as structural validation (every relevant muscle
  group gets intentional weekly exposure; no split repeats an identical
  slot set across days), explicitly **not** a MEV/MAV/MRV volume model.
- Everything else in this document (§1-7, §10-19's non-slot-count
  content, §20's decision list) stands as originally written and
  informed the approved plan.

## 1. Executive summary

**TrainingOS has a genuinely sophisticated planning/scheduling/execution
shell, wrapped around a hypertrophy content generator that produces the
same one exercise pair, every training day, for the entire program.**
This is not a bug and not incomplete wiring — it is a deliberately
scoped, self-documented Stage 4 placeholder (`HypertrophyProgramGenerator
.swift`'s own doc comment: *"one representative primary + paired-
accessory slot pair per training day... no source workbook survives...
flagged as a follow-up, not fabricated here with false confidence"*).
Every layer above it (annual planning, phases, tactical windows,
concurrent scheduling, readiness, substitution, warm-up) is real,
tested, production logic operating correctly on top of genuinely thin
program content. The recommended next step is **not** a rewrite and
**not** "add more exercises" — it is a bounded content/structure
extension to the *existing* slot-and-template architecture, which is
otherwise the right abstraction and does not need to be replaced.

## 2. Current production architecture (what exists, and at what level)

Using the audit's own A-E classification throughout this document:

| Concept | Classification | Evidence |
|---|---|---|
| Goal → TrainingPlan → TrainingPhase | **B** (real, tested) | `LongTermPlanner.proposeStrategicPlan`, `AcceptStrategicPlanUseCase` |
| TrainingPhase → TrainingMix (recommended/selected) | **B** | `LongTermPlanner.proposeTrainingMix`, `TrainingMix.swift` |
| TrainingMix → TrainingMixComponent (frequency/priority/flexibility) | **B** | `TrainingMixComponent.swift` — real typed scheduling metadata |
| TrainingMixComponent → ProgramDefinition (template graph) | **B**, but see §4 | `HypertrophyProgramGenerator.generate` |
| ProgramDefinition → ProgramInstance (materialization) | **B** | `StrengthMaterializer.swift` |
| ProgramInstance → tactical window rolling | **B** | `RollTacticalWindowUseCase`, `TacticalWindowPolicy` |
| ExerciseSlot → concrete Exercise resolution | **B** | `SubstitutionValidator`, `SubstituteExerciseUseCase` |
| Weekly load/set/rep progression | **B** | `StrengthProgressionEngine` (pure resolvers, deterministic) |
| Autoregulated set count (paired-slot feedback) | **B** | `AutoregulationRatingResolver` + `HypertrophyFeedbackView` |
| Concurrent scheduling (day placement across modalities) | **B** | `ConcurrentScheduler.swift` |
| Readiness-driven same-day adaptation | **B** (Stage 8B) | `EvaluateReadinessAdaptationUseCase` |
| This-session/going-forward substitution | **B** | `SubstituteExerciseUseCase`, `SlotSelectionOverride` |
| Pre-workout warm-up generation | **B** (Stage 9B) | `GenerateWarmupSequenceUseCase` |
| **Per-day muscle-group/movement-pattern variation within one program** | **C/E** — a fixed constant per split, not a rule | `HypertrophyProgramGenerator.primaryTargets(dayIndex:split:)` — `dayIndex` parameter is unused inside the switch |
| **Weekly/session muscle-group volume tracking** | **E** — does not exist | confirmed zero hits for `volume`/`fatigue`/`jointStress` anywhere in the codebase |
| **Exercise selection reasoning about secondary muscles, fatigue cost, exercise order** | **E** — does not exist | no such fields anywhere on `Exercise`/`ExerciseSlot`/`PrescriptionTemplate` |
| **Rich, realistic multi-exercise day content** | **D only** — `SeedScenarios.materializedLowerASession` (a hand-authored TEST fixture, never called by the real seed path or the generator) | confirmed by direct trace; Stage 9B's own manual-acceptance investigation already established this |

## 3. Current materialization pipeline (traced end to end)

```
LongTermPlanner.proposeStrategicPlan(goal:)          -- real phases, PhaseDurationDefaults
  → AcceptStrategicPlanUseCase.accept                -- persists TrainingPlan/TrainingPhase
  → LongTermPlanner.proposeTrainingMix(phase:goal:)   -- candidate TrainingMixes (recommended/selected)
  → StartPhaseUseCase / TransitionPhaseUseCase        -- instantiates the mix's components
      → per Hypertrophy component: HypertrophyProgramGenerator.generate(configuration:)
          -- configuration is ONE of the 6 HypertrophyBuiltInLibrary entries
          -- (dayCount, split) picked once; generate() builds `dayCount` TemplateSessions,
          -- each with EXACTLY 2 PrescriptionTemplates (one primary, one paired accessory)
          -- primarySlotName/primaryTargets depend ONLY on `split`, never on which day
      → StrengthMaterializer materializes week 0, then each subsequent tactical window
          -- StrengthProgressionEngine.resolveWeight/resolveSetCount/resolveRepGoal
          -- deterministic, chains from week 1's own resolved value — this part is genuinely solid
  → RollTacticalWindowUseCase                         -- extends the rolling window forward
  → ConcurrentScheduler                                -- places Sessions on real calendar Days
  → (at execution time) ReadinessGateFlow → GenerateWarmupSequenceUseCase → StartSessionUseCase
```

Everything from `StartPhaseUseCase` down to `ConcurrentScheduler` is real
and well-tested. The gap is entirely **inside** `HypertrophyProgramGenerator
.generate`/`makeSlotPair` — the step that decides *what the program
actually contains*.

## 4. Exact explanation of the two-exercise hypertrophy sessions

**Source: `TrainingOS/Application/UseCases/HypertrophyProgramGenerator.swift`,
`generate()` (≈lines 61-108) and `makeSlotPair()` (≈lines 110-172).**

- `generate()` loops `dayIndex in 0..<configuration.dayCount` and, for
  **every single day**, creates exactly one `WorkoutBlockTemplate`
  containing exactly two `PrescriptionTemplate`s: one "primary" slot and
  one "paired accessory" slot (`paired.pairedSlot = primary`, used only
  for the autoregulated-set-count/load-link mechanism, not for content
  variety).
- `primarySlotName(dayIndex:split:)` and `primaryTargets(dayIndex:split:)`
  take `dayIndex` as a parameter but **never reference it** inside their
  `switch` statements — only `configuration.split` (one of 4 cases:
  `.fullBody`, `.legs`, `.armsShoulders`, `.backChest`) determines the
  slot. The **only** place `dayIndex` actually changes anything is the
  "Heavy Legs Exception" (`isHeavyLegsException`), which changes a
  *loading percentage* for day 0 of a `.legs` split — never the
  exercise/muscle-group selection.
- The paired accessory slot is **always** `"Chest Isolation or Triceps"`
  (`allowedTargets: [.chest, .triceps]`), **regardless of split** — even
  a `.legs`-split program's accessory slot targets chest/triceps, not
  hamstrings/calves.
- Consequence, directly observed in Stage 9B acceptance testing: "5-Day
  Upper/Arms Focus" produces 5 *identical-shape* days (Overhead Press +
  Chest Isolation/Triceps); even "5-Day **Full Body** Hypertrophy"
  produces 5 identical days of Chest/Shoulders + Chest/Triceps — despite
  its name, it never trains legs or back at all.

**Answering your exact questions:**
- **Intentional V1 limitation?** Yes — explicitly, in the generator's
  own doc comment and `STAGE4_IMPLEMENTATION_REPORT.md`.
- **Seeded template data?** No — this is the *generator's own logic*,
  not seed/demo data layered on top. Every program built through this
  path, real or seeded, gets this shape.
- **Hard-coded?** The *slot pairing structure* (1 primary + 1 paired) is
  hard-coded. The *muscle group per split* is a 4-case switch, not
  literally hard-coded per instance, but it never varies within one
  program's own days.
- **A slot-count rule?** Yes, exactly one: always 2 slots per day,
  unconditionally.
- **A bug?** No — self-documented as an intentional scope boundary
  pending real program content.
- **Incomplete implementation?** Yes — this is the most accurate single
  label: the *mechanism* (slots, progression, autoregulation) is
  complete and correct; the *day-to-day content authoring* was never
  finished, for lack of source program material (confirmed: "no source
  workbook survives in this repository").
- **Does the architecture already support richer sessions even though
  the generator doesn't create them?** **Yes, unambiguously.**
  `WorkoutBlockTemplate.addPrescriptionTemplate` has no arity limit;
  `ExerciseSlot`/`PrescriptionTemplate ` are designed to be created in
  any number (`SeedScenarios.materializedLowerASession` itself proves
  this by hand-building 5 slots on one block using the exact same types).
  The schema and materializer do not need to change at all to support
  more slots per day.
- **What would happen if we simply increased the number of slots?**
  Mechanically, it would work — `StrengthMaterializer`/
  `StrengthProgressionEngine` are already slot-count-agnostic. But
  *which* additional slots/targets to add, in what order, at what
  volume, is exactly the missing domain intelligence (§6) — this is why
  the brief explicitly says not to patch this by "just adding more
  exercises."

## 5. Existing capabilities (confirmed real, not aspirational)

- Deterministic, testable weekly load/set/rep progression, chained from
  week 1's own resolved value (`StrengthProgressionEngine`).
- A real slot/substitution model already capable of expressing "any of
  these N exercises satisfies this training need" (`ExerciseSlot
  .allowedTargets/.allowedExercises`, `SubstitutionValidator`).
- A real provenance/history model for autoregulated feedback
  (`autoregulationRating`, `AutoregulationRatingResolver`).
- Real phase-level intent (`HypertrophyPhaseType`: basicHypertrophy /
  metaboliteFocus / resensitization) that already changes loading
  percentages and set-count rules per phase — a genuine (if narrow)
  form of phase-aware programming.
- A real concurrent-scheduling layer that places sessions from
  independently-generated modalities onto a shared calendar without
  hard-coding "is this a strength session" anywhere (CLAUDE.md rule 7).
- Real, deterministic readiness adaptation and warm-up generation that
  both already read the *live*, current prescription rather than a
  fixed template — meaning any future richer program content
  automatically benefits from both without changes to either.

## 6. Missing capabilities — evaluated against your list, not assumed necessary

**Necessary for credible hypertrophy programming (recommend building):**
- **Target muscle group per day, varying across the week** — the
  single biggest gap; without this, "program" is not yet a meaningful
  word for what's generated.
- **Movement pattern variety per day** (squat/hinge/horizontal push/
  vertical push/horizontal pull/vertical pull) — already representable
  via existing `MovementFunction`, just never assigned per day today.
- **Per-session exercise count** (a real 2-6 exercise session structure,
  not a fixed 2).
- **Weekly frequency per muscle group** — needed to decide how many
  times/week a muscle group is trained given the mix's own session
  frequency; this is genuinely necessary domain intelligence, not
  optional polish.
- **Rep-range/RIR logic per slot role** (primary/compound vs. accessory/
  isolation) — a narrow generalization of what `repGoalSchedule` already
  does for exactly 2 roles today.

**Useful, not necessary for V1 credibility (defer):**
- Secondary-muscle-aware exercise selection.
- Exercise-overlap-aware ordering (e.g. never two lower-body compounds
  back to back).
- Compound-vs-isolation sequencing rules beyond "primary first."
- Specialization/prioritization (extra volume for a lagging muscle
  group) — a real, common training concept, but adds a whole new
  "priority per muscle group" input surface; defer until the basic
  per-day/per-week structure exists.

**Explicitly NOT necessary — would be overengineering for this app's
stated scope:**
- Fatigue-cost/axial-fatigue/joint-stress modeling — this is
  academic-exercise-science territory with no existing hook, no source
  material, and (per CLAUDE.md rule 10) would require inventing
  thresholds this repo has no authority to invent.
- A generic "exercise stimulus" scoring model — same objection.
- Recovery-between-sessions modeling beyond what `ConcurrentScheduler`'s
  `requiredSpacingDays`/`allowsDoubleSessionPairing` already provide at
  the scheduling layer (that's the right layer for spacing; it should
  not be duplicated inside the hypertrophy generator).

## 7. Current vs. desired example week (Muscle Gain: 3× Hypertrophy, 2× Functional Fitness, 1× Running)

**Current production system** (traced, not hypothetical): the
Hypertrophy component instantiates ONE `HypertrophyBuiltInConfiguration`
(e.g. "3-Day Full Body Hypertrophy") and `ConcurrentScheduler` places its
3 sessions across the week. All 3 sessions are **identical in
structure**: 1 primary slot (chest/shoulders, "Horizontal Push") + 1
paired accessory slot (chest/triceps), progressing only in load/reps
week to week. Functional Fitness and Running are generated by their own
separate, already-real generators/schedulers and interact with
Hypertrophy only at the calendar-placement level (spacing/day
assignment) — there is no shared awareness of "you already trained
chest today in Functional Fitness."

**Desired conceptual programming** (structure only, no invented
numbers): 3 distinct Hypertrophy days across the week — e.g. Day A
(horizontal push + horizontal pull + one accessory), Day B (squat
pattern + hinge pattern + one accessory), Day C (vertical push + vertical
pull + one accessory) — each with **3-4 exercises**, compounds before
accessories, RIR tighter on compounds than accessories (mirroring the
existing primary/paired split's own established discipline, generalized
to more roles instead of exactly 2). Exercise selection is aware of
which movement patterns the SAME week's Functional Fitness sessions
already stress (via the already-existing `MovementFunction`/
`FunctionalModality` vocabulary Functional Fitness already tags itself
with), so Hypertrophy doesn't double up an already-heavily-loaded
pattern the same week — this is a **read**, not a new coordination
engine: Hypertrophy's own day-assignment logic consulting data that
already exists. Running interacts only via `ConcurrentScheduler`'s
existing spacing mechanism (no lower-body Hypertrophy day scheduled
adjacent to a hard running day beyond what spacing already allows) —
already-existing infrastructure, not a new concept. Progression intent
remains exactly what `StrengthProgressionEngine` already guarantees:
week-over-week chains from week 1's resolved value, per exercise slot,
unchanged by any of the above.

## 8. Minimum viable programming engine

> **Superseded — see "Amendments" above and `STAGE10B_IMPLEMENTATION_PLAN.md`.**
> Point 2's "2-4 slot roles" framing and point 3's `.compound`/`.accessory`
> pair were rejected by the product owner. Left unedited below as the
> historical record of what was proposed and why it was corrected — the
> same "a revision references what it replaces, it doesn't rewrite it"
> discipline this codebase already applies to plan revisions (CLAUDE.md
> rule 19d). Points 1, 4 and 5's underlying intent survive, reshaped by
> the Amendments.

The smallest architecture that makes hypertrophy programming credible —
extending, not replacing, what exists:

1. **A per-day "focus" concept on the existing template generation
   loop** — instead of `primaryTargets(dayIndex:split:)` ignoring
   `dayIndex`, a small, closed, TRAININGOS-DESIGNED per-split day
   rotation (e.g. `.fullBody` cycles [Horizontal Push + Horizontal Pull,
   Squat + Hinge, Vertical Push + Vertical Pull] across however many
   days the config has). *Why:* this is the one change that actually
   fixes the observed gap. *Persisted or derived:* derived — computed
   once at `ProgramDefinition` generation time, same as today.
   *Belongs to:* `HypertrophyProgramGenerator` itself — no new entity.
   *Needed now.*
2. **A generalized N-slot-per-day loop** (replace the fixed
   primary+paired pair with a small, per-day list of 2-4 slot roles:
   `.compound`, `.compound`, `.accessory`, `.accessory`). *Why:* enables
   §7's 3-4-exercise days without inventing per-exercise fatigue
   accounting. *Persisted or derived:* the resulting `PrescriptionTemplate`s
   are persisted exactly as today (no schema change — `WorkoutBlockTemplate
   .addPrescriptionTemplate` already accepts any count). *Belongs to:*
   `HypertrophyProgramGenerator`. *Needed now.*
3. **A `SlotRole` enum (`.compound`/`.accessory`)** replacing the
   ad hoc "primary"/"paired" naming, driving rep-range/RIR/set-count
   rules generically instead of two hard-coded shapes. *Why:* lets the
   N-slot loop (#2) assign rules without a combinatorial explosion of
   special cases. *Persisted or derived:* a small field on
   `PrescriptionTemplate` (derived at generation time, stored like any
   other template field). *Belongs to:* extends `PrescriptionTemplate`,
   not a new entity. *Needed now.*
4. **Weekly muscle-group frequency awareness** — a pure, stateless
   check at generation time ("does this split's day rotation train each
   targeted muscle group at least once, at most N times, across the
   week"), not a persisted volume-tracking system. *Why:* the minimum
   bar for "credible," without building real volume-landmark science.
   *Persisted or derived:* derived, at generation time only — nothing
   new stored. *Belongs to:* a pure function inside/near
   `HypertrophyProgramGenerator`. *Can be deferred one slice* if #1/#2/#3
   alone already produce reasonable variety; recommend building it
   alongside #1 since it's cheap once day-rotation exists.
5. **Cross-modality movement-pattern read** for the concurrent-training
   interaction (§7's "don't double up Functional Fitness's own movement
   patterns"). *Why:* directly serves the "preserve training intent
   across concurrent modalities" product principle. *Persisted or
   derived:* fully derived — reads existing `MovementFunction` tags off
   already-materialized sessions in the same tactical window; no new
   storage. *Belongs to:* a new, small read-only helper consulted by
   `HypertrophyProgramGenerator` (or, more likely, whichever use case
   assigns day-rotation focus to a specific calendar day) — **defer to
   its own slice**, since it depends on #1-#3 existing first and is the
   part most likely to need its own product decision about exactly how
   much cross-modality awareness is wanted.

**Explicitly NOT part of the minimum viable engine:** fatigue cost,
joint stress, exercise-order optimization beyond compound-before-
accessory, specialization/prioritization, a general "stimulus" score.
All of these are real training concepts but not required to cross the
line from "prototype" to "credible" — adding them now would be exactly
the "giant rules engine" the brief warns against.

## 9. Proposed domain-model changes (summary table)

| Change | New or extends existing? | Persisted? | Needed now? |
|---|---|---|---|
| Per-split day-focus rotation | New pure data (a small table/array) inside `HypertrophyProgramGenerator` | No — computed at generation time, same as today's fixed split logic | Yes |
| N-slot-per-day loop | Extends `generate()`'s existing loop | Existing `PrescriptionTemplate`/`ExerciseSlot` types, no schema change | Yes |
| `SlotRole` (`.compound`/`.accessory`) | Extends `PrescriptionTemplate` | Yes — one small new field | Yes |
| Weekly muscle-group frequency check | New pure function | No | Yes (cheap, bundle with the above) |
| Cross-modality movement-pattern read | New, small read-only use case | No | Defer to its own slice |
| Specialization/prioritization | Would extend `TrainingMixComponent` or a new per-goal input | Yes, if built | Defer |
| Fatigue/volume-landmark modeling | Would be an entirely new subsystem | N/A | Do not build |

**No existing entity is replaced or deprecated.** `ProgramDefinition`,
`TrainingWeek`, `ExerciseSlot`, `PrescriptionTemplate`,
`StrengthProgressionEngine`, `StrengthMaterializer` all stay exactly as
they are structurally — this is content/structure generation logic
gaining more resolution, not a new pipeline.

## 10. Generic vs. modality-specific responsibilities

**Already correctly generic, keep as-is:** `Session`/`WorkoutBlock` (any
modality), `ExerciseSlot`/`SubstitutionValidator` (already shared across
Strength and Functional Fitness), `ConcurrentScheduler` (modality-blind
by design, CLAUDE.md rule 7), readiness adaptation, warm-up generation,
`TrainingMixComponent` (frequency/priority/spacing are already
modality-agnostic).

**Correctly modality-specific, keep separate:** hypertrophy's own
volume/rep-range/RIR logic (this proposal), `SteadyStateProgressionEngine`'s
own zero-feedback-by-design model, `IntervalProgressionEngine`'s
completion-gated model, Functional Fitness's `FunctionalFitnessDecisionEngine`
stimulus-balancing rules. **None of these should be merged** — hypertrophy
volume logic must never be forced onto Running, exactly as you said.

**Should become generic (currently duplicated or ad hoc per system):**
"training intent" as a concept (what a slot/day is FOR) is currently
expressed differently per system (`SessionRole` for endurance,
`WorkoutBlockType` for strength/FF) — the proposed `SlotRole` (§8 item 3)
should stay Strength/Hypertrophy-specific for now rather than forcing a
premature unification; revisit only if Functional Fitness's own
programming needs the identical concept later.

## 11. Interaction with progression

No change to `StrengthProgressionEngine`'s contract. More slots per day
means more `ExerciseSlot`/`PrescriptionTemplate` rows, each independently
resolved week-to-week exactly as today — the engine is already slot-
count-agnostic (confirmed: it operates per-slot, never per-day-as-a-whole).
`AutoregulationRatingResolver`'s paired-slot mechanism generalizes
directly: any accessory slot can name a `pairedSlot`, not just "the one
accessory."

## 12. Interaction with readiness

None of Stage 8B's contracts change. `EvaluateReadinessAdaptationUseCase`
already reads whatever `session.orderedBlocks` contains at execution
time — richer programs mean richer, more specific readiness matching
(e.g. a real squat-pattern day genuinely deriving `hipMobility`/
`ankleMobility` for Stage 9B's warm-up, as already proven by the
`materializedLowerASession` acceptance fixture) — this is a direct,
free improvement, not a required change.

## 13. Interaction with substitution

None of Stage 4C's contracts change. More slots simply means more
`ExerciseSlot`s each independently substitutable, exactly as today.

## 14. Interaction with concurrent training

`ConcurrentScheduler` needs no changes to *place* a richer program's
sessions — it already schedules by frequency/spacing, not by content.
The only NEW interaction is the proposed cross-modality movement-pattern
read (§8 item 5, its own deferred slice) — everything else (spacing,
double-session rules, key-session priority) is unaffected and already
correct.

## 15. Future Home Gym compatibility

The current model already supports this well: `ExerciseSlot
.allowedTargets`/`.allowedMovementFunctions` describe *what the slot
needs*, never *which specific piece of equipment* — exactly the "preserve
intent, vary the concrete choice" shape Home Gym needs. The proposed
`SlotRole`/day-rotation changes describe training *need* (compound squat
pattern, accessory pull, etc.), not equipment — so a future equipment
constraint filters `SubstitutionValidator`'s candidate resolution exactly
as it would today, without touching the day-rotation/slot-role logic at
all. This audit does not add anything that would need to be undone for
Home Gym.

## 16. Migration/backward-compatibility implications

No schema migration is strictly required for §8's core proposal — `SlotRole`
is one new field on `PrescriptionTemplate`, and everything else is
generation-time logic change, not a schema change. Existing seeded/test
`ProgramDefinition`s (already materialized, already frozen per
`ProgramDefinition.generatorVersion`'s own doc comment) are entirely
unaffected — a generator version bump only changes *future* generation,
never retroactively rewrites already-materialized programs (the existing,
proven invariant). Same "no migration system yet" caveat already
recorded as backlog debt in `STAGE8B_ACCEPTANCE_REPORT.md` applies if the
one new field is added.

## 17. Testing strategy (for whenever this is approved for implementation)

- Day-rotation determinism: same configuration → same day-focus sequence,
  every time (no randomness).
- Weekly muscle-group coverage: for each built-in configuration, assert
  every intended muscle group is hit at least once and not more than a
  defined maximum across the week.
- Slot-role rep-range/RIR assignment: compound vs. accessory roles
  produce the expected `repGoalSchedule`/`setCountRule` shape.
- Regression: every existing `HypertrophyProgramGeneratorTests`/
  `HypertrophyBuiltInLibraryTests`/`StrengthMaterializerTests` assertion
  about the CURRENT 2-slot shape will need deliberate, reviewed updates —
  flagged now so it isn't a surprise later.
- Cross-modality read (deferred slice): a Functional Fitness day's own
  movement-function tags correctly suppress a same-week Hypertrophy day
  from doubling that pattern, table-driven per combination.

## 18. Risks / overengineering traps

- **The biggest real risk is scope creep into exercise science.** The
  brief's own instinct (don't build fatigue/joint-stress modeling) is
  correct — resist any temptation to "just add one more signal" once
  inside this code.
- **Content authoring risk:** the actual per-split day-rotation table is
  itself a real training-content decision (which patterns, which order)
  — per CLAUDE.md rule 10, this needs your explicit sign-off per split,
  not an invented "reasonable-sounding" rotation.
- **Determinism risk:** any "smart" exercise selection must remain a
  pure function of typed inputs — no randomness, matching CLAUDE.md rule
  4's discipline already proven everywhere else in this codebase.
- **Test-debt risk:** existing generator tests assert the current 2-slot
  shape; changing it without deliberately reviewing every such test would
  silently weaken coverage rather than strengthen it.

## 19. Recommended implementation slices

- **Stage 10A (this document)** — audit/design only. Complete.
- **Stage 10B** — the day-rotation + N-slot-per-day + `SlotRole` change
  for ONE split first (recommend `.fullBody`, the most-used default),
  fully tested, manually accepted, before extending to the other 3
  splits — the same incremental, one-slice-at-a-time discipline used for
  Stage 8B/9B.
- **Stage 10C** — extend the same day-rotation/N-slot model to the
  remaining 3 splits (`.legs`, `.armsShoulders`, `.backChest`) + the
  weekly muscle-group frequency check.
- **Stage 10D (future, separate approval)** — the cross-modality
  movement-pattern read for concurrent training awareness.
- **Explicitly not scheduled:** specialization/prioritization, fatigue/
  volume-landmark modeling, exercise-order optimization beyond compound-
  first — revisit only if a future product need makes a concrete case
  for one of them.

## 20. Explicit product decisions requiring your approval before implementation

1. **Approve the overall direction:** extend `HypertrophyProgramGenerator`
   with day-rotation + N slots + `SlotRole`, rather than any alternative
   (e.g. a new parallel generator, or importing an external program
   library format).
2. **The exact day-rotation content per split** — this is real training
   content, not something to silently invent (rule 10). Needs your
   sign-off per split (recommend starting with just `.fullBody` per
   Stage 10B's scope).
3. **The exact N-slot count per day** (e.g. always 3-4, or split-
   dependent) — a real, bounded product decision.
4. **Whether the weekly muscle-group frequency check ships in Stage 10B
   or is deferred to 10C** — recommend bundling it into 10B since it's
   cheap once day-rotation exists, but flagging as your call.
5. **Whether cross-modality movement-pattern awareness (Stage 10D) is
   wanted at all**, given it's the one piece that reaches outside
   Hypertrophy's own generator — confirm before any 10D design work
   begins.
6. **Confirm the incremental, one-split-first rollout** (Stage
   10B = `.fullBody` only, 10C = the rest) rather than changing all 4
   splits simultaneously.

---

**This is design/audit only. No production code has been changed.**
Awaiting your decisions on items 1-6 before Stage 10B implementation
begins.
