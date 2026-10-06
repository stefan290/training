# Progression preview consistency, checkpoint 1

Base: a61d823bd45a0f1ba79242c66b7c3fad280a92d1 (the C1 handoff).

FF-owned RM-based resistance completion previews now call the same
ResistanceLoadEvidenceResolver recommendation helper as next-week
materialization. Existing training thresholds, equipment rounding and
calibration fallback remain in place. Source program progression is untouched.
Incomplete or accepted-readiness-adapted FF exposures do not advertise a
result-driven next-load forecast in this checkpoint.

Five regression tests cover a single above-target set, a single missed set,
on-target performance, missing RIR and incomplete logging. Four compare the
completion preview with a real next-week tactical materialization and check
that original target weights and logged result counts survive.

## Validation status

Only static diff/API inspection and git diff --check were possible in the
Linux authoring environment. Swift/Xcode/XCTest are unavailable here.
No claim is made that this commit builds or that the tests pass.

## Mac verification

Use a separate git worktree at the PR head. Do not overwrite the existing
working copy. Run exactly one xcodebuild process at a time, using a dedicated
DerivedData directory for this checkout.

1. Build and run GeneralProgrammingAllocationArchitectureTests,
   EndToEndProgressionLoopTests, DoubleProgressionEngineTests,
   LoadFirstProgressionIntegrationTests and AdvanceTacticalWeekCapabilityWiringTests.
2. If focused checks pass, run the full TrainingOSTests suite once.
3. Preserve exact commands, commit SHA and unfiltered logs. Report failures
   with the failing test and assertion. Do not change code or merge this PR.
4. Publish logs on the verification branch so the implementation owner can
   inspect them directly.

## Remaining core work

This checkpoint does not implement all weight progression. Later checkpoints
must address latest-result recommendations for already-materialized future
sessions, RIR-only/source policy coverage and readiness forecast consistency.
Functional Bodybuilding/CrossFit separation, optional conditioning, tempo
and combined-week product verification remain subsequent core work.
