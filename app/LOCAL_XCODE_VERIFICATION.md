# Local Xcode verification steps

This project was written and statically audited without access to Xcode or
a Swift compiler (see the validation-pass report for what "statically
audited" covers and doesn't). These steps are what turns that into an
actual green build. Run them in order; report back after step E even if
everything passes, and definitely if anything fails.

## A. Open the project

Open `app/TrainingOS.xcodeproj` in Xcode (16.0 or newer, for iOS 18 SDK
support).

Expect: the project opens with two targets in the navigator, `TrainingOS`
and `TrainingOSTests`, and the folder structure `App / Application / Domain
/ Engines / Integrations / Persistence / Resources / UI` under `TrainingOS`.

## B. Select an iPhone simulator

Pick any iPhone simulator running iOS 18+ from the scheme's destination
picker (e.g. "iPhone 16"). Do **not** pick "Any iOS Device" or a physical
device for this pass.

## C. Signing

Leave signing on Automatic. **A simulator destination should not require a
development team.** If Xcode prompts for one anyway, that's worth reporting
back — it may mean a build setting needs adjusting, not that you need to
enroll a team just to run this locally.

## D. Build the app target

Product → Build (⌘B) with the `TrainingOS` scheme selected.

**Expect: zero errors.** Warnings are acceptable to report but not
blocking. If the build fails, copy the *first* error only (later ones are
often noise from the first) and send it back — don't try to fix SwiftData
model code yourself first.

## E. Run all tests

Product → Test (⌘U).

Expect all 39 tests below to pass, grouped by file:

| File | What it proves | Tests |
|---|---|---|
| `DomainModelScenarioTests` | The 8 required scenarios (A–H) have no special-case model code | 8 |
| `PerformanceProfileContinuityTests` | Bench Press history survives a program transition, and survives that program's outright deletion | 3 |
| `DeleteRuleMatrixTests` | Every row in `DELETE_RULE_MATRIX.md` that touches performance data | 7 |
| `RelationshipOwnershipTests` | `addX`/`attachX` methods produce exactly one relationship entry, and SwiftData maintains the inverse without manual dual-side mutation | 8 |
| `PersistenceRoundTripTests` | The full seeded graph survives save + refetch through a fresh `ModelContext`, ordering included | 1 |
| `ScoringEngineTests` | PR comparison rules (higher/lower-is-better, Rx vs Scaled) | 5 |
| `DoubleProgressionEngineTests` | The one implemented progression method, at its stated boundaries | 7 |

If any test fails, the most useful thing to send back is: the test's exact
name, the assertion message, and whether it's in `RelationshipOwnershipTests`
or `DeleteRuleMatrixTests` specifically — those two files exist to catch
exactly the kind of SwiftData relationship behavior that can't be verified
outside Xcode, so a failure there is signal, not noise.

## F. Launch and confirm the three tabs render

Run the app (⌘R) on the simulator chosen in step B.

Expect, using the seeded dev dataset created on first launch
(`TrainingOSApp.swift` seeds automatically when the store is empty):

- **Today** shows two sessions: "Lower A" (07:00) and "Evening Zone 2"
  (18:00), each with its block type and exercise names visible.
- **Plan** shows a Goal ("Muscle Gain"), and two Phases — one marked
  `COMPLETED` ("5-Day Hypertrophy"), one marked `ACTIVE` ("3-Day Full
  Body").
- **Progress** shows a non-empty list of exercises with set counts, and at
  least one entry (Fran) showing a `PR` value.

None of this needs to look polished — this pass explicitly skipped visual
polish. The bar is "renders without crashing and shows the right data,"
not "looks finished."

## G. Report back

Before Stage 3 starts, report:

1. Build result (pass/fail, and the first error if it failed).
2. Test result (pass/fail count; which tests failed, if any).
3. Whether the three tabs rendered as described in step F.
4. Anything Xcode flagged that this document didn't anticipate (a schema
   migration prompt, a signing prompt, a warning that looks structural
   rather than cosmetic).

Everything else in this pass — the relationship refactor, the delete-rule
matrix, the new tests — was reviewed as carefully as static reading allows,
but none of it has actually run. Treat this first Xcode run as part of
reviewing the pass, not a formality before moving on.
