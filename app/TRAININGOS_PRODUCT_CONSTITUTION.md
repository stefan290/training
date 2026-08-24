# TrainingOS Product Constitution

**STATUS: PROPOSED. Not yet approved by the product owner. Not committed.**
This document records the standing product principles established by the
original design handoff (`chats/chat1.md`, `project/Training OS Handoff.dc.html`)
and reaffirmed by the Stage 10R investigation (`STAGE10R_SOURCE_PROGRAM_LIBRARY_RECOVERY.md`),
so future stages inherit them without needing to rediscover them. It sits
alongside, and does not replace, `CLAUDE.md`'s existing 21 non-negotiable
rules — this document is about program *content authority*, a dimension
CLAUDE.md's existing rules touch (rules 10, 11, 14, 17) but don't fully
spell out.

---

## 1. The three-layer architecture

Every training program TrainingOS presents to a user is one of exactly
three things, and the three must never be silently conflated:

1. **Authored program content** — a specific, real methodology's rules
   (load progression, rep/set scheme, deload pattern, exercise categories)
   that TrainingOS did not invent. Today this is exclusively the Family
   A/B/C content recovered and documented in `PROGRAM_LOGIC_SPEC.md`,
   `STAGE3_DECISION_MEMO.md`, and `V1_PROGRAM_LIBRARY.md` from the 15
   originally-supplied Excel workbooks + 3 PDFs. TrainingOS's job for this
   layer is **execution, not authorship**: the Program Engine runs the
   methodology exactly as sourced, per the handoff's own words ("the
   Progression Engine needs to execute the methodology rather than merely
   reproduce the spreadsheet").
2. **TrainingOS orchestration** — genuinely TrainingOS's own, and
   correctly so: which program(s) a user's goal/availability/preference
   selects (`LongTermPlanner`), how multiple modalities share a calendar
   (`ConcurrentScheduler`), how a program adapts same-day to readiness
   (`EvaluateReadinessAdaptationUseCase`), how a slot substitutes to a
   different exercise (`SubstitutionValidator`), how a warm-up is derived
   (`GenerateWarmupSequenceUseCase`). None of this layer claims to be
   sourced content, and none of it should — it is scheduling/orchestration
   intelligence sitting *around* whichever program content it's handed.
3. **TrainingOS execution adaptation** — narrow, explicitly-labeled,
   bounded modifications *of* a specific sourced program's own rules
   (e.g. the approved "prefer visible load progression over reps when
   both are reasonable" tie-break). This layer is legitimate and was
   always anticipated by the handoff and by CLAUDE.md rule 14
   ("subject to explicit user training preferences") — but it must be
   implemented as an additive layer on top of the sourced rule, never as
   a replacement of the rule vocabulary that computes it. See §4.

Functional Fitness, Steady-State, and Interval training have no supplied
source material at all (`OPEN_PROGRAMMING_QUESTIONS.md` §9) — every one of
their numeric rules is, correctly and explicitly, layer-2/layer-3
TrainingOS-designed content, already labeled as such throughout
`PROGRAMMING_SYSTEM_MODEL.md`'s Stage 4C/4D/4E sections. This constitution
does not ask those modalities to pretend to a sourcing authority they
don't have — it asks Hypertrophy/Powerlifting, which *do* have one, to
stop losing track of it.

## 2. Worked example — Muscle Gain phase, restated

A user on a Muscle Gain goal, with 3 available training days, should have
their Hypertrophy component resolve to **an existing, named, sourced
3-Day Hypertrophy program** (`V1_PROGRAM_LIBRARY.md` configuration #1,
traceable to `4847f523-3_day_full_body_Novice.xlsx`) as its anchor — not
a TrainingOS-invented rule set that happens to also produce 3 sessions a
week. `LongTermPlanner`/`ConcurrentScheduler` (layer 2) select and place
that program; they do not, and must never, author its progression rules.
If the user's approved load-vs-rep preference (layer 3) applies, it
modifies *that* program's own numbers additively — it does not replace
the program the planner selected with a different one under the same
name.

## 3. The Final Product Invariant

**An informed user who was told "this is a 3-Day Full Body Hypertrophy
program" should, after all TrainingOS orchestration and execution
adaptation is applied, still recognize the underlying source program** —
its rep/set shape, its RIR/failure philosophy, its deload mechanic — even
if TrainingOS's own scheduling, substitution, readiness, or bounded
progression preferences have visibly touched the day-to-day experience.
**A user should never be silently handed a different methodology under a
name that implies continuity with a specific sourced program.** This is
the invariant Stage 10B.6 violated for configuration #1: a user selecting
"3-Day Full Body Hypertrophy" received a rule system with a different
rep philosophy (ranges + RIR trajectory, never to failure) and a
different load mechanism (performance-reactive, not %RM-scheduled) than
the program that name refers to in `V1_PROGRAM_LIBRARY.md`, with no
labeling anywhere in the running app to signal the substitution.

## 4. Rules for future stages (the "Product Constitution Check")

Every future stage's design document and implementation report must
answer, explicitly, before any progression-rule code is written or
merged:

1. **Does this `ProgramDefinition`/configuration trace to a real source
   workbook** (check `V1_PROGRAM_LIBRARY.md`'s table, restated and
   expanded in `STAGE10R_SOURCE_PROGRAM_LIBRARY_RECOVERY.md` §2's full
   program library matrix)? Answer yes/no, explicitly, in the report.
2. **If yes, is this change an additive layer, or a replacement of the
   rule vocabulary** (`LoadRule`/`SetCountRule`/`RepGoal`/`DeloadStrategy`)
   the sourced program uses? A replacement requires an explicit,
   separate product-owner decision that names the sourcing fact plainly
   (see the recovery document's §19 "TrainingOS MAY vs. SHOULD NOT" and
   §4/§12's confirmed example of exactly this failure) — not a decision
   framed only in engineering or training-science terms.
3. **Is `ProgramProvenance` set correctly** on every `ProgramDefinition`
   this stage touches or creates — `.sourced(file:sheet:cell:)` for
   anything tracing to real content, `.constructed(reason:)` for anything
   that doesn't? A stage that changes a configuration's rule vocabulary
   without updating its provenance is a documentation defect on its own,
   independent of whether the change itself was approved.
4. **If a sourced program's shape is believed to be wrong, undesirable,
   or superseded**, the stage's own audit must say so in exactly those
   terms — "this is real, originally-supplied program content; are we
   choosing to knowingly deviate from it, or add an alternative alongside
   it?" — not merely "should this training pattern be replaced?" The two
   questions read as similar but carry very different stakes, and only
   the first one lets the product owner make an informed call.
5. **A new custom program (any modality) is never authored with
   TrainingOS's own invented rule content unless the product owner has
   explicitly asked for a TrainingOS-original program**, distinct from
   asking for an adaptation of, or a variant tied to, an existing sourced
   program. Confusing "design a 5-Day split" with "recover/extend the
   real 5-Day source program" is exactly the ambiguity that led to Stage
   10C.2 — future requests should disambiguate this explicitly up front.

## 5. Relationship to CLAUDE.md

This document does not modify or supersede any of CLAUDE.md's 21 rules.
It specifically sharpens the application of:

- **Rule 10** ("do not invent ambiguous training rules") — extended here
  to cover not just *inventing new* rules, but *silently replacing
  existing sourced rules* with invented ones under the same program name.
- **Rule 11** ("do not silently expand V1 scope... the full planning
  engine, the full progression engine... out of scope until explicitly
  requested") — reaffirmed: no stage should build a parallel,
  TrainingOS-originated progression engine for content that already has
  a sourced engine, without that being the explicit, named request.
- **Rule 14** ("user-selected training modalities must not be silently
  replaced by theoretically more optimal modalities") — generalized here
  from *modality* selection to *program-rule* selection: a user-selected
  named program's own rules must not be silently replaced by a
  theoretically-preferred rule system either.
- **Rule 17** ("a theoretically optimal program the user does not want to
  perform is not practically optimal... must never attempt to predict
  motivation or adherence using an opaque model") — the same discipline
  applies to *methodology* substitution: TrainingOS's own judgment that a
  sourced program's training philosophy is suboptimal (Stage 10B.5's
  correct, honest finding) is not, by itself, authority to replace that
  program's content without the product owner's explicit, informed
  sign-off.

## 6. What this constitution is not

- It is not a claim that Family A's literal-failure ramp is objectively
  better or worse training than Hypertrophy V2's rep-range/RIR model —
  that is a training-science and product judgment call reserved for the
  product owner, informed by (not decided by) this document.
- It is not a rollback of Stage 10B's day-focus/N-slot/`SlotRole`
  construction, autoregulation-fan-out fix, readiness, warm-up, or Stage
  10C.1's catalog work — none of that is implicated.
- It is not a license to stop building TrainingOS-original content where
  none exists (Functional Fitness, Steady-State, Interval) — those
  remain correctly, explicitly TrainingOS-designed, and should stay that
  way, clearly labeled.
- It does not itself implement any recovery slice — see
  `STAGE10R_SOURCE_PROGRAM_LIBRARY_RECOVERY.md` §23 for the proposed,
  not-yet-approved recovery plan (six slices).
