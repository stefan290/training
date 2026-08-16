import XCTest
import SwiftData
@testable import TrainingOS

/// Hardening pass: proves the two weak points Stage 4F's own report
/// flagged are actually fixed —
/// (1) `GoalAlignmentEvaluator` never depends on `warnings` display text,
/// only on structured `ScheduleIssue`s, and
/// (2) `.primaryGoalPriority`/conflict resolution reflects real,
/// configuration-driven priority (never "whichever component was
/// inserted first," never hardcoded to a specific modality).
@MainActor
final class SchedulerHardeningTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func mondayStart() -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
    }

    private func makeSession(
        _ name: String,
        modality: TrainingModality = .strength,
        stress: TrainingStressProfile? = nil,
        isKeySession: Bool = false
    ) -> Session {
        let session = Session(name: name, modality: modality, isKeySession: isKeySession)
        context.insert(session)
        if let stress {
            let block = WorkoutBlock(type: .strength, trainingStressProfile: stress)
            context.insert(block)
            session.addBlock(block)
        }
        return session
    }

    private func makeComponent(
        label: String,
        priority: GoalPriority,
        frequency: SessionFrequency,
        flexibility: ComponentFlexibility = .preferred,
        allowsDoubleSessionPairing: Bool = true,
        preferredDays: [Weekday] = [],
        requiredSpacingDays: Int? = nil,
        mix: TrainingMix? = nil
    ) -> TrainingMixComponent {
        let component = TrainingMixComponent(
            label: label,
            priority: priority,
            frequency: frequency,
            flexibility: flexibility,
            allowsDoubleSessionPairing: allowsDoubleSessionPairing,
            preferredDays: preferredDays,
            requiredSpacingDays: requiredSpacingDays
        )
        context.insert(component)
        mix?.addComponent(component)
        return component
    }

    // MARK: - A/B: GoalAlignment never depends on warning/display text

    /// Two proposals whose `issues` are entirely empty (a clean schedule)
    /// but whose `reason` strings are deliberately alarming — if
    /// `GoalAlignmentEvaluator` accidentally keyed off text content, this
    /// would report a compromise that doesn't structurally exist.
    func testGoalAlignmentNeverReadsWarningsText() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let component = makeComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 1), mix: mix)
        let session = makeSession("S0")

        let alarmingIssue = ScheduleIssue(
            code: .doubleSessionRequired,
            severity: .soft,
            componentLabel: "Strength",
            session: session,
            reason: "CATASTROPHIC SCHEDULING FAILURE — EVERYTHING IS BROKEN, DO NOT TRUST THIS PLAN"
        )
        let placement = SessionPlacement(session: session, componentLabel: "Strength", date: mondayStart(), sortIndexInDay: 0, reasonCodes: [.programOrderPreserved])
        let proposal = ScheduleProposal(
            schedulerVersion: ConcurrentScheduler.currentVersion,
            window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 7),
            placements: [placement],
            conflicts: [],
            feasibility: .feasibleWithSoftViolations,
            issues: [alarmingIssue]
        )

        XCTAssertTrue(proposal.warnings.first?.contains("CATASTROPHIC") ?? false, "sanity check: the alarming text really is in `warnings`")

        let alignment = GoalAlignmentEvaluator.evaluate(mix: mix, proposal: proposal)
        // `.doubleSessionRequired` isn't one of the codes any factor
        // reads (only `.interferenceConflict`/`.recoverySpacingCompromise`
        // affect `interferenceAndRecoveryCompromise`) — so despite the
        // alarming display text, every factor should still read clean.
        XCTAssertTrue(alignment.factors.allSatisfy(\.satisfied), "alarming warning TEXT must never influence the structured result")
        XCTAssertEqual(alignment.rating, .excellent)
    }

    /// Same structured `issues` (same codes/severities), only the display
    /// `reason` text changed — the alignment result must be byte-identical.
    func testChangingIssueDisplayCopyNeverChangesGoalAlignment() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let primary = makeComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 1), mix: mix)
        _ = primary
        let session = makeSession("S0")
        let placement = SessionPlacement(session: session, componentLabel: "Strength", date: mondayStart(), sortIndexInDay: 0, reasonCodes: [.programOrderPreserved, .softConstraintViolated])

        let originalIssue = ScheduleIssue(code: .preferenceCompromise, severity: .soft, componentLabel: "Strength", session: session, reason: "No preferred day was available.")
        let rewordedIssue = ScheduleIssue(code: .preferenceCompromise, severity: .soft, componentLabel: "Strength", session: session, reason: "")

        func makeProposal(issue: ScheduleIssue) -> ScheduleProposal {
            ScheduleProposal(
                schedulerVersion: ConcurrentScheduler.currentVersion,
                window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 7),
                placements: [placement],
                conflicts: [],
                feasibility: .feasibleWithSoftViolations,
                issues: [issue]
            )
        }

        let originalAlignment = GoalAlignmentEvaluator.evaluate(mix: mix, proposal: makeProposal(issue: originalIssue))
        let rewordedAlignment = GoalAlignmentEvaluator.evaluate(mix: mix, proposal: makeProposal(issue: rewordedIssue))

        XCTAssertEqual(originalAlignment, rewordedAlignment)
        XCTAssertNotEqual(makeProposal(issue: originalIssue).warnings, makeProposal(issue: rewordedIssue).warnings, "sanity check: display copy really did change")
    }

    // MARK: - C/D: real conflict resolution, not first-claim

    func testPrimaryRequiredSessionWinsARealPlacementConflict() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let primary = makeComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 1), flexibility: .required, mix: mix)
        let secondary = makeComponent(label: "Functional Fitness", priority: .secondary, frequency: SessionFrequency(target: 1), flexibility: .preferred, mix: mix)

        let availability = UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1))

        let proposal = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: primary, sessions: [makeSession("Lift")]),
            ScheduledProgramInput(component: secondary, sessions: [makeSession("WOD")]),
        ], constraints: constraints)

        XCTAssertEqual(proposal.placements.count, 1)
        let winner = try XCTUnwrap(proposal.placements.first)
        XCTAssertEqual(winner.componentLabel, "Strength")
        XCTAssertTrue(winner.reasonCodes.contains(.primaryGoalPriority), "priority only mattered because Functional Fitness genuinely also wanted this day")
        XCTAssertEqual(proposal.conflicts.first?.componentLabel, "Functional Fitness")
    }

    /// Same scenario as above, but the lower-priority component is listed
    /// FIRST in the `inputs` array — proves the winner is decided by
    /// configured priority, never by array/insertion order.
    func testSecondaryPreferredSessionNeverDisplacesRequiredPrimaryWorkRegardlessOfInsertionOrder() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let secondary = makeComponent(label: "Functional Fitness", priority: .secondary, frequency: SessionFrequency(target: 1), flexibility: .preferred, mix: mix)
        let primary = makeComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 1), flexibility: .required, mix: mix)

        let availability = UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1))

        // Secondary listed FIRST here — old "first-claim" code would have
        // let it grab the only day.
        let proposal = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: secondary, sessions: [makeSession("WOD")]),
            ScheduledProgramInput(component: primary, sessions: [makeSession("Lift")]),
        ], constraints: constraints)

        XCTAssertEqual(proposal.placements.count, 1)
        XCTAssertEqual(proposal.placements.first?.componentLabel, "Strength")
        XCTAssertEqual(proposal.conflicts.first?.componentLabel, "Functional Fitness")
    }

    // MARK: - E: optional component can remain unscheduled, with a structured issue

    func testOptionalSupportingSessionCanRemainUnscheduledAndProducesAStructuredIssue() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let required = makeComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 1), flexibility: .required, mix: mix)
        let optional = makeComponent(label: "Zone 2", priority: .supporting, frequency: SessionFrequency(target: 1), flexibility: .optional, mix: mix)

        let availability = UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1))

        let proposal = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: required, sessions: [makeSession("Lift")]),
            ScheduledProgramInput(component: optional, sessions: [makeSession("Easy Zone 2")]),
        ], constraints: constraints)

        XCTAssertEqual(proposal.placements.first?.componentLabel, "Strength")
        let issue = try XCTUnwrap(proposal.issues.first { $0.code == .optionalComponentUnscheduled })
        XCTAssertEqual(issue.severity, .soft, "an optional component going unscheduled is a low-severity, expected outcome")
        XCTAssertEqual(issue.componentLabel, "Zone 2")
        // Never a `.primaryGoalCompromise` for the merely-optional component.
        XCTAssertFalse(proposal.issues.contains { $0.code == .primaryGoalCompromise && $0.componentLabel == "Zone 2" })
    }

    // MARK: - F: user-selected mix stays respected even at lower alignment, never mutated

    func testUserSelectedHybridMixRemainsRespectedEvenIfAlignmentIsLowerThanRecommendedMix() throws {
        let recommendedMix = TrainingMix(kind: .recommended, name: "Recommended: Pure Hypertrophy")
        context.insert(recommendedMix)
        let recommendedComponent = makeComponent(label: "Hypertrophy", priority: .primary, frequency: SessionFrequency(target: 1), mix: recommendedMix)

        let selectedMix = TrainingMix(kind: .selected, name: "Selected: Hybrid With A Compromise")
        context.insert(selectedMix)
        let selectedComponent = makeComponent(
            label: "Hybrid", priority: .primary, frequency: SessionFrequency(target: 1),
            preferredDays: [.wednesday], mix: selectedMix
        )

        let availability = UserAvailability(trainingDaysPerWeek: 7, unavailableWeekdays: [.wednesday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 7))

        let recommendedProposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: recommendedComponent, sessions: [makeSession("R0")])],
            constraints: constraints
        )
        let selectedProposal = ConcurrentScheduler.schedule(
            [ScheduledProgramInput(component: selectedComponent, sessions: [makeSession("S0")])],
            constraints: constraints
        )

        let recommendedAlignment = GoalAlignmentEvaluator.evaluate(mix: recommendedMix, proposal: recommendedProposal)
        let selectedAlignment = GoalAlignmentEvaluator.evaluate(mix: selectedMix, proposal: selectedProposal)

        XCTAssertEqual(recommendedAlignment.rating, .excellent)
        XCTAssertLessThan(selectedAlignment.rating, recommendedAlignment.rating, "the selected mix genuinely scores lower")

        // The lower-scoring SELECTED mix must still be schedulable.
        XCTAssertNotEqual(selectedProposal.feasibility, .infeasible)
        XCTAssertEqual(selectedProposal.placements.count, 1)

        // Scheduling/evaluating the selected mix must never mutate the
        // recommended one.
        XCTAssertEqual(recommendedMix.kind, .recommended)
        XCTAssertEqual(recommendedMix.orderedComponents.first?.label, "Hypertrophy")
        XCTAssertEqual(recommendedMix.orderedComponents.first?.frequency, SessionFrequency(target: 1))
    }

    // MARK: - G: running-priority phase protects key running work (not modality-hardcoded)

    func testRunningPriorityPhaseProtectsKeyRunningWork() throws {
        let mix = TrainingMix(kind: .selected, name: "Running Performance Phase")
        context.insert(mix)
        // Running is PRIMARY here — proves protection is config-driven,
        // not "strength always wins."
        let running = makeComponent(label: "Running", priority: .primary, frequency: SessionFrequency(target: 1), flexibility: .required, mix: mix)
        let strength = makeComponent(label: "Strength Maintenance", priority: .secondary, frequency: SessionFrequency(target: 1), mix: mix)

        let contestedAvailability = UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let contestedConstraints = SchedulingConstraints(availability: contestedAvailability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1))

        let contestedProposal = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: running, sessions: [makeSession("Key Long Run", modality: .conditioning)]),
            ScheduledProgramInput(component: strength, sessions: [makeSession("Maintenance Lift")]),
        ], constraints: contestedConstraints)

        XCTAssertEqual(contestedProposal.placements.first?.componentLabel, "Running")
        XCTAssertEqual(contestedProposal.conflicts.first?.componentLabel, "Strength Maintenance")

        // Within Running's OWN sessions, the key session (long run) is
        // protected over a plain easy run when only one of two fits.
        let runningWithThreeSessions = makeComponent(label: "Running Week", priority: .primary, frequency: SessionFrequency(target: 3), flexibility: .preferred)
        let easyRun = makeSession("Easy Run", modality: .conditioning, isKeySession: false)
        let longRun = makeSession("Long Run", modality: .conditioning, isKeySession: true)
        let tempoRun = makeSession("Tempo Run", modality: .conditioning, isKeySession: true)

        let scarceAvailability = UserAvailability(trainingDaysPerWeek: 2, availableWeekdays: [.monday, .tuesday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let scarceConstraints = SchedulingConstraints(availability: scarceAvailability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 2))

        let weekProposal = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: runningWithThreeSessions, sessions: [easyRun, longRun, tempoRun]),
        ], constraints: scarceConstraints)

        let placedNames = Set(weekProposal.placements.map { $0.session.name })
        XCTAssertEqual(placedNames, ["Long Run", "Tempo Run"], "the two KEY sessions must be protected over the plain easy run")
        XCTAssertEqual(weekProposal.conflicts.first?.unplacedSessions.first?.session.name, "Easy Run")
    }

    // MARK: - H: muscle-gain phase protects required resistance training

    func testMuscleGainPhaseProtectsRequiredResistanceTraining() throws {
        let mix = TrainingMix(kind: .selected, name: "Muscle Gain Phase")
        context.insert(mix)
        let strength = makeComponent(label: "Hypertrophy", priority: .primary, frequency: SessionFrequency(target: 1), flexibility: .required, mix: mix)
        let functionalFitness = makeComponent(label: "Functional Fitness", priority: .secondary, frequency: SessionFrequency(target: 1), mix: mix)

        let availability = UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1))

        let proposal = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: strength, sessions: [makeSession("Squat Day", modality: .hypertrophy)]),
            ScheduledProgramInput(component: functionalFitness, sessions: [makeSession("Metcon", modality: .functionalFitness)]),
        ], constraints: constraints)

        XCTAssertEqual(proposal.placements.first?.componentLabel, "Hypertrophy")
        XCTAssertTrue(proposal.placements.first?.reasonCodes.contains(.primaryGoalPriority) ?? false)
        XCTAssertEqual(proposal.conflicts.first?.componentLabel, "Functional Fitness")
    }

    // MARK: - I: impossible schedule returns Infeasible

    func testImpossibleScheduleReturnsInfeasibleAlignment() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let component = makeComponent(label: "Overloaded", priority: .primary, frequency: SessionFrequency(target: 3, minimum: 3), flexibility: .required, allowsDoubleSessionPairing: false, mix: mix)
        let sessions = (0..<3).map { makeSession("S\($0)") }

        let availability = UserAvailability(trainingDaysPerWeek: 1, availableWeekdays: [.monday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 1))

        let proposal = ConcurrentScheduler.schedule([ScheduledProgramInput(component: component, sessions: sessions)], constraints: constraints)
        XCTAssertEqual(proposal.feasibility, .infeasible)

        let alignment = GoalAlignmentEvaluator.evaluate(mix: mix, proposal: proposal)
        XCTAssertEqual(alignment.rating, .infeasible)
    }

    // MARK: - J: feasible with minor soft compromise returns a non-infeasible, non-excellent rating

    func testFeasibleScheduleWithMinorSoftCompromiseReturnsAppropriateNonInfeasibleAlignment() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let component = makeComponent(
            label: "Strength", priority: .primary, frequency: SessionFrequency(target: 1),
            preferredDays: [.wednesday], mix: mix
        )
        // Wednesday unavailable forces exactly one compromise
        // (`.preferenceCompromise`) while everything else is clean.
        let availability = UserAvailability(trainingDaysPerWeek: 6, unavailableWeekdays: [.wednesday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 7))

        let proposal = ConcurrentScheduler.schedule([ScheduledProgramInput(component: component, sessions: [makeSession("S0")])], constraints: constraints)
        XCTAssertEqual(proposal.feasibility, .feasibleWithSoftViolations)

        let alignment = GoalAlignmentEvaluator.evaluate(mix: mix, proposal: proposal)
        XCTAssertNotEqual(alignment.rating, .infeasible)
        XCTAssertNotEqual(alignment.rating, .excellent, "one real compromise must cost something")
        XCTAssertGreaterThan(alignment.rating, .poor)
    }

    // MARK: - K: identical inputs produce identical proposal AND alignment

    func testIdenticalInputsProduceIdenticalProposalAndAlignment() throws {
        func build() -> (TrainingMix, [ScheduledProgramInput]) {
            let mix = TrainingMix(kind: .selected, name: "Mix")
            context.insert(mix)
            let strength = makeComponent(label: "Strength", priority: .primary, frequency: SessionFrequency(target: 2), mix: mix)
            let ff = makeComponent(label: "Functional Fitness", priority: .secondary, frequency: SessionFrequency(target: 1), mix: mix)
            return (mix, [
                ScheduledProgramInput(component: strength, sessions: (0..<2).map { makeSession("Strength \($0)") }),
                ScheduledProgramInput(component: ff, sessions: [makeSession("FF", stress: nil)]),
            ])
        }

        let availability = UserAvailability(trainingDaysPerWeek: 4, unavailableWeekdays: [.saturday, .sunday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 5))

        let (mixA, inputsA) = build()
        let (mixB, inputsB) = build()

        let resultA = SchedulingPipeline.propose(mix: mixA, inputs: inputsA, constraints: constraints)
        let resultB = SchedulingPipeline.propose(mix: mixB, inputs: inputsB, constraints: constraints)

        func signature(_ proposal: ScheduleProposal) -> [String] {
            proposal.placements
                .sorted { $0.componentLabel == $1.componentLabel ? $0.date < $1.date : $0.componentLabel < $1.componentLabel }
                .map { "\($0.componentLabel)|\($0.date.timeIntervalSince1970 - proposal.window.startDate.timeIntervalSince1970)|\($0.reasonCodes.sorted { $0.rawValue < $1.rawValue })" }
        }

        XCTAssertEqual(signature(resultA.proposal), signature(resultB.proposal))
        XCTAssertEqual(resultA.alignment, resultB.alignment)
    }

    // MARK: - L: insertion order of TrainingMixComponents does not change the result

    func testInsertionOrderOfEquallyPrioritizedComponentsNeverChangesTheResult() throws {
        let mix = TrainingMix(kind: .selected, name: "Mix")
        context.insert(mix)
        let componentA = makeComponent(label: "Aerobic Base", priority: .secondary, frequency: SessionFrequency(target: 1), mix: mix)
        let componentB = makeComponent(label: "Functional Fitness", priority: .secondary, frequency: SessionFrequency(target: 1), mix: mix)

        let availability = UserAvailability(trainingDaysPerWeek: 2, availableWeekdays: [.monday, .tuesday], allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let constraints = SchedulingConstraints(availability: availability, window: SchedulingWindow(startDate: mondayStart(), numberOfDays: 2))

        let sessionA = makeSession("Zone 2")
        let sessionB = makeSession("WOD")

        let forwardOrder = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: componentA, sessions: [sessionA]),
            ScheduledProgramInput(component: componentB, sessions: [sessionB]),
        ], constraints: constraints)

        let reversedOrder = ConcurrentScheduler.schedule([
            ScheduledProgramInput(component: componentB, sessions: [sessionB]),
            ScheduledProgramInput(component: componentA, sessions: [sessionA]),
        ], constraints: constraints)

        func datesByComponent(_ proposal: ScheduleProposal) -> [String: Date] {
            Dictionary(uniqueKeysWithValues: proposal.placements.map { ($0.componentLabel, $0.date) })
        }

        XCTAssertEqual(datesByComponent(forwardOrder), datesByComponent(reversedOrder))
    }
}
