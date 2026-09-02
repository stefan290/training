import XCTest
import SwiftData
@testable import TrainingOS

/// Stage CP.1: proves `TrainingStressProfile` parity across Hypertrophy/
/// Powerlifting/Interval/SteadyState — the same coarse, categorical,
/// explainable vocabulary Functional Fitness already stamped, now stamped
/// by every other materialized modality too, through the existing
/// `WorkoutBlock.trainingStressProfile` seam. This is observational only:
/// no test here asserts anything about a resolved prescription changing —
/// several explicitly assert the opposite (§A.4).
@MainActor
final class TrainingStressProfileParityTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    let ownerUserID = UUID()
    let equipment = EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5)

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func exercise(_ name: String, targets: [MuscleGroup]) -> Exercise {
        Exercise(canonicalName: name, modality: .hypertrophy, equipment: "barbell", movementPattern: "test", primaryTargets: targets)
    }

    /// The legacy fixed-pair `HypertrophyProgramGenerator` path (unlike
    /// the day-focus-driven path) never pre-resolves `ExerciseSlot
    /// .resolvedExercise` — that normally happens later, via a real
    /// catalog lookup this test has no need to set up in full, since
    /// resolved exercise identity is irrelevant to proving weight/reps/RIR
    /// are unaffected by stress mapping. Resolves every slot in the
    /// generated definition directly so `StrengthMaterializer` produces
    /// real, non-nil `ExercisePrescription.exercise` values to classify.
    private func resolveAllSlots(in definition: ProgramDefinition, to exercise: Exercise) {
        for templateSession in definition.orderedTemplateSessions {
            for blockTemplate in templateSession.orderedBlockTemplates {
                for template in blockTemplate.orderedPrescriptionTemplates {
                    template.exerciseSlot?.resolvedExercise = exercise
                }
            }
        }
    }

    // MARK: A. Hypertrophy — pure classification logic

    func testUpperDominantHypertrophyProducesMeaningfulUpperBodyStressOnly() throws {
        let prescriptions = [
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Bench Press", targets: [.chest, .triceps]), weightKg: 80, repGoal: .rir(1), setCount: 4)
        ]
        let profile = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: prescriptions))
        XCTAssertNotEqual(profile.upperBodyLoad, .none)
        XCTAssertEqual(profile.lowerBodyLoad, .none)
        XCTAssertEqual(profile.impactLoading, .none, "controlled barbell/dumbbell/machine work carries no impact loading")
    }

    func testLowerDominantHypertrophyProducesMeaningfulLowerBodyStressOnly() throws {
        let prescriptions = [
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Back Squat", targets: [.quadriceps, .glutes]), weightKg: 120, repGoal: .rir(1), setCount: 4)
        ]
        let profile = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: prescriptions))
        XCTAssertNotEqual(profile.lowerBodyLoad, .none)
        XCTAssertEqual(profile.upperBodyLoad, .none)
    }

    /// "Do not classify a whole session from one exercise" — a mixed
    /// full-body block must reflect BOTH regions regardless of which
    /// prescription happens to be inspected first.
    func testMixedFullBodyHypertrophyReflectsBothRegionsRegardlessOfOrder() throws {
        let squat = StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Back Squat", targets: [.quadriceps, .glutes]), weightKg: 100, repGoal: .rir(2), setCount: 3)
        let bench = StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Bench Press", targets: [.chest, .triceps]), weightKg: 60, repGoal: .rir(2), setCount: 3)

        let profileA = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: [squat, bench]))
        let profileB = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: [bench, squat]))

        for profile in [profileA, profileB] {
            XCTAssertNotEqual(profile.lowerBodyLoad, .none, "a mixed full-body block must reflect lower-body load regardless of inspection order")
            XCTAssertNotEqual(profile.upperBodyLoad, .none, "a mixed full-body block must reflect upper-body load regardless of inspection order")
        }
        XCTAssertEqual(profileA.lowerBodyLoad, profileB.lowerBodyLoad)
        XCTAssertEqual(profileA.upperBodyLoad, profileB.upperBodyLoad)
    }

    /// The direct proof that CP.1 never touches source-authored values —
    /// same expected weight `StrengthMaterializerTests`'s own pre-CP.1
    /// assertion already established (MROUND(100*0.85, 2.5) for Basic
    /// Hypertrophy week 1).
    func testSourcePrescriptionIsUnchangedByStressMapping() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 5, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: definition, to: exercise("Bench Press", targets: [.chest, .triceps]))
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let result = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100) }, context: context
        )
        let session = try XCTUnwrap(result.sessions.first)
        let block = try XCTUnwrap(session.orderedBlocks.first)
        XCTAssertNotNil(block.trainingStressProfile, "precondition: CP.1 actually stamped this block")

        let primary = try XCTUnwrap(block.orderedPrescriptions.first { $0.orderedSetPrescriptions.count == 3 })
        for setPrescription in primary.orderedSetPrescriptions {
            XCTAssertEqual(setPrescription.targetWeight ?? -1, 85, accuracy: 0.0001)
            XCTAssertNil(setPrescription.repRangeLow)
            XCTAssertNil(setPrescription.repRangeHigh)
        }
    }

    /// A real deload week's genuinely reduced weight must never classify
    /// as MORE demanding than the progressive week it follows — proven
    /// through the real materializer/mapper pipeline, with no isDeload
    /// branch anywhere in the mapper itself.
    func testDeloadIsNotReinterpretedAsNormalProgressiveStress() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: definition, to: exercise("Back Squat", targets: [.quadriceps, .glutes]))
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let peakWeekResult = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 3, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100, weekOneResolvedWeightKg: 85) }, context: context
        )
        let deloadResult = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 4, isDeload: true,
            startDate: Date(timeIntervalSince1970: 7 * 4 * 86400), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 100, weekOneResolvedWeightKg: 85) }, context: context
        )

        let peakBlock = try XCTUnwrap(peakWeekResult.sessions.first?.orderedBlocks.first)
        let deloadBlock = try XCTUnwrap(deloadResult.sessions.first?.orderedBlocks.first)
        let peakProfile = try XCTUnwrap(peakBlock.trainingStressProfile)
        let deloadProfile = try XCTUnwrap(deloadBlock.trainingStressProfile)

        XCTAssertLessThanOrEqual(
            deloadProfile.overallIntensity.ordinal, peakProfile.overallIntensity.ordinal,
            "the real deload week must never classify as more demanding than the peak progressive week (RIR 1) it follows"
        )
        XCTAssertLessThanOrEqual(deloadProfile.systemicDemand.ordinal, peakProfile.systemicDemand.ordinal)
    }

    // MARK: B. Powerlifting — same shared mapper, powerlifting-representative movements

    func testSquatDeadliftDominantWorkExposesLowerBodyAndSystemicStress() throws {
        let prescriptions = [
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Back Squat", targets: [.quadriceps, .glutes]), weightKg: 140, repGoal: .rir(1), setCount: 5),
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Conventional Deadlift", targets: [.hamstrings, .glutes, .back]), weightKg: 160, repGoal: .rir(1), setCount: 3)
        ]
        let profile = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: prescriptions))
        XCTAssertEqual(profile.lowerBodyLoad, .high)
        XCTAssertEqual(profile.overallIntensity, .high)
        XCTAssertEqual(profile.systemicDemand, .high, "8 total heavy near-failure sets is genuinely high total volume too")
    }

    func testBenchDominantWorkExposesUpperBodyStress() throws {
        let prescriptions = [
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Bench Press", targets: [.chest, .triceps]), weightKg: 100, repGoal: .rir(1), setCount: 5)
        ]
        let profile = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: prescriptions))
        XCTAssertNotEqual(profile.upperBodyLoad, .none)
        XCTAssertEqual(profile.lowerBodyLoad, .none)
    }

    func testMixedPowerliftingSessionComposesCorrectly() throws {
        let prescriptions = [
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Back Squat", targets: [.quadriceps, .glutes]), weightKg: 140, repGoal: .rir(2), setCount: 3),
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Bench Press", targets: [.chest, .triceps]), weightKg: 90, repGoal: .rir(2), setCount: 3)
        ]
        let profile = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: prescriptions))
        XCTAssertNotEqual(profile.lowerBodyLoad, .none)
        XCTAssertNotEqual(profile.upperBodyLoad, .none)
    }

    // MARK: C. Interval — real generator + materializer

    func testIntervalSessionsReceiveNonEmptyMeaningfulStress() throws {
        let configuration = IntervalProgramConfiguration(
            activityType: .running, allowedActivityTypes: [.running],
            daysPerWeek: 1, lengthWeeks: 1, sessionRole: .interval, workBasis: .duration,
            includeWarmUp: true, includeCoolDown: true
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let sessions = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let session = try XCTUnwrap(sessions.first)
        let blocks = session.orderedBlocks
        XCTAssertEqual(blocks.map(\.type), [.warmup, .intervals, .cooldown])
        for block in blocks {
            XCTAssertNotNil(block.trainingStressProfile, "\(block.type) must receive a real, non-nil profile")
        }
        // The interval block itself, running, repeated structure — real,
        // non-trivial stress, never a fabricated all-.none profile.
        let intervalProfile = try XCTUnwrap(blocks[1].trainingStressProfile)
        XCTAssertNotEqual(intervalProfile.lowerBodyLoad, .none)
        XCTAssertNotEqual(intervalProfile.impactLoading, .none, "running carries real impact loading")
    }

    func testActivityTypeAffectsImpactAndBodyRegionDimensions() throws {
        for activityType in [ActivityType.running, .cycling, .rowing] {
            let configuration = IntervalProgramConfiguration(
                activityType: activityType, allowedActivityTypes: [activityType],
                daysPerWeek: 1, lengthWeeks: 1, sessionRole: .interval, workBasis: .duration,
                includeWarmUp: false, includeCoolDown: false
            )
            let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
            let instance = ProgramInstance(ownerUserID: ownerUserID)
            context.insert(instance)
            instance.programDefinition = definition

            let sessions = try IntervalMaterializer.materializeWeek(
                definition: definition, instance: instance, weekIndex: 0,
                startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
                weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
            )
            let block = try XCTUnwrap(sessions.first?.orderedBlocks.first)
            let profile = try XCTUnwrap(block.trainingStressProfile)
            XCTAssertEqual(profile.modality, activityType)

            switch activityType {
            case .running:
                XCTAssertNotEqual(profile.impactLoading, .none, "running must carry real impact loading")
            case .cycling, .rowing:
                XCTAssertEqual(profile.impactLoading, .none, "\(activityType) is non-impact by construction")
            default: break
            }
        }
    }

    func testMissingIntensityDataUsesDocumentedConservativeFallback() throws {
        // No zone-shaped IntensityTarget resolved anywhere in this
        // configuration — a duration-basis config with no explicit
        // per-week intensity override falls back to whatever the
        // template's own default is; this proves the mapper never turns
        // a genuinely uncertain intensity into `.none` (which would
        // silently disable InterferenceAvoidanceRule's protection).
        let configuration = IntervalProgramConfiguration(
            activityType: .other, allowedActivityTypes: [.other],
            daysPerWeek: 1, lengthWeeks: 1, sessionRole: .interval, workBasis: .duration,
            includeWarmUp: false, includeCoolDown: false
        )
        let definition = IntervalProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let sessions = try IntervalMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 0,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,
            weekContext: { _ in .init() },  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let profile = try XCTUnwrap(sessions.first?.orderedBlocks.first?.trainingStressProfile)
        XCTAssertNotEqual(profile.overallIntensity, .none, "genuinely uncertain intensity must fall back to a conservative non-none default, never silently disable interference protection")
        XCTAssertNotEqual(profile.lowerBodyLoad, .none, ".other activity type is the documented conservative-fallback case")
    }

    // MARK: D. Steady State — real generator + materializer

    func testSteadyStateSessionsReceiveMeaningfulStress() throws {
        let configuration = SteadyStateProgramConfiguration(activityType: .cycling, allowedActivityTypes: [.cycling], daysPerWeek: 1, lengthWeeks: 1, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let sessions = try SteadyStateMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let block = try XCTUnwrap(sessions.first?.orderedBlocks.first)
        let profile = try XCTUnwrap(block.trainingStressProfile)
        XCTAssertEqual(profile.modality, .cycling)
        // The generator's own real default is Zone 2 (`.heartRateZone(.two)`)
        // — a real, domain-native zone value, not a guess.
        XCTAssertEqual(profile.overallIntensity, .low, "Zone 2 (zones 1-2) is the documented low-intensity bucket")
    }

    func testActivityTypeInfluencesImpactAndMovementDimensions() throws {
        for (activityType, expectImpact) in [(ActivityType.running, true), (.cycling, false), (.rowing, false)] {
            let configuration = SteadyStateProgramConfiguration(activityType: activityType, allowedActivityTypes: [activityType], daysPerWeek: 1, lengthWeeks: 1, progressionDimension: .none)
            let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
            let instance = ProgramInstance(ownerUserID: ownerUserID)
            context.insert(instance)
            instance.programDefinition = definition

            let sessions = try SteadyStateMaterializer.materializeAllWeeks(
                definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
            )
            let profile = try XCTUnwrap(sessions.first?.orderedBlocks.first?.trainingStressProfile)
            if expectImpact {
                XCTAssertNotEqual(profile.impactLoading, .none, "\(activityType)")
            } else {
                XCTAssertEqual(profile.impactLoading, .none, "\(activityType)")
            }
        }
    }

    func testDurationMappingRemainsCategoricalUsingExistingThresholds() throws {
        // 2700s (45min, the generator's own real default) must classify
        // as `.long` under FunctionalFitnessStimulusValidator's own
        // existing >900s threshold — reused, never a second competing
        // threshold table.
        let configuration = SteadyStateProgramConfiguration(activityType: .running, allowedActivityTypes: [.running], daysPerWeek: 1, lengthWeeks: 1, progressionDimension: .none)
        let definition = SteadyStateProgramGenerator.generate(configuration: configuration, provenance: .constructed(reason: "test"), context: context)
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition

        let sessions = try SteadyStateMaterializer.materializeAllWeeks(
            definition: definition, instance: instance, startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID,  environment: TrainingEnvironmentTestSupport.full(context: context), context: context
        )
        let profile = try XCTUnwrap(sessions.first?.orderedBlocks.first?.trainingStressProfile)
        XCTAssertEqual(profile.durationClassification, .long)
    }

    // MARK: E. Cross-modality — the decisive proof this whole stage exists for

    /// A real, materialized Hypertrophy session (heavy squat, via the real
    /// `StrengthMaterializer`/`StrengthTrainingStressMapper`) and a real
    /// Functional Fitness stimulus (heavy squat-loaded, via FF's own real,
    /// unchanged `FunctionalFitnessStressProfileMapper`) must now be
    /// visible to the existing, unmodified `InterferenceAvoidanceRule` —
    /// this was impossible before CP.1 (Hypertrophy had no stress profile
    /// at all).
    func testRealHypertrophyAndRealFunctionalFitnessConflictIsNowVisibleToInterferenceRule() throws {
        let definition = try HypertrophyProgramGenerator.generate(
            configuration: HypertrophyProgramConfiguration(dayCount: 1, split: .fullBody, phaseType: .basicHypertrophy),
            provenance: .constructed(reason: "test fixture"), context: context
        )
        resolveAllSlots(in: definition, to: exercise("Back Squat", targets: [.quadriceps, .glutes]))
        let instance = ProgramInstance(ownerUserID: ownerUserID)
        context.insert(instance)
        instance.programDefinition = definition
        // Week index 3 — the real peak progressive week (RIR 1, the
        // hardest of the mesocycle per the corrected §14 source-fidelity
        // understanding) — week 0 alone (RIR 3) only classifies `.moderate`,
        // not `.high`, and would never clear `conservativeDefault`'s
        // threshold; this must be the genuinely heaviest real week.
        let hypResult = StrengthMaterializer.materializeWeek(
            definition: definition, instance: instance, weekIndex: 3, isDeload: false,
            startDate: Date(timeIntervalSince1970: 0), ownerUserID: ownerUserID, equipmentProfile: equipment,
            slotContext: { _ in .init(rmKilograms: 140, weekOneResolvedWeightKg: 140 * 0.85) }, context: context
        )
        let hypertrophySession = try XCTUnwrap(hypResult.sessions.first)
        let hypertrophyProfile = try XCTUnwrap(SessionStressComposer.compose(hypertrophySession))

        let heavyFFStimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .load
        )
        let ffBlock = WorkoutBlock(type: .functionalFitness, trainingStressProfile: FunctionalFitnessStressProfileMapper.map(stimulus: heavyFFStimulus))
        context.insert(ffBlock)
        let ffSession = Session(name: "Heavy FF", modality: .functionalFitness)
        context.insert(ffSession)
        ffSession.addBlock(ffBlock)
        let ffProfile = try XCTUnwrap(SessionStressComposer.compose(ffSession))

        let rule = try XCTUnwrap(InterferenceAvoidanceRule.conservativeDefault.first { $0.dimension == .lowerBodyLoad })
        XCTAssertTrue(rule.triggers(hypertrophyProfile, ffProfile), "a real heavy-lower-body Hypertrophy session and a real heavy-lower-body FF stimulus must now trigger the existing interference rule")
    }

    /// A non-conflicting pair (light upper-body-only hypertrophy + a real
    /// low-load FF stimulus) must not be falsely rejected.
    func testNonConflictingRealPairIsNotFalselyRejected() throws {
        let lightUpperPrescriptions = [
            StrengthTrainingStressMapper.ResolvedPrescription(exercise: exercise("Bench Press", targets: [.chest, .triceps]), weightKg: 40, repGoal: .rir(3), setCount: 2)
        ]
        let hypertrophyProfile = try XCTUnwrap(StrengthTrainingStressMapper.map(prescriptions: lightUpperPrescriptions))

        let lightFFStimulus = Stimulus(
            targetDurationDomain: .short, intensity: .low, loading: .bodyweightOnly,
            movementFunctions: [.gymnasticsPull], movementModalityMix: [ModalityCount(modality: .gymnastics, count: 1)],
            skillDemand: .low, systemicDemand: .low, scoreType: .repetitions
        )
        let ffProfile = FunctionalFitnessStressProfileMapper.map(stimulus: lightFFStimulus)

        let rule = try XCTUnwrap(InterferenceAvoidanceRule.conservativeDefault.first { $0.dimension == .lowerBodyLoad })
        XCTAssertFalse(rule.triggers(hypertrophyProfile, ffProfile), "a light upper-body session and a light FF stimulus must never be falsely flagged as interfering")
    }

    // MARK: F. Regression

    func testFunctionalFitnessStressMapperBehaviorIsCompletelyUnchanged() {
        let stimulus = Stimulus(
            targetDurationDomain: .medium, intensity: .high, loading: .heavy,
            movementFunctions: [.squatLoaded], movementModalityMix: [ModalityCount(modality: .weightlifting, count: 1)],
            skillDemand: .moderate, systemicDemand: .high, scoreType: .load
        )
        let profile = FunctionalFitnessStressProfileMapper.map(stimulus: stimulus)
        XCTAssertEqual(profile.lowerBodyLoad, .high)
        XCTAssertEqual(profile.upperBodyLoad, .none)
        XCTAssertEqual(profile.overallIntensity, .high)
    }
}
