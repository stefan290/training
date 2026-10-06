# CP.3 Design Lock + Global Training Environment Audit

**Status: DESIGN/AUDIT ONLY. Nothing implemented, committed, or pushed.** HEAD: `ac76e1a24bb868583798f144fa65bfd0ea7c1a1d`. Closed stages, unmodified: CP.2 (`bca43e2`), CP.2R (`2f02c60`), FF.L1 (`ae5898c`), FF.E1 (`a3c3d0b`), FF.P1 (`ac76e1a`). The four prior design docs and `POST_FFP1_FUNCTIONAL_FITNESS_GAP_AUDIT.md` are historical evidence, not authority — every claim below is re-derived from the real code at HEAD, cited by file:line, or explicitly marked as reasoned inference from confirmed facts.

---

## A. Executive conclusion

Two independent findings, both empirically decisive:

1. **CP.3's core premise needs one correction before design, not after.** CP.2's cross-modality repair (`adjustForCrossModalityConstraint`) can only fire when the FF candidate's own mapped `lowerBodyLoad`/`impactLoading` is *already* `.high` — but the one real FF construction site (`LongTermPlanner.functionalFitnessParameterCandidates`) always sets `loading: .moderate`, which maps to `LoadLevel.moderate`, never `.high`. **The cross-modality repair path is real, tested, and currently unreachable in production with today's real baseline** — not merely invisible, structurally unreachable given real inputs. Same-week complementarity (`adjustForSameWeekComplementarity`) has no such threshold gate and IS reachable. CP.3 must be designed to make a real, honest concrete difference for the reachable mechanism (same-week complementarity, via `intensity`/`targetDurationDomain`/`systemicDemand`/`skillDemand`) and must not silently assume the cross-modality path routinely fires.
2. **Training Environment support is MISSING at the consumption layer, but the exercise-metadata foundation for it already exists, fully populated, completely unused.** `Exercise.requiredEquipment: [EquipmentRequirement]` (Stage 10C.1) is a real, multi-value, capability-based enum — populated for essentially every real seeded exercise, including a distinct `.pullUpBar` case for Pull-up/Toes-to-Bar (directly disproving the "Pull-up = bodyweight = no equipment" category error the audit was asked to test for) — with **zero real consumers anywhere in the codebase.** `EquipmentProfile`/`UserProfile.equipmentIncrements` are a different concept entirely (load-rounding math, not availability). No user-facing equipment configuration exists. This is the rare case where content-authoring is already done and only the eligibility filter + a user profile are missing.

Given both findings: **CP.3 remains safe to design and does not depend on Training Environment work** (§BB proves this precisely), but the recommended next TrainingOS stage is **not CP.3** — it is the equipment stage, because an existing modality (Hypertrophy/Strength/Powerlifting, and FF itself) can today prescribe an exercise the athlete cannot actually perform, with no correct resolution path, which is a correctness gap outranking CP.3's cosmetic-adaptation gap.

---

## PART I — CP.3 Design Lock

## B. CP.3 exact mutation audit

| Field | Owner (file:line) | Trigger | Real reachability | Direction | Reachable in muscleGainVariedMix? | Reachable in functionalFitnessFocusedMix? | Multiple per decision? | Precedence |
|---|---|---|---|---|---|---|---|---|
| `loading` | `CrossModalityStimulusRepair.minimalRepair`, called from `FunctionalFitnessDecisionEngine.adjustForCrossModalityConstraint` (`:110-137`) | `protectedSiblingStressProfilesThisWeek` non-empty AND `InterferenceAvoidanceRule.conservativeDefault` triggers (both sides' `lowerBodyLoad`/`impactLoading` `>= .high`) | **Real code path, but UNREACHABLE given the real configured baseline** (`loading: .moderate` never maps to `.high`, per §A.1) | One step down `LoadingClassification.allCases` (e.g. `.heavy→.moderate`) — never up | Has a `.primary` sibling (Strength) but the trigger condition never fires with the real baseline | No sibling at all (FF is the only, and is itself `.primary`) — this check can never even attempt to fire | No — `adaptationPhase` returns on first match, so `loading` and any Phase-2 field are mutually exclusive per call | Checked FIRST in `adaptationPhase` |
| `intensity` | `AdaptationObjectiveStimulusMapping.nudge(_:toward: .power)`, called from `adjustForSameWeekComplementarity` (`:146-187`) | Only reached if the cross-modality check (above) did NOT fire; requires `.power` in `componentAdaptationObjectives` and under-covered this week | **Real, reachable** in any mix with `.power` and >1 real FF session/week | Toward `.high` only (one-way nudge; `nudge` returns nil if already `.high`) | Yes — FF has `.power` | Yes — FF has `.power` | No — same mutual-exclusion as above | Checked SECOND, only one field mutates per call |
| `targetDurationDomain` | `AdaptationObjectiveStimulusMapping.nudge(_:toward: .aerobicCapacity/.anaerobicCapacity)` | Same gate as above; requires `.aerobicCapacity` (→`.long`) or `.anaerobicCapacity` (→`.short`) under-covered | Real, reachable | Toward `.long` OR `.short` depending on which objective is under-covered (never toward `.medium`, the real baseline) | Yes (`.aerobicCapacity` present) | Yes (`.aerobicCapacity`, `.anaerobicCapacity` both present) | No | Same |
| `systemicDemand` | `nudge(_:toward: .workCapacity)` | Same gate; requires `.workCapacity` under-covered | Real, reachable | Toward `.high` only | Yes | Yes | No | Same |
| `skillDemand` | `nudge(_:toward: .skillAcquisition)` | Same gate; requires `.skillAcquisition` under-covered | Real, reachable **as a Stimulus mutation**, but see §I — has zero downstream consumer anywhere (confirmed: `FunctionalFitnessStressProfileMapper.map` has no `skillDemand` input at all, and `FunctionalFitnessMovementTargetRule.resolve`'s signature never accepts it) | Toward `.high` only | No (`functionalFitnessFocusedMix` has `.skillAcquisition`, `muscleGainVariedMix` does not) | Yes | No | Same |

**Composition semantics, confirmed by direct trace:** `decideWithIntent` calls `adaptationPhase` exactly once per `materializeWeek` per-slot iteration; it returns on the FIRST matching check (`adjustForCrossModalityConstraint` then `adjustForSameWeekComplementarity`), so **AT MOST ONE field ever changes per single decision.** Across the 2-4 real sessions a real FF component materializes in one week, EACH session gets its own independent decision — so different sessions in the same week CAN end up with different single-field changes, but no single session's FINAL Stimulus ever differs from INTENDED in more than one field. **This resolves §15 (multiple simultaneous FINAL changes) definitively: composition across fields within one decision is structurally impossible, not merely rare — CP.3 needs no stacking/priority-ordering logic for the within-one-session case, only (optionally) a per-session independent resolution, which the architecture already provides.**

## C. CP.3 stimulus semantics (real repository meaning, from `FunctionalFitnessStressProfileMapper` — the one real place these fields get a concrete meaning today)

- **`.loading`**: maps to `lowerBodyLoad`/`upperBodyLoad`, gated by which `movementFunctions` are present (`FunctionalFitnessStressProfileMapper.swift:14-22`). Real meaning: **how much the movement PATTERN itself loads the body** — a categorical proxy for external/movement resistance, not overall workout loading and not merely "heavy vs light."
- **`.intensity`**: maps to `overallIntensity` AND `metabolicDemand` identically (`:19,31` — "metabolic demand mirrors overall intensity, this pass has no independent signal to distinguish them"). Real meaning: **how metabolically/cardiovascularly hard the effort is** — closer to "how hard are you working" than "how heavy."
- **`.systemicDemand`**: maps to `systemicDemand` AND `recoveryDemand` identically (`:35` — "recovery demand mirrors systemic demand, same reasoning"). Real meaning: **total-body cost/recovery cost of the session as a whole**, independent of any single movement's own loading.
- **`.targetDurationDomain`**: maps directly to `durationClassification` (`:32`). Real meaning: **how long the block is intended to take** (short <5min / medium 5-15min / long >15min, per `Stimulus.swift:7-11`'s own doc comment).
- **`.skillDemand`**: **has no mapping anywhere in `FunctionalFitnessStressProfileMapper` at all** — confirmed by direct read, the mapper function has no `skillDemand` parameter or reference in its body. Its only real repository meaning today is "a value CP.2's own same-week complementarity check can nudge," with no other real consumer.

## D. CP.3 concrete lever matrix

| Lever | Availability |
|---|---|
| Exercise identity | AVAILABLE NOW (Stage D resolution exists) but changing it for CP.3 would be a category error — see §M, identity is FF.P1/variance's concern, not CP.2's |
| movementFunction/modality | AVAILABLE NOW structurally, but CP.2 never mutates these fields (confirmed §B) — not a real lever for THIS stage |
| reps | AVAILABLE NOW (FF.P1's own field) |
| distance | AVAILABLE NOW (FF.P1's own field) |
| calories | REPRESENTABLE BUT NOT HONESTLY USABLE (never populated by FF.P1 either, no new information to adapt) |
| numeric load | NOT AVAILABLE (confirmed by the Prescription Depth audit, unchanged at HEAD) |
| rounds | AVAILABLE NOW (`WorkoutFormat.roundsForTime(rounds:, _)`'s own `Int`) — but see §H, changing it risks workout-identity violation |
| time cap | AVAILABLE NOW structurally (`capSeconds: Int?`), never set in real production (`nil`) — introducing one for the first time via CP.3 would be inventing new information, not adapting existing information |
| format | AVAILABLE NOW as a type, but changing format changes workout identity entirely — rejected outright, no repository evidence supports this as an adaptation lever |
| work/rest interval | NOT AVAILABLE for `.roundsForTime` (the format has no such fields) |
| movement count/order | AVAILABLE NOW structurally, but no honest Stimulus-to-count/order mapping exists |

Preserving workout identity: only reps/distance changes preserve identity outright (same movements, same format, same round count — just a different per-round dose). Rounds changes are borderline (same movements/format, different total volume — discussed in §H). Everything else either doesn't preserve identity or isn't honestly available.

## E. Loading decision

**Loading cannot yet be concretized — and moreover, per §B, the mechanism that would produce a loading change is currently unreachable in real production anyway.** No concrete lever honestly represents "reduce movement loading" today: `loadKilograms` is unavailable (§D, prior audit); `movementFunctions`/`modality` changes would be an exercise-selection decision CP.2 has no authority over; reps/distance do not represent loading (a rep count and a load are different physical quantities — reducing reps does not mean "lighter," it means "less volume"). **Answer: B — no, not until numeric load exists**, and this is now doubly true since the trigger is also unreachable. CP.3 must not pretend loading concretizes; document it as explicitly NON-CONCRETIZABLE alongside skillDemand.

## F. Intensity decision

Tested each candidate mapping against the real domain meaning (§C: intensity = "how hard/metabolically demanding," not movement loading):
- Reps up/down: **REJECTED.** More reps of the same movement at the same (unprescribed) load is not the same as "harder effort" — an athlete could do more reps easily at a lighter self-selected load. Reps and intensity are orthogonal in this domain (confirmed: `FunctionalFitnessMovementTargetRule` and `AdaptationObjectiveStimulusMapping` never share a field).
- Tighter time cap: **SEMANTICALLY DEFENSIBLE, but requires introducing a NEW value** (`capSeconds` is `nil` in real production) — this isn't adapting an existing prescription, it's authoring a brand-new constraint the neutral baseline never had. Locking this in would blur "FF.P1 neutral baseline" vs. "CP.3 tactical adaptation" (§M) in a way that's hard to reverse cleanly on the next session.
- Format change: rejected (§D).
- **Honest answer: intensity, like loading, currently has no concrete lever that survives scrutiny without either introducing new information (a cap that didn't exist) or conflating two different physical quantities (reps ≠ effort).** Lock intensity as NON-CONCRETIZABLE for the smallest honest CP.3 (§W), same as loading — a genuinely conservative but correct finding.

## G. SystemicDemand decision

Tested: total reps (sum across movements) — **SEMANTICALLY DEFENSIBLE**: `systemicDemand` real meaning is "total-body cost of the session," and total prescribed volume (reps+distance combined) is the one concrete quantity FF.P1 already produces that plausibly tracks whole-session cost. Total distance — same reasoning, defensible as a component of the same total-volume idea. Round count — **WEAK/INDIRECT**: changing round count changes total volume too, but also changes workout IDENTITY (a "5 rounds" workout becoming "4 rounds" is a different named workout in the athlete's own history/memory, unlike a same-round different-rep-count workout) — reject as the primary lever, though see §H for whether it's acceptable as a LAST-resort bounded case. Movement count: NOT AVAILABLE (FF.P1 doesn't change which movements exist, only their targets). Work/rest: NOT AVAILABLE for `.roundsForTime`. **Chosen concrete lever for systemicDemand: a bounded reduction in TOTAL prescribed reps/distance across the three movements when `systemicDemand` nudges toward `.high`... but wait — `.high` is an INCREASE in demand, and CP.2's same-week complementarity only ever nudges UPWARD (toward `.high`, never down, confirmed §B).** This is a critical, correct finding: the only real systemicDemand mutation CP.2 can produce is an INCREASE (toward `.workCapacity`), never a decrease — so CP.3's systemicDemand-driven lever must INCREASE total volume, never decrease it, when this specific nudge fires. This must be small and bounded (§Y absurdity tests) — e.g. one additional round-equivalent unit of volume on one movement, not a doubling.

## H. TargetDurationDomain decision

Real fixed production format is `.roundsForTime(rounds: 5, capSeconds: nil)`. `targetDurationDomain` real meaning (§C) is "how long the block should take." Tested: **rounds** is the only concrete lever that plausibly maps to duration for this format (more rounds ≈ longer block, at a fixed per-round dose) — **SEMANTICALLY DEFENSIBLE, with a real caveat**: since `capSeconds` is always `nil`, there's no actual time constraint to honor — "duration" for this format is really "total round-implied volume," which overlaps heavily with §G's systemicDemand lever (both would end up changing round count/total volume). **This is the decisive finding for §M: `targetDurationDomain`'s only honest concrete lever (rounds) and `systemicDemand`'s only honest concrete lever (total volume) converge on the SAME underlying quantity** — meaning CP.3 should not design two independent mechanisms that could each independently mutate round-derived volume (a real risk of the absurdity-test "stacking" scenario, §Y). **Recommend treating rounds-adjustment as the SINGLE shared concrete mechanism serving BOTH `targetDurationDomain`-toward-`.short`/`.long` and `systemicDemand`-toward-`.high`, never two separate mechanisms that could compound.** Given CP.2 only ever moves `targetDurationDomain` toward `.long` OR `.short` (one-way per nudge, never both, and never toward the real baseline `.medium`), and only ever moves `systemicDemand` toward `.high`: a `.long`/`.short` nudge maps to rounds+1/rounds-1 respectively (bounded, ±1 only — never more, per the absurdity tests in §Y), and the `.workCapacity`→`.high` nudge (from §G) ALSO maps to rounds+1 — meaning these two are actually the same lever, and if BOTH somehow fired in the same session (they can't per §B's mutual exclusion, but could across a week's two sessions) they'd still each independently be a single ±1 round adjustment, never compounding within one session.

## I. SkillDemand decision

**Re-verified precisely at current HEAD: `skillDemand` has zero downstream effect anywhere** — not in `FunctionalFitnessStressProfileMapper` (no parameter references it, confirmed §C), not in `FunctionalFitnessMovementTargetRule.resolve` (signature is `format/modality/movementFunctions/exercise`, no `skillDemand` parameter at all), not in Stage-E validation (the Prescription Depth audit already confirmed `matchesSkill` is hardcoded `true`). **LOCKED: skillDemand is NON-CONCRETIZABLE in CP.3.** Do not invent a skill-progression mechanism to give it meaning — that would violate the "no fake precision" guardrail and duplicate the already-deferred skill-system work.

## J. Concurrent adaptation vs. progression boundary

**Precise distinction, locked:** concurrent adaptation (CP.2/CP.3) answers "given what ELSE is real and already happening THIS WEEK (sibling stress, same-week sibling FF sessions), what should THIS session's stimulus be, right now" — a purely lateral, same-week, stateless-across-weeks decision. Progression (FF.PROG1, not this stage) answers "given what happened in PAST weeks (performance, adherence, exposure), what should change GOING FORWARD" — a longitudinal, cross-week, history-dependent decision. CP.3's proposed rounds-adjustment mechanism reads ONLY same-week inputs (`protectedSiblingStressProfilesThisWeek`, `currentWeekContext`) — it never reads `exposureHistory`'s performance content (only the already-inert Phase-1 variance checks do, and only for `Stimulus`-field repetition, never performance) — confirming CP.3 as designed cannot accidentally become a progression engine, because it has no access to any cross-week signal at all.

## K. Intended/Final preservation

No change to FF.L1's model. `FunctionalFitnessPrescription.intendedStimulus`/`.stimulus` remain exactly the two `Stimulus`-level snapshots FF.L1 established. CP.3 introduces a THIRD, later value (the concrete reps/distance/rounds actually materialized) that is derived from FINAL, never reconstructs or overwrites INTENDED, and — per §W — requires no new `Stimulus`-level field at all, only an extension of the already-real `FunctionalFitnessMovementTargetRule`/materializer call site.

## L. CP.3 concrete-prescription ownership

Traced the real call order in `FunctionalFitnessMaterializer.materializeWeek` precisely (`:95` `decideWithIntent` returns FINAL → `:131-132` Stage D resolves `resolvedExercise` → `:143-146` `FunctionalFitnessMovementTargetRule.resolve` is called, using `exerciseSlot.allowedModalities`/`.allowedMovementFunctions`/`resolvedExercise`, but **NOT** `decision.finalStimulus` at all today). **Option C from the user's own list is the proven-correct answer: FINAL → Exercise resolution → FF.P1 baseline → CP.3 adaptation** — because this is the exact real, already-existing call order; CP.3 only needs to extend the ALREADY-EXISTING call site (add `finalStimulus`-derived parameters to the resolver call, or apply one additional bounded adjustment to `generatedTarget` immediately after it's computed), never introduce a new pass, a new call site, or "generate then patch" pattern. No post-scheduler regeneration, no duplicated table — the existing single call site simply gains one more, still-pure, still-deterministic input.

## M. FF.P1 interaction

**The user's own stated preference (FF.P1 = neutral baseline, CP.3 = tactical adaptation from it) is CONFIRMED correct by the real architecture, not merely assumed.** `FunctionalFitnessMovementTargetRule.resolve` already IS a pure function producing a `Target` value from non-Stimulus-adaptable inputs (format/modality/movementFunctions/exercise) — CP.3's job is to take that `Target` (the neutral baseline) and apply ONE bounded, deterministic adjustment (±1 round-equivalent, only when the specific reachable nudges from §B/§G/§H fire) — this is Option E ("use FF.P1 as the neutral baseline") combined with Option C ("leave targets untouched, alter another structural property" — specifically, alter `rounds`, not `reps`/`distanceMeters` themselves). **CP.3 does NOT modify the FF.P1 target table (12/8/200m stay exactly as locked) — it adjusts how many ROUNDS of that same table apply.** This cleanly avoids Option A/B/D (modify/wrap/supersede the per-movement targets), preserving FF.P1's own closed semantics untouched.

## N. Multi-field composition

Already resolved precisely in §B/§H: within one session's one decision, at most one Stimulus field ever changes (structural guarantee, not a policy CP.3 needs to enforce). Across a week's multiple sessions, each session's own single change is independent — no compounding within a session is possible, and the ONLY real concrete lever this design proposes (±1 round) is shared by both `targetDurationDomain` and `systemicDemand` nudges (§H), so even the "different session picks a different field" case never produces more than a single ±1 round adjustment per session. **No stacking/priority-ordering mechanism needs to be built — the architecture already prevents the concern.**

## O. Same-week FF complementarity → concrete

For `functionalFitnessFocusedMix` (no sibling, only same-week complementarity reachable, §B): today, complementarity changes only `intensity`/`targetDurationDomain`/`systemicDemand`/`skillDemand` — all four currently invisible per §E/§F/§I/§C-analysis except `targetDurationDomain`/`systemicDemand`, which §H shows share one concrete lever (±1 round). **Concretely: FF-A (materialized first) might get no adjustment (nothing under-covered yet); FF-B (materialized second, sees FF-A's real recorded stimulus via `CurrentWeekFunctionalFitnessProgrammingContext`) might get nudged toward `.aerobicCapacity` (→`targetDurationDomain: .long`) if FF-A already covered `.power`/`.workCapacity` — under CP.3, this becomes FF-B running ONE additional round (6 instead of 5) rather than an invisible field change.** This is the ONLY mechanism this audit found that gives `functionalFitnessFocusedMix` (which the user correctly flagged as having no cross-modality sibling) a genuine, athlete-visible, non-arbitrary same-week difference between its sessions.

## P. muscleGainVariedMix worked example

Real week: 3 Strength (`.primary`, `[.muscleGain]`), FF ×2 (`.supporting`, `[.workCapacity,.aerobicCapacity,.power]`), Running ×1. Given §A.1's finding, the cross-modality repair is UNREACHABLE with the real baseline — so this week's REAL complementarity is driven entirely by the same-week mechanism (§O), identical in kind to `functionalFitnessFocusedMix`'s case, NOT by cross-modality Strength stress. **This is a real, disclosed correction to the framing implied by the user's own question (§17): CP.3 cannot currently prove cross-modality-driven complementarity for this mix either, because that mechanism is unreachable — the complementarity that IS provable here is the SAME same-week mechanism as §O, not a cross-modality one.** FF-A: 5 rounds, 12 Wall Ball/8 Pull-up/200m Row (no adjustment, nothing under-covered yet). FF-B: sees FF-A covered `.power`(intensity high, if it fired)/`.workCapacity`; if `.aerobicCapacity` remains under-covered, FF-B gets `targetDurationDomain→.long` → 6 rounds: 5 rounds' worth of dose does not change per-round (still 12/8/200m), but the SIXTH round adds 12 more Wall Ball, 8 more Pull-ups, 200 more meters. Total FF-B: 72 Wall Ball, 48 Pull-ups, 1200m Row vs. FF-A's 60/40/1000m — a real, explainable, athlete-visible difference driven by a real locked objective (`.aerobicCapacity` under-coverage), not cosmetic variety.

## Q. functionalFitnessFocusedMix worked example

Real week: 4 sessions (frequency target 4, minimum 3), all FF, 5-objective GPP set, no sibling. FF-A: 5 rounds, baseline (12/8/200m), no adjustment (nothing covered yet). FF-B: sees FF-A's real stimulus; if FF-A's baseline already served `.power` (intensity==`.high`? — real baseline is `.moderate`, so NO, baseline doesn't inherently serve `.power`) — served-so-far starts empty in practice since the real baseline stimulus itself doesn't concretely serve any objective (`.moderate` intensity, `.medium` duration, `.moderate` systemicDemand, `.moderate` skillDemand — none of these equal the `objectivesServed` thresholds of `.high`/`.long`/`.short`, confirmed against `AdaptationObjectiveStimulusMapping.objectivesServed`'s exact conditions). **This is a further, important correction: the real configured FF baseline serves ZERO objectives on its own — meaning EVERY real FF session's FIRST same-week complementarity check should find its own baseline underserving essentially everything, and the very first nudge (whichever objective is checked first in `AdaptationObjective.allCases`' declared order) is likely to fire on session 1 itself, not just session 2+.** This changes the picture from "FF-A never adjusts, FF-B does" (as the user's framing assumes) to "the FIRST session of the week may already adjust, if its own configured baseline objectively serves nothing" — a materially different, more precise finding that must be verified in implementation-time testing (§BG), not asserted definitively here without running the real code (I did not execute this path, only traced it statically — flagging this precisely rather than asserting a specific session-by-session outcome I have not run).

## R. AdaptationObjective interaction

| Objective | Nudge | FINAL field | CP.3 concrete effect |
|---|---|---|---|
| `.workCapacity` | →`systemicDemand: .high` | systemicDemand | **YES** — +1 round (§G/§H) |
| `.aerobicCapacity` | →`targetDurationDomain: .long` | targetDurationDomain | **YES** — +1 round (§H) |
| `.anaerobicCapacity` | →`targetDurationDomain: .short` | targetDurationDomain | **Honest answer: NO clean concrete effect** — shortening duration via ROUNDS would mean −1 round, which combined with §G's "only ever increase, never decrease" finding for systemicDemand creates an asymmetry CP.3 must handle explicitly: a `.short` nudge is a real, intentional REDUCTION, not a mistake, so −1 round (never below a floor, e.g. never below 3 rounds — an absurdity guard, §Y) is the correct, disclosed exception to "only ever increases" |
| `.power` | →`intensity: .high` | intensity | **NO honest concrete effect** — locked NON-CONCRETIZABLE in §F |
| `.skillAcquisition` | →`skillDemand: .high` | skillDemand | **NO honest concrete effect** — locked NON-CONCRETIZABLE in §I |

3 of 5 real objectives gain a genuine concrete effect under this design; 2 (`.power`, `.skillAcquisition`) honestly do not, and CP.3 must say so rather than force one.

## S. Readiness/substitution stale-state analysis

**Traced precisely against the real `SubstituteFunctionalFitnessMovementUseCase.substituteThisSessionOnly` (`:53-60`):** it already recomputes `reps`/`distanceMeters` via the identical `FunctionalFitnessMovementTargetRule.resolve` call — but this call site has access ONLY to `slot`/`format`/`exercise`, **NOT** to `decision.finalStimulus` or any per-session recorded adjustment (like the proposed ±1 round). **This is a REAL, NEW staleness risk CP.3 would introduce if round-count adjustment is stored only as an ephemeral local variable during materialization**: if readiness substitutes an Exercise into an already-CP.3-adjusted 6-round session, the existing recomputation logic (unchanged) would correctly refresh THIS movement's reps/distance for the new Exercise, but has no way to know or preserve "this session is running 6 rounds, not 5" — because round count isn't a per-movement field the substitution use case ever touches or is aware of at all; it lives at the `WorkoutFormat`/session level, which substitution never re-derives. **Resolution options, evaluated:** (1) persist the CP.3-adjusted round count on the real materialized `FunctionalFitnessPrescription.format` itself (the format field already exists and is real per-prescription state, not a new persisted concept — simply store the ADJUSTED `WorkoutFormat.roundsForTime(rounds: 6, ...)` there instead of the template's original 5, exactly mirroring how `stimulus`/`intendedStimulus` are already independent per-prescription snapshots distinct from the template) — **this is the correct answer**, since `format` is already read from `prescription.format` by execution/completed-detail code, not re-derived from the template at substitution time, so storing the adjusted value there is both safe and already-architecturally-consistent. (2) Recompute round count at substitution time by re-deriving same-week context — REJECTED, substitution has no access to `protectedSiblingStressProfilesThisWeek`/`currentWeekContext` (both are `materializeWeek`-local, never persisted, confirmed by `CurrentWeekFunctionalFitnessProgrammingContext`'s own doc comment: "started fresh per call, never persisted"), so this data is gone by substitution time — recomputation is not possible, only preservation of the already-decided value is. **Lock: CP.3's round-count adjustment must be written into the real, already-existing `FunctionalFitnessPrescription.format` field at materialization time (a genuinely different value than the template's own format, exactly analogous to `stimulus` vs. `intendedStimulus`), so it survives substitution untouched, since substitution never reads or rewrites `prescription.format`.**

## T. Authored-target precedence

**LOCKED: NO, CP.3 may not adapt authored targets — confirmed by direct architectural mirroring, no contradicting evidence found.** CP.3's round-count mechanism operates on `WorkoutFormat`/session-level state, not `FunctionalFitnessMovementSlotTemplate.reps`/`.distanceMeters` at all — it is structurally incapable of touching authored per-movement targets, since it doesn't operate on that field. The existing FF.P1 precedence (`slotTemplate.reps ?? generatedTarget.reps`) is completely untouched by this design.

## U. History/immutability

CP.3 runs exactly once, inside `materializeWeek`'s existing per-session loop, at the exact point `decision.finalStimulus` first becomes available and before `WorkoutBlock`/`FunctionalFitnessPrescription` are constructed (`:110-119`) — i.e., strictly during materialization, before athlete execution, exactly the user's own required boundary. No retroactive rewrite is possible because there is no code path that re-runs this logic against an already-materialized Session.

## V. CP.3 validation/persistence

**No new persisted state required.** `FunctionalFitnessPrescription.format: WorkoutFormat` already exists, already `Codable`/`Equatable`, already independently settable per prescription (§S). No Stage-E validation expansion needed: the round-count adjustment is a pure, deterministic function of already-validated inputs (FINAL stimulus, which is itself validated indirectly via existing tests) — a table-driven unit test suite (§BG) is sufficient and consistent with FF.P1's own established precedent (no Stage-E expansion there either).

## W. Smallest honest CP.3 scope

**OPTION 3 (bounded rounds adaptation), narrowly scoped to exactly the two real reachable nudges that concretely justify it (`targetDurationDomain`→`.long`/`.short` and `systemicDemand`→`.high`, which §H proves share one lever) — NOT Option 1/2/4 alone, and explicitly NOT Option 5.** Loading/intensity/skillDemand are locked NON-CONCRETIZABLE (§E/§F/§I) and excluded entirely — CP.3 does not attempt five fields, it truthfully concretizes the two that survive scrutiny, using the one lever (rounds, ±1, bounded, floor at 3) that both share. This is smaller than the user's own Option 3 framing ("reps/distance/rounds bounded adaptation") — reps/distance themselves are NOT touched by CP.3 at all (§M); only rounds is.

## X. 12+ CP.3 concrete before/after examples

All examples use the real production triplet (Wall Ball/Pull-up/Row Erg-family, FF.P1's real 12/8/200m table) at 5 real baseline rounds (60/40/1000m).

1. **Neutral, INTENDED==FINAL** (no CP.2 adaptation fires): 5 rounds — 60 Wall Ball / 40 Pull-up / 1000m Row. No CP.3 change.
2. **Loading changed only** (test-fixture scenario only, per §A.1 — NOT reachable with the real baseline): loading `.heavy→.moderate` — NO CONCRETE CHANGE (§E, locked non-concretizable). Prescription stays 5 rounds, 60/40/1000m.
3. **Intensity changed only**: `.moderate→.high` (toward `.power`) — NO CONCRETE CHANGE (§F, locked non-concretizable). 5 rounds, unchanged.
4. **SystemicDemand changed only**: `.moderate→.high` (toward `.workCapacity`) — CONCRETE CHANGE: 6 rounds — 72/48/1200m.
5. **TargetDurationDomain changed only, toward `.long`**: 6 rounds — 72/48/1200m (same lever as #4).
6. **TargetDurationDomain changed only, toward `.short`**: 4 rounds — 48/32/800m (floor-respecting reduction).
7. **SkillDemand changed only**: `.moderate→.high` — NO CONCRETE CHANGE (§I, locked non-concretizable). 5 rounds, unchanged.
8. **Multiple FINAL fields "changed" (hypothetical, cannot occur in one decision per §B)**: N/A — structurally impossible within one session; shown here only to confirm the guardrail: even if it could, only one lever (rounds) would ever be touched, never compounded.
9. **muscleGainVariedMix FF session 1 (FF-A)**: 5 rounds, 60/40/1000m (baseline, nothing under-covered yet — see §Q's caveat that this assumption needs implementation-time verification).
10. **muscleGainVariedMix FF session 2 (FF-B)**: 6 rounds, 72/48/1200m (worked in §P).
11. **functionalFitnessFocusedMix, 4 same-week sessions**: session pattern depends on real check order (§Q) — illustratively, sessions land on 5/6/5/4 rounds as different objectives become covered/under-covered in turn, never identical for cosmetic reasons — exact sequence requires implementation-time table-driven proof, not asserted definitively here.
12. **Readiness substitution after concrete adaptation**: FF-B (6 rounds, per #10) has its Row Erg substituted to Assault Bike mid-week by readiness — round count (6) is preserved (read from `prescription.format`, per §S's fix), distance target correctly clears to nil for the Assault Bike movement specifically (FF.P1's own existing substitution recomputation, unchanged) — result: 6 rounds, 72 Wall Ball / 48 Pull-up / Assault Bike (no target).
13. **Assault Bike case, no adaptation**: 5 rounds, 60 Wall Ball / 40 Pull-up / Assault Bike (no target) — CP.3 doesn't interact with the Assault Bike exclusion at all (§M — it never touches per-movement targets).

## Y. Absurdity tests

- **Low systemicDemand rule producing a meaningless workout**: rejected structurally — CP.2 only ever nudges `systemicDemand` UP (§B), never down, so no rule exists that could shrink a workout via this field; the only shrink case (§X.6, `.anaerobicCapacity`→`.short`) is bounded by an explicit floor (3 rounds — never below, an explicit, disclosed guard).
- **Multiple reductions stacking into "2 rounds, 4 Pull-ups, 50m Row"**: impossible per §B/§N — at most one ±1 adjustment can ever apply to one session; there is no code path that could apply two reductions to the same session.
- **Duration adaptation accidentally altering loading semantics**: impossible — the rounds lever never touches `Stimulus.loading`, `FunctionalFitnessMovementSlotTemplate`, or the FF.P1 per-movement table at all (§M/§T); it only ever mutates the materialized `WorkoutFormat.roundsForTime`'s own `rounds` integer.
- **Heavy→moderate loading repair reducing reps even though reps don't represent loading**: rejected by design — §E locks loading as producing NO concrete effect at all, so no rep reduction is ever triggered by a loading change.
- **High-intensity nudge increasing total volume, unintentionally increasing systemic demand**: rejected — §F locks intensity as producing NO concrete effect, so an intensity nudge alone never touches rounds; only a genuinely separate `systemicDemand`/`targetDurationDomain` nudge does, and only ever by the same bounded ±1.

## Z. CP.3 future compatibility

- **FF.M1 (movement diversity)**: independent — CP.3 operates on rounds/session-format state, never on which `Exercise`/`MovementFunction` a slot resolves to; FF.M1 can expand reachable functions without any CP.3 conflict.
- **FF.RF1 (result feedback)**: independent — CP.3 reads no performance/result data at all (§J), so a future feedback consumer can be added without touching CP.3's inputs.
- **FF.PROG1 (progression)**: explicitly separate layer, proven by §J's boundary — progression would need to read across weeks; CP.3 structurally cannot, by construction, so the two can never be confused even by a future maintainer.
- **FF.LOAD1 (numeric load)**: independent — CP.3 never touches `loadKilograms` (§D/§M).
- **Skill system**: independent — CP.3 explicitly excludes `skillDemand` (§I); a future skill system would need its own, separate concretization mechanism, not an extension of CP.3.
- **Format expansion**: CP.3's rounds-lever is `.roundsForTime`-specific (mirroring FF.P1's own format gate, §D); a future format-expansion stage would need its own per-format concrete lever design, not inherited from CP.3 automatically.
- **VarianceConstraints activation**: a real, disclosed FUTURE risk — if movement-function/modality variance is ever activated, CP.3's round-count adjustment (keyed only on `WorkoutFormat`, never on `movementFunctions`) remains unaffected/orthogonal, confirmed safe by construction.

---

## PART II — Global Training Environment / Equipment Audit

## AA. Current global equipment architecture

Three genuinely distinct, currently-real "equipment" concepts exist in this codebase, and conflating any two would be a real error:

1. **`Exercise.equipment: String`** (`Exercise.swift:17`) — a loose, single-value "loading family" tag (e.g. `"barbell"`), consumed ONLY by `UserProfile.equipmentIncrements: [String: Double]` to pick a load-ROUNDING increment. Answers "how is this exercise's WEIGHT rounded," never "can the athlete access this exercise."
2. **`Exercise.requiredEquipment: [EquipmentRequirement]`** (`Exercise.swift:53`, `EquipmentRequirement.swift`) — a real, Stage-10C.1, multi-value, capability-based enum (`.barbell`/`.rack`/`.bench`/`.dumbbells`/`.cableStation`/`.machine`/`.pullUpBar`/`.kettlebell`/`.medicineBall`/`.bodyweight`/`.bike`/`.rower`/`.skiErg`) — **fully populated for essentially every real seeded exercise** (38 real assignments confirmed in `ExerciseCatalog.swift`, including Pull-up/Toes-to-Bar → `[.pullUpBar]`, directly answering §32's own challenge: this is NOT a category error, a distinct pull-up-bar requirement already exists separately from "bodyweight"). **Zero real consumers exist anywhere** — confirmed by exhaustive grep: the only references are its own declaration, its own initializer, and its own population in seed data. This is real, correct, complete domain data, entirely dormant.
3. **`EquipmentProfile`/`UserProfile.equipmentIncrements`** — purely numeric load-rounding math (barbell/dumbbell/machine increment + rounding rule), threaded through `StrengthMaterializer` (`:192,209`) exclusively for weight-rounding, never for exercise eligibility.

**Classification: (D) no meaningful environment/availability model exists for the athlete side** — but with an unusual asset: the exact metadata a real environment feature would need to consume (`requiredEquipment`) already exists, is already correct, and is already populated. The gap is entirely at the CONSUMPTION layer (no eligibility filter anywhere, no user-facing configuration anywhere), not the content layer.

## AB. Equipment behavior by every production modality

| Modality | A: prescribes Exercises? | B: can require equipment? | C: eligibility decided where | D: equipment an input today? | E: user can configure? | F: impossible Exercise currently prescribable? | G: substitution can introduce unavailable? | H: readiness preserves validity? | I: rollforward preserves constraint? | J: generation preserves it? |
|---|---|---|---|---|---|---|---|---|---|---|
| Hypertrophy/Strength | Yes | Yes (`requiredEquipment` populated) | `SubstitutionValidator.isValid` (category-based, `ExerciseSlot.allowedTargets`) | **No** | **No** (no real UI found) | **Yes** — nothing prevents it | **Yes** — no equipment check anywhere in `SubstitutionValidator` | **No** — same validator, same gap | N/A (no constraint exists to preserve) | N/A |
| Powerlifting | Yes | Yes | Same mechanism (category-based slots, confirmed `ExerciseSlot`'s own doc comment: never hardcoded to one Exercise) | No | No | **Yes** | Yes | No | N/A | N/A |
| Functional Fitness | Yes | Yes | Same `SubstitutionValidator.isValid`, plus `.equipment == "bike"` special-cased ONLY inside `FunctionalFitnessMovementTargetRule` (for the target, not eligibility) | No | No | **Yes** | Yes (confirmed: Row Erg↔Assault Bike substitution has no equipment gate at all — only FF.P1's own narrow target-recomputation happens to make the CONSEQUENCE honest, eligibility itself is unchecked) | No | N/A | N/A |
| Running/SteadyState | Yes (via `ActivityType`, a coarser real/other-modality-authored choice, not a candidate-pool resolution) | Plausibly (rower/bike/ski-erg-style activities need the machine) | Chosen once at program-configuration time, not resolved via a candidate pool the way FF/Hypertrophy exercises are | No | No | Plausible (e.g. prescribing `.rowing` with no rower) | N/A (no substitution mechanism traced for `ActivityType` itself in this pass) | N/A | N/A | N/A |
| Intervals | Same as SteadyState | Same | Same | No | No | Plausible | N/A | N/A | N/A | N/A |

**No production modality has ANY equipment/environment awareness today.** This is a cross-cutting gap, confirmed identical in shape across every real modality — none privileged, none exempt.

## AC. Current user equipment configurability

**None found.** Exhaustive search of onboarding/settings/profile/plan-setup view code found no UI surface for "what equipment do you have." `UserProfile.equipmentIncrements` defaults to a fixed dictionary (`["barbell": 2.5, "dumbbell": 2.0, "machine": 5.0]`, `UserProfile.swift:31`) and is never user-edited via any UI this audit found reference to — and even if it were, it answers rounding, not availability (§AA).

## AD. `Exercise.equipment` semantic audit

Confirmed via real `ExerciseCatalog.swift` entries: `equipment` is a single, loose string ("barbell", "medicineBall", "bodyweight", "bike", "rower", "skiErg", "none", etc.) — used ONLY by FF.P1's own Assault Bike exclusion (`exercise?.equipment != "bike"`) and by `UserProfile.equipmentIncrements` lookup. It is NOT a completeness claim about what's needed to perform the exercise (e.g. Back Squat's `equipment` is presumably `"barbell"`, but `requiredEquipment` correctly also includes `.rack` — confirmed real entries show `[.barbell, .rack]` and `[.barbell, .rack, .bench]` for real barbell lifts, proving the SEPARATE `requiredEquipment` field already captures the multi-capability truth `equipment: String` alone cannot). **The user's own challenge is confirmed and answered**: "Back Squat = barbell is insufficient if execution also requires plates/rack" is TRUE of `equipment: String` alone, but ALREADY FALSE of `requiredEquipment` — the richer field already exists and already gets this right.

## AE. Compound equipment/capability requirements

**A real `Set<Equipment>`-shaped model already exists and already suffices** — `EquipmentRequirement` is precisely this shape (`[EquipmentRequirement]`, effectively a set of flat capability tags), and real multi-capability exercises already use it correctly (`[.barbell, .rack, .bench]` for Bench Press-family lifts). No facility/resource semantics (ceiling height, floor space, quantities, locations) exist or are needed for a first stage — `EquipmentRequirement`'s own doc comment already explicitly defers these ("never equipment quantities, locations, or environmental constraints... deferred to whenever Home Gym itself is actually scoped"). **No new metadata evolution is needed — the existing `EquipmentRequirement` enum is already the correct abstraction.**

## AF. Proposed Training Environment domain model

`struct TrainingEnvironment { id: UUID; name: String; availableEquipment: Set<EquipmentRequirement>; isDefault: Bool }` — reusing the EXISTING `EquipmentRequirement` enum verbatim, never inventing a parallel taxonomy. **PERSISTED STATE** (a real, user-owned, reusable, named profile — genuinely needs persistence, unlike most of this project's derived-value defaults, because it's explicit user configuration, not a computed fact).

## AG. Environment ownership/inheritance/override semantics

Smallest architecture supporting the user's own stated requirement (default + future session-level override, without redesign later): `UserProfile` (or a new `User`-level relationship) owns `[TrainingEnvironment]` plus one designated default. A `TrainingMixComponent`/`ProgramInstance` inherits the user's current default at materialization time (read, not copied structurally — see §AV for why the concrete resolved Exercise itself is the real historical snapshot, not the environment reference). A future `Session`-level override field (`session.environmentOverride: TrainingEnvironment?`) can be added later, additively, without migrating anything already built in this first stage — confirmed safe because nothing in the proposed first-stage model requires per-Session storage yet.

## AH. Hard eligibility architecture

**Equipment must be a HARD constraint — confirmed this is NOT the same axis as CP.2's `ConstraintEligibility`/`ConstraintPreference` vocabulary, and forcing reuse would be wrong.** CP.2's two-axis vocabulary exists specifically for SAME-WEEK STRESS coordination between real, already-programmed sibling sessions (a soft/hard distinction about tactical timing) — equipment eligibility is a completely different question (can this exercise physically be performed at all, independent of any sibling or week), decided once per candidate-exercise-pool construction, not per-week. **Recommend a small, separate, equipment-specific hard filter** (`candidate.requiredEquipment.isSubset(of: environment.availableEquipment)`) applied at the exact point `SubstitutionValidator.isValid` already runs — an ADDITIONAL, independent condition alongside the existing `allowedTargets`/`allowedMovementFunctions`/`allowedModalities`/`allowedExercises` checks, never a repurposing of CP.2's own two-axis type.

## AI. Generation vs. materialization ownership

**Generation stays user-independent (unchanged architectural discipline, confirmed by `ExerciseSlot`'s own doc comment — a slot is a CATEGORY, "Horizontal Push," never hardcoded to one Exercise, for BOTH Hypertrophy/Powerlifting and Functional Fitness).** Equipment eligibility belongs at CANDIDATE-EXERCISE-POOL CONSTRUCTION / RESOLUTION time — i.e., inside `SubstitutionValidator.isValid` (or an equivalent filter applied to the `candidateExercises`/`strengthCandidateExercises`/`functionalFitnessCandidateExercises` arrays before they reach the materializer) — exactly the same seam FF.P1's own target rule already proved correct for equipment-adjacent logic (the Assault Bike exclusion). This is the SAME seam for every modality, since `SubstitutionValidator.isValid` is already shared infrastructure (`ExerciseSubstitutionEngine.swift`, used by Hypertrophy/Powerlifting/Functional Fitness substitution alike, confirmed by direct read).

## AJ. Source-authority interaction

**Confirmed, decisive: source-authored slots are category-based, never exercise-specific** (`ExerciseSlot.swift`'s own doc comment, "never hard-coded to one Exercise merely to avoid this schema — Stage 3 decision A6"). This means equipment eligibility slots in as ONE MORE candidate-filtering dimension at resolution time, with ZERO source-authority conflict — the source workbook already only specifies a movement-pattern category (e.g. "Horizontal Push"); TrainingOS already resolves that category to a concrete Exercise via a candidate pool + validator. If the environment lacks equipment for every candidate satisfying a category, the correct behavior (mirroring `FunctionalFitnessMaterializer`'s own existing Stage-E discipline, `:175-188`, "never silently create impossible workouts") is: **the block fails materialization with a typed error** (a new case alongside the existing `FunctionalFitnessMaterializationError`/an equivalent for Strength), never a silent unrelated-movement substitution and never a silent ignore.

## AK. Functional Fitness equipment behavior

Real reachable pools (re-verified at current HEAD, unchanged from prior audits): squatLoaded→{Back Squat, Wall Ball, Thruster}; gymnasticsPull→{Pull-up, Toes-to-Bar}; monostructural→{Easy Run, Track Interval Run, Assault Bike, Row Erg, SkiErg}. Real `requiredEquipment` per candidate (confirmed in `ExerciseCatalog.swift`): Back Squat→`[.barbell,.rack]`; Wall Ball→`[.medicineBall]`; Pull-up/Toes-to-Bar→`[.pullUpBar]`; Assault Bike→`[.bike]`; Row Erg→`[.rower]`; SkiErg→`[.skiErg]`. **All real, all provable, all already correct — no gap in the metadata, only in consumption.**

## AL/AM/AN. Hypertrophy/Strength/Powerlifting equipment behavior

Same architectural shape as FF (§AJ) — category-based `ExerciseSlot`s, candidate-pool resolution via the SAME `SubstitutionValidator.isValid`, SAME zero-equipment-awareness gap. **Source-authored main lifts (Powerlifting's competition Squat/Bench/Deadlift) are a genuinely different case, per the user's own §41**: these slots likely have a real, narrow `allowedExercises` (the explicit narrower allow-list `SubstitutionValidator.isValid` checks FIRST and which short-circuits every other dimension, confirmed `:30-32`) rather than a broad category — meaning for a TRUE competition-lift slot, if the required exercise's own equipment is unavailable, this is correctly a HARD program/environment conflict (materialization must fail, or the user must be told this program cannot run in this environment), never a valid substitution opportunity, distinct from an ordinary accessory-category slot where any equipment-compatible candidate is a legitimate substitute.

## AO. Running/endurance equipment behavior

`ActivityType` (`.running`/`.cycling`/`.rowing`/`.skiErg`/`.other`) is chosen once, at program-configuration time — NOT resolved via a candidate-exercise pool the way FF/Hypertrophy movements are (confirmed: no `SubstitutionValidator`-style resolution mechanism was found for `ActivityType` in this pass's scope of files read). This means Running/Interval's real equipment gap is structurally DIFFERENT from FF/Hypertrophy's — it's a configuration-time choice, not a materialization-time resolution, so the correct fix point is different (likely at the SAME planning layer that currently picks `.rowing`/`.cycling` unconditionally, not inside a materializer). Flagged as requiring its own, separate resolution-mechanism design in the equipment stage, not assumed identical to FF/Hypertrophy's fix.

## AP. Substitution equipment safety

**Confirmed, real, current gap: NONE of the three real substitution engines (`SubstituteExerciseUseCase`, `SubstituteFunctionalFitnessMovementUseCase`, `SubstituteActivityUseCase`) check equipment availability** — all three route eligibility through `SubstitutionValidator.isValid`, which (confirmed by direct read, §Part-I context) never references `equipment`/`requiredEquipment` at all. **Lock: a substitute must satisfy BOTH semantic compatibility (existing) AND environment compatibility (new) — this is a single, small, additive change to `SubstitutionValidator.isValid` itself (one more non-empty-dimension check, mirroring its own existing `allowedModalities`/`allowedMovementFunctions` pattern exactly), automatically fixing all three substitution engines at once since they all share this one function.**

## AQ. Readiness equipment safety

Readiness (`ReadinessAdaptationDecisionUseCase`) calls the SAME `substituteThisSessionOnly` mechanisms — fixing `SubstitutionValidator.isValid` once (§AP) automatically closes the readiness gap too, with no separate readiness-specific change needed.

## AR. Tactical lifecycle/environment behavior

Environment selection (once it exists, §AF) must be read fresh at each `rollForward`/materialization call, never baked permanently into the `ProgramDefinition` (which stays user-independent, §AI) — this mirrors exactly how `equipmentProfile`/`candidateExercises` are ALREADY passed in fresh per call via `TacticalMaterializationContext`, not persisted inside the definition. No new lifecycle risk beyond what already exists for the (already-real) candidate-exercise-pool pattern.

## AS. Session override behavior

Design only, not built: a future `Session.environmentOverride: TrainingEnvironment?` field, read instead of the user's default ONLY for that Session's own (re-)materialization — this does not require re-materializing anything already committed; it only matters for a NOT-yet-materialized future session, consistent with the "no retroactive rewrite" principle (§U's equivalent for CP.3 applies identically here).

## AT. Missing/unknown environment semantics

**LOCKED: missing configuration must read as `unknown`, never as "everything available."** Mirrors FF.E1's own exact precedent (`PrescriptionAdherence.unknown`, never silently upgraded to `asPrescribed`) — the identical honest-uncertainty discipline. **UNRESOLVED, flagged explicitly per the user's own instruction**: what a truly "unknown" environment means for candidate-exercise filtering (block everything until configured? assume a conservative minimal/bodyweight-only default? require explicit onboarding before any equipment-dependent modality can materialize?) is a genuine product decision this audit does not resolve.

## AU. Persistence/migration decision

Minimum: the new `TrainingEnvironment` type (§AF) — genuinely new persisted state, justified (§AF). **Confirmed, importantly, LESS new persistence is needed than might be assumed**: no environment SNAPSHOT needs to be stored per-Session, because (§AV) the real resolved `Exercise` is already a permanent, immutable part of the materialized graph.

## AV. Historical truth

**Confirmed directly: a materialized `FunctionalFitnessMovement`/`ExercisePrescription` already stores its resolved `Exercise` as a real, permanent relationship, set once at materialization time and never re-derived from a live environment profile afterward.** If the user edits their environment's `availableEquipment` next month, EVERY already-materialized historical session's `movement.exercise` remains exactly what it was — the environment identity itself doesn't need its own historical snapshot, because the concrete Exercise choice (the only fact that actually matters for history) is already immutable by construction. **This means environment mutability poses zero retroactive-corruption risk without any additional snapshot mechanism — a real, non-obvious simplification confirmed empirically, not assumed.**

## AW. Minimum required UX

A single settings/profile surface: "My Equipment" — a multi-select over the real `EquipmentRequirement` cases, saved as the user's default `TrainingEnvironment`. No polish design here (explicitly out of scope) — this is the minimum surface for the architecture to be usable at all; the user MUST be able to tell TrainingOS what's available, or the whole feature has no real input.

## AX. Equipment metadata evolution

**None needed.** `EquipmentRequirement` already exists, is already correctly populated, and is already the right shape (§AE). This section's answer is simply: the metadata evolution already happened, in a prior stage (10C.1), and was never consumed — the "evolution" this stage needs is a CONSUMER, not a new type.

## AY. 16+ real environment scenarios

1. Full commercial gym → Hypertrophy: all candidates eligible, no behavior change from today.
2. Home gym (barbell+rack+bench) → Strength: cable/machine-only candidates correctly excluded once the filter exists; today, they'd be silently offered.
3. Home gym without cable machine → Hypertrophy cable-category slot: today, silently prescribable; post-fix, filtered out, remaining barbell/dumbbell candidates in the same category chosen instead (a real, valid substitution — the category itself has non-cable alternatives).
4. Minimal equipment → FF: squatLoaded pool narrows to bodyweight-compatible only if any exist (today: none of the 3 real squatLoaded candidates are bodyweight-only — Back Squat/Wall Ball/Thruster all require real equipment; this exposes a REAL content gap the equipment stage would surface, not invent).
5. No rower/SkiErg/bike → FF monostructural: narrows to Easy Run/Track Interval Run only (both real, `equipment: "none"`-adjacent) — a clean, already-supported fallback.
6. Pull-up movement, no pull-up bar: correctly excluded; if no other real `.gymnasticsPull` candidate exists (today, both Pull-up AND Toes-to-Bar require `.pullUpBar`), this exposes the SAME kind of real content gap as #4 — a genuine product finding, not a design flaw.
7. Barbell available, no rack → Back Squat: correctly excluded (`requiredEquipment: [.barbell,.rack]` already distinguishes this).
8. Hotel gym, mixed dumbbell/machine: works using the same additive filter, no special-casing needed.
9. Outdoor environment → running: `ActivityType`-level gap (§AO), needs its own resolution point, not the same fix as candidate-pool filtering.
10. Session switched to Home Gym tomorrow: per §AS, a future session-level override, safely deferred.
11. Readiness substitution under restricted equipment: fixed automatically once `SubstitutionValidator.isValid` gains the equipment dimension (§AQ).
12. FF Row Erg→Assault Bike, environment has Row Erg only: correctly BLOCKED once the filter exists (today: silently allowed, a real live gap).
13. Source-authored Powerlifting main lift unavailable: hard program/environment conflict (§AN), surfaced explicitly, never silently substituted.
14. User edits environment after historical sessions completed: zero retroactive corruption (§AV).
15. Tactical rollforward into next week, same default environment: reads fresh each call (§AR), no staleness.
16. One week, different environments on different days: requires the session-level override (§AS) — correctly deferred past the first stage, not required for it.

## AZ. Equipment absurdity tests

All of the user's listed absurd outcomes are rejected by the design as stated: Pull-up with no pull-up capability (blocked by `requiredEquipment` filter, §AH); Back Squat with barbell-but-no-rack (already distinguished by real, separate `requiredEquipment` entries, §AD); Row Erg prescribed via vague "cardio equipment exists" reasoning (rejected — the design uses exact `EquipmentRequirement` cases, never a coarser category); machine exercise with no matching machine (blocked, same filter); readiness substitution into unavailable equipment (fixed once, centrally, §AQ); source main lift silently replaced (explicitly forbidden, §AJ — hard conflict surfaced instead); editing equipment rewriting history (proven impossible, §AV); FF.M1 generating more unavailable movements (this is exactly why §BC locks FF.M1 behind this stage); missing environment meaning "everything available" (explicitly forbidden, `.unknown` locked, §AT); each modality inventing its own taxonomy (explicitly rejected — one shared `EquipmentRequirement` enum, one shared `SubstitutionValidator.isValid` fix, §AP).

## BA. Proposed global equipment stage

**TE.1 — Training Environment Foundation.** Problem: no production modality can currently guarantee a prescribed Exercise is actually performable in the athlete's real environment, despite the exact metadata (`EquipmentRequirement`) already existing and being correct. Scope: (1) new `TrainingEnvironment` persisted type (§AF); (2) one additive hard-eligibility check inside `SubstitutionValidator.isValid` (§AH/§AP); (3) minimal settings UX (§AW); (4) a typed "cannot materialize in this environment" error path mirroring the existing `FunctionalFitnessMaterializationError` pattern (§AJ) for both FF and Strength/Hypertrophy/Powerlifting candidate-pool exhaustion. Does NOT solve: `ActivityType`-level equipment awareness for Running/Interval (§AO, a separate, smaller follow-on); session-level override (§AS, deferred); soft equipment preference (§52, hard-only for this stage, explicit); facility/quantity/location semantics (already explicitly out of scope per `EquipmentRequirement`'s own doc comment).

---

## PART III — Reprioritize

## BD. Reprioritized stage ranking

| Stage | Athlete value | Correctness value | Longitudinal value | Architectural leverage | Impl. confidence | Prereq. readiness | Complexity | Semantic risk | Fake-precision risk | Migration risk | Regression risk |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **TE.1 — Training Environment** | 4 | **5** | 2 | 4 | 4 | 5 | 2 | 1 | 1 | 2 | 2 |
| CP.3 — Concrete Effect | 3 | 2 | 3 | 4 | 4 | 5 | 2 | 2 | 1 | 1 | 2 |
| FF.M1 — Movement Diversity | 4 | 2 | 2 | 3 | 4 | **2** (locked behind TE.1, §BC) | 2 | 2 | 1 | 1 | 1 |
| FF.RF1 — Result Feedback | 4 | 2 | 5 | 4 | 4 | 4 | 3 | 2 | 2 | 2 | 2 |
| FF.PROG1 — Progression | 5 | 2 | 5 | 4 | 3 | 2 | 3 | 3 | 3 | 2 | 2 |
| FF.LOAD1 — Numeric Load | 5 | 3 | 3 | 2 | 1 | 1 | 5 | 4 | 5 | 2 | 2 |

**Correctness value is the decisive column, per the user's own stated criterion this round ("correctness outranks cosmetic capability").** TE.1 is the only stage scoring the maximum 5 — every production modality today can silently prescribe a genuinely unusable exercise, with no correct resolution path, using metadata that already exists and is already correct. CP.3 scores only 2 on correctness (it fixes an invisibility, not a wrongness — nothing CP.2 does today is incorrect, merely unseen).

## BE. Dependency graph

```
TE.1 — Training Environment Foundation
  BLOCKS: FF.M1 (movement diversity must not expand invalid-prescription risk before environment awareness exists — user's own §54 lock, reconfirmed)
  SHOULD PRECEDE: FF.LOAD1 (a future numeric-load anchor selecting equipment-specific %1RM-style logic would be safer with real equipment context)
  PARALLEL-SAFE: CP.3 (proven independent, §BB), FF.RF1, benchmark/retest, format expansion
  INDEPENDENT: VarianceConstraints activation (orthogonal to equipment)

CP.3 — Concrete Concurrent-Programming Effect
  PARALLEL-SAFE with TE.1 (no shared files, no shared architecture, §BB)
  SHOULD PRECEDE: nothing new discovered this round (unchanged from the prior audit's own W section)

FF.RF1 — Result Feedback Foundation
  PARALLEL-SAFE with TE.1 and CP.3
  BLOCKS: FF.PROG1 (unchanged from the prior audit)

FF.M1 — Movement Diversity Expansion
  BLOCKED BY: TE.1 (locked)

FF.LOAD1 — Numeric Load
  SHOULD FOLLOW: TE.1 (weak dependency — real equipment context makes a future load-anchor decision more honest, not a hard blocker)
  Otherwise unchanged: still blocked on its own unresolved product decision (the percentage formula), independent of TE.1/CP.3

Skill system, VarianceConstraints activation, benchmark/retest UI, format expansion: unchanged, independent, no new dependency discovered this round
```

## BF. ONE recommended actual next stage

**TE.1 — Training Environment Foundation.**

---

## PART IV — Test/design requirements

## BG. CP.3 test plan

Pure-rule tests: rounds-adjustment table for each of the 3 concretizable nudges (`.workCapacity`→+1, `.aerobicCapacity`→+1, `.anaerobicCapacity`→−1, floor-respecting) and the 2 locked-non-concretizable ones (`.power`, `.skillAcquisition`→no change, `loading`→no change since unreachable anyway). INTENDED==FINAL neutral case (no rounds change). Each supported FINAL change individually. Unsupported FINAL fields produce no fabrication (loading/intensity/skillDemand never touch rounds). Real `muscleGainVariedMix` FF-A/FF-B materialization, asserting the exact round counts and resulting total dose. Real `functionalFitnessFocusedMix`, all 4 real sessions, asserting round-count sequence empirically (not asserted definitively in this design, per §Q's own caveat — the test must PROVE the sequence, not assume it). Substitution/readiness stale-state safety: a CP.3-adjusted (6-round) session, substitute a movement, assert round count survives (via `prescription.format`, §S) while the substituted movement's own target still recomputes correctly. Authored-target preservation: a hand-authored template with explicit reps is untouched by a CP.3 rounds adjustment (different field entirely, but assert explicitly to close the question). Assault Bike interaction: a CP.3-adjusted 6-round session with an Assault Bike slot — assert 6 rounds, no distance target on that one movement, real per-movement values on the other two × 6. Full regression: all CP.2 (26/26), CP.2R, FF.L1 (8/8), FF.E1 (12/12), FF.P1 (21/21) tests unchanged; full suite unchanged elsewhere.

## BH. CP.3 file/type plan

`FunctionalFitnessMaterializer.swift` — extend the existing call site (`:143-146`) to also compute a bounded rounds adjustment from `decision.finalStimulus` vs. `decision.intendedStimulus` (or `reasonCode`), and construct `prescription` with an adjusted `WorkoutFormat` when applicable (§S). A new, small, pure function — **recommend a SEPARATE new type, e.g. `FunctionalFitnessConcreteAdaptationRule`, NOT an evolution of `FunctionalFitnessMovementTargetRule` into a broader `FunctionalFitnessConcretePrescriptionRule`** — because the two rules have genuinely different real inputs (FF.P1's rule needs `format`/`modality`/`movementFunctions`/`exercise`; CP.3's rule needs `finalStimulus` vs. `intendedStimulus` and produces a `WorkoutFormat`, not a per-movement `Target`) and different real callers (FF.P1's rule is called once per MOVEMENT slot; CP.3's rule would be called once per SESSION, before the movement loop) — merging them would conflate two genuinely different grains of decision, the same class of error this whole document series has repeatedly found and corrected (e.g. CP.2R's own `loadingRole` lesson). Keep them separate, composable pure functions, consistent with the existing multi-small-pure-function shape this codebase already uses throughout (`FunctionalFitnessStimulusValidator`, `FunctionalFitnessStressProfileMapper`, `CrossModalityStimulusRepair`, `AdaptationObjectiveStimulusMapping`, `FunctionalFitnessMovementTargetRule` — five small pure engines already, a sixth is consistent, not excessive).

## BI. Unresolved product decisions

- Whether the ±1 round bound is the right magnitude, or whether a different small bounded value should be authored (a genuine product decision, not invented here per CLAUDE.md rule 10).
- The exact real session-by-session sequence for `functionalFitnessFocusedMix`'s 4 real sessions (§Q) — requires implementation-time table-driven verification, not asserted here.
- Whether a floor below 3 rounds is the right absurdity guard, or whether a different floor is more appropriate.
- The exact default/legacy semantic for "unknown environment" (§AT) — genuinely unresolved, flagged explicitly.
- Whether TE.1's typed materialization-failure error should be a NEW error type per modality or a single shared cross-modality type — a real design choice for TE.1's own implementation stage, not resolved here.
- Whether Running/Interval's `ActivityType`-level equipment gap (§AO) should be folded into TE.1 or treated as its own immediate follow-on — this audit recommends follow-on (different resolution mechanism, §AO) but does not mandate it.

## BJ. Contradictions found in closed stages

**None.** No closed stage's own stated invariant is violated by any finding in this audit. The unreachability of CP.2's cross-modality repair given the real baseline (§A.1) is a genuinely new empirical finding, not a contradiction of anything CP.2/CP.2R ever claimed — neither stage's design doc asserted the repair fires routinely in production, only that it is correctly implemented and tested against a constructed fixture.

## BK. Explicit final statements

**CP.3 IS SAFE TO IMPLEMENT** — once the smallest honest scope (§W) is adopted and the exact ±1 magnitude/floor values receive explicit product sign-off (§BI), mirroring the same discipline every prior stage in this series has followed.

**TRAINING ENVIRONMENT SUPPORT IS CURRENTLY: MISSING** — at the consumption layer; the content/metadata layer (`EquipmentRequirement`) is unusually complete and ready.

**THE RECOMMENDED NEXT TRAININGOS STAGE IS: TE.1 — Training Environment Foundation**

---

## STOP

Design/audit only. Nothing implemented, committed, or pushed. All five closed stages (CP.2, CP.2R, FF.L1, FF.E1, FF.P1) remain closed and unmodified. None of the five existing design/audit documents was edited.
