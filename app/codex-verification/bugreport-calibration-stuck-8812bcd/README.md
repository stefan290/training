# Bug report: calibration never resolves for a session moved before its ProgramInstance's start date

**Installed/verified version:** commit `8812bcd13f1b04811dc4fc911e33e1043784672b` (PR #4 round 5,
previously reported as cleanly passing — `verify/codex-distinct-training-styles-8812bcd`).
**Simulator:** `896F3964-F0BA-47DF-863D-7532BD478E11` ("iPhone 17", iOS 26.5).
**Confirmed exact match**, not assumed: `shasum -a 256` of the installed
`TrainingOS.debug.dylib` is `30a31815507ee3db3393afca1cca0fdda672d27b67d3239183adaa49d943df44`,
byte-identical to the round-5 verification package's own reference build artifact.

The user reproduced this manually, independent of my own earlier automation-driven testing, by
re-opening the exact 3×Functional Strength + 1×CrossFit mix accepted during round-5 verification:
entering a 10RM for Back Squat and pressing "Confirm & Continue" repeatedly never dismisses the
prompt, and the prompt reappears every time the session is reopened. This report investigates the
existing installation directly — **no code was changed, no merge was performed.**

## Root cause, directly proven by database evidence

`ProgramWeekGrouping.realSessions(in:forWeek:)`
(`app/TrainingOS/Engines/ProgramWeekGrouping.swift:24-38`) is the sole source the calibration
backfill use case queries for "which prescriptions need resolving right now":

```swift
static func realSessions(in instance: ProgramInstance, forWeek weekIndex: Int) -> [Session] {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: instance.startDate)
    return instance.sessions.filter { session in
        guard let date = session.day?.date else { return false }
        let daysSinceStart = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? -1
        guard daysSinceStart >= 0 else { return false }
        return daysSinceStart / 7 == weekIndex
    }...
}
```

**A session whose day falls *before* `instance.startDate` is silently excluded** by the
`daysSinceStart >= 0` guard — not just from "week 0," from every week, permanently, since a
negative offset can never equal any non-negative `weekIndex`.

`SessionDetailView`'s existing "Start Today Instead" feature (Dogfood Round 1, Finding 4) moves a
future-scheduled session onto today's real date whenever the athlete wants to start early — a
completely ordinary, intended action. When "today" is earlier than the owning `ProgramInstance`'s
own `startDate` (exactly the case here: the plan starts Monday, 12 October 2026, and the session
was started on Tuesday, 7 October 2026 — see `03-dates-proving-exclusion.txt`), the moved session's
own prescriptions become permanently invisible to
`ResolveCalibrationDependentPrescriptionsUseCase.resolve`
(`app/TrainingOS/Application/UseCases/ResolveCalibrationDependentPrescriptionsUseCase.swift:39-109`),
which builds its entire candidate list from `ProgramWeekGrouping.realSessions(in: instance,
forWeek: 0)` (line 48) and nothing else.

### Direct database proof of the asymmetry

Both this device's two `ProgramInstance`s ("1-Day CrossFit" and "3-Day Functional Strength") have
the **identical** `ZSTARTDATE` (2026-10-11 22:00 UTC = 12 Oct local) —
`03-dates-proving-exclusion.txt`. Only the Functional Strength instance's own Session 1 (Z_PK=4)
was moved via "Start Today Instead," onto 2026-10-07 22:00 UTC (7 Oct local) — **before** the
instance start date. The CrossFit instance's own Session 1 (Z_PK=3) was never moved and remains on
its originally scheduled date, 2026-10-14 (**after** the instance start date).

Both sessions contain a Back Squat prescription, sourced from templates with the identical
`loadRule=rmBased`/`rmType=rm10` (`04-prescription-templates.txt`, templates 13/14/26). Both were
calibrated by submitting real values through the exact same production UI flow
(`02-exercise-prescriptions-by-instance.txt`, `01-source-rm-calibration.txt`):

| Prescription | Session | Day date vs. instance start | Calibration submitted | Resolved? |
|---|---|---|---|---|
| Z_PK=7, Back Squat | CrossFit Session 1 (Z_PK=3) | 14 Oct — **after** start | kg=80, once | **`rmBasedLoad`** |
| Z_PK=10, Back Squat | Functional Strength Session 1 (Z_PK=4, moved via Start Today Instead) | 7 Oct — **before** start | kg=80→70→65, **7 separate submissions** | **still `calibrationRequired`** |

The Functional Strength session's other two prescriptions in the same block (Barbell Hip Thrust,
Barbell Bench Press) are likewise permanently stuck, despite their own calibrations also being
recorded (`Barbell Hip Thrust`: kg=70 then kg=50, 3 submissions; `Barbell Bench Press`: kg=55, one
submission) — every exercise in this one moved session is affected identically, never exercises in
unmoved sessions.

**`SourceRMCalibration` recording itself works correctly, every single time** — confirmed by the
up-to-date `Z_OPT` counters (7 updates for Back Squat alone) and exact-matching
`(exercise, programInstance, rmType)` keys. The defect is specifically that
`ResolveCalibrationDependentPrescriptionsUseCase.resolve` never sees this session's prescriptions
at all, so it can never flip their `appliedLoadReasonCode` away from `.calibrationRequired` —
regardless of how many times, or how correctly, the athlete enters a value.

## Why the UI shows total silence instead of an error

`StrengthExecutionView.swift`'s "Confirm & Continue" button:

```swift
Button("Confirm & Continue") {
    guard let value = Double(calibrationText), value > 0 else { return }
    guard viewModel.submitCalibration(kilograms: value, modelContext: modelContext) else { return }
    resetInputsForCurrentSet()
}
```

and `StrengthExecutionViewModel.submitCalibration` (lines 278-301) both discard failure with a bare
`return`/`catch { return false }` — no error message, no logging, nothing. In this specific case
`submitCalibration` actually **returns `true`** (the function throws nothing; it simply finds zero
matching prescriptions to resolve and returns normally — `ResolveCalibrationDependentPrescriptionsUseCase.swift:107`,
`guard didResolveAnything else { return }`), so `resetInputsForCurrentSet()` **is** called, the text
field clears — but `recomputeMovementIndexAfterCalibration` then recomputes `movementIndex` via the
exact same `resolveMovementIndex`, which still finds this same movement's `appliedLoadReasonCode ==
.calibrationRequired` and lands right back on the identical prompt. From the athlete's perspective
this is indistinguishable from the button doing nothing at all.

A live `log stream` capture spanning the exact repro window (text entry through the "Confirm &
Continue" press, `log-stream-repro-window.log`, 12,428 lines) confirms **zero** application-level
error, exception, or SwiftData diagnostic anywhere in the OS unified logging system for this
attempt — every line belongs to UIKit/keyboard/accessibility framework noise. This is consistent
with the code read above: nothing in this path ever calls `os_log`/`print`, so even a framework
like SwiftData, which did emit a visible validation-error log line during round-4's "Finding Q"
investigation, has nothing to emit here — there is no save failure, just a silently empty result
set.

## Reproduction steps

1. On simulator `896F3964-F0BA-47DF-863D-7532BD478E11`, with commit `8812bcd` installed, open the
   already-accepted "3× Functional Strength + 1× CrossFit" plan (materialized during round-5
   verification; Today → "Week 1 — Session 1" → Resume).
2. Tap into the "Functional Bodybuilding" block (Back Squat, Barbell Hip Thrust, Barbell Bench
   Press) — this is the session that was previously moved onto today's date via "Start Today
   Instead."
3. On the "What's your 10RM?" prompt for Back Squat, enter any value (e.g. 65) and tap
   "Confirm & Continue."
4. **Observed:** the text field clears, but the identical calibration prompt for Back Squat is
   shown again immediately. Database inspection (immediately after, no further interaction)
   confirms a new `SourceRMCalibration` row/update was written with the entered value, and the
   Back Squat `ExercisePrescription.appliedLoadReasonCode` remains `calibrationRequired`.
5. Leaving and re-entering the session (including after a full app relaunch) reproduces the exact
   same prompt every time — the session can never be started or logged, matching the user's own
   report precisely.

This reproduces identically whether the value is entered via the simulator's on-screen keypad
(confirmed by the user, by me via host automation, and via this investigation's own direct
reproduction) — **the two prior "host accessibility-automation" disclosures in the round-4 and
round-5 verification packages were a wrong attribution.** The real defect is the one described
above; it merely happened to surface, in every verification round so far, through a calibration
attempt made against a session that had been moved earlier than its instance's start date.

## Scope note

This defect is specific to calibrating an exercise inside a session that has been moved (via
"Start Today Instead") to a date earlier than its own `ProgramInstance.startDate`. It is not
specific to the Functional-Strength/CrossFit mix itself — any session moved the same way, in any
mix, would hit the identical `ProgramWeekGrouping.realSessions` exclusion. Not investigated further
(e.g., whether `RequiredRunningCalibrationUseCase`'s own resolution path, or any other caller of
`ProgramWeekGrouping.realSessions`, shares the same exposure) — flagged for Codex's own
judgment rather than guessed at.

## Contents of this package

- `01-source-rm-calibration.txt` — every `SourceRMCalibration` row on this device, proving
  calibration is recorded correctly for every exercise in both program instances.
- `02-exercise-prescriptions-by-instance.txt` — every `ExercisePrescription` in both instances,
  showing the Functional Strength instance's three exercises permanently stuck at
  `calibrationRequired` while the CrossFit instance's identical-shape prescriptions resolve.
- `03-dates-proving-exclusion.txt` — the exact `ProgramInstance.startDate` and `Session.day.date`
  values proving the moved session falls before its own instance's start date.
- `04-prescription-templates.txt` — confirms the affected templates are genuinely `rmBased`/`rm10`,
  ruling out a type/rmType mismatch as an alternative explanation.
- `05-data-integrity-check.txt` — session/instance/plan counts, confirming this entire
  investigation (three additional live submission attempts, log capture) changed no counts and
  erased no data.
- `log-stream-repro-window.log` — the live `log stream` capture (`process == "TrainingOS"`,
  `--level debug`) spanning the exact text-entry-through-press window of the final reproduction
  attempt, confirming no application-level error is logged anywhere.
- `screenshots/` — the exact screens at each reproduction step (00: state as left by the user;
  01-02: navigating back in; 03: the Back Squat calibration prompt, "Exercise 1 of 3, 0/3
  completed," identical to the user's own report).

No application code was changed to produce this report. No merge was performed. No existing
training data was erased — confirmed via `05-data-integrity-check.txt` and by this device's
session/instance/plan counts being identical before and after this investigation.
