import Foundation

/// The graduated re-entry ladder from FAQ's pain-during-a-rep protocol
/// (`RUNNING_PROGRAMMING_MODEL_R1.md` §13/§14 item 2, R2.9): "stop
/// running immediately... Begin walking again after 1-3 minutes rest, if
/// completely pain free. If completely pain free during walking, try
/// jogging very slowly. If completely pain free while jogging, try
/// jogging slightly faster. If completely pain free during all jogging,
/// attempt the prescribed running pace once more. If pain is present at
/// all during any of the previous steps, cease running or walking
/// immediately, discontinue workout, and seek medical advice."
///
/// **This is an execution safety state, not a medical diagnosis.** No
/// stage here interprets *what* the pain is (the source's own examples —
/// "nagging pain on one side... different from the other side," "painful
/// cracking, popping, snapping, stabbing, tingling, numbness" — are
/// listed only as the trigger condition, never as inputs this type
/// reasons about).
enum RunningPainReentryStage: String, Codable, CaseIterable {
    case stopped
    case walking
    case joggingSlowly
    case joggingSlightlyFaster
    case fullPrescribedPace
    /// Terminal state — "discontinue workout, and seek medical advice
    /// from a physical therapist or orthopedic specialist." No stage
    /// transitions out of this one; a new workout/session is a fresh
    /// re-entry, out of this type's scope.
    case discontinuedSeekMedicalAdvice
}

enum RunningPainResponseEngine {
    /// Pain reported for the first time during a rep — the immediate,
    /// unconditional entry point.
    static func onPainReported() -> RunningPainReentryStage {
        .stopped
    }

    /// One graduated step forward, or an immediate, permanent stop if
    /// pain recurred at the just-attempted stage. "Any recurrence" always
    /// wins over the ladder's own progression, at every stage.
    static func nextStage(current: RunningPainReentryStage, painFreeAtCurrentStage: Bool) -> RunningPainReentryStage {
        guard painFreeAtCurrentStage else { return .discontinuedSeekMedicalAdvice }
        switch current {
        case .stopped: return .walking
        case .walking: return .joggingSlowly
        case .joggingSlowly: return .joggingSlightlyFaster
        case .joggingSlightlyFaster: return .fullPrescribedPace
        case .fullPrescribedPace: return .fullPrescribedPace
        case .discontinuedSeekMedicalAdvice: return .discontinuedSeekMedicalAdvice
        }
    }
}
