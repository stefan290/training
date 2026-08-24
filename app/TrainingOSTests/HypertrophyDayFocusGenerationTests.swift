import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10B: proves the day-focus-driven 3-Day Full Body Hypertrophy
/// path — `HypertrophyProgramGenerator.generateDayFocusDriven` — end to
/// end. See `STAGE10B_IMPLEMENTATION_PLAN.md` for the approved design
/// and `STAGE10B_IMPLEMENTATION_REPORT.md` for the manual acceptance
/// record this automated suite backs.
@MainActor
final class HypertrophyDayFocusGenerationTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func generateReferenceConfig(phaseType: HypertrophyPhaseType = .basicHypertrophy) throws -> ProgramDefinition {
        try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: phaseType),
            provenance: .constructed(reason: "test fixture"), context: context
        )
    }

    // MARK: - Deterministic Day A/B/C construction & distinct emphasis

    func testDayFocusRotationHasThreeDistinctDaysMatchingApprovedDefinitions() {
        let rotation = HypertrophyProgramGenerator.threeDayFullBodyRotation
        XCTAssertEqual(rotation.map(\.name), ["Day A", "Day B", "Day C"])

        XCTAssertEqual(rotation[0].primary, [.quadriceps, .chest, .shoulders])
        XCTAssertEqual(rotation[0].secondary, [.back, .hamstrings, .glutes])
        XCTAssertEqual(rotation[0].accessory, [.biceps, .triceps, .calves], "Day A is one of the 2 approved calf-accessory days")

        XCTAssertEqual(rotation[1].primary, [.back, .hamstrings, .glutes])
        XCTAssertEqual(rotation[1].secondary, [.chest, .quadriceps, .shoulders])
        XCTAssertEqual(rotation[1].accessory, [.biceps, .triceps], "Day B deliberately has no calf work — see the placement policy doc comment")

        XCTAssertEqual(rotation[2].primary, [.quadriceps, .hamstrings, .glutes, .chest, .back, .shoulders])
        XCTAssertEqual(rotation[2].secondary, [], "Day C deliberately carries no secondary tier — never forced for symmetry")
        XCTAssertEqual(rotation[2].accessory, [.biceps, .triceps, .calves], "Day C is the other approved calf-accessory day")
    }

    func testGeneratedProgramProducesExactlyThreeDistinctTemplateSessions() throws {
        let definition = try generateReferenceConfig()
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Day A", "Day B", "Day C"])

        // Distinctness must be judged on (role, targets) together, not
        // targets alone — Day A and Day B legitimately share the exact
        // same set of muscle-group groupings (Hinge Pattern, Horizontal
        // Push, Quadriceps, Back, Biceps, Triceps), just with opposite
        // primary/secondary emphasis, which the raw targets-only view
        // cannot see but the role assignment can.
        let slotSignatures = definition.orderedTemplateSessions.map { session -> Set<[String]> in
            Set(session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).compactMap { template -> [String]? in
                guard let role = template.slotRole, let targets = template.exerciseSlot?.allowedTargets else { return nil }
                return [role.rawValue] + targets.map(\.rawValue)
            })
        }
        XCTAssertNotEqual(slotSignatures[0], slotSignatures[1], "Day A and Day B must be genuinely distinct in role emphasis even where raw muscle-group groupings coincide")
        XCTAssertNotEqual(slotSignatures[1], slotSignatures[2], "Day B and Day C must be genuinely distinct")
        XCTAssertNotEqual(slotSignatures[0], slotSignatures[2], "Day A and Day C must be genuinely distinct")
    }

    // MARK: - Variable slot construction (count is an output, never hardcoded)

    func testGroupMuscleGroupsClaimsKnownCompoundPatternsBeforeFallingBackToSoloSlots() {
        // Day A's raw tiers, traced by hand against the approved grouping
        // priority (Squat Pattern, then Horizontal Push, then Hinge
        // Pattern, then whatever remains solo).
        XCTAssertEqual(
            HypertrophyProgramGenerator.groupMuscleGroups([.quadriceps, .chest, .shoulders]),
            [[.chest, .shoulders], [.quadriceps]],
            "no glutes present alongside quadriceps in this tier, so Squat Pattern cannot claim it — quadriceps stays solo"
        )
        XCTAssertEqual(
            HypertrophyProgramGenerator.groupMuscleGroups([.back, .hamstrings, .glutes]),
            [[.hamstrings, .glutes], [.back]]
        )
        XCTAssertEqual(
            HypertrophyProgramGenerator.groupMuscleGroups([.biceps, .triceps]),
            [[.biceps], [.triceps]],
            "biceps/triceps deliberately never group into one combined 'arms' slot"
        )
    }

    func testGroupMuscleGroupsPrefersSquatPatternWhenQuadricepsAndGlutesShareATier() {
        // Day C's broad primary tier — proves Squat Pattern claims
        // quadriceps+glutes before Hip-dominant leftovers fragment them.
        let grouped = HypertrophyProgramGenerator.groupMuscleGroups([.quadriceps, .hamstrings, .glutes, .chest, .back, .shoulders])
        XCTAssertEqual(grouped, [[.quadriceps, .glutes], [.chest, .shoulders], [.hamstrings], [.back]])
    }

    func testGroupMuscleGroupsOnEmptyTierProducesNoSlots() {
        XCTAssertEqual(HypertrophyProgramGenerator.groupMuscleGroups([]), [])
    }

    func testEachGeneratedDayProducesBetweenFiveAndSevenSlotsForThisReferenceConfiguration() throws {
        let definition = try generateReferenceConfig()
        for session in definition.orderedTemplateSessions {
            let count = session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).count
            XCTAssertTrue((5...7).contains(count), "\(session.name) produced \(count) slots — expected the 5-7 range for this reference config (an acceptance heuristic, never a hardcoded generator invariant)")
        }
    }

    // MARK: - SlotRole assignment & ordering

    func testEverySlotCarriesTheCorrectSlotRoleMatchingItsSourceTier() throws {
        let definition = try generateReferenceConfig()
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let templates = try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates

        let roles = templates.map(\.slotRole)
        XCTAssertTrue(roles.allSatisfy { $0 != nil }, "every Stage 10B slot must carry a SlotRole")
        // Day A: 2 primary (Horizontal Push, Quadriceps), 2 secondary
        // (Hinge Pattern, Back), 3 accessory (Biceps, Triceps, Calves —
        // Day A is one of the 2 calf-accessory days per the Blocker-1
        // placement policy) = 7.
        XCTAssertEqual(roles.filter { $0 == .primary }.count, 2)
        XCTAssertEqual(roles.filter { $0 == .secondary }.count, 2)
        XCTAssertEqual(roles.filter { $0 == .accessory }.count, 3)
    }

    func testSlotOrderingIsPrimaryThenSecondaryThenAccessoryNeverInterleaved() throws {
        let definition = try generateReferenceConfig()
        for session in definition.orderedTemplateSessions {
            let templates = try XCTUnwrap(session.orderedBlockTemplates.first).orderedPrescriptionTemplates
            let roleRank: [SlotRole: Int] = [.primary: 0, .secondary: 1, .accessory: 2]
            let ranks = templates.compactMap { $0.slotRole.flatMap { roleRank[$0] } }
            XCTAssertEqual(ranks, ranks.sorted(), "\(session.name)'s slots must never place an accessory before a primary/secondary slot")
        }
    }

    func testDayCHasNoSecondaryRoleSlotsSessionsNeedNotContainEveryRole() throws {
        let definition = try generateReferenceConfig()
        let dayC = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let roles = try XCTUnwrap(dayC.orderedBlockTemplates.first).orderedPrescriptionTemplates.map(\.slotRole)
        XCTAssertFalse(roles.contains(.secondary), "Day C's approved design has no secondary tier — must never be force-filled")
        XCTAssertTrue(roles.contains(.primary) && roles.contains(.accessory))
    }

    // MARK: - Weekly muscle-group coverage (9 groups; calves at the approved 2x policy)

    func testApprovedRotationSatisfiesTheExactNineGroupExposurePolicyIncludingCalvesAtTwoX() {
        let report = HypertrophyProgramGenerator.validateWeeklyCoverage(dayFocuses: HypertrophyProgramGenerator.threeDayFullBodyRotation)
        XCTAssertTrue(report.mismatches.isEmpty, "mismatches: \(report.mismatches)")
        XCTAssertTrue(report.duplicateDayNames.isEmpty)

        // Prove the exact intentional exposure map, not just "present at
        // least once" — 8 groups at 3x, calves deliberately at 2x.
        let expected: [MuscleGroup: Int] = [
            .chest: 3, .back: 3, .quadriceps: 3, .hamstrings: 3, .glutes: 3,
            .shoulders: 3, .biceps: 3, .triceps: 3, .calves: 2,
        ]
        for (group, expectedCount) in expected {
            XCTAssertEqual(report.exposureCountByGroup[group], expectedCount, "\(group) must be exposed exactly \(expectedCount)x/week")
        }
    }

    func testCalvesAppearOnlyOnDayAAndDayCNeverDayB() {
        let rotation = HypertrophyProgramGenerator.threeDayFullBodyRotation
        let dayA = try! XCTUnwrap(rotation.first { $0.name == "Day A" })
        let dayB = try! XCTUnwrap(rotation.first { $0.name == "Day B" })
        let dayC = try! XCTUnwrap(rotation.first { $0.name == "Day C" })
        XCTAssertTrue(dayA.accessory.contains(.calves))
        XCTAssertFalse(dayB.accessory.contains(.calves), "Day B (posterior-chain/hinge-primary) is deliberately the one day without calf work")
        XCTAssertTrue(dayC.accessory.contains(.calves))
    }

    func testCoverageValidationDetectsAMissingMuscleGroup() {
        // A deliberately broken day-focus table that never trains
        // triceps or quadriceps at all — proves the pure detection
        // function itself, independent of the (correct) production table.
        let broken = [
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "X", primary: [.chest], secondary: [], accessory: [.biceps]),
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "Y", primary: [.back], secondary: [], accessory: [.biceps]),
        ]
        let report = HypertrophyProgramGenerator.validateWeeklyCoverage(dayFocuses: broken)
        XCTAssertTrue(report.mismatches.contains { $0.group == .triceps && $0.actual == 0 })
        XCTAssertTrue(report.mismatches.contains { $0.group == .quadriceps && $0.actual == 0 })
    }

    func testCoverageValidationDetectsAnOverOrUnderExposedGroupEvenWhenItAppearsAtLeastOnce() {
        // Calves appearing on all 3 days (mathematically-symmetric, but
        // NOT the approved 2x policy) must still be reported as a
        // mismatch — proves the validator checks the actual policy, not
        // merely "present somewhere."
        let allThreeDaysCalves = [
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "X", primary: [.chest], secondary: [], accessory: [.biceps, .calves]),
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "Y", primary: [.back], secondary: [], accessory: [.biceps, .calves]),
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "Z", primary: [.quadriceps], secondary: [], accessory: [.biceps, .calves]),
        ]
        let report = HypertrophyProgramGenerator.validateWeeklyCoverage(dayFocuses: allThreeDaysCalves)
        XCTAssertTrue(report.mismatches.contains { $0.group == .calves && $0.expected == 2 && $0.actual == 3 })
    }

    func testCoverageValidationDetectsADuplicateDayFocus() {
        let duplicate = [
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "X", primary: [.chest], secondary: [], accessory: [.biceps]),
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "Y", primary: [.chest], secondary: [], accessory: [.biceps]),
        ]
        let report = HypertrophyProgramGenerator.validateWeeklyCoverage(dayFocuses: duplicate)
        XCTAssertEqual(report.duplicateDayNames, ["X", "Y"])
    }

    /// D-10B-3: generation must hard-fail, never silently persist, if its
    /// own structural coverage check fails. The approved production table
    /// is correct by construction (proven above) so this exercises the
    /// typed error path directly rather than trying to force the real
    /// generator to fail.
    func testHypertrophyGenerationErrorIsTheTypedFailureSurfacedForBrokenCoverage() {
        let mismatch = MuscleGroupExposureMismatch(group: .triceps, expected: 3, actual: 0)
        let missing: HypertrophyGenerationError = .weeklyExposurePolicyViolated(mismatches: [mismatch])
        let duplicate: HypertrophyGenerationError = .duplicateDayFocus(dayNames: ["X", "Y"])
        XCTAssertNotEqual(missing, duplicate)
        XCTAssertEqual(missing, .weeklyExposurePolicyViolated(mismatches: [mismatch]))
    }

    func testGenerateNeverThrowsForTheApprovedReferenceConfiguration() {
        XCTAssertNoThrow(try generateReferenceConfig())
    }

    /// `LongTermPlanner.proposeProgram` must never crash or propagate a
    /// generation failure — it converts it into a `CapabilityGap`
    /// (D-10B-3: "surface it through the existing generation/result/error
    /// architecture"), exactly like an uninstantiable-parameters gap.
    func testCapabilityGapReasonHasADistinctGenerationFailedCase() {
        XCTAssertNotEqual(CapabilityGapReason.generationFailed, .parametersNotInstantiable)
    }

    // MARK: - Numeric rule reuse (D-10B-4)

    /// Stage 10B.6: primary/secondary now share the SAME numeric shape
    /// (`.doubleProgression` load, identical RIR trajectory, autoregulated
    /// set count with the same baseline) — see
    /// `STAGE10B6_HYPERTROPHY_PRESCRIPTION_REDESIGN.md` §5/§8 for why no
    /// role-specific set-count split is invented. They differ only in rep
    /// range (5-10 vs. 6-12), which this test also confirms.
    func testPrimaryAndSecondarySlotsReuseIdenticalNumericRulesExceptRepRange() throws {
        let definition = try generateReferenceConfig()
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let templates = try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates
        let primary = try XCTUnwrap(templates.first { $0.slotRole == .primary })
        let secondary = try XCTUnwrap(templates.first { $0.slotRole == .secondary })

        XCTAssertEqual(primary.rules?.setCountRule, secondary.rules?.setCountRule)
        XCTAssertEqual(primary.rules?.loadRule, .doubleProgression)
        XCTAssertEqual(secondary.rules?.loadRule, .doubleProgression)

        let primarySchedule = try XCTUnwrap(primary.rules?.repGoalSchedule)
        let secondarySchedule = try XCTUnwrap(secondary.rules?.repGoalSchedule)
        XCTAssertEqual(primarySchedule.map(\.targetRir), secondarySchedule.map(\.targetRir), "same RIR trajectory")
        XCTAssertEqual(primarySchedule.map(\.reps), Array(repeating: 5, count: 4))
        XCTAssertEqual(primarySchedule.map(\.repRangeHigh), Array(repeating: 10, count: 4))
        XCTAssertEqual(secondarySchedule.map(\.reps), Array(repeating: 6, count: 4))
        XCTAssertEqual(secondarySchedule.map(\.repRangeHigh), Array(repeating: 12, count: 4))
    }

    /// Stage 10B.6: accessory slots have their own independent history
    /// (`.doubleProgression`, same as every other role) and a fixed,
    /// never-autoregulated set schedule at their own baseline (2).
    func testAccessorySlotsUseFixedSetScheduleWithIndependentDoubleProgressionLoad() throws {
        let definition = try generateReferenceConfig()
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let accessory = try XCTUnwrap(try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates.first { $0.slotRole == .accessory })

        XCTAssertEqual(accessory.rules?.setCountRule, .fixed(setsByWeek: [2, 2, 2, 2]))
        XCTAssertEqual(accessory.rules?.loadRule, .doubleProgression)
        let schedule = try XCTUnwrap(accessory.rules?.repGoalSchedule)
        XCTAssertEqual(schedule.map(\.reps), Array(repeating: 10, count: 4))
        XCTAssertEqual(schedule.map(\.repRangeHigh), Array(repeating: 20, count: 4))
        XCTAssertEqual(schedule.map(\.targetRir), Array(repeating: 2, count: 4), "flat RIR target, never progressed toward failure")
        XCTAssertNil(accessory.pairedSlot, "never autoregulated — nothing needs a rating source")
    }

    /// Stage 10B.6 fix (D-10B6-6): the fan-out flaw is gone — every
    /// primary/secondary slot rates ITSELF, so one slot's feedback can
    /// never drive a sibling's set count.
    func testAutoregulationRatingSourceIsSelfAttributedForEveryPrimaryAndSecondarySlot() throws {
        let definition = try generateReferenceConfig()
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let templates = try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates
        let primaryAndSecondary = templates.filter { $0.slotRole == .primary || $0.slotRole == .secondary }

        XCTAssertFalse(primaryAndSecondary.isEmpty)
        for template in primaryAndSecondary {
            XCTAssertEqual(template.pairedSlot?.id, template.id, "every primary/secondary slot must rate itself, never a shared canonical slot")
        }
        // No two distinct primary/secondary slots may share a pairedSlot.
        let pairedSlotIDs = primaryAndSecondary.compactMap { $0.pairedSlot?.id }
        XCTAssertEqual(Set(pairedSlotIDs).count, primaryAndSecondary.count, "no fan-out: every slot's rating source is distinct")
    }

    // MARK: - Content-based Heavy Quads/Glutes exception (D-10B-5)

    func testHeavyQuadsGlutesExceptionFiresOnlyForPrimaryQuadGluteSlotsUnderLegsSplit() {
        XCTAssertTrue(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.quadriceps, .glutes], split: .legs))
        XCTAssertTrue(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.glutes, .quadriceps], split: .legs), "order-independent")
        XCTAssertFalse(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .secondary, targets: [.quadriceps, .glutes], split: .legs), "never fires for a non-primary role")
        XCTAssertFalse(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.quadriceps, .glutes], split: .fullBody), "never fires outside .legs")
        XCTAssertFalse(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.quadriceps], split: .legs), "must match both targets, not quadriceps alone")
    }

    /// Stage 10B.6: the Heavy Quads/Glutes exception was a mechanism of
    /// `.rmBased` loading (a %RM week-1 factor) — Hypertrophy V2 doesn't
    /// use `.rmBased` at all, so the exception cannot apply to any
    /// day-focus-driven slot, full stop. This still proves Day C's own
    /// {quadriceps, glutes} Squat Pattern primary slot uses the normal
    /// V2 rule shape, not some special-cased variant.
    func testHeavyExceptionNeverFiresUnderStage10BsActualFullBodyReferenceConfig() throws {
        let definition = try generateReferenceConfig()
        let dayC = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let squatPatternSlot = try XCTUnwrap(
            try XCTUnwrap(dayC.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
                $0.slotRole == .primary && Set($0.exerciseSlot?.allowedTargets ?? []) == Set([.quadriceps, .glutes])
            }
        )
        XCTAssertEqual(squatPatternSlot.rules?.loadRule, .doubleProgression, "Hypertrophy V2 never uses .rmBased, so no %RM factor — Heavy or otherwise — applies here")
        XCTAssertEqual(squatPatternSlot.rules?.repGoalSchedule.map(\.reps), Array(repeating: 5, count: 4), "the normal primary rep range, same as every other primary slot")
    }

    // MARK: - Slot movement-intent (Blocker 2): Squat Pattern vs Hinge Pattern vs Horizontal Push

    func testSquatPatternAndHingePatternSlotsCarryDistinctMovementFunctionIntent() throws {
        let definition = try generateReferenceConfig()
        let dayC = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let templates = try XCTUnwrap(dayC.orderedBlockTemplates.first).orderedPrescriptionTemplates

        let squatSlot = try XCTUnwrap(templates.first { Set($0.exerciseSlot?.allowedTargets ?? []) == Set([.quadriceps, .glutes]) }?.exerciseSlot)
        XCTAssertEqual(squatSlot.allowedMovementFunctions, [.squatLoaded])

        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let hingeSlot = try XCTUnwrap(
            try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
                Set($0.exerciseSlot?.allowedTargets ?? []) == Set([.hamstrings, .glutes])
            }?.exerciseSlot
        )
        XCTAssertEqual(hingeSlot.allowedMovementFunctions, [.hingeLoaded])
        XCTAssertNotEqual(squatSlot.allowedMovementFunctions, hingeSlot.allowedMovementFunctions, "the two slots share the .glutes target but must NOT share movement intent")
    }

    func testHorizontalPushSlotCarriesPressLoadedIntent() throws {
        let definition = try generateReferenceConfig()
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let pushSlot = try XCTUnwrap(
            try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
                Set($0.exerciseSlot?.allowedTargets ?? []) == Set([.chest, .shoulders])
            }?.exerciseSlot
        )
        XCTAssertEqual(pushSlot.allowedMovementFunctions, [.pressLoaded])
    }

    func testSoloLeftoverSlotsCarryNoMovementFunctionConstraint() throws {
        // "Quadriceps"/"Hamstrings"/"Back" solo slots are already
        // unambiguous by target alone in this catalog (§ implementation
        // report) — constraining them would wrongly exclude legitimate
        // candidates like Leg Curl for a hamstrings-only slot.
        let definition = try generateReferenceConfig()
        let dayC = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let hamstringsSoloSlot = try XCTUnwrap(
            try XCTUnwrap(dayC.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
                $0.exerciseSlot?.allowedTargets == [.hamstrings]
            }?.exerciseSlot
        )
        XCTAssertEqual(hamstringsSoloSlot.allowedMovementFunctions, [])
    }

    /// The exact bug reported: a hinge-intent slot must never resolve to
    /// a squat-pattern exercise merely because both happen to target
    /// `.glutes`.
    func testHingeIntentSlotCannotResolveToFrontSquat() throws {
        let realCatalog = ExerciseCatalog.makeAndInsert(context: context)
        let candidates = [realCatalog.frontSquat, realCatalog.romanianDeadlift]

        let definition = try generateReferenceConfig()
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: candidates)

        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let hingeSlot = try XCTUnwrap(
            try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
                Set($0.exerciseSlot?.allowedTargets ?? []) == Set([.hamstrings, .glutes])
            }?.exerciseSlot
        )
        XCTAssertEqual(hingeSlot.resolvedExercise?.canonicalName, "Romanian Deadlift", "a hinge-intent slot must resolve to the compatible hinge movement, never Front Squat, even though Front Squat also targets .glutes")
    }

    func testHingeIntentSlotResolvesToACompatibleHingeMovementWhenOneExists() throws {
        let realCatalog = ExerciseCatalog.makeAndInsert(context: context)
        let definition = try generateReferenceConfig()
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(
            definition: definition,
            candidateExercises: [realCatalog.romanianDeadlift, realCatalog.conventionalDeadlift, realCatalog.backSquat, realCatalog.frontSquat]
        )
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let hingeSlot = try XCTUnwrap(
            try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
                Set($0.exerciseSlot?.allowedTargets ?? []) == Set([.hamstrings, .glutes])
            }?.exerciseSlot
        )
        let resolvedName = hingeSlot.resolvedExercise?.canonicalName
        XCTAssertTrue(resolvedName == "Romanian Deadlift" || resolvedName == "Conventional Deadlift", "must resolve to a genuinely hinge-compatible movement, got \(resolvedName ?? "nil")")
    }

    /// The inverse of the bug: a squat-intent slot must never resolve to
    /// a pure hinge movement merely due to shared `.glutes` overlap.
    func testSquatIntentSlotCannotResolveToAnIncompatibleHingeMovement() throws {
        let realCatalog = ExerciseCatalog.makeAndInsert(context: context)
        let definition = try generateReferenceConfig()
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(
            definition: definition, candidateExercises: [realCatalog.romanianDeadlift]
        )
        let dayC = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let squatSlot = try XCTUnwrap(
            try XCTUnwrap(dayC.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
                Set($0.exerciseSlot?.allowedTargets ?? []) == Set([.quadriceps, .glutes])
            }?.exerciseSlot
        )
        XCTAssertNil(squatSlot.resolvedExercise, "with only a hinge-tagged candidate available, the squat-intent slot must be left unresolved (.calibrationRequired) rather than incorrectly accepting Romanian Deadlift")
    }

    // MARK: - Exercise continuity across weeks, no reroll

    private func makeStrengthCandidatePool() -> [Exercise] {
        func exercise(_ name: String, _ targets: [MuscleGroup], _ movementFunctions: [MovementFunction] = []) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets, movementFunctions: movementFunctions)
            context.insert(ex)
            return ex
        }
        // `.pressLoaded`/`.squatLoaded`/`.hingeLoaded` tags are required
        // (Blocker 2) for these candidates to satisfy "Horizontal Push"/
        // "Squat Pattern"/"Hinge Pattern"'s movement-intent constraint —
        // muscle-group overlap alone is no longer sufficient.
        return [
            exercise("Zzz Test Chest Shoulders", [.chest, .shoulders], [.pressLoaded]),
            exercise("Zzz Test Quads", [.quadriceps], [.squatLoaded]),
            exercise("Zzz Test Hamstrings Glutes", [.hamstrings, .glutes], [.hingeLoaded]),
            exercise("Zzz Test Back", [.back]),
            exercise("Zzz Test Biceps", [.biceps]),
            exercise("Zzz Test Triceps", [.triceps]),
            exercise("Zzz Test Calves", [.calves]),
        ]
    }

    func testExerciseContinuityAcrossWeeksNoSlotEverRerolls() throws {
        let definition = try generateReferenceConfig()
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: makeStrengthCandidatePool())

        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let week0 = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let week1 = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 1, isDeload: false,
            startDate: Calendar.current.date(byAdding: .day, value: 7, to: Date(timeIntervalSince1970: 0))!,
            ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { slot in
                let week0Weight = AutoregulationRatingResolver.weekZeroResolvedWeight(
                    for: slot.prescriptionTemplate ?? PrescriptionTemplate(), in: instance
                )
                return .init(rmKilograms: 100, weekOneResolvedWeightKg: week0Weight, previousWeekSetCount: 3, autoregulationRating: 0)
            }, context: context
        )

        XCTAssertEqual(week0.sessions.count, 3)
        XCTAssertEqual(week1.sessions.count, 3)

        for (session0, session1) in zip(week0.sessions, week1.sessions) {
            let exercises0 = session0.orderedBlocks.flatMap(\.orderedPrescriptions).compactMap { $0.sourceExerciseSlot.map { ($0.id, $0.resolvedExercise?.id) } }
            let exercises1 = session1.orderedBlocks.flatMap(\.orderedPrescriptions).compactMap { $0.sourceExerciseSlot.map { ($0.id, $0.resolvedExercise?.id) } }
            let bySlot0 = Dictionary(uniqueKeysWithValues: exercises0)
            let bySlot1 = Dictionary(uniqueKeysWithValues: exercises1)
            for (slotID, exerciseID) in bySlot0 {
                XCTAssertEqual(bySlot1[slotID] ?? nil, exerciseID, "slot \(slotID) must resolve to the identical exercise both weeks — no reroll")
            }
        }
    }

    func testResolvingTwiceIsDeterministicAcrossIndependentDefinitions() throws {
        let pool = makeStrengthCandidatePool()
        let definitionA = try generateReferenceConfig()
        let definitionB = try generateReferenceConfig()
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definitionA, candidateExercises: pool)
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definitionB, candidateExercises: pool)

        // Keyed by (day name, slot name) rather than slot name alone —
        // unlike a single-day fixture, this 3-day reference config
        // legitimately repeats slot names across days (e.g. "Triceps" on
        // every day), which would otherwise collide in a flat dictionary.
        func resolvedNamesByDayAndSlotName(_ definition: ProgramDefinition) -> [String: String] {
            var result: [String: String] = [:]
            for session in definition.orderedTemplateSessions {
                for slot in session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates).compactMap(\.exerciseSlot) {
                    result["\(session.name)|\(slot.name)"] = slot.resolvedExercise?.canonicalName ?? ""
                }
            }
            return result
        }
        XCTAssertEqual(resolvedNamesByDayAndSlotName(definitionA), resolvedNamesByDayAndSlotName(definitionB), "identical inputs must resolve identically — no randomness")
    }

    // MARK: - Progression correctness carries over unchanged

    /// Stage 10B.6: a primary slot's week-to-week weight is no longer a
    /// static %RM multiplier — it's `HypertrophyV2ProgressionEngine`'s
    /// performance-qualified decision, driven by real logged history via
    /// `DoubleProgressionHistoryResolver`. With no history at all, every
    /// week resolves to calibration required; this is the correct,
    /// intentional replacement for the old fixed-multiplier expectation.
    func testPrimarySlotWeightResolutionRequiresCalibrationWithNoHistoryAtAnyWeek() throws {
        let definition = try generateReferenceConfig()
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let primary = try XCTUnwrap(try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates.first { $0.slotRole == .primary })
        XCTAssertEqual(primary.rules?.loadRule, .doubleProgression)

        let exercise = Exercise(canonicalName: "Test Exercise", modality: .strength, equipment: "barbell", movementPattern: "squat")
        let resolution = HypertrophyV2ProgressionEngine.resolveWeight(exercise: exercise, performanceProfile: nil, equipmentIncrement: 2.5)
        XCTAssertEqual(resolution.reasonCode, .calibrationRequired)
        XCTAssertNil(resolution.weightKg)
    }

    // MARK: - New exercise seed metadata (D-10B-6)

    func testNewAccessoryExerciseRowsHaveCorrectDomainMetadata() {
        let catalog = ExerciseCatalog.makeAndInsert(context: context)
        XCTAssertEqual(catalog.barbellCurl.canonicalName, "Barbell Curl")
        XCTAssertEqual(catalog.barbellCurl.primaryTargets, [.biceps])
        XCTAssertEqual(catalog.barbellCurl.modality, .hypertrophy)

        XCTAssertEqual(catalog.cableTricepsPushdown.canonicalName, "Cable Triceps Pushdown")
        XCTAssertEqual(catalog.cableTricepsPushdown.primaryTargets, [.triceps])

        XCTAssertEqual(catalog.dumbbellLateralRaise.canonicalName, "Dumbbell Lateral Raise")
        XCTAssertEqual(catalog.dumbbellLateralRaise.primaryTargets, [.shoulders])

        XCTAssertEqual(catalog.barbellRow.canonicalName, "Barbell Row")
        XCTAssertEqual(catalog.barbellRow.primaryTargets, [.back, .biceps])

        for exercise in [catalog.barbellCurl, catalog.cableTricepsPushdown, catalog.dumbbellLateralRaise, catalog.barbellRow] {
            XCTAssertFalse(exercise.equipment.isEmpty)
            XCTAssertFalse(exercise.movementPattern.isEmpty)
        }
    }

    // MARK: - Substitution compatibility

    func testGeneratedSlotsStillValidateSubstitutionCorrectly() throws {
        let definition = try generateReferenceConfig()
        let dayA = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let biceps = try XCTUnwrap(try XCTUnwrap(dayA.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
            $0.slotRole == .accessory && $0.exerciseSlot?.allowedTargets == [.biceps]
        }?.exerciseSlot)

        let validCandidate = Exercise(canonicalName: "Zzz Valid Bicep Candidate", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "test", primaryTargets: [.biceps])
        let invalidCandidate = Exercise(canonicalName: "Zzz Invalid Candidate", modality: .hypertrophy, equipment: "machine", movementPattern: "test", primaryTargets: [.calves])
        context.insert(validCandidate)
        context.insert(invalidCandidate)

        XCTAssertTrue(SubstitutionValidator.isValid(candidate: validCandidate, for: biceps))
        XCTAssertFalse(SubstitutionValidator.isValid(candidate: invalidCandidate, for: biceps))
    }

    // MARK: - Readiness compatibility

    func testReadinessAdaptationStillEvaluatesCorrectlyAgainstARichlyGeneratedSession() throws {
        let definition = try generateReferenceConfig()
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: makeStrengthCandidatePool())
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let materialized = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let session = try XCTUnwrap(materialized.sessions.first)

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.biceps])
        context.insert(checkIn)

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: context)
        XCTAssertFalse(proposal.isEmpty, "reported pain in a muscle group this session actually trains (biceps) must still surface a real adaptation proposal against a Stage 10B multi-slot session")
    }

    // MARK: - Warm-up compatibility

    func testWarmupGenerationStillProducesARicherSequenceForAStage10BSession() throws {
        let exerciseCatalog = ExerciseCatalog.makeAndInsert(context: context)
        WarmupCatalog.makeAndInsert(exerciseCatalog: exerciseCatalog, context: context)

        let definition = try generateReferenceConfig()
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: makeStrengthCandidatePool())
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let materialized = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let session = try XCTUnwrap(materialized.sessions.first)

        let sequence = GenerateWarmupSequenceUseCase.generate(
            context: WarmupGenerationContext(executableWorkout: session, readiness: nil), modelContext: context
        )
        XCTAssertNotNil(sequence, "a richly-generated Stage 10B session must still produce a warm-up sequence")
        XCTAssertFalse(sequence?.items.isEmpty ?? true)
    }

    // MARK: - Unchanged behavior for other configurations (regression)

    func testOtherHypertrophyConfigurationsStillUseTheUnchangedLegacyTwoSlotShape() throws {
        for config in HypertrophyBuiltInLibrary.all where !(config.dayCount == 3 && config.split == .fullBody) {
            let definition = try HypertrophyProgramGenerator.generate(
                configuration: HypertrophyProgramConfiguration(dayCount: config.dayCount, split: config.split, phaseType: .basicHypertrophy),
                provenance: .constructed(reason: "regression"), context: context
            )
            for session in definition.orderedTemplateSessions {
                let count = try XCTUnwrap(session.orderedBlockTemplates.first).orderedPrescriptionTemplates.count
                XCTAssertEqual(count, 2, "\(config.name) must still produce exactly 1 primary + 1 paired accessory, unchanged by Stage 10B")
            }
        }
    }

    func testPowerliftingGenerationIsCompletelyUnaffected() {
        for entry in PowerliftingBuiltInLibrary.all {
            let definition = PowerliftingProgramGenerator.generate(
                configuration: entry.configuration, provenance: .constructed(reason: "regression"), context: context
            )
            XCTAssertEqual(definition.orderedTemplateSessions.count, entry.configuration.dayCount)
            XCTAssertEqual(definition.programmingSystem, .powerlifting)
        }
    }
}

