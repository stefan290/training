# TrainingOS Product Model Alignment

Analysis only. No production code, UI, tests, or source workbooks modified.
No commit. No push.

---

## 1. Executive Finding

The intended hierarchy (Goal → Long-Term Plan → Phase → Programming
Emphasis → Training Mix → Program → Execution) is **already substantially
correctly implemented** at the domain-model level. This is not a case of
deep architectural conflation requiring a redesign:

- `GoalType` (outcome: `.muscleGain`, `.fatLoss`, `.generalStrength`,
  `.enduranceEvent`, `.functionalFitness`, `.maintenance`) is already
  distinct from `TrainingStyle` (discipline/preference:
  `.hypertrophy`, `.strengthTraining`, `.functionalFitness`, `.running`,
  `.cycling`) — this separation was **deliberately built** in an earlier
  checkpoint literally named "Goal ≠ Training Method"
  (`LongTermGoalTypes.swift`'s own header comment).
- `PhaseType` mirrors `GoalType` almost 1:1 and carries no modality/engine
  field of its own — a `TrainingPhase` names a strategic purpose
  (`.strength`, `.muscleGain`, …), never a training method.
- `TrainingMix`/`TrainingMixComponent` already sit exactly where the
  intended model puts them: a practical, per-phase weekly composition,
  independently persisted, distinct from both `Goal` and `ProgramDefinition`.
- `ProgramDefinition.lengthWeeks` is already architecturally prevented from
  defining the strategic-plan horizon: `TrainingPlan` holds an ordered list
  of `TrainingPhase`s with their own `startDate`/`endDate`, and exhausting a
  `ProgramDefinition`'s own week count is already treated as requiring a new
  `ProgramInstance` (a phase-transition-shaped event), never a silent
  extension of the strategic plan (confirmed directly in
  `RollTacticalWindowUseCase.rollForward`'s own doc comment).

**However, one real, concrete, athlete-facing semantic bug was found**,
exactly in the place the user's message predicted it would be hiding: the
default **recommended** `TrainingMix` for a `GET STRONGER` goal
(`LongTermPlanner.strengthFocusedMix()`) is named **"Focused Powerlifting"**
and labels its sole component **"Powerlifting"** — even though the athlete
never said they wanted Powerlifting, only that they want to get stronger.
This is a direct, literal instance of "GET STRONGER → POWERLIFTING" leaking
into athlete-facing text, produced by exactly the mechanism the user
anticipated: shared-engine reuse (`ProgrammingSystemKind.powerlifting`) was
allowed to dictate athlete-facing naming. A second, smaller inconsistency
was found alongside it (`defaultAdaptationObjectives` disagreeing with
`strengthFocusedMix` on which `AdaptationObjective` "Strength Training"
means). Both are **narrow, label/data-level fixes** — no entity, engine, or
persisted schema change is required.

No new persisted "Programming Emphasis" type is needed. No new
`TrainingStyle`/`ProgrammingSystemKind` case is needed. The recovered
Strength source programs (`Strength_Program_1/2.xlsx`) belong exactly where
the completed Strength Source Recovery V1 report placed them — as 2 more
`PowerliftingFamily` engine configurations reachable through the existing
`TrainingStyle.strengthTraining` athlete-facing path — this checkpoint
**sharpens, not overturns**, that conclusion: it must ship only *after* the
naming bug above is fixed, so a GET STRONGER athlete who receives this
content sees "Strength Training," never "Powerlifting."

---

## 2. Current Product Model

```
Goal (GoalType: outcome)
  -> TrainingPlan (ordered TrainingPhases, revision lineage)
       -> TrainingPhase (PhaseType: strategic purpose; TrainingPriority: scheduling tiebreak)
            -> TrainingMix (.recommended and/or .selected)
                 -> TrainingMixComponent (label, ProgrammingSystemKind, AdaptationObjective[], frequency)
                      -> ProgramInstance -> ProgramDefinition (ProgrammingSystemKind, per-system configuration)
                           -> TemplateSession / TrainingWeek (source-authored structure)
                                -> Session -> WorkoutBlock -> SetResult/WorkoutResult (performance, separate types)
```

`TrainingStyle` sits outside this vertical chain, as the athlete's
horizontal, standing **preference** input — read by `Goal.preferences`
(`preferredModalities`/`dislikedModalities`, expressed as
`ModalityPreference`, i.e. `ProgrammingSystemKind` + optional
`ActivityType`) and by the explicit "Build My Own Mix" construction path
(`LongTermPlanner.buildCustomMix`). It never appears on `Goal`, `TrainingPlan`,
or `TrainingPhase` directly.

---

## 3. Intended Product Model

Exactly as specified in the user's directive — reproduced here only to
anchor §19-20's evaluation, not repeated in full. The one addition this
audit contributes: the intended model does **not** require a new
"Programming Emphasis" persisted type — see §7.

---

## 4. Goal Semantics

`GoalType` (`TrainingOS/Domain/ValueTypes/Enums.swift:12`):
```swift
enum GoalType: String, Codable, CaseIterable {
    case muscleGain, fatLoss, generalStrength, enduranceEvent, functionalFitness, maintenance
}
```
Every case is a genuine outcome, never a training method:
`.generalStrength` is explicitly NOT `.powerlifting` — no such
`GoalType` case exists, and `.generalStrength` carries no reference to any
`ProgrammingSystemKind`/`TrainingStyle` anywhere in its own definition.
`Goal` (`Domain/Entities/Goal.swift`) additionally carries
`bodyCompositionDirection` (independent of `primaryType` — "a
`.generalStrength` primary objective can still carry a `.loseFat`
direction," per its own doc comment), `datedObjectives: [DatedObjective]`,
and `preferences: GoalPreferences?` (never required — "every planner call
degrades to coarser recommendations, it never fails").

**Alignment: ALIGNED.** `GoalType` already correctly models outcome, not
method. No correction needed.

---

## 5. Long-Term Planning

`TrainingPlan` (`Domain/Entities/TrainingPlan.swift`) is an ordered list of
`TrainingPhase`s with an explicit revision lineage (`supersedes`/
`lineageID`) — a plan is not one program, it is a chain of phases that can
extend indefinitely. `LongTermPlanner.proposeStrategicPlan` /
`reviseStrategicPlan` / `proposeForwardOnlyPhases` /
`proposeMilestoneAnchoredPhases` / `proposeReconciledPhases` (all in
`LongTermPlanner.swift`) already build multi-phase sequences, not single
mesocycles — `fillForwardPhases` explicitly continues proposing phases
beyond whatever the current or next phase's own program duration is.

There is no single type named `StrategicPlanningEngine` in the codebase —
this responsibility lives inside `LongTermPlanner` (the `enum` namespace
itself acts as this engine). This is a **naming mismatch with the user's
own vocabulary, not a functional gap** — classified MISNAMED BUT
FUNCTIONALLY SAFE, no fix required (renaming a 2144-line, heavily-tested,
production `enum` for vocabulary alignment alone is explicitly out of scope
per §16/§21's "smallest correction" instruction).

**Alignment: ALIGNED.**

---

## 6. Phase Semantics

`TrainingPhase` (`Domain/Entities/TrainingPhase.swift`): `type: PhaseType`,
`priorityRule: TrainingPriority`, `startDate`/`endDate`, `programInstances`,
`trainingMixes`. **Critically, `TrainingPhase` has no `ProgrammingSystemKind`
or `TrainingStyle` field of its own** — a phase's modality composition is
entirely owned by its `TrainingMix`, exactly the separation of "phase
objective vs. training modality" CLAUDE.md rule 19a already requires.
`PhaseType` (`Enums.swift:39`) mirrors `GoalType` (`.muscleGain`, `.fatLoss`,
`.strength`, `.enduranceEvent`, `.functionalFitness`, `.recovery`,
`.transition`, `.maintenance`) — every case names a strategic purpose, never
a method.

`endDate` is `Date?` (open-ended is legal); a phase's actual materialized
program(s) may be shorter than the phase itself, and `fillForwardPhases`
already handles proposing subsequent phases once a program's duration is
consumed.

**Alignment: ALIGNED.**

---

## 7. Programming Emphasis

**Does a "Programming Emphasis" concept need to become a new persisted
type?** No — determined directly from what already exists, per the user's
own explicit instruction to check before assuming:

- `TrainingPhase.type` (`PhaseType`) already answers "what strategic
  purpose does this phase serve" (e.g. `.strength`).
- `TrainingPhase.priorityRule` (`TrainingPriority`: `.strength`/
  `.endurance`/`.mixedModal`) already answers "which scheduling tiebreak
  applies" — itself derived from `PhaseType`
  (`LongTermPlanner.priorityRule(for:)`), not asked separately.
- `TrainingMixComponent.adaptationObjectives: [AdaptationObjective]`
  (`muscleGain`, `maxStrength`, `power`, `aerobicCapacity`,
  `anaerobicCapacity`, `workCapacity`, `skillAcquisition`) already answers
  "what adaptation is this specific component actually pursuing" — at
  finer grain than the phase itself, and already independent of which
  `ProgrammingSystemKind` produced it (a Hypertrophy-engine component can
  carry `.muscleGain`; a Powerlifting-engine component can carry
  `.maxStrength`; nothing forces a 1:1 engine-to-objective mapping).

Together, `PhaseType` + `TrainingMixComponent.adaptationObjectives` already
express exactly the concept the user calls "Programming Emphasis": *what
adaptation matters now*, independent of *which discipline delivers it*.
The user's own worked example — "a GET STRONGER plan may temporarily use a
higher-volume/hypertrophy-oriented phase" — is **already directly
representable today**, with zero new code: `candidateMixTemplates(phase:
goal:)`'s `.strength` case already returns `muscleGainVariedMix()` (a
Hypertrophy-engine-primary mix, labeled "Strength") as a real alternative
recommendation for a `.strength`-type phase, specifically because
"Strength" and "Hypertrophy" are already known to be substitutable
emphases toward the same `GET STRONGER` goal — this is not a hypothetical,
it is already-shipped code with its own doc comment explaining exactly this
reasoning (`LongTermPlanner.swift:1251-1274`).

**Conclusion: no new persisted `ProgrammingEmphasis` enum/entity is
needed.** The existing `PhaseType` + `AdaptationObjective` pair already
covers it. **Alignment: ALIGNED** (concept exists implicitly, correctly,
and is reused, not duplicated).

---

## 8. Training Methods / Preferences

`TrainingStyle` (`LongTermGoalTypes.swift:68`): `.hypertrophy`,
`.strengthTraining`, `.functionalFitness`, `.running`, `.cycling` — the
athlete-facing "how do you like to train" vocabulary, deliberately separate
from `GoalType`, per its own doc comment. Two real, independent production
paths read it:

1. **Preference signal** (`Goal.preferences.preferredModalities`/
   `dislikedModalities`, built from `TrainingStyle.modalityPreferences`) —
   feeds `rankCandidateMixes`'s promotion logic (CLAUDE.md rule 17: may
   promote among goal-compatible candidates, never override a
   goal-incompatibility gate). Optional — a `Goal` with no preference
   degrades gracefully.
2. **Explicit construction** (`LongTermPlanner.buildCustomMix`, "Build My
   Own Mix," `WeeklyCompositionEditorView`) — the athlete picks an exact
   (style, frequency) composition directly, one row per `TrainingStyle`,
   bypassing recommendation entirely. `underlyingSystem(for:)` is the one
   translation from style to concrete `ProgrammingSystemKind` for this
   path; it has exactly 3 call sites (2 here, 1 display-only).

Both paths are already genuinely distinct from `Goal` selection in the
onboarding flow (`OnboardingViewModel`: `selectedGoalType` and
`preferredTrainingStyles`/`dislikedTrainingStyles` are separate, independent
`@State`-equivalent fields) — an athlete is never forced to reconfirm the
same information twice; `preferredTrainingStyles` may be empty.

**Alignment: ALIGNED** at the type level. The one defect is not in this
separation itself but in what a *specific* style/goal combination is
labeled downstream — see §12/§19.

---

## 9. TrainingMix Semantics

`TrainingMixComponent.programmingSystem: ProgrammingSystemKind?` —
confirmed by direct read (`Domain/Entities/TrainingMixComponent.swift:42`)
to be an **engine identity field**, not a `TrainingStyle`. This is correct
and intentional: a `TrainingMix` is "practical weekly composition," and
what actually executes a component is which engine materializes it, not
which athlete-facing style it was requested through. `label: String` is
the separate, independent athlete-facing text field — set by whichever
factory function builds the mix, and this is exactly where §12's bug lives
(the label was set wrong for one specific factory, not because the field
doesn't exist).

`TrainingMix.kind` (`.recommended`/`.selected`) and the "once selected,
authoritative" invariant are both already real and already enforced:
`TrainingPhase.selectedTrainingMix` always wins over
`recommendedTrainingMix` (`primaryInstance`/`secondaryInstances`, §
confirmed by direct read), and nothing in `LongTermPlanner` mutates an
existing `.selected` mix's components without an explicit revision call.

**Alignment: ALIGNED.** No change requested or needed to `TrainingMix`'s
own shape — confirmed safe to leave untouched, per the user's explicit "do
NOT redesign TrainingMix" instruction.

---

## 10. Program vs Engine

`ProgramDefinition.programmingSystem: ProgrammingSystemKind?` tags which
engine produced it; `lengthWeeks: Int` is a per-definition fact, never read
anywhere as a strategic-plan-level horizon (confirmed: `TrainingPlan`
carries no `lengthWeeks`-derived field, and `RollTacticalWindowUseCase`'s
own doc comment treats exhausting `lengthWeeks` as requiring a **new**
`ProgramInstance`, i.e. a phase-transition-shaped event, never a silent
plan extension). `ProgramInstance` carries dates/status/calibration
overrides — zero performance data, per CLAUDE.md rule 2, confirmed by
direct read.

**Alignment: ALIGNED.** §11's invariant ("a source program's duration does
not define the plan") is already architecturally enforced, not merely
assumed.

---

## 11. Strength Source Programs

Full recovery in `STRENGTH_SOURCE_RECOVERY_V1.md` (already closed as
analysis). Under this checkpoint's sharper lens (separating athlete-facing
role from engine, and testing whether shared-engine reuse improperly
dictated taxonomy): the underlying conclusion is **unchanged** — both
workbooks are additional, real, formula-driven Powerlifting-engine
configurations, not a new methodology — but the **athlete-facing exposure
path must go through a correctly-labeled "Strength Training" surface**, not
through anything that says "Powerlifting" to a GET STRONGER athlete who
never asked for it. See §18/§21 for the full placement decision.

---

## 12. Hypertrophy Semantic Check

`.hypertrophy` is heavily overloaded across FOUR layers today, examined
directly:

1. `GoalType` — **no** `.hypertrophy` case exists (the closest is
   `.muscleGain`, an outcome). Hypertrophy is NOT a `Goal`.
2. `PhaseType` — **no** `.hypertrophy` case exists (closest: `.muscleGain`,
   a strategic purpose). Hypertrophy is NOT a `Phase` purpose.
3. `TrainingStyle.hypertrophy` — a real athlete-facing preference/discipline
   case.
4. `ProgrammingSystemKind.hypertrophy` — a real engine identity.

This is **already correctly resolved**, not conflated: `Goal`/`Phase` never
use the word "hypertrophy" at all — they use `.muscleGain` (outcome) —
and "Hypertrophy" only ever appears as (3) a training-discipline preference
or (4) an engine tag, exactly the same two-layer split already established
for Strength Training/Powerlifting (§8-9). The apparent "same word at 4
layers" concern the user raised does not materialize in code — only 2 of
the 4 conceptual layers actually use this name, and those 2 are the correct
ones (discipline + engine), never goal or phase.

One real, minor label inconsistency found alongside this (see §9):
`muscleGainVariedMix()`'s single resistance component is labeled
**"Strength"** while running on the **Hypertrophy** engine
(`programmingSystem: .hypertrophy`) — this exact mix is reused as a
candidate under BOTH `.muscleGain` and `.strength` phase types. The label
"Strength" for a Hypertrophy-engine component is defensible in a
`.strength`-phase context (it genuinely is serving a strength-adjacent
role there) but is a bit imprecise in a `.muscleGain`-phase context (where
the same mix is offered as "Strength Plus Variety" for a BUILD MUSCLE
goal). Non-blocking — classified FOLLOW-UP (label polish only, no
behavioral effect, does not misroute the athlete to a wrong engine or a
wrong goal).

**Alignment: ALIGNED** at the Goal/Phase layer; **FOLLOW-UP** at the
component-label layer.

---

## 13. Powerlifting Semantic Check

`ProgrammingSystemKind.powerlifting` is a pure engine identity — confirmed,
no `GoalType`/`PhaseType` case named `.powerlifting` exists anywhere.
`TrainingStyle` also has **no separate `.powerlifting` case** — "Strength
Training" is the only athlete-facing route to this engine. This means the
specific conflation the user warned about in §5-6 ("Powerlifting is not Get
Stronger") **cannot occur through mismatched enum selection** — an athlete
is never offered "Powerlifting" as a style distinct from "Strength
Training" that could be confused with it.

**However, it DOES occur through mislabeled TEXT**, independent of the enum
model: `strengthFocusedMix()` — the actual default *recommendation* content
shown to a `GET STRONGER` athlete — names itself "Focused Powerlifting" and
labels its component "Powerlifting." This is the one concrete place the
word "Powerlifting" reaches an athlete who selected `GoalType.generalStrength`
and asked for nothing else. See §19 Scenario B for the full trace.

**Alignment: SEMANTICALLY OVERLOADED at the recommendation-content layer
only** (not the type-model layer). Minimum fix in §20/§21.

---

## 14. Functional Fitness Semantic Check

`GoalType.functionalFitness` (outcome-shaped: "I want to do CrossFit-style
training as my primary objective," confirmed by `functionalFitnessFocusedMix()`'s
own doc comment: "the user's own strategic goal here IS general physical
preparedness itself"), `PhaseType.functionalFitness` (mirrors it),
`TrainingStyle.functionalFitness` (discipline/preference), and
`ProgrammingSystemKind.functionalFitness` (engine) — four layers, but here
ALL FOUR are legitimately meaningful simultaneously, because Functional
Fitness is unusual among these methods: it can genuinely BE the athlete's
primary goal (not just a means to another goal), unlike Hypertrophy/
Powerlifting engines which never have a matching `GoalType`. This is not a
conflation — it is a correct, deliberate design already reflected in
`candidateMixTemplates`'s `.functionalFitness` case only ever returning the
one focused mix, and `muscleGainVariedMix()`/`strengthFocusedMix()` using
Functional Fitness only as a **supporting** component (never claiming it as
the primary objective) when the actual goal is `.muscleGain`/`.generalStrength`.

`.functionalFitness` is never synonymous with "conditioning" anywhere in
the code inspected — its own `adaptationObjectives` usage spans
`.workCapacity`/`.aerobicCapacity`/`.anaerobicCapacity`/`.power`/
`.skillAcquisition`, a genuinely broad set, not a narrow "cardio" label.

**Alignment: ALIGNED.**

---

## 15. Running / Cycling Semantic Check

`GoalType.enduranceEvent` is the outcome ("I have/want an endurance
performance objective"); `TrainingStyle.running`/`.cycling` are disciplines;
`ProgrammingSystemKind.running` is a real, closed, source-backed engine
(5K/2-Day V1); `.cycling` still resolves to generic `.steadyState`
(disclosed, unchanged, out of scope). Running is never treated as
synonymous with the endurance Goal — an athlete can select
`TrainingStyle.running` as a preference under a `.generalStrength` or
`.muscleGain` goal (confirmed: `muscleGainVariedMix()`/`enduranceVariedMix()`
both already place Running/Interval components under non-endurance goals),
and a `DatedObjective.runningEvent` can raise Running's priority temporarily
without changing `Goal.primaryType` (§16).

**Alignment: ALIGNED.**

---

## 16. Dated Objectives

`DatedObjective` (`LongTermGoalTypes.swift:209`): `kind`
(`.bodyCompositionMilestone`/`.runningEvent`), `date`, `status`, and one of
two payload fields — **never** a field that changes `Goal.primaryType`.
Confirmed directly: `Goal.datedObjectives` is documented as "authoritative
whenever non-empty... Never changes `primaryType`." `LongTermPlanner`'s
`proposeMilestoneAnchoredPhases`/`phaseType(forObjective:)` turn a dated
objective into a **temporary phase**, sequenced within the same
`TrainingPlan`, never a goal replacement — exactly the "Build Muscle
dominant → Build Muscle + race prep → race-specific phase → race →
recovery → return toward Build Muscle dominant" chain the user describes,
already a real, implemented, tested mechanism (Dated Objectives + 10K
Strategic Reconciliation V1, already closed).

The `EVENT → RECOMMENDATION → REASON → ATHLETE APPROVAL` rule is upheld:
`proposeStrategicPlan`/`reviseStrategicPlan` return `StrategicPlanProposal`s
(never mutate a plan directly); acceptance is a separate, explicit use case.

**Alignment: ALIGNED.**

---

## 17. Scenario Traces A-G

**Scenario A** — Goal: BUILD MUSCLE, no style preference.
`phaseType(for: .muscleGain) = .muscleGain`. `candidateMixTemplates`
returns `[muscleGainFocusedHypertrophyMix(), muscleGainVariedMix()]` —
both real Hypertrophy-engine-primary options, labeled "Hypertrophy" /
"Strength" respectively. `rankCandidateMixes` picks the best-aligned by
default (no preference to promote against). **Correct**: the athlete never
sees a method name that contradicts their stated goal.

**Scenario B** — Goal: GET STRONGER, no Powerlifting preference.
`phaseType(for: .generalStrength) = .strength`. `candidateMixTemplates`
returns `[strengthFocusedMix(), muscleGainVariedMix()]`. With no stated
preference, `rankCandidateMixes` selects by alignment — **today this
surfaces `strengthFocusedMix()`, named "Focused Powerlifting," labeled
"Powerlifting."** **This is the confirmed bug**: TrainingOS CAN build
canonical general-strength programming without a separate engine, but it
currently CANNOT do so without the athlete-facing text itself saying
"Powerlifting" — directly contradicting the user's own framing ("A
general-strength athlete should not have to become a Powerlifting athlete
because the implementation happens to reuse Powerlifting programming
mechanics"). Fix in §20.

**Scenario C** — Goal: GET STRONGER, athlete explicitly wants Powerlifting.
There is **no distinct way to express this today** — `TrainingStyle` has
no `.powerlifting` case separate from `.strengthTraining`, so "explicitly
wants Powerlifting" and "wants general strength training" are
**indistinguishable inputs**, and (once §20's fix lands) would produce
**identical output**, both correctly labeled "Strength Training." This is a
genuine **gap**, not a bug: the product currently cannot represent B vs. C
as different athlete intents. Whether it *should* is a real open
question — see §19/§24. Classified **FOLLOW-UP/V2**, not a blocker: no
recovered source content differs behaviorally between "general strength"
and "competitive powerlifting" (RM self-calibration/peaking/attempt
selection are all already-deferred, not-yet-built mechanics for both), so
adding a cosmetic-only second style with no behavioral consequence would
itself violate the user's own "avoid redundant choices" principle (§19).

**Scenario D** — Goal: GET STRONGER, athlete wants Functional Fitness to
remain important. Already representable: the athlete adds
`ModalityPreference(system: .functionalFitness)` to
`preferredModalities`, and `.strength`'s own second candidate
(`muscleGainVariedMix()`) already contains a real Functional Fitness
component — `rankCandidateMixes`'s promotion logic (§17 non-negotiable
rule) surfaces it over `strengthFocusedMix()` when the preference signal is
strong enough, without ever changing `Goal.primaryType` away from
`.generalStrength`. **Correct, already works.**

**Scenario E** — Goal: BUILD MUSCLE, 5K dated objective.
`DatedObjective(kind: .runningEvent, ...)` → `phaseType(forObjective:)`
returns `.enduranceEvent` for the objective-driven phase only;
`candidateMixTemplates`'s `.enduranceEvent` case forces "Running" via
`preferredEnduranceActivityLabel`/hardcoded "Running" exactly per the
already-locked rule (§10 of this report; confirmed in code at
`LongTermPlanner.swift:1275-1289`). `Goal.primaryType` remains
`.muscleGain` throughout — confirmed never mutated by this path. **Correct,
already works.**

**Scenario F** — Goal: BUILD MUSCLE, ~12-month horizon, multiple
sequential Hypertrophy mesocycles/phases.
`TrainingPlan.orderedPhases` + `fillForwardPhases` + the revision lineage
(`supersedes`/`lineageID`) already support an arbitrarily long chain of
phases, each with its own `ProgramInstance`(s); no code path treats one
`ProgramDefinition.lengthWeeks` as the plan's own horizon (§11/§6).
**Correct, already works** — confirmed architecturally, not merely
assumed.

**Scenario G** — Goal: GET STRONGER, ~12-month horizon,
foundation→volume→strength→intensification→test/recovery, without
hardcoding this exact sequence.
`PhaseType` already has `.strength`/`.muscleGain`/`.recovery`/`.transition`
as distinct, freely-sequenceable values; `fillForwardPhases`/
`proposeForwardOnlyPhases` already construct forward phase chains driven by
`Goal`, not a hardcoded template. **Nothing in the current architecture
prevents this sequence from being proposed** — whether `LongTermPlanner`'s
*specific* phase-selection heuristics would today choose to alternate
`.muscleGain`↔`.strength`↔`.recovery` phases the way the example describes
is a tuning/heuristics question, not an architectural blocker: the phase
vocabulary and chaining mechanism already support it. **Architecturally
capable; not a gap.**

---

## 18. Strength Source Content Decision

Re-examined, not merely repeated, against this checkpoint's sharper
athlete-facing-role-vs-engine lens (§6/§18 of the user's directive):

**Athlete-facing role: A modified — "canonical general-strength
programming building blocks," reached through the existing
`TrainingStyle.strengthTraining` surface** (never through a hypothetical
separate "Powerlifting" surface, because none exists and none is
justified — see Scenario C above). This is a **refinement** of, not a
reversal of, the Strength Source Recovery V1 report's own conclusion:
that report answered "is Strength a distinct engine/mechanism from
Powerlifting" (no) without yet having this checkpoint's three-tier
Goal/Style/Engine separation fully in view; with that separation now
explicit, the correct framing is that these 2 workbooks are
**Answer C: shared-engine configurations usable in different athlete-facing
contexts** — usable equally under a `GET STRONGER` goal (via
`TrainingStyle.strengthTraining`) as under an explicit
`TrainingStyle.strengthTraining` preference selected for any other goal.

**Underlying engine: unchanged — `PowerliftingProgramGenerator`, 2 new
`PowerliftingFamily` cases**, exactly as scoped in
`STRENGTH_SOURCE_RECOVERY_V1.md` §14. No new `ProgrammingSystemKind`, no new
`TrainingStyle` case.

**The one real precondition this checkpoint adds**: before this content
ships, `strengthFocusedMix()`'s naming bug (§13/§19 Scenario B) must be
fixed. Shipping 2 new real Powerlifting-engine configurations into a mix
still named "Focused Powerlifting" would make the mislabeling *more*
consequential, not less — more athletes reaching real content through a
mislabeled surface. This is why §16/§24 sequence the naming fix as a
prerequisite to, not a follow-on from, the Strength content
implementation.

---

## 19. Athlete Input Requirements

What genuinely needs explicit athlete input, vs. what TrainingOS should
recommend, based on what actually varies outcome vs. what's redundant:

- **Primary goal** — MUST be explicit (`GoalType`). No default can guess
  this; it is the root of everything downstream.
- **Long-term horizon** — SHOULD be explicit where a dated objective exists
  (`DatedObjective.date`); otherwise TrainingOS reasonably defaults to
  open-ended (`TrainingPhase.endDate == nil`), needing no forced choice.
- **Training preferences/disciplines (`TrainingStyle`)** — SHOULD remain
  optional, exactly as currently built (`preferredTrainingStyles` defaults
  to empty). This is NOT redundant with Goal, because it carries genuinely
  new information no `GoalType` implies: e.g. "GET STRONGER, but I also
  want Functional Fitness in the mix" is information `GoalType.generalStrength`
  alone cannot express. The one place this becomes close to redundant is
  the narrow Scenario C gap already documented (§17) — not worth adding a
  cosmetic-only extra choice for.
- **Availability** — MUST be explicit (`UserAvailability`); no goal or
  style implies how many days/week or session length an athlete has.
- **Environment** — MUST be explicit (equipment gates real capability,
  e.g. Cycling's `requiredEquipment`, already gated in
  `WeeklyCompositionEditorView`).
- **Dated objectives** — SHOULD be optional and additive, never forced at
  onboarding; already built this way (`Goal.datedObjectives` defaults to
  `[]`).

**The one redundancy risk the user explicitly asked to test for** — "Goal:
GET STRONGER, then: Do you want Strength Training?" — **does not occur
today**: the onboarding flow (`OnboardingViewModel`) asks Goal
(`selectedGoalType`) and style preferences
(`preferredTrainingStyles`/`dislikedTrainingStyles`) as two independent,
both-optional-after-goal fields in the same flow, never presenting a
"Strength Training?" yes/no gate keyed directly off `.generalStrength`. No
onboarding-flow correction is required.

---

## 20. Long-Term Planning Invariants

| # | Invariant | Verdict | Reasoning |
|---|---|---|---|
| I1 | Goal describes the athlete's long-term desired outcome | **CONFIRMED** | `GoalType`'s 6 cases are all outcomes; no method name among them (§4). |
| I2 | Goal may persist across multiple phases with different programming emphases | **CONFIRMED** | `TrainingPlan.orderedPhases` + `fillForwardPhases`; Scenario G traces this directly (§17). |
| I3 | A TrainingPhase describes what TrainingOS is trying to develop during a bounded period | **CONFIRMED** | `PhaseType`/`priorityRule`, no modality field of its own (§6). |
| I4 | A source program is a phase/programming building block, not the strategic plan itself | **CONFIRMED** | `ProgramDefinition.lengthWeeks` never read as a plan horizon; exhaustion requires a new `ProgramInstance` (§10, `RollTacticalWindowUseCase`). |
| I5 | Training methods/preferences describe how the athlete wants to train, not what outcome they want | **CONFIRMED** | `TrainingStyle` carries no outcome semantics; verified distinct from `GoalType` in both type and usage (§8). |
| I6 | Powerlifting is not synonymous with Get Stronger | **NEEDS QUALIFICATION** | True at the type level (no `GoalType.powerlifting`, no `TrainingStyle.powerlifting`) but **violated at the recommendation-content/label level** by `strengthFocusedMix()` (§13/§19-B). Fix required before this invariant is fully true in the running app, not just in the type model. |
| I7 | Functional Fitness is not synonymous with conditioning | **CONFIRMED** | `.functionalFitness`'s adaptation-objective usage spans 5 distinct domains, never narrowed to "cardio" (§14). |
| I8 | Running is not synonymous with an endurance Goal | **CONFIRMED** | `TrainingStyle.running` is independently selectable under any goal; `GoalType.enduranceEvent` is a separate, distinct case (§15). |
| I9 | Strength and hypertrophy can describe programming emphasis without requiring separate execution engines | **CONFIRMED** | `muscleGainVariedMix()` already labels a Hypertrophy-engine component "Strength" for exactly this purpose (§7/§12). |
| I10 | Shared engine implementation must not dictate athlete-facing taxonomy | **NEEDS QUALIFICATION** | True for the TYPE model (`TrainingStyle` has no `.powerlifting` case forced by the engine); **currently false for recommendation TEXT** — `strengthFocusedMix()` is the counter-example (§13). This is the same underlying finding as I6, viewed from the opposite direction. |
| I11 | TrainingMix is the exact practical composition selected for a phase | **CONFIRMED** | Directly verified in `TrainingMix`/`TrainingMixComponent` (§9). |
| I12 | Once selected/accepted, exact TrainingMix is authoritative until the athlete approves a change | **CONFIRMED** | `TrainingPhase.selectedTrainingMix` always wins over `recommendedTrainingMix`; no code path silently mutates a `.selected` mix's components (§9). |
| I13 | Dated objectives may change phase recommendations without silently replacing the primary Goal | **CONFIRMED** | `Goal.datedObjectives`'s own doc comment: "Never changes `primaryType`" (§16). |
| I14 | Long-term planning may chain multiple source programs/mesocycles | **CONFIRMED** | Scenario F (§17); `TrainingPlan.orderedPhases`. |
| I15 | Future phases may communicate strategic direction without fabricating future exact TrainingMix/program selections | **CONFIRMED** | `PlanPresentation.swift`'s own doc comment: "per-TYPE description — never a per-instance fabricated rationale"; Year Overview's own established principle (already-closed work, confirmed unchanged by grep, not reopened). |

---

## 21. Semantic Mismatches

**Mismatch 1 — `strengthFocusedMix()` naming.**
- CURRENT: `TrainingMix(name: "Focused Powerlifting")` with its sole
  component `label: "Powerlifting"`, returned as a real candidate
  recommendation for `PhaseType.strength` (i.e., `GoalType.generalStrength`
  with no special preference).
- INTENDED: An athlete pursuing GET STRONGER with no stated discipline
  preference should see a goal-neutral label — "Strength Training" (the
  exact string `componentLabel(for: .strengthTraining)` already produces
  elsewhere) — never "Powerlifting," a sport-specific discipline name the
  athlete never requested.
- IMPACT: Directly contradicts CLAUDE.md rule 14 in spirit (a modality
  identity — "you are now doing Powerlifting" — is implied without the
  athlete selecting it) and is the literal scenario the user's directive
  opened with ("GET STRONGER ≠ POWERLIFTING").
- CLASSIFICATION: **CHECKPOINT BUG.**
- MINIMUM FIX: rename `TrainingMix(name:)` to `"Focused Strength Training"`
  and the component `label` to `"Strength Training"` in
  `strengthFocusedMix()` (`LongTermPlanner.swift:1561-1569`). Zero change
  to `programmingSystem: .powerlifting`, `adaptationObjectives`,
  `frequency`, or any scheduling/materialization behavior.

**Mismatch 2 — `defaultAdaptationObjectives` disagreement for
`.strengthTraining`.**
- CURRENT: `buildCustomMix`'s `defaultAdaptationObjectives(for:
  .strengthTraining)` returns `[.muscleGain]`
  (`LongTermPlanner.swift:815-820`), while the equivalent recommended-path
  content, `strengthFocusedMix()`, tags its Powerlifting component
  `[.maxStrength]`.
- INTENDED: The same athlete-facing style should carry the same adaptation
  semantics regardless of which construction path (recommended vs.
  custom-built) produced it.
- IMPACT: An athlete who explicitly builds "4x Strength Training" via
  "Build My Own Mix" gets a component objectively tagged as pursuing
  `.muscleGain` — the SAME objective Hypertrophy carries — even though the
  underlying engine is Powerlifting and the equivalent recommended mix
  correctly says `.maxStrength`. This could affect any future logic that
  reads `adaptationObjectives` to reason about what a component is for
  (e.g. maintenance-target sizing, alignment scoring) inconsistently
  depending on which path built the component.
- CLASSIFICATION: **CHECKPOINT BUG** (small, but a direct, provable
  inconsistency the user's directive specifically asked to be caught).
- MINIMUM FIX: change `case .hypertrophy, .strengthTraining: return
  [.muscleGain]` to two separate cases —
  `case .hypertrophy: return [.muscleGain]` /
  `case .strengthTraining: return [.maxStrength]`.

**Mismatch 3 — `muscleGainVariedMix()`'s "Strength" label under the
Hypertrophy engine.**
- CURRENT: component `label: "Strength"`, `programmingSystem: .hypertrophy`.
- INTENDED: unambiguous, context-correct labeling in both of this mix's
  reuse contexts (`.muscleGain` phase and `.strength` phase).
- IMPACT: Cosmetic only — no behavioral effect; a careful athlete could
  find "Strength" (Hypertrophy engine) shown alongside "Strength Training"
  (Powerlifting engine, once Mismatch 1 is fixed) slightly confusing.
- CLASSIFICATION: **FOLLOW-UP** (label polish, not required before the next
  checkpoint).
- MINIMUM FIX (deferred): consider a phase-context-aware label (e.g.
  "Strength-Focused Hypertrophy") — not implemented now, per §16's
  "smallest correction" instruction.

**Mismatch 4 — Scenario B/C indistinguishability (general strength vs.
explicit competitive Powerlifting intent).**
- CURRENT: no `TrainingStyle` case exists to express "I specifically want
  competitive Powerlifting" as distinct from "I want general strength
  training."
- INTENDED: per the user's own Scenario C question, the product should be
  ABLE to represent this difference if it matters.
- IMPACT: none today — no recovered source content or engine behavior
  actually differs between the two intents (peaking/attempt-selection/
  competition-specific calibration are all already out of scope,
  independent of this checkpoint).
- CLASSIFICATION: **V2** (no behavioral content exists yet to justify the
  distinction; revisit only if/when competition-specific Powerlifting
  mechanics — e.g. RM self-calibration, peaking — are ever built, per
  `STRENGTH_SOURCE_RECOVERY_V1.md` §12's own deferred item).
- MINIMUM FIX: none now.

---

## 22. Minimum Required Corrections

Only Mismatches 1 and 2 qualify as BLOCKER/CHECKPOINT BUG (the only tiers
the user's §16 instruction allows into the immediate implementation plan):

1. **CHECKPOINT BUG** — rename `strengthFocusedMix()`'s `TrainingMix.name`
   and component `label` from "Focused Powerlifting"/"Powerlifting" to
   "Focused Strength Training"/"Strength Training."
   (`LongTermPlanner.swift:1561-1569`, ~2 line changes, 0 test-breaking
   risk to any mechanic — only display strings change.)
2. **CHECKPOINT BUG** — split `defaultAdaptationObjectives`'s
   `.hypertrophy, .strengthTraining` combined case so `.strengthTraining`
   returns `[.maxStrength]`, matching `strengthFocusedMix()`.
   (`LongTermPlanner.swift:815-820`, 1 line change.)

Everything else identified (Mismatch 3, Scenario C's gap, the
`StrategicPlanningEngine` naming mismatch in §5) is FOLLOW-UP or V2 —
explicitly NOT part of the immediate implementation plan, per the user's
own instruction.

No new `ProgrammingEmphasis` type. No new `TrainingStyle` case. No new
`ProgrammingSystemKind` case. No `TrainingMix`/`TrainingMixComponent`
schema change. No `Goal`/`TrainingPhase`/`TrainingPlan` schema change.

---

## 23. Strength Implementation Placement

Confirms and sequences §11/§18: implement
`STRENGTH_SOURCE_RECOVERY_V1.md` §14's scope (2 new `PowerliftingFamily`
cases, `.d`/`.e`, reusing `PowerliftingProgramGenerator` unchanged) **after**
the 2 corrections in §22 land — specifically because the new content's
only athlete-facing entry point is exactly the surface Mismatch 1 currently
mislabels. No change to that implementation's own already-specified scope
is needed; only its *sequencing* relative to this checkpoint's fix.

---

## 24. Recommended Next Checkpoint

Single checkpoint, narrow, in this order:

1. Apply the 2 CHECKPOINT BUG fixes in §22 (label/objective corrections
   only).
2. Implement the already-fully-specified Strength V1 scope from
   `STRENGTH_SOURCE_RECOVERY_V1.md` §14 (2 new `PowerliftingFamily` cases,
   `ProgramCapabilityRegistry` additions, `StrengthSourceFidelityTests.swift`).
3. Regression: full test suite, confirm the exact same 1 known unrelated
   failure baseline, confirm no label string appears in any existing test
   assertion that this checkpoint's rename would break (grep
   `"Focused Powerlifting"`/`"Powerlifting"` label assertions before
   applying).
4. Close this checkpoint.
5. Proceed directly to the final Whole Athlete Journey audit — nothing in
   this analysis identified a reason to insert any further audit or
   redesign pass first.

---

## Verdict

GOAL SEMANTICS ALIGNED: YES
LONG-TERM MULTI-PHASE MODEL ALIGNED: YES
PHASE EMPHASIS REPRESENTABLE: YES
TRAINING PREFERENCES DISTINCT FROM GOALS: YES
POWERLIFTING DISTINCT FROM STRENGTH GOAL: NO
HYPERTROPHY ROLE CLEAR: YES
TRAINING MIX SEMANTICS SAFE: YES
SOURCE PROGRAMS ARE BUILDING BLOCKS: YES
SHARED ENGINE CAN REMAIN: YES
STRENGTH SOURCE PROGRAM ROLE RESOLVED: YES
CLOSED SYSTEMS REQUIRE REOPENING: NO
MINIMUM CORRECTION IDENTIFIED: YES
READY FOR IMPLEMENTATION CHECKPOINT: YES
WHOLE ATHLETE JOURNEY AFTER NEXT IMPLEMENTATION: YES
