# Stage 10R.1C — Source RM Calibration Design & Audit

**STATUS: APPROVED AND IMPLEMENTED.** This document was originally a
design/audit-only pass; the user approved it (Decisions 1-4, see
`STAGE10R1C_SOURCE_RM_CALIBRATION_IMPLEMENTATION_REPORT.md`) and it has
now been implemented exactly as designed — generically for every
`.rmBased` family, not Hypertrophy-specific. Nothing committed, nothing
pushed, Mesocycle 2/3 untouched, source progression untouched, Stage
10B.6 not revived, no e1RM/RM-estimator introduced.

**Source-fidelity guard re-verified before implementation (per your
instruction):** the recovered `3day_original_downloads.txt` extraction
confirms every one of the 24 rows' `G` column (the 10RM input cell) is
an independent, un-linked cell — no formula anywhere references another
row's `G` cell. This means the workbook's raw structure *permits* a
different value per row even for a repeated exercise (e.g. "Horizontal
Push"/Barbell Bench Press appears on all 3 days, each with its own `G`
cell). However, nothing in the recovered documentation or cell evidence
shows this was ever *exploited* — no rating/comment/formula treats a
repeated exercise's rows as intentionally divergent, and a real 10RM is
physically a property of the movement, not the day it's trained on. Per
your explicit approval of the `(ProgramInstance, Exercise, RMType)`
identity with this exact repeated-exercise case already named in your
decision, this was implemented as approved — one calibration per
distinct exercise+RMType per instance, not per row/slot.

---

## Part 1 — RM semantics audit

| Type/field | File | Intended meaning | Writers (production) | Readers | Families that consume it |
|---|---|---|---|---|---|
| `ExercisePerformanceProfile.estimatedOneRepMax: Double?` | `ExercisePerformanceProfile.swift:16` | Doc comment: "an estimated 1RM." A single, generic, exercise-global estimate. | **None.** Grepped every production file — `LogSetUseCase`/`RecordSetResultUseCase` never write it; no e1RM formula exists anywhere in the codebase. Only test fixtures construct it directly. | `SubstitutionAwareRecommendation.resolve` | Hypertrophy (Family A) *and* Powerlifting (Families B/C) — same generic field, no per-family distinction |
| `ExercisePerformanceProfile.confidence: Double` | same file | 0...1, gates whether `estimatedOneRepMax` is trusted at all (`profile.confidence > 0`) | Never written in production (defaults to `0` at construction — `PerformanceProfileStore.exerciseProfile`) | `SubstitutionAwareRecommendation.resolve` | same as above |
| `RMBasedLoad.rmType: RMType` | `StrengthProgressionRules.swift:51-55` | Discriminator: which rep-max basis (`.rm10`/`.rm8`/`.rm5`) this rule is *supposed* to be anchored to | Set once, per slot, by whichever generator authors the `PrescriptionTemplate` (`HypertrophyProgramGenerator`, `PowerliftingProgramGenerator`) | **Nothing.** Confirmed by direct grep of `StrengthProgressionEngine.swift`: `payload.rmType` is never referenced inside `resolveWeight`. | Family A (`.rm10`), Family B (`.rm5`/`.rm8` per slot), Family C (`.rm10`) |
| `RMType` cases (`.rm10`/`.rm8`/`.rm5`) | same file | Labels for 10RM/8RM/5RM bases | n/a (enum) | n/a — stored metadata only, never consulted by arithmetic | A/B/C |
| `StrengthProgressionEngine.resolveWeight(...rmKilograms:...)` | `StrengthProgressionEngine.swift:39-44` | A **bare, opaque scalar** — "whatever tested number this rule's `weekOneFactor` was calibrated against" | n/a (function parameter) | Multiplies it by `weekOneFactor` directly. **Never inspects `rmType`, never converts between bases.** | A/B/C — identical code path |
| `SubstitutionAwareRecommendation.resolve(...).referenceOneRepMax` | `SubstitutionAwareRecommendation.swift:47-82` | Reads `estimatedOneRepMax` directly, or a related exercise's, at reduced confidence; otherwise `nil`/`.calibrationRequired` | n/a | `RollTacticalWindowUseCase.strengthSlotContext` | A/B/C — same generic path for every family |
| `SlotContext.rmKilograms: Double?` | `StrengthMaterializer.swift` | Week-0 input handed to the engine | `RollTacticalWindowUseCase.strengthSlotContext` (week 0 branch) | `StrengthMaterializer.materializeWeek` | A/B/C |
| `PersonalRecord` | `PersonalRecord.swift` | A scored, banded (`repBand`) best result — e.g. best-known set at a given rep count | `RecordSetResultUseCase.recordSet`, on every logged set that beats the existing best for its `repBand` | UI (progress history), `ScoringEngine` | Not RM-based at all — a different concept (best logged performance, not a resolved test value) |
| `SetResult` | `SetResult.swift` | One logged, dated set (weight/reps/RIR) | `RecordSetResultUseCase.recordSet` | UI ("PREVIOUS" panel), `ExercisePerformanceProfile.setResults` | Universal — every modality |

**What `estimatedOneRepMax` actually represents, semantically, today:** nothing concrete. It is a stub field with a plausible-sounding name and a read path already built around it (`SubstitutionAwareRecommendation`), but zero production writers. Its doc comment says "1RM." Nothing in the codebase currently distinguishes a 1RM from a 10RM/8RM/5RM at the point of use — `resolveWeight` treats `rmKilograms` as whatever number `weekOneFactor` expects, and `weekOneFactor` is chosen per-family assuming a SPECIFIC basis (0.85 for Family A assumes a real 10RM; 0.7/0.95 for Family B assume a real 5RM; 0.95 for Family C assumes a real 10RM). **`rmType` is authored correctly per slot but is never enforced or consulted anywhere — it is inert metadata.**

### Direct answer to the worked example

> "If the user enters Barbell Bench Press 10RM = 80 kg, what exact value should reach `resolveWeight(...rmKilograms:)`?"

**80 kg — unconverted, exactly as entered.** `weekOneFactor: 0.85` (Family A's Basic Hypertrophy factor) is a multiplier calibrated specifically against a *real 10RM* input; `resolveWeight` performs no unit/basis conversion of any kind. The current architecture, if `estimatedOneRepMax` were ever wired up as it exists today, would be a **semantic mismatch**: that field's stated meaning ("estimated 1RM," a fundamentally different, larger quantity than a 10RM) would flow straight into a `weekOneFactor: 0.85` multiplier calibrated for a 10RM, silently producing an incorrect Week-1 load with no error and no reason code distinguishing it from a correct calibration. This is not a hypothetical concern confined to Hypertrophy — Family B's `.rm5` slots (`weekOneFactor: 0.7`) and `.rm8` slots (`weekOneFactor: 0.95`) share the exact same acquisition path and would be equally corrupted the moment `estimatedOneRepMax` is ever populated by *any* future code, even code written for an unrelated reason.

**Conclusion: `ExercisePerformanceProfile.estimatedOneRepMax` is the wrong storage location for this feature, both semantically (1RM ≠ 10RM/8RM/5RM) and structurally (global-per-exercise vs. the source's fresh-per-mesocycle requirement — see Part 3).**

---

## Part 2 — Source RM requirements by family

| | **Family A** (Hypertrophy) | **Family B** (Powerlifting Strength) | **Family C** (Powerlifting Hypertrophy-block) | **Family D** (Strength_Program_1/2) |
|---|---|---|---|---|
| What's entered | 10RM per exercise | RM per slot — basis is a **hardcoded label per slot**, not derived from the exercise chosen | 10RM per slot | Same field layout as B/C lineage — **never populated in either surviving file** |
| Basis | 10RM (uniform) | Mixed: 5RM (Legs×2/Push×2/Deadlift), 8RM (Hamstring/Upper-Pull×2/Shoulder×2) — `PROGRAM_LOGIC_SPEC.md` `FAMILY_B_RM_BASIS`, sheet cells `H3:H7='5RM'`, `H8:H12='8RM'` | 10RM (uniform) — `FAMILY_C_RM_BASIS` | B's 5RM/8RM (Program_1) or C's 10RM (Program_2), inherited, unused |
| Granularity | Per exercise-slot | Per exercise-slot (10 category slots) | Per exercise-slot (16 weekly rows / 10 categories) | Same structural layout as lineage |
| Once per mesocycle / carried over | Once per mesocycle, **never carried over** (`PROGRAM_LOGIC_SPEC.md` §2.2 — explicit) | N/A — single self-contained 4+1 week block, not multi-mesocycle; not addressed | Same as B — single block | Not established (blank) |
| Retested within mesocycle | Not documented | Not documented | Not documented | Not established |
| Formula-derived? | **No** — manual entry only, confirmed by direct cell inspection (no formula ever computes it) | **No** — manual entry (sheet b's RM cell) | **No** — same convention | **No** (convention inherited; cells simply empty) |
| Shipped in TrainingOS today | Yes | Yes | Yes | **No** — confirmed evidence-only, not part of `V1_PROGRAM_LIBRARY.md` |

**The one universal invariant across every real, shipped family: the RM/test value is always a real, physically-tested number a human enters, never a spreadsheet formula.** Family D adds nothing new (it's the same engine, hand-edited, never populated) and confirms the underlying "one configurable Powerlifting system" architecture decision — it does not change any of the above.

**Design implication:** any calibration mechanism must (a) never derive a value automatically, (b) be keyed by exercise-slot (not globally per exercise-forever), and (c) explicitly carry which basis (10RM/8RM/5RM) was entered, since Family B alone mixes two bases within a single program and the engine has no way to tell them apart on its own.

---

## Part 3 — Domain model recommendation

Evaluated:

- **A. Reuse `estimatedOneRepMax`** — rejected. Wrong semantic (a generic "1RM estimate" concept, not a literal per-mesocycle tested 10RM/8RM/5RM), wrong scope (permanent/global per exercise, contradicting Family A's explicit non-carry-over rule), and carries no `RMType` tag — reusing it would silently conflate three different rep-max bases the moment two families' data ever coexisted.
- **B. Rename/generalize the existing field** — rejected. Renaming doesn't fix the scoping problem (still global-per-exercise), and it would permanently entangle this feature with whatever future "true estimated 1RM from training history" feature might legitimately want that field for a *different* purpose — exactly the "two concepts that may not mean the same thing" risk you flagged. Keep them structurally separate.
- **C. Add explicit source calibration state with an RM type** — necessary, but insufficient alone without D.
- **D. Store per program/mesocycle instance rather than globally** — **required.** Family A's own documented behavior ("blank and independent... nothing carries... from one phase to the next") cannot be modeled by anything scoped globally to `Exercise`.

**Recommendation: C + D together** — a new entity, modeled directly on the already-proven `SlotSelectionOverride` shape (`SlotSelectionOverride.swift`), which already solves an almost identical problem ("one authoritative, `ProgramInstance`-scoped value for a template slot, distinct from the shared template graph and from any global per-exercise state"):

```swift
@Model
final class SourceCalibration {
    var id: UUID
    var programInstance: ProgramInstance?      // scoping unit — satisfies "fresh per mesocycle"
    var exercise: Exercise?                    // which real exercise this value is FOR
    var rmType: RMType                         // which basis was entered (10RM/8RM/5RM) — makes the value self-describing
    var valueKilograms: Double                 // the literal entered number, unconverted
    var enteredAt: Date
}
```

At materialization time, `strengthSlotContext`'s week-0 branch would look up a `SourceCalibration` for `(instance, resolvedExercise)` whose `rmType` matches the slot's own `rules.loadRule`'s `rmType`, and use `valueKilograms` directly as `rmKilograms` — no conversion, no estimate, no formula. `ExercisePerformanceProfile`/`estimatedOneRepMax` stays completely untouched, reserved exclusively for whatever a genuinely different future "estimated 1RM from history" feature might someday be.

**One decision this design does not resolve unilaterally (flagged for you, Part 15):** should the calibration be keyed at `(instance, exercise)` granularity (one value shared by every slot/day that resolves to the same exercise within the mesocycle — lower friction, matches how a human actually thinks about "my Bench Press 10RM") or at `(instance, PrescriptionTemplate/slot)` granularity (matching the workbook's literal row-independence, where two rows referencing the same real movement technically have two separate input cells)? Nothing in the recovered source documentation states whether a real user re-entered the same number per row or expected it once — this genuinely wasn't captured by the recovery, and I am not inferring it.

---

## Part 4 — UX design

**New user, first mesocycle (case 1):**
1. Program selected → `ProgramDefinition` generated (unchanged), exercise slots resolved (already happens today, at generation/instance-creation time, since Slice 1A/1B pre-resolve `ExerciseSlot.resolvedExercise` directly on the shared template graph).
2. A new, pure query (`RequiredSourceCalibrationsUseCase` or similar) walks the definition's `.rmBased` templates and their resolved exercises, and returns the distinct `(Exercise, RMType)` pairs that have no `SourceCalibration` yet for the about-to-be-created instance.
3. If that list is non-empty, present a **"Set your starting weights"** screen, one row per required `(Exercise, RMType)`, before Week 1 is ever materialized. Each row offers exactly two paths (case 2 and case 3 below) — never a silent default.

**Case 2 — user knows their 10RM/8RM/5RM:** a plain numeric entry field, labeled with the specific basis this slot needs (e.g. "Barbell Bench Press — 10RM"). Writes a `SourceCalibration` directly (`rmType` matches what was asked for, `valueKilograms` = the literal entered number).

**Case 3 — user doesn't know it:** a source-compatible, deliberately minimal option — *"Test this before starting"* — a short explanatory line ("Perform a real 10-rep-max attempt for this exercise, then come back and enter the result") and nothing more. **No automated testing protocol, no estimate, no fallback number** — the program simply cannot materialize a Week-1 load for that slot until the user returns with a real value. This matches the source exactly: the workbook has no derivation path either.

**Case 4 — returning user, new mesocycle:** because calibration is scoped per `ProgramInstance` (Part 3), a new instance has zero `SourceCalibration` rows and the gate above fires again automatically — no code path needs to "remember not to reuse" the old value, because there is structurally nothing to reuse. The UI may show the prior instance's value as read-only reference (a simple lookup: same `Exercise`/`RMType`, most recent prior `ProgramInstance`), clearly labeled **"PREVIOUS: 82.5 kg"**, visually and semantically distinct from the **"CURRENT MESOCYCLE CALIBRATION"** input field the user must still fill in themselves.

**Case 5 — exercise substitution:** `SubstituteExerciseUseCase.substituteGoingForward` already writes a `SlotSelectionOverride` (instance+slot scoped). Recommendation: a substitution that changes a `.rmBased` slot's resolved exercise must re-run the same required-calibration check for the *new* exercise — if no `SourceCalibration` exists for `(instance, newExercise, rmType)`, that slot's next materialization correctly falls back to today's existing `.calibrationRequired`/blank behavior until recalibrated. **No automatic transfer from the old exercise's value.** This needs no new mechanism beyond re-surfacing the same calibration prompt at the substitution moment — but see Part 9: `RollTacticalWindowUseCase.rollForward` (the only function that would ever re-materialize week 2+ with a substituted exercise) has zero production call sites today, so this specific scenario is not yet reachable in the shipped app regardless of this feature.

---

## Part 5 — Materialization timing

Traced the real sequence:

1. **Program structure creation** — `HypertrophyProgramGenerator.generate`/`PowerliftingProgramGenerator.generate`: user-independent, happens once per `ProgramDefinition`, already fully separate from any instance.
2. **Exercise resolution** — happens at two points today: (a) generation time for source-recovered configs (Slice 1A pre-resolves directly on the shared `ExerciseSlot`), and (b) `StartPhaseUseCase.start` calls `ResolveProgramInstanceExerciseSlotsUseCase.resolve` again (a no-op for already-resolved slots, per its own idempotent contract). Either way, exercise resolution is **not** the blocker — it already completes before materialization.
3. **RM values become required** — the instant `strengthSlotContext`'s week-0 branch runs, which today happens **synchronously, inside the same `StartPhaseUseCase.start` call**, immediately after instance creation and slot resolution (`StartPhaseUseCase.swift:135-165`): `start()` creates the `ProgramInstance`, resolves slots, then unconditionally calls `RollTacticalWindowUseCase.materializeFirstWindow` in the same function body, and **throws if it yields no sessions** (`StartPhaseError.noExecutableComponents`).
4. **Week 1 materialized** — as part of step 3, permanently (`StrengthMaterializer`'s own doc comment: "already-materialized Sessions are never revisited").
5. **Sessions visible on Today** — a separate, unrelated read (`TodayViewModel`'s existing date-range query over already-materialized `Session`s).

**Finding: today's architecture does *not* yet have a resting state between "instance exists, slots resolved" and "week 0 materialized" — they are one atomic call.** Separating them is naturally supported (`materializeFirstWindow` is already its own distinct function, just invoked immediately), but genuinely requires a small, real change: `StartPhaseUseCase.start` needs to stop *unconditionally* calling `materializeFirstWindow` in the same breath as instance creation for `.rmBased` programs missing required calibration, and a separate, later step needs to perform that deferred materialization once calibration is confirmed satisfied.

**This is not "retroactively mutate a frozen prescription."** The one-time, never-revisited materialization invariant stays completely intact — we are only moving *when* that one-time event happens (after calibration, instead of immediately), never touching an already-materialized week afterward. I recommend this over any retroactive-mutation approach, exactly per your stated preference, and confirmed by the audit that the architecture already has the right seam (`materializeFirstWindow` as a distinct call) to support it without inventing a new frozen/unfrozen state machine.

---

## Part 6 — Load-first overlay seam (not implemented)

Calibration answers *"what is the user's tested RM anchor"* — strictly upstream of and orthogonal to progression. The future load-bias overlay modifies *how load progresses from that anchor* (`weekOneFactor`/`laterWeekMultipliers`/an entirely different rule), never *what the anchor itself is*. The only seam worth preserving now: keep `SourceCalibration` (or whatever the calibration store ends up being called) as the single, uncontested source of the RM anchor, so a future overlay rule can read the *same* calibrated value rather than inventing a second calibration path. Nothing to build yet.

---

## Part 7 — Test plan (design only)

1. Entering a calibration produces the exact literal Week-1 load (`rm * weekOneFactor`, rounded through the equipment profile) — no conversion applied.
2. Equipment-increment rounding still applies correctly on top of the entered value.
3. Two different exercises calibrated independently never cross-contaminate each other's resolved load.
4. A second `ProgramInstance` (simulating a new mesocycle) has no calibration until entered again — proves no silent carry-over.
5. The previous instance's calibration is readable as reference data but never auto-populates the current instance's required input.
6. Substituting to a different exercise mid-instance does not inherit the original exercise's calibration — the new exercise requires its own.
7. A `.rmBased` slot with no matching `SourceCalibration` still resolves to `(nil, .calibrationRequired)` — unchanged, existing behavior.
8. Family B's mixed `.rm5`/`.rm8` slots each require and use their own correctly-typed calibration — a `.rm5`-tagged calibration must never satisfy an `.rm8`-tagged slot (or vice versa) even for the same exercise.
9. Logging an ordinary `SetResult` (via `LogSetUseCase`) never creates or modifies a `SourceCalibration` — calibration is only ever written by the explicit entry flow.
10. No e1RM/Epley/Brzycki formula appears anywhere in the new code.
11. Every existing Family A/B/C `StrengthProgressionEngine`/`StrengthMaterializer`/deload test continues to pass unmodified — this feature only supplies an input, never changes the engine's arithmetic.

---

## Part 8 — Report

**1. Current RM architecture.** One generic, family-agnostic path: `SubstitutionAwareRecommendation.resolve` reads `ExercisePerformanceProfile.estimatedOneRepMax` (permanently `nil` in production — no writer exists anywhere) and feeds it as `SlotContext.rmKilograms` into `StrengthProgressionEngine.resolveWeight`. `RMType` (`.rm10`/`.rm8`/`.rm5`) is stored per slot but never read by the engine or the acquisition path — it is inert metadata today.

**2. Exact semantic mismatch.** `estimatedOneRepMax` means "a 1RM," a fundamentally different (and larger) quantity than the 10RM/8RM/5RM the source workbooks actually require and than `weekOneFactor` is calibrated against. Even setting aside the "estimated vs. literal" distinction, a 1RM value fed into a `weekOneFactor` meant for a 10RM (or 5RM, or 8RM) would silently produce a wrong load with no error. This risk already exists for Powerlifting (Family B/C) today, not just Hypertrophy, since they share the identical acquisition code.

**3. Source RM requirements by family.** All three shipped families (A/B/C) require a manually-entered, physically-tested RM per exercise-slot — never derived, never formula-computed. Family A = 10RM, never carried over between mesocycles. Family B = mixed 5RM/8RM per slot. Family C = uniform 10RM. Family D exists only as unpopulated evidence and is not shipped.

**4. Recommended domain model.** A new, explicit `SourceCalibration`-style entity — not a reuse or rename of `estimatedOneRepMax` — carrying `rmType` and a literal `valueKilograms`, so the stored value is self-describing and can never be silently misapplied across bases.

**5. Recommended persistence model.** Scoped to `(ProgramInstance, Exercise[, RMType])`, modeled directly on the already-proven `SlotSelectionOverride` shape — never globally per `Exercise`. This is what makes "fresh per mesocycle, never carried over" true by construction rather than by convention. One open granularity question (per-exercise vs. per-slot) is flagged for your decision, not resolved unilaterally.

**6. Recommended UX.** A "Set your starting weights" step inserted between program/mix selection and Week-1 materialization, offering only "enter it" or "test it first" (no automatic estimate), with prior-mesocycle values shown strictly as labeled, non-authoritative reference.

**7. Recommended insertion point.** Between exercise-slot resolution and `RollTacticalWindowUseCase.materializeFirstWindow` — today these happen back-to-back inside one `StartPhaseUseCase.start` call; the recommendation is to defer the `materializeFirstWindow` call specifically (not instance/slot creation) until required calibrations are satisfied.

**8. Materialization changes required.** `StartPhaseUseCase.start` needs to stop unconditionally materializing week 0 in the same call as instance creation for `.rmBased` programs with missing calibration; a new, separate "materialize now that calibration is satisfied" step is needed. No retroactive mutation of an already-materialized week is introduced or needed.

**9. Exercise-substitution behavior.** A substitution never carries over the old exercise's calibration; the new exercise must be separately calibrated, using the existing `.calibrationRequired` fallback exactly as it already behaves today when no RM is available.

**10. Mesocycle-boundary behavior.** Handled for free by scoping calibration to `ProgramInstance` rather than `Exercise` — a new instance has no calibration rows, forcing fresh entry automatically, with the prior instance's value visible only as clearly-labeled reference.

**11. Impact on existing Powerlifting/Strength paths.** None to the engine or deload logic. Powerlifting shares the exact same acquisition gap today (confirmed: `.rmBased`/`RMType`/`SubstitutionAwareRecommendation` are all already used identically by Family B/C) — this design closes the gap for all three families at once via the same generic mechanism, not a Hypertrophy-specific patch.

**12. Exact implementation slices (for a future, separately-approved pass — not now):**
   - Slice A: `SourceCalibration` entity + persistence + a pure "which calibrations are still required" query.
   - Slice B: split `StartPhaseUseCase.start`'s materialization call behind the calibration gate; add the deferred-materialize step.
   - Slice C: the "Set your starting weights" UI (enter / test-first paths, previous-value reference display).
   - Slice D: substitution-triggers-recalibration wiring.
   - Slice E: source-derived test matrix (Part 7).

**13. Test plan.** Listed in full in Part 7 above.

**14. Newly discovered source-vs-TrainingOS conflicts / related gaps.**
   - `RMType` is authored per slot but never consulted by the engine anywhere — a live semantic landmine for *any* future code (not just this feature) that ever populates `estimatedOneRepMax`.
   - `RollTacticalWindowUseCase.rollForward` (the only function that would ever materialize week 2+, including after a mid-mesocycle substitution or a real rating) has **zero production call sites** today — a separate, pre-existing gap that bounds what "returning user"/"substitution during an active mesocycle" can even mean in the shipped app right now, independent of this feature.
   - Family B/C's own source documentation never states whether 10RM/8RM/5RM is retested within a mesocycle or how repeated-exercise rows (same movement, multiple slots) were really handled by real users — genuinely unknown, not inferred here.

**15. Decisions needed from you before implementation:**
   1. Calibration granularity: per-exercise (one entry reused across every slot/day using it within the instance) vs. per-slot/template (literal, independent per row, matching the workbook's own structure exactly).
   2. Whether the "test it first" case needs any structured follow-up (e.g. a reminder/badge) or is purely a static informational message with manual re-entry later.
   3. Whether to build this for Hypertrophy only first, or for Hypertrophy + Powerlifting together in one slice, given both already share the identical gap and mechanism.
   4. Whether `StartPhaseUseCase.start`'s split (Part 5/12 Slice B) should apply to *every* `.rmBased` program from day one, or be scoped narrowly to the 3-Day Full Body Mesocycle 1 configuration first, consistent with this project's "don't generalize too early" discipline.

---

Per your stop condition: nothing implemented, nothing committed, nothing pushed, Mesocycle 2/3 untouched, source progression untouched, Stage 10B.6 not revived, no automatic RM estimator introduced. Waiting for your decisions above.
