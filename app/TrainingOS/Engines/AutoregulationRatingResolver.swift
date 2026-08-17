import Foundation

/// Resolves the two runtime inputs `StrengthProgressionEngine.resolveSetCount`'s
/// `.autoregulated` case has always required — `previousWeekSetCount` and
/// `autoregulationRating` — from the real materialized execution graph,
/// so a caller materializing week N>0 can supply them via `SlotContext`
/// exactly as the engine's own contract expects
/// (`PROGRAM_LOGIC_SPEC.md` §FAMILY_A/B/C_AUTOREGULATION: "rating(most
/// recently completed paired slot)"). Pure read — never mutates
/// anything, never itself decides a set count.
enum AutoregulationRatingResolver {
    /// The rating collected against whichever materialized
    /// `ExercisePrescription` is `template`'s own `pairedSlot`'s most
    /// recently completed instance — `nil` if there's no paired slot, or
    /// nothing's been rated for it yet (a legitimate "not available"
    /// state, never a guessed value).
    static func rating(for template: PrescriptionTemplate, in instance: ProgramInstance) -> Int? {
        guard let pairedTemplate = template.pairedSlot else { return nil }
        return mostRecentlyCompletedPrescription(for: pairedTemplate, in: instance)?.autoregulationRating
    }

    /// The same slot's own most recent previously-materialized set count
    /// — `weekN-1.sets(sameSlot)` in the source formula.
    static func previousWeekSetCount(for template: PrescriptionTemplate, in instance: ProgramInstance) -> Int? {
        let prescription = mostRecentlyCompletedPrescription(for: template, in: instance)
        guard let prescription, !prescription.orderedSetPrescriptions.isEmpty else { return nil }
        return prescription.orderedSetPrescriptions.count
    }

    private static func mostRecentlyCompletedPrescription(
        for template: PrescriptionTemplate, in instance: ProgramInstance
    ) -> ExercisePrescription? {
        let candidates = instance.sessions
            .flatMap { $0.orderedBlocks }
            .flatMap { $0.orderedPrescriptions }
            .filter { $0.sourcePrescriptionTemplate?.id == template.id }

        return candidates.max { lhs, rhs in
            completionDate(of: lhs) < completionDate(of: rhs)
        }
    }

    private static func completionDate(of prescription: ExercisePrescription) -> Date {
        let session = prescription.workoutBlock?.session
        return session?.completedAt ?? session?.day?.date ?? .distantPast
    }
}
