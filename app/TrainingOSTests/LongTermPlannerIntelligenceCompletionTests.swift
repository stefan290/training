import XCTest
import SwiftData
@testable import TrainingOS

/// Long-Term Planner Intelligence (Vertical Completion V2): proves
/// `StrategicPeriodizationPolicy` replaces the old mechanical
/// `consecutivePrimary >= 2 ? .maintenance : primaryType` loop with a
/// real, explainable, deterministic strategic policy — golden 12-month
/// traces (A/B), dated-objective integration (C/D), horizon edge cases
/// (E/F/G), and the 15 specific requirements the checkpoint's own
/// directive lists. Every phase here comes from the real
/// `LongTermPlanner.proposeStrategicPlan`/`AcceptStrategicPlanUseCase`
/// pipeline, never a hand-built fixture.
@MainActor
final class LongTermPlannerIntelligenceCompletionTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }

    private func df(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Mirrors `PhaseTransitionOrchestrationTests.completeAllSessions`'s
    /// exact pattern, scoped to one materialized week so it can be called
    /// once per real tactical roll without double-completing a session.
    private func completeSessions(in instance: ProgramInstance, weekIndex: Int, performanceProfile: PerformanceProfile, asOf: Date) throws {
        let sessions = ProgramWeekGrouping.realSessions(in: instance, forWeek: weekIndex)
        for session in sessions {
            for block in session.orderedBlocks {
                for prescription in block.orderedPrescriptions {
                    for setPrescription in prescription.orderedSetPrescriptions {
                        RecordSetResultUseCase.recordSet(
                            setIndex: 0, weight: setPrescription.targetWeight ?? 40, reps: 8, targetRir: nil, actualRir: nil, prBand: nil,
                            scoringDirection: .higherIsBetter, context: .rx, setPrescription: setPrescription, exercisePrescription: prescription,
                            exercise: prescription.exercise ?? Exercise(canonicalName: "fallback-\(UUID())", modality: .hypertrophy, equipment: "none", movementPattern: "none"),
                            performanceProfile: performanceProfile, completedAt: asOf, modelContext: context
                        )
                    }
                }
                try CompleteBlockUseCase.complete(block, context: .full, modelContext: context)
            }
            try CompleteSessionUseCase.complete(session, context: .full, asOf: asOf, modelContext: context)
        }
    }

    private func printPhaseTable(_ label: String, phases: [ProposedPhase]) {
        print("\n=== \(label) ===")
        for (index, phase) in phases.enumerated() {
            let end = phase.endDate.map(df) ?? "open-ended"
            let weeks = phase.startDate.distance(to: phase.endDate ?? phase.startDate) / (7 * 24 * 3600)
            print("Phase \(index + 1) | \(df(phase.startDate)) -> \(end) | ~\(Int(weeks))wk | \(phase.type.rawValue) | reasons: \(phase.reasonCodes.map(\.rawValue).joined(separator: ","))")
        }
    }

    // MARK: - Golden A: Get Stronger, ~52 weeks, no objective

    func testGoldenA_GetStrongerTwelveMonthsProducesRealStrategicVariety() throws {
        let asOf = date(2026, 1, 5)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: asOf)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        printPhaseTable("Golden A — Get Stronger, 52 weeks", phases: proposal.phases)

        let types = proposal.phases.map(\.type)
        XCTAssertTrue(types.contains(.muscleGain), "must contain a development phase — this is the entire point of the fix")
        XCTAssertTrue(types.contains(.strength), "must contain direct-strength phases")
        XCTAssertTrue(types.contains(.maintenance), "must contain a real recovery-role phase")
        XCTAssertGreaterThan(Set(types).count, 2, "requirement 1: no longer just 2 distinct phase types")

        // Never the old exact 2-type alternation pattern.
        let oldLoopShape = Array(repeating: [PhaseType.strength, .strength, .maintenance], count: 4).flatMap { $0 }
        XCTAssertNotEqual(Array(types.prefix(oldLoopShape.count)), Array(oldLoopShape.prefix(types.count)))

        // Every phase has an explicit, real reason.
        for phase in proposal.phases {
            XCTAssertFalse(phase.reasonCodes.isEmpty, "\(phase.type) phase must carry an explicit reason")
        }
        let developmentPhase = try XCTUnwrap(proposal.phases.first { $0.type == .muscleGain })
        XCTAssertTrue(developmentPhase.reasonCodes.contains(.developmentPhaseSupportsPrimaryGoal))
        let recoveryPhase = try XCTUnwrap(proposal.phases.first { $0.type == .maintenance })
        XCTAssertTrue(recoveryPhase.reasonCodes.contains(.recoveryPhaseInserted), "requirement 7: recovery occurs for an explicit policy reason")

        // Never Powerlifting-competition behavior for generic Get Stronger (requirement 13).
        for phase in proposal.phases where phase.type == .strength {
            // strengthFocusedMix() only ever resolves to canonical General
            // Strength content; no competition/peaking mix exists to select.
            XCTAssertEqual(phase.priorityRule, .strength)
        }

        // LTP-DURATION-1 (Completion Pass): every Strength-typed phase's
        // PLANNED duration must now equal Family D/E's own real executable
        // mesocycle length (5 weeks) — not the generic 8-week
        // `PhaseDurationDefaults` estimate, which the prior pass's own
        // dogfood proved does not reflect reality (D/E has no
        // within-phase succession, so the phase is genuinely
        // phase-terminal at week 5 regardless of what an 8-week estimate
        // implies). This is a disclosed correction of this same test's
        // own prior (accepted-in-principle, now superseded) assumption.
        for phase in proposal.phases where phase.type == .strength {
            let weeks = Int((phase.startDate.distance(to: phase.endDate ?? phase.startDate) / (7 * 24 * 3600)).rounded())
            XCTAssertEqual(weeks, PowerliftingProgramGenerator.mesocycleLengthWeeks, "a Direct Strength phase must be planned for its real executable capacity, never a knowing overestimate")
        }
        // Development phases keep the existing, uncapped Hypertrophy
        // estimate — Hypertrophy's own real succession mechanism
        // (StartNextHypertrophyMesocycleUseCase) justifies NOT capping
        // this phase type the way Strength now is (requirement C).
        for phase in proposal.phases where phase.type == .muscleGain {
            let weeks = Int((phase.startDate.distance(to: phase.endDate ?? phase.startDate) / (7 * 24 * 3600)).rounded())
            XCTAssertLessThanOrEqual(weeks, 12, "must never exceed the existing muscleGain planning estimate")
        }

        // Never mutates Goal.primaryType (requirement 3).
        XCTAssertEqual(goal.primaryType, .generalStrength)
    }

    // MARK: - Golden B: Build Muscle, ~52 weeks, no objective

    func testGoldenB_BuildMuscleTwelveMonthsProducesRealStrategicVariety() throws {
        let asOf = date(2026, 1, 5)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: date(2027, 1, 4), createdAt: asOf)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        printPhaseTable("Golden B — Build Muscle, 52 weeks", phases: proposal.phases)

        let types = proposal.phases.map(\.type)
        XCTAssertTrue(types.contains(.muscleGain))
        XCTAssertTrue(types.contains(.maintenance))
        // Recovery must appear with a real reason, not merely because a
        // counter reached 2 — requirement 2/7.
        let recoveryPhases = proposal.phases.filter { $0.type == .maintenance }
        XCTAssertFalse(recoveryPhases.isEmpty)
        for phase in recoveryPhases {
            XCTAssertTrue(phase.reasonCodes.contains(.recoveryPhaseInserted))
        }
        // Directive's own explicit allowance: Build Muscle may legitimately
        // repeat .muscleGain more than Get Stronger repeats .strength — the
        // requirement is only that recovery isn't a counter-hack. Confirmed
        // above. Never invents a Strength phase for symmetry alone.
        XCTAssertFalse(types.contains(.strength), "must not invent a Strength phase for Build Muscle merely for symmetry with Get Stronger")
        XCTAssertEqual(goal.primaryType, .muscleGain)
    }

    // MARK: - Requirement 4: a supporting phase can differ from primary Goal type

    func testSupportingPhaseCanDifferFromPrimaryGoalType() throws {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: date(2026, 1, 5))
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: date(2026, 1, 5))
        let primaryPhaseType = PhaseType.strength
        let differentTypePhase = try XCTUnwrap(proposal.phases.first { $0.type != primaryPhaseType && $0.type != .maintenance })
        XCTAssertEqual(differentTypePhase.type, .muscleGain)
        XCTAssertEqual(goal.primaryType, .generalStrength, "the athlete's Goal never changes just because a supporting phase uses a different type")
    }

    // MARK: - Requirement 5: Direct Strength phase resolves to Strength D/E

    func testDirectStrengthPhaseResolvesToStrengthSourceContentFamilyDOrE() throws {
        let asOf = date(2026, 1, 5)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let strengthPhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .strength })

        let candidates = LongTermPlanner.proposeTrainingMix(phase: strengthPhase, goal: goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })
        let component = try XCTUnwrap(recommended.mix.orderedComponents.first)
        XCTAssertEqual(component.programmingSystem, .powerlifting)
        XCTAssertEqual(component.strengthContentSelector, .sourceBackedGeneralStrength, "must resolve via the canonical General Strength content selector, never plain Powerlifting")

        let profile = PerformanceProfile()
        context.insert(profile)
        let (programCandidates, gaps) = LongTermPlanner.proposeProgram(
            component: component, profile: profile, availability: UserAvailability(trainingDaysPerWeek: 4), context: context
        )
        XCTAssertTrue(gaps.isEmpty)
        let families = Set(programCandidates.compactMap { $0.programDefinition.powerliftingConfiguration?.family })
        XCTAssertEqual(families, [.d, .e], "must resolve to exactly Family D/E, never Family B/C")
        for candidate in programCandidates {
            XCTAssertFalse(candidate.programDefinition.name.contains("Powerlifting"), "athlete-facing content must never say Powerlifting")
        }
    }

    // MARK: - Requirement 6: Build Muscle primary phase resolves to Hypertrophy

    func testBuildMusclePrimaryPhaseResolvesToHypertrophySourceContent() throws {
        let asOf = date(2026, 1, 5)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: date(2027, 1, 4), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let muscleGainPhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .muscleGain })

        let candidates = LongTermPlanner.proposeTrainingMix(phase: muscleGainPhase, goal: goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })
        let component = try XCTUnwrap(recommended.mix.orderedComponents.first)
        XCTAssertEqual(component.programmingSystem, .hypertrophy)
    }

    // MARK: - Requirement 8: determinism

    func testSameInputsProduceSameSequenceDeterministically() {
        let asOf = date(2026, 1, 5)
        let goal1 = Goal(ownerUserID: UUID(), primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: asOf)
        let goal2 = Goal(ownerUserID: UUID(), primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: asOf)
        let proposal1 = LongTermPlanner.proposeStrategicPlan(goal: goal1, asOf: asOf)
        let proposal2 = LongTermPlanner.proposeStrategicPlan(goal: goal2, asOf: asOf)
        XCTAssertEqual(proposal1.phases.map(\.type), proposal2.phases.map(\.type))
        XCTAssertEqual(proposal1.phases.map(\.startDate), proposal2.phases.map(\.startDate))
        XCTAssertEqual(proposal1.phases.map(\.endDate), proposal2.phases.map(\.endDate))
        XCTAssertEqual(proposal1.phases.map(\.reasonCodes), proposal2.phases.map(\.reasonCodes))
    }

    // MARK: - Golden F / Requirement 9: short horizon truncates safely

    func testGoldenF_ShortHorizonDegradesGracefully() {
        let asOf = date(2026, 1, 5)
        // Shorter than even one Strength phase's own minimum (4 weeks).
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2026, 1, 26), createdAt: asOf)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .infeasible, "too short for even one minimum-duration phase — must not force every phase type in")
        XCTAssertTrue(proposal.phases.isEmpty)
    }

    // MARK: - Golden E: horizon boundary cuts through a phase's normal duration

    func testGoldenE_HorizonBoundaryTruncatesCleanlyNoInventedWeeks() throws {
        let asOf = date(2026, 1, 5)
        // ~10 weeks: enough for the Development phase (~12wk typical, but
        // clamped) plus a partial remainder, never a full 3rd/4th phase.
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2026, 3, 16), createdAt: asOf)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        printPhaseTable("Golden E — Horizon boundary", phases: proposal.phases)
        let lastPhase = try XCTUnwrap(proposal.phases.last)
        XCTAssertEqual(lastPhase.endDate, goal.targetDate, "no phase may extend past the target date")
        for phase in proposal.phases {
            XCTAssertLessThanOrEqual(phase.endDate ?? goal.targetDate!, goal.targetDate!, "no phase past target date")
        }
    }

    // MARK: - Golden G: repeated cycle — 2+ full development cycles

    func testGoldenG_RepeatedCycleStaysCoherentAfterFirstRecovery() throws {
        let asOf = date(2026, 1, 5)
        // ~2 years — enough for at least 2 full 4-position Get Stronger cycles.
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2028, 1, 3), createdAt: asOf)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        printPhaseTable("Golden G — Repeated cycle, ~2 years", phases: proposal.phases)

        let recoveryIndices = proposal.phases.enumerated().filter { $0.element.type == .maintenance }.map(\.offset)
        XCTAssertGreaterThanOrEqual(recoveryIndices.count, 2, "must reach at least 2 full cycles, each ending in a real recovery phase")
        // After the FIRST recovery phase, the cycle must repeat coherently
        // (Development -> Strength -> Strength -> Recovery again), never
        // fall back to the old mechanical 2-type loop.
        if let first = recoveryIndices.first, proposal.phases.indices.contains(first + 1) {
            let phaseAfterFirstRecovery = proposal.phases[first + 1]
            XCTAssertEqual(phaseAfterFirstRecovery.type, .muscleGain, "the cycle restarts with Development, exactly like the first cycle")
        }
    }

    // MARK: - Golden C: Build Muscle + real 5K dated objective

    func testGoldenC_BuildMusclePlusFiveKObjectiveReconciliation() throws {
        let asOf = date(2026, 1, 5)
        let raceDate = date(2026, 4, 13) // ~14 weeks out
        let goal = Goal(
            ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: date(2027, 1, 4),
            datedObjectives: [DatedObjective(kind: .runningEvent, date: raceDate, runningStartingState: .comfortably10K)],
            createdAt: asOf
        )
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        printPhaseTable("Golden C — Build Muscle + 5K objective", phases: proposal.phases)

        XCTAssertTrue(proposal.phases.contains { $0.type == .muscleGain }, "base Build Muscle strategy still runs before the objective")
        XCTAssertTrue(proposal.phases.contains { $0.type == .transition }, "a real transition phase before the event")
        let eventPhase = try XCTUnwrap(proposal.phases.first { $0.type == .enduranceEvent })
        XCTAssertEqual(eventPhase.endDate, raceDate)
        XCTAssertTrue(proposal.phases.last?.type == .muscleGain || proposal.phases.last?.type == .maintenance, "returns toward Build Muscle after the event")
        XCTAssertEqual(goal.primaryType, .muscleGain, "Goal never mutates because of a dated objective")
    }

    // MARK: - Golden D: Get Stronger + a currently supported dated objective

    func testGoldenD_GetStrongerPlusTemporaryObjective() throws {
        let asOf = date(2026, 1, 5)
        let raceDate = date(2026, 5, 4)
        let goal = Goal(
            ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4),
            datedObjectives: [DatedObjective(kind: .runningEvent, date: raceDate, runningStartingState: .occasionalShorterDistances)],
            createdAt: asOf
        )
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        printPhaseTable("Golden D — Get Stronger + temporary objective", phases: proposal.phases)

        XCTAssertTrue(proposal.phases.contains { $0.type == .strength || $0.type == .muscleGain }, "primary strength-goal development persists before the objective")
        XCTAssertTrue(proposal.phases.contains { $0.type == .enduranceEvent })
        // requirement 11: post-objective planning returns toward primary Goal.
        let eventIndex = try XCTUnwrap(proposal.phases.firstIndex { $0.type == .enduranceEvent })
        if proposal.phases.indices.contains(eventIndex + 1) {
            let after = proposal.phases[(eventIndex + 1)...]
            XCTAssertTrue(after.contains { $0.type == .strength || $0.type == .muscleGain || $0.type == .maintenance }, "returns to strength-goal development after the event")
        }
        XCTAssertEqual(goal.primaryType, .generalStrength)
    }

    // MARK: - Requirement 12: exact selected TrainingMix stays authoritative

    func testExactSelectedTrainingMixStaysAuthoritativeUntilAcceptedRevision() throws {
        let asOf = date(2026, 1, 5)
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .muscleGain, targetDate: date(2027, 1, 4), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        let phase = try XCTUnwrap(plan.orderedPhases.first)

        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)
        let variedMix = try XCTUnwrap(candidates.first { $0.mix.name == "Strength Plus Variety" })
        variedMix.mix.kind = .selected
        context.insert(variedMix.mix)
        phase.addTrainingMix(variedMix.mix)
        try context.save()

        // Re-deriving strategic policy / re-proposing a plan must never
        // silently overwrite the athlete's own selected mix.
        _ = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(phase.selectedTrainingMix?.id, variedMix.mix.id, "the exact selected mix is untouched by re-proposing a strategic plan")
        XCTAssertEqual(phase.selectedTrainingMix?.name, "Strength Plus Variety")
    }

    // MARK: - Requirement 14: source program duration unchanged

    func testSourceProgramDurationRemainsUnchangedByThisCheckpoint() throws {
        let strengthD = try PowerliftingProgramGenerator.generate(
            configuration: PowerliftingProgramConfiguration(family: .d, dayCount: 4),
            provenance: .constructed(reason: "test"), context: context
        )
        XCTAssertEqual(strengthD.lengthWeeks, 5, "Family D's own real mesocycle length must be unchanged")

        let hypertrophy = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 5, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test"), context: context
        )
        XCTAssertEqual(hypertrophy.lengthWeeks, 5, "basicHypertrophy's own real mesocycle length must be unchanged")
    }

    // MARK: - Final Duration Fix: duration derived from the ACTUAL resolved mix, never PhaseType alone

    /// Requirements A/B: `ExecutablePhaseDurationResolver` (not
    /// `StrategicPeriodizationPolicy`, which no longer knows about any
    /// concrete engine at all) is the sole place this decision lives now.
    /// Proven directly against the two REAL candidate mixes
    /// `candidateMixTemplates(.strength)` actually returns — never a
    /// synthetic fixture — so this test breaks honestly if either
    /// candidate's real shape ever changes.
    func testExecutablePhaseDurationResolverCapsFamilyDEButNotHypertrophyAlternate() throws {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: date(2026, 1, 5))
        let phase = TrainingPhase(type: .strength, startDate: date(2026, 1, 5), priorityRule: .strength, status: .planned)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        let strengthTraining = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Strength Training" })
        XCTAssertEqual(
            ExecutablePhaseDurationResolver.executablePlanningDuration(for: strengthTraining.mix),
            .fixed(weeks: PowerliftingProgramGenerator.mesocycleLengthWeeks),
            "requirement A: the real Family D/E mix must be capped to its own real executable mesocycle length"
        )

        let variedAlternative = try XCTUnwrap(candidates.first { $0.mix.name == "Strength Plus Variety" })
        XCTAssertNil(
            ExecutablePhaseDurationResolver.executablePlanningDuration(for: variedAlternative.mix),
            "requirement B: the real Hypertrophy-engine alternate must NOT be capped — Hypertrophy's own real succession mechanism justifies the existing, longer estimate"
        )
    }

    /// Requirement J: `StrategicPeriodizationPolicy` must remain
    /// completely independent of any concrete program/engine detail —
    /// duration/engine knowledge lives only in
    /// `ExecutablePhaseDurationResolver`. A direct source-text check
    /// (not merely "the tests still pass") — this file breaks the moment
    /// a future edit reintroduces a concrete-engine reference into the
    /// policy file's own CODE. Doc comments are deliberately excluded from
    /// the scan (this file's own doc comments legitimately NAME the
    /// forbidden types in prose, explaining exactly why it doesn't depend
    /// on them — a real code reference, not a comment mentioning one, is
    /// what this test actually guards against).
    func testStrategicPeriodizationPolicyHasNoConcreteProgramEngineDependency() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("TrainingOS/Application/UseCases/StrategicPeriodizationPolicy.swift")
        let fullSource = try String(contentsOf: url, encoding: .utf8)
        let codeOnly = fullSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return (trimmed.hasPrefix("///") || trimmed.hasPrefix("//")) ? "" : String(line)
            }
            .joined(separator: "\n")
        for forbidden in ["PowerliftingProgramGenerator", "HypertrophyProgramGenerator", "StrengthSourceContentLibrary", "ExecutablePhaseDurationResolver"] {
            XCTAssertFalse(codeOnly.contains(forbidden), "StrategicPeriodizationPolicy's own CODE (not doc comments) must never reference \(forbidden) — engine/duration-capability knowledge belongs only in ExecutablePhaseDurationResolver")
        }
    }

    /// Requirement D: LTP-DURATION-1 must not have touched the Get
    /// Stronger cycle's own TYPE sequence — only Strength's DURATION
    /// changed, never which types appear or in what order.
    func testGetStrongerCycleShapeUnchangedByTheDurationFix() {
        let intents = (0..<4).map { StrategicPeriodizationPolicy.nextPhaseIntent(primaryType: .strength, cyclePosition: $0) }
        XCTAssertEqual(intents.map(\.type), [.muscleGain, .strength, .strength, .maintenance])
        XCTAssertEqual(intents[0].reasonCodes, [.developmentPhaseSupportsPrimaryGoal])
        XCTAssertEqual(intents[3].reasonCodes, [.recoveryPhaseInserted])
    }

    // MARK: - Requirement 15 + §22 dogfood: source mesocycle lifecycle across a strategic phase boundary

    func testDogfood_GetStrongerCrossesRealFamilyDMesocycleEndAndStrategicPhaseBoundary() throws {
        let asOf = date(2026, 1, 5) // a real Monday
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: asOf)
        context.insert(goal)
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        let plan = try AcceptStrategicPlanUseCase.accept(proposal, context: context, decidedAt: asOf)
        XCTAssertEqual(plan.orderedPhases.first?.type, .muscleGain)
        let strengthPhase = try XCTUnwrap(plan.orderedPhases.first { $0.type == .strength })

        let candidates = LongTermPlanner.proposeTrainingMix(phase: strengthPhase, goal: goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })
        let performanceProfile = PerformanceProfile()
        context.insert(performanceProfile)
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            trainingEnvironment: TrainingEnvironmentTestSupport.full(context: context)
        )
        let availability = UserAvailability(trainingDaysPerWeek: 4, allowsDoubleSessions: false, maxSessionsPerDay: 1)

        try StartPhaseUseCase.start(
            phase: strengthPhase, mix: recommended.mix, asOf: strengthPhase.startDate, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability,
            materializationContext: materializationContext, context: context
        )
        try CalibrationTestSupport.completeAnyPendingCalibrationAndMaterialize(
            phase: strengthPhase, performanceProfile: performanceProfile, availability: availability,
            materializationContext: materializationContext, asOf: strengthPhase.startDate, context: context
        )
        let strengthInstance = try XCTUnwrap(strengthPhase.primaryInstance)
        let originalDefinitionID = strengthInstance.programDefinition?.id
        XCTAssertEqual(strengthInstance.programDefinition?.lengthWeeks, 5, "Family D/E's own real 5-week mesocycle, unchanged")
        XCTAssertEqual(strengthInstance.programDefinition?.powerliftingConfiguration?.family == .d || strengthInstance.programDefinition?.powerliftingConfiguration?.family == .e, true)

        // Roll every real tactical week (0..4 = 5 weeks) forward — the
        // source mesocycle's own exact, unmodified 5-week length. Each
        // week's real sessions are actually completed (real logged
        // results through the real production result/completion path) so
        // `TacticalWeekCompletion.isInstanceExhausted` can honestly become
        // true — never asserted without real completed history behind it.
        var rollDate = strengthPhase.startDate
        let mix = try XCTUnwrap(strengthPhase.selectedTrainingMix ?? strengthPhase.recommendedTrainingMix)
        try completeSessions(in: strengthInstance, weekIndex: 0, performanceProfile: performanceProfile, asOf: rollDate)
        for weekIndex in 1...4 {
            rollDate = Calendar.current.date(byAdding: .day, value: 7, to: rollDate) ?? rollDate
            _ = try RollTacticalWindowUseCase.rollForward(
                mix: mix, asOf: rollDate, ownerUserID: ownerUserID,
                performanceProfile: performanceProfile, availability: availability,
                materializationContext: materializationContext, context: context
            )
            try completeSessions(in: strengthInstance, weekIndex: weekIndex, performanceProfile: performanceProfile, asOf: rollDate)
        }
        XCTAssertEqual(strengthInstance.programDefinition?.id, originalDefinitionID, "no source week duplicated/fabricated — same ProgramDefinition throughout its own real 5 weeks")
        XCTAssertEqual(strengthInstance.programDefinition?.orderedWeeks.count, 5, "still exactly 5 real source weeks")

        // Now the instance is tactically exhausted (week index 4, the
        // deload week, already materialized by StartPhase+4 rolls) and —
        // because Family D/E has no mesocycle-succession mechanism at all
        // (hasNextHypertrophyMesocycle reads a nil hypertrophyConfiguration
        // for a Powerlifting-engine definition) — genuinely phase-terminal.
        XCTAssertTrue(TacticalWeekCompletion.isInstanceExhausted(for: strengthInstance))
        XCTAssertTrue(TrainingPhaseCompletion.isPhaseTerminal(strengthPhase), "the strategic phase itself is genuinely ready to transition — real tactical exhaustion, never a fabricated date-based guess")

        // LTP-DURATION-1 (Completion Pass): the PLANNED end date must now
        // match the REAL point of tactical exhaustion — no known
        // deterministic gap between planned (was 8wk) and actual (5wk)
        // remains. `rollDate` is the start of the last completed real
        // week (week index 4); tactical exhaustion is reached exactly 7
        // days later — this must equal the phase's own planned `endDate`.
        let actualExhaustionDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 7, to: rollDate))
        XCTAssertEqual(strengthPhase.endDate, actualExhaustionDate, "planned Strength phase end must equal the real executable exhaustion point, never a knowing 3-week overestimate")

        // The NEXT strategic phase (second Direct Strength block per the
        // Get Stronger cycle) gets its own correct recommendation and a
        // brand-new ProgramInstance — never a stretch of the same one.
        let nextPhase = try XCTUnwrap(strengthPhase.plan?.orderedPhases.first { $0.startDate > strengthPhase.startDate })
        XCTAssertEqual(nextPhase.type, .strength, "the Get Stronger cycle's second position is another Direct Strength block")
        // The second Direct Strength phase is ALSO planned for the real
        // executable capacity (5wk), not the old 8wk estimate — the fix
        // applies uniformly, not just to the first occurrence.
        let nextPlannedWeeks = try XCTUnwrap(nextPhase.endDate).timeIntervalSince(nextPhase.startDate) / (7 * 24 * 3600)
        XCTAssertEqual(Int(nextPlannedWeeks.rounded()), PowerliftingProgramGenerator.mesocycleLengthWeeks)
        let nextCandidates = LongTermPlanner.proposeTrainingMix(phase: nextPhase, goal: goal)
        let nextRecommended = try XCTUnwrap(nextCandidates.first { $0.roles.contains(.recommended) })
        XCTAssertEqual(nextRecommended.mix.orderedComponents.first?.strengthContentSelector, .sourceBackedGeneralStrength)

        try context.save()
        let transitionResult = try TransitionPhaseUseCase.transition(
            from: strengthPhase, toNextPhaseWithMix: nextRecommended.mix, asOf: rollDate, ownerUserID: ownerUserID,
            performanceProfile: performanceProfile, availability: availability,
            materializationContext: materializationContext, context: context
        )
        XCTAssertEqual(transitionResult.completedPhase.id, strengthPhase.id)
        XCTAssertEqual(strengthPhase.status, .completed, "historical phase remains intact, marked completed, never deleted")
        XCTAssertEqual(strengthInstance.status, .completed)
        XCTAssertEqual(strengthInstance.programDefinition?.id, originalDefinitionID, "the historical ProgramInstance is never mutated by the transition (requirement 15)")
        XCTAssertEqual(transitionResult.nextPhase.id, nextPhase.id)
        XCTAssertEqual(nextPhase.status, .active)
        let nextInstance = try XCTUnwrap(nextPhase.primaryInstance)
        XCTAssertNotEqual(nextInstance.id, strengthInstance.id, "an explicit NEW ProgramInstance for the new phase, never a same-instance stretch")
    }

    // MARK: - Final Duration Fix: same PhaseType, different resolved mix, different planned duration

    /// Superseded note, kept for history: an earlier pass left the
    /// "PhaseType.strength -> 5 weeks" cap unconditional, arguing the
    /// resulting underestimate for a preference-promoted Hypertrophy
    /// alternate was safety-proven-harmless (never causes an incorrect
    /// early transition, `TrainingPhaseCompletion.isPhaseTerminal` being
    /// date-independent). Independent review correctly rejected that as
    /// insufficient: `PLAN = DIRECTION` — a strategic date TrainingOS
    /// already knows is wrong at planning time is knowingly incorrect
    /// product information, regardless of whether it also happens to be
    /// safe against a forced-early-transition failure mode. `fillForwardPhases`
    /// now threads a real `Goal` through and previews the ACTUAL
    /// recommended `TrainingMix` for each phase before deciding its
    /// duration (see `LongTermPlanner.fillForwardPhases`) — the test below
    /// proves the alternate candidate's phase is now genuinely planned at
    /// its own correct (uncapped) duration through the real production
    /// path, not merely proven "safe to be wrong."

    func testStrengthPhaseCandidateSetKnownEngineProfilesFutureCapabilityTripwire() throws {
        let goal = Goal(ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4), createdAt: date(2026, 1, 5))
        context.insert(goal)
        let phase = TrainingPhase(type: .strength, startDate: date(2026, 1, 5), priorityRule: .strength, status: .planned)
        context.insert(phase)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: phase, goal: goal)

        // If this count ever changes, a human must re-examine whether the
        // new candidate's executable-capacity profile still matches this
        // test's own assumptions below.
        XCTAssertEqual(candidates.count, 2, "a third .strength candidate would require re-evaluating the duration policy's default-candidate assumption")

        let strengthTraining = try XCTUnwrap(candidates.first { $0.mix.name == "Focused Strength Training" })
        XCTAssertEqual(strengthTraining.mix.orderedComponents.first?.programmingSystem, .powerlifting)
        XCTAssertEqual(strengthTraining.mix.orderedComponents.first?.strengthContentSelector, .sourceBackedGeneralStrength, "Family D/E — the profile executablePlanningDuration's 5wk cap actually describes")

        let variedAlternative = try XCTUnwrap(candidates.first { $0.mix.name == "Strength Plus Variety" })
        XCTAssertEqual(variedAlternative.mix.orderedComponents.first?.programmingSystem, .hypertrophy, "the known alternate candidate — Hypertrophy engine, real succession, deliberately NOT capped by executablePlanningDuration")
    }

    /// Golden Alternate (§11): a real `GoalPreferences` input strong
    /// enough to genuinely promote `muscleGainVariedMix()` to
    /// `.recommended` for a `.strength`-typed phase — proving, through the
    /// REAL `fillForwardPhases` production path (not a hand-built phase),
    /// that the identical `PhaseType` now legitimately produces a
    /// DIFFERENT planned duration depending on which mix actually gets
    /// recommended (requirement C).
    func testGoldenAlternate_PreferencePromotedHypertrophyCandidateForStrengthPhaseIsNotCappedTo5Weeks() throws {
        let asOf = date(2026, 1, 5)
        let preferences = GoalPreferences(
            preferredModalities: [ModalityPreference(system: .functionalFitness), ModalityPreference(system: .steadyState)]
        )
        let goal = Goal(
            ownerUserID: ownerUserID, primaryType: .generalStrength, targetDate: date(2027, 1, 4),
            preferences: preferences, createdAt: asOf
        )
        let proposal = LongTermPlanner.proposeStrategicPlan(goal: goal, asOf: asOf)
        XCTAssertEqual(proposal.feasibility, .feasible)
        printPhaseTable("Golden Alternate — Get Stronger, FF/aerobic preference", phases: proposal.phases)

        let strengthPhase = try XCTUnwrap(proposal.phases.first { $0.type == .strength })
        // Sanity check the promotion genuinely happened for this phase —
        // confirms this test exercises the real, non-default branch, not
        // accidentally the canonical one.
        let previewPhase = TrainingPhase(type: .strength, startDate: strengthPhase.startDate, priorityRule: .strength, status: .planned)
        let candidates = LongTermPlanner.proposeTrainingMix(phase: previewPhase, goal: goal)
        let recommended = try XCTUnwrap(candidates.first { $0.roles.contains(.recommended) })
        XCTAssertEqual(recommended.mix.name, "Strength Plus Variety", "this preference input must genuinely promote the Hypertrophy-engine alternate")
        XCTAssertEqual(recommended.mix.orderedComponents.first?.programmingSystem, .hypertrophy)

        let weeks = Int((strengthPhase.startDate.distance(to: strengthPhase.endDate ?? strengthPhase.startDate) / (7 * 24 * 3600)).rounded())
        print("PhaseType: \(strengthPhase.type.rawValue) | recommended: \(recommended.mix.name) | engine: \(recommended.mix.orderedComponents.first?.programmingSystem?.rawValue ?? "nil") | planned: \(weeks)wk | reason: \(strengthPhase.reasonCodes.map(\.rawValue))")
        XCTAssertNotEqual(weeks, PowerliftingProgramGenerator.mesocycleLengthWeeks, "requirement B: must NOT be capped to Family D/E's 5-week figure — this phase's real recommended content is Hypertrophy-engine, with real succession")
        XCTAssertEqual(weeks, PhaseDurationDefaults.range(for: .strength).planningWeeks, "uses the ordinary, uncapped `.strength` estimate — Hypertrophy succession can legitimately sustain it")

        XCTAssertEqual(goal.primaryType, .generalStrength, "Goal never mutates because of a preference-promoted alternate candidate")
    }
}
