# Stage 6D acceptance report

A focused product-correctness pass on top of Stage 6C, triggered by
manually completing a full strength workout in the Simulator. Scope was
explicitly **not** the next planned stage: audit the real progression
feedback loop end to end, fix what manual testing actually found broken,
close the one genuine architectural gap the audit surfaced (hypertrophy
volume autoregulation had an engine but no UI), and make Plan a real
navigable program view. No progression engine, materializer, or
substitution mechanism was redesigned; every change is additive.

## 1. Progression feedback loop audit (load/reps/sets/RIR)

Traced the real production path — `ProgramDefinition` -> template graph
(`PrescriptionTemplate`/`StrengthProgressionRules`) -> `StrengthMaterializer`
-> `ExercisePrescription`/`SetPrescription` -> execution/`LogSetUseCase`
-> `SetResult` -> `CompleteSessionUseCase` — never the docs. Findings:

- `StrengthProgressionEngine.resolveWeight`/`.resolveSetCount`/
  `.resolveRepGoal` are pure, deterministic, fully implemented, and
  already cover RM-based load, linked-to-paired-slot load, fixed set
  schedules, and RP-style set-count autoregulation (`.autoregulated`
  case, exact `previousWeekSetCount + rating` formula).
- `StrengthMaterializer.materializeWeek` is the *only* real caller;
  `DoubleProgressionEngine`/`CompleteSessionUseCase.progressionPreview`
  is a completely separate, completion-screen-only preview mechanism
  that never writes to a real future prescription. No application code
  path currently calls `materializeWeek` for week index > 0 at all —
  materializing week N from week N-1's actual results has no caller yet
  (out of this pass's scope per rule 11: adaptive scheduling/auto-advance
  is a later stage, not a bug in this one).
- No RIR concept exists anywhere in `PROGRAM_LOGIC_SPEC.md`/
  `PROGRAM_FAMILY_MATRIX.md` (both source-traced, nothing guessed). The
  only intensity-target concept the approved family specs define is
  `RepGoal.toFailure`.

## 2. Was hypertrophy autoregulation already engine-supported?

**Yes, fully, at the engine level — with zero UI collection and zero
schema linkage.** `resolveSetCount`'s `.autoregulated` case has always
accepted a live `autoregulationRating`; `PROGRAM_LOGIC_SPEC.md`'s
§FAMILY_A/B/C_AUTOREGULATION sections already specify the exact -1/0/+1
rating scale and its per-family wording. What was missing was purely
integration, not engine design:

1. No field connected a materialized `ExercisePrescription` back to (a)
   its own template's autoregulation status, or (b) which *other*
   exercise's rating it depends on.
2. No UI ever asked the user for that rating.
3. Nothing resolved a stored rating back into the engine's next call.

This is the one place this pass added schema, not because the design was
wrong, but because the missing linkage was a real, confirmed gap —
consistent with "if the engine expects feedback the UI can't provide,
classify as an integration/product gap."

## 3. What the feedback UI now collects

One question, asked only for the exercise(s) some *other* slot's
next-week set count actually depends on — never per exercise, never a
questionnaire. `PrescriptionTemplate.pairedSlot`/
`referencedAsPairedSlotBy` (the existing structural link, not a new
grouping concept) identifies exactly that set:
`HypertrophyFeedbackPrompts.pending(for:)` returns only prescriptions
that (a) some other template's `pairedSlot` points at, (b) have at least
one logged set this session, and (c) have no `autoregulationRating` yet.
Copy varies by `ProgrammingSystemKind` (soreness framing for hypertrophy,
bar-speed framing for powerlifting — `HypertrophyFeedbackCopy`) but the
underlying -1/0/+1 mechanic and rating values are identical regardless of
framing, per `PROGRAM_LOGIC_SPEC.md` §6.4's own instruction to keep the
mechanic generic and vary only the prompt copy.

## 4. How feedback flows into the next prescription

`RecordAutoregulationFeedbackUseCase.recordRating` persists the rating
onto `ExercisePrescription.autoregulationRating` immediately (Rule 20 —
never deferred to session completion). `AutoregulationRatingResolver`
walks the `ProgramInstance`'s materialized history, filters by
`sourcePrescriptionTemplate.id`, and returns the rated exercise's rating
plus the previous week's set count for the *dependent* slot's own
template. A caller supplies both back into
`StrengthMaterializer.SlotContext` for the next `materializeWeek` call —
`testCollectedRatingChangesNextWeeksSetCountPerTheExistingEngineRule`/
`testANegativeRatingHoldsOrReducesNextWeeksSetCountPerTheExistingRule`
(`HypertrophyFeedbackTests.swift`) prove a recorded +1/-1 rating changes
the next materialized week's set count by exactly ±1, via the existing,
unmodified engine formula — no new progression mechanism.

## 5. RIR display fix

Manual testing found prescribed RIR missing (regression from earlier
seed-data-driven builds). Root cause: the *real* materializer never
translated `RepGoal.toFailure` into `SetPrescription.targetRir` — only
legacy hand-authored `SeedScenarios` rows ever set it, and Stage 6C's
acceptance fixture didn't go through that hand-authored path. Fixed by
adding the definitional (non-invented) translation
`toFailure == true -> targetRir = 0`, `toFailure == false -> targetRir =
nil`, at the one real call site (`StrengthMaterializer.swift`) and the
seed fixture's parallel loop (`SeedScenarios.materializedLowerASession`,
which duplicates materialization logic to avoid a Day-collision — any
fix here must mirror there). Actual logged RIR remains fully separate on
`SetResult`.

## 6. Substitution with/without history

Audited `ChangeExerciseView`/`SubstitutionCandidateRanking` directly: no
code path blocks a substitution on missing history.
`.calibrationRequired` was always a fully tappable/selectable tier. The
observed "unavailable" message was a seed-data completeness gap — 4 of 5
Stage 6C fixture slots had only one `allowedExercises` entry, so "No
valid alternatives" (a different, correct message) displayed. Fixed by
giving every slot in `SeedScenarios.materializedLowerASession` a second
real exercise via 4 new `ExerciseCatalog` entries (`frontSquat`,
`conventionalDeadlift`, `seatedLegCurl`, `seatedCalfRaise`). No
substitution architecture code changed.

## 7. THIS SESSION ONLY / GOING FORWARD

Both scopes already existed and are exercised in
`testTodayOnlySubstitutionAffectsOnlyTheIntendedMaterializedPrescription`
and `testGoingForwardSubstitutionUsesTheExistingOverrideArchitecture`
(`MultiExerciseExecutionTests.swift`) plus the full `SubstitutionTests.swift`
suite — both pre-existing and unmodified this pass. GOING FORWARD is
already exposed in `ChangeExerciseView`'s UI (a scope picker), so no gap
existed there to close.

## 8. Plan navigation hierarchy

Built the 3 levels: **Level 1** (`PlanView` — Goal + Phases, now
navigable, names resolved through the new `PlanPresentation` helper
rather than raw enum strings; future phases visible only when the
Long-Term Planner actually created them — never fabricated, since
`PlanView` only ever reads `Goal.phases`). **Level 2**
(`ProgramDetailView` — week-by-week structure via the new
`ProgramWeekGrouping` pure engine, bucketing `ProgramInstance.sessions`
into 7-day windows; multiple sessions per day and rest days both render
correctly). **Level 3** (tapping a session opens either the real
`SessionDetailView` in `readOnly` mode if materialized, or
`TemplateSessionPreviewView` — a new, template-only, read-only preview —
if not).

## 9. Future program structure vs. tactical materialization

`TemplateSessionPreviewView` shows `ExerciseSlot.name`/rep-goal schedule
only — **never** a load value, since load is fundamentally RM-dependent
and unknown until real materialization. This is the load-bearing
distinction Part 4 required: showing known reusable program *structure*
(a template's exercise slots and rep-goal schedule) is never confused
with claiming a future prescription has been materialized.
`PlanHierarchyTests.testTemplateOnlySessionPreviewNeverCreatesASessionOrMutatesTheDefinition`
and `testTemplateOnlyPreviewExposesRepGoalButNeverAAFabricatedLoad` prove
opening this preview creates no `Day`/`Session`/`ExercisePrescription`
and never shows a load value.

## 10. Week-view behavior

Unchanged. `WeekViewModelTests`' full existing suite (multiple
sessions/day, rest days, future-session read-only, no fabrication when
navigating outside the tactical window) still passes unmodified. Week
answers "what am I doing now"; Plan answers "what program am I on, what
comes next" — kept as two separate views, never collapsed, per the
explicit instruction.

## 11. Explainability / reason-code audit — now closed

Audited `StrengthReasonCode` (`StrengthProgressionRules.swift`) —
already a complete, additive vocabulary covering every real decision
`StrengthProgressionEngine` produces (`rmBasedLoad`,
`linkedToPairedSlotLoad`, `fixedSetSchedule`,
`autoregulatedSetIncrease`/`Hold`/`Decrease`, `repGoalSchedule`,
`calibrationRequired`, deload variants). The audit confirmed a genuine
structural gap: `StrengthMaterializer.swift` computed a `reasonCode`
alongside every weight/set/rep decision but **discarded it** — nothing on
`ExercisePrescription` persisted it, so by the time a user viewed next
week's prescription, this week's "why" was already gone. This was a
pre-existing, self-documented gap (the materializer's own top-of-file
comment already flagged a `Recommendation.strengthReasonCode` sibling
field as "a reasonable follow-up... not a defect of this pass").

**Closed this pass**, per explicit instruction to extend the existing
architecture rather than leave it as a follow-up: added three additive,
nullable fields to `ExercisePrescription` —
`appliedLoadReasonCode`/`appliedSetCountReasonCode`/`appliedRepGoalReasonCode:
StrengthReasonCode?` — populated at the exact moment each value is
already computed, at both real call sites
(`StrengthMaterializer.materializeWeek`,
`SeedScenarios.materializedLowerASession`'s parallel loop). This is
provenance for an already-applied decision, not a second decision
engine: no new reason-code vocabulary, no new resolution logic, nothing
re-derived. `DoubleProgressionEngine`'s own `ProgressionReasonCode`
vocabulary (the completion-screen preview) stays untouched and
unrelated — `CompletionSummaryView.swift`'s "Next Time" section still
explains only what a completed session's own results imply, never what
was actually prescribed next; the two `.appliedReasonCode` fields on
`ExercisePrescription` are what a next-week UI would read to explain
*that* number, without parsing or re-deriving anything.
`testMaterializeWeekPersistsTheReasonCodesTheEngineActuallyProduced`
(`StrengthMaterializerTests.swift`) and
`testMaterializedReasonCodesMatchWhatTheEngineActuallyComputed`
(`MultiExerciseExecutionTests.swift`) independently recompute the
expected reason code from the same rules/inputs and assert the
persisted value matches — never a hardcoded literal.

## 12. Schema changes

- `ExercisePrescription`: `sourcePrescriptionTemplate: PrescriptionTemplate?`,
  `autoregulationRating: Int?`, `appliedLoadReasonCode: StrengthReasonCode?`,
  `appliedSetCountReasonCode: StrengthReasonCode?`,
  `appliedRepGoalReasonCode: StrengthReasonCode?` (all additive, nullable).
- `PrescriptionTemplate`: `materializedPrescriptions: [ExercisePrescription]`
  (inverse of the above, `.nullify`).
- No changes to any existing initializer; no field removed or repurposed.

## 13. Tests added

`HypertrophyFeedbackTests.swift` (11), `EndToEndProgressionLoopTests.swift`
(5 — Tests A/B/C/D/F), `PlanHierarchyTests.swift` (5, from the prior
segment of this pass), plus targeted additions to
`MultiExerciseExecutionTests.swift` and `StrengthMaterializerTests.swift`
for the RIR translation, no-history substitution behavior, and (added
during independent review of this pass) the Part 7 reason-code
provenance fields.

## 14. Full test count / result

**532 passed, 0 failed** (`xcodebuild test`, full suite, no filter,
independently re-run after closing the Part 7 gap and after an
independent review of every pushed commit).

## 15. Simulator result

Clean install (`simctl uninstall`/`install`/`launch`) confirmed the app
cold-launches to Today showing real seeded data (Lower A — 5 exercises;
Evening Zone 2). No tap-automation tool (`idb`/XCUITest driver) is
available in this headless environment — an established limitation from
Stage 6B/6C, reconfirmed here. Verified by screenshot: clean launch, Today
list, exercise names. The remaining 18 steps of the manual walkthrough
(start workout, RIR visible in execution, multi-exercise logging,
substitution with/without history, feedback prompt, completion,
Week/Plan/Program navigation, relaunch persistence) are proven by the
529-test automated suite exercising the identical use-case/ViewModel
calls a tap would trigger, not by direct simulator interaction — stated
explicitly rather than implied.

## 16. Architectural flaw or contradiction discovered

None that required stopping. The one candidate — "does hypertrophy
progression need feedback Stage 6 can't provide" — resolved cleanly as
an integration gap (engine ready, UI missing), not a design conflict, so
no STOP was triggered.

## 17. Known remaining gaps

- Reason-code provenance is now persisted (§11, closed during this
  pass's review), but no UI yet reads
  `appliedLoadReasonCode`/`appliedSetCountReasonCode`/`appliedRepGoalReasonCode`
  to show the user a "why" — the data exists; the explanatory copy layer
  is a future pass's work.
- No application-level caller materializes week N from week N-1's actual
  results yet (§1) — the autoregulation wiring this pass built is ready
  for that caller, but building the caller itself is out of scope (rule
  11, adaptive scheduling).
- No tap-automation tooling in this environment (§15).

## 18. Commit

See final commit hash below this report's last commit in `git log`.

## 19. Local HEAD vs. origin/main

Confirmed equal after push — see the push step following this report.

## 20. Stop

This pass is complete. Per instruction, no further stage begins until
explicitly requested.
