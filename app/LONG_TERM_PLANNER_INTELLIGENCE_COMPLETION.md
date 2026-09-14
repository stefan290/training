# Long-Term Planner Intelligence Completion — Strategic Periodization

Vertical Completion V2 from the Whole Athlete Journey final audit, fixing
BLOCKER LTP-1. Implementation checkpoint. Not committed, not pushed —
stopped after implementation, dogfood, tests, and this report for
independent review.

## 1. Baseline

Full suite immediately before this checkpoint's changes: **1604 tests, 0
failures** (`xcodebuild test-without-building -parallel-testing-enabled
NO`, real summary line, confirmed directly before any edit).

## 2. Root Cause

`LongTermPlanner.fillForwardPhases` (`LongTermPlanner.swift:463-527`) was
the single production function responsible for sequencing phases when no
dated objective/milestone exists (the common case). Its entire logic was:

```swift
let useMaintenance = consecutivePrimary >= 2
let phaseType: PhaseType = useMaintenance ? .maintenance : primaryType
```

— a raw counter, never a reason. For GET STRONGER this produced
`Strength, Strength, Maintenance, Strength, Strength, Maintenance, ...`
forever; for BUILD MUSCLE, `MuscleGain, MuscleGain, Maintenance, ...`
forever. No phase ever carried a distinguishing reason beyond
`.phaseSelectedForGoal` for a primary-type phase, or the same code for
Maintenance. This directly failed the product's own north star (a
"long-term training operating system," not a short-program repeater) for
the plurality of athletes who never set a dated objective.

## 3. Existing Strategic Vocabulary (inventoried before writing any code)

- **`GoalType`**: `muscleGain, fatLoss, generalStrength, enduranceEvent,
  functionalFitness, maintenance` — 6 cases, unchanged, all outcomes.
- **`PhaseType`**: `muscleGain, fatLoss, strength, enduranceEvent,
  functionalFitness, recovery, transition, maintenance` — **8 cases,
  unchanged**. Critically: `.recovery` already existed as a fully
  distinct, wired case (own `PhaseDurationDefaults` entry, own display
  name, own `candidateMixTemplates` arm) but was never produced by
  `fillForwardPhases`. `.transition` already existed and is used,
  unchanged, by the dated-objective path.
- **`PhaseDurationDefaults`**: `.muscleGain` 12wk (6-20), `.fatLoss` 8wk
  (4-12), `.maintenance` 4wk (2-8), `.recovery` 2wk (1-4), `.transition`
  2wk (1-3), `.strength` 8wk (4-12), `.functionalFitness` 8wk (4-12) — all
  unchanged.
- **`PlannerReasonCode`**: an open, `CaseIterable`, additive vocabulary
  already carrying `phaseSelectedForGoal`, `fatLossTimedToMilestone`,
  `muscleRetentionPriority`, `transitionPhaseInserted`,
  `recoveryPhaseInserted` (already existed, previously unused by the
  mechanical loop), `objectivePrepCompressed`, and 15 more. **Exactly one
  new case added this checkpoint**: `developmentPhaseSupportsPrimaryGoal`.
- **`candidateMixTemplates(phase:goal:)`**: already offers 2 real
  candidates for `.muscleGain` (`muscleGainFocusedHypertrophyMix` — 5x
  Hypertrophy + Zone 2; `muscleGainVariedMix` — 3x Hypertrophy-engine
  "Strength" + FF + Running) and 2 for `.strength` (`strengthFocusedMix` —
  4x Strength Training, `.powerlifting` engine via
  `strengthContentSelector: .sourceBackedGeneralStrength` → Family D/E;
  `muscleGainVariedMix`, shared verbatim across both phase types). `.fatLoss`
  already has `fatLossConditioningFocusedMix`/`fatLossVariedMix`.
  `.functionalFitness` has exactly one candidate. `.maintenance` already
  has a real, sophisticated policy seam (`maintenanceMix`, see §10).
  `.recovery`/`.transition` already share `lowerDemandGenericMix`, with an
  existing comment explicitly inviting exactly this kind of independent
  extension. **None of this needed to change** — the fix is entirely in
  which `PhaseType` `fillForwardPhases` asks for, never in how a
  `PhaseType` resolves to content.
- **`phaseType(for goalType:)`**: unchanged — still the fixed
  goalType→phaseType mapping for the PRIMARY phase only.
- **`proposeReconciledPhases`/`proposeMilestoneAnchoredPhases`**: the
  dated-objective path, confirmed genuinely good by the Whole Athlete
  Journey audit. Both call `fillForwardPhases` as a sub-routine for their
  own fill-segments — this checkpoint's fix automatically integrates with
  them for free, since `fillForwardPhases`'s public signature/contract
  (`(from:to:primaryType:baseReasonCodes:) -> (phases:feasible:)`) is
  unchanged; only its internal phase-type decision changed.
- **`TrainingPhaseCompletion`/`TacticalWeekCompletion`**: confirmed by
  direct read that date boundaries are NEVER treated as proof of
  completion — real transition-readiness is decided by tactical
  exhaustion (+ Hypertrophy's own existing, `.basicHypertrophy →
  .metaboliteFocus → .resensitization` mesocycle-succession mechanism,
  `HypertrophyProgramJourney.orderedPhaseTypes`, already user-initiated,
  never automatic). This means a phase's planned `endDate`/`durationKind`
  is only a forward-looking STRATEGIC ESTIMATE for horizon-filling/Plan
  display — it does not need to be forced to exactly match a source
  mesocycle's real length, and no new `.fixed(weeks:)` special-casing was
  needed anywhere.

## 4. Strategic Periodization Policy

New file: `TrainingOS/Application/UseCases/StrategicPeriodizationPolicy.swift`
— a small, pure policy type kept deliberately separate from horizon
filling (still `fillForwardPhases`'s job), TrainingMix resolution (still
`candidateMixTemplates`'s job), and program resolution (still
`proposeProgram`'s job):

```swift
enum StrategicPeriodizationPolicy {
    struct PhaseIntent { var type: PhaseType; var reasonCodes: [PlannerReasonCode] }
    static func nextPhaseIntent(primaryType: PhaseType, cyclePosition: Int) -> PhaseIntent
}
```

`fillForwardPhases` now calls this once per phase it builds, incrementing
`cyclePosition` regardless of type (replacing `consecutivePrimary`).
Deterministic: same `(primaryType, cyclePosition)` always returns the same
intent — no randomness, no clock read.

## 5. Authority Classification

Every phase-type/duration/reason decision in this checkpoint is a
**TrainingOS STRATEGIC POLICY** decision, explicitly labeled as such in
code comments — never attributed to RP, CrossFit, the Running source, or
any workbook. Source authority is untouched: `strengthFocusedMix()` still
resolves only to canonical General Strength Family D/E content (never
Powerlifting competition/peaking, which does not exist to select);
`muscleGainFocusedHypertrophyMix()`/`muscleGainVariedMix()` still resolve
to the exact same, unchanged Hypertrophy source content; the dated-
objective path's Running/`.enduranceEvent` handling is completely
untouched.

## 6. Get Stronger Policy

```swift
case .strength:
    [PhaseIntent(.muscleGain, [.developmentPhaseSupportsPrimaryGoal]),
     PhaseIntent(.strength, []),
     PhaseIntent(.strength, []),
     PhaseIntent(.maintenance, [.recoveryPhaseInserted])]
```

**A. GET STRONGER remains the primary Goal throughout** — verified
directly (`goal.primaryType` asserted unchanged after building/accepting
the plan in every test).
**B. Direct-strength phases resolve to canonical General Strength content**
— `strengthFocusedMix()`'s component carries `strengthContentSelector:
.sourceBackedGeneralStrength`, resolving to Family D/E only, verified via
`proposeProgram`.
**C. The development phase legitimately uses the Hypertrophy engine** —
`.muscleGain`-typed, resolves through the unchanged
`muscleGainFocusedHypertrophyMix()`/`muscleGainVariedMix()` candidates.
**D. Described as supporting GET STRONGER, never changing the Goal** — the
new `developmentPhaseSupportsPrimaryGoal` reason code says exactly this;
`Goal.primaryType` is never touched.
**E. Recovery has a real purpose, not a counter** — the `.maintenance`
phase now carries `recoveryPhaseInserted`, and reuses `.maintenance`'s own
real, existing reduced-dose-of-the-preceding-mix policy (see §10) rather
than an arbitrary generic filler.
**F/G. No Powerlifting-specific peak, no competition content invented** —
confirmed: no such candidate/content exists anywhere in
`candidateMixTemplates`/`StrengthSourceContentLibrary` to select.

## 7. Build Muscle Policy

```swift
case .muscleGain:
    [PhaseIntent(.muscleGain, []),
     PhaseIntent(.muscleGain, []),
     PhaseIntent(.maintenance, [.recoveryPhaseInserted])]
```

Deliberately does **not** insert a Strength-typed phase for symmetry with
Get Stronger — no real reason exists for one, and the directive explicitly
forbids inventing one merely for visual variety. Build Muscle legitimately
repeats `.muscleGain`-typed phases more than Get Stronger repeats
`.strength`-typed phases (explicitly permitted) — the key fix is that the
down-regulation phase is now `recoveryPhaseInserted`-reasoned policy, not
an uncommented `consecutivePrimary >= 2` counter. Hypertrophy remains the
sole canonical primary content, unchanged.

## 8. Lose Fat Policy

```swift
case .fatLoss:
    [PhaseIntent(.fatLoss, [.muscleRetentionPriority]),
     PhaseIntent(.fatLoss, [.muscleRetentionPriority]),
     PhaseIntent(.maintenance, [.recoveryPhaseInserted])]
```

Reuses the existing `fatLossConditioningFocusedMix()`/`fatLossVariedMix()`
candidates and the existing `muscleRetentionPriority`/
`fatLossTimedToMilestone` reason codes, unchanged. **Disclosed limitation**
(per the directive's own explicit permission to document rather than
fabricate precision): no distinct "development" sub-role was invented for
Lose Fat, since neither the directive nor current domain content
establishes what such a role would concretely mean for a fat-loss goal
specifically (unlike Get Stronger's real, existing hypertrophy-content
building block). Lose Fat's long-term intelligence is therefore currently
limited to "repeated Fat Loss blocks + a real, reasoned recovery period" —
a genuine, disclosed improvement over the old counter-loop, but not as
strategically rich as Get Stronger's. No nutrition/metabolic claims were
added or implied anywhere.

## 9. Functional Fitness Policy

```swift
case .functionalFitness:
    [PhaseIntent(.functionalFitness, []),
     PhaseIntent(.functionalFitness, []),
     PhaseIntent(.maintenance, [.recoveryPhaseInserted])]
```

`candidateMixTemplates(.functionalFitness)` has exactly one existing
candidate (`functionalFitnessFocusedMix()`) — no variety mechanism exists
to select between alternatives, so this checkpoint does not invent one.
Same disclosed limitation as Lose Fat: a real, reasoned recovery period
replaces the old counter-hack, but no distinct development/intensification
sub-role was invented, since current FF authored content offers none to
select. No FF V2 content, no new claimed source authority (still
TrainingOS-authored V1, unchanged).

## 10. Maintenance / Recovery / Transition Semantics

Investigated directly before deciding: `.maintenance` already has a real,
extensively-tested policy (`LongTermPlanner.maintenanceMix`/
`maintenanceComponentDecisions`) that preserves whatever the athlete was
ACTUALLY training in the immediately preceding phase, at a genuinely
reduced dose — never a generic unrelated substitute. `.recovery`/
`.transition` currently share a simpler `lowerDemandGenericMix` (flat 2x
General Conditioning), with an existing code comment explicitly noting
this is deliberate and that a distinct policy could be added independently
later without touching Maintenance's own.

**Decision**: the periodic down-regulation slot in every cycle above uses
`PhaseType.maintenance` (not `.recovery`), because `.maintenance`'s own
existing, real, unchanged reduced-dose-of-the-actual-preceding-mix policy
is a strictly better strategic fit for "recover from accumulated focused
development" than `.recovery`'s current generic fallback. **This does not
redefine `.maintenance`'s semantics** — every existing test
(`MaintenancePlanningContextTests`, 18 tests) continues to pass unmodified,
proving the policy/content itself is untouched. The only change is that
this `.maintenance` phase now also carries the new
`recoveryPhaseInserted` reason code, making the STRATEGIC PURPOSE ("a
policy-driven periodized down-regulation," not "the athlete's goal is now
maintenance") explicit for the first time. `.recovery` itself remains
fully intact, untouched, and available for a future checkpoint that wants
a genuinely different down-regulation policy. A phase never exists merely
because `consecutivePrimary >= 2` anymore — it exists because
`StrategicPeriodizationPolicy`'s explicit, documented cycle says so, with
a real reason code attached.

## 11. Phase Duration Policy

**CORRECTED by the Completion Pass (LTP-DURATION-1) — this section's
original claim below is superseded; see §12A for the fix.** The original
implementation reused `PhaseDurationDefaults.range(for:)` unmodified for
every phase type, on the reasoning that a phase's planned duration is
"only a forward-looking strategic estimate, never itself the mechanism
that decides real transition-readiness." That reasoning is correct as far
as it goes (tactical exhaustion, not dates, decides real
transition-readiness — unchanged, confirmed again below), but independent
review correctly identified that it does not excuse TrainingOS from
knowingly representing an estimate it already knows is wrong at planning
time. For `.strength`-typed phases specifically, TrainingOS already knows
(a) they resolve to Family D/E, (b) Family D/E is exactly 5 real weeks,
and (c) no succession exists — so an 8-week estimate was not honest
uncertainty, it was a knowing misrepresentation. §12A below is the fix.

## 12. Strategic Phase vs Source Mesocycle

Investigated directly (`RollTacticalWindowUseCase.swift`,
`TrainingPhaseCompletion.swift`, `HypertrophyProgramJourney.swift`,
`StartNextHypertrophyMesocycleUseCase.swift`) before writing any code:

- **Family D/E (Direct Strength phases)**: exactly 5 real source weeks,
  confirmed unchanged (`PowerliftingProgramGenerator.generate` still
  produces this length — now read from a named constant,
  `mesocycleLengthWeeks`, see §12A). No mesocycle-succession mechanism
  exists for Powerlifting-engine content (`hasNextHypertrophyMesocycle`
  reads `instance.programDefinition?.hypertrophyConfiguration`, `nil` for
  a Powerlifting-engine `ProgramDefinition`) — so a `.strength`-typed
  phase becomes genuinely phase-terminal
  (`TrainingPhaseCompletion.isPhaseTerminal`) at exactly its own real 5th
  week, confirmed directly in the dogfood (§22). **This was previously,
  incorrectly, described in this report as "sooner than the 8-week
  planning estimate — harmless." That framing is retracted — see §12A: it
  is not harmless, it is the exact bug (LTP-DURATION-1) this Completion
  Pass fixes.**
- **Hypertrophy (Development phases)**: `.basicHypertrophy` configuration,
  confirmed unchanged 5 real source weeks per mesocycle
  (`progressiveWeekCount(for: .basicHypertrophy) == 4`, `+1` deload).
  Hypertrophy DOES have a real, existing, user-initiated succession
  mechanism (`StartNextHypertrophyMesocycleUseCase`, confirmed by direct
  read of its own doc comment: "a Hypertrophy mesocycle succession is
  program-level progression INSIDE that same strategic phase" — it reuses
  the SAME `TrainingPhase`/`TrainingMix`/`TrainingMixComponent`, only
  creates a fresh `ProgramInstance` and reassigns the component's current
  pointer, per `HypertrophyProgramJourney.orderedPhaseTypes =
  [.basicHypertrophy, .metaboliteFocus, .resensitization]`) — meaning a
  `.muscleGain`-typed phase's real natural duration (before
  `isPhaseTerminal` returns true) can legitimately span more than one
  5-week mesocycle if the athlete explicitly advances through it, closer
  to the type's own ~12-week planning estimate than to a single 5-week
  block. **This is the exact, narrow distinction §12A's fix keys off**:
  `.muscleGain` correctly stays uncapped; `.strength` does not have this
  mechanism and correctly gets capped.
- **No mid-phase reinstantiation mechanic was needed or built.** The
  existing, already-proven `StartPhaseUseCase`/`TransitionPhaseUseCase`
  phase-to-phase transition machinery is the ONLY mechanism this checkpoint
  relies on for moving between strategic phases — confirmed end-to-end in
  the dogfood (§22). STOP condition C was not triggered.
- **No source weeks are ever invented, stretched, or duplicated** —
  confirmed directly: the dogfood's real Family D/E instance keeps exactly
  5 `orderedWeeks` throughout, and the same `ProgramDefinition.id`
  persists across every real tactical roll within its own natural
  lifetime.

## 12A. Strategic Duration vs Executable Program Capacity (LTP-DURATION-1 fix)

**Old behavior**: `fillForwardPhases` used `PhaseDurationDefaults.range(for:
intent.type)` unconditionally for every phase type's planned duration —
`.strength` therefore planned at 8 weeks (the generic estimate) even
though, at planning time, TrainingOS already knew the phase would resolve
to Family D/E (exactly 5 real weeks, no succession). Golden Scenario A's
own original table showed this literally; the checkpoint's own dogfood
independently proved the real transition happens at week 5. This was a
knowing misrepresentation, not estimate uncertainty — a real, disclosed
CHECKPOINT BUG (LTP-DURATION-1), not a design flaw in
`StrategicPeriodizationPolicy` itself (which is unchanged by this fix).

**New invariant**: STRATEGIC PHASE DURATION must be coherent with
CURRENTLY EXECUTABLE PROGRAM LIFECYCLE. `TrainingPhase` and
`ProgramInstance` remain distinct concepts (a phase may still legitimately
span multiple mesocycles, as `.muscleGain` already does) — but where
current production capability provides only one exact source mesocycle
with no succession mechanism, the planned phase duration must not exceed
what is currently, actually executable.

**Implementation** — the narrowest correct capability source, not a
hardcoded `if phaseType == .strength` disconnected from source truth:

1. `PowerliftingProgramGenerator`'s previously-inline `lengthWeeks: 5`
   literal is now a named constant, `PowerliftingProgramGenerator
   .mesocycleLengthWeeks`, read by `generate(configuration:...)` itself —
   one single source of truth, never two independently-maintained copies
   of "5."
2. `StrategicPeriodizationPolicy.executablePlanningDuration(for
   phaseType: PhaseType) -> PhaseDurationKind?` (new, pure, small): returns
   `.fixed(weeks: PowerliftingProgramGenerator.mesocycleLengthWeeks)` for
   `.strength` (the one phase type that both resolves to a single
   fixed-length mesocycle AND has no succession mechanism); `nil` for
   every other phase type, including `.muscleGain` (Hypertrophy's real
   succession mechanism justifies keeping its existing, uncapped
   estimate — proven directly,
   `testStrengthPlannedDurationCappedToExecutableCapacityHypertrophyNotCapped`).
3. `fillForwardPhases` now computes `phaseDurationKind =
   StrategicPeriodizationPolicy.executablePlanningDuration(for:
   intent.type) ?? PhaseDurationDefaults.range(for: intent.type)` — a
   2-line change. When the capability source returns non-`nil`, it wins;
   otherwise behavior is byte-for-byte unchanged from the prior
   (accepted) implementation.

No new Strength succession mechanism was built (deliberately out of
scope — that is separate, deferred future work). `StrategicPeriodizationPolicy
.cycle(for:)` (the Development → Strength → Strength → Recovery sequence
of TYPES) is completely unchanged — this fix only changes DURATION for one
phase type, never which types appear or in what order (confirmed directly,
`testGetStrongerCycleShapeUnchangedByTheDurationFix`).

**Get Stronger revised yearly trace** (real production output,
`testGoldenA_GetStrongerTwelveMonthsProducesRealStrategicVariety`, same
inputs as the original Golden A — `GoalType.generalStrength`,
2026-01-05 → 2027-01-04):

| Phase # | Start | End | Duration | PhaseType | Strategic Purpose | Executable Programming Capability |
|---|---|---|---|---|---|---|
| 1 | 2026-01-05 | 2026-03-29 | 12wk | muscleGain | Development — capacity-building supporting the strength goal | Hypertrophy (uncapped — real succession mechanism) |
| 2 | 2026-03-29 | 2026-05-03 | **5wk** | strength | Direct strength development | Family D/E (capped to real executable length) |
| 3 | 2026-05-03 | 2026-06-07 | **5wk** | strength | Direct strength development (second block) | Family D/E |
| 4 | 2026-06-07 | 2026-07-05 | 4wk | maintenance | Recovery/down-regulation | Maintenance (reduced-dose of preceding) |
| 5 | 2026-07-05 | 2026-09-27 | 12wk | muscleGain | Development (cycle repeats) | Hypertrophy |
| 6 | 2026-09-27 | 2026-11-02 | **5wk** | strength | Direct strength development | Family D/E |
| 7 | 2026-11-02 | 2026-12-07 | **5wk** | strength | Direct strength development (second block) | Family D/E |
| 8 | 2026-12-07 | 2027-01-04 | 4wk | maintenance | Recovery/down-regulation | Maintenance |

8 phases now fit in the same 52-week horizon (was 6, with the old,
incorrect 8-week Strength estimate) — TWO complete Development→Strength→
Strength→Recovery cycles, a materially more credible demonstration of real
periodization than the original table. Every Strength phase is now
exactly `PowerliftingProgramGenerator.mesocycleLengthWeeks` (5) weeks,
verified by direct assertion in the updated
`testGoldenA_GetStrongerTwelveMonthsProducesRealStrategicVariety`.

**Actual-vs-planned dogfood proof**
(`testDogfood_GetStrongerCrossesRealFamilyDMesocycleEndAndStrategicPhaseBoundary`,
extended this pass): after real materialization, 5 real tactical rolls,
and real session completion, `TrainingPhaseCompletion.isPhaseTerminal`
becomes true at real elapsed time `strengthPhase.startDate + 5 weeks`
(confirmed: `rollDate` after the roll loop is `startDate + 4 weeks`;
exhaustion is reached exactly 7 days later). This is now asserted directly
equal to `strengthPhase.endDate` — **the planned end date and the real
executable exhaustion point are now the same date, with no known
deterministic gap**. The SECOND Direct Strength phase (`nextPhase` in the
same test) is confirmed to carry the same corrected 5-week planned
duration, proving the fix applies uniformly, not just to the first
occurrence.

Build Muscle (Golden B) was re-run as a control and is completely
unaffected — its cycle never produces a `.strength`-typed phase, so
`executablePlanningDuration` always returns `nil` for it; every duration
in Golden B's table is unchanged from the original report.

## 13. TrainingMix Policy

Recommended mixes remain advisory; a `.selected` mix remains authoritative
and is never silently replaced. Verified directly
(`testExactSelectedTrainingMixStaysAuthoritativeUntilAcceptedRevision`):
after an athlete explicitly selects "Strength Plus Variety" for a phase,
re-running `LongTermPlanner.proposeStrategicPlan` for the same goal does
not touch `phase.selectedTrainingMix` at all — no code path in this
checkpoint's changes reads or writes `TrainingMixComponent`/`TrainingMix`
selection state; `fillForwardPhases`/`StrategicPeriodizationPolicy` only
ever produce `ProposedPhase` VALUES (never-yet-persisted proposals), never
touch an already-`.selected` mix on an already-accepted phase.

## 14. Dated Objective Integration

`proposeReconciledPhases`/`proposeMilestoneAnchoredPhases` are completely
unmodified — confirmed via the full, unchanged pass of
`DatedObjectivesReconciliationTests` (all pre-existing assertions,
unweakened). This checkpoint's new policy only changes what
`fillForwardPhases` — called BY those functions as a sub-routine —
produces for the FILL segments before/between/after dated objectives.
Golden C (§18) and Golden D (§19) both prove this integration live: base
strategy → objective reconciliation (real `.transition` phase) → the
objective's own phase → return toward the primary goal, using the NEW,
richer cycle for every fill segment, with `Goal.primaryType` never
mutated.

## 15. No-Target-Date Behavior

Unchanged, per explicit instruction: `proposeForwardOnlyPhases` still
returns a single, permanently open-ended phase when no target date exists
(`LongTermPlanner.swift:123-127`) — a deliberate, honest choice (never
fabricate a horizon), not touched or reclassified by this checkpoint.
Confirmed by direct read; not re-tested since nothing in this area
changed. No small rolling-horizon improvement was pursued — out of scope,
correctly not broadened into.

## 16. Golden Scenario A — Get Stronger

`GoalType.generalStrength`, target date ~52 weeks out (2026-01-05 →
2027-01-04), no dated objective, no Powerlifting preference. Full real
production trace (`testGoldenA_GetStrongerTwelveMonthsProducesRealStrategicVariety`),
**revised by the Completion Pass — see §12A for the full LTP-DURATION-1
fix; this table replaces the original report's own table, which
incorrectly showed 8-week Strength phases**:

| Phase # | Start | End | Duration | PhaseType | Strategic Purpose | Adaptation Objective | TrainingMix Role | Reason Authority |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-01-05 | 2026-03-29 | 12wk | muscleGain | Development — capacity-building supporting the strength goal | muscleGain | Focused Hypertrophy / Strength Plus Variety (Hypertrophy engine) | TrainingOS Strategic Policy |
| 2 | 2026-03-29 | 2026-05-03 | **5wk** | strength | Direct strength development | maxStrength | Focused Strength Training → Family D/E | Source-Backed Rule (content) + TrainingOS Strategic Policy (sequencing + executable-capacity cap) |
| 3 | 2026-05-03 | 2026-06-07 | **5wk** | strength | Direct strength development (second block) | maxStrength | Focused Strength Training → Family D/E | Source-Backed Rule + TrainingOS Strategic Policy |
| 4 | 2026-06-07 | 2026-07-05 | 4wk | maintenance | Recovery/down-regulation after 2 focused strength blocks | (preserves preceding mix, reduced dose) | Maintenance (reduced-dose of whatever preceded it) | TrainingOS Strategic Policy |
| 5 | 2026-07-05 | 2026-09-27 | 12wk | muscleGain | Development (cycle repeats) | muscleGain | Focused Hypertrophy / Strength Plus Variety | TrainingOS Strategic Policy |
| 6 | 2026-09-27 | 2026-11-02 | **5wk** | strength | Direct strength development | maxStrength | Focused Strength Training → Family D/E | Source-Backed Rule + TrainingOS Strategic Policy |
| 7 | 2026-11-02 | 2026-12-07 | **5wk** | strength | Direct strength development (second block) | maxStrength | Focused Strength Training → Family D/E | Source-Backed Rule + TrainingOS Strategic Policy |
| 8 | 2026-12-07 | 2027-01-04 | 4wk | maintenance | Recovery/down-regulation | (preserves preceding mix, reduced dose) | Maintenance | TrainingOS Strategic Policy |

**8 phases now fit the same 52-week horizon (was 6)** — a direct,
material consequence of Strength phases now honestly reflecting their
real 5-week executable capacity rather than a knowingly-wrong 8-week
estimate; the year now shows TWO complete Development→Strength→Strength→
Recovery cycles instead of 1.5. Answers to the directive's own 13
questions: phases are created in an explainable 4-position cycle
(Development → Strength → Strength → Recovery), each with an explicit
reason; Direct Strength resolves to Family D/E (source-verified) AND is
now planned for its real executable duration; development legitimately
uses Hypertrophy; recovery is real and reasoned; the year shows genuine
periodization, not a repeating short program; Plan (unmodified) can now
honestly surface these real reasons AND real durations since they exist on
`ProposedPhase.reasonCodes`/`durationKind`.

## 17. Golden Scenario B — Build Muscle

`GoalType.muscleGain`, ~52 weeks, no objective
(`testGoldenB_BuildMuscleTwelveMonthsProducesRealStrategicVariety`):

| Phase # | Start | End | Duration | PhaseType | Strategic Purpose | Adaptation Objective | TrainingMix Role | Reason Authority |
|---|---|---|---|---|---|---|---|---|
| 1 | 2026-01-05 | 2026-03-29 | 11wk | muscleGain | Primary-goal development | muscleGain | Focused Hypertrophy / Strength Plus Variety | TrainingOS Strategic Policy |
| 2 | 2026-03-29 | 2026-06-21 | 12wk | muscleGain | Primary-goal development | muscleGain | Focused Hypertrophy / Strength Plus Variety | TrainingOS Strategic Policy |
| 3 | 2026-06-21 | 2026-07-19 | 4wk | maintenance | Recovery/down-regulation | (preserves preceding mix, reduced dose) | Maintenance | TrainingOS Strategic Policy |
| 4 | 2026-07-19 | 2026-10-11 | 12wk | muscleGain | Primary-goal development (cycle repeats) | muscleGain | Focused Hypertrophy / Strength Plus Variety | TrainingOS Strategic Policy |
| 5 | 2026-10-11 | 2027-01-04 | 12wk | muscleGain | Primary-goal development | muscleGain | Focused Hypertrophy / Strength Plus Variety | TrainingOS Strategic Policy |

No Strength phase invented for symmetry (confirmed: `.strength` never
appears). Recovery is real and reasoned (`recoveryPhaseInserted`), not a
counter artifact. Hypertrophy remains sole canonical content throughout.

## 18. Golden Scenario C — Build Muscle + 5K

Real dated objective (`.runningEvent`, 2026-04-13, ~14 weeks out from
2026-01-05), `GoalType.muscleGain`
(`testGoldenC_BuildMusclePlusFiveKObjectiveReconciliation`):

```
Phase 1: Transition        2026-02-02 -> 2026-02-16 (2wk)
Phase 2: Endurance Event    2026-02-16 -> 2026-04-13 (7wk, ends exactly on race date)
Phase 3: Muscle Gain        2026-04-13 -> 2026-07-06 (12wk)
Phase 4: Muscle Gain        2026-07-06 -> 2026-09-28 (12wk)
Phase 5: Maintenance        2026-09-28 -> 2026-10-26 (4wk, recoveryPhaseInserted)
Phase 6: Muscle Gain        2026-10-26 -> 2027-01-04 (9wk)
```

Base Build Muscle strategy runs before the objective is even reachable (no
fill phase before Transition here because the 7-week Running lead time —
`.comfortably10K` tier — combined with the 2-week transition consumes the
entire gap from `asOf`); a real `.transition` phase precedes the event;
the event phase ends exactly on the real race date; the plan then resumes
Build Muscle development, including its own real recovery phase, entirely
unchanged from Golden B's own cycle. `Goal.primaryType` confirmed
`.muscleGain` throughout — never mutated. Running's own capability (2/week,
13 relative weeks/25 workouts) is untouched — this test operates purely at
the strategic-phase level, never touching Running's own source generator.

## 19. Golden Scenario D — Get Stronger + Objective

Real dated objective (`.runningEvent`, 2026-05-04, `.occasionalShorterDistances`
tier = 12wk lead), `GoalType.generalStrength`
(`testGoldenD_GetStrongerPlusTemporaryObjective`), **revised by the
Completion Pass — Phases 4/5's duration corrected from 8wk to 5wk,
shifting Phases 6/7 earlier and extending Phase 7 (less truncation, since
the shorter Strength phases leave more of the horizon remaining)**:

```
Phase 1: Transition       2026-01-26 -> 2026-02-09 (2wk)
Phase 2: Endurance Event  2026-02-09 -> 2026-05-04 (11wk, ends on the real objective date)
Phase 3: Muscle Gain      2026-05-04 -> 2026-07-27 (12wk, developmentPhaseSupportsPrimaryGoal)
Phase 4: Strength         2026-07-27 -> 2026-08-31 (5wk — corrected, was 8wk)
Phase 5: Strength         2026-08-31 -> 2026-10-05 (5wk — corrected, was 8wk)
Phase 6: Maintenance      2026-10-05 -> 2026-11-02 (4wk, recoveryPhaseInserted)
Phase 7: Muscle Gain      2026-11-02 -> 2027-01-04 (9wk — less truncated than before, since Phases 4/5 now consume 6 fewer weeks of the horizon)
```

Primary strength Goal (`.generalStrength`) persists throughout — confirmed
never mutated. After the temporary Running objective, the plan resumes
EXACTLY the Get Stronger cycle from its own first position (Development),
never restarting some different/generic sequence — a genuine, verified
"return to appropriate strength development." The LTP-DURATION-1 fix
applies uniformly through the dated-objective reconciliation path too —
Phases 4/5 (Direct Strength, post-objective) are correctly capped to 5
weeks exactly like Golden A's own Strength phases, confirming
`fillForwardPhases`'s corrected duration computation is shared, not
duplicated, across the forward-only and reconciled-phases call sites.

## 20. Horizon Boundary

`testGoldenE_HorizonBoundaryTruncatesCleanlyNoInventedWeeks`: a ~10-week
horizon (shorter than the Development phase's own 12-week typical
duration) produces exactly ONE phase, clipped precisely to the target
date (`2026-03-16`, matching `goal.targetDate` exactly) — confirmed no
phase extends past the target date, and the single phase absorbs the
remainder cleanly (the pre-existing "absorb the sub-week remainder into
the last phase" fix, confirmed still working correctly with the new
policy).

## 21. Repeated Cycle

`testGoldenG_RepeatedCycleStaysCoherentAfterFirstRecovery`: a ~2-year
horizon produces 13 phases spanning 3+ full Get Stronger cycles (Recovery
occurs at phases 4, 8, and 12). Confirmed: the phase immediately following
EVERY recovery phase restarts at Development (`.muscleGain` with
`developmentPhaseSupportsPrimaryGoal`) — the exact same coherent 4-position
cycle repeats indefinitely, never degrading into the old mechanical
2-type loop.

## 22. Source Mesocycle Lifecycle Dogfood

`testDogfood_GetStrongerCrossesRealFamilyDMesocycleEndAndStrategicPhaseBoundary`
— a full production trace, real Family D/E, real materialization, real
logged results (not faked):

1. Real accepted plan for `GoalType.generalStrength`; first phase
   confirmed `.muscleGain` (Development); the first `.strength`-typed
   phase (Direct Strength) is located and started via the real
   `StartPhaseUseCase.start` → real calibration completion
   (`CalibrationTestSupport`).
2. Confirmed: real `ProgramDefinition.lengthWeeks == 5`; family is `.d` or
   `.e` (General Strength content, never plain Powerlifting).
3. All 5 real tactical weeks materialized via real
   `RollTacticalWindowUseCase.rollForward` calls (one per real 7-day
   step); every real session in every week is actually completed through
   the real production result/completion path
   (`RecordSetResultUseCase.recordSet` → `CompleteBlockUseCase.complete`
   → `CompleteSessionUseCase.complete`) — not merely materialized.
4. Confirmed: the `ProgramDefinition.id` never changes across all 5 weeks
   (no source week duplicated/fabricated, no silent restart); still
   exactly 5 `orderedWeeks` throughout.
5. Confirmed: `TacticalWeekCompletion.isInstanceExhausted` and
   `TrainingPhaseCompletion.isPhaseTerminal` both become genuinely `true`
   — real tactical exhaustion, never a fabricated date-based guess.
6. The NEXT strategic phase (the cycle's second Direct Strength block)
   is located, confirmed `.strength`-typed, and its own real recommended
   mix confirmed to carry `strengthContentSelector: .sourceBackedGeneralStrength`
   — the correct TrainingMix recommendation for what comes next.
7. A real `TransitionPhaseUseCase.transition` call completes: the outgoing
   phase is marked `.completed` (never deleted), its `ProgramInstance`
   likewise `.completed` and its `ProgramDefinition.id` **unchanged**
   (historical instance never mutated — requirement 15), the new phase is
   `.active` with a brand-NEW `ProgramInstance` (confirmed a different
   `id` from the outgoing one — never a same-instance stretch).

No STOP condition was triggered — the existing, already-proven
`StartPhaseUseCase`/`TransitionPhaseUseCase` machinery handled the entire
lifecycle without any new orchestration mechanic.

## 23. Plan Presentation

Not modified (per instruction). `ProposedPhase.reasonCodes` already
carries everything Plan would need to honestly explain "why this phase" —
this checkpoint makes those reason codes real and meaningful (previously
every non-primary phase carried only `.phaseSelectedForGoal`, now
distinguishing `developmentPhaseSupportsPrimaryGoal`/`recoveryPhaseInserted`/
`transitionPhaseInserted`/`muscleRetentionPriority` per real strategic
purpose). No future phase's exact TrainingMix/program is fabricated ahead
of resolution — `ProposedPhase` still carries only type/duration/reason,
never a materialized program, exactly as before.

## 24. Product Intelligence Disclosure

- Direct-strength phase → Family D/E: **SOURCE-BACKED RULE** (content
  fidelity) + **TRAININGOS STRATEGIC POLICY** (why this phase occurs now).
- Development phase → Hypertrophy engine: **TRAININGOS STRATEGIC POLICY**
  (a deliberate, disclosed product decision — hypertrophy-oriented volume
  supporting a strength goal — never attributed to any source).
- Recovery phase → `.maintenance` + reduced-dose policy: **TRAININGOS
  STRATEGIC POLICY** (phase-type/reason choice) + the underlying
  `maintenanceMix` dose-reduction itself remains its own pre-existing,
  already-disclosed **TRAININGOS-DESIGNED** policy (not sourced from any
  reference, confirmed by that function's own doc comment).
- Dated-objective phase timing/lead-time: **SOURCE-BACKED RULE**
  (Running's own `RunningStartingState.leadTimeWeeks` tiers) /
  **ATHLETE PREFERENCE** (which tier the athlete self-reports) /
  **DATED OBJECTIVE** (the objective's own date drives placement).
- Cycle length/typical durations (8/12/4 weeks etc.): **DETERMINISTIC
  TECHNICAL DEFAULT** (`PhaseDurationDefaults`, explicitly
  TRAININGOS-DESIGNED, never claimed as sourced).
- Strength Program 1 vs. 2 selection (unrelated to this checkpoint, but
  re-confirmed unchanged): still a **DETERMINISTIC TECHNICAL DEFAULT**
  (alphabetical tie-break) — not personalization, not touched here, no
  new UI surfaces it.

No selection or sequencing anywhere in this checkpoint is described, in
code or in this report, as scientifically individualized or AI-driven.

## 25. Tests

`TrainingOSTests/LongTermPlannerIntelligenceCompletionTests.swift` (new,
14 tests, all passing, all against the real production
`proposeStrategicPlan`/`AcceptStrategicPlanUseCase`/`StartPhaseUseCase`/
`RollTacticalWindowUseCase`/`TransitionPhaseUseCase` pipeline):

1. `testGoldenA_...` — Get Stronger no longer produces the old 2-type loop.
2. `testGoldenB_...` — Build Muscle no longer produces the old 2-type loop.
3. Verified inline in Golden A/B/C/D — primary Goal identity never mutates.
4. `testSupportingPhaseCanDifferFromPrimaryGoalType`.
5. `testDirectStrengthPhaseResolvesToStrengthSourceContentFamilyDOrE`.
6. `testBuildMusclePrimaryPhaseResolvesToHypertrophySourceContent`.
7. Verified inline in Golden A/B — recovery/transition occurs for an
   explicit `PlannerReasonCode`, asserted directly.
8. `testSameInputsProduceSameSequenceDeterministically`.
9. `testGoldenF_ShortHorizonDegradesGracefully`.
10. Existing `DatedObjectivesReconciliationTests` (unmodified, all
    passing) + Golden C/D exercise this live.
11. Golden D verifies post-objective planning returns toward the primary
    Goal's own real cycle position.
12. `testExactSelectedTrainingMixStaysAuthoritativeUntilAcceptedRevision`.
13. Verified inline in Golden A — no Powerlifting-competition content
    exists to select for a generic Get Stronger phase.
14. `testSourceProgramDurationRemainsUnchangedByThisCheckpoint`.
15. Verified inline in the dogfood test — `ProgramInstance` rollover never
    mutates the historical instance's own `ProgramDefinition.id`/status
    transition.

Plus Golden E (`testGoldenE_...`), Golden G (`testGoldenG_...`), and the
full dogfood (`testDogfood_...`).

One EXISTING test file was updated (disclosed, not weakened):
`ProgramInstanceExerciseSlotResolutionTests.swift`'s shared
`makeAcceptedPlan` helper previously assumed a `.generalStrength` goal's
FIRST phase was always `.strength`-typed (true under the old mechanical
loop) — now looks up the first `.strength`-typed phase specifically
(true under the new policy too, just not necessarily at position 0),
preserving every one of its 7 dependent tests' real intent (a genuine
Powerlifting-engine-resolving Direct Strength phase) unchanged.

**Completion Pass (LTP-DURATION-1) additions — 2 new tests, plus 3
existing tests extended with new assertions (disclosed, not weakened)**:

16. `testStrengthPlannedDurationCappedToExecutableCapacityHypertrophyNotCapped`
    (new) — requirement A/C: `executablePlanningDuration(for: .strength)`
    returns `.fixed(weeks: 5)`; `.muscleGain` and every other phase type
    return `nil` (uncapped).
17. `testGetStrongerCycleShapeUnchangedByTheDurationFix` (new) —
    requirement D: the cycle's own TYPE sequence
    (`[.muscleGain, .strength, .strength, .maintenance]`) and reason codes
    are unchanged by this fix.
18. `testGoldenA_...` extended (requirement E) — now asserts every
    `.strength`-typed phase is exactly
    `PowerliftingProgramGenerator.mesocycleLengthWeeks` (5) weeks, and
    every `.muscleGain`-typed phase stays at or under its existing 12-week
    estimate (never capped).
19. `testDogfood_...` extended (requirement B) — now asserts
    `strengthPhase.endDate` equals the real date `TacticalWeekCompletion
    .isInstanceExhausted` actually becomes true, AND that the SECOND
    Direct Strength phase (`nextPhase`) is also planned for the corrected
    5-week duration, never just the first occurrence.
20. `testSourceProgramDurationRemainsUnchangedByThisCheckpoint` re-run
    unmodified (requirement G) — `PowerliftingProgramGenerator`/
    `HypertrophyProgramGenerator`'s own real `lengthWeeks` values are
    unchanged; only the literal `5` was given a name, never a different
    value.

Requirement H (no new Strength succession mechanism invented) is a
structural fact, not a test: no new use case analogous to
`StartNextHypertrophyMesocycleUseCase` exists anywhere in this
checkpoint's diff — confirmed via `git diff --stat` (§27).

## 26. Regression

- New test class alone: **16 tests, 0 failures** (14 from the prior pass
  + 2 new this Completion Pass).
- Full suite: **1620 tests, 0 failures** (was 1618/0 immediately before
  this Completion Pass; 1604/0 before the original implementation pass).
  1620 − 1618 = 2, exactly the 2 new tests added this pass — zero other
  test-count drift, zero regressions anywhere else in the suite,
  including `PowerliftingSourceFidelityTests`/`StrengthSourceFidelityTests`
  (Family D/E's own source-fidelity tests, confirmed unmodified and
  passing — requirement G), the full, unmodified
  `MaintenancePlanningContextTests` (18 tests), `DatedObjectivesReconciliationTests`,
  `LongTermPlannerStrategicPlanTests`, `LongTermPlannerRevisionTests`,
  `CrossModalityFunctionalFitnessProgrammingTests`. No test assertion was
  weakened this pass — 3 existing tests were EXTENDED with new, stricter
  assertions (disclosed above), never loosened. (One transient,
  already-known-flaky failure — the same intermittent
  `StrategicPhaseTransitionUITests` date/time flakiness diagnosed in the
  Whole Athlete Journey audit — was observed in a single baseline-confirmation
  run before any change was made and did not reproduce on immediate
  re-run; not a regression from this checkpoint.)

## 27. Closed-System Impact

No Hypertrophy/Strength/Powerlifting/Running/Functional Fitness SOURCE
CONTENT semantics touched (only `PowerliftingProgramGenerator`'s own
`lengthWeeks: 5` literal was given a name — the value itself is
byte-for-byte unchanged, confirmed by `testSourceProgramDurationRemainsUnchangedByThisCheckpoint`
re-passing unmodified). No `ConcurrentScheduler` rule touched. No Training
Environment, R0, Running threshold calibration/execution (the just-closed
prior checkpoint), Today execution architecture, Progress, Exercise
Library, or RM calibration semantics touched. `phaseType(for goalType:)`,
`candidateMixTemplates`, `proposeReconciledPhases`,
`proposeMilestoneAnchoredPhases`, `StartPhaseUseCase`,
`TransitionPhaseUseCase`, `RollTacticalWindowUseCase`,
`StartNextHypertrophyMesocycleUseCase`, `HypertrophyProgramJourney` all
have zero diff lines. This Completion Pass's own diff — confirmed via
`git diff --stat` — touches exactly: `LongTermPlanner.swift` (2-line
wiring change), `PowerliftingProgramGenerator.swift` (named-constant
extraction, no value change), `StrategicPeriodizationPolicy.swift` (one
new pure function), `LongTermPlannerIntelligenceCompletionTests.swift`
(2 new tests + 3 extended assertions), and `project.pbxproj`
(pre-existing file registration, unchanged this pass). No new use case
was created — requirement H confirmed structurally, not just asserted.

## 28. Deferred Items

- Lose Fat / Functional Fitness's own distinct development/intensification
  sub-role — disclosed limitation (§8/§9), not invented without a real
  content/domain basis. FOLLOW-UP if a future checkpoint recovers/builds
  content that would make one meaningful.
- A small rolling-horizon behavior for no-target-date athletes (§15) —
  explicitly out of scope, not pursued, per instruction.
- `.recovery` (as a distinct PhaseType, separate from `.maintenance`'s
  reduced-dose policy) remains available, untouched, for a future
  checkpoint wanting a genuinely different down-regulation policy.
- **A within-phase Strength succession mechanism** (analogous to
  `StartNextHypertrophyMesocycleUseCase`, but for Powerlifting-engine
  content) — deliberately NOT built this pass, per explicit instruction.
  If a future product decision wants a single strategic Strength phase to
  legitimately span more than one 5-week Family D/E mesocycle, this is the
  separate, scoped future capability that would enable it; until then, a
  Direct Strength phase's honest executable capacity is exactly 5 weeks,
  and the strategic cycle already provides variety via a SECOND, separate
  Direct Strength phase (a real phase-to-phase transition) rather than one
  artificially-long phase.
- Everything already deferred by prior checkpoints (Powerlifting
  preference/competition, Running V2, FF V2, advanced readiness, etc.) —
  unchanged, not re-litigated here.

## 29. Final Verdict

**This verdict block is superseded by the Completion Pass verdict
immediately below**, per the user's own "COMPLETION PASS" directive
(LTP-DURATION-1). The original 26-line verdict above this line is kept
for historical record of the first implementation pass's own
self-assessment; the Completion Pass's verdict is the one that governs
whether this checkpoint is ready for commit.

STRATEGIC POLICY EXPLICIT: PASS
POLICY AUTHORITY HONESTLY CLASSIFIED: PASS
GET STRONGER LONG-TERM STRATEGY: PASS
BUILD MUSCLE LONG-TERM STRATEGY: PASS
LOSE FAT POLICY: PASS (with disclosed limitation, §8)
FUNCTIONAL FITNESS POLICY: PASS (with disclosed limitation, §9)
PRIMARY GOAL IDENTITY PRESERVED: PASS
SUPPORTING PHASE EMPHASIS WORKS: PASS
RECOVERY/TRANSITION HAS STRATEGIC REASON: PASS
PHASE DURATION COHERENT: PASS (superseded — see Completion Pass verdict: this was NOT actually coherent, see §12A)
SOURCE MESOCYCLE LENGTH PRESERVED: PASS
STRATEGIC PHASE / PROGRAM LIFECYCLE: PASS
GENERAL STRENGTH STILL RESOLVES TO D/E: PASS
BUILD MUSCLE STILL RESOLVES TO H SOURCE: PASS
DATED OBJECTIVE PATH PRESERVED: PASS
POST-OBJECTIVE RETURN TO PRIMARY GOAL: PASS
EXACT SELECTED TRAINING MIX PRESERVED: PASS
SHORT-HORIZON BEHAVIOR: PASS
REPEATED-CYCLE BEHAVIOR: PASS
PLAN CAN EXPLAIN WHY: PASS
DETERMINISTIC: PASS
J9 LONG-TERM STRENGTH: PASS
FULL SUITE: PASS
NEW FAILURES: 0
LTP-1: CLOSED
LONG-TERM PLANNER INTELLIGENCE: PASS

## 30. Completion Pass Final Verdict (LTP-DURATION-1)

STRATEGIC POLICY EXPLICIT: PASS
GET STRONGER POLICY PRESERVED: PASS
BUILD MUSCLE POLICY PRESERVED: PASS
PLANNED PHASE DURATION EXECUTABLE: PASS
STRENGTH D/E LENGTH PRESERVED: PASS
NO STRENGTH SUCCESSION INVENTED: PASS
HYPERTROPHY LONGER PHASE CAPABILITY PRESERVED: PASS
PLANNED END MATCHES REAL STRENGTH PHASE TERMINAL: PASS
DATED OBJECTIVE PATH PRESERVED: PASS
YEAR OVERVIEW STRATEGICALLY HONEST: PASS
J9 LONG-TERM STRENGTH: PASS
FULL SUITE: PASS
NEW FAILURES: 0
LTP-DURATION-1: CLOSED
LTP-1: CLOSED
READY FOR COMMIT: YES
READY FOR VERTICAL PRODUCT HARDENING: YES

## 31. Final Pre-Commit Semantic Check — Is `.strength -> 5 weeks` a True Invariant?

> **SUPERSEDED — see §32.** This section's own conclusion (documentation +
> a tripwire test, leaving the "5wk default-candidate estimate, safe when
> wrong" cap in place unconditionally) was independently reviewed and
> REJECTED as insufficient: `PLAN = DIRECTION` — a strategic date
> TrainingOS already knows is wrong at planning time is knowingly incorrect
> product information, regardless of whether it also happens to be safe
> against a forced-early-transition failure mode. The trace table and
> "CURRENT .strength EXECUTABLE PATHS" analysis immediately below remain
> accurate and are the evidentiary basis §32's substantive fix is built on
> — only the two verdict lines "PHASETYPE → 5 WEEK OVERRIDE IS CURRENTLY
> SOUND" and "CODE CHANGE REQUIRED" (and the Final Verdict block at this
> section's own end) are superseded by §32's.

**Question**: does `StrategicPeriodizationPolicy.executablePlanningDuration`'s
`.strength -> .fixed(weeks: 5)` cap hold for EVERY current production path
that can produce a `TrainingPhase` with `type == .strength`, or only for the
canonical Get Stronger / `strengthFocusedMix()` path Golden Scenario A
exercises?

**Answer, proven by direct trace, not assumed: it is NOT a universal
invariant.** `candidateMixTemplates(phase: goal:)`'s `.strength` case
(`LongTermPlanner.swift:1283-1306`, re-read directly, unchanged by any
checkpoint this session) returns **two** real candidates:

```swift
case .strength:
    return [
        (strengthFocusedMix(), [.phaseSelectedForGoal]),   // .powerlifting -> Family D/E, 5wk, no succession
        (muscleGainVariedMix(), [.phaseSelectedForGoal]),   // .hypertrophy primary component, real succession
    ]
```

`muscleGainVariedMix()`'s primary component (`LongTermPlanner.swift:1518-1536`)
is `programmingSystem: .hypertrophy` — the SAME engine already confirmed
(§12) to have a real, proven, within-strategic-phase succession mechanism
(`StartNextHypertrophyMesocycleUseCase`). `rankCandidateMixes`'s existing,
unmodified §5b bounded-promotion logic (`LongTermPlanner.swift:1101-1190`,
re-read directly) can genuinely promote `muscleGainVariedMix()` to
`.recommended` for a real athlete preference input aligned with it (e.g. a
stated Hypertrophy/Functional-Fitness/Running preference within the
existing tier-gap bound) — this is a real, reachable production path, not a
hypothetical.

### CURRENT .strength EXECUTABLE PATHS

| Path | Mix selection | Athlete-selected mix authoritative? | ProgrammingSystemKind | ProgramDefinition family | lengthWeeks | Within-phase succession? | Tactical exhaustion = phase terminal? | Executable capacity always 5wk? |
|---|---|---|---|---|---|---|---|---|
| Canonical Get Stronger recommendation (no preference) | `rankCandidateMixes` picks `strengthFocusedMix()` as `.bestGoalAlignment`/`.recommended` (nothing promotes the alternate) | Yes — becomes `.selected` on acceptance | `.powerlifting` | Family D or E | 5 | No | Yes | **Yes** |
| Get Stronger + athlete preference aligned with Hypertrophy/FF/Running | `rankCandidateMixes` §5b promotes `muscleGainVariedMix()` to `.recommended` | Yes — becomes `.selected` on acceptance | `.hypertrophy` (primary component) | Hypertrophy (`.basicHypertrophy` etc.) | 5 per mesocycle | **Yes** (`StartNextHypertrophyMesocycleUseCase`) | No (until succession exhausted) | **No** |
| Build My Own Mix, athlete builds a custom composition, then the mix is attached to an existing `.strength`-typed phase | `buildCustomMix` — fully athlete-driven, no validation anywhere ties `TrainingMixComponent`/`TrainingMix` content to `TrainingPhase.type` (confirmed: `grep` for `phase.type ==` across every use case finds no such check; `TrainingPhase.type` and its mix are architecturally independent, per the Product Model Alignment checkpoint) | Yes, definitionally (it's the athlete's own explicit choice) | Whatever the athlete builds — any engine, including none of Family D/E at all | Whatever that engine's own generator produces | Varies | Varies | Varies | **No — arbitrary** |
| Strategic re-proposal / accepted selected mix on an existing phase | `phase.selectedTrainingMix ?? phase.recommendedTrainingMix` (`TrainingPhase.swift:130`) — reads whichever is actually set; re-proposing the strategic plan never touches an already-`.selected` mix (confirmed §13, unchanged) | Yes | Whatever was previously selected | Whatever was previously selected | Whatever was previously selected | Whatever was previously selected | Whatever was previously selected | Depends entirely on what was selected |
| Dated-objective return into a `.strength`-typed phase (Golden D) | Goes through the exact same `candidateMixTemplates(.strength)` resolution as the canonical path — no separate resolution logic exists for a post-objective return (confirmed: `proposeReconciledPhases`/`proposeMilestoneAnchoredPhases` build `ProposedPhase` values only; actual mix resolution always happens later, at `proposeTrainingMix`/phase-start time, identically regardless of how the phase came to exist) | Yes | Same 2-candidate set as canonical | Same as canonical path | Same as canonical path | Same as canonical path | Same as canonical path | Same ambiguity as the canonical path |
| Any other current caller producing `PhaseType.strength` | None found — `grep -rn "\.strength" TrainingOS/Application/UseCases/*.swift` (excl. Tests) shows only `phaseType(for goalType:)`'s `.generalStrength -> .strength` mapping and `StrategicPeriodizationPolicy.cycle(for:)`'s own cases; no other production caller constructs a `.strength`-typed `TrainingPhase` | — | — | — | — | — | — | — |

### ATHLETE-SELECTED MIX CAN CHANGE EXECUTABLE DURATION: YES

Confirmed directly: `TrainingPhase.type` and its `TrainingMix` content are
fully decoupled architecturally (no validation anywhere ties them), and
`rankCandidateMixes`'s own real, unmodified promotion logic can make the
Hypertrophy-engine alternative the actual recommended-and-then-selected mix
for a `.strength`-typed phase for a real, non-contrived preference input.

### PHASETYPE → 5 WEEK OVERRIDE IS CURRENTLY SOUND: YES, WITH A DISCLOSED, PROVEN-SAFE SCOPE LIMITATION

The cap is **not** a universal semantic claim — it is, and is now explicitly
documented as, the executable capacity of the **default, no-preference,
first-listed candidate** (`strengthFocusedMix()`, which is also what
`rankCandidateMixes` picks absent any promoting preference — the common
case). For the real, proven minority path where the alternate candidate is
what actually resolves, the estimate is honestly disclosed as capable of
being an **underestimate**, never an overestimate, and never a source of
incorrect behavior: a new, dedicated safety test
(`testAlternateHypertrophyCandidateForStrengthPhaseNeverIncorrectlyForceTerminatedByThePlannedEstimate`)
proves directly that when the Hypertrophy-engine alternative is what
actually gets started or the athlete's actually-selected mix for the
`.strength`-typed phase, `TrainingPhaseCompletion.isPhaseTerminal` correctly
stays `false` past the planned 5-week estimate — real succession
(`hasNextHypertrophyMesocycle`) is what governs actual completion, exactly
as it already does everywhere else in this codebase; the estimate being
short for this path never causes an incorrect early phase transition, lost
data, or fabricated content. This is why the existing cap can be
**retained unchanged** rather than removed or made conditional: removing it
would reintroduce the ORIGINAL LTP-DURATION-1 bug for the (dominant) default
case to guard against a (real but non-default, and safety-provably-inert)
minority case.

A fully substantive fix — deriving the planning-time estimate from the
athlete's actual predicted resolution rather than the default candidate —
was considered and explicitly NOT built this pass: it would require
threading goal/preference-aware ranking logic into `fillForwardPhases`
(which has no `Goal`/`GoalPreferences` in scope today, by design — future
phases are never resolved ahead of their own start, per the established
"strategic plan vs. tactical materialization" separation). This is a real,
disclosed FOLLOW-UP, not swept under the rug.

### FUTURE-CAPABILITY REGRESSION TEST PRESENT: YES

`testStrengthPhaseCandidateSetKnownEngineProfilesFutureCapabilityTripwire`
asserts `candidateMixTemplates(.strength)` returns exactly 2 candidates
today, and asserts each one's known engine/content profile
(`strengthFocusedMix()` → `.powerlifting` + `.sourceBackedGeneralStrength`;
`muscleGainVariedMix()` → `.hypertrophy`). If a future checkpoint adds a
third `.strength` candidate, or changes either existing one's profile, this
test breaks immediately and forces a human to re-examine whether the
duration policy (and this section's own trace table) still holds.

### CODE CHANGE REQUIRED: YES (narrow — documentation + 2 new tests, no behavior change to the cap itself)

- `StrategicPeriodizationPolicy.executablePlanningDuration`'s doc comment
  extended to precisely scope the `.strength` claim (default-candidate
  estimate, not a universal guarantee) and point to the two new tests as
  evidence.
- `LongTermPlannerIntelligenceCompletionTests.swift`: 2 new tests —
  `testStrengthPhaseCandidateSetKnownEngineProfilesFutureCapabilityTripwire`
  (future-capability tripwire) and
  `testAlternateHypertrophyCandidateForStrengthPhaseNeverIncorrectlyForceTerminatedByThePlannedEstimate`
  (safety proof for the non-default path).
- **No change** to `executablePlanningDuration`'s actual returned value,
  `StrategicPeriodizationPolicy.cycle(for:)`, `fillForwardPhases`, or any
  source content/engine — confirmed via `git diff` (only the doc comment
  and the test file changed).

### FULL SUITE

1622 tests, 0 failures (was 1620/0 before this pass — exactly the 2 new
tests added, zero regressions). Independently confirmed via
`xcodebuild test-without-building -parallel-testing-enabled NO`.

### Final Verdict (Final Pre-Commit Semantic Check)

STRATEGIC POLICY EXPLICIT: PASS
GET STRONGER POLICY PRESERVED: PASS
BUILD MUSCLE POLICY PRESERVED: PASS
PLANNED PHASE DURATION EXECUTABLE: PASS
STRENGTH D/E LENGTH PRESERVED: PASS
NO STRENGTH SUCCESSION INVENTED: PASS
HYPERTROPHY LONGER PHASE CAPABILITY PRESERVED: PASS
PLANNED END MATCHES REAL STRENGTH PHASE TERMINAL: PASS
DATED OBJECTIVE PATH PRESERVED: PASS
YEAR OVERVIEW STRATEGICALLY HONEST: PASS
J9 LONG-TERM STRENGTH: PASS
FULL SUITE: PASS
NEW FAILURES: 0
LTP-DURATION-1: CLOSED
LTP-1: CLOSED
READY FOR COMMIT: YES

> **Superseded — see §32's own Final Verdict, which is authoritative.**

## 32. DURATION RESOLUTION AFTER TRAINING MIX SELECTION (Final Duration Fix)

### Why PhaseType-only duration was rejected

§31 proved `PhaseType.strength` does not imply one universal executable
lifecycle — `candidateMixTemplates(.strength)` genuinely returns two
different-lifecycle candidates, and a real (if non-default) athlete
preference input can make the Hypertrophy-engine one the actual
recommended/selected mix. The previous resolution (leave the unconditional
5-week cap in place, proven merely "safe to be wrong" via
`TrainingPhaseCompletion.isPhaseTerminal`'s date-independence) was
independently rejected: **Plan = Direction** — the athlete-facing planned
date is real product information, and TrainingOS already has enough
information, at planning time, to get it right for this real path, not
merely to avoid it causing a downstream safety defect. Leaving a known-
incorrect estimate in place because a *different* mechanism happens to
never act on it is not the same as the estimate being correct.

### Where duration is now actually resolved

A new type, **`ExecutablePhaseDurationResolver`**
(`TrainingOS/Application/UseCases/ExecutablePhaseDurationResolver.swift`),
is now the ONLY place in the entire strategic-planning stack that knows
about a concrete program engine's real executable mesocycle length:

```swift
enum ExecutablePhaseDurationResolver {
    static func executablePlanningDuration(for mix: TrainingMix) -> PhaseDurationKind? {
        guard let primary = mix.orderedComponents.first(where: { $0.priority == .primary }) else { return nil }
        guard primary.programmingSystem == .powerlifting,
              primary.strengthContentSelector == .sourceBackedGeneralStrength
        else { return nil }
        return .fixed(weeks: PowerliftingProgramGenerator.mesocycleLengthWeeks)
    }
}
```

It takes a whole `TrainingMix` (never a `PhaseType`), inspects only its
PRIMARY component, and returns a stricter bound only when it recognizes a
known single-mesocycle, no-succession engine/selector combination (today:
exactly Family D/E). Everything else — including a `.hypertrophy`-primary
mix, regardless of which `PhaseType` it's attached to — returns `nil`
(use the existing `PhaseDurationDefaults` estimate unchanged).

**`StrategicPeriodizationPolicy.executablePlanningDuration(for: PhaseType)`
was REMOVED entirely** — the policy type now has zero knowledge of any
concrete engine (`PowerliftingProgramGenerator`/`HypertrophyProgramGenerator`/
`StrengthSourceContentLibrary`/`ExecutablePhaseDurationResolver` itself),
confirmed both by direct code review and by a new regression test
(`testStrategicPeriodizationPolicyHasNoConcreteProgramEngineDependency`)
that scans the file's own CODE (doc comments are deliberately excluded —
they legitimately name these types in prose to explain the separation)
and fails if any of them is ever referenced there again.

**`fillForwardPhases`** (`LongTermPlanner.swift`) now takes a `goal: Goal`
parameter (threaded through its 3 real callers —
`proposeForwardOnlyPhases`, `proposeMilestoneAnchoredPhases`,
`proposeReconciledPhases` — and their own 2 callers, `proposeStrategicPlan`
and `reviseByChangingMilestoneDate`, both of which already had a real
`Goal` in scope). For each phase intent `StrategicPeriodizationPolicy`
produces, IF `intent.type == .strength` (the only type the resolver can
currently return a stricter bound for — checked explicitly, not merely as
an optimization, see the next paragraph), it constructs a pure,
never-persisted `TrainingPhase` preview value, calls the real
`LongTermPlanner.proposeTrainingMix(phase:goal:)` (the exact same function
the real athlete-facing recommendation flow uses) to find the
ACTUAL-would-be-recommended mix, and passes that mix to
`ExecutablePhaseDurationResolver`. Every other phase type skips this
preview step entirely and uses `PhaseDurationDefaults.range(for:)`
unchanged, exactly as before this fix.

**A real bug found and fixed during implementation, worth disclosing
precisely**: the first version of this change called `proposeTrainingMix`
for EVERY phase type unconditionally. This hung the test runner
indefinitely. Root cause, confirmed by direct investigation:
`candidateMixTemplates`'s `.maintenance`/`.recovery`/`.transition` cases
route through `planningContext(for:)`, which reads `phase.plan` — a
SwiftData relationship property that cannot be safely faulted on a
`TrainingPhase` instance that was never inserted into any `ModelContext`
(the preview phase, by design, never is — see below). Restricting the
preview step to exactly `.strength` (the only type this checkpoint's
resolver has a rule for) sidesteps this entirely, since `.strength`'s own
`candidateMixTemplates` case never touches `phase.plan` at all — confirmed
empirically (the hang reproduced with the unconditional version and
disappeared once scoped) and architecturally (there is no reason to
preview a mix for a phase type the resolver will unconditionally return
`nil` for anyway). This is a genuine constraint on the implementation, not
merely an optimization — documented directly in `fillForwardPhases`'s own
code comment.

The preview `TrainingPhase` itself remains pure and is never inserted into
any `ModelContext` and never persisted — it exists solely to ask
`proposeTrainingMix` "what would be recommended here," exactly mirroring
how the real athlete-facing recommendation flow already works for an
actually-accepted phase.

### The canonical D/E case

Golden Scenario A (Get Stronger, no preference), re-run through the new
path: **identical output** to the previous (accepted) pass — Direct
Strength phases still plan for exactly 5 weeks, because
`strengthFocusedMix()` is still what `rankCandidateMixes` recommends with
no promoting preference, and `ExecutablePhaseDurationResolver` still caps
it. Nothing regressed for the default/common case.

### The alternate Hypertrophy case (the key scenario the previous pass could not produce)

**Golden Alternate** (new,
`testGoldenAlternate_PreferencePromotedHypertrophyCandidateForStrengthPhaseIsNotCappedTo5Weeks`):
`GoalType.generalStrength` with `GoalPreferences(preferredModalities:
[.functionalFitness, .steadyState])` — a real preference input that
genuinely promotes `muscleGainVariedMix()` to `.recommended` for the
`.strength`-typed phase (confirmed inline in the test, not assumed). Real
production trace, phase table printed:

```
Phase 1 | 2026-01-05 -> 2026-03-29 | ~11wk | muscleGain | developmentPhaseSupportsPrimaryGoal
Phase 2 | 2026-03-29 -> 2026-05-24 | ~8wk  | strength   | phaseSelectedForGoal
Phase 3 | 2026-05-24 -> 2026-07-19 | ~8wk  | strength   | phaseSelectedForGoal
Phase 4 | 2026-07-19 -> 2026-08-16 | ~4wk  | maintenance| recoveryPhaseInserted
Phase 5 | 2026-08-16 -> 2026-11-09 | ~12wk | muscleGain | developmentPhaseSupportsPrimaryGoal
Phase 6 | 2026-11-09 -> 2027-01-04 | ~8wk  | strength   | phaseSelectedForGoal

PhaseType: strength | recommended: Strength Plus Variety | engine: hypertrophy | planned: 8wk | reason: ["phaseSelectedForGoal"]
```

The identical `PhaseType.strength` now correctly plans for **8 weeks**
(the ordinary, uncapped `.strength` `PhaseDurationDefaults` estimate) —
not 5 — because its ACTUAL recommended content is the Hypertrophy-engine
alternate, which has real succession available to legitimately sustain
that duration. This is requirement C proven directly: same `PhaseType`,
different resolved mix, different (both now CORRECT) planned duration.
`Goal.primaryType` confirmed unchanged (`.generalStrength`) throughout.

### The selected-mix case — the exact current product contract, investigated directly

For an already-`.active` phase whose mix has already been explicitly
`.selected` (whether the athlete accepted the recommendation or built a
custom one via Build My Own Mix): `TrainingPhase.endDate` is set ONCE, at
strategic-plan proposal/acceptance time, as a forward-looking estimate.
**There is no existing mechanism that revises `TrainingPhase.endDate`
after the fact if the athlete's actual selection differs from what was
assumed at proposal time** — confirmed directly: `AcceptScheduleProposalUseCase`/
`AcceptStrategicPlanUseCase` (re-read in full) attach the selected mix and
materialize sessions; neither touches `TrainingPhase.endDate`. This is the
existing, disclosed, unchanged product contract (not something this
checkpoint invents or alters) — the REAL transition trigger has never been
`endDate` at all, it is `TrainingPhaseCompletion.isPhaseTerminal` (tactical
exhaustion + no further succession), which reads live materialized state,
never the planned estimate. This checkpoint's fix improves the QUALITY of
the up-front ESTIMATE (by consulting the actual recommended mix instead of
guessing from `PhaseType` alone) — it does not, and was not asked to,
build a new "revise endDate after selection" mechanism, which would be a
distinct, larger, out-of-scope feature (a plan-revision capability, already
covered by the existing `PlanRevisionRequest.extendPhase`/`.shortenPhase`
athlete-initiated flow when an athlete wants to explicitly resize a
phase).

### The dated-objective return case

Golden C and Golden D (re-run, unaffected in shape): `proposeReconciledPhases`/
`proposeMilestoneAnchoredPhases` are completely unmodified except for
threading the new `goal:` parameter through to their own `fillForwardPhases`
calls — since a real `Goal` was always in scope at both call sites, this
is a mechanical, behavior-preserving change. Golden D's own Development/
Strength phases (post-objective return) show the same corrected, mix-aware
durations (Development ~12wk, Direct Strength 5wk each, matching the
canonical no-preference case, since Golden D states no special
Hypertrophy/FF/Running preference either).

### Architectural separation achieved

`StrategicPeriodizationPolicy` → decides WHAT `PhaseType` and WHY (zero
engine knowledge, confirmed by a regression-guarded code scan).
`ExecutablePhaseDurationResolver` → decides HOW LONG, given the ACTUAL
resolved `TrainingMix` (zero phase-sequencing knowledge — it is a pure
function of one `TrainingMix` value, nothing else). `fillForwardPhases` →
orchestrates the horizon (how many phases fit, where their dates fall),
calling the other two, never embedding either's own logic.
`LongTermPlanner.proposeTrainingMix` → the one, single, already-existing
recommendation-resolution function, now reused for BOTH the real
athlete-facing recommendation flow AND this preview step — never a second,
parallel resolution mechanism.

### Regression

Baseline confirmed before this pass: **1622 tests, 0 failures** (the prior,
now-superseded §31 pass's own final state). After this pass: **1623 tests,
0 failures** — net +1 (removed the old `PhaseType`-keyed resolver test,
added the new mix-keyed resolver test + the policy-independence regression
test + renamed/repurposed the old "safety-proof" test into the new Golden
Alternate scenario). Targeted run
(`LongTermPlannerIntelligenceCompletionTests`, 19 tests) and full suite
both independently re-confirmed via `xcodebuild test-without-building
-parallel-testing-enabled NO`. Zero regressions anywhere else in the
suite — confirmed via the full run's own unchanged pass count elsewhere.

### Final Verdict (Final Duration Fix — authoritative, supersedes §29/§30/§31's own verdict blocks)

STRATEGIC POLICY INDEPENDENT OF PROGRAM ENGINE: PASS
DURATION DERIVED FROM EXECUTABLE CAPABILITY: PASS
CANONICAL STRENGTH D/E PLANS 5 WEEKS: PASS
ALTERNATE .STRENGTH HYpertrophy PATH NOT CAPPED TO 5: PASS
SAME PHASETYPE CAN SUPPORT DIFFERENT DURATIONS: PASS
ATHLETE-SELECTED MIX PRESERVED: PASS
DATED OBJECTIVE RETURN DURATION CORRECT: PASS
STRENGTH D/E SOURCE LENGTH PRESERVED: PASS
NO STRENGTH SUCCESSION INVENTED: PASS
HYPERTROPHY SUCCESSION PRESERVED: PASS
GET STRONGER YEAR COHERENT: PASS
PLAN DATES COHERENT WITH EXECUTABLE PROGRAMMING: PASS
FULL SUITE: PASS
NEW FAILURES: 0
LTP-DURATION-1: CLOSED
LTP-1: CLOSED
READY FOR COMMIT: YES
