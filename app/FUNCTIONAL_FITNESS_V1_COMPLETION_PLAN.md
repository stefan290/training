# Functional Fitness V1 Completion Plan

Analysis only. No code changed, no architecture changes, no UI, no git
operations. Powerlifting V1 (commit `e840ff9`, pushed) is closed and
untouched by this checkpoint.

## 1. Existing FF Architecture

FF rides the same generic template-graph/materializer architecture as every
other system (`ProgramDefinition`/`TemplateSession`/`WorkoutBlockTemplate`/
`Session`/`WorkoutBlock`) — no parallel FF-only entity hierarchy.
FF-specific types: `FunctionalFitnessPrescriptionTemplate`/`Prescription`
(stimulus + format), `FunctionalFitnessMovementSlotTemplate`/`Movement`
(the resolved exercise + target), `FunctionalFitnessResult`/
`PerformedMovement` (logged outcome), `Stimulus`/`VarianceConstraints`/
`WorkoutFormat` (value types). Two real engines:
`FunctionalFitnessDecisionEngine` (pure, deterministic stimulus
adjustment — duration/loading/modality/movement-function variance +
cross-modality interference avoidance + same-week complementarity) and
`FunctionalFitnessMovementComposer` (pure, deterministic movement-function
selection — same-week primary coverage + prior-week tie-break). Generation
(`FunctionalFitnessProgramGenerator`) supplies configuration; materialization
(`FunctionalFitnessMaterializer`) runs the live, exposure/environment-aware
resolution (Stages C-E), mirroring the Hypertrophy/Running split exactly.

## 2. Previously Closed Capabilities Verified

Per the user's own instruction, treated as CLOSED and only spot-verified
against live code (not re-litigated):
- **CP2 objective taxonomy / intended vs. final stimulus**: confirmed real —
  `FunctionalFitnessDecisionEngine.decideWithIntent` produces both
  `intendedStimulus` (Phase 1) and `finalStimulus` (Phase 2), both persisted
  on `FunctionalFitnessPrescription`.
- **Execution adherence truth**: `FunctionalFitnessResult`/
  `RecordFunctionalFitnessResultUseCase.swift` exist; a dedicated
  `FunctionalFitnessPrescriptionAdherenceTests.swift` exists.
- **Structural movement targets**: `FunctionalFitnessMovementTargetRule.resolve`
  called at materialization time in both the dynamic and authored paths.
- **FF.M1 movement diversity**: confirmed real and working —
  `FunctionalFitnessMovementComposer` (same-week primary coverage cycling
  between loaded/gymnastics classes, prior-week tie-break, conditioning
  fill) plus `FunctionalFitnessMaterializer`'s prior-week/this-week exercise
  exposure tracking, both exercised by real tests
  (`FunctionalFitnessMovementDiversityTests.swift`,
  `FunctionalFitnessGoingForwardPreferenceTests.swift`).
- **Existing FF session-generation infrastructure**: real, reachable in
  production — `LongTermPlanner.functionalFitnessParameterCandidates`
  (line ~1858) is a genuine, currently-live path from a TrainingMix FF
  component to a real generated `ProgramDefinition`.

No concrete regression or defect found in any of the above.

## 3. Current End-to-End Pipeline

`TrainingMixComponent` (system `.functionalFitness`) → `LongTermPlanner
.functionalFitnessParameterCandidates` (builds ONE fixed `Stimulus` +
`FunctionalFitnessProgramConfiguration`, `varianceConstraints:
VarianceConstraints()` — empty) → `FunctionalFitnessProgramGenerator.generate`
(Stage A/B from config; Stage C pre-baked only if `isDynamicallyComposed ==
false`, which the real candidate never sets) → `FunctionalFitnessMaterializer
.materializeWeek` (Stage C dynamic composition via
`FunctionalFitnessMovementComposer`, Stage D exercise resolution via
`SubstitutionValidator`/environment, Stage E `FunctionalFitnessStimulusValidator`)
→ real `Session`/`WorkoutBlock`/`FunctionalFitnessPrescription`/`Movement` →
`SessionDetailView` dispatches `.functionalFitness` blocks to the real,
dedicated `FunctionalFitnessExecutionView` (confirmed, not a placeholder) →
`RecordFunctionalFitnessResultUseCase`/`FunctionalFitnessResult` → completed
sessions feed `FunctionalFitnessExposureHistoryBuilder` → back into the
decision engine's variance checks for the NEXT materialization call.

## 4. What Already Works (WORKING NOW)

- One complete, real, environment-aware FF session generates and executes
  end to end (generic UI, no gap).
- Multiple sessions/week, coordinated same-week via
  `CurrentWeekFunctionalFitnessProgrammingContext` (complementarity +
  cross-modality interference avoidance).
- Real week-to-week movement/exercise diversity (not stimulus-level, see
  §7) via `FunctionalFitnessMovementComposer`'s prior-week exposure.
- Strength+metcon composition mechanism (`includeStrengthBlock`) —
  structurally proven, real generic `Session`/multi-block architecture,
  no new entity needed.
- Training Environment compatibility — real, fail-fast, same
  `TrainingEnvironmentCompatibilityRule` machinery as Hypertrophy/Running.
- Substitution — `SubstituteFunctionalFitnessMovementUseCase` wired to real
  materialized movements via `sourceExerciseSlot`.
- Composability metadata — `TrainingStressProfile` (shared, modality-
  agnostic type already used elsewhere) is populated for every FF block via
  `FunctionalFitnessStressProfileMapper.map(stimulus:)` — exposes
  intensity/systemic/lower-body/upper-body/impact/metabolic demand,
  duration classification, modality, recovery demand.
- Execution UI — `SessionDetailView` already dispatches `.functionalFitness`
  to a real, dedicated `FunctionalFitnessExecutionView`.

## 5. FF V1 Blockers (BLOCKS FF V1)

1. **The one real, reachable production FF configuration never varies.**
   `LongTermPlanner.functionalFitnessParameterCandidates` always builds the
   identical `Stimulus` (medium duration, moderate everything,
   weightlifting+gymnastics+conditioning, `.roundsForTime`) for every week
   and every session — the program IS multi-week (`lengthWeeks: 4`,
   confirmed real `TrainingWeek`s), but its content is one repeated shape,
   not a coherent progression or deliberate variation. This is the single
   fact that makes today's FF read as "isolated similar WODs" rather than
   a program — and it is a **configuration/content gap**, not a missing
   engine.
2. **`varianceConstraints: VarianceConstraints()` (all-nil) in the one real
   candidate** — the entire, real, tested stimulus-balancing engine
   (duration/loading/modality/movement-function rotation) is structurally
   inert in production today because nothing ever populates a non-nil
   window. Confirmed directly at the exact call site.
3. **No progression of any kind** (load, volume, density, complexity,
   duration, conditioning demand) — the fixed candidate stimulus never
   escalates across the 4 configured weeks. Movement/exercise-level
   diversity is real; difficulty/demand progression is not.
4. **`includeStrengthBlock: false`** in the one real candidate — the
   proven strength+metcon composition mechanism is never actually invoked
   in production, so today's real FF sessions are metcon-only regardless
   of the "structured Functional Fitness" product direction.

## 6. Checkpoint Bugs (CHECKPOINT BUG)

None found. Every gap in §5 is a configuration/content choice on top of a
working, tested engine — not a defect relative to what any prior
checkpoint claimed to deliver.

## 7. Multi-Week Programming Status

Two genuinely different mechanisms, must not be conflated:
- **Movement/exercise diversity across weeks: REAL, working, unconditional.**
  `FunctionalFitnessMovementComposer` + the materializer's prior-week/
  this-week exposure tracking actively vary WHICH movement functions and
  WHICH exercises get selected, every session, every week — not gated by
  any configuration flag.
- **Stimulus-level variance/balance across weeks: real, tested, but
  DORMANT.** `FunctionalFitnessDecisionEngine`'s 4 variance checks
  (duration domain, loading, modality mix, movement function) require
  `VarianceConstraints` windows to be non-nil; the one real production
  configuration never sets them, so the engine's own "no variance
  constraint was violated (or none is configured)" fallback always fires.
  **Minimum fix**: author a real configuration with non-nil windows (e.g.
  `avoidRepeatingDurationDomainWithinSessions: 2`) — no new engine code
  needed, this is a content/configuration change only.

## 8. Progression Status

What progresses today: exercise/movement-function selection diversity
only (via exposure tracking). What does NOT progress: load, volume,
density, complexity, duration, skill demand, or conditioning demand — the
fixed candidate stimulus is identical week 1 through week 4. This is the
most significant gap for "a coherent sequence... not isolated random WODs"
specifically, and it is real, not merely under-tested.

## 9. Session Composition / Archetypes

`SessionRole` already has `.functionalFitness`/`.skill`/`.mixed` cases, but
the one real production path always uses `.functionalFitness` uniformly —
no archetype variation is actually exercised today. The composition
mechanism for a richer archetype (e.g. "structured/Functional-Bodybuilding"
= `includeStrengthBlock: true` + `.loading: .light`/controlled tempo
framing vs. "performance/mixed-modal" = `includeStrengthBlock: false` +
higher `.intensity`) is already provably supported by existing types —
**no new session-role enum is required for V1**; a small, explicit
product decision (2-3 named configurations using existing fields
differently) is sufficient. Note: `MovementFunction` already declares
`carry`/`locomotion`/`jumping`/`trunk` and 5 other cases explicitly as
"deferred" — never produced by the composer today — so unilateral/carry-
style Functional-Bodybuilding work is representable in the type system but
not yet reachable through real generation.

## 10. TrainingMix / Composability Metadata

Sufficient today. `TrainingStressProfile` (the same shared type already
used for Running per this engagement) is populated on every FF block:
`overallIntensity`, `systemicDemand`, `lowerBodyLoad`, `upperBodyLoad`,
`impactLoading`, `metabolicDemand`, `durationClassification`, `modality`,
`recoveryDemand`. This already gives a hypothetical future orchestrator
everything asked for (primary muscle/movement stress, conditioning stress,
modality, duration, recovery cost) without new metadata work. FF-vs-Running
distinction (running-heavy vs. monostructural-other vs. mixed-modal vs.
primarily-muscular conditioning) is already expressible via
`modality`/`metabolicDemand`/`movementModalityMix`'s existing typed
vocabulary — no gap found. Cross-modality interference-avoidance logic
already exists and is tested (`CrossModalityFunctionalFitnessProgrammingTests.swift`)
using exactly this shared profile type against sibling components' stress.

## 11. Training Environment Status

WORKING NOW. Confirmed directly: `FunctionalFitnessMaterializer` fails fast
(`.trainingEnvironmentRequired`) before any composition/resolution runs on
an unknown environment, filters eligible movement functions/exercises
through `TrainingEnvironmentCompatibilityRule.evaluate` before composition
ever sees them, and throws a precise `.environmentIncompatible` (never a
silent substitution or empty session) when nothing eligible remains — the
identical discipline already proven for Hypertrophy/Running. No gap.

## 12. Execution / Result Status

WORKING NOW. `SessionDetailView` already dispatches real FF blocks to
`FunctionalFitnessExecutionView` (not a placeholder). `FunctionalFitnessResult`/
`RecordFunctionalFitnessResultUseCase` exist and are tested
(`FunctionalFitnessPrescriptionAdherenceTests.swift`). Completed sessions
correctly feed `FunctionalFitnessExposureHistoryBuilder` (completion-gated,
never counts a scheduled-but-skipped session). The one caveat: since the
real production `VarianceConstraints` are empty (§7), this real exposure
history currently has no practical effect on future stimulus — the plumbing
is correct, the configuration that would make it matter is missing.

## 13. Recommended FF V1 Boundary

Narrower than the user's own example scope, because the current
architecture can support real, deliberate multi-week programming with
almost no new code — the gap is content/configuration, not engine work:

- 2-3 real curated `FunctionalFitnessProgramConfiguration`-based weekly
  templates (not full named "archetypes" as a new taxonomy — just 2-3
  concrete, deliberately different configurations), e.g. one
  metcon-forward mixed-modal week and one `includeStrengthBlock: true`
  structured week, each with real, non-nil `VarianceConstraints` windows.
- 1-3 sessions/week, 4-week coherent program (already the real shape
  `LongTermPlanner` produces).
- Real week-to-week stimulus variation, turned ON via configuration
  (duration domain and/or loading rotation) — no new engine logic.
- Existing movement diversity, Training Environment compatibility,
  execution, and adherence — unchanged, already correct.
- Composability metadata — unchanged, already sufficient.

Explicitly NOT in V1: a rich session-archetype enum, unilateral/carry
movement functions (still type-declared-but-deferred), true load/volume/
density progression across mesocycles (no source-grounded methodology to
anchor it — this is genuinely a V2 design question, not a config flip),
cross-program concurrent-scheduling interference logic beyond what
`InterferenceAvoidanceRule.conservativeDefault` already does.

## 14. Exact Implementation Scope

1. Author 2-3 real `FunctionalFitnessProgramConfiguration` values (content,
   not new types) with genuinely different `targetStimulus`/`format`/
   `includeStrengthBlock`, and real non-nil `VarianceConstraints` windows.
2. Extend `LongTermPlanner.functionalFitnessParameterCandidates` to surface
   more than the current single fixed candidate (mirrors how Hypertrophy/
   Powerlifting already expose more than one curated shape) — additive,
   no change to existing recommendation-ranking policy.
3. Add fidelity/regression tests proving: real stimulus variation actually
   fires across a real multi-week materialization (using the
   now-non-empty `VarianceConstraints`), the strength+metcon composed
   session actually materializes when configured, and nothing above
   regresses movement diversity/environment/execution/adherence.
4. Dogfood: materialize a real 4-week instance end-to-end, show session
   roles/stimulus genuinely differ session-to-session and week-to-week,
   not just structurally-different-but-identical-in-content.

No new domain entity, no new engine, no UI work, no LongTermPlanner
ranking-policy change.

## 15. Explicit FF V2 Backlog

- True progression (load/volume/density/complexity) across mesocycles —
  needs an explicit TrainingOS product decision on a progression model
  (not source-recoverable the way Hypertrophy/Powerlifting are; not
  something CrossFit.com WODs can source-authorize either).
- Activating the 9 deferred `MovementFunction` cases (carry, locomotion,
  jumping, trunk, the loaded-variant pulls/pushes) in the composer —
  needed for genuine unilateral/carry-style Functional-Bodybuilding work.
- A richer, explicit session-archetype concept, if 2-3 configurations
  prove insufficient in practice.
- Wiring `isPowerliftingSourceVerified`-style fidelity gates is N/A here
  (FF has no literal source workbook) — instead, a future "is this FF
  configuration curated/reviewed" capability marker, mirroring the
  Hypertrophy/Powerlifting pattern, if a real curated library grows.
- Cross-program concurrent scheduling beyond same-week soft interference
  avoidance (`ConcurrentScheduler`'s own, separate, later concern).

## 16. External Research Decision

For every gap identified in §5/§8/§9, a defensible V1 product decision is
achievable using ONLY the existing FF architecture and already-established
methodology (deterministic variance rotation, existing stimulus/format
vocabulary, existing composition mechanism) — none require new external
research into CrossFit/Marcus Filly/HWPO/Mayhem programming to ship V1.
**EXTERNAL RESEARCH REQUIRED BEFORE FF V1: NO.** The one item that
genuinely would benefit from a future, deliberate methodology decision
(true progression across mesocycles, §15) is explicitly deferred to V2,
per the checkpoint's own default-against-research instruction.

## 17. Recommended Next Checkpoint

A narrow "FF V1 Multi-Week Content + Variance Activation" implementation
checkpoint covering exactly §14 — author 2-3 real configurations with
genuine week-to-week variation and non-nil `VarianceConstraints`, extend
`LongTermPlanner`'s FF candidate surface additively, add the fidelity/
dogfood tests proving the existing (already correct) variance/diversity/
composition engines actually fire in a real multi-week materialization —
with its own dogfood proof that a real 4-week FF program shows genuine
session-to-session and week-to-week difference, not the same shape
repeated.

---

POWERLIFTING V1 CHECKPOINT: CLOSED
FUNCTIONAL FITNESS CURRENT PIPELINE UNDERSTOOD: YES
FF V1 BOUNDARY IDENTIFIED: YES
EXTERNAL RESEARCH REQUIRED BEFORE FF V1: NO
READY FOR FF V1 IMPLEMENTATION: YES
