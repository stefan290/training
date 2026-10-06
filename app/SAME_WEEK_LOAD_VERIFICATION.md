# Same-week execution load recommendations

Base: 915035b164a004d93cf36e5ac5945e758f8028c2, verified preview checkpoint.

## Behavior

A working movement opened for execution uses the owner's latest result-driven
load recommendation for FF-owned RM-based resistance or double-progression
slots. Existing source-backed RM progression keeps its existing overlay.
Recommendations are separate optional fields on ExercisePrescription. The
original SetPrescription targets and actual SetResults are never rewritten.
Guidance is frozen when first shown, saved immediately and reused on reload.
It is keyed to the canonical exercise to avoid reuse after substitution.
Warm-up sets, historical sessions and already-attempted legacy movements do
not receive a new snapshot. Accepted readiness adaptations retain their own
adapted target. If the latest FF evidence was readiness-adapted, no new
live recommendation is created from it. Failed snapshot saves fall back to the original target.

The FF path accepts an explicit asOf date and retains existing calibration
fallback. The V2 path reuses the existing exercise-history and progression
policy; no new training thresholds or progression rules are introduced.

## Tests and limits

Eight new tests use real FF generation/logging and the actual execution VM.
A repeated exercise fixture is attached to another real session in the same
week, using a copy of the generated targets. This deliberately isolates the
execution seam from the generator's variable exercise selection.
Tests cover increase, decrease, freeze/reload, attempted movement protection,
missing history, exercise change, the double-progression policy dispatch and
historical session protection. The V2 dispatch fixture sets an explicit V2
template tag; it is not a full production hypertrophy-generation proof.

This checkpoint does not unify different method policies, introduce tempo,
or solve accepted-readiness evidence filtering across all progression paths.

## Validation

Author environment: Linux, no Swift/Xcode. git diff --check passes.
Build, XCTest and existing-store migration are NOT yet verified.

Mac verifier: use a separate worktree at the exact PR head and dedicated
DerivedData. Run one Xcode process at a time. Build and run:
- GeneralProgrammingAllocationArchitectureTests
- EndToEndProgressionLoopTests
- DoubleProgressionEngineTests
- LoadFirstProgressionIntegrationTests
- AdvanceTacticalWeekCapabilityWiringTests
- ReadinessAdaptationTests
- SubstitutionTests
- TemplateGraphPersistenceTests

If focused checks pass, run all TrainingOSTests once. Preserve raw logs,
commands and exact tested SHA on a verification branch. Do not fix code or
merge. Report exact build errors/assertions to the implementation owner.

The schema adds four optional fields. Also verify opening an existing
simulator store with prior logged results, without deleting/resetting its
data, and report whether history remains intact. Simulator UI inspection
should confirm Suggested/Why shows the execution guidance while the plan's
original target remains unchanged.
