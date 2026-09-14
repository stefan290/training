import Foundation
import SwiftData

enum StartSessionOnDifferentDayError: Error, Equatable {
    /// The session is already scheduled for today — this use case exists
    /// only for the "override" case; the ordinary `StartSessionUseCase`
    /// already handles today's own sessions.
    case alreadyScheduledForToday
    /// Never moves a session that's already being executed or is done —
    /// this is an override for a still-`.scheduled` session only.
    case notScheduled
}

/// Dogfood Round 1 (Finding 4): "PLAN = RECOMMENDATION, ATHLETE APPROVAL/
/// ACTION = AUTHORITATIVE." Stefan could inspect a session scheduled for
/// a different day but never start it. This lets the athlete execute
/// that SAME session today instead — never a new/duplicated Session,
/// never a second materialization, never a fabricated workout.
///
/// Re-parents the session onto today's real `Day` using the *exact same*
/// mechanism `AcceptScheduleProposalUseCase.accept` already performs for
/// ordinary scheduling (`oldDay.sessions.removeAll` + `findOrCreateDay` +
/// `Day.addSession`) — never a new rescheduling engine, per this
/// checkpoint's explicit "do not build one" scope. The old Day is left
/// behind, empty but not deleted (same nullify-not-cascade discipline
/// `AcceptScheduleProposalUseCase` already relies on) — so the original
/// scheduled slot no longer shows this session sitting there unperformed;
/// it genuinely moved. WorkoutBlock/ExercisePrescription/SetResult/source
/// identity are entirely untouched: this only ever changes which `Day`
/// the same Session row is attached to, then starts it via the existing,
/// unmodified `StartSessionUseCase`. This never touches any other Session
/// in the week — the remaining tactical schedule is left exactly as it
/// was; only ONE session moved.
enum StartSessionOnDifferentDayUseCase {
    /// `ownerUserID` is read from the session's own current `Day` — never
    /// a second, separately-supplied identity that could disagree with
    /// it; a `.scheduled` session materialized through the real
    /// production pipeline always has one.
    @discardableResult
    static func startToday(_ session: Session, asOf: Date, modelContext: ModelContext) throws -> Session {
        guard session.status == .scheduled else { throw StartSessionOnDifferentDayError.notScheduled }
        guard let oldDay = session.day else { throw StartSessionOnDifferentDayError.notScheduled }

        let today = Calendar.current.startOfDay(for: asOf)
        if Calendar.current.isDate(oldDay.date, inSameDayAs: today) {
            throw StartSessionOnDifferentDayError.alreadyScheduledForToday
        }

        oldDay.sessions.removeAll { $0.id == session.id }
        let targetDay = try findOrCreateDay(date: today, ownerUserID: oldDay.ownerUserID, context: modelContext)
        targetDay.addSession(session)
        session.scheduledTime = today

        return try StartSessionUseCase.start(session, asOf: asOf, modelContext: modelContext)
    }

    /// Mirrors `AcceptScheduleProposalUseCase.findOrCreateDay` exactly —
    /// kept as its own private copy rather than exposing that one, so
    /// this checkpoint touches nothing about that already-closed,
    /// already-tested use case.
    private static func findOrCreateDay(date: Date, ownerUserID: UUID, context: ModelContext) throws -> Day {
        let descriptor = FetchDescriptor<Day>(
            predicate: #Predicate { $0.ownerUserID == ownerUserID && $0.date == date }
        )
        if let existing = try context.fetch(descriptor).first {
            return existing
        }
        let day = Day(ownerUserID: ownerUserID, date: date)
        context.insert(day)
        return day
    }
}
