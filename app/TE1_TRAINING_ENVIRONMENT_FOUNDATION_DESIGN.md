# TE.1 — Training Environment Foundation — Design Lock

**Status: DESIGN/AUDIT ONLY. Nothing implemented, committed, or pushed.** HEAD: `ac76e1a24bb868583798f144fa65bfd0ea7c1a1d`. Closed stages, unmodified: CP.2 (`bca43e2`), CP.2R (`2f02c60`), FF.L1 (`ae5898c`), FF.E1 (`a3c3d0b`), FF.P1 (`ac76e1a`). This narrows `CP3_AND_TRAINING_ENVIRONMENT_AUDIT.md`'s recommendation. Every claim is re-derived from the real code at HEAD, cited by file:line.

## AMENDMENT (Round 2) — Two Blocking Corrections

**Status: DESIGN/AUDIT ONLY.** This amendment corrects two blocking issues in the design above. Everywhere this amendment disagrees with a section below, **this amendment is authoritative** — the sections below have been edited in place to match it, so the document reads as one coherent design, not two contradictory answers.

### A. Correction to unknown-environment semantics

The prior `isCompatible(exercise:environment:) -> Bool` returning `true` for `environment == nil` is **REJECTED and removed**. A pure compatibility function must never assert "compatible" when it cannot know that — doing so is indistinguishable from claiming "all equipment available," exactly the violation the invariant forbids. The fix is architectural, not a wording change: (1) the pure rule becomes genuinely tri-state, never collapsing "unknown" into a boolean; (2) separately, the real product behavior for "no environment configured at all" is handled **upstream of any per-candidate compatibility check**, as an explicit fail-fast guard in each materializer, before any candidate is even considered — never by asking the compatibility function to lie on the materializer's behalf.

### B. Exact tri-state compatibility model

```swift
enum TrainingEnvironmentCompatibility: Equatable {
    case compatible
    case incompatible(missing: Set<EquipmentRequirement>)
    case environmentUnknown
}

enum TrainingEnvironmentCompatibilityRule {
    static func evaluate(required: [EquipmentRequirement], environment: TrainingEnvironment?) -> TrainingEnvironmentCompatibility {
        guard let environment else { return .environmentUnknown }
        let missing = Set(required).subtracting(Set(environment.availableEquipment))
        return missing.isEmpty ? .compatible : .incompatible(missing: missing)
    }
}
```

This is the **smallest good design** — a free function returning a 3-case enum, not a class, not a protocol, not a generic context object. Locked behavior: `required == []` → always `.compatible` once an environment exists (vacuous subset, matches Easy Run/Track Interval Run's real, correct `[]`). `environment.availableEquipment == []` (a real environment configured with zero equipment) → `.compatible` only for `required == []` candidates, `.incompatible` for everything else — a real, legitimate, deliberately austere environment, not an error state. Missing/duplicate stored values are absorbed by `Set` naturally (order-independent, duplicate-safe). A future `EquipmentRequirement` case added to the enum fails closed automatically — any candidate requiring the new case is `.incompatible` with every environment predating that case, the correct conservative default. **`environment == nil` NEVER produces `.compatible` — it always, unconditionally, produces `.environmentUnknown`.**

`SubstitutionValidator.isValid` consumes this by treating anything other than `.compatible` as ineligible for that one candidate:

```swift
static func isValid(candidate: Exercise, for slot: ExerciseSlot, environment: TrainingEnvironment?) -> Bool {
    // ...existing allowedExercises/allowedTargets/allowedMovementFunctions/allowedModalities checks...
    guard TrainingEnvironmentCompatibilityRule.evaluate(required: candidate.requiredEquipment, environment: environment) == .compatible else { return false }
    return true
}
```

This alone would make an unknown environment silently empty every candidate pool, indistinguishable from "a real environment exists but nothing satisfies it" (exactly the (A)-vs-(B) confusion Blocker 1 forbids) — which is why the fail-fast guard below is a separate, required piece, not optional polish.

### C. Migration behavior

Additive schema migration only: `UserProfile.defaultTrainingEnvironment` starts `nil` for every existing user — this is honest persisted truth, not a gap to paper over. No environment row is fabricated. No historical or already-materialized data is touched by migration itself.

### D. Configuration-required failure behavior

**New, required, upstream guard** — each real materializer that resolves a candidate pool (`ResolveProgramInstanceExerciseSlotsUseCase` for Hypertrophy/Strength/Powerlifting; `FunctionalFitnessMaterializer` for FF; the endurance materializers per §F below) checks, BEFORE entering any per-candidate filtering loop: is `trainingEnvironment == nil`? If so, throw/return a typed `.trainingEnvironmentRequired`-shaped case **immediately** — never attempting exercise/activity resolution, never producing a misleading "no compatible candidate" result. This is a distinct, separate failure from case (B) below, and callers must never conflate them. This guard is what actually implements the invariant; the pure `evaluate` function's `.environmentUnknown` case exists so no OTHER caller can silently misuse it as `.compatible`, not so this specific guard has to re-derive the same fact per-candidate.

Distinguishing the two real failures precisely:
- **(A) No Training Environment configured at all** → `.trainingEnvironmentRequired` (or the per-modality-equivalent case name) — thrown by the upstream guard, before any candidate is evaluated.
- **(B) A real environment exists, but no eligible candidate satisfies a slot** → the existing `.environmentIncompatible(slot:missingEquipment:)`-shaped case from §M — thrown only after real, known-environment filtering leaves the candidate pool empty.

These must be two distinct cases in each modality's typed error enum, never collapsed into one, exactly per the user's own instruction.

### E. Existing future-session behavior

Unchanged from the original design (Option A, §AY item 18): already-materialized future Sessions are left completely untouched by migration and by later environment edits — they already represent real, committed prescription truth (resolved `Exercise`/`ActivityType` relationships, immutable). **New locked addition**: if the user later takes an EXPLICIT action that re-triggers resolution for that same session (e.g. a "GOING FORWARD" substitution, or the design-locked-but-unimplemented future session-override from §AS) — THAT explicit action does require a configured environment, and hits the same §D guard as any other new resolution. Passive existence of an old session never requires anything; an explicit new resolution action always does.

### F. ActivityType production audit

Re-audited precisely, correcting the original design's framing: `ActivityType` (`ActivityType.swift:13-19`, 5 real cases: `running`/`cycling`/`rowing`/`skiErg`/`other`) is chosen once at configuration time (`LongTermPlanner.swift:1184,1194`, `preferredActivityType`) — **but a real, working eligibility/resolution mechanism already exists for it**, contrary to the original design's claim of "no candidate-pool resolution mechanism at all." `SubstituteActivityUseCase.isValid(candidate:for:)` (`SubstituteActivityUseCase.swift:16-18`) is a real, tested gate (`template.allowedActivityTypes.contains(candidate)`), and `resolvedActivityType(for:defaultActivityType:in:)` (`:74-76`) is the real function both `SteadyStateMaterializer` (`:69-71`) and `IntervalMaterializer` (`:95,140`, confirmed two real call sites) already call INSTEAD of reading `preferredActivityType` directly — mirroring `SubstituteExerciseUseCase.resolvedExercise`'s exact precedent. **Corrected finding: `resolvedActivityType` itself performs NO validity check at all today** — it returns the real per-instance "GOING FORWARD" override (itself already validated via `isValid` at the moment the override was created) or falls back to the unvalidated configured default. This means there is currently zero re-validation at the point materialization actually uses the value — a real, narrow, and now-closable gap, not a "no mechanism exists" situation.

### G. ActivityType requirement mapping

`EquipmentRequirement` **already contains** `.bike`, `.rower`, `.skiErg` cases (`EquipmentRequirement.swift`, confirmed real, pre-existing, not newly proposed) — the exact shape needed. A small, pure, derived (never persisted) mapping:

```swift
extension ActivityType {
    var requiredEquipment: [EquipmentRequirement] {
        switch self {
        case .running: return []
        case .cycling: return [.bike]
        case .rowing: return [.rower]
        case .skiErg: return [.skiErg]
        case .other: return []  // see explicit disclosure below
        }
    }
}
```

`.running → []` is locked as genuinely truthful (matches the real, already-existing FF-side precedent of Easy Run/Track Interval Run both correctly carrying `[]`) — **explicit disclosure, not silently glossed over**: this guarantees no TrainingOS-modeled equipment blocks running, but it does NOT model outdoor space, weather, or track/treadmill access — those remain genuinely out of scope, a real and disclosed limitation, not a defect. `.other` is honestly marked `[]` **as a default-permissive placeholder, not a proven truthful requirement** — `.other` exists specifically so the model never blocks an activity it hasn't anticipated (per the type's own doc comment); TE.1 cannot honestly claim to know `.other`'s real requirement, so it deliberately never blocks on it, disclosed as an explicit non-goal rather than invented content.

### H. Endurance validation ownership

**The narrowest correct seam is inside the two real call sites that already call `resolvedActivityType`** — `SteadyStateMaterializer.swift:69-71` and `IntervalMaterializer.swift:95,140` — immediately after resolution, before constructing the real prescription. This is NOT forced into `SubstitutionValidator`/`ExerciseSubstitutionEngine` (a semantically wrong fit — that type's whole shape is candidate-POOL filtering; `ActivityType` resolution here is a single-value read, never a pool search) and is not folded into `SubstituteActivityUseCase.isValid` either (that function answers "is this candidate compatible with the TEMPLATE's allow-list," a different, already-correct question from "is this candidate compatible with the ENVIRONMENT" — composing both, not merging them, mirrors exactly how `SubstitutionValidator.isValid` already composes its OWN multiple independent dimensions). Concretely: after `let activityType = SubstituteActivityUseCase.resolvedActivityType(...)`, each materializer calls `TrainingEnvironmentCompatibilityRule.evaluate(required: activityType.requiredEquipment, environment: trainingEnvironment)` and throws a typed failure if not `.compatible` — a small, symmetric addition, real shared RULE, intentionally NOT a shared call site (the user's own instruction: "A shared compatibility RULE does not require a shared resolution CALL SITE").

**One real, disclosed architectural wrinkle**: `SteadyStateMaterializer.materializeAllWeeks` (`SteadyStateMaterializer.swift:20-22`) is currently **non-throwing** — no `throws` keyword, no existing error enum. `IntervalMaterializer.materializeWeek` already throws (`IntervalMaterializationError`, confirmed real). TE.1 therefore requires ONE additional small change beyond what the original design anticipated: `SteadyStateMaterializer.materializeAllWeeks` must become `throws` and gain its own small typed error enum (mirroring `IntervalMaterializationError`'s own shape) — a real, narrow, disclosed scope addition, not a redesign.

Intervals and SteadyState use the exact same check (`TrainingEnvironmentCompatibilityRule.evaluate`) at their own two real call sites — confirmed they do NOT need separate semantics, only separate call sites (matching their already-separate real architecture).

### I. Decision: fold into TE.1 vs. TE.2

**OPTION A — folded into TE.1.** Justified precisely against the user's own bar ("do not create TE.2 merely because the resolution mechanism is different... only choose B if the mapping+validation genuinely isn't small"): the mapping is a 5-line, fully-resolvable `switch` (4 of 5 cases trivial, 1 case — `.other` — honestly disclosed as permissive-by-necessity, not unresolved-and-blocking); the equipment vocabulary needed already exists (`.bike`/`.rower`/`.skiErg`, zero new `EquipmentRequirement` cases); the validation seam is two real, already-identified call sites reusing the identical pure rule from §B; the only non-trivial cost is one materializer gaining `throws` (§H) — real, but small and mechanical, not an architectural redesign. This is genuinely small and truthful, meeting the user's own bar for Option A. **TE.2 as a separate stage is REJECTED as unnecessary** — there is no real remaining ActivityType-environment gap to defer.

### J. Global definition of done

**Corrected and now satisfied by folding endurance in**: Training Environment Foundation is DONE when every current production-reachable athlete-facing workout type either (A) has its equipment/resource requirements validated against the selected environment, or (B) truthfully requires none. With ActivityType folded in: Hypertrophy/Strength/Powerlifting/Functional Fitness (Exercise-resolved, via `SubstitutionValidator.isValid`) and SteadyState/Intervals (`ActivityType`-resolved, via the same `TrainingEnvironmentCompatibilityRule.evaluate`, at their own two real call sites) are **all** covered. No current production-reachable modality is left unaddressed. Future hypothetical modalities remain correctly out of scope.

### K. Multiple-environment confirmation

Unaffected by either blocker — re-confirmed: `UserProfile.trainingEnvironments: [TrainingEnvironment]` + a single nullable `defaultTrainingEnvironment` reference already supports multiple reusable environments from day one; nothing in this amendment requires revisiting that model.

### L. Session materialized-environment semantics

Unaffected by either blocker, restated for clarity per the user's own instruction: `Session.materializedInEnvironment: TrainingEnvironment?` is **diagnostic metadata, not immutable historical truth** — since the relationship nullifies on environment deletion, it can become `nil` for an old Session while that Session's real historical truth (its resolved `Exercise`/`ActivityType` relationships) remains completely unaffected. No snapshot is added solely to preserve this reference's content; historical truth was never this field's job.

### M. Updated complete pipeline

**Exercise-based** (Hypertrophy/Strength/Powerlifting/Functional Fitness):
```
selected/default TrainingEnvironment (nil or real)
  → IF nil: typed .trainingEnvironmentRequired failure, thrown BEFORE any candidate resolution (§D)
  → IF real: slot semantic constraints (allowedTargets/allowedMovementFunctions/allowedModalities/allowedExercises)
      → candidate Exercises
      → hard semantic eligibility (existing SubstitutionValidator checks)
      → hard environment compatibility (TrainingEnvironmentCompatibilityRule.evaluate == .compatible)
      → resolved Exercise
      → materialized prescription (FF.P1 target rule unchanged downstream)
  → IF real but zero candidates pass both gates: typed .environmentIncompatible(slot:missingEquipment:) failure (§D case B)
```

**ActivityType-based** (SteadyState/Intervals):
```
selected/default TrainingEnvironment (nil or real)
  → IF nil: typed .trainingEnvironmentRequired failure, thrown BEFORE resolvedActivityType is even consulted
  → IF real: SubstituteActivityUseCase.resolvedActivityType(...) → activityType
      → TrainingEnvironmentCompatibilityRule.evaluate(required: activityType.requiredEquipment, environment:) == .compatible
      → materialized endurance prescription
  → IF real but incompatible: typed failure (new case on IntervalMaterializationError / SteadyStateMaterializer's new error enum, §H)
```

### N. Updated implementation file/type plan

Adds to the original file list (§ "Exact file/type plan" below, now corrected in place): `Engines/TrainingEnvironmentCompatibility.swift` now defines the tri-state enum + `evaluate` free function (not a `Bool`-returning `isCompatible`). New: `ActivityType.requiredEquipment` computed property (in `ActivityType.swift` or a small adjacent extension file). Modified additionally: `SteadyStateMaterializer.swift` (gains `throws`, a new small typed error enum, the environment parameter, and the compatibility check at its one real call site) and `IntervalMaterializer.swift` (gains the environment parameter and the compatibility check at its two real call sites, adding one new case to its existing `IntervalMaterializationError`). `TacticalMaterializationContext` (already gaining `trainingEnvironment: TrainingEnvironment?` per the original design) now threads to `SteadyStateMaterializer`/`IntervalMaterializer` too via `RollTacticalWindowUseCase`'s existing three real call sites (`RollTacticalWindowUseCase.swift:63,67,169`, confirmed) — no new parameter needed on `rollForward` itself, matching the original design's own established pattern.

### O. Updated test plan

Adds to the original 24-item plan (§ "Exact test plan" below): UNKNOWN group — `nil` environment never evaluates to `.compatible` (pure rule test); no-default-environment produces `.trainingEnvironmentRequired` before any candidate is touched, for BOTH Exercise-based and ActivityType-based materializers; history/existing-future-sessions remain readable and unchanged; retry after configuring an environment succeeds; no fabricated "Full Gym" anywhere. EXERCISE group — subset-passes/one-missing-capability-fails/explicit-`[]`-passes-a-zero-equipment-environment/no-valid-candidate-typed-failure (all as originally planned, now against the corrected tri-state rule). ACTIVITYTYPE group (new) — each of the 5 real `ActivityType` cases' exact derived requirement; a compatible environment; an incompatible environment; an unknown (`nil`) environment; the real SteadyState call-site path; the real Intervals call-site path (both real call sites, per §H). GLOBAL group (new) — every current production modality (Hypertrophy/Strength/Powerlifting/FF/SteadyState/Intervals) is covered by either the Exercise or the ActivityType compatibility path; no athlete-facing production materialization path bypasses environment validation.

### P. Updated dependency graph

```
TE.1 — Training Environment Foundation (NOW COVERS Exercise-based AND ActivityType-based modalities — global invariant satisfied in one stage)
  → FF.M1 — Movement Diversity Expansion (BLOCKED by TE.1, unchanged)
  → FF.LOAD1 — Numeric Load (SHOULD PRECEDE weakly, unchanged)
CP.3 — Concrete Concurrent-Programming Effect (PARALLEL-SAFE with TE.1, unchanged)
FF.RF1 — Result Feedback Foundation (PARALLEL-SAFE, unchanged)
Skill system / benchmark-retest / VarianceConstraints activation (INDEPENDENT, unchanged)
```
**TE.2 is removed from the roadmap entirely** — folded into TE.1 per §I, no separate stage remains.

### Q. Explicit final statements (this amendment)

**UNKNOWN TRAINING ENVIRONMENT SEMANTICS ARE:** `UserProfile.defaultTrainingEnvironment == nil` is the unknown state. The pure compatibility rule (`TrainingEnvironmentCompatibilityRule.evaluate`) returns `.environmentUnknown` for it — **never** `.compatible`. Separately and additionally, every real materializer that would resolve a candidate/activity fails fast with a typed `.trainingEnvironmentRequired`-shaped error the moment it observes `environment == nil`, before attempting any resolution — existing history, existing materialized future Sessions, navigation, and settings remain fully usable regardless.

**ALL CURRENT PRODUCTION WORKOUT TYPES ARE COVERED BY THE TE.1 DESIGN: YES** — Hypertrophy, Strength, Powerlifting, and Functional Fitness via the corrected `SubstitutionValidator.isValid`; SteadyState and Intervals via the same shared `TrainingEnvironmentCompatibilityRule.evaluate` rule at their own two real, distinct call sites. No current production-reachable modality is deferred.

**TE.1 IS SAFE TO IMPLEMENT: YES** — once (a) the original design's §AA seed-data fix (explicit `requiredEquipment: []` on Easy Run/Track Interval Run) and (b) this amendment's `SteadyStateMaterializer` throws-signature change both land as part of the same stage.

**THE RECOMMENDED NEXT IMPLEMENTATION STAGE IS: TE.1 — Training Environment Foundation** (now scoped to cover every current production-reachable modality, Exercise-based and ActivityType-based alike).

---

## A. Executive decision

The prior audit's "fully populated, essentially all exercises" claim is **confirmed but not exact** — exhaustive count below. `SubstitutionValidator.isValid` is confirmed, by direct grep, to be the **single real gate** used by every real candidate-resolution and substitution path across Hypertrophy, Strength, Powerlifting, and Functional Fitness — one semantic rule needs exactly one physical function. `EquipmentProfile`/`equipmentIncrements` are conclusively a different concept (load-rounding math only). **TE.1 is safe to design.** **SUPERSEDED by the Round-2 Amendment above**: the original recommendation to defer `ActivityType`-based endurance to a separate TE.2 stage was corrected — a real, working `ActivityType` eligibility mechanism (`SubstituteActivityUseCase.isValid`/`resolvedActivityType`) already exists, and `EquipmentRequirement` already carries the exact cases (`.bike`/`.rower`/`.skiErg`) needed to express endurance requirements truthfully. TE.1's final scope covers **both** Exercise-based modalities (Hypertrophy/Strength/Powerlifting/Functional Fitness) **and** ActivityType-based modalities (SteadyState/Intervals) — see the Amendment's §F-§J for the full corrected audit. No separate TE.2 stage remains.

## B. Exact `requiredEquipment` coverage

Exhaustive count against every real `Exercise` construction in `ExerciseCatalog.swift` (the sole real catalog — confirmed no other seed file constructs catalog-level `Exercise` rows outside test/seed-scenario fixtures):

**TOTAL production-reachable Exercises: 37**

**WITH explicit `requiredEquipment`: 35** — Barbell Bench Press, Incline Dumbbell Press, Back Squat, Wall Ball, Burpee, Kettlebell Swing, Thruster, Pull-up, Assault Bike, Row Erg, SkiErg, Toes-to-Bar, Push-up, Handstand Push-up, Deadlift, Dumbbell Snatch, Romanian Deadlift, Leg Press, Bulgarian Split Squat, Leg Curl, Calf Raise, Front Squat, Conventional Deadlift, Seated Leg Curl, Seated Calf Raise, Barbell Curl, Cable Triceps Pushdown, Dumbbell Lateral Raise, Barbell Row, Barbell Overhead Press, Leg Extension, Cable Chest Fly, Face Pull, Lat Pulldown, Seated Cable Row, Stiff-Legged Deadlift.

**WITHOUT explicit `requiredEquipment` (relying on the `[]` default, `ExerciseCatalog.swift:157-164`): 2** — Easy Run (Zone 2), Track Interval Run. Both are real, production-reachable candidates in the FF monostructural pool.

**AMBIGUOUS: those same 2.** `[]` here is very likely *correct* (running genuinely needs no equipment, matching `equipment: "none"` on both), but the type has **no way to prove** "confirmed empty" versus "omitted/not yet classified" — both look identical. This is not a hypothetical concern (§25) — it is a real, present ambiguity affecting 2 of 37 real exercises (5.4%), both production-reachable today.

## C. TrainingEnvironment model

```swift
@Model
final class TrainingEnvironment {
    @Attribute(.unique) var id: UUID
    var name: String
    var availableEquipment: [EquipmentRequirement]   // Set semantics enforced by usage, not the type
    var userProfile: UserProfile?
}
```

No existing "one-of-several-owned-records-is-the-default" `@Model` pattern was found elsewhere in this codebase to mirror (`TrainingMix.kind` distinguishes `.recommended`/`.selected` but that's a lifecycle state, not a peer-default flag among siblings). Recommend **not** using a boolean `isDefault` flag on each row (which can accidentally have zero or multiple `true` rows) — instead put `var defaultTrainingEnvironment: TrainingEnvironment?` directly on `UserProfile` (real, `UserProfile.swift:9-11` already shows this class holds exactly this kind of single-owned-reference field, e.g. `user: User?`). This makes "no default configured" and "exactly one default" the only two representable states — "multiple defaults" is structurally impossible.

## D. Default ownership model

`UserProfile.defaultTrainingEnvironment: TrainingEnvironment?` (nullable — `nil` means "unconfigured," see E). Deleting the current default sets this back to `nil` (`.nullify` delete rule) rather than cascading — the user's other environments survive. Changing the default is a single reference reassignment, atomic, no dual-write.

## E. Unknown/unconfigured semantics

**SUPERSEDED by the Round-2 Amendment's §A/§D/§Q above.** `UserProfile.defaultTrainingEnvironment == nil` remains the unknown state (no separate legacy sentinel row needed) — but the original claim that the compatibility rule itself could safely return `true`/pass for `nil` is corrected: the pure rule now returns a distinct `.environmentUnknown` value, never `.compatible`, and every real materializer fails fast with a typed `.trainingEnvironmentRequired` outcome before attempting any resolution when no environment is configured. Rejected Option A (blocking materialization entirely is too disruptive for a first stage and for every existing user on upgrade) — but "not blocking navigation/history" and "not silently asserting compatibility" are now BOTH satisfied, rather than trading one for the other. Existing users on migration: `defaultTrainingEnvironment` is `nil` (no environment rows exist yet) — this is the honest state, not a fabricated "Full Gym" default.

## F. Compatibility rule

**SUPERSEDED by the Round-2 Amendment's §B above — the tri-state `TrainingEnvironmentCompatibility`/`TrainingEnvironmentCompatibilityRule.evaluate` shape there is the final, locked design.** The original `isCompatible(...) -> Bool` returning `true` for `environment == nil` is REJECTED in full — it is not merely reworded, it is a different, corrected mechanism: the pure rule never returns anything indistinguishable from "compatible" for an unknown environment, and the "don't block every existing modality on day one" concern is now handled entirely by the upstream fail-fast guard (Amendment §D), not by the pure rule lying on its behalf. `requiredEquipment == []` remains vacuously compatible once a REAL environment exists (correct: Easy Run/Track Interval Run pass under any real environment). `environment.availableEquipment == []` (a real, deliberately austere environment) correctly makes only `[]`-requiring exercises compatible. Duplicate requirements are absorbed by `Set` naturally. A future `EquipmentRequirement` case fails closed automatically, unchanged from the original finding.

## G. Hard eligibility ownership

**Confirmed, by exhaustive grep, ONE real function used by every real call site across every modality**: `SubstitutionValidator.isValid` (`ExerciseSubstitutionEngine.swift`), called from: `FunctionalFitnessMaterializer.swift:132` (FF initial resolution), `ResolveProgramInstanceExerciseSlotsUseCase.swift:83` (Hypertrophy/Strength/Powerlifting initial slot resolution, at instance-creation time), `SubstituteExerciseUseCase.swift:27,51` (Hypertrophy/Strength/Powerlifting substitution), `SubstituteFunctionalFitnessMovementUseCase.swift:27` (FF substitution), `EvaluateReadinessAdaptationUseCase.swift:213` (readiness, both modalities), `SubstitutionCandidateRanking.swift:31` (recommendation ranking), `StartNextHypertrophyMesocycleUseCase.swift:333` (mesocycle-succession exercise carry-forward). **One semantic rule needs exactly one physical function — confirmed, not assumed.** Add the equipment dimension as one more guard inside this single function, alongside its existing `allowedExercises`/`allowedTargets`/`allowedMovementFunctions`/`allowedModalities` checks — every one of the 7 real call sites above gains equipment awareness simultaneously, with zero duplicated logic.

## H. Primary resolution integration

`ResolveProgramInstanceExerciseSlotsUseCase.swift:83`'s `sortedCandidates.filter { SubstitutionValidator.isValid(candidate: $0, for: slot) }` and `FunctionalFitnessMaterializer.swift:132`'s `candidateExercises.first { SubstitutionValidator.isValid(...) }` both already filter through the one gate — adding environment awareness to `isValid` itself means BOTH real primary-resolution paths become environment-aware automatically, with no separate "first materialization" special case needed.

## I. Substitution integration

All three real substitution engines (`SubstituteExerciseUseCase`, `SubstituteFunctionalFitnessMovementUseCase`, and `SubstituteActivityUseCase` — the latter for `ActivityType`, structurally separate per §S) call the shared gate identically, except `SubstituteActivityUseCase`, which cannot benefit from this fix at all (§S) since `ActivityType` has no `requiredEquipment`-style metadata. Hypertrophy/Strength/Powerlifting/FF substitution and readiness (which calls the same `isValid` per §G) are all closed by the one fix.

## J. Readiness integration

`EvaluateReadinessAdaptationUseCase.swift:213` already gates its own candidate search through `SubstitutionValidator.isValid` — confirmed by direct grep, readiness inherits the fix automatically, requiring no readiness-specific code change.

## K. Source-authority behavior

Every real `ExerciseSlot` construction seen in Hypertrophy generation is category-based (`allowedTargets`/`allowedMovementFunctions`/`allowedModalities`), never a single hardcoded `Exercise` — confirmed by `ExerciseSlot.swift`'s own doc comment ("never hard-coded to one Exercise merely to avoid this schema (Stage 3 decision A6)"). This is a **CATEGORY/INTENT SLOT** by default across the whole real slot graph. The one real narrower mechanism, `allowedExercises` (a slot-level explicit allow-list, confirmed real on `ExerciseSlot.swift:61`), is how a **SPECIFIC EXERCISE**/**COMPETITION-MAIN-LIFT** constraint is actually expressed in this codebase — `SubstitutionValidator.isValid`'s own real logic checks `allowedExercises` FIRST and, if non-empty, short-circuits to identity-only matching (confirmed, `ExerciseSubstitutionEngine.swift:29-31` in this conversation's own prior verified reads). **Lock: when `allowedExercises` is non-empty and every listed Exercise is environment-incompatible, this is a typed environment conflict (Option B), never a silent substitution** — the narrow allow-list is itself the signal that no other movement is a valid stand-in.

## L. Competition/main-lift conflict behavior

Smallest TE.1 behavior: **fail materialization for that one Session with a typed error** (mirroring `HypertrophyGenerationError`'s already-real, established pattern, `HypertrophyProgramGenerator.swift:16`) naming the slot and the missing capability. Do not build a "propose another environment" UX in TE.1 — that is a UX refinement layered on top of a real, typed, already-actionable failure, deferred without blocking correctness.

## M. Materialization failure model

**Recommend (B): a per-modality typed error case with a shared reason payload**, not one universal cross-modality error type — mirrors the codebase's own established convention (`HypertrophyGenerationError`, `FunctionalFitnessMaterializationError`, `IntervalMaterializationError` are already separate, real, per-modality enums; a single shared error would be the first cross-modality error type in the codebase, an unjustified new abstraction). **Amended per the Round-2 correction (Amendment §D): each per-modality error enum needs TWO new cases, not one** — `.trainingEnvironmentRequired` (case A: no environment configured at all, thrown before any candidate resolution is attempted) and `.environmentIncompatible(slot: String, missingEquipment: [EquipmentRequirement])` (case B: a real environment exists but no eligible candidate/activity satisfies it) — these must never collapse into a single case, per the user's own explicit instruction. `SteadyStateMaterializer` needs a new small error enum entirely (Amendment §H), since it doesn't currently have one at all.

## N. No-valid-candidate behavior

Traced precisely against the real FF gymnasticsPull pool (`{Pull-up, Toes-to-Bar}`, both `requiredEquipment: [.pullUpBar]`, confirmed §B): an environment lacking `.pullUpBar` empties this candidate pool completely. **Locked: return a typed failure (per §M), never silently drop the slot, never substitute an unrelated movement, never materialize an incomplete workout.** This is a real, legitimate outcome this audit found the current FF content genuinely produces under a real, common restricted environment (no gymnastics rig) — TE.1 must surface this truth, not hide it, exactly as the user's own instruction requires.

## O. Functional Fitness integration

Full real path, environment entering at exactly one point:

```
FINAL stimulus (CP.2, unchanged)
  → movement slot (allowedModalities/allowedMovementFunctions, unchanged)
  → candidateExercises.first { SubstitutionValidator.isValid(candidate:for:) }
      ↑ TE.1 adds environment compatibility HERE, inside isValid
  → resolved Exercise
  → FunctionalFitnessMovementTargetRule.resolve(format:modality:movementFunctions:exercise:)  — UNCHANGED, confirmed no touch needed
  → materialized prescription
```

Real example using actual `requiredEquipment` (§B): environment `{.barbell, .pullUpBar, .rower}` — squatLoaded slot resolves Back Squat (`[.barbell, .rack]` — **FAILS**, no `.rack`) or Wall Ball (`[.medicineBall]` — fails) or Thruster (`[.barbell]` — **passes**); gymnasticsPull resolves Pull-up/Toes-to-Bar (`[.pullUpBar]` — both pass); monostructural resolves Row Erg (`[.rower]` — passes), Assault Bike/SkiErg fail, Easy Run/Track Interval Run pass (empty requirement, §B). FF.P1's target rule is untouched — it never sees environment, only the already-resolved `Exercise`.

## P. Hypertrophy integration

Traced via `ResolveProgramInstanceExerciseSlotsUseCase.swift:83`, called once at instance creation (before any materialization), against `strengthCandidateExercises`. Real test: a horizontal-pull slot (`allowedMovementFunctions: [.horizontalPullLoaded]`) with real candidates Barbell Row (`[.barbell]`) and Seated Cable Row (`[.cableStation]`) — an environment lacking a cable station resolves Barbell Row only; an environment with neither fails per §M/§N, correctly, rather than resolving nothing silently (today's real gap: this exact case can currently resolve to `nil` at instance-creation and propagate an unresolved slot with no typed signal — TE.1 makes this an explicit, named failure instead).

## Q. Strength integration

Same mechanism as Hypertrophy (both route through the identical `ResolveProgramInstanceExerciseSlotsUseCase`/`StrengthMaterializer` pipeline, confirmed in this conversation's own prior verified reads — "Strength" is the shared family name for Hypertrophy+Powerlifting materialization). Generic strength slots (category-based) get environment-compatible substitution; genuine main-lift slots (narrow `allowedExercises`) get the §L hard-conflict behavior.

## R. Powerlifting integration

`PowerliftingProgramGenerator.swift`/`PowerliftingBuiltInLibrary.swift` confirmed real, separate files — but resolved through the same shared `ResolveProgramInstanceExerciseSlotsUseCase`/`SubstitutionValidator.isValid` pipeline as Hypertrophy (no separate Powerlifting-specific resolution mechanism found). Competition main lifts (Squat/Bench/Deadlift) are the canonical real-world case for `allowedExercises`-narrowed slots — §L's hard-conflict rule is the primary intended consumer of that mechanism.

## S. Endurance/ActivityType decision

**SUPERSEDED by the Round-2 Amendment's §F-§I above — LOCKED: OPTION A, folded into TE.1.** The original claim ("no candidate-pool resolution mechanism for `ActivityType` at all") is corrected: `SubstituteActivityUseCase.isValid`/`resolvedActivityType` (`SubstituteActivityUseCase.swift`) is a real, already-tested eligibility/resolution mechanism, already called by both `SteadyStateMaterializer` (`:69-71`) and `IntervalMaterializer` (`:95,140`) instead of reading `preferredActivityType` directly. `resolvedActivityType` itself performs no validity re-check today — a real, narrow, closable gap. `EquipmentRequirement` already carries `.bike`/`.rower`/`.skiErg` — no new equipment vocabulary is needed. A small, pure `ActivityType.requiredEquipment` derived mapping (Amendment §G) plus one compatibility check inserted at each materializer's own real call site (Amendment §H) closes this for SteadyState and Intervals within TE.1 itself — no separate TE.2 stage. The one real, disclosed cost: `SteadyStateMaterializer.materializeAllWeeks` must become `throws` (it currently isn't) and gain a small new typed error enum, mirroring `IntervalMaterializationError`'s already-real shape.

## T. Inheritance/materialization model

`ProgramDefinition` stores **no** environment (confirmed correct — reusable program intent must stay user/environment-independent, matching the established discipline that generation is user-independent throughout this codebase). `ProgramInstance` stores no environment either. The materializer reads `UserProfile.defaultTrainingEnvironment` fresh at each call, via the same real, already-established `TacticalMaterializationContext`-threading pattern this codebase already uses for `equipmentProfile`/`candidateExercises` (confirmed real fields on this type from this conversation's own prior verified work) — add one more field, `trainingEnvironment: TrainingEnvironment?`, to that same context object. `RollTacticalWindowUseCase.rollForward` resolves the CURRENT default once per call, matching its own existing "read real state fresh each real week" discipline (confirmed, `RollTacticalWindowUseCase.swift:97-101` already threads a fresh `materializationContext` per call). If the user changes their default between weeks, the NEXT roll-forward call picks it up automatically — no explicit propagation code needed beyond the one added context field.

## U. Session environment identity decision

**Challenged directly, per instruction, and the prior audit's "no reference needed" claim is only PARTIALLY correct.** The resolved `Exercise` relationship IS sufficient for historical *exercise* truth (§V) — but it is NOT sufficient to answer "why did this session choose Thruster instead of Wall Ball," which matters for diagnostics/auditability/future override design, even though it's not required for correctness. **Recommend REFERENCE ONLY** (not snapshot): `Session.materializedInEnvironment: TrainingEnvironment?`, nullable, `.nullify` delete rule (so deleting an environment later never invalidates historical Sessions). This is a real, small, justified addition beyond the prior audit's own conclusion — the resolved-Exercise-is-enough argument only covers correctness, not explainability, and the user's own instruction explicitly asked this to be re-examined rather than rubber-stamped.

## V. Historical truth

Confirmed empirically (re-verified via `ExerciseSlot.swift:68`, `FunctionalFitnessMovement`'s real `exercise`/`sourceExerciseSlot` fields, both already real relationship state, immutable once materialized): a completed Session's resolved `Exercise` never re-derives from a live environment profile. Editing `TrainingEnvironment.availableEquipment` later, or even deleting the environment entirely (with the `.nullify` rule from §U), cannot retroactively alter any already-materialized `WorkoutResult`/`FunctionalFitnessResult`/adherence/progression evidence. Confirmed: less new persistence is needed than might be assumed — only `TrainingEnvironment` itself and the one new reference field (§U) are genuinely new.

## W. Environment edit semantics

Editing `availableEquipment` on an existing `TrainingEnvironment` never touches any already-materialized Session (§V) — it only changes what future `isCompatible` checks will produce, the next time materialization runs.

## X. User ownership/persistence

`UserProfile` (`@Attribute(.unique) var id`, confirmed real) gains `var trainingEnvironments: [TrainingEnvironment] = []` (inverse relationship, `.cascade` delete — environments belong to exactly one user, deleting the user deletes their environments) and `var defaultTrainingEnvironment: TrainingEnvironment?` (`.nullify` — deleting the default clears the pointer, doesn't cascade-delete the user). No uniqueness constraint on `name` needed for TE.1 (a cosmetic UX concern, not a correctness one). New users: `trainingEnvironments == []`, `defaultTrainingEnvironment == nil` until onboarding creates the first one. Legacy users: identical state on migration — no fabricated environment.

## Y. Minimum UX

One settings screen: create/name an environment, multi-select real `EquipmentRequirement` cases, mark one as default, edit later. No new screen for "resolve this workout's conflict" beyond a typed error message surfaced wherever materialization failures are already shown to the user (existing error-surfacing UI, not new UX).

## Z. Equipment picker semantics

`EquipmentRequirement` has no existing `displayName` — add one small computed property (`.barbell → "Barbell"`, `.pullUpBar → "Pull-up Bar"`, etc.) directly on the enum, reused by the settings picker. No second, parallel UI-facing enum.

## AA. Metadata completeness rule

**LOCKED invariant for TE.1 shippability: every production-resolvable Exercise must carry an EXPLICIT `requiredEquipment` argument at construction, including `[]` for genuinely equipment-free movements.** Per §B, 2 real exercises (Easy Run, Track Interval Run) currently rely on the implicit default rather than an explicit `[]` — **this must be corrected before TE.1 ships**, not because the value is wrong (it's very likely correct) but because the CURRENT code cannot distinguish "confirmed empty" from "omitted." This is a one-line, two-exercise fix (add `requiredEquipment: []` explicitly to both `make(...)` calls) — trivial, but blocking, per the user's own explicit instruction not to interpret missing metadata as "no equipment required" without proof.

## AB. `requiredEquipment` empty/unknown semantics

Directly caused by §AA's finding: the array type itself cannot carry this distinction (an empty array is an empty array, whether passed explicitly or defaulted). The smallest fix is NOT a new Optional-wrapping type — it's the authoring discipline in §AA (every real call site passes the parameter explicitly) plus, if a truly type-level guarantee is wanted, a lightweight coverage test (§AY item C) asserting every catalog exercise's construction call includes the `requiredEquipment:` argument textually — a test, not new persisted complexity.

## AC. Load-increment separation

Confirmed distinct and correctly separate (§B's `EquipmentProfile`/`equipmentIncrements` read): `EquipmentProfile.equipmentType`/`smallestIncrementKg` answer "how do I round a weight for THIS piece of equipment," never "is this exercise available." TE.1 does not merge them. Future composition (e.g. FF.LOAD1) is unblocked — a future numeric-load stage can independently ask both "is `.barbell` available" (TE.1) and "what's my barbell's smallest increment" (already-existing `EquipmentProfile`), composed by the consuming code, never by merging the two types.

## AD. Hard-vs-soft decision

**LOCKED: hard-only for TE.1.** No preference/ranking/favorite-equipment scoring — no real use case found requiring it, matching the user's own strong default.

## AE. Deterministic selection preservation

`candidateExercises.first { isValid(...) }` (FF) and `sortedCandidates.filter { isValid(...) }` (Hypertrophy) both already operate on a **pre-ordered** array — adding one more boolean condition to `isValid` only shrinks the passing subset, it never reorders the remaining candidates. Confirmed: no variance/randomness is introduced; the existing deterministic tie-break (array order) is fully preserved.

## AF. Exact validator signature/design

**Amended per the Round-2 correction (Amendment §B)** — the internal check now consumes the tri-state rule and only accepts `.compatible`, never treating `.environmentUnknown` as passing:

```swift
enum SubstitutionValidator {
    static func isValid(candidate: Exercise, for slot: ExerciseSlot, environment: TrainingEnvironment?) -> Bool {
        // existing allowedExercises / allowedTargets / allowedMovementFunctions / allowedModalities checks, unchanged
        guard TrainingEnvironmentCompatibilityRule.evaluate(required: candidate.requiredEquipment, environment: environment) == .compatible else { return false }
        return true
    }
}
```

A plain, explicit optional parameter — not a generic `Context` object (no second use case for one exists yet; introducing one now would be architecture-for-elegance, which the user's own instruction forbids). Every one of the 7 real call sites (§G) gains one new argument, threaded from whatever context each already carries. **Each of these 7 call sites' own CALLER must additionally implement the Amendment §D fail-fast guard** (check `environment == nil` before ever entering the per-candidate loop that calls `isValid`) — `isValid` returning `false` for every candidate when the environment is unknown is not, by itself, sufficient to distinguish case (A) from case (B); the upfront guard is what makes that distinction real.

## AG. Exact materializer signature changes

`FunctionalFitnessMaterializer.materializeWeek` — add `trainingEnvironment: TrainingEnvironment?` parameter, threaded to its one `isValid` call site, plus the Amendment §D fail-fast guard at the top of the function. `ResolveProgramInstanceExerciseSlotsUseCase` (covers Hypertrophy/Strength/Powerlifting) — same addition. `StrengthMaterializer`/`HypertrophyProgramGenerator` themselves need **no signature change** — they don't call `isValid` directly (confirmed by the grep in §G; only `ResolveProgramInstanceExerciseSlotsUseCase` and the two Substitute* use cases do). **Amended per the Round-2 correction**: `SteadyStateMaterializer.materializeAllWeeks` — add `trainingEnvironment: TrainingEnvironment?` parameter AND `throws` (a real signature change from non-throwing today, Amendment §H), plus the fail-fast guard and the compatibility check at its one real `resolvedActivityType` call site. `IntervalMaterializer.materializeWeek` — add the same parameter (already `throws`), plus the fail-fast guard and the compatibility check at its two real `resolvedActivityType` call sites, adding cases to its existing `IntervalMaterializationError`.

## AH. Tactical rollforward propagation

`RollTacticalWindowUseCase.rollForward`'s existing `materializationContext: TacticalMaterializationContext` parameter (already real, already threaded, `:100`) gains one new field, read once per call from `userProfile?.defaultTrainingEnvironment`. No new parameter needed on `rollForward` itself. **Amended**: this same context field now threads to all three real per-modality call sites this use case owns (`RollTacticalWindowUseCase.swift:63` SteadyState, `:67,169` Intervals — confirmed real, in addition to the Hypertrophy/Strength/FF call sites already covered) — one shared context field, six total real materializer call sites updated, no new parameter shape needed anywhere in this use case.

## AI. Atomicity

`rollForward`'s real, already-established atomic/scratch-context discipline (confirmed from this conversation's own prior verified reads of this exact function across CP.2/CP.2R) is preserved unchanged: if a materialization failure occurs (§M/§N) for any one component, the existing failure-handling behavior (whatever it already does for `HypertrophyGenerationError`/`FunctionalFitnessMaterializationError` today) is reused for the new environment-conflict case — no new partial-persistence risk, since TE.1 adds a new FAILURE REASON, not a new failure MECHANISM.

## AJ. Strategic phase transition

`StartPhaseUseCase`/`TransitionPhaseUseCase` both ultimately call into the same `ResolveProgramInstanceExerciseSlotsUseCase`/materializer paths — no separate environment-propagation code needed beyond §AG/§AH's additions, since environment enters at the shared low-level seam, not duplicated per lifecycle entry point. No environment data is persisted onto `TrainingPlan`/`TrainingPhase` themselves (correctly avoided, per the "reusable strategic intent stays environment-independent" principle).

## AK. FF.P1 interaction

Confirmed, directly: `FunctionalFitnessMovementTargetRule.resolve`'s real signature (`format:modality:movementFunctions:exercise:`) takes an already-resolved `Exercise` as input — TE.1 only changes WHICH `Exercise` gets resolved upstream, never touches this function's own logic. Example: Row Erg unavailable, SkiErg available → SkiErg resolves → `FunctionalFitnessMovementTargetRule` still correctly produces `distanceMeters: 200` (SkiErg's `equipment != "bike"`); only-Assault-Bike-available → Assault Bike resolves → the rule's own existing bike exclusion still correctly produces no target. Zero TE.1-specific logic needed inside FF.P1's own rule.

## AL. CP.3 interaction

Confirmed orthogonal: CP.3 (per the prior audit's own design lock) operates entirely on `WorkoutFormat`'s round count, downstream of an already-resolved `Exercise` and never touching `Exercise` identity or `requiredEquipment`. TE.1 constrains WHICH Exercise is eligible; CP.3 constrains HOW MANY rounds of the resulting prescription apply. Combined future pipeline: `FINAL stimulus → [TE.1: environment-filtered candidate pool] → resolved Exercise → FF.P1 baseline target → [CP.3: bounded round adaptation] → materialized prescription`. No conflict, no shared mutable field, no reordering needed between them.

## AM. FF.M1 dependency

**Confirmed and re-locked, not relitigated**: FF.M1 (movement diversity expansion) must not ship before TE.1, because expanding the real production-reachable `MovementFunction` set (currently only 3 of 15) would introduce more real candidate exercises — including ones like Deadlift/Kettlebell Swing/Push-up that the exhaustive §B audit already shows carry real, sometimes-restrictive `requiredEquipment` — without a resolver that can guarantee any of them are actually performable. TE.1 BLOCKS FF.M1.

## AN. FF.LOAD1 dependency

Confirmed unrelated concerns per §AC — TE.1 answers "is the equipment TYPE available," FF.LOAD1 will separately need "what numeric load can I load onto it" via the pre-existing, untouched `EquipmentProfile`. TE.1 SHOULD PRECEDE FF.LOAD1 weakly (a numeric load prescription is meaningless for equipment that isn't even available) but does not block it architecturally.

## AO. Apple integration

No real HealthKit/WorkoutKit/Watch code path was found (in this conversation's own exhaustive prior grep, reconfirmed here by the complete absence of any such references in every file read for this audit) that consumes equipment/environment data — TE.1 constrains what TrainingOS prescribes BEFORE any export step exists, and no such export step currently exists to require schema changes. No Apple-side change needed for TE.1.

## AP. Substitution equipment safety

Confirmed (§I): `SubstituteExerciseUseCase`/`SubstituteFunctionalFitnessMovementUseCase` both gate on the one shared `isValid` (§G) — adding environment there closes both simultaneously. `SubstituteActivityUseCase` is untouched by TE.1 (§S) — a disclosed, explicit limitation, not an oversight.

## AQ. Readiness equipment safety

Confirmed (§J): readiness's real candidate search already routes through `isValid` — inherits the fix with zero readiness-specific code.

## AR. Tactical lifecycle/environment behavior

Environment is read fresh at each real materialization call (§T/§AH) — never cached across weeks, never silently reverting to a stale value, since there is no cache to go stale; it's a live read of `UserProfile.defaultTrainingEnvironment` every time.

## AS. Session override behavior

Design-locked, not implemented: a future `Session.trainingEnvironment` override (distinct from the read-only `materializedInEnvironment` reference in §U, which records what was ACTUALLY used) would require **re-resolving only the not-yet-completed session's exercises** — never touching `ProgramDefinition` (reusable, environment-independent) and never retroactively rewriting a completed Session. This mirrors the existing `SubstituteExerciseUseCase.substituteThisSessionOnly` "this session only" pattern exactly — a future override is best modeled as a targeted re-substitution pass over one Session's movements, not a rematerialization.

## AT. Missing/unknown environment semantics

**SUPERSEDED by the Round-2 Amendment's §A/§D/§Q above.** `nil` reads as `.environmentUnknown` in the pure compatibility rule (never `.compatible`), and as a typed `.trainingEnvironmentRequired` fail-fast failure at the point any materializer would otherwise attempt resolution — history, navigation, and settings remain fully usable regardless. **Remaining genuinely unresolved (unaffected by either blocker)**: exactly when this fail-fast failure should first be surfaced to the user (onboarding-mandatory vs. deferred-to-first-materialization) is a real product-timing decision, not resolved here.

## AU. Persistence/migration decision

Only `TrainingEnvironment` (new `@Model`) and two new fields on `UserProfile` (`trainingEnvironments`, `defaultTrainingEnvironment`) and one new field on `Session` (`materializedInEnvironment`, §U) are new persisted state — all additive, all optional/empty-defaulted, matching this codebase's own established zero-custom-migration precedent (confirmed repeatedly across FF.L1/FF.E1/FF.P1's own real, already-shipped additive-field additions).

## AV. Historical truth

Restated from §V for completeness: proven safe by already-real, already-immutable resolved-`Exercise` relationships — no snapshot duplication needed.

## AW. Minimum required UX

Restated from §Y: one settings surface, create/edit/select-default, reusing `EquipmentRequirement`'s own cases via one new `displayName` helper (§Z).

## AX. Equipment metadata evolution

**None needed.** `EquipmentRequirement` (13 real cases, §AT of the prior audit) already suffices for every real exercise in the catalog (§B) — the only correction needed is authoring discipline (§AA), not a new type.

## AY. 18+ scenario outcomes

1. Full commercial gym + Hypertrophy: all real candidates compatible, normal resolution. 2. Home gym with barbell+rack+bench + Strength: Back Squat/Bench Press-family compatible, cable-only exercises excluded. 3. No cable machine + cable-oriented slot: falls back to a compatible non-cable alternative if the slot is category-based, or a typed conflict if narrowly `allowedExercises`-restricted to a cable movement. 4. Minimal-equipment FF: likely produces real, honest no-valid-candidate failures for squatLoaded/gymnasticsPull unless bodyweight-only alternatives exist (none currently do in the real 3-function reachable set, §B — a genuine content gap TE.1 correctly surfaces, doesn't paper over). 5. No rower/SkiErg/bike: Easy Run/Track Interval Run remain compatible (empty requirement) — the monostructural slot degrades gracefully, never fully empty. 6. Pull-up, no pull-up bar: both real gymnasticsPull candidates fail — typed no-valid-candidate result (§N). 7. Barbell, no rack, Back Squat: fails (`[.barbell,.rack]` not a subset) — Front Squat also fails identically (same requirement) — Thruster (`[.barbell]` only) passes if the slot's function allows it. 8. Hotel gym (mixed dumbbell/machine): dumbbell-only exercises compatible, barbell-rack exercises excluded. 9. Outdoor running: covered by TE.1 (§S, amended) — `.running.requiredEquipment == []`, so it is always `.compatible` once a real environment exists; TE.1 does not model outdoor space/weather/track access, a disclosed, correctly out-of-scope limitation, not an unaddressed gap. 10. Default changes commercial→home before next week: next `rollForward` call picks up the new default automatically (§T), no manual propagation. 11. Readiness substitution under restricted equipment: inherits the same gate (§J), never proposes an incompatible candidate. 12. Row Erg→Assault Bike substitution, Assault Bike unavailable: correctly rejected by the same gate — the FF.P1-era substitution use case's own validity check (§I) now additionally requires environment compatibility, so this specific substitution is blocked, never silently applied. 13. Powerlifting main lift unavailable: typed hard conflict (§L), never a silent substitution. 14. Environment edited after completed sessions: zero effect on history (§V). 15. Rollforward using current default: confirmed fresh-read behavior (§AR). 16. Different environment per day (future): architecturally unblocked by TE.1's design (§AS) even though not implemented now. 17. Existing user migrates with no environment: `nil` default, non-blocking transitional compatibility (§E/§F), app remains usable immediately. 18. Already-materialized future Session survives migration: **Option A locked (§AP-below)** — left unchanged, since it already represents real, already-committed prescription truth; TE.1 does not retroactively validate or rewrite it.

## AZ. Absurdity-test results

All 13 rejected outcomes the user listed are correctly prevented by this design: missing environment does NOT mean full gym in any sense, permanent or transitional — the pure rule returns `.environmentUnknown`, never `.compatible`, and every materializer fails fast with a typed `.trainingEnvironmentRequired` error before any candidate is even considered (Amendment §A/§D, §E/§AT); Pull-up with no pull-up bar is correctly rejected (§AY.6); Back Squat requires BOTH barbell AND rack per real metadata, never barbell alone (§B); Row Erg is never selected via a vague "cardio" category — the real slot constraint is `allowedModalities`/`allowedMovementFunctions`, and the equipment check is a separate, additional AND-condition, never a replacement for semantic matching; no unavailable-equipment semantic OR readiness substitution can pass `isValid` post-TE.1 (§G/§I/§J); no source main lift is ever silently replaced (§L, hard conflict only); editing environment cannot rewrite history (§V); no modality invents its own separate equipment taxonomy — one shared `EquipmentRequirement` enum, one shared `isValid` gate; no materializer reads global mutable state implicitly — environment is an explicit, threaded, testable parameter (§AF/§AG); no partial tactical week persists after a failure (§AI, reuses existing atomic discipline); `[]` will no longer silently mean "unknown" once §AA's fix ships; generation never bakes one environment into a reusable `ProgramDefinition` (§T).

## BA. Proposed TE.1 implementation scope

Confirmed, unchanged from the prior audit's own naming: **TE.1 — Training Environment Foundation.**

## Reprioritized dependency graph (§52)

**SUPERSEDED by the Round-2 Amendment's §P above — TE.2 is removed entirely, folded into TE.1.**

```
TE.1 — Training Environment Foundation (covers Exercise-based AND ActivityType-based modalities)
  → FF.M1 — Movement Diversity Expansion (BLOCKED by TE.1, confirmed §AM)
  → FF.LOAD1 — Numeric Load (SHOULD PRECEDE weakly, §AN)
CP.3 — Concrete Concurrent-Programming Effect (PARALLEL-SAFE with TE.1, confirmed §AL)
FF.RF1 — Result Feedback Foundation (PARALLEL-SAFE, unrelated concern)
Skill system / benchmark-retest / VarianceConstraints activation (INDEPENDENT, unaffected by TE.1)
```

## Exact file/type plan (§50)

**Amended per the Round-2 correction (Amendment §N) — additions in bold.** New: `Domain/Entities/TrainingEnvironment.swift`, `Engines/TrainingEnvironmentCompatibility.swift` (now defines the tri-state enum + `evaluate` free function, not a `Bool`-returning `isCompatible`), `UI/Settings/TrainingEnvironmentSettingsView.swift` (or repo-native equivalent path), **`ActivityType.requiredEquipment` computed property** (in `ActivityType.swift` or a small adjacent extension), test files for each. Modified: `Domain/Entities/UserProfile.swift` (+2 fields), `Domain/Entities/Session.swift` (+1 field, §U), `Domain/ValueTypes/EquipmentRequirement.swift` (+`displayName`), `Engines/ExerciseSubstitutionEngine.swift` (`isValid` gains `environment:` parameter, consumes the tri-state rule), `Application/UseCases/ResolveProgramInstanceExerciseSlotsUseCase.swift`, `Application/UseCases/FunctionalFitnessMaterializer.swift`, `Application/UseCases/SubstituteExerciseUseCase.swift`, `Application/UseCases/SubstituteFunctionalFitnessMovementUseCase.swift`, `Application/UseCases/EvaluateReadinessAdaptationUseCase.swift`, `Application/UseCases/StartNextHypertrophyMesocycleUseCase.swift`, **`Application/UseCases/SteadyStateMaterializer.swift` (gains `throws`, a new small typed error enum, the environment parameter, and the compatibility check at its one real call site)**, **`Application/UseCases/IntervalMaterializer.swift` (gains the environment parameter and the compatibility check at its two real call sites, +1 case on `IntervalMaterializationError`)**, `Application/UseCases/RollTacticalWindowUseCase.swift` (thread environment through `TacticalMaterializationContext` to all six real materializer call sites), `Domain/ValueTypes/TacticalMaterializationContext.swift` (+1 field), `HypertrophyGenerationError`/`FunctionalFitnessMaterializationError`/`IntervalMaterializationError` and Powerlifting's equivalent (+2 cases each — `.trainingEnvironmentRequired` and `.environmentIncompatible`, §M), `Application/Seed/ExerciseCatalog.swift` (§AA's 2-exercise explicit-`[]` fix), `project.pbxproj`.

## Exact test plan (§51)

**Amended per the Round-2 correction (Amendment §O) — additions in bold.** A. `TrainingEnvironment` model round-trip/default-invariant tests. B. `TrainingEnvironmentCompatibilityRule.evaluate` pure-rule tests (subset/empty/**nil-environment produces `.environmentUnknown`, never `.compatible`**/duplicate/future-case). C. Metadata coverage test asserting every real catalog exercise has an explicit `requiredEquipment` argument (closes §AA). D-G. Hypertrophy/Strength/Powerlifting/FF materialization with a real restrictive environment, proving correct filtering. **G2-G3. SteadyState/Intervals materialization with a real restrictive environment at their own real `resolvedActivityType` call sites.** H. Substitution tests (all 3 engines, environment-aware where applicable). I. Readiness tests. J. Rollforward atomicity test (environment-caused failure doesn't partially persist, across all six real materializer call sites). K. Phase transition test. L. Migration/default test (new user, legacy user). M. **Unknown-environment (`nil`) test proving `.trainingEnvironmentRequired` is thrown BEFORE any candidate/activity resolution is attempted, for both Exercise-based and ActivityType-based materializers** (corrected from the original "non-blocking" framing). N. History-immutability test (edit environment after completion, assert no change). O. Existing-future-session migration test (Option A, unchanged). P. User-configuration UI-level test. **P2. Each of the 5 real `ActivityType` cases' exact derived `requiredEquipment` value, table-driven.** Q-U. Full CP.2/CP.2R/FF.L1/FF.E1/FF.P1 regression. V. Full suite. W. `build-for-testing`. X. Persistence/CoreData/SwiftData warning check.

## Unresolved product decisions

**Amended**: the "TE.2 scheduling" question is moot — `ActivityType` awareness is folded into TE.1 (Amendment §I), no separate stage exists. Remaining genuinely unresolved: the exact onboarding gate timing for the `.trainingEnvironmentRequired` fail-fast failure (mandatory-at-onboarding vs. deferred-to-first-materialization — not chosen here, a genuine product call); whether multiple environments ship with full session-override UX in one stage or two (this design supports the model either way without redesign, §AS); `.other` `ActivityType`'s permissive-by-necessity `[]` requirement (Amendment §G) remains a disclosed, not fully resolved, approximation.

## Contradictions found in closed stages

None. The §AA metadata-completeness finding is a new, narrow, pre-implementation fix to seed data, not a reopening of any closed stage's own logic.

## BB. Explicit final statements

**SUPERSEDED by the Round-2 Amendment's §Q above — restated here as the final, authoritative word:**

**TRAINING ENVIRONMENT SUPPORT IS CURRENTLY: MISSING**

**TE.1 IS SAFE TO IMPLEMENT: YES**, once (a) the §AA seed-data fix (explicit `requiredEquipment: []` on Easy Run/Track Interval Run) and (b) the Amendment's `SteadyStateMaterializer` throws-signature change both land as part of the same stage. Exact locked semantics:
- **Unknown environment**: `UserProfile.defaultTrainingEnvironment == nil`. The pure compatibility rule returns `.environmentUnknown` for it — **never** `.compatible`. Every real materializer (Exercise-based AND ActivityType-based) fails fast with a typed `.trainingEnvironmentRequired` error before attempting any resolution when this is the case. History, navigation, and settings remain fully usable regardless.
- **Default environment**: a single nullable reference on `UserProfile`, never a per-row boolean flag — makes "zero or one default" the only representable state.
- **Compatibility**: `Set(required).subtracting(Set(environment.availableEquipment)).isEmpty` once a REAL environment exists — `.compatible`/`.incompatible(missing:)`/`.environmentUnknown`, three genuinely distinguishable states, never collapsed.
- **Source conflicts**: narrow `allowedExercises` slots with no environment-compatible member fail materialization with a typed error; never silently substituted.
- **Materialization failure**: TWO new cases per existing (or, for SteadyState, newly-introduced) per-modality typed error enum — `.trainingEnvironmentRequired` (no environment at all) and `.environmentIncompatible` (real environment, no eligible candidate) — never collapsed into one.
- **Migration**: purely additive; no fabricated environment for existing users; already-materialized future Sessions are left untouched (Option A) unless an explicit new resolution action is taken against them, which then requires a configured environment like any other new resolution.
- **Already-materialized future sessions**: unchanged on migration and on any later environment edit — historical/scheduled prescription truth is never retroactively validated or rewritten by TE.1.

**ALL CURRENT PRODUCTION WORKOUT TYPES ARE COVERED BY THE TE.1 DESIGN: YES** — Exercise-based (Hypertrophy/Strength/Powerlifting/Functional Fitness) via `SubstitutionValidator.isValid`; `ActivityType`-based (SteadyState/Intervals) via the same shared `TrainingEnvironmentCompatibilityRule.evaluate` at their own two real call sites. No current production-reachable modality is deferred to a later stage.

**THE RECOMMENDED NEXT TRAININGOS IMPLEMENTATION STAGE IS: TE.1 — Training Environment Foundation** (scope now covers every current production-reachable modality, Exercise-based and ActivityType-based alike — no separate TE.2 remains).

---

## STOP

Design/audit only. Nothing implemented, committed, or pushed. All five closed stages remain closed and unmodified; none of the six existing design/audit documents was edited.
