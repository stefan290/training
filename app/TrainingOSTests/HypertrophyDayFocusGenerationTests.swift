import XCTest
import SwiftData
@testable import TrainingOS

/// Stage 10R.1 Slice 1A: proves `HypertrophyProgramGenerator.generateDayFocusDriven`
/// now reflects the REAL, cell-cited Mesocycle 1 "Basic Hypertrophy"
/// structure recovered from `3 day full body_Novice.xlsx`
/// (`SOURCE_PROGRAM_MANIFEST.md` §3), not the retired TrainingOS-invented
/// Day A/B/C rotation. Tests that exercise still-generic, content-
/// independent mechanisms (`groupMuscleGroups`, `validateWeeklyCoverage`,
/// `isHeavyQuadsGlutesException`, the legacy/Powerlifting regression
/// checks) are kept from the prior Stage 10B suite unchanged — they test a
/// mechanism, not the retired content.
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

    /// Seeds the real catalog first so `generateDayFocusDriven`'s
    /// direct-by-name exercise lookup (`findCatalogedExercise`) actually
    /// finds something — mirrors the real production seeding order
    /// (catalog exists before any program is generated).
    @discardableResult
    private func generateReferenceConfigWithCatalogSeeded() throws -> (definition: ProgramDefinition, catalog: ExerciseCatalog) {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        let definition = try generateReferenceConfig()
        return (definition, catalog)
    }

    // MARK: - Exact source category sequence (Day 1/2/3), per Slice 1A's own requirement

    func testSourceMesocycle1HasExactlyThreeDaysWithTheRecoveredEmphasisNames() throws {
        let definition = try generateReferenceConfig()
        XCTAssertEqual(definition.orderedTemplateSessions.map(\.name), ["Push Emphasis", "Legs Emphasis", "Pull Emphasis"])
    }

    func testDayOneMatchesTheExactRecoveredSourceCategorySequence() throws {
        let definition = try generateReferenceConfig()
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Horizontal Push", "Chest Isolation or Triceps", "Incline Push or Front Delts", "Side Delts",
            "Vertical Pull", "Horizontal Pull", "Hamstrings Isolation", "Quads",
        ])
        XCTAssertEqual(slots.map { $0.rules?.setCountRule }, [
            .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            .autoregulated(AutoregulatedSetCount(baselineSets: 2, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 2, treatMissingRatingAsNoChange: true)),
        ], "Week-1 baseline sets must be the literal recovered source value per slot, not a flat role-derived constant")
    }

    func testDayTwoMatchesTheExactRecoveredSourceCategorySequenceIncludingTheRepeatedQuadsCategory() throws {
        let definition = try generateReferenceConfig()
        let day2 = try XCTUnwrap(definition.orderedTemplateSessions[1])
        let slots = try XCTUnwrap(day2.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Quads", "Quads", "Hamstrings Hip Hinge", "Side Delts", "Vertical Pull",
            "Horizontal Pull", "Incline Push or Front Delts", "Horizontal Push",
        ])
        XCTAssertEqual(slots.map(\.rules?.setCountRule), [
            .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 3, treatMissingRatingAsNoChange: true)),
            .autoregulated(AutoregulatedSetCount(baselineSets: 2, treatMissingRatingAsNoChange: true)), .autoregulated(AutoregulatedSetCount(baselineSets: 2, treatMissingRatingAsNoChange: true)),
        ])
    }

    func testDayThreeMatchesTheExactRecoveredSourceCategorySequence() throws {
        let definition = try generateReferenceConfig()
        let day3 = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let slots = try XCTUnwrap(day3.orderedBlockTemplates.first).orderedPrescriptionTemplates
        XCTAssertEqual(slots.compactMap { $0.exerciseSlot?.name }, [
            "Vertical Pull", "Horizontal Pull", "Rear Delts or Side Delts", "Biceps",
            "Horizontal Push", "Incline Push", "Glutes", "Hamstrings Isolation",
        ])
    }

    func testNoSourceCategoryIsOmittedAndNoCategoryIsInvented() throws {
        let definition = try generateReferenceConfig()
        let allSlotNames = definition.orderedTemplateSessions
            .flatMap { $0.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) }
            .compactMap { $0.exerciseSlot?.name }
        // Every recovered source label, in the exact recovered multiplicity
        // (e.g. "Quads" appears 3x across the week, "Horizontal Push" 3x).
        let expected = HypertrophyProgramGenerator.threeDayFullBodyMesocycle1BasicHypertrophy
            .flatMap(\.categories).map(\.sourceLabel)
        XCTAssertEqual(allSlotNames.sorted(), expected.sorted())
        XCTAssertEqual(allSlotNames.count, 24, "8 categories/day x 3 days, exactly matching the recovered workbook — never more, never fewer")
    }

    // MARK: - Canonical category identity + source-label provenance (Decision 3)

    func testEveryGeneratedSlotCarriesTheCorrectCanonicalCategoryTargetsAndMovementIntent() throws {
        let definition = try generateReferenceConfig()
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let slots = try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates
        let horizontalPush = try XCTUnwrap(slots.first { $0.exerciseSlot?.name == "Horizontal Push" }?.exerciseSlot)
        XCTAssertEqual(horizontalPush.allowedTargets, SourceHypertrophyCategory.horizontalPush.allowedTargets)
        XCTAssertEqual(horizontalPush.allowedMovementFunctions, SourceHypertrophyCategory.horizontalPush.allowedMovementFunctions)

        let day3 = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let day3Slots = try XCTUnwrap(day3.orderedBlockTemplates.first).orderedPrescriptionTemplates
        // The exact source-label-variance case (Decision 3): this file's
        // real label is "Rear Delts or Side Delts," not "Rear or Side
        // Delts" (the label another real workbook uses for the identical
        // canonical category) — both must resolve to the same canonical
        // identity, and THIS file's own literal label must survive as the
        // slot's display name (provenance preserved, never silently
        // renamed to the other file's spelling).
        let rearOrSideDelts = try XCTUnwrap(day3Slots.first { $0.exerciseSlot?.name == "Rear Delts or Side Delts" }?.exerciseSlot)
        XCTAssertEqual(SourceHypertrophyCategory.labelAliases["Rear Delts or Side Delts"], .rearOrSideDelts)
        XCTAssertEqual(SourceHypertrophyCategory.labelAliases["Rear or Side Delts"], .rearOrSideDelts, "a different real workbook's label variant must normalize to the identical canonical category")
        XCTAssertEqual(rearOrSideDelts.allowedTargets, SourceHypertrophyCategory.rearOrSideDelts.allowedTargets)
    }

    // MARK: - Source-approved exercise resolution (never a TrainingOS-invented substitute)

    func testEveryResolvedExerciseBelongsToItsCategorysSourceApprovedOptionSet() throws {
        let (definition, _) = try generateReferenceConfigWithCatalogSeeded()
        for session in definition.orderedTemplateSessions {
            for template in session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) {
                guard let slot = template.exerciseSlot, let category = SourceHypertrophyCategory.labelAliases[slot.name] else {
                    XCTFail("every generated slot must carry a recognized source label"); continue
                }
                let resolvedName = try XCTUnwrap(slot.resolvedExercise?.canonicalName, "\(slot.name) must resolve to a real exercise once the catalog is seeded")
                let approved = category.sourceApprovedExerciseNames
                // Documented, narrow equivalences (never an unrelated
                // substitute) — see `HypertrophyProgramGenerator
                // .sourceCategoryResolvedExerciseName`'s own doc comment
                // for why each of these specific pairs is a defensible
                // same-movement naming variant, not a different exercise.
                let recognizedEquivalences: [String: String] = [
                    "Barbell Bench Press": "Medium Grip Bench Press",
                    "Barbell Overhead Press": "Standing Barbell Shoulder Press",
                    "Cable Chest Fly": "Cable Flye",
                    "Barbell Row": "Barbell Bent Over Row",
                    "Lat Pulldown": "Wide-Grip Pulldown",
                    "Dumbbell Lateral Raise": "Dumbbell Side Lateral Raise",
                    "Face Pull": "Cable Facepull",
                    "Conventional Deadlift": "Deadlift",
                ]
                let isDirectMatch = approved.contains(resolvedName)
                let isRecognizedEquivalence = recognizedEquivalences[resolvedName].map(approved.contains) ?? false
                XCTAssertTrue(
                    isDirectMatch || isRecognizedEquivalence,
                    "\(resolvedName) resolved for \(slot.name) (\(category)) is neither a literal source-approved name nor a documented equivalence: \(approved)"
                )
            }
        }
    }

    func testTheTwoQuadsSlotsOnLegsEmphasisResolveToTwoDistinctSourceApprovedExercises() throws {
        let (definition, _) = try generateReferenceConfigWithCatalogSeeded()
        let day2 = try XCTUnwrap(definition.orderedTemplateSessions[1])
        let quadsSlots = try XCTUnwrap(day2.orderedBlockTemplates.first).orderedPrescriptionTemplates
            .filter { $0.exerciseSlot?.name == "Quads" }
        XCTAssertEqual(quadsSlots.count, 2)
        let resolvedNames = quadsSlots.compactMap { $0.exerciseSlot?.resolvedExercise?.canonicalName }
        XCTAssertEqual(Set(resolvedNames).count, 2, "the same category appearing twice in one day must not prescribe the identical exercise twice")
        for name in resolvedNames {
            XCTAssertTrue(SourceHypertrophyCategory.quads.sourceApprovedExerciseNames.contains(name), "\(name) must be one of Quads' real source-approved options")
        }
    }

    func testTheOneNewCatalogExerciseIsARealSourceNamedMovementNotATrainingOSInvention() {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        XCTAssertEqual(catalog.stiffLeggedDeadlift.canonicalName, "Stiff-Legged Deadlift")
        XCTAssertTrue(SourceHypertrophyCategory.hamstringsHipHinge.sourceApprovedExerciseNames.contains("Stiff-Legged Deadlift"))
    }

    // MARK: - Progression restoration (Stage 10R.1 Slice 1B)

    /// Every slot in this Mesocycle uses the restored source-compatible
    /// `.rmBased` load (Week-1 factor 0.85, the shared Family A later-week
    /// multipliers) and the literal fixed rep/failure schedule — Stage
    /// 10B.6's `.doubleProgression`/rep-range/RIR mechanism is retired
    /// from this program's path entirely (kept as infrastructure
    /// elsewhere, per the Slice 1B design doc's routing/authority
    /// distinction).
    func testEverySlotUsesTheRestoredSourceCompatibleLoadAndRepSchedule() throws {
        let definition = try generateReferenceConfig()
        for session in definition.orderedTemplateSessions {
            for template in session.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) {
                guard case .rmBased(let payload) = try XCTUnwrap(template.rules?.loadRule) else {
                    return XCTFail("every real Mesocycle 1 slot must use the restored source-compatible .rmBased load")
                }
                XCTAssertEqual(payload.rmType, .rm10)
                XCTAssertEqual(payload.weekOneFactor, 0.85, accuracy: 0.0001)
                XCTAssertEqual(payload.laterWeekMultipliers, [1.05, 1.075, 1.1])
                // Stage 10R.1D: "N/fail" is RIR N, never a fixed rep count.
                let schedule = try XCTUnwrap(template.rules?.repGoalSchedule)
                let rirValues = schedule.map { goal -> Int? in
                    guard case .rir(let n) = goal.prescription else { return nil }
                    return n
                }
                XCTAssertEqual(rirValues, [3, 3, 2, 1], "the literal source RIR schedule, never a fabricated fixed rep count")
                XCTAssertTrue(schedule.allSatisfy { $0.repRangeHigh == nil }, "no Stage 10B.6 rep range on a source-recovered slot")
                XCTAssertTrue(schedule.allSatisfy { $0.targetRir == nil }, "no Stage 10B.6 explicit RIR companion value — the .rir(_:) prescription IS the effort target")
                if case .autoregulated(let config) = try XCTUnwrap(template.rules?.setCountRule) {
                    XCTAssertTrue(config.treatMissingRatingAsNoChange, "Decision A: a blank source rating is 'no change,' not .calibrationRequired, for this program")
                } else {
                    XCTFail("every real Mesocycle 1 slot autoregulates its set count")
                }
            }
        }
    }

    /// Stage 10R.1 Slice 1B: every slot's `pairedSlot` must match the real,
    /// fixed, cell-cited source rating-pairing table exactly — never
    /// Slice 1A's temporary self-reference, and never a re-derived
    /// "nearest same-category" heuristic.
    func testEverySlotsPairedSlotMatchesTheRealRecoveredSourcePairingTable() throws {
        let definition = try generateReferenceConfig()
        let templatesByDay = definition.orderedTemplateSessions.map { $0.orderedBlockTemplates.flatMap(\.orderedPrescriptionTemplates) }
        XCTAssertEqual(templatesByDay.map(\.count), [8, 8, 8])

        for pairing in HypertrophyProgramGenerator.threeDayFullBodyMesocycle1RatingPairings {
            let template = templatesByDay[pairing.dayIndex][pairing.slotIndex]
            let expectedPaired = templatesByDay[pairing.pairedDayIndex][pairing.pairedSlotIndex]
            XCTAssertEqual(template.pairedSlot?.id, expectedPaired.id, "day \(pairing.dayIndex) slot \(pairing.slotIndex) must be paired exactly per the recovered source table")
        }
        // No slot is left self-paired (Slice 1A's retired placeholder).
        for day in templatesByDay {
            for template in day {
                XCTAssertNotEqual(template.pairedSlot?.id, template.id, "Slice 1A's temporary self-pairing must be fully replaced")
            }
        }
    }

    /// Part 3 of the Slice 1B design: which exercise a category resolves
    /// to must never influence its `pairedSlot` — pairing is by source
    /// slot/row identity, completely orthogonal to exercise resolution.
    /// The two "Quads" slots on Legs Emphasis resolve to two different
    /// exercises (Front Squat vs. Leg Press) yet both correctly pair back
    /// to the same Push Emphasis Quads slot, per the recovered table.
    func testExerciseResolutionNeverAffectsTheSourcePairingRelationship() throws {
        let (definition, _) = try generateReferenceConfigWithCatalogSeeded()
        let day2 = try XCTUnwrap(definition.orderedTemplateSessions[1])
        let quadsSlots = try XCTUnwrap(day2.orderedBlockTemplates.first).orderedPrescriptionTemplates.filter { $0.exerciseSlot?.name == "Quads" }
        XCTAssertEqual(quadsSlots.count, 2)
        XCTAssertEqual(Set(quadsSlots.compactMap { $0.exerciseSlot?.resolvedExercise?.canonicalName }).count, 2, "sanity: the two Quads slots really do resolve differently")
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let pushQuads = try XCTUnwrap(try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates.first { $0.exerciseSlot?.name == "Quads" })
        for slot in quadsSlots {
            XCTAssertEqual(slot.pairedSlot?.id, pushQuads.id, "both distinctly-resolved Quads slots pair to the identical source row, regardless of which exercise each resolves to")
        }
    }

    func testPrimarySlotWeightResolutionRequiresCalibrationWithNoHistoryAtAnyWeek() throws {
        let definition = try generateReferenceConfig()
        let day1 = try XCTUnwrap(definition.orderedTemplateSessions.first)
        let firstTemplate = try XCTUnwrap(try XCTUnwrap(day1.orderedBlockTemplates.first).orderedPrescriptionTemplates.first)
        let rules = try XCTUnwrap(firstTemplate.rules)
        guard case .rmBased = rules.loadRule else { return XCTFail("expected .rmBased") }

        let resolution = StrengthProgressionEngine.resolveWeight(
            rules: rules, weekIndex: 0, rmKilograms: nil, weekOneResolvedWeightKg: nil,
            pairedSlotResolvedWeightKg: nil, equipmentProfile: equipment
        )
        XCTAssertEqual(resolution.reasonCode, .calibrationRequired)
        XCTAssertNil(resolution.weightKg)
    }

    // MARK: - Determinism / no reroll across weeks

    func testExerciseContinuityAcrossWeeksNoSlotEverRerolls() throws {
        let (definition, catalog) = try generateReferenceConfigWithCatalogSeeded()
        // Slots are already pre-resolved from the real catalog; this only
        // needs to confirm nothing about a second `resolve()` call changes
        // that (idempotent, per `ResolveProgramInstanceExerciseSlotsUseCase`'s
        // own contract).
        ResolveProgramInstanceExerciseSlotsUseCase.resolve(definition: definition, candidateExercises: [catalog.backSquat])

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
        let catalogA = ExerciseCatalog.resolveOrInsert(context: context)
        let definitionA = try generateReferenceConfig()
        // A second, independent context+catalog+definition, so this
        // proves determinism isn't an artifact of sharing one context.
        let containerB = PersistenceController.makeInMemoryContainer()
        let contextB = containerB.mainContext
        _ = ExerciseCatalog.resolveOrInsert(context: contextB)
        let definitionB = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 3, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: contextB
        )
        _ = catalogA // silence unused-var warning; kept for readability of intent

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

    // MARK: - Substitution / readiness / warm-up execution regression

    func testGeneratedSlotsStillValidateSubstitutionCorrectly() throws {
        let definition = try generateReferenceConfig()
        let day3 = try XCTUnwrap(definition.orderedTemplateSessions.last)
        let biceps = try XCTUnwrap(try XCTUnwrap(day3.orderedBlockTemplates.first).orderedPrescriptionTemplates.first {
            $0.exerciseSlot?.name == "Biceps"
        }?.exerciseSlot)

        let validCandidate = Exercise(canonicalName: "Zzz Valid Bicep Candidate", modality: .hypertrophy, equipment: "dumbbell", movementPattern: "test", primaryTargets: [.biceps])
        let invalidCandidate = Exercise(canonicalName: "Zzz Invalid Candidate", modality: .hypertrophy, equipment: "machine", movementPattern: "test", primaryTargets: [.calves])
        context.insert(validCandidate)
        context.insert(invalidCandidate)

        XCTAssertTrue(SubstitutionValidator.isValid(candidate: validCandidate, for: biceps))
        XCTAssertFalse(SubstitutionValidator.isValid(candidate: invalidCandidate, for: biceps))
    }

    /// Covers every `SourceHypertrophyCategory` target/movement-function
    /// combination the real recovered Mesocycle 1 actually uses (all 3
    /// days), so these generic execution-regression tests never
    /// accidentally leave a real slot unresolved for lack of a matching
    /// synthetic candidate.
    private func makeStrengthCandidatePool() -> [Exercise] {
        func exercise(_ name: String, _ targets: [MuscleGroup], _ movementFunctions: [MovementFunction] = []) -> Exercise {
            let ex = Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets, movementFunctions: movementFunctions)
            context.insert(ex)
            return ex
        }
        return [
            exercise("Zzz Test Horizontal Push", [.chest], [.pressLoaded]),
            exercise("Zzz Test Incline Push", [.chest], [.pressLoaded]),
            exercise("Zzz Test Vertical Push", [.shoulders], [.verticalPushLoaded]),
            exercise("Zzz Test Chest Isolation Triceps", [.chest, .triceps]),
            exercise("Zzz Test Horizontal Pull", [.back], [.horizontalPullLoaded]),
            exercise("Zzz Test Vertical Pull", [.back], [.verticalPullLoaded]),
            exercise("Zzz Test Side Delts", [.lateralDelt]),
            exercise("Zzz Test Rear or Side Delts", [.rearDelt, .lateralDelt]),
            exercise("Zzz Test Biceps", [.biceps]),
            exercise("Zzz Test Quads", [.quadriceps], [.squatLoaded]),
            exercise("Zzz Test Glutes", [.glutes], [.hingeLoaded]),
            exercise("Zzz Test Hip Hinge", [.hamstrings, .glutes], [.hingeLoaded]),
            exercise("Zzz Test Hamstrings Isolation", [.hamstrings], [.kneeFlexionLoaded]),
        ]
    }

    func testReadinessAdaptationStillEvaluatesCorrectlyAgainstTheRealSourceSession() throws {
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
        // Biceps only appears on "Pull Emphasis" (Day 3) in the real
        // recovered structure — unlike the retired invented rotation,
        // where every day's accessory tier included biceps.
        let session = try XCTUnwrap(materialized.sessions.first { $0.name == "Pull Emphasis" })

        let checkIn = ReadinessCheckIn(recordedAt: Date(), reportedPain: [.biceps])
        context.insert(checkIn)

        let proposal = EvaluateReadinessAdaptationUseCase.evaluate(session: session, checkIn: checkIn, modelContext: context)
        XCTAssertFalse(proposal.isEmpty, "reported pain in a muscle group this real source session actually trains (biceps, via the dedicated Biceps category slot) must still surface a real adaptation proposal")
    }

    func testWarmupGenerationStillProducesASequenceForARealSourceSession() throws {
        let exerciseCatalog = ExerciseCatalog.resolveOrInsert(context: context)
        WarmupCatalog.makeAndInsert(exerciseCatalog: exerciseCatalog, context: context)

        let definition = try generateReferenceConfig()
        // Slots already pre-resolved from the seeded catalog; nothing
        // further needed before materializing.
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
        XCTAssertNotNil(sequence, "a real, richly-populated source session must still produce a warm-up sequence")
        XCTAssertFalse(sequence?.items.isEmpty ?? true)
    }

    // MARK: - Generic mechanism tests, unaffected by content retirement

    func testGroupMuscleGroupsClaimsKnownCompoundPatternsBeforeFallingBackToSoloSlots() {
        XCTAssertEqual(
            HypertrophyProgramGenerator.groupMuscleGroups([.quadriceps, .chest, .shoulders]),
            [[.chest, .shoulders], [.quadriceps]]
        )
        XCTAssertEqual(
            HypertrophyProgramGenerator.groupMuscleGroups([.back, .hamstrings, .glutes]),
            [[.hamstrings, .glutes], [.back]]
        )
        XCTAssertEqual(
            HypertrophyProgramGenerator.groupMuscleGroups([.biceps, .triceps]),
            [[.biceps], [.triceps]]
        )
    }

    func testGroupMuscleGroupsPrefersSquatPatternWhenQuadricepsAndGlutesShareATier() {
        let grouped = HypertrophyProgramGenerator.groupMuscleGroups([.quadriceps, .hamstrings, .glutes, .chest, .back, .shoulders])
        XCTAssertEqual(grouped, [[.quadriceps, .glutes], [.chest, .shoulders], [.hamstrings], [.back]])
    }

    func testGroupMuscleGroupsOnEmptyTierProducesNoSlots() {
        XCTAssertEqual(HypertrophyProgramGenerator.groupMuscleGroups([]), [])
    }

    func testCoverageValidationDetectsAMissingMuscleGroup() {
        let broken = [
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "X", primary: [.chest], secondary: [], accessory: [.biceps]),
            HypertrophyProgramGenerator.HypertrophyDayFocus(name: "Y", primary: [.back], secondary: [], accessory: [.biceps]),
        ]
        let report = HypertrophyProgramGenerator.validateWeeklyCoverage(dayFocuses: broken)
        XCTAssertTrue(report.mismatches.contains { $0.group == .triceps && $0.actual == 0 })
        XCTAssertTrue(report.mismatches.contains { $0.group == .quadriceps && $0.actual == 0 })
    }

    func testCoverageValidationDetectsAnOverOrUnderExposedGroupEvenWhenItAppearsAtLeastOnce() {
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

    func testCapabilityGapReasonHasADistinctGenerationFailedCase() {
        XCTAssertNotEqual(CapabilityGapReason.generationFailed, .parametersNotInstantiable)
    }

    func testHeavyQuadsGlutesExceptionFiresOnlyForPrimaryQuadGluteSlotsUnderLegsSplit() {
        XCTAssertTrue(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.quadriceps, .glutes], split: .legs))
        XCTAssertTrue(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.glutes, .quadriceps], split: .legs))
        XCTAssertFalse(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .secondary, targets: [.quadriceps, .glutes], split: .legs))
        XCTAssertFalse(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.quadriceps, .glutes], split: .fullBody))
        XCTAssertFalse(HypertrophyProgramGenerator.isHeavyQuadsGlutesException(role: .primary, targets: [.quadriceps], split: .legs))
    }

    func testNewAccessoryExerciseRowsHaveCorrectDomainMetadata() {
        let catalog = ExerciseCatalog.resolveOrInsert(context: context)
        XCTAssertEqual(catalog.barbellCurl.canonicalName, "Barbell Curl")
        XCTAssertEqual(catalog.barbellCurl.primaryTargets, [.biceps])
        XCTAssertEqual(catalog.barbellCurl.modality, .hypertrophy)
        XCTAssertEqual(catalog.cableTricepsPushdown.canonicalName, "Cable Triceps Pushdown")
        XCTAssertEqual(catalog.cableTricepsPushdown.primaryTargets, [.triceps])
        XCTAssertEqual(catalog.dumbbellLateralRaise.canonicalName, "Dumbbell Lateral Raise")
        XCTAssertEqual(catalog.dumbbellLateralRaise.primaryTargets, [.shoulders, .lateralDelt])
        XCTAssertEqual(catalog.barbellRow.canonicalName, "Barbell Row")
        XCTAssertEqual(catalog.barbellRow.primaryTargets, [.back, .biceps])
        for exercise in [catalog.barbellCurl, catalog.cableTricepsPushdown, catalog.dumbbellLateralRaise, catalog.barbellRow] {
            XCTAssertFalse(exercise.equipment.isEmpty)
            XCTAssertFalse(exercise.movementPattern.isEmpty)
        }
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
                XCTAssertEqual(count, 2, "\(config.name) must still produce exactly 1 primary + 1 paired accessory, unchanged by Stage 10R.1 Slice 1A")
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
