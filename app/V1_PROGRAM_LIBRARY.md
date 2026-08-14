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

## 2. Recommended V1 pre-built `ProgramDefinition`s

One representative per family, chosen for breadth of coverage (different
day-count, different `ProgrammingSystem`) rather than completeness:

| # | Source workbook | ProgrammingSystem + parameters | Why this one, not another Family-A file |
|---|---|---|---|
| 1 | `bb847616-4_day_legs.xlsx` | `HypertrophyProgrammingSystem{dayCount: 4, split: legs}` | Only file that exercises `FAMILY_A_LEGS_HEAVY_EXCEPTION` — shipping this one, not a full_body file, gives V1 a real example of the exercise-category-override mechanism, not just the baseline rule shape. |
| 2 | `f046f129-RPPowerliftingStr4Day.xlsx` | `PowerliftingProgrammingSystem{rmBasisMode: mixed5_8, dayCount: 4}` | The only Family B/C workbook with real, non-blank author data (`PROGRAM_REGRESSION_TEST_PLAN.md` §1) — the one file we can *prove* the shipped definition matches source, not just the formula shape. |
| 3 | `6d06b9fd-RPPowerliftingHyp5Day.xlsx` | `PowerliftingProgrammingSystem{rmBasisMode: uniform10, dayCount: 5}` | Gives V1 the natural strength→hypertrophy-block pairing RP's own material describes (§6.1 documentation mapping), and exercises the Week-4-freeze autoregulation asymmetry (`PROGRAM_REGRESSION_TEST_PLAN.md` §5.2) as a real shipped case, not fixture-only. |

Three pre-built programs, not one per workbook. A 4th (a plain full_body
Family-A hypertrophy program at a common day-count, e.g. 4-day full body)
is a reasonable product addition if user research wants a "no
specialization" default — deliberately left as a product decision, not
added speculatively here.

## 3. Everything else: generator parameters or regression-only, not shipped

| Source workbook(s) | Disposition | Rationale |
|---|---|---|
| Remaining 10 Family A workbooks (`e1f8fb19`, `1e3d5441`, `1eb44a1e`, `f06502c6`, `f63aa557`, and the 5 Novice-named files) | **Generator parameter space, not shipped programs** | Each is a `{dayCount, split}` combination the generator can already produce from #1's `HypertrophyProgrammingSystem`; shipping them separately would duplicate #1's engine 10 times over. |
| The 5 "Novice"-named files specifically | **No separate disposition — same as above, with no novice flag** | `PROGRAM_FAMILY_MATRIX.md` §2 found no distinct novice ruleset to preserve; there is nothing novice-specific to carry into a shipped program that isn't already in #1. |
| `7da7a0ae-Strength_Program_1.xlsx`, `201e3cbc-Strength_Program_2.xlsx` (Family D) | **Regression/configuration evidence only — not shipped as V1 content** | These are one unidentified end-user's personal edits of Family B/C (`PROGRAM_LOGIC_SPEC.md` §5), not RP-authored reference material. They're valuable proof that the `PowerliftingProgrammingSystem` parameters are independently reconfigurable (day-map, deload placement) by a real user, but shipping someone's personal customization as an official TrainingOS built-in has no source authority behind it. If product wants a "custom powerlifting" example program for onboarding/demo purposes, that's a legitimate but separate design decision — not implied by these files existing. |

## 4. What this recommendation is not

- **Not a claim that 3 pre-built programs are sufficient long-term** — it's
  a V1 floor. More splits/day-counts become available for free once the
  generator exists (§2 of this doc), without needing new source material
  or new shipped `ProgramDefinition` rows.
- **Not a ranking of training quality.** The selection criterion above is
  "which file best demonstrates a mechanic V1 needs to prove works,"
  not "which file is the best program" — that's outside this analysis's
  scope entirely.
- **Not a decision about Mesocycle sequencing.** Family A's three phases
  ("Basic Hypertrophy" / "Metabolite Focus" / "Resensitization") stay
  unresolved per `OPEN_PROGRAMMING_QUESTIONS.md` §2; the #1 recommendation
  above ships as a single phase (Basic Hypertrophy) until that's settled,
  rather than guessing a sequencing/gating behavior into a shipped
  program.

## 5. Missing modality coverage, restated

None of the 3 recommended pre-built programs, nor the generator's
parameter space, cover endurance or functional-fitness modalities — the
source material doesn't address them at all (`PROGRAM_FAMILY_MATRIX.md`
§4). V1's program library is hypertrophy + powerlifting-strength only;
this is a coverage gap to flag to the product owner, not something to
paper over with an invented program.
