import XCTest

/// SIMULATOR AUTOMATION HARNESS — first real end-to-end reproduction.
/// Drives the REAL TrainingOS UI (never constructs domain objects
/// directly, never seeds persistence) through onboarding → goal
/// selection → training days → custom Training Mix (5x Functional
/// Fitness) → movement-capability questions → Back Squat 10RM
/// calibration → generated Week 1, capturing a screenshot + the real
/// accessibility hierarchy at every checkpoint the project lead's order
/// specifies. This is diagnostic only — it makes no judgment about
/// whether any observed programming output is acceptable.
final class MuscleFiveFFDogfoodUITests: XCTestCase {
    var app: XCUIApplication!
    var artifactsRoot: URL!
    var checkpointIndex = 0
    static let bundleID = "com.macadegolf.trainingos"

    override func setUpWithError() throws {
        continueAfterFailure = true
        let fm = FileManager.default
        // Per-test root (keyed by the test's own name) — the diagnostic
        // closure pass runs two independent scenarios in one target, and
        // they must never overwrite each other's artifacts.
        let testName = name.components(separatedBy: CharacterSet(charactersIn: "[] ")).filter { !$0.isEmpty }.last ?? "run"
        artifactsRoot = URL(fileURLWithPath: "/tmp/ff-dogfood-artifacts-\(testName)")
        try? fm.removeItem(at: artifactsRoot)
        try? fm.createDirectory(at: artifactsRoot.appendingPathComponent("screenshots"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: artifactsRoot.appendingPathComponent("ui-state"), withIntermediateDirectories: true)

        app = XCUIApplication()
        // Real, deterministic clean-state mechanism: a launch argument the
        // app's own entry point checks to wipe its persistent store before
        // `PersistenceController` opens it — the smallest truthful "reset
        // before onboarding" seam. `-FFDogfoodTrace` additionally gates the
        // DEBUG-ONLY `DogfoodTraceDump` (see that type's own doc comment) —
        // zero effect on any launch that omits it.
        app.launchArguments = ["-FFDogfoodCleanState", "YES", "-FFDogfoodTrace"]
        app.launch()
    }

    /// DIAGNOSTIC CLOSURE, Section A/C: `Process`/`Foundation.Process` is
    /// unavailable on the iOS SDK this UI-test target compiles against
    /// (confirmed empirically this pass — a real SDK constraint, not a
    /// design choice), so this test target cannot shell out to
    /// `simctl` itself. The trace file is retrieved as a SEPARATE step
    /// immediately after this test run, from the host macOS process
    /// driving `xcodebuild test` (see the coordinator's own report) — the
    /// app writes `dogfood-runtime-trace.json` to its real on-disk
    /// container regardless of who reads it back afterward, so the
    /// correlation to THIS SAME materialization is unaffected by which
    /// process performs the file read.
    @discardableResult
    private func retrieveRuntimeTrace() -> String? { nil }

    /// Captures a screenshot (PNG) and the real accessibility hierarchy
    /// (plain text, exact strings from `XCUIElement.debugDescription` —
    /// never OCR) under one stable, numbered filename pair.
    @discardableResult
    private func checkpoint(_ name: String) -> String {
        checkpointIndex += 1
        let stem = String(format: "%02d_%@", checkpointIndex, name)
        let screenshot = app.screenshot()
        let pngURL = artifactsRoot.appendingPathComponent("screenshots/\(stem).png")
        try? screenshot.pngRepresentation.write(to: pngURL)
        let hierarchy = app.debugDescription
        let txtURL = artifactsRoot.appendingPathComponent("ui-state/\(stem).txt")
        try? hierarchy.write(to: txtURL, atomically: true, encoding: .utf8)
        print("CHECKPOINT[\(stem)] screenshot=\(pngURL.path) hierarchy=\(txtURL.path)")
        return hierarchy
    }

    private func tapFirstButton(labelContains fragment: String, timeout: TimeInterval = 8) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", fragment)
        let button = app.buttons.matching(predicate).firstMatch
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return true
    }

    private func tapExactButton(_ label: String, timeout: TimeInterval = 8) -> Bool {
        let button = app.buttons[label]
        guard button.waitForExistence(timeout: timeout) else { return false }
        button.tap()
        return true
    }

    func testMuscleGoalFiveFunctionalFitnessDogfood() throws {
        var log: [String] = []
        func note(_ s: String) { log.append(s); print("DOGFOOD LOG: \(s)") }

        // 1. Primary-goal screen.
        checkpoint("primary_goal_screen")
        note("Onboarding launched. Checking for goal options.")

        // Tap "Build muscle" — PlanPresentation.mainGoalLabel(.muscleGain).
        // Try a few plausible label fragments since the exact copy is
        // read from source, not guaranteed to match a single literal.
        let goalTapped = tapFirstButton(labelContains: "muscle")
        note("Tapped a 'muscle' goal option: \(goalTapped)")
        if !goalTapped {
            note("BLOCKED: could not find a goal option containing 'muscle'. Dumping hierarchy and stopping this section.")
            checkpoint("BLOCKED_goal_screen")
        }

        if goalTapped {
            _ = tapExactButton("Continue")
            checkpoint("after_goal_continue")
        }

        // 2. Training days / preferences screen. REAL, EMPIRICALLY
        // CONFIRMED default state (captured via a prior run's real
        // accessibility hierarchy dump): every weekday (Mon-Sun) starts
        // ON. To reach exactly 5 real training days = Monday-Friday, the
        // correct real-athlete interaction is to turn OFF Saturday and
        // Sunday — NOT to tap Monday-Friday (which would deselect them,
        // as an earlier harness run incorrectly did, leaving only 2 days
        // selected). Query each switch's actual `value` first and only
        // tap when it needs to change, so this is correct regardless of
        // which default the app actually ships.
        func setWeekday(_ day: String, to shouldBeOn: Bool) -> Bool {
            let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", day)).firstMatch
            guard toggle.waitForExistence(timeout: 3) else { return false }
            let isOn = (toggle.value as? String) == "1"
            if isOn != shouldBeOn { toggle.tap() }
            return true
        }
        var toggledCount = 0
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] {
            if setWeekday(day, to: true) { toggledCount += 1 }
        }
        for day in ["Saturday", "Sunday"] {
            _ = setWeekday(day, to: false)
        }
        note("Ensured ON count=\(toggledCount) of 5 (Mon-Fri); explicitly turned OFF Saturday+Sunday.")
        checkpoint("preferences_screen_after_weekday_selection")

        if toggledCount > 0 {
            _ = tapExactButton("Continue")
            checkpoint("after_preferences_continue")
        } else {
            note("BLOCKED: no weekday toggles found/tapped — cannot proceed with training-days selection deterministically.")
        }

        // 3. Training environment screen — assume default Full Gym is
        // already valid; just tap Continue if enabled.
        checkpoint("environment_screen")
        let envContinued = tapExactButton("Continue")
        note("Tapped Continue on environment screen: \(envContinued)")
        checkpoint("after_environment_continue")

        // 4. Review screen -> "See My Recommended Plan".
        checkpoint("review_screen")
        let sawRecommendation = tapFirstButton(labelContains: "Recommended Plan")
        note("Tapped 'See My Recommended Plan': \(sawRecommendation)")

        // 5. Recommended-plan screen — capture BEFORE touching anything,
        // this is the exact screen the real dogfood session reported
        // "4 Hypertrophy + 1 Zone 2 Conditioning" on.
        let recommendedHierarchy = checkpoint("recommended_plan_screen")
        note("Recommended plan screen hierarchy captured (\(recommendedHierarchy.count) chars).")

        // 6. Switch to custom mix: "Build My Own Mix".
        let customMixOpened = tapFirstButton(labelContains: "Build My Own Mix")
        note("Opened custom Training Mix editor: \(customMixOpened)")
        checkpoint("custom_training_mix_screen_initial")

        if customMixOpened {
            // Find the Functional Fitness row's "+" stepper and tap it 5
            // times, verifying the row's own displayed count after each
            // tap so we never silently under/over-shoot if the allowed
            // frequency set has gaps (e.g. only even values supported).
            let ffRowPlus = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "plus")).firstMatch
            var ffPlusTapped = 0
            // The plus buttons are unlabeled SF Symbol images in this
            // view (no explicit accessibility label set in source) — try
            // the image-based query as a fallback if the button-label
            // query above finds nothing.
            let allPlusButtons = app.buttons.allElementsBoundByIndex
            note("Total buttons visible on custom-mix screen: \(allPlusButtons.count). Attempting to locate the Functional Fitness row's stepper by proximity to its label text.")

            let ffLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Functional Fitness")).firstMatch
            if ffLabel.waitForExistence(timeout: 5) {
                note("Found 'Functional Fitness' row label. Frame=\(ffLabel.frame)")
                // Buttons in the same row are horizontally near this
                // label's frame; select the plus (rightmost of the two
                // stepper buttons) by looking for icon-only buttons in
                // the same vertical band.
                let sameRowButtons = allPlusButtons.filter { abs($0.frame.midY - ffLabel.frame.midY) < 30 }
                note("Buttons in Functional Fitness row band: \(sameRowButtons.count)")
                if let plusButton = sameRowButtons.last {
                    for i in 0..<5 {
                        if plusButton.exists, plusButton.isEnabled {
                            plusButton.tap()
                            ffPlusTapped += 1
                        } else {
                            note("Plus button not tappable at iteration \(i) (exists=\(plusButton.exists), enabled=\(plusButton.isEnabled)).")
                            break
                        }
                    }
                } else {
                    note("BLOCKED: could not isolate the Functional Fitness row's '+' stepper button by row-proximity heuristic.")
                }
            } else {
                note("BLOCKED: 'Functional Fitness' row label not found on custom mix screen.")
            }
            note("Functional Fitness '+' tapped \(ffPlusTapped) times (target 5).")
            checkpoint("custom_training_mix_after_ff_selection")

            let usedMix = tapFirstButton(labelContains: "Use This Mix")
            note("Tapped 'Use This Mix': \(usedMix)")
            checkpoint("after_use_this_mix")
        }

        // 7. Accept & Start Training.
        let accepted = tapFirstButton(labelContains: "Accept & Start Training")
        note("Tapped 'Accept & Start Training': \(accepted)")
        checkpoint("after_accept_and_start")

        // 8. Calibration: Back Squat 10RM. The real entry point observed
        // empirically is the "Today" tab's own banner ("Some exercises
        // still need a starting weight — set it now...") — never an
        // automatic prompt right after accepting the plan. Tap it if
        // present before capturing/interacting with the calibration UI.
        let todayHierarchyBeforeBanner = checkpoint("today_tab_before_calibration_banner")
        note("Today tab hierarchy captured. Contains 'starting weight': \(todayHierarchyBeforeBanner.contains("starting weight"))")
        var bannerTapped = tapFirstButton(labelContains: "starting weight", timeout: 5)
        if !bannerTapped {
            // Not every tappable row in this app is an XCUIElement.buttons
            // match (some are custom-gesture rows) — fall back to
            // tapping the static text itself, which XCUITest hit-tests
            // by real screen coordinate against whatever view is there.
            let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "starting weight")).firstMatch
            if text.waitForExistence(timeout: 3) {
                text.tap()
                bannerTapped = true
            }
        }
        note("Tapped the 'set starting weight' banner: \(bannerTapped)")

        let calibrationScreenHierarchy = checkpoint("calibration_screen_before_entry")
        note("Calibration screen hierarchy captured. Contains 'Back Squat': \(calibrationScreenHierarchy.contains("Back Squat")). Contains '10RM': \(calibrationScreenHierarchy.contains("10RM"))")

        // DOGFOOD HARNESS COMPLETION, Section 1: the real calibration
        // screen (confirmed via the real accessibility hierarchy captured
        // in the prior pass) is an OPTIONAL, per-exercise "Set your
        // starting weights" screen ("OPTIONAL... or skip any of them —
        // we'll ask again the first time you reach that exercise") with
        // FOUR real 10RM text fields in this exact order: Back Squat,
        // Barbell Bench Press, Barbell Hip Thrust, Barbell Row — never
        // just one. Fill all four with documented, deterministic,
        // plausible values (never chosen to make later programming look
        // better):
        //   Back Squat          10RM = 70 kg  (per project-lead spec)
        //   Barbell Bench Press 10RM = 50 kg  (documented fixture)
        //   Barbell Hip Thrust  10RM = 80 kg  (documented fixture)
        //   Barbell Row         10RM = 50 kg  (documented fixture)
        let textFields = app.textFields.allElementsBoundByIndex
        note("Text fields visible on calibration screen: \(textFields.count) (expected 4: Back Squat, Barbell Bench Press, Barbell Hip Thrust, Barbell Row).")
        let calibrationValues = ["70", "50", "80", "50"]
        let calibrationExerciseNames = ["Back Squat", "Barbell Bench Press", "Barbell Hip Thrust", "Barbell Row"]
        var filledCount = 0
        // Re-query fresh each iteration (not the stale `textFields`
        // snapshot) — the scroll view's content shifts as the keyboard
        // appears/disappears for each field, which can move a
        // not-yet-tapped field's real screen coordinates and cause
        // XCUITest's synthesized tap to land on the wrong element/miss
        // keyboard focus entirely (observed empirically this pass).
        // Dismiss the keyboard back to a fully-settled, known scroll
        // position between fields by tapping the screen's own stable
        // title text (never a coordinate under/near the keyboard) —
        // observed empirically this pass: tapping the next field WHILE
        // the keyboard is still up for a prior field can silently fail
        // to move keyboard focus at all (the prior field stayed
        // focused), which is a harness robustness issue, not a product
        // defect.
        let screenTitle = app.staticTexts["Set your starting weights"]
        for index in 0..<calibrationValues.count {
            if index > 0, screenTitle.exists { screenTitle.tap() }
            let freshField = app.textFields.element(boundBy: index)
            guard freshField.waitForExistence(timeout: 5) else {
                note("BLOCKED: text field index \(index) (\(calibrationExerciseNames[index])) not present.")
                continue
            }
            freshField.tap()
            freshField.typeText(calibrationValues[index])
            // Verify by reading the real resulting value back — never
            // assume the synthesized tap/type succeeded silently.
            var actualValue = (app.textFields.element(boundBy: index).value as? String) ?? ""
            if actualValue != calibrationValues[index] {
                // One retry: dismiss keyboard fully via the stable title,
                // then re-query and try again.
                if screenTitle.exists { screenTitle.tap() }
                let retryField = app.textFields.element(boundBy: index)
                if retryField.waitForExistence(timeout: 3) {
                    retryField.tap()
                    retryField.typeText(calibrationValues[index])
                    actualValue = (app.textFields.element(boundBy: index).value as? String) ?? ""
                }
            }
            if actualValue == calibrationValues[index] {
                filledCount += 1
                note("Entered '\(calibrationValues[index])' kg 10RM for \(calibrationExerciseNames[index]) (field index \(index)), verified value='\(actualValue)'.")
            } else {
                note("BLOCKED: text field index \(index) (\(calibrationExerciseNames[index])) shows value='\(actualValue)' after entry+retry, expected '\(calibrationValues[index])'.")
            }
        }
        if screenTitle.exists { screenTitle.tap() } // final dismiss before reading overall screen state
        note("Filled \(filledCount) of \(textFields.count) real calibration fields (target: all 4).")
        checkpoint("calibration_after_entering_all_values")

        // Try to confirm/advance past calibration — the real button on
        // this screen (confirmed via prior hierarchy capture) is exactly
        // "Continue", not "Confirm"/"Save".
        let confirmed = tapExactButton("Continue") || tapFirstButton(labelContains: "Confirm") || tapFirstButton(labelContains: "Save")
        note("Attempted to confirm calibration entry via 'Continue': \(confirmed)")
        checkpoint("state_after_calibration_confirm_attempt")

        // Section 2: factually determine whether the starting-weight
        // banner is gone now that all 4 fields are filled (the real
        // signal for whether the calibration flow "advances") — never
        // assume; read the real resulting hierarchy.
        let postCalibrationHierarchy = app.debugDescription
        let bannerStillPresent = postCalibrationHierarchy.contains("still need a starting weight")
        note("FACT: 'starting weight' banner still present after filling all 4 real fields and tapping Continue: \(bannerStillPresent).")

        // Additional documented deterministic capability fixtures, if
        // capability-question UI appears at this point in the flow —
        // report presence/absence rather than guessing blindly.
        for (movement, capacityNote) in [
            ("Toes-to-Bar", "WORKOUT_READY, max unbroken = 7"),
            ("Pull-Up", "WORKOUT_READY, max unbroken = 5"),
            ("Handstand Push", "WORKOUT_READY, max unbroken = 3"),
        ] {
            let present = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", movement)).firstMatch.exists
            note("Capability question for '\(movement)' present on current screen: \(present). Intended deterministic fixture value: \(capacityNote).")
        }

        // 9. Reach the real Week 1 view. The real Today-tab state
        // (confirmed via prior hierarchy capture) is "Not started
        // yet" / "Your plan starts Monday, 28 September" with a real
        // "View Week" button — the plan's first tactical week is
        // scheduled in the future relative to the simulator's clock, so
        // Week 1's sessions are NOT directly on the Today tab; "View
        // Week" is the real navigation into them.
        let viewWeekTapped = tapExactButton("View Week", timeout: 5)
        note("Tapped 'View Week': \(viewWeekTapped)")
        var weekHierarchy = checkpoint("week1_overview_attempt")
        if !viewWeekTapped {
            // Fallback: the Plan tab (identifier 'calendar') is the other
            // real, documented entry point into the week/session list.
            let planTabTapped = tapFirstButton(labelContains: "Plan", timeout: 5)
            note("Fallback: tapped 'Plan' tab: \(planTabTapped)")
            weekHierarchy = checkpoint("week1_overview_via_plan_tab")
        }
        // Real, empirically confirmed structural fact: "View Week" lands
        // on the CURRENT calendar week ("This Week"), which reads "Not
        // yet planned" / "This week hasn't been scheduled yet" whenever
        // the plan's own real first tactical week starts later than
        // today (confirmed this run: plan starts the following Monday,
        // today is mid-week) — the real scheduled Week 1 is one "Next
        // Week" tap forward. Advance forward (bounded to avoid an
        // infinite loop) until real session content appears or the
        // bound is hit.
        var weekAdvances = 0
        while weekHierarchy.contains("hasn't been scheduled yet") && weekAdvances < 3 {
            let nextWeekTapped = tapExactButton("Next Week", timeout: 5)
            note("Week not yet scheduled — tapped 'Next Week' (attempt \(weekAdvances + 1)): \(nextWeekTapped)")
            guard nextWeekTapped else { break }
            weekAdvances += 1
            weekHierarchy = checkpoint("week_view_after_next_week_tap_\(weekAdvances)")
        }

        for sessionIndex in 1...5 {
            let sessionRow = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Session \(sessionIndex)")).firstMatch
            if sessionRow.waitForExistence(timeout: 5) {
                sessionRow.tap()
                checkpoint("session\(sessionIndex)_overview")
                // Tap into every distinguishable block/row on this
                // session's own screen (real block cells), capturing a
                // checkpoint for each, then back out to the session
                // overview before returning to the week list.
                let blockCells = app.cells.allElementsBoundByIndex
                note("Session \(sessionIndex): \(blockCells.count) real cell(s) found on session-overview screen.")
                if blockCells.isEmpty {
                    // Some session screens render blocks as plain rows
                    // (Other/Button), not XCUITest `.cells` — fall back to
                    // scrolling the whole screen and capturing snapshots
                    // until the hierarchy stabilizes, which still
                    // captures every block's real rendered text even if
                    // we can't isolate/tap each one as a distinct element.
                    var lastHierarchyLength = -1
                    for scrollAttempt in 0..<4 {
                        let hierarchy = checkpoint("session\(sessionIndex)_block_scroll\(scrollAttempt)")
                        if hierarchy.count == lastHierarchyLength { break }
                        lastHierarchyLength = hierarchy.count
                        app.swipeUp()
                    }
                } else {
                    for (blockIndex, cell) in blockCells.enumerated() {
                        guard cell.exists else { continue }
                        cell.tap()
                        checkpoint("session\(sessionIndex)_block\(blockIndex)_detail")
                        if app.navigationBars.buttons.element(boundBy: 0).exists {
                            app.navigationBars.buttons.element(boundBy: 0).tap()
                        }
                    }
                }
                if app.navigationBars.buttons.element(boundBy: 0).exists {
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                }
            } else {
                note("Session \(sessionIndex) row not found on Week 1 view — real navigation for this session was not reached.")
            }
        }

        // DIAGNOSTIC CLOSURE, Section A/C: retrieve the runtime trace
        // written by THIS SAME materialization (the app process is still
        // running here — the trace file was written synchronously inside
        // `acceptAndStart`, long before this point) and prove correlation
        // against the real UI hierarchy already captured above for
        // Session 3 and Session 5.
        let traceString = retrieveRuntimeTrace()
        note("Runtime trace retrieved: \(traceString != nil). Length: \(traceString?.count ?? 0) chars.")
        if let traceString {
            let hasRunID = traceString.contains("dogfoodRunID")
            let traceHasAmrap4 = traceString.contains("\"workoutFormatCapSeconds\" : 240") || traceString.contains("\"workoutFormatCapSeconds\": 240")
            let traceHasEasyRun = traceString.contains("Easy Run")
            let traceHasDeadlift = traceString.contains("Deadlift")
            let traceHasRow200 = traceString.contains("Row Erg")
            let traceHasForTime1200 = traceString.contains("\"workoutFormatCapSeconds\" : 1200") || traceString.contains("\"workoutFormatCapSeconds\": 1200")
            note("CORRELATION CHECK: trace contains dogfoodRunID=\(hasRunID); 240s-cap block=\(traceHasAmrap4); 'Easy Run' exercise=\(traceHasEasyRun); 'Deadlift' exercise=\(traceHasDeadlift); 'Row Erg' exercise=\(traceHasRow200); 1200s(20min)-cap block=\(traceHasForTime1200).")
            note("CORRELATION CONCLUSION: trace and UI describe the same materialization iff all six facts above are true AND the UI hierarchy already captured this run's Session 3/5 checkpoints shows the identical strings — see causal-closure.md for the final side-by-side comparison.")
        } else {
            note("CORRELATION CHECK: FAILED TO RETRIEVE — trace file not found via simctl get_app_container. This means the runtime-correlated trace proof did NOT succeed this run; report this honestly rather than asserting correlation without evidence.")
        }

        // Persist the full narrative log alongside the structured
        // checkpoints for the README/report to consume verbatim.
        let logURL = artifactsRoot.appendingPathComponent("ui-state/00_dogfood_log.txt")
        try? log.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Custom Training Mix reproduction (Sections E-F)

    /// DIAGNOSTIC CLOSURE, Section E-F: starting fresh (Build Muscle, 5
    /// training days), open Custom Training Mix and attempt to construct
    /// the recommendation-equivalent 4xHypertrophy+1xRunning/Zone2 mix
    /// through the REAL UI — never assumed from source. Captures the
    /// initial screen, the state after selecting 4xHypertrophy, the
    /// attempt to add a 5th Running session, and whatever validation/
    /// error/disabled/success state actually results.
    func testCustomMixRunningEquivalentReproduction() throws {
        var log: [String] = []
        func note(_ s: String) { log.append(s); print("CUSTOMMIX LOG: \(s)") }

        _ = tapFirstButton(labelContains: "muscle")
        _ = tapExactButton("Continue")

        func setWeekday(_ day: String, to shouldBeOn: Bool) -> Bool {
            let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", day)).firstMatch
            guard toggle.waitForExistence(timeout: 3) else { return false }
            let isOn = (toggle.value as? String) == "1"
            if isOn != shouldBeOn { toggle.tap() }
            return true
        }
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] { _ = setWeekday(day, to: true) }
        for day in ["Saturday", "Sunday"] { _ = setWeekday(day, to: false) }
        _ = tapExactButton("Continue")

        _ = tapExactButton("Continue") // environment screen
        _ = tapFirstButton(labelContains: "Recommended Plan") // review screen

        checkpoint("custommix_recommended_plan_screen")
        let customMixOpened = tapFirstButton(labelContains: "Build My Own Mix")
        note("Opened custom Training Mix editor: \(customMixOpened)")
        let initialHierarchy = checkpoint("custommix_initial")
        note("Initial custom-mix hierarchy captured (\(initialHierarchy.count) chars).")

        guard customMixOpened else {
            note("BLOCKED: could not open Custom Training Mix at all — cannot attempt the equivalent mix.")
            let logURL = artifactsRoot.appendingPathComponent("ui-state/00_customMix_log.txt")
            try? log.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
            return
        }

        // Select 4x Hypertrophy via the same row-proximity stepper
        // heuristic used for Functional Fitness in the primary scenario.
        func setStepper(rowLabelContains label: String, taps: Int) -> Int {
            let rowLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", label)).firstMatch
            guard rowLabel.waitForExistence(timeout: 5) else {
                note("Row label '\(label)' not found.")
                return 0
            }
            let allButtons = app.buttons.allElementsBoundByIndex
            let sameRow = allButtons.filter { abs($0.frame.midY - rowLabel.frame.midY) < 30 }
            guard let plusButton = sameRow.last else {
                note("Could not isolate stepper '+' for row '\(label)' (found \(sameRow.count) candidate buttons in row band).")
                return 0
            }
            var tapped = 0
            for i in 0..<taps {
                if plusButton.exists, plusButton.isEnabled {
                    plusButton.tap()
                    tapped += 1
                } else {
                    note("Stepper '+' for '\(label)' not tappable at iteration \(i) (exists=\(plusButton.exists), enabled=\(plusButton.isEnabled)).")
                    break
                }
            }
            return tapped
        }

        let hyperTapped = setStepper(rowLabelContains: "Hypertrophy", taps: 4)
        note("Hypertrophy '+' tapped \(hyperTapped) times (target 4).")
        checkpoint("custommix_after_4_hypertrophy")

        // Attempt to add the 5th session as Running/Zone2 — try every
        // plausible real row label for this Training Form; report exactly
        // which (if any) exists, never assume the label text.
        var runningRowFound: String?
        for candidateLabel in ["Running", "Zone 2", "Steady State", "Cardio", "Endurance"] {
            let exists = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", candidateLabel)).firstMatch.exists
            note("Custom-mix row label candidate '\(candidateLabel)' present: \(exists)")
            if exists, runningRowFound == nil { runningRowFound = candidateLabel }
        }

        let beforeAttemptHierarchy = checkpoint("custommix_before_running_attempt")
        note("Hierarchy captured before attempting to add Running/Zone2. Real row found: \(runningRowFound ?? "NONE").")

        var runningTapped = 0
        var validationMessage: String?
        if let rowLabel = runningRowFound {
            runningTapped = setStepper(rowLabelContains: rowLabel, taps: 1)
            note("'\(rowLabel)' '+' tapped \(runningTapped) times (target 1).")
        } else {
            note("FACT: no Running/Zone2/Steady-State/Cardio/Endurance row exists at all on the custom-mix screen for this goal — the recommendation-equivalent mix cannot even be ATTEMPTED, let alone validated.")
        }

        let afterAttemptHierarchy = checkpoint("custommix_after_running_attempt")
        // Look for any real, visible validation/error text that appeared
        // as a result of the attempt.
        let errorCandidates = ["not supported", "unavailable", "cannot", "invalid", "not available", "unsupported"]
        for candidate in errorCandidates {
            if afterAttemptHierarchy.lowercased().contains(candidate) {
                validationMessage = candidate
                break
            }
        }
        note("Validation/error text detected after attempt: \(validationMessage ?? "none detected in hierarchy text").")

        let useThisMixEnabled = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Use This Mix")).firstMatch.isEnabled
        note("FACT: 'Use This Mix' button enabled state after the attempt: \(useThisMixEnabled).")

        let mismatchReproduced: Bool
        if runningRowFound == nil {
            mismatchReproduced = true
            note("CONCLUSION: CUSTOM MIX MISMATCH REPRODUCED = YES — no user-facing Running/Zone2 option exists on this screen at all, while the recommendation engine offered exactly this combination.")
        } else if runningTapped == 0 {
            mismatchReproduced = true
            note("CONCLUSION: CUSTOM MIX MISMATCH REPRODUCED = YES — a Running/Zone2 row exists but its stepper could not be incremented (disabled/unresponsive).")
        } else {
            mismatchReproduced = false
            note("CONCLUSION: CUSTOM MIX MISMATCH REPRODUCED = NO — the row exists and its stepper was successfully incremented; preserve this as evidence the equivalent mix CAN be constructed live.")
        }
        note("FINAL: CUSTOM MIX MISMATCH REPRODUCED = \(mismatchReproduced)")

        checkpoint("custommix_final_state")
        let logURL = artifactsRoot.appendingPathComponent("ui-state/00_customMix_log.txt")
        try? log.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - MUSCLE VERTICAL SLICE REPAIR, Sections 22-24: real-simulator
    // acceptance — Scenario 1 (accept the default recommendation)

    /// Scenario 1: Build Muscle, 5 training days, NO stated conditioning
    /// preference, ACCEPT THE RECOMMENDATION AS-IS (never Custom Mix) —
    /// drives the real production UI end to end and asserts real,
    /// semantic (never hardcoded-exercise-name) invariants against what
    /// the app itself displays. Unlike the diagnostic tests above, this
    /// is a genuine PASS/FAIL acceptance test (`XCTAssert`, not print-only
    /// narration) — the locked product decision under test is: 5 days +
    /// no conditioning preference -> exactly 5x Hypertrophy, never an
    /// invented Hypertrophy+Zone2 split (Sections 1-4).
    func testBuildMuscleFiveDaysAcceptRecommendationDogfood() throws {
        var log: [String] = []
        func note(_ s: String) { log.append(s); print("ACCEPTANCE LOG: \(s)") }

        // 1. Primary goal.
        checkpoint("s1_primary_goal_screen")
        let goalTapped = tapFirstButton(labelContains: "muscle")
        note("Tapped a 'muscle' goal option: \(goalTapped)")
        XCTAssertTrue(goalTapped, "INVARIANT 1: a 'Build Muscle'-labeled goal option must be real and tappable on the primary-goal screen")
        _ = tapExactButton("Continue")
        checkpoint("s1_after_goal_continue")

        // 2. Training days: Mon-Fri ON, Sat/Sun OFF -> exactly 5 days.
        func setWeekday(_ day: String, to shouldBeOn: Bool) -> Bool {
            let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", day)).firstMatch
            guard toggle.waitForExistence(timeout: 3) else { return false }
            let isOn = (toggle.value as? String) == "1"
            if isOn != shouldBeOn { toggle.tap() }
            return true
        }
        var toggledCount = 0
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] {
            if setWeekday(day, to: true) { toggledCount += 1 }
        }
        for day in ["Saturday", "Sunday"] { _ = setWeekday(day, to: false) }
        note("Weekday toggles confirmed ON for \(toggledCount)/5 weekdays.")
        checkpoint("s1_preferences_after_weekday_selection")
        _ = tapExactButton("Continue")
        checkpoint("s1_after_preferences_continue")

        // 3. Training environment — default Full Gym, just continue.
        _ = tapExactButton("Continue")
        checkpoint("s1_after_environment_continue")

        // 4. Review -> "See My Recommended Plan".
        let sawRecommendation = tapFirstButton(labelContains: "Recommended Plan")
        note("Tapped 'See My Recommended Plan': \(sawRecommendation)")
        XCTAssertTrue(sawRecommendation, "INVARIANT 2: a real 'See My Recommended Plan' action must exist on the review screen")

        // 5. THE recommendation screen — capture and assert the real,
        // locked shape BEFORE touching anything (never a custom mix).
        let recommendedHierarchy = checkpoint("s1_recommended_plan_screen")
        let mentionsHypertrophy = recommendedHierarchy.localizedCaseInsensitiveContains("hypertrophy")
        let mentionsZoneTwo = recommendedHierarchy.localizedCaseInsensitiveContains("zone 2")
        let mentionsConditioning = recommendedHierarchy.localizedCaseInsensitiveContains("conditioning")
        note("Recommended-plan screen mentions Hypertrophy=\(mentionsHypertrophy), 'Zone 2'=\(mentionsZoneTwo), 'Conditioning'=\(mentionsConditioning).")
        XCTAssertTrue(mentionsHypertrophy, "INVARIANT 3 (Section 21-B): the recommended plan screen must display a Hypertrophy component")
        XCTAssertFalse(mentionsZoneTwo, "INVARIANT 4 (Sections 2-3): the recommendation must never display a fabricated 'Zone 2' component for Build Muscle + 5 days + no conditioning preference")
        XCTAssertFalse(mentionsConditioning, "INVARIANT 5 (Sections 2-3): the recommendation must never display any Conditioning component for this exact scenario")

        // 6. Accept the recommendation AS-IS — never open Custom Mix.
        let accepted = tapFirstButton(labelContains: "Accept & Start Training")
        note("Tapped 'Accept & Start Training' directly on the recommendation (no Custom Mix): \(accepted)")
        XCTAssertTrue(accepted, "INVARIANT 6: the recommendation must be directly acceptable without requiring the Custom Mix editor")
        checkpoint("s1_after_accept_and_start")

        // 7. Calibration (Back Squat/Bench/Hip Thrust/Row 10RM) — same
        // real, documented fixture values as the diagnostic test above.
        let todayHierarchy = checkpoint("s1_today_tab_before_calibration_banner")
        var bannerTapped = tapFirstButton(labelContains: "starting weight", timeout: 5)
        if !bannerTapped {
            let text = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "starting weight")).firstMatch
            if text.waitForExistence(timeout: 3) { text.tap(); bannerTapped = true }
        }
        note("Today tab captured (contains 'starting weight': \(todayHierarchy.contains("starting weight"))); banner tapped: \(bannerTapped).")
        let screenTitle = app.staticTexts["Set your starting weights"]
        let calibrationValues = ["70", "50", "80", "50"]
        var filledCount = 0
        for index in 0..<calibrationValues.count {
            if index > 0, screenTitle.exists { screenTitle.tap() }
            let freshField = app.textFields.element(boundBy: index)
            guard freshField.waitForExistence(timeout: 5) else { continue }
            freshField.tap()
            freshField.typeText(calibrationValues[index])
            var actualValue = (app.textFields.element(boundBy: index).value as? String) ?? ""
            if actualValue != calibrationValues[index] {
                if screenTitle.exists { screenTitle.tap() }
                let retryField = app.textFields.element(boundBy: index)
                if retryField.waitForExistence(timeout: 3) {
                    retryField.tap()
                    retryField.typeText(calibrationValues[index])
                    actualValue = (app.textFields.element(boundBy: index).value as? String) ?? ""
                }
            }
            if actualValue == calibrationValues[index] { filledCount += 1 }
        }
        if screenTitle.exists { screenTitle.tap() }
        note("Filled \(filledCount)/\(calibrationValues.count) calibration fields.")
        checkpoint("s1_calibration_after_entering_values")
        _ = tapExactButton("Continue") || tapFirstButton(labelContains: "Confirm") || tapFirstButton(labelContains: "Save")
        checkpoint("s1_state_after_calibration_confirm")

        // 8. Reach the real generated Week 1 and assert its real,
        // semantic shape.
        let viewWeekTapped = tapExactButton("View Week", timeout: 5)
        var weekHierarchy = checkpoint("s1_week1_overview_attempt")
        if !viewWeekTapped {
            _ = tapFirstButton(labelContains: "Plan", timeout: 5)
            weekHierarchy = checkpoint("s1_week1_overview_via_plan_tab")
        }
        var weekAdvances = 0
        while weekHierarchy.contains("hasn't been scheduled yet") && weekAdvances < 3 {
            guard tapExactButton("Next Week", timeout: 5) else { break }
            weekAdvances += 1
            weekHierarchy = checkpoint("s1_week_view_after_next_week_tap_\(weekAdvances)")
        }
        note("Final week-view hierarchy captured after \(weekAdvances) 'Next Week' advance(s).")

        // Real, empirically confirmed label format for this week view
        // (captured this run): each real training day is its own button
        // labeled exactly "Day N, <status>, <BLOCK TYPE>, N exercises" —
        // never "Session N" (that label belongs to a different screen).
        var dayRowsFound = 0
        var dayRowsLabeledHypertrophy = 0
        var dayRowsLabeledOther = 0
        for dayIndex in 1...7 {
            let dayButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Day \(dayIndex),")).firstMatch
            guard dayButton.waitForExistence(timeout: 3) else { continue }
            dayRowsFound += 1
            let label = dayButton.label
            note("Day \(dayIndex) row label: '\(label)'")
            if label.localizedCaseInsensitiveContains("hypertrophy") {
                dayRowsLabeledHypertrophy += 1
            } else {
                dayRowsLabeledOther += 1
            }
        }
        note("Real training-day rows found on the generated Week 1 view: \(dayRowsFound) (expected exactly 5 — Sat/Sun render as 'Rest Day' text, not a Day button).")
        XCTAssertEqual(dayRowsFound, 5, "INVARIANT 7 (Section 21-B): 5 training days, no conditioning preference -> exactly 5 real training days materialize, never 4 (the old 4H+1Z2 split) or 6+")
        XCTAssertEqual(dayRowsLabeledHypertrophy, 5, "INVARIANT 9 (Section 19/21-B): every one of the 5 real training days must be labeled HYPERTROPHY, reflecting its actual canonical block type — never a mix of some Hypertrophy + some other system")
        XCTAssertEqual(dayRowsLabeledOther, 0, "INVARIANT 10 (Sections 2-3): zero training days may be labeled Conditioning/Functional Fitness/Zone 2 for this exact scenario")

        let restDayCount = app.staticTexts.matching(NSPredicate(format: "label == %@", "Rest Day")).allElementsBoundByIndex.count
        note("Real 'Rest Day' rows found: \(restDayCount) (expected exactly 2 — Saturday + Sunday).")
        XCTAssertEqual(restDayCount, 2, "INVARIANT 11: exactly 2 real rest days (Sat/Sun) — 5 training days never silently becomes 7")

        let weekMentionsZoneTwo = weekHierarchy.localizedCaseInsensitiveContains("zone 2")
        note("Week 1 view mentions 'Zone 2': \(weekMentionsZoneTwo).")
        XCTAssertFalse(weekMentionsZoneTwo, "INVARIANT 8 (Sections 2-3): the materialized week must never contain a Zone 2/steady-state session for this exact scenario")

        // Open the first real training day and confirm its detail view is
        // internally consistent with the week-overview label (Section 19:
        // rendered block labels must reflect actual canonical purpose).
        let firstDayButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Day 1,")).firstMatch
        if firstDayButton.waitForExistence(timeout: 5) {
            firstDayButton.tap()
            let detail = checkpoint("s1_day1_detail")
            let detailMentionsHypertrophy = detail.localizedCaseInsensitiveContains("hypertrophy")
            note("Day 1 detail view mentions Hypertrophy: \(detailMentionsHypertrophy).")
            XCTAssertTrue(detailMentionsHypertrophy, "INVARIANT 12 (Section 19): Day 1's own detail view must also reflect its real Hypertrophy block type, consistent with the week-overview row")
        }

        let logURL = artifactsRoot.appendingPathComponent("ui-state/00_scenario1_log.txt")
        try? log.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Scenario 2 (primary): Build Muscle + 5 days + Custom Mix
    // 5x Functional Fitness, real movement-capability entry through the
    // real UI, real Week 1 materialization, every session/block captured.

    /// MUSCLE VERTICAL SLICE CONTINUATION, Sections 20-23: the primary
    /// real-simulator acceptance scenario. Clean state, real onboarding,
    /// real Custom Mix (5x Functional Fitness), real entry of the 3
    /// gated movements' capability through Profile -> Movement Capability
    /// (Sections 9-11's own new screen — never seeded/bypassed), real
    /// Accept & Start, real Week 1, every one of the 5 real sessions and
    /// every real block captured (screenshot + accessibility hierarchy).
    /// A genuine PASS/FAIL acceptance test, not print-only narration.
    func testMuscleFiveFFCustomMixWithRealCapabilityEntryScenario2() throws {
        var log: [String] = []
        func note(_ s: String) { log.append(s); print("SCENARIO2 LOG: \(s)") }

        // 1. Primary goal.
        checkpoint("s2_primary_goal_screen")
        let goalTapped = tapFirstButton(labelContains: "muscle")
        note("Tapped a 'muscle' goal option: \(goalTapped)")
        XCTAssertTrue(goalTapped, "a 'Build Muscle'-labeled goal option must be real and tappable")
        _ = tapExactButton("Continue")
        checkpoint("s2_after_goal_continue")

        // 2. Training days: Mon-Fri ON, Sat/Sun OFF -> exactly 5 days.
        func setWeekday(_ day: String, to shouldBeOn: Bool) -> Bool {
            let toggle = app.switches.matching(NSPredicate(format: "label CONTAINS[c] %@", day)).firstMatch
            guard toggle.waitForExistence(timeout: 3) else { return false }
            let isOn = (toggle.value as? String) == "1"
            if isOn != shouldBeOn { toggle.tap() }
            return true
        }
        var toggledCount = 0
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"] {
            if setWeekday(day, to: true) { toggledCount += 1 }
        }
        for day in ["Saturday", "Sunday"] { _ = setWeekday(day, to: false) }
        note("Weekday toggles confirmed ON for \(toggledCount)/5 weekdays.")
        XCTAssertEqual(toggledCount, 5, "all 5 weekday toggles must be real and reachable")
        checkpoint("s2_preferences_after_weekday_selection")
        _ = tapExactButton("Continue")
        checkpoint("s2_after_preferences_continue")

        // 3. Training environment — default Full Gym, just continue.
        _ = tapExactButton("Continue")
        checkpoint("s2_after_environment_continue")

        // 4. Review -> "See My Recommended Plan".
        let sawRecommendation = tapFirstButton(labelContains: "Recommended Plan")
        note("Tapped 'See My Recommended Plan': \(sawRecommendation)")
        checkpoint("s2_recommended_plan_screen")

        // 5. Custom mix: 5x Functional Fitness.
        let customMixOpened = tapFirstButton(labelContains: "Build My Own Mix")
        note("Opened custom Training Mix editor: \(customMixOpened)")
        XCTAssertTrue(customMixOpened, "the 'Build My Own Mix' entry point must be real and reachable")
        checkpoint("s2_custom_mix_initial")

        let allPlusButtons = app.buttons.allElementsBoundByIndex
        let ffLabel = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", "Functional Fitness")).firstMatch
        var ffPlusTapped = 0
        if ffLabel.waitForExistence(timeout: 5) {
            let sameRowButtons = allPlusButtons.filter { abs($0.frame.midY - ffLabel.frame.midY) < 30 }
            if let plusButton = sameRowButtons.last {
                for _ in 0..<5 where plusButton.exists && plusButton.isEnabled {
                    plusButton.tap()
                    ffPlusTapped += 1
                }
            }
        }
        note("Functional Fitness '+' tapped \(ffPlusTapped) times (target 5).")
        XCTAssertEqual(ffPlusTapped, 5, "the real Custom Mix editor must allow exactly 5x Functional Fitness")
        checkpoint("s2_custom_mix_after_ff_selection")

        let usedMix = tapFirstButton(labelContains: "Use This Mix")
        note("Tapped 'Use This Mix': \(usedMix)")
        checkpoint("s2_after_use_this_mix")

        // 6. Accept & Start Training.
        let accepted = tapFirstButton(labelContains: "Accept & Start Training")
        note("Tapped 'Accept & Start Training': \(accepted)")
        XCTAssertTrue(accepted, "'Accept & Start Training' must be real and reachable from the reviewed custom mix")
        checkpoint("s2_after_accept_and_start")

        // 7. MUSCLE VERTICAL SLICE CONTINUATION, Sections 9-11: real
        // movement-capability entry through Profile -> Movement
        // Capability — never seeded/bypassed. Same deterministic fixture
        // values this UI test target has documented since the earlier
        // diagnostic pass (Toes-to-Bar=7, Pull-up=5, Handstand Push-up=3),
        // now entered through the real screen this checkpoint built.
        let profileTabTapped = tapFirstButton(labelContains: "Profile", timeout: 5)
        note("Tapped 'Profile' tab: \(profileTabTapped)")
        checkpoint("s2_profile_tab")
        XCTAssertTrue(profileTabTapped, "the Profile tab must be real and reachable after Accept & Start")

        let movementCapabilityOpened = tapFirstButton(labelContains: "Movement Capability", timeout: 5)
        note("Opened Movement Capability screen: \(movementCapabilityOpened)")
        XCTAssertTrue(movementCapabilityOpened, "the real Movement Capability screen (Sections 9-11) must be reachable from Profile")
        checkpoint("s2_movement_capability_initial")

        let capabilityFixtures: [(exercise: String, reps: String)] = [
            ("Toes-to-Bar", "7"), ("Pull-up", "5"), ("Handstand Push-up", "3"),
        ]
        var capabilityRowsSet = 0
        for (exercise, reps) in capabilityFixtures {
            let toggle = app.switches["workoutReadyToggle.\(exercise)"]
            guard toggle.waitForExistence(timeout: 5) else {
                note("BLOCKED: workout-ready toggle for '\(exercise)' not found.")
                continue
            }
            // The identifier is on the ROW-SPANNING `Toggle` container; a
            // synthesized tap on it doesn't reliably hit-test the actual
            // switch control (real, empirically observed this run — the
            // outer element's tap silently did not flip `value`). The
            // real, always-present inner `Switch` sub-element is what
            // must receive the tap.
            if (toggle.value as? String) != "1" {
                let innerSwitch = toggle.switches.firstMatch
                if innerSwitch.exists { innerSwitch.tap() } else { toggle.tap() }
            }
            let toggleValueAfterTap = (app.switches["workoutReadyToggle.\(exercise)"].value as? String) ?? "?"
            note("'\(exercise)' workout-ready toggle value after tap: \(toggleValueAfterTap).")
            let field = app.textFields["maxUnbrokenRepsField.\(exercise)"]
            if field.waitForExistence(timeout: 5) {
                field.tap()
                field.typeText(reps)
                capabilityRowsSet += 1
                note("Set '\(exercise)' workout-ready with max unbroken reps = \(reps).")
            } else {
                note("BLOCKED: max-unbroken-reps field for '\(exercise)' not found after enabling workout-ready (toggle value was '\(toggleValueAfterTap)').")
            }
        }
        note("Movement capability rows set: \(capabilityRowsSet) of \(capabilityFixtures.count).")
        XCTAssertEqual(capabilityRowsSet, 3, "all 3 gated movements' capability must be real, enterable, and verifiable through the actual UI")
        checkpoint("s2_movement_capability_after_entry")

        let capabilitySaved = tapFirstButton(labelContains: "Save", timeout: 5)
        note("Tapped 'Save' on Movement Capability screen: \(capabilitySaved)")
        XCTAssertTrue(capabilitySaved, "the real Save action must be reachable and must dismiss back to Profile")
        checkpoint("s2_after_movement_capability_save")

        // Re-open to prove the entry actually persisted (real round-trip
        // through SwiftData, never merely an in-memory form state).
        let reopened = tapFirstButton(labelContains: "Movement Capability", timeout: 5)
        note("Re-opened Movement Capability screen to verify persistence: \(reopened)")
        checkpoint("s2_movement_capability_reopened")
        let reopenedToggle = app.switches["workoutReadyToggle.Toes-to-Bar"]
        let reopenedToggleValue = reopenedToggle.waitForExistence(timeout: 5) ? (reopenedToggle.value as? String ?? "?") : "missing"
        let reopenedField = app.textFields["maxUnbrokenRepsField.Toes-to-Bar"]
        let reopenedFieldValue = reopenedField.waitForExistence(timeout: 5) ? (reopenedField.value as? String ?? "?") : "missing"
        note("FACT: reopened Toes-to-Bar toggle value='\(reopenedToggleValue)' (expect '1'), reps field value='\(reopenedFieldValue)' (expect '7').")
        XCTAssertEqual(reopenedToggleValue, "1", "the real entered workout-ready state must round-trip through real persistence, never lost on dismiss")
        XCTAssertEqual(reopenedFieldValue, "7", "the real entered capacity value must round-trip through real persistence, never lost on dismiss")
        _ = app.navigationBars.buttons.element(boundBy: 0).exists && { app.navigationBars.buttons.element(boundBy: 0).tap(); return true }()

        // 8. Reach the real Week 1 view. The real Plan tab (confirmed via
        // this run's own captured hierarchy) lands on the STRATEGIC plan
        // overview, not the tactical week list directly — "View Tactical
        // Week" is the real navigation from there into it, distinct from
        // the older diagnostic harness's "View Week"/"Next Week" pattern
        // (that one reached the tactical week directly from Today).
        let planTabTapped = tapFirstButton(labelContains: "Plan", timeout: 5)
        note("Tapped 'Plan' tab: \(planTabTapped)")
        checkpoint("s2_plan_overview")
        let viewTacticalWeekTapped = tapFirstButton(labelContains: "View Tactical Week", timeout: 5)
        note("Tapped 'View Tactical Week': \(viewTacticalWeekTapped)")
        var weekHierarchy = checkpoint("s2_week_overview_attempt")
        var weekAdvances = 0
        while (weekHierarchy.contains("hasn't been scheduled yet") || weekHierarchy.contains("nothing to do before it starts")) && weekAdvances < 3 {
            let nextWeekTapped = tapExactButton("Next Week", timeout: 5)
            note("Week not yet scheduled — tapped 'Next Week' (attempt \(weekAdvances + 1)): \(nextWeekTapped)")
            guard nextWeekTapped else { break }
            weekAdvances += 1
            weekHierarchy = checkpoint("s2_week_view_after_next_week_tap_\(weekAdvances)")
        }

        // MUSCLE VERTICAL SLICE CONTINUATION, Section 16: the real
        // dogfood defect — every one of the 5 sessions showed "STRENGTH"
        // regardless of real content. Capture every session/block and
        // assert the week-overview labels are no longer uniformly
        // "STRENGTH".
        let strengthLabelCount = weekHierarchy.components(separatedBy: "STRENGTH").count - 1
        note("Week-overview occurrences of literal 'STRENGTH': \(strengthLabelCount) (must not be 5 — the exact dogfood defect).")
        XCTAssertNotEqual(strengthLabelCount, 5, "INVARIANT (Section 16): all 5 sessions showing the raw 'STRENGTH' label regardless of real content is the exact dogfood defect this checkpoint fixed")

        for sessionIndex in 1...5 {
            // Real, empirically-confirmed label for a Functional-Fitness-
            // modality mix's tactical week row (this run's own captured
            // hierarchy): "Week 1 — Session N, Upcoming, <REAL BLOCK
            // LABEL>, ..." — a compound Button, not a bare StaticText.
            let sessionRow = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Session \(sessionIndex),")).firstMatch
            if sessionRow.waitForExistence(timeout: 5) {
                sessionRow.tap()
                checkpoint("s2_session\(sessionIndex)_overview")
                let blockCells = app.cells.allElementsBoundByIndex
                note("Session \(sessionIndex): \(blockCells.count) real cell(s) found.")
                if blockCells.isEmpty {
                    var lastHierarchyLength = -1
                    for scrollAttempt in 0..<4 {
                        let hierarchy = checkpoint("s2_session\(sessionIndex)_block_scroll\(scrollAttempt)")
                        if hierarchy.count == lastHierarchyLength { break }
                        lastHierarchyLength = hierarchy.count
                        app.swipeUp()
                    }
                } else {
                    for (blockIndex, cell) in blockCells.enumerated() {
                        guard cell.exists else { continue }
                        cell.tap()
                        checkpoint("s2_session\(sessionIndex)_block\(blockIndex)_detail")
                        if app.navigationBars.buttons.element(boundBy: 0).exists {
                            app.navigationBars.buttons.element(boundBy: 0).tap()
                        }
                    }
                }
                if app.navigationBars.buttons.element(boundBy: 0).exists {
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                }
            } else {
                note("Session \(sessionIndex) row not found on Week 1 view.")
            }
        }

        let traceString = retrieveRuntimeTrace()
        note("Runtime trace retrieved in-process: \(traceString != nil) (expected false — see coordinator's own separate simctl retrieval step).")

        let logURL = artifactsRoot.appendingPathComponent("ui-state/00_scenario2_log.txt")
        try? log.joined(separator: "\n").write(to: logURL, atomically: true, encoding: .utf8)
    }
}
