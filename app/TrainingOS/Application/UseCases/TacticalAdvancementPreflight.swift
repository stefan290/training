import Foundation

/// Stage 10R.6A/D-10R6-6: a targeted, CHEAP check for predictable,
/// deterministic prerequisites `RollTacticalWindowUseCase.rollForward`
/// would otherwise discover only after it has already started mutating
/// the scratch context (Locked Decision 6). Never a second progression
/// engine, never a second materialization pass — it re-reads the exact
/// same "does this template require history that doesn't exist yet"
/// booleans the real materializers already enforce
/// (`IntervalMaterializationError.previousOutcomeRequired`/
/// `FunctionalFitnessMaterializationError.previousExposureRequired`), one
/// step earlier, so a mixed-modality mix fails fast — before any
/// component (including ones that WOULD have succeeded) is touched —
/// rather than discovering the same failure mid-loop.
///
/// **Deliberately narrow.** Stimulus validation
/// (`FunctionalFitnessMaterializationError.stimulusValidationFailed`)
/// genuinely requires running Stage D/E of the Functional Fitness
/// pipeline — checking it here would be exactly the "simulate the entire
/// materialization process twice" the locked decision forbids. That
/// failure mode is still caught (via the scratch-context discard,
/// `AdvanceTacticalWeekUseCase`'s own atomicity guarantee), just not
/// pre-empted.
enum TacticalAdvancementPreflightError: Error, Equatable {
    /// A Functional Fitness component's next week has at least one block
    /// template requiring recent exposure history to progress, and no
    /// real completed-session history exists yet for that instance.
    case functionalFitnessExposureHistoryUnresolvable(componentID: UUID)
    /// An Interval component's next week has at least one block template
    /// requiring the previous week's actual outcome to progress, and no
    /// real previous-week result can be resolved for that instance.
    case intervalWeekContextUnresolvable(componentID: UUID)
}

enum TacticalAdvancementPreflight {
    /// `nil` means every eligible, non-exhausted, rollForward-managed
    /// component in `mix` has what it needs to materialize its next week
    /// honestly. Read-only — inserts nothing, mutates nothing.
    static func check(mix: TrainingMix) -> TacticalAdvancementPreflightError? {
        for component in mix.orderedComponents {
            guard
                let instance = component.programInstance,
                let definition = instance.programDefinition,
                let system = component.programmingSystem, system != .steadyState,
                !TacticalWeekCompletion.isInstanceExhausted(for: instance)
            else { continue }

            let weekIndex = ProgramWeekGrouping.nextWeekIndex(for: instance)
            guard weekIndex > 0, definition.orderedWeeks.indices.contains(weekIndex) else { continue }
            let blockTemplates = definition.orderedTemplateSessions
                .filter { $0.activeFromWeek <= weekIndex }
                .flatMap(\.orderedBlockTemplates)

            switch system {
            case .functionalFitness:
                let requiresExposure = blockTemplates
                    .compactMap(\.functionalFitnessPrescriptionTemplate)
                    .contains { $0.requiresRecentExposureToProgress }
                guard requiresExposure else { continue }
                if FunctionalFitnessExposureHistoryBuilder.build(fromCompletedSessionsIn: instance).isEmpty {
                    return .functionalFitnessExposureHistoryUnresolvable(componentID: component.id)
                }
            case .interval:
                // Checked per-`WorkoutBlockTemplate`, exactly like
                // `IntervalMaterializer`'s own throw guard — a mix of
                // several block templates where only SOME require prior
                // history must not let one resolvable block mask another,
                // genuinely-unresolvable one.
                let resolver = IntervalWeekContextBuilder.build(instance: instance, weekIndex: weekIndex)
                for blockTemplate in blockTemplates {
                    guard let rules = blockTemplate.intervalPrescriptionTemplate?.progressionRules,
                          rules.requiresSuccessfulCompletionToProgress
                    else { continue }
                    if resolver(blockTemplate).previousOutcome == nil {
                        return .intervalWeekContextUnresolvable(componentID: component.id)
                    }
                }
            case .hypertrophy, .powerlifting, .steadyState:
                continue
            }
        }
        return nil
    }
}
