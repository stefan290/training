# Stage 10R.1 — Slice 1A Implementation Report

**Scope: 3-Day Full Body Hypertrophy, Mesocycle 1 "Basic Hypertrophy," SOURCE
CONTENT ONLY.** Mesocycle 2/3, Slice 1B (progression), the chronological
autoregulation web, the load-first overlay, and every other Hypertrophy
configuration remain untouched, as instructed. Uncommitted, unpushed.

## Product Constitution Check

1. **What source content is authoritative?** The literal, cell-cited
   Mesocycle 1 "Basic Hypertrophy" category sequence recovered from
   `3 day full body_Novice.xlsx` (`SOURCE_PROGRAM_MANIFEST.md` §3) — exact
   day emphasis names ("Push/Legs/Pull Emphasis"), exact category order
   per day, exact Week-1 baseline sets per category.
2. **What TrainingOS infrastructure was reused?** `SlotRole`, the N-slot
   `TemplateSession`/`WorkoutBlockTemplate`/`PrescriptionTemplate`/
   `ExerciseSlot` generation mechanism, `ExerciseSlot.resolvedExercise`'s
   existing idempotent-pre-resolution contract, `SubstitutionValidator`,
   `HypertrophyV2ProgressionEngine`'s rep-range/RIR-by-role table (used
   entirely unchanged), the Stage 10B.6 autoregulation self-attribution
   fix, `ExerciseCatalog`.
3. **What source behavior remained untouched?** All of it, for this
   slice's stated scope: the `.doubleProgression` load rule, the
   autoregulated set-count mechanism, the primary rep-range/RIR trajectory,
   the deload path — none of `StrengthProgressionEngine`,
   `HypertrophyV2ProgressionEngine`, `DoubleProgressionEngine`, or
   `StrengthMaterializer` was edited. Only which categories exist, in what
   order, and their Week-1 baseline-sets input changed.
4. **Why this change did not invent training content?** Every category
   name, day emphasis, and Week-1 sets value is a direct transcription of
   a real cell in a real, personally-owned RP workbook (hash-verified
   identical across two on-disk copies) — not a TrainingOS-authored
   rotation. Exercise *resolution* (which one of several source-approved
   options executes) is TrainingOS's own deterministic, documented choice
   among literal or narrowly-equivalent source-approved names — never an
   unrelated substitute, and never expanding a category's approved set
   with an invented exercise.

## What changed

- **New:** `TrainingOS/Domain/ValueTypes/SourceHypertrophyCategory.swift`
  — canonical category identity (13 cases, the ones Mesocycle 1 needs),
  source-label aliases (Decision 3: normalize internally, preserve the
  literal label for provenance), the full recovered source-approved
  exercise-name list per category, and the real `allowedTargets`/
  `allowedMovementFunctions` per category (including one new,
  additively-tagged `MovementFunction.kneeFlexionLoaded`, to correctly
  distinguish "Hamstrings Isolation" from hip-hinge-pattern deadlift
  variants — the same class of fix as the existing `.verticalPushLoaded`/
  `.horizontalPullLoaded` additions).
- **New:** `ExerciseCatalog.stiffLeggedDeadlift` — the one real,
  source-named exercise this slice's 13 categories had no existing
  cataloged equivalent for (Hamstrings Hip Hinge); `.kneeFlexionLoaded`
  added additively to `legCurl`/`seatedLegCurl`.
- **Changed:** `HypertrophyProgramGenerator.swift` — `threeDayFullBodyRotation`
  (invented Day A/B/C) retired; `generateDayFocusDriven` rebuilt around
  the new `threeDayFullBodyMesocycle1BasicHypertrophy` recovered day/
  category data, with direct-by-canonical-name exercise pre-resolution
  (`findCatalogedExercise`) instead of relying on the shared candidate
  pool's ambiguity-prone overlap matching; `makeDayFocusTemplate` replaced
  by `makeSourceCategoryTemplate(baselineSets:)`, which takes the literal
  source Week-1 sets value instead of a role-derived constant.
  `HypertrophyDayFocus`/`validateWeeklyCoverage`/`trackedMuscleGroups`/
  `expectedWeeklyExposure`/`groupMuscleGroups`/`movementPatternGroupings`/
  `isHeavyQuadsGlutesException` remain declared (generic mechanism, still
  unit-tested) but are no longer wired into any production generation
  path for this configuration.
- **Changed:** `DebugAcceptanceFixturesUseCase.swift` — one added
  parameter (`stiffLeggedDeadlift`) to its `ExerciseCatalog` reconstruction.
- **Changed:** `TrainingOS.xcodeproj/project.pbxproj` — the new source
  file added to the build (PBXBuildFile/PBXFileReference/group/Sources
  entries).
- **Rewritten:** `TrainingOSTests/HypertrophyDayFocusGenerationTests.swift`
  — new source-fidelity tests (exact category sequence per day, exact
  baseline sets, source-approved-set membership, canonical-category/
  label-provenance, no omitted/invented category); generic mechanism
  tests (`groupMuscleGroups`, `validateWeeklyCoverage`,
  `isHeavyQuadsGlutesException`) and other-configuration/Powerlifting
  regression tests kept, updated only where they referenced the retired
  content.
- **Updated for content-only regression** (day names/exercise names
  changed, progression code untouched): `HypertrophyV2EndToEndTests.swift`,
  `SessionAutoAdvanceTests.swift`, `TacticalPlanningOrchestrationTests.swift`,
  `MixedModalityOrchestrationTests.swift`.

## Source category → resolution mapping (documented, per category)

| Source category (Day) | Canonical identity | Resolved exercise | Relationship to source-approved set |
|---|---|---|---|
| Horizontal Push (1,2,3) | `.horizontalPush` | Barbell Bench Press | ≈ "Medium Grip Bench Press" |
| Chest Isolation or Triceps (1) | `.chestIsolationOrTriceps` | Cable Chest Fly | ≈ "Cable Flye" |
| Incline Push or Front Delts (1,2) | `.inclinePushOrFrontDelts` | Barbell Overhead Press | ≈ "Standing Barbell Shoulder Press" |
| Side Delts (1,2) | `.sideDelts` | Dumbbell Lateral Raise | ≈ "Dumbbell Side Lateral Raise" |
| Vertical Pull (1,2,3) | `.verticalPull` | Lat Pulldown | ≈ "Wide-Grip Pulldown" |
| Horizontal Pull (1,2,3) | `.horizontalPull` | Barbell Row | ≈ "Barbell Bent Over Row" |
| Hamstrings Isolation (1,3) | `.hamstringsIsolation` | Seated Leg Curl | exact literal match |
| Quads (1: 1x, 2: 2x) | `.quads` | Front Squat, then Leg Press (2nd occurrence) | both exact literal matches |
| Hamstrings Hip Hinge (2) | `.hamstringsHipHinge` | Stiff-Legged Deadlift | exact literal match (new catalog row) |
| Rear Delts or Side Delts (3) | `.rearOrSideDelts` | Face Pull | ≈ "Cable Facepull" |
| Biceps (3) | `.biceps` | Barbell Curl | exact literal match |
| Incline Push (3) | `.inclinePush` | Incline Dumbbell Press | exact literal match |
| Glutes (3) | `.glutes` | Conventional Deadlift | ≈ "Deadlift" |

## Tests

29 new/updated tests in `HypertrophyDayFocusGenerationTests.swift`, all
passing. Full suite: **770/770 passing**, 0 failures, real Xcode build
(not a syntax-only check).

## Simulator

Fresh install + launch on iPhone 17 Pro (`A18AB0FB-82F2-4F51-ABFC-7BF232DC3340`).
Real production path (`SeedAnnualPlanJourney` → `LongTermPlanner` →
`StartPhaseUseCase`/`TransitionPhaseUseCase`, unchanged) reaches Today
showing **"Push Emphasis," Hypertrophy, 8 exercises, "Barbell Bench Press,
Cable Chest Fly, Barbell Ove[rhead Press]..."** — the real recovered Day 1
content, not the retired invented rotation. Left on this screen, Start not
tapped. (This session's sandboxed environment had no permitted UI-tap path
into the Simulator to open the full detail view — the Today card itself is
the production-path evidence captured.)
