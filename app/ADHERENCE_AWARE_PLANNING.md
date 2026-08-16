# Adherence-Aware Planning

The locked principle this document exists to operationalize:

> A theoretically optimal program that the user does not want to perform
> is not considered practically optimal. But preference must never erase
> major goal incompatibility.

This governs three concrete mechanisms: variety preference, temporary
modality switching, and recommended alternatives — plus one hard
boundary: **no behavioral prediction, ever, in this stage.** §5's
two-stage ranking model is the precise mechanism that makes both halves
of the locked principle true simultaneously: preference can win, but
only among candidates a goal-compatibility gate has already approved.

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

### 2a. No universal hard maximum — but a materiality check (Decision 2, resolved)

A temporary block is never capped at one fixed universal duration. What
it does have, always:

- a start date (`validFrom`),
- an intended review date or duration (`validUntil`, or a duration the
  planner converts to one),
- explicit temporary status — the plain fact that `validUntil != nil`,
  restated here so it's never ambiguous: a mix either has a review date
  (temporary) or it doesn't (stable), and that fact alone is what "explicit
  temporary status" means — no separate flag is needed (§3 below).

TrainingOS may *recommend* a typical review window (e.g. several weeks) —
a single configurable `typicalReviewWindowWeeks` default (TRAININGOS_DESIGNED,
proposed default: 4 weeks, matching `STRATEGIC_PLAN_MODEL.md` §4a's
"transition"/"recovery" row precedent for how illustrative-but-configurable
numbers are handled elsewhere in this design) — never a hard rule the
user cannot exceed.

What TrainingOS does enforce is a **materiality check**, distinct from
the plain expiry prompt (§2's own three-option prompt, which fires
*at* `validUntil`): if a temporary block (including its own renewals) has
run long enough to **materially change the character of the current
strategic phase** — proposed default: cumulative temporary duration
reaches half the enclosing phase's `PhaseDurationKind.range`'s `typical` value
(`STRATEGIC_PLAN_MODEL.md` §4a), or it has been renewed more than once
consecutively without a stable resolution — the next tactical-window
generation surfaces a distinct prompt (reason code
`TEMPORARY_PREFERENCE_MATERIALITY_THRESHOLD`,
`PLAN_REVISION_MODEL.md` §3):

> "This now looks more like a phase change than a temporary training
> block."

with exactly three options, none applied silently:

1. **Continue temporarily** — extend the window again; the materiality
   check simply re-evaluates at the next threshold.
2. **Convert/update the current phase** — the temporary mix's
   composition becomes the phase's own selected mix going forward
   (`validUntil` cleared); routed through `LongTermPlanner.reviseStrategicPlan`
   as a minor revision (`PLAN_REVISION_MODEL.md` §4), never a silent
   mutation.
3. **Re-plan the remaining roadmap** — treated as a full revision
   (`PLAN_REVISION_MODEL.md` §4/§5, scaled to whichever is actually
   warranted — extending/reshaping the current phase is a minor revision;
   only an actual long-term-goal change supersedes the whole plan).

The materiality threshold's exact numbers are TRAININGOS_DESIGNED and
configurable, exactly like every other duration default in this design —
never a claim of validated science, and never applied as an automatic
conversion.

## 3. Stable preference vs. temporary desire — the same field distinguishes both

§50 asks these to be distinguished, not merged. They already are, by one
field:

| | `validUntil` | Example |
|---|---|---|
| Stable preference | `nil` | "I generally prefer cycling to running" — captured in `Goal.preferences?.preferredModalities` (`STRATEGIC_PLAN_MODEL.md` §1b/1d), which shapes every `proposeTrainingMix` call going forward |
| Temporary desire | set | "I want CrossFit this month" — a bounded `TrainingMix` window, §2 above |

A temporary desire never silently becomes a stable preference (§50's own
instruction) — the *only* paths from one to the other are the user
explicitly choosing option 2 in §2's expiry prompt, or option 2 in §2a's
materiality-check prompt. Both are distinct, logged `PlannerDecision`s,
never an implicit default.

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

## 5. Recommended alternatives — a two-stage ranking model (Decision 3, resolved)

**Preference/adherence CAN promote an alternative above the
highest-`GoalAlignment` candidate into the top `.recommended` slot** —
this is now a core, locked TrainingOS principle: *"A theoretically
superior plan that the user strongly does not want to perform is not
necessarily the best practical recommendation."* This reverses this
document's own earlier draft position (strict alignment-only ranking),
per explicit product-owner decision. It is bounded, never unconstrained:
preference can reorder among candidates that already clear a goal-
compatibility gate; it can never promote a candidate that doesn't.

```swift
enum CandidateMixRole: String, CaseIterable {
    case recommended            // top of the ranked list AFTER §5b's promotion step
    case bestGoalAlignment       // the single highest-GoalAlignment candidate —
                                  // ALWAYS shown, even when a promotion means it
                                  // isn't also `.recommended`
    case bestVarietyAlternative
    case userPreferenceAlternative
}

struct CandidateTrainingMix {
    var mix: TrainingMix              // kind == .recommended, transient until accepted
    var roles: Set<CandidateMixRole>  // a candidate may carry more than one role at once
                                       // (e.g. {.recommended, .bestGoalAlignment} when
                                       // nothing was promoted)
    var alignment: GoalAlignment      // Stage 4G, unmodified — §6 below
    var reasonCodes: [PlannerReasonCode]
}
```

### 5a. Stage one — the compatibility gate

Only candidates whose `GoalAlignment.rating` is **`.acceptable` or
higher** (a single TRAININGOS_DESIGNED, configurable threshold —
`compatibilityThreshold`) are eligible for promotion at all. A `.poor`-
or `.infeasible`-rated candidate can never become `.recommended`,
regardless of how strongly it matches stated preference — this is the
exact guarantee that stops "preference erasing major goal
incompatibility" (the locked instruction). `.poor` candidates may still
be *shown* (as a plain alternative, correctly labeled Poor Fit,
`PROGRAM_RECOMMENDATION_MODEL.md` §2a) — they are simply never the
recommended one.

### 5b. Stage two — preference-based promotion among compatible candidates

Among candidates that clear the gate, a candidate is **preference-aligned**
(a plain boolean, not a fabricated score) when:

- it contains **zero** components whose modality is in
  `Goal.preferences?.dislikedModalities`, **and**
- it contains **at least one** component whose modality is in
  `preferredModalities`, **and**
- when `varietyPreference == .high`, it represents strictly more
  distinct `ProgrammingSystemKind`s than the best-`GoalAlignment`
  candidate.

A preference-aligned candidate is promoted to `.recommended` when its
`GoalAlignmentRating` is no more than `maxPromotableTierGap` tiers below
the best-`GoalAlignment` compatible candidate's rating — proposed
default **1 tier** (e.g. `.good` is promotable over an `.excellent` best;
`.acceptable` is not, when the best is `.excellent`). Both the boolean
gate and the tier-gap number are structured, deterministic, and
transparent — no numeric score is invented anywhere in this computation.
When a promotion happens:

- The promoted candidate is tagged `.recommended` plus reason code
  `ADHERENCE_PREFERENCE_PROMOTED_ALTERNATIVE` (`PLAN_REVISION_MODEL.md`
  §3).
- The candidate that would have been `.recommended` absent promotion
  (the best-`GoalAlignment` compatible candidate) is always still
  surfaced, tagged `.bestGoalAlignment` — never hidden, per the locked
  requirement that "Best Physiological Match" and "Recommended For You"
  remain visibly distinct when they differ.

### 5c. Result set — still 2-3 paths, never dozens

`proposeTrainingMix` returns at most 3-4 entries: `.recommended` (post-
promotion), `.bestGoalAlignment` (only shown separately when it differs
from `.recommended`), and at most one each of `.bestVarietyAlternative`/
`.userPreferenceAlternative` when either is a genuinely different
composition from what's already shown (§24's "do not generate dozens of
choices"). A user's own already-selected mix is always evaluated
alongside this list as a distinct, always-present option — it is never
*competing* to be recommended, it is simply respected
(`LONG_TERM_PLANNER.md` §1).

### 5d. Worked example (matches the product-owner decision exactly)

- Candidate A — 5-Day Hypertrophy + 2 Zone 2: `.excellent` alignment, not
  preference-aligned (no representation of a preferred variety modality).
- Candidate B — 3 Strength + 2 Functional Fitness + 1 Run: `.good`
  alignment (one tier below A), preference-aligned (matches stated
  variety preference, no disliked modality).
- Candidate C (hypothetical) — a `.poor`-alignment, strongly
  preference-aligned mix: **never promotable**, gated out at 5a
  regardless of how strongly it matches preference.

Result: B is promoted to `.recommended` (tier gap from A is 1, within
`maxPromotableTierGap`); A is still shown, tagged `.bestGoalAlignment`.
Display copy (generated from structured roles/reason codes, never the
source of truth itself):

> **Recommended for you** — 3 Strength + 2 Functional Fitness + 1 Run.
> Still supports your muscle-gain objective well, matches your stated
> preference for more variety, more likely to be a plan you'll actually
> follow.
>
> **Best pure goal alignment** — 5-Day Hypertrophy + 2 Zone 2. Strongest
> hypertrophy-specific alignment; lower variety.

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
implementation. §5a/§5b's compatibility gate and tier-gap comparison both
use `GoalAlignmentRating`'s own existing `Comparable` ordering directly —
no second ranking mechanism is introduced.

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
