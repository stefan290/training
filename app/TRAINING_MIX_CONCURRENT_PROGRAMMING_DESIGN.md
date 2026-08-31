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
| **5 (deload)** | Day A/B/C, week 5 (genuine deload — `TrainingWeek.isDeload == true`; weight/reps resolved via `SourceCompatibleDeloadStrategy`, never `repGoalSchedule`) | **Corrected (CP.2 review correction 3):** the Concurrent Programming layer never reads `isDeload` and knows nothing about the source label "deload." It only ever reads Hypertrophy's already-CP.1-stamped `TrainingStressProfile` for this week. Because `StrengthTrainingStressMapper` has zero `isDeload` parameter (CP.1) and the deload week's resolved weight/reps/sets are genuinely lower, the mapper naturally stamps a lower profile this week — the eligibility gate loosens purely as an **emergent consequence of a lower stamped profile**, not as a conditional branch on the label. FF does not independently escalate either, since deload weeks exist for Hypertrophy's recovery, not for shifting fatigue onto the supporting modality — that emerges from FF's own inputs being unrelated to Hypertrophy's `isDeload` flag, not from a rule that references it. | Same — genuinely lower systemic demand this week (because the sibling profile it reads is genuinely lower), not "make up for it" |

The point, restated and now source-accurate: coherence comes from the Concurrent Programming layer's constraint (role/objective + Hypertrophy's real, CP.1-stamped `TrainingStressProfile` + recent FF exposure), *not* from a fixed FF-A/FF-B template and *not* from any `isDeload`-aware branch anywhere in Concurrent Programming — the constraint tightens progressively across weeks 1→4 only because the real stamped profile rises, and loosens at week 5 only because the real stamped profile falls. See the CP.2 Design Audit below for the full correction record.

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

## CP.2 Design Audit — Concurrent Programming Constraint Generation + FF Pre-Generation Constraint Consumption — **CORRECTED (round 2)**

**Status: DESIGN / AUDIT ONLY. Not implemented. Not committed. Not pushed.**

**Round 2 correction summary.** The round-1 audit below was independently reviewed and found insufficient in three places, now corrected in place (the round-1 text these replace is not left standing alongside them): (1) FF-A/FF-B same-week coordination cannot rely only on completed history or differing sibling volume — a new derived, non-persisted **current-week FF programming context** is required (Step 6); (2) "primary before supporting" is **not** locked as the general materialization order — the real orchestration answer is a two-pass split keyed on **constraint-consumer vs. producer role** (a `ProgrammingSystemKind` classification), not `GoalPriority` (Step 1); (3) all remaining "reads `isDeload`" language is removed — Concurrent Programming only ever reads the already-CP.1-stamped `TrainingStressProfile` (Step 5, and §14 above). A recheck also confirmed `InterferenceAvoidanceRule.triggers` is already a shared, neither-side-owned predicate CP.2 can call directly — no new predicate needed (Step 7a).

CP.1 answered "what stress does each programmed session represent?" This audit answers CP.2's question — "given that surrounding stress and the strategic role of FF, what FF stimuli are eligible/preferred/discouraged/prohibited BEFORE the workout is generated?" — against the REAL production code, not against this document's own earlier (necessarily speculative) pipeline-mapping guess in §6. Where the real code proves a narrower or different seam than §6 assumed, that correction is called out explicitly below rather than silently reused.

Reference case throughout: `TrainingMix` = 3× Hypertrophy (`priority = .primary`, `adaptationObjectives = [.muscleGain]`) + 2× Functional Fitness (FF‑A, FF‑B; `priority = .supporting`, `adaptationObjectives = [.workCapacity, .aerobicCapacity, .power]` — **illustrative only; Step 11a below finds `LongTermPlanner` cannot currently assign this exact combination from any real signal it has today**).

### Step 1 — Audit of the real production path

**Where FF `Stimulus` is actually chosen — corrected finding.** §6 of this document assumed "weekly FF objectives (given siblings)" would feed into `FunctionalFitnessProgramGenerator`'s Stage A/B (`Stimulus`/`WorkoutFormat` selection). The real code proves this is wrong: Stage A's `targetStimulus` is supplied once, at **template-configuration time**, and never varies again for the life of that `ProgramDefinition`:

- `LongTermPlanner.swift:1144-1169` (`functionalFitnessParameterCandidates`) hand-builds one fixed `Stimulus` (`targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural], …`) and wraps it in one `FunctionalFitnessProgramConfiguration`. This runs once, when `LongTermPlanner` proposes/materializes the component's program — not once per week.
- `FunctionalFitnessProgramGenerator.generate` (`FunctionalFitnessProgramGenerator.swift:36-87`) writes that single `configuration.targetStimulus` into **every** week's `FunctionalFitnessPrescriptionTemplate` (line 72-79, inside the `for dayIndex in 0..<configuration.daysPerWeek` loop, itself outside any per-week loop — there is only one `TemplateSession` per day, reused for the whole `lengthWeeks` block via `TrainingWeek(isDeload: false)` stamped identically `configuration.lengthWeeks` times, lines 53-57). The generator's own doc comment (lines 10-13) confirms this explicitly: "Stage A (`configuration.targetStimulus`) is supplied by the caller, not invented here… out of this pass's scope." **There is no code path where Stage A's baseline `Stimulus` changes week to week, let alone in response to a sibling component.**

**Where the real per-week variability actually happens.** `FunctionalFitnessMaterializer.materializeWeek` (`FunctionalFitnessMaterializer.swift:32-130`) is called once per week (from `RollTacticalWindowUseCase`, see below) and, for each block, runs:
```
let decision = FunctionalFitnessDecisionEngine().decide(ProgrammingDecisionInput(
    exposureHistory: exposureHistory,
    stimulusRequirements: ffTemplate.stimulus,       // the SAME fixed Stimulus every week
    varianceConstraints: ffTemplate.varianceConstraints ?? VarianceConstraints()
))
```
(`FunctionalFitnessMaterializer.swift:69-73`). `FunctionalFitnessDecisionEngine.decide` (`FunctionalFitnessDecisionEngine.swift:21-33`) checks exactly 4 dimensions in a fixed priority order — duration domain (line 37), loading (line 57), modality mix (line 77), movement function (line 107) — against `input.exposureHistory` (FF's own history only, via `FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:)`, which itself only ever scans one `ProgramInstance`'s own sessions, `FunctionalFitnessExposureHistoryBuilder.swift:18-39`) and adjusts **the first one it finds violated**, returning the baseline unchanged (`reasonCode: .stimulusAsConfigured`) if nothing is. This output, `decision.nextStimulus`, is what stamps `block.trainingStressProfile` (line 78, via the existing `FunctionalFitnessStressProfileMapper.map(stimulus:)` — confirmed unchanged by CP.1) and feeds Stage D (movement-slot exercise resolution, lines 87-110) and Stage E (`FunctionalFitnessStimulusValidator.validate`, lines 119-125) immediately after, in the same call.

**Does the pipeline know about non‑FF sessions at FF‑generation time? No — confirmed by direct read.** Neither `FunctionalFitnessMaterializer.materializeWeek`'s signature (`definition:instance:weekIndex:startDate:ownerUserID:candidateExercises:exposureHistory:context:`) nor `ProgrammingDecisionInput` (`ProgrammingDecisionEngine.swift:56-60`) carries any reference to a sibling `TrainingMixComponent`, a sibling `ProgramInstance`, or any cross-modality `TrainingStressProfile`. Zero awareness today.

**Who calls `materializeWeek`, and what do they already have in scope?** Two call sites, both real:
- `RollTacticalWindowUseCase.materializeFirstWindow` (`RollTacticalWindowUseCase.swift:59-64`) — week 0 only, called once per component from `StartPhaseUseCase`, one component at a time, not from within a loop that also touches siblings.
- `RollTacticalWindowUseCase.rollForward` (`RollTacticalWindowUseCase.swift:83-171`) — **this is the one call that already has every sibling in scope simultaneously.** It iterates `for component in mix.orderedComponents` (line 91) in a single pass, materializing each not-yet-exhausted component's next week (`ProgramWeekGrouping.nextWeekIndex(for: instance)`, line 95) and only AFTER the loop completes does it hand the whole batch to `SchedulingPipeline.propose(mix:inputs:constraints:)` (line 167). Inside that same loop, the `.functionalFitness` case (lines 149-154) already computes `FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance)` fresh, inline, and passes it straight into `materializeWeek` — i.e. **the established pattern for "supply derived, just-in-time context to this one call" already exists at exactly this call site.**

**A real, load-bearing ordering fact this audit surfaces (not previously known to this document):** `rollForward`'s single `for component in mix.orderedComponents` loop means a sibling component's THIS-WEEK session is only already materialized (and thus queryable via `SessionStressComposer.compose`) by the time FF's turn comes **if and only if** that sibling is iterated first. `orderedComponents` is ordered by `TrainingMixComponent.sortIndex` (`TrainingMixComponent.swift:57-59`), assigned by `TrainingMix.addComponent(_:)` — a display/insertion-order field, not a documented "materialize primary before supporting" contract. In every mix `LongTermPlanner.candidateMixTemplates` actually builds (`muscleGainVariedMix()` etc., cited in §1 answer 4 above), Hypertrophy is added before Functional Fitness, so this happens to hold today — but it is an implicit accident of construction order, not an enforced invariant. **This is a real design decision CP.2 must make explicit, not silently rely on** (resolved in Step 1's seam recommendation below).

**The narrowest correct injection seam, and why.** Two candidate seams exist; the correct one is the *outer* one, for a concrete reason proven by the code above:
1. *Inside* `FunctionalFitnessDecisionEngine.decide` (deep) — would require threading a new constraint type through `ProgrammingDecisionInput`, a pure/no-`@Model` type (`ProgrammingDecisionEngine.swift:66-68` — deliberately kept free of any `@Model` dependency). This is exactly where the actual per-week Stimulus adjustment happens, so it is the right place for the *check*, but the engine itself cannot reach across to a sibling `ProgramInstance` (it never imports `SwiftData`) — the constraint value must be computed **before** this call and handed in as a plain value, not derived by the engine itself.
2. *At* `RollTacticalWindowUseCase.rollForward`'s per-component loop (outer) — this is the correct place to **compute** the constraint (it already has `mix.orderedComponents`, the current `ModelContext`, and — given the ordering fix above — every already-materialized sibling session for this exact week), then pass the computed, plain value down into `materializeWeek` → `ProgrammingDecisionInput`, mirroring the exact existing `exposureHistory` parameter-passing convention at lines 149-154.

**Recommended seam:** compute the constraint in `rollForward` (a new small, pure, derived-context step — see Step 12), add one optional field to `ProgrammingDecisionInput`, and add exactly one more check to `FunctionalFitnessDecisionEngine.decide`'s existing fixed-priority chain (Step 3/7 below) — consistent with, not a replacement for, the engine's own documented "checks N dimensions in a fixed order, adjusts the first violated" philosophy (`FunctionalFitnessDecisionEngine.swift:12-19`).

**Correction (round 2, correction 2): "primary before supporting" is REJECTED as the general ordering fix.** The round-1 audit proposed sorting `rollForward`'s loop by `GoalPriority` so protected components materialize before constraint-consuming ones. This conflates two orthogonal concepts exactly like Step 2 warns against: `GoalPriority` expresses *how protected a component's stress budget is*, not *which components must materialize before which others can read their stress*. Stress-tested against six cases:

| Case | Priority-ordered ("primary first")? | What actually determines correct order |
|---|---|---|
| (A) primary HYP + supporting FF | Works, but only by accident | HYP is a stress-*producer* (no constraint-consuming stage exists for it); FF is the *consumer* |
| (B) primary FF + supporting Strength | **Breaks** — "primary first" would materialize FF before Strength even exists this week, leaving FF with nothing to read | Strength is still the producer regardless of its priority; FF is still the consumer regardless of its priority |
| (C) two `.secondary` components | **Undefined** — priority ties, "primary first" has no answer | Producer/consumer role, not priority, still resolves it (e.g. secondary HYP produces, secondary FF consumes) |
| (D) multiple components at the same priority | Same as (C) | Same |
| (E) 2 HYP + 2 FF + 2 Running | Works for HYP/Running vs FF, coincidentally | Producer/consumer split, not priority, is what actually generalizes |
| (F) FF-only, multiple FF sessions (no HYP at all) | **Meaningless** — there is no "primary" to order against | FF components must coordinate with EACH OTHER — a same-role, same-priority-tier case priority ordering cannot express at all |

Case (F) alone disqualifies "primary before supporting" as the general rule: intra-FF coordination is not a primary/supporting relationship, it is siblings-of-the-same-role coordinating with each other.

**Chosen solution — Option B, two-pass orchestration, keyed on producer/consumer role (a `ProgrammingSystemKind` classification), never on `GoalPriority`:**

- **Pass 1 (producers):** materialize every component whose `programmingSystem` has no constraint-*consuming* stage today — currently `.hypertrophy`, `.powerlifting`, `.interval` (SteadyState is handled separately already, per `rollForward`'s existing `continue`). These already stamp a CP.1 `TrainingStressProfile` and need no cross-modality input to do so.
- **Pass 2 (consumers):** materialize every component whose `programmingSystem` DOES have a constraint-consuming stage — currently only `.functionalFitness` — in `orderedComponents` order among themselves. Each one reads every Pass-1 session already materialized THIS week (Step 5's gate) plus Step 6's new current-week context, incrementally updated as each Pass-2 component in turn materializes.
- **What determines the classification:** which `ProgrammingSystemKind` has a real constraint-consuming call site (i.e. its materializer calls something like `FunctionalFitnessDecisionEngine.decide`, which can accept an added constraint input) — today that is `.functionalFitness` alone. This is **not** `GoalPriority`-keyed at all: a `.primary` FF-only mix (case F) still runs entirely in Pass 2, ordered only among its own FF siblings; a `.secondary` Hypertrophy component still runs in Pass 1 regardless of its priority (case C/D).
- **Case (F) resolution:** for an FF-only mix, Pass 1 is empty and Pass 2 processes every FF component in `sortIndex` order. This is NOT a special case of the two-pass split — it is what the split degenerates to when there are no producers, and it is exactly where Step 6's incrementally-built current-week context becomes the ONLY coordination mechanism (the first FF component in the pass sees an empty context; the second sees the first's already-programmed decision; and so on). The two-pass split and Step 6's context are complementary, not the same mechanism: Pass 1/2 answers "which components exist to read from," Step 6 answers "how does a same-role sibling coordinate with another same-role sibling once both are in the consuming pass."
- **Option A (pure priority ordering)** — rejected per the table above (fails cases B, C, D, F).
- **Option C (precompute from templates/prescriptions, no materialization sequencing at all)** — audited and rejected for now: Hypertrophy's real per-week values (weight/reps/RIR) are resolved through `StrengthProgressionEngine`'s autoregulation chain (previous week's actual logged results feed the next), so "what will this sibling look like this week" is not knowable from the template alone before materialization — only after. This option would require duplicating real resolution logic outside the materializer, which is exactly the kind of second, competing computation this project's rules forbid. Not pursued.
- **Option D** — no other two-phase pattern was found already native to `SchedulingPipeline`/`RollTacticalWindowUseCase` worth mirroring; Option B is a minimal, purpose-built addition to `rollForward`'s existing single loop, not a borrowed pattern.

This requires modifying `rollForward`'s single loop into two passes (still one function, still one `ModelContext`, no redesign of anything else) — the sort key is "does `component.programmingSystem` have a constraint-consuming stage," not `GoalPriority.ordinal`.

### Step 2 — `GoalPriority` vs `AdaptationObjective`: kept distinct

- **`GoalPriority`** answers: *how protected is this component's stress budget from being encroached on by others?* It is read today by `ConcurrentScheduler.processingOrder`/`priorityOrdinal` (`ConcurrentScheduler.swift:193-211`) purely for calendar-placement precedence. CP.2 reuses the exact same enum for a second, analogous purpose: `priority == .primary` is what makes a component's stress dimensions "protected" in the `ConstraintEligibility` sense (§3a) — i.e. it answers *whose stress a competing candidate is not allowed to compromise*.
- **`AdaptationObjective`** (locked 7-case taxonomy, §4) answers: *why does this component exist, and what stimuli would actually serve it?* CP.2 reads it to answer a completely different question: *given that FF is unprotected/supporting, which of FF's own candidate stimuli would actually serve ITS OWN stated purpose* (`[.workCapacity, .aerobicCapacity, .power]` → favors medium/long duration, higher-volume-tolerant formats, short explosive low-fatigue content — exactly the per-case programming-decision mapping already locked in §4's enum comments) — independent of whether anything is protected at all.
- **Concretely, in the reference case:** Hypertrophy's `priority = .primary` tells CP.2 "protect this component's `lowerBodyLoad`/`systemicDemand` this week" (an eligibility-gate input, Step 3). FF's `adaptationObjectives = [.workCapacity, .aerobicCapacity, .power]` tells CP.2 "among whatever remains eligible, prefer medium/long-duration metabolic-conditioning-leaning candidates over, say, a pure skill/gymnastics stimulus" (a preference-ranking input). The two never collapse: a component could be `.primary` with objective `.workCapacity` (protection with no bearing on which stimuli serve it), or `.supporting` with objective `.maxStrength` (an unprotected component whose own content should still favor low-variety, high-systemic-tolerance stimuli) — orthogonal axes, exactly as CLAUDE.md rule 19a already requires orthogonality between adjacent-but-distinct planning concepts.

### Step 3 — Seam-level audit (A–G)

`FunctionalFitnessStressProfileMapper.map(stimulus:)` (`FunctionalFitnessStressProfileMapper.swift:9-37`, confirmed unmodified by CP.1) already classifies stress from **`Stimulus` alone** — before `WorkoutFormat`, before movement-slot/exercise resolution. CP.1's entire cross-modality vocabulary is therefore already anchored at the `Stimulus` grain. Cross-checked against the real internal generation sequence: Stage A/B (`Stimulus`/`WorkoutFormat`, fixed at configuration time, Step 1) → per-week `Stimulus` adjustment (`FunctionalFitnessDecisionEngine.decide`, produces `nextStimulus`) → Stage D (movement/exercise resolution, `FunctionalFitnessMaterializer.swift:87-110`, consumes `decision.nextStimulus`) → Stage E (validation, consumes the same). There is exactly one point where a `Stimulus` value exists in complete, checkable form before anything downstream commits to it: `decision.nextStimulus`, the instant `decide()` returns.

- **(A) whole FF sessions** — too coarse; a session already contains `WorkoutFormat`+movements+load, more than CP.2 needs to gate.
- **(B) `Stimulus` candidates** — **the answer.** Matches CP.1's own classification grain exactly (no new grain introduced), matches the one real per-week decision point (`decide()`'s output), and every dimension CP.2 needs to reason about (duration domain, intensity, loading, movement function, modality mix) is already a `Stimulus` field.
- **(C) `WorkoutFormat` candidates** — `WorkoutFormat` (`WorkoutFormat.swift:8-18`) is a structural container "deliberately separate from `Stimulus`" (its own doc comment) — two workouts sharing a format can have unrelated stimuli. Gating at this level would conflate structure with content; not appropriate.
- **(D) `MovementFunction`/movement candidates** — already a `Stimulus` sub-field (`movementFunctions`); gating here alone would miss `loading`/`intensity`/`duration`, which independently drive stress (Step 5's protected-adaptation principle needs all of them together).
- **(E) loading candidates** — same reasoning as (D); a sub-field, not a standalone gate.
- **(F) duration/time-domain candidates** — same.
- **(G) multiple levels** — unnecessary complexity for the smallest useful milestone (Step 16); (B) already carries every dimension (D)-(F) would isolate, without needing separate plumbing for each.

**Conclusion: CP.2 operates at level (B) — `Stimulus` candidates — consuming the same `ProgrammingDecisionOutput.nextStimulus` seam CP.1's own mapper already reads from.**

### Step 4 — Candidate CP.2 input classification

| # | Input | Classification | Why |
|---|---|---|---|
| 1 | `TrainingMixComponent.priority` | **REQUIRED NOW** | Defines which sibling's stress is protected (Step 2) — the entire eligibility gate depends on it. Real field, `TrainingMixComponent.swift:43`. |
| 2 | `TrainingMixComponent.adaptationObjectives` | **REQUIRED NOW (blocked on the field existing)** | Drives preference ranking among eligible candidates (Step 2/7). **Not yet a real field** — taxonomy locked (§4) but unimplemented; CP.2 cannot ship without it, so implementing this field is a CP.2 prerequisite, not a CP.2-internal decision. |
| 3 | Already-materialized neighboring sessions, this tactical window | **REQUIRED NOW** | The only way to know what a sibling actually did this week — real `Session`s already in `instance.sessions`/`day.sessions` by the time `rollForward`'s loop reaches FF, given Step 1's ordering fix. |
| 4 | `TrainingStressProfile` of those sessions, via `SessionStressComposer` | **REQUIRED NOW** | This *is* CP.1's entire payload — the reason CP.1 was built first. Composing it is a pure, already-existing, unchanged function call (`SessionStressComposer.compose(session)`). |
| 5 | Temporal distance/adjacency between sessions | **USEFUL LATER, NOT REQUIRED FOR THE SMALLEST MILESTONE** | Meaningful once CP.2 reasons about *which* day a candidate is destined for, but at Stage-A-adjustment time (before `ConcurrentScheduler` runs) no calendar day is assigned yet — `rollForward` computes the constraint pre-scheduling. Same-week is a sufficient granularity for the smallest useful milestone (Step 16); day-level adjacency stays `ConcurrentScheduler`'s job (Step 11). |
| 6 | Modality of neighboring sessions | **USEFUL LATER** | Interesting for future multi-Interval/SteadyState-contributing scenarios (§8's "FF-first, not only" scope), but for the reference case the modality is already implied by which component the `TrainingStressProfile` came from — redundant with #3/#4 for CP.2's first pass. |
| 7 | FF's own exposure history (`FunctionalFitnessExposureHistoryBuilder`) | **REQUIRED NOW, already wired** | Already flows into `decide()` today (`FunctionalFitnessMaterializer.swift:70`) — CP.2 adds one more check to the same engine that already consumes this; no new plumbing needed for this input specifically. |
| 8 | Movement-function exposure history | **NOT APPROPRIATE AT THIS LAYER (for CP.2's first pass)** | Already folded into #7 (`VarianceExposureRecord.movementFunctionsUsed`, consumed by `adjustForMovementFunction`, `FunctionalFitnessDecisionEngine.swift:107-134`) — a genuinely separate cross-modality movement-exposure ledger is not proven necessary yet (Step 9 explains why). |
| 9 | Planned-but-not-yet-materialized future source sessions | **NOT APPROPRIATE AT THIS LAYER — resolved empirically, not by assumption.** `rollForward`'s own doc comment (`RollTacticalWindowUseCase.swift:70-72`): "Rolls every not-yet-exhausted component of `mix` forward by **exactly the next real week** — never a batch of several weeks at once, and never a week whose inputs don't yet exist." There is no mechanism anywhere in this pipeline that materializes ahead of the current week for Hypertrophy/Powerlifting/Interval/FF (only SteadyState front-loads its whole block, `materializeFirstWindow` line 51-53, and is explicitly excluded from `rollForward`, line 93/155-156). **CP.2 must reason only about the currently materialized tactical window — there is no forward-looking data to see even if it wanted to**, for the 3HYP+2FF case or any other. This resolves the open question directly: it isn't a design choice, it's a structural fact about how far ahead this pipeline ever materializes. |
| 10 | Previously completed vs. merely planned sessions | **REQUIRED NOW, already the existing discipline** | `SessionStressComposer.compose` reads whatever blocks a `Session` actually has, regardless of `.completed`/`.scheduled` status — but `FunctionalFitnessExposureHistoryBuilder` (#7) already enforces "only `.completed` counts as exposure" (`FunctionalFitnessExposureHistoryBuilder.swift:20`, citing §27: don't count a skipped session). CP.2's cross-component stress input (#3/#4) should mirror this: a sibling's `.scheduled`-but-not-yet-attempted session's stress profile is real, already-decided programming (not a guess), so it's legitimate context for "what is programmed to happen this week," but a component's own *exposure history* (#7) must stay completed-only. Two different questions, already answered by two different existing mechanisms — CP.2 does not need to invent a third. |
| 11 | Readiness state | **NOT APPROPRIATE AT THIS LAYER — deferred, per §13** | FF readiness Level 2/5 remain explicitly deferred (§13/§19/§20). Feeding live readiness into CP.2 now would entangle two independently-deferred capabilities; keep them separate until each is designed on its own. |

### Step 5 — Protected adaptation principle

**⚠️ SUPERSEDED IN PART by "## CP.2 Final Design Lock" below (Blocker 1).** The `.ineligible` verdict in the table immediately below is based only on same-tactical-week co-occurrence, with no true calendar-day-adjacency evidence — this conflates "same week" with "adjacent day," which the Final Design Lock section identifies as an invalid jump and corrects: the same-week signal is downgraded to `.discouraged` (a preference), and true `.ineligible` is reserved for a real post-placement adjacency conflict. Read this Step 5 for the underlying `StressDimension`/threshold vocabulary (still correct and reused), not for the eligibility verdict itself.

**Anti-pattern (explicitly rejected):** "primary Hypertrophy trains legs this week → FF may not touch legs this week." This is wrong for two reasons proven by the real model: (a) it conflates *movement pattern* with *training stress* — exactly the error §11's round-1 correction already identified and fixed for strength-inside-FF, generalized here to the whole protected-adaptation question; (b) it would make FF's `adaptationObjectives` (e.g. `.workCapacity`, which per §4 "favors medium/long duration + higher-volume-tolerant formats," often naturally locomotion/leg-involving) nearly unsatisfiable whenever Hypertrophy trains legs at all, which given a full-body 3-day split (§14) is every single week — a rule that broad isn't protecting Hypertrophy, it's disabling FF.

**Corrected rule:** primary Hypertrophy protects its own **specific stressed `StressDimension`s this week** (`lowerBodyLoad`, `systemicDemand`, `recoveryDemand`, etc. — read straight off its real, CP.1-stamped `TrainingStressProfile`, never inferred from exercise names), not "everything that overlaps a body region." A candidate FF `Stimulus` is `.ineligible` only when its own resulting stress on the SAME dimension would itself clear the same conservative threshold `InterferenceAvoidanceRule.conservativeDefault` already uses (`.high` — `SchedulingTypes.swift:172-175`) — i.e., CP.2's eligibility gate is a **pre-emptive, same-vocabulary application of the exact rule `ConcurrentScheduler` already enforces reactively**, just applied before FF content exists instead of after two already-committed sessions collide.

| Hypertrophy this week (CP.1 `TrainingStressProfile`) | FF candidate `Stimulus`'s implied stress | Verdict |
|---|---|---|
| `lowerBodyLoad = .high` (peak week, e.g. week 4/RIR1) | Candidate implies `lowerBodyLoad = .high` (e.g. heavy squat-loaded weightlifting stimulus) | `.ineligible` — same dimension, both clear `.high` |
| `lowerBodyLoad = .high` | Candidate implies `lowerBodyLoad = .low`/`.none`, `upperBodyLoad = .moderate` (upper-skew metcon) | `.eligible` — no shared dimension breach, regardless of "legs were trained this week" being true |
| `lowerBodyLoad = .moderate` (early week, RIR3) | Candidate implies `lowerBodyLoad = .moderate` | `.eligible` (below `.high` threshold — matches `conservativeDefault`'s own bar exactly, no new threshold invented) |
| Deload week (real, lower CP.1-stamped profile) | Any candidate | Constraint loosens across the board — **not because Concurrent Programming reads `isDeload`, but because the profile it reads (Hypertrophy's `TrainingStressProfile`) is itself genuinely lower that week** (CP.1's `StrengthTrainingStressMapper` has zero `isDeload` parameter — the reduced stress is an emergent property of the real reduced weight/reps/sets, not a label). Mirrors §14's corrected week-5 row. |

This directly reuses `StressDimension`/`LoadLevel`/`InterferenceAvoidanceRule.conservativeDefault` — no new vocabulary, no new threshold table (CLAUDE.md rule 10). **Correction (round 2, correction 3): no rule anywhere in this design reads `TrainingWeek.isDeload`, `isDeload`, or any other source label. Concurrent Programming's only observable input is the already-stamped `TrainingStressProfile` — the same discipline CP.1 itself established.**

### Step 6 — Current-week FF programming context (round 2, correction 1) + FF‑A/FF‑B pairing, derived not templated

**Round-1 finding, now corrected as insufficient:** the round-1 audit concluded FF-A/FF-B same-week differentiation could only come from (a) genuinely different prior-week completed exposure history, or (b) differing amounts of already-materialized sibling Hypertrophy stress. This is wrong — it misses the case where FF-B should react to FF-A's own already-programmed (not-yet-performed) intent this same week, which neither (a) nor (b) can express.

**Why `FunctionalFitnessExposureHistoryBuilder`/`VarianceExposureRecord` cannot represent this, confirmed by direct re-read:**
- `FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn:)` filters `$0.status == .completed` and requires a real `block.functionalFitnessResult` to exist before constructing a record (`FunctionalFitnessExposureHistoryBuilder.swift`) — its own doc comment cites §27: "never a scheduled-but-not-yet-attempted prescription." This is a hard, correct invariant — FF-A's just-decided, not-yet-performed `Stimulus` must NOT be added to this builder's output, or every downstream consumer of "exposure history" silently starts meaning something different (a real correctness regression, not a refinement).
- `VarianceExposureRecord`'s own fields (`ProgrammingDecisionEngine.swift`) are: `date: Date` (sourced from `result.completedAt` — there is no `completedAt` for a not-yet-performed decision), `durationDomain`, `loading`, `movementModalityMix`, `movementFunctionsUsed`, `skillDemand`, `wasHighIntensity`. Even though the non-`date` fields could structurally hold a planned `Stimulus`'s values, the type's entire reason for existing is "this really happened" — reusing it for planned intent would be a type-level lie every future reader of `[VarianceExposureRecord]` would have to know to distrust. **Not reused.**

**New type — `CurrentWeekFunctionalFitnessProgrammingContext` (name chosen to match this repo's existing derived-per-week-context naming convention, e.g. `TacticalMaterializationContext`, `IntervalWeekContextBuilder`'s output — not locked, easily renamed at implementation time):**
```swift
/// Derived, non-persisted, built fresh inside RollTacticalWindowUseCase.rollForward's
/// Pass 2 loop — NOT completed-exposure history (see FunctionalFitnessExposureHistoryBuilder,
/// which this deliberately does not touch or extend). Answers "what has already been
/// PROGRAMMED for this tactical week, regardless of whether it has been performed yet,"
/// a genuinely different question from "what did the athlete actually do."
struct CurrentWeekFunctionalFitnessProgrammingContext {
    /// One entry per FF component already materialized earlier in this same Pass 2 —
    /// appended incrementally as each sibling's decide() call returns, never read back
    /// from persistence.
    var alreadyProgrammedThisWeek: [ProgrammedStimulusSummary]
}

struct ProgrammedStimulusSummary {
    var componentID: UUID
    var stimulus: Stimulus
}
```
Constructed once per Pass 2 (Step 1), starting empty, and appended to after each FF component's `decide()` call returns — never read from or written to a `ModelContext`, never crosses a materialization boundary, discarded at the end of the `rollForward` call. Passed as a new field on `ProgrammingDecisionInput` (alongside the existing `exposureHistory`), so `FunctionalFitnessDecisionEngine.decide` gains one more real input without touching its existing four checks.

**Concrete pairing mechanism for the reference case:** FF-A materializes first in Pass 2 (context empty) and produces its `Stimulus`. Before FF-B materializes, `rollForward` appends FF-A's `Stimulus` to the context. FF-B's `decide()` call now has both (a) the same cross-modality Hypertrophy-stress input from Step 5, and (b) FF-A's already-programmed intent from this new context — see Step 12 for the concrete pairing rules this enables. The differentiator between FF-A and FF-B is therefore genuinely two independent, additive signals working together: cross-modality stress (Step 5, shared by both) and intra-FF same-week awareness (this step, asymmetric — only FF-B sees FF-A, never the reverse, by construction of the incremental append). Neither FF-A nor FF-B is privileged; "FF-A" simply means "whichever FF component materializes first in `sortIndex` order this Pass 2" — an arbitrary but harmless tie-break, since this context only ever adds preference nudges, never eligibility exclusions (swapping which FF component goes first changes which specific stimulus lands on which session, never correctness).

### Step 7 — Concrete rule set for the reference case

**⚠️ SUPERSEDED IN PART by "## CP.2 Final Design Lock" below (Blocker 1).** The INELIGIBLE rule below is renamed DISCOURAGED there — see the Final Design Lock's revised rule set for the actual verdicts; true ineligibility only exists post-placement.

Kept to the smallest set that proves the milestone (Step 16), every rule using only real, already-existing fields:

- **INELIGIBLE** *(now DISCOURAGED pre-placement — see Final Design Lock)*: FF candidate `Stimulus` whose implied `lowerBodyLoad` (per Step 5's derivation) is `.high`, while this week's real Hypertrophy `TrainingStressProfile.lowerBodyLoad` (composed via `SessionStressComposer` over the sibling's already-materialized sessions) is also `.high`, AND Hypertrophy's `priority == .primary`. (Mirrors `InterferenceAvoidanceRule.conservativeDefault`'s own `lowerBodyLoad ≥ .high` rule exactly, applied pre-generation instead of post-hoc.)
- **DISCOURAGED**: FF candidate implies `systemicDemand`/`recoveryDemand == .moderate` while Hypertrophy's own this-week profile is already `.high` on the same dimension, with `priority == .primary` — genuinely eligible (does not breach the hard `.high`/`.high` gate) but adds real cumulative load on top of an already-demanding protected week.
- **NEUTRAL**: FF candidate whose implied dimensions don't overlap any of Hypertrophy's `.high` dimensions at all, and doesn't obviously serve `[.workCapacity, .aerobicCapacity, .power]` either (e.g. a moderate skill-only stimulus with no strong duration/intensity signature).
- **PREFERRED**: FF candidate whose `targetDurationDomain`/`intensity`/`movementModalityMix` match at least one of the component's own `adaptationObjectives`' documented decision (§4's per-case comments — e.g. `.workCapacity` → medium/long duration + `.amrap`/`.forTime`/`.chipper`-shaped; `.power` → short, explosive, low-fatigue-cost) AND clears the eligibility gate above.

Each rule: one sentence, deterministic (pure function of two already-real `TrainingStressProfile`s + `GoalPriority` + `[AdaptationObjective]`), testable (identical inputs → identical verdict, no clock/randomness), grounded (every field cited above is a real, already-existing or already-locked type), coarse (four categorical buckets, no numeric weighting — same discipline as `TrainingStressProfile`'s own founding doc comment).

### Step 7a — Shared compatibility predicate, not duplicated threshold logic (round 2 recheck)

**Confirmed by direct re-read of `SchedulingTypes.swift`: no new predicate is needed.** `InterferenceAvoidanceRule` — `dimension`, `threshold`, and the pure method `func triggers(_ a: TrainingStressProfile, _ b: TrainingStressProfile) -> Bool` — is defined in `SchedulingTypes.swift`, a shared value-type file owned by neither `ConcurrentScheduler.swift` nor any FF file. `ConcurrentScheduler` merely *consumes* `SchedulingConstraints.interferenceRules` (which defaults to `InterferenceAvoidanceRule.conservativeDefault`) — it does not own the type's definition. This means CP.2 can call the exact same predicate directly:

```swift
let rule = InterferenceAvoidanceRule(dimension: .lowerBodyLoad, threshold: .high)
let ineligible = rule.triggers(hypertrophyProfile, candidateProfile)  // same function, same threshold, same file
```

Both `FunctionalFitnessDecisionEngine`'s new check and `ConcurrentScheduler` call the SAME `triggers(_:_:)` on the SAME `InterferenceAvoidanceRule` value — CP.2 USES it, `ConcurrentScheduler` USES it, and `SchedulingTypes.swift` owns it; neither consumer owns the other's responsibility, and the two systems can never independently drift, because there is only one implementation to drift from. No new shared free predicate needs to be designed or added — this recheck's own premise (that reuse might not be clean) does not hold once `InterferenceAvoidanceRule`'s actual home is confirmed.

### Step 8 — Temporal representation

**Reuse `InterferenceAvoidanceRule`'s concept as-is — do not invent a new one, and do not need to at CP.2's own decision point.** `ConcurrentScheduler`'s same-day/adjacent-day (`±1` offset) adjacency check (`ConcurrentScheduler.swift:494`, `neighbors = (dayOccupants[offset - 1] ?? []) + (dayOccupants[offset + 1] ?? [])`) operates strictly on already-scheduled calendar offsets — a concept that does not exist yet at CP.2's own decision point (Step 3 established CP.2 runs *before* `ConcurrentScheduler`, at `rollForward` time, when no calendar day is assigned). CP.2 therefore does not need day-level adjacency at all for its own gate — same-week is its only real granularity (Step 4 #5) — and `ConcurrentScheduler`'s existing day-adjacency check remains exactly what it is today: the safety net that catches whatever CP.2 didn't (or couldn't, pre-generation) prevent. No new temporal type; CP.2 and `ConcurrentScheduler` operate at two different, already-distinct temporal grains (week vs. day) that were already implicit in the pipeline, now made explicit.

### Step 9 — `TrainingStressProfile` direct consumption — no new `CrossModalityExposureSummary` needed for CP.2

§8 of this document (locked) proposed a derived `CrossModalityExposureSummary(for:asOf:window:)`. Audited against CP.2's actual, now-concrete need: CP.2's Step 5 rule only ever needs **this week's already-materialized sibling sessions' `TrainingStressProfile`, composed via the existing, unchanged `SessionStressComposer.compose(session)`** — a same-week, no-decay, no-aggregation-across-multiple-past-weeks lookup. Nothing in the reference case (or the stress-tests, Step 14) requires reading further back than the current week. **Necessity is not proven for CP.2 — defer `CrossModalityExposureSummary`, as §8 itself already anticipated ("Concurrent Programming layer's constraint output for any given week" is meant to be recomputed per week, not accumulated).** If a future stage needs a genuine rolling multi-week aggregate (e.g. "3 consecutive high-`systemicDemand` weeks"), design it then, against that stage's own real requirement — not now, speculatively.

### Step 10 — Strength-inside-FF under primary Hypertrophy

`Exercise.movementFunctions: [MovementFunction]` (`Exercise.swift:38`, Stage 4E addition) already shares the exact same closed enum FF's own `Stimulus.movementFunctions` uses — the movement-pattern check needs **no new type**:

1. **Movement-pattern check**: `Set(candidateStimulus.movementFunctions) ∩ Set(hypertrophyExerciseSlot.resolvedExercise.movementFunctions)` — non-empty at moderate-or-higher load this week ⇒ flag for check 2 with heightened scrutiny (per §11's corrected rule); empty ⇒ still must pass check 2 independently (§11's explicit fix: pattern-distinctness alone is never sufficient).
2. **Stress-eligibility check**: apply Step 5/7's same eligibility gate to the FF weightlifting candidate's own implied `TrainingStressProfile` (via the existing, unmodified `FunctionalFitnessStressProfileMapper.map(stimulus:)`) against Hypertrophy's real this-week profile.

**Concrete example (reference case):** an FF `Stimulus` with `movementModalityMix` including `.weightlifting`, `movementFunctions: [.squatLoaded]`, `loading: .heavy` the same week as a real Hypertrophy Day with `lowerBodyLoad = .high` (peak week): check 1 finds pattern overlap (both `.squatLoaded`) → check 2 independently evaluates the candidate's own implied `lowerBodyLoad` (`.high`, since `loading: .heavy` + `.squatLoaded` → `loadingLevel` applied to `lowerBodyLoad` per `FunctionalFitnessStressProfileMapper.swift:21`) against Hypertrophy's `.high` → **`.ineligible`**, for the stress reason, not merely the pattern-overlap reason (§11's exact required distinction). The same candidate during a deload week (Hypertrophy's `lowerBodyLoad` reduced) → check 2 passes even though check 1 still finds pattern overlap → **`.eligible`** — proving the two checks are independent, as required.

### Step 11 — Concurrent-Programming-vs-Scheduler boundary, preserved

`ConcurrentScheduler`'s own doc comment (`ConcurrentScheduler.swift:3-9`), verbatim: *"Places already-materialized Sessions onto a tactical calendar window. `ConcurrentScheduler` never generates training methodology, never prescribes intensity and never picks exercises… Its only job is calendar placement."* CP.2 must never assign a calendar day, never touch `SchedulingWindow`/`UserAvailability`, and never duplicate `InterferenceAvoidanceRule`'s day-adjacency logic (Step 8). `ConcurrentScheduler` must never gain a stimulus-selection or exercise-selection responsibility — it already receives fully-formed `Session`s and must keep doing exactly that. CP.2 decides **WHAT** (is this `Stimulus` candidate eligible/preferred, before any Session exists); `ConcurrentScheduler` decides **WHEN** (which day, given Sessions that already exist) — the two never overlap, confirmed by the real code: CP.2's seam (`rollForward`'s per-component loop, before line 167's `SchedulingPipeline.propose` call) runs strictly before `ConcurrentScheduler` ever sees any of this week's Sessions.

### Step 11a — `AdaptationObjective` assignment seam: where `LongTermPlanner` actually knows enough to assign one honestly

Traced every real `TrainingMixComponent(...)` construction site in `LongTermPlanner.swift` (`candidateMixTemplates`'s per-`PhaseType` dispatch to `muscleGainFocusedHypertrophyMix`/`muscleGainVariedMix`/`fatLossConditioningFocusedMix`/`fatLossVariedMix`/`strengthFocusedMix`/`enduranceFocusedMix`/`enduranceVariedMix`/`functionalFitnessFocusedMix`/`maintenanceMix`/`lowerDemandGenericMix`, lines 614-939). **This must be a per-construction-site mapping, never a global per-`ProgrammingSystemKind` table** — the same `programmingSystem` gets a different honest objective (or none) depending on which real candidate builder constructs it:

| Builder (real `phase.type` context) | Component | Honest `adaptationObjectives`? |
|---|---|---|
| `muscleGainFocusedHypertrophyMix` (`.muscleGain`) | Hypertrophy, primary | `[.muscleGain]` — direct: phase type IS the objective |
| | Zone 2 Conditioning, supporting, steadyState | `[.aerobicCapacity]` — defensible: "Zone 2"/steadyState is definitionally submaximal aerobic work, independent of phase type |
| `muscleGainVariedMix` (`.muscleGain`) | Strength (hypertrophy), primary | `[.muscleGain]` |
| | **Functional Fitness, supporting** | **Leave empty — insufficient real signal.** Phase type (`.muscleGain`) says nothing about which of the 7 objectives FF should serve; the planner has no per-sub-objective signal for FF anywhere today. **This is the user's own reference case's FF component — its illustrative `[.workCapacity, .aerobicCapacity, .power]` combination is NOT currently producible by `LongTermPlanner`; it would need a new signal source (explicit user/UI configuration, or a new candidate-mix template with a stated FF sub-purpose) before this exact assignment is honest, not fabricated.** |
| | Running (steadyState), supporting | `[.aerobicCapacity]` |
| `fatLossConditioningFocusedMix` (`.fatLoss`) | Conditioning (interval), primary | `[.anaerobicCapacity]` — defensible from `programmingSystem == .interval` itself (repeated high-intensity effort is interval's definitional shape), not from phase type |
| | **Resistance Training (hypertrophy), secondary+required** | **Leave empty — real gap found.** This component's actual purpose is muscle *retention* during fat loss ("protects muscle," the builder's own doc comment) — not muscle *gain*. None of the 7 locked objectives honestly express "retention"; assigning `.muscleGain` here would be dishonest. This is the same category of hole the round-2 taxonomy lock already closed once for `.maintenance` (a direction/state, not an objective) — flagged as a genuinely unresolved product question in item 12 below, not silently patched. |
| | Easy Aerobic (steadyState), supporting | `[.aerobicCapacity]` |
| `fatLossVariedMix` (`.fatLoss`) | Functional Fitness, primary | Leave empty — same FF gap as above |
| | Resistance Training (hypertrophy), secondary+required | Leave empty — same retention gap as above |
| `strengthFocusedMix` (`.strength`) | Powerlifting, primary | `[.maxStrength]` — direct: phase type AND `programmingSystem == .powerlifting` both agree |
| `enduranceFocusedMix`/`enduranceVariedMix` (`.enduranceEvent`) | Named activity (steadyState), primary | `[.aerobicCapacity]` |
| | Interval Work, secondary | `[.anaerobicCapacity]` |
| | Strength Maintenance (hypertrophy), supporting | Leave empty — same retention gap (label literally says "Maintenance") |
| `functionalFitnessFocusedMix` (`.functionalFitness`) | Functional Fitness, primary, required | Leave empty — same FF gap; phase type alone doesn't pick a sub-objective out of FF's inherently multi-modal 7-way space |
| `maintenanceMix` (`.maintenance`) | Every carried-forward component | **Not phase-type-derived at all** — the honest seam is a straight carry-forward: once the field exists, `MaintenanceComponentDecision` should copy `component.adaptationObjectives` unchanged from `previousMix`'s own component into the new one (a one-line addition alongside the existing `sourceLabel`/`sourceSystem`/`sourcePriority` carry-forward, `LongTermPlanner.swift:679-682`/`793-797`). Maintenance changes dose, never purpose. |
| `lowerDemandGenericMix` (`.recovery`/`.transition`/fallback) | General Conditioning (steadyState), primary | `[.aerobicCapacity]` |

**Headline finding:** only `.muscleGain`, `.maxStrength`, `.aerobicCapacity`, `.anaerobicCapacity` currently have a real, non-fabricated per-construction-site signal anywhere in `LongTermPlanner`. **`.power`, `.workCapacity`, and `.skillAcquisition` have NO current assignment seam at all** — no existing candidate builder's real inputs (phase type, programming system, label) distinguish them. They would stay empty for every planner-generated component until a new signal source is added (explicit user/UI sub-objective selection is the most likely candidate, out of scope here). This is a genuinely new finding, not previously stated: **the reference case throughout this whole document (FF = `[.workCapacity, .aerobicCapacity, .power]`) is illustrative of what CP.2 should DO with that data once it exists, not a claim that `LongTermPlanner` can produce it today.**

### Step 11b — Objective → existing `Stimulus` preference mapping

For each locked objective, the preference is stated as a direction over already-real `Stimulus` fields — never a new field, never a numeric formula:

| Objective | Existing `Stimulus` fields it can honestly influence | Preference direction |
|---|---|---|
| `power` | `intensity`, `targetDurationDomain`, `movementModalityMix` | Prefers `intensity == .high` + `targetDurationDomain == .short` + `movementModalityMix` weighted toward `.weightlifting` (single, high-force efforts, not sustained) |
| `aerobicCapacity` | `targetDurationDomain`, `intensity`, `movementModalityMix` | Prefers `targetDurationDomain == .long` (or `.medium`) + `intensity == .low`/`.moderate` (sustainable) + `movementModalityMix` weighted toward `.metabolicConditioning`/monostructural |
| `workCapacity` | `systemicDemand`, `targetDurationDomain` | Prefers `systemicDemand == .high` combined with `targetDurationDomain == .medium` — the classic "sustained multi-modal hard output" signature; `systemicDemand` is exactly the field this objective's own name maps to |
| `skillAcquisition` | `skillDemand`, `movementFunctions` | Prefers `skillDemand == .high`, especially when `movementFunctions` includes `.gymnasticsPull`/`.gymnasticsPush` or weightlifting technical patterns — `skillDemand` is a direct, already-existing field match |
| `anaerobicCapacity` | `intensity`, `targetDurationDomain`, `systemicDemand` | Distinguished from `power` (single short max-effort) and `workCapacity` (sustained-but-moderate) by the specific combination `intensity == .high` + `targetDurationDomain` at `.short`-to-`.medium` + `systemicDemand == .high` — repeated high-intensity efforts, not one, and not sustained past `.medium` |
| `maxStrength` | `loading` (weakly) | **NO CP.2 MAPPING YET.** `loading == .heavy` is the closest available signal, but FF's coarse `LoadingClassification` cannot express true maximal-strength programming (%1RM, low-rep singles/doubles) the way source-authored Powerlifting's `SetPrescription`/RM resolution already does. This objective's real programming home is Powerlifting/Hypertrophy; it should inform a Strength-typed sibling's own protected priority, but never rank FF `Stimulus` candidates. |
| `muscleGain` | none honestly | **NO CP.2 MAPPING YET.** FF's `Stimulus` model has no field expressing volume-at-a-rep-range/mechanical-tension programming — this objective's real home is Hypertrophy exclusively. |

**Multiple simultaneous objectives — categorical resolution, no scoring.** A candidate `Stimulus` is `.preferred` if it clears Step 7's eligibility gate AND its direction aligns with AT LEAST ONE of the component's mapped `adaptationObjectives`; `.discouraged` only if it actively opposes a mapped objective's direction AND no other still-eligible candidate this same session could satisfy that objective at all this week (rare — normally, leaning toward one objective while not serving another is `.neutral`-to-`.preferred`, not opposed); `.neutral` otherwise. **A genuine cross-objective conflict (e.g. FF's real `[.workCapacity, .aerobicCapacity, .power]`: `power` prefers short/high-intensity, `aerobicCapacity` prefers long/sustainable — directly opposed directions) is never resolved by picking one "winning" objective or computing a weighted score.** Instead, coverage is achieved at the WEEKLY, multi-session level: FF-A can lean into `.power` this week, FF-B can lean into `.aerobicCapacity`, and together the component's full objective set gets served across its sessions — no single session is forced to satisfy every objective simultaneously. This is precisely what Step 6's current-week context and Step 11c below make possible.

### Step 11c — Current-week FF pairing rule, using Step 6's context

Once `CurrentWeekFunctionalFitnessProgrammingContext` exists, the minimum coarse pairing rules — additional checks appended to `FunctionalFitnessDecisionEngine`'s existing fixed-priority chain (duration domain → loading → modality → movement function, unchanged order and unchanged existing checks — Step 6/7's new checks run alongside, never reordering, the original four):

- If an already-programmed sibling FF session this week (`context.alreadyProgrammedThisWeek`) is short + high-intensity, **discourage** (never forbid) another short + high-intensity candidate for this session — provided an eligible alternative `Stimulus` can still satisfy this component's own `adaptationObjectives` (Step 11b's categorical rule; never force a worse-fitting candidate purely to differ).
- If a sibling FF session already emphasizes `movementModalityMix.weightlifting`, **prefer** a complementary mix (e.g. `.metabolicConditioning`/`.gymnastics`-leaning) for this session, when compatible with objectives.
- If a sibling was longer/aerobic-leaning, **do not force** this session toward `.power` unless `.power` is actually one of this component's own `adaptationObjectives` — pairing must never invent a preference the component's own objectives don't already justify.

**Real, empirically-confirmed detail this correction surfaces:** `LongTermPlanner.functionalFitnessParameterCandidates` (the only real production construction of `FunctionalFitnessProgramConfiguration`) passes `varianceConstraints: VarianceConstraints()` — every field `nil` (`LongTermPlanner.swift:1165`). Since every one of `FunctionalFitnessDecisionEngine`'s existing four checks starts with `guard let window = input.varianceConstraints.avoidRepeating...WithinSessions, window > 0 else { return nil }`, **FF's own variance/rotation engine never actually fires in the real default production configuration today** — every week, absent CP.2, `decide()` falls through all four checks to `.stimulusAsConfigured`, the unchanged baseline. This means CP.2's new checks (Step 5's cross-modality gate and this step's intra-FF pairing) would be the FIRST source of any real per-week stimulus variation in the actual default-configured production path — not an addition on top of already-active FF rotation, but, in the realistic default case, the only mechanism producing week-to-week or session-to-session difference at all. This is corrected into the walkthrough below rather than assumed away.

### Step 12 — Failure/fallback semantics (design only)

Hierarchy: **preferred → neutral → discouraged-but-eligible → explicit-constrained-fallback.** Genuine `.ineligible` candidates are never selected to "produce a workout anyway" — that would be exactly the kind of speculative safety-overloading CLAUDE.md rule 18 forbids one layer over (using an eligibility gate as a workaround defeats the reason it's a hard gate rather than a preference). When even discouraged-but-eligible is empty:

- **Broaden candidate generation** — not applicable at CP.2's own decision point: `FunctionalFitnessDecisionEngine.decide` doesn't choose among a generated candidate set today (Step 1) — it adjusts one fixed baseline along one dimension. "Broadening" here means CP.2's new check, like the existing 4, may itself choose *which* dimension to adjust (same mechanism, not a new one).
- **Relax only soft preferences** — always safe; this is exactly what "discouraged-but-eligible" already is, so this branch is never actually reached if the hierarchy above is honored correctly (discouraged is, by construction, always still eligible).
- **Surface a structured, typed unresolved-conflict fact** — the correct answer when CP.2's own eligibility gate would eliminate every dimension-adjustment the engine's fixed-priority chain could try. Modeled the same way `ScheduleIssue`/`ScheduleIssueCode` already are (`ScheduleIssue.swift:7-63`, `83-114`) — never a parsed string (CLAUDE.md rule 16, applied one layer earlier as §3a already anticipated): a new, additive `FunctionalFitnessReasonCode` case (e.g. `.concurrentConstraintUnresolved`) is the right shape, reusing the exact precedent `reasonCode`/`inputsSummary` already establish on `ProgrammingDecisionOutput` (`ProgrammingDecisionEngine.swift:69-74`) — display text (`inputsSummary`) stays separate from the typed `reasonCode`, exactly like `ScheduleIssue.reason` vs. `.code`.
- **Ask the scheduler for a different placement** — out of scope for CP.2 by the boundary in Step 11; if this is ever needed, it is `ConcurrentScheduler`'s existing soft-interference/day-shifting mechanism doing its job downstream, unchanged, not something CP.2 requests.

This is design only — no `FunctionalFitnessReasonCode` case is added in this pass.

### Step 13 — Full 13-step reference-week walkthrough — **CORRECTED: real Family A week 4 (RIR 1, the peak progressive week), not week 3**

Week 4 = `repGoalSchedule[3] == .rir(1)` (`HypertrophyProgramGenerator.swift:129-130`, index 3 of 4) — confirmed the genuinely heaviest real progressive week, reusing the exact real resolution CP.1's own decisive interference test already exercised (`TrainingStressProfileParityTests.swift`: `weekIndex: 3, isDeload: false`, `slotContext: { _ in .init(rmKilograms: 140, weekOneResolvedWeightKg: 140 * 0.85) }`, a Back Squat-carrying full-body session). The real 3-Day Full Body structure (§14) means all 3 HYP sessions this week are full-body, not split by body part — so all 3 realistically carry squat/press/pull-pattern work and all 3 classify at the week's peak intensity, not just one "leg day." Per Step 11c's finding, `VarianceConstraints()` is all-`nil` in the real default production configuration, so absent CP.2, FF's own 4-check chain never fires and every session's baseline `Stimulus` stays `.stimulusAsConfigured` (`LongTermPlanner.swift:1146-1161`'s fixed baseline) all week — CP.2 is therefore the sole source of any differentiation shown below, both cross-modality and intra-FF, which is the honest default-configuration case rather than an assumption that FF's own rotation is already active.

1. **All 3 HYP sessions' week-4 CP.1-derived stress context**: Day A/B/C, week 4 (RIR 1) — `StrengthTrainingStressMapper` (CP.1, unchanged) resolves RIR 1 → `intensityLevel == .high` per-prescription (its own `RIR≤1 → .high` rule) on the squat/press/pull work each full-body day carries; composed via unchanged `SessionStressComposer`, each of the 3 sessions' `TrainingStressProfile` carries `lowerBodyLoad = .high`, `overallIntensity = .high`, `systemicDemand = .high` — matching CP.1's own real decisive test exactly (`testRealHypertrophyAndRealFunctionalFitnessConflictIsNowVisibleToInterferenceRule`).
2. **FF-A's baseline `Stimulus`**: the one fixed Stage-A baseline (`LongTermPlanner.swift:1146-1161`) — `targetDurationDomain: .medium, intensity: .moderate, loading: .moderate, movementFunctions: [.squatLoaded, .gymnasticsPull, .monostructural], movementModalityMix: [weightlifting:1, gymnastics:1, metabolicConditioning:1], skillDemand: .moderate, systemicDemand: .moderate`. Identical every week at the baseline level (Step 1's corrected finding) — nothing week-specific happens until `decide()` runs.
3. **FF-A's completed-history variance input**: real default `VarianceConstraints()` is all-`nil` (Step 11c) — every one of the 4 existing checks short-circuits regardless of what `exposureHistory` actually contains; FF's own rotation contributes nothing this week in the realistic default case.
4. **FF-A's cross-modality eligibility/preference**: Step 5's gate reads Day A/B (already materialized in Pass 2, per Step 1's two-pass order — all of Pass 1's HYP sessions materialize before any FF component starts Pass 2) — `lowerBodyLoad = .high`, `priority == .primary`. Baseline's `movementFunctions` includes `.squatLoaded` with `movementModalityMix.weightlifting` — Step 11b's `power`/`workCapacity` preference directions would favor keeping it, but Step 5's hard gate checks the IMPLIED stress of that baseline (heavy squat-loaded weightlifting content → `lowerBodyLoad` would classify `.high` via `FunctionalFitnessStressProfileMapper`) against Hypertrophy's real `.high` this week → **`.ineligible`** on the baseline as configured.
5. **FF-A's final programmed `Stimulus`**: the new CP.2 check (added to the existing chain per Step 1/7) fires — the baseline's `.ineligible` squat-loaded/weightlifting-heavy shape is adjusted toward a `.eligible` alternative that still serves at least one of `[.workCapacity, .aerobicCapacity, .power]` (Step 11b): `movementFunctions` shifted off `.squatLoaded` toward `.gymnasticsPull`/`.monostructural`-dominant, `loading` reduced toward `.light`/`.bodyweightOnly`, `movementModalityMix` reweighted away from `.weightlifting` toward `.gymnastics`/`.metabolicConditioning` — an upper/monostructural-skewed, medium-duration, `.workCapacity`-serving stimulus, with a reason code explaining the adjustment (Step 12).
6. **The derived current-week context now containing FF-A**: `CurrentWeekFunctionalFitnessProgrammingContext.alreadyProgrammedThisWeek` gains one `ProgrammedStimulusSummary` — FF-A's final `Stimulus` from step 5, appended before FF-B materializes (Step 6).
7. **FF-B's baseline `Stimulus`**: identical fixed baseline as FF-A (step 2) — the SAME configured `targetStimulus`, since Stage A is per-component, not per-session.
8. **FF-B's completed-history variance input**: same as FF-A (step 3) — all-`nil` `VarianceConstraints`, no rotation fires from history.
9. **FF-B's cross-modality constraints**: same Step 5 gate against the same week-4 `.high` Hypertrophy profile (now all 3 HYP days materialized, per Pass 1 completing before Pass 2 starts) — the baseline is `.ineligible` for FF-B for the identical reason as FF-A.
10. **FF-B's same-week pairing preference from FF-A**: Step 11c's pairing rule reads the context from step 6 — FF-A already leaned upper/monostructural/gymnastics-heavy and `.workCapacity`-serving; the "prefer a complementary mix" rule nudges FF-B toward `.aerobicCapacity`'s own preference direction instead (Step 11b: longer `targetDurationDomain`, lower `intensity`, `.metabolicConditioning`-dominant) rather than repeating FF-A's exact adjusted shape.
11. **FF-B's final programmed `Stimulus`**: eligible (clears the same Step 5 gate as FF-A, for the same reason), and distinct from FF-A's for a stated, non-templated reason — FF-A resolved toward `.workCapacity` (shorter, gymnastics/monostructural-mixed), FF-B resolved toward `.aerobicCapacity` (longer, lower-intensity, monostructural-dominant) — driven by step 10's pairing rule reacting to step 6's real content, not a fixed "FF-A = X, FF-B = Y" template.
12. **The 5 real Sessions handed to `ConcurrentScheduler`**: 3 HYP (all `.high` lower-body/systemic) + FF-A (adjusted, upper/gymnastics-skewed, low lower-body implication) + FF-B (adjusted, aerobic/monostructural-skewed, low lower-body implication) via `SchedulingPipeline.propose`/`ScheduledProgramInput`, unchanged.
13. **Downstream scheduling result**: because CP.2 already pre-filtered the `lowerBodyLoad`-heavy baseline out of both FF sessions before they existed, `InterferenceAvoidanceRule.conservativeDefault`'s `lowerBodyLoad ≥ .high` rule (Step 7a — same predicate, called directly) finds no `.high`/`.high` pair among the 5 real sessions in the common case — a clean placement. If `ConcurrentScheduler`'s OTHER factors (availability, `requiredSpacingDays`, double-session limits) still can't find a fully conflict-free week, the honest outcome is unchanged from today: a soft `.interferenceConflict`/`.recoverySpacingCompromise` `ScheduleIssue`, never a hard failure — CP.2 reduces the frequency of this outcome, never claims to eliminate it (Step 8).

This walkthrough demonstrates BOTH mechanisms working together and staying genuinely separate: **cross-modality coordination** (Step 5, shared identically by FF-A and FF-B, driven by real Hypertrophy stress) and **intra-FF same-week coordination** (Step 11c, asymmetric, driven by FF-A's already-programmed-but-not-completed intent) — removing either one changes the outcome (without Step 5, both FF sessions would keep their heavy baseline; without Step 11c, FF-A and FF-B would resolve to the identical adjusted shape instead of complementary ones).

### Step 14 — Stress-test against other mixes — **updated for the two-pass orchestration (Step 1)**

| Mix | Handled without special-casing? |
|---|---|
| 2 HYP + 3 FF | Yes — Pass 1 (2 HYP) materializes fully, Pass 2 (3 FF) processes each in turn, each seeing every prior FF sibling via Step 6's incrementally-built context; same per-component computation, more iterations. |
| 4 FF + 1 Strength | Yes — Strength is the sole Pass-1 producer regardless of its `GoalPriority`; all 4 FF components run in Pass 2 and coordinate with each other exactly as in the reference case's FF-A/FF-B mechanism, now with 4 siblings instead of 2. |
| 2 HYP + 2 Running | Handled by the SAME two-pass split **once Interval/SteadyState become constraint-consuming** (still explicitly UNRESOLVED per §21 item 7) — until then, Running sessions are Pass-1 producers only (their `TrainingStressProfile` is readable by FF's Step 5 gate today, since CP.1 already stamps them), they just never themselves consume a constraint. Not built now — flagged, not solved speculatively. |
| 2 HYP + 2 FF + 2 Running | **Explicitly NOT solved here.** HYP and Running both land in Pass 1 (both producers today); FF's Pass-2 gate is still pairwise (one candidate vs. one already-materialized sibling at a time) — extending it to reason about 3+ simultaneously-`.high` producers in aggregate is the same genuinely different, UNRESOLVED problem §15/§19 already flag. The two-pass split does not solve aggregate interference; it only correctly sequences who materializes before whom. **Left UNRESOLVED, not defaulted-to-solved.** |
| FF-only, multiple FF sessions (e.g. FF-A/FF-B/FF-C) | Pass 1 is empty; Pass 2 processes every FF component in `sortIndex` order, each consuming Step 6's incrementally-built context from every FF sibling materialized earlier in the same pass — this is the case that most directly exercises intra-FF coordination with NO cross-modality signal at all, and requires no special-casing beyond "Pass 1 is empty this time." |

### Step 15 — Domain impact classification

| Item | Classification | Persist? |
|---|---|---|
| `TrainingMixComponent.adaptationObjectives: [AdaptationObjective]` | NEW DOMAIN CONCEPT (CP.2 prerequisite — Step 4/9) | Yes |
| `ConstraintEligibility`/`ConstraintPreference`/`ConstraintViolationReason` (§3a, unchanged) | NEW DOMAIN CONCEPT | No |
| `CurrentWeekFunctionalFitnessProgrammingContext` / `ProgrammedStimulusSummary` (Step 6) | DERIVED VALUE — built fresh per `rollForward` call, discarded at the end of it | No |
| One new `FunctionalFitnessDecisionEngine` check function for cross-modality eligibility (Step 5/7) | ENGINE extension — new pure function inside the existing engine, not a new engine | No |
| One new `FunctionalFitnessDecisionEngine` check function for intra-FF pairing (Step 11c) | ENGINE extension, same as above | No |
| Two new optional fields on `ProgrammingDecisionInput` (a cross-modality constraint value + the current-week context) | ENGINE INPUT | No — plain values, computed fresh per call |
| The constraint-computation step itself, called from `RollTacticalWindowUseCase.rollForward`'s Pass 2 loop | APPLICATION SERVICE (mirrors `FunctionalFitnessExposureHistoryBuilder`'s own shape) | No |
| `rollForward`'s two-pass split (producer pass, then consumer pass) | APPLICATION SERVICE — an orchestration change to existing code, keyed on `ProgrammingSystemKind` role, never `GoalPriority` | No (behavior-only) |
| A new `FunctionalFitnessReasonCode` case for unresolved conflict (Step 12) | ENGINE OUTPUT (typed, additive) | No — design only |
| `CrossModalityExposureSummary` | **DEFERRED — necessity not proven (Step 9)** | N/A |

No new persisted table, relationship, or competing source of truth anywhere in this design — the only new persisted field is `adaptationObjectives`.

### Step 16 — Smallest useful CP.2 milestone — **revised, now requires BOTH cross-modality AND intra-FF proof** — **⚠️ SUPERSEDED by "## CP.2 Final Design Lock" below §13**

**Milestone:** *A Functional Fitness workout generated as part of a mixed TrainingMix makes a different, explainable stimulus choice because of surrounding training stress and component priority/objectives, AND a second FF session in the same tactical week makes a different, explainable choice because the first is already programmed — without the first being marked completed.* Concretely, both (A) and (B) must be proven together, not either alone:

- **(A)** implement `adaptationObjectives` (prerequisite, Step 11a), add the Step 5/7 cross-modality eligibility check to `FunctionalFitnessDecisionEngine`'s existing chain, compute it from real sibling `TrainingStressProfile`s materialized in `rollForward`'s Pass 1 (Step 1's two-pass split).
- **(B)** implement `CurrentWeekFunctionalFitnessProgrammingContext` (Step 6), add the Step 11c intra-FF pairing check to the same chain, populate the context incrementally within Pass 2.

Prove both with one concrete before/after case: **a real 3-HYP-primary + 2-FF-supporting mix, materializing both FF sessions' real week-4 (peak, RIR 1, `lowerBodyLoad = .high`) week** (the walkthrough in Step 13) — before CP.2, both FF sessions would independently resolve to the same heavy squat-loaded baseline if nothing intervened; after CP.2, FF-A resolves to one adjusted, eligible `Stimulus` and FF-B resolves to a DIFFERENT adjusted, eligible `Stimulus` for a stated reason (Step 11c's pairing rule reacting to FF-A's real, not-yet-completed decision) — and the pre-CP.2 baseline, if forced through a test harness that bypasses CP.2, would trigger `InterferenceAvoidanceRule` exactly as CP.1's own decisive test already proved. This is the minimum proof that `TrainingMix` behaves as ONE coordinated program rather than independent generators patched together after the fact — explicitly NOT "build the entire perfect concurrent-training AI": no `CrossModalityExposureSummary`, no aggregate-weekly interference, no Interval/SteadyState consumption, no readiness interaction, no benchmark logic.

---

**CP.2 audit conclusion (round 2 — ⚠️ see "## CP.2 Final Design Lock" below for the corrected version of the claims marked below):** the narrowest correct seam remains `FunctionalFitnessDecisionEngine.decide`'s existing fixed-priority check chain, now fed by TWO new values — a cross-modality eligibility signal (Step 5 — **superseded: this is a discouragement signal pre-placement, not eligibility; true eligibility is a post-placement fact, see Final Design Lock §1**) and an intra-FF current-week context (Step 6 — still correct) — computed at `RollTacticalWindowUseCase.rollForward`, restructured into two passes keyed on producer/consumer role (Step 1 — **the two-pass shape is revised into three stages, see Final Design Lock §2**), never on `GoalPriority`. `adaptationObjectives` (Step 11a) is a hard prerequisite, and — newly found — `LongTermPlanner` cannot currently assign it for Functional Fitness components at all (no per-sub-objective signal exists yet); this document's own reference case's exact FF objective combination is illustrative, not currently producible **(resolved by an explicit product decision, see Final Design Lock §3 — it is now honestly producible)**. `InterferenceAvoidanceRule.triggers` is reused directly, unmodified (Step 7a) — no new predicate, still correct. Concurrent Programming reads no source label (`isDeload` or otherwise) anywhere in this design (Step 5/§14) — still correct. `CrossModalityExposureSummary` stays deferred. Aggregate (3+-component) interference stays explicitly UNRESOLVED. Nothing in this audit implements any of it.

## CP.2 Final Design Lock

**Status: DESIGN / AUDIT ONLY. Not implemented. Not committed. Not pushed.**

Three remaining blockers were found in the round-2 audit and are resolved here, empirically, against the real code. Most of round 2 stands (see the annotations added throughout the round-2 section above marking exactly what is superseded). This section is the final word where the two disagree.

### §1 — Temporal-interference solution

**The round-2 rule was wrong.** It treated same-tactical-week co-occurrence as equivalent to `ConcurrentScheduler`'s day-adjacency interference check. These are not the same thing, and conflating them makes Concurrent Programming systematically over-conservative — for 3 full-body HYP + 2 FF during a peak week, nearly every FF candidate would classify `.high` on the same dimension as HYP all week, making almost everything `.ineligible` regardless of which actual days things land on.

**Audited empirically.** Every materializer (`StrengthMaterializer.swift:126-127`, `FunctionalFitnessMaterializer.swift:47-48`, `SteadyStateMaterializer.swift:42`, `IntervalMaterializer.swift:77`) already assigns each new `Session` a real, if provisional, `Day.date` at construction time — `date = weekStartDate + dayIndex`, one calendar day per template-session index. Confirmed this is a genuine *nominal* date, not a placeholder sentinel: `ConcurrentScheduler.swift:389-396`'s own `originWeekFloorOffset` reads it back as a real floor constraint, and `Session.swift:34-41`'s doc comment confirms it stays intact "until `AcceptScheduleProposalUseCase.accept` re-parents the Session onto its real scheduled Day."

**But this date is not usable as true adjacency information at CP.2's decision point, for a decisive reason:** `RollTacticalWindowUseCase.rollForward` (`RollTacticalWindowUseCase.swift:105` for Hypertrophy/Powerlifting, `:151` for Functional Fitness) computes each component's naive dates **independently**, each restarting its own `dayIndex` count from the same shared week start. A 3-session Hypertrophy component and a 2-session FF component both materializing "this week" produce naive dates that literally collide (both start at day-index 0 from the same week). `ConcurrentScheduler.schedule` is the ONLY place that actually disentangles these into a real, non-conflicting calendar week (`buildPhases`/`place`/`score`, `ConcurrentScheduler.swift:45-101` and `225-355`). **The naive date is a same-week ordering floor, not a placement — real day-adjacency does not exist anywhere before `ConcurrentScheduler.schedule` runs.** This empirically closes the question: at FF-generation time (inside `rollForward`'s per-component loop, before line 167's `SchedulingPipeline.propose` call — CP.2's own established seam), there is no true adjacency information available, only "same week." The key invariant therefore applies exactly as stated: a hard `.ineligible` decision must be justified by actual information available at that point, and same-week presence alone is not that.

**Chosen: Option A (soft-before-placement / hard-after-placement), and it turns out to require zero new detection machinery.** `ConcurrentScheduler.score` (`ConcurrentScheduler.swift:483-509`) already computes true day-adjacency interference during placement — `neighbors = (dayOccupants[offset-1] ?? []) + (dayOccupants[offset+1] ?? [])`, checked against `constraints.interferenceRules` (i.e. `InterferenceAvoidanceRule.conservativeDefault`) — and when it can't avoid a violation, `place` (`ConcurrentScheduler.swift:315-323`) already appends a real, already-typed `ScheduleIssue(code: .interferenceConflict, severity: .soft, componentLabel:, session:, reason:)` to the proposal. This is the exact "true adjacency, now known" signal Option A needs, and it already exists — CP.2 does not need to invent a placement mechanism of its own (which would violate the WHAT-vs-WHEN boundary, §11/Step 11) or duplicate `ConcurrentScheduler`'s interference detection a second time.

**Exact mechanism:**
1. **Pre-placement (inside `rollForward`'s FF-generation stage, before line 167):** the same-tactical-week stress overlap (round 2's Step 5/7 rule, same `StressDimension`/`.high` vocabulary) is downgraded from `.ineligible` to **`.discouraged`** — a preference, not a hard gate. CP.2 still applies its one-dimension repair (§5 below) to steer away from it when doing so doesn't cost the component ALL of its objective coverage (the pairing-preference invariant from round 2's Step 11c/round 3's precedence model, §6 below) — but if steering away isn't clean, the discouraged candidate is allowed through, unlike a genuine `.ineligible` verdict.
2. **`rollForward` proceeds exactly as it does today**: all this week's Sessions materialize, then `SchedulingPipeline.propose` runs once (the existing, unchanged, pure call at line 167) — same cost as today, no new call yet.
3. **Bounded check (new, small):** scan `scheduled.proposal.issues` for a `.interferenceConflict` whose `componentLabel`/`session` names an FF session CP.2 had already flagged `.discouraged` pre-generation for the same `StressDimension`. If none — done, proceed to `.accept` exactly as today.
4. **If one is found — exactly ONE bounded reprogramming pass:** re-invoke the same Stage A→E per-session materialization for that one FF session with the constraint now promoted to genuine, evidence-backed `.ineligible` (real adjacency is now proven, so §5's repair is applied unconditionally this time, even if it would give up an objective — real interference outranks objective coverage, mirroring round 2's Step 12: "genuine hard ineligibility is never overridden to produce a workout," now correctly scoped to when ineligibility is actually genuine). Call `SchedulingPipeline.propose` a second time (still the same pure, side-effect-free function — safe to call twice, nothing has been `.accept`-ed yet). Use whichever proposal comes back; never retry a third time — if the second proposal still conflicts, accept it as-is, exactly today's existing soft-issue behavior. (Whether the one-session reprogramming rebuilds that Session's `WorkoutBlock`s in place or constructs fresh ones is an implementation-time detail, not a design blocker — either way nothing has been accepted/exposed yet.)

This is genuinely the smallest change: it reuses `SchedulingPipeline.propose` (already pure, already called once per `rollForward` invocation) a second time only in the rare case a discouraged candidate actually collides, and reuses `ScheduleIssue`/`.interferenceConflict` (already computed, already typed) rather than inventing new detection logic. **Option B (schedule structure first, content second) is rejected**: it would require generating placeholder Session "shells" before any modality generates content — a real restructuring of every materializer's call order — when the naive-date evidence above shows this isn't necessary; the existing scheduler's own real interference signal, read back once, does the same job for free. **Option C (negotiation)** is not a separate option — it's what this mechanism's step 4 already is, just bounded to exactly one retry rather than an open-ended protocol, and grounded in an existing signal rather than a new one. **Option D** — no other applicable native pattern was found.

### §2 — Producer/consumer orchestration after the temporal resolution

The two-pass split (Pass 1: `.hypertrophy`/`.powerlifting`/`.interval` producers; Pass 2: `.functionalFitness` consumers, in `sortIndex` order, reading Step 6's incrementally-built current-week context) **remains structurally correct** — §1's finding changes WHAT the eligibility check reads (same-week discouragement instead of same-week ineligibility), not WHEN materialization happens relative to `SchedulingPipeline.propose`. The orchestration becomes three stages, not because the pass split was wrong, but because §1 adds one new, conditional stage after the existing single `propose` call:

1. **Pass 1 (producers)** — unchanged from round 2.
2. **Pass 2 (consumers, FF)** — unchanged from round 2, except the eligibility check it feeds (§1/§6) now produces `.discouraged`, never `.ineligible`, at this stage.
3. **Propose, then bounded conditional repair** — the existing single `SchedulingPipeline.propose` call, now followed by the small conditional check-and-single-retry from §1's step 3-4. This is still one function, still `rollForward`, still no redesign of `ConcurrentScheduler`/`SchedulingPipeline` themselves — just three named stages inside the one use case instead of two.

`GoalPriority` still never determines materialization order (round 2's finding stands unchanged) — the producer/consumer classification is still keyed on which `ProgrammingSystemKind` has a real constraint-consuming call site, exactly as before.

### §3 — TrainingOS PRODUCT DECISION: FF adaptationObjectives per real LongTermPlanner builder

Every real FF-producing builder in `LongTermPlanner.swift` was read for its own stated rationale (doc comments + display name + reason codes):

| Builder | FF's role (real rationale) | Primary vs. side effect | **PRODUCT DECISION** |
|---|---|---|---|
| `muscleGainVariedMix` (`LongTermPlanner.swift:817-832`) | Doc comment: "§5d's exact worked-example candidate B: 3 Strength + 2 Functional Fitness + 1 Run." Mix display name: **"Strength Plus Variety."** FF is `.supporting`, alongside a `.primary` Strength component — its stated purpose is breadth/variety alongside a focused hypertrophy emphasis, not a narrow physiological target. | Primary contribution: covering what a pure strength/hypertrophy focus does not — metabolic conditioning, aerobic engine, explosive power. No signal at all distinguishing which of these three is *most* wanted; the mix's own name ("variety") implies breadth is the point. | **`[.workCapacity, .aerobicCapacity, .power]`** — labeled PRODUCT DECISION, not recovered behavior. Justification: this is exactly the three-way breadth a supporting "variety" component is FOR when it sits next to a primary strength focus — the three adaptation domains general strength/hypertrophy training under-develops. This is the same combination this whole document has used illustratively throughout — it is now grounded in a stated reason (the builder's own "variety" framing), not merely asserted because the reference case needed it. |
| `fatLossVariedMix` (`LongTermPlanner.swift:854-865`) | Mix display name: **"Functional Fat Loss."** FF is `.primary` here — the dominant training-science need in a fat-loss phase is caloric expenditure + metabolic conditioning, with muscle preserved by the paired `.secondary`/`.required` Resistance Training component. | Primary contribution: metabolic conditioning and aerobic engine work — the actual fat-loss driver. No stated rationale for explosive-power development specifically in a fat-loss context. | **`[.workCapacity, .aerobicCapacity]`** — PRODUCT DECISION. `.power` is deliberately excluded here (unlike the variety case above) because nothing in this builder's own stated purpose (fat loss via conditioning) calls for it — including it here would be inventing a target the builder's own rationale doesn't support. |
| `functionalFitnessFocusedMix` (`LongTermPlanner.swift:917-924`) | `phase.type == .functionalFitness` — the user's actual strategic GOAL is general fitness/GPP itself, not FF-as-a-supporting-component-of-something-else. Mix name: "Focused Functional Fitness." | This is the one case where genuine breadth across nearly every domain FF can honestly serve IS the stated product intent — CrossFit's own definitional claim (already cited in this document, §1 of the earlier audit) is "increased work capacity across broad time and modal domains." | **`[.workCapacity, .aerobicCapacity, .anaerobicCapacity, .power, .skillAcquisition]`** — PRODUCT DECISION, and explicitly **not** "auto-assign all 7": `.maxStrength` and `.muscleGain` are deliberately excluded because round 2's Step 11b already proved neither has an honest FF `Stimulus` mapping — this assignment is "every objective FF can honestly serve, because true GPP's own stated purpose is breadth," not "every objective that exists." |
| `lowerDemandGenericMix` | Constructs only a `.steadyState` "General Conditioning" component — **no FF component exists in this builder at all** (confirmed by direct re-read; round 2's Step 11a already found this, restated here for completeness). No assignment needed. | — | — |

**Headline resolution:** this closes round 2's headline gap. The reference case's FF combination (`[.workCapacity, .aerobicCapacity, .power]`) used illustratively throughout this document is now a real, honestly-justified `PRODUCT DECISION` for `muscleGainVariedMix` specifically — it is no longer illustrative-only.

### §4 — Muscle-retention semantic gap

**Recommendation: use `[.muscleGain]` for the secondary/supporting Resistance Training component during fat loss (`fatLossConditioningFocusedMix`/`fatLossVariedMix`) — do not add a new adaptation-direction concept now.**

Reasoning: the training STIMULUS a resistance-training component needs to apply to retain muscle during a caloric deficit is mechanically identical to the stimulus needed to gain it — adequate volume, intensity, and proximity to failure on the same movement patterns. What differs is not the adaptation being trained, it's (a) the athlete's whole-body energy balance, which is completely external to this component's own training stimulus, and (b) how much relative priority/dose it gets — which is already a separate, already-existing axis (`GoalPriority == .secondary`, `SessionFrequency`'s reduced target/minimum), not something `AdaptationObjective` needs to re-express. Concretely for CP.2: whether this component is labeled `.muscleGain` or a hypothetical `.muscleRetention` changes nothing about how CP.2 behaves today, because round 2's Step 11b already proved `.muscleGain` has **no honest FF `Stimulus` mapping at all** — the label is inert for CP.2's own cross-modality/objective-preference logic either way; it only matters for round 3's own `GoalPriority`-based protection logic (§1/Step 5), which already reads `priority`, never `adaptationObjectives`, to decide what's protected. A genuine "direction" concept, if ever needed, has an exact precedent for where it belongs: `PhaseType.maintenance` already exists as a *state*, separate from `AdaptationObjective` — the same reasoning that excluded `.maintenance` from the taxonomy in the first place applies here. Defer a direction/target concept until a real consumer needs to distinguish gain from retention; none does today. Avoids taxonomy expansion, as instructed.

### §5 — Exact deterministic Stimulus repair/selection mechanism

**Read `FunctionalFitnessDecisionEngine.swift` in full.** Every one of its 4 existing checks (`adjustForDurationDomain`/`adjustForLoading`/`adjustForModality`/`adjustForMovementFunction`) copies `input.stimulusRequirements` fresh each time (never chains a prior check's output) and mutates exactly one field before returning — the engine's own generic `rotated<T: CaseIterable & Equatable>(_:through:)` helper (`FunctionalFitnessDecisionEngine.swift:141-145`) rotates an enum-valued field to the "next" case in its declared order, wrapping around; `movementModalityMix`/`movementFunctions` instead get an **additive append** of the single least-exposed value (never a removal). This confirms (C) the existing engine changes exactly one dimension per decision, never several, and (D) that invariant should hold for CP.2's new checks too, for the same reason it holds today (Stage 4D precedent, cited in the engine's own doc comment: "do not change several things at once").

**Read `FunctionalFitnessStressProfileMapper.swift` — this produces a materially better answer than round 2's walkthrough assumed.** `lowerBodyLoad = hasLowerBodyFunction ? loadLevel(from: loading) : .none`, where `hasLowerBodyFunction` is true only if `movementFunctions` contains `.squatLoaded`/`.hingeLoaded`, and `loadLevel(from: loading)` maps `.heavy → .high`, everything else → `.moderate`/`.low`. **This means `lowerBodyLoad == .high` requires BOTH a lower-body movement function present AND `loading == .heavy` — either one alone is a complete, sufficient repair.** Round 2's walkthrough (Step 13, step 5) described a repair touching THREE fields simultaneously (`movementFunctions`, `loading`, `movementModalityMix`) — **this was unnecessary overreach, now corrected: a single-field repair suffices.**

**(A)/(B) Chosen repair — reuse the existing `rotated` helper on `loading`, exactly as `adjustForLoading` already does, with zero new mutation helper required.** `LoadingClassification`'s declared case order is `.bodyweightOnly, .light, .moderate, .heavy` — the only value that can ever combine with a lower-body movement function to produce `.high` is `.heavy` itself, and `rotated(.heavy, through: LoadingClassification.allCases)` wraps directly to `.bodyweightOnly` (the last case wrapping to the first) — the maximally conservative value, which is exactly the right behavior for a hard-repair context (as opposed to the existing checks' gentle variety-rotation, where a big jump would be undesirable but isn't at stake here). The identical mechanism generalizes to a `systemicDemand`- or `intensity`-driven DISCOURAGED verdict (§1's other real dimensions): rotate whichever single field the violated `StressDimension` is actually sourced from (`stimulus.loading` for `lowerBodyLoad`/`upperBodyLoad`, `stimulus.systemicDemand` for `systemicDemand`/`recoveryDemand`, `stimulus.intensity` for `overallIntensity`/`metabolicDemand`) — same generic helper, same one-field-at-a-time philosophy, in every case.

**(E) CP.2 produces exactly ONE modified `Stimulus` via this single rotation — not a candidate set, not a multi-step sequence, and no new mutation helper.** No combinatorial matrix is needed or built. (`impactLoading`, driven by array-membership rather than an enum field, is the one dimension the rotation approach can't reach — but no rule in §6/§7 keys off `impactLoading` today, so this is a documented non-goal, not a gap: if a future rule needs it, a removal-style helper (symmetric to the existing additive-append helpers) would be designed then, against that rule's own real requirement.)

**Objective coverage under this single-field repair:** rotating `loading` down (e.g. away from a heavy squat-loaded stimulus) can reduce how strongly the result serves `.power` (which prefers heavier/weightlifting-weighted content, §11b) while leaving `.workCapacity`/`.aerobicCapacity` unaffected (neither's mapping references `loading`). This is not a problem to solve inside the repair itself — round 2's Step 11b already established that a component's objectives are covered across its MULTIPLE sessions over a week, never forced into one session; §6 below's same-week pairing check is exactly the mechanism that notices this session no longer serves `.power` and can nudge a sibling session toward it instead.

### §6 — Exact precedence: eligibility vs. objectives vs. pairing vs. existing variance

Audited against the real engine's actual short-circuit chain (§5) — the two new CP.2 checks are inserted at the FRONT, not appended at the back, because a hard discourage/eligibility fact must be able to override whatever the existing variance checks would otherwise produce:

```swift
func decide(_ input: ProgrammingDecisionInput) -> ProgrammingDecisionOutput {
    if let output = adjustForCrossModalityConstraint(input) { return output }   // NEW — §1/§5/§7, discouraged pre-placement / ineligible post-placement
    if let output = adjustForSameWeekPairing(input) { return output }          // NEW — §Step 6 (round 2, unchanged), reached only if the first didn't fire
    if let output = adjustForDurationDomain(input) { return output }          // existing, unchanged
    if let output = adjustForLoading(input) { return output }                 // existing, unchanged
    if let output = adjustForModality(input) { return output }                // existing, unchanged
    if let output = adjustForMovementFunction(input) { return output }        // existing, unchanged
    return .stimulusAsConfigured
}
```

- **HARD ELIGIBILITY / DISCOURAGEMENT (new check 1)** — §1/§5/§7's cross-modality constraint. This is genuinely first: if it fires, the existing variance chain (checks 3-6) never runs against the original baseline at all THIS call — the engine's own one-thing-per-call design doesn't support "apply this, then also check that," so when eligibility/discouragement changes something, FF's own historical-variety rotation is skipped for this one session. This is an accepted, explicitly-stated consequence, not a bug — and, per round 2's Step 11c finding, moot in practice today anyway since `VarianceConstraints()` is all-`nil` in the real default production configuration (checks 3-6 never fire regardless, §8 below).
- **PRESERVE OBJECTIVE COVERAGE** is not a separate check — it is the tie-break check 1's own repair uses when choosing what to rotate toward (§5): the repair only ever needs one field, and that field's mutation naturally still serves whichever of the component's objectives don't reference that field (shown concretely in §5's last paragraph). No separate step is needed to "preserve" it; it falls out of which field the mapper's dependency structure makes rotatable.
- **AVOID UNNECESSARY SAME-WEEK REPETITION (new check 2, pairing)** — reached only when check 1 did not fire (the candidate is already eligible/undiscouraged). Reuses round 2's Step 6 current-week context and Step 11c's pairing rules verbatim. **Explicit invariant, stated exactly as required:** this check must never fire if doing so would leave the resulting stimulus serving NONE of the component's own `adaptationObjectives` — if the only way to differ from a sibling would abandon every objective, this check returns `nil` and falls through to checks 3-6 unchanged, exactly mirroring check 1's own "never override to produce a workout" discipline one level down (a soft, not hard, version of the same idea).
- **EXISTING FF VARIANCE PREFERENCE (checks 3-6, unchanged)** — genuinely last, reached only when nothing above needed to act. This composition is correct against the real code: it never reorders or removes the existing 4 checks, it only adds two new ones ahead of them, preserving every existing test's behavior for any input where neither new check fires.

### §7 — Current-week objective-coverage mechanism

**`ProgrammedStimulusSummary { componentID: UUID; stimulus: Stimulus }` (round 2's shape) is sufficient, unchanged — no `servedObjectives: Set<AdaptationObjective>` field is added.** Reasoning: "which objectives does this stimulus serve" is always re-derivable on demand from `.stimulus` via the same §11b-style mapping function, whenever §6's pairing check needs it — caching it as a second, parallel representation on the summary risks the two silently drifting if the mapping function is ever revised in one place and not the other (the same class of risk `VarianceExposureRecord`'s own real-vs-planned distinction, round 2 §6, was built to avoid). A free function (e.g. `objectivesServed(by stimulus: Stimulus) -> Set<AdaptationObjective>`, applying §11b's table) is the right shape — computed fresh each time it's needed, never stored, never persisted, and reusable by both §6's pairing check and anywhere else "what does this stimulus serve" needs answering. No numeric scoring anywhere in this computation — it returns a `Set`, checked for non-empty intersection with the component's own `adaptationObjectives`, nothing more.

### §8 — Real production-path week-4 walkthrough (3 Strength + 2 Functional Fitness + 1 Running — the real `muscleGainVariedMix`)

Per §3's product decision, the closest real `LongTermPlanner`-producible mix matching this document's long-used "3 HYP + 2 FF" reference case is `muscleGainVariedMix` (`LongTermPlanner.swift:817-832`) — which, honestly, is actually 3 Strength + 2 Functional Fitness **+ 1 Running**, not exactly 2 components. This document's simplified "3 HYP + 2 FF" framing throughout was always an abstraction of this real mix; the Running component is included below for accuracy but does not materially change the cross-modality/intra-FF mechanics, which are the point of the walkthrough. Real `adaptationObjectives` per §3: Strength → `[.muscleGain]`; Functional Fitness → `[.workCapacity, .aerobicCapacity, .power]`; Running → `[.aerobicCapacity]`.

1. **Strength's 3 real week-4 sessions** (RIR 1, `repGoalSchedule[3]`, the genuine peak progressive week) materialize in Pass 1 exactly as CP.1's own decisive test fixture — `TrainingStressProfile.lowerBodyLoad = .high`, `overallIntensity = .high`, `systemicDemand = .high`, composed via unchanged `SessionStressComposer`.
2. **Running's week-4 session already exists** (Steady State front-loads its whole block at phase start, per `RollTacticalWindowUseCase.swift:93`'s explicit `continue` — it is not freshly materialized by THIS `rollForward` call, but its real, already-persisted `TrainingStressProfile` is queryable via `SessionStressComposer` exactly like a Pass-1 session; a minor precision this walkthrough surfaces beyond round 2's own account).
3. **FF-A's baseline `Stimulus`**: the one fixed Stage-A baseline (`LongTermPlanner.swift:1146-1161`), unchanged week to week.
4. **FF-A's completed-history variance input**: `VarianceConstraints()` all-`nil` in the real default configuration (round 2's Step 11c finding) — contributes nothing.
5. **Check 1 (cross-modality, §1/§5/§7):** Strength's real `.high` `lowerBodyLoad` this week + FF-A's squat-loaded/heavy baseline implies `.high` too on the same dimension → **`.discouraged`** (not `.ineligible` — this is the corrected verdict). Check 1's repair rotates `loading` (`.heavy → .bodyweightOnly`, §5) — this doesn't abandon all of FF-A's objectives (`.workCapacity`/`.aerobicCapacity` still served by the resulting bodyweight-monostructural-leaning content) — check 1 fires, returns the repaired `Stimulus`.
6. **Check 2 (pairing) does not run this call** — check 1 already fired and returned.
7. **The current-week context now contains FF-A's repaired `Stimulus`** (`ProgrammedStimulusSummary`, §7).
8. **FF-B's baseline `Stimulus`**: identical fixed baseline as FF-A.
9. **FF-B's variance input**: same as FF-A — contributes nothing.
10. **Check 1 for FF-B**: same `.discouraged` verdict against the same real `.high` Strength profile → repairs identically via the same single-field rotation (this is a legitimate, non-templated outcome of the SAME mechanism applied to the SAME real inputs, not a coincidence to be smoothed away).
11. **Check 2 does not run for FF-B either**, for the same reason as FF-A — meaning, honestly, in THIS specific real week, FF-A and FF-B's programmed content is NOT differentiated by §6's pairing mechanism at all, because check 1 already fired for both. Round 2's walkthrough implied check 2 (pairing) would be the differentiator between FF-A/FF-B in this exact scenario — **this is corrected here**: pairing differentiates FF-A/FF-B only in weeks where check 1 does NOT fire for at least one of them (e.g. an early, lower-intensity week, or a week where Strength's profile doesn't clear `.high`) — intra-FF pairing and cross-modality discouragement are still two independent, genuinely separate mechanisms (round 2's core claim stands), but they are not both simultaneously active in every week, and week 4 specifically happens to be dominated by mechanism 1. A lower-intensity week (e.g. week 1, RIR 3) is the honest scenario where mechanism 2 alone differentiates FF-A/FF-B, since check 1 doesn't fire there.
12. **The 6 real Sessions handed to `SchedulingPipeline.propose`**: 3 Strength (`.high`) + Running (real, pre-existing) + FF-A (repaired) + FF-B (repaired).
13. **Downstream result**: `propose` runs once; since both FF sessions already rotated away from heavy squat-loaded content pre-generation, `InterferenceAvoidanceRule.conservativeDefault`'s `lowerBodyLoad ≥ .high` check finds no real day-adjacent `.high`/`.high` pair in the common case → no `.interferenceConflict` issue → no bounded retry needed. If one nonetheless appeared (e.g. Strength and an FF session land on adjacent days and some OTHER dimension still collides), the bounded one-shot repair (§1 step 4) would apply once, then accept whichever proposal results — unchanged from §1.

### §9 — Failure/fallback behavior (updated)

Unchanged hierarchy from round 2 (preferred → neutral → discouraged-but-eligible → explicit-constrained-fallback), with §1's correction folded in: **pre-placement, nothing CP.2 produces is ever hard-`.ineligible`** — the worst a pre-placement candidate can be is `.discouraged`-but-still-eligible. **True hard ineligibility exists only post-placement**, triggered by a real `.interferenceConflict` naming a specific session, and is resolved by exactly one bounded reprogramming-and-reprose pass (§1) — never a second retry, never an open-ended negotiation loop. If the single retry's proposal still conflicts, the existing, unchanged soft-issue behavior (a `ScheduleIssue`, never a hard failure) is accepted as final — CP.2 reduces the frequency of this outcome, never claims to eliminate it, exactly as round 2 already concluded, now on a factually correct footing.

### §10 — Exact types/files to change

- `TrainingOS/Domain/Entities/TrainingMixComponent.swift` — add `adaptationObjectives: [AdaptationObjective]` (new persisted field).
- New file, `Domain/ValueTypes/AdaptationObjective.swift` — the locked 7-case enum.
- `TrainingOS/Application/UseCases/LongTermPlanner.swift` — populate `adaptationObjectives` at each real construction site per §3's product-decision table; `maintenanceMix`'s carry-forward (`LongTermPlanner.swift:679-682`/`793-797`) copies it unchanged from the previous mix.
- `TrainingOS/Engines/ProgrammingDecisionEngine.swift` — add fields to `ProgrammingDecisionInput` (a cross-modality constraint value + `CurrentWeekFunctionalFitnessProgrammingContext`); no change to `ProgrammingDecisionOutput`'s shape.
- New file, `Engines/CurrentWeekFunctionalFitnessProgrammingContext.swift` (or inline in the use case) — `CurrentWeekFunctionalFitnessProgrammingContext`/`ProgrammedStimulusSummary` (round 2, unchanged) + the `objectivesServed(by:)` free function (§7, new).
- `TrainingOS/Engines/FunctionalFitnessDecisionEngine.swift` — add `adjustForCrossModalityConstraint`/`adjustForSameWeekPairing` at the front of `decide`'s chain (§6), reusing the existing `rotated` helper (§5) — no new mutation helper needed.
- `TrainingOS/Application/UseCases/RollTacticalWindowUseCase.swift` — restructure `rollForward`'s single loop into the 3 stages (§2): Pass 1 (producers, unchanged materialization) → Pass 2 (FF, computing and passing the new constraint + context) → the existing `propose` call, followed by the new bounded check-and-single-retry (§1).
- `TrainingOS/Domain/ValueTypes/FunctionalFitnessReasonCode.swift` — one new case for the post-placement hard-conflict repair's reason code (e.g. `.crossModalityAdjacencyConflict`), and optionally one for the pre-placement discouragement (e.g. `.crossModalityDiscouraged`) — additive only.
- No change to `ConcurrentScheduler.swift`, `SchedulingPipeline.swift`, `SchedulingTypes.swift`, `FunctionalFitnessStressProfileMapper.swift`, `FunctionalFitnessExposureHistoryBuilder.swift`, or any source-authority file (`StrengthProgressionEngine`, `LoadFirstOverlayEngine`, `DeloadStrategy`, `HypertrophyProgramGenerator`, `SourceRMCalibration`).

### §11 — Persistence/migration implications

Only one new persisted field anywhere in this design: `TrainingMixComponent.adaptationObjectives: [AdaptationObjective]`, a simple additive `[String]`-backed-enum array — the same class of change CP.1 already made zero times (CP.1 added no persisted fields at all) and Stage 4E's own `MovementFunction` case additions already established as safe, no-migration-required precedent (purely additive `String`-rawValue enum). No new persisted relationship, no new table, no schema version bump expected. Everything else in this design (`CurrentWeekFunctionalFitnessProgrammingContext`, the two new `ProgrammingDecisionInput` fields, `objectivesServed(by:)`) is derived, in-memory, and discarded at the end of each `rollForward` call.

### §12 — Complete test matrix

- **§3 product decision**: per-builder `adaptationObjectives` assignment matches the table exactly, including `lowerDemandGenericMix` correctly getting none (no FF component exists there); `maintenanceMix` carries forward unchanged from the previous mix's component.
- **§1 temporal correction**: a same-week `.high`/`.high` overlap produces `.discouraged`, never `.ineligible`, pre-placement; a genuine adjacent-day `.interferenceConflict` (constructed via a test that forces a real placement collision) triggers exactly one bounded reprogramming-and-reprose pass, never more than one; a second still-conflicting proposal is accepted as-is (soft issue, not a hard failure); a non-adjacent same-week placement produces no retry at all.
- **§5 repair mechanism**: rotating `loading` on a `.heavy`+`.squatLoaded` candidate wraps to `.bodyweightOnly` and clears the `lowerBodyLoad` gate; the SAME rotation reused for a `systemicDemand`-driven and an `intensity`-driven discouragement, each touching only that one field; confirm no test ever observes more than one `Stimulus` field changing per single `decide()` call across ALL 6 checks (existing 4 + 2 new).
- **§6 precedence**: check 1 firing suppresses checks 2-6 in the same call (existing variance never runs against the original baseline that call); check 2 never fires if it would leave zero served objectives; checks 3-6 behave identically to their current, already-passing tests whenever checks 1-2 don't fire.
- **§7 coverage**: `objectivesServed(by:)` returns a non-empty set for FF-A's repaired stimulus in the §8 walkthrough; confirm it is never stored on `ProgrammedStimulusSummary` (a compile-time/structural check, not a runtime one).
- **§8 walkthrough as an integration test**: reproduce the real week-4 `muscleGainVariedMix` scenario end to end — real `LongTermPlanner` mix, real Strength materialization at week 4, real FF-A/FF-B materialization with check 1 firing for both, real `SchedulingPipeline.propose`, confirm no `.interferenceConflict` remains in the common case; a SEPARATE test at an early week (e.g. week 1, RIR 3, check 1 does not fire) confirms check 2 (pairing) IS the differentiator there — proving both mechanisms are independently exercised somewhere in the suite, not merely claimed.
- **Regression**: full existing suite (currently 981/2/0) unchanged; FF's own existing 4-check tests unchanged; source progression/deload/calibration/readiness/warm-up/tactical roll-forward/strategic transition all unchanged; no new persistence/CoreData warnings; a fresh migration check confirms no schema bump is triggered by the one new field.

### §13 — Smallest CP.2 implementation boundary (final milestone)

**Unchanged goal from round 2's Step 16, now stated against the corrected mechanism:** a Functional Fitness workout generated as part of a mixed `TrainingMix` makes a different, explainable stimulus choice because of surrounding training stress (§1's corrected discouragement-then-bounded-repair mechanism, not same-week ineligibility) and component priority/objectives (§3's real, product-decided `adaptationObjectives`), AND a second FF session in the same tactical week can make a different, explainable choice because the first is already programmed — without the first being marked completed (§6/§7, exercised via the week-1-style scenario in §12, since week 4 alone does not exercise it per §8's honest finding). Proven via the REAL production path: real `LongTermPlanner.muscleGainVariedMix` → real `TrainingMixComponent`s with real `adaptationObjectives` (§3) → real Strength week-4 materialization (CP.1's own fixture) → real FF-A/FF-B materialization through the corrected engine (§1/§5/§6) → real `SchedulingPipeline.propose` → real, unchanged `ConcurrentScheduler`. Explicitly NOT: `CrossModalityExposureSummary`, aggregate 3+-component interference, Interval/SteadyState as constraint-consumers, readiness interaction, benchmark logic, or fixing the pre-existing `VarianceConstraints()`-all-`nil` production gap (§14 below).

### §14 — Remaining genuinely unresolved items

- Aggregate 3+-component interference (still deliberately unsolved — same conclusion as round 2).
- Interval/SteadyState as future constraint-consumers (unresolved — same as round 2).
- Whether a real, non-`nil` `VarianceConstraints` production default should ever be set is a genuinely separate, pre-existing product gap this whole investigation surfaced but does not fix — **CP.2 coexists with FF's own variance engine currently never firing in production; it does not claim to "integrate with an already-active system."** A later stage should decide production variance policy explicitly.
- Whether a future direction/target concept (gain vs. retention) is ever needed beyond `PhaseType`/`GoalPriority`'s existing expressiveness (§4, deferred, not built).
- `CrossModalityExposureSummary` (deferred, unproven — unchanged from round 2).
- Whether the one-bounded-retry reprogramming pass (§1 step 4) should rebuild the conflicting Session's blocks in place or construct fresh ones — an implementation-time decision, not a design blocker, deliberately left open here.
- Whether `functionalFitnessFocusedMix`'s deliberately broad 5-objective assignment (§3) ever needs its own internal prioritization (e.g. this week leans skill, next week leans aerobic) — not required for the smallest milestone (§13), potentially relevant once true GPP-only mixes get more than 2-3 real production users to observe.

---

**Confirmed at the end of this audit:** `git status --short`/`git diff --stat` show only `TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md` changed; nothing under `TrainingOS/`/`TrainingOSTests/` was touched; local HEAD remains `c7ae62e` (Stage CP.1, unchanged, still pushed to `origin/main`). Nothing in this round was implemented, committed, or pushed.

## CP.2 Implementation Closure — final corrections, as actually shipped

**Status: IMPLEMENTED, verified, ready to commit.** This section is the final word: it supersedes two specific mechanisms described in "CP.2 Final Design Lock" above (§1/§2/§9's post-scheduler reprogramming, and §5's `.heavy → .bodyweightOnly` rotation-based repair) with what was actually authorized and shipped. The rest of the Final Design Lock (producer/consumer two-pass orchestration, §3's product decisions, §4's muscle-retention resolution, §6's precedence, §7's coverage mechanism, §10-§11's boundaries) stands unchanged and was implemented as designed.

### Correction 1 (superseding Final Design Lock §1/§2/§9) — no post-scheduler regeneration

The Final Design Lock's bounded reprogramming-after-`propose` mechanism (§1 steps 3-4, §2's "three stages," §9's post-placement hard-ineligibility) was **never implemented and is formally withdrawn**. As actually shipped: the cross-modality signal is **soft-only, pre-placement, permanently** — same-week `.primary`-sibling stress overlap produces `.discouraged`, never `.ineligible`, full stop. `RollTacticalWindowUseCase.rollForward` calls `SchedulingPipeline.propose` **exactly once** per successful attempt (confirmed by direct grep — one real call site, `RollTacticalWindowUseCase.swift:231`), identical to pre-CP.2 behavior. If `ConcurrentScheduler` still can't avoid a real day-adjacency conflict, the existing, unmodified `.interferenceConflict` `ScheduleIssue` behavior is the final word — Concurrent Programming does not observe or react to it. **Post-scheduler reprogramming/negotiation remains a DEFERRED FUTURE CAPABILITY**, to be built later only if real cases prove soft discouragement + scheduler placement insufficient — not built, not scaffolded, no hook left for it.

### Correction 2 (superseding Final Design Lock §5) — minimum-sufficient repair, not enum rotation

The Final Design Lock's `rotated(.heavy, through: LoadingClassification.allCases)` mechanism (wrapping all the way to `.bodyweightOnly`) was **never implemented and is formally withdrawn** — reusing a variance-rotation helper for constraint-repair was rejected as conflating two different purposes. As actually shipped (`CrossModalityStimulusRepair.minimalRepair`): steps `LoadingClassification` back exactly **one** adjacent case (`.heavy → .moderate`), recomputes the profile via the real, unmodified `FunctionalFitnessStressProfileMapper`, and accepts the step only if it actually clears the violated dimension below its threshold — proven concretely: `.heavy → .moderate` clears `lowerBodyLoad` below `.high` (real production test, cited below). Returns `nil` — keeping the original discouraged-but-eligible `Stimulus` completely unmodified — if no one-field step both clears the condition and preserves at least one of the component's real `adaptationObjectives`. No repair table exists for any `StressDimension` besides `.lowerBodyLoad` (the only one an FF candidate's own profile can ever reach `.high` on).

### Same-component, multi-session FF pairing semantics — the real production grain

Empirically confirmed (audited against every real `LongTermPlanner` FF-producing builder): every real mix carries **at most one** Functional Fitness `TrainingMixComponent`. "FF-A/FF-B" same-week coordination is therefore never cross-component — it is that ONE component's own multiple weekly Sessions (per `TrainingMixComponent.frequency.target`), decided one after another within a single `FunctionalFitnessMaterializer.materializeWeek` call. `CurrentWeekFunctionalFitnessProgrammingContext` is built fresh at the top of that one call and updated after each session's `decide()` returns — Session 2 sees Session 1's real programmed `Stimulus` before Session 1 is ever completed, without cross-component orchestration of any kind. `ProgrammedStimulusSummary` was audited for its `componentID: UUID` field and found to have **zero real consumers** (every real use of the context list reads it purely positionally/by-value) — since at most one component ever exists, an identity field answering "which component programmed this?" answers a question nothing asks. **Removed**, not left inert.

### Causal pairing proof

`testRemovingCurrentWeekContextWhileHoldingEveryOtherInputIdenticalRemovesTheSameWeekPairingDecision` (`CrossModalityFunctionalFitnessProgrammingTests.swift`) materializes a real Session 1 through the real production path, captures its real programmed `Stimulus`, then calls `FunctionalFitnessDecisionEngine.decide` twice with every input held identical except `currentWeekContext` — populated (real Session-1 stimulus) vs. empty. Confirms `.sameWeekComplementarityPreferred` with the context present vs. `.stimulusAsConfigured` (baseline unchanged) with it empty — proving the context is the *cause* of Session 2's differing decision, not a coincidence of some other input.

### KNOWN CP.2 LIMITATION — initial mixed-phase materialization is not yet constraint-aware

`StartPhaseUseCase.start()`'s real production path was audited directly: sibling components (e.g. a primary Strength component alongside a supporting Functional Fitness component) **do exist** and are processed at initial phase start — this is not a case of no sibling training conceptually existing. `start()` interleaves `ProgramInstance` creation, exercise-slot resolution, source-RM-calibration gating, and materialization for every component inside one single-pass loop (`StartPhaseUseCase.swift:136`), and `RollTacticalWindowUseCase.materializeFirstWindow` only ever accepts `componentAdaptationObjectives` — no `protectedSiblingStressProfilesThisWeek` parameter exists in its signature at all. The plumbing `rollForward`'s two-pass split provides is simply not threaded through this earlier call.

**KNOWN CP.2 LIMITATION: Concurrent Programming coordination begins with tactical `rollForward`. The first tactical window created during initial mixed-phase start is not yet cross-modality constraint-aware.** This is a real, disclosed gap in WHEN coordination begins — not a claim that no sibling context exists. Restructuring `start()`'s interleaved instance-creation/calibration-gating/materialization loop into a real producer/consumer order would be substantial lifecycle work in a use case with its own documented history of scheduler double-pass fragility (see `materializeOnceCalibrationComplete`'s own doc comment) — correctly out of CP.2's authorized scope. A future dedicated stage may evaluate whether initial phase materialization should adopt the same producer/consumer orchestration `rollForward` already uses, without weakening calibration, atomicity, or lifecycle semantics — not decided or scoped here.

### Final deferred/unresolved items (unchanged from the Final Design Lock, restated for closure)

Aggregate 3+-component interference (unresolved); Interval/SteadyState as future constraint-consumers (unresolved); the `VarianceConstraints`-all-`nil` production-default gap (real, pre-existing, not fixed by CP.2 — CP.2 coexists with FF's own variance engine never firing in production today); a future direction/target concept for muscle gain vs. retention (deferred — `[.muscleGain]` reused, no taxonomy expansion); `CrossModalityExposureSummary` (deferred, unproven); the Week-0/`StartPhaseUseCase` limitation documented above; post-scheduler reprogramming/negotiation as a deferred future capability (Correction 1); `functionalFitnessFocusedMix`'s 5-objective assignment's own internal week-to-week prioritization (not required for this milestone).

### Verification record

24/24 targeted CP.2 tests pass; full suite 1004 passed / 2 skipped / 0 failed; clean `build-for-testing`; zero CoreData/SwiftData warnings; zero diff in every source-authority file; exactly one `SchedulingPipeline.propose` call site confirmed by direct grep; local HEAD unchanged at `c7ae62e` pending this commit.

## STOP

Stage CP.1 (Training Stress Profile Parity) is implemented, tested, and verified — committed as `c7ae62e`, pushed to `origin/main`. The CP.2 design/audit above is design and audit only: not implemented, not committed, not pushed. Onboarding not started. Functional Fitness redesign not started.
