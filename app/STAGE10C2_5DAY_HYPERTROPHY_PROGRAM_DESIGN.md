# Stage 10C.2 — 5-Day Hypertrophy V2 Program Design

> **SUPERSEDED / QUARANTINED — DO NOT IMPLEMENT.**
>
> This is a wholly TrainingOS-designed 5-day program (no day-count/split
> combination under this name exists in the recovered source library —
> see `STAGE10R_SOURCE_PROGRAM_LIBRARY_RECOVERY.md` §2's full program
> matrix). It was superseded by the Stage 10R product-direction
> correction and `TRAININGOS_PRODUCT_CONSTITUTION.md`: TrainingOS does
> not author new named training programs when no authoritative source
> program exists — it orchestrates and adapts real, sourced programs. If
> a genuine 5-day source program is ever recovered or re-supplied, this
> document's design reasoning (arm-balance analysis, rear-delt
> quantification, autoregulation stress-testing, calendar-separation
> math) may still be useful evidence to consult — it is preserved below,
> unedited, for exactly that reason. It must not become production code
> as written, and must not be revived without an explicit new product
> decision naming a real source for it.
>
> Original design-phase content follows, unchanged, as the historical
> record.

**STATUS: DESIGN/AUDIT ONLY. No production code changed. Not committed
per explicit instruction.** This is a training-program design, not an
implementation — every exercise, role, set/rep/RIR number, calendar
placement, and volume estimate below is a proposal for your review, not
something the engine has built. Where the current domain model can't
yet express something, that's stated plainly rather than worked around.

---

## 1. Catalog readiness — the real available pool (23 entries)

| Exercise | Target(s) | Movement function | Equipment req. | Likely role | Credible day(s) |
|---|---|---|---|---|---|
| Back Squat | quadriceps, glutes | squatLoaded | barbell, rack | Primary | Lower |
| Front Squat | quadriceps, glutes | squatLoaded | barbell, rack | Primary (alt.) | Lower, Legs |
| Leg Press | quadriceps, glutes | squatLoaded | machine | Secondary | Legs |
| Bulgarian Split Squat | quadriceps, glutes | squatLoaded | dumbbells, bench | Primary/Secondary (alt.) | Legs |
| Romanian Deadlift | hamstrings, glutes | hingeLoaded | barbell | Primary | Lower |
| Conventional Deadlift | hamstrings, glutes | hingeLoaded | barbell | Primary | Legs |
| Barbell Bench Press | chest, triceps | pressLoaded | barbell, rack, bench | Primary | Upper |
| Incline Dumbbell Press | chest, triceps | pressLoaded | dumbbells, bench | Secondary | Push |
| Barbell Overhead Press | shoulders, triceps | verticalPushLoaded | barbell, rack | Primary | Push |
| Barbell Row | back, biceps | horizontalPullLoaded | barbell | Primary | Upper |
| Seated Cable Row | back, biceps | horizontalPullLoaded | cableStation | Secondary | Pull |
| Pull-up | back, biceps | gymnasticsPull, verticalPullLoaded | pullUpBar | Primary (alt.) | Pull |
| Lat Pulldown | back, biceps | verticalPullLoaded | cableStation | Primary | Pull |
| Leg Curl | hamstrings | — | machine | Accessory | Lower |
| Seated Leg Curl | hamstrings | — | machine | Accessory (alt.) | Lower, Legs |
| Leg Extension | quadriceps | — | machine | Accessory | Legs |
| Calf Raise | calves | — | machine | Accessory | Lower |
| Seated Calf Raise | calves | — | machine | Accessory (alt.) | Legs |
| Barbell Curl | biceps | — | barbell | Accessory | Upper, Pull |
| Cable Triceps Pushdown | triceps | — | cableStation | Accessory | Upper |
| Dumbbell Lateral Raise | shoulders, lateralDelt | — | dumbbells | Accessory | Upper, Push |
| Cable Chest Fly | chest | — | cableStation | Accessory | Push |
| Face Pull | shoulders, rearDelt | — | cableStation | Accessory | Pull |

### Remaining gaps

| Gap | A (blocker) / B (future variety) / C (unnecessary) |
|---|---|
| A second rear-delt exercise (only Face Pull exists) | **B** — the program works with one; a second (e.g. reverse pec deck) would only help future variety, not needed to ship |
| A second triceps isolation (only Cable Triceps Pushdown) | **B** — same reasoning |
| A second chest-isolation angle | **C** — Cable Chest Fly plus 2 compound press angles (flat, incline) is already enough |
| A barbell/dumbbell-based vertical- or horizontal-pull fallback that ISN'T already used elsewhere in the week | **B, flagged as real for later** — see §12/§18; not a blocker for the commercial-gym design itself |
| A true hip-thrust/glute-isolation movement | **C** — glutes are already heavily loaded by 4 different compounds across the week (§4); not requested by your target list either |

**No genuine (A) blocker exists.** The catalog is sufficient to build a
complete, non-degenerate 5-Day program today.

## 2. Training targets — design intent vs. current domain representation

| Training design target | Current domain representation |
|---|---|
| Chest | `.chest` |
| Back/lats (vertical-pull emphasis) | `.back` — **no lat-specific tag**; distinguished only by the exercise's `movementFunctions` (`.verticalPullLoaded`), never by a separate muscle tag |
| Upper back (horizontal-pull/row emphasis) | `.back` — **same tag as lats**, distinguished only by `.horizontalPullLoaded` |
| Shoulders/pressing (general) | `.shoulders` |
| Lateral delts | `.lateralDelt` (Stage 10C.1 addition) |
| Rear delts | `.rearDelt` (Stage 10C.1 addition) |
| Biceps | `.biceps` |
| Triceps | `.triceps` |
| Quadriceps | `.quadriceps` |
| Hamstrings | `.hamstrings` |
| Glutes/hip extension | `.glutes` |
| Calves | `.calves` |

**Collapsed distinction, not silently ignored:** "back/lats" and "upper
back" are two real training-design targets that collapse onto the
SAME `.back` tag today. The program design below still respects the
distinction (different exercises, different days, different movement
functions) — it just isn't independently queryable as two muscle tags
the way lateral/rear delt now are. Flagged as a possible future
refinement (§22), not solved here.

## REVISION NOTE (post-review)

Sections 3-16 below replace the original proposal following your
review. Two substantive changes were made:

1. **Conventional Deadlift removed from Legs**, replaced with
   **Bulgarian Split Squat (primary) + Leg Press (secondary)** — see
   the new §3a analysis. This eliminates the RDL/Conventional-Deadlift
   hinge-redundancy problem entirely, but (as the stress test in §10
   found) shifts an equivalent concern onto quadriceps instead — full
   accounting below, not hidden.
2. **Cable Triceps Pushdown added to Push day**, restoring direct
   biceps/triceps symmetry (§3b). **Seated Leg Curl added to Legs day**
   to partially offset the hamstring-frequency reduction caused by
   removing Conventional Deadlift — this second addition was not
   explicitly dictated by you, so it's flagged for explicit approval in
   §16, not silently locked in.

## 3a. Conventional Deadlift vs. alternatives — analysis

| | A. Conventional Deadlift | B. Bulgarian Split Squat | C. Front Squat (considered) |
|---|---|---|---|
| Quad stimulus | Low | **High** (unilateral, real quad driver) | High |
| Hamstring stimulus | High | Low-moderate (stabilizer only) | Low |
| Glute stimulus | High | High | Moderate |
| Spinal/lower-back fatigue | **Highest in the catalog** — near-maximal spinal loading from the floor | Low — dumbbell-loaded, no spinal compression comparable to a barbell hinge | Moderate (front-rack position reduces spinal shear vs. back squat, but still barbell-loaded) |
| Systemic fatigue | High | Low-moderate | Moderate |
| Progression quality | Fine on its own | Fine — already tagged `.squatLoaded`, dumbbell/bench equipment, works cleanly with `.doubleProgression` | Fine |
| Overlap with RDL | **High — same hinge pattern, same prime movers** | None — squat pattern, different prime movers | None |
| Recovery into next week | Poor — heavy hinge fatigue compounds with Lower's own RDL | Good | Good |
| Concurrent Running/FF compatibility | **Worst of the three** — heaviest spinal/systemic cost stacks poorly with running's own impact loading | Best — lowest systemic cost | Good |

**Conclusion: Bulgarian Split Squat is the clear winner**, exactly
matching your stated preference. Programming both RDL and Conventional
Deadlift as primaries in the same week duplicates one movement
pattern's fatigue cost without adding real stimulus diversity — it
was the wrong choice. Front Squat was considered but rejected as
Legs' *primary*: it's still barbell/rack-loaded and spinally-loaded
(just less than a back squat), so it doesn't diversify stimulus/
equipment/fatigue from Lower's Back Squat as cleanly as a dumbbell-
loaded unilateral movement does. **Adopted: Legs = Bulgarian Split
Squat (primary) + Leg Press (secondary).**

**Consequence, stated plainly:** with no hip-hinge movement left on
Legs day, hamstrings drop from 2 direct compound exposures/week to 1
(RDL only) + isolation. This is discussed in §5's frequency map and
addressed partially (not fully) via the added Seated Leg Curl —
flagged for your confirmation in §16, not treated as fully resolved by
assumption.

## 3b. Arm-balance fix

Direct triceps work previously existed only on Upper (Cable Triceps
Pushdown), while biceps already had 2 direct exposures (Upper + Pull).
**Cable Triceps Pushdown is added to Push day too** — the same single
available triceps-isolation exercise repeated once more, matching
exactly how biceps and lateral delt already handle their own single-
candidate scarcity (§6). This restores **direct** symmetry: biceps 4
fixed sets/week, triceps 4 fixed sets/week (both exactly the same
now). Indirect/secondary contribution (half-credit convention, §5) is
also close to symmetric: biceps ≈4.5 from 3 pulling compounds, triceps
≈4.5 from 3 pressing compounds — not identical exercises, but
comparably balanced totals on both sides, not "compensating with
volume everywhere."

## 3-5. The five sessions, weekly frequency, and volume

**Accounting convention (stated once, applied consistently):** a
compound exercise's FIRST-listed target gets full set credit; a
SECOND listed target (secondary involvement, e.g. Bench Press's
triceps) gets half credit, never full — compound sets are never
double-counted as a full set for every muscle they merely also touch.
Accessory/isolation exercises always get full credit (that's their
only job). Bounds shown use the approved autoregulation range
(`baseline-1...baseline+2` for primary/secondary; accessory is fixed).

### UPPER

| # | Exercise | Slot intent | Role | Sets | Reps | Wk-1 RIR | Target | Why here |
|---|---|---|---|---|---|---|---|---|
| 1 | Barbell Bench Press | Horizontal push | Primary | 3 | 5-10 | 3 | chest, triceps | The week's main flat press |
| 2 | Barbell Row | Horizontal pull | Primary | 3 | 5-10 | 3 | back, biceps | Paired compound pull, same day as the main press — balances the day |
| 3 | Dumbbell Lateral Raise | Lateral delt | Accessory | 2 | 10-20 | 2 | lateral delt | First of 2 weekly lateral-delt exposures |
| 4 | Barbell Curl | Biceps isolation | Accessory | 2 | 10-20 | 2 | biceps | First of 2 weekly biceps exposures |
| 5 | Cable Triceps Pushdown | Triceps isolation | Accessory | 2 | 10-20 | 2 | triceps | Only dedicated triceps isolation this week (see §6) |

### LOWER

| # | Exercise | Slot intent | Role | Sets | Reps | Wk-1 RIR | Target | Why here |
|---|---|---|---|---|---|---|---|---|
| 1 | Back Squat | Squat pattern | Primary | 3 | 5-10 | 3 | quadriceps, glutes | Week's main bilateral squat |
| 2 | Romanian Deadlift | Hip hinge | Primary | 3 | 5-10 | 3 | hamstrings, glutes | Week's main hinge |
| 3 | Leg Curl | Hamstring isolation | Accessory | 2 | 10-20 | 2 | hamstrings | Direct isolation the compounds don't fully cover |
| 4 | Calf Raise | Calf isolation | Accessory | 2 | 10-20 | 2 | calves | First of 2 weekly calf exposures |

### PUSH (revised — triceps isolation added)

| # | Exercise | Slot intent | Role | Sets | Reps | Wk-1 RIR | Target | Why here |
|---|---|---|---|---|---|---|---|---|
| 1 | Barbell Overhead Press | Vertical push | Primary | 3 | 5-10 | 3 | shoulders, triceps | This day's own distinct compound — never repeats Upper's flat bench |
| 2 | Incline Dumbbell Press | Horizontal push (incline) | Secondary | 3 | 6-12 | 3 | chest, triceps | Genuinely different angle/stimulus from Upper's flat Bench — real variety, not repetition |
| 3 | Dumbbell Lateral Raise | Lateral delt | Accessory | 2 | 10-20 | 2 | lateral delt | Second of 2 weekly lateral-delt exposures (deliberate — see §6) |
| 4 | Cable Chest Fly | Chest isolation | Accessory | 2 | 10-20 | 2 | chest | Direct chest isolation the presses don't fully cover |
| 5 | Cable Triceps Pushdown | Triceps isolation | Accessory | 2 | 10-20 | 2 | triceps | **New** — restores direct triceps/biceps symmetry (§3b) |

### PULL (unchanged)

| # | Exercise | Slot intent | Role | Sets | Reps | Wk-1 RIR | Target | Why here |
|---|---|---|---|---|---|---|---|---|
| 1 | Lat Pulldown | Vertical pull | Primary | 3 | 5-10 | 3 | back, biceps | Default primary — see §9 for why not Pull-up |
| 2 | Seated Cable Row | Horizontal pull (2nd variant) | Secondary | 3 | 6-12 | 3 | back, biceps | Different equipment/stability profile from Upper's Barbell Row — real variety |
| 3 | Face Pull | Rear delt | Accessory | 2 | 10-20 | 2 | rear delt | Only dedicated rear-delt work this week (see §6) |
| 4 | Barbell Curl | Biceps isolation | Accessory | 2 | 10-20 | 2 | biceps | Second of 2 weekly biceps exposures |

### LEGS (revised — Conventional Deadlift replaced, hamstring isolation added)

| # | Exercise | Slot intent | Role | Sets | Reps | Wk-1 RIR | Target | Why here |
|---|---|---|---|---|---|---|---|---|
| 1 | Bulgarian Split Squat | Unilateral squat pattern | Primary | 3 | 5-10 | 3 | quadriceps, glutes | Replaces Conventional Deadlift (§3a) — genuinely different pattern/fatigue profile from Lower's Back Squat |
| 2 | Leg Press | Squat pattern (machine) | Secondary | 3 | 6-12 | 3 | quadriceps, glutes | Machine-based, lowest spinal loading of the quad options |
| 3 | Leg Extension | Quadriceps isolation | Accessory | 2 | 10-20 | 2 | quadriceps | Direct isolation the compounds don't fully cover |
| 4 | Seated Leg Curl | Hamstring isolation | Accessory | 2 | 10-20 | 2 | hamstrings | **New, flagged** — partial compensation for losing Legs' hip-hinge work (§3a); not explicitly dictated, confirm in §16 |
| 5 | Seated Calf Raise | Calf isolation (2nd variant) | Accessory | 2 | 10-20 | 2 | calves | Second of 2 weekly calf exposures |

**Total: 23 slots/week** (up from 21 — the 2 additions in §3b), still
the same order of magnitude as the 3-Day reference config's own
~19-21, confirming volume still grows by *distributing*, not
multiplying.

### Weekly frequency map (revised)

| Target | Direct exposures | Days | Secondary/indirect | Note |
|---|---|---|---|---|
| Chest | 2 compound + 1 isolation | Upper, Push | — | unchanged |
| Back/lats/upper back | 3 movements (Row, Pulldown, Cable Row) | Upper, Pull | — | unchanged |
| Shoulders (general) | 1 (Overhead Press) | Push | half-credit from all presses | unchanged |
| Lateral delt | 2 (isolation only) | Upper, Push | half-credit from all presses (kept separate, §5-verify) | unchanged |
| Rear delt | 1 (isolation) | Pull | meaningful half-credit from 2 horizontal-pull compounds (§4) | quantified below, not just asserted |
| Biceps | 2 (isolation, fixed 4 sets) | Upper, Pull | half-credit from 3 pulling compounds (≈4.5) | unchanged |
| Triceps | **2 (isolation, fixed 4 sets)** | Upper, Push | half-credit from 3 pressing compounds (≈4.5) | **now symmetric with biceps (§3b)** |
| Quadriceps | **3 compound/secondary + 1 isolation** | Lower, Legs | — | **now 3 autoregulated slots — see §10** |
| Hamstrings | **1 compound + 2 isolation** | Lower, Legs | — | **reduced from 2 compound; see §3a consequence** |
| Glutes | 4 compounds' worth of indirect load | Lower, Legs | high indirect | unchanged, no isolation needed |
| Calves | 2 (isolation) | Lower, Legs | — | unchanged |

### Weekly volume table (revised)

| Target | Direct sets (baseline) | Low | High | Autoregulated slots | Rationale |
|---|---|---|---|---|---|
| Chest | 8 (3+3+2) | 6 | 12 | 2 | unchanged |
| Back | 9 (3+3+3) | 6 | **15** | **3** | unchanged — see §10 |
| Shoulders (general) | 3 | 2 | 5 | 1 | unchanged |
| Lateral delt | 4 (fixed) | 4 | 4 | 0 | unchanged |
| Rear delt | 2 (fixed) direct + ≈3 indirect | 2 | 2 | 0 | see §4 quantification |
| Biceps | 4 (fixed) direct + ≈4.5 indirect | 4 | 4 | 0 | unchanged |
| Triceps | **4 (fixed)** direct + ≈4.5 indirect | 4 | 4 | 0 | **now matches biceps (§3b)** |
| Quadriceps | **11 (3+3+3+2 fixed)** | **8** | **17** | **3** | **new: largest swing in the program — see §10** |
| Hamstrings | **7 (3 + 2+2 fixed)** | **6** | **9** | **1** | **narrower than before — see §3a/§10** |
| Glutes | not separately tallied | — | — | — | unchanged |
| Calves | 4 (fixed) | 4 | 4 | 0 | unchanged |

## 6. Exercise repetition — justified, not accidental

**Biceps (Barbell Curl, Upper + Pull) and triceps (Cable Triceps
Pushdown, Upper + Push):** only one isolation exercise exists for each;
repeating each is the only way to give both arms muscles 2× direct
isolation frequency — now symmetric (§3b), justified by scarcity, not
laziness.

**Lateral delt (Dumbbell Lateral Raise, Upper + Push):** same
reasoning — only one lateral-delt isolation exercise exists.

**Rear delt (Face Pull) is used only ONCE, deliberately not
duplicated** — quantified in §4: the meaningful indirect contribution
from 2 weekly horizontal-pull compounds makes a second direct exposure
unnecessary for V1, not merely "the catalog has nothing else."

**Calves (Calf Raise, Seated Calf Raise) and quadriceps/hamstring
isolation** each use a distinct second variant rather than repeating
the identical exercise — genuine variation, not scarcity-driven
repetition.

**Intentional variation** (never simple repetition): chest gets a flat
press (Upper) and an incline press (Push) — a different angle. Back
gets a row (Upper), a vertical pulldown (Pull), and a second row
variant on a different implement (Pull) — three genuinely different
movements. Hamstrings get an RDL (Lower, hip-hinge) and a machine-
based isolation on Legs — different pattern, not the same lift
repeated. Quads get a bilateral free-weight squat (Lower) and a
unilateral dumbbell squat pattern (Legs) — genuinely different
stimulus/fatigue profile, replacing what was previously a hinge-vs-
hinge redundancy (§3a) with real pattern variation.

## Rear delt frequency — quantified (was §4 in your review)

Direct: Face Pull, 2 fixed sets/week. Indirect: Barbell Row (Upper, 3
sets) and Seated Cable Row (Pull, 3 sets) are both horizontal-pulling
compounds with real, biomechanically meaningful rear-delt recruitment
— not a token/incidental stimulus the way a random unrelated exercise
might be. Using the same half-credit convention as everywhere else:
3×0.5 + 3×0.5 = 3 effective sets, plus the 2 direct = **≈5 effective
rear-delt sets/week**. This is a credible total for a muscle that
generally needs less isolated volume than large primary movers,
**given rows already substantially load it. Recommendation: keep 1×
direct Face Pull for V1** — not adding a second rear-delt exercise, as
you asked me not to do automatically.

## Lateral delt vs. general shoulder pressing — verified, not conflated (was §5 in your review)

Confirmed by re-checking the actual tags: Barbell Bench Press, Incline
Dumbbell Press, and Barbell Overhead Press carry `[chest/shoulders,
triceps]` — **none of them carry `.lateralDelt`**. Only Dumbbell
Lateral Raise carries `.lateralDelt`. So "lateral delt" (4 fixed sets,
Upper+Push) and "general shoulder pressing" (3 sets, Overhead Press
only) are tracked as two completely separate rows in every table above
— pressing volume was never counted toward lateral-delt totals, and
vice versa. This is exactly the distinction `.lateralDelt`/`.rearDelt`
were added in Stage 10C.1 to make possible.

## 7. Fatigue map and weekly calendar (re-evaluated post-revision)

**The original highest-risk interaction is now GONE.** Removing
Conventional Deadlift (§3a) means Legs no longer contains any hip-hinge
movement at all — Lower's Romanian Deadlift is now the week's *only*
heavy hinge, so the "heavy RDL → shortly afterward deadlift" pattern
you warned about cannot occur anywhere in this revised program.

**A different, smaller adjacency now matters instead:** Lower's Back
Squat and Legs' Bulgarian Split Squat + Leg Press are all squat-
pattern/quad-dominant (confirmed as the largest volume swing in §10) —
these two days still benefit from real separation, just for quad
recovery rather than spinal-hinge recovery, and at a lower absolute
fatigue cost than the original Conventional-Deadlift scenario.

**Corrected math, stated honestly:** my original proposal claimed
Lower→Legs got "4 days separation" — that only measured the forward
direction within one week. Since the calendar repeats indefinitely,
the correct measure is the *circular* distance (the shorter of the two
directions around the loop). With 7 days and 5 training sessions, **3
days is the mathematical maximum circular separation achievable
between any 2 specific sessions** — no arrangement can beat this.

| Option | Lower↔Legs circular gap | Upper↔Push circular gap |
|---|---|---|
| A: Mon Upper / Tue Lower / Wed rest / Thu Push / Fri Pull / Sat Legs / Sun rest | 3 (max) | 3 (max) |
| B: Mon Push / Tue Pull / Wed Legs / Thu rest / Fri Upper / Sat Lower / Sun rest | 3 (max) | 3 (max) |

**Both options achieve the mathematical maximum on both critical
pairs simultaneously** — recovery outcomes are equivalent, not a
trade-off between them (unlike my original, miscalculated framing).
Both also produce the same shape (a 2-day training block and a 3-day
training block, separated by single rest days) — Option A's 3-day
block is Push→Pull→Legs (chest/shoulders → back/biceps → quads/glutes,
minimal same-muscle overlap across the 3 consecutive days); Option B's
3-day block is the same 3 days in the same relative order, just
shifted to the front of the week. Structurally equivalent.

**Recommendation: Option A**, on a legitimate secondary tie-breaker
now that recovery is a wash: it preserves the natural Upper→Lower→
Push→Pull→Legs label order chronologically (Mon-Sat), which is a real
communication/UX advantage for a program the user thinks of by that
name — not a compromise of recovery quality, since none exists between
the two options.

## 8. Session length estimates (revised)

| Day | Exercises | Working sets | Estimated duration |
|---|---|---|---|
| Upper | 5 | 12 | ~60-70 min |
| Lower | 4 | 10 | ~50-60 min |
| Push | 5 (+1 vs. original) | 12 (+2) | ~60-70 min |
| Pull | 4 | 10 | ~50-55 min |
| Legs | 5 (+1 vs. original) | 12 (+2) | ~60-70 min |

Adding triceps to Push and hamstring isolation to Legs brings both up
to Upper's size (12 sets), not beyond it — 3 of 5 days now sit at
~60-70 min and 2 at ~50-60 min. No day became disproportionately long;
the two additions were absorbed within the range the program's own
largest day (Upper) already established, not a new outlier.

## 9. Progression compatibility

All 21 slots have a valid rep range, an explicit target RIR, and a
resolvable equipment-increment family — no blocking incompatibility
found. Two real, concrete nuances flagged, not fixed:

- **Pull-up as primary substitute for Lat Pulldown:** works
  architecturally (added-weight progression from a 0kg baseline is a
  legitimate `.doubleProgression` case), but a user who cannot yet
  perform a single unweighted pull-up has no calibration path in the
  current catalog (no assisted-pull-up/band variant exists). This is
  why **Lat Pulldown, not Pull-up, is the proposed default** — it
  calibrates cleanly from any starting point. Pull-up remains a
  legitimate, already-compatible substitution option, not the default.
- **Cable-based exercises and the equipment-increment gap — resolved
  as a concrete recommendation (was §7 in your review):**
  `UserProfile.equipmentIncrements`'s default dictionary is
  `["barbell": 2.5, "dumbbell": 2.0, "machine": 5.0]` — every entry a
  single flat kg value per equipment-type string, already the exact
  granularity `"cable"` needs (this codebase already accepts "one
  number per equipment family," e.g. every `"machine"` exercise —
  Leg Press, Leg Curl, Leg Extension, Calf Raise — already shares ONE
  5.0kg value; `"cable"` needs nothing more granular than that same
  precedent). Real cable stacks vary genuinely between gyms (2.5kg,
  5kg, sometimes larger per pin) — there is no single universally
  correct physical answer, and I am not pretending otherwise. Cable
  Chest Fly, Face Pull, Lat Pulldown, Seated Cable Row, and Cable
  Triceps Pushdown (5 of this program's 23 slots) currently fall
  through to the generic `?? 2.5` fallback silently.

  **Recommendation:** add an explicit `"cable": 2.5` entry to
  `UserProfile.equipmentIncrements`'s default dictionary — a
  conservative choice deliberately (an under-estimate just means the
  engine suggests a smaller jump than a stack might allow, which the
  user can freely exceed by logging what they actually lifted; an
  over-estimate would risk recommending a genuinely non-loadable
  number, which is the failure mode that actually matters). This
  makes the choice explicit and intentional rather than an accidental
  fallback coincidence, with no architecture change — one dictionary
  key, the same "TRAININGOS_DESIGNED fallback" pattern already
  documented elsewhere in this codebase. Real per-user history (once
  any cable exercise has been logged once) anchors `lastKnownWeight`
  to what the user actually lifted regardless of the increment choice
  — the increment only affects how much is added on top of already-
  real data, which further de-risks getting this number slightly wrong.
  **Proposed for your approval, not yet implemented.**
- **Bulgarian Split Squat as a Primary-tier slot:** already tagged
  `.squatLoaded`, dumbbell/bench equipment — resolves through
  `.doubleProgression` with no special handling needed, same as any
  other dumbbell-loaded exercise. No incompatibility found.
- **Light isolation movements and the 10% proportional-increment
  guard:** an exercise starting at a low absolute weight (e.g. a
  lateral raise at 8kg) hits the ≤10% guard easily with even a small
  fixed increment, meaning these slots will often show `HOLD LOAD /
  PROGRESS REPS` rather than a clean load increase early in a user's
  training — expected, intentional conservatism, not a bug, but worth
  naming explicitly since you asked me to identify exactly this case.

## 10. Set-autoregulation stress test — full 6-target sweep

**How the numbers are produced, exactly:** each PRIMARY/SECONDARY slot
independently self-rates (Stage 10B.6's per-slot attribution). Each
slot's set count next week = `previous ± rating`, bounded to
`[baseline-1, baseline+2]`. A slot can only move ±1/week, so reaching
`baseline+2` requires **two consecutive weeks of "felt easy" feedback
on that specific slot** — it is not a one-week jump. ACCESSORY-tier
slots never autoregulate at all (fixed count every week, by design).

| Target | Autoregulated slots | Baseline | Low | High | Swing |
|---|---|---|---|---|---|
| **Quadriceps** | **3** (Back Squat, Bulgarian Split Squat, Leg Press) | 11 (incl. 2 fixed) | 8 | **17** | **+55%, the largest in the program — a new consequence of this revision** |
| **Back** | 3 (Barbell Row, Lat Pulldown, Seated Cable Row) | 9 | 6 | 15 | +67% (unchanged from before) |
| Chest | 2 (Bench, Incline DB) | 8 (incl. 1 fixed) | 6 | 12 | +50% |
| **Hamstrings** | **1** (RDL only) | 7 (incl. 4 fixed) | 6 | 9 | **+29% — narrower than before (was 2 slots, now 1; a direct benefit of removing Conventional Deadlift)** |
| Lateral delt | 0 (both accessory) | 4 | 4 | 4 | none |
| Biceps | 0 (both accessory) | 4 | 4 | 4 | none |
| Triceps | 0 (both accessory) | 4 | 4 | 4 | none |

**Can multiple independent slots for the same target all reach
`+2` simultaneously? Yes — nothing in the architecture prevents it.**
Each slot rates itself independently; if a user genuinely finds all 3
of their back (or now, quad) movements easy for 2 consecutive weeks,
all 3 will independently drift to their ceiling. This is the intended,
working behavior of per-slot local autoregulation, not a malfunction.

**New finding this revision surfaced, stated plainly:** fixing the
hamstring hinge-redundancy (§3a) moved Legs' primary/secondary quad
work from "2 autoregulated quad slots" to a **third** — quadriceps now
has the SAME multi-slot exposure back does, and a slightly larger
percentage swing (+55% vs. back's +67% in absolute terms, but a
higher high-end multiplier off baseline). This is not hidden: solving
one redundancy concentrated a comparable one somewhere else.

**Is this pathological? No — for three convergent reasons:**
1. The ramp requires 2 consecutive "easy" weeks on ALL contributing
   slots simultaneously — not instant, and requires sustained,
   genuine positive feedback, which is exactly the evidence the system
   is supposed to respond to.
2. The 5-week mesocycle's deload resets any accumulated drift every
   cycle — the ceiling is only realistically reached in the last 1-2
   weeks before a reset, not sustained indefinitely.
3. Every ACCESSORY-tier target (lateral delt, biceps, triceps, calves)
   has **zero** swing by construction — the concern is structurally
   confined to PRIMARY/SECONDARY-tier compounds only, and only where
   more than one such slot shares a target.

**Is a weekly volume guard needed? No, not at this time.** The
existing per-slot bounds plus the 2-week ramp requirement plus deload
resets already make this self-limiting. A global weekly ceiling
(MEV/MAV/MRV-adjacent) is not recommended and not being proposed —
consistent with your explicit instruction not to build one merely
from this finding. If real usage data later shows this actually
causing problems, the smallest addition would be a simple **per-target
weekly ceiling check at materialization time** (not a fatigue model,
just a cap) — named here only as a possible future concept, not
approved or built.

## 11. Readiness compatibility

- **Sore quads before Legs — changed by this revision, worth
  re-stating honestly:** with Conventional Deadlift replaced by
  Bulgarian Split Squat, Legs' PRIMARY is now itself quad-dominant
  (unlike the original design, where the hinge-pattern primary was
  naturally insulated from quad soreness). Sore quads now plausibly
  affect Legs' primary, secondary, AND accessory simultaneously (all
  3 target quads) — a real trade-off of the Conventional Deadlift fix,
  not something to hide. Readiness would need to reduce sets broadly
  across the day rather than isolate the adaptation to one slot. Lower
  day still has the same property in reverse (Back Squat is Lower's
  own quad-dominant primary) — so quad soreness now affects 2 full
  primary-bearing days instead of being cleanly contained to
  secondary/accessory slots on one of them.
- **Shoulder pain before Push:** the hardest case found. Push's
  PRIMARY (Overhead Press) and SECONDARY (Incline DB Press) both
  meaningfully load the shoulder — there's no good same-day substitute
  that avoids the joint entirely, since "vertical/horizontal push"
  inherently means shoulder involvement. Readiness would likely need to
  reduce sets on both, or the day loses most of its intended stimulus.
  Genuinely the most fragile day in the program for this specific pain
  pattern — flagged, not solved.
- **Low readiness before Lower:** works as intended — Lower's two
  primaries are both legitimately high-fatigue; existing Stage 8
  set-count reduction applies normally, no gap found.
- **Unavailable cable station:** affects Push's accessory (Cable Chest
  Fly), and **all of Pull's primary + secondary** (Lat Pulldown, Seated
  Cable Row). Pull-up and Barbell Row already carry the matching
  movement-function tags (`.verticalPullLoaded`/`.horizontalPullLoaded`)
  from Stage 10C.1 specifically so this substitution is already
  architecturally possible today, with no new code — a real, confirmed
  strength of the semantic model, not just a risk.
- **Exercise-specific (e.g. elbow/bicep) pain before Pull:** Lat
  Pulldown, Seated Cable Row, and Barbell Curl all load biceps to some
  degree — a single pain report plausibly triggers correlated
  adaptations across most of Pull day. Realistic, not a flaw.

## 12. Equipment / Home Gym architecture audit (revised)

| Day | Required equipment (union) |
|---|---|
| Upper | barbell, rack, bench, dumbbells, cableStation |
| Lower | barbell, rack, machine |
| Push | barbell, rack, dumbbells, bench, cableStation |
| Pull | cableStation, barbell |
| Legs | **dumbbells, bench, machine** (changed — Conventional Deadlift's `barbell` requirement is gone; Bulgarian Split Squat needs dumbbells+bench instead) |

**Scenario A — barbell + rack + bench + plates only:** Upper and Lower
mostly survive. Push collapses to 1 exercise. Pull collapses to 1
exercise (unchanged finding, below). **Legs now collapses to ZERO
exercises** (previously 1, via Conventional Deadlift) — Bulgarian
Split Squat needs dumbbells, Leg Press/Leg Extension/Seated Leg
Curl/Seated Calf Raise all need machines; nothing in Legs' new lineup
runs on barbell-only equipment.

**Scenario C — barbell/rack/bench + dumbbells, no cable/machine:**
Legs now keeps its primary (Bulgarian Split Squat only needs
dumbbells+bench, both present in this scenario) — an IMPROVEMENT over
the original design, where Legs' primary needed a barbell specifically.

**Pull day's finding is unchanged by this revision:** its entire
primary+secondary remains cable-only (Lat Pulldown, Seated Cable Row),
with Barbell Row (the catalog's one barbell-based horizontal pull)
already assigned to Upper day — confirmed again, not newly introduced.

**Per your explicit instruction, the commercial-gym program is NOT
being redesigned to fix this.** What matters instead: is Pull day
already expressed through training intent rather than hard exercise
dependence? **Yes, confirmed:** `SubstitutionValidator.isValid`
matches on `allowedTargets`/`allowedMovementFunctions` overlap, not
exercise identity. Lat Pulldown and Pull-up both carry
`.verticalPullLoaded`; Barbell Row and Seated Cable Row both carry
`.horizontalPullLoaded` (all four tagged this way specifically in
Stage 10C.1, anticipating exactly this need). A future equipment-aware
resolver could today express:
- vertical pull: Lat Pulldown → Pull-up (already works, zero new code)
- horizontal pull: Seated Cable Row → Barbell Row → a future Dumbbell
  Row (would only need the same `.horizontalPullLoaded` tag to join
  this chain)

**This is already true, documented, and requires no changes.** The
commercial-gym program stays exactly as designed; the semantic
resolution seam it depends on is already sufficient.

## 13. Deload design (revised for 23 slots)

Applying the already-built V2 deload rule (round(baseline×0.5), min 1;
explicit RIR 4; same rep range and exercise identity as week 4; no
`toFailure` inheritance):

| Day | Deload sets (primary→2, secondary→2, accessory→1 each) | Total |
|---|---|---|
| Upper | 2+2+1+1+1 | 7 (vs. 12 normal) |
| Lower | 2+2+1+1 | 6 (vs. 10) |
| Push | 2+2+1+1+1 | 8 (vs. 12) |
| Pull | 2+2+1+1 | 6 (vs. 10) |
| Legs | 2+2+1+1+1 | 8 (vs. 12) |

Every exercise stays in the rotation (nothing dropped entirely) at
roughly half its normal set count and an explicit RIR 4. Deload
exclusion from the next mesocycle's progression input
(`DoubleProgressionHistoryResolver.isLikelyDeloadExposure`, built in
Stage 10B.6) generalizes to this split automatically — it keys on
`targetRir == 4`, not on which split produced the exposure, so **no new
work is needed here.**

## 14. Comparison with 3-Day V2

| | 3-Day Full Body | 5-Day U/L/P/P/L |
|---|---|---|
| Weekly slots | ~19-21 | 23 |
| Per-muscle direct frequency | Most groups 3× | Most groups 2× |
| Avg. session length | ~60-80 min (7 exercises) | ~50-70 min (4-5 exercises) |
| Exercise diversity per muscle | Often 1 movement/week | Typically 2-3 distinct movements/week |
| Fatigue distribution | One session must cover everything | Each session covers less, more focused |
| Progression identities/muscle | Usually 1 | Usually 2-3, tracked independently |
| Weekly training-day commitment | 3 | 5 |
| Robustness to a missed session | High — still full-body on remaining days | Lower — a missed day removes a whole targeted stimulus for the week |
| Complexity | Simple, 3 templates | More templates, more roles to reason about |
| Likely best-fit user | Time-constrained, lower training age, adherence-risk-averse | High, consistent weekly availability; benefits from more variety/frequency granularity |

**The actual training advantage 5-Day buys is not "more volume"** —
total weekly slots are nearly identical. It's **more exercise variety
per muscle, more distinct progression identities, and better
per-session fatigue distribution** — at the cost of a materially higher
weekly commitment and materially lower robustness to a missed session.

## 15. Default Muscle Gain recommendation — analysis only, no change

Consistent with, and extending, Stage 10C's own earlier finding
(§16 of `STAGE10C_HYPERTROPHY_V2_SPLIT_EXPANSION.md`): **"best
hypertrophy program under perfect adherence" and "best default for an
unknown-preference new user" are genuinely not the same question.**
5-Day's real advantages (§14) only materialize with full adherence;
its real costs (higher commitment, lower robustness to a missed
session) hit hardest for exactly the generic, preference-unstated new
user the default recommendation serves. **My recommendation, unchanged
from before and reinforced by this design pass: even once 5-Day V2
ships, defaulting to it purely because it now has parity with 3-Day's
engine would still be optimizing for program sophistication over
actual fit.** The cleaner long-term fix is what §16 already named —
resolving the recommendation from a real stated/inferred frequency
preference — not a blanket switch to whichever frequency is newest. No
change made; this is analysis only, as instructed.

## 16. Exact unresolved decisions requiring your approval (revised)

1. Confirm the revised session tables (§3-5) — including Bulgarian
   Split Squat + Leg Press replacing Conventional Deadlift on Legs, and
   the added Cable Triceps Pushdown on Push.
2. **Confirm or reject the added Seated Leg Curl on Legs** (§3a/§5) —
   this was my own addition to partially offset the hamstring-frequency
   loss from removing Conventional Deadlift, not something you
   explicitly dictated. Legs becomes 5 exercises/12 sets if kept, 4/10
   if not.
3. Confirm Lat Pulldown as Pull day's default primary (not Pull-up) —
   unchanged from before.
4. Confirm 1× direct rear-delt frequency is acceptable given the
   quantified ≈5 effective sets/week (§4 callout) — my recommendation
   is yes, not adding a second exercise.
5. Confirm the weekly calendar — **Option A** (Mon Upper/Tue Lower/Wed
   rest/Thu Push/Fri Pull/Sat Legs/Sun rest), given both evaluated
   options are now mathematically equivalent on recovery grounds (§7).
6. **New finding requiring a decision:** quadriceps now has 3
   independently-autoregulated slots (8→17 sets/week swing, the
   largest in the program) as a direct consequence of the Conventional
   Deadlift fix (§10). Confirm this is an acceptable trade-off (my
   recommendation, for the reasons in §10), or direct a different
   Legs-day role structure.
7. **Approve or reject the cable-increment recommendation** (§9): add
   `"cable": 2.5` to `UserProfile.equipmentIncrements`'s default
   dictionary.
8. Confirm no weekly volume guard is needed at this time (§10) — my
   recommendation, not a decision I'm making unilaterally.
9. Confirm Pull day's cable-dependency remains an acceptable trade-off
   (§12) — unchanged finding, now also confirmed that training-intent
   resolution already supports a future fallback with zero new code.
10. Confirm the rep-range/RIR rules apply completely unchanged to this
    split — unchanged from before.
11. Confirm the Muscle Gain default-recommendation conclusion (§15) as
    the standing analysis, pending a real decision after 5-Day V2 is
    implemented and accepted.
12. Confirm whether the "lats vs. upper back" semantic collapse (§2) is
    acceptable to leave as-is — unchanged from before.

**Nothing above is implemented. No production code was changed. This
document is not committed. Waiting for your review before any Stage
10C.2 implementation begins.**
