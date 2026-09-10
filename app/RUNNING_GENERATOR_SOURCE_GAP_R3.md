# RUNNING R3 — Generator Source Gap Plan

Scope: analysis only. No production code, no generator implementation, no UI,
no commit, no push. R1 (source recovery) and R2 (running foundation) are
CLOSED and are not reopened here; nothing below revisits threshold-relative
intensity, threshold→pace math, execution-override rules, adaptation rules,
missed-session/re-entry, pain response, scheduled-recalibration semantics,
generic prescription/repeat representation, or the Running↔Orchestrator
foundation — those are settled.

## 1. Current Generator Readiness

TrainingOS has the **primitives** to represent any running prescription R1
observed (R2, CLOSED). It does not yet have the **decision logic** a
generator needs: given an athlete's goal/ability/available days/target date,
which frequency, which starting volume, which progression rate, which
mesocycle/taper shape to produce. All of that decision logic is currently
backed by exactly **one** observed instance (2 runs/week, one athlete, one
capture) — sufficient to represent that instance faithfully, not sufficient
to generalize it into a parametrized generator without either (a) more
source evidence or (b) an explicitly disclosed, narrow V1 boundary that
stops short of claiming generalization it can't support.

## 2. Questions Already Solved by R1/R2 (not reopened)

Threshold-relative intensity representation; threshold→pace calculation;
athlete execution-override rules (rep-1, ≤95%, ≤RPE6, corrected ≤89%
same-block ceiling); in-workout adaptation rules; missed-session/illness/
travel/multi-week/>1-month re-entry; pain-response ladder; scheduled
threshold-recalibration gating; running prescription representation
(source-labeled `SteadyStatePrescription`/`IntervalPrescription`, ordered
multi-repeat-group blocks, RPE-only blocks); Running↔Orchestrator contract
metadata (quality/easy classification, recovery sensitivity, advisory
cross-domain rules). CLOSED.

## 3. Generator Questions Still Unsupported

Mapped against the checkpoint's own 14-item list. "Supported" here means
"backed by more than one instance, or by explicit RP documentation stating a
rule" — not merely "observed once."

| # | Question | Status |
|---|---|---|
| 1 | Weekly running frequency (how chosen) | UNSUPPORTED — no selection rule exists anywhere in source; only one frequency observed |
| 2 | Workout roles within a frequency | SUPPORTED for 2-day only (Slot A quality / Slot B easy-active); not generalized |
| 3 | Starting weekly volume | UNSUPPORTED — one athlete's one starting value, no rule connecting ability→volume |
| 4 | Starting per-session volume | UNSUPPORTED — same reason as #3 |
| 5 | Number of quality sessions | SUPPORTED for 2-day only (exactly 1/week); no evidence how this scales |
| 6 | Easy-volume allocation | SUPPORTED for 2-day only (1 Active/Easy slot); no evidence how this scales |
| 7 | Long-run presence/role | **NOT OBSERVED AT ALL** — the 2-day plan's largest continuous block (6.00 mi, week 11) is labeled "Active," never a distinct "long run" role; unknown whether higher frequencies introduce one |
| 8 | Workout-family selection | SUPPORTED for 2-day only (7 families, R1 §7); unknown if higher frequency adds families |
| 9 | Progression rate | Observed once (two-axis model, R1 §8); rate is this-instance-specific, not proven as a rule |
| 10 | Mesocycle structure | Doubly corroborated **within this one frequency** (R1 §9); zero evidence at any other frequency |
| 11 | Deload/reduction cadence | Same as #10 |
| 12 | Transition to race-specific work | Observed once (week 9 onward); timing rule (e.g. "always final third") not established |
| 13 | Taper structure | Observed once (2-week taper); length rule not established |
| 14 | Race-week prescription | Observed once (RPE-only); universality not established (see §11) |

**Net finding:** every one of the 14 questions is either fully unsupported or
supported only within the single observed 2-day instance. None is currently
answerable in a form a generator could apply to a different frequency,
level, or distance without guessing.

## 4. Minimum Additional Source Set

Evaluated against "smallest source set that distinguishes UNIVERSAL from
2-DAY-PROGRAM-SPECIFIC," not "every RP running product":

| Candidate | Resolves | Does NOT resolve | Required before generator? |
|---|---|---|---|
| **A. One higher-frequency RP 5K plan** (e.g. 3-day or 4-day, same distance) | Frequency generalization (#1, #2, #5, #6, #7 — whether a long run appears, #9 rate, #10/#11 mesocycle universality, #14 as a side-effect, see §11) | Level generalization, distance generalization | **YES**, for any frequency beyond 2/week |
| **B. One lower/different-level RP 5K plan** (same frequency, different declared experience tier) | Athlete-level generalization (#3, #4 starting volume/intensity by ability; whether mesocycle/progression rate changes by level) | Frequency generalization, distance generalization | **YES**, for any personalization by starting ability |
| **C. One different-distance RP plan** (10K/half/marathon) | Distance generalization (#9, #12, #13 possibly distance-scaled; whether the intensity model — %threshold — is distance-invariant) | Frequency generalization, level generalization | Only if V1 claims more than 5K |
| **D. RP documentation on frequency/level/volume selection** (if it exists — e.g. a program-selection guide, intake questionnaire, or landing-page description) | Potentially #1, #3, #4 directly, as explicit stated rules rather than inferred comparison — the highest-leverage single item IF it exists | Nothing, if it doesn't exist or is marketing copy without real selection logic | Unknown — cheap to check, not yet confirmed to exist |

No candidate above was already ruled out by R1 — R1 explicitly flagged "RP's
other Endurance Training Program tiers" and "any non-5K distance's RP
program" as MISSING SOURCE (R1 §3), not as unobtainable.

## 5. Highest-Value Next Source

**Candidate A (a second 5K frequency variant)**, specifically the smallest
step up from the observed 2-day plan — a **3-day RP 5K plan, same
"intermediate level or higher" tier** if selectable, so frequency is the
only variable that changes. Reasoning:

- It is the only candidate that directly tests whether the single most
  load-bearing structural finding in R1/R2 — the ~4-week mesocycle/deload
  cadence — is a property of RP's running methodology in general, or an
  artifact of this one 2-day capture. Every downstream generator decision
  (#9-#14) depends on this being resolved before it can be trusted beyond
  2 runs/week.
- It directly tests whether a distinct "long run" role exists (#7) — a
  structural question the 2-day capture cannot answer at all, since 2
  slots/week may simply have no room for one.
- As a side-effect (no separate acquisition needed), it also tests the
  race-day RPE question (§11) and the 16-week-vs-13-week discrepancy (§10) —
  if the same ~3-week shortfall or the same RPE-only race week recurs in an
  independently-transcribed second plan, that is real corroborating
  evidence either way, not just a second unexplained instance.
- Candidate D (a selection-methodology document) would be cheaper if it
  exists, but its existence is unconfirmed and its content unknown — it
  cannot be relied on as the primary acquisition target. It is worth a quick,
  low-cost check in parallel, not a substitute for A.

## 6. Comparison Matrix (template — do not assume these variants exist until confirmed)

To be filled in once Candidate A (or whichever variant is actually obtained)
is captured, compared row-by-row against the existing 2-day reference:

| Variable | 2-day (captured, R1) | 3-day (or whatever frequency is obtained) | 4+-day (if later obtained) |
|---|---|---|---|
| Weekly mileage (per relative week) | known | — | — |
| Session count/week | 2 | — | — |
| Workout roles present | Tempo/Hard (quality) + Active (easy) | — | — |
| Quality-session count | 1 | — | — |
| Easy-session count | 1 | — | — |
| Long-run structure | none identified as distinct | — | — |
| Intensity distribution (which %threshold bands used, how often) | 13 distinct paces, §6 of R1 | — | — |
| Progression pattern (volume/pace axis, structural-complexity axis) | two-axis, weeks 1-8 vs 9-12 | — | — |
| Deload/reduction cadence | ~4 weeks, doubly corroborated | — | — |
| Race-specific transition timing | week 9 of 12 (build portion) | — | — |
| Taper length | 2 weeks | — | — |
| Race-week prescription mechanism | RPE-only | — | — |

Do not populate the right-hand columns from assumption — only from a
directly inspected second source, using the same evidence-classification
discipline as R1 (SOURCE FACT / DERIVED FACT / PROGRAMMING INFERENCE /
TRAININGOS PRODUCT DECISION).

## 7. Frequency Generalization Gap

UNSUPPORTED beyond 2 runs/week. Every mesocycle-length, deload-cadence,
progression-rate, and race-transition-timing finding in R1/R2 is a
single-instance observation at exactly one frequency. Closing this gap
requires Candidate A (§4/§5). Until closed, a generator must not be
parametrized by "days per week" beyond 2 without fabricating behavior R1
already warned against (R1 §21's first risk, restated here: treating this
one instance's parameters as universal constants).

## 8. Athlete-Level Generalization Gap

The captured plan is explicitly "Intermediate Level and Higher"
(`How-To Int+5k Endurance Running.docx` line 3, SOURCE FACT). RP's FAQ does
document one experience-based rule that is NOT structural — goal-time-setting
percentages by experience level (5-10%/yr new athletes, 1-3%/yr advanced,
<1%/yr elite; R1 §13) — but this is about realistic *outcome expectations*,
not about how starting volume, starting intensity distribution, or
progression rate should differ across levels for the plan itself. That
remains completely UNSUPPORTED. Closing this gap requires Candidate B.
Without it, any generator that accepts "current running ability" as an input
(per this checkpoint's own PRIMARY QUESTION framing) has no source-backed
way to translate that input into a different starting prescription — it can
only apply the one captured intermediate-tier starting point to every
athlete, which is a V1 boundary (see §12), not a solved generalization.

## 9. Distance Generalization Gap

UNSUPPORTED, and the one existing piece of related evidence is ambiguous
rather than clarifying: FAQ lines 52-53 (SOURCE FACT) state the 5K plan
*can* be cross-used as general aerobic-base training for other race
distances, but this describes using the 5K plan as a substitute, not RP's
own dedicated programming for those distances — it says nothing about
whether a purpose-built 10K/half/marathon RP plan uses the same intensity
model, mesocycle length, or taper shape. Do not read FAQ 52-53 as evidence
that distance is a non-factor. Closing this gap requires Candidate C, and
only if TrainingOS's Running Generator V1 is meant to cover more than 5K.

## 10. 16-Week Discrepancy

**Resolving evidence would be:** either (a) the original TrainingPeaks
calendar/export for this exact plan showing all 16 weeks with real dates
(requires the athlete's own TrainingPeaks account access — the captured
reference is explicitly a transcription, not an export, per R1 §2/§3), or
(b) an independently-captured second instance of the *same* 2-day 5K plan
that happens to include the missing ~3 weeks, allowing a direct comparison.
Neither is guaranteed obtainable — (a) depends on account/history access
already flagged as a MISSING SOURCE in R1, and (b) is opportunistic, not a
targeted acquisition.

**Classification: SAFE TO HANDLE THROUGH EXPLICIT V1 PRODUCT BOUNDARY.**
Reasoning: nothing about the 14 generator questions in §3 requires knowing
the content of the missing ~3 weeks specifically — the *shape* already
recovered (13 relative weeks, 3-4 mesocycles + a 2-week taper + race week)
is a complete, internally-consistent, usable structure on its own. R1 §22
already recommended exactly this resolution path (document the 13-week
captured shape as the authoritative V1 boundary rather than block on
recovering the original 16). This R3 checkpoint confirms that recommendation
rather than revising it: **do not fabricate the missing weeks; state
plainly, wherever V1 documents its own scope, that it implements the
13-relative-week structure actually recovered, not an unverified 16-week
original.**

## 11. Race-Day RPE Gap

Smallest evidence that would resolve whether the RPE-only race prescription
is (a) universal RP doctrine, (b) specific to this plan, (c) specific to
this athlete/transcription, or (d) a TrainingOS decision to make
independently:

- **If Candidate A (a second frequency, same distance) also drops to
  RPE-only at its own race week** → strong evidence for (a) or (b) — RP
  policy for 5K races generally, at least across frequency.
- **If Candidate C (a different distance) also does** → strong evidence for
  (a) — RP policy for races in general, not distance-specific.
- **If either shows a %threshold-compatible race prescription instead** →
  evidence for (c) — this specific transcription/athlete's own choice
  (possibly the analyst's or athlete's personal preference recorded
  alongside the plan, not RP's own template), which would mean TrainingOS
  must make its own product decision (d) rather than copy an
  athlete-specific choice as if it were RP doctrine.

No existing source (R1's five inspected files, re-confirmed unchanged this
checkpoint) says anything more on this question than what R1 already
extracted — the FAQ states race week's *purpose* ("designed to encourage
recovery and peaking") but never its intensity-prescription mechanism. This
checkpoint does not resolve the question with current evidence; it remains
exactly as unresolved as R1 left it, and the same Candidate A/C acquisitions
that close §7/§9 would resolve this one as a direct side-effect.

## 12. Recommended TrainingOS Running Generator V1 Boundary

Given §3-§9, the smallest boundary that is honestly generative (parametrized
by real athlete input) without over-generalizing unproven structure:

**TrainingOS Running Generator V1:**
- **Distance:** 5K only.
- **Frequency:** 2 runs/week only (the sole source-supported frequency).
- **Athlete level:** the single observed tier ("intermediate level or
  higher" per source) — V1 does not attempt to scale starting volume/
  intensity for other levels, because no source evidence supports how that
  scaling should work (§8).
- **Structure:** the recovered 13-relative-week shape (workout families,
  ~4-week mesocycle/deload cadence, 2-week taper, race week) reproduced as
  *this plan's* structure — explicitly documented as derived from one
  captured instance, not asserted as RP's universal running methodology.
- **Personalization within V1:** athlete-specific threshold pace (fully
  supported, R2) drives every absolute pace target; the weekly *shape*
  (distances, session roles, mesocycle timing) does not vary by athlete
  within this V1 — this is the honest limit of what's source-supported.
- **Race week:** modeled as RPE-only, exactly as observed, with the
  limitation from §11 stated explicitly wherever this is surfaced (not
  asserted as universal RP doctrine).
- **Explicitly out of V1:** any other frequency, any other distance, any
  other experience tier, any claim to reproduce the "official" 16-week
  program, and any universal mesocycle/taper/race-day rule.

This boundary is intentionally narrower than "a generative Running Engine"
in the fullest sense — it is closer to "one real, source-grounded template,
parametrized by the athlete's own threshold pace, with every unproven
generalization explicitly fenced off." Extending it in any direction (more
frequencies, more levels, more distances) requires the corresponding source
in §4, not an assumption.

## 13. Exact Evidence Needed Before Implementation

- To implement V1 exactly as scoped in §12 (single frequency, single level,
  single distance, disclosed limitations): **no new source is strictly
  required** for the *representation* — R2 already built every primitive.
  What is still missing is not source but **ratified product decisions**:
  (i) explicit acceptance that V1 documents the 13-relative-week shape
  rather than claiming the nominal 16 weeks (§10), and (ii) explicit
  acceptance that race week is modeled as RPE-only with the §11 caveat
  disclosed, not asserted as universal.
- To implement anything **beyond** that narrow V1 — a second frequency, a
  different level, or a different distance — the corresponding source in
  §4 (A, B, or C respectively) is **required**, not optional. Attempting to
  interpolate or guess any of those without new source would repeat exactly
  the over-generalization risk R1 §21 already flagged.
- If the product goal is a Running Generator that is "genuinely generative"
  in the sense of adjusting its *structure* (not just its paces) to a given
  athlete's current ability — as opposed to replaying one fixed structure
  with personalized paces — then **Candidate B is required even for V1**,
  since starting-volume-by-ability is otherwise entirely unsupported (§8).
  This checkpoint flags this rather than deciding it: whether V1 accepts
  "structure is fixed, only pace is personalized" as sufficiently generative
  is itself a TRAININGOS PRODUCT DECISION, not resolved here.

## 14. Evidence Safe to Defer

- The original 16-week TrainingPeaks export/dates (§10) — safe to defer
  indefinitely behind the V1 boundary; not worth pursuing unless it becomes
  unusually easy to obtain.
- Any RP running frequency beyond the one acquired next (e.g., if 3-day is
  acquired, 4-day/5-day/6-day remain deferred until V1 is validated at 3
  frequencies' worth of evidence, not before).
- Any non-5K distance (Candidate C) — defer until 5K V1 ships and the
  product decides to expand distance coverage.
- Exact calculator seconds-rounding edge behavior (already flagged
  SAFE-TO-DEFER in R1 §20 — unchanged).
- Diet-template/training-load reconciliation (already flagged SAFE-TO-DEFER
  in R1 §20 — unchanged).

---

## NEXT SOURCE NEEDED

**A captured RP Endurance 5K TrainingPeaks program at a different weekly
running frequency than the one already captured — 3 runs/week if selectable
as a distinct tier, otherwise whichever frequency tier RP actually offers
that is closest to 2/week, at the same or nearest-available experience
level ("intermediate or higher" if possible, to hold level constant while
frequency changes.)**

### WHY

This single acquisition is the only source candidate that directly tests
whether the ~4-week mesocycle/deload cadence, the workout-family taxonomy,
the two-axis progression pattern, and the race-day RPE prescription
(everything currently backed by exactly one instance) are real RP running
methodology or artifacts of the one 2-day capture. It also directly answers
whether a distinct "long run" role exists at higher frequency — a question
the 2-day plan structurally cannot answer at all. It is the smallest single
item that converts the current "PLAUSIBLE-BUT-UNPROVEN"/"BLOCKING-FOR-R2"
findings from R1 into either confirmed-universal or confirmed-instance-
specific, for the frequency axis specifically.

### MINIMUM CAPTURE REQUIRED

The same shape already successfully used for the 2-day reference — it does
not need to be a raw TrainingPeaks export, a faithful transcription is
sufficient, exactly as before:

- **Source & Inputs**: declared frequency/level/distance, captured
  threshold pace, and the same provenance caveats (transcription method,
  whether dates are assigned).
- **Calendar Overview**: which weeks are flagged as lighter/deload weeks,
  and where any "Threshold Pace Adjustment" checkpoints fall.
- **Workout Blocks**: every block, in the same column shape as before —
  Workout ID, Relative Week, Slot, Block #, Repeat Group, Repeat Count,
  Source Label, Distance, Source Pace (or RPE), TP Zone (if shown),
  Source Notes — for every workout in the plan, start to finish, including
  the race week.
- **Workout Index**: the full workout list in order, with slot labels.
- **Intensity Map**: every distinct pace/zone/RPE value used, with its
  derived %threshold if the plan uses a different captured threshold than
  5:00/km.
- **Handoff Notes**: the same explicit caveats as before (is this a full
  export or a transcription; are dates assigned; is this athlete's own
  threshold or a template default).
- Critically: **the total number of weeks actually captured**, and whether
  this second capture also falls short of any nominal published length —
  this alone helps triangulate whether the missing-weeks phenomenon (§10)
  recurs.

---

## Files created/changed

- **Created**: `app/RUNNING_GENERATOR_SOURCE_GAP_R3.md` (this file). Nothing
  else created or modified. `RUNNING_PROGRAMMING_MODEL_R1.md` and
  `RUNNING_FOUNDATION_R2.md` were read for reference, not edited.
- `app/source_workbooks/` re-inventoried this checkpoint (`ls -la`): no new
  running-relevant file has been added since R2; still gitignored, still
  untracked.

```
$ git diff --stat
(empty — no tracked file was modified by this checkpoint)

$ git status --short
 M TrainingOS.xcodeproj/project.pbxproj
 M TrainingOS/Domain/Entities/IntervalPrescription.swift
 M TrainingOS/Domain/Entities/ProgramInstance.swift
 M TrainingOS/Domain/Entities/SteadyStatePrescription.swift
 M TrainingOS/Persistence/PersistenceController.swift
?? RUNNING_GENERATOR_SOURCE_GAP_R3.md
(+ pre-existing untracked files from R1/R2 and earlier checkpoints, unchanged:
 RUNNING_PROGRAMMING_MODEL_R1.md, RUNNING_FOUNDATION_R2.md, new Running R2
 production/test files, other pre-existing audit .md files, xcuserdata, .DS_Store)
```

The 5 modified files above are the same, already-verified R2 diff (135
insertions/2 deletions) — untouched by this checkpoint. No new file besides
this one was created. Nothing staged. No commit made. No push made.

---

## Verdict

RUNNING R3 SOURCE GAP: PASS
GENERATOR IMPLEMENTATION READY NOW: NO
ADDITIONAL SOURCE REQUIRED: YES
