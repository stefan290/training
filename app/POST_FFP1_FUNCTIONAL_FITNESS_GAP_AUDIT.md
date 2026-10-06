# Post-FF.P1 Functional Fitness Gap + Priority Audit

**Status: DESIGN/AUDIT ONLY. Nothing implemented, committed, or pushed.** HEAD at time of audit: `ac76e1a24bb868583798f144fa65bfd0ea7c1a1d` (FF.P1 closed). Closed prerequisite stages: CP.2 (`bca43e2`), CP.2R (`2f02c60`), FF.L1 (`ae5898c`), FF.E1 (`a3c3d0b`), FF.P1 (`ac76e1a`). None modified by this audit.

The four existing design docs (`TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`, `FUNCTIONAL_FITNESS_LONGITUDINAL_PROGRAMMING_DESIGN.md`, `FUNCTIONAL_FITNESS_EXECUTION_TRUTH_DESIGN.md`, `FUNCTIONAL_FITNESS_PRESCRIPTION_DEPTH_DESIGN.md`) are treated here as historical evidence, not authority. Every conclusion below is re-derived directly against the real code at HEAD, with file citations, not restated from those documents' own prior recommendations.

---

## A. Executive conclusion

Functional Fitness at HEAD can generate one, single, structurally coherent workout shape — a 5-round-for-time triplet with concrete reps/distance targets on 2-3 of 3 movements — and can materialize it identically, week after week, for the life of a `ProgramInstance`. **Nothing in the current production system makes that workout change, adapt, or progress over time in any athlete-visible way.** Every mechanism that theoretically could (CP.2's stimulus adaptation, `VarianceConstraints`, exposure history, `AdaptationObjective`) either (a) never fires in the real default configuration, or (b) fires but only mutates a categorical `Stimulus` field the concrete FF.P1 target rule never reads. The single highest-value next stage is **not** numeric load — it is closing the gap between CP.2's real, shipped semantic adaptation and the athlete's real, concrete prescription, because right now that gap means the entire Concurrent Programming investment (CP.2/CP.2R) has **zero athlete-visible effect** on the one real production workout shape. See §O, §T, §U.

---

## B. Current production FF pipeline (verified against HEAD)

```
Goal/Phase → LongTermPlanner mix builder (e.g. muscleGainVariedMix, functionalFitnessFocusedMix)
  → TrainingMixComponent(programmingSystem: .functionalFitness, priority, adaptationObjectives, frequency)
  → LongTermPlanner.functionalFitnessParameterCandidates(component:)  [LongTermPlanner.swift:1201-1226]
      → ONE fixed Stimulus + ONE fixed WorkoutFormat (.roundsForTime(rounds:5,capSeconds:nil)),
        VarianceConstraints() all-nil, lengthWeeks: 4 — IDENTICAL regardless of which mix,
        which adaptationObjectives, or which priority requested it (confirmed: this is the
        SOLE real construction site, used by every FF-producing builder)
  → FunctionalFitnessProgramGenerator.generate  [FunctionalFitnessProgramGenerator.swift:36-118]
      → Stage C: one FunctionalFitnessMovementSlotTemplate per ModalityCount entry,
        round-robin movementFunction assignment, loadingRole captured from stimulus.loading
      → SAME TemplateSession/slot graph reused for all 4 weeks (no per-week regeneration)
  → RollTacticalWindowUseCase.rollForward (per real tactical week)
      → FunctionalFitnessDecisionEngine.decideWithIntent
          → Phase 1 (intent, 4 variance checks, ALWAYS a no-op in production — VarianceConstraints
            all-nil) → INTENDED == configured baseline, always
          → Phase 2 (CP.2's 2 checks) → FINAL (may differ from INTENDED only if a same-week
            .primary sibling triggers cross-modality repair, or same-week FF complementarity fires)
  → FunctionalFitnessMaterializer.materializeWeek  [FunctionalFitnessMaterializer.swift:32-193]
      → Stage D: resolvedExercise = GOING-FORWARD override ?? candidateExercises.first{isValid}
        (deterministic given a stable candidateExercises array — not random, but also never varied)
      → FunctionalFitnessMovementTargetRule.resolve(format, modality, movementFunctions, exercise)
        [FunctionalFitnessMovementTargetRule.swift] → reps/distanceMeters, generation-time-frozen
        template value wins if non-nil
      → movement.sourceExerciseSlot = exerciseSlot (FF.P1 addition, enables substitution)
      → Stage E validation (matchesDuration/matchesModality/matchesLoading[deferred, CP.2R]/
        matchesSkill[deferred]/matchesScoreType)
  → Execution (FunctionalFitnessExecutionView, shared header via BlockPresentation.prescribedMovementLine)
  → Legal substitution (readiness-driven only) re-runs the SAME target rule to keep the concrete
    prescription consistent with whichever Exercise is now attached
  → Finish → FunctionalFitnessResult(scoreValue, scoreDirection, adherence, benchmark: nil ALWAYS
    in real production UI [FunctionalFitnessExecutionView.swift:90])
  → FunctionalFitnessExposureHistoryBuilder builds VarianceExposureRecord from completed sessions'
    prescription.stimulus fields ONLY — feeds the 4 Phase-1 checks that never fire in production
```

This confirms the user's own "known current FF pipeline" framing is accurate at HEAD.

---

## C. Real FF programming today

**`muscleGainVariedMix`** (`LongTermPlanner.swift:832-850`): FF component `.supporting`, `[.workCapacity, .aerobicCapacity, .power]`, `frequency.target: 2`. Real generated FF `ProgramDefinition`: `daysPerWeek: 2`, `lengthWeeks: 4`. Every week: 2 sessions, each `.roundsForTime(rounds: 5, capSeconds: nil)`, 3 movement slots (`.weightlifting`/`.squatLoaded`, `.gymnastics`/`.gymnasticsPull`, `.metabolicConditioning`/`.monostructural`). INTENDED == configured baseline always (VarianceConstraints inert). FINAL differs from INTENDED only in a week where the real sibling Strength component's `TrainingStressProfile.lowerBodyLoad`/`.impactLoading` clears `.high` (peak weeks, per the real `repGoalSchedule` — week 4 of the 5-week Family A mesocycle) — CP.2's repair then steps `loading` back one case. This changes the persisted `Stimulus.loading` field only; it does not change which slots exist, which Exercise resolves, or the concrete reps/distance targets (see §O). Resolved Exercise pool per slot: squatLoaded → {Back Squat, Wall Ball, Thruster}; gymnasticsPull → {Pull-up, Toes-to-Bar}; monostructural → {Easy Run, Track Interval Run, Assault Bike, Row Erg, SkiErg} — confirmed real, exhaustive (`ExerciseCatalog.swift:151-209`). Given a stable candidate-exercise fetch order, the SAME Exercise resolves to the SAME slot every week for the life of the `ProgramInstance` (no randomness, no built-in rotation). Readiness can substitute the resolved Exercise (session-only); FF.P1 then recomputes the concrete target for whichever Exercise is now attached. Result/adherence: real `FunctionalFitnessResult` created at Finish, `benchmark: nil` always, `adherence` explicitly confirmed by the athlete (`asPrescribed`/`modified`) or `unknown` if not confirmed.

**`functionalFitnessFocusedMix`** (`LongTermPlanner.swift:972-980`): FF component `.primary`, `[.workCapacity, .aerobicCapacity, .anaerobicCapacity, .power, .skillAcquisition]`, `frequency.target: 4` (minimum 3). Confirmed: this mix has **no sibling component at all** (the builder constructs exactly one `TrainingMixComponent`) — meaning `protectedSiblingStressProfilesThisWeek` is always empty for this mix's own FF sessions (CP.2's cross-modality check can never fire for a component with no `.primary` sibling), and same-week complementarity is the ONLY CP.2 mechanism that can ever act on it, across its own 4 weekly sessions. Otherwise byte-identical generated shape to `muscleGainVariedMix`'s FF component — same fixed `Stimulus`/format/slots, same resolved-exercise pools, confirmed by direct re-read of `functionalFitnessParameterCandidates` being the sole, shared construction site.

---

## D. Week-to-week change audit

| Property | Owner / code path | Classification |
|---|---|---|
| `format` | Fixed at `LongTermPlanner.swift:1221`, never revisited | **G — nothing, always identical** |
| `targetDurationDomain` | `adjustForDurationDomain` — inert (VarianceConstraints nil) | **G**, dormant **B** |
| `intensity` | `adjustForSameWeekComplementarity`/`AdaptationObjectiveStimulusMapping.nudge` — CAN change, real | **C** (concurrent adaptation, same-week complementarity only) |
| `loading` | `adjustForLoading` (inert) / `CrossModalityStimulusRepair.minimalRepair` (real) | **C** (real, but see §O — no concrete effect) |
| `skillDemand` | `nudge` toward `.skillAcquisition` — real, but see §L (never read downstream) | **C**, functionally inert |
| `systemicDemand` | `nudge` toward `.workCapacity` — real | **C** (real, no concrete effect — see §O) |
| `scoreType` | Fixed, never touched by any check | **G** |
| `movementFunctions` | `adjustForMovementFunction` — inert; NEVER touched by CP.2 | **G** (dormant **B** only) |
| `movementModalityMix` | `adjustForModality` — inert; NEVER touched by CP.2 | **G** (dormant **B** only) |
| `resolvedExercises` | `candidateExercises.first{isValid}` — deterministic given stable input, no rotation mechanism | **E**, effectively **G** week-to-week (same pick every week absent substitution) |
| `reps`/`distanceMeters` | `FunctionalFitnessMovementTargetRule.resolve` — a pure function of `format`/`modality`/`movementFunctions`/`exercise`, none of which ever change week-to-week in production | **G** — identical every week |
| `calories`/`numeric load` | Never set by any real path | **G** — always nil |
| `rounds`/`timeCap`/`workRest` | Fixed in `format`, never varies | **G** |
| `benchmarkIdentity` | Never assigned (`benchmark: nil` hardcoded at the one real UI call site) | **G** |
| `scaling/substitution` | `SubstituteFunctionalFitnessMovementUseCase`, readiness-triggered only | **D** — occasional, session-scoped, never persists forward |

**Explicit answer: if the athlete follows the generated FF program for 8 weeks, nothing structurally progresses.** The only thing that can ever differ between two specific sessions is `Stimulus.intensity`/`loading`/`systemicDemand`/`skillDemand` via CP.2's real adaptation mechanisms — and none of those four fields is read by the concrete target rule, so even that difference is invisible to the athlete (§O). Every other property is either fixed forever or gated behind an inert `VarianceConstraints`.

---

## E. AdaptationObjective effectiveness

| Objective | Stored on component? | Actually changes FF programming? |
|---|---|---|
| `workCapacity` | Yes (both real mixes) | Only via `nudge` in `adjustForSameWeekComplementarity` — a real, same-week-only categorical `Stimulus.systemicDemand` change with **zero concrete effect** (§O) |
| `aerobicCapacity` | Yes (both) | Same — `targetDurationDomain` nudge, zero concrete effect |
| `power` | Yes (`muscleGainVariedMix` only) | Same — `intensity` nudge, zero concrete effect |
| `anaerobicCapacity` | `functionalFitnessFocusedMix` only | No honest mapping consumes it for FF's `targetDurationDomain == .short` nudge in the same-week path... confirmed real (mapped in `AdaptationObjectiveStimulusMapping`), same zero-concrete-effect caveat |
| `skillAcquisition` | `functionalFitnessFocusedMix` only | `nudge` toward `.skillAcquisition` sets `skillDemand = .high` — but `skillDemand` has zero downstream effect anywhere (§L) — **doubly inert** |
| `muscleGain`/`maxStrength` | Never assigned to FF components (no honest mapping, per CP.2's own locked design) | N/A — correctly never reaches FF |

**Strict conclusion: every `AdaptationObjective` currently assigned to a real FF component is "stored/represented" but produces ZERO athlete-facing programming difference** — each nudge only nudges a `Stimulus` field the concrete target rule (§B/§O) never reads. This is not a partial implementation gap — it is a complete, real, currently-invisible pipeline: the objective genuinely changes a persisted value, and that value genuinely has no consumer that produces a different workout.

---

## F. Prescription completeness (post-FF.P1)

| Dimension | Status | Real production frequency |
|---|---|---|
| Movement identity | Fully prescribed | Every session |
| Reps (squatLoaded/gymnasticsPull) | Fully prescribed (12/8) | 2 of 3 movements, every session |
| Distance (monostructural, non-bike) | Fully prescribed (200m) | 1 of 3 movements, most sessions (4 of 5 real candidates) |
| Distance (Assault Bike) | Intentionally unprescribed | Whenever Assault Bike resolves — real, not rare (1 of 5 real candidates) |
| Calories | Never prescribed | Every session |
| Numeric load | Never prescribed | Every session with a squatLoaded slot |
| Rounds | Fully prescribed (5) | Every session |
| Time cap | Never set (`capSeconds: nil` in the one real config) | Every session |
| Work/rest interval | N/A — format never generates a work/rest structure | Every session |
| Movement ordering | Prescribed (slot order) | Every session |
| Score direction/type | Fully prescribed (`.time`) | Every session |
| Scaling guidance | None beyond post-hoc `adherence` confirmation | Every session |
| Skill prescription | None — `skillDemand` inert | Every session |

**Ranked by real production frequency/impact**: (1) numeric load absence — affects 1 of 3 movements every single session, the highest-frequency gap; (2) Assault Bike's unprescribed distance — affects roughly 1 in 5 real monostructural resolutions; (3) no time cap — affects every session's completion-context signal quality (the athlete can't know if they're "supposed" to finish under a cap); (4) calories — never affects a real session today (no calorie-appropriate candidate is ever asked to receive a target). Numeric load is real and high-frequency, but §K shows it is NOT the cheapest gap to close.

---

## G. Movement diversity

Re-confirmed directly against `ExerciseCatalog.swift` at HEAD: the real generator's `stimulus.movementFunctions = [.squatLoaded, .gymnasticsPull, .monostructural]` (`LongTermPlanner.swift:1205`) is unconditional and unchanged — **still exactly 3 of `MovementFunction`'s 15 real cases are ever assigned into a real generated slot.** The catalog itself is materially richer than that: real, seeded, `functionalModality`-carrying entries exist for `.hingeLoaded`+`.weightlifting` (Deadlift, Kettlebell Swing, Dumbbell Snatch — `ExerciseCatalog.swift:177,182,233,238`), `.gymnasticsPush`+`.gymnastics` (Push-up, Handstand Push-up — `:221,226`), and `.other`+`.gymnastics` (Burpee — `:172`, not eligible for any real generated slot since no slot is ever assigned `.other`). **DOMAIN CAN REPRESENT**: hinge, press, gymnastics push, loaded pull (`.horizontalPullLoaded`/`.verticalPullLoaded`), carry, trunk, jumping, locomotion, and multiple squat-pattern variants — all real enum cases with real catalog entries. **PRODUCTION GENERATOR CAN PROGRAM**: only squat-loaded, gymnastics-pull, monostructural. This is a domain-vs-generator gap, not a domain-vs-catalog gap — the catalog is ready; `functionalFitnessParameterCandidates`'s one hardcoded `movementFunctions` array is the sole blocker.

---

## H. Format diversity

All 9 `WorkoutFormat` cases classified:

| Format | Classification |
|---|---|
| `.roundsForTime` | **A — generated in real production** (the only one) |
| `.amrap` | B — seed/test only |
| `.emom` | B — seed/test only |
| `.forTime` | B — seed/test only |
| `.chipper` | B — seed/test only |
| `.ladder` | B — seed/test only |
| `.maxLoad` | B — seed/test only |
| `.maxReps` | B — seed/test only |
| `.intervals` | B — seed/test only |

Every non-`.roundsForTime` format is fully supported by execution (`FunctionalFitnessExecutionView` has a real, distinct body for each) and by Stage-E validation — this is **C (represented but dormant)**, not D/E. Format expansion assessment: given §D/§O's finding that even the ONE generated format produces an identical workout every week regardless of any real adaptation mechanism, adding more formats without also closing the "nothing actually changes" gap would add cosmetic variety only — a `.forTime` triplet with the same fixed 3 movements is not meaningfully different from a `.roundsForTime` one for longitudinal-programming purposes. Format expansion is not high-value until something real drives WHICH format to choose and WHY.

---

## I. Result-feedback loop

Traced `FunctionalFitnessResult` forward exhaustively: `scoreValue`/`scoreDirection` feed only `ScoringEngine.bestRecord`/PR comparison, gated on `adherence == .asPrescribed` AND `benchmark != nil` (`RecordFunctionalFitnessResultUseCase.swift:39`) — since `benchmark` is hardcoded `nil` at the one real UI call site, **this entire path is dormant in real production; no FF PersonalRecord has ever been created.** `resultContext` is read only by the same dormant PR path. `PrescriptionAdherence` is read only by that same gate. Completed state / substitution flags are read only for display. **No real code path feeds ANY of this back into a future FF programming decision** — the only thing that reads history at all is `FunctionalFitnessExposureHistoryBuilder`, which builds `VarianceExposureRecord`s from `prescription.stimulus` fields (never `scoreValue`/`adherence`/performance) to feed the 4 Phase-1 variance checks, which are permanently inert because `VarianceConstraints()` is all-nil. **Answer: no, athlete performance today does not alter future FF programming, in any way, at all.** This is a stronger, more definitive finding than "performance feedback is weak" — it is real, actual zero.

---

## J. Progression-axis feasibility matrix

| Axis | Domain | Execution | Result-data | Calibration | New persisted state | CP.2 interaction | Readiness interaction | Substitution interaction | Fake-precision risk | Complexity | Value |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1. Reps/volume | Full | Full | Partial (adherence only) | None | None | None (never touched) | Safe (recomputed on substitution) | Safe | Low | Low | High |
| 2. Distance | Full (non-bike) | Full | Partial | None | None | None | Safe | Safe | Low | Low | Medium |
| 3. Numeric load | Partial (`loadKilograms` exists) | Full | None | **Required** — no honest anchor for most FF movements | Possibly (a calibration anchor) | None | Unproven | Unproven | **High** without an anchor | Medium-High | High but blocked |
| 4. Density | None (no workout-identity concept) | N/A | None | Depends | Likely | Unknown | Unknown | Unknown | High | High | Low-medium until identity exists |
| 5. Duration | Partial (`capSeconds` exists, never set) | Full | Partial | None | None | Blocked by format-coherence (`targetDurationDomain` vs. fixed format) | Safe | Safe | Low | Medium (format coupling) | Low (no cap ever set today) |
| 6. Rounds | Full | Full | Partial | None | None | None | Safe | Safe | Low | Low | Low (fixed at 5, works fine) |
| 7. Time cap | Full (structurally) | Full | Full (`completionContext`) | None | None | None | Safe | Safe | Low | Low | Medium (currently unused, real gap) |
| 8. Work/rest ratio | Full for `.emom`/`.intervals` (never generated) | Full | Partial | None | None | Unknown (untested) | Unknown | Unknown | Low | Medium (format expansion needed) | Low until format expands |
| 9. Skill/difficulty | **None** — no catalog variant-linking concept | N/A | N/A | **Required, large** (new catalog relationships) | Yes (new relationship) | N/A | N/A | N/A | High without catalog work | High | Medium, blocked |
| 10. Movement complexity | Partial (more `MovementFunction`s exist than are generated) | Full for existing catalog entries | N/A | None | None | Unproven | Unproven | Unproven | Low | Low-medium (generator authoring only) | Medium-high |
| 11. Systemic demand | Full (categorical) | N/A (invisible to athlete, §O) | None | None | None | Real (CP.2 already touches it) | N/A | N/A | Low | Low | Low until it has a concrete consumer |
| 12. Benchmark performance | Full (`BenchmarkDefinition` exists) | Full | Full | None | None | Untested | Untested | Untested | Low | Medium (needs benchmark-tagging UI) | Medium, currently dormant not because it's hard but because it's never invoked |
| 13. Repeatability/quality | Partial (`adherence` exists) | Full | Partial | None | None | N/A | N/A | N/A | Low | Low | Medium (already the cheapest real signal, FF.E1 shipped it) |

---

## K. Numeric-load readiness

Traced exhaustively: (A) domain field exists — yes, `FunctionalFitnessMovement.loadKilograms: Double?`. (B) data exists somewhere — yes, `ExercisePerformanceProfile.estimatedOneRepMax`, real, keyed by any `Exercise`, populated from logged `SetResult`s regardless of program. (C) data valid for THIS exercise — **only conditionally**: populated only for an `Exercise` the athlete has actually logged strength data against. Real squatLoaded pool = {Back Squat, Wall Ball, Thruster} — Back Squat plausibly overlaps a real Hypertrophy program's own canonical exercise (shared catalog entry), but Wall Ball/Thruster almost never would. (D) formula exists — no; no validated %1RM-to-metcon-load conversion exists anywhere in the repository. (E) formula is product-authorized — no; CLAUDE.md rule 10 explicitly forbids inventing one. (F) execution captures enough feedback to progress it — no; `loadKilograms` is never captured as a performed value anywhere in the real execution flow. **Conclusion, unchanged from all prior audits and re-confirmed at HEAD: TrainingOS cannot honestly prescribe "12 Thrusters @ X kg" today.** The missing piece is not a domain field — it's (D)/(E), a validated, product-authorized formula, which requires an explicit product decision this audit does not invent.

---

## L. Skill system readiness

Re-confirmed precisely at HEAD: `skillDemand` has genuinely zero downstream effect anywhere in the real pipeline — not in `FunctionalFitnessMovementTargetRule.resolve` (doesn't take it as a parameter at all), not in `FunctionalFitnessStressProfileMapper.map` (no `skillDemand` reference in its body, confirmed by direct re-read), not in Stage-E validation (`matchesSkill` remains hardcoded `true`, unchanged by CP.2R or FF.P1). The ONLY place `skillDemand` is ever written is `AdaptationObjectiveStimulusMapping.nudge(toward: .skillAcquisition)` — a real mutation with a real, confirmed-zero consumer. Catalog audit: no skill-tier relationships exist — Pull-up and Toes-to-Bar exist as real, independent catalog entries, with no "harder variant of" relationship field on `Exercise`, and no "Chest-to-Bar Pull-up"/"Bar Muscle-up" (or equivalent) entries exist in the catalog at all. **TrainingOS cannot currently progress any skill family** — both the wiring and the underlying catalog content are absent.

---

## M. Variance system status

`VarianceConstraints`'s 4 dimensions (duration domain, loading, modality mix, movement function) are all real, all fully implemented in `FunctionalFitnessDecisionEngine`'s Phase 1, and all dormant — the one real production construction site (`LongTermPlanner.swift:1222`) passes `VarianceConstraints()` with every field nil, unchanged since before CP.2. Even if active, it only avoids repetition (rotates to the next case after N identical exposures) — it does not create deliberate, purposeful progression.

**Critical safety finding, a real CP.2R-class risk, confirmed by tracing the actual mechanism:** `adjustForModality`/`adjustForMovementFunction` (if ever activated) mutate `Stimulus.movementModalityMix`/`.movementFunctions` at the PER-WEEK decision-engine level — but the real, per-slot `ExerciseSlot.allowedMovementFunctions`/`.allowedModalities` are fixed ONCE at generation time (`FunctionalFitnessProgramGenerator.movementSlots`, `:94-118`) and never regenerated per week. Activating movement-function/modality variance today would produce a `Stimulus` that describes a DIFFERENT movement mix than the slots that actually exist to materialize it — the exact "frozen generation-time value vs. live per-week value of the same field" pattern CP.2R just fixed for `loading`, now latent for `movementFunctions`/`movementModalityMix` instead. **This is a real, disclosed, currently-dormant risk**: activating `VarianceConstraints` for these two dimensions without first solving how the slot graph would be regenerated (or reinterpreted) per week would either silently do nothing (the new `Stimulus.movementFunctions` value has no slot to express it) or require a real architectural change to slot generation. This is worth locking as an explicit prerequisite before any future variance-activation stage.

---

## N. Benchmark/retest status

`BenchmarkDefinition`/`BenchmarkPerformanceProfile` are real, fully implemented types. Generated production FF **cannot create benchmark identity** — confirmed, the one real UI call site hardcodes `benchmark: nil` (`FunctionalFitnessExecutionView.swift:90`). No retesting is scheduled anywhere (no code references a benchmark-retest cadence). PR logic (`RecordFunctionalFitnessResultUseCase`) is real but entirely dormant for the same reason. Adherence interacts with benchmark validity correctly in principle (only `.asPrescribed` results are PR-eligible) but the interaction has never actually fired in production. **Assessment: benchmark/retest capability is still premature** — it depends on a benchmark-tagging UI/flow that doesn't exist yet, and building retest scheduling before that exists would be building on top of a dormant foundation.

---

## O. Concurrent-programming concrete-effect audit — the decisive finding of this report

For the real `3× Hypertrophy + 2× Functional Fitness + 1× Running` case: traced precisely whether CP.2's real, shipped adaptation changes what the athlete concretely sees. `CrossModalityStimulusRepair.minimalRepair` mutates **only `Stimulus.loading`**. `AdaptationObjectiveStimulusMapping.nudge` mutates only one of `intensity`/`targetDurationDomain`/`systemicDemand`/`skillDemand` per call. **`FunctionalFitnessMovementTargetRule.resolve`'s real signature is `(format:modality:movementFunctions:exercise:)` — it does not accept `loading`, `intensity`, `targetDurationDomain`, `systemicDemand`, or `skillDemand` as inputs at all.** Every field CP.2 can ever change is a field the concrete target rule structurally cannot see.

Concretely: if CP.2 changes `loading` heavy → moderate for a real peak Strength week, the athlete's FF session is still, byte-for-byte: **"5 Rounds For Time: 12 Wall Ball, 8 Pull-ups, 200m Row."** Nothing about which exercise resolves, how many reps, or what distance changes. **A genuine SEMANTIC-vs-CONCRETE gap exists, and it is total for the current production shape**: CP.2 correctly adapts the invisible `Stimulus`/`TrainingStressProfile` record (which matters for CP.1's cross-modality interference math against the Hypertrophy/Running siblings), but this adaptation has zero athlete-facing consequence today. The entire CP.2/CP.2R investment is real, correctly implemented, and currently invisible to the person actually doing the workout.

---

## P. Readiness-depth audit

Traced `ReadinessAdaptationDecisionUseCase.accept` exhaustively (`:19-78`): for Functional Fitness, only `.exerciseSubstituted` has a real, wired path (`SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly`, which since FF.P1 also recomputes the concrete target). `.loadReduced` exists as a case but is "not automatically produced by `EvaluateReadinessAdaptationUseCase`" per its own doc comment — dormant for FF. `.setCountReduced` only applies to `ExercisePrescription` (Strength), not `FunctionalFitnessMovement`. `.blockRemoved`/`.postponeRecommended` are whole-block/session skips, not FF-specific adaptations. **Readiness cannot today change reps, distance, load, rounds, duration, format, or skill for Functional Fitness — only the resolved Exercise, via substitution.** This remains entirely categorical/infrastructural, exactly as the prior audit found, now re-confirmed with FF.P1's own target-recomputation change layered on top (which makes substitution safer, not deeper).

---

## Q. 10+ athlete-visible real workout examples

1. **muscleGainVariedMix, week 1, no CP.2 adaptation**: "5 Rounds For Time: 12 Back Squat, 8 Pull-up, 200 m Row Erg." — **PARTIALLY SPECIFIED** (movement/reps/distance real; no load, no cap).
2. **muscleGainVariedMix, real peak Strength week, CP.2 fires**: identical to #1, byte-for-byte (§O). — **PARTIALLY SPECIFIED**, and this specific example demonstrates CP.2's invisibility.
3. **functionalFitnessFocusedMix, any week**: "5 Rounds For Time: 12 Wall Ball, 8 Toes-to-Bar, 200 m SkiErg." — **PARTIALLY SPECIFIED**.
4. **Assault Bike resolves for the monostructural slot**: "5 Rounds For Time: 12 Thruster, 8 Pull-up, Assault Bike." — **SEMANTICALLY UNDER-SPECIFIED** for the third movement (no target at all, deliberately, per FF.P1's own lock — the athlete has no volume/duration signal for that movement whatsoever).
5. **A hand-authored/seed benchmark, e.g. Fran-shaped content** (real, `SeedScenarios.swift`): explicit reps/rounds authored directly — **EXECUTABLE AS WRITTEN** for the dimensions it authors, though still no numeric load.
6. **A `.maxLoad` format instance** (test/seed-only, never generated): no reps target applies by FF.P1's own rule (§4 of the earlier design lock) — **SEMANTICALLY UNDER-SPECIFIED**, the format's entire point (a numeric load) is exactly the dimension this system cannot honestly prescribe.
7. **A `.amrap` instance** (test/seed-only): FF.P1 assigns no target at all (format-gated) — movements shown with names only — **SEMANTICALLY UNDER-SPECIFIED**.
8. **Post-substitution, Row Erg → Assault Bike** (readiness-driven): "5 Rounds For Time: 12 Wall Ball, 8 Pull-up, Assault Bike" (distance correctly cleared) — **PARTIALLY SPECIFIED**, honestly degraded.
9. **Post-substitution, Assault Bike → Row Erg**: target correctly regained, 200m — **PARTIALLY SPECIFIED**.
10. **A slot resolving to Kettlebell Swing or Deadlift** (real catalog entries, `.hingeLoaded`) — **not currently reachable** in real production (the generator never assigns `.hingeLoaded` to a slot) — illustrates §G's diversity gap directly; if it were reachable, it would receive NO FF.P1 target (rule only covers `.squatLoaded`) — **SEMANTICALLY UNDER-SPECIFIED** if this ever became reachable without a corresponding dose-rule extension.
11. **A hypothetical bodyweight-only triplet** (Pull-up/Push-up/Toes-to-Bar, domain-valid, not real production shape): Push-up (`.gymnasticsPush`) receives no target even though it's a real catalog entry with a real `functionalModality` — **PARTIALLY SPECIFIED**, an honest gap the current rule discloses rather than fabricates.

---

## R. 8-week reconstruction

**`muscleGainVariedMix` FF component (2 sessions/week, 4-week `ProgramDefinition`, weeks 5-8 require a fresh `ProgramDefinition` generation — same `functionalFitnessParameterCandidates` call, byte-identical Stimulus/format):**

| Week | Session A | Session B | What changed vs. prior week |
|---|---|---|---|
| 1 | 12 Back Squat / 8 Pull-up / 200m Row (candidate set: squat→{Back Squat, Wall Ball, Thruster}; pull→{Pull-up, Toes-to-Bar}; mono→{Easy Run, Track Interval Run, Assault Bike, Row Erg, SkiErg}; resolution deterministic, shown as first-eligible given stable fetch order) | Same shape, same resolved exercises | — (week 0 baseline) |
| 2 | Identical | Identical | Nothing — VarianceConstraints inert, no CP.2 trigger assumed (early Strength week, moderate stress) |
| 3-4 | Identical | Identical | Nothing, same reasoning |
| **Peak Strength week** (real week-4-of-5 Family A pattern, RIR1, `lowerBodyLoad = .high`) | `Stimulus.loading` repaired `.heavy→.moderate` if the baseline ever carried `.heavy` (real production baseline is `.moderate` already, per `functionalFitnessParameterCandidates` — so in the REAL default configuration, this repair may never even trigger, since the configured `loading` is already `.moderate`, below the `.high` threshold the repair reacts to) — **concretely: no visible change either way** | Same | CP.2 semantic-only adaptation (§O), invisible regardless |
| 5-8 (new 4-week `ProgramDefinition`) | Same generator call, same fixed Stimulus/format → identical resolved exercises (same candidate pool, same deterministic pick) | Same | Nothing — a fresh `ProgramDefinition` reuses the exact same construction, there is no generation-time state carried or varied between `ProgramDefinition` instances |

**`functionalFitnessFocusedMix` FF component (4 sessions/week, no sibling component — CP.2's cross-modality check can never fire, only same-week complementarity can):**

| Week | Sessions A-D | What changed |
|---|---|---|
| 1 | All 4: 12 Back Squat / 8 Pull-up / 200m Row (or whichever exercises deterministically resolve) — same-week complementarity MAY nudge sessions B/C/D's `intensity`/`targetDurationDomain`/`systemicDemand`/`skillDemand` if session A already "covers" an objective per `AdaptationObjectiveStimulusMapping.objectivesServed` — but per §O, this nudge is invisible in the concrete prescription regardless | Categorical-only variation among sessions, invisible to the athlete |
| 2-8 | Identical shape every week | Nothing structural changes across the full 8 weeks |

**Conclusion, stated plainly**: over 8 real weeks, both mixes' FF programming is, from the athlete's perspective, the same workout repeated 8-32 times (depending on frequency), with zero visible variation, zero visible progression, and zero visible response to concurrent training load — even though a real, correctly-functioning adaptation engine (CP.2) is running underneath it the entire time.

---

## S. Complete gap inventory

| Gap | Severity | Reach | Type | Dependencies |
|---|---|---|---|---|
| CP.2 adaptation has no concrete effect (§O) | **Blocker** | Every generated FF session | Architecture | None — smallest possible fix is extending the target rule's inputs |
| No true longitudinal progression of any kind | High | Every generated FF session | Product/Architecture | Result-feedback loop (below) |
| Result feedback loop entirely absent (§I) | High | Every generated FF session | Data/Architecture | Adherence already ships (FF.E1); needs a real consumer |
| `AdaptationObjective` produces no athlete-visible difference (§E) | High | Every real FF component | Product | Same fix as CP.2 gap — a concrete consumer of the nudged fields |
| Numeric load absent | High | Every session with a squatLoaded slot | Data/Product | A validated calibration formula — genuinely blocked, not just unbuilt |
| Movement diversity dormant (§G) | Medium | Every generated session (only 3 of 15 functions ever used) | Architecture | Generator authoring decision only — smallest real lever available |
| Assault Bike unprescribed (§F/§C) | Medium | ~1 in 5 monostructural resolutions | Product | Already correctly deferred, not a regression |
| No time cap ever set | Medium | Every session | Product | Trivial to set; currently just unauthored |
| Skill system absent (§L) | Medium | Every session (dormant field) | Data/Architecture | New catalog relationships — genuinely larger investment |
| Format diversity dormant (§H) | Low | N/A (never generated) | Product | Low value until something drives WHICH format and WHY |
| Benchmark/retest dormant (§N) | Low | N/A (never tagged) | Product/UX | A benchmark-tagging UI flow |
| `VarianceConstraints` activation risk for movement-function/modality (§M) | Low (dormant, but a real latent risk) | Would be every session, if ever activated | Architecture | Slot-regeneration-per-week design, not yet solved |
| Calories never prescribed | Low | Never currently relevant | Product | N/A — correctly deferred |

---

## T. Ranked Top 5 next stages

**1. CP.3 — Concrete Concurrent-Programming Effect (name provisional).** Problem solved: closes §O's semantic-vs-concrete gap by extending `FunctionalFitnessMovementTargetRule` (or a sibling mechanism) to actually consume the CP.2-adapted fields it currently ignores — e.g. reducing a rep/distance target, or nudging movement-function choice, when CP.2 has already determined the athlete's surrounding training is under real stress. Why now: it makes an already-built, already-tested, already-shipped system (CP.2/CP.2R) finally do something an athlete can perceive; the smallest possible next step given everything else depends on this mattering at all. Athlete-visible benefit: a Functional Fitness session genuinely feels lighter/shorter/different on a real heavy Strength week. Architectural benefit: makes the whole Concurrent Programming investment retroactively justified. Dependencies: none beyond what's already shipped. Risks: must not re-open CP.2/CP.2R's own closed semantics — extend the TARGET rule's inputs, never the Stimulus-adaptation mechanism itself. Scope: small — one function signature extension plus a coarse, categorical dose-reduction rule. Does NOT solve: numeric load, skill, longitudinal progression across weeks.
   - Scores: athlete value 4, longitudinal-programming value 3, architectural leverage 5, implementation confidence 4, prerequisite readiness 5. Complexity 2, semantic risk 2, fake-precision risk 1, regression risk 2.

**2. FF.RF1 — Result Feedback Foundation.** Problem: closes §I's total absence of a feedback loop by having at least ONE real consumer read `adherence`/`scoreValue` history to inform something (even just "the last N sessions were consistently `.asPrescribed` → eligible for a coarse dose bump"). Why now: `PrescriptionAdherence` already ships (FF.E1) with no consumer — a real, disclosed dangling capability. Athlete-visible benefit: the first real sense that performance matters. Architectural benefit: proves the FF.L1/FF.E1 truth chain is actually load-bearing, not just historically accurate. Dependencies: a small derived per-session history read (mirrors `FunctionalFitnessExposureHistoryBuilder`'s own shape). Risks: must not invent progression precision the domain can't support (reps-only, categorical). Scope: small-medium. Does NOT solve: numeric load, skill, CP.2 concreteness.
   - Scores: athlete value 4, longitudinal value 5, architectural leverage 4, implementation confidence 4, prerequisite readiness 4. Complexity 3, semantic risk 2, fake-precision risk 2, regression risk 2.

**3. FF.M1 — Movement Diversity Expansion.** Problem: closes §G's dormant-diversity gap by letting the generator draw from more than 3 of 15 `MovementFunction` cases (hinge, press, gymnastics-push at minimum — all real, catalog-ready today). Why now: pure generator-authoring work, zero new architecture, immediately visible. Athlete-visible benefit: real workout variety across `ProgramDefinition` regenerations. Architectural benefit: proves the slot/target-rule machinery generalizes beyond the 3 cases it was built and tested against. Dependencies: `FunctionalFitnessMovementTargetRule` needs dose-class entries for the new functions (small, same shape as existing 3). Risks: low, but must resist adding more functions than the target rule can honestly dose. Scope: small-medium. Does NOT solve: progression, numeric load, CP.2 concreteness.
   - Scores: athlete value 4, longitudinal value 2, architectural leverage 3, implementation confidence 5, prerequisite readiness 5. Complexity 2, semantic risk 1, fake-precision risk 1, regression risk 1.

**4. FF.PROG1 — Structural Reps Progression.** Problem: a first, honest, coarse progression axis (reps/volume — the axis with the shortest honest path per §J) — e.g., N consecutive `.asPrescribed` sessions at the current rep target → eligible for one categorical step up. Why now: FF.P1 already gives it a concrete value to progress; FF.E1 already gives it a real confirmation signal. Athlete-visible benefit: the first real sense of "this program is getting harder because I'm ready." Architectural benefit: the first real progression axis in FF, proving the whole chain end-to-end. Dependencies: FF.RF1 (a real feedback loop) as a strict prerequisite — cannot honestly progress without first proving performance data reaches anywhere. Risks: real risk of building "fake progression" if rushed ahead of FF.RF1; must stay coarse/categorical. Scope: medium. Does NOT solve: numeric load, skill, CP.2 concreteness.
   - Scores: athlete value 5, longitudinal value 5, architectural leverage 4, implementation confidence 3 (blocked on #2), prerequisite readiness 2 (blocked). Complexity 3, semantic risk 3, fake-precision risk 3, regression risk 2.

**5. FF.LOAD1 — Numeric Load Anchor Decision.** Problem: closes §K's numeric-load gap via an explicit, product-authorized formula (not invented here). Why now: the single most obvious remaining nil field, high real frequency. Athlete-visible benefit: high, if solved honestly. Architectural benefit: unlocks a genuine second progression axis. Dependencies: a real product decision on a validated anchor/formula — the actual blocker, not an implementation task. Risks: the highest fake-precision risk of any candidate on this list if rushed; CLAUDE.md rule 10 directly forbids guessing the formula. Scope: large, and gated on a decision this audit cannot make. Does NOT solve: skill, movement diversity, CP.2 concreteness, or progression for the 2 of 3 movements that never carry load at all.
   - Scores: athlete value 5, longitudinal value 3, architectural leverage 2, implementation confidence 1 (blocked on an unresolved product decision), prerequisite readiness 1. Complexity 5, semantic risk 4, fake-precision risk 5, regression risk 2.

---

## U. ONE recommended next stage

**CP.3 — Concrete Concurrent-Programming Effect.**

---

## V. Why the other four lose

FF.RF1 (result feedback) and FF.M1 (movement diversity) are both real, valuable, low-risk next steps — but neither is THE highest-leverage one, because both operate downstream of a system (CP.2) that currently produces zero visible effect; building more feedback or more diversity on top of an invisible adaptation layer doesn't make that layer visible, it just adds more machinery around it. FF.PROG1 (reps progression) is explicitly gated on FF.RF1 existing first — picking it now would mean building progression on a feedback loop that doesn't exist yet, exactly the "fake progression" risk the user's own guardrails forbid. **FF.LOAD1 (numeric load) loses for a specific, evidence-based reason, not because it's hard: this audit found the real blocker isn't architecture or data plumbing — it's a genuinely unresolved product decision (a validated %1RM-or-equivalent formula) that no amount of implementation work can substitute for, and forcing an answer now would violate CLAUDE.md rule 10 directly.** Numeric load is not "ready and more important" than the alternatives — it is the LEAST ready of the five, scoring lowest on implementation confidence and prerequisite readiness, and highest on fake-precision risk, of any candidate audited. CP.3 wins because it is the only candidate that (a) requires no new product decision, (b) has zero prerequisite dependency, (c) makes an already-completed, already-tested, already-shipped investment (CP.2/CP.2R, five stages of real work) actually matter for the first time, and (d) directly satisfies the stated selection criterion — highest increase in TrainingOS's ability to produce COHERENT programming OVER TIME — because "coherent" requires the concurrent-adaptation layer to actually touch the concrete prescription, which today it structurally cannot.

---

## W. Recommended dependency sequence

```
FF.P1 (closed)
  → CP.3 — Concrete Concurrent-Programming Effect
      → FF.M1 — Movement Diversity Expansion (independent of CP.3, can run in parallel;
                becomes MORE valuable after CP.3 since a richer movement pool gives
                CP.3's own concrete-adaptation rule more real options to nudge toward)
      → FF.RF1 — Result Feedback Foundation (independent of CP.3, can run in parallel or after)
          → FF.PROG1 — Structural Reps Progression (strictly requires FF.RF1)
  → FF.LOAD1 — Numeric Load (requires an explicit product decision, sequenced last —
               not because it's technically dependent on the others, but because the
               product decision it needs benefits from having a real feedback loop
               (FF.RF1) already in place to validate against)
  → Skill system / catalog-variant work (large, independent, no urgency established by this audit)
  → Benchmark/retest UI (independent, gated on wanting benchmark-tagged content at all)
```

CP.3 and FF.M1 make FF.RF1/FF.PROG1 more valuable (richer, more responsive workouts to have feedback ABOUT), but do not block them technically — the sequence above reflects value-maximization, not a hard technical dependency chain beyond FF.PROG1→FF.RF1.

---

## X. Contradictions found in closed stages

**None that require reopening a closed stage.** One real, disclosed-but-not-fixed architectural risk was reconfirmed (§M — `VarianceConstraints` activation for movement-function/modality would face a CP.2R-class staleness risk against the fixed slot graph) — this was already flagged as unresolved in the FF.L1/CP.2 design docs and remains correctly unresolved, not contradicted; no closed stage's own stated invariant is violated by this finding, since none of them ever claimed `VarianceConstraints` was safe to activate. CP.2/CP.2R's own closed scope explicitly never claimed the adaptation would be athlete-visible — §O's finding is a genuine gap in downstream consumption, not a broken promise from either closed stage.

---

## Y. Final statement

**THE RECOMMENDED NEXT FUNCTIONAL FITNESS STAGE IS: CP.3 — Concrete Concurrent-Programming Effect**

---

## STOP

Design/audit only. Nothing implemented, committed, or pushed. All five closed stages (CP.2, CP.2R, FF.L1, FF.E1, FF.P1) remain closed and unmodified; none of the four existing design docs was edited.
