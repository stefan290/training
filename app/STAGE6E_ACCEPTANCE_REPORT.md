# Stage 6E acceptance report

**Manually accepted.** Triggered by a manual Simulator report: after
completing "Lower A," the Session could no longer be reopened from
Today. Scope was narrow and explicit: make a completed Session
inspectable, read-only, without a full analytics/history product and
without touching HealthKit, Charts, or the next planned stage.

## 1. Root cause

`SessionDetailView` routed on `readOnly || session.status == .scheduled`.
A completed Session opened with Today's own default (`readOnly: false`)
failed that check and fell into the live per-block execution list — the
same screen used to log sets on an in-progress workout, with no route to
a real summary of what happened.

A second, distinct defect surfaced during the manual acceptance pass
itself: even after routing was fixed, the completed card on Today could
not actually be tapped. `SessionCard` (Today), `sessionRow` (Week), and
`realSessionRow` (Plan) each wrap a fully custom label in
`NavigationLink { ... } label: { ... }.buttonStyle(.plain)` with no
`.contentShape()`. A completed Session's card renders no button of its
own (Start/Mark Missed only ever show for `.scheduled`), so the whole
card relied on SwiftUI's default label hit-testing — which reliably
registers taps on rendered content (text/icon glyphs) but not reliably on
background/padding — with no explicit fallback target.

## 2. Fix

**Routing**: `SessionDisplayMode.mode(for: SessionStatus, readOnly: Bool)`
— a completed/skipped/missed/abandoned Session is *always*
`.completedHistory`, regardless of the caller's `readOnly` flag; the flag
only disambiguates a `.scheduled` Session (Today's actionable one vs. a
future one inspected from Week/Plan). No caller (Today/Week/Plan) needed
to change — they already pass status and a readOnly hint; the routing
function itself is what was wrong.

**Tappability**: `.contentShape(Rectangle())` added to all three card/row
views, guaranteeing the entire card is one tap target regardless of where
a finger lands. An explicit "View Workout ›" / "Resume ›" affordance is
now shown for every status with no button of its own — navigation no
longer depends on incidental SwiftUI hit-testing behavior at all.

## 3. Completed/read-only presentation architecture

One new view tree, `CompletedSessionDetail` → per-modality detail
(`CompletedStrengthBlockDetail`/`CompletedExerciseDetail`,
`CompletedSteadyStateDetail`, `CompletedIntervalDetail`,
`CompletedFunctionalFitnessDetail`). No `modelContext`, no use-case call,
no mutable state anywhere in the tree — mutation-safety by construction.

## 4. Strength history

Per exercise: prescribed (sets/rep range/RIR/suggested load) vs. actual
per-set (weight/reps/RIR), substitution notice (prescribed exercise via
`slot.resolvedExercise` vs. performed), PR badge distinguishing "first
recorded" from "personal record" by re-deriving the same comparison
`RecordSetResultUseCase` makes at log time, autoregulation feedback
(`autoregulationRating`) and the reason THIS week's own set count is what
it is (`appliedSetCountReasonCode`, via a new small presentation mapper —
`StrengthReasonCodePresentation` — never a second decision engine),
and a next-time load recommendation reusing `CompleteSessionUseCase`'s
existing `progressionPreview` (exposed, was private, since it's pure and
safe to recompute on demand).

## 5. Endurance/Interval/Functional Fitness history

Steady State shows actual duration/distance/HR/power/pace/RPE alongside
the prescription. Intervals show every per-rep result individually
(never averaged), including incomplete ones, plus the session summary.
Functional Fitness shows final score, Rx/Scaled context, benchmark, and
any scaled-movement substitution (the original prescription is never
overwritten).

## 6. Partial history

Completion context (`.partial`) is shown explicitly; a block/exercise
that was never reached shows as not-completed, never hidden or faked.

## 7. Mutation-safety guarantees

Verified structurally (no write API reachable from any completed-history
view) and by test: re-reading a completed Session's full data repeatedly
leaves status, `completedAt`, `SetResult` count, `PersonalRecord` count,
and `PerformanceProfile` all unchanged.

## 8. Tests

30 tests across two passes (`CompletedSessionHistoryTests.swift`):
routing for every status × readOnly combination; the REAL
`SessionDetailView`/`CompletedSessionDetail` types constructed exactly as
`TodayView`/`WeekView`/`ProgramDetailView` construct them (not a
reimplementation of the routing logic); strength prescribed-vs-performed
data shape; substitution identity reconstruction; autoregulation feedback
inspection; partial-completion visibility; Steady State/Interval/
Functional Fitness completed-result data shape; PR first-vs-genuine
re-derivation.

## 9. Full test result

**549 passed, 0 failed** (`xcodebuild test`, full suite, no filter).

## 10. Simulator result

Manually accepted by the product owner: Today → completed workout → tap
→ completed workout history opens successfully. This is the authoritative
acceptance signal — automated tests alone were correctly treated as
insufficient proof for a navigation-reachability bug, since the initial
routing fix passed 544/544 tests while the real tap-through was still
broken (the missing-`.contentShape()`/no-affordance defect, §1).

## 11. Schema changes

None. Everything needed was already persisted.

## 12. Known remaining gaps

- Reason codes are persisted and now surfaced in completed history, but
  no *upcoming* prescription UI reads them yet outside this history view.
- No application-level caller materializes week N+1 automatically yet —
  correctly out of scope (see `TACTICAL_PLANNING_HANDOFF.md`).
- No tap-automation tooling in this environment — every navigation fix
  in this pass required the product owner's own manual Simulator taps to
  confirm; automated tests could prove the routing decision but not
  physical reachability.

## 13. Commits

`1867eb8` (completed-history views + routing), `2bbab37` (tests +
pbxproj), `80bd516` (tappability fix: `.contentShape` + explicit
affordance, found by manual acceptance).

## 14. Local/remote verification

Confirmed equal at `80bd5164df5b148ea3690da73440df32a584507f` after the
final push.
