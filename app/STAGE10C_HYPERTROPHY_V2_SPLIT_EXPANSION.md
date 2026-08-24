# Stage 10C — Hypertrophy V2 Frequency/Split Expansion

**STATUS: DESIGN/AUDIT ONLY. No production code changed.** Extends the
now-approved, now-committed Hypertrophy V2 architecture
(`STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md`) beyond its current
3-Day Full Body-only scope. Every fact below was read directly from the
repository, not assumed — cited by file/function. Nothing here is
implemented; no `HypertrophyBuiltInLibrary`/`HypertrophyProgramGenerator`/
`LongTermPlanner` code was touched.

---

## 1. Current supported hypertrophy configurations

`HypertrophyBuiltInLibrary.all` (`HypertrophyBuiltInLibrary.swift:16-23`)
— exactly 6, no more, none invented:

| # | Name | dayCount | split |
|---|---|---|---|
| 1 | 3-Day Full Body Hypertrophy | 3 | `.fullBody` |
| 2 | 4-Day Full Body Hypertrophy | 4 | `.fullBody` |
| 3 | 5-Day Full Body Hypertrophy | 5 | `.fullBody` |
| 4 | 5-Day Upper/Arms Focus | 5 | `.armsShoulders` |
| 5 | 4-Day Lower/Leg Focus | 4 | `.legs` |
| 6 | 6-Day High-Frequency Hypertrophy | 6 | `.fullBody` |

## 2. Legacy vs. V2 matrix

| Config | Engine today | Real `ProgramDefinition` generator | Recommended by any real Mix | Reachable/selectable in production today | Special legacy assumptions |
|---|---|---|---|---|---|
| 3-Day Full Body | **Hypertrophy V2** | `generateDayFocusDriven` | No (alternative, "Strength Plus Variety") | Yes — real, selectable, verified end-to-end | None — this is the reference config |
| 4-Day Full Body | Legacy Family A | `generateLegacyFixedPair` | No mix requests target 4 today | **Not reachable from any current real Mix** (exists in the library, technically the tie-break winner if a target-4 request ever occurred — see §3 — but nothing asks for one) | 1 primary + 1 paired-accessory slot/day |
| 5-Day Full Body | Legacy Family A | `generateLegacyFixedPair` | **Yes — `.muscleGain`'s own `.recommended` default** ("Focused Hypertrophy") | Yes, and it's the DEFAULT for a new Muscle Gain user | 1 primary + 1 paired-accessory slot/day |
| 5-Day Upper/Arms Focus | Legacy Family A | `generateLegacyFixedPair` | No | **Never actually selected** — always loses its own exact-dayCount tie to "5-Day Full Body" alphabetically (§3) | 1 primary + 1 paired-accessory slot/day |
| 4-Day Lower/Leg Focus | Legacy Family A | `generateLegacyFixedPair` | No | **Never actually selected** — same alphabetical-tie loss against "4-Day Full Body" | 1 primary + 1 paired-accessory slot/day |
| 6-Day High-Frequency | Legacy Family A | `generateLegacyFixedPair` | No mix requests target 6 today | Not reachable from any current real Mix | 1 primary + 1 paired-accessory slot/day |

`ProgramCapabilityRegistry.canInstantiate` for `.hypertrophy` is simply
`configuration.dayCount > 0` — **no per-config gating exists at all**;
every one of the 6 is always instantiable. The "programAvailabilityMatch"
fit factor is identical (`true`) for all 6, since `curatedCount = 6` is
a flat constant — fit-scoring cannot and does not discriminate between
configs by anything except day-count distance (§3).

## 3. Reachability mechanics (why 2 of the 6 configs are structurally dead)

`LongTermPlanner.closestByDayCount` (`LongTermPlanner.swift:1175-1186`):
exact-match first, else smallest `abs(dayCount - target)`, else
alphabetical name — top 2 candidates kept, both scored by `fitFactors`,
which has **no day-count-proximity factor of its own** (`fitFactors`,
lines 1224-1265 — `availabilityMatch` only checks `dayCount <=
availability.trainingDaysPerWeek`, true for both candidates in every
observed case). Since the top-2 pair from `closestByDayCount` therefore
score identically on every fit factor whenever neither exceeds
availability, **the final tie-break is always the alphabetical name
comparison in `proposeProgram`'s own sort** (`candidates.sort`, line
1092-1095).

Consequence, confirmed by direct computation against the 6 real
dayCounts `[3,4,5,5,4,6]`:

- target 4: "4-Day Full Body" vs. "4-Day Lower/Leg Focus" tie at
  distance 0 → **"Full Body" wins** (F < L). Lower/Leg Focus can never
  win.
- target 5: "5-Day Full Body" vs. "5-Day Upper/Arms Focus" tie at
  distance 0 → **"Full Body" wins** (F < U). Upper/Arms Focus can
  never win.
- target 2: nearest is distance 1 ("3-Day Full Body" — no 2-day config
  exists at all).
- target 6: exact match, no tie ("6-Day High-Frequency").

**This is a pre-existing characteristic of the current ranking
mechanism, not something Stage 10C is asked to fix** — flagged for
awareness (§26), not touched here.

## 4. Which frequencies are actually requested by any real Mix today

Every `TrainingMix` with a `.hypertrophy` component
(`LongTermPlanner.swift`, full survey):

| Mix | Goal | Hypertrophy target | Priority | Other components |
|---|---|---|---|---|
| "Focused Hypertrophy" (802-813) | `.muscleGain` | 5 | primary | Zone 2 Conditioning, target 2 |
| "Strength Plus Variety" (817-832) | `.muscleGain` | 3 | primary | Functional Fitness 2, Running 1 |
| "Conditioning-Focused Fat Loss" (837-852) | `.fatLoss` | 3, min 2, `.required` | **secondary** | Interval 3 (primary), Easy Aerobic 1 |
| "Varied Fat Loss" (854-865) | `.fatLoss` | 2, min 2, `.required` | **secondary** | Functional Fitness 3 (primary) |
| "Endurance-Focused" (887-898) | `.enduranceEvent` | 2 | **supporting** ("Strength Maintenance") | primary endurance activity, target 5 |
| "Endurance-Varied" (900-915) | `.enduranceEvent` | 1 | **supporting** ("Strength Maintenance") | steadyState 3, interval 2 |
| `maintenanceMix` (670-799) | any (phase transition) | derived: `previous >= 3 ? 2 : max(1, previous)` | inherited | whatever the prior phase had |

**Only targets 5, 3, 2, and 1 are ever actually requested.** No real Mix
requests 4 or 6. This means dayCounts 4 and 6 in the library are
presently unreachable in two separate senses: their own exact-match
tie-break loses (§3), *and* nothing ever asks for that target anyway.

**Critical, load-bearing fact for the recommendation question (§18):**
targets 2 and 1 are **always** secondary/supporting roles inside a
larger, non-hypertrophy-primary program (Fat Loss, Endurance
maintenance) — never someone's dedicated hypertrophy focus. Target 5
is the one real primary Muscle Gain default. Target 3 is Muscle Gain's
real, selectable, non-default alternative (already V2). This is not
"5 splits of decreasing size" — it's two structurally different
product situations: **a primary hypertrophy block** (3 or 5) vs. **a
minimal strength-maintenance dose riding alongside a different primary
goal** (1 or 2).

## 5. Recommended V2 split per frequency (proposals, not automatic clones of 3-Day)

| Frequency | Product situation | Proposed structure | Reasoning |
|---|---|---|---|
| **1/week** (maintenance, supporting) | Riding alongside Endurance | **One broad Full Body day**, structurally identical in *kind* to the existing Day C (a single session whose primary tier already spans 6 muscle groups) | Day C already proves this shape works within the existing generator; no new mechanism needed, just reuse it as the sole day |
| **2/week** (maintenance/secondary, Fat Loss/Endurance) | Two-day maintenance dose | **Full Body A / Full Body B**, a new 2-tier rotation table (same mechanism as `threeDayFullBodyRotation`, 2 entries instead of 3) | User's own example; matches the existing "both-day exposure for major groups" pattern; no split concept needs inventing |
| **3/week** (primary, already built) | Muscle Gain primary alternative | **Unchanged — Day A/B/C** | Already implemented, tested, accepted |
| **4/week** (currently unreachable from any Mix, but library-present) | Would become primary if ever wired to a Mix | **Upper/Lower/Upper/Lower** — the standard, coherent 4-day hypertrophy structure | Rejected the library's own "Lower/Leg Focus" name as the model — a single-emphasis 4-day split is a narrower, different product idea than a balanced 4-day hypertrophy program, and nothing in the repository's real Mixes ever asks for a legs-emphasis config. **However — see §12 — the current exercise catalog cannot yet support 2 genuinely distinct Upper days without repeating the same back/shoulder movement in both.** Flagged as a real gate before this frequency should be built at all. |
| **5/week** (primary, currently reachable, currently the Muscle Gain default) | Muscle Gain primary default | **Upper/Lower/Push/Pull/Legs**, exactly the user's own example | Standard, well-understood structure; **same catalog-variety gate as 4-day applies, more severely** (§12) — this is the highest-priority frequency to eventually convert (it's the actual default), but also the one the current catalog is least ready for |
| **6/week** (library-present, unreachable from any Mix) | Not currently anyone's real program | **Defer entirely.** No real Mix requests it; building it now would be speculative work with zero current reachability | Matches "only if actually supported in the repository" — it exists as a named config, but nothing routes to it |

**None of the above is approved — §26 lists every decision point.**

## 6. Session-role model per split

Reuses `SlotRole` (primary/secondary/accessory) unchanged for every
split — it is a plain, day-focus-agnostic field
(`SlotRole.swift`; `PrescriptionTemplate.slotRole`). What changes per
split is **which muscle groups occupy which tier on which day**, i.e. a
new `[HypertrophyDayFocus]`-shaped rotation table per split, exactly the
existing `threeDayFullBodyRotation` shape (`HypertrophyProgramGenerator.swift:337-350`),
never a new mechanism:

- **Full Body A/B (2-day)**: each day's primary tier covers roughly half
  the 9 tracked groups, secondary the other half, so both days still
  touch nearly everything (matching the user's "both-day exposure"
  framing) — exact tier assignment is a decision point (§26), not
  invented here.
- **Upper/Lower (4-day)**: Upper days' primary/secondary tiers are
  chest/back/shoulders/arms; Lower days' are quads/hamstrings/glutes/
  calves. Accessory tier still carries biceps/triceps/calves as
  appropriate per day, same pattern as today.
- **Upper/Lower/Push/Pull/Legs (5-day)**: Push's primary is chest/
  shoulders/triceps-adjacent groups (triceps still an accessory slot,
  per the existing "no compound/isolation as a domain concept" rule);
  Pull's primary is back/biceps-adjacent; Legs' primary is quads/
  hamstrings/glutes/calves. This is the closest of all the new splits
  to actual product convention, but also the one needing the most
  distinct movement variety (§12).

## 7. Weekly muscle exposure maps (intent, not invented exact numbers)

| Split | chest | back | quad | ham | glute | shoulder | biceps | triceps | calves |
|---|---|---|---|---|---|---|---|---|---|
| 1-Day Full Body | 1× | 1× | 1× | 1× | 1× | 1× | 1× | 1× | maybe 1× |
| 2-Day Full Body A/B | 1-2× (both days may touch it) | 1-2× | 1-2× | 1-2× | 1-2× | 1-2× | 1-2× | 1-2× | 1× |
| 3-Day (existing, approved) | 3× | 3× | 3× | 3× | 3× | 3× | 3× | 3× | 2× |
| 4-Day Upper/Lower | ~2× (both Upper days) | ~2× | ~2× (both Lower days) | ~2× | ~2× | ~2× | ~2× | ~2× | ~2× |
| 5-Day U/L/Push/Pull/Legs | ~2× (Upper + Push) | ~2× (Upper + Pull) | ~1-2× (Lower + Legs, if distinct) | ~1-2× | ~1-2× | ~2-3× (Upper+Push, sometimes Pull rear-delt work) | ~2× (Upper+Pull) | ~2× (Upper+Push) | ~1-2× |

Exact numbers are explicitly **not** claimed as scientifically derived
— they follow directly from how many days each muscle group's tier
appears across the proposed rotation, the same "policy, not derived
science" discipline `expectedWeeklyExposure` already uses for the 3-Day
config (`HypertrophyProgramGenerator.swift:363-379`) — that dict's own
values are calibrated specifically to a 3-exposure/3-day cadence and
are **not** directly reusable unchanged; each new frequency needs its
own analogous table, a real (small) implementation item, not free.

## 8. Likely session size

The existing Day A/B/C reference sits at **7 exercises/day** — the
proven ceiling this repository has actually shipped and accepted. The
design principle for every new split: **grow weekly volume by adding
more, smaller, more focused sessions — never by repeating the same
7-exercise full-body template more times per week.**

| Split | Estimated exercises/session | Why |
|---|---|---|
| 1-Day Full Body | ~7 (same as Day C) | Single day must still cover everything |
| 2-Day Full Body A/B | ~6-7 each | Still whole-body per day, similar to today |
| 4-Day Upper/Lower | ~5-6 each | Each day covers HALF the muscle groups, needs fewer slots |
| 5-Day U/L/P/P/L | ~4-5 each | Each day covers an even narrower slice |

This directly answers §10's "5×7 exercises = absurd volume" concern:
because each Upper/Lower/Push/Pull/Legs day trains fewer muscle groups
than a full-body day, its own slot count should be smaller, not equal —
the day-focus generator already computes slot count as an *output* of
`groupMuscleGroups` on that day's own tier lists (`HypertrophyProgramGenerator.swift:442-458`),
so this falls out naturally from correctly-scoped per-day tier lists,
**without inventing a global `maxExercises` constant** and without any
MEV/MAV/MRV volume-landmark model.

## 9. SlotRole usage

Confirmed generic and already-shipped: `SlotRole` is a plain 3-case
enum with zero rotation-specific logic; every split reuses it
identically. No changes needed to this type for Stage 10C.

## 10. Exercise-intent model

`ExerciseSlot.allowedTargets`/`allowedMovementFunctions` — confirmed
generic (Stage 4C/4E infrastructure, reused unmodified by Stage 10B) —
and `movementPatternGroupings`
(`HypertrophyProgramGenerator.swift:417-421`, exactly 3 entries: Squat
Pattern, Horizontal Push, Hinge Pattern) is **not specific to the
3-day rotation** — it's a flat, reusable lookup table consumed by
`groupMuscleGroups`/`movementFunctionIntent`, already proven to work
for any tier list passed to it. New splits reuse this exact table
unchanged; only the day-focus *tier assignments* (which groups appear
on which day) are new per split.

## 11. Exercise continuity

Progression history is scoped per-Exercise via
`DoubleProgressionHistoryResolver` (Stage 10B.6), never per-slot or
per-`ProgramInstance` — this already generalizes correctly to any
split with **zero changes**: if a movement recurs on multiple days in
a week (e.g. a Push day's Bench Press and an Upper day's Bench Press,
should a 5-day split ever reuse the same movement twice), its
performance history is naturally shared and consistent, exactly as
already proven for the 3-Day config's own repeated exercises (Back
Squat legitimately appears on 2 of its 3 days today — confirmed
directly in this stage's own end-to-end test work). The open design
question is not "does progression handle repetition" (it already does,
correctly) — it's **whether a new split's rotation table should
deliberately vary the resolved exercise across repeated exposures of
the same muscle group** (§12), which is a slot-*design* decision, not a
progression-engine capability gap.

## 12. Exercise variety policy — the real gating constraint

**This is the single most important finding for Stage 10C's own
sequencing.** The actual `ExerciseCatalog.swift` content (31 entries
total, most tagged `.functionalFitness` modality and not eligible
strength candidates) leaves the *usable-for-hypertrophy* pool at:

| Movement pattern | Real candidates today |
|---|---|
| Horizontal push (chest) | 2 (Barbell Bench Press, Incline Dumbbell Press) |
| Vertical/horizontal pull (back) | **1** (Barbell Row — every other `.back`-tagged exercise, e.g. Pull-up/Deadlift, is `.functionalFitness` modality, not a strength candidate) |
| Squat pattern (quad) | 4 (Back Squat, Front Squat, Leg Press, Bulgarian Split Squat) |
| Hinge (hamstring/glute) | 4 (Romanian Deadlift, Conventional Deadlift, Leg Curl, Seated Leg Curl — 2 hinge, 2 knee-flexion) |
| Calf | 2 (Calf Raise, Seated Calf Raise) |
| Shoulder isolation | **1** (Dumbbell Lateral Raise) |
| Biceps isolation | 1 (Barbell Curl) |
| Triceps isolation | 1 (Cable Triceps Pushdown) |
| Overhead press (compound) | **0** |
| Lat pulldown / seated cable row (a second real back option) | **0** |

**Concrete consequence:** a 4-day Upper/Lower split needs 2 *distinct*
Upper days. With only 1 real back exercise and 1 real shoulder
isolation exercise, both Upper days would be forced to repeat Barbell
Row and Dumbbell Lateral Raise identically — **exactly the
"overusing the same movement" danger Stage 10B's own audit already
flagged**, this time structural (no variety exists to avoid it), not a
generator bug. A 5-day Push/Pull/Legs split (Muscle Gain's own current
*default* frequency) is worse: Push and Pull days both need their own
distinct chest/back/shoulder movements, and the catalog cannot supply
that today.

**Recommendation, not a decision I'm making unilaterally:** catalog
expansion (a small, concrete list — e.g. an overhead press movement, a
second back movement such as a lat pulldown or seated cable row, a
second shoulder-isolation movement) is a **prerequisite** for 4-day and
5-day V2, not a nice-to-have alongside it. This is flagged as an
explicit decision in §26, and as its own implementation slice in §23 —
not silently done here, and not invented as specific named exercises
without your sign-off on which ones.

## 13. Prescription/progression/set-autoregulation/deload/calibration reuse

All confirmed already-generic, zero changes needed for any new split:

- **Rep ranges/RIR mesocycle** (`HypertrophyV2ProgressionEngine.repRange`/
  `primarySecondaryRirTrajectory`/`accessoryTargetRir`) — keyed by
  `SlotRole` only, not by day or split.
- **Performance-qualified progression** (`DoubleProgressionEngine`) —
  keyed by real logged history per Exercise, not by split.
- **Set-count autoregulation** (`HypertrophyV2ProgressionEngine.resolveSetCount`,
  self-attributed `pairedSlot`) — keyed by template/slot, generic.
- **Deload** (`HypertrophyV2ProgressionEngine.resolveRepGoal`'s
  `isDeload` branch) — keyed by `TrainingWeek.isDeload` + the
  template's own week-4 rep goal, not by split.
- **Calibration** (`DoubleProgressionHistoryResolver`) — keyed by
  Exercise via `ExercisePerformanceProfile`, not by split.

**Every one of these is already split-agnostic infrastructure.** The
only genuinely new per-split work is the day-focus *rotation table*
itself (which muscle groups on which day) plus a per-frequency
`expectedWeeklyExposure`-equivalent table (§7).

## 14. Readiness/warm-up/substitution compatibility

All three are keyed off the real materialized `Session`/`WorkoutBlock`/
`ExercisePrescription` graph, never off split identity or day count
(confirmed by this stage's own new production-path integration test,
which already exercises readiness → warm-up → execution against the
3-Day config's real materialized session with zero split-specific
code in any of those three systems). No new compatibility work is
needed for additional splits — they inherit this for free, the same
way Stage 10B's own day-focus path already did.

## 15. Structural volume policy (§7/§10's minimum answer, restated explicitly)

The smallest policy that prevents runaway volume without a landmark
system:

1. Each new split gets its **own** day-focus rotation table (like
   `threeDayFullBodyRotation`), where each day's tier lists are scoped
   to *that day's own emphasis*, never "every muscle group, every day."
2. Each new split gets its **own** `expectedWeeklyExposure`-equivalent
   policy table, an explicit, reviewable, per-frequency product
   decision (not derived from a formula) — matching the existing
   discipline that intentional exposure counts are never "however many
   days happen to include it."
3. Session size is never capped by a global constant — it is the
   natural output of `groupMuscleGroups` applied to each day's
   deliberately-narrower tier lists (§8).
4. No frequency's total weekly slot count needs to exceed roughly
   3-Day's own total (~19-21 slots/week today) by much, since higher
   frequency trades session *breadth* for session *count*, not for
   more total slots.

## 16. Program recommendation problem — analysis (no change made)

**Why 5-Day is currently recommended**: `muscleGainFocusedHypertrophyMix`
is listed first among `.muscleGain`'s two candidates
(`LongTermPlanner.swift:616-620`) and is empirically confirmed
`.recommended` by this stage's own new test. Nothing in `fitFactors`
distinguishes it from the 3-Day alternative on frequency grounds
specifically — the "recommended" role appears to simply be this pair's
first-listed candidate along with whatever "phaseGoalMatch"/etc. factors
both mixes score identically on.

**Does the planner know a real stated frequency preference?**
`GoalPreferences.availableTrainingDaysPerWeek` exists
(`LongTermGoalTypes.swift:75-77`) but is a **coarse, strategic-grain
availability ceiling**, explicitly documented as never duplicating
`UserAvailability`, and is **confirmed not consumed** by either
`muscleGainFocusedHypertrophyMix()` or `muscleGainVariedMix()` (both
zero-argument functions with hardcoded targets 5 and 3) or by
`candidateMixTemplates`'s own goal-type switch. **A new user's stated
availability currently has no bearing on which of these two mixes gets
`.recommended`.**

**My recommendation** (yours to decide, §26 item 1): **do not change
the default now.** Making 3-Day V2 the default purely because it has
the newer/better-designed engine — while 5-Day is still what the
system would otherwise judge the better frequency fit for many users —
would be optimizing for "which engine we just finished," not for the
user's actual fit, which conflicts with this repository's own standing
principle that a recommendation must track genuine goal/practical
alignment, never an implementation-convenience shortcut. The
architecturally cleanest point to revisit the default is **once 5-Day
itself has V2 rules** (since 5-Day is the one that's actually reachable
and actually recommended today) — at that point the existing
recommendation naturally serves V2 without any frequency mismatch, and
no separate "should we prefer the newer system" judgment call is
needed at all. Until then, a real user's default experience stays
exactly what it already validly was before this stage — not a
regression, just not yet upgraded.

## 17. Concurrent-training future seam

Every Hypertrophy-bearing mix that isn't Muscle Gain's own primary
choice already runs Hypertrophy at reduced priority/frequency alongside
a different primary system (§4's table) — Fat Loss (Interval/Functional
Fitness primary), Endurance (steadyState primary). The 1-day and 2-day
splits proposed in §5 are specifically sized for this exact use —
already the smallest, least session-count-hungry designs, which is
naturally compatible with a concurrent primary modality without any
interference-engine logic. No seam needs to be built for Stage 10C;
the split-size proposals already respect it by construction. Stage 10D
(deferred, unbuilt) is where the planner would ever *choose* a
different hypertrophy structure based on the concurrent mix — not
addressed here.

## 18. Home Gym future seam

Every proposed split continues to encode **slot intent** (muscle
groups + optional movement-function constraint), resolved to a concrete
Exercise only at materialization time via the existing
`ExerciseSlot`/`SubstituteExerciseUseCase` machinery — never a
hardcoded exercise name as program identity. This is unchanged by
Stage 10C and requires no new design.

## 19. Migration / backward compatibility

No existing `ProgramDefinition`/`ProgramInstance` is ever
retroactively reinterpreted (unchanged discipline from Stage 10B.6). A
`generatorVersion` bump remains the seam for any newly-V2'd
configuration, exactly as the 3-Day config already used it.

## 20. Legacy Family A disposition implications

Unchanged from Stage 10B.6's own decision (D-10B6-9): retained,
documented, not migrated. Converting 4/5-Day (or any other config) to
V2 does not require deleting or renaming Family A — it requires the
SAME kind of change Stage 10B.6 already made for 3-Day: swap that
config's `makeDayFocusTemplate`-equivalent construction from `.rmBased`
to `.doubleProgression`, leaving `generateLegacyFixedPair` itself
untouched for whichever configs aren't converted yet.

## 21. Implementation slices (proposed order, not approved)

1. **Catalog expansion decision** (§12/§26) — resolve before any 4-day+
   split is built; otherwise defer 4/5-day and implement only 1-day/
   2-day first (both work fine with the existing catalog).
2. 2-Day Full Body A/B rotation table + its own exposure policy.
3. 1-Day Full Body (reuses Day C's own shape almost directly).
4. 4-Day Upper/Lower (only after §1's catalog decision).
5. 5-Day Upper/Lower/Push/Pull/Legs (only after §1's catalog decision;
   highest product value since it's the current default, also the
   most catalog-constrained).
6. 6-Day — deferred indefinitely; not reachable by any real Mix today.
7. Recommendation-default reconsideration (§16) — only after whichever
   frequency is actually the current default (5-Day) has V2 rules.

## 22. Automated test strategy

For each newly-converted split: mirror Stage 10B.6's own proven
pattern — `HypertrophyDayFocusGenerationTests`-equivalent structural/
coverage tests for the new rotation table, plus a
`HypertrophyV2EndToEndTests`-equivalent real materialization → log →
roll-forward proof, plus one `TacticalPlanningOrchestrationTests`-style
real-production-path test per newly-reachable frequency (especially
important for 5-Day, since that's the default path a real new user
actually takes).

## 23. Simulator acceptance strategy

Same discipline as Stage 10B/10B.6: real onboarding path only (no
hand-seeded fixture), fresh install, manual walkthrough of Day
structure/rep-ranges/RIR/readiness/warm-up per newly-converted split,
before any commit.

## 24. Explicit decisions requiring your approval

1. **Do not change the Muscle Gain default now** (§16) — confirm, or
   direct otherwise.
2. **Catalog expansion is a prerequisite for 4-day/5-day splits**
   (§12) — confirm this gate, and if so, whether to scope the exact
   new exercises now or as a separate follow-up decision.
3. **Implementation order** (§21) — confirm 1-day/2-day first (no
   catalog gate), 4/5-day only after §12 resolves, 6-day deferred
   indefinitely.
4. **Exact tier assignments** for the new 1-day/2-day/4-day/5-day
   rotation tables — none are decided in this document; only the
   overall day-role model is proposed.
5. **Exact per-frequency `expectedWeeklyExposure` tables** — not
   decided here, same reasoning as #4.
6. Whether "4-Day Lower/Leg Focus"/"5-Day Upper/Arms Focus" (currently
   unreachable, §3) should ever be revived as real distinct splits, or
   whether their unreachability is acceptable/intentional going
   forward — flagged, not resolved.

**Do not implement any of the above. Stage 10C stays design-only until
you approve specific items.**
