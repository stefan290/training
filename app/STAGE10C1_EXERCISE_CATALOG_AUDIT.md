# Stage 10C.1 — Exercise Catalog & Movement Family Foundation Audit

**STATUS: AUDIT/DESIGN ONLY. No catalog additions, no Home Gym, no
planner changes, no dormant-config revival implemented.** Every fact
below was read directly from the repository. Recommendations are
explicitly separated from facts and require your approval before any
code is written.

---

## 1. Every exercise in the production catalog (`ExerciseCatalog.swift`)

31 total. Columns: canonical name / movement family (movement-pattern
string + primary targets) / equipment / modality / functions /
aliases / real production candidate pool / Hypertrophy-V2-slot-capable
today / substitution-candidate today.

| Exercise | Movement pattern → targets | Equipment | Modality | Functions | Aliases | Real strength candidate pool? | V2-slot-capable? | Sub. candidate? |
|---|---|---|---|---|---|---|---|---|
| Barbell Bench Press | horizontalPush → chest, triceps | barbell | hypertrophy | pressLoaded | — | **Yes** | Yes | Yes |
| Incline Dumbbell Press | horizontalPush → chest, triceps | dumbbell | hypertrophy | pressLoaded | 3 aliases (~0.94 conf) | **Yes** | Yes | Yes |
| Back Squat | squat → quadriceps, glutes | barbell | strength | squatLoaded | — | **Yes** | Yes | Yes |
| Romanian Deadlift | hinge → hamstrings, glutes | barbell | strength | hingeLoaded | — | **Yes** | Yes | Yes |
| Leg Press | squat → quadriceps, glutes | machine | strength | squatLoaded | — | **Yes** | Yes | Yes |
| Front Squat | squat → quadriceps, glutes | barbell | strength | squatLoaded | — | **Yes** | Yes | Yes |
| Leg Curl | kneeFlexion → hamstrings | machine | strength | — | — | **Yes** | Yes | Yes |
| Calf Raise | ankleExtension → calves | machine | strength | — | — | **Yes** | Yes | Yes |
| Barbell Curl | elbowFlexion → biceps | barbell | hypertrophy | — | — | **Yes** | Yes | Yes |
| Cable Triceps Pushdown | elbowExtension → triceps | cable | hypertrophy | — | — | **Yes** | Yes | Yes |
| Dumbbell Lateral Raise | shoulderAbduction → shoulders | dumbbell | hypertrophy | — | — | **Yes** | Yes | Yes |
| Barbell Row | horizontalPull → back, biceps | barbell | hypertrophy | *(none)* | — | **Yes** | Yes | Yes |
| Bulgarian Split Squat | squat → quadriceps, glutes | dumbbell | strength | squatLoaded | — | No (sub-fixture only) | Yes | Yes |
| Conventional Deadlift | hinge → hamstrings, glutes | barbell | strength | hingeLoaded | — | No (sub-fixture only) | Yes | Yes |
| Seated Leg Curl | kneeFlexion → hamstrings | machine | strength | — | — | No (sub-fixture only) | Yes | Yes |
| Seated Calf Raise | ankleExtension → calves | machine | strength | — | — | No (sub-fixture only) | Yes | Yes |
| Pull-up | verticalPull → back, biceps | bodyweight | **functionalFitness** | gymnasticsPull | — | No (FF pool only) | **Yes — matching never checks `modality`** | limited |
| Deadlift | hinge → back, hamstrings, glutes | barbell | functionalFitness | hingeLoaded | — | No (FF pool only) | Yes | limited |
| Wall Ball | squatToPress → quadriceps, shoulders | medicineBall | functionalFitness | squatLoaded, pressLoaded | — | No (FF pool only) | Yes | limited |
| Thruster | squatToPress → quadriceps, shoulders | barbell | functionalFitness | squatLoaded, pressLoaded | — | No (FF pool only) | Yes | limited |
| Dumbbell Snatch | hingeToPress → shoulders, glutes | dumbbell | functionalFitness | hingeLoaded, pressLoaded | — | No (FF pool only) | Yes | limited |
| Kettlebell Swing | hipHinge → glutes, hamstrings | kettlebell | functionalFitness | hingeLoaded | — | No (FF pool only) | Yes | limited |
| Push-up | horizontalPush → chest, triceps | bodyweight | functionalFitness | gymnasticsPush | — | No | Yes | limited |
| Handstand Push-up | verticalPush → shoulders, triceps | bodyweight | functionalFitness | gymnasticsPush | — | No | Yes | limited |
| Burpee | fullBody → *(none)* | bodyweight | functionalFitness | other | — | No | No (no targets) | No |
| Toes-to-Bar | coreFlexion → core | bodyweight | functionalFitness | gymnasticsPull, trunk | — | No | Yes (core only) | limited |
| Assault Bike / Row Erg / SkiErg / Easy Run / Track Interval Run | locomotion → *(none)* | various | conditioning/FF | monostructural, locomotion | — | No | No | No |

## 2. `ExerciseRelationship` (curated substitution graph)

**Zero rows exist in production data.** Only 2 rows exist anywhere in
the repository, both in test fixtures (`SteadyStatePersistenceTests.swift:146`,
`SubstitutionTests.swift:224`), both `.directSubstitute`, both using
synthetic barbell/dumbbell test exercises — **no real catalog exercise
has ever had a curated relationship authored for it.** Every real
substitution alternative today is discovered purely through
`ExerciseSlot.allowedTargets`/`allowedMovementFunctions` overlap, never
a curated equivalence.

## 3. The slot-matching predicate — a load-bearing finding

`ExerciseSubstitutionEngine.isValid` (`TrainingOS/Engines/ExerciseSubstitutionEngine.swift:30-46`):

```swift
static func isValid(candidate: Exercise, for slot: ExerciseSlot) -> Bool {
    if !slot.allowedExercises.isEmpty {
        return slot.allowedExercises.contains { $0.id == candidate.id }
    }
    if !slot.allowedTargets.isEmpty, Set(candidate.primaryTargets).isDisjoint(with: Set(slot.allowedTargets)) {
        return false
    }
    if !slot.allowedMovementFunctions.isEmpty, Set(candidate.movementFunctions).isDisjoint(with: Set(slot.allowedMovementFunctions)) {
        return false
    }
    if !slot.allowedModalities.isEmpty {
        guard let candidateModality = candidate.functionalModality, slot.allowedModalities.contains(candidateModality) else {
            return false
        }
    }
    return true
}
```

Matching is **"any overlap," never "subset,"** for both dimensions, and
**`Exercise.modality` (`TrainingModality`) is never checked at all** —
only the narrower `functionalModality` is checked, and only when a
slot sets `allowedModalities` (Hypertrophy slots never do). **Concrete
consequence: Pull-up and Deadlift (both `.functionalFitness` modality)
already satisfy a Hypertrophy back/hinge slot today on `primaryTargets`
alone** — the only reason they don't appear in a real Hypertrophy
program is that `SeedAnnualPlanJourney.strengthCandidates` simply omits
them. **This is a candidate-pool curation gap, not a matching-logic
gate** — the cheapest possible "new" vertical-pull/second-hinge option
is not a new exercise at all, it's promoting an exercise that already
exists and already matches.

## 4. Vocabulary ceiling — `MuscleGroup` and `MovementFunction`

```swift
enum MuscleGroup: String, Codable, CaseIterable {
    case chest, back, shoulders, triceps, biceps, quadriceps, hamstrings, glutes, calves, core, forearms
}
enum MovementFunction: String, Codable, CaseIterable {
    case squatLoaded, hingeLoaded, pressLoaded, gymnasticsPull, gymnasticsPush,
         monostructural, carry, locomotion, trunk, jumping, other
}
```

**No sub-region exists for `shoulders`** — lateral delt and rear delt
are both just `.shoulders`; the model cannot distinguish them via
target matching, full stop. **No `MovementFunction` case distinguishes
horizontal/incline/vertical press**, and **no case exists for a
general loaded pull at all** — `.gymnasticsPull` is specifically
bodyweight/gymnastics-flavored (Pull-up, Toes-to-Bar); there is no
`.pullLoaded` analog for a barbell/dumbbell/cable row or lat pulldown
(Barbell Row currently has `movementFunctions: []` — it satisfies zero
movement-function dimension today, matched on `primaryTargets` alone).
**No unilateral/bilateral flag exists anywhere.** **No secondary-target
field exists** — `primaryTargets` is one flat, unweighted list; a
Bench Press's chest emphasis and triceps involvement are represented
identically, with no priority ordering.

## 5. Equipment representation

`Exercise.equipment: String` — a free string, 11 distinct literal
values observed across the catalog (barbell/dumbbell/machine/cable/
bodyweight/kettlebell/medicineBall/bike/rower/skiErg/none), no enum,
no validation, **exactly one value per exercise** (cannot represent
"needs a barbell AND a bench AND a rack"). `EquipmentProfile`/
`EquipmentType` (barbell/dumbbell/machine/cable/bodyweightPlusExternal)
is a completely separate concept — **never attached per-Exercise**,
supplied once per phase/program purely to round a resolved weight.
Nothing today ties one specific Exercise to one specific
`EquipmentType`.

## 6. Movement-family gap matrix (against your 16 required families + audit)

| Family | Real candidates today | Gap? |
|---|---|---|
| Horizontal push | Bench Press, Incline DB Press | None |
| Incline push | *(Incline DB Press exists but is mislabeled `movementPattern: "horizontalPush"` — not actually distinguished from flat)* | **Semantic gap**, not a missing exercise — the model cannot currently tell incline apart from horizontal at all |
| Vertical push (overhead) | Handstand Push-up only (bodyweight, gymnastics-flavored, poor fit for standard hypertrophy rep ranges/progression) | **Real gap** |
| Horizontal pull | Barbell Row (only one; `movementFunctions: []`) | Thin — one option only |
| Vertical pull | Pull-up (catalog-present, matches today, but bodyweight-only and not in the real candidate pool) | Curation gap + thin (no loaded machine/cable option) |
| Knee-dominant squat (bilateral) | Back Squat, Front Squat, Leg Press | None |
| Unilateral knee-dominant | Bulgarian Split Squat (exists, uncurated) | Curation gap only |
| Hip hinge (bilateral) | Romanian Deadlift, Conventional Deadlift (uncurated) | Thin, one curated |
| Hamstring isolation | Leg Curl, Seated Leg Curl (uncurated) | Curation gap only |
| Quadriceps isolation | **None at all** | **Real gap** |
| Chest isolation | **None at all** (Bench/Incline are compound presses) | **Real gap** |
| Lateral delt | Dumbbell Lateral Raise | None |
| Rear delt | **None at all**, and the model can't distinguish it from lateral delt via `MuscleGroup` even once added (§4) | **Real gap + a semantic-model limitation** |
| Biceps | Barbell Curl (only one) | Thin |
| Triceps | Cable Triceps Pushdown (only one) | Thin |
| Calves | Calf Raise, Seated Calf Raise (uncurated) | Curation gap only |

**No additional structurally-necessary movement family was found**
beyond your list — glute-isolation (e.g. hip thrust) was considered and
deliberately not added, since glutes are already well covered by the
existing squat/hinge compounds and your list didn't name it.

## 7. Home Gym future-seam assessment (no implementation)

**Current model gives a clean seam for *training intent*** (targets +
movement function + slot-based resolution — already exactly "what
stimulus is required," never "this exact exercise," confirmed by §3).
**It does not yet give a clean seam for *equipment availability*** —
`equipment: String` is a single loose tag, not a requirements list, so
"can this exercise run in this environment" cannot be answered
correctly today (a barbell bench press needs a bench and often a rack
too; the single string can't say that).

**Recommendation (not a decision I'm making unilaterally):** the
smallest generic foundation worth adding now — not a `HomeGymProfile`,
not any matching logic — is widening `equipment` from one string into
an array of required equipment tags (e.g. `requiredEquipment: [String]`),
so a future Home Gym feature never has to retrofit every exercise's
schema again. Nothing else needs to change now; space/ceiling-height/
rack-specific semantics are correctly left for whenever that feature is
actually scoped, not a "small foundation" item today. **This is a
recommendation, flagged as a decision (§25/main report), not applied.**

## 8. Minimum catalog additions proposed (common, broadly available, nothing obscure)

**Zero-cost (already exist, only need candidate-pool promotion):**
Bulgarian Split Squat, Conventional Deadlift, Seated Leg Curl, Seated
Calf Raise, Pull-up.

**New exercises needed (5, each filling exactly one real gap from §6,
none invented for variety's own sake):**

| New exercise | Fills | Proposed tagging |
|---|---|---|
| Standing Barbell (or Dumbbell) Overhead Press | Vertical push | `[shoulders, triceps]`, barbell/dumbbell |
| Leg Extension | Quadriceps isolation | `[quadriceps]`, machine |
| Cable/Machine Chest Fly | Chest isolation | `[chest]`, cable/machine |
| Face Pull or Reverse Pec Deck | Rear delt | `[shoulders]` — the model cannot yet distinguish this from lateral delt (§4/§6); flagged, not solved here |
| Lat Pulldown | Vertical pull (loaded, non-bodyweight) | `[back, biceps]`, cable/machine |

**One curation decision, not a new exercise either way:** a second
horizontal-pull option (Seated Cable Row — gym-standard — or Dumbbell
Row — more home-gym-friendly) for 4/5-day variety. Your call, not
decided here.

## 9. What Stage 10C.1 would need to actually build (not done yet)

1. Promote the 5 zero-cost exercises into the real strength candidate
   pool.
2. Add the 5 new exercises above (pending your sign-off on exact
   names/tagging).
3. Decide the second horizontal-pull option.
4. Decide whether to widen `equipment` to `requiredEquipment: [String]`
   now (§7) or leave it for whenever Home Gym is actually scoped.
5. Decide whether the rear-delt/lateral-delt indistinguishability (§4)
   is acceptable to leave coarse, or needs a small semantic extension.

---

## 5-Day split architecture comparison (D-10C-4)

Three concrete slot-level structures, evaluated against your criteria.
No exercises hardcoded — only slot intent.

### A. Upper / Lower / Push / Pull / Legs

| Day | Primary tier | Secondary tier | Accessory tier |
|---|---|---|---|
| Upper | Horizontal push, Horizontal/vertical pull | — | Lateral delt, biceps, triceps |
| Lower | Knee-dominant squat, Hip hinge | — | Quad isolation, hamstring isolation, calves |
| Push | Vertical push | Horizontal push (2nd variant) | Lateral/rear delt, triceps |
| Pull | Vertical pull | Horizontal pull (2nd variant) | Rear delt, biceps |
| Legs | Hip hinge (2nd variant) or unilateral squat | Knee-dominant squat (2nd variant) | Hamstring isolation, calves |

Weekly exposure: chest ~2× (Upper+Push), back ~2× (Upper+Pull),
shoulders ~2-3× (Upper+Push, +Pull's rear-delt accessory), quads ~2×
(Lower+Legs), hamstrings ~2× (Lower+Legs), glutes ~2×, biceps ~2×
(Upper+Pull), triceps ~2× (Upper+Push), calves ~2×.

### B. Upper / Lower / Upper / Lower / Full Body

| Day | Primary tier | Secondary tier | Accessory tier |
|---|---|---|---|
| Upper A | Horizontal push, horizontal pull | — | Lateral delt, biceps, triceps |
| Lower A | Knee-dominant squat, hip hinge | — | Quad isolation, hamstring isolation, calves |
| Upper B | Vertical push, vertical pull | — | Rear delt, biceps, triceps |
| Lower B | Unilateral squat, hip hinge (2nd variant) | — | Hamstring isolation, calves |
| Full Body | (light touch of everything) | — | — |

Weekly exposure: most major groups ~2× guaranteed (the two Upper/two
Lower days), rising toward ~3× wherever the Full Body day also touches
them — **but the Full Body day needs its own, currently-nonexistent
"lighter/accessory-weighted" role** to avoid both oversized sessions
and under-recovered muscle groups; this is a real, not-yet-designed
architectural addition, not free.

### C. 5-Day Full-Body Rotation (extends the existing 3-Day mechanism to 5 emphasis-varying full-body days — no Upper/Lower concept introduced)

Each of the 5 days is a `HypertrophyDayFocus`-shaped tier list
(exactly the existing mechanism), just with 5 rows instead of 3,
rotating which 2-3 groups are "primary" each day while everything else
rides as secondary/accessory — structurally the smallest possible
change (literally just a longer rotation array), but pushes every major
group toward ~4-5× real weekly exposure at meaningful intensity, which
is unusually high for standard hypertrophy programming and would need
5 genuinely distinct movement choices per major muscle group to avoid
staleness — the catalog (even after §8's additions) supports at most
3-4 per group, not 5.

### Comparison

| Criterion | A (U/L/P/P/L) | B (U/L/U/L/FB) | C (5× Full Body) |
|---|---|---|---|
| Hypertrophy quality (frequency) | 2×/muscle — well-supported | up to 3× — good if recovery is managed | 4-5× — likely excessive at full intensity |
| Recovery | Clean, even spacing | Needs a new "light day" concept | Weakest — least spacing per group |
| Session duration | Moderate, naturally bounded (fewer groups/day) | Moderate, but Full Body day risks growing large | Every day risks being large (still touching most groups) |
| Movement repetition | Solvable with §8's additions | Needs the same additions, plus more for the Full Body day | Needs the most variety — insufficient even with §8 |
| Progression continuity | Clean — 2 stable slots/muscle | Clean, plus a 3rd looser one | Hardest — 5 slots/muscle need distinct stable identity |
| Concurrent-modality compatibility | Tightest fit already (5 dedicated days) | Same as A | Same as A |
| Substitution ease | Same mechanism, unaffected | Same | Same |
| Home Gym compatibility | Same seam, unaffected | Same | Same |

**Recommendation: A (Upper/Lower/Push/Pull/Legs).** It matches the
best-supported per-muscle frequency without inventing a new session
role (unlike B's undesigned "light day"), needs the least additional
catalog depth to avoid staleness (unlike C), and keeps session sizes
naturally bounded through fewer muscle groups per day rather than more
days doing the same broad thing. B is a legitimate future refinement if
a "light/accessory-weighted day" role is deliberately designed later,
not a reason to prefer it now. C is correctly rejected for the 5-day
*primary* case — it's already the right shape for the 1-2 day
*maintenance* frequencies proposed earlier, not for a primary 5-day
block.
