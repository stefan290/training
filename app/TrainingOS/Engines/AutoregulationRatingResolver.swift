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

    /// Stage 7 (Tactical Planning Orchestration): week 0's own resolved
    /// weight for this template — `StrengthProgressionEngine.resolveWeight`'s
    /// own contract requires exactly this value for every later week's
    /// multiplier ("the multiplier always applies to the resolved Week 1
    /// value, never a recomputation from the raw RM"), never the
    /// immediately-previous week's own resolved value. `nil` only when
    /// week 0 itself never resolved a weight (e.g. `.calibrationRequired`
    /// at week 0, or genuinely not yet materialized).
    static func weekZeroResolvedWeight(for template: PrescriptionTemplate, in instance: ProgramInstance) -> Double? {
        let candidates = instance.sessions
            .flatMap { $0.orderedBlocks }
            .flatMap { $0.orderedPrescriptions }
            .filter { $0.sourcePrescriptionTemplate?.id == template.id }

        let earliest = candidates.min { lhs, rhs in
            materializedDate(of: lhs) < materializedDate(of: rhs)
        }
        return earliest?.orderedSetPrescriptions.first?.targetWeight
    }

    private static func materializedDate(of prescription: ExercisePrescription) -> Date {
        prescription.workoutBlock?.session?.day?.date ?? .distantFuture
    }

    /// Stage 10R.1 Slice 1B fix: a prescription whose session has actually
    /// completed (`completedAt != nil`) always outranks one that hasn't,
    /// regardless of either's `completionDate` fallback. Discovered while
    /// implementing the real cross-day source pairing web: within one
    /// `materializeWeek(weekIndex: N)` call, an earlier-processed day's own
    /// fresh week-N prescription (not yet completed, but already carrying
    /// a real `session.day.date`) could otherwise out-rank an actually-
    /// completed WEEK N-1 prescription from a later-processed day —
    /// because `completionDate`'s fallback (`session?.day?.date`) made the
    /// brand-new, uncompleted session look "more recent" than the
    /// genuinely completed prior one. This never surfaced before Slice 1B
    /// because every pre-existing pairing (Family A/B/C's
    /// primary<->paired-accessory, Stage 10B.6's self-pairing) was always
    /// resolved same-day or same-slot, where the rating source's own fresh
    /// prescription for the current week is never created before the
    /// reader's own is. A completed candidate is preferred outright rather
    /// than filtered against an uncompleted one (not simply excluding
    /// uncompleted candidates) so the pre-existing, intentional case of a
    /// rating recorded before the session is ever formally completed
    /// (`HypertrophyFeedbackTests` fixtures) still resolves correctly when
    /// it is the only candidate.
    private static func mostRecentlyCompletedPrescription(
        for template: PrescriptionTemplate, in instance: ProgramInstance
    ) -> ExercisePrescription? {
        let candidates = instance.sessions
            .flatMap { $0.orderedBlocks }
            .flatMap { $0.orderedPrescriptions }
            .filter { $0.sourcePrescriptionTemplate?.id == template.id }

        return candidates.max { lhs, rhs in
            let lhsCompleted = lhs.workoutBlock?.session?.completedAt != nil
            let rhsCompleted = rhs.workoutBlock?.session?.completedAt != nil
            if lhsCompleted != rhsCompleted {
                return rhsCompleted
            }
            return completionDate(of: lhs) < completionDate(of: rhs)
        }
    }

    private static func completionDate(of prescription: ExercisePrescription) -> Date {
        let session = prescription.workoutBlock?.session
        return session?.completedAt ?? session?.day?.date ?? .distantPast
    }
}
