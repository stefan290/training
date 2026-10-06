import Foundation
import SwiftData

/// FINAL DIAGNOSTIC CLOSURE — Section A-C: a DEBUG/DOGFOOD-ONLY runtime
/// trace dumper. Gated behind an explicit launch argument
/// (`-FFDogfoodTrace`), so every real athlete launch (which never passes
/// this argument) is completely unaffected — zero behavior change, purely
/// additive read-only serialization of already-materialized, already-
/// persisted domain objects.
///
/// Called from `StrategicPlanSelectionViewModel.acceptAndStart` — the
/// same real call site the "Accept & Start Training" button already
/// invokes — immediately after `StartPhaseUseCase.start` has materialized
/// the real Sessions/Blocks/Prescriptions and `modelContext.save()` has
/// persisted them. This is NEVER a second/separate materialization run:
/// it only reads back what was just written, via the exact same
/// `phase.programInstances -> .sessions -> .orderedBlocks ->
/// .exercisePrescriptions/.functionalFitnessPrescription` relationship
/// graph the UI itself renders from.
enum DogfoodTraceDump {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-FFDogfoodTrace")
    }

    /// Writes `dogfood-runtime-trace.json` to the app's real Documents
    /// directory (readable from the host via `simctl get_app_container`
    /// since this is a Simulator run, never a production distribution
    /// path) with a fresh, unique `dogfoodRunID` for every dump — the
    /// exact correlation key the XCUITest harness compares against the
    /// UI hierarchy it captures in the SAME run.
    static func dump(phase: TrainingPhase, performanceProfile: PerformanceProfile?) {
        guard isEnabled else { return }
        let runID = UUID().uuidString
        var sessionsJSON: [[String: Any]] = []

        let allSessions = phase.programInstances.flatMap(\.sessions)
        let ordered = allSessions.sorted { (lhs, rhs) in
            (lhs.day?.date ?? .distantFuture) < (rhs.day?.date ?? .distantFuture)
        }

        for (index, session) in ordered.enumerated() {
            var blocksJSON: [[String: Any]] = []
            for block in session.orderedBlocks {
                var blockDict: [String: Any] = [
                    "canonicalBlockType": String(describing: block.type),
                    "status": String(describing: block.status),
                    "sortIndex": block.sortIndex,
                    // MUSCLE + 5FF FINAL CLOSURE, Section 20: the real,
                    // truthful athlete-facing purpose/label this block
                    // renders as — the SAME production call
                    // `WeekView`/`SessionDetailView`/etc. already make
                    // (Section 16's own fix), never re-derived
                    // differently here.
                    "canonicalBlockPurpose": BlockPresentation.functionalFitnessAwareBlockLabel(for: block),
                    "renderedBlockLabel": BlockPresentation.functionalFitnessAwareBlockLabel(for: block)
                ]

                // STRENGTH/resistance-role exercises.
                var exercisesJSON: [[String: Any]] = []
                for ep in block.exercisePrescriptions.sorted(by: { $0.sortIndex < $1.sortIndex }) {
                    var exDict: [String: Any] = [
                        "exerciseID": ep.exercise?.id.uuidString ?? "nil",
                        "exerciseName": ep.exercise?.canonicalName ?? "nil",
                        "movementFunctions": (ep.exercise?.movementFunctions ?? []).map { String(describing: $0) },
                        "appliedLoadReasonCode": ep.appliedLoadReasonCode.map { String(describing: $0) } ?? "nil",
                        "appliedRepGoalReasonCode": ep.appliedRepGoalReasonCode.map { String(describing: $0) } ?? "nil",
                        // Section 20: the real, already-persisted source
                        // slot this exercise resolved from — the exact
                        // trace-to-source link `ExerciseSlot`'s own
                        // documented "resolved to a concrete Exercise"
                        // contract already establishes; never re-derived
                        // or guessed here.
                        "sourceExerciseSlotName": ep.sourceExerciseSlot?.name ?? "nil"
                    ]
                    var setsJSON: [[String: Any]] = []
                    for sp in ep.orderedSetPrescriptions {
                        setsJSON.append([
                            "isWarmup": sp.isWarmup,
                            "repRangeLow": sp.repRangeLow as Any,
                            "repRangeHigh": sp.repRangeHigh as Any,
                            "targetRir": sp.targetRir as Any,
                            "targetRirHigh": sp.targetRirHigh as Any,
                            "targetWeight": sp.targetWeight as Any,
                            "targetDistanceMeters": sp.targetDistanceMeters as Any,
                            "targetDurationSeconds": sp.targetDurationSeconds as Any
                        ])
                    }
                    exDict["sets"] = setsJSON
                    // Real per-athlete capability state, actually
                    // consulted at THIS materialization — never
                    // artificially populated if none exists.
                    if let exercise = ep.exercise, let profile = performanceProfile,
                       let capability = profile.movementCapability(for: exercise) {
                        exDict["movementCapability"] = [
                            "proficiency": String(describing: capability.proficiency),
                            "capacityType": capability.capacityType.map { String(describing: $0) } ?? "nil",
                            "capacityValue": capability.capacityValue as Any
                        ]
                    } else {
                        exDict["movementCapability"] = "no MovementCapabilityProfile row for this exercise"
                    }
                    exercisesJSON.append(exDict)
                }
                blockDict["strengthExercises"] = exercisesJSON

                // FUNCTIONAL FITNESS / conditioning role.
                if let ff = block.functionalFitnessPrescription {
                    var ffDict: [String: Any] = [
                        "sessionFamily": ff.sessionFamily.map { String(describing: $0) } ?? "nil",
                        "archetype": String(describing: ff.archetype),
                        "format": String(describing: ff.format),
                        "workoutFormatKind": String(describing: ff.workoutFormatKind),
                        "workoutFormatCapSeconds": ff.workoutFormatCapSeconds as Any,
                        "workoutFormatRounds": ff.workoutFormatRounds as Any,
                        "workoutFormatWorkSeconds": ff.workoutFormatWorkSeconds as Any,
                        "workoutFormatRestSeconds": ff.workoutFormatRestSeconds as Any,
                        "workoutFormatCount": ff.workoutFormatCount as Any,
                        "stimulus.targetDurationDomain": String(describing: ff.stimulus.targetDurationDomain),
                        "stimulus.scoreType": String(describing: ff.stimulus.scoreType),
                        "stimulus.systemicDemand": String(describing: ff.stimulus.systemicDemand),
                        "stimulus.movementFunctions": ff.stimulus.movementFunctions.map { String(describing: $0) }
                    ]
                    // MUSCLE + 5FF FINAL CLOSURE, Section 20: a real,
                    // truthful re-derivation of
                    // `FunctionalFitnessCompositionValidator`'s own typed
                    // result against this block's ALREADY-PERSISTED,
                    // ALREADY-MATERIALIZED composition — never a second,
                    // divergent validation, the exact same pure function
                    // real materialization itself calls.
                    let compositionInputs = ff.orderedMovements.map { movement in
                        FunctionalFitnessCompositionValidator.MovementInput(
                            exercise: movement.exercise, reps: movement.reps, distanceMeters: movement.distanceMeters,
                            durationSeconds: movement.durationSeconds, calories: movement.calories, loadGuidanceTier: movement.relativeLoadTier
                        )
                    }
                    let compositionResult = FunctionalFitnessCompositionValidator.validate(
                        format: ff.format, stimulus: ff.stimulus, movements: compositionInputs, performanceProfile: performanceProfile
                    )
                    switch compositionResult {
                    case .valid(let magnitude):
                        ffDict["compositionValidationResult"] = "valid"
                        ffDict["compositionMagnitude"] = String(describing: magnitude)
                    case .invalid(let reasonCode, let offendingDimension):
                        ffDict["compositionValidationResult"] = "invalid"
                        ffDict["compositionValidationReasonCode"] = String(describing: reasonCode)
                        ffDict["compositionValidationOffendingDimension"] = String(describing: offendingDimension)
                    }
                    var movementsJSON: [[String: Any]] = []
                    for movement in ff.orderedMovements {
                        var mDict: [String: Any] = [
                            "exerciseID": movement.exercise?.id.uuidString ?? "nil",
                            "exerciseName": movement.exercise?.canonicalName ?? "nil",
                            "movementFunctions": (movement.exercise?.movementFunctions ?? []).map { String(describing: $0) },
                            "measuredDimensions": (movement.exercise?.measuredDimensions ?? []).map { String(describing: $0) },
                            "reps": movement.reps as Any,
                            "distanceMeters": movement.distanceMeters as Any,
                            "durationSeconds": movement.durationSeconds as Any,
                            "calories": movement.calories as Any,
                            "loadKilograms": movement.loadKilograms as Any,
                            "relativeLoadTier": movement.relativeLoadTier.map { String(describing: $0) } ?? "nil",
                            "sourceExerciseSlotName": movement.sourceExerciseSlot?.name ?? "nil"
                        ]
                        if let exercise = movement.exercise, let profile = performanceProfile,
                           let capability = profile.movementCapability(for: exercise) {
                            mDict["movementCapability"] = [
                                "proficiency": String(describing: capability.proficiency),
                                "capacityType": capability.capacityType.map { String(describing: $0) } ?? "nil",
                                "capacityValue": capability.capacityValue as Any
                            ]
                        } else {
                            mDict["movementCapability"] = "no MovementCapabilityProfile row for this exercise"
                        }
                        movementsJSON.append(mDict)
                    }
                    ffDict["movements"] = movementsJSON
                    blockDict["functionalFitnessPrescription"] = ffDict
                }

                blocksJSON.append(blockDict)
            }

            sessionsJSON.append([
                "sessionIndex": index,
                "sessionID": session.id.uuidString,
                "name": session.name,
                "modality": String(describing: session.modality),
                "role": session.role.map { String(describing: $0) } ?? "nil",
                "dayDate": session.day?.date.description ?? "nil",
                "blocks": blocksJSON
            ])
        }

        var payload: [String: Any] = [
            "dogfoodRunID": runID,
            "capturedAt": ISO8601DateFormatter().string(from: Date()),
            "phaseID": phase.id.uuidString,
            "phaseType": String(describing: phase.type),
            "sessions": sessionsJSON
        ]

        // MUSCLE + 5FF FINAL CLOSURE, Section 20: the real, shared
        // weekly muscle-volume ledger's own source contribution and
        // remaining requirement — re-derived (never re-computed
        // differently) from the phase's real, accepted mix via the
        // exact same `MuscleVolumeRequirementCalculator` pure functions
        // production materialization itself calls. `nil` mix (no
        // accepted selection yet) reports honestly, never fabricated.
        if let mix = phase.selectedTrainingMix {
            let sourceContribution = MuscleVolumeRequirementCalculator.sourceContribution(mix: mix)
            let remaining = MuscleVolumeRequirementCalculator.remainingRequirement(sourceContribution: sourceContribution)
            payload["weeklyMuscleRequirementSourceContribution"] = Dictionary(uniqueKeysWithValues: sourceContribution.map { (String(describing: $0.key), $0.value) })
            payload["weeklyMuscleRequirementRemaining"] = Dictionary(uniqueKeysWithValues: remaining.map { (String(describing: $0.key), $0.value) })
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        if let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let url = docsDir.appendingPathComponent("dogfood-runtime-trace.json")
            try? data.write(to: url)
        }
    }
}
