# V1 Program Library

Recommendation for which of the 15 source workbooks become curated,
shipped `ProgramDefinition`s in V1, versus which stay regression fixtures
only. Per the Stage 3A brief: "if several files are merely variants of the
same hypertrophy system, one generic system should generate them" — not
"import all 15 as separate built-in programs."

## 1. The framing this recommendation depends on

`PROGRAM_FAMILY_MATRIX.md` already established there are **3 families, not
15 programs**. Once `PROGRAM_GENERATOR_SPEC.md`'s generator exists, "which
of the 11 Family A workbooks do we ship" stops being a content question and
becomes a **generator parameter question** — day-count and split are
`HypertrophyProgrammingSystem` parameters a user (or the generator) picks,
not 11 separate hardcoded artifacts. Shipping all 11 as distinct
`ProgramDefinition` rows would be exactly the "import as unrelated
hard-coded programs" outcome the brief explicitly prohibited.

This document therefore recommends two different things for two different
purposes:

- **A small set of pre-built, ready-to-use `ProgramDefinition`s** — for a
  user who wants to start training today without running the generator or
  answering its inputs.
- **The generator's parameter space** — for everything else, driven by
  `GeneratorInput` (`PROGRAM_GENERATOR_SPEC.md` §2), not a library of files.

## 2. PROGRAMMING SYSTEM vs. BUILT-IN PROGRAM CONFIGURATION

Two different levels, not to be conflated:

- **PROGRAMMING SYSTEM** = the methodology + rule vocabulary + parameter
  *space* (`HypertrophyProgrammingSystem`, `PowerliftingProgrammingSystem`
  — `PROGRAMMING_SYSTEM_MODEL.md` §4). **There are exactly two.** This
  revision adds zero new systems and zero engine duplication versus the
  original 3-program recommendation.
- **BUILT-IN PROGRAM CONFIGURATION** = one specific, named, ready-to-use
  point in that parameter space — a `ProgramDefinition` a user can start
  today without running the Generator. There can be as many of these as
  the source material actually supports, at zero additional engine cost
  per configuration, because each one is just a parameter choice.

The original recommendation (3 configurations) was architecturally
correct but too narrow for real product use — a user picking "start
training" in V1 would see only one option per `ProgrammingSystem` plus a
legs-specialization option. This revision widens the **configuration**
count to 8 while leaving the **system** count at 2, per further
product-owner direction (`STAGE3_DECISION_MEMO.md`, "Second pass: V1
Program Library").

## 3. Recommended V1 built-in configurations (revised: 8, not 3)

| # | Configuration name | Programming System | Parameters | Source workbook | Why this configuration |
|---|---|---|---|---|---|
| 1 | 3-Day Full Body Hypertrophy | Hypertrophy | `dayCount: 3, split: full_body` | `4847f523-3_day_full_body_Novice.xlsx` | Smallest-day-count baseline. Named without "Novice" — `PROGRAM_FAMILY_MATRIX.md` §2 found no behavioral basis for that label; carrying it into the product name would misrepresent our own finding. |
| 2 | 4-Day Full Body Hypertrophy | Hypertrophy | `dayCount: 4, split: full_body` | `e1f8fb19-4_day_full_body.xlsx` | The reference file for every Family A rule in `PROGRAM_LOGIC_SPEC.md` §2 — most direct traceability of any Family A file. |
| 3 | 5-Day Full Body Hypertrophy | Hypertrophy | `dayCount: 5, split: full_body` | `1e3d5441-5_day_full_body.xlsx` | Mid-range day-count; `8ebd24ac-5_day_full_body_Novice.xlsx` corroborates that this configuration's rules don't change under the "Novice" label either. |
| 4 | 5-Day Upper/Arms Focus | Hypertrophy | `dayCount: 5, split: arms_shoulders` | `f06502c6-5_day_arms__shoulders.xlsx` | The specialization-split case from the architectural proof table (`PROGRAMMING_SYSTEM_MODEL.md` §7); also exercises the dual-tagged-category question (`STAGE3_DECISION_MEMO.md` A6). |
| 5 | 4-Day Lower/Leg Focus | Hypertrophy | `dayCount: 4, split: legs` | `bb847616-4_day_legs.xlsx` | Only file exercising `FAMILY_A_LEGS_HEAVY_EXCEPTION` — ships a real example of the exercise-category-override mechanism, not just the baseline rule. |
| 6 | 6-Day High-Frequency Hypertrophy | Hypertrophy | `dayCount: 6, split: full_body` | `1eb44a1e-6_day_full_body.xlsx` | Highest day-count in the source set; full_body (not `f63aa557` back/chest or the two 6-day novice-labeled split files) so the name reads as "more frequency," not "more specialization." |
| 7 | 4-Day Powerlifting Strength | Powerlifting | `rmBasisMode: mixed5_8, dayCount: 4` | `f046f129-RPPowerliftingStr4Day.xlsx` | Unchanged from the original recommendation — the only Family B/C workbook with real, non-blank author data (`PROGRAM_REGRESSION_TEST_PLAN.md` §1), the highest-confidence regression-verified configuration in the set. |
| 8 | 5-Day Powerlifting Hypertrophy | Powerlifting | `rmBasisMode: uniform10, dayCount: 5` | `6d06b9fd-RPPowerliftingHyp5Day.xlsx` | Unchanged — exercises the Week-4 autoregulation freeze (`STAGE3_DECISION_MEMO.md` B4), a real behavior a shipped program must get right, not a latent one. |

**Two `ProgrammingSystem`s, eight configurations.** Every row is a
parameter choice on `HypertrophyProgrammingSystem` (1–6) or
`PowerliftingProgrammingSystem` (7–8) — exactly the outcome
`PROGRAM_FAMILY_MATRIX.md`'s "3 families, not 15 programs" conclusion
predicts, applied one level down (configurations within a system, not new
systems). No row required inventing a rule the source material doesn't
already contain.

All 6 Hypertrophy configurations ship as **Mesocycle 1 ("Basic
Hypertrophy") only** — mesocycle sequencing is unresolved
(`OPEN_PROGRAMMING_QUESTIONS.md` §2, `STAGE3_DECISION_MEMO.md` A1), so no
configuration here builds a sequencing/gating behavior that isn't proven.
Shipping Mesocycle 2/3 as additional named configurations later (e.g.
"4-Day Full Body Hypertrophy — Metabolite Focus") is a small, zero-new-
engine follow-on once A1 has an answer — noted as available, not decided
here.

## 4. Everything else: generator parameters or regression-only, not shipped

| Source workbook(s) | Disposition | Rationale |
|---|---|---|
| Remaining Family A workbooks not chosen as a configuration's representative above (`f63aa557`, `2d17f31c`, `bf7f7b32`, and the "Novice"-named files not used in §3) | **Generator parameter space, not shipped configurations** | Each is a `{dayCount, split}` combination the same `HypertrophyProgrammingSystem` can already produce; shipping every one separately would duplicate the same engine dozens of times over for no functional gain. |
| "Novice"-named files specifically, wherever they appear | **No separate disposition — same as above, with no novice flag anywhere** | `PROGRAM_FAMILY_MATRIX.md` §2 / `STAGE3_DECISION_MEMO.md` C1 found no distinct novice ruleset to preserve; nothing novice-specific exists to carry into any configuration. |
| `7da7a0ae-Strength_Program_1.xlsx`, `201e3cbc-Strength_Program_2.xlsx` (Family D) | **Regression/configuration evidence only — not shipped as V1 content** | One unidentified end-user's personal edits of Family B/C (`PROGRAM_LOGIC_SPEC.md` §5), not RP-authored reference material. Valuable proof that `PowerliftingProgrammingSystem`'s parameters are independently reconfigurable by a real user, but shipping someone's personal customization as an official TrainingOS built-in has no source authority behind it. A "custom powerlifting" example program for onboarding/demo purposes is a legitimate, separate product decision — not implied by these files existing. |

## 5. What this recommendation is not

- **Not engine expansion.** 8 configurations, 2 systems — identical count
  to the original recommendation. Every addition here is a parameter
  choice, never a new rule type or a new `ProgrammingSystem`.
- **Not a ranking of training quality.** The selection criterion is "which
  file best demonstrates a mechanic V1 needs to prove works" or "which
  gap in day-count/split coverage a real user would notice missing," not
  "which file is the best program" — outside this analysis's scope.
- **Not a decision about Mesocycle sequencing.** Restated from §3 above —
  every Hypertrophy configuration ships single-phase until
  `OPEN_PROGRAMMING_QUESTIONS.md` §2 is resolved.
- **Not a claim that 8 is a ceiling.** More configurations remain
  available for free from the same two systems' parameter space (§4);
  8 is what this pass recommends shipping now, not a hard limit.

## 6. Missing modality coverage, restated

None of the 8 configurations, nor the generator's parameter space, cover
endurance or functional-fitness modalities — the source material doesn't
address them at all (`PROGRAM_FAMILY_MATRIX.md` §4). V1's program library
is hypertrophy + powerlifting-strength only; this is a coverage gap to
flag to the product owner, not something to paper over with an invented
program.
