# Stage 9B Implementation Report

**STATUS: MANUALLY ACCEPTED by the product owner. Stage 9B is closed.**
See `STAGE9_WARMUP_DESIGN.md` for the approved design (D-W1-D-W6) this
report implements, and the "Manual acceptance record" section below for
the accepted case, the ranking refinement pass, and known
limitations/refinement opportunities that are explicitly NOT Stage 9B
blockers.

## Manual acceptance record

**Case A (upper-body pressing — Bench Press + Incline Dumbbell Press):**
Arm Circles, Band Pull-Apart, Cat-Cow, Inchworm to Push-up, Push-up,
Scapular Wall Slide, World's Greatest Stretch — ~3 min. Accepted.

**Case B (lower-body — Back Squat, Romanian Deadlift, Leg Press, Leg
Curl, Calf Raise, via the debug acceptance fixture reusing the real
`SeedScenarios.materializedLowerASession` production path):**
Ankle Rocks, Bodyweight Squat, Glute Bridge, Inchworm to Push-up, Leg
Swings, Pogo Hops, Single-Leg Balance Reach, Single-Leg RDL Reach
(Bodyweight) — ~5 min. **Accepted** — confirmed to be visibly,
substantively different from Case A and clearly reflective of the
lower-body/squat/hinge demand, not a generic fallback routine.

Both cases were reached only after a ranking refinement pass (see
"Refinement pass" section below) fixed two real bugs found during the
first acceptance attempt: (1) `WarmupEmphasisDerivation`'s pressing/
pulling branch was incorrectly gated behind `MovementFunction`, which
the seeded Hypertrophy catalog entries don't populate, starving the
candidate pool for a pressing session; (2) the general-activation
fallback tier was incorrectly reachable via a coincidental tag-overlap
even when specifically relevant candidates already existed, letting
Arm Circles leak into an unrelated lower-body sequence. Both are fixed
generically (no session-specific hardcoding) in
`WarmupEmphasisDerivation.swift`/`GenerateWarmupSequenceUseCase.swift`;
23 tests cover the fix, including 4 new refinement-specific tests.

## Known limitations / refinement opportunities (NOT Stage 9B blockers)

Explicitly acknowledged and accepted as future refinement, not unfinished
Stage 9B scope:
- Whether every hypertrophy lower-body warm-up should include a
  plyometric item (Pogo Hops) is a content/ranking-weight question, not
  an architecture defect.
- Whether 8 items is the right target count for a ~5-minute window (vs.
  fewer, longer items) is a tunable policy question
  (`WarmupPolicy.maxItemCount`/`targetDurationSeconds`), not a Stage 9B
  requirement.
- `MuscleGroup` has no distinct "hips"/"lower back" case (inherited from
  Stage 8B's own taxonomy).
- The seeded catalog (16 movements) is intentionally small.

## Final domain model

```swift
enum PreparationEmphasis: String, Codable, CaseIterable {
    case ankleMobility, hipMobility, thoracicMobility
    case overheadShoulderMobility, plyometricReadiness
    case unilateralStability, generalActivation
}

enum WarmupPolicy {                       // D-W4 — one central policy source
    static let targetDurationSeconds = 300
    static let perItemMaxSeconds = 60
    static let secondsPerRep = 3
    static let maxItemCount = 8
}

@Model final class WarmupMovement {
    var name: String
    var exercise: Exercise?                        // D-W2: optional link, avoids duplication
    var targetMuscleGroups: [MuscleGroup]           // authoritative only when exercise == nil
    var targetMovementFunctions: [MovementFunction] // authoritative only when exercise == nil
    var emphasis: [PreparationEmphasis]
    var instructionText: String
    var defaultDurationSeconds: Int?
    var defaultReps: Int?
    var hasSides: Bool
    var requiresEquipment: Bool
    // effectiveMuscleGroups / effectiveMovementFunctions read from `exercise` when set
    // estimatedSeconds — reps×secondsPerRep×(hasSides?2:1), capped at perItemMaxSeconds
}

@Model final class WarmupSequence {   // Session-owned, cascade — mirrors ReadinessCheckIn
    var generatedAt: Date
    var wasSkippedEntirely: Bool
    var items: [WarmupSequenceItem]   // cascade
}

@Model final class WarmupSequenceItem {
    var sortIndex: Int
    var movement: WarmupMovement?
    var prescribedDurationSeconds: Int?
    var prescribedReps: Int?
    var wasCompleted: Bool
}

// Session gains: var warmupSequence: WarmupSequence?  (.cascade)
// MovementFunction gains: case jumping (purely additive)
```

Full delete-rule table in `DELETE_RULE_MATRIX.md`'s new "Stage 9B
additions" section — three new relationships, all mirroring an
already-established pattern (`Session -> ReadinessCheckIn`,
`ExerciseSlot -> materializedPrescriptions`).

## Generator algorithm (`GenerateWarmupSequenceUseCase`)

1. Filter `session.orderedBlocks` to in-scope, non-skipped blocks
   (everything except `.steadyState`/`.intervals`/`.warmup`/`.cooldown`/
   `.mobility` — an exhaustive, compiler-checked switch, not an allow-list
   that could silently miss a future case). Empty → no sequence (`nil`).
2. Derive `SessionDemand`: the first in-scope block (by `sortIndex`) is
   primary, the rest secondary — muscle groups collected directly from
   each block's current exercises (post-Stage-8B-adaptation, since
   nothing here reads the template graph), plus a derived
   `PreparationEmphasis` set per tier via `WarmupEmphasisDerivation`
   (pure, deterministic mapping — e.g. `.squatLoaded` → `hipMobility` +
   `ankleMobility`; chest-dominant pressing → `thoracicMobility`;
   shoulder-dominant, non-chest pressing → `overheadShoulderMobility`;
   `.jumping` → `plyometricReadiness`).
3. Candidate pool = full `WarmupMovement` catalog, **pain-excluded**
   first (any candidate whose effective muscle groups intersect
   `readiness.reportedPain` is removed before ranking even happens).
4. Rank remaining candidates by fixed priority: 0 = stiffness match, 1 =
   primary-block match (muscle group OR emphasis), 2 = secondary-block
   match, 3 = `generalActivation`. No match at all → **excluded from the
   pool entirely**, never included as filler (D-W3). Ties broken by
   movement name (deterministic).
5. Greedily walk the ranked list, summing `estimatedSeconds`, stopping
   once the running total reaches `WarmupPolicy.targetDurationSeconds`
   or `maxItemCount` items — whichever first. Nothing already added is
   ever removed to "fit better."
6. Empty result → `nil` (no screen shown at all) rather than an empty
   sequence.

## Candidate ranking / stiffness / pain (Stage 9 design §2 Q4, confirmed by test)

- **Stiffness** re-ranks the *same* candidate pool to priority 0 — it
  never adds items on top of the budget. `test5` proves the total stays
  within budget while the selection genuinely changes.
- **Pain** excludes outright, before ranking, using the identical
  "candidate's own targets disjoint from pain areas" rule
  `EvaluateReadinessAdaptationUseCase.validSubstitute` already uses.
  `test6`/`test11` prove no pain-conflicting candidate is ever included,
  even to fill the time budget.

## Readiness/adaptation ordering — proof the FINAL EXECUTABLE workout is used

`ReadinessGateFlow` now runs warm-up generation strictly after the
adaptation step resolves (accepted, rejected, or never needed) —
`proceedToWarmup(checkIn:)` is the single call site, reading `session`
at that point, which already reflects any accepted Stage 8B mutation in
place. `test7` proves an accepted Level 4 removal means the removed
block's demand (Romanian Deadlift's hinge preparation) is not derived at
all; `test8` proves a rejected adaptation leaves the original demand
intact and reflected in the generated sequence. No second "final
workout" projection exists anywhere — this is free by construction, per
the approved design.

## Persistence / history

`WarmupSequence` is persisted immediately upon generation
(`RecordWarmupSequenceUseCase.record`), before the user acts on it —
same durability discipline as `ReadinessCheckIn`. Marking an item done
and skipping the whole sequence are two independent, separately
persisted facts (`wasCompleted` per item, `wasSkippedEntirely` on the
sequence) — `test17And18` proves both survive a fresh `ModelContext`
reload and remain independently distinguishable. **Nothing here is ever
read by `CompleteSessionUseCase`/`SessionStatus`/`SessionCompletionContext`
— confirmed directly by `test14And15And16`, which completes a Session
with a partially-done, then explicitly-skipped warm-up and asserts
completion is entirely unaffected (D-W6).**

## UI flow

`ReadinessGateFlow` gains one step: after the (possibly-skipped)
adaptation step, `proceedToWarmup` generates and — if non-nil — shows
`WarmupView` (plain checklist, D-W1): title, estimated total minutes,
tappable rows showing name/instruction/duration-or-reps, "Start Workout"
(always available) and "Skip Warm-up" (explicit). No per-item timer, no
video/illustration. If generation returns `nil` (excluded modality or
nothing safe/relevant survives), the flow proceeds straight to
`onFinished` exactly as it did before Stage 9B existed.

## Seeded catalog (16 movements — quality over quantity)

Overhead/horizontal pressing: Arm Circles, Band Pull-Apart, Scapular
Wall Slide, Push-up (linked to the existing `Exercise`), Cat-Cow,
Inchworm to Push-up. Squat/lower body: Bodyweight Squat, Ankle Rocks,
World's Greatest Stretch, Leg Swings. Hinge: Glute Bridge, Single-Leg RDL
Reach. Unilateral/plyometric/general: Single-Leg Balance Reach, Pogo
Hops, Dead Bug, Marching in Place (general fallback). Minimal/no
equipment throughout except Band Pull-Apart (a resistance band).

## Known limitations

- **`MuscleGroup` has no distinct "hips" or "lower back" case** —
  readiness reports of hip stiffness or lower-back pain map to the
  closest available option (`.glutes`, `.back`), a genuine granularity
  limit inherited from Stage 8B's own taxonomy, not introduced here.
- The seeded catalog is intentionally small; some session shapes may hit
  the `generalActivation` fallback tier more often than a larger catalog
  would (`test10` proves the fallback itself works correctly).
- `WarmupEmphasisDerivation`'s mapping rules are TRAININGOS-DESIGNED,
  not clinically validated — same illustrative-default discipline as
  every other such constant in this codebase.

## Deferred work

- **Ramp-up sets** — confirmed out of scope. `SetPrescription.isWarmup`
  remains untouched, still unset anywhere in the codebase, preserved for
  a future `StrengthMaterializer`/strength-execution enhancement.
- **Home Gym / equipment seam** — preserved structurally, not as a dead
  field: `candidatePool`'s doc comment marks the exact point (immediately
  after pain-exclusion, before ranking) where a future equipment/
  environment filter attaches, without an `EnvironmentConstraint` type
  being invented now.
- Real per-item timers, video/illustration, manual/custom workouts,
  strategic planning changes, load-over-reps redesign — all untouched,
  per the approved implementation boundary.

## Test coverage

`WarmupGenerationTests.swift` — 22 test methods: the original 18
covering all 22 requested scenarios (several combined where naturally
related) plus two SwiftData delete-rule tests, plus 4 refinement-pass
tests added after the first manual acceptance attempt (proving
pressing/scapular relevance out-ranks generic fallback; sufficient
relevant coverage doesn't terminate early; a lower-body session never
includes upper-body-only filler even if shorter than target; the
generator stops rather than pads when no relevant candidates remain).
`DebugAcceptanceFixturesUseCaseTests.swift` — 5 tests, including the new
lower-body multi-exercise fixture. All pass. **Final full suite:
699/699, 0 failures.**
