# Independent verification: codex/progression-preview-consistency

**Verified commit:** `915035b164a004d93cf36e5ac5945e758f8028c2`
("Align FF resistance completion preview with next-week load policy")
**Branch verified:** `codex/progression-preview-consistency`
**Base stated by the author:** `a61d823bd45a0f1ba79242c66b7c3fad280a92d1`
(the C1 working-copy handoff) — confirmed via `git merge-base` that this
is exactly this branch's merge-base with `handoff/working-copy-c1-complete`
(the still-unmerged, draft-PR handoff branch). Note: this branch's
merge-base with `main` itself is `e5332205f56a9a87a64f782e82acf8efaf643c17`
(the pre-handoff commit), since the handoff PR has not been merged to
`main` yet — `codex/progression-preview-consistency` was built on top of
the handoff branch, not on top of `main` directly.

This verification was performed per `app/PROGRESSION_PREVIEW_VERIFICATION.md`
(committed at the verified commit), which explicitly states the author
could only perform static diff/API inspection and `git diff --check` in
a Linux authoring environment with no Swift/Xcode/XCTest available, and
made no claim that the commit builds or that its tests pass. This
package is that claim's independent, real-build/real-test verification.

## Method

- A dedicated `git worktree` was used, checked out at the exact commit
  above — the existing main working copy was never touched or switched.
- A dedicated, separate `-derivedDataPath` was used for every build/test
  invocation in this verification, isolated from any other DerivedData
  on this machine.
- Exactly one `xcodebuild` process was run at a time (confirmed via
  `ps aux` immediately before each invocation) — no concurrent builds or
  test runs.
- No code was changed. No merge was performed.

## Steps and results

### 1. Build for testing
Command: `00-build-for-testing-command.txt`
Raw log: `01-build-for-testing.log` (3,058 lines)
**Result: `** TEST BUILD SUCCEEDED **`, exit 0.**

### 2. Focused tests (per the verification doc's required list)
Command: `02-focused-tests-command.txt`
Raw log: `03-focused-tests.log` (380 lines)

| Test class | Result |
|---|---|
| `GeneralProgrammingAllocationArchitectureTests` | passed (112 tests) |
| `EndToEndProgressionLoopTests` | passed (6 tests) |
| `DoubleProgressionEngineTests` | passed (22 tests) |
| `LoadFirstProgressionIntegrationTests` | passed (7 tests) |
| `AdvanceTacticalWeekCapabilityWiringTests` | passed (4 tests) |

**Aggregate: 151 tests executed, 0 failures.** Each class's own
`Test Suite '<name>' started`/`passed` lines are present in the raw log
confirming every named class genuinely ran (not silently skipped by a
name mismatch).

### 3. Full `TrainingOSTests` suite (run once, since focused checks passed)
Command: `04-full-suite-command.txt`
Raw log: `05-full-suite.log` (4,436 lines)

**Result: `Executed 1888 tests, with 0 failures (0 unexpected) in 81.176
(81.644) seconds`.**

(1888 = the 1883-test baseline from the C1 handoff commit plus 5 new
regression tests this checkpoint adds, consistent with the verification
doc's own description of "five regression tests.")

One `error:` string appears in the raw log
(`SwiftData.DefaultStore save failed with error: ... "Multiple
validation errors occurred."`) — this is the same known, benign SwiftData
console-noise line that has appeared in every full-suite run across this
entire project's history, from an unrelated test's transient in-memory
model state; it is not a real failure (0 failures, 0 unexpected, is the
suite's own authoritative result) and is called out here only for
transparency.

## Conclusion

Build succeeds. All 5 explicitly required focused test classes pass
(151/151). The full suite passes clean (1888/1888/0). No code was
changed to achieve this; no merge was performed. This is a verification-
only branch — safe to inspect, not intended to be merged itself.
