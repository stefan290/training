import Foundation
import SwiftData

/// Strength Source Content V1: the small, narrowly-scoped mechanism that
/// fills in a `RepPrescriptionKind.priorSlotActualResultRelative` row's
/// real rep targets once the slot it's defined relative to has actually
/// been performed this week — Family E's Friday-Legs2 backoff ("1/2
/// Tuesday's") is the one recovered case this exists for.
///
/// **Why this can't happen at week-materialization time**: `StrengthMaterializer
/// .materializeWeek` builds every day of a week in one call, before any of
/// that week's own sessions have been executed — the referenced slot
/// (Tuesday) genuinely has no logged result yet when Friday's own
/// `SetPrescription`s are first created (`StrengthProgressionEngine
/// .resolveRepGoal`'s own doc comment). This use case is the deferred,
/// later resolution step: called once a session completes
/// (`CompleteSessionUseCase.complete`), it looks for any NOT-YET-EXECUTED
/// sibling row in the SAME `ProgramInstance` whose rep goal depends on a
/// slot that might now have a fresh completed result, and fills in the
/// real target — never touching the referenced slot's own completed,
/// historical `SetResult`s/`SetPrescription`s (CLAUDE.md rule 20 protects
/// already-logged results; a not-yet-executed sibling being resolved for
/// the first time is not "historical state").
///
/// **Idempotent** (mirrors `CompleteSessionUseCase.complete`'s own
/// contract): only ever touches a `SetPrescription` whose `repRangeLow` is
/// still `nil` — a row already resolved (from an earlier call) is never
/// re-touched, so calling this multiple times (e.g. completing several
/// sessions in the same week) is always safe.
enum PriorSlotActualResultRepGoalBackfillUseCase {
    static func backfillPendingRepGoals(in instance: ProgramInstance, modelContext: ModelContext) {
        for session in instance.sessions {
            for block in session.orderedBlocks {
                for prescription in block.orderedPrescriptions {
                    guard let template = prescription.sourcePrescriptionTemplate,
                          let referenceSlot = template.actualResultReferenceSlot else { continue }
                    let pendingSets = prescription.orderedSetPrescriptions.filter { $0.repRangeLow == nil }
                    guard !pendingSets.isEmpty else { continue }

                    let result = ActualResultRelativeRepGoalResolver.resolvedRepTargets(
                        referenceSlot: referenceSlot,
                        requiredSetCount: prescription.orderedSetPrescriptions.count,
                        in: instance
                    )
                    prescription.appliedRepGoalReasonCode = result.reasonCode
                    guard let targets = result.targets, targets.count == prescription.orderedSetPrescriptions.count else { continue }

                    for (index, setPrescription) in prescription.orderedSetPrescriptions.enumerated() {
                        guard setPrescription.repRangeLow == nil else { continue }
                        setPrescription.repRangeLow = targets[index]
                        setPrescription.repRangeHigh = targets[index]
                    }
                }
            }
        }
        try? modelContext.save()
    }
}
