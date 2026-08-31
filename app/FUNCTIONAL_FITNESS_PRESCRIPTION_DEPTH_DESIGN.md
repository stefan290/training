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

## STOP

**Design / audit only for everything above the CP.2R Closure section; that section reflects real, uncommitted implementation work — a narrow correctness repair, not a new design stage.** Stage CP.2 remains closed at `bca43e2ff47d21d8703275d06354af6a086f0d45`; Stage FF.L1 remains closed at `ae5898c36cdb5617edf77f2ad68507149ea3e2ac`; Stage FF.E1 remains closed at `a3c3d0b532a68878411a9383f1d154225bdc4fc4`. None of their closed semantics is modified. FF.P1 has not been started.
