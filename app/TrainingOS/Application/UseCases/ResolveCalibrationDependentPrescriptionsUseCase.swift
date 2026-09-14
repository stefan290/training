import Foundation
import SwiftData

/// Dogfood Round 1 (Finding 1): the "resolve dependent prescriptions once
/// calibration becomes known" half of the deferred/in-session calibration
/// lifecycle. `StartPhaseUseCase` no longer defers materialization for a
/// component with missing source RM calibration — it always materializes,
/// leaving any affected slot honestly unresolved (`SetPrescription
/// .targetWeight == nil`, `ExercisePrescription.appliedLoadReasonCode ==
/// .calibrationRequired`, exactly what `StrengthProgressionEngine
/// .resolveWeight` already produces for this case). Once the athlete
/// enters a real value — via the optional "estimate now" screen or the
/// in-session prompt this checkpoint adds to `StrengthExecutionView` —
/// this is the one place that resolves every already-materialized
/// prescription that was waiting on it.
///
/// Never a second/approximated formula: every recomputation here calls
/// the exact same `StrengthProgressionEngine.resolveWeight` the
/// materializer itself used. Never fabricates a value for a slot this
/// calibration doesn't actually cover — only `.rmBased` slots for this
/// exact `(exercise, rmType)`, and `.linkedToPairedSlot` slots that
/// depend on one of those (resolved via a small fixed-point pass, since a
/// paired slot can itself be another slot's pair).
///
/// Scoped to week 0 of `instance` only — `RollTacticalWindowUseCase
/// .materializeFirstWindow`'s own doc comment: nothing past week 0 is
/// ever materialized ahead of live results, so there is nothing further
/// to backfill yet.
enum ResolveCalibrationDependentPrescriptionsUseCase {
    /// Dogfood Round 1 — Final Close (Finding 1 correction): takes
    /// `userProfile`, never a single pre-built `EquipmentProfile` shared
    /// across every dependent prescription — a paired-slot dependent can
    /// legitimately be a DIFFERENT exercise on different equipment than
    /// the exercise actually being calibrated (e.g. a dumbbell accessory
    /// paired against a barbell main lift), so equipment is resolved
    /// individually, per prescription, from that prescription's own real
    /// `Exercise` (`EquipmentProfile.resolved(for:userProfile:)`) — never
    /// one blanket profile for the whole batch.
    static func resolve(
        exercise: Exercise, rmType: RMType, kilograms: Double,
        instance: ProgramInstance, userProfile: UserProfile?, enteredAt: Date = Date(), modelContext: ModelContext
    ) throws {
        RecordSourceRMCalibrationUseCase.record(
            exercise: exercise, rmType: rmType, kilograms: kilograms, for: instance, enteredAt: enteredAt, modelContext: modelContext
        )
        try modelContext.save()

        let prescriptions = ProgramWeekGrouping.realSessions(in: instance, forWeek: 0)
            .flatMap(\.orderedBlocks).flatMap(\.orderedPrescriptions)

        // Seed with whatever's already resolved (e.g. a sibling exercise
        // resolved at original materialization time, or an earlier
        // calibration this same session already backfilled) so a paired
        // slot that depends on an already-known weight resolves in the
        // very first pass.
        var resolvedWeightsByTemplateID: [UUID: Double] = [:]
        for prescription in prescriptions {
            guard let templateID = prescription.sourcePrescriptionTemplate?.id else { continue }
            guard let weight = prescription.orderedSetPrescriptions.first?.targetWeight else { continue }
            resolvedWeightsByTemplateID[templateID] = weight
        }

        var didResolveAnything = false
        for _ in 0..<max(1, prescriptions.count) {
            var changedThisPass = false
            for prescription in prescriptions {
                guard prescription.appliedLoadReasonCode == .calibrationRequired else { continue }
                guard let template = prescription.sourcePrescriptionTemplate, let rules = template.rules else { continue }
                guard let slotExercise = prescription.exercise else { continue }
                // Resolved per-prescription, from THIS slot's own real
                // exercise — never one blanket profile shared across
                // every dependent prescription (see this type's own doc
                // comment).
                let resolvedEquipmentProfile = EquipmentProfile.resolved(for: slotExercise, userProfile: userProfile)

                let result: (weightKg: Double?, reasonCode: StrengthReasonCode)
                switch rules.loadRule {
                case .rmBased(let payload):
                    guard slotExercise.id == exercise.id, payload.rmType == rmType else { continue }
                    result = StrengthProgressionEngine.resolveWeight(
                        rules: rules, weekIndex: 0, rmKilograms: kilograms,
                        weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: nil, equipmentProfile: resolvedEquipmentProfile
                    )
                case .linkedToPairedSlot:
                    guard let pairedTemplateID = template.pairedSlot?.id,
                          let pairedWeight = resolvedWeightsByTemplateID[pairedTemplateID] else { continue }
                    result = StrengthProgressionEngine.resolveWeight(
                        rules: rules, weekIndex: 0, rmKilograms: nil,
                        weekOneResolvedWeightKg: nil, pairedSlotResolvedWeightKg: pairedWeight, equipmentProfile: resolvedEquipmentProfile
                    )
                case .none, .doubleProgression:
                    continue
                }
                guard let weightKg = result.weightKg else { continue }

                prescription.appliedLoadReasonCode = result.reasonCode
                for setPrescription in prescription.orderedSetPrescriptions {
                    setPrescription.targetWeight = weightKg
                }
                resolvedWeightsByTemplateID[template.id] = weightKg
                changedThisPass = true
                didResolveAnything = true
            }
            if !changedThisPass { break }
        }

        guard didResolveAnything else { return }
        try modelContext.save()
    }
}
