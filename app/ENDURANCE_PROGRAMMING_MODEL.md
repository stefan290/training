# Endurance Programming Model

Stage 3B architecture validation for Aerobic Base, Beginner/Developed
Running, and VO2/Interval work. This is a proposed abstraction, not an
implementation — nothing here is built. Source grounding for every claim
below is in `PROGRAMMING_SOURCES.md` §§1–3; this document assumes that
classification and doesn't repeat it inline except where the distinction
is load-bearing for a design decision.

## 1. Headline finding

**One generic system handles steady-state work across every modality
(`SteadyStateProgrammingSystem`), and one generic system handles interval
work across every modality (`IntervalProgrammingSystem`) — including
Running's own interval sessions and VO2 work. Running does not need, and
does not get, its own rule engine.** This is the central conclusion of
this document and is argued in full in §4. Everything else here (Beginner
Running's regression proof, the VO2 4×4 fixture, the aerobic prescription
proof) is evidence for or consequence of that conclusion, not a separate
finding.

## 2. Aerobic Base is a stimulus; Bike/Run/Row/Ski are modalities that execute it

The brief's key question (§4 of the Stage 3B instruction): is Aerobic Base
fundamentally a programming *stimulus*, with Bike/Run/Row/SkiErg as
interchangeable *modalities* used to deliver it?

**Yes — validated, and preferred, per the instruction's own default.**
Evidence: British Cycling's own zone/build-week model (`PROGRAMMING_SOURCES.md`
§2) has nothing cycling-specific about its *mechanics* — "Build weeks
increase intensity/volume, then a recovery week, then return to Build 1"
and "prescribe by Zone 1–5, HR or power" are equally sensible instructions
for a rower, a runner doing easy long runs, or a Zone 2 cyclist. Nothing
in the source material ties the build/recovery *cycle* or the *zone*
concept to bicycles specifically — those are properties of steady-state
aerobic training generically, and cycling is simply where British Cycling
happened to publish a public example of them.

```
struct SteadyStateProgrammingSystem: ProgrammingSystem {
    // parameters, per Stage 3B brief §4:
    let modality: TrainingModality           // existing enum, e.g. .cycling, .running,
                                              // .rowing, .skiErg — NOT a new type
    let sessionsPerWeek: Int
    let duration: DurationSpec                // fixed, or a per-week progression table
    let targetIntensity: IntensityTarget      // see §5 below — HR zone | power zone | RPE
    let progressionVariable: SteadyStateProgressionVariable   // see §3
    let recoveryWeekStrategy: RecoveryWeekStrategy            // e.g. everyNthWeek(3), fixed reduction factor
}
```

`modality` reuses the **existing** `TrainingModality` enum from Stage 1–2
(already present for exactly this purpose — nothing new is introduced by
using it here). The system produces ordinary `ProgramDefinition`s exactly
like `HypertrophyProgrammingSystem` does; only its `ProgressionRule`
vocabulary and prescription shape differ, per §5–6.

## 3. `IntervalProgrammingSystem` — generic across Running, Bike, Row, and VO2

Per the brief's §14 explicitly: don't finalize a `VO2ProgrammingSystem` name
until this comparison is done. It's done — **there is no
`VO2ProgrammingSystem`.** VO2max work (Helgerud's 4×4 protocol) is one
named parameter preset of a single generic `IntervalProgrammingSystem`
that also represents Running's tempo/threshold/interval sessions, Beginner
Running's run/walk sessions, and Bike/Row interval work.

```
struct IntervalProgrammingSystem: ProgrammingSystem {
    let modality: TrainingModality
    let intervalCount: Int
    let workSpec: IntervalLegSpec              // duration and/or distance + target
    let recoverySpec: IntervalLegSpec           // duration and/or distance + target,
                                                 // target may be "walk"/"rest"/"active" —
                                                 // see §7 for the Beginner Running case
    let progressionVariable: IntervalProgressionVariable   // see §6
    let sessionsPerWeek: Int
}

struct IntervalLegSpec {
    let duration: Duration?
    let distance: Distance?
    let target: IntensityTarget?               // HR zone | power zone | pace | RPE | none
}

enum IntensityTarget {
    case heartRateZone(HeartRateZone)
    case powerZone(PowerZone)
    case pace(PaceRange)
    case rpe(ClosedRange<Int>)
    case percentOfHRMax(ClosedRange<Double>)   // needed to cite Helgerud's own "90-95% HRmax"
                                                 // faithfully, per §8 below
}
```

### 3.1 Named presets are data, not subclasses

Consistent with how `PROGRAMMING_SYSTEM_MODEL.md` §4 already treats
Hypertrophy/Powerlifting as "named bundles, not new entity types," VO2
work is a **named parameter preset**, not a class:

```
extension IntervalProgrammingSystem {
    static func helgerud4x4(modality: TrainingModality) -> IntervalProgrammingSystem {
        IntervalProgrammingSystem(
            modality: modality,
            intervalCount: 4,
            workSpec: IntervalLegSpec(duration: .minutes(4), distance: nil,
                                       target: .percentOfHRMax(0.90...0.95)),
            recoverySpec: IntervalLegSpec(duration: .minutes(3), distance: nil,
                                           target: .percentOfHRMax(0.70...0.70)),
            progressionVariable: .none,          // the source study fixed this protocol;
                                                   // see PROGRAMMING_SOURCES.md §3 — presenting
                                                   // this as ever needing to "progress" would
                                                   // misrepresent the source
            sessionsPerWeek: 3
        )
    }
}
```

This preset is explicitly labeled per `PROGRAMMING_SOURCES.md` §3 as one
validated reference fixture (SOURCE-DERIVED numbers), not a claim that 4×4
is the only valid VO2 structure — the brief's §13 instruction is enforced
by construction here: there is no code path that treats `helgerud4x4` as
anything other than one named preset among arbitrarily many.

## 4. Modality-independent intervals — the proof

Per Stage 3B §15: the same `IntervalProgrammingSystem` represents Running,
Bike, and Row 4×4 sessions, with only `modality` and the intensity-target
*type* changing:

| Field | Running | Bike | Row |
|---|---|---|---|
| `modality` | `.running` | `.cycling` | `.rowing` |
| `intervalCount` | 4 | 4 | 4 |
| `workSpec.duration` | 4 min | 4 min | 4 min |
| `workSpec.target` | `.percentOfHRMax(0.90...0.95)` | `.powerZone(.four)` | `.strokeRate(...)` — see below |
| `recoverySpec.duration` | 3 min | 3 min | 3 min |
| `recoverySpec.target` | `.percentOfHRMax(0.70...0.70)` | `.powerZone(.one)` | easy stroke rate |

**One gap this proof surfaces:** `IntensityTarget` as defined in §3 has no
case for rowing's own primary intensity idiom, **stroke rate** (strokes
per minute), or split pace (time per 500m). This is a real, useful finding
from the stress test, not a reason to abandon the generic design — the
fix is additive, not structural:

```
enum IntensityTarget {
    // ...cases from §3...
    case strokeRate(ClosedRange<Int>)          // rowing-specific, new
    case splitPace(PaceRange)                  // rowing/running-shared idiom (time per
                                                 // distance unit), reuses PaceRange from §3
}
```

Adding a case to an existing enum, driven by a modality's own native unit,
is exactly the kind of change this validation pass exists to catch *now*
— it costs nothing architecturally (no new `ProgrammingSystem`, no new
`WorkoutBlock` type, no schema migration) and confirms the generic
interval architecture is preferable to a duplicate per-modality engine,
per the brief's own instruction in §15.

## 5. Aerobic prescription proof

The two examples from Stage 3B §5, checked against §2's model:

**Example A — Zone 2 Bike, 45 min, target HR Zone 2, result: duration, average HR, distance.**

```
SteadyStateProgrammingSystem(modality: .cycling, sessionsPerWeek: ..., 
    duration: .fixed(.minutes(45)), targetIntensity: .heartRateZone(.two), ...)
→ WorkoutBlock(type: .steadyState, prescription: .steadyState(duration: 45min, target: HRZone2))
→ result: SteadyStateResult(duration: Duration, averageHR: Int, distance: Distance?)
```

**Example B — Zone 2 Row, 40 min, target RPE/HR range, result: duration, distance, average HR.**

Identical shape, `modality: .rowing`, `targetIntensity` carrying either an
RPE range or an HR zone (both already representable per §3's
`IntensityTarget` enum — this is exactly the "RPE as fallback" pattern
British Cycling itself uses, per `PROGRAMMING_SOURCES.md` §2, generalized
across modalities).

**Confirmed: neither example requires sets, reps, RIR, or load.** A
`WorkoutBlock` of type `.steadyState` never populates
`ExercisePrescription`'s strength-shaped fields at all — see
`PRESCRIPTION_RESULT_MODEL_REVIEW.md` for why this requires a new
`BlockPrescription` shape rather than leaving unused strength fields
`nil` on the existing type.

## 6. Aerobic and interval progression — no universal sequence

Per §6 and §16 of the brief: progression must be a menu, not a hardcoded
recipe.

```
enum SteadyStateProgressionVariable {
    case progressDuration(weeklyIncrease: Duration)
    case progressSessionFrequency(from: Int, to: Int, overWeeks: Int)
    case progressIntensity(zoneProgression: [HeartRateZone])
    case none   // e.g. a fixed-duration maintenance block
}

enum IntervalProgressionVariable {
    case increaseIntervalCount(by: Int, everyNWeeks: Int)
    case increaseIntervalDuration(by: Duration, everyNWeeks: Int)
    case increaseTargetIntensity(...)
    case decreaseRecoveryDuration(by: Duration, everyNWeeks: Int)
    case increaseFrequency(from: Int, to: Int)
    case none
}
```

Each case is a single, named, independently-selectable progression axis —
exactly the `ProgressionRule`-as-data pattern already established in
`PROGRAMMING_SYSTEM_MODEL.md` §3 for Hypertrophy/Powerlifting, reused
here rather than reinvented. Per §16's explicit requirement, an
`IntervalProgrammingSystem` instance also carries a **`progressionPriority:
[IntervalProgressionVariable]`** — an ordered list stating which
variable(s) actually change and in what order of precedence, so a
progression that increases interval count this block and target intensity
next block doesn't require guessing which one "wins" if a rule engine
ever needs to reconcile two simultaneously-eligible changes. This
directly satisfies §16's requirement without assuming variables move
together.

## 7. Beginner Running is a same-session composition, not a special mechanic

Per Stage 3B §9's specific requirement: Couch to 5K's run/walk sessions
must be provable as a semantic composition, not opaque per-week static
data.

**Week 1** (`PROGRAMMING_SOURCES.md` §1, SOURCE-DERIVED): 5-min warm-up
walk, then alternating 60s run / 90s walk to ~20 min total, 5-min cool-down.

```
Session {
    blocks: [
        WorkoutBlock(type: .warmUp,   prescription: .steadyState(duration: 5min, target: .walk)),
        WorkoutBlock(type: .interval, prescription: .interval(
            intervalCount: 8,   // ~20 min / (60s + 90s) ≈ 8 reps
            workSpec:     IntervalLegSpec(duration: .seconds(60), target: .rpe(comfortable)),
            recoverySpec: IntervalLegSpec(duration: .seconds(90), target: .walk)
        )),
        WorkoutBlock(type: .coolDown, prescription: .steadyState(duration: 5min, target: .walk))
    ]
}
```

**Week 9** (SOURCE-DERIVED, the plan's final week): the *same three-block
shape* — warm-up, main block, cool-down — where the main block has
degenerated to a single steady-state block, because there is no more
interval structure left to represent:

```
Session {
    blocks: [
        WorkoutBlock(type: .warmUp,    prescription: .steadyState(duration: 5min, target: .walk)),
        WorkoutBlock(type: .steadyState, prescription: .steadyState(duration: 30min, target: .comfortableRPE)),
        WorkoutBlock(type: .coolDown,  prescription: .steadyState(duration: 5min, target: .walk))
    ]
}
```

**This is the proof the brief asked for:** the *only* thing that changed
between Week 1 and Week 9 is which `WorkoutBlock` type occupies the middle
slot (`.interval` → `.steadyState`) and that block's own parameters — the
outer `Session` shape (warm-up → main → cool-down) is unchanged, and no
new entity type was needed to represent "the program has progressed past
needing intervals at all." **Week 5** (SOURCE-DERIVED — three different
session shapes in one week, per `PROGRAMMING_SOURCES.md` §1) is the
sharpest confirmation: session 3 that week is already a 20-minute
steady-state block with no interval structure, while sessions 1–2 in the
*same week* still use interval blocks — proving a `Session`'s block
composition is chosen per-session, not fixed for a whole program stage.

**Confirmed: the generic `Session`/`WorkoutBlock` model supports
alternating activity states within one session** (walk/run/walk/run...)
without any bespoke "run-walk mechanic" — it's an ordinary
`IntervalProgrammingSystem` output whose recovery leg's target happens to
be "walking" rather than "easy jog" or "active recovery," which §3's
`IntervalLegSpec.target` already accommodates as a value, not a new type.

## 8. Session roles — semantics, not new entity types

Per Stage 3B §10, Developed Running needs Easy / Recovery / Long Run /
Tempo / Threshold / Interval / (later) Race-specific. Validated as an
enum tag on `ProgramDefinition`/`Session`, orthogonal to which generic
system produced the underlying blocks:

```
enum SessionRole {
    case easy, recovery, longRun, tempo, threshold, interval, raceSpecific
}
```

Mapping onto the two generic systems from §2–3 (this mapping is itself
TRAININGOS-DESIGNED, per `PROGRAMMING_SOURCES.md` §1 — no source dictates
this mapping, it's our own synthesis):

| Session role | Produced by | Why |
|---|---|---|
| Easy, Recovery, Long Run | `SteadyStateProgrammingSystem` | Continuous effort at a controlled, sub-threshold intensity — no interval structure. |
| Tempo, Threshold | `SteadyStateProgrammingSystem` at a higher `targetIntensity`, OR `IntervalProgrammingSystem` with long work legs and short/no recovery (both are legitimate; which a given `RunningProgrammingSystem` configuration picks is a methodology choice, not an architecture constraint) | |
| Interval | `IntervalProgrammingSystem` | Discrete work/recovery structure — VO2 4×4, track repeats, etc. |
| Race-specific | Either, depending on race distance/demand | Explicitly deferred — no source material analyzed for this yet; the role exists as an enum case so it's representable when it is designed, per §12 non-goals. |

This confirms §10's own framing: **these are programming semantics, not
new core entity types.**

## 9. `RunningProgrammingSystem` — validated as composition, not a new engine

Per Stage 3B §32's explicit invitation not to force an answer: does
Running need its own `ProgrammingSystem` implementation? **No new rule
engine — but a named system is still useful as a methodology-level
composer**, exactly mirroring the existing pattern where
`HypertrophyProgrammingSystem`/`PowerliftingProgrammingSystem` share one
`ProgressionRule` vocabulary (`PROGRAMMING_SYSTEM_MODEL.md` §4) but are
still named separately because each represents a distinct, coherent
methodology worth surfacing to a user or a `ProgramGenerator` by name.

```
struct RunningProgrammingSystem: ProgrammingSystem {
    let experienceLevel: RunningExperienceLevel   // .beginner | .developing | .trained
    let weeklyStructure: [SessionRole: IntervalOrSteadyStateConfig]
    // produces a ProgramDefinition (or, composed across stages, a
    // ProgramJourney — see §10 below) whose individual Sessions/
    // WorkoutBlocks are ordinary IntervalProgrammingSystem / 
    // SteadyStateProgrammingSystem output with modality = .running
}
```

`RunningProgrammingSystem` owns *methodology* decisions (which session
roles appear this week, how the beginner run/walk ratio advances, when a
Tempo session gets introduced) — it does not own a competing
`ProgressionRule` vocabulary, a competing `WorkoutBlock` type, or a
competing prescription/result shape. This is the direct, load-bearing
consequence of §1's headline finding, stated here in system-design terms:
**validated as a thin, named configuration/composition layer, not an
independent rule engine** — satisfying Stage 3B §8/§10's request to
"validate `RunningProgrammingSystem`" with a validated-but-narrower answer
than the brief's phrasing might suggest, exactly as §32 permitted.

## 10. Running Journey — validating `ProgramJourney` for a non-hypertrophy case

Per Stage 3B §38's example, "Beginner Run/Walk → Base Running → 5K
Development":

```
ProgramJourney(
    name: "Beginner to 5K",
    phases: [
        .single(ProgramDefinition(system: .running(beginnerConfig))),   // IntervalProgrammingSystem
                                                                          // output, run/walk, per §7
        .single(ProgramDefinition(system: .running(baseRunningConfig))), // SteadyStateProgrammingSystem
                                                                          // output, continuous easy running
        .single(ProgramDefinition(system: .running(fiveKDevConfig)))     // mixed Easy/Tempo/Interval
                                                                          // roles, per §8
    ],
    transitionTrigger: .userInitiated
)
```

This is the same `ProgramJourney` shape introduced for Family A's
hypertrophy mesocycles in `PROGRAMMING_SYSTEM_MODEL.md` §5.1 — no change
needed to the `ProgramJourney` type itself. See
`MODALITY_ARCHITECTURE_VALIDATION.md` §6 for the one generalization
`ProgramJourney` *does* need (multi-system concurrent phases), which
surfaces from the Hybrid Journey example, not the Running one.

## 11. What this document does not decide

- **Exact zone-table values, FTP-test protocols, or specific named
  workouts as shipped content** — `PROGRAMMING_SOURCES.md` explicitly
  flags these as needing re-verification against live sources before any
  number is hardcoded into a shipped fixture; this is architecture
  validation, not content authoring.
- **Whether `RunningProgrammingSystem`'s beginner/developing/trained
  configurations are exactly right** — the *shape* (a named composer over
  two generic systems) is validated; the specific weekly structures per
  experience level are Stage 4+ content work.
- **Prescription/result value types themselves** (`IntervalLegSpec`,
  `SteadyStateResult`, etc.) — sketched here for this document's own
  proof, but the authoritative, cross-modality version (including how
  they interact with Functional Fitness's needs) is
  `PRESCRIPTION_RESULT_MODEL_REVIEW.md`.
