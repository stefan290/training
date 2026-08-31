# Functional Fitness Execution Truth — Design / Audit

**Status: DESIGN / AUDIT ONLY. Nothing implemented, committed, or pushed.**

This document builds on two closed prerequisites: Stage CP.2 (`bca43e2ff47d21d8703275d06354af6a086f0d45`, cross-modality/same-week Concurrent Programming coordination) and Stage FF.L1 (`ae5898c36cdb5617edf77f2ad68507149ea3e2ac`, the INTENDED-vs-FINAL Stimulus foundation, recorded in `FUNCTIONAL_FITNESS_LONGITUDINAL_PROGRAMMING_DESIGN.md`). Neither is modified here. FF.L1 established the programming-side truth chain — CONFIGURED BASELINE → INTENT PHASE → INTENDED → CP.2 ADAPTATION → FINAL. This document investigates the missing third leg: **PERFORMED** — what the athlete actually did, and whether TrainingOS can currently tell the difference between "the athlete performed the FINAL prescription as written" and "the default value happens to say `.rx`."

Every claim below is grounded in a direct read of the real production code, not test fixtures, not the prior audits' own claims re-asserted without re-checking.

---

## 1. Real production execution path

Traced end to end from a materialized `FunctionalFitnessPrescription` through to a persisted result:

1. **Materialization** (`FunctionalFitnessMaterializer.materializeWeek`, unchanged by this audit) produces a `WorkoutBlock` with an attached `FunctionalFitnessPrescription` (post-FF.L1: `stimulus`=FINAL, `intendedStimulus`=INTENDED) and its ordered `FunctionalFitnessMovement`s (prescribed movements).
2. **Session execution UI** (`FunctionalFitnessExecutionView.swift`, 364 lines) renders one of 9 typed bodies per real `WorkoutFormat` case (`amrapBody`/`emomBody`/`runningClockBody`/`maxLoadBody`/`maxRepsBody`/`intervalsBody`). On `.task`, calls `CompleteBlockUseCase.start` and starts a real wall-clock `TimerState` (`UpdateBlockTimerUseCase.start`) for every format except `.maxLoad`.
3. **Athlete interaction during execution** — the ONLY values a real athlete can enter, confirmed by direct read of every body function:
   - **`+ ROUND` tap** (AMRAP, Rounds-For-Time) → `viewModel.incrementRound()`/`decrementRound()` — a plain in-memory `Int`, `roundsCompleted`. **PERFORMANCE. Not persisted until `finish()`. Origin: UI tap. Edited: UI tap. Future programming: not yet readable (see §16).**
   - **"Extra reps" stepper** (`partialRepsEntryView`) → `partialRepsEntry`, an in-memory `Int` folded into `scoreValue.roundsAndReps(rounds:partialReps:)` at Finish. **PERFORMANCE.**
   - **"Mark Minute Incomplete" button** (EMOM) → `viewModel.markMinuteIncomplete(asOf:)` → appends to `incompleteMinuteIndices: Set<Int>`. **PERFORMANCE — and a real, decisive finding: this value is captured in the ViewModel but is NEVER read anywhere inside `finish()` or persisted anywhere. It is dead UI state today** — the athlete can mark a minute incomplete and that fact is silently discarded at Finish.
   - **Load text field** (`.maxLoad` format) → `loadEntry: String` → `scoreValue.load(kilograms:)`. **PERFORMANCE.**
   - **Reps stepper** (`.maxReps` format) → `repsEntry: Int` → `scoreValue.repetitions(_:)`. **PERFORMANCE.**
   - **Finish tap timing** (all formats) → real wall-clock elapsed seconds via `WorkoutTimer.elapsedSeconds` → `scoreValue.time(seconds:)`. **AUTOMATICALLY OBSERVED, not user-entered — a real signal (§10).**
4. **`finish()`** (`FunctionalFitnessExecutionViewModel.swift:82-108`) constructs exactly one `FunctionalFitnessResult(scoreType: prescription.stimulus.scoreType, scoreValue:, scoreDirection:)` — **`resultContext` is never passed, so it silently defaults to `.rx`** (confirmed again directly, `FunctionalFitnessResult.swift:52`). Calls `LogFunctionalFitnessResultUseCase.logResult` → `RecordFunctionalFitnessResultUseCase.recordResult` (attaches the result, folds into `BenchmarkPerformanceProfile`/`PersonalRecord` bookkeeping only when `benchmark != nil` — **every real UI call site hardcodes `benchmark: nil`**, confirmed by exhaustive grep across `FunctionalFitnessExecutionView.swift` — benchmark tagging has no real UI path either, a related but out-of-scope finding). Then calls `CompleteBlockUseCase.complete(block, context: completionContext, ...)`, where `completionContext` (`.full`/`.partial`) is chosen by the VIEW's own logic (e.g. `timeCapped ? .partial : .full`) — **automatically derived from real timer state, never a separate user question.**
5. **No movement-level editing exists anywhere in the execution UI.** No substitution picker, no per-movement reps/load/exercise editor, no Rx/Scaled toggle. `FunctionalFitnessPerformedMovement.addPerformedMovement` is never called from any real code path (`grep` across `TrainingOS/` outside tests: zero real call sites) — confirmed, matching and extending the prior audit's finding.

**A separate, real substitution mechanism exists but is NOT athlete-initiated during execution:** `SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly` (Stage 8B) is real and wired, but its only real caller is `ReadinessAdaptationDecisionUseCase` (an automated readiness-adaptation flow, out of this audit's scope) — never the execution view. Critically, **it directly overwrites `FunctionalFitnessMovement.exercise` in place** and sets `movement.substitutionUsed = true`/`movement.substitutionReason` — this is a genuine architectural inconsistency with `FunctionalFitnessPerformedMovement`'s own doc comment, which insists "the original prescription is preserved exactly as prescribed... never overwriting it." Two different substitution mechanisms exist in this codebase with two different (and contradictory) preservation guarantees. This audit does not resolve that inconsistency (out of scope — it belongs to the readiness-adaptation flow, not execution truth) but flags it as a real fact any future execution-truth design must not silently paper over.

## 2. Complete result-model audit

| Field | Type | Classification | Real construction site | Real consumer |
|---|---|---|---|---|
| `FunctionalFitnessResult.workoutBlock` | `WorkoutBlock?` | DERIVED RESULT (relationship) | `attachFunctionalFitnessResult` | UI display, `Session`/`WorkoutBlock` graph |
| `.benchmarkPerformanceProfile` | `BenchmarkPerformanceProfile?` | BENCHMARK METADATA | `RecordFunctionalFitnessResultUseCase` (only if `benchmark != nil`) | Never populated in real production UI (§1) |
| `.benchmark` | `BenchmarkDefinition?` | BENCHMARK METADATA | same | same — always `nil` in real production today |
| `.scoreType` | `ScoreType` | PRESCRIPTION (copied from `prescription.stimulus.scoreType` at Finish) | `finish()` | `CompletedFunctionalFitnessDetail`, `ScoringEngine` (indirectly, via `scoreValue`) |
| `.scoreValue` | `ScoreValue` | PERFORMANCE | `finish()`, from real UI input/timer (§1) | `ScoringEngine.bestRecord`/`comparableValue`, UI display |
| `.scoreDirection` | `ScoreDirection` | DERIVED RESULT (deterministic function of `format`, `FunctionalFitnessScoring.scoreDirection`) | `finish()` | `ScoringEngine.mapToScoringDirection` |
| `.resultContext` | `ResultContext` | **Notionally USER-REPORTED CONTEXT — actually a hardcoded default, never real user-reported data today.** | Defaults `.rx` at `init`; never overridden | **`ScoringEngine.bestRecord`/`RecordFunctionalFitnessResultUseCase` — a REAL, ACTIVE consumer** (see the critical finding below) |
| `.completedAt` | `Date` | DERIVED RESULT (wall clock at construction) | `finish()` (implicit default `Date()`) | sort/window key everywhere |
| `.performedMovements` | `[FunctionalFitnessPerformedMovement]` | UNUSED / DEAD IN PRODUCTION | Never populated by any real call site | `CompletedFunctionalFitnessDetail`'s UI already renders this collection correctly — ready, but structurally always empty |
| `.personalRecord` | `PersonalRecord?` | DERIVED RESULT | `RecordFunctionalFitnessResultUseCase` (benchmark-gated) | UI display |
| `FunctionalFitnessPerformedMovement.prescribedMovement` | `FunctionalFitnessMovement?` | traceability pointer | never constructed in production | N/A |
| `.performedExercise`/`.performedReps`/`.performedCalories`/`.performedDistanceMeters`/`.performedLoadKilograms` | all optional | intended as PERFORMANCE | never constructed in production | UNUSED / DEAD IN PRODUCTION |

**Critical finding beyond the prior audit's own framing: `resultContext` is not merely unassigned — it is ALREADY a real, active input to `RecordFunctionalFitnessResultUseCase`'s Personal Record bucketing** (`ScoringEngine.bestRecord(among:context:repBand:)`, called with `context: result.resultContext`; "Rx and Scaled never compete for the same record" — `RecordFunctionalFitnessResultUseCase.swift:35-38`). This means **every real Functional Fitness Personal Record today is silently bucketed as an Rx record**, regardless of whether the athlete actually performed it as prescribed — a real, currently-live correctness gap in the PR system itself, not merely a future-progression blocker. This sharpens (rather than merely repeats) the prior audit's "Rx does not currently certify anything" finding: the false default isn't inert, it's already load-bearing for a real, currently-shipping feature.

## 3. Precise definition of "as prescribed"

Evaluated against every dimension the current domain actually represents (movement identity/variant, format, completion status — the only ones with real prescription-side data per §5) — explicitly excluding load/reps/distance/calories/duration/work-rest granularity, since **the domain does not currently prescribe real numeric values for any of these for a generated (non-benchmark) workout** (§5). "As prescribed" today can only honestly mean:

**PROGRAM COMPLETION** (already fully modeled, unrelated to this audit): `Session.status == .completed` / `WorkoutBlock.status == .completed` with `completionContext == .full` — the athlete did SOMETHING and the app considers the block/session finished. Already real, already correct as far as it goes (§12).

**PRESCRIPTION ADHERENCE** (does not yet exist as a real signal): whether the movements actually attempted, the format actually followed, and the completion actually achieved matched what the FINAL prescription specified. Given §5's finding that only exercise identity/movement-function/modality/format/rounds-target/duration-cap are real prescribed dimensions today (never numeric load/reps/calories/distance), **the only honest, currently-representable adherence claim is: "the prescribed movements/format were followed, with no substitution, to program completion" — not "the prescribed load/reps/distance/calories were met," because none of those are prescribed with enough precision to compare against.** A future richer prescription model could widen this; today's honest ceiling is movement-identity + format + completion-status adherence only.

**These are explicitly two different facts.** A Session/Block can be `.completed` (PROGRAM COMPLETION) while every single movement was substituted and every round was scaled down (PRESCRIPTION ADHERENCE = false) — the architecture already proves this distinction is real and necessary (§12's `CompleteSessionUseCase` finding).

## 4. Rx/Scaled vs. prescription-adherence recommendation

**Current notional meaning, audited precisely:** the domain's own doc comments imply Rx should mean "no substitutions, prescribed load/volume met" (borrowing CrossFit convention), but **nothing in the real code enforces, checks, or even asks about any of this** — it is a pure default. Does ANY deviation imply Scaled? Notionally yes (CrossFit convention), but operationally the app cannot currently detect a single deviation, so the question is moot for the current codebase.

**Distinctions worth making** (only those that would change future programming or history interpretation, per instruction): pre-planned scaling (chosen before starting, e.g. via a substitution UI that doesn't exist yet) vs. mid-workout change both collapse to the same fact for programming purposes — "the prescription as materialized was not what was performed" — the WHEN doesn't change what a future longitudinal check would do with it, so this distinction is **not** worth building. Equipment-substitution vs. ability-substitution matters for a future coaching-explanation UI but not for programming logic (either way, the FINAL prescription's specific movement-function/loading target wasn't met) — **not worth a separate field yet, revisit if a future stage needs to explain WHY, not just THAT.** Reduced-load/reduced-reps/reduced-distance/changed-movement/stopped-early are exactly the dimensions §5 shows the domain doesn't even prescribe precisely enough to detect deviation on — so a fine-grained enum here would be inventing precision the prescription side doesn't have. **The one distinction that DOES matter and IS representable today: did the athlete follow the FINAL prescription's movements/format to completion, or not** — a coarse binary-plus-unknown, not a rich taxonomy.

**Challenge accepted: Rx/Scaled is not the right TrainingOS-native concept.** Recommend a **PRESCRIPTION ADHERENCE** concept instead — `unknown` / `asPrescribed` / `modified` — three states, not two, because the current two-case `ResultContext` structurally cannot represent "we don't know" (every record defaults to one of the two real cases, which is exactly today's bug). Workout-specific scoring (`scoreValue`/`scoreType`/`scoreDirection`) stays completely separate, unchanged — this was never conflated with adherence in the first place (§2's audit confirms `scoreValue` and `resultContext` are already independent fields). Do not keep `ResultContext`/Rx/Scaled merely because the enum exists — Functional Fitness is TrainingOS-authored, and "Rx" is real evidence of nothing today; a fresh, honestly-3-valued concept is smaller and more truthful than patching CrossFit terminology to mean something it was never built to represent.

## 5. Prescription-capability matrix

| Dimension | Classification | Evidence |
|---|---|---|
| Exercise/movement identity | **FULLY PRESCRIBED** | Real `ExerciseSlot`-based resolution, same mechanism as every other modality |
| Movement variant (which specific pattern) | **FULLY PRESCRIBED** | `MovementFunction` assigned round-robin from `stimulus.movementFunctions`, real and deterministic |
| Reps | **NOT PRESCRIBED for generated content** (generator gap, not a domain-model limitation — `FunctionalFitnessMovement.reps` exists and IS populated by seed/benchmark data, e.g. `SeedScenarios.swift:318`, but `FunctionalFitnessProgramGenerator.movementSlots` — the ONLY real generation path — never sets it, confirmed by direct read: `FunctionalFitnessProgramGenerator.swift:110` constructs `FunctionalFitnessMovementSlotTemplate(loadingRole: stimulus.loading)` with every other field left at its `nil`/`0`/`[]` default) | direct code read |
| Load | **NOT PRESCRIBED for generated content** — same generator gap, confirmed independently by the prior audit (§8 of the Design Lock section) and re-confirmed here | direct code read |
| Distance | **NOT PRESCRIBED for generated content** — same gap | direct code read |
| Calories | **NOT PRESCRIBED for generated content** — same gap | direct code read |
| Rounds (target count) | **FULLY PRESCRIBED where the format carries it** — `WorkoutFormat.roundsForTime(rounds:, capSeconds:)`'s `rounds` is a real Int, and `Ladder`'s structure is real | `WorkoutFormat.swift` |
| Duration/time cap | **FULLY PRESCRIBED where the format carries it** — every format case with a cap (`amrap`, `forTime`, `chipper`, `ladder`, `roundsForTime`, `maxReps`) stores a real `capSeconds`/`Int?` | `WorkoutFormat.swift` |
| Work/rest structure | **FULLY PRESCRIBED where the format carries it** — `.emom(intervalSeconds:totalSeconds:)`, `.intervals(count:workSeconds:restSeconds:)` are real, concrete Ints | `WorkoutFormat.swift` |
| Movement variant loading intensity | **PARTIALLY PRESCRIBED** — `loadingRole: LoadingClassification?` (categorical) is real and set, but explicitly "informational... not a hard substitution filter," never a number | `FunctionalFitnessMovementSlotTemplate.swift:38-41` |
| Format itself | **FULLY PRESCRIBED, fixed at configuration time** | unchanged, confirmed by the prior audit |
| Substitutions (as materialized) | NOT APPLICABLE — a materialized movement either resolves to a real exercise or the block fails Stage-E validation; there is no "prescribed substitution," only resolved-vs-later-changed | direct code read |

**Execution truth cannot exceed prescription truth — the central constraint, now proven concretely, not asserted.** A future execution-truth model cannot honestly ask "did you meet the prescribed load/reps/distance/calories" for any generated (non-benchmark, non-seed) Functional Fitness workout, because none of those values are ever real prescriptions today. It CAN honestly ask about movement identity, format, rounds/duration targets, and completion status — because those ARE real.

## 6. Movement-level execution finding

`FunctionalFitnessPerformedMovement` is architecturally the correct shape (a sparse-delta record referencing `prescribedMovement`, matching the exact non-destructive-override pattern this codebase already uses elsewhere, e.g. `ExercisePrescription.substitutionUsed`/`substitutionReason`) — but its fields (`performedReps`/`performedCalories`/`performedDistanceMeters`/`performedLoadKilograms`) are precision this codebase's own prescription side doesn't yet produce for generated content (§5), so populating them today would be **recording performance against numbers that were never actually prescribed** — a comparison with nothing honest to compare against. It should be created **only when performance differs from prescription** (never for every movement — that would duplicate prescription data for no reason, exactly the anti-pattern the instruction warns against), and specifically:
- created when a movement substitution occurred (`performedExercise != prescribedMovement.exercise`) — this IS meaningful today, since movement identity IS a real prescription (§5);
- NOT created to record a numeric performed value the prescription side has no real target for (reps/load/distance/calories) — that would be **fabricating precision on the performance side to compensate for its absence on the prescription side**, which is backwards.

## 7. Sparse-delta feasibility

**Confirmed feasible and historically truthful, WITH the §5 constraint respected.** "No performed override = performed as prescribed for that dimension" is honest only for dimensions that ARE really prescribed (movement identity, format, rounds/duration targets) — applying that same "no override = as prescribed" inference to reps/load/distance/calories would be **dishonest**, since there is no real prescribed value to have been "as" in the first place. The sparse-delta model must therefore be scoped explicitly to the dimensions §5 classifies as FULLY/PARTIALLY PRESCRIBED, never silently extended to NOT PRESCRIBED dimensions. This remains historically truthful as prescription models evolve, precisely because it never asserts more precision than the prescription side had at materialization time — a future stage that adds real numeric prescriptions would then, and only then, have real numeric performed values to sparsely override against.

## 8. Automatic vs. manual evidence matrix

| Signal | Classification | Evidence |
|---|---|---|
| Timer completion / elapsed time | AUTOMATICALLY OBSERVED | real `WorkoutTimer.elapsedSeconds`, wall-clock-derived, `finish()`'s own `scoreValue.time` |
| Rounds count | EXPLICITLY USER CONFIRMED (a tap per round, not automatic) | `+ ROUND` button |
| Score (final value) | EXPLICITLY USER CONFIRMED / entered at Finish | every format's own entry mechanism (§1) |
| Movement substitution | **UNKNOWN today** — the real mechanism (`SubstituteFunctionalFitnessMovementUseCase`) exists but is never invoked from execution UI (§1) | confirmed absent from the athlete-facing flow |
| Load/rep/distance edits during execution | **DOES NOT EXIST** — no UI surfaces this at all | confirmed absent |
| Early termination / time cap | AUTOMATICALLY OBSERVED (the VIEW itself computes `timeCapped`/derives `.partial` vs `.full`) | `FunctionalFitnessExecutionView.swift`'s own `timeCapped` logic |
| "Mark Minute Incomplete" (EMOM) | EXPLICITLY USER CONFIRMED, but **UNKNOWN in effect** — captured, never persisted (§1's dead-state finding) | direct code read |
| Session-level skip/miss/abandon | EXPLICITLY USER CONFIRMED (`ChangeSessionStatusUseCase`) or DERIVED (never-attempted sessions) | `ChangeSessionStatusUseCase.swift` |

No Apple Watch/HealthKit signal is invented anywhere in this matrix — confirmed none of the real FF execution code reads any HealthKit API (out of scope per CLAUDE.md rule 11/13 and the instruction).

## 9. scoreValue finding

Real `ScoreType`/`ScoreValue` cases, each tied to real `WorkoutFormat`s via `FunctionalFitnessScoring.scoreDirection` (a pure, deterministic, format-to-direction mapping, `FunctionalFitnessScoring.swift`): `.amrap`/`.emom`/`.maxLoad`/`.maxReps`/`.intervals` → `.higherIsBetter`; `.forTime`/`.chipper`/`.ladder`/`.roundsForTime` → `.lowerIsBetter`. `scoreValue` proves exactly one number (or pair, for `.roundsAndReps`) the athlete produced under the FINAL prescription's structural constraints (format/cap). **It does NOT prove**: that the prescribed movements were used unmodified (no substitution check anywhere in the scoring path), that any particular load/rep/distance target was met (none exist to compare against, §5), or that the result is comparable to a DIFFERENT week's score unless the underlying `Stimulus`+`format` shape is provably the same (the stimulus-vs-workout-identity gap the prior audit already found, unresolved here, cited not re-litigated). **It CAN, once the workout-identity gap is closed (a separate, already-flagged prerequisite), support a genuinely comparable "did output improve" signal for a repeated, identically-shaped workout** — but that is future work, not something this audit builds. Scores are comparable across sessions ONLY when format AND scoreType match exactly — comparing an AMRAP score to a For-Time score is meaningless by construction (`ScoreValue`'s own typed-union shape already prevents this at the type level, a real existing safeguard). **"Better score" is never conflated with "better adaptation" anywhere in this design** — a higher AMRAP round count could reflect an easier stimulus, not fitness improvement, without a stimulus-comparability check first.

## 10. Completion-status finding

Confirmed by direct read of `CompleteSessionUseCase.complete` (`:29-37`): **every remaining `.pending`/`.active` block is forcibly marked `.skipped` and the Session is unconditionally marked `.completed`** the moment a "Finish Session" action fires — this is real, existing, already-shipped behavior, not a hypothetical risk. **`Session.status == .completed` already, structurally, does NOT imply every prescribed block was performed** — the architecture has already solved half of the exact problem this section asks about, for Session-level completion. `SessionCompletionContext` (`.full`/`.partial`) is the existing, real signal distinguishing these two cases at the session level; `BlockCompletionContext` (`.full`/`.partial`) is the equivalent at the block level, already fed into `finish()` by the view's own real-timer-derived logic (§1). **A genuinely close, already-established precedent for the PERFORMED-vs-INTENDED epistemic discipline this whole audit is asking for already exists elsewhere in this exact codebase**: `CompleteSessionUseCase.progressionPreview` explicitly treats a readiness-adapted completed result as "NEUTRAL evidence about the unperformed original prescription — never a failed attempt at it, and never proof the adapted number should become the new anchor" (`CompleteSessionUseCase.swift:125-144`) — the identical INTENDED-vs-adapted-vs-PERFORMED reasoning this document proposes for Functional Fitness, already proven correct and shipped for Hypertrophy. Session status alone (`.completed`/`.skipped`/`.missed`/`.abandoned` — confirmed the real, `Codable` enum, `Enums.swift:108-115`) must never be read as "completed prescription as written," and nothing in the real codebase currently makes that mistake for Session-level status; the risk is specifically that a FUTURE FF progression stage might make exactly this mistake at the `FunctionalFitnessResult`/`resultContext` level if the adherence gap isn't closed first.

**One real, minor finding: `SessionStatus.abandoned` appears to be a dead case** — confirmed by exhaustive grep, no real code path ever assigns `session.status = .abandoned` (the only real `.abandoned` assignment found anywhere is `TrainingPhase.status = .abandoned`, an entirely different enum/entity). Out of scope to fix here, noted for completeness.

## 11. Scaling vs. substitution finding

The domain does not yet distinguish these for Functional Fitness in any way that matters for future programming: **substitution (replacing a movement)** is the only one of the two the domain can currently represent at all (via `FunctionalFitnessMovement.substitutionUsed`/`.substitutionReason`, real fields, real — if narrowly-wired — mechanism). **Scaling (changing difficulty while preserving intended movement/stimulus)** has no representable dimension today, because §5 already proved there is no real prescribed load/rep/distance/calorie target to scale FROM for generated content — "scaling" a value that was never prescribed numerically is not a representable fact yet. The locked principle "scaling should preserve stimulus" remains correct and untouched, but it is **not safe to assume every substitution preserves stimulus** (a movement-function-changing substitution could easily NOT preserve the intended stimulus) — this audit does not resolve that tension, only names it accurately: substitution-with-preserved-movement-function vs. substitution-that-changes-movement-function is the one distinction future programming would actually need, and it is derivable today (compare `performedExercise.movementFunctions` against `prescribedMovement.exercise.movementFunctions`, when/if performed movements are ever populated) — not a new field, a derived comparison.

## 12. INTENDED / FINAL / PERFORMED contract

Locked exactly as specified: **INTENDED** = Functional Fitness's own programming intent, pre-CP.2-adaptation (FF.L1, persisted `intendedStimulus`). **FINAL** = the TrainingOS prescription actually issued after CP.2 orchestration (FF.L1, persisted `stimulus`). **PERFORMED** = what the athlete actually did/confirmed (this document's new concept — NOT YET IMPLEMENTED). None may overwrite another: a future adherence/performed-truth field must never retroactively imply anything about INTENDED (mirroring FF.L1's own "never reconstruct intended from what happened downstream" discipline) and must never be conflated with FINAL (the prescription) either — `resultContext`/whatever adherence concept replaces it stays a property of the RESULT, not the PRESCRIPTION, exactly as the current (if unpopulated) domain model already separates them.

## 13. Historical immutability model

Stress-tested against a 2026 workout opened in 2028: **must persist** — whether the athlete confirmed adherence (the new 3-state concept, §4) at the time, since (mirroring FF.L1's own §5 proof) reconstructing "did they follow it" from anything else later would require re-deriving a fact only the athlete's own contemporaneous input could establish — no algorithm change could ever honestly reconstruct this. **Can remain derived**: `scoreValue`/`scoreDirection`/`completionContext` comparisons (pure functions of already-persisted data, never need re-running "current" logic against different meaning); which movements were substituted, IF `FunctionalFitnessPerformedMovement` is only ever populated at the moment of substitution (a real snapshot, never inferred later). **Prefer sparse persisted execution deltas**: only the adherence state itself (§4's 3-value concept) and any real substitution/performed-movement record are genuinely new persisted facts; everything else this document discusses (score comparisons, format/scoreType agreement) is already derivable from existing persisted fields.

## 14. Legacy-data semantics

Every `FunctionalFitnessResult` persisted before this stage carries `resultContext == .rx` by construction default, **indistinguishable from a genuinely user-confirmed Rx record** — confirmed, there is no provenance/version field anywhere on `FunctionalFitnessResult` today. A future adherence field must therefore default legacy records to **`unknown`**, never `asPrescribed` — mirroring FF.L1's own exact legacy-`intendedStimulus == nil` precedent (this document's `unknown` is the FF-execution-truth equivalent of that same honest-uncertainty pattern). No destructive migration; the existing `resultContext` field can either be reinterpreted going forward (with legacy values read as `unknown` regardless of their stored `.rx`/`.scaled` value) or a new, separate additive field can be introduced alongside it — an implementation-time choice, not resolved here, but either way **no historical record may be silently upgraded from "default value" to "confirmed evidence."**

## 15. Future-performance-evidence matrix

| Evidence | Classification |
|---|---|
| Confirmed adherence to FINAL prescription (movement/format/completion only, per §3/§5) | USEFUL FOR BOTH |
| "Modified" adherence state (any deviation, unspecified) | USEFUL FOR HISTORY ONLY until a specific future check needs to distinguish WHY |
| Movement substitution (which exercise, whether movement-function-preserving) | USEFUL FOR BOTH — history (what actually happened) and future programming (pattern-preserving vs. not, §11) |
| Performed numeric load/reps/distance/calories | **NOT RELIABLE ENOUGH** — nothing real to compare against for generated content (§5); would need the prescription-side gap closed first |
| `scoreValue`/`scoreDirection` | USEFUL FOR BOTH, but only once workout-identity (a separate, already-flagged prerequisite) makes cross-session comparison honest |
| `completionContext`/time-cap result | USEFUL FOR BOTH — already real, already correctly modeled |

## 16. Real workout walkthroughs

Using the real `muscleGainVariedMix` FF component (supporting, `[.workCapacity, .aerobicCapacity, .power]`) and its real generated shape (per §5: movement identity + movement function + modality + `loadingRole` categorical only; no real numeric reps/load/distance/calories):

**A. Exactly as prescribed.** FINAL: e.g. a `.roundsForTime(rounds: 5, capSeconds: nil)` with 3 movement slots (weightlifting/gymnastics/metcon, per the real fixed baseline). UI: athlete taps `+ ROUND` 5 times, taps Finish, `scoreValue = .time`. Persisted: `resultContext` defaults `.rx` (accidentally "correct" here, but not because anything verified it). Adherence state (if it existed): would honestly read `asPrescribed` for movement/format (nothing suggests otherwise), but the app cannot currently confirm this — it can only fail to detect a deviation, which is not the same as confirming adherence.

**B. Athlete reduces load.** Since load is never prescribed numerically (§5), "reducing load" has **no representable prescription to compare against** — the athlete simply performs the workout at whatever load they choose, and nothing in the current or proposed model can call this a "deviation," because there was no numeric target. This walkthrough itself proves §5's constraint concretely: this scenario is currently unanswerable, not merely unimplemented.

**C. Athlete substitutes one movement.** Real mechanism exists (`SubstituteFunctionalFitnessMovementUseCase`) but is not athlete-invocable during execution today (§1) — if it were wired to a UI, `movement.exercise` would change in place and `substitutionUsed = true` would be set on the PRESCRIBED movement itself (overwriting, not sparse-delta — the §1 inconsistency). A future execution-truth design should instead route this through a genuine `FunctionalFitnessPerformedMovement` sparse override, preserving `prescribedMovement` unmutated. Persisted (proposed): one `FunctionalFitnessPerformedMovement` row, `performedExercise` set, `prescribedMovement` unchanged. Adherence state: `modified`. Future programming may truthfully infer: this component's movement-function coverage that day differed from FINAL — useful for future exposure-history purposes, not for any numeric progression (none exists to progress).

**D. Athlete reduces reps.** Same as B — reps are never prescribed numerically for generated content. Unanswerable today, for the identical structural reason.

**E. Athlete hits a time cap.** Already fully real and correct: the view's own `timeCapped` computation drives `completionContext: .partial`, persisted on `WorkoutBlock.completionContext`. Adherence state (proposed): format/movements followed, but completion was partial — a real, honestly-representable combination distinct from "modified" (the movements/format WERE followed; only the volume of work completed was less, which is a completion-status fact, not an adherence-to-format fact).

**F. Athlete abandons the workout.** Two real paths: `CompleteBlockUseCase.skip` (block never attempted at all — real, wired from a generic placeholder view) or `ChangeSessionStatusUseCase` at the session level (`.missed`/`.skipped`). No `FunctionalFitnessResult` is ever created in this case — there is nothing to assign an adherence state to, correctly (you cannot rate adherence for a workout that was never attempted).

**G. Athlete completes a workout where no numeric load was ever prescribed.** This IS every real generated Functional Fitness workout today (§5) — not a special case, the default case. Future programming may truthfully infer, from this walkthrough set as a whole: movement-identity/format/completion-status adherence, and nothing about load/rep/distance/calorie adherence, for any generated workout, until the prescription side is deepened first (out of this document's scope, named as a real prerequisite).

## 17. Recommended execution granularity

**HYBRID / SPARSE OVERRIDES, scoped narrowly to WORKOUT-LEVEL adherence plus MOVEMENT-LEVEL substitution only** — not set/round-level. Justified directly by §5: since no real numeric prescription exists below the movement-identity/format level for generated content, a set/round-level granular truth model would be recording precision the prescription side cannot even define a target for. Workout-level adherence (the 3-state concept, §4) answers "did the athlete follow this workout as written," and movement-level substitution (sparse, only on deviation) answers "which specific movement, if any, differed" — together this is enough to program the next workout honestly, without building a forensic, set-by-set CrossFit-judging system the product has never asked for.

## 18. Smallest next implementation stage

**Recommend (A) Adherence truth only** — not (B) or (C). Reasoning, directly from §5/§6/§16's walkthroughs: movement-level sparse overrides (§7) are only meaningful for substitution, which requires a UI surface that doesn't exist yet (a real, separate, larger piece of scope — a substitution picker during live execution) and is not itself blocking the core truthfulness fix. **(A) alone — replacing the false default `resultContext`/Rx-Scaled assumption with an honest `unknown`/`asPrescribed`/`modified` 3-state concept, populated by the smallest possible UI change (one optional confirmation, never a mandatory questionnaire, per the core product principle) — is the smallest stage that turns current false data into truthful data, useful even before movement-level substitution or numeric-prescription-depth work exists.** It directly fixes the real, currently-live PR-bucketing correctness gap found in §2. (B)/(C) remain real future work, sequenced after (A), not blocked by needing to happen simultaneously.

**Minimum-friction UX for (A), designed per the core principle:** on Finish, if the athlete has done nothing during execution to suggest a deviation (no substitution invoked, no explicit "something changed" action), the app should **not** silently assume `asPrescribed` — per the explicit invariant in the instruction, lack of edits is not automatically confirmation, because (per §1) there is currently no UI ability to EDIT anything mid-workout that would prove adherence either way. The lowest-friction HONEST design is therefore: a single, optional, skippable prompt at Finish — **"Followed as prescribed?" [Yes] [No, something changed]** — defaulting to `unknown` if dismissed/ignored, `asPrescribed` only on explicit "Yes," `modified` only on explicit "No." This is one tap for the common case (Yes), never a questionnaire, and never fabricates confirmation from silence.

## 19. Exact domain types/files that stage would affect

- New (or repurposed) field: an adherence concept on `FunctionalFitnessResult` — either reinterpret `resultContext` (keep the `@Model` field, change its case set from `rx`/`scaled` to `unknown`/`asPrescribed`/`modified`, with legacy records read as `unknown` per §14) or add a new field alongside it — implementation-time choice, but NOT both a legacy-shaped and a new-shaped field coexisting with overlapping meaning.
- `FunctionalFitnessExecutionViewModel.finish(...)` — accept the new adherence value as a parameter, pass it into the `FunctionalFitnessResult` initializer.
- `FunctionalFitnessExecutionView.swift` — add the single optional Finish-time prompt (§18).
- `CompletedFunctionalFitnessDetail.swift` — update `resultContextLabel`/display to reflect the new 3-state concept honestly (including an explicit "Unknown" display for legacy/skipped-prompt records, never hidden or defaulted to a false-positive label).
- `RecordFunctionalFitnessResultUseCase`/`ScoringEngine.bestRecord` — decide (a genuinely unresolved product decision, §23) whether PR bucketing should require `asPrescribed` specifically, treat `unknown` as its own third bucket, or something else — currently silently treats everything as one Rx bucket, which is the real bug this stage fixes at the root.
- No change to `FunctionalFitnessPerformedMovement`, `SubstituteFunctionalFitnessMovementUseCase`, `FunctionalFitnessMovement`, `LongTermPlanner`, CP.2's own files, FF.L1's own files, or any source-authority file.

## 20. Exact UX changes that stage would require

One new, optional, two-button prompt at Finish ("Followed as prescribed? [Yes] / [No, something changed]"), dismissible with no penalty (defaults to `unknown`, never blocks Finish from completing). `CompletedFunctionalFitnessDetail`'s existing Rx/Scaled label becomes a 3-state adherence label. No new screen, no movement editor, no substitution picker — those remain future scope (§18).

## 21. Required tests

Persistence round-trip of the new adherence value (all 3 states); legacy-record read test (an old-shaped `FunctionalFitnessResult` reads as `unknown`, never `asPrescribed`); a test proving `finish()` defaults to `unknown` when the prompt is dismissed/never answered (never silently `asPrescribed`); a test proving an explicit "Yes" produces `asPrescribed` and an explicit "No" produces `modified`; a `ScoringEngine.bestRecord`/PR-bucketing regression test confirming the bucketing decision made in §19's open item behaves as specified once decided; a UI-level test (or at minimum a ViewModel-level test) confirming the prompt never blocks Finish and never crashes when dismissed; full existing suite unchanged (this stage adds a field/parameter, it must not alter any FF.L1/CP.2/CP.1 test's existing assertions).

## 22. Do not expand scope — confirmed

None of the following is required by any current architectural fact uncovered in this audit: longitudinal progression (still blocked on this stage existing first, per the original longitudinal audit's own D+C sequencing — not required BY this stage); `VarianceConstraints` activation (unrelated); benchmark retesting (§16/§1 confirm `BenchmarkDefinition`'s identity model is untouched and unnecessary for this stage); readiness integration (unrelated, though §10 notes the codebase's OWN readiness-adaptation code already proves the exact epistemic pattern this stage borrows — a precedent, not a dependency); equipment/environment (unrelated); `StartPhaseUseCase` CP.2 parity (unrelated, different subsystem); aggregate interference (unrelated); Apple Watch execution redesign (no HealthKit/Watch code exists in the real FF execution path today, confirmed by grep — nothing to redesign); HealthKit-based FF performance inference (same). **Nothing in this audit found a current architectural fact that would force any of these into scope.**

## 23. Genuinely unresolved product decisions

- Whether `ResultContext` is reinterpreted in place or replaced by a new field alongside it (implementation-time choice, §19).
- Whether PR bucketing (`ScoringEngine.bestRecord`) should require `asPrescribed` specifically to count as a competing record, treat `unknown` as its own third bucket, or merge `unknown`/`modified` for bucketing purposes while keeping them distinct for display — a real product decision, not decided here.
- Whether the Finish-time prompt should ever be skippable-by-setting ("always assume Yes for this athlete") — a personalization question out of this audit's scope.
- Whether/when movement-level substitution UI (§18's deferred (B)/(C)) should be built, and whether it should reuse `SubstituteFunctionalFitnessMovementUseCase`'s existing (overwrite-in-place) mechanism or require fixing the §1-identified inconsistency with `FunctionalFitnessPerformedMovement`'s own non-destructive design first.
- Whether the `SessionStatus.abandoned` dead-case finding (§10) warrants its own small fix — out of this audit's scope, named for completeness only.
- The prescription-depth gap itself (§5: no real numeric load/reps/distance/calories for generated content) remains the deeper, larger prerequisite this entire document's B/C-scenario walkthroughs (§16 B/D) prove is unanswerable today — not designed or scoped here, but now documented with concrete proof rather than assumption.

---

## Design Lock — Stage FF.E1: Prescription Adherence Truth

**Status: DESIGN LOCK / AUDIT ONLY. Nothing implemented, committed, or pushed.** Narrows the prior audit's proposed direction per three locked corrections: do not reinterpret `ResultContext`; `unknown` is not a normal skippable Finish choice; PR correctness is explicitly in scope. Answers only A-I, per instruction.

### A. Exact persisted shape of `PrescriptionAdherence`

A new, genuinely separate type, not a repurposing of `ResultContext`:

```swift
enum PrescriptionAdherence: String, Codable, CaseIterable {
    case unknown
    case asPrescribed
    case modified
}
```

Lives as a new field directly on `FunctionalFitnessResult`: `var adherence: PrescriptionAdherence = .unknown`. Non-optional with a default — SwiftData's lightweight migration handles an additive non-optional field with a default value the same way FF.L1's own `intendedStimulus: Stimulus?` was added (confirmed precedent: this codebase already has one FF.L1-shipped additive-field migration to point to). A default `.unknown` rather than an `Optional` is preferred here specifically because the domain already has a real "don't know" case as a first-class enum value — unlike `intendedStimulus` (where `nil` genuinely meant "no fact exists yet"), here `.unknown` IS the fact for legacy rows, so a plain default-valued field is smaller than introducing an `Optional<PrescriptionAdherence>` with an extra un-needed nil layer.

### B. Legacy migration semantics

Every `FunctionalFitnessResult` row created before this field existed reads `adherence == .unknown` automatically, via the field's own default value at schema-migration time (SwiftData populates additive fields with their declared default for pre-existing rows — no custom migration code required, matching FF.L1's own zero-custom-migration precedent). No destructive migration: `resultContext` is untouched, still readable, still whatever it was. No inference is performed — a legacy `resultContext == .rx` row is NOT read as `adherence == .asPrescribed`; it simply has no adherence fact at all (`.unknown`), for the same reason FF.L1 refused to reconstruct `intendedStimulus` for legacy prescriptions: the historical fact was never actually recorded, and inventing one now would be dishonest evidence.

### C. Exact finish UX / transaction ordering

**Confirm-then-persist is correct, and requires no new safety mechanism — it exactly mirrors the transaction shape the real code already uses today.** Traced precisely: `FunctionalFitnessExecutionViewModel.finish(scoreValue:completionContext:benchmark:modelContext:)` (`FunctionalFitnessExecutionViewModel.swift:81-108`) is a single synchronous function, called from a single button-tap action in the View, which constructs `FunctionalFitnessResult` and saves it (`LogFunctionalFitnessResultUseCase.logResult` calls `modelContext.save()` at line 20 of that file) all inside one call — nothing is persisted before this call fires, by design (the ViewModel's own doc comment: "the whole result is logged atomically at Finish," no live per-round persistence). Every real Finish button call site in `FunctionalFitnessExecutionView.swift` already computes at least one derived value (e.g. `completionContext: timeCapped ? .partial : .full`) BEFORE calling `finish(...)`. The identical pattern extends cleanly: the View shows the tiny "As prescribed / Modified" confirmation first, and only calls `finish(..., adherence: confirmedValue, ...)` once the athlete answers — `adherence` becomes one more parameter alongside `completionContext`/`benchmark`, threaded into the SAME already-atomic save, never a second write. If the app backgrounds or is killed while the confirmation is showing, nothing is lost beyond what is already true today if the athlete backgrounds before tapping Finish at all (an already-accepted, unchanged risk — in-progress round counts/timer state are governed separately by the existing persisted-timer-state discipline, untouched by this stage). No two-step "persist unknown, then update" flow is needed; it would only be necessary if `finish()`'s save could not be deferred behind one more piece of already-available input, which it can, since it already defers behind `completionContext`.

### D. All `ResultContext` consumers, classified

Exhaustive grep across `TrainingOS/` (non-test) for `resultContext`/`ResultContext` found it used far more broadly than FF alone — **`ResultContext` is a cross-modality shared enum**, also used by `WorkoutResult` (Strength), `IntervalResult`, `SteadyStateResult`, and `PersonalRecord.context` generally — this is a real fact this design lock surfaces beyond the prior audit's FF-only framing:

- `FunctionalFitnessResult.resultContext` — **UNRELATED TO ADHERENCE going forward, KEEP USING RESULTCONTEXT TEMPORARILY as an inert legacy field.** Not removed (still-readable field with a real, if uninformative, stored value), not migrated (its 2-case shape cannot honestly hold `PrescriptionAdherence`'s 3 states), simply no longer consulted for adherence meaning by any FF.E1-era code.
- `RecordFunctionalFitnessResultUseCase.swift:38,46` (`ScoringEngine.bestRecord`/`PersonalRecord(context:)`) — **MIGRATE TO PRESCRIPTIONADHERENCE for FF specifically.** This is the one real, FF-specific consumer that must change (see E).
- `CompletedFunctionalFitnessDetail.swift:57,127` (`resultContextLabel`) — **MIGRATE TO PRESCRIPTIONADHERENCE.** Replace the "Rx"/"Scaled" label with an adherence label ("As prescribed" / "Modified" / no label or a neutral "—" for `unknown`).
- `SeedScenarios.swift:331` — **UNRELATED, demo/seed data only**, not a real production path; may optionally also set the new field for demo fidelity, not required.
- Every other real consumer found (`WorkoutResult`/`IntervalResult`/`SteadyStateResult`/`LogSetUseCase`/`LogIntervalRepUseCase`/`RecordSetResultUseCase`/`RecordIntervalResultUseCase`/`RecordSteadyStateResultUseCase`/`FinalizeIntervalResultUseCase`, all in `Application/UseCases/`) — **UNRELATED TO ADHERENCE.** These consume `ResultContext` for entirely different modalities (Strength/Interval/SteadyState), where the Rx/Scaled concept was never in question by this audit and is explicitly out of scope — `ResultContext` is NOT deleted or altered in shape anywhere, precisely because doing so would affect these unrelated, working consumers. This is why item 6's "smallest repository-safe approach" is: leave `ResultContext` completely alone (shape, default, every non-FF consumer), and simply stop FF's OWN PR logic from reading it — a new, FF-specific `adherence` field is the entire fix, with zero risk to Strength/Interval/SteadyState.

### E. Exact new PR eligibility/comparison semantics

**Smallest truthful model: only `adherence == .asPrescribed` results are eligible to compete for the canonical `PersonalRecord` (via `ScoringEngine.bestRecord`/`isNewPersonalRecord`). `.modified` and `.unknown` results are never compared against the canonical bucket and never produce a `PersonalRecord`.** Concretely, in `RecordFunctionalFitnessResultUseCase.recordResult`, change the two real `ScoringEngine` calls (`:38`/`:46`) from keying on `result.resultContext` to gating on `result.adherence == .asPrescribed` before attempting `bestRecord`/`isNewPersonalRecord` at all — if adherence is `.modified` or `.unknown`, skip PR logic entirely for that result (the result itself is still saved, still displayed, still has a real `scoreValue` — only the PR-comparison step is skipped). **This does not require three leaderboards** — it requires exactly one canonical PR bucket (`asPrescribed` only), with everything else simply not participating, which is both the smallest change to `ScoringEngine`'s existing single-bucket-per-context shape and the most honest: a modified/unknown result's score remains real personal history (visible in the UI, per §9's own instruction that score stays separate), it just never overwrites or gets compared against a canonical PR it did not actually earn under confirmed identical conditions. **Real user consequence:** an athlete who taps "Modified" (or never answers, for a legacy/interrupted case) keeps their score in their history but will not see a "New PR!" banner for it, even if the raw number would have beaten the current best — correct, since a modified attempt (e.g. a scaled-down movement) is not a comparable performance.

### F. Treatment of historical PR records

Confirmed by direct read: `PersonalRecord` is a **durable, persisted snapshot** (`PersonalRecord.swift`'s own doc comment: "copied at creation time so the record stands on its own even if its source... is later edited"), never dynamically recalculated from source results at read time. But (per §D's benchmark-gating discovery, see the flagged correction below) **no FF PersonalRecord has ever actually been created in the real shipped app** — `RecordFunctionalFitnessResultUseCase.recordResult`'s own `guard let benchmark, let performanceProfile else { return (result, false) }` (line 23) means PR logic is skipped entirely whenever `benchmark == nil`, and every real Finish-button call site in `FunctionalFitnessExecutionView.swift` hardcodes `benchmark: nil` (all 9 call sites, confirmed by grep) — **the resultContext-driven PR bucketing bug the prior audit found is real in the code but currently DORMANT, not actively corrupting any PR a real user has today, because the guarded PR-creation path is unreachable without a benchmark-tagging UI that does not exist yet.** This is a real, precise correction to the prior audit's framing (which called it "a real, currently-live correctness gap") — it is a landmine, not yet a live wound. Given this: **no existing historical `PersonalRecord`/`benchmarkPerformanceProfile` needs any migration or reinterpretation at all** — there are none to reinterpret. E's fix (gate PR creation on `adherence == .asPrescribed`) simply ensures that WHENEVER a future benchmark-tagging UI ships and PR creation becomes reachable for the first time, it is truthful from that very first real PR onward, never retroactively fixed.

### G. Exact production files/types that must change

- `TrainingOS/Domain/Entities/FunctionalFitnessResult.swift` — add `var adherence: PrescriptionAdherence = .unknown`.
- New file `TrainingOS/Domain/ValueTypes/PrescriptionAdherence.swift` (or co-located in `Enums.swift` next to `ResultContext` — repository convention check needed at implementation time; either is narrow) — the 3-case enum.
- `TrainingOS/Application/ViewModels/FunctionalFitnessExecutionViewModel.swift` — `finish(...)` gains an `adherence: PrescriptionAdherence` parameter, passed into the `FunctionalFitnessResult` initializer.
- `TrainingOS/UI/Session/FunctionalFitnessExecutionView.swift` — the new tiny confirmation surface before each real `finish(...)` call site (9 call sites, all updated to supply the confirmed value).
- `TrainingOS/Application/UseCases/RecordFunctionalFitnessResultUseCase.swift` — gate the two `ScoringEngine` calls on `result.adherence == .asPrescribed` (§E).
- `TrainingOS/UI/Session/CompletedFunctionalFitnessDetail.swift` — replace `resultContextLabel` with an adherence label.
- No change to: `ResultContext`/`Enums.swift`'s existing shape, `WorkoutResult`/`IntervalResult`/`SteadyStateResult`/any of their use cases, `PersonalRecord.swift`, `ScoringEngine.swift`'s own generic comparison logic (only its FF call site's gating changes, not the engine itself), `FunctionalFitnessPerformedMovement`, `SubstituteFunctionalFitnessMovementUseCase`, `LongTermPlanner`, any CP.2 file, any FF.L1 file, any source-authority file.

### H. Exact tests required

Persistence round-trip of `adherence` (all 3 states); legacy-record read test (a pre-FF.E1-shaped `FunctionalFitnessResult`, or one constructed via the old initializer signature, reads `adherence == .unknown`); migration test confirming the additive field triggers no destructive schema change and no CoreData/SwiftData warning; a `finish()`-level test proving an explicit "As prescribed" tap produces `adherence == .asPrescribed` and "Modified" produces `.modified`; a PR-gating test proving a `.modified`-adherence result with a numerically better `scoreValue` than the current best does NOT become a new `PersonalRecord` (and does not overwrite the existing one); a companion test proving an `.asPrescribed` result WITH a better score DOES become the new PR, unchanged from today's comparison logic once adherence is `.asPrescribed`; a regression test confirming every existing `ScoringEngine`/Strength/Interval/SteadyState `ResultContext`-based test is completely unaffected (proving the shared-enum finding in §D didn't leak any behavior change into unrelated modalities); a UI/ViewModel-level test confirming the new confirmation prompt never blocks Finish indefinitely and the existing `completionContext`/`benchmark` behavior is unchanged; full existing suite unchanged.

### I. Does this require touching FF.L1, CP.2, `LongTermPlanner`, any source-authority file, `FunctionalFitnessPerformedMovement`, or readiness substitution code?

**NO**, confirmed by the file list in G — none of these are touched. One adjacent, non-blocking fact worth naming: `ResultContext` (item D) turns out to be a genuinely cross-modality shared type (Strength/Interval/SteadyState also use it), which was not fully surfaced in the prior audit's FF-only framing — but this does NOT require touching any of those other modalities' files, precisely because this design lock's entire G-file-list strategy is to add a new, FF-only field rather than touch the shared `ResultContext` type at all.

---

## FF.E1 Implementation Report — Prescription Adherence Truth

**Status: IMPLEMENTED (uncommitted). Not CP.3, not a later CP stage — a separate, narrow execution-truth stage. CP.2 remains closed at `bca43e2ff47d21d8703275d06354af6a086f0d45`; FF.L1 remains closed at `ae5898c36cdb5617edf77f2ad68507149ea3e2ac`.**

### Adherence is separate from ResultContext

`PrescriptionAdherence` (`Domain/ValueTypes/PrescriptionAdherence.swift`, new): `enum PrescriptionAdherence: String, Codable, CaseIterable { case unknown, asPrescribed, modified }`. `ResultContext` (Rx/Scaled) is untouched — same shape, same file, still shared cross-modality (Strength/Interval/SteadyState). Functional Fitness's own PR-eligibility and display logic now read `adherence`, never `resultContext`.

### Legacy adherence == unknown

`FunctionalFitnessResult.adherence: PrescriptionAdherence` is additive, `init` defaults it to `.unknown`. No pre-FF.E1 record is ever read as `.asPrescribed` — proven by `testLegacyShapedResultResolvesToUnknown` and `testNewResultDefaultsSafelyToUnknownWhenNoExplicitAdherenceIsSupplied`.

### Confirmation applies to FINAL

`FunctionalFitnessExecutionViewModel.finish` takes `adherence: PrescriptionAdherence` with no default — every real call site must pass one explicitly. The confirmation is evaluated against the FINAL (post-CP.2) prescribed workout the athlete actually attempted, never `intendedStimulus`.

### completionContext and adherence are independent

Untouched, unconstrained by each other — proven by `testCompletionContextRemainsIndependentOfAdherence` (`asPrescribed`+`.partial` and `modified`+`.full` both valid).

### Score and adherence are independent

`scoreValue`/`scoreType`/`scoreDirection` computation is completely unchanged — `adherence` only gates PR *eligibility*, never whether a score exists or is displayed (`testModifiedAndUnknownResultsRetainTheirRealScoreAndRemainInHistory`).

### Only asPrescribed is canonical FF PR eligible

`RecordFunctionalFitnessResultUseCase.recordResult` gates PR creation/comparison on `result.adherence == .asPrescribed`, evaluated after the result and its score are already attached to history (so `.modified`/`.unknown` results are still saved, still real, just never contest the canonical record) — proven by `testAsPrescribedResultIsEligibleForCanonicalPersonalRecord`/`testModifiedResultIsNotEligibleForCanonicalPersonalRecordEvenWithABetterScore`/`testUnknownResultIsNotEligibleForCanonicalPersonalRecordEvenWithABetterScore`.

### ResultContext remains cross-modality legacy/shared state

Confirmed zero diff to `Enums.swift` (where `ResultContext` is defined) and to every Strength/Interval/SteadyState consumer.

### One shared finish/adherence flow, not nine duplicated copies

`FunctionalFitnessExecutionView`'s 8 real format-specific Finish actions now set a local `PendingFinish` (score + completion context) instead of calling `viewModel.finish` directly. One shared `.confirmationDialog` ("Did you follow the workout as prescribed?" — As Prescribed / Modified / Cancel) is the ONLY place that calls `viewModel.finish`, passing the athlete's explicit choice. Cancelling clears `pendingFinish` and persists nothing — the block stays not-yet-completed, so no completed work is ever lost to a dismissed prompt. Confirm-then-persist preserved exactly: still one synchronous `finish()`/`modelContext.save()` call, never a persist-then-patch two-step. `.unknown` is never offered as a normal choice.

### Deviation from the original file-list lock, disclosed

`TrainingOS/Application/Seed/SeedScenarios.swift`'s Fran demo scenario constructs a `FunctionalFitnessResult` via the real `RecordFunctionalFitnessResultUseCase.recordResult` path with a real `benchmark` — three pre-existing tests (`DeleteRuleMatrixTests.testDeletingFunctionalFitnessResultPreservesItsPersonalRecord`, `DeleteRuleMatrixTests.testExplicitPersonalRecordDeletionOnlyRemovesThatRecord`, `DomainModelScenarioTests.testForTimeBenchmarkRecordsRxTimeAndCreatesAPersonalRecord`) depend on that seed producing a real `PersonalRecord`. Under the new, intentionally-changed PR-eligibility gate, that seed's result needed one added parameter — `adherence: .asPrescribed` — to keep representing what it always meant to represent (a confirmed demo PR), not a workaround. This was not in the original §G file list; disclosed here rather than silently expanded. Two other pre-existing tests' fixtures (`FunctionalFitnessSubstitutionAndBenchmarkTests`, `RecordEnduranceResultUseCaseTests`) were updated the same way, for the same reason.

### Generated FF still lacks numeric prescription depth / movement substitution remains deferred / incompleteMinuteIndices remains a known gap / no progression consumes adherence yet

All confirmed unchanged and untouched by this stage — `FunctionalFitnessPerformedMovement.swift`, `SubstituteFunctionalFitnessMovementUseCase.swift`, and every readiness-substitution file show zero diff; `incompleteMinuteIndices` is still captured but never persisted (unfixed, as instructed); no progression axis or `VarianceConstraints` activation exists anywhere in this diff.

### Verification record

12 targeted FF.E1 tests pass; all 8 existing FF.L1 tests pass unchanged; all 24 existing CP.2 tests pass unchanged; full suite 1025 passed / 2 skipped / 0 failed (baseline 1013/2/0 + 12 new); clean `build`/`build-for-testing`; a fresh simulator install/launch produced no crash and no CoreData/SwiftData migration or corruption warnings (only the expected, benign "no existing store file yet" first-launch probe, unrelated to this change); source-authority diff zero; `LongTermPlanner.swift` diff zero; production `VarianceConstraints()` construction unchanged; exactly one `SchedulingPipeline.propose` call site. No true end-to-end UI tap-through smoke test was performed — this project has no XCUITest automation target (only `TrainingOS` and `TrainingOSTests`, confirmed via `xcodebuild -list`), so the closest available and actually meaningful proof is the ViewModel-level integration tests exercising the identical `finish()`/persistence/display-reading code paths across all 8 real `WorkoutFormat` cases, plus the clean fresh-launch smoke test.

---

## STOP

**Design lock / audit only for every section before "FF.E1 Implementation Report"; that section reflects real, uncommitted implementation work.** Nothing has been committed or pushed. Stage CP.2 remains closed at `bca43e2ff47d21d8703275d06354af6a086f0d45`; Stage FF.L1 remains closed at `ae5898c36cdb5617edf77f2ad68507149ea3e2ac`. Neither this document's analysis nor any future stage built from it may retroactively reinterpret either as anything other than what their own closing reports recorded.
