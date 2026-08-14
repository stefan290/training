# Program Family Matrix

Which of the 15 source workbooks are genuinely different methodologies,
and which are configurations of the same underlying system. See
`PROGRAM_LOGIC_SPEC.md` for the full rule-by-rule evidence this matrix
summarizes.

## Verdict

**Three families, not fifteen programs, not one program.**

| Family | Workbooks | Methodology | Can one engine represent all variants in the family? |
|---|---|---|---|
| A — RP General Hypertrophy | 11 | Muscle hypertrophy, three sequential(?) phases per program | **Yes** — one engine, parametrized by day-count, split, and phase. "Novice" is not a parameter this data supports (§4). |
| B — RP Powerlifting Strength | 1 (+ Program_1 as a derivative) | Powerlifting-specific strength | **Yes**, and Family C shares enough of the same engine that one configurable `PowerliftingProgrammingSystem` can represent both — see §3. |
| C — RP Powerlifting Hypertrophy-block | 1 (+ Program_2 as a derivative) | Muscle size in service of a later powerlifting strength block | Same engine as B, see §3. |

Family D (`Strength_Program_1`, `Strength_Program_2`) is not a fourth
methodology — it's user-edited configurations of Families B and C
respectively (see `PROGRAM_LOGIC_SPEC.md` §5). It's listed here as
evidence for the B/C engine's configurability, not as its own row.

---

## 1. Family A internals — what varies, what's shared

| Dimension | Shared across all 11? | Detail |
|---|---|---|
| Load-progression formula shape (`week1 = 10RM×factor`, `weekN = week1×multiplier`) | **Yes** | Same shape in every file, every phase, every split, every day-count |
| Progression multipliers (1.05 / 1.075 / 1.1) | **Yes** | Identical constants everywhere checked |
| Autoregulation formula shape (`sets = priorSets + pairedRating`) | **Yes** | Identical shape; only which row pairs with which shifts by layout |
| Rating scale (−1/0/1) | **Yes** | Same three values everywhere; wording constant within family A |
| Deload day-boundary asymmetry (full weight first half of week, halved second half) | **Yes** | Present in all 11; boundary position tracks day-count |
| Which exercises fill which day (the split) | **No — this is the parameter** | full_body / legs / arms+shoulders / back+chest, each with its own category-to-day map |
| Number of training days | **No — this is the parameter** | 3/4/5/6, changes exercise-slot count and rest-day placement, not the math |
| Mesocycle-phase parameters (Week-1 intensity %, superset y/n, duration, rounding unit) | **No — this is the parameter** | Basic Hypertrophy / Metabolite Focus / Resensitization, see `PROGRAM_LOGIC_SPEC.md` §2.2 table |
| Rounding increment (2.5 vs 5) | Inconsistent, not cleanly tied to any parameter | See `PROGRAM_LOGIC_SPEC.md` §6.2 — treat as file-level noise, not a rule |
| "Heavy" 1.0×-baseline exception for squat/deadlift | **Legs split only** | Confirmed absent even on squat/deadlift rows in the other three splits |

**Conclusion:** day-count, split, and mesocycle-phase are legitimate
`ProgramDefinition` configuration parameters on one `HypertrophyProgrammingSystem`.
The legs-only "Heavy" exception should be modelled as an explicit,
named exercise-category override (available to any split, defaulting off)
rather than hardcoded to the legs split specifically — see
`OPEN_PROGRAMMING_QUESTIONS.md` §6 for why this is flagged rather than settled.

## 2. Novice vs. standard — not a confirmed parameter

Compared directly (same split, different day-counts): 3-day Novice vs.
4-day and 5-day standard, all full_body. Every mechanism that can be
isolated from the day-count confound (rep ranges, RM basis, progression
factors, autoregulation formula, deload formulas, exercise catalog breadth)
is **identical**. No novice-specific label, guardrail, or simplified menu
exists in the Novice file.

**Recommendation:** do not implement a distinct "novice mode" in the
Progression or Program Engine based on this evidence. If "novice" needs to
mean something in TrainingOS (e.g. a different *starting point* — more
calibration, more coaching copy, a recommended day-count — that's a
planning/UX concern, not a different ProgrammingSystem ruleset. Revisit
only if the product owner can supply a same-day-count novice/standard pair
to test against — see `OPEN_PROGRAMMING_QUESTIONS.md` §7.

## 3. Family B and C — one engine, two configurations

Both families share, formula-for-formula: the three-sheet
Instructions/DataEntry/Mesocycle architecture; exercise-category dropdown
slots (Legs ×2, Push ×2, Deadlift, Hamstring, Upper-Pull ×2, Shoulder ×2);
`week1 = MROUND(RM × factor, unit)` then `weekN = MROUND(week1 × multiplier,
unit)` off the same Week-1 cell; a `−1/0/1` rating feeding a future
set-count formula that can cross specific exercises within a pattern; a
deload week with a day-boundary weight split and text-only rep instructions.

They differ only in **parameter values**, not in engine shape:

| Parameter | Family B (Strength) | Family C (Hypertrophy-block) |
|---|---|---|
| RM basis | Mixed: 5RM for Legs/Push/Deadlift, 8RM for Hamstring/Pull/Shoulder (fixed per slot) | Single 10RM for every slot |
| Days/week | 4 (Mon/Tue/Thu/Fri) | 5 (Mon–Fri) |
| Week-1 factor (standard) | 0.95 | 0.95 |
| Week-1 factor (backoff/Triples session) | 0.7 (2 specific sessions) | 0.85 (Friday backoff only) |
| Rounding unit | 2.5 | 5 |
| Autoregulated rows | Only 8 "central" barbell rows; accessories fixed | Some rows fixed too (both Upper-Pull, both Shoulder slots — dead rating inputs) |
| Week-4 autoregulation | Applies to all autoregulated rows | **Freezes** for Thursday/Friday rows only (undocumented asymmetry, see spec §4) |
| Deload weight rule | 0.7× (Mon/Tue), 0.5× (Thu/Fri) | Unchanged (Mon/Tue), 0.5× (Wed/Thu/Fri) |
| Deload rep instruction | "2/3 reps of Week 1" (Mon/Tue), "1/2 reps of Week 1" (Thu/Fri) | "1/2 reps of Week 1" everywhere except Friday backoff ("Same reps as Week 1") |

**Conclusion:** one `PowerliftingProgrammingSystem`, configured by RM-basis
mode (mixed 5RM/8RM vs. uniform 10RM), day-count/day-map, and a per-day
factor table (standard/backoff), can represent both. Family D
(`Strength_Program_1/2`) is direct evidence this is the right shape: a real
user took this exact engine and re-tuned the day-map and backoff placement
without touching the load/rating formulas.

## 4. What this does *not* cover

The supplied source material is hypertrophy and powerlifting-strength
only. It says nothing about aerobic base, running, VO2/intervals,
functional fitness/CrossFit-style programming, or concurrent/hybrid
scheduling — see `PROGRAM_GENERATOR_SPEC.md` §5 and
`OPEN_PROGRAMMING_QUESTIONS.md` §9 for the interface implications, not
detailed rules (per the Stage 3A brief, detailed rules for those modalities
wait for separate source material).
