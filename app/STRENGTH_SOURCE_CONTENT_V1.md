# Strength Source Content V1 + Product Model Alignment Fixes

Implementation checkpoint. Not committed, not pushed — stopped after
implementation, verification, dogfood, and this report for independent
review, per explicit instruction.

## COMPLETION PASS — WHAT CHANGED FROM THE PREVIOUS VERSION OF THIS REPORT

Independent review of the original checkpoint found **two unresolved
blockers**, both now fixed. The original report's final verdict
prematurely marked `STRENGTH PROGRAM 2 SOURCE FIDELITY: PASS` and
`STRENGTH SOURCE CONTENT V1: CLOSED` — **both were wrong**, for the
reasons below. This version corrects both, with real code changes, real
tests, and a real dogfood proof — it does not merely reword the verdict.

**Blocker 1 (source fidelity regression)**: Family E's Friday-Legs2
backoff rep goal ("1/2 Tuesday's" — the source's own footnote,
`Strength_Program_2.xlsx`, `c.) Mesocycle` B48/B49) is genuinely defined
relative to Tuesday-Legs2's ACTUAL logged reps, per set index, halved and
floored (worked example: Tuesday logs 10,8,8,8,7,7 across its 6 sets;
Friday, which has 2 sets, targets 5,4). The original pass substituted the
generic placeholder RIR schedule instead — a real, disclosed-but-still-
wrong shortcut that discarded real source meaning, exactly the kind of
improvisation the checkpoint's own STOP condition existed to prevent. This
is now modeled exactly: a new `RepPrescriptionKind.priorSlotActualResultRelative`
case, a new `PrescriptionTemplate.actualResultReferenceSlot` cross-slot
reference, a new pure resolver (`ActualResultRelativeRepGoalResolver`), and
a new, narrowly-scoped backfill use case
(`PriorSlotActualResultRepGoalBackfillUseCase`) invoked from
`CompleteSessionUseCase.complete` — see §5 and §10 below for the full
design and its justification.

**Blocker 2 (content unreachable)**: the previous pass built real Family
D/E content in `StrengthSourceContentLibrary` but never wired it into any
athlete-facing resolution path — `strengthFocusedMix()`'s component still
resolved exclusively through `PowerliftingBuiltInLibrary` (Family B/C),
meaning "Strength Training" never actually materialized as the recovered
Strength content, only as more Powerlifting content under a corrected
label. This is now fixed with the smallest additive change: a new
`TrainingMixComponent.strengthContentSelector` field (CONTENT selection,
never execution-engine identity — `programmingSystem` stays `.powerlifting`
throughout) that `powerliftingParameterCandidates` reads to choose which
library to resolve against. See §7/§11 below for the full design, the full
end-to-end proof, and why the existing Powerlifting candidate set is
provably unaffected.

Both fixes are additive; no existing passing test was weakened, and no
closed system was reopened. Full suite: **1592 tests, 0 failures** (was
1582/0 before this completion pass — 10 new tests, zero regressions).

---

## 1. Baseline

Full suite immediately before the ORIGINAL implementation pass: **1554
tests, 0 failures**. After that pass: **1582 tests, 0 failures** (28 new
`StrengthSourceFidelityTests`). Independently re-confirmed at the start of
THIS completion pass: still **1582 tests, 0 failures** — matches exactly,
no drift, safe to build on. The previously-known
`StrategicPhaseTransitionUITests.testTransitionWithNoCalibrationRequiredSystemMaterializesSessionsImmediately`
failure continues not to reproduce (a pre-existing, unrelated UI-test
flakiness matter, not a regression from either pass).

## 2. Product-Model Corrections

Unchanged from the original pass, independently re-confirmed still intact
this completion pass (neither blocker touched these):

**Fix 1 — General Strength must not say Powerlifting.**
`LongTermPlanner.strengthFocusedMix()`: `TrainingMix.name` = `"Focused
Strength Training"`; component `label` = `"Strength Training"`.
`programmingSystem: .powerlifting`, `adaptationObjectives: [.maxStrength]`,
`frequency`, `priority` unchanged.

**Fix 2 — Strength Training adaptation objective.**
`defaultAdaptationObjectives(for:)`: `.hypertrophy` → `[.muscleGain]`,
`.strengthTraining` → `[.maxStrength]` (previously incorrectly shared).

## 3. Files Changed

**From the original pass** (unchanged this completion pass):
`PowerliftingConfiguration.swift` (+`.d`/`.e`), `ProgramCapabilityRegistry.swift`
(+`isPowerliftingSourceVerified` for `.d`/`.e`), `StrengthSourceContentLibrary.swift`
(new), `StrengthSourceFidelityTests.swift` (new, extended this pass — see
below), `GoalTrainingStyleProductModelTests.swift` (Fix 1 label updates,
extended this pass), `project.pbxproj` (manual registration).

**New this completion pass**:
- `TrainingOS/Domain/ValueTypes/StrengthProgressionRules.swift` —
  `RepPrescriptionKind.priorSlotActualResultRelative` (Blocker 1),
  `StrengthReasonCode.repGoalRequiresPriorSlotActualResult` (Blocker 1),
  `RepGoal.priorSlotActualResultRelative` static helper.
- `TrainingOS/Domain/Entities/PrescriptionTemplate.swift` —
  `actualResultReferenceSlot` (+ inverse) (Blocker 1); flattened
  `repGoalIsPriorSlotActualResultRelative: [Bool]` override array, purely
  additive to the existing `repGoalSchedule` flattening (Blocker 1).
- `TrainingOS/Engines/StrengthProgressionEngine.swift` — `resolveRepGoal`
  now honestly reports `(nil, .repGoalRequiresPriorSlotActualResult)` for
  this rep-goal kind at week-materialization time (Blocker 1).
- `TrainingOS/Engines/AutoregulationRatingResolver.swift` —
  `mostRecentlyCompletedPrescription` widened from `private` to internal
  so the new resolver can reuse its exact selection logic, never duplicate
  it (Blocker 1).
- `TrainingOS/Engines/ActualResultRelativeRepGoalResolver.swift` (new) —
  the pure resolver (Blocker 1).
- `TrainingOS/Application/UseCases/PriorSlotActualResultRepGoalBackfillUseCase.swift`
  (new) — the backfill use case (Blocker 1).
- `TrainingOS/Application/UseCases/CompleteSessionUseCase.swift` — calls
  the backfill use case once a session completes (Blocker 1).
- `TrainingOS/Application/UseCases/StrengthMaterializer.swift`,
  `TrainingOS/Application/Seed/SeedScenarios.swift`,
  `TrainingOS/Engines/StrengthTrainingStressMapper.swift`,
  `TrainingOS/UI/Plan/TemplateSessionPreviewView.swift` — each has exactly
  one exhaustive `switch`/`case` over `RepPrescriptionKind` that the
  compiler required updating for the new case; each updated to the
  correct, honest behavior (Blocker 1 — see §5 for detail on each).
- `TrainingOS/Application/UseCases/PowerliftingProgramGenerator.swift` —
  `generateFamilyE`'s Friday-Legs2-backoff row now uses
  `.priorSlotActualResultRelative` + `actualResultReferenceSlot = tueLegs2`
  instead of the placeholder RIR schedule (Blocker 1); its own top-level
  doc comment corrected to no longer claim this is an accepted, unmodeled
  gap. `generateFamilyD`/`generateFamilyC`/`generateFamilyB` **untouched**
  (confirmed: `git diff` shows zero `+`/`-` lines inside `generateFamilyC`'s
  or `generateFamilyB`'s bodies).
- `TrainingOS/Domain/Entities/TrainingMixComponent.swift` — new
  `strengthContentSelector: StrengthContentSelector?` field + new
  `StrengthContentSelector` enum (Blocker 2).
- `TrainingOS/Domain/ValueTypes/ProgramCapabilityRegistry.swift` — new
  `isStrengthSourceContentFrequencySupported(_:)`, separate from
  `supportedFrequencies(for: .powerlifting)` (Blocker 2).
- `TrainingOS/Application/UseCases/LongTermPlanner.swift` —
  `strengthFocusedMix()` sets the new selector; `buildCustomMix`'s
  `.strengthTraining` case sets it too and gates frequency through the new
  Strength-specific capability check; `powerliftingParameterCandidates`
  branches on the selector to resolve against `StrengthSourceContentLibrary`
  instead of `PowerliftingBuiltInLibrary` when set (Blocker 2).

No onboarding file touched. No `TrainingMix` schema change beyond the one
new optional field. No `ProgrammingSystemKind`/engine/materializer change.

## 4. Strength Program 1 Implementation (Family D)

Unchanged from the original pass — re-confirmed this completion pass by
full regression (`StrengthSourceFidelityTests`'s Family D tests, all still
passing unmodified). No Family D content or mechanic was touched by either
blocker's fix.

## 5. Strength Program 2 Implementation (Family E) — CORRECTED THIS PASS

Everything from the original pass stands (4 days, 16 rows, uniform 10RM,
2.5 working-week rounding, RIR 3/3/2/1, Monday/Tuesday-unchanged-Thursday/
Friday-halved deload, the Friday backoff's LOAD being plain `.rmBased` at
0.85× rather than `.linkedToPairedSlot`) — **except** the Friday backoff's
REP GOAL, which is corrected here:

**The exact recovered source rule** (re-verified directly against
`Strength_Program_2.xlsx`'s own footnote, B48/B49): `"'1/2 Tuesday's'
instructs that you should stop your reps at half of what you did on
Tuesday's 'legs move 2'... So if you did 10,8,8,8,7,7 reps on Tuesday, you
should only do 5,4 reps on Friday's second exercise. Only 2 sets as
indicated. If a rep is odd, round down."` This is a **per-set-index**
correspondence — `target[i] = floor(Tuesday's actual reps at set index i /
2)`, for `i` in `0..<Friday's own set count` (2) — never "half of the
total," "half of the last set," or "half of the average." The fraction
(one-half) is a fixed, source-confirmed constant; there is exactly one
recovered relationship of this shape (this row), so this is not a
generalized "result-relative rep goal" framework, just this one modeled
correctly.

**Why this genuinely cannot be resolved at week-materialization time** (a
new architectural fact this completion pass established, not assumed):
`RollTacticalWindowUseCase.materializeFirstWindow`/`rollForward` build one
whole week at a time, in a single call, before any of that week's own
sessions have been executed. Every EXISTING cross-slot dependency in this
codebase (`AutoregulationRatingResolver.rating`/`previousWeekSetCount`) is
a **cross-week** dependency — week N reads week N-1's already-completed
data, always safely available by materialization time. Family E's Friday-
depends-on-Tuesday relationship is a **same-week, cross-day** dependency —
genuinely new in kind, and unresolvable at the moment Friday's own
`SetPrescription`s are first created (Tuesday, 3 days earlier in the same
week, has not been performed yet).

**The fix, mirroring two existing precedents exactly**:
1. At week-materialization time, `StrengthProgressionEngine.resolveRepGoal`
   now special-cases this rep-goal kind and returns `(nil,
   .repGoalRequiresPriorSlotActualResult)` — an honest, unresolved state,
   mirroring `SourceCompatibleDeloadStrategy.resolveDeloadRepGoal`'s own
   `(nil, .deloadRepsRequireLoggedPerformanceData)` precedent for a
   structurally analogous "genuinely can't know yet" case. **The two are
   NOT the same case**: deload's ambiguity has NO source-provided answer
   (which Week-1 set to reference is genuinely undetermined); Family E's
   Friday-Tuesday relationship has an EXACT, unambiguous source formula —
   it just can't be evaluated until Tuesday happens. A new, distinct
   `StrengthReasonCode` case exists for exactly this reason.
2. A new, narrowly-scoped `PriorSlotActualResultRepGoalBackfillUseCase`,
   invoked from `CompleteSessionUseCase.complete` right after a session is
   marked completed, scans the same `ProgramInstance` for any not-yet-
   executed prescription whose template carries an
   `actualResultReferenceSlot` and still has unresolved (`nil`)
   `SetPrescription`s, and resolves them via
   `ActualResultRelativeRepGoalResolver` — which reads the referenced
   slot's most-recently-completed prescription's real, logged `SetResult.reps`
   (reusing `AutoregulationRatingResolver`'s own proven "most recent,
   completed-preferred" selection logic, never duplicated), computes
   `floor(actual/2)` per set index, and persists the result. **Never
   touches the referenced slot's own logged `SetResult`s or completed
   `SetPrescription`s** — only fills in a not-yet-executed sibling's own,
   previously-`nil` fields. **Idempotent** — only ever touches a
   `SetPrescription` whose `repRangeLow` is still `nil`, so calling it
   repeatedly (e.g. a double-tapped Finish button, matching
   `CompleteSessionUseCase.complete`'s own existing idempotency contract)
   is always safe.
3. **A THIRD cross-slot reference was needed, not a reuse of the existing
   two**: this row already has `pairedSlot = thuLegs1` (its RATING
   pairing) and no `autoregulationReferenceSlot` set. Its REP-GOAL
   relationship is to a DIFFERENT slot again (Tuesday-Legs2) — reusing
   `autoregulationReferenceSlot` for this would have overloaded a field
   whose own doc comment specifically ties it to autoregulation rating,
   not rep-count derivation. `PrescriptionTemplate.actualResultReferenceSlot`
   is a new, small, precisely-named third reference — `nil` for every
   other row in every family, purely additive.
4. **Persistence shape**: follows this codebase's own hard-won rule
   exactly — no enum-with-multiple-associated-values on an `@Model`.
   `RepPrescriptionKind.priorSlotActualResultRelative` carries NO payload
   at all (mirrors `LoadRuleKind.doubleProgression`'s own "resolution
   reads real logged history externally" shape) — the flattened storage
   gets one new, purely additive `Bool` array
   (`repGoalIsPriorSlotActualResultRelative`), defaulting to `false`/empty
   for every pre-existing row, zero risk to Family A/B/C/D.
5. **Missing-prior-result behavior**: confirmed the source provides no
   fallback text for "Tuesday wasn't done" — the honest "pending" state
   (§ above) is therefore correct, not a placeholder pending a better
   answer.
6. **Family C's analogous "1/2 Monday's" relationship — deliberately left
   UNCHANGED this pass.** Per the user's own explicit instruction, this was
   NOT migrated: doing so was judged out of the narrow scope of this
   checkpoint (it would mean touching Family C's own generator, a CLOSED,
   already-verified system, for a mechanic this pass did not set out to
   fix there). This is **disclosed, deferred source debt**, not silently
   swept under the "same as before" rug — see §14.

## 6. Engine Reuse

Unchanged from the original pass for Family D/E's own load/set-count/
deload mechanics. This completion pass's Blocker 1 fix adds exactly one
new mechanic (`RepPrescriptionKind.priorSlotActualResultRelative` +
its resolver/backfill pair) — investigated first, confirmed genuinely
necessary (no existing mechanism expresses "rep goal relative to another
slot's ACTUAL logged performance"), and kept as narrow as the one
recovered relationship requires. No STOP condition was triggered this
pass either — the new mechanic was buildable additively.

## 7. Content Identity — Blocker 2 fix

`StrengthSourceContentLibrary` remains deliberately separate from
`PowerliftingBuiltInLibrary.all` (unchanged design decision from the
original pass, now actually load-bearing since content is reachable).

**The reachability fix**: `TrainingMixComponent.strengthContentSelector:
StrengthContentSelector?` (new, optional, additive field; `nil` for every
existing component/system — zero behavior change for anything that
doesn't set it). `StrengthContentSelector` has exactly one case,
`.sourceBackedGeneralStrength` — a CONTENT-selection discriminator,
explicitly not a new `ProgrammingSystemKind`: `programmingSystem` stays
`.powerlifting` on every component regardless of this field.

`powerliftingParameterCandidates(component:)` now branches on
`component.strengthContentSelector`: `nil` resolves against
`PowerliftingBuiltInLibrary.all` exactly as before (byte-for-byte, proven
by regression — see §12); `.sourceBackedGeneralStrength` resolves against
`StrengthSourceContentLibrary.all` instead, via the SAME existing
`closestByDayCount` tie-break logic, just pointed at the other library —
no new selection heuristic, no duplicated logic.

`strengthFocusedMix()` and `buildCustomMix`'s `.strengthTraining` case both
set the new selector — the two real production paths that create a
`.powerlifting`-engine component for the "Strength Training" athlete-facing
style. Business logic never infers this from the display `label` string
(CLAUDE.md rule 16's general principle) — a proper typed field drives
resolution, always.

## 8. Capability Gating — Blocker 2 fix

`ProgramCapabilityRegistry.isStrengthSourceContentFrequencySupported(_:)`
(new) — reads `StrengthSourceContentLibrary.all`'s own day counts
directly (currently `{4}`), fail-closed for anything else. Deliberately
SEPARATE from `supportedFrequencies(for: .powerlifting)` (still `{4, 5}`,
untouched, still derived only from `PowerliftingBuiltInLibrary.all`) —
Strength content's real capability must never be silently widened by the
broader Powerlifting engine's own `{4, 5}`.

`buildCustomMix` now applies BOTH checks for a `.strengthTraining`
selection: the existing `isFrequencySupported(_:for: .powerlifting)`
(passes for 4 or 5) AND the new Strength-specific check (passes only for
4) — so requesting "5x Strength Training" (a real, valid Powerlifting
frequency, but not a real Strength Program frequency) is correctly
rejected outright, never silently approximated to the nearest supported
Strength configuration. Proven by
`testBuildCustomMixStrengthTrainingRejectsFrequencyValidOnlyForPowerlifting`.

## 9. Calibration

Unchanged from the original pass.

## 10. Source Fidelity Verification

Original pass's 28 tests unchanged and still passing. This completion pass
adds:
- 6 new tests in `StrengthSourceFidelityTests.swift` proving the Family E
  rep-goal dependency: the canonical source-footnote fixture (10,8,8,8,7,7
  → 5,4, exactly as the workbook's own worked example), odd-actual-reps
  rounds down, honestly-pending-before-Tuesday-completes, never-mutates-
  Tuesday's-own-logged-results, idempotent-across-repeated-completion, and
  honestly-unresolved-at-materialization-time (with the reason code
  asserted directly, not inferred).
- 2 new tests proving `buildCustomMix`'s Strength-specific capability gate
  (accepts 4 + sets the selector; rejects 5 even though it's valid for the
  underlying Powerlifting engine).
- 2 new tests in `GoalTrainingStyleProductModelTests.swift` proving the
  FULL production chain (see §11) and proving an unrelated, selector-less
  `.powerlifting` component's resolution is completely unaffected.

## 11. Dogfood — Blocker 2's full chain, not stopping at the label

`testGeneralStrengthRecommendationResolvesToStrengthSourceContentNotPowerlifting`
(new): `Goal(primaryType: .generalStrength)`, no stated preference →
`StrategicPlanSelectionViewModel.load` (the real, full,
private-`candidateMixTemplates`-exercising production path) →
`reviewedMix.name == "Focused Strength Training"`, its component carries
`strengthContentSelector == .sourceBackedGeneralStrength` → that REAL
component passed into `LongTermPlanner.proposeProgram` (the exact function
`StartPhaseUseCase` calls in production) → resulting candidates' own
`ProgramDefinition.name`s contain "Strength Training," NEVER "Powerlifting"
→ their `powerliftingConfiguration.family` values are exactly `{.d, .e}`,
never `{.b, .c}`. A companion negative-control test
(`testPowerliftingComponentWithoutSelectorStillResolvesToPowerliftingBuiltInLibrary`)
proves an ordinary, selector-less `.powerlifting` component still resolves
to `{.b, .c}` exactly as before this checkpoint (both entries, since
`closestByDayCount` has ALWAYS returned best + one runner-up for a 2-entry
library — confirmed pre-existing, unrelated behavior, not something this
pass changed).

**Program 1 vs Program 2 selection**: `StrengthSourceContentLibrary.all`'s
2 entries are both `dayCount: 4`; `closestByDayCount`'s existing
alphabetical tie-break surfaces "Strength Program 1 (General Strength)" as
primary and "...Program 2..." as the visible runner-up — exactly the same
"more than one legitimate option, both surfaced, athlete/approval flow
decides" pattern every other system with 2+ equally-close curated entries
already uses. No new selection heuristic invented, matching the directive's
explicit instruction not to fabricate a "better fit" rule the source gives
no basis for.

**Family E's actual-result dependency, dogfooded through the real
production path** (`testFamilyEFridayBackoffResolvesFromTuesdayActualLoggedRepsCanonicalFootnoteFixture`):
real `StrengthMaterializer.materializeWeek` week-0 materialization → real
`LogSetUseCase.logSet` (the actual production set-logging entry point,
not a hand-constructed `SetResult`) logs Tuesday-Legs2's 6 sets as
10,8,8,8,7,7 → real `CompleteSessionUseCase.complete(tuesday, ...)` →
Friday's backoff `SetPrescription`s resolve to exactly `[5, 4]` — the
workbook's own worked example, reproduced exactly through real production
code. A companion test proves an odd actual count (7) rounds DOWN (→3),
never up.

## 12. Regression Results

- Targeted (`StrengthSourceFidelityTests` + `GoalTrainingStyleProductModelTests`):
  36 + 16 = 52 tests (was 28 + 14 = 42 before this completion pass), **0
  failures**.
- Full suite: **1592 tests, 0 failures** (was 1582/0 before this
  completion pass). 1592 − 1582 = 10, exactly the number of new tests
  added this pass (6 + 2 + 2) — confirming zero other test-count drift and
  zero regressions anywhere else in the suite, including every existing
  Powerlifting/Hypertrophy/deload/autoregulation test.
- `PowerliftingSourceFidelityTests`/`PowerliftingProgramGeneratorTests`
  (Family B/C's own tests) re-run explicitly: unchanged, all passing —
  proves Family C's deliberately-untouched status is real, not merely
  claimed.

## 13. Closed-System Impact

None of the explicitly protected closed systems were touched. Family C's
own generator code (`generateFamilyC`) has zero `+`/`-` diff lines
(confirmed directly via `git diff`) — the deferred-debt decision in §5.6/
§14 is a genuine non-change, not a disguised one.

## 14. Deferred Follow-Ups

- **Family C's own "1/2 Monday's" relationship** (the analogous, pre-
  existing, already-disclosed gap in stock Family C's own Friday-Push1
  backoff) — NOT migrated to the new mechanic this pass, per explicit
  instruction. This is now the SAME class of gap as Family E's was before
  this completion pass — a real, disclosed, deferred source-fidelity item
  for stock Powerlifting Family C, to be picked up as its own narrow
  follow-up (reusing `RepPrescriptionKind.priorSlotActualResultRelative`/
  `actualResultReferenceSlot`/the resolver/backfill pair, all already
  built and proven — the follow-up would be almost entirely wiring, not
  new mechanism design).
- Wiring Family D/E into the broader athlete-facing recommendation
  surface beyond `strengthFocusedMix()`/`buildCustomMix` (e.g. an explicit
  Program-1-vs-2 UI choice, if ever wanted beyond the existing best+
  runner-up candidate pattern) — FOLLOW-UP, not required now.
- `TrainingStyle.powerlifting` / a distinct Powerlifting preference —
  FOLLOW-UP/V2, unchanged from the original pass's own deferral.
- RM self-calibration, peaking, competition workflow — deferred, unchanged.
- `muscleGainVariedMix()`'s "Strength" label under the Hypertrophy engine
  — cosmetic-only, FOLLOW-UP, unchanged.

## 15. Final Verdict

PRODUCT MODEL LABEL FIX: PASS
STRENGTH ADAPTATION OBJECTIVE FIX: PASS
STRENGTH PROGRAM 1 SOURCE FIDELITY: PASS
STRENGTH PROGRAM 2 SOURCE FIDELITY: PASS
CROSS-SESSION ACTUAL-REP RULE: PASS
STRENGTH CONTENT PRODUCTION REACHABILITY: PASS
GENERAL STRENGTH RESOLVES TO STRENGTH SOURCE CONTENT: PASS
EXACT STRENGTH FREQUENCY 4: PASS
POWERLIFTING CANDIDATE SET UNCHANGED: PASS
SOURCE RM SEMANTICS: PASS
AUTOREGULATION GRAPH: PASS
DELOAD FIDELITY: PASS
GENERAL STRENGTH CONTENT IDENTITY: PASS
SHARED ARCHITECTURE REUSED: PASS
NEW STRENGTH ENGINE CREATED: NO
FULL SUITE: PASS
NEW FAILURES: 0
STRENGTH SOURCE CONTENT V1: CLOSED
READY FOR WHOLE ATHLETE JOURNEY: YES
