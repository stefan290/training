import Foundation

/// MUSCLE + 5FF FINAL CLOSURE, Section 13 (project-owner decision):
/// deterministic recomposition on an invalid
/// `FunctionalFitnessCompositionValidator` result — never materializes a
/// still-invalid composition, never guesses.
///
/// **Honest scope note.** This recomposer performs exactly one class of
/// deterministic fix it can make with full confidence and no new inputs:
/// QUANTITY recomposition — converting an offending fixed-distance/
/// calorie monostructural movement (Rules A/B) to the real
/// SUSTAINED_AEROBIC duration target Section 9 already establishes as
/// authoritative for `.long` domain. It does NOT perform movement
/// reselection or format reselection, because doing either safely
/// requires a real candidate-exercise pool and a real alternate-format
/// policy — neither of which this pure validator/recomposer pair owns
/// (that authority lives with `FunctionalFitnessMaterializer`'s own
/// selection step). Rather than fabricate a replacement exercise or
/// guess a different format here, an invalid composition this
/// recomposer cannot fix via quantity alone returns `.unsupported` — the
/// exact typed, non-silent outcome Section 13 requires ("never
/// materializing an invalid fallback"). Wiring a full movement/format
/// reselection ladder into real materialization is real, disclosed,
/// unstarted follow-up work, not something this type claims to do.
enum FunctionalFitnessCompositionRecompositionOutcome: Equatable {
    case recomposed(movements: [FunctionalFitnessCompositionValidator.MovementInput], magnitude: FunctionalFitnessCompositionMagnitude)
    case unchanged(magnitude: FunctionalFitnessCompositionMagnitude)
    case unsupported(reasonCode: FunctionalFitnessCompositionReasonCode, offendingDimension: FunctionalFitnessCompositionDimension)
}

enum FunctionalFitnessCompositionRecomposer {
    static func recompose(
        format: WorkoutFormat,
        stimulus: Stimulus,
        movements: [FunctionalFitnessCompositionValidator.MovementInput],
        performanceProfile: PerformanceProfile?
    ) -> FunctionalFitnessCompositionRecompositionOutcome {
        let initial = FunctionalFitnessCompositionValidator.validate(
            format: format, stimulus: stimulus, movements: movements, performanceProfile: performanceProfile
        )
        guard case .invalid(let reasonCode, let offendingDimension) = initial else {
            guard case .valid(let magnitude) = initial else {
                // Unreachable — `validate` only ever returns `.valid`/`.invalid`.
                return .unsupported(reasonCode: .noExecutableWorkPackage, offendingDimension: .executableWorkPackage)
            }
            return .unchanged(magnitude: magnitude)
        }

        // Quantity recomposition: the one deterministic fix available
        // without a candidate exercise pool — retarget an offending
        // fixed-distance/calorie monostructural movement to a real
        // SUSTAINED_AEROBIC duration instead (Rules A/B only).
        if reasonCode == .longDurationForTimeTrivialCyclicalEffort || reasonCode == .sustainedAerobicTinyFixedQuantity {
            let recomposedMovements = movements.map { movement -> FunctionalFitnessCompositionValidator.MovementInput in
                guard movement.exercise?.movementFunctions.contains(.monostructural) == true,
                      movement.durationSeconds == nil,
                      movement.distanceMeters != nil || movement.calories != nil
                else { return movement }
                var fixed = movement
                fixed.distanceMeters = nil
                fixed.calories = nil
                fixed.durationSeconds = FunctionalFitnessMovementTargetRule.sustainedAerobicDurationSeconds
                return fixed
            }
            let revalidated = FunctionalFitnessCompositionValidator.validate(
                format: format, stimulus: stimulus, movements: recomposedMovements, performanceProfile: performanceProfile
            )
            switch revalidated {
            case .valid(let magnitude):
                return .recomposed(movements: recomposedMovements, magnitude: magnitude)
            case .invalid(let stillReasonCode, let stillOffendingDimension):
                // Quantity recomposition alone did not resolve it — never
                // materialize the still-invalid result.
                return .unsupported(reasonCode: stillReasonCode, offendingDimension: stillOffendingDimension)
            }
        }

        // Rules C/D/E/F each require re-selecting a different concrete
        // exercise or a different format — genuinely out of this
        // recomposer's scope (see this type's own doc comment). Honest,
        // typed `.unsupported`, never a silently-materialized invalid
        // fallback.
        return .unsupported(reasonCode: reasonCode, offendingDimension: offendingDimension)
    }
}
