# Adherence-Aware Planning

The locked principle this document exists to operationalize:

> A theoretically optimal program that the user does not want to perform
> is not considered practically optimal.

This governs three concrete mechanisms: variety preference, temporary
modality switching, and recommended alternatives — plus one hard
boundary: **no behavioral prediction, ever, in this stage.**

## 1. `VarietyPreference` — a stated input, not a prediction

```swift
enum VarietyPreference: String, Codable, CaseIterable {
    case low
    case moderate  // default
    case high
}
```

Read only when generating `[CandidateTrainingMix]` (§3) — it never adds
randomness anywhere. `LongTermPlanner` never calls anything equivalent to
`Math.random()`/reads the system clock as an implicit input, exactly
matching `ConcurrentScheduler`'s own determinism discipline (CLAUDE.md
rule 4, extended here): the same `LongTermGoal` (including the same
stated `varietyPreference`) always produces the same ranked candidate
list. A higher variety preference does not change training "randomly for
novelty" (§13's own instruction) — it changes which *deterministically
generated* alternative gets surfaced and how prominently, never invents
an alternative that wouldn't already have been a valid, goal-constrained
candidate.

## 2. Temporary modality switching — already-existing schema, no new type

§14/§15's "I want Functional Fitness for the next 4 weeks" requires no
new persisted type at all. `TrainingMix.validFrom`/`.validUntil` (Stage
4F, previously declared but not yet given real behavior) is exactly a
temporary preference block: a `.selected` `TrainingMix` with a bounded
window applies without touching the enclosing `TrainingPlan`/
`TrainingPhase` — precisely what Stage 4F's own doc comment already
promised ("CrossFit for the next 4 weeks... without touching the
enclosing TrainingPlan/TrainingPhase at all").

What Stage 5A adds is the **behavior** around expiry, since Stage 4F
only declared the fields:

- While `validUntil` is in the future (or `nil`), the temporary mix is
  simply the phase's `selectedTrainingMix` — `ConcurrentScheduler`
  schedules it exactly as it would any other selected mix, with the
  usual `userSelectedMix` reason code.
- When a tactical window is generated (`TACTICAL_PLANNING_HANDOFF.md`)
  and `selectedTrainingMix.validUntil` has passed, the planner surfaces a
  `PlannerDecision` (reason code `TEMPORARY_PREFERENCE_EXPIRED`) with
  exactly the three options §15 names — **never auto-reverts**:
  1. Return to the phase's `.recommended` mix.
  2. Continue the current modality (creates a new `.selected` mix with
     `validUntil == nil` — see §3 below, this is the one explicit path
     that promotes a temporary desire into a stable preference).
  3. Choose another path (re-run `proposeTrainingMix`).

No new engine concept, no new schema — the only change from Stage 4F is
that `validUntil` now has defined consumers.

## 3. Stable preference vs. temporary desire — the same field distinguishes both

§50 asks these to be distinguished, not merged. They already are, by one
field:

| | `validUntil` | Example |
|---|---|---|
| Stable preference | `nil` | "I generally prefer cycling to running" — captured in `LongTermGoal.preferredModalities` (`STRATEGIC_PLAN_MODEL.md` §1b), which shapes every `proposeTrainingMix` call going forward |
| Temporary desire | set | "I want CrossFit this month" — a bounded `TrainingMix` window, §2 above |

A temporary desire never silently becomes a stable preference (§50's own
instruction) — the *only* path from one to the other is the user
explicitly choosing option 2 in §2's expiry prompt, which is a distinct,
logged `PlannerDecision`, not an implicit default.

## 4. The adherence-signal boundary — explicit intent only, no ML

Stage 5A specifies boundaries, not an adaptive algorithm. Permitted
inputs to any planner reasoning are only:

- Explicit stated preference (`LongTermGoal` fields, temporary mix
  windows) — always literal user input.
- Observable completion facts already recorded by existing systems:
  `Session.status` (scheduled/completed/skipped/missed),
  `SlotSelectionOverride`/`ActivitySelectionOverride` history (repeated
  substitutions), and `ScheduleIssue`s accumulated across tactical
  windows (`.requiredFrequencyUnsatisfied` recurring, e.g.).

**Explicitly out of scope, this stage and until separately requested**
(CLAUDE.md rule 11): any model that infers *why* a pattern occurred, any
prediction of future adherence probability, and any machine-learning
component of any kind. Where a signal from the list above triggers a
planner recommendation (`PHASE_PLANNING_RULES.md` §6's missed-progress
handling), that recommendation is always a `PlannerDecision`-backed
proposal requiring approval (§5 of `LONG_TERM_PLANNER.md`'s
non-mutating-proposal pattern) — never a silent, autonomous plan change.
A future version may learn preferences; this one only records and
responds to what the user explicitly says and what actually happened.

## 5. Recommended alternatives — 2-3 paths, never dozens

```swift
enum CandidateMixRole: String, CaseIterable {
    case recommended
    case bestVarietyAlternative
    case userPreferenceAlternative
}

struct CandidateTrainingMix {
    var mix: TrainingMix              // kind == .recommended, transient until accepted
    var role: CandidateMixRole
    var alignment: GoalAlignment      // Stage 4G, unmodified — §6 below
    var reasonCodes: [PlannerReasonCode]
}
```

`proposeTrainingMix` returns at most 3: the best-`GoalAlignment` mix
(`.recommended`), the best-alignment mix among those with materially more
modality variety (`.bestVarietyAlternative`, present only when it's
genuinely a different composition, not a near-duplicate — omitted
otherwise, per §24's "do not generate dozens of choices"), and the
closest-to-stated-preference mix (`.userPreferenceAlternative`, present
only when it differs from `.recommended`). A user's own already-selected
mix is always evaluated as a fourth, always-present option outside this
ranked list — it is never *competing* to be recommended, it is simply
respected (`LONG_TERM_PLANNER.md` §1).

## 6. Using `GoalAlignment` as-is — no new scoring system

Every `alignment: GoalAlignment` above comes from the exact, unmodified
Stage 4G `GoalAlignmentEvaluator.evaluate(mix:proposal:)` — computed
against a representative `ScheduleProposal` for that candidate mix (a
`SchedulingPipeline.propose` call using the goal's coarse availability
fields as a stand-in `UserAvailability` for comparison purposes only,
never persisted as if it were the real tactical-time availability). §23's
own instruction ("do not reimplement another alignment system") is
satisfied by construction — there is only one alignment system in this
codebase, and the planner is a new *caller* of it, not a new
implementation.

## 7. No punitive UX — a structural guarantee, not just a style rule

§63/§64 ask that choosing a valid alternative modality never reads as
failure. This is enforced two ways:

1. **Every `PlannerReasonCode`** (`PLAN_REVISION_MODEL.md` §3) is named
   neutrally — `USER_SELECTED_ALTERNATIVE`, `VARIETY_PREFERENCE_APPLIED`,
   never anything implying error or loss. A reason-code vocabulary with
   no punitive code in it structurally cannot produce punitive
   *structured* output.
2. **Display copy** (any future UI's explanation text, generated from
   `reasonCodes`/`factors`, never the reverse — CLAUDE.md rule 16's
   discipline extended to planning explanations) must render a lower
   `GoalAlignmentRating` as a tradeoff ("slightly lower goal alignment for
   maximum hypertrophy, higher training variety," §63's own example),
   never as "off track" or "ruined." This is a content guideline for
   whichever layer generates that text, not something the type system
   alone can guarantee — flagged as a UI-implementation instruction to
   carry forward, not a Stage 5A code deliverable.
