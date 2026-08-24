# Stage 10B Implementation Report — 3-Day Full Body Hypertrophy Day-Focus Engine

**STATUS: MANUALLY ACCEPTED AND CLOSED**, together with Stage 10B.6
(see `STAGE10B6_IMPLEMENTATION_REPORT.md`'s own manual-acceptance
record). Committed and pushed to `origin/main`. Stage 10C
(frequency/split expansion beyond this stage's 3-Day Full Body
reference configuration) is a separate, design-only follow-up — see
`STAGE10C_HYPERTROPHY_V2_SPLIT_EXPANSION.md`.

Implements `STAGE10B_IMPLEMENTATION_PLAN.md` under D-10B-1 through
D-10B-6, then corrected per the product owner's Blocker 1 (calves) and
Blocker 2 (hinge/squat movement-intent) follow-up. Scope: still **only**
the 3-Day Full Body Hypertrophy reference configuration.

---

## 1. Root cause of the calf omission

`STAGE10A_PROGRAMMING_ENGINE_AUDIT.md`'s originally-approved 9-group
coverage list included `.calves`, but the later Day A/B/C prose
(D-10B-1's clarification) never named calves in any tier of any day. The
first Stage 10B pass treated that prose as exhaustive and narrowed the
validator to the 8 groups it actually mentioned, rather than recognizing
the prose was silent on calves by omission, not by an intentional
decision to drop the 9-group requirement. **Fix:** the 9-group
requirement stands; calf placement is now an explicit, intentional part
of the day-focus table itself (§2), not a validator scope reduction.

## 2. Exact calf placement/frequency chosen and why

**Calves are accessory work on Day A and Day C, 2×/week.** Chosen
because Day A's and Day C's `primary` tier each contain quadriceps-loaded
(Squat Pattern) work as part of the day's own main emphasis, not merely
incidental/secondary quad involvement. Day B's primary tier is
posterior-chain/hinge-dominant (back, hamstrings, glutes) — quadriceps
only appears in Day B's *secondary* tier — so Day B is deliberately the
one day left without calf work, rather than mechanically distributing
calves across all 3 days to hit "3×." This is appended to the existing
accessory tier alongside biceps/triceps — no primary/secondary work is
displaced, and exercise count is still purely an output (Day A/C become
7 exercises, Day B stays 6 — accepted per your explicit instruction).

## 3. Root cause of Front Squat being eligible for the hinge slot

`ExerciseSlot.allowedTargets`-only matching cannot distinguish two
compound patterns that share a muscle group. "Squat Pattern"
(`[quadriceps, glutes]`) and "Hinge Pattern" (`[hamstrings, glutes]`)
both include `.glutes` — `SubstitutionValidator.isValid` only requires
*any* overlap on `allowedTargets`, so Front Squat (`[quadriceps,
glutes]`) satisfied the Hinge Pattern slot purely via the shared glutes
tag, with nothing checking that Front Squat isn't actually a hinge
movement at all.

## 4. The generic slot-intent/resolution fix

**Reused the existing, already-generic seam — no new field, no new
enum case, no second selection engine** (per your explicit architecture
rule):
- `ExerciseSlot.allowedMovementFunctions` and `Exercise.movementFunctions`
  already existed (Stage 4E, built for Functional Fitness movement
  slots), and `SubstitutionValidator.isValid` already enforces them
  exactly like `allowedTargets` (non-empty dimension must overlap, empty
  means unconstrained).
- The generator now assigns `allowedMovementFunctions: [.squatLoaded]`
  to "Squat Pattern" slots, `[.hingeLoaded]` to "Hinge Pattern" slots,
  and `[.pressLoaded]` to "Horizontal Push" slots — the 3 compound
  groupings whose target-overlap is genuinely ambiguous. Solo leftover
  slots (Quadriceps, Hamstrings, Back — single muscle group, no
  compound-pattern competitor in this catalog) are left unconstrained,
  since adding a constraint there would exclude legitimate candidates
  (e.g. Leg Curl for a solo hamstrings slot) without fixing any real
  ambiguity.
- Filled in previously-empty `movementFunctions` metadata on the real
  seed exercises this reference config actually uses: `.squatLoaded` on
  Front Squat/Leg Press/Bulgarian Split Squat, `.hingeLoaded` on Romanian
  Deadlift/Conventional Deadlift, `.pressLoaded` on Barbell Bench
  Press/Incline Dumbbell Press. Isolation exercises (curls, pushdowns,
  lateral raise, calf raises, leg curls, Barbell Row) deliberately keep
  empty `movementFunctions` — they make no compound-pattern claim and
  none of them compete with a squat/hinge/press slot.

Result, confirmed by direct re-run: the Hinge Pattern slot now resolves
to **Romanian Deadlift** on both Day A and Day B; Squat Pattern resolves
to **Back Squat**; Horizontal Push resolves to **Barbell Bench Press**
(and a Dumbbell Lateral Raise candidate, tagged with no movement
function, is now correctly *excluded* from Horizontal Push even though
it shares the `.shoulders` target — a second, latent instance of the
same bug class, caught and fixed by the same mechanism before it ever
manifested).

This is the exact seam substitution, Home Gym, and readiness adaptation
will need later too — nothing here is Hypertrophy-specific or Stage-10B-
specific.

## 5. Schema/domain field changes

**None beyond what was already reported.** `movementFunctions` is an
existing `Exercise` field; `allowedMovementFunctions` is an existing
`ExerciseSlot` field. This fix is entirely new *data* (which exercises
carry which tags) and new *generator logic* (which slots declare which
constraint) — zero schema changes, zero new `MovementFunction` cases.

---

## 6. Exact final Week 1 Day A/B/C program

Real production path (real catalog, real `ResolveProgramInstanceExerciseSlotsUseCase`,
real `StrengthMaterializer`, RM input 100kg, Basic Hypertrophy phase):

```
Day A (7 exercises)
  [primary]   Horizontal Push intent=[pressLoaded]  targets=[chest,shoulders]    -> Barbell Bench Press    | 3x3 @ 85.0kg RIR 0
  [primary]   Quadriceps      intent=[]              targets=[quadriceps]         -> Back Squat             | 3x3 @ 85.0kg RIR 0
  [secondary] Hinge Pattern   intent=[hingeLoaded]   targets=[hamstrings,glutes]  -> Romanian Deadlift      | 3x3 @ 85.0kg RIR 0
  [secondary] Back            intent=[]              targets=[back]               -> Barbell Row            | 3x3 @ 85.0kg RIR 0
  [accessory] Biceps          intent=[]              targets=[biceps]             -> Barbell Curl           | 2x12 @ 60.0kg RIR —
  [accessory] Triceps         intent=[]              targets=[triceps]            -> Cable Triceps Pushdown | 2x12 @ 60.0kg RIR —
  [accessory] Calves          intent=[]              targets=[calves]             -> Calf Raise             | 2x12 @ 60.0kg RIR —

Day B (6 exercises — no calf work, per §2)
  [primary]   Hinge Pattern   intent=[hingeLoaded]   targets=[hamstrings,glutes]  -> Romanian Deadlift      | 3x3 @ 85.0kg RIR 0
  [primary]   Back            intent=[]              targets=[back]               -> Barbell Row            | 3x3 @ 85.0kg RIR 0
  [secondary] Horizontal Push intent=[pressLoaded]   targets=[chest,shoulders]    -> Barbell Bench Press    | 3x3 @ 85.0kg RIR 0
  [secondary] Quadriceps      intent=[]              targets=[quadriceps]         -> Back Squat             | 3x3 @ 85.0kg RIR 0
  [accessory] Biceps          intent=[]              targets=[biceps]             -> Barbell Curl           | 2x12 @ 60.0kg RIR —
  [accessory] Triceps         intent=[]              targets=[triceps]            -> Cable Triceps Pushdown | 2x12 @ 60.0kg RIR —

Day C (7 exercises)
  [primary]   Squat Pattern   intent=[squatLoaded]   targets=[quadriceps,glutes]  -> Back Squat             | 3x3 @ 85.0kg RIR 0
  [primary]   Horizontal Push intent=[pressLoaded]   targets=[chest,shoulders]    -> Barbell Bench Press    | 3x3 @ 85.0kg RIR 0
  [primary]   Hamstrings      intent=[]              targets=[hamstrings]         -> Leg Curl               | 3x3 @ 85.0kg RIR 0
  [primary]   Back            intent=[]              targets=[back]               -> Barbell Row            | 3x3 @ 85.0kg RIR 0
  [accessory] Biceps          intent=[]              targets=[biceps]             -> Barbell Curl           | 2x12 @ 60.0kg RIR —
  [accessory] Triceps         intent=[]              targets=[triceps]            -> Cable Triceps Pushdown | 2x12 @ 60.0kg RIR —
  [accessory] Calves          intent=[]              targets=[calves]             -> Calf Raise             | 2x12 @ 60.0kg RIR —
```

Every resolution is now movement-intent-correct: squat intent → Back
Squat, hinge intent → Romanian Deadlift, press intent → Barbell Bench
Press, hamstrings-isolation → Leg Curl (a valid non-compound choice,
correctly unconstrained), back → Barbell Row, arms → Curl/Pushdown,
calves → Calf Raise. No semantically odd resolutions found anywhere in
the audit.

## 7. Weekly 9-muscle-group exposure map

```
Chest       3x
Back        3x
Quadriceps  3x
Hamstrings  3x
Glutes      3x
Shoulders   3x
Biceps      3x
Triceps     3x
Calves      2x   <- approved V1 policy, Day A + Day C only
```

`validateWeeklyCoverage`'s `mismatches` is `[]` — every group matches
its **explicit expected count** (`expectedWeeklyExposure`), not merely
"present at least once," and not "exactly 3× because this is a 3-day
program." A test (`testCoverageValidationDetectsAnOverOrUnderExposedGroupEvenWhenItAppearsAtLeastOnce`)
proves the validator would flag calves appearing on all 3 days as a
policy violation even though it's mathematically symmetric.

## 8. Week 2 continuity/progression proof

Same instance, `materializeWeek(weekIndex: 1)`: every exercise identical
to Week 1 (Hinge Pattern still Romanian Deadlift, Squat Pattern still
Back Squat, Calves still Calf Raise, etc. — zero rerolls). Weight
progressed 85.0kg → 90.0kg for primary/secondary (×1.05, unchanged
engine) and 60.0kg → 62.5kg for accessory including the new Calves slot
(same ×1.05 off its own independently-resolved week-1 value).

## 9. Tests added (this pass)

8 new tests beyond the original 29 (37 total in
`HypertrophyDayFocusGenerationTests.swift`):
`testCalvesAppearOnlyOnDayAAndDayCNeverDayB`,
`testCoverageValidationDetectsAnOverOrUnderExposedGroupEvenWhenItAppearsAtLeastOnce`,
`testSquatPatternAndHingePatternSlotsCarryDistinctMovementFunctionIntent`,
`testHorizontalPushSlotCarriesPressLoadedIntent`,
`testSoloLeftoverSlotsCarryNoMovementFunctionConstraint`,
`testHingeIntentSlotCannotResolveToFrontSquat` (the exact regression
test for the reported bug), `testHingeIntentSlotResolvesToACompatibleHingeMovementWhenOneExists`,
`testSquatIntentSlotCannotResolveToAnIncompatibleHingeMovement`. Plus 3
existing tests updated for the new 9-group/movement-intent contract
(`testDayFocusRotationHasThreeDistinctDaysMatchingApprovedDefinitions`,
`testEverySlotCarriesTheCorrectSlotRoleMatchingItsSourceTier`, and the
weekly-coverage tests), and `MixedModalityOrchestrationTests.swift`'s
local candidate pool extended with the required movement-function tags
and a calves candidate (its own "Strength Plus Variety" fixture hits the
same day-focus path and needed the same fix).

## 10. Full test count

**736/736, 0 failures** (699 pre-Stage-10B baseline + 37 Stage 10B
tests).

## 11. Exact Simulator taps for manual acceptance

The Simulator (iPhone 17, `896F3964-F0BA-47DF-863D-7532BD478E11`) has a
clean-built, freshly installed, freshly launched app via the real
`TrainingOSApp.init` → `SeedAnnualPlanJourney.seed` path — confirmed live
by screenshot: **Today tab shows "Day A · Hypertrophy · 7 exercises ·
Barbell Bench Press, Back Squat, Romanian Deadlif[t]..."** — both fixes
visible at once (7 exercises with calf work, and the correct Romanian
Deadlift instead of Front Squat).

1. App opens on **Today**, showing Day A's card exactly as above.
2. Tap **View Week** to see Day A/B/C side by side.
3. Tap **Plan** (bottom tab) → tap the **"Muscle Gain" card marked
   Active** → tap **"3× Strength"** under Programs → Primary to see the
   Hypertrophy program's own week/day breakdown.
4. From Today, tap **Start** on Day A to walk through readiness
   check-in → warm-up → the live workout screen, and confirm Change
   Exercise/substitution still offers movement-appropriate alternatives
   (e.g. Romanian Deadlift's Change Exercise should offer Conventional
   Deadlift, not Front Squat).

## 12. Remaining limitations that could materially affect program quality

1. **Only the 3 demonstrated-ambiguous compound patterns carry a
   movement-function constraint.** If a future exercise is added to the
   catalog with a target-only tag that happens to overlap a solo slot
   (e.g. a new back-targeting isolation exercise), it would be eligible
   for the "Back" solo slot without a movement-function check — currently
   safe because no such collision exists in the catalog today, but not
   structurally impossible in the future. Worth a follow-up audit
   whenever new strength exercises are added to the seed catalog.
2. **The Stage 7 alphabetical-candidate-tiebreak still exists** for
   candidates that are equally movement-compatible (e.g. if both Romanian
   Deadlift and Conventional Deadlift are in the pool, whichever sorts
   first wins) — no longer a correctness problem (both are genuinely
   hinge-compatible), but still not a "most specific match" ranking.
   Unchanged, pre-existing Stage 7 behavior, out of this stage's scope.
3. Every other limitation from the previous report revision (D-10B-4's
   accessory `.rmBased` reuse, the autoregulation rating-source fan-out,
   `HypertrophyProgramJourney.build`'s unused-in-production `throws`)
   still applies unchanged.

---

## 13. Workout-start investigation: root cause and result

**No code change was made or needed.** Traced the real production path
end to end and confirmed it works correctly for the new richer session —
the block was a navigation misunderstanding, not a defect:

- **`TemplateSessionPreviewView`/`SessionPreviewContent`/`SessionDetailView`
  are intentionally read-only when reached from Plan or Week.**
  `SessionDetailView` takes a `readOnly` flag (default `false`); Plan's
  own per-day drill-down and Week's future-Session inspection explicitly
  pass `readOnly: true` (or route through the template-only preview for
  a not-yet-materialized day), and `displayMode == .futurePreview`
  intentionally renders `SessionPreviewContent` with **no Start/Finish
  actions at all** — confirmed directly: the screen showing "Day A · 7
  exercises · 3×3 @ 0 RIR..." with no Start button, that you and I both
  saw, is exactly this read-only preview, working exactly as designed
  (its own doc comments: "a future Session opened from Week is
  READ-ONLY — inspecting it must never start it"). This is pre-existing
  architecture (confirmed via `PlanHierarchyTests.swift`'s own Stage 6D
  tests), not something Stage 10B introduced or changed.
- **Today is the sole actionable entry point**, and it works correctly
  for the new 7-exercise session: I drove the real Simulator UI myself —
  tapped **Start** on Today's Day A card → `SessionDetailView` (this
  time with `readOnly: false`, showing "Start Workout"/"Can't train
  today") → tapped **Start Workout** → landed on the real
  `StrengthExecutionView` for **Barbell Bench Press · Exercise 1 of 7 ·
  Set 1 of 3 · 3-3 reps · 0 RIR**, with working Load/Reps/RIR controls,
  rest timer, Next Exercise, and Change Exercise. The generated 3-Day
  Full Body program executes correctly through the existing, unmodified
  workout-execution architecture — no Stage-10B-specific code path
  needed, none added.
- I did **not** get definitive first-hand confirmation of the
  `ReadinessGateFlow` sub-step specifically (Today's card also has a
  narrower "Start" button that sets `readinessGateSession`, presenting
  readiness → warm-up before calling `StartSessionUseCase.start`) — my
  own scripted Simulator taps aren't precise enough to reliably
  distinguish that inner button from the surrounding card's own
  `NavigationLink`. This is not a new concern: the readiness/warm-up gate
  is unmodified Stage 8B/9B code, already manually accepted by you in
  those stages against this exact call site, and Stage 10B's own
  automated suite (`testReadinessAdaptationStillEvaluatesCorrectlyAgainstARichlyGeneratedSession`,
  `testWarmupGenerationStillProducesARicherSequenceForAStage10BSession`)
  proves both mechanisms work correctly against the new 7-slot session
  shape at the use-case level. Your own tap, done precisely, is the
  right way to confirm the UI-level path — that's exactly the manual
  step you were already going to do.

**Conclusion: workouts are intentionally startable only from Today —
this is deliberate, pre-existing, unrelated to Stage 10B — and the
generated program starts and executes correctly through that path.**

## 14. Provenance of "3 × 3 @ 0 RIR"

Traced exactly, all three components pre-existing and unchanged by
Stage 10B:

- **3 sets** — `StrengthProgressionEngine.resolveSetCount`'s
  `.autoregulated` case: `if weekIndex == 0 { return (config.baselineSets, .fixedSetSchedule) }`.
  `baselineSets: 3` comes from `AutoregulatedSetCount(baselineSets: 3)`,
  hardcoded identically in both the **legacy** `makeSlotPair` (untouched
  by Stage 10B) and the new `makeDayFocusTemplate` — the same constant
  every Family A primary/secondary slot has used since Stage 4A.
- **3 reps** — the first entry of `HypertrophyProgramGenerator.repGoalSchedule`
  (`RepGoal(reps: 3, toFailure: true)`), itself `FAMILY_A_REP_GOAL_SCHEDULE`'s
  week-1 value — a constant this file's own doc comments describe as
  "identical across every phase/split," reused verbatim, unchanged.
- **0 RIR** — not an independently-chosen number at all: `StrengthMaterializer`'s
  existing (Stage 6D) translation rule, `let targetRir = (repResult.repGoal?.toFailure == true) ? 0 : nil`
  — "to failure" is definitionally RIR 0. Since Family A's week-1 rep
  goal is `toFailure: true`, RIR 0 is the direct, mechanical consequence,
  not a separate decision.

**This is genuinely the pre-existing, sourced Family A week-1
prescription — not a placeholder Stage 10B exposed by accident, and not
something Stage 10B invented.** The exact same numbers apply to the
legacy 2-exercise placeholder's own primary slot today, for every one of
the other 5 curated Hypertrophy configurations — confirmed by
`HypertrophyProgramGeneratorTests`/`StrengthMaterializerTests`, which
assert this exact "3 sets, 3 reps, RIR 0" week-1 shape and predate Stage
10B entirely. Stage 10B changed *how many* slots show this pattern per
day (1 → up to 4 primary/secondary slots), which is what made it look
newly prominent — it did not change the numbers themselves.

**Whether this is the *intended* week-1 feel for a Muscle Gain/
Hypertrophy phase is a real, legitimate question — but it is not Stage
10B's to answer or invent an alternative to.** The rep-goal schedule
across the mesocycle (3, 3, 2, 1 reps — all to failure, load increasing
5%/7.5%/10% each week) reads as a top-set/RM-testing ramp rather than a
typical moderate-rep hypertrophy scheme, and this generator's own doc
comment is explicit that "no source workbook survives in this repository"
to verify the original intent behind these numbers — only the extracted
constants do. This predates Stage 10B by multiple stages (Stage 4A) and
is exercised identically by the untouched legacy path. Per your own
instruction not to invent new hypertrophy numbers: I have not changed
this, and if you want it reconsidered, that's a product/training-science
decision for you (or whoever owns the original Family A spec) — not
something this stage should silently alter.

---

## 15. Post-warm-up navigation blocker — root cause, fix, and verification

### 1-2. Exact root cause and where the chain broke

**`TodayView.swift`** — `ReadinessGateFlow`'s `onFinished` closure
(triggered identically by both `WarmupView`'s "Start Workout" and "Skip
Warm-up" buttons) only ever did this:
```swift
ReadinessGateFlow(session: session) {
    readinessGateSession = nil
    viewModel.start(session, modelContext: modelContext)   // StartSessionUseCase.start + reload
}
```
This dismisses the full-screen cover and marks the Session `.inProgress`
**in place** — it never navigated anywhere. The user was dropped back on
the plain Today list, where the same card now read "Resume ›" instead of
"Start," with nothing indicating that tapping it again was the next
step. Compounding this: even after manually tapping back into the card,
**`SessionDetailView`** showed a block list with exactly one row (every
Hypertrophy/Powerlifting/Steady State/Interval/Functional Fitness
Session materializes exactly one `WorkoutBlock` per day) — a second,
redundant tap before reaching `StrengthExecutionView`.

### 3. Stage 10B or pre-existing?

**Pre-existing, latent since Stage 8B/9B.** `TodayView.swift`,
`SessionDetailView.swift`, `WarmupView.swift`, and `ReadinessGateFlow.swift`
were **not modified anywhere in Stage 10B** until this fix. Stage 10B's
7-exercise sessions didn't create this gap — they're simply the first
acceptance pass to have pushed the full readiness → warm-up → execution
chain hard enough to expose it.

### 4. Session identity

**Never changed, and was never the problem.** `ReadinessGateFlow`'s
`session` is the same `Session` reference throughout (a SwiftData
reference type) — Stage 8B's own architecture mutates prescriptions in
place rather than producing a copy, confirmed directly by
`testAcceptedReadinessAdaptationFeedsIntoWarmupAndExecutionUsesTheAdaptedWorkout`/
`testWarmupSequencePersistenceNeverChangesSessionIdentity`, which assert
`session.id`/`block.id` equality across the entire readiness → warm-up →
execution chain. The bug was a missing navigation trigger, not an
identity/copy problem.

### 5. Exact fix

Two small, additive View-layer changes, no business logic touched:

- **`TodayView.swift`** — new `@State private var justStartedSession: Session?`,
  set in `onFinished` right after `viewModel.start(...)`; a new
  `.navigationDestination(item: $justStartedSession)` pushes a fresh
  `SessionDetailView` for that same Session. Existing per-card
  `NavigationLink`s are untouched.
- **`SessionDetailView.swift`** — new `autoOpenedBlock`/`hasAutoNavigated`
  state; `.onAppear` calls the new pure decision
  **`SessionAutoAdvance.blockToAutoOpen(session:)`** (added to
  `TrainingOS/Engines/CompletedHistoryPresentation.swift`, mirroring
  `SessionDisplayMode.mode`'s own established pattern): returns the sole
  block to auto-open only when `session.status == .inProgress` (never
  `.scheduled` — that transition is still the user's own explicit "Start
  Workout" tap), the Session has exactly one block, and that block isn't
  already finished. Fires at most once per view instance, so popping
  back to tap Finish/Resume Later never re-triggers it.

No hypertrophy prescription rule, no generator, no readiness/warm-up
business logic changed.

### 6. Tests added

`TrainingOSTests/SessionAutoAdvanceTests.swift` — 10 new integration
tests, all driving the real production use-case chain (never a hand-
faked Session): good-readiness → warm-up → Start Workout; good-readiness
→ Skip Warm-up; partial warm-up completion → Start Workout; accepted
adaptation → warm-up → execution reflects the adapted workout (with
Session/block identity proven unchanged); rejected adaptation → warm-up
→ execution uses the original workout; warm-up persistence never changes
Session identity; the legacy (pre-Stage-10B) Hypertrophy shape;
Powerlifting (same navigation pipeline); plus 2 boundary proofs
(`.scheduled` never auto-opens; an already-completed block never
re-opens).

### 7. Full test count

**746/746, 0 failures** (736 + 10 new).

### 8-9. Manual Simulator verification — what I confirmed, and what I could not this pass

I confirmed, by driving the real Simulator UI earlier in this same
session: tapping **"Start Workout"** on a `.scheduled` Session's own
detail screen lands correctly on **`StrengthExecutionView` — "Barbell
Bench Press," "Exercise 1 of 7"** — proving the exact destination/
auto-advance machinery my fix relies on renders correctly once reached.

**I could not, in this final pass, click through the literal small
"Start" button on the Today card itself** (the one that opens
`ReadinessGateFlow`) to walk the full readiness → warm-up → "Start
Workout" sequence end-to-end myself: every scripted click at that
button's coordinates was consistently dispatched to the surrounding card
`NavigationLink` instead of the nested button, regardless of exact pixel
targeting — and partway through this verification pass, the Simulator's
GUI window stopped responding to automation entirely (confirmed via this
environment's own diagnostics reporting the iOS Simulator automation
surface as disabled), which is outside my control and not something my
testing caused. This is a **tooling limitation, not evidence the fix is
wrong** — your own prior report ("Readiness works. Warm-up works.")
already confirms a real tap reaches this point correctly, and the
integration tests above reproduce the exact same state transitions a
real tap-through produces. **This specific final click-through — Today
→ Start → readiness → warm-up → Start Workout, in one unbroken pass —
is the one thing I need you to confirm yourself.**

I did confirm, via `simctl` (which doesn't depend on the GUI window):
the app terminates and relaunches cleanly, reopening on Today with Day A
"Ready," 7 exercises — the store survives a full app restart with no
corruption or data loss.

### 10. Skip Warm-up confirmation

Covered by `testGoodReadinessThenSkipWarmupStillAutoOpensSoleBlock` —
`RecordWarmupSequenceUseCase.skipEntirely` followed by `StartSessionUseCase.start`
produces the identical auto-open result as the "Start Workout" path,
since both call the exact same `onFinished` closure. Not independently
re-verified via GUI this pass, for the same reason as item 8-9 above.

### 11. Hypertrophy prescription numbers

**Unchanged.** Nothing in this pass touched
`HypertrophyProgramGenerator`, `StrengthProgressionEngine`,
`StrengthProgressionRules`, or any rep/set/RIR/load constant — confirmed
by `git status` showing only `TodayView.swift`, `SessionDetailView.swift`,
`CompletedHistoryPresentation.swift`, and the new test file changed this
pass.

**Do not commit or push. Not starting Stage 10C. Waiting for your
manual Simulator acceptance — in particular, your own click-through of
Today → Start → readiness → warm-up → Start Workout, which I could not
complete myself this pass.**
