import Foundation

/// Which materialized exercises in a completed Session need the
/// lightweight -1/0/+1 rating `StrengthProgressionEngine.resolveSetCount`'s
/// `.autoregulated` case depends on — never every exercise, only the ones
/// some other slot's next-week set count actually depends on
/// (`template.referencedAsPairedSlotBy`), and only once (never re-asked
/// once already rated). Pure, deterministic, no persistence side effect.
enum HypertrophyFeedbackPrompts {
    static func pending(for session: Session) -> [ExercisePrescription] {
        session.orderedBlocks
            .flatMap { $0.orderedPrescriptions }
            .filter { prescription in
                guard let template = prescription.sourcePrescriptionTemplate else { return false }
                guard !template.referencedAsPairedSlotBy.isEmpty else { return false }
                guard prescription.autoregulationRating == nil else { return false }
                return !prescription.loggedSetResults.isEmpty
            }
    }
}

/// Rating-prompt copy — Part 6/`PROGRAM_LOGIC_SPEC.md` §6.4: "the
/// mechanic (feed a -1/0/+1 into a future set-count formula) is
/// identical; only the label text... differ[s]" per programming system.
/// The persisted rating is always the same generic `Int` regardless of
/// which copy set produced it — never a second decision mechanism.
enum HypertrophyFeedbackCopy {
    struct Option {
        let rating: Int
        let label: String
    }

    /// Family B and Family C both map to `.powerlifting` (there is no
    /// finer-grained persisted distinction) and share Family B's
    /// bar-speed framing here — Family C's own slightly different
    /// difficulty-framing wording is a disclosed simplification, not a
    /// mechanic difference (`STAGE6D_ACCEPTANCE_REPORT.md`).
    static func options(for system: ProgrammingSystemKind?) -> [Option] {
        switch system {
        case .powerlifting:
            return [
                Option(rating: 1, label: "Moved fast and felt light"),
                Option(rating: 0, label: "Moved at a normal pace"),
                Option(rating: -1, label: "Moved slowly and felt heavy"),
            ]
        case .hypertrophy, .steadyState, .interval, .functionalFitness, nil:
            return [
                Option(rating: 1, label: "Wasn't very sore"),
                Option(rating: 0, label: "Noticeably sore, tough but manageable"),
                Option(rating: -1, label: "Very sore"),
            ]
        }
    }

    static func programmingSystem(for prescription: ExercisePrescription) -> ProgrammingSystemKind? {
        prescription.sourcePrescriptionTemplate?
            .workoutBlockTemplate?
            .templateSession?
            .programDefinition?
            .programmingSystem
    }

    /// Stage 6E: the reverse lookup completed history needs — a recorded
    /// `Int` rating back to the exact framed copy the user was actually
    /// shown when they answered, never a second wording table.
    static func label(forRating rating: Int, system: ProgrammingSystemKind?) -> String? {
        options(for: system).first { $0.rating == rating }?.label
    }
}
