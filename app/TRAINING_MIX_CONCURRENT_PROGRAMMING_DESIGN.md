# Training Mix + Concurrent Programming + Functional Fitness Architecture Investigation

**Status: DESIGN ACCEPTED. Stage CP.1 (Training Stress Profile Parity) IMPLEMENTED — see the CP.1 Implementation Report appended after §22. Nothing beyond CP.1 has been implemented.**

This document was independently reviewed after its first draft, then again after a second revision. Overall direction is **ACCEPTED**. All corrections/decisions from both review rounds are incorporated below; the original text is not silently rewritten — see **Review Decisions** for exactly what changed and why, across both rounds. Every section is labeled **APPROVED**, **LOCKED**, **DEFERRED**, or **UNRESOLVED** so status is never ambiguous — no section remains marked "REQUIRES TAXONOMY DECISION" any longer (see round 2 below).

---

## Review Decisions

### Round 1

1. **§14 source-fidelity error, corrected.** The first draft's 4-week reference table mislabeled the recovered Family A Mesocycle 1 structure. Full correction and root cause below (§14) — see the explicit safeguard added in §22 (CP.1 contract) to make sure it can't recur through a new mapper either.
2. **`AdaptationObjective` taxonomy revised** — three of the original ten cases (`movementVariability`, `generalAthleticism`, `maintenance`) removed — each failed the test "show a programming decision this case, and only this case, would change." Revised to 7 cases (§4).
3. **`GoalPriority` decision LOCKED** — no separate `role` field; `GoalPriority` becomes the general relative-importance signal, scheduling is one consumer of it.
4. **Constraint model redesigned.** The original soft-vs-hard framing is rejected as too coarse. Replaced with two orthogonal axes — **eligibility** (hard: can this even be selected) and **preference** (soft: how much do we want it, among what's eligible) — §3a.
5. **§11 (strength inside FF) corrected.** The original rule authorized FF strength content based on movement-pattern non-overlap alone. Movement pattern and training stress are different dimensions — a pattern-distinct movement (e.g. a clean vs. a hypertrophy squat) can still carry high lower-body/systemic/recovery cost. §11 now requires both checks.
6. **Scope locked for the first implementation stage**: stress-profile parity confirmed as Stage CP.1; cross-modality exposure stays derived, FF confirmed as the first (not only) generative consumer (§8); benchmark retesting and FF readiness Level 2/5 remain **DEFERRED**; equipment/environment remains **DEFERRED**; pairwise-vs-aggregate interference remains explicitly **UNRESOLVED**.

### Round 2 — final locks, then CP.1 authorized and implemented

7. **The revised 7-case `AdaptationObjective` taxonomy is now LOCKED, not merely proposed.** `muscleGain`, `maxStrength`, `power`, `aerobicCapacity`, `anaerobicCapacity`, `workCapacity`, `skillAcquisition` — confirmed non-mutually-exclusive (a component may carry several at once, describing *why* it exists in the mix, never a workout format/progression state/programming strategy). `maintenance`/`movementVariability`/`generalAthleticism` stay excluded. No further taxonomy expansion without a new, equally specific need.
8. **The two-axis constraint model (`ConstraintEligibility`/`ConstraintPreference`, §3a) is LOCKED.** Associated-value details may be refined at implementation time, but the conceptual separation (hard gate vs. soft ranking among eligible candidates) may never collapse into one ordinal score.
9. **Stage CP.1 authorized and implemented** — see the CP.1 Implementation Report appended after §22. Nothing beyond CP.1 (no `ConcurrentProgrammingConstraint` type, no `AdaptationObjective` behavior, no FF pre-generation constraints, no aggregate weekly fatigue, no benchmark logic, no equipment/environment) was implemented.

Nothing below silently drops any earlier finding — §1/§2/§5–§10/§12–§13/§15–§19 are carried forward from round 1 unchanged except where a review decision explicitly touches them (§4, §11), which are marked.

---

## 1. Current architecture audit *(unchanged from first draft)*

**1. What does `TrainingMix` currently represent?**
`TrainingOS/Domain/Entities/TrainingMix.swift:20-65` — exactly: `id`, `kind` (`.recommended`/`.selected`), `name`, `phase` (inverse), `validFrom`/`validUntil` (temporary-mix window), `preferenceStrength` (`.systemRecommended`/`.userPrefers`/`.userStronglyPrefers`), `components: [TrainingMixComponent]`. It is a named container + selection-state wrapper around an ordered component list. **It carries no field describing the mix's overall strategic intent** — "why these modalities together" doesn't exist above component level at all.

**2. What does `TrainingMixComponent` currently represent?**
`Domain/Entities/TrainingMixComponent.swift:29-83` — `id`, `trainingMix`, `programInstance` (optional by design), `label` (free text, display only), `programmingSystem`, `priority` (`GoalPriority`), `frequency` (`SessionFrequency`: target/minimum/maximum), `flexibility` (`ComponentFlexibility`: required/preferred/optional), `allowsDoubleSessionPairing`, `preferredDays`, `requiredSpacingDays`, `sortIndex`. Every field is **scheduling-relevant metadata** — the type's own doc comment (line 19-20) says it adds "the scheduling-relevant metadata" to an instance, nothing more. No field expresses *why* the component exists.

**3. Does the model contain primary/supporting-modality, adaptation-priority, objective, or budget concepts?**
- `GoalPriority` (`.primary`/`.secondary`/`.supporting`) exists, but its own doc comment (`Enums.swift:67-74`) is explicit: it decides *"which `ProgramInstance` wins **scheduling conflicts**"* — a conflict-resolution tiebreak for the scheduler, not a declared "how important is this adaptation" field. It happens to correlate with adaptation importance in every mix built so far, but nothing enforces that meaning. **(See §3-review: this is now LOCKED as the intended, widened meaning.)**
- **No `adaptationObjective` field exists anywhere.** `label: String` (free text) is the only descriptive hint.
- **No training/fatigue "budget" concept exists** at the mix or component level.
- A separate, apparently-stale `TrainingPriority` enum (`Enums.swift:61-65`: `.strength`/`.endurance`/`.mixedModal`) exists with the comment "priority is derived from the active Phase, never asked as a direct question" — a different enum from `GoalPriority`, worth flagging as possible dead weight, not something to build on.

**4. Where does `LongTermPlanner` decide modality combinations?**
`LongTermPlanner.swift:614-653`, `candidateMixTemplates(phase:goal:)`, switching on `phase.type`. For `.muscleGain`: `muscleGainFocusedHypertrophyMix()` (line 802-813: Hypertrophy `.primary`×5, SteadyState `.supporting`×2) and `muscleGainVariedMix()` (line 817-832: Hypertrophy `.primary`×3, FunctionalFitness `.supporting`×2, SteadyState `.supporting`×1). **Every component is constructed independently inside the same function — nothing reads one component's fields while building another.** The relationship between components is entirely implicit in hand-picked literal numbers.

**5. Does LongTermPlanner (or SchedulingPipeline) express relationships between modalities?**
`LongTermPlanner`/`candidateMixTemplates` itself: **no**. But one layer down, `ConcurrentScheduler` does. `GoalAlignment`/`SchedulingPipeline.propose` (`SchedulingTypes.swift:381-389`, `GoalAlignmentEvaluator.swift`) reasons only from **scheduling outcomes** (`ScheduleIssue`s: was frequency satisfied, was interference avoided) — never from a component's actual prescribed sets/reps/movements.

**6. What does SchedulingPipeline know about session content?**
`ScheduledProgramInput` (`{component, sessions: [Session]}`) carries **real, already-materialized Sessions**, not placeholders. But `SchedulingPipeline`/`ConcurrentScheduler` only look at them through one lens: `SessionStressComposer.compose(session)` folds a session's `WorkoutBlock.trainingStressProfile` values into one worst-case-per-dimension `TrainingStressProfile`. It never looks at actual exercises/sets/reps/movement identity — only this coarse categorical profile, and only when a block carries one at all.

**7. Can SchedulingPipeline identify "heavy lower-body FF adjacent to high-priority lower-body hypertrophy"?**
The mechanism is real: `InterferenceAvoidanceRule.conservativeDefault = [lowerBodyLoad ≥ .high, impactLoading ≥ .high]` (`SchedulingTypes.swift:172-175`); `ConcurrentScheduler.score(...)` (lines 483-509) checks same-day + adjacent-day (±1) neighbors and penalizes (soft, not hard) a day where both sides clear the threshold. **But it can only ever fire between two Functional-Fitness-tagged sessions today**, because Hypertrophy sessions have no stress profile to compare (`compose` returns `nil`; the guard at `ConcurrentScheduler.swift:496` requires both non-nil). **The plumbing already exists; only the Hypertrophy-side (and Interval/SteadyState-side) mapper is missing** — this is Stage CP.1, §22.

**8. Does any existing engine maintain a cross-modality exposure ledger?**
No. `FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:)` and `IntervalWeekContextBuilder.build(instance:weekIndex:)` each scan **only one `ProgramInstance`'s own** completed sessions. Neither ever looks at a sibling component's instance in the same phase/mix.

**9/10. Cross-modality result visibility (both directions)?**
Zero. FF materialization never reads `SetResult`/`PersonalRecord`/`ExercisePerformanceProfile`. Hypertrophy/tactical planning never reads `FunctionalFitnessResult`/`FunctionalFitnessPerformedMovement`.

**11. Sufficient vs. needing semantic expansion**
Sufficient as-is: `TrainingStressProfile`/`LoadLevel`/`InterferenceAvoidanceRule`, the whole `ConcurrentScheduler` mechanism, `Stimulus`/`WorkoutFormat`/`MovementFunction`, `TrainingMixComponent`'s scheduling fields, `FunctionalFitnessDecisionEngine`'s variance algorithm, `StrengthProgressionEngine`/`SourceRMCalibration`/`LoadFirstOverlayEngine`/`DeloadStrategy` (source-authority preservation), `ProgramCapabilityRegistry`. Needs semantic expansion: `GoalPriority`'s documented scope (now **APPROVED**, §3-review) and every non-FF materializer (needs to stamp `TrainingStressProfile`, §22). Missing entirely: `adaptationObjective`, cross-modality exposure ledger, benchmark-retest triggering, FF readiness volume-reduction.

---

## 2. Current TrainingMix limitations *(unchanged)*

- **No expressed "why."** `TrainingMixComponent.label` is free text; nothing machine-reasonable captures that Hypertrophy exists for muscle gain and FF exists for work capacity/aerobic fitness/athleticism.
- **`priority` was documented as a scheduling tiebreak only** — now resolved: **APPROVED** to widen its documented scope (§3-review), not to add a parallel field.
- **Components are built independently** inside `candidateMixTemplates` — no code path where one component's construction is informed by another's.
- **No budget concept** — nothing caps or trades off total systemic demand across components.
- **No mechanism connects TrainingMix's own construction to `TrainingStressProfile`.**

---

## 3. Proposed responsibility boundaries *(unchanged — APPROVED)*

```
STRATEGIC PLANNER          — LongTermPlanner (exists, real)
      ↓
MODALITY PROGRAMMERS       — Hypertrophy/FF/Interval/SteadyState engines (exist, real)
      ↓
CONCURRENT PROGRAMMING     — does NOT exist as a layer yet
      ↓
TACTICAL SCHEDULER         — ConcurrentScheduler/SchedulingPipeline (exists, real)
      ↓
EXECUTION / RESULTS        — exists, real
```

`ConcurrentScheduler` is the **Tactical Scheduler**, not the Concurrent Programming layer — its own doc comment says it "never generates training methodology, never prescribes intensity, never picks exercises" (CLAUDE.md rule 15, already enforced in code). It is a post-hoc, day-choice safety net; it cannot make FF choose *lighter* content, only a *different day* for whatever FF already built.

**Concurrent Programming should be a new, explicit domain layer (option A)** — not folded into `LongTermPlanner` (wrong grain: strategic, not weekly-tactical), not folded into `SchedulingPipeline`/`ConcurrentScheduler` (would violate its own deliberate, tested "never programs" boundary), not distributed across engines (indistinguishable from today's bug). It sits between Modality Programmers and the Tactical Scheduler, handing each modality programmer a **constraint object** before that programmer generates its own week — see §3a for exactly what that object contains, now that "soft vs. hard" has been redesigned.

---

## 3a. Concurrent Programming constraint vocabulary — **LOCKED (review correction 4, confirmed round 2)**

The first draft offered a binary SOFT/HARD choice. **Rejected on review.** Real constraints span two genuinely different questions, and collapsing them into one scale would repeat exactly the kind of overloading CLAUDE.md rule 18 already warns against for `GoalAlignmentRating`/`ScheduleFeasibility` (a rating that means two different things depending on who's asking is a correctness bug, not an economy).

**Two orthogonal axes, not one four-point scale:**

```swift
/// Can this candidate even be selected at all? A hard gate — mirrors
/// LongTermPlanner's own §5a compatibility gate (rankCandidateMixes),
/// which already uses exactly this "eligible/ineligible" shape for an
/// analogous problem. Never a score; never "somewhat ineligible."
enum ConstraintEligibility: Equatable {
    case eligible
    case ineligible(reason: ConstraintViolationReason)
}

/// Given that a candidate IS eligible, how much do we want it? A soft
/// ranking — mirrors LongTermPlanner's own §5b bounded promotion. Ordered,
/// coarse, never a numeric score (same discipline as GoalAlignmentRating).
enum ConstraintPreference: Comparable {
    case discouraged
    case neutral
    case preferred
}

/// A typed, explainable reason — never a raw string thrown away after use,
/// mirrors ScheduleIssueCode's own discipline of typed, structured facts
/// that downstream code reads, never parses back out of display copy
/// (CLAUDE.md rule 16's discipline, applied one layer earlier).
enum ConstraintViolationReason {
    case wouldCompromiseProtectedPrimaryAdaptation(component: UUID, dimension: StressDimension)
    // additional cases added only as real scenarios demonstrate they're needed
}
```

**Why two axes, not `ALLOWED`/`PREFERRED`/`DISCOURAGED`/`PROHIBITED` as one flat enum:** a flat four-value scale can't cleanly express "this is eligible but discouraged" vs. "this is ineligible" as different *kinds* of fact — a caller reading a single ordinal value has to guess whether a low value still permits selection under constraint (e.g., nothing else clears the gate this week) or forbids it outright. Two axes make that explicit: `.ineligible` always means never-select, regardless of anything else; `.discouraged` (while `.eligible`) always means select-only-if-nothing-better, which is a real, useful, different state from forbidden.

**Consumption pattern:** the Concurrent Programming layer emits eligibility judgments for whichever `Stimulus` dimension values would violate a protected component's constraint (hard), plus preference judgments for the remainder (soft) — the FF engine's existing Stage A/B (`Stimulus`/`WorkoutFormat` selection) filters candidates by eligibility first, then uses preference only to break ties among what's left. This is exactly the two-stage "gate, then rank" shape `LongTermPlanner.rankCandidateMixes` already uses for mix selection — not a new pattern for this codebase, an extension of one already proven.

---

## 4. Proposed TrainingMix semantics — **REVISED (round 1), taxonomy LOCKED (round 2)**

**ROLE vs. PRIORITY vs. OBJECTIVE vs. FREQUENCY:**

- **FREQUENCY** — already correct (`SessionFrequency`). No change. **APPROVED.**
- **ROLE and PRIORITY are the same concept.** `GoalPriority.primary/.secondary/.supporting` already *is* "primary vs. supporting modality" in every real mix template written so far; its doc comment just narrowed its declared purpose to scheduling. **LOCKED per review: widen `GoalPriority`'s documented scope** to "the general relative-importance signal for this component; scheduling conflict resolution is one consumer of it, not its definition." A doc/scope change only — **no new field, no persistence-model change.** **APPROVED.**
- **OBJECTIVE is genuinely new.** Neither role/priority nor frequency can express *why*. **This is the one real gap — but the taxonomy is not locked; see below.**

### AdaptationObjective — revised taxonomy

The first draft proposed 10 cases. On review, three fail the test *"show at least one programming decision this case, and only this case, would change"* and are removed:

- **`maintenance` — REMOVED.** It's a rate/direction ("hold, don't build"), not a *which-capacity* label — a different axis entirely from the rest of the enum. "Maintenance" as a strategic intent already lives correctly at `PhaseType.maintenance` (confirmed real, `LongTermPlanner.swift`'s `maintenanceMix(...)`); duplicating it as a per-component objective would conflate two different questions (which capacity vs. what rate of change) into one enum, the same category error CLAUDE.md rule 18 warns against elsewhere.
- **`generalAthleticism` — REMOVED.** Too vague to change any specific `Stimulus`-selection decision that the *combination* of the other retained objectives doesn't already cover. If a component genuinely serves many purposes at once, that's exactly why the field is an array — tag it with several specific objectives, not one catch-all label that adds nothing machine-actionable.
- **`movementVariability` — REMOVED.** Not an adaptation the body moves toward — it's a *programming strategy* (vary the movements used), which `FunctionalFitnessDecisionEngine`'s existing repetition-triggered variance algorithm already implements mechanically, independent of any declared objective. Encoding it as an objective would conflate "why does this component exist" with "how is its content selected."

**Muscular endurance and repeatability were considered and intentionally excluded as new cases**: muscular endurance is a specific expression of `workCapacity` (+ `anaerobicCapacity` at shorter durations), not an atomic thing needing its own case; repeatability (smaller output degradation across intervals) is a *result/signal* read from execution, feeding progression (§9), not something you'd tag a component with going in.

**Revised, tightened taxonomy — 7 cases, each with the concrete decision it uniquely drives:**

```swift
enum AdaptationObjective {
    case muscleGain          // protects against high eccentric/impact volume from concurrent components; anchors RM-based calibration awareness
    case maxStrength         // protects CNS/systemic-demand budget more aggressively than muscleGain alone — favors lower total concurrent systemic load even at variety's expense
    case power               // permits/favors short, explosive, low-fatigue-cost FF content as complementary; discourages long fatiguing pieces the same day
    case aerobicCapacity     // favors long duration-domain + low/moderate intensity; tolerant of frequent, low-recovery-cost placement
    case anaerobicCapacity   // favors short/medium duration + high intensity + repeated-effort formats (.intervals/.emom); expects and spaces for higher recovery cost
    case workCapacity        // favors medium/long duration + higher-volume-tolerant formats (.amrap/.forTime/.chipper); accepts higher metabolic demand
    case skillAcquisition    // favors a LOWER fatigue/recovery ceiling regardless of duration (skill degrades under fatigue) and prioritizes technical slots over rounds/time pressure
}
// TrainingMixComponent.adaptationObjectives: [AdaptationObjective]
```

Still an array — the reference case's FF component still serves several of these at once (e.g. `[workCapacity, aerobicCapacity, power, skillAcquisition]`), now expressed through the *specific* vocabulary above instead of the removed vague catch-all.

**This taxonomy is LOCKED (round 2 review)** — not merely proposed. These 7 objectives are explicitly non-mutually-exclusive (a component may carry several at once — the example given: Hypertrophy `priority = .primary, objectives = [.muscleGain]`; Functional Fitness `priority = .supporting, objectives = [.workCapacity, .aerobicCapacity, .power]`). They describe WHY a component exists in the mix — never a workout format, a progression state, or a programming strategy. No further expansion without a new, equally specific need demonstrated against a real scenario.

**"Interference tolerance/protection"** — remains **derived, not persisted** (§3a's constraint vocabulary computes it from `(priority, adaptationObjectives)` at decision time). No new persisted field.

**Smallest durable semantic model, unchanged verdict: exactly one new field** (`adaptationObjectives: [AdaptationObjective]`, revised case list above), one doc-scope clarification (`GoalPriority`, now locked), zero new "role" or "budget" fields.

---

## 5. Functional Fitness Programming Constitution *(unchanged — APPROVED)*

**Already real, already correctly designed — reuse as-is:**

| Dimension | Already exists as | Status |
|---|---|---|
| Time domain | `DurationDomain` (short/medium/long) | Real, used |
| Modality | `FunctionalModality` (metabolicConditioning/gymnastics/weightlifting) | Real, used |
| Movement function | `MovementFunction` (15 cases) | Real, used, broader than the brief's own list |
| Loading | `LoadingClassification` (bodyweightOnly/light/moderate/heavy) | Real, used |
| Workout structure | `WorkoutFormat` (9 cases) | Real, used, covers the brief's list fully |
| Skill complexity | `SkillDemand` | Modeled, but no per-Exercise skill data to validate against yet — deferred dependency |
| Local/systemic fatigue, impact | `TrainingStressProfile` | Real — shared cross-modality vocabulary, not FF-only |

**CrossFit-derived naming:** `FunctionalModality`'s three cases borrow CrossFit's own broad category *names* as classification vocabulary — fine, and should stay. The line to hold: **borrowing category vocabulary = fine; borrowing an actual prescribed workout = never.** `FunctionalFitnessProgramGenerator` builds movement slots generically, never from a fixed workout library — confirmed, nothing in the audit violates this.

**Genuine new pieces:** (1) "output character" (power/repeatable-intervals/sustainable-aerobic) — a **derived classification**, computed from existing `(intensity, systemicDemand, targetDurationDomain, format)`, never a new persisted field; (2) Hypertrophy/Interval/SteadyState-side `TrainingStressProfile` mapper — the single highest-leverage gap, now Stage CP.1 (§22).

---

## 6. Functional Fitness session-construction pipeline *(unchanged — APPROVED)*

| Pipeline stage | Owner | Status |
|---|---|---|
| Strategic role → block objective | `LongTermPlanner` + `TrainingMixComponent.adaptationObjectives` | Mostly exists; needs the one new field |
| Weekly FF objectives (given siblings) | **NEW: Concurrent Programming layer** | New |
| Session stimulus → structure → movement functions | `FunctionalFitnessProgramGenerator` Stage A/B/C | Exists, reused as-is, receives a *constrained* candidate set |
| Movements → dose/load → scaling | `FunctionalFitnessMaterializer` Stage D | Exists, reused as-is |
| Concurrent-program compatibility check | **NEW layer** (pre-commit) + existing `FunctionalFitnessStimulusValidator` (internal consistency) + existing `ConcurrentScheduler` (placement safety net) | Layered, not replaced |
| Tactical scheduling | `SchedulingPipeline`/`ConcurrentScheduler` | Exists, unchanged |
| Execution | Existing machinery | Exists, unchanged |
| Exposure/result history → next decision | `FunctionalFitnessExposureHistoryBuilder` + **NEW cross-modality summary feed** | Own-modality part exists; cross-modality part new |

---

## 7. Two FF sessions as a pair *(unchanged — APPROVED)*

For 3× Hypertrophy (full-body, Day A/B/C) + 2× FF: since every hypertrophy day already carries meaningful lower-body load, the FF pair should, as a *starting default* (never a hardcoded rule): favor upper-body/monostructural/skill-carry emphasis over another heavy lower-body exposure, and differ from each other along FF's own already-varied dimensions. **The pairing is a consequence of shared constraints, never a fixed FF-A/FF-B template** — the "right" pair changes if the hypertrophy split changes (§14/§15 corrected accordingly).

---

## 8. Cross-modality exposure/load model — **SCOPE LOCKED (review correction 6)**

**Do not build false precision.** No "10 pull-ups = 0.63 hypertrophy sets" formula. `TrainingStressProfile`'s own design already embodies this discipline.

**Two distinct concepts:** direct programmed stimulus (each component's own prescription, unchanged) vs. concurrent exposure/fatigue cost (a *read-only*, cross-component, rolling-window summary — derived on read, never persisted, mirroring `FunctionalFitnessExposureHistoryBuilder`'s own shape, widened in scope).

**Locked scope decision:** the input model is **not FF-specific** — Hypertrophy/FF/Running/Interval/SteadyState may all eventually *contribute* stress/exposure data once each has a mapper (§22 covers Hypertrophy/Interval/SteadyState; FF's already exists). But **Functional Fitness is confirmed as the first (not the only) generative modality whose own programming choices are actively *constrained* by the new Concurrent Programming layer** — i.e., every modality can eventually feed the ledger, but only FF's Stage A/B consumes a constraint object in the first implementation pass. This keeps the input model honestly general while keeping the actual behavior change small and incremental (§20 step 4).

**Minimum representation:** `CrossModalityExposureSummary(for: phase, asOf: date, window: Int) -> [StressDimension: LoadLevel]` — a pure function reading sibling `ProgramInstance.sessions` completed within the window, worst-case-composing their stamped profiles (mirroring `SessionStressComposer`'s own worst-case-not-average discipline). No new entity, no new persisted rows.

---

## 9. FF progression model *(unchanged — APPROVED, benchmark-retest portion DEFERRED)*

- **Session-to-session**: `FunctionalFitnessDecisionEngine`'s existing repetition-triggered variance already governs capacity/density/load. No new mechanism.
- **Block-level**: skill/loading-ceiling progression — new, small, block-boundary decisions, analogous to Hypertrophy's own `PrescriptionTemplate.rules`.
- **Occasional testing (benchmark retesting)** — confirmed does not exist today (zero "retest" references anywhere). **DEFERRED per review — explicitly excluded from the first Concurrent Programming implementation sequence** (§20/§21). Kept as a future FF programming capability, not designed further here.
- **Movement quality/repeatability** — read from execution, feed the block-level driver, not a fourth independent objective (confirms §4's exclusion of a dedicated case).

---

## 10. Supporting-vs-primary FF behavior *(unchanged — APPROVED)*

| | Case A (3 Hyp + 2 FF) | Case B (2 Hyp + 3 FF) | Case C (1–2 Strength + 4 FF) |
|---|---|---|---|
| FF role | SUPPORTING | balanced/hybrid | PRIMARY |
| Volume/intensity | Lower ceiling; protect Hypertrophy's recovery | Moderate | FF's own progression drives the block |
| Complexity/skill | Conservative | Moderate | Full skill progression ladder |
| Dedicated strength inside FF | Avoid — see §11 (corrected) | Situational — see §11 | Appropriate — FF is the only place loaded strength lives |
| Benchmark frequency | Rare (deferred, §9) | Occasional (deferred) | More frequent (deferred) |
| Recovery cost deference | High | Moderate | Low |

Driven by one gradient mechanism (role/priority + `adaptationObjectives` + Concurrent Programming constraint tightness), never three separate code paths.

---

## 11. Strength inside Functional Fitness — **CORRECTED (review correction 5)**

**The original rule was wrong.** It authorized FF strength content based on movement-pattern non-overlap alone ("a clean is pattern-distinct from a hypertrophy squat, so it's fine"). **Movement pattern and training stress are different dimensions** — a clean may be a different movement *expression* from a hypertrophy squat, but that does not imply negligible `lowerBodyLoad`/`systemicDemand`/`recoveryDemand`/`impactLoading`/`metabolicDemand`. A pattern-distinct movement can still be extremely costly.

**Corrected rule:** FF may include dedicated loaded strength work only when **both**:

1. **Movement-pattern check** — no separate Strength/Hypertrophy/Powerlifting component in the same `TrainingMix` already programs an equal-or-higher-priority exposure for the **same movement pattern** at moderate-or-higher load this week; **and**
2. **Stress/recovery-cost check** — the candidate FF strength content's own `TrainingStressProfile` (once Stage CP.1 exists, or FF's own existing mapper for this content) must clear the Concurrent Programming layer's **eligibility gate** (§3a) the same way any other FF stimulus choice would. Passing check 1 alone is never sufficient — a heavy clean/snatch session can still be `.ineligible` on stress grounds even with zero movement-pattern overlap against the hypertrophy program, if its `lowerBodyLoad`/`systemicDemand` would compromise a protected primary objective this week.

- Case A/B (a real Hypertrophy component exists, comparable-or-higher priority): FF's strength-shaped content should avoid heavy loaded versions of already-covered patterns **and** must independently clear the stress-eligibility gate even for pattern-distinct movements.
- Case C (no separate strength modality, or a much smaller one): FF becomes the legitimate home for genuine loaded strength work — subject to the same stress-eligibility check (there is more headroom in this case, not an exemption from the check).

---

## 12. Equipment/environment dependency *(unchanged — DEFERRED)*

FF/Concurrent Programming will eventually need per-exercise equipment availability, space/environment constraints, and per-implement load-increment granularity — none of this is being built now. Remains exactly the already-known, already-deferred gap (Stage 10R.6, D-10R6-11).

---

## 13. Readiness interaction with Functional Fitness *(unchanged principle — mechanism DEFERRED)*

FF has no implemented Level 2 (volume reduction) today; Level 5 (`.sessionConvertedToLowerDemand`) is already named in `ReadinessActionKind` and explicitly deferred. **Dividing principle** (unchanged, APPROVED as a principle): dose changes that preserve the session's original objective (reduce rounds/load/complexity within the same `Stimulus` category) are safe to automate; changes that convert the objective (e.g. power → sustainable aerobic) must never be silent and must feed the exposure ledger with what *actually* happened, not the stale plan. **No new readiness mechanism is to be implemented — confirmed DEFERRED per review**, pending a separate training-science policy decision.

---

## 14. Concrete 3 HYP + 2 FF four-week reference block — **CORRECTED (review correction 1)**

### What was wrong

The first draft's table showed a **4-week** schedule and labeled "Week 4" as simultaneously **"RIR 1"** and **"deload."** This is a real source-fidelity error, not a stylistic one, for two independent reasons:

1. **The recovered Family A Mesocycle 1/2 structure is five weeks, not four**: `HypertrophyProgramGenerator.swift:221-222`'s own doc comment states plainly, *"The legacy fixed-pair path always builds 4 progressive + 1 deload week... unchanged since Stage 4A."* The day-focus-driven path used for the real 3-Day Full Body reference program is explicitly the same shape for Mesocycle 1/2 (line 223-225: *"4 progressive + 1 deload for Mesocycle 1/2"*). Confirmed directly in code: `generateLegacyFixedPair` builds `ProgramDefinition(..., lengthWeeks: 5, ...)` (line 254), then **four** `TrainingWeek(isDeload: false)` (line 263-266) followed by **one separate** `TrainingWeek(isDeload: true)` (line 268-270).
2. **`repGoalSchedule = [.rir(3), .rir(3), .rir(2), .rir(1)]` (line 129-130) has exactly four entries — one per progressive week (weeks 1-4) — and does not apply to the deload week at all.** RIR 1 (week 4) means "one rep in reserve," i.e. the *hardest*, closest-to-failure week — the peak of the progressive block, not a deload. The deload week (week 5) is resolved through a completely different mechanism, `SourceCompatibleDeloadStrategy` (`DeloadStrategy.swift`): its weight is a fraction of the *already-resolved Week-1 weight* (full weight for the first half of that week's training days, half weight for the rest — Family A's specific asymmetric pattern, `DeloadStrategy.swift:38-50`), and its rep goal comes from a separate `deloadRepAction`-gated resolution — never from `repGoalSchedule`'s RIR values. Calling week 4 "RIR 1 / deload" conflated the hardest progressive week with the actual, separate recovery week that follows it.

### The correction

| Week | Order | HYP content (source, unchanged) | FF-A | FF-B |
|---|---|---|---|---|
| 1 | HYP A → FF A → HYP B → HYP C → FF B | Day A/B/C, week 1 (RIR 3 — first progressive week) | Short, high power: weightlifting + monostructural, light total lower-body volume, upper-skew | Longer, aerobic/mixed-modal: gymnastics + monostructural, sustainable pace |
| 2 | Same order | Day A/B/C, week 2 (RIR 3, autoregulated sets — second progressive week, same RIR target as week 1 per the source's own schedule) | Same duration/power category as wk1 (FF's repetition trigger not yet met at N=2); different specific movements | Same category as wk1; different specific movements |
| 3 | Same order | Day A/B/C, week 3 (RIR 2 — third progressive week, effort intensifying) | FF's repetition trigger fires (3rd consecutive same-category week) → rotates loading/modality mix; Concurrent Programming layer tightens the lower-body-load ceiling given week 3's rising hypertrophy intensity | Duration domain rotates per FF's own variance algorithm; stays upper/aerobic-biased |
| 4 | Same order | Day A/B/C, week 4 (RIR 1 — **the peak progressive week, hardest of the mesocycle**, not a deload) | Concurrent Programming layer keeps the lower-body-load ceiling tight — this is the week hypertrophy fatigue is HIGHEST, the opposite of a recovery week | Continues the rotation from week 3; still constrained by the same tight ceiling |
| **5 (deload)** | Day A/B/C, week 5 (genuine deload — `TrainingWeek.isDeload == true`; weight/reps resolved via `SourceCompatibleDeloadStrategy`, never `repGoalSchedule`) | FF systemic demand ceiling drops in step with the real deload week — the Concurrent Programming layer reads the `isDeload` flag as a hard signal to loosen the "protect Hypertrophy" constraint, but does not independently escalate FF, since deload weeks exist for recovery, not for shifting fatigue onto the supporting modality | Same — genuinely lower systemic demand this week, not "make up for it" |

The point, restated and now source-accurate: coherence comes from the Concurrent Programming layer's constraint (role/objective + the real `isDeload` flag + recent stress exposure), *not* from a fixed FF-A/FF-B template — and the constraint should tighten progressively across weeks 1→4 as hypertrophy intensity rises toward its real peak, then loosen only at the real, separate week-5 deload.

---

## 15. Stress test against other TrainingMix combinations *(unchanged — APPROVED)*

| Mix | Where the architecture holds | Where it's stressed / open questions |
|---|---|---|
| 5 Hypertrophy (no FF) | Degenerates cleanly to today's behavior | None |
| 3 Hyp + 2 FF (reference) | Fully worked in §14 (corrected) | — |
| 2 Hyp + 3 FF | Role shifts toward Case B; data-driven, not a hardcoded 3-vs-2 rule | Confirms role is genuinely derived from the mix |
| 2 Hyp + 2 Running | Running (SteadyState/Interval) has the **identical** stress-profile-stamping gap as Hypertrophy today | Confirms the CP.1 fix belongs at a shared materializer-contract level (§22), not Hypertrophy-only |
| 2 Hyp + 2 FF + 2 Running | Tests whether the model generalizes beyond a pair | **UNRESOLVED per review, deliberately not solved speculatively** (§19/§21) — `InterferenceAvoidanceRule` checks pairs only; a rolling weekly-aggregate concept may eventually be needed but should wait for a real 3-modality case to prove pairwise reasoning insufficient |
| 4 FF + 1 Strength | FF becomes PRIMARY (Case C, §10/§11 corrected) | Confirms the role-flip requires no code branching, only data |

---

## 16. Proposed domain/code impact — **updated for review decisions**

| Item | Classification | Persist? |
|---|---|---|
| `TrainingMixComponent.adaptationObjectives: [AdaptationObjective]` (revised 7-case taxonomy, §4) | **NEW DOMAIN CONCEPT — LOCKED, not yet implemented** | Yes |
| Hypertrophy/Powerlifting/Interval/SteadyState `TrainingStressProfile` mapper(s) | **SEMANTIC EXPANSION — APPROVED as Stage CP.1, contract in §22** | No — stamps an existing field |
| Concurrent Programming layer (coordinator) | **NEW DOMAIN CONCEPT — APPROVED IN PRINCIPLE, NOT YET SCHEDULED** | No |
| `ConstraintEligibility`/`ConstraintPreference` vocabulary (§3a) | **NEW DOMAIN CONCEPT — APPROVED design, not implemented** | No |
| Cross-modality exposure summary function | **NEW DOMAIN CONCEPT, derived — APPROVED, FF-first scope locked (§8)** | No |
| `GoalPriority` doc-scope clarification | **SEMANTIC EXPANSION (docs only) — APPROVED/LOCKED** | N/A |
| Benchmark-retest scheduling trigger | **NEW DOMAIN CONCEPT — DEFERRED** | Minimal, if/when built |
| FF readiness Level 2 (volume reduction) | **DEFERRED DEPENDENCY** | N/A |
| Equipment/environment domain | **DEFERRED DEPENDENCY** | N/A |
| Per-Exercise skill classification data | **DEFERRED DEPENDENCY** | N/A |

---

## 17. What should persist vs. be derived *(unchanged — APPROVED)*

**Persist:** `adaptationObjectives` (once its taxonomy is locked). Benchmark-retest decision records, if/when built. Everything already persisted stays persisted.

**Derive, never persist:** cross-modality exposure summary; the Concurrent Programming layer's constraint output for any given week (a value type, computed and consumed in one pass, mirroring `ScheduleProposal`/`GoalAlignment`); "output character" classification.

---

## 18. Migration/backward-compatibility considerations *(unchanged — APPROVED)*

`adaptationObjectives: [AdaptationObjective] = []` (default empty) is a purely additive `@Model` field — the same class of change as Stage 10R.7A-TX's `Exercise.resolvedSlots` addition, empirically proven to migrate cleanly. Stress-profile mappers touch no schema (the field already exists, already optional). `GoalPriority`'s widening changes no stored values. No migration risk identified beyond the already-proven-safe additive-field pattern.

---

## 19. Risks and unresolved questions — **updated statuses**

1. **Pairwise vs. aggregate interference checking** — **UNRESOLVED, explicitly not to be solved speculatively per review.** Defer until a real 3-modality mix demonstrates pairwise reasoning is actually insufficient.
2. **Constraint enforcement tightness** — now partially resolved by §3a's two-axis model (eligibility is always hard, preference is always soft); what remains open is exactly *which* violations should be `.ineligible` vs. merely `.discouraged` in practice — a product-level calibration question, not an architectural one.
3. **Whether `adaptationObjectives` should be user-settable** — still open, plan-editing territory, out of scope here.
4. **Benchmark-retest cadence** — **DEFERRED** along with the whole capability (§9/§20/§21).
5. **Whether Concurrent Programming ever needs to run more than once a week** (e.g. after a Level 5 readiness event) — still open, blocked on §13's mechanism being built at all (which is itself deferred).

---

## 20. Recommended implementation stages, in order — **updated**

1. **Stage CP.1 — Stress-profile parity.** APPROVED as first stage. Contract in §22. **IMPLEMENTED — see the CP.1 Implementation Report appended after §22.**
2. **`adaptationObjectives` field** — taxonomy now LOCKED (§4); implementation not yet begun.
3. **Cross-modality exposure summary** (derived query, FF-first consumption per §8's locked scope).
4. **Concurrent Programming layer** (coordinator) — FF-only first, using §3a's constraint vocabulary.
5. **Benchmark-retest scheduling** — **DEFERRED**, not part of this sequence.
6. **FF readiness Level 2/Level 5** — **DEFERRED**, pending separate training-science policy decision.
7. **Equipment/environment domain** — **DEFERRED**, unchanged.

---

## 21. Explicit decisions needed before implementation — **updated**

1. ~~Lock the revised 7-case `AdaptationObjective` taxonomy~~ — **LOCKED (round 2, §4).** No longer open.
2. `GoalPriority` doc-scope widening — **already approved/locked**, nothing further needed.
3. Constraint model — **LOCKED (round 2, §3a)**; remaining decision is calibration (§19 item 2), not architecture.
4. Stress-profile-mapper parity as Stage CP.1 — **IMPLEMENTED**; see the CP.1 Implementation Report appended after §22.
5. Benchmark-retest cadence — **deferred**, no decision needed now.
6. FF readiness Level 2/Level 5 — **deferred**, confirmed out of scope until its own design pass.
7. Interval/SteadyState inclusion in the Concurrent Programming layer's *constraint-consuming* side (as opposed to contributing side, which all modalities do per §8) — still open; §20 step 4 proposes FF-only first.

---

## 22. Stage CP.1 contract — Training Stress Profile Parity

**Not implemented. Design only, per explicit instruction.**

### Production types/files affected

- **New**: a per-modality mapper file each, mirroring `FunctionalFitnessStressProfileMapper`'s existing shape and location convention:
  - `StrengthStressProfileMapper.swift` (serves both Hypertrophy and Powerlifting — they already share `StrengthMaterializer`/`StrengthProgressionEngine`, so they share one mapper too, never two near-duplicates).
  - `SteadyStateStressProfileMapper.swift`
  - `IntervalStressProfileMapper.swift`
- **Modified**: `StrengthMaterializer.swift` (call the new mapper, stamp `block.trainingStressProfile`, mirroring `FunctionalFitnessMaterializer.swift:78`'s exact call shape), the Interval materializer, `SteadyStateMaterializer.swift`.
- **Untouched, by design**: `WorkoutBlock.swift` (field already exists, already optional), `SessionStressComposer.swift`, `ConcurrentScheduler.swift`, `InterferenceAvoidanceRule`, `TrainingStressProfile.swift`, `LoadLevel` — every consumer of this data already works correctly and needs zero changes once the field starts being populated for these modalities.

### Mapper ownership

Each modality's own materializer owns its own mapper — never one shared cross-modality mapper — because each modality's reliable input shape is genuinely different (movement pattern + resolved load/RIR for Strength; activity type + duration/intensity-zone for SteadyState; activity type + work/recovery/intensity for Interval). This mirrors the existing precedent exactly (FF owns its own mapper today).

### Reliable inputs per modality

- **Strength (Hypertrophy/Powerlifting)**: `Exercise.movementPattern`/`primaryTargets` (already canonical, persisted, curated — not guessed) → which body-region dimensions apply at all (a squat/hinge/lunge pattern engages `lowerBodyLoad`; press/pull engages `upperBodyLoad`). Resolved `SetPrescription.targetWeight`/reps + the week's `RepGoal`/RIR (already resolved by the untouched `StrengthProgressionEngine`/`LoadFirstOverlayEngine`) → intensity tier (RIR 1-2 + moderate-heavy load → `.high`; RIR 3+ → `.moderate`; light/no-load accessory → `.low`). `impactLoading` → reliably `.none`/`.low` for essentially all hypertrophy movements (controlled, non-ballistic by construction — a real, defensible default, not a guess). `systemicDemand`/`metabolicDemand` → correlate with total same-day volume across large-muscle-group slots, composed at the session level (see below). `TrainingWeek.isDeload == true` → reliably lowers every dimension a tier versus the same slot's non-deload week (the deload's own real weight/rep reduction, from `DeloadStrategy`, already tells us this — not an assumption layered on top).
- **SteadyState/Interval**: `preferredActivityType: ActivityType` (`running`/`cycling`/`rowing`/`skiErg`/`other` — already real, persisted, canonical on both `SteadyStatePrescriptionTemplate` and `IntervalPrescriptionTemplate`) is the single most reliable input: running is genuinely, uncontroversially higher `impactLoading` and `lowerBodyLoad` than cycling/rowing/skiErg at a comparable intensity — a real physiological fact, not invented precision, the same class of claim `FunctionalFitnessStressProfileMapper` already makes per movement function. Resolved duration/distance/intensity-zone (already computed by the untouched `SteadyStateProgressionEngine`/interval engine) → `durationClassification` (reuse `FunctionalFitnessStimulusValidator`'s own existing short/medium/long thresholds for consistency, never a second competing threshold table) and `overallIntensity`/`metabolicDemand`. Interval's work/recovery ratio → higher `systemicDemand`/`recoveryDemand` than an equivalent-duration steady effort (repeated near-threshold efforts vs. one sustained effort is again an uncontroversial physiological distinction, not a formula).
- `TrainingStressProfile.modality: ActivityType?` already exists specifically to carry this — SteadyState/Interval simply never populate it today. CP.1 populates it directly from `preferredActivityType`.

### Exact classification philosophy

**Coarse, categorical, explainable, no false precision** — unchanged from `TrainingStressProfile`'s own founding discipline. Every mapping is a small, named lookup/decision table with a one-line rationale comment (mirroring `FunctionalFitnessStressProfileMapper`'s own style exactly) — e.g. "squat/hinge/lunge pattern → `lowerBodyLoad` applies; press/pull pattern → `upperBodyLoad` applies; RIR ≤2 + moderate-or-heavier resolved load → `.high`" — never a weighted formula, never a numeric score converted into a bucket.

### Handling of missing/ambiguous information

Two distinct fallback conventions, used for two distinct reasons — never conflated:

1. **Semantically inapplicable → `.none`.** A genuine, honest zero (e.g. `upperBodyLoad` for a pure squat pattern). This is a real classification, not a guess.
2. **Applicable but genuinely uncertain in magnitude → conservative `.moderate` default**, explicitly documented as a deliberate "err toward extra caution" choice — never `.none` (which would silently disable `InterferenceAvoidanceRule`'s protection, a false negative, the worse failure direction for a soft-penalty system) and never `.high` (which would over-trigger). This path should be rare given how much reliable input each modality actually has (see above) — it exists for genuine edge cases, not as the default path.
3. **Whole-block unclassifiable at all** (should not normally occur given the inputs above, but the contract must define behavior): the mapper returns `nil` for the entire profile, and the block's `trainingStressProfile` stays `nil` — **identical to today's status quo for that block**, never a partially-fabricated profile mixing real and guessed dimensions.

### Block vs. session composition

Mappers operate at **block grain**, matching where `WorkoutBlock.trainingStressProfile` already lives. No change to `SessionStressComposer`'s existing worst-case-per-dimension roll-up — a session with a heavy main-lift block and a light warmup block already correctly surfaces the main lift's profile as the session's own, via existing, unchanged logic. Every block that can be honestly classified should be (including accessory/warmup blocks, which will simply classify low across most dimensions) — partial coverage (some blocks profiled, some not) is fine and already handled correctly by the existing composer.

### Interaction with `SessionStressComposer`

None required. It already composes whatever `TrainingStressProfile`s it finds; it does not need to know mappers exist.

### Interaction with `InterferenceAvoidanceRule`

None required. `conservativeDefault` (`lowerBodyLoad ≥ .high`, `impactLoading ≥ .high`) already exists and already fires correctly for any pair of sessions that both carry a profile — CP.1's entire value is simply making Hypertrophy/Interval/SteadyState sessions eligible to participate in a check that already works.

### Tests required

1. Per-modality mapper unit tests: known slot/prescription inputs → exact expected profile, dimension by dimension, including boundary cases (a light accessory slot → low across the board; the same slot compared peak-week vs. deload-week → measurably lower).
2. A "nil-when-genuinely-unclassifiable" test proving the mapper honestly omits stamping rather than guessing.
3. **The decisive regression test**: a real Hypertrophy session and a real FF session, both stamped, placed adjacently, both clearing `conservativeDefault` → `ConcurrentScheduler` actually produces `.interferenceConflict`/avoids it — proving the reference-case bug this whole investigation opened with is fixed, using `ConcurrentScheduler`'s own existing test fixtures/patterns.
4. A regression test confirming FF-vs-FF interference behavior is completely unchanged.
5. Full suite green, same discipline as every stage in this project.

### Backward compatibility

Purely additive. `WorkoutBlock.trainingStressProfile` already exists and is already optional — no schema change. Historical, already-materialized blocks are never retroactively stamped (mirrors CLAUDE.md rule 19d's "a completed snapshot is never mutated by a later revision," applied here to session history) — they simply remain `nil` forever, exactly as today. Only newly materialized blocks from this stage forward are stamped.

### Persistence implications

None beyond the already-existing, already-optional field. The mappers themselves are pure functions — no new persisted type, no new table, no new relationship.

### Source-authority safeguards

**This is the direct lesson of the §14 correction, applied prospectively.** The mapper must derive its classification **only** from already-resolved, source-faithful prescription data — the real output of the untouched `StrengthProgressionEngine`/`LoadFirstOverlayEngine`/`DeloadStrategy` (resolved weight, resolved reps, resolved RIR, the real `isDeload` flag) — and must **never** alter, reinterpret, second-guess, or approximate any source-derived value in order to produce a stress classification. The mapper is a strictly read-only, downstream *classifier* of what the source-authoritative engines already decided; it has no write path to and no influence over source programming, timing, or progression. Just as this design document itself must never become a competing source of truth for hypertrophy programming (the error this review corrected), neither may this new mapper.

### Explicit non-goals

Does not compute a numeric score. Does not change any modality's own prescribed content, weight, reps, or timing. Does not add a new persisted field (stamps an existing one). Does not modify `ConcurrentScheduler`, `InterferenceAvoidanceRule`, `SessionStressComposer`, or `TrainingStressProfile` itself. Does not implement the Concurrent Programming layer (a later, separate stage). Does not touch Functional Fitness's own existing, already-correct mapper.

---

## CP.1 Implementation Report

**Status: IMPLEMENTED. Not committed. Not pushed. Nothing beyond CP.1 was implemented.**

### Files changed

New: `TrainingOS/Engines/ActivityTypeStressCharacteristics.swift` (shared activity-type + zone lookup, used by SteadyState/Interval mappers), `TrainingOS/Engines/StrengthTrainingStressMapper.swift` (Hypertrophy + Powerlifting), `TrainingOS/Engines/SteadyStateTrainingStressMapper.swift`, `TrainingOS/Engines/IntervalTrainingStressMapper.swift`, `TrainingOSTests/TrainingStressProfileParityTests.swift` (17 tests).

Modified: `TrainingOS/Application/UseCases/StrengthMaterializer.swift` (accumulates each block's resolved prescriptions, calls the mapper once per block after its prescriptions are built, stamps `block.trainingStressProfile`), `TrainingOS/Application/UseCases/SteadyStateMaterializer.swift` (one call site), `TrainingOS/Application/UseCases/IntervalMaterializer.swift` (two call sites — the real `.intervals` block, and the embedded warm-up/cool-down `SteadyStatePrescription` blocks this same materializer also produces, mapped via the SteadyState mapper).

Untouched, as required: `WorkoutBlock.swift`, `SessionStressComposer.swift`, `ConcurrentScheduler.swift`, `InterferenceAvoidanceRule`, `TrainingStressProfile.swift`, `FunctionalFitnessStressProfileMapper.swift`, every source-authority engine (`StrengthProgressionEngine`, `LoadFirstOverlayEngine`, `SourceCompatibleDeloadStrategy`, `SteadyStateProgressionEngine`, `IntervalProgressionEngine`).

### Mapper design

`StrengthTrainingStressMapper.map(prescriptions: [ResolvedPrescription]) -> TrainingStressProfile?` — one call per `WorkoutBlock`, after every prescription template in that block has resolved, so classification always reflects the whole block, never one exercise. `nil` only when the block has nothing resolvable at all. No `isDeload` parameter anywhere in the mapper — it observes whatever weight/repGoal/setCount the real, untouched progression/deload engines already resolved, deload or not.

`SteadyStateTrainingStressMapper.map(activityType:durationSeconds:primaryIntensity:) -> TrainingStressProfile` and `IntervalTrainingStressMapper.map(activityType:intervalCount:workDurationSeconds:recoveryDurationSeconds:workIntensity:) -> TrainingStressProfile` — always produce a profile (`activityType` is always real and non-optional on both prescription types). Both share `ActivityTypeStressCharacteristics` for the activity-type-driven dimensions (impact/lower-body/upper-body) and the zone-based intensity lookup, so this physiological classification can't drift between the two mappers.

### Classification rules per modality

- **Strength/Hypertrophy/Powerlifting**: body-region dimensions from `Exercise.primaryTargets` (a real, canonical `MuscleGroup` set) against fixed lower-body/upper-body group lists; effort tier from resolved RIR (`≤1 → .high`, else `.moderate`) with a `.moderate`/`.low` fallback for non-RIR prescriptions; volume tier from total resolved set count (coarse thresholds); `impactLoading` is unconditionally `.none` (every exercise this catalog resolves Strength/Hypertrophy/Powerlifting slots to is controlled barbell/dumbbell/machine work — a real fact about this catalog's content, not a lazy default); systemic/metabolic/recovery demand mirror the worse of effort-tier and volume-tier.
- **Interval/SteadyState**: impact/lower-body/upper-body from `ActivityType` (running = impact + leg-dominant; cycling = leg-dominant, no impact; rowing/skiErg = full-body, no impact; `.other` = conservative `.moderate` across the board, the domain's own documented "unanticipated activity" case); intensity from the domain's own `HeartRateZone`/`PowerZone` (1-2 low, 3 moderate, 4-5 high) when present, else conservative `.moderate`; duration reuses `FunctionalFitnessStimulusValidator.durationDomain(forEstimatedSeconds:)` verbatim — no second threshold table. Interval additionally applies a structural floor (`intervalCount > 1 → at least .moderate`) since a repeated work/recovery structure is, by construction, more demanding than one continuous effort of the same total time — a structural fact, not a guess.

### Ambiguity/fallback handling

Two conventions, never conflated: (1) semantically inapplicable → `.none` (e.g. `upperBodyLoad` for a pure squat) — a real classification; (2) applicable but genuinely uncertain → conservative `.moderate` (e.g. a fixed-rep prescription with no RIR context; a non-zone `IntensityTarget` like pace/RPE/cadence, deliberately never converted into an invented zone; `.other` activity type). Never `.none` for a genuinely-applicable-but-uncertain dimension (would silently disable `InterferenceAvoidanceRule`), never `.high` (would over-trigger). Proven directly by `testMissingIntensityDataUsesDocumentedConservativeFallback`.

### Source-authority proof

`testSourcePrescriptionIsUnchangedByStressMapping` asserts the exact same resolved weight (`MROUND(100×0.85, 2.5) = 85kg`) `StrengthMaterializerTests`'s own pre-CP.1 test already asserted — proving CP.1 changed nothing about the resolved source prescription. `testDeloadIsNotReinterpretedAsNormalProgressiveStress` proves a real deload week's genuinely-reduced values classify at or below the peak progressive week's (RIR 1) classification — with zero `isDeload` branch in the mapper to have gotten this wrong via a special case; it's a natural consequence of classifying real, already-correctly-reduced numbers.

### Cross-modality interference proof

`testRealHypertrophyAndRealFunctionalFitnessConflictIsNowVisibleToInterferenceRule`: a real `StrengthMaterializer`-produced peak-week (RIR 1) squat session and a real `FunctionalFitnessStressProfileMapper`-produced heavy squat-loaded FF stimulus — both via their real, unchanged, production mapper — now trigger `InterferenceAvoidanceRule.conservativeDefault`'s `lowerBodyLoad` rule through the unchanged `SessionStressComposer`/`InterferenceAvoidanceRule` pipeline. This was impossible before CP.1 (Hypertrophy had no stress profile to compare). `testNonConflictingRealPairIsNotFalselyRejected` proves a light pair does not falsely trigger it.

### Targeted test count/results

17/17 passed (`TrainingStressProfileParityTests`) — 4 Hypertrophy, 3 Powerlifting-representative, 3 Interval, 3 SteadyState, 2 cross-modality (the decisive proof + the non-conflict proof), 1 FF-regression, 1 (deload comparison, counted under Hypertrophy).

### Full-suite result

**981 passed / 2 pre-existing skipped / 0 failed** (964 + 17 new). No regressions.

### Simulator result

Fresh erase, clean build (`DerivedData` removed, `xcodebuild clean` + `build`), install, launch: clean launch, no crash, no fatal/CoreData/SwiftData errors in logs.

### Persistence warnings

None. No schema change (the field already existed, already optional); no migration exercised or required.

### Deviations from the approved CP.1 contract

None of substance. One naming note: the contract's illustrative names (`StrengthTrainingStressMapper`/`SteadyStateTrainingStressMapper`/`IntervalTrainingStressMapper`) were used exactly as given. The embedded `SteadyStatePrescription` warm-up/cool-down blocks inside `IntervalMaterializer` are mapped via `SteadyStateTrainingStressMapper` (not a separate mapper) — the contract's own "mapper ownership" section already anticipated this by ownership of *prescription type*, not materializer file, so this is a direct application of the contract, not a deviation.

### Remaining deferred/unresolved items (unchanged)

Deferred: benchmark-retest scheduling, FF readiness Level 2/Level 5, Training Environment/Equipment Profile. Unresolved: pairwise vs. aggregate weekly interference; whether Interval/SteadyState later become constraint-*consuming* modalities (as opposed to contributing, which they now do). No `ConcurrentProgrammingConstraint` type, no `AdaptationObjective` field, no FF pre-generation constraints, no aggregate weekly fatigue, no benchmark logic, and no equipment/environment work were implemented — CP.1 is stress-profile parity only.

## STOP

Stage CP.1 (Training Stress Profile Parity) is implemented, tested, and verified. Not committed. Not pushed. CP.2 not started. Onboarding not started. Functional Fitness redesign not started.
