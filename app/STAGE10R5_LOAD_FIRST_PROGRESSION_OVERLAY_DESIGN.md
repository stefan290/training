# Stage 10R.5 — Load-First Progression Overlay: Design / Evidence Pass

**Status: design APPROVED with locked decisions D-10R5-1 through
D-10R5-20 (below); IMPLEMENTED — see
`STAGE10R5_LOAD_FIRST_PROGRESSION_OVERLAY_IMPLEMENTATION_REPORT.md` for
the full implementation report. Awaiting manual acceptance before
commit/push (not yet committed as of this writing).** Checkpoint
`0cffb20` (Stage 10R.4) is the protected baseline this pass builds on.

## LOCKED DECISIONS (post-approval addendum)

The design below (§1-27) is the evidence base. The following decisions,
given by the product owner, supersede any option this document merely
compared without resolving, and are the actual implementation authority:

- **D-10R5-1**: Model 2 (Performance-Qualified Source Schedule) is the
  implemented algorithm. Source mode remains fully functional/testable
  with the overlay disabled.
- **D-10R5-2**: Two-layer evaluation — the complete per-set RIR-surplus
  vector is classified as CONSISTENTLY EASY / MATCHED / INCONSISTENT /
  TOO HARD. An increase requires EVERY valid set at or above target RIR
  (no set below target may qualify as easy) AND a meaningful surplus for
  the exposure as a whole.
- **D-10R5-3**: Meaningful surplus = +2 RIR. `5/5/2` (target 3) is NOT
  easy — one set below target vetoes the whole exposure.
- **D-10R5-4**: Increase requires only ONE clearly-easy exposure (no
  streak). Decrease requires TWO consecutive clearly-too-hard exposures.
  This asymmetry is intentional.
- **D-10R5-5**: `NEXT SOURCE LOAD + PERFORMANCE QUALIFICATION = FINAL
  LOAD RECOMMENDATION`. Matched → accept source's next value. Easy →
  source's next value + one increment. Hard (first) → hold at the
  previous actual/effective reference weight (not the source's fresh
  value). Hard (second consecutive) → previous reference weight − one
  increment. Insufficient/ineligible data → source value stands, UNLESS
  doing so would contradict an already-established hard streak (an
  ineligible exposure never resets or advances the streak — it is
  simply invisible to it).
- **D-10R5-6**: Set autoregulation completely unchanged (Strategy A).
- **D-10R5-7**: Actual reps are not a progression target for RIR-based
  slots; only actual RIR drives classification.
- **D-10R5-8**: Proportional guard `0.10`, DEFER (hold, evidence
  persists) not discard.
- **D-10R5-9**: Two consecutive eligible too-hard exposures required to
  regress; reset the streak on any eligible non-hard exposure; ineligible
  exposures don't count either way.
- **D-10R5-10**: Readiness-adapted exposures (accepted adaptations)
  excluded entirely, reusing `READINESS_PROGRESSION_CONTRACT.md` §3.
- **D-10R5-11**: Skipped/missed/abandoned → zero evidence, never
  increase/decrease/reset/advance a streak.
- **D-10R5-12**: Evidence is exercise-specific; a substitution starts at
  zero evidence.
- **D-10R5-13**: Option B — history remains stored/queryable, but never
  auto-populates a new mesocycle's `SourceRMCalibration`; active
  evidence/streak state resets at the `ProgramInstance` boundary. Model 3
  (automatic anchor recalibration) is REJECTED for this stage.
- **D-10R5-14**: Overlay fully disabled during deload; deload exposures
  never contribute evidence, forward or backward.
- **D-10R5-15/16**: `UserProfile.preferredProgressionStyle` (default
  `.loadFocused`) + `ProgramInstance.progressionStyleOverride` (nil =
  defer to profile default). SOURCE always remains selectable.
- **D-10R5-17**: New standalone `LoadOverlayReasonCode` — the exact 8
  cases proposed, never extending `StrengthReasonCode`.
- **D-10R5-18**: `SetPrescription.targetWeight` never mutated. Execution
  UI must consume the effective (overlay-adjusted) weight when
  LOAD_FOCUSED is active, while the source value remains separately
  intact and readable.
- **D-10R5-19**: Live computation preferred; the one exception —
  freezing the applied overlay result (final weight + reason code) onto
  `ExercisePrescription` the FIRST time it's computed for a given
  exposure (mirrors `SetResult.targetRir`'s existing "snapshot at the
  moment of use" precedent), so a completed exposure's provenance is
  never subject to later recomputation drift.
- **D-10R5-20**: Scoped to the recovered 3-Day Full Body Family A path
  only (`.rmBased` load rule AND `dayCount == 3 && split == .fullBody`).
  Never silently activates elsewhere.

## Architecture trace (performed before writing any production code, per instruction)

**Where the effective load must enter `StrengthExecutionView`**: traced
directly. Exactly two call sites read `SetPrescription.targetWeight`
today — `header(exercise:)`'s "Suggested load: X kg" text (line ~200)
and `resetInputsForCurrentSet()`'s `weightText` prefill (line ~318).
Both go through `StrengthExecutionViewModel.currentSetPrescription`, the
one seam. **No architectural conflict**: both call sites can be
redirected to a new `StrengthExecutionViewModel.effectiveTargetWeight(modelContext:)`
method, which returns the frozen/computed overlay value in LOAD_FOCUSED
mode or the untouched source value otherwise — a two-line change in the
View, zero change to `SetPrescription`/materialization.

**Whether historical provenance needs persistence**: traced. A pure
live-recomputation would be fully reconstructable in principle (the
exposure resolver only ever looks at STRICTLY PRIOR exposures, so a
later recomputation for an already-completed exposure would use the same
inputs) — but D-10R5-19 explicitly asks for the smallest additive
freeze mechanism rather than relying on that reconstructability, so this
design freezes `appliedLoadOverlayReasonCode`/`loadOverlayRecommendedWeight`
onto `ExercisePrescription` the moment they're first computed (i.e., the
first time the execution screen is opened for that exposure), never
recomputed again afterward. **No conflict found** — proceeding to
implementation.

## Final decision table (as required before coding)

| Exposure pattern | Classification | Reason code | Final weight |
|---|---|---|---|
| All valid sets ≥ target, avg surplus ≥ +2 (e.g. 5/5/5 @ target 3) | CONSISTENTLY EASY | `.loadIncreaseEasyPerformance` | source next value + 1 increment (guard permitting) |
| All valid sets == target (e.g. 3/3/3 @ target 3) | MATCHED | `.holdMatchedTarget` | source next value, unchanged |
| Any valid set < target, even if others are easy (e.g. 5/5/2 @ target 3) | INCONSISTENT (vetoed) | `.holdMatchedTarget` | source next value, unchanged |
| Worst valid set surplus ≤ −2, 1st such exposure | TOO HARD (first) | `.holdMatchedTarget` | previous actual/effective reference weight (not source's fresh value) |
| Worst valid set surplus ≤ −2, 2nd CONSECUTIVE such exposure | TOO HARD (repeated) | `.loadDecreaseRepeatedHardPerformance` | previous reference weight − 1 increment |
| Readiness-adapted (accepted) most-recent exposure | excluded | `.readinessExcluded` (surfaced when this is the only/most-recent data) | source next value, unchanged |
| Missing/skipped/abandoned (no exposure at all) | excluded | `.holdInsufficientData` | source next value, unchanged |
| Deload week (current exposure) | overlay inactive | `.deloadSourceAuthority` | source value, unconditionally |
| Easy performance, but smallest increment disproportionate (>10%) | CONSISTENTLY EASY, guard blocks | `.holdIncrementTooLarge` | source next value, unchanged this exposure — evidence not discarded |
| New `ProgramInstance` (mesocycle boundary) | evidence resets | `.holdInsufficientData` until new real exposures accumulate | source next value (fresh calibration, never auto-populated) |

This is a TrainingOS **product feature**, not source recovery. Every
value the recovered Family A source produces (day/category structure,
RM type, RIR targets, fixed-rep prescriptions where they exist, set
baselines, rating relationships, deload, phase transitions) remains
100% authoritative and unchanged. The overlay described here is an
**optional, disable-able TrainingOS adjustment layered on top of the
source's own next-exposure load**, never a replacement for it, and its
own decisions are never described as recovered RP/source behavior.

---

## 1. Source progression baseline (restated, as the comparison anchor)

Recovered in Stages 10R.1–10R.3, confirmed unchanged through Stage 10R.4:

| | M1 (Basic Hypertrophy) | M2 (Metabolite Focus) | M3 (Resensitization) |
|---|---|---|---|
| Week-1 factor | 0.85 × RM | 0.75 primary / 0.6 superset partner (own RM) | 1.0 × RM |
| Later-week multipliers | ×1.05, ×1.075, ×1.10 (weeks 2-4) | same as M1 | ×1.05 only (week 2) |
| Target RIR schedule | 3, 3, 2, 1 | same as M1 | 3, 3 |
| Baseline sets | literal per-row source table | literal per-row source table (+3 superset-partner rows) | literal per-row source table |
| Set autoregulation | rating-driven (-1/0/+1) via paired-slot lookup, `treatMissingRatingAsNoChange` | same, partner's count mirrors its primary | same mechanism, no supersets |
| Rating mechanism | fixed cell-cited pairing web | same, partner reads same external target as its primary | fixed cell-cited pairing web |
| Deload | day-position weight split, 2-set constant, week 5 | same, partner completely omitted | same, week 3 |
| **Does actual reps affect load?** | **No — never** | **No — never** | **No — never** |
| **Does actual RIR affect load?** | **No — never** | **No — never** | **No — never** |
| **Does actual performance ever change load, at all?** | **No.** Load is 100% deterministic: `Week-1 anchor × fixed multiplier[weekIndex]`. Only SET COUNT responds to feedback, and only via a subjective -1/0/+1 rating — never a numeric RIR/rep comparison. | Same. | Same. |

**This last row is the entire motivation for Stage 10R.5.** The source
program's own load progression is a fixed, pre-determined schedule; the
only performance-responsive dial it has is set count, driven by a
coarse ±1 rating. The user's product preference is for load itself to
respond to actual effort accuracy — a genuinely new TrainingOS capability,
not a gap in source recovery.

---

## 2. Stage 10B.6 legacy audit

`HypertrophyV2ProgressionEngine`/`.doubleProgression` has **zero live
production content-generation call sites** today — `HypertrophyProgramGenerator`
never assigns `.doubleProgression` anywhere; every reference elsewhere is
a branch check on already-decoded old data. **A new overlay can be built
as a genuinely parallel, new engine with zero live-path disturbance
risk.**

| Component | Classification | Why |
|---|---|---|
| RIR-surplus concept (`actualRir - targetRir ≥ threshold`) in `DoubleProgressionEngine` | **REUSABLE AS GENERIC ENGINE INFRASTRUCTURE** | Source-agnostic; the exact mechanism the product brief's own worked examples describe. Threshold (2) and rationale ("filters ordinary RIR-estimation noise") are directly portable. |
| Rep-range ceiling/floor gating (`metCeiling`/`metMinimum`) | **SOURCE-INCOMPATIBLE ASSUMPTION** | Requires a non-optional rep range (`SetTarget.repRangeLow/High`). Family A's real RIR-only sets have `repRangeLow/High == nil` by design (Stage 10R.1D) — this branch is structurally unreachable for real source content. |
| Proportional-increment guard (`maxProportionalIncrementRatio = 0.10`) | **REUSABLE AS GENERIC ENGINE INFRASTRUCTURE** | Cleanly separable from the rep-range logic around it; directly answers §9. |
| Two-consecutive-miss regression | **USEFUL IDEA BUT NEEDS REDESIGN** | Shape (require repetition before regressing) is sound and matches the product brief's own instruction; `missedBottom`'s rep-range definition must become an RIR-deficit definition. |
| Role-based rep ranges / RIR trajectories / set baselines in `HypertrophyV2ProgressionEngine` | **SOURCE-INCOMPATIBLE ASSUMPTION** | TrainingOS-invented content with no relationship to the recovered source — must never be reused or presented as source-adjacent. |
| Bounded local set-autoregulation shape (`baseline-1...baseline+2`) | **USEFUL IDEA BUT NEEDS REDESIGN** | The bounding concept is relevant to §7's set-growth-capping question; concrete bounds are V2-specific and would need re-deriving relative to Family A's own real baselines, never invented fresh. |
| `resolveWeight`'s call shape (look up history → delegate to pure engine → typed result + reason code + summary) | **REUSABLE AS GENERIC ENGINE INFRASTRUCTURE** | Clean, source-agnostic pattern worth mirroring exactly. |
| `DoubleProgressionHistoryResolver`'s walk/grouping/readiness-exclusion architecture | **REUSABLE AS GENERIC ENGINE INFRASTRUCTURE** | Already correctly implements "ignore readiness-adapted sessions" (§11) and "no fabricated interpretation of missing data" (§12) as an already-approved, already-tested precedent. |
| `exposure(from:)`'s rep-range-required guard | **SOURCE-INCOMPATIBLE ASSUMPTION**, narrowly localized | Guards `repRangeLow/High != nil`, so it literally cannot see Family A's real RIR-only data. Everything else about the resolver is reusable; only this one predicate needs replacing. |
| `isLikelyDeloadExposure` (keyed on a V2 RIR constant) | **USEFUL IDEA BUT NEEDS REDESIGN** | Concept is exactly right (§15); needs rewiring to Family A's real deload signal (§4 below), not a V2-specific constant. |
| `ProgressionReasonCode` (most cases) | **REUSABLE AS GENERIC ENGINE INFRASTRUCTURE** | `loadIncrease`/`hold`/`loadDecrease`/`calibrationRequired`/`readinessAdaptedHold`/`recencyDecay`/`substitutionEstimate` are generic outcome concepts. |
| `ProgressionReasonCode.repIncrease`/`.doubleProgressionIncomplete`/`.percentageOfEstimate` | **OBSOLETE** | Rep-range-specific or refer to an unrelated mechanism (estimated-1RM percentage loading) never used by Family A's literal-RM path. |
| `ExercisePerformanceProfile` | **REUSABLE AS GENERIC ENGINE INFRASTRUCTURE** | Already fully generic per-`Exercise`, cross-`ProgramInstance`, holds real logged `SetResult`s — exactly the historical-data source a new overlay needs, unchanged. |
| `SubstitutionAwareRecommendation`'s half-confidence cross-exercise RM transfer | **OBSOLETE for this feature — must stay isolated, not reused** | Already fully isolated from `.rmBased`/`SourceRMCalibration` today (confirmed: `RollTacticalWindowUseCase.strengthSlotContext` never calls it for Family A/B/C). The overlay must continue that isolation, not bridge it. |

---

## 3. Overlay boundary — recommended architecture

Governed directly by CLAUDE.md rule 3 ("Prescription, Recommendation and
Result are separate concepts, never merged into one type") and rule 4
("no randomness, no reading the current date/time as an implicit
input" — the overlay must remain deterministic given the same logged
history).

**`SetPrescription.targetWeight` is never mutated by the overlay.** It
remains, permanently, the source's own literal resolved value — this is
what makes the source "remain recoverable/reproducible even when overlay
is disabled" (§8's own requirement) trivially true: disabling the
overlay is simply "stop calling it," with zero data migration, since the
source's own value was never touched.

**Recommended shape**: a pure, **read-time-computed** recommendation —
mirroring `ProgramWeekGrouping`/`AutoregulationRatingResolver`/
`TacticalWeekCompletion`'s own established "derive, never persist"
discipline, and `HypertrophyV2ProgressionEngine.resolveWeight`'s own
call shape:

```
SourcePrescription (SetPrescription.targetWeight — frozen, source-authoritative, never mutated)
        │
        ▼ (read-only, plus real logged SetResult history)
LoadFirstOverlayEngine.recommend(sourceWeight:, targetRir:, exposures:, equipmentIncrement:)
        │
        ▼
LoadFirstRecommendation { sourceWeight, finalWeight, reasonCode, explanation }
        │
        ▼ (consumed by the execution UI only — never re-persisted as a new "final" prescription value)
```

Computed live, on demand (e.g. when `TodayViewModel`/`StrengthExecutionView`
loads a session), not baked into the materialized graph at generation
time. Advantages, weighed explicitly against the alternative:
- Never requires re-materializing anything if the algorithm improves later.
- Trivially disable-able (a feature flag simply stops calling it).
- Matches the codebase's existing "pure derived query" precedent rather
  than introducing a new class of stored-and-potentially-stale derived
  state.
- Counter-consideration, addressed: unlike `SetResult.targetRir` (which
  IS snapshotted at logging time, since it's a genuine "what was I told"
  historical fact), the LOAD recommendation shown before a set is logged
  does not need a separate snapshot field — it is fully re-derivable at
  any later point from the same immutable historical `SetResult`s that
  produced it, exactly like `AutoregulationRatingResolver`'s own
  precedent for autoregulated set counts. No new persisted field is
  required for this alone.

**Provenance field**: a **third**, new, coexisting optional reason-code
field on `ExercisePrescription`, alongside the existing
`appliedLoadReasonCode: StrengthReasonCode?` (source authority) and
`appliedProgressionReasonCode: ProgressionReasonCode?` (V2, unrelated) —
e.g. `appliedLoadOverlayReasonCode: LoadOverlayReasonCode?` — following
the exact "two coexisting typed reason-code tracks on one prescription"
pattern the codebase already establishes. **`StrengthReasonCode` is
never extended or reused for this** — it has been deliberately kept
meaning "this is what the source itself says" throughout Stages
10R.1–10R.4, and overloading it here would be exactly the kind of
silent source/product conflation CLAUDE.md rule 16 (structured, never
string-parsed, never-reinterpreted meaning) warns against by analogy.

*(This is the one place this design proposes an actual new persisted
field, and only for provenance/explainability — the recommendation
value itself is never persisted, see above.)*

---

## 4. Source load vs. overlay load — provenance mechanics

Directly answers §4's worked example. `LoadFirstRecommendation` always
carries both values:
- `sourceWeight` — the source's own resolved, rounded value (89.25 → 90
  in the example) — always present, always computable independent of
  the overlay (it's just `SetPrescription.targetWeight` as already
  materialized).
- `finalWeight` — `sourceWeight` unchanged when the overlay holds/is
  disabled; an adjusted value when it recommends otherwise.
- `reasonCode` — one of the codes in §18.

The UI (§19) shows only `finalWeight` + a one-line reason by default;
the full `sourceWeight`/`finalWeight` pair is available for an
"explain" affordance, never forced on the user every set.

**Deload identification at read time** (needed so the overlay can
correctly disable itself, §15): no direct `isDeload` flag exists on
`Session`/`ExercisePrescription`. The clean, already-existing seam:
`ExercisePrescription.appliedLoadReasonCode`'s case is one of the 5
deload-prefixed `StrengthReasonCode` cases (`.deloadWeightPrescribed`,
`.deloadWeightOmitted`, `.deloadRepPrescribed`, `.deloadRepOmitted`,
`.deloadRepsRequireLoggedPerformanceData`) exactly when that
prescription was materialized during a deload week — zero new plumbing
needed, confirmed by direct code audit.

---

## 5. What counts as "too easy" — candidate rule, with reasoning

**Primary signal: RIR surplus** = (worst-case actual RIR across the
exposure's completed, non-adapted-away sets) − target RIR.

**Aggregation choice, explicit**: use the **minimum** actual RIR across
a exposure's sets (the hardest set), not the average and not the last
set alone. Reasoning: the product brief explicitly warns "do not
blindly increase weight every session" — using the worst set is the
conservative reading (an exposure with one hard set among several easy
ones should not read as uniformly "too easy"), and is more consistent
with an effort-accuracy framing than an average, which can mask a
genuinely-near-limit set. This is a specific analytical choice this
design is making, not left silently ambiguous — flagged in §27 as worth
your explicit confirmation since reasonable people could pick average
instead.

**Secondary gates, both required for an increase, mirroring
`DoubleProgressionEngine`'s existing shape**:
- Every prescribed (non-adapted-away) set of the exposure was actually
  completed (a `SetResult` exists for it) — an incomplete exposure never
  independently justifies an increase.
- RIR surplus ≥ threshold (recommend reusing 2, the already-established
  Stage 10B.6 value, as a starting point — reasoned, not re-derived from
  scratch, and flagged for confirmation in §27).

**Explicitly rejected as a default**: a rep-range ceiling ("reach top of
range before increasing load"). Family A has no source-supported rep
range — `repRangeLow/High` are `nil` by design for every real RIR-only
row. Using a rep-range ceiling here would be inventing unsupported
training content exactly as CLAUDE.md rule 10 forbids ("do not invent
ambiguous training rules... flag it rather than silently deciding").

---

## 6. Should actual reps matter?

**Recommendation: reps are (C) informational only for this stage's
primary algorithm, not a direct progression input — with one explicit
(B) safety/outlier exception.**

Reasoning: the source defines success purely in RIR terms; a rep count
by itself carries no source-approved meaning (85kg×2 vs 85kg×15 "are not
necessarily equivalent," per the brief's own framing, but the SOURCE
never says what they mean either — inventing a meaning here would again
violate rule 10). However, reps remain useful as an **outlier/safety
guard**: if actual reps for a set are extremely low (e.g. 1-2) alongside
a claimed high RIR, that combination is itself suspicious (either a form
break, a technical failure, or an RIR self-report error) and should
suppress an increase recommendation regardless of the reported RIR,
rather than silently trusting a numerically "easy" RIR paired with an
implausibly low rep count. This is a narrow (B) safety role, not a (A)
independent progression signal, and not (D) an invented rep-range
guardrail. (E) — a future, explicitly-opt-in TrainingOS policy that DOES
use reps more centrally (e.g. for a user who wants a more traditional
double-progression-style scheme) — is explicitly out of this stage's
scope, but the architecture (§3's pure `recommend()` engine, swappable
per Feature Mode in §17) does not preclude adding it later as a
distinct, separately-named algorithm.

---

## 7. Set-progression interaction — recommendation

Compared the three offered strategies:

| | Source fidelity | Hypertrophy intent | Fatigue mgmt | Complexity | Reversibility | Deload interaction |
|---|---|---|---|---|---|---|
| A — leave set autoregulation completely alone | Highest — zero change to an already-accepted mechanism | Preserved exactly as recovered | Preserved exactly as recovered | Lowest | Trivial (nothing to revert) | None — deload set logic untouched |
| B — cap positive set growth, shift overload toward load | Medium — a real behavior change to an accepted mechanism | Plausible, matches user's stated preference more directly | Slightly better (less volume creep) | Medium | Needs a defined "undo" | Needs its own deload-interaction analysis |
| C — freeze sets near baseline | Low — the most invasive | Uncertain — removes a whole accepted degree of freedom | Best volume control, but least flexible | Highest | Hardest to reverse cleanly | Needs its own deload-interaction analysis |

**Recommendation: Strategy A** for this stage. The user's stated
preference is specifically about LOAD progression ("progress primarily
by increasing LOAD... avoid forcing progression to occur mainly by
adding more sets") — Strategy A already achieves this by construction,
simply by giving load a new responsive mechanism it didn't have before,
without needing to also suppress the existing set mechanism. It is the
smallest, most reversible, most source-faithful change, and matches the
explicit instruction "no source set baseline change unless separately
approved." Strategy B is a reasonable phase-2 idea if, after real usage,
load-first alone doesn't sufficiently shift the felt balance — flagged
as a future option, not recommended now. Strategy C is not recommended
at all — it goes further than what was asked and meaningfully changes
fatigue management, which the product intent explicitly did not ask for.

---

## 8. Weekly source-multiplier interaction — the central design decision

Compared all four options plus the two production-grade algorithms in
§21 build directly on this comparison:

- **Option A (overlay replaces source multipliers)** — rejected outright.
  Loses the frozen source schedule as a fallback, makes "disable
  overlay" meaningless (there'd be nothing to revert to), and directly
  contradicts "the source must remain recoverable/reproducible even when
  overlay is disabled."
- **Option B (source schedule remains baseline; overlay adds/subtracts
  small performance-derived adjustments)** — viable, straightforward,
  but "small adjustment on top of a moving baseline every week" risks
  compounding drift that's hard to explain simply.
- **Option C (performance chooses whether to accept/hold/advance the
  next source-scheduled load)** — viable; treats the source schedule as
  the default and the overlay as a bounded accept/hold/accelerate
  decision on top of it — highest source fidelity of the three real
  contenders, and the easiest to explain ("normally we follow the plan;
  we only deviate when your data clearly says so").
- **Option D (adaptive anchor / recalibrated source RM)** — a genuinely
  different, complementary model (this becomes Model 3 in §21): instead
  of ever touching the week-to-week multiplier sequence, only the
  ANCHOR (the RM the multipliers are applied to) is reconsidered, and
  only at natural checkpoints. Full analysis in §21.

**Recommendation: a hybrid of B and C** (this becomes Model 2, the
primary recommended algorithm, §21) — the source's own next-scheduled
value is always the DEFAULT; the overlay's role is narrowly to decide
accept / hold / accelerate based on accumulated (never single-exposure)
evidence. Full mechanics in §21.

---

## 9. Load increments

Reuse `EquipmentProfile`/`UserProfile.equipmentIncrements` for rounding,
unchanged — the overlay never invents its own increment granularity.

**Proportional guard: reuse the `0.10` (10%) ratio concept from Stage
10B.6**, but as a **defer, never cancel** guard, not a hard block:
if the smallest available equipment increment would exceed 10% of the
current working weight, the overlay HOLDS this exposure (reason code
`.holdIncrementTooLarge`) rather than forcing an oversized jump — but
the underlying "this has been easy" evidence is NOT discarded; it
continues to accumulate, so a lighter exercise that's been easy for
several exposures in a row eventually earns the increase once either (a)
enough evidence has accumulated to justify a larger jump under whatever
accept/accelerate rule is active, or (b) the load has grown enough
(from ordinary source progression) that the same absolute increment is
no longer disproportionate. This directly matches the curl-vs-squat
example in the brief: a small exercise doesn't get "stuck" forever, it
just needs a slightly stronger case before jumping.

---

## 10. Regression policy

Redefine "miss," ported from Stage 10B.6's shape but in RIR terms: an
exposure is a **miss** when its worst-set RIR surplus ≤ −2 (materially
harder than prescribed) AND every prescribed set was still completed
(a non-completed set is handled separately — see §12, never conflated
with a hard-but-completed miss).

**Two consecutive misses (reusing the Stage 10B.6 shape, redesigned
input)** → decrease by one equipment increment, reason code
`.loadDecreaseRepeatedHardPerformance`. A single hard exposure never
regresses by itself — matches the explicit instruction not to regress
off one bad day, and gives readiness/fatigue/an off day a chance to
simply be an off day before the algorithm reacts.

---

## 11. Readiness interaction — already answered by existing product decision

Not a new open question. `READINESS_PROGRESSION_CONTRACT.md` §3
(already-approved, already product-owner-corrected once before
shipping): *"readiness-adapted AND successfully completed = neutral
evidence about the unperformed original prescription... do not progress
as though the original had actually been performed."* This is Candidate
Policy **A** from the brief's own list ("ignore readiness-adapted
sessions for progression"), and it's already implemented, tested
precedent — `DoubleProgressionHistoryResolver`'s existing exclusion of
any exposure with an accepted `ReadinessAdaptationDecision`. **Recommendation:
reuse this exact rule and this exact mechanism** (query
`exercisePrescription.readinessAdaptationDecisions.contains { $0.userResponse
== .accepted }` before including an exposure), rather than re-litigating
the question. Reason code for an excluded exposure: `.readinessExcluded`.

---

## 12. Missed/skipped/abandoned — no-data behavior

Confirmed: zero fabrication anywhere in this design (matches Locked
Decision 3's discipline from Stage 10R.4, extended here). A missed/
skipped/abandoned session simply has no `SetResult`s for that exercise
— the exposure-walk (§2's reused `DoubleProgressionHistoryResolver`
architecture) naturally produces no exposure for that week at all. The
overlay's recommendation in that case is `.holdInsufficientData` (if no
real exposure exists yet anywhere) or a repeat of whatever the most
recent REAL exposure already concluded (if one exists) — never
interpreted as either good or bad performance.

---

## 13. Substitution behavior

`ExercisePerformanceProfile` is scoped `(performanceProfile, exercise)`
— genuinely exercise-specific by construction. A substitution (Bench
Press → Dumbbell Bench Press) naturally produces a DIFFERENT profile row
with zero shared history — no transfer occurs, and none should be added.
**Recommendation: the overlay simply reports `.holdInsufficientData`/
`.sourceBaseline` for a freshly-substituted exercise** until enough new
real exposures accumulate under the new exercise — exactly the same
no-data behavior as §12, no special-casing needed. **Confirmed:
`SubstitutionAwareRecommendation`'s half-confidence cross-exercise RM
estimate is already fully isolated from `.rmBased`/`SourceRMCalibration`
today** (never called by `RollTacticalWindowUseCase.strengthSlotContext`
for Family A/B/C) — this design continues that isolation deliberately;
the overlay must never call into `SubstitutionAwareRecommendation` or
any similar cross-exercise estimator.

---

## 14. Mesocycle-boundary behavior

**Recommendation: Option B — retain historical performance as
reference; never automatically adjust the new mesocycle's fresh
calibration.** `ExercisePerformanceProfile` is already cross-`ProgramInstance`
by construction, so nothing needs to change for history to remain
visible/queryable across the boundary. But `SourceRMCalibration` for the
new instance is entered by the user exactly as today — a real, literal,
freshly-tested-or-estimated value — with **zero overlay pre-fill**,
preserving Stage 10R.1C's already-locked rule that calibration is never
auto-derived. A purely optional, non-binding UX idea for later (not part
of this recommendation, flagged as deferred): the calibration screen's
copy could mention "last mesocycle you were working around ~X kg" as
informational context, never a pre-filled or auto-submitted value —
worth a product decision later, not now.

---

## 15. Deload

**Overlay disabled during deload, on both sides**: (a) a deload week's
own prescriptions are never passed through the overlay for a
recommendation — the deload strategy remains the sole authority for
that week's numbers, reason code `.deloadSourceAuthority`; (b) a deload
exposure is excluded from the exposure history used for any FUTURE
week's overlay decision (reusing/rewiring the Stage 10B.6
`isLikelyDeloadExposure` concept, keyed on the real Family A deload
signal from §4 — `appliedLoadReasonCode`'s deload-prefixed cases —
rather than a V2-specific RIR constant). This prevents a deload's
deliberately-light week from ever being misread as "this load was too
easy, increase it."

---

## 16. Mixed-modality scope

The overlay only ever activates for a slot whose `PrescriptionTemplate
.rules.loadRule == .rmBased` — mirroring `StrengthMaterializer`'s own
existing `if rules.loadRule == .doubleProgression` branching precedent
exactly. Running/Steady-State/Interval/Functional-Fitness slots never
have `.rmBased` load rules at all, so they are excluded by construction,
with zero new scoping logic needed beyond checking the same field every
other load-rule-aware code path already checks.

---

## 17. Feature-mode / user-control — recommended ownership

**Recommendation: a per-`ProgramInstance` setting, with a `UserProfile`-level
default** — directly mirroring the already-established
`ProgramInstance.adherenceModeOverride: AdherenceMode?` pattern (an
existing per-instance override field, same shape). Concretely:
- A new `ProgramInstance.progressionStyleOverride: ProgressionStyle?`
  (`.source` / `.loadFirst`), `nil` meaning "use the profile default."
- A `UserProfile`-level `preferredProgressionStyle: ProgressionStyle`
  default (defaulting to `.source` until the user explicitly opts in, or
  to `.loadFirst` once/if it becomes the shipped default — a genuine
  product decision, not resolved here, see §27).

This satisfies your stated architectural preference directly: **source
behavior remains permanently selectable and testable per instance**
(the entire Stage 10R.1–10R.4 test suite continues exercising `.source`
mode forever, completely unaffected by whatever the default becomes),
while still allowing a single profile-level default so most users never
have to think about the choice. Scoping at `ProgramInstance` (not
globally hardcoded, not only a profile-wide constant) also naturally
supports the case where a user wants Mesocycle 1 to be a clean "trust
the program" experience and only switches to load-first for a later
mesocycle, without needing two separate profiles.

---

## 18. Provenance / reason-code design

New `LoadOverlayReasonCode` (a new, purpose-built enum — never extends
`StrengthReasonCode`, never repurposes `ProgressionReasonCode`, per §3):

| Case | Meaning |
|---|---|
| `.sourceBaseline` | Overlay disabled, or no adjustment made — `finalWeight == sourceWeight`, this is simply the source's own value |
| `.loadIncreaseEasyPerformance` | Accumulated evidence justified an increase beyond the source's own next value |
| `.holdMatchedTarget` | Recent exposure(s) matched the prescribed effort — no reason to deviate |
| `.holdInsufficientData` | No qualifying real exposure exists yet (new exercise, post-substitution, all-skipped history, etc.) |
| `.holdIncrementTooLarge` | Evidence supports an increase, but the smallest equipment increment would be disproportionate this exposure — deferred, not cancelled (§9) |
| `.loadDecreaseRepeatedHardPerformance` | Two consecutive real misses (§10) |
| `.deloadSourceAuthority` | This week is a deload — overlay does not apply at all |
| `.readinessExcluded` | The most/only relevant recent exposure was readiness-adapted and is excluded from consideration (§11) |

Exactly the 8 cases the product brief itself proposed — confirmed
sufficient, no additions needed, no reuse of `ProgressionReasonCode`
required (its few generic cases don't need duplicating; this is a
self-contained, purpose-built vocabulary for a self-contained feature).

---

## 19. UI (description only, not implemented)

Minimum viable framing, consistent with the already-accepted Stage
10R.1D execution-UI discipline (no fabricated numbers, clear
prescription-vs-actual labeling):

```
Suggested load: 90 kg
Next time: increase to 92.5 kg
Reason: You completed all sets with more reps in reserve than planned.
```

Internal formulas (RIR surplus math, threshold values, proportional
guard) are never exposed by default — only a plain-language reason,
matching the reason-code table above (`.loadIncreaseEasyPerformance` →
"more reps in reserve than planned," `.holdMatchedTarget` → "right in
line with the plan," etc.). An optional "why?" affordance could reveal
`sourceWeight` vs `finalWeight` for a curious user, but is not required
for this pass's scope and is not designed further here (explicitly
deferred — no execution-UI redesign this stage, per instruction).

---

## 20. Worked decision table

10RM calibration 100kg, M1 Week 1 source load = 85kg, target RIR 3
(source's own Week-2 value, for reference: 85×1.05 = 89.25 → 90kg
equipment-rounded).

| Case | Input | Aggregate (min-set RIR surplus) | Recommended output | Reason code |
|---|---|---|---|---|
| A | All sets @ actual RIR 3 | 0 | Hold — source's own Week 2 (90kg) stands | `.holdMatchedTarget` |
| B | All sets @ actual RIR 5 | +2 | Single exposure: not yet 2 consecutive under Model 2 — accept source's own Week 2 unchanged, but start an "easy streak" counter | `.holdMatchedTarget` (streak=1) |
| C | Mixed RIR 3/4/5 across sets | 0 (worst set) | Hold — worst set was right at target | `.holdMatchedTarget` |
| D | All sets @ RIR 1 | −2 | Hold (first hard exposure — never regress off one) | `.holdMatchedTarget` (miss-streak=1, not yet a regression) |
| E | One incomplete set, others near target | N/A (completion gate fails) | Hold — completion required for an increase; not treated as a miss unless RIR data on completed sets also shows difficulty | `.holdInsufficientData` |
| F | One skipped Session | No exposure produced | Hold — carries forward the last real exposure's conclusion, or no data | `.holdInsufficientData` |
| G | Readiness-reduced load | Excluded entirely | Hold — never counted toward progression | `.readinessExcluded` |
| H | Deload performance | Excluded; overlay inactive this week | Deload's own source value stands, unconditionally | `.deloadSourceAuthority` |
| I | Easy performance, but smallest increment (e.g. +2.5kg on 20kg) is 12.5% | Evidence qualifies, guard blocks | Hold this exposure; evidence carries forward, not discarded | `.holdIncrementTooLarge` |
| J | Two consecutive hard exposures (RIR ≤ 1 both times) | −2, −2 | Decrease by one equipment increment from the most recent actual working weight | `.loadDecreaseRepeatedHardPerformance` |

Case B repeated a second time (i.e. two consecutive easy exposures,
surplus ≥ +2 both times) is the case that actually triggers
`.loadIncreaseEasyPerformance` under the recommended Model 2 — shown
separately below in §21's model comparison, since it's specifically
about the accept/hold/accelerate state machine, not a single-row lookup.

---

## 21. Three candidate algorithms — full comparison

### Model 1 — RIR-Delta Load Progression (single-exposure reactive)

Every real, non-deload, non-excluded exposure independently decides the
NEXT exposure's load: surplus ≥ +2 and all sets completed → increase by
one equipment increment (bounded by the proportional guard); surplus ≤
−2 → count as a possible miss (regress only on a 2nd consecutive miss,
§10); otherwise hold at the source's own next-scheduled value.

- Source fidelity: **Low-Medium** — the source's own multiplier becomes
  advisory nearly every week.
- Stability: **Low** — single-exposure driven, sensitive to RIR
  self-report noise.
- Complexity: **Low-Medium** — directly reuses the ported
  Stage 10B.6 RIR-surplus/proportional-guard machinery with minimal
  change.
- Responsiveness: **High**.
- Predictability: **Medium** — "did well → goes up" is intuitive, but
  exact weekly magnitude can feel arbitrary.
- Set interaction: orthogonal (Strategy A, §7).
- Deload interaction: excluded exposures, overlay off during deload
  (§15), same for every model.

### Model 2 — Performance-Qualified Source Schedule (RECOMMENDED)

The source's own next-scheduled value is always the default. The
overlay only ever ACCEPTs it (the common case), HOLDs at the current
actual working weight instead of advancing (after evidence of
difficulty), or ACCELERATEs past the source's own increment (only after
**2 consecutive** qualifying easy exposures — never a single one).
Tracks two small counters (`easyStreak`, `missStreak`) per exercise,
reset to 0 by any exposure that doesn't extend the relevant streak
(including any excluded/no-data exposure, conservatively).

- Source fidelity: **High** — the source's own number is the literal
  output in the common case; deviation is the reasoned exception, not
  the rule.
- Stability: **High** — requires repeated evidence, exactly matching
  "do not blindly increase weight every session."
- Complexity: **Medium** — a small, explicit per-exercise state
  machine (2 counters), otherwise reuses the same RIR-surplus/
  proportional-guard building blocks as Model 1.
- Responsiveness: **Medium** — one "slow" week possible before an
  early-easy signal is acted on, by design (a feature, not a bug, given
  the explicit "avoid blindly increasing" instruction).
- Predictability: **High** — "the plan says X, unless you've clearly
  outgrown it for two exposures running" is easy to state and remember.
- Set interaction: orthogonal (Strategy A, §7).
- Deload interaction: deload exposures never extend or reset either
  streak (excluded entirely, per §15) — the streak simply picks up
  again, unaffected, at the next real week.

### Model 3 — Adaptive Anchor / Recalibrated Source RM

Never touches the week-to-week multiplier sequence at all. Instead,
at defined checkpoints (mesocycle-internal, e.g. after each real
exposure of a fresh calibration, or simply continuously re-estimated),
back-solves what the "true" effective RM would have to be for actual
performance to match the target RIR, and re-derives all subsequent
weeks' loads by applying the SAME unmodified source multiplier sequence
to that adjusted anchor instead of the literal entered RM.

- Source fidelity: **Highest of the three** — the multiplier ratios
  themselves are never adjusted, only the single input they're applied
  to.
- Stability: **High** (checkpoint-driven).
- Complexity: **Medium-High** — needs a back-solve function and a
  clear definition of when re-anchoring fires.
- Responsiveness: **Low-Medium** — reacts only at checkpoints, not
  every week.
- Predictability: **Medium** — less legible week-to-week (the
  underlying anchor moved, rather than a visible incremental delta).
- Set interaction: orthogonal.
- Deload/mesocycle-boundary interaction: **the most naturally elegant
  of the three specifically for §14** — a recalibrated anchor is exactly
  the kind of informational hint that could (non-bindingly, per §14's
  own recommendation) inform the NEXT mesocycle's calibration screen
  copy, without violating "calibration is always a real, literal,
  user-entered value."
- **Flagged concern, not resolved here**: re-deriving the RM anchor at
  all is philosophically closer to auto-deriving calibration than
  Stage 10R.1C's locked "always literal user-entered" rule anticipated
  — even framed as informational-only, this needs your explicit sign-off
  before any future implementation stage builds it (§27).

### Recommendation

**Model 2 (Performance-Qualified Source Schedule)** as the primary
algorithm — it most directly satisfies the stated product intent (bias
toward load, explicitly avoid session-to-session churn, avoid
over-reliance on reps/sets), is the most source-faithful of the three
in the common case, and is the smallest, most incremental, most
reversible addition to the already-proven-correct architecture. **Model
3's anchor-recalibration idea is recommended as a complementary,
later-stage enhancement specifically for the mesocycle-boundary handoff
(§14)** — not as a replacement for Model 2's in-mesocycle mechanism, and
not part of this stage's recommended build scope. Model 1 is not
recommended as the primary algorithm (too reactive/unstable relative to
the explicit "don't blindly increase every session" instruction), but
its underlying RIR-surplus/proportional-guard building blocks are
exactly what Model 2 also needs — nothing about Model 1's analysis is
wasted.

---

## 22. Required domain-model changes (for a future implementation stage — not built now)

1. New pure engine type(s) — a load-first overlay engine (`recommend()`
   shape, mirrors `HypertrophyV2ProgressionEngine.resolveWeight`) plus a
   new RIR-aware exposure resolver (mirrors `DoubleProgressionHistoryResolver`'s
   walk/grouping/exclusion architecture, with the corrected extraction
   predicate and deload signal from §2/§4).
2. New `LoadOverlayReasonCode` enum (§18) — new, standalone type.
3. One new optional field: `ExercisePrescription.appliedLoadOverlayReasonCode:
   LoadOverlayReasonCode?` — provenance only, never the recommendation
   value itself (computed live, not persisted, per §3).
4. Two new fields for feature-mode ownership (§17):
   `ProgramInstance.progressionStyleOverride: ProgressionStyle?` and a
   `UserProfile.preferredProgressionStyle: ProgressionStyle` default.
5. `ProgressionStyle` enum (`.source` / `.loadFirst`) — new, standalone.

**No changes** to `SetPrescription`, `SourceRMCalibration`,
`TrainingWeek`, `AutoregulatedSetCount`, `SourceCompatibleDeloadStrategy`,
or any Family A source content table.

---

## 23. Proposed implementation slices (for a future stage — not this one)

**10R.5A** — new engine + resolver (pure, unit-testable in isolation,
zero production wiring yet): RIR-surplus computation, proportional
guard, Model 2's accept/hold/accelerate state machine, deload/readiness/
missing-data exclusion, `LoadOverlayReasonCode`.

**10R.5B** — provenance field + `ProgressionStyle`/`ProgramInstance`/
`UserProfile` wiring, still no execution-UI change — recommendation
computable and testable end-to-end, but not yet shown to a real user.

**10R.5C** — minimal execution-UI surface (§19's copy pattern only,
explicitly not a redesign) + real production wiring into
`TodayViewModel`/`StrengthExecutionView`'s existing display path.

*(Explicitly NOT a slice for this stage: Model 3/anchor-recalibration,
any calibration-screen hint text, any rep-count-centric alternative
algorithm per §6(E).)*

---

## 24. Test strategy (for a future stage)

- Pure engine unit tests mirroring `HypertrophyMesocycle1-3SourceProgressionTests`'s
  own discipline: every row of §20's decision table as an explicit test
  case, plus the Model 2 streak state machine (single easy exposure
  holds; two consecutive accelerates; a miss resets the easy streak;
  two consecutive misses regresses; a miss then an easy exposure resets
  the miss streak).
- Readiness-exclusion regression: an accepted-adaptation exposure never
  contributes to either streak (reusing the exact
  `READINESS_PROGRESSION_CONTRACT.md` §3 assertion pattern).
- Deload-exclusion regression: a deload exposure never contributes to
  either streak, and the overlay never produces a non-`.deloadSourceAuthority`
  result for a deload week's own prescription.
- Substitution regression: switching exercises mid-mesocycle resets to
  `.holdInsufficientData`, never transfers evidence.
- Source-fidelity regression (critical, mirrors Stage 10R.4's own
  discipline): with `progressionStyleOverride == .source` (or the
  overlay simply never called), every existing Stage 10R.1–10R.4 test
  must remain byte-identical — proving the overlay is genuinely
  additive, never a silent default behavior change.
- Feature-mode regression: an instance-level override correctly beats
  the profile default in both directions.

---

## 25. Every unresolved question

1. Exposure aggregation: minimum-set RIR surplus (recommended, §5) vs.
   average — a specific analytical choice made here, not left silently
   ambiguous, but genuinely arguable either way.
2. Exact RIR-surplus threshold (recommended: reuse Stage 10B.6's `2`,
   §5/§21) — not re-derived from first principles for this program.
3. Exact streak length required to accelerate (recommended: 2
   consecutive, mirroring the existing 2-consecutive-miss regression
   shape symmetrically) — could reasonably be 3 for extra conservatism.
4. Whether Model 3's anchor-recalibration concept is acceptable at all
   given Stage 10R.1C's "calibration is always literal, never
   auto-derived" rule, even as informational-only hint text (§14/§21).
5. Whether the eventual DEFAULT `UserProfile.preferredProgressionStyle`
   should be `.source` or `.loadFirst` once this ships (§17) — a real
   product decision, not an engineering one.

## 26. Decisions genuinely required from you before any implementation

1. **Confirm or amend Model 2 as the primary algorithm** (§21) — the
   single most consequential design decision in this document.
2. **Confirm the minimum-set (not average) RIR-surplus aggregation**
   (§5, item 1 above).
3. **Confirm the 2-consecutive-exposure threshold** for both
   acceleration and regression (§21/§10, items 2-3 above).
4. **Decide whether Model 3's anchor-recalibration idea should be
   pursued at all**, even deferred to a later stage — or whether it
   should be dropped as incompatible with the locked calibration rule
   (item 4 above).
5. **Decide `ProgressionStyle` ownership and default** (§17) — confirm
   the per-instance-with-profile-default architecture, and separately
   decide what the actual default value should be once shipped (item 5
   above) — these are two different decisions (architecture vs. default
   value) and neither is resolved here.
6. **Authorize (or decline) proceeding to implementation** of slices
   10R.5A/5B/5C (§23) in a future stage, once the above are settled.

---

## 27. Do-not-touch confirmation (unchanged by this pass)

Nothing in `TrainingOS/` was modified. No test was modified. No source
progression, set autoregulation, RM calibration, or deload logic was
altered. No additional source program was recovered. Warm-up and Family
C remain untouched. Nothing was committed; nothing was pushed.
