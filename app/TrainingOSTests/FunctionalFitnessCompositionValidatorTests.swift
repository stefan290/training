import XCTest
import SwiftData
@testable import TrainingOS

/// MUSCLE + 5FF FINAL CLOSURE, Sections 10-13: standalone, isolated
/// proof of `FunctionalFitnessCompositionValidator`/
/// `FunctionalFitnessCompositionRecomposer` — deliberately NOT yet wired
/// into real materialization (see this checkpoint's own causal-analysis
/// doc for why: real wiring needs its own careful, empirical full-
/// regression pass, never guessed). Every rule (A-F) and the magnitude
/// classifier is proven independently here first.
@MainActor
final class FunctionalFitnessCompositionValidatorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        container = PersistenceController.makeInMemoryContainer()
        context = container.mainContext
    }

    private func monostructural(_ name: String = "Easy Run (Zone 2)") -> Exercise {
        let ex = Exercise(
            canonicalName: name, modality: .functionalFitness, equipment: "none", movementPattern: "locomotion",
            movementFunctions: [.monostructural, .locomotion], functionalModality: .metabolicConditioning,
            measuredDimensions: [.distance, .duration]
        )
        context.insert(ex)
        return ex
    }

    private func lowIntensityMonostructural() -> Exercise {
        let ex = monostructural()
        ex.intendedIntensity = .low
        return ex
    }

    private func loadedMovement(_ name: String, tier: RelativeLoadTier) -> (Exercise, RelativeLoadTier) {
        let ex = Exercise(canonicalName: name, modality: .functionalFitness, equipment: "barbell", movementPattern: "hinge", movementFunctions: [.hingeLoaded], functionalModality: .weightlifting)
        context.insert(ex)
        return (ex, tier)
    }

    private func technicalMovement(_ name: String = "Toes-to-Bar") -> Exercise {
        let ex = Exercise(canonicalName: name, modality: .functionalFitness, equipment: "bodyweight", movementPattern: "coreFlexion", movementFunctions: [.gymnasticsPull, .trunk], functionalModality: .gymnastics)
        context.insert(ex)
        return ex
    }

    private func baseStimulus(domain: DurationDomain, intensity: IntensityClassification = .moderate) -> Stimulus {
        Stimulus(
            targetDurationDomain: domain, intensity: intensity, loading: .moderate,
            movementFunctions: [], movementModalityMix: [], skillDemand: .moderate, systemicDemand: .moderate, scoreType: .time
        )
    }

    // MARK: - Section 10: magnitude classification

    func testSingleMovementNonRepeatingFormatIsTrivial() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200)]
        XCTAssertEqual(FunctionalFitnessCompositionValidator.classifyMagnitude(format: .forTime(capSeconds: 1200), movements: movements), .trivial)
    }

    func testTwoMovementsNonRepeatingFormatIsSmall() {
        let movements = [
            FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200),
            FunctionalFitnessCompositionValidator.MovementInput(exercise: technicalMovement(), reps: 10),
        ]
        XCTAssertEqual(FunctionalFitnessCompositionValidator.classifyMagnitude(format: .forTime(capSeconds: 1200), movements: movements), .small)
    }

    func testThreeMovementsOrRepeatingRoundsIsModerate() {
        let threeMovements = [
            FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200),
            FunctionalFitnessCompositionValidator.MovementInput(exercise: technicalMovement(), reps: 10),
            FunctionalFitnessCompositionValidator.MovementInput(exercise: loadedMovement("Deadlift", tier: .heavy).0, reps: 8),
        ]
        XCTAssertEqual(FunctionalFitnessCompositionValidator.classifyMagnitude(format: .forTime(capSeconds: 1200), movements: threeMovements), .moderate)

        let repeatingRound = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200)]
        XCTAssertEqual(FunctionalFitnessCompositionValidator.classifyMagnitude(format: .roundsForTime(rounds: 5, capSeconds: nil), movements: repeatingRound), .moderate)
    }

    func testChipperOrFourPlusMovementsIsSubstantial() {
        let chipper = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200)]
        XCTAssertEqual(FunctionalFitnessCompositionValidator.classifyMagnitude(format: .chipper(capSeconds: 1200), movements: chipper), .substantial)

        let fourMovements = (0..<4).map { FunctionalFitnessCompositionValidator.MovementInput(exercise: technicalMovement("Movement \($0)"), reps: 10) }
        XCTAssertEqual(FunctionalFitnessCompositionValidator.classifyMagnitude(format: .roundsForTime(rounds: 1, capSeconds: nil), movements: fourMovements), .substantial)
    }

    // MARK: - Rule A: LONG + FOR_TIME + single trivial cyclical effort

    func testRuleA_LongForTimeSingleMonostructuralIsRejected() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .forTime(capSeconds: 1200), stimulus: baseStimulus(domain: .long), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(result, .invalid(reasonCode: .longDurationForTimeTrivialCyclicalEffort, offendingDimension: .durationDomainVsFormat))
    }

    func testRuleA_DoesNotFireForShortOrMediumDomain() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200)]
        for domain: DurationDomain in [.short, .medium] {
            let result = FunctionalFitnessCompositionValidator.validate(
                format: .forTime(capSeconds: 1200), stimulus: baseStimulus(domain: domain), movements: movements, performanceProfile: nil
            )
            if case .invalid(let reasonCode, _) = result {
                XCTAssertNotEqual(reasonCode, .longDurationForTimeTrivialCyclicalEffort, "\(domain) must never trigger Rule A — this is the exact real, already-shipped aerobicEngine pairing")
            }
        }
    }

    func testRuleA_DoesNotFireWhenMovementAlreadyDurationBased() {
        // Section 9's own fix — a real `.long`-domain monostructural role
        // already gets a duration target, never a fixed distance, so
        // Rule A structurally never fires against properly-generated
        // content; proven here directly.
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), durationSeconds: 1800)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .forTime(capSeconds: 1800), stimulus: baseStimulus(domain: .long), movements: movements, performanceProfile: nil
        )
        if case .valid = result {} else { XCTFail("a real duration-based monostructural role must be VALID, got \(result)") }
    }

    // MARK: - Rule B: SUSTAINED_AEROBIC + tiny fixed distance/calorie prescription

    func testRuleB_LongDomainFixedCaloriesAlongsideOtherMovementsIsRejected() {
        // Not a Rule-A single-movement case (2 movements) — proves Rule B
        // catches the fixed-quantity leak independently of Rule A's own
        // narrower single-movement shape.
        let movements = [
            FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), calories: 15),
            FunctionalFitnessCompositionValidator.MovementInput(exercise: technicalMovement(), reps: 10),
        ]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .forTime(capSeconds: 1800), stimulus: baseStimulus(domain: .long), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(result, .invalid(reasonCode: .sustainedAerobicTinyFixedQuantity, offendingDimension: .sustainedAerobicQuantity))
    }

    // MARK: - Rule C: SHORT_HIGH_OUTPUT + LOW-intensity-only movement

    func testRuleC_ShortHighOutputWithLowIntensityMovementIsRejected() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: lowIntensityMonostructural(), distanceMeters: 200)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .amrap(capSeconds: 240), stimulus: baseStimulus(domain: .short, intensity: .high), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(result, .invalid(reasonCode: .shortHighOutputLowIntensityMovement, offendingDimension: .shortHighOutputIntensity))
    }

    func testRuleC_DoesNotFireWithoutHighIntensityRequirement() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: lowIntensityMonostructural(), distanceMeters: 200)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .amrap(capSeconds: 240), stimulus: baseStimulus(domain: .short, intensity: .moderate), movements: movements, performanceProfile: nil
        )
        if case .invalid(let reasonCode, _) = result {
            XCTAssertNotEqual(reasonCode, .shortHighOutputLowIntensityMovement)
        }
    }

    // MARK: - Rule D: repeated technical movement + insufficient evidence

    func testRuleD_RepeatedTrackedMovementWithNoCapacityEvidenceIsRejected() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: technicalMovement("Toes-to-Bar"), reps: 12)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .roundsForTime(rounds: 5, capSeconds: nil), stimulus: baseStimulus(domain: .medium), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(result, .invalid(reasonCode: .repeatedTechnicalMovementInsufficientEvidence, offendingDimension: .repeatedTechnicalMovementEvidence))
    }

    func testRuleD_PassesWhenRealCapacityEvidenceExists() throws {
        let exercise = technicalMovement("Toes-to-Bar")
        let user = User(displayName: "Fixture")
        context.insert(user)
        let profile = PerformanceProfile()
        context.insert(profile)
        user.attachPerformanceProfile(profile)
        let capability = MovementCapabilityProfile(
            exercise: exercise, proficiency: .workoutReady, capacityType: .maxUnbrokenReps, capacityValue: 20,
            evidenceSource: .assessment
        )
        context.insert(capability)
        profile.addMovementCapability(capability)

        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: exercise, reps: 12)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .roundsForTime(rounds: 5, capSeconds: nil), stimulus: baseStimulus(domain: .medium), movements: movements, performanceProfile: profile
        )
        if case .invalid = result { XCTFail("real capacity evidence must clear Rule D, got \(result)") }
    }

    func testRuleD_DoesNotFireForUntrackedMovements() {
        // A technical/gymnastics movement NOT in
        // `TechnicalCapacityDoseAuthority.repeatedDoseTrackedNames` (e.g.
        // Push-up) must never trigger Rule D — this rule is scoped
        // exactly to the 7 real, already-locked gated names, never a
        // broader "any gymnastics movement" guess.
        let pushUp = Exercise(canonicalName: "Push-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "push", movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics)
        context.insert(pushUp)
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: pushUp, reps: 20)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .roundsForTime(rounds: 5, capSeconds: nil), stimulus: baseStimulus(domain: .medium), movements: movements, performanceProfile: nil
        )
        if case .invalid = result { XCTFail("Push-up is not a repeated-dose-tracked name and must never trigger Rule D, got \(result)") }
    }

    // MARK: - Rule E: format with no executable work package

    func testRuleE_NoMovementsAtAllIsRejected() {
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .amrap(capSeconds: 600), stimulus: baseStimulus(domain: .medium), movements: [], performanceProfile: nil
        )
        XCTAssertEqual(result, .invalid(reasonCode: .noExecutableWorkPackage, offendingDimension: .executableWorkPackage))
    }

    func testRuleE_MovementWithNoRealDoseAtAllIsRejected() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural())]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .amrap(capSeconds: 600), stimulus: baseStimulus(domain: .medium), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(result, .invalid(reasonCode: .noExecutableWorkPackage, offendingDimension: .executableWorkPackage))
    }

    // MARK: - Rule F: AMRAP + semantically incompatible repeatable unit

    func testRuleF_AmrapWithHeavyLoadGuidanceTierIsRejected() {
        let (deadlift, tier) = loadedMovement("Deadlift", tier: .heavy)
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: deadlift, reps: 5, loadGuidanceTier: tier)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .amrap(capSeconds: 600), stimulus: baseStimulus(domain: .medium), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(result, .invalid(reasonCode: .amrapUnitIncompatibleWithStimulus, offendingDimension: .amrapRepeatableUnitCompatibility))
    }

    func testRuleF_DoesNotFireForNonHeavyTiersOrNonAmrapFormats() {
        let (kettlebell, lightTier) = loadedMovement("Kettlebell Swing", tier: .light)
        let lightMovements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: kettlebell, reps: 15, loadGuidanceTier: lightTier)]
        let amrapResult = FunctionalFitnessCompositionValidator.validate(
            format: .amrap(capSeconds: 600), stimulus: baseStimulus(domain: .medium), movements: lightMovements, performanceProfile: nil
        )
        if case .invalid(let reasonCode, _) = amrapResult { XCTAssertNotEqual(reasonCode, .amrapUnitIncompatibleWithStimulus) }

        let (deadlift, heavyTier) = loadedMovement("Deadlift", tier: .heavy)
        let heavyMovements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: deadlift, reps: 5, loadGuidanceTier: heavyTier)]
        let nonAmrapResult = FunctionalFitnessCompositionValidator.validate(
            format: .roundsForTime(rounds: 5, capSeconds: nil), stimulus: baseStimulus(domain: .medium), movements: heavyMovements, performanceProfile: nil
        )
        if case .invalid(let reasonCode, _) = nonAmrapResult { XCTAssertNotEqual(reasonCode, .amrapUnitIncompatibleWithStimulus) }
    }

    // MARK: - Section 21, item 9: substantial fixed work + legitimate FOR_TIME remains valid

    func testSubstantialFixedWorkLongForTimeCompositionRemainsValid() {
        // Deliberately NOT the trivial shape Rule A rejects: 4 real
        // movements (SUBSTANTIAL per Section 10's own movement-count
        // dimension), a genuinely fixed (non-monostructural-distance)
        // work package, `.long` domain, plain `.forTime` — a real
        // chipper-shaped "long, substantial fixed work package" must
        // remain valid, never rejected merely for being `.long` + `.forTime`.
        // Deliberately NOT a repeated-dose-tracked movement (never Toes-
        // to-Bar/Pull-up/etc.) — this test is about Section 10's
        // magnitude classification and Rule A's own trivial-vs-substantial
        // boundary, not Rule D's evidence requirement.
        let pushUp = Exercise(canonicalName: "Push-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "push", movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics)
        context.insert(pushUp)
        let movements = [
            FunctionalFitnessCompositionValidator.MovementInput(exercise: pushUp, reps: 15),
            FunctionalFitnessCompositionValidator.MovementInput(exercise: loadedMovement("Kettlebell Swing", tier: .light).0, reps: 20, loadGuidanceTier: .light),
            // A `.long`-domain monostructural role must be duration-based
            // (Rule B) — this test is about a real SUBSTANTIAL fixed-work
            // FOR_TIME package, so its monostructural role correctly
            // carries a duration here, never a fixed distance/calorie.
            FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural("Row Erg"), durationSeconds: 600),
            FunctionalFitnessCompositionValidator.MovementInput(exercise: loadedMovement("Wall Ball", tier: .light).0, reps: 20, loadGuidanceTier: .light),
        ]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .forTime(capSeconds: 1800), stimulus: baseStimulus(domain: .long), movements: movements, performanceProfile: nil
        )
        guard case .valid(let magnitude) = result else {
            return XCTFail("a real, substantial 4-movement fixed work package under a legitimate long FOR_TIME cap must remain VALID, got \(result)")
        }
        XCTAssertEqual(magnitude, .substantial)
    }

    // MARK: - Section 21, item 12: AMRAP4 short-high-output remains valid

    func testAmrap4ShortHighOutputCompositionRemainsValid() {
        // The exact real, already-shipped shape (Section 19.O) — a
        // normal-intensity (never low-intensity) movement in a genuine
        // 4-minute AMRAP under a SHORT/HIGH stimulus must remain valid;
        // proves Rule C's own intensity check does not over-fire against
        // ordinary, non-low-intensity AMRAP4 content.
        let normalIntensity = monostructural("Assault Bike")
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: normalIntensity, calories: 15)]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .amrap(capSeconds: 240), stimulus: baseStimulus(domain: .short, intensity: .high), movements: movements, performanceProfile: nil
        )
        if case .invalid = result { XCTFail("a real AMRAP4/SHORT_HIGH_OUTPUT composition with an ordinary (non-low) intensity movement must remain VALID, got \(result)") }
    }

    // MARK: - Valid compositions pass cleanly

    func testRealisticCoherentCompositionsAllValidate() {
        // Deliberately a NON-repeated-dose-tracked movement (Push-up,
        // never Toes-to-Bar/Pull-up/etc.) — this test proves an ordinary
        // coherent couplet validates cleanly; Rule D's own real behavior
        // for tracked movements is proven separately above.
        let pushUp = Exercise(canonicalName: "Push-up", modality: .functionalFitness, equipment: "bodyweight", movementPattern: "push", movementFunctions: [.gymnasticsPush], functionalModality: .gymnastics)
        context.insert(pushUp)
        let couplet = [
            FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200),
            FunctionalFitnessCompositionValidator.MovementInput(exercise: pushUp, reps: 8),
        ]
        let result = FunctionalFitnessCompositionValidator.validate(
            format: .roundsForTime(rounds: 5, capSeconds: nil), stimulus: baseStimulus(domain: .medium), movements: couplet, performanceProfile: nil
        )
        XCTAssertEqual(result, .valid(magnitude: .moderate))

        let sustainedRun = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), durationSeconds: 1800)]
        let sustainedResult = FunctionalFitnessCompositionValidator.validate(
            format: .forTime(capSeconds: 1800), stimulus: baseStimulus(domain: .long), movements: sustainedRun, performanceProfile: nil
        )
        XCTAssertEqual(sustainedResult, .valid(magnitude: .trivial))
    }

    // MARK: - Section 13: recomposer

    func testRecomposer_QuantityRecompositionFixesRuleAAndRevalidates() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), distanceMeters: 200)]
        let outcome = FunctionalFitnessCompositionRecomposer.recompose(
            format: .forTime(capSeconds: 1200), stimulus: baseStimulus(domain: .long), movements: movements, performanceProfile: nil
        )
        guard case .recomposed(let recomposedMovements, let magnitude) = outcome else {
            return XCTFail("expected a successful quantity recomposition, got \(outcome)")
        }
        XCTAssertEqual(magnitude, .trivial)
        XCTAssertEqual(recomposedMovements.first?.durationSeconds, FunctionalFitnessMovementTargetRule.sustainedAerobicDurationSeconds)
        XCTAssertNil(recomposedMovements.first?.distanceMeters, "the offending fixed distance must be cleared, never left alongside the new duration")
    }

    func testRecomposer_ReturnsUnsupportedForRulesItCannotFix() {
        let (deadlift, tier) = loadedMovement("Deadlift", tier: .heavy)
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: deadlift, reps: 5, loadGuidanceTier: tier)]
        let outcome = FunctionalFitnessCompositionRecomposer.recompose(
            format: .amrap(capSeconds: 600), stimulus: baseStimulus(domain: .medium), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(outcome, .unsupported(reasonCode: .amrapUnitIncompatibleWithStimulus, offendingDimension: .amrapRepeatableUnitCompatibility), "Rule F requires movement/format reselection this recomposer honestly does not attempt — never a silently-materialized invalid fallback")
    }

    func testRecomposer_ReturnsUnchangedForAlreadyValidCompositions() {
        let movements = [FunctionalFitnessCompositionValidator.MovementInput(exercise: monostructural(), durationSeconds: 1800)]
        let outcome = FunctionalFitnessCompositionRecomposer.recompose(
            format: .forTime(capSeconds: 1800), stimulus: baseStimulus(domain: .long), movements: movements, performanceProfile: nil
        )
        XCTAssertEqual(outcome, .unchanged(magnitude: .trivial))
    }
}
