# Functional Fitness Prescription Depth — Design / Audit

**Status: DESIGN / AUDIT ONLY. Nothing implemented, committed, or pushed.**

This document builds on three closed prerequisites: Stage CP.2 (`bca43e2ff47d21d8703275d06354af6a086f0d45`, cross-modality/same-week Concurrent Programming coordination), Stage FF.L1 (`ae5898c36cdb5617edf77f2ad68507149ea3e2ac`, INTENDED-vs-FINAL Stimulus foundation), and Stage FF.E1 (`a3c3d0b532a68878411a9383f1d154225bdc4fc4`, truthful `PrescriptionAdherence`). None is modified here. The truthful chain those stages built is:

CONFIGURED BASELINE → INTENDED STIMULUS → FINAL STIMULUS → MATERIALIZED WORKOUT → PERFORMANCE RESULT → PRESCRIPTION ADHERENCE

This audit asks: is the MATERIALIZED WORKOUT itself deep enough for any of that truthfulness to matter? Every claim below is grounded in a direct read of the real production code as it stands after FF.E1 — not restated from prior audits without re-verification.

---

## 1. End-to-end generation trace

Traced exactly, file:line, from the one real production path:

1. **`LongTermPlanner.functionalFitnessParameterCandidates(component:)`** (`LongTermPlanner.swift:1201-1224`) — the SOLE real construction site for a generated FF `Stimulus`, used identically by every FF-producing mix (`muscleGainVariedMix`, `fatLossVariedMix`, `functionalFitnessFocusedMix`, etc. — confirmed by grep, all route through this one function regardless of the mix's own `adaptationObjectives`). Creates ONE fixed `Stimulus` (`targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural], movementModalityMix: [weightlifting:1, gymnastics:1, metabolicConditioning:1], skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time`) and ONE fixed `format: .roundsForTime(rounds: 5, capSeconds: nil)`, wrapped in a `FunctionalFitnessProgramConfiguration` with `varianceConstraints: VarianceConstraints()` (all-nil, confirmed unchanged). `days = component.frequency.target` is the only per-mix variation — everything else is identical regardless of which mix, which objectives, or which priority requested it.
2. **`FunctionalFitnessProgramGenerator.generate`** (`:36-87`) builds `configuration.lengthWeeks` (4) identical `TrainingWeek`s (all `isDeload: false`), and for each of `daysPerWeek` `TemplateSession`s, ONE `FunctionalFitnessPrescriptionTemplate` carrying the SAME `stimulus`/`format`/`varianceConstraints` — reused unchanged across the whole `ProgramDefinition`'s life. Stage C (`movementSlots(for:context:)`, `:94-118`) runs here: for each `ModalityCount` entry (expanded by its own `count`), builds one `FunctionalFitnessMovementSlotTemplate(loadingRole: stimulus.loading)` — **and this is the ENTIRE numeric-prescription content the generator ever produces: `reps`/`calories`/`distanceMeters`/`loadKilograms`/`minuteSlot`/`repScheme` are never passed to this initializer at all, confirmed by the exact call site (`:110`), so all five stay at their declared `nil`/`0`/`[]` defaults.** The movement function assigned to each slot is round-robin from `stimulus.movementFunctions` (`:99-101`) — deterministic, never random.
3. **Stages D/E deliberately deferred to materialization** (the generator's own doc comment, `:14-24`, states this explicitly: they depend on live exposure history/candidates unavailable at generation time).
4. **`FunctionalFitnessDecisionEngine.decideWithIntent`** (called from `FunctionalFitnessMaterializer.materializeWeek:95-102`) runs Phase 1 (4 original variance checks, always a no-op in production since `VarianceConstraints()` is all-nil) then Phase 2 (CP.2's 2 checks) against `ffTemplate.stimulus` — producing `intendedStimulus`/`finalStimulus`. **Neither phase ever touches `reps`/`load`/`distance`/`calories` — the entire decision-engine chain, both pre- and post-FF.E1, operates exclusively on the 8 `Stimulus` fields, never on `FunctionalFitnessMovementSlotTemplate`'s numeric fields.**
5. **`FunctionalFitnessMaterializer.materializeWeek`** (`:110-147`) constructs the real `FunctionalFitnessPrescription` (`stimulus: decision.finalStimulus, intendedStimulus: decision.intendedStimulus`, per FF.L1) and, for each `slotTemplate` in `ffTemplate.orderedMovementSlots`, resolves a concrete `Exercise` (Stage D — deterministic, GOING-FORWARD-override-first, else first candidate satisfying the slot's typed constraints, `:131-132`) and constructs a `FunctionalFitnessMovement(exercise:, reps: slotTemplate.reps, calories: slotTemplate.calories, distanceMeters: slotTemplate.distanceMeters, loadKilograms: slotTemplate.loadKilograms, minuteSlot: slotTemplate.minuteSlot)` (`:134-141`) — **a faithful 1:1 copy of whatever the template held.** Since the template's own numeric fields are always nil/0/empty (per §1 above), **every real generated `FunctionalFitnessMovement`'s `reps`/`calories`/`distanceMeters`/`loadKilograms` is always nil, unconditionally, with 100% certainty, for every real production FF session ever materialized.** This is not a probabilistic gap — it is a structural guarantee, because the ONLY code path that could ever populate the template's numeric fields (Stage C in the generator) never does.
6. **Stage E validation** (`FunctionalFitnessStimulusValidator.validate`, `:50-108`) checks `matchesDuration`/`matchesModality`/`matchesLoading` (categorical `loadingRole` vs. `target.loading`)/`matchesSkill` (**hardcoded `true`, always** — see §12)/`matchesScoreType`. **Never inspects `reps`/`load`/`distance`/`calories` at all** — validation has no opinion on numeric prescription depth, confirming it is not what's blocking this.
7. **Execution UI** (`FunctionalFitnessExecutionView.swift`) — confirmed by exhaustive grep: zero references anywhere to `movement.reps`/`.loadKilograms`/`.distanceMeters`/`.calories`/`.loadingRole`. The live execution surface neither displays nor allows editing any of these fields, consistent with them always being nil in practice — but this also means the UI has genuinely never been built to show them even conceptually.
8. **Completed-detail UI is a different, important story** (`CompletedFunctionalFitnessDetail.swift:120-124`): this view ALREADY contains real, ready, dormant display code — `if let reps = movement.reps { parts.append("\(reps) reps") }` and the equivalent for calories/distance/load — gated correctly on optionality, simply never triggered because the upstream fields are never populated. **This is decisive evidence that reason (E) "execution UI cannot render it" is FALSE for the summary/detail surface** — the UI is ready and waiting; only the generator-side data is missing.

## 2. `FunctionalFitnessMovement` field audit

| Field | Meaning | Persisted/Derived | Writer | Reader | Generated FF populates? | Benchmark/seed populates? | Execution UI shows? | Classification |
|---|---|---|---|---|---|---|---|---|
| `exercise` | Resolved canonical exercise | Persisted | `FunctionalFitnessMaterializer` (Stage D) | Everywhere | **Yes, always** | Yes | Yes | **ACTIVE PRODUCTION PRESCRIPTION** |
| `reps` | Prescribed rep count | Persisted | Never set by the generator; copied 1:1 from the (always-nil) template by the materializer | `CompletedFunctionalFitnessDetail` (dormant) | **No, never** | **Yes** (`SeedScenarios.swift`, e.g. Fran's `21/15/9`-shaped movements) | Dormant (ready, never triggered) | **DOMAIN CAPABILITY BUT UNWIRED** |
| `calories` | Prescribed calorie target | Persisted | Same as `reps` | Same | No, never | Yes, for monostructural benchmark content | Dormant | **DOMAIN CAPABILITY BUT UNWIRED** |
| `distanceMeters` | Prescribed distance | Persisted | Same as `reps` | Same | No, never | Yes | Dormant | **DOMAIN CAPABILITY BUT UNWIRED** |
| `loadKilograms` | Prescribed absolute load | Persisted | Same as `reps` | Same | No, never | Yes (benchmark load-based movements) | Dormant | **DOMAIN CAPABILITY BUT UNWIRED** |
| `minuteSlot` | EMOM 1-based minute assignment | Persisted | Generator's Stage C *could* set this on the template but does not (same nil pattern); never populated in real generated content | EMOM display logic | No | Only where seed/tests construct EMOM content directly | Yes (EMOM body reads it) | **DOMAIN CAPABILITY BUT UNWIRED** for generated content, **ACTIVE** for hand-authored/seed EMOM |
| `substitutionUsed`/`substitutionReason` | Whether/why a different exercise was used | Persisted | `SubstituteFunctionalFitnessMovementUseCase` (readiness-adaptation flow only, per the Execution Truth audit) | `CompletedFunctionalFitnessDetail` | N/A (materialization-time resolution isn't a "substitution") | N/A | Yes | **ACTIVE PRODUCTION**, but only via the readiness path, not athlete-initiated (out of this audit's scope, already documented) |
| `sourceExerciseSlot` | Traceability pointer for substitution validation | Persisted (relationship) | `FunctionalFitnessMaterializer` at construction | `SubstituteFunctionalFitnessMovementUseCase` | Yes, always (every materialized movement gets one) | N/A | No | **ACTIVE PRODUCTION** (infrastructure, not a prescription value) |
| `performedAttempts`/`readinessAdaptationDecisions` | Inverse relationships | Derived (relationship bookkeeping) | SwiftData, from declared inverses | Delete-rule correctness only | N/A | N/A | No | **DEAD/UNUSED** as a prescription concern — exists purely for correct cascade/nullify behavior, confirmed by its own doc comment ("nothing reads this") |

`loadingRole` lives on `FunctionalFitnessMovementSlotTemplate`, not `FunctionalFitnessMovement` itself (confirmed by direct read — `FunctionalFitnessMovement.swift` has no `loadingRole` field at all) — see §13 for why this matters.

## 3. `Stimulus` consequence matrix

Verified precisely against `FunctionalFitnessProgramGenerator.swift`, `FunctionalFitnessStressProfileMapper.swift`, and `FunctionalFitnessStimulusValidator.swift` directly:

| Axis | A: exercise selection | B: format | C: numeric prescription | D: stress profile only | E: no visible effect | F: validation only |
|---|---|---|---|---|---|---|
| `targetDurationDomain` | No | No | No | Yes (`durationClassification`) | No | **Yes** — must match the fixed format's own estimated duration domain or Stage-E throws (already found: BLOCKED BY FORMAT COHERENCE) |
| `intensity` | No | No | No | **Yes** (`overallIntensity`/`metabolicDemand`) | No | No |
| `loading` | No | No | No | **Yes** (`lowerBodyLoad`/`upperBodyLoad`, gated by `movementFunctions`) | No | **Yes, and dangerously so** — see the new finding in §7/§16 below: the materializer validates the FIXED template's `loadingRole` against the LIVE `finalStimulus.loading`, which can diverge the moment CP.2's repair actually fires |
| `movementModalityMix` | **Yes** (directly drives slot count/modality per entry) | No | No | No | No | Indirectly (feeds `resolvedModalities` overlap check) |
| `movementFunctions` | **Yes** (round-robin assigned per slot, feeds catalog filtering) | No | No | **Yes** (feeds `hasLowerBodyFunction`/`hasUpperBodyFunction`/`hasLocomotionFunction`) | No | No |
| `skillDemand` | No | No | No | No | **Yes — confirmed precisely, zero effect anywhere** (see §12: not even in the stress-profile mapper, which has no `skillDemand` input at all) | Nominally (`matchesSkill = true` unconditionally, with an explicit "deferred" note — so it can never fail either) |
| `systemicDemand` | No | No | No | **Yes** (`systemicDemand`/`recoveryDemand`) | No | No |
| `scoreType` | No | No | No | No | No | **Yes** — must equal the format's own `defaultScoreType` or Stage-E throws |

## 4. `WorkoutFormat` prescription matrix

All 9 real cases (`WorkoutFormat.swift:8-18`), what each structurally prescribes, and what remains unspecified inside it:

| Format | Structurally prescribes | Remains unspecified |
|---|---|---|
| `.amrap(capSeconds:)` | Time cap only | Rounds achieved (that's the SCORE, not the prescription); which movements, how many reps of each |
| `.emom(intervalSeconds:, totalSeconds:)` | Interval length + total duration (derives minute count) | Which movement occupies which minute beyond `minuteSlot` (unpopulated for generated content), reps/load per minute |
| `.forTime(capSeconds:)` | Optional time cap | Everything about the actual work — reps, rounds, load |
| `.roundsForTime(rounds:, capSeconds:)` | **Round count** (the one real structural number generated FF actually uses today) + optional cap | Reps/load/distance per round, movement order beyond slot sequence |
| `.chipper(capSeconds:)` | Optional cap | The entire chipper's actual rep/movement ladder — `repScheme` exists on the template exactly for this but is never populated for generated content |
| `.ladder(direction:, capSeconds:)` | Ascending/descending direction + optional cap | The actual per-rung rep counts (again, `repScheme`, unpopulated) |
| `.maxLoad` | Nothing structural (a single-lift format) | The load itself — ironically the ONE format whose entire point is a numeric load, and generated content still prescribes none |
| `.maxReps(capSeconds:)` | Time cap | The rep target — the athlete's own rep count IS the score, so there is no separate "prescribed reps" to specify here by definition |
| `.intervals(count:, workSeconds:, restSeconds:)` | Full work/rest/count structure (the most numerically complete format that exists) | Reps/load/distance performed per work interval |

**`.roundsForTime` is the only format real generated content actually produces** (per §1's finding that every FF mix routes through the same one configuration). Every other case's real prescription depth is currently theoretical for generated content — they are fully valid domain representations, exercised only by tests/seed data.

## 5. Real generated workout examples

**A. `muscleGainVariedMix` FF session** and **B. `functionalFitnessFocusedMix` FF session** produce byte-identical Stage A/B/C output, confirmed directly — both route through the same `functionalFitnessParameterCandidates` (§1). The only difference between them is `frequency.target` (2 vs. 4) and the mix-level `adaptationObjectives`, neither of which reaches the generator at all. So both real production examples are:

```
Format: 5 Rounds For Time (no cap)
Movement 1: modality=weightlifting, function=squatLoaded, loadingRole=.moderate
  → resolves to a real weightlifting/.squatLoaded catalog exercise (e.g. Wall Ball or
    equivalent — ExerciseCatalog.swift:154 assigns .weightlifting+.squatLoaded to a
    real seeded barbell/medicine-ball movement)
  reps = nil, load = nil, distance = nil, calories = nil
Movement 2: modality=gymnastics, function=gymnasticsPull, loadingRole=.moderate
  → resolves to a real gymnastics/.gymnasticsPull catalog exercise
    (ExerciseCatalog.swift:192 — Pull-up carries exactly this pairing)
  reps = nil, load = nil, distance = nil, calories = nil
Movement 3: modality=metabolicConditioning, function=monostructural, loadingRole=.moderate
  → resolves to a real metabolicConditioning/.monostructural catalog exercise
    (ExerciseCatalog.swift:199/204/209 — Assault Bike/Row Erg-family entries carry
    exactly this pairing)
  reps = nil, load = nil, distance = nil, calories = nil
```

The athlete literally sees: **"5 Rounds For Time: [Exercise 1], [Exercise 2], [Exercise 3]"** — with no rep count, no load, no distance, no calorie target, for any movement, in any real generated FF session that exists in this product today. This is not a summary of the gap — it is the complete, exact, real prescription depth of every generated FF workout.

**C. One workout per materially different `WorkoutFormat` family:** since the real generator only ever produces `.roundsForTime`, every other family (AMRAP, EMOM, chipper, ladder, max-load, max-reps, intervals) is currently reachable ONLY through test fixtures, seed data (`SeedScenarios.swift`'s Fran demo — a hand-authored `.roundsForTime`/`21-15-9` benchmark, itself using `reps` populated directly, not through the generator), or `TrainingOSTests/` constructions that build a `FunctionalFitnessProgramConfiguration` directly with a different `format` value — proving the DOMAIN can represent every format richly, while the GENERATOR only ever exercises the shallowest one.

## 6. Prescription-depth matrix

| Dimension | Domain CAN represent it | Generator ACTUALLY produces it | Classification |
|---|---|---|---|
| Movement identity | Yes (`Exercise`) | **Yes** | FULLY PRESCRIBED |
| Movement order | Yes (`sortIndex`) | **Yes** | FULLY PRESCRIBED |
| Movement function | Yes (`MovementFunction`) | **Yes** (round-robin) | CATEGORICALLY PRESCRIBED |
| Movement variant (difficulty tier) | **No stable representation** — see §12, catalog has no linked-variant concept | No | NOT REPRESENTED |
| Reps | Yes (`Int?`) | **No** | NOT PRESCRIBED |
| Load | Yes (`Double?` numeric) | **No** | NOT PRESCRIBED |
| Distance | Yes (`Double?`) | **No** | NOT PRESCRIBED |
| Calories | Yes (`Int?`) | **No** | NOT PRESCRIBED |
| Duration (block-level) | Yes (format's own cap/total) | **Yes, where format carries a cap** — but `.roundsForTime(capSeconds: nil)` is the real generated value, so even this is unset in practice | PARTIALLY PRESCRIBED (structurally capable, generated value is `nil`) |
| Round count | Yes | **Yes** (`rounds: 5`, the one real hardcoded number) | FULLY PRESCRIBED |
| Work interval | Yes (`.intervals`/`.emom`) | No (format never generated) | NOT PRESCRIBED for generated content |
| Rest interval | Yes (`.intervals`) | No | NOT PRESCRIBED for generated content |
| Pace/intensity (numeric) | **No numeric pace field anywhere in `Stimulus`/`FunctionalFitnessMovement`** | No | NOT REPRESENTED |
| Skill level | `skillDemand` exists categorically | **No effect anywhere** (§12) | CATEGORICALLY REPRESENTED, NOT FUNCTIONALLY PRESCRIBED |
| Range-of-motion/difficulty variant | No catalog concept | No | NOT REPRESENTED |
| Score target (target score to beat) | `scoreType` exists; no numeric TARGET field | No | NOT REPRESENTED (only the SCORING METHOD is prescribed, never a target value) |
| Time cap | Yes (`capSeconds`) | **No** (real generated value is `nil`) | NOT PRESCRIBED in practice, though structurally capable |

## 7. Reason each numeric dimension is currently missing (independent, not grouped)

- **Reps**: **(B) generator never sets an existing field.** The domain model (`FunctionalFitnessMovement.reps: Int?`, `FunctionalFitnessMovementSlotTemplate.reps: Int?`) is fully present and already correctly consumed by seed/benchmark content and dormant UI — `FunctionalFitnessProgramGenerator.movementSlots` simply never passes a value for it (`:110`). Not a domain gap, not a catalog gap, not a UI gap.
- **Load**: **(B) generator never sets an existing field**, compounded by a real, separate **(C) movement-catalog gap**: even if the generator wanted to set a number, no general-purpose numeric strength anchor exists for most FF movements (see §9 — `ExercisePerformanceProfile.estimatedOneRepMax` is real and general, but only populated for exercises the athlete has actually logged `SetResult`s against, which most FF-catalog movements — Wall Ball, Pull-up, Row Erg — never are). So even fixing (B) alone would only work for the subset of FF movements that happen to overlap with a Hypertrophy/Powerlifting-logged exercise.
- **Distance/Calories**: **(B) generator never sets an existing field.** No catalog metadata gap exists here — see §11, the domain doesn't even need per-exercise metadata to prescribe a flat, format-consistent number (e.g. "500m Row"), it simply never does.
- **Skill/difficulty variant**: **(C) movement-catalog metadata gap, genuinely different from the others** — this is not a generator-wiring problem, because there is nothing to wire TO. The catalog has no linked-difficulty-tier concept (§12) — `.rmBased`-style progression logic couldn't consume this even if the decision engine tried, since the underlying `Exercise` entities for e.g. "Pull-up" and a harder variant simply don't both exist as related catalog entries today.

No dimension's absence is explained by (A) domain-model-missing, (D) decision-engine-lacks-rules [the engine never touches these fields at all — nothing to lack rules FOR], (E) execution-UI-cannot-render [disproven for the summary/detail surface, §1 item 8], (F) validation-prevents-it [validation has zero opinion on these fields, §1 item 6], (G) no-progression-model [structural, non-progressive prescription — "10 wall balls" — needs no progression model at all, per §10], (H) deliberate product choice [no doc comment anywhere states this was intentionally withheld — it reads as an honest generator-scope limitation, consistent with the generator's own stated V1 scope], or (I) intent not recoverable — the generator's own doc comment is explicit that Stage A (`stimulus`)/B (`format`) are supplied by the caller and Stages C-E are "what runs here," with no claim anywhere that reps/load/distance were ever meant to be produced by this stage. The most honest classification for reps/distance/calories is squarely **(B)**; for load specifically it is **(B) + (C)** together.

## 8. Exercise-catalog capability audit

Real `Exercise` fields (`Exercise.swift:14-72`, confirmed by direct read): `id`, `canonicalName`, `modality: TrainingModality`, `equipment: String` (a free-text descriptor, e.g. `"barbell"`/`"bodyweight"`/`"medicineBall"`/`"bike"`/`"rower"` — confirmed real values from `ExerciseCatalog.swift`), `movementPattern: String`, `primaryTargets: [MuscleGroup]`, `movementFunctions: [MovementFunction]`, `functionalModality: FunctionalModality?`, `requiredEquipment: [EquipmentRequirement]`, `aliases`, `resolvedSlots`. **No fields exist for**: default rep ranges, distance/calorie capability flags, unilateral/bilateral, skill classification, or any linked-difficulty-variant relationship. `equipment` is a loose string, not a structured bodyweight-vs-external-load boolean, though it's usable as a coarse proxy (`"bodyweight"` vs. anything else).

**Smallest missing metadata that genuinely blocks useful prescription: none is strictly required for reps/distance/calories** — a flat, format-consistent number ("10 Thrusters," "250m Row") needs no per-exercise metadata at all, only a generator decision to assign one. **For numeric load specifically, the smallest missing piece is a reusable strength anchor per FF movement** — not a new catalog field, but a real data availability gap (§9). **For skill/difficulty progression, the smallest missing piece is a genuine catalog relationship** (e.g. "Chest-to-Bar Pull-up is a harder variant of Pull-up") that does not exist today and would require new catalog entries plus a new linking concept — a real, nontrivial gap, not a wiring oversight.

## 9. Numeric-load feasibility

Traced every real reusable data source:

- **Categorical `Stimulus.loading`** — real, but explicitly coarse (4 cases), never a number (§13).
- **Source RM calibration** (`instance.sourceRMCalibration(for:rmType:)`, used by `RollTacticalWindowUseCase`'s `strengthSlotContext`, `:293`) — real, but scoped explicitly to Hypertrophy/Powerlifting `ProgramInstance`s requiring a source-workbook-tested RM (10RM/8RM/5RM per `RMType`) for a specific slot's specific `Exercise`. **Not general-purpose** — most FF catalog movements (Wall Ball, Pull-up, Row Erg) never go through this calibration flow at all, confirmed by its own doc comment's explicit "permanent-per-exercise vs. fresh-per-mesocycle" scoping.
- **`ExercisePerformanceProfile.estimatedOneRepMax`** (`ExercisePerformanceProfile.swift:16`) — **real, general-purpose, keyed by any `Exercise`**, populated from real logged `SetResult`s regardless of which program logged them. **This is the one honest, reusable source that could feed a numeric FF load prescription** — but only conditionally: it exists only for an `Exercise` the athlete has actually performed and logged strength data against. A bodyweight/implement-fixed FF movement (Pull-up, Wall Ball, Row Erg) would almost never have this populated; a barbell/dumbbell FF movement that happens to be a canonical `Exercise` ALSO used in the athlete's Hypertrophy/Powerlifting program (e.g. a shared "Deadlift"/"Thruster" entry) genuinely could.
- **Relative-bodyweight prescription** — no athlete bodyweight field was found referenced anywhere in this audit's read of `Exercise`/`FunctionalFitnessMovement`/`Stimulus`; not confirmed available without further investigation outside this audit's scope.
- **Fixed absolute defaults / percentage-of-known-anchors formula** — CLAUDE.md rule 10 explicitly forbids inventing an unvalidated threshold/formula into persisted logic; no such formula is proposed here.

**Answer: NO, FF cannot currently prescribe a real numeric load without either (a) a new FF-specific athlete calibration system, or (b) accepting that numeric load prescription would only ever be available for the subset of FF movements that happen to coincide with an `Exercise` the athlete has independently logged real strength data against via `ExercisePerformanceProfile` — and even then, the % of that 1RM to prescribe is itself an unvalidated formula this audit does not invent.** The complete honest chain that DOES exist today: `SetResult` (logged elsewhere) → `ExercisePerformanceProfile.estimatedOneRepMax` (real, derived) → **[missing: a validated percentage-prescription formula]** → a numeric load. The chain is real up to the point a product decision about the percentage would need to be made — which this audit correctly does not invent.

## 10. Rep-prescription feasibility

`FunctionalFitnessMovement.reps`/`FunctionalFitnessMovementSlotTemplate.reps` are real, already fully functional fields (proven by seed/benchmark content and dormant detail-view display, §1/§2). **STRUCTURAL rep prescription — "10 Wall Balls," a fixed number chosen once at generation/materialization time with no athlete-specific calibration and no week-to-week change — is possible RIGHT NOW, with zero new domain work, purely by having the generator's `movementSlots` function pass a `reps:` value instead of omitting it.** This requires no progression model, no catalog metadata, no new persisted state — it is a pure generator-authoring decision (what number to pick, e.g. a fixed value per `WorkoutFormat`/movement-function combination), which IS itself a product decision needing SOME rule (CLAUDE.md rule 10 still applies — the rule must be a stated, documented product choice, not an invented "feels right" number). **PROGRESSIVE rep prescription (changing the number over time based on exposure/performance) is a materially larger question, requiring the same performance-evidence-and-progression-axis machinery the earlier longitudinal-programming audit already found absent** — and is explicitly out of this stage's scope per §19/§20 below.

## 11. Distance/calorie feasibility

The domain (`FunctionalFitnessMovement.distanceMeters: Double?`, `.calories: Int?`) can represent both; no catalog metadata is required to populate a flat, format-consistent value (e.g. "500m Row," "20 Calorie Bike") — monostructural movements (`.monostructural`/`.locomotion` `MovementFunction`s, confirmed real catalog entries "Assault Bike"/"Row Erg" carry exactly these) don't need per-exercise distance/calorie CAPABILITY metadata the way load prescription needs a strength anchor, because a flat, generator-chosen number works identically regardless of which specific monostructural exercise gets resolved. **The exact same blocker as reps: (B) generator never sets an existing field** — not a measurement-model gap, not a `WorkoutFormat` gap (any format that already carries a duration cap could just as easily carry a distance/calorie target instead, per the format's own scoring intent), not an activity-specific-metadata gap.

## 12. Skill/difficulty feasibility

**Verified precisely, re-confirmed directly against `FunctionalFitnessStimulusValidator.swift:85-89` and `FunctionalFitnessStressProfileMapper.swift` (which has no `skillDemand` parameter or reference anywhere in its body): `Stimulus.skillDemand` has genuinely ZERO effect on ANYTHING in real production code** — not movement selection, not stress-profile classification, not even validation (which hardcodes `matchesSkill = true` with an explicit doc comment: "No per-Exercise skill classification exists yet... always passes"). This is the most completely inert field in the entire `Stimulus` struct.

The catalog does NOT distinguish movement-difficulty variants — confirmed by direct search of `ExerciseCatalog.swift`: "Pull-up" and "Handstand Push-up" exist as real seeded entries, but no "Chest-to-Bar Pull-up," "Pistol (single-leg squat)," or "Power Clean" entries exist anywhere in the real catalog. Even if they did, nothing links them as a difficulty progression of a base movement — `Exercise` has no such relationship field (§8). **This audit does not propose a speculative skill-progression system** — the honest finding is that both the wiring (decision engine/validator) AND the underlying catalog data (linked variant relationships) are absent, and building either without the other would be incoherent.

## 13. Loading terminology map

Five genuinely distinct "loading" concepts exist in this codebase, and conflating any two of them would be a real correctness bug:

| Concept | Type | Grain | What it actually means |
|---|---|---|---|
| `Stimulus.loading` | `LoadingClassification` (4 cases: `.bodyweightOnly`/`.light`/`.moderate`/`.heavy`) | Per-block, categorical | What CP.1/CP.2/the decision engine reason about — a coarse programming-intent label, never a number |
| `FunctionalFitnessMovementSlotTemplate.loadingRole` | `LoadingClassification?` | Per-movement-slot, categorical, fixed at GENERATION time | "How heavy this slot should be, independent of which Exercise fills it" — explicitly documented as "informational... not a hard substitution filter." **Critically, this value is a snapshot of the template's ORIGINAL configured `stimulus.loading` and is never updated when the decision engine's per-week `finalStimulus.loading` differs** (see the new finding in §16 below) |
| `FunctionalFitnessMovement.loadKilograms` | `Double?` (numeric) | Per-movement, concrete | The only real NUMERIC load concept in the whole FF domain — always `nil` for generated content (§1/§6) |
| `TrainingStressProfile.lowerBodyLoad`/`.upperBodyLoad` | `LoadLevel` (categorical, from CP.1) | Per-session, derived | A DIFFERENT categorical scale, computed FROM `Stimulus.loading` + `movementFunctions` by `FunctionalFitnessStressProfileMapper` — exists purely for cross-modality interference reasoning (CP.2), never fed back into prescription |
| `ExercisePerformanceProfile.estimatedOneRepMax` | `Double?` (numeric) | Per-Exercise, athlete-specific, derived from logged `SetResult`s | The one real numeric strength anchor that exists in this codebase — general-purpose but NOT currently connected to FF prescription in any way |

**A categorical "heavy" (`Stimulus.loading == .heavy`) must never be treated as if it were a "100kg" prescription** — no code path in this audit does this today, but the risk is real precisely because `loadingRole` and `loadKilograms` sit right next to each other on adjacent types with superficially similar names.

## 14. Prescription-identity finding

Two generated FF workouts can be identified as: **SAME PRESCRIPTION SHAPE** — trivially, since every real generated FF workout for every mix shares the identical `Stimulus`+`format` (§1/§5) — there is currently only ONE shape in production. **SIMILAR STIMULUS** — meaningful once a real longitudinal/variance mechanism ever produces a genuinely different `Stimulus` week-to-week (not built yet, per the earlier longitudinal audit). **COMPLETELY DIFFERENT WORKOUT** — not currently distinguishable from "similar stimulus," because (as the Execution Truth audit already found and this audit reconfirms) there is no `workoutTemplate`/`workoutName`/`canonicalWorkoutID` concept for ordinary generated content, only `BenchmarkDefinition`'s deliberately separate, benchmark-scoped identity.

**Numeric progression COULD work without exact workout identity**, using the SAME mechanism CP.1/CP.2/FF.L1 already established: a comparison keyed on `Stimulus` field values + `WorkoutFormat` shape (not a workout NAME), exactly how `ScoreValue` comparability is already gated ("comparable only when format AND scoreType match exactly," per the Execution Truth audit). Structural rep/distance/calorie prescription (§10/§11) needs no identity concept at all — it's a property of THIS week's materialized content, not a comparison across weeks. This audit does not design benchmark retesting and finds no reason this stage would need to.

## 15. Variance-vs-depth architecture — the anchor-loss problem

Concrete example, using real domain types: if a future purposeful-variance check rotated `movementFunctions` from `[.squatLoaded, ...]` toward a different function (the EXISTING, currently-inactive `adjustForMovementFunction` check already has this exact mechanism, per the longitudinal audit), Stage D's exercise resolution would then resolve a DIFFERENT `Exercise` for that slot next week (e.g. Goblet Squat → a hinge-pattern movement instead). **If a hypothetical future load-progression mechanism had anchored "you did 40kg last time, try 42.5kg this time" against the movement-1 slot POSITION rather than the specific resolved `Exercise`, it would silently carry a Goblet Squat's load number forward onto a Deadlift** — a real, concrete anchor-loss risk. **This is exactly why WHAT workout is selected (variance/movement rotation) and HOW deeply the selected workout is prescribed (numeric depth) must stay architecturally separate concerns**, mirroring FF.L1's own INTENDED-vs-FINAL and FF.E1's own adherence-vs-completionContext separations: a future numeric-progression mechanism must key its anchor to the resolved `Exercise` identity (or `ExercisePerformanceProfile`, which already is `Exercise`-keyed, §9), never to a slot position, precisely because slot content is allowed to change under purposeful variance and progression evidence must not silently transfer across that boundary.

## 16. Concurrent Programming interaction — plus a new, decisive finding

**Lock confirmed: any future numeric prescription must be resolved from FINAL, never INTENDED** — exactly mirroring FF.L1's own already-proven discipline, since CP.2's adaptation is real and already changes `loading`/other fields between INTENDED and FINAL.

**Is `FunctionalFitnessMaterializer` still the right seam?** Yes, confirmed by the real call order: `decision.finalStimulus` only exists AFTER `decideWithIntent` returns (`FunctionalFitnessMaterializer.swift:95-108`), and Stage D exercise resolution (which any numeric prescription would need to run alongside, since e.g. a load value likely depends on WHICH exercise was resolved) already happens in this exact same function, in this exact same loop (`:124-147`). There is no earlier point where both FINAL and the resolved `Exercise` are simultaneously known, and no later point exists before the workout is considered materialized. This matches the SAME real precedent `StrengthMaterializer` already establishes for numeric strength prescription: `RollTacticalWindowUseCase.rollForward`/`.materializeFirstWindow` already thread a `slotContext` closure carrying real `PerformanceProfile`-derived numeric data (`rmKilograms`) into `StrengthMaterializer.materializeWeek` at the exact analogous point — confirmed directly (`RollTacticalWindowUseCase.swift:53,159,293-302`). **A future FF numeric-prescription stage should mirror this exact, already-proven pattern**: thread an analogous closure/context (carrying, e.g., `ExercisePerformanceProfile` lookups) into `FunctionalFitnessMaterializer.materializeWeek`, resolved AFTER `decision.finalStimulus`/Stage D's exercise resolution, never before.

**A new, decisive finding this audit surfaces, not previously documented: a real, currently-latent Stage-E validation bug exists for ANY future case where the decision engine's `finalStimulus.loading` differs from the template's fixed `loadingRole`.** Traced precisely: `FunctionalFitnessMaterializer.materializeWeek` collects `resolvedLoadingRoles` from `slotTemplate.loadingRole` (`:146`) — a value fixed ONCE at generation time, from the ORIGINAL configured `stimulus.loading`, and NEVER updated per week. It then validates these against `decision.finalStimulus` (`:156-158`) — the LIVE, potentially CP.2-adjusted value. `FunctionalFitnessStimulusValidator.validate`'s `matchesLoading` check (`:80`) requires every resolved loading role to equal `target.loading` exactly. **The moment CP.2's cross-modality repair actually changes `loading` (e.g. `.heavy → .moderate`, its own real, shipped mechanism) for a real production mix WITH non-empty movement slots, this validation would fail and `FunctionalFitnessMaterializer` would throw `stimulusValidationFailed`.** This is not a hypothetical: confirmed by direct read of the real CP.2 test suite (`CrossModalityFunctionalFitnessProgrammingTests.swift`) and the FF.L1 test suite (`FunctionalFitnessIntendedVsFinalStimulusTests.swift`) — **every single test that exercises CP.2's repair through the REAL materializer deliberately uses a `Stimulus` with `movementModalityMix: []`** (their own doc comments state this explicitly: "so Stage E checks... can never fail regardless of what CP.2 changes about loading"). **This means CP.2's loading repair has never actually been proven safe through the real materializer against a real, non-empty movement-slot mix — the exact shape every real production `muscleGainVariedMix`/`functionalFitnessFocusedMix` FF component actually has.** This is a genuine, pre-existing architectural risk this prescription-depth audit uncovered as a side effect of tracing the full pipeline precisely — flagged here, not fixed (fixing it is out of this audit's design/audit-only scope), and any future numeric-prescription stage MUST NOT copy this same "freeze at generation time" pattern for whatever new field it adds.

## 17. Intended/final/concrete-prescription contract

**INTENDED and FINAL staying `Stimulus`-level, with a single MATERIALIZED PRESCRIPTION holding concrete numbers, is sufficient — no "intended numeric prescription" duplicate is needed.** Reasoning: FF.L1's INTENDED/FINAL distinction exists specifically because CP.2 ADAPTS the stimulus between those two points — there are genuinely two different `Stimulus` VALUES worth preserving. A numeric prescription (reps/load/distance) would be resolved ONCE, downstream of FINAL, by a single deterministic function (per §16) — there is no analogous "the numeric value changed between two decision phases" event to preserve two snapshots of, unless a future stage explicitly designs a THIRD adaptation phase that adjusts numbers after they're first computed (not proposed here). The smallest immutable truth model: `FunctionalFitnessPrescription` (or a movement-level field) gains ONE new concrete value per numeric dimension, resolved once, immutable thereafter — exactly mirroring how `finalStimulus` itself is a single immutable snapshot, never a second "intended-numeric" duplicate.

## 18. Adherence interaction

FF.E1's `PrescriptionAdherence` is explicitly scoped, in its own doc comment, to "the dimensions TrainingOS actually prescribes today" — this is not an accident this audit needs to work around, it is the exact honesty discipline that makes the answer here straightforward: **`asPrescribed` records created BEFORE a future numeric-depth stage remain truthful FOREVER, with no reinterpretation needed, because they were only ever a claim about movement/format/completion — never a claim about reps/load/distance that didn't exist to confirm.** When a future stage adds real numeric prescription, `asPrescribed`'s MEANING naturally, mechanically widens going forward (because the dimensions "TrainingOS actually prescribes" grows), without invalidating a single historical record, precisely BECAUSE `FunctionalFitnessPrescription` (and any future per-movement prescribed-value field) is already an immutable, timestamped snapshot per FF.L1's own established discipline — **this does NOT require prescription-version-aware interpretation as a new mechanism; it falls out naturally from persisted prescription fields already being immutable snapshots**, exactly as this audit's own instruction suspected. No design work is needed here beyond confirming this — which is now confirmed.

## 19. First honest progression-axis reassessment

| Axis | 1: Prescribe concretely? | 2: Observe honestly? | 3: Compare over time? | 4: Athlete-visible? | 5: Coexists with variance? | 6: Needs new calibration? |
|---|---|---|---|---|---|---|
| LOAD | **No** (§9 — needs a new anchor system for most movements) | N/A yet | N/A yet | Yes, if ever prescribed | Yes (anchor to `Exercise`, §15) | **Yes** |
| REPS/VOLUME | **Yes, structurally** (§10) | Yes, once a numeric target exists to compare `scoreValue`/performed-reps against | Yes, once workout-shape identity (§14) is available | **Yes, immediately, even without progression** (§21) | Yes | **No** |
| CAPACITY/DURATION | Partially (`capSeconds` exists, generated value is always `nil`) | Yes, via existing timer/`completionContext` | Only once format is held constant (BLOCKED BY FORMAT COHERENCE, per the longitudinal audit, reconfirmed here) | Yes | No — direct conflict with the fixed-format constraint | No |
| SKILL | **No** (§12 — no catalog support at all) | No | No | N/A | N/A | **Yes, and a large one** (new catalog relationships) |
| DENSITY | No (needs workout-identity + numeric baseline) | No | No | N/A | N/A | Yes |
| REPEATABILITY | No (needs repeated identical numeric prescriptions first) | No | No | N/A | N/A | Yes |
| QUALITY (Rx/Scaled-equivalent) | Already real (FF.E1's `adherence`) | **Yes, already shipped** | Yes, already | Yes, already | Yes | No |

**REPS/VOLUME has the shortest honest path of any NEW axis** — structural rep prescription is possible today with zero new architecture (§10), produces an immediate, real athlete-visible difference ("10 Wall Balls" vs. "Wall Balls"), requires no athlete calibration, and coexists cleanly with variance (per §15's anchor-to-Exercise discipline). It is not yet a PROGRESSION axis (nothing compares exposure over time yet) — but it is the axis whose STRUCTURAL prescription alone would make the product feel meaningfully more programmed, which is exactly what this audit was asked to find (§20).

## 20. Minimum viable prescription-depth recommendation

**Recommend (A) reps only, structural — not progressive.** Justified directly by §7/§10/§19: reps is the one dimension with zero blocking factors (no catalog gap, no validation conflict, no format-coherence risk, no athlete-calibration need) — purely a generator-authoring decision. (B) reps+distance/calories is a reasonable NEXT increment (§11 shows an identical, equally clean path) but is not "smaller" than (A) in any architecturally meaningful way — it's the same fix applied to a second field, better sequenced as a fast-follow than bundled, to keep the first stage narrowly verifiable. (C) categorical load guidance risks the exact `loadingRole`-vs-`loadKilograms` conflation this audit warns against in §13 — a "moderate" load LABEL is not new information the athlete doesn't already implicitly get from the exercise choice itself. (D) numeric load is explicitly NOT recommended yet — §9 proves it requires either new athlete calibration or an unvalidated percentage formula, either of which is a real, separate, larger product decision. (E) per-movement structured targets (reps+load+distance+calories all at once) bundles (D)'s unresolved blocker into what would otherwise be a clean stage.

## 21. Athlete-facing before/after examples

**Example 1 (weightlifting/gymnastics/metcon triplet, the real production shape, §5):**
- Before: *"5 Rounds For Time: Wall Ball, Pull-up, Row Erg."*
- After (reps-only): *"5 Rounds For Time: 15 Wall Balls, 10 Pull-ups, 250m Row."* — note distance stays unset in this "reps only" example since Row Erg's natural unit is distance, not reps; a rounded-out (B)-stage version would read *"...15 Wall Balls, 10 Pull-ups, 250m Row"* with the distance also populated, which is why (B) is the natural fast-follow, not a separate architectural stage.

**Example 2 (a hypothetical bodyweight-only slot set, still `.roundsForTime`, using only real catalog entries):**
- Before: *"5 Rounds For Time: Push-up, Pull-up."*
- After: *"5 Rounds For Time: 15 Push-ups, 10 Pull-ups."*

**Example 3 (`.maxLoad` format, currently ONLY reachable via test/seed content, never generated):**
- This format structurally has NOTHING to add via reps-only work (§4 — `.maxLoad` is defined by load, not reps) — a genuine, honest limit of the (A) recommendation: it improves the one real generated format (`.roundsForTime`) completely, and would improve `.amrap`/`.chipper`/`.ladder`/`.intervals` if the generator ever produced them, but does nothing for `.maxLoad`/`.maxReps`, which are structurally about the dimensions (A) deliberately defers.

## 22. Ownership model

| Dimension | Owner | Why |
|---|---|---|
| Reps (structural) | **`FunctionalFitnessProgramGenerator`** (Stage C, `movementSlots`) | The exact same place `loadingRole` is already assigned — no new architectural layer, just one more parameter at an existing call site |
| Distance/Calories (structural, fast-follow) | Same — `FunctionalFitnessProgramGenerator` | Identical reasoning |
| Numeric load (future, if ever built) | **`FunctionalFitnessMaterializer`** (a new context/closure, mirroring `StrengthMaterializer`'s established `slotContext` pattern, §16) | Needs athlete-specific data (`ExercisePerformanceProfile`) and the resolved `Exercise` identity, both only available at materialization time — never at generation time, which is user-independent by this generator's own architecture |
| Movement-difficulty/skill (future, if ever built) | Would require BOTH a new catalog relationship (owned by `ExerciseCatalog`/`Exercise`) AND a new decision-engine check (owned by `FunctionalFitnessDecisionEngine`) — genuinely incoherent to assign to either alone | Neither exists today; this audit does not design it |

**No dedicated new "FF Prescription Engine" layer is recommended.** The generator already owns Stage C (movement-slot construction, where reps/distance/calories naturally belong) and the materializer already owns Stage D/E (where any future athlete-specific numeric resolution would belong, mirroring `StrengthMaterializer` exactly) — introducing a new layer between them would duplicate responsibility the existing two-stage split already cleanly expresses.

## 23. Exact proposed domain/types/files for next stage (FF.P1, reps-only)

- `FunctionalFitnessProgramGenerator.movementSlots` (`:94-118`) — pass a `reps:` value into the `FunctionalFitnessMovementSlotTemplate(...)` initializer, per a new, explicit, documented product rule (e.g. a fixed rep count keyed by `MovementFunction`/`FunctionalModality` combination — the EXACT rule is a product decision this audit does not invent, per CLAUDE.md rule 10; it must be authored explicitly, not guessed).
- No new persisted field — `FunctionalFitnessMovementSlotTemplate.reps`/`FunctionalFitnessMovement.reps` already exist (**DOMAIN CAPABILITY, not a new concept** — reusing existing fields exactly as instructed).
- The reps-assignment rule itself, if it needs its own home rather than living inline in `movementSlots`: classify as an **APPLICATION STATE**-free, pure **DERIVED VALUE** function (e.g. `FunctionalFitnessRepPrescription.repsFor(movementFunction:modality:) -> Int`), analogous in spirit to `FunctionalFitnessStimulusValidator`'s own pure-function shape — not a new persisted type, not a new engine.
- No change to `FunctionalFitnessMaterializer`, `FunctionalFitnessDecisionEngine`, `FunctionalFitnessStimulusValidator` (reps aren't validated today and don't need to be for this stage), `LongTermPlanner`, CP.2's files, FF.L1's files, FF.E1's files, or any source-authority file.

## 24. Required tests

A rep-prescription-rule unit test proving the chosen rule is deterministic and table-driven (CLAUDE.md rule 4) across every real `MovementFunction`/`FunctionalModality` combination the generator actually produces; a real-materialization test proving a generated `FunctionalFitnessMovement.reps` is now non-nil for the real `muscleGainVariedMix`/`functionalFitnessFocusedMix` shapes; a regression test confirming Stage-E validation behavior is completely unchanged (reps were never validated, must not start being validated as a side effect); a regression test confirming `CompletedFunctionalFitnessDetail`'s existing dormant display logic now activates correctly with real data (no UI code change needed, but its correct activation should be proven); full existing suite unchanged.

## 25. Stress-test walkthroughs

- **Bodyweight-only workout**: reps-only prescription works cleanly (Example 2, §21) — no load dependency at all.
- **Barbell/dumbbell/kettlebell workout**: reps-only prescription still works (reps don't require a load value to be meaningful — "15 Thrusters" is a complete, honest instruction even with no prescribed weight) — but the athlete still self-selects load, exactly as today; this stage does not claim otherwise.
- **Monostructural-only workout**: reps-only recommendation (A) genuinely does nothing here — this is exactly why (B) distance/calories is the natural fast-follow, not bundled into (A) is still an honest, disclosed limitation of choosing (A) first.
- **Mixed-modal workout**: works per-slot independently — each movement's rep rule is evaluated on its own `MovementFunction`/`FunctionalModality`, no cross-slot dependency.
- **Upper-body-biased FF after lower-body HYP / lower-body FF after upper-body HYP**: unaffected — CP.2's cross-modality repair still operates purely on `Stimulus.loading`/other categorical fields (§3), reps-only prescription doesn't interact with or need to know about CP.2 at all, since reps are assigned at GENERATION time (before any per-week decision-engine call), not at materialization time.
- **CP.2 intended != final**: unaffected for the same reason — reps live on the template, set once at generation, independent of the per-week `Stimulus` adaptation chain entirely.
- **Time-capped / AMRAP / EMOM / for-time-rounds**: reps-only prescription would apply the identical rule regardless of format, since it's keyed on movement function/modality, not on format — genuinely format-agnostic, a real strength of choosing this axis first.
- **Max-load/max-reps formats**: **degrades truthfully** — `.maxLoad` has no reps dimension to prescribe at all (§21 Example 3); `.maxReps` is defined by the athlete's OWN rep output as the score, so a "prescribed rep count" would be incoherent for this one format and must be explicitly excluded from the new rule's domain, not silently applied.
- **Athlete with no prior load history**: entirely irrelevant to this recommendation — (A) reps-only never touches load or any athlete-specific data at all, so "no history" degrades to exactly the same experience as "some history": a real, athlete-independent rep count either way.
- **Athlete with rich prior strength history**: also irrelevant to (A) for the same reason — this athlete's rich `ExercisePerformanceProfile` data remains completely unused by this recommendation, correctly deferred to a future numeric-load stage (§9/§20) that this audit explicitly does not authorize building yet.

## 26. Genuinely unresolved product decisions

- The exact rep-count rule itself (§23) — this audit explicitly does not invent one, per CLAUDE.md rule 10; it must be authored as a stated product decision before implementation, not guessed.
- Whether (B) distance/calories should ship as part of the same stage or as an immediately-following one — this audit recommends sequencing them separately for narrower verifiability, but does not treat this as a hard requirement.
- The real, currently-latent Stage-E validation risk (§16) — a genuine architectural gap this audit discovered as a side effect, not something this audit is authorized to fix, but one that any future stage touching `loadingRole`/per-week loading behavior MUST account for before it can safely activate.
- Whether/when a numeric-load anchor system (a new FF-specific calibration, or a formalized `ExercisePerformanceProfile`-percentage rule) is ever built — explicitly deferred, no timeline implied.
- Whether/when a catalog difficulty-variant relationship (§12) is ever built — explicitly deferred, a genuinely larger product/content-authoring investment than anything else surfaced in this audit.
- Whether the reps-assignment rule should ever be exposed to `AdaptationObjective`-aware variation (e.g. a `.workCapacity`-leaning component preferring higher rep counts) — not evaluated here, a real future question this audit does not answer, consistent with keeping this stage narrowly structural.

## 27. Exact next implementation-stage recommendation

**FF.P1 — Structural Rep Prescription.** Adds: a real, non-nil `reps` value on every generated `FunctionalFitnessMovement`, assigned once at generation time by `FunctionalFitnessProgramGenerator.movementSlots`, per an explicit, documented, deterministic rule keyed on `MovementFunction`/`FunctionalModality` (the exact rule to be authored, not invented here) — reusing entirely existing domain fields, touching no engine, no materializer, no CP.2/FF.L1/FF.E1 machinery, no source-authority code. Deferred: distance/calorie prescription (a clean, structurally identical fast-follow); numeric load prescription (blocked on a real athlete-calibration decision, §9); skill/difficulty prescription (blocked on new catalog relationships, §12); any form of progression, `VarianceConstraints` activation, benchmark retesting, substitution UI, readiness redesign, equipment/environment profiles, `StartPhaseUseCase` parity, HealthKit/Watch capture, the `SessionStatus.abandoned` fix, and the `incompleteMinuteIndices` persistence fix — **none of which this audit found to be a current architectural dependency of FF.P1; all remain correctly out of scope.**

---

## CP.2R Closure — Final Loading Materialization Repair

**Status: IMPLEMENTED (uncommitted). A narrow correctness repair, not a reopening of CP.2/FF.L1/FF.E1's own closed architecture or semantics.**

### The bug — proven, not assumed

§16 above predicted that `FunctionalFitnessMaterializer.materializeWeek` collects `resolvedLoadingRoles` from `slotTemplate.loadingRole` (frozen at generation time from the CONFIGURED `stimulus.loading`) and validates them against `decision.finalStimulus` (the live, potentially CP.2-adjusted value), and that every real CP.2/FF.L1 test exercising the repair through the real materializer dodges this by using `movementModalityMix: []`. **This was proven true empirically**, not merely asserted: a new test, `testCP2RRealNonEmptyMovementSlotWithGenuineLoadingRepairProof` (`CrossModalityFunctionalFitnessProgrammingTests.swift`), reproduced the exact real production path — real Strength peak-week materialization (`lowerBodyLoad = .high`), a real FF configuration with a genuinely non-empty `movementModalityMix` (`heavySquatStimulus()`, not the dodge-shaped `heavySquatMaterializableStimulus()`), a real candidate `Exercise` resolved into the real, non-empty movement slot, and CP.2's real cross-modality repair firing (`.heavy → .moderate`). **Before the fix, this test threw exactly the predicted error**: `stimulusValidationFailed(matchesLoadingClassification: false, notes: ["At least one movement slot's loadingRole contradicts the target stimulus's loading classification (moderate)."])`.

### The actual semantic meaning of `loadingRole`

Traced precisely: `FunctionalFitnessMovementSlotTemplate.loadingRole` is written exactly once, by `FunctionalFitnessProgramGenerator.movementSlots`, from the CONFIGURED `stimulus.loading` at generation time — before any per-week decision-engine call ever runs. Its own doc comment, written before Stage CP.2 existed, already states it is "informational for the generator/decision engine, not itself a hard substitution filter." **It never influences Stage-D exercise resolution**: `SubstitutionValidator.isValid` (the sole real resolution-eligibility check) reads only `allowedTargets`/`allowedMovementFunctions`/`allowedModalities` — confirmed by direct read, `loadingRole` appears nowhere in it. It is read exactly once elsewhere in production: Stage-E's `matchesLoading` check. It has no relationship to FF.L1's `intendedStimulus`/`stimulus` snapshots — those are per-week, per-materialization `Stimulus` values; `loadingRole` is a per-slot, per-`ProgramDefinition` (i.e. per-template, shared across every week of that definition's life) artifact, generated once and never revisited. **Before Stage CP.2 existed, this check was tautologically true**: the only `Stimulus` a slot's `loadingRole` was ever generated from and the only `Stimulus` it was ever validated against were, definitionally, the exact same value — the check never had the power to catch a real defect. Stage CP.2 is the first, and an intentional, mechanism that legitimately lets these two values diverge.

### The incorrect Stage-E invariant

`FunctionalFitnessStimulusValidator.validate`'s `matchesLoading` check (`resolvedLoadingRoles.allSatisfy { $0 == target.loading }`) required a frozen, generation-time, non-authoritative, informational value to exactly equal a live, per-week, intentionally-adaptable value. This was never a meaningful invariant — it was an accidental byproduct of both values happening to originate from the same `Stimulus` before Stage CP.2 gave the decision engine any reason to diverge them. Requiring their continued equality the moment a real, legitimate cross-modality adaptation mechanism exists is structurally incorrect, not a defensible safety check being "loosened."

### The repair — smallest correct fix

`FunctionalFitnessStimulusValidator.validate`'s `matchesLoading` is now deferred exactly like `matchesSkill` already is (an established, existing precedent in the same function, for the same "no real invariant to check here" reason): computed as `true` unconditionally, reported via an honest note ("Loading-role validation deferred: `loadingRole` is a generation-time-only, informational field that Stage CP.2 may legitimately diverge from the live target stimulus's loading; it was never a hard substitution filter and gates nothing downstream."), and removed from the `passes` gate. `resolvedLoadingRoles` remains an unchanged parameter/computation in the materializer (harmless, inert, not removed, to keep the diff to exactly one file's logic) — no new persisted field, no change to exercise selection, no change to CP.2's producer/consumer ordering, same-week complementarity, `GoalPriority` semantics, `adaptationObjectives`, scheduling behavior, or FF.L1/FF.E1's own persistence or semantics.

### Production-path regression coverage now in place

Two new tests close the exact coverage hole identified: `testCP2RRealNonEmptyMovementSlotWithGenuineLoadingRepairProof` (real non-empty slots, real resolved exercise, real CP.2 repair firing, materialization now succeeds, FINAL retains the repaired `.moderate` loading, INTENDED retains the unmodified `.heavy` configured value, the movement graph is intact) and `testCP2RControlCaseConfiguredEqualsFinalUnchangedWithRealNonEmptySlots` (identical real non-empty setup, no sibling stress at all, CONFIGURED == INTENDED == FINAL exactly, byte-for-byte, proving the fix changes nothing about the ordinary no-adaptation case). **Every one of the pre-existing 24 CP.2 tests that use `movementModalityMix: []` to dodge real slot generation remains unchanged and still passes** — this repair did not require rewriting them, only adding the two narrowly-targeted new tests that finally exercise the real, non-empty shape.

### Verification record

Both new tests pass. All 26 CP.2 tests pass (24 existing + 2 new). All 8 FF.L1 tests pass, unchanged. All 12 FF.E1 tests pass, unchanged. Full suite: 1027 passed / 2 skipped / 0 failed (baseline 1024/2/0 + 3 net new). Clean build, no new warnings. Zero CoreData/SwiftData warnings. Source-authority diff zero (all 6 files). `LongTermPlanner.swift` diff zero. Production `VarianceConstraints()` construction unchanged. Exactly one `SchedulingPipeline.propose` call site, unchanged. `FunctionalFitnessPerformedMovement.swift` zero diff. Readiness substitution code zero diff. `PrescriptionAdherence`/FF.E1 adherence code zero diff. No rep/distance/calorie/numeric-load field touched anywhere — FF.P1 was not started.

---

## FF.P1 Design Lock — Structural Movement Targets

**Status: DESIGN LOCK ONLY. Nothing implemented, committed, or pushed.** Builds on CP.2 (`bca43e2ff47d21d8703275d06354af6a086f0d45`), FF.L1 (`ae5898c36cdb5617edf77f2ad68507149ea3e2ac`), FF.E1 (`a3c3d0b532a68878411a9383f1d154225bdc4fc4`), CP.2R (`2f02c603e7b5acc0a4e1ff86ab1239a848d54f7d`) — none modified. Every claim below is grounded in a direct re-read of the real code, not carried forward from the prior audit's own recommendation without re-proof — the ownership question in particular is answered from first principles, not assumed.

### A. Exact FF.P1 product scope

**OPTION 2 — reps for repetition-native movement categories + distance for the distance-native monostructural category.** The prior audit's own (A) reps-only is REJECTED as the final scope: real production `movementModalityMix` is unconditionally `[weightlifting:1, gymnastics:1, metabolicConditioning:1]` (`LongTermPlanner.swift:1213-1217`) — every single real generated FF workout, with zero exceptions, contains exactly one monostructural slot. Reps-only would leave 1-of-3 movements in **every real generated workout** completely unprescribed, which is not a rare edge case this audit can defer — it is the guaranteed universal case. Calories is explicitly NOT included: it is idiomatic for Assault Bike/Row Erg/SkiErg but not for Easy Run/Track Interval Run (both real catalog entries with `equipment: "none"`, `ExerciseCatalog.swift:157-164`), and distinguishing calorie-appropriate from distance-appropriate monostructural exercises would require a per-exercise/equipment branch this stage does not need — distance alone applies honestly and uniformly to every real monostructural catalog entry (Bike, Row, SkiErg, Run all have a real, sensible distance reading). Numeric load stays explicitly deferred (unchanged from the prior audit — blocked on a real calibration decision).

### B. Production `WorkoutFormat` scope

**OPTION A — support only `.roundsForTime`, the sole format real generated content produces.** Confirmed again directly: `LongTermPlanner.functionalFitnessParameterCandidates` hardcodes `format: .roundsForTime(rounds: 5, capSeconds: nil)` (`:1219`) and is the only real construction site for any FF `Stimulus`/format pair. Implementation must gate on format explicitly — see M for the required signature change — so that hand-authored/test/seed content using any other format (AMRAP, EMOM, chipper, ladder, max-load, max-reps, intervals) degrades truthfully to no new target rather than silently applying a rounds-for-time-shaped rule. No format's rules are designed here beyond `.roundsForTime`.

### C. Target-type classification rule

Keyed on the SLOT's own declared `FunctionalModality` (authoritative for target TYPE, see F) — not the specific `Exercise` later resolved by Stage D, and not derived per-Exercise metadata (none needed, confirmed by the prior audit §11):

- `.weightlifting` slot → **reps**
- `.gymnastics` slot → **reps**
- `.metabolicConditioning` slot → **distance** (meters)
- Any other real `FunctionalModality` value: there are only 3 real cases in the entire enum (`Stimulus.swift:40-44`) — no fourth case exists, so no residual "unknown modality" branch is needed for FF.P1's classification itself, only for format-gating (B) and for movement-function reachability (E).

### D. Deterministic structural-dose rule

Total dose = round count (read from the gating format, `.roundsForTime(rounds:, _)`) × per-round target — never a single constant applied everywhere. Real production round count is always 5. Proposed dose classes, keyed on the slot's `MovementFunction` (authoritative for dose CLASS, see F) — **exact numbers are a proposed product decision for explicit sign-off, per CLAUDE.md rule 10, not silently invented into shipped logic**:

| MovementFunction (real slot value) | Dose class | Per-round target | Total @ 5 rounds |
|---|---|---|---|
| `.gymnasticsPull` | LOW REP (demanding bodyweight pulling) | 8 reps | 40 reps |
| `.squatLoaded` | MODERATE REP (loaded, more rep-tolerant) | 12 reps | 60 reps |
| `.monostructural` | DISTANCE | 200 m | 1000 m |

This is a small, closed table — not exercise-science precision, a coherent programmed-workout heuristic per the instruction's own framing. Stress-tested in O.

### E. Production-reachable `MovementFunction` mappings

Confirmed by direct read of `LongTermPlanner.functionalFitnessParameterCandidates` (the sole real construction site): **only 3 of the enum's 15 real cases are ever assigned into a real generated slot today** — `.squatLoaded`, `.gymnasticsPull`, `.monostructural`. Each is classified in D. Every other real `MovementFunction` case (`hingeLoaded`, `pressLoaded`, `gymnasticsPush`, `carry`, `locomotion`, `trunk`, `jumping`, `other`, `horizontalPullLoaded`, `verticalPullLoaded`, `verticalPushLoaded`, `kneeFlexionLoaded`) is **NOT PRODUCTION REACHABLE** — real, valid domain values, exercised only by tests/seed/benchmark content, correctly left with **no FF.P1 target** (classification D: "receives no concrete target in FF.P1") rather than a guessed rule for a case that cannot occur.

### F. `FunctionalModality` precedence

**`FunctionalModality` is authoritative for target TYPE (reps vs. distance); `MovementFunction` is authoritative for dose CLASS (how much) once type is decided.** Reasoning: modality is the more direct signal for "how is this measured" — `.metabolicConditioning` structurally implies engine/distance-style work regardless of which specific movement function happens to be paired with it, while `.weightlifting`/`.gymnastics` both structurally imply a countable-repetition style of work. `MovementFunction` then differentiates demand character within the reps type (a gymnastics pull is a more demanding per-rep pattern than a general loaded squat pattern, independent of modality). **In real production this precedence is currently moot** — every real slot's modality and function already agree by construction (`weightlifting`+`squatLoaded`, `gymnastics`+`gymnasticsPull`, `metabolicConditioning`+`monostructural` are the only 3 real pairs, confirmed identical index correspondence in `movementSlots`'s round-robin assignment). The precedence is locked now so a future format/stimulus richer than today's single triplet cannot silently misclassify a slot if a mismatch is ever introduced.

### G. Monostructural rule

Confirmed real catalog entries for the one real `.metabolicConditioning`/`.monostructural` slot: Assault Bike (`equipment: "bike"`), Row Erg (`"rower"`), SkiErg (`"skiErg"`), Easy Run/Track Interval Run (`"none"`) — `ExerciseCatalog.swift:157-209`. **A single flat distance number (200m/round, per D) applies uniformly regardless of which of these Stage D actually resolves** — deliberately NOT differentiated per specific exercise or equipment, mirroring exactly why `loadingRole` itself was defined at the slot/modality level rather than per-`Exercise` in the first place (a target keyed on the *specific resolved Exercise* would need to be recomputed on every substitution, reintroducing exactly the kind of frozen-vs-live tension CP.2R just resolved for `loading`). This is a real, disclosed imprecision — 1000m total means something different in wall-clock terms for a Row vs. a Run vs. an Assault Bike — accepted deliberately as truthful partial depth rather than fabricated per-equipment precision the domain doesn't yet model (equipment-aware calorie/pace differentiation is explicitly deferred, not designed here).

### H. Ownership: generator vs. materializer — stress-tested against the CP.2R failure class, not assumed

**LOCKED: `FunctionalFitnessProgramGenerator` (generation time), not the materializer — and this is now proven, not carried forward.** The CP.2R failure class was specifically: *a value frozen at generation time from field X, later checked for continued equality against a live, per-week value of the SAME field X, where a real mechanism (CP.2) legitimately changes X between generation and materialization.* Traced precisely whether a rep/distance target keyed on `MovementFunction`/`FunctionalModality` repeats this class:

- `CrossModalityStimulusRepair.minimalRepair` (CP.2's only stimulus-mutating repair) mutates **exactly one field: `Stimulus.loading`** — confirmed by direct read, its own repair table is explicitly restricted to `.lowerBodyLoad`/`.impactLoading` (both loading-driven), with an explicit doc comment forbidding extension to any other `StressDimension`.
- `AdaptationObjectiveStimulusMapping.nudge` (CP.2's same-week complementarity mechanism) mutates exactly one of `intensity`/`targetDurationDomain`/`systemicDemand`/`skillDemand` per call, per objective — confirmed by direct read of its full `switch`. **Neither CP.2 mechanism, in either of its two real code paths, EVER touches `movementFunctions` or `movementModalityMix`.**
- Therefore: a rep/distance target computed from `MovementFunction`/`FunctionalModality` at generation time depends on exactly the two `Stimulus` fields CP.2 is structurally incapable of changing. There is no live, per-week value for these fields to diverge from — unlike `loadingRole`, which was checked for equality against the one field CP.2 exists specifically to adapt. **This is not the same failure class, proven by exhaustive enumeration of every real CP.2 mutation path, not by assumption.**
- Concretely: `INTENDED heavy → CP.2 FINAL moderate` changes nothing about which `MovementFunction`/`FunctionalModality` a slot carries — the rep/distance target remains exactly as valid after the adaptation as before it, because the target's own inputs were never touched. Structural targets are correctly, provably orthogonal to CP.2's stimulus adaptations.

**Materializer ownership is explicitly rejected for FF.P1**: resolving reps/distance downstream of FINAL would gain nothing (FINAL's `loading`/`intensity`/`systemicDemand`/`skillDemand` are irrelevant inputs to this rule) while adding an unnecessary dependency on materialization-time state, contrary to the "smallest correct seam" discipline this whole document series has followed throughout (CP.1/CP.2/FF.L1 each resolved things at the narrowest seam that actually needed them).

### I. Variance/substitution/readiness safety

**Substitution — proven safe, answer is (A) preserves the target.** `SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly` mutates exactly `movement.exercise`/`.substitutionUsed`/`.substitutionReason` — confirmed by direct read, it never touches `reps`/`distanceMeters`/`calories`/`loadKilograms`. Critically, `SubstitutionValidator.isValid` (the gate every real substitution must pass) requires the candidate to satisfy the SAME `allowedMovementFunctions`/`allowedModalities` the original slot was built from — so any valid substitute is *guaranteed*, by construction, to share the exact movement-function/modality classification the target was computed from. A target keyed on slot-level modality/function (not the originally-resolved `Exercise`) therefore remains coherent across any valid substitution — Toes-to-Bar substituted for Pull-up both satisfy `.gymnasticsPull`, so the 8-rep target (D) stays honest for either.

**Readiness — identical, confirmed by direct read.** `ReadinessAdaptationDecisionUseCase` calls the exact same `substituteThisSessionOnly` mechanism (`ReadinessAdaptationDecisionUseCase.swift:52,56`) — no separate reasoning needed.

**Variance — a real, disclosed future risk, correctly out of scope now.** `VarianceConstraints`'s currently-inactive `adjustForMovementFunction`/`adjustForModality` checks, if ever activated, WOULD change `Stimulus.movementFunctions`/`.movementModalityMix` at the per-week decision-engine level — the exact two fields FF.P1's target is keyed on. But the per-slot `ExerciseSlot.allowedMovementFunctions`/`.allowedModalities` (and therefore any per-slot target derived from them) is fixed ONCE at generation time and never revisited per week — the SAME "frozen at generation, never revisited" lifecycle `loadingRole` had. **This means IF variance is ever activated for movement function/modality, that future stage would face the exact CP.2R-class question again**, and would need to decide explicitly whether reactivating the template graph per week or some other mechanism is required — not resolved here, correctly flagged as unresolved (P), not fixed, since `VarianceConstraints` stays inactive and untouched in FF.P1.

### J. Validation additions

**None to Stage-E.** The rep/distance value is the pure, deterministic output of a table-driven function (D) with no external/runtime input — it cannot be malformed by athlete data, substitution, or CP.2 adaptation (H/I), so there is no runtime condition for Stage-E to guard against that a table-driven unit test (N) doesn't already prove exhaustively at compile-adjacent time. Adding a new `StimulusValidation` dimension for this would be validating a fact that can only ever be correct by construction — the "malformed prescriptions should not silently ship" concern is fully addressed by the deterministic-rule unit test instead, avoiding the overbuild the instruction explicitly warns against. `FunctionalFitnessStimulusValidator.swift` is not touched.

### K. Live UI changes — explicitly IN scope, per the correction in the user's own §25

Confirmed by direct read: `FunctionalFitnessExecutionView.swift`'s `header(_:)` (`:95-106`) is the ONE shared function every one of the 8 real format bodies renders through (mirroring FF.E1's own "one shared flow" precedent) — it currently builds `prescription.orderedMovements.compactMap { $0.exercise?.canonicalName }.joined(separator: " · ")`, i.e. exercise names only. `CompletedFunctionalFitnessDetail.swift` already has the exact, already-correct, already-tested string-building logic FF.P1 needs (`prescribedMovementLine(_:)`, `:119-125`: `"\(exercise) · \(reps) reps · ..."`, gated correctly on optionality). **The smallest change: share that exact formatting logic (promote it to a small shared presentation helper, or duplicate the ~5-line pure function) and call it from `header(_:)` instead of the bare `canonicalName` mapping.** Display-only — no editing, no new screen, no new state. **FF.P1's scope explicitly INCLUDES this change** — per the user's own locked expectation, populating the model alone without this would not make the workout "truly executable," and this document does not call FF.P1 complete without it.

### L. Adherence semantic impact

No FF.E1 code change. `PrescriptionAdherence`'s own doc-comment scope ("the dimensions TrainingOS actually prescribes today") mechanically widens once FF.P1 ships real reps/distance targets — an `asPrescribed` confirmation logged after FF.P1 now honestly covers movement/format/completion/reps/distance; a historical pre-FF.P1 `asPrescribed` record remains scoped to its own shallower, real prescription at the time, automatically and correctly, because `FunctionalFitnessPrescription`/`FunctionalFitnessMovement` are already immutable per-materialization snapshots (FF.L1's own precedent). No new adherence UI, no per-target confirmation, no performed-movement tracking — confirmed unnecessary, matching the user's own explicit instruction.

### M. Exact files/types to change

- `FunctionalFitnessProgramGenerator.swift` — `movementSlots(for:context:)` gains a `format: WorkoutFormat` parameter (needed for both B's format gate and D's round count), called from `generate` which already has `configuration.format` in scope; passes `reps:`/`distanceMeters:` into `FunctionalFitnessMovementSlotTemplate(...)` per C/D's rule, only when `format` is `.roundsForTime` (else neither field is set, matching today's exact behavior for every other format).
- New file, e.g. `Engines/FunctionalFitnessMovementTargetRule.swift` — a small, pure **DERIVED VALUE** function (`target(for movementFunction: MovementFunction, modality: FunctionalModality, rounds: Int) -> (reps: Int?, distanceMeters: Double?)` or equivalent), analogous in shape to `FunctionalFitnessStimulusValidator`'s own pure-function style. Not a persisted type, not a new engine, not a new entity.
- `FunctionalFitnessExecutionView.swift` — `header(_:)` updated to render the shared movement-target line (K).
- `CompletedFunctionalFitnessDetail.swift` — `prescribedMovementLine`'s formatting logic shared with the execution view (either promoted to `internal`/a shared helper, or duplicated as a tiny pure function) — no behavior change to the completed-detail view itself.
- `TrainingOS.xcodeproj/project.pbxproj` — register the one new file.
- New/updated tests (N).
- This design-doc file (already done, this section).
- **No change to**: `FunctionalFitnessMaterializer.swift`, `FunctionalFitnessDecisionEngine.swift`, `FunctionalFitnessStimulusValidator.swift`, `CrossModalityStimulusRepair.swift`, `CurrentWeekFunctionalFitnessProgrammingContext.swift`, `LongTermPlanner.swift`, `SubstituteFunctionalFitnessMovementUseCase.swift`, `ReadinessAdaptationDecisionUseCase.swift`, `FunctionalFitnessPerformedMovement.swift`, `FunctionalFitnessResult.swift`/`PrescriptionAdherence.swift`, `VarianceConstraints`, or any source-authority file.

### N. Required tests

**A.** Target-type classification: `.weightlifting`→reps, `.gymnastics`→reps, `.metabolicConditioning`→distance, table-driven across the real reachable set. **B.** Deterministic target values: `.squatLoaded`→12, `.gymnasticsPull`→8, `.monostructural`→200m, exact and repeatable. **C.** Total-dose sanity: 5 rounds × each per-round value equals the locked totals in D (40/60/1000). **D.** Real `muscleGainVariedMix` materialization produces non-nil reps/distance on all 3 real movements. **E.** Real `functionalFitnessFocusedMix` materialization — identical result (byte-identical Stage A/B/C output per the prior audit's own §5 finding). **F.** Non-empty CP.2 intended != final case (reuse CP.2R's own real fixture) — reps/distance targets identical before and after CP.2's repair fires, proving orthogonality empirically, not just by code-path argument. **G.** Bodyweight movement (Pull-up) gets the correct `.gymnasticsPull` reps value. **H.** Loaded movement (Wall Ball/Thruster) gets a reps value while `loadKilograms` stays `nil` — proving the two remain independently correct. **I.** Distance-native monostructural movement (Row Erg/Assault Bike/SkiErg — parameterize across all three real candidates) gets the 200m target uniformly. **J.** An unsupported/non-reachable `MovementFunction` (e.g. a test fixture using `.hingeLoaded`) degrades to no target, not a guessed value. **K.** An unsupported `WorkoutFormat` (e.g. `.amrap`) does not receive reps/distance — degrades truthfully. **L.** Live execution view renders "12 Wall Ball" / "200m Row Erg" style labels (ViewModel/view-level test, mirroring FF.E1's own testing approach for the shared finish flow). **M.** `CompletedFunctionalFitnessDetail` continues rendering correctly (regression, no behavior change). **N.** `PrescriptionAdherence`/FF.E1 semantics completely unchanged (regression). **O.** Substitution (`SubstituteFunctionalFitnessMovementUseCase`) and readiness behavior completely unchanged (regression). **P.** All CP.2R tests remain green (26/26). **Q.** All CP.2 tests remain green. **R.** All FF.L1 tests remain green. **S.** All FF.E1 tests remain green. **T.** Full suite, zero regressions.

### O. Concrete before/after workouts with total dose, plus absurdity stress test

1. **Real production triplet** (Wall Ball / Pull-up / Row Erg): Before *"5 Rounds For Time: Wall Ball, Pull-up, Row Erg."* After *"5 Rounds For Time: 12 Wall Ball, 8 Pull-ups, 200m Row Erg."* Total: **60 Wall Ball, 40 Pull-ups, 1000m Row.**
2. **Same slots, different resolved exercises** (Thruster / Toes-to-Bar / Assault Bike) — same modality/function per slot, targets IDENTICAL to #1 (proving the target is keyed on function/modality, not the specific `Exercise`): 60 reps, 40 reps, 1000m.
3. **Same slots, SkiErg resolved instead of Row/Bike**: target degrades identically — 200m/round, 1000m total, regardless of which real monostructural candidate Stage D happens to resolve.
4. **Bodyweight-only hypothetical** (gymnastics-only: Pull-up + Push-up + Toes-to-Bar — domain-valid per the prior audit's own Example 2, not real production today): Push-up isn't production-reachable (its `MovementFunction` is `.gymnasticsPush`, not one of the 3 real cases) — correctly receives **no FF.P1 target** (E/J), while Pull-up/Toes-to-Bar (both `.gymnasticsPull`) get 8 reps each. Honest, partial result: *"5 Rounds For Time: 8 Pull-ups, Push-up, 8 Toes-to-Bar."*
5. **Monostructural-only hypothetical** (all 3 slots `.metabolicConditioning`): every slot gets 200m/round — *"5 Rounds For Time: 200m Row, 200m Bike, 200m Ski"* — total 1000m each. Genuinely improved by choosing OPTION 2 over reps-only, which would have left this workout completely unimproved.
6. **CP.2-adapted case** (real Strength peak-week sibling, CP.2 repairs `.heavy → .moderate`, reusing CP.2R's own fixture): reps/distance targets on all 3 movements are **byte-identical** before and after the repair — 12/8/200m unchanged — empirically proving H's orthogonality claim, not just arguing it.
7. **Substitution case**: Pull-up (8-rep target) substituted this-session-only to Toes-to-Bar — target remains 8 reps, correctly, because both satisfy `.gymnasticsPull` (I).
8. **Absurdity — rejected (excessive reps)**: a hypothetical rule assigning `reps = 20` to `.gymnasticsPull` → 5×20 = **100 total pull-ups** — rejected as incoherent for a single "5 rounds for time" triplet block; the locked rule (8/round, 40 total) is the accepted, coherent alternative.
9. **Absurdity — rejected (trivial reps)**: a hypothetical `reps = 2` for `.squatLoaded` → 5×2 = **10 total** — rejected as too trivial to constitute real programmed work; the locked rule (12/round, 60 total) is accepted.
10. **Absurdity — rejected (excessive distance)**: a hypothetical `distanceMeters = 1000` PER ROUND for `.monostructural` → 5×1000 = **5000m total row** — rejected as grossly incoherent with the real `.medium` `targetDurationDomain` this Stimulus always carries; the locked rule (200m/round, 1000m total) is accepted as a real, achievable, medium-duration dose.
11. **Identical-targets-for-different-movements check**: since `.other`/`.trunk`-style functions (which a hypothetical Burpee/Sit-up pairing might carry) are not in the real reachable set (E), the rule naturally does NOT assign them identical (or any) targets — avoided structurally rather than solved by coincidence.

### P. Remaining unresolved decisions

- The exact numeric dose-class values in D (8/12/200m) are this document's proposal, not an authored, approved product decision — must be explicitly signed off before implementation, per CLAUDE.md rule 10.
- Whether calories should ever be added for erg-type monostructural equipment specifically (deferred, would need an equipment-aware branch this stage avoids).
- Whether/how a future `VarianceConstraints` activation for movement-function/modality rotation would need to regenerate or re-derive the per-slot target (flagged in I, not designed).
- Whether the dose-class table should ever become `AdaptationObjective`-aware (explicitly deferred per the user's own strong default — no evidence found that the same movement/format is currently incoherent without it).
- Whether `functionalFitnessFocusedMix` and supporting-FF-inside-`muscleGainVariedMix` should ever diverge in their structural targets — **locked NO for FF.P1**: both route through the byte-identical `functionalFitnessParameterCandidates` output (confirmed, prior audit §5), so sharing the same structural targets is a correct, deliberate simplification, not an oversight.
- The pre-existing, unrelated `targetDurationDomain`-vs-fixed-`capSeconds:nil` looseness (noted in passing, not a blocker: `estimatedDurationSeconds` returns `nil` for the real production format, so `matchesDuration` already short-circuits to `true` regardless of what CP.2's same-week nudge does to `targetDurationDomain` — an existing, inert looseness FF.P1 neither creates nor worsens).

### Q. Is FF.P1 safe to implement?

**YES**, once P's numeric dose-class values receive explicit product sign-off. No architectural blocker was found: ownership is proven (not assumed) safe against the exact failure class CP.2R just closed; substitution/readiness are proven safe; the live-UI change is small and reuses already-correct, already-tested formatting logic; no new persisted state, no Stage-E validation change, no touch to any closed stage's files or semantics. The only genuinely open item blocking a first line of code is the numeric rule itself (P's first bullet) — a deliberate, disclosed product decision this design lock proposes but does not unilaterally finalize, per the same discipline CP.1/CP.2/FF.L1/FF.E1/CP.2R have all followed throughout this series.

---

## FF.P1 Numeric Dose Lock

**Status: DESIGN/AUDIT ONLY. Nothing implemented, committed, or pushed.** Audits the ONE item the FF.P1 Design Lock left open — the exact numeric dose table — against the real `ExerciseCatalog`. Everything else in that section (scope, ownership, format gate, UI inclusion, no validation change, no `AdaptationObjective` awareness) is already approved and is not re-litigated here.

### A. Complete real candidate pool for each of the 3 functions

Eligibility is determined by the real, exhaustive rule in `SubstitutionValidator.isValid` (`ExerciseSubstitutionEngine.swift:29-42`): a candidate must have `functionalModality` set AND contained in the slot's single `allowedModalities` entry, AND `movementFunctions` intersecting the slot's single `allowedMovementFunctions` entry. Both dimensions are required — a candidate missing `functionalModality` entirely is excluded regardless of its `movementFunctions`. Applied to every real `ExerciseCatalog.swift` entry:

**`.squatLoaded` + `.weightlifting` slot** — real eligible pool = **{Back Squat, Wall Ball, Thruster}**:
- Back Squat: `movementFunctions: [.squatLoaded]`, `functionalModality: .weightlifting`, `equipment: "barbell"`
- Wall Ball: `movementFunctions: [.squatLoaded, .pressLoaded]`, `functionalModality: .weightlifting`, `equipment: "medicineBall"`
- Thruster: `movementFunctions: [.squatLoaded, .pressLoaded]`, `functionalModality: .weightlifting`, `equipment: "barbell"`
- (Front Squat, Bulgarian Split Squat, Leg Press all carry `.squatLoaded` but `functionalModality: nil` — **not eligible**, confirmed by direct read; they are Hypertrophy-catalog entries, never resolvable into an FF slot.)

**`.gymnasticsPull` + `.gymnastics` slot** — real eligible pool = **{Pull-up, Toes-to-Bar}**:
- Pull-up: `movementFunctions: [.gymnasticsPull, .verticalPullLoaded]`, `functionalModality: .gymnastics`, `equipment: "bodyweight"`
- Toes-to-Bar: `movementFunctions: [.gymnasticsPull, .trunk]`, `functionalModality: .gymnastics`, `equipment: "bodyweight"`
- (Push-up/Handstand Push-up are real `.gymnastics` candidates but carry `.gymnasticsPush`, not `.gymnasticsPull` — correctly excluded from this specific function's pool.)

**`.monostructural` + `.metabolicConditioning` slot** — real eligible pool = **{Easy Run (Zone 2), Track Interval Run, Assault Bike, Row Erg, SkiErg}**, all 5 real:
- Easy Run: `equipment: "none"`; Track Interval Run: `equipment: "none"`; Assault Bike: `equipment: "bike"`; Row Erg: `equipment: "rower"`; SkiErg: `equipment: "skiErg"` — all carry `movementFunctions: [.monostructural, .locomotion]`, `functionalModality: .metabolicConditioning`.

### B. Candidate-by-candidate stress test of 8/12/200

**`.gymnasticsPull` = 8 reps/round → 40 total:**
- Pull-up: 40 total pull-ups across a 5-round for-time triplet — a standard, common real CrossFit-style dose (comparable to well-known benchmark rep ranges for this movement in a metcon context). Coherent.
- Toes-to-Bar: the more demanding candidate (grip + core, per real practice) — 40 total T2B is on the higher-but-not-absurd end of real metcon programming (real benchmark workouts routinely program 8-15 T2B per round in triplets/couplets). Not obviously incoherent.

**`.squatLoaded` = 12 reps/round → 60 total:**
- Back Squat: 60 total loaded back squats in one for-time block. At a HEAVY/near-max load this would be incoherent — but FF.P1's own locked scope leaves `loadKilograms == nil` (numeric load explicitly deferred, athlete self-selects), which is the exact real-world CrossFit convention this rule relies on: a rep-only prescription with no numeric load is understood to mean "choose a weight that lets you complete this rep scheme for time," not "use your heaviest weight." At a self-scaled, metcon-appropriate load, 60 total reps is coherent.
- Wall Ball: lighter, more rep-tolerant per real practice (a well-known real benchmark workout uses considerably higher unbroken rep counts) — 60 total is comfortably coherent, arguably on the easy side, not incoherent in either direction.
- Thruster: the worst case — a combined squat-to-press movement, more systemically demanding per rep than a plain squat pattern at equivalent relative load. Real metcon programming for Thrusters spans from low reps at heavy prescribed loads (e.g. a well-known 21-15-9 benchmark) up through higher-rep sets at lighter self-scaled loads. **Because FF.P1 never prescribes a numeric load, the athlete scales load down for a 12-rep/round Thruster exactly as real practice already expects — the same self-scaling reasoning that saves Back Squat resolves Thruster too.** Not obviously incoherent once load is understood as self-selected.

**`.monostructural` = 200m/round → 1000m total:**
- Easy Run / Track Interval Run: 200m/round is a completely standard real metcon running distance. Coherent for both.
- Row Erg / SkiErg: both real Concept2-style ergometers display distance directly in meters as their primary, idiomatic unit — 200m/round, 1000m total is a standard, real, displayable prescription. Coherent for both.
- **Assault Bike: a real semantic problem, confirmed** — see C.

### C. Semantic issue with distance on a specific monostructural candidate, and resolution

**Assault Bike is a real, disclosed exception.** Unlike Row Erg/SkiErg (whose Concept2-style monitors treat meters as their primary, idiomatic readout) and Easy Run/Track Interval Run (meters/distance is the natural unit for running), an air/assault bike's overwhelmingly standard real-world CrossFit programming convention is **calories**, not meters — "200m Assault Bike" is technically representable in this domain but is not an idiomatic, well-formed prescription an athlete would recognize as normal programming, exactly the concern the instruction raises.

**Chosen resolution: (A)/(C) combined, using the existing `equipment` field only — no new metadata.** `Exercise.equipment` already carries a distinct, real string per candidate (`"bike"` vs. `"rower"`/`"skiErg"`/`"none"`) — this is not new metadata, it is the same field already read throughout this codebase. FF.P1's target rule should check `equipment == "bike"` specifically and assign **no target at all** for that one real candidate, while Row Erg/SkiErg/Easy Run/Track Interval Run all receive the 200m target normally. This is the smallest possible fix: one additional `else` branch keyed on already-existing data, not a new distance-vs-calorie decision, not new equipment classification work, and not silently switching to calories to "solve" the mismatch (explicitly forbidden). Truthful partial depth — Assault Bike shows only the exercise name with no target, exactly like every currently-non-reachable `MovementFunction` case already does under the approved Design Lock.

### D. Complete-workout dose assessment

The full generated triplet at the locked/corrected numbers: **60 total squatLoaded reps (self-scaled load) + 40 total gymnasticsPull reps (bodyweight) + 1000m monostructural (Row/Ski/Run; Assault Bike excluded)**, 5 rounds for time. Evaluated as one whole: this is a real, coherent, moderate-to-substantial CrossFit-style metcon triplet dose — comparable in shape and scale to real, well-known benchmark workout structures (a squat/press-pattern movement + a gymnastics pulling movement + a monostructural distance piece, at moderate-rep/moderate-distance volume). It is neither trivially short nor absurdly long for a single "5 rounds for time" block. No candidate combination produces an incoherent total once B/C's findings are applied.

### E. One rule for both real FF mix roles — explicit PRODUCT DECISION

**Confirmed, still holds with real numbers on the table: the same 8/12/200 baseline is locked as acceptable for BOTH supporting FF inside `muscleGainVariedMix` and `functionalFitnessFocusedMix`.** Neither mix's real `adaptationObjectives` (`[.workCapacity, .aerobicCapacity, .power]` vs. the 5-case GPP set) implies a *different* coherent baseline dose at this first, deliberately non-`AdaptationObjective`-aware stage — a moderate, generically "well-rounded metcon triplet" dose is a reasonable generic starting point for a supporting-variety role and a focused-GPP role alike. **PRODUCT DECISION, explicit**: FF.P1 ships one shared dose table for both real mixes; divergent, objective-aware dosing is deliberately deferred to a future stage, not attempted here.

### F. FINAL NUMERIC TABLE

| MovementFunction | Modality | Target | Per-round | Total @ 5 rounds |
|---|---|---|---|---|
| `.squatLoaded` | `.weightlifting` | reps | 12 | 60 |
| `.gymnasticsPull` | `.gymnastics` | reps | 8 | 40 |
| `.monostructural` | `.metabolicConditioning`, **`equipment != "bike"`** | distanceMeters | 200 | 1000 |
| `.monostructural` | `.metabolicConditioning`, **`equipment == "bike"` (Assault Bike)** | — | **no target** | **no target** |

The only change from the original proposal is the one narrow Assault Bike exclusion (C) — 8/12/200 themselves are otherwise unchanged and confirmed safe.

### G. One-sentence product rationale per number

- **12 reps/round (squatLoaded)**: a moderate, self-scaled-load metcon dose that stays coherent across the real candidate pool's full demand range (Wall Ball through Thruster) precisely because FF.P1 leaves load unprescribed, letting the athlete supply the missing variable real practice already expects them to supply.
- **8 reps/round (gymnasticsPull)**: a standard, real metcon rep count for bodyweight pulling work that remains coherent even against the pool's more demanding member (Toes-to-Bar), without being trivially easy for the less demanding one (Pull-up).
- **200m/round (monostructural, non-bike)**: the idiomatic, real, monitor-displayed distance unit shared honestly across every meter-native real candidate (Run ×2, Row, Ski) at a standard, recognizable metcon distance.
- **No target (Assault Bike)**: truthful partial depth is preferred over an idiomatically wrong unit or an invented calorie-conversion this stage has no honest basis for.

### H. Explicit safety statement

**FF.P1 NUMERIC DOSE RULE IS SAFE TO LOCK**, with the one disclosed, minimal correction in C/F (Assault Bike receives no target, using only the already-existing `equipment` field — no new metadata, no calorie substitution). 8 (gymnasticsPull) and 12 (squatLoaded) are confirmed safe against the real, complete candidate pool including their respective worst-case members, specifically because FF.P1's own already-locked scope leaves numeric load unprescribed. 200 (monostructural) is confirmed safe for 4 of 5 real candidates, with the 5th (Assault Bike) correctly excluded rather than forced.

---

## FF.P1 Implementation Closure — Structural Movement Targets

**Status: IMPLEMENTED (uncommitted).** Builds on CP.2 (`bca43e2ff47d21d8703275d06354af6a086f0d45`), FF.L1 (`ae5898c36cdb5617edf77f2ad68507149ea3e2ac`), FF.E1 (`a3c3d0b532a68878411a9383f1d154225bdc4fc4`), CP.2R (`2f02c603e7b5acc0a4e1ff86ab1239a848d54f7d`) — none modified.

**Ownership superseded.** The FF.P1 Design Lock section above (§H) locked GENERATOR ownership. This was superseded before implementation: the Numeric Dose Lock's Assault Bike exclusion depends on the ACTUAL RESOLVED `Exercise.equipment`, which is only known at Stage D (materialization time), not at generation time. Targets are therefore resolved in `FunctionalFitnessMaterializer.materializeWeek`, after `decideWithIntent` has produced FINAL and Stage D has resolved the real `Exercise` — never in `FunctionalFitnessProgramGenerator`, which is unmodified by this stage.

**One semantic source, reused by two callers.** `FunctionalFitnessMovementTargetRule.resolve(format:modality:movementFunctions:exercise:)` (`Engines/FunctionalFitnessMovementTargetRule.swift`, new) is the sole implementation of the locked numeric table. `FunctionalFitnessMaterializer` calls it once per slot, after Stage D; `SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly` calls the identical function again after a valid substitution, to keep the concrete target consistent with whichever `Exercise` is now actually attached — no second table exists anywhere.

**A real, pre-existing gap this stage closed as necessary infrastructure.** Before this stage, `FunctionalFitnessMaterializer` never set `FunctionalFitnessMovement.sourceExerciseSlot` — the field `SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly` requires to validate or apply any substitution at all. This meant the real readiness-adaptation substitution flow could not execute against any real generated (non-benchmark) Functional Fitness movement — it would throw `SubstitutionError.invalidForSlot` immediately, before ever reaching `SubstitutionValidator.isValid`. The materializer now sets `movement.sourceExerciseSlot = exerciseSlot`, mirroring `StrengthMaterializer`'s already-established, identical `prescription.sourceExerciseSlot = slot` pattern exactly — no new mechanism, no change to `SubstitutionValidator`, `allowedMovementFunctions`/`allowedModalities`, recommendation logic, or readiness policy. This was disclosed rather than silently done: it is the reason the Row/SkiErg/Run → Assault Bike substitution-staleness scenario is now actually reachable (and now correctly handled) in production, rather than remaining unreachable behind a separate, unrelated bug.

**Numeric load remains genuinely unspecified — never implicitly self-scaled.** Correcting language from the earlier design-lock rounds (whose own historical text is left unedited above, as the record of what was reviewed and locked at the time): `FunctionalFitnessMovementTargetRule` prescribes a repetition or distance COUNT only. It does not encode, and its own doc comment explicitly disclaims, any "choose a weight that lets you complete this" or other self-scaling semantic — TrainingOS has not defined one. A 12-rep Back Squat with no numeric load means exactly that: 12 repetitions prescribed, load genuinely unspecified.

**Assault Bike intentionally receives no target in FF.P1** — the one real monostructural candidate whose idiomatic real-world unit (calories) this stage does not attempt to prescribe; it shows only its exercise name, exactly as truthfully as every other currently-unprescribed case.

**Authored-vs-generated precedence.** `FunctionalFitnessMovementSlotTemplate.reps`/`.distanceMeters` are the reliable provenance signal: the generator never sets them for real generated content, so a nil template field means the movement's own current value (if any) is FF.P1-generated and safe to (re)compute; a non-nil template field means the value was explicitly authored (hand-authored/seed/benchmark content) and is never touched, at materialization time or at substitution time.

**Prescription completeness, not progression.** Nothing in this stage compares exposure across sessions, adjusts a target based on performance, or reads `AdaptationObjective`. The same shared dose table applies to every real FF component regardless of role (`muscleGainVariedMix`-supporting vs. `functionalFitnessFocusedMix`-primary) — a deliberate, disclosed simplification, not an oversight.

**Verification.** 21/21 new targeted tests pass; all 26 CP.2R tests, all CP.2 tests, all 8 FF.L1 tests, all 12 FF.E1 tests pass unchanged; **authoritative full-suite result (independently re-run at checkpoint): 1047 passed / 2 skipped / 0 failed**; clean `build-for-testing` and plain `build`; zero persistence warnings; zero diff in every source-authority file, `LongTermPlanner.swift`, `FunctionalFitnessDecisionEngine.swift`, `CrossModalityStimulusRepair.swift`, `AdaptationObjectiveStimulusMapping.swift`, `CurrentWeekFunctionalFitnessProgrammingContext.swift`, `SchedulingPipeline.swift`, and `FunctionalFitnessPerformedMovement.swift`; production `VarianceConstraints()` construction unchanged; exactly one `SchedulingPipeline.propose` call site. **Simulator status, recorded accurately:** build succeeded; install succeeded; interactive live launch was unavailable because this host reports iOS Simulator interaction as unsupported at its own rollout-flag level (`"iosSimulator":{"status":"unsupported","reason":"iOS Simulator is disabled by its rollout flag"}`), independent of this change — this is not a claim of a successful live interactive smoke test; the exact string-formatting logic the live header renders (`BlockPresentation.prescribedMovementLine`) is instead proven directly by automated test, matching the identical fallback FF.E1's own prior report already established for this same environment limitation.

---

## STOP

**Design / audit only for everything above the CP.2R Closure section (which reflects real, uncommitted implementation work), for the FF.P1 Design Lock and FF.P1 Numeric Dose Lock sections (design lock only, at the time they were written), and now IMPLEMENTED (uncommitted) for the FF.P1 Implementation Closure section above.** Stage CP.2 remains closed at `bca43e2ff47d21d8703275d06354af6a086f0d45`; Stage FF.L1 remains closed at `ae5898c36cdb5617edf77f2ad68507149ea3e2ac`; Stage FF.E1 remains closed at `a3c3d0b532a68878411a9383f1d154225bdc4fc4`; Stage CP.2R remains closed at `2f02c603e7b5acc0a4e1ff86ab1239a848d54f7d`. None of their closed semantics is modified. Nothing has been committed or pushed.
