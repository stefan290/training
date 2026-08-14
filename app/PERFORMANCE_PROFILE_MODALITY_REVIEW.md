# Performance Profile Modality Review

Stage 3B stress test of `PerformanceProfile`/`ExercisePerformanceProfile`
against non-strength modalities. Per explicit instruction, this document
does **not** remove `ExercisePerformanceProfile` — it determines what, if
anything, needs to sit alongside it.

## 1. The stress test

`PerformanceProfile` must remain cross-program and permanent (locked
invariant, `CLAUDE.md` rule 1) and must index performance for four
different kinds of "thing a user has a history of":

| Kind | Example | Indexed by |
|---|---|---|
| Exercise | Bench Press | Canonical `Exercise` ID (existing) |
| Activity | 5 km run | An activity/modality identity that doesn't exist yet |
| Benchmark | Fran | `BenchmarkDefinition.canonicalID` (`FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §5) |
| Physiological/conditioning trend | interval pace or cycling power over time | Not a single "thing" at all — a trend derived across many logged results, not one canonical entity |

The last row is the one genuinely different case: "how has my 4×4 interval
pace changed over the last 3 months" isn't performance-on-a-thing, it's a
computed trend over a filtered result set. This distinction matters for
the design below.

## 2. Proposed shape: sibling profile types under a thin shared protocol

**`ExercisePerformanceProfile` is unchanged.** Two new siblings are added:

```
protocol PerformanceMetricProfile {
    associatedtype Metric
    var history: [DatedResult<Metric>] { get }
    var personalRecords: [PersonalRecord] { get }
}

// UNCHANGED from Stage 1-2:
final class ExercisePerformanceProfile: PerformanceMetricProfile {
    // existing implementation, existing fields — Metric = strength load/reps
}

// NEW:
final class ActivityPerformanceProfile: PerformanceMetricProfile {
    let activityType: ActivityType          // see §3
    // Metric = whatever's meaningful for that activity — pace for running,
    // power for cycling — a typed value per ActivityType, not a generic Double
    var history: [DatedResult<ActivityMetric>]
    var personalRecords: [PersonalRecord]    // e.g. fastest 5km, longest Zone 2 ride
}

// NEW:
final class BenchmarkPerformanceProfile: PerformanceMetricProfile {
    let benchmark: BenchmarkDefinition
    var history: [DatedResult<ScoreValue>]   // ScoreValue from PRESCRIPTION_RESULT_MODEL_REVIEW.md §4
    var personalRecords: [PersonalRecord]     // best time/rounds+reps/load for this specific benchmark
}
```

**Why a thin shared protocol, not one generic `PerformanceMetric`
class:** per the brief's §44 discipline, a single generic profile type
would need `Metric` to be something like `[String: Double]` to
accommodate strength load, running pace, and Fran's time simultaneously —
exactly the "unstructured generic data" the brief prohibits. The protocol
exists only so cross-cutting UI/query code ("show me all this user's
tracked PRs across every modality") can operate generically over
`[any PerformanceMetricProfile]` without each concrete type sacrificing
its own strong typing internally. This mirrors the existing
`ProgressionEngine` pattern exactly: one protocol, several concrete,
strongly-typed implementations, chosen deliberately over one type trying
to serve every case.

## 3. Physiological/conditioning trends — not a new profile type

The fourth row of §1's table ("interval pace or cycling power over time")
is **not** modeled as its own `PerformanceMetricProfile` conformer.
`ActivityPerformanceProfile.history` (§2) already contains every dated
result for that activity; a "trend" is a query/derived view over that
existing history (e.g. "average pace per calendar month, last 6 months"),
not a new persisted entity. Adding a fourth profile type for trends would
duplicate data `ActivityPerformanceProfile` already owns — flagged here
explicitly as a considered-and-rejected option, not an oversight.

## 4. Canonical identity — `ActivityType` and `BenchmarkDefinition`

Per Stage 3B §37, strength's canonical-Exercise-ID pattern needs
equivalents for two different kinds of identity, and they are **not the
same shape**:

- **`ActivityType`** — a small, closed set (running, cycling, rowing,
  ski-erg — the same handful of values `TrainingModality` already
  enumerates from Stage 1–2). Proposed: **reuse `TrainingModality`
  directly as the identity**, rather than introducing a parallel
  `ActivityType` enum/catalog. Two closed enums covering the same small,
  stable set of things would be a duplicate-identity smell of exactly the
  kind this validation pass exists to catch — there's no evidence a
  separate `ActivityType` needs to vary independently of `TrainingModality`.
- **`BenchmarkDefinition`** — an open, community-extensible catalog (RP
  doesn't name benchmarks, but CrossFit has dozens — Fran, Murph, Grace,
  and so on, plus user/gym-authored ones), structurally identical to how
  `Exercise` is already an open, catalog-backed canonical identity with
  its own `ExerciseAlias` resolution (Stage 1–2). Proposed: reuse that
  exact pattern — a `BenchmarkDefinition` catalog with a
  `BenchmarkAlias`-equivalent for name-variant resolution (e.g. "Fran" vs.
  "the Fran benchmark" vs. regional spelling variants), rather than
  inventing a new resolution mechanism.
- **Route/distance-benchmark types** (e.g. "my usual 5K route," a
  location-specific PR) — genuinely no source material or existing
  product need analyzed in this pass. Per the standing rule against
  inventing ambiguous logic (`CLAUDE.md` rule 10), this is flagged as an
  **open question, deferred**, not solved — see
  `STAGE3B_ARCHITECTURE_DECISIONS.md`.

## 5. Continuity across programs — confirmed unaffected

The one non-negotiable check this document must pass: does anything here
risk `PerformanceProfile` losing history across a program change (the
single most important locked invariant from Stage 1–2, re-confirmed as a
Stage 3B smell to flag in §43 of the brief)? **No** —
`ActivityPerformanceProfile` and `BenchmarkPerformanceProfile` are new
siblings with the exact same "permanent, program-independent" contract
`ExercisePerformanceProfile` already has; nothing about adding new profile
*types* changes how any profile relates to `ProgramDefinition`/
`ProgramInstance` lifecycle (still zero relationship in that direction,
per the existing delete-rule invariant). A user switching from a
Hypertrophy program to a Running journey keeps every `ExercisePerformanceProfile`
they had, and starts accumulating `ActivityPerformanceProfile` history
that similarly survives any future program change.

## 6. What this document does not decide

- **The concrete `ActivityMetric` type per activity** (pace vs. power vs.
  stroke rate) — sketched conceptually in §2; the exact value types are
  `PRESCRIPTION_RESULT_MODEL_REVIEW.md`/`ENDURANCE_PROGRAMMING_MODEL.md`
  territory, not repeated here.
- **Route/distance-benchmark identity** — explicitly deferred, §4.
- **UI/query surface for the shared `PerformanceMetricProfile` protocol**
  — a product/UI decision, not a data-model one.
