# Stage 3B Architecture Decisions

Answers to the Stage 3B review gate (brief §48), and the MUST-BEFORE-
STAGE-4 vs. CAN-WAIT classification the brief's point 10 asks for. This
document is the one to read first for a yes/no answer to each gate
question; `MODALITY_ARCHITECTURE_VALIDATION.md` and the five companion
documents carry the supporting analysis.

## 1. Does the existing `ProgrammingSystem` abstraction survive?

**Yes, unchanged, as a protocol.** The concrete-implementation count is
smaller than the brief's illustrative list — 5 systems, not 6+ — because
Aerobic Base, Running's individual sessions, and VO2 all collapse into two
new generic systems (`SteadyStateProgrammingSystem`, `IntervalProgrammingSystem`)
rather than needing one system per modality name. Full reasoning:
`MODALITY_ARCHITECTURE_VALIDATION.md` §2.

## 2. Does `ExercisePrescription` need replacement/generalization?

**No replacement. Generalization via addition.** `ExercisePrescription`
is untouched; a new `BlockPrescription` enum wraps it as one case among
new siblings (`.steadyState`, `.interval`, `.functionalFitness`). Full
design: `PRESCRIPTION_RESULT_MODEL_REVIEW.md` §2.

## 3. Do result models need generalization?

**Yes, by the same additive method.** `BlockResult` wraps
`WorkoutResult`/`SetResult`'s existing shape as one case (`.strength`)
alongside new typed siblings (`.steadyState`, `.interval`,
`.functionalFitness`), each with its own named fields rather than shared
nullable properties. Full design: `PRESCRIPTION_RESULT_MODEL_REVIEW.md` §3.

## 4. What `PerformanceProfile` changes are required?

`ExercisePerformanceProfile` is kept exactly as-is. Two new sibling types
are added — `ActivityPerformanceProfile` (running/cycling/rowing-style
history, indexed by `TrainingModality` reused as the activity identity)
and `BenchmarkPerformanceProfile` (named-benchmark history, indexed by a
new `BenchmarkDefinition` catalog, structurally identical to how
`Exercise` already works). A thin shared `PerformanceMetricProfile`
protocol unifies them for cross-cutting queries only. Full design:
`PERFORMANCE_PROFILE_MODALITY_REVIEW.md` §2–4.

## 5. What Functional Fitness abstractions are required?

A full new `FunctionalFitnessProgrammingSystem` with a five-stage
authoring pipeline (Stimulus → Format → Movement slots → Exercise
selection → Stimulus validation), a strict `Stimulus`/`WorkoutFormat`
type separation, a generic `ScoreType`/`ScoreDirection` model with no
inferred defaults, a lightweight `BenchmarkDefinition` entity (not a new
result type), and scaling modeled via existing prescribed-vs-performed
fields, never by overwriting the prescription. Full design:
`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md`.

## 6. What are `ConcurrentScheduler`'s boundaries?

It consumes already-complete `Session`s from one or more
`ProgrammingSystem`s and decides only **placement** (which `Day`, what
order, same-day pairing) — it never generates prescription content, and
it never overrides a `ProgrammingSystem`'s own output. Inputs and outputs
are a fixed, typed contract (`ScheduledProgramInput` /
`TrainingStressProfile` in; `SessionPlacement` + explicit
`SchedulingReasonCode`s out), deliberately free of any hardcoded
universal interference rule, consistent with the concurrent-training
literature's own conditional findings (`PROGRAMMING_SOURCES.md` §5). Full
design: `CONCURRENT_SCHEDULER_MODEL.md`.

## 7. Is `ProgramJourney` compatible with non-hypertrophy modalities?

**Mostly yes, with one required generalization.** A Running journey
(Beginner Run/Walk → Base Running → 5K Development) fits the existing
shape with zero changes. A Hybrid journey (phases that are themselves
concurrent combinations of multiple systems, e.g. "Fat Loss + Functional
Fitness") does not fit the existing `phases: [ProgramDefinition]` typing
— it needs `phases: [PhaseContent]` where `PhaseContent` is `.single` or
`.concurrent`. Full reasoning: `MODALITY_ARCHITECTURE_VALIDATION.md` §3.

## 8. Any other generic-domain changes recommended?

- `SessionRole` enum (Easy/Recovery/Long Run/Tempo/Threshold/Interval/
  Race-specific) as session-level metadata, not a new entity —
  `ENDURANCE_PROGRAMMING_MODEL.md` §8.
- `TrainingStressProfile` as a shared, modality-agnostic vocabulary every
  `ProgrammingSystem` stamps its own output with, consumed uniformly by
  `ConcurrentScheduler` — `CONCURRENT_SCHEDULER_MODEL.md` §2.
- `ProgressionInput`/`ProgressionOutput`'s payload fields generalize from
  strength-specific types to `BlockPrescription`/`BlockResult` — the
  protocol itself is unchanged. Functional Fitness stretches this
  interface further than any other modality (exposure-informed
  generation rather than parametric adjustment) — noted as an honest
  limit, not hidden. `MODALITY_ARCHITECTURE_VALIDATION.md` §5.

## 9. New architectural risks identified

- **The `ProgressionEngine` interface fitting Functional Fitness is
  looser than it fitting every other modality.** Satisfying the protocol
  is not the same as the implementation feeling like a natural fit —
  Stage 4 should not assume a `FunctionalFitnessProgressionEngine` will
  resemble `DoubleProgressionEngine` structurally just because both
  conform to the same protocol.
- **`IntervalLegSpec.target`'s modality coverage is incomplete as
  drafted** — the Running/Bike/Row proof surfaced a missing case
  (rowing's stroke rate/split pace) during validation itself. This is
  evidence the design process works (the gap was caught, not shipped
  silently), but Stage 4 should expect more such gaps as more modalities'
  native units get exercised, and treat `IntensityTarget` as an enum
  that will keep growing cases, not a closed set.
- **Every web-sourced fact in `PROGRAMMING_SOURCES.md` was obtained via
  search-snippet extraction, not direct primary-source fetch** (this
  environment's egress restrictions blocked nhs.uk, britishcycling.org.uk,
  pubmed.ncbi.nlm.nih.gov, and crossfit.com directly). Every number is
  cross-checked across independent snippets and flagged accordingly, but
  none should be treated as verified to the standard Stage 3A's direct
  spreadsheet-cell citations were — re-verify against the live sources
  before shipping any of these as a citable in-app reference or a
  regression fixture.
- **`BenchmarkDefinition`'s catalog-curation process is undesigned.** The
  data shape is validated (§5 of `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md`);
  who authors/approves new benchmarks, and whether user-created benchmarks
  are allowed, is not decided and could affect the catalog's shape later
  (e.g. whether it needs the same alias/moderation machinery `Exercise`
  has, or a lighter one).

## 10. MUST-BEFORE-STAGE-4 vs. CAN-WAIT

| Change | Classification | Why |
|---|---|---|
| `ProgramJourney.phases` generalized to `PhaseContent` (§7 above) | **MUST** | Stage 4 will otherwise build `ProgramJourney`-consuming code against the narrower shape; retrofitting after the fact touches more call sites than fixing it now. |
| `BlockPrescription`/`BlockResult` enum shape adopted as the standard for any non-strength `WorkoutBlock` | **MUST** | Every other change in this document set (Endurance, Functional Fitness, Concurrent Scheduler) assumes this exists; building any one of them without it first would reintroduce exactly the dummy-field/nullable-property smells this validation pass exists to prevent. |
| `TrainingStressProfile` vocabulary defined and required as output from every `ProgrammingSystem` | **MUST** | `ConcurrentScheduler` cannot be built at all without every system already emitting this — it's a producer-side contract that has to exist before the consumer does. |
| `SteadyStateProgrammingSystem`/`IntervalProgrammingSystem` concrete implementation | **CAN WAIT** | The *shape* is validated now (this is the point of Stage 3B); actually building the evaluators is ordinary Stage 4 implementation work, sequenced whenever Endurance is prioritized. |
| `FunctionalFitnessProgrammingSystem` concrete implementation | **CAN WAIT** | Same reasoning — shape validated, implementation sequenced by product priority. |
| `ConcurrentScheduler` concrete implementation (the actual placement algorithm) | **CAN WAIT** | Explicitly out of scope for this pass per the brief; the input/output *contract* is what had to be validated now. |
| `ActivityPerformanceProfile`/`BenchmarkPerformanceProfile` concrete implementation | **CAN WAIT** | No other Stage 3B conclusion depends on these existing yet — they're consumed by future modality work, not by each other. |
| `RunningProgrammingSystem` as a named composer (vs. leaving Running as bare Interval/SteadyState configuration with no named wrapper) | **CAN WAIT** | A product/naming decision with no schema consequence either way — can be added or skipped later without affecting anything else in this document set. |
| Route/distance-benchmark canonical identity | **CAN WAIT (deferred, not merely delayed)** | No source material or product requirement analyzed yet — genuinely undecided, not just unscheduled; needs its own future analysis pass, not a Stage 4 sprint slot. |
| `BenchmarkDefinition` catalog-curation/authoring process | **CAN WAIT** | Data shape validated; the process question doesn't block Stage 4 engine work, only the eventual benchmark-content-authoring workflow. |

**Bottom line for what Stage 4 needs before it starts building *any*
new-modality engine:** the three MUST items above (`ProgramJourney`
generalization, the `BlockPrescription`/`BlockResult` shape, and the
`TrainingStressProfile` contract) are foundational — they're small,
additive, and don't require touching any Stage 1–2/3A code, but Stage 4
should apply them before writing the first `SteadyStateProgrammingSystem`
or `FunctionalFitnessProgrammingSystem` line, not retrofit them after.
Everything else is genuinely sequenceable by product priority.

---

Per the brief's closing instruction: this is a review-gate document.
**No `SteadyStateProgrammingSystem`, `IntervalProgrammingSystem`,
`FunctionalFitnessProgrammingSystem`, `ConcurrentScheduler`, or
`ProgramGenerator` code was written or prototyped in this pass** — every
type shown across this document set is a specification in a markdown code
block, not compiled Swift, and no Xcode build/test cycle was needed
because no Swift file was added to the project. Waiting for
product-owner review before any of this becomes implementation.
