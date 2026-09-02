import Foundation
import SwiftData

/// Stage 10R.1C: drives the "Set your starting weights" screen — the
/// minimum UI necessary for a real user to supply the literal, source-
/// required RM values `RequiredSourceCalibrationsUseCase` finds missing,
/// before the first tactical window for a `.rmBased` program can
/// materialize. Never estimates, converts, or pre-fills a value; every
/// row starts blank.
@Observable
final class SourceRMCalibrationViewModel {
    struct Row: Identifiable {
        var id: String
        var exercise: Exercise
        var rmType: RMType
        var previousValueKilograms: Double?
        var enteredText: String = ""
        var needsTesting: Bool = false
    }

    private(set) var pendingInstance: ProgramInstance?
    /// Mutated directly by the view's `TextField` bindings (`@Bindable`) —
    /// not `private(set)`, since per-row text entry is exactly the kind of
    /// lightweight, view-local mutation `@Observable`/`@Bindable` exists
    /// for.
    var rows: [Row] = []

    /// Whether there is anything to show at all — the caller (e.g.
    /// `RootTabView`) uses this to decide whether to present the screen
    /// in the first place.
    var hasPendingCalibration: Bool { pendingInstance != nil && !rows.isEmpty }

    /// Every row has a real, parseable, positive value entered — "I need
    /// to test this first" never satisfies this, by design (Decision 2:
    /// "do not start the source program until required calibration is
    /// complete").
    var allSatisfied: Bool {
        !rows.isEmpty && rows.allSatisfy { Double($0.enteredText).map { $0 > 0 } ?? false }
    }

    /// Scans every `.active` `ProgramInstance` for outstanding source RM
    /// calibration requirements and loads the first one found — this app
    /// materializes one primary Hypertrophy/Powerlifting instance per
    /// phase today, so "first" is unambiguous in practice; a future
    /// multi-component phase would need this to surface more than one.
    ///
    /// Also handles the recovery case a real manual-acceptance crash
    /// exposed: calibration can be fully entered and durably saved (each
    /// `RecordSourceRMCalibrationUseCase.record` call saves immediately)
    /// while materialization itself still fails or never ran (e.g. the
    /// app terminated between the two steps). Such an instance has no
    /// outstanding calibration requirement but also no sessions yet —
    /// rather than silently leaving it stuck forever, this retries
    /// materialization right here before concluding nothing is pending.
    /// User-entered calibration is never re-requested to recover from
    /// this state.
    func load(modelContext: ModelContext) {
        let instances = (try? modelContext.fetch(FetchDescriptor<ProgramInstance>())) ?? []
        for instance in instances where instance.status == .active {
            guard let definition = instance.programDefinition else { continue }
            let required = RequiredSourceCalibrationsUseCase.stillRequired(for: definition, instance: instance)
            if !required.isEmpty {
                pendingInstance = instance
                rows = required.map { requirement in
                    let previous = PreviousSourceRMCalibrationUseCase.mostRecentPriorValue(
                        for: requirement.exercise, rmType: requirement.rmType, excluding: instance,
                        ownerUserID: instance.ownerUserID, modelContext: modelContext
                    )
                    return Row(
                        id: "\(requirement.exercise.id.uuidString)-\(requirement.rmType.rawValue)",
                        exercise: requirement.exercise, rmType: requirement.rmType,
                        previousValueKilograms: previous?.kilograms
                    )
                }
                return
            }
            let system = definition.programmingSystem
            if instance.sessions.isEmpty, system == .hypertrophy || system == .powerlifting {
                attemptMaterialization(for: instance, modelContext: modelContext)
            }
        }
        pendingInstance = nil
        rows = []
    }

    func text(for row: Row) -> String { rows.first { $0.id == row.id }?.enteredText ?? "" }

    func setText(_ text: String, for row: Row) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].enteredText = text
        rows[index].needsTesting = false
    }

    /// Decision 2: purely informational — clears any partial entry and
    /// marks the row as "needs testing," which keeps `allSatisfied` false
    /// (the program cannot start until a real value is entered) without
    /// fabricating one.
    func markNeedsTesting(_ row: Row) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        rows[index].needsTesting = true
        rows[index].enteredText = ""
    }

    /// Records every entered value, saves that whole batch in one
    /// explicit transaction, then attempts the one, deferred
    /// materialization for this instance. Never called until
    /// `allSatisfied`.
    ///
    /// **Persistence ordering (a real manual-acceptance crash found this
    /// missing):** every calibration value is recorded AND saved — as one
    /// batch — before materialization is ever attempted, so a failure or
    /// crash during materialization can never erase already-entered RM
    /// values — "user calibration data must not be lost." (An earlier
    /// version saved once per row instead of once per batch; that caused
    /// a *different* regression — spurious scheduling `infeasible`
    /// failures from saving mid-construction of the larger phase-start
    /// object graph — see `RecordSourceRMCalibrationUseCase.record`'s own
    /// doc comment.) `rows`/`pendingInstance` are cleared only once
    /// materialization actually succeeds; if it fails, this screen simply
    /// stays put with the already-saved values still satisfied, and
    /// `load()`'s own recovery path (see its doc comment) will retry
    /// materialization on the next app launch/reappear without ever
    /// re-asking the user for RM values again.
    func completeCalibrationAndStart(modelContext: ModelContext) {
        guard let instance = pendingInstance, allSatisfied else { return }
        for row in rows {
            guard let value = Double(row.enteredText), value > 0 else { continue }
            RecordSourceRMCalibrationUseCase.record(
                exercise: row.exercise, rmType: row.rmType, kilograms: value, for: instance, modelContext: modelContext
            )
        }
        guard (try? modelContext.save()) != nil else { return }
        if attemptMaterialization(for: instance, modelContext: modelContext) {
            pendingInstance = nil
            rows = []
        }
    }

    /// Attempts the deferred `materializeOnceCalibrationComplete` step for
    /// `instance` — shared by `completeCalibrationAndStart` (the first
    /// attempt) and `load()` (the retry path for an instance whose
    /// calibration is already complete but whose materialization
    /// previously failed/never ran). Returns whether it succeeded.
    @discardableResult
    private func attemptMaterialization(for instance: ProgramInstance, modelContext: ModelContext) -> Bool {
        guard
            let phase = instance.phase,
            let component = instance.trainingMixComponents.first,
            let mix = component.trainingMix
        else { return false }
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let performanceProfile = users.first?.performanceProfile
        // No persisted user-availability setting exists yet in this app
        // (a separate, unbuilt feature) — this default matches the same
        // convention already used by `SeedAnnualPlanJourney`/this
        // project's own test fixtures.
        let availability = UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1)
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            trainingEnvironment: users.first?.profile?.defaultTrainingEnvironment
        )

        do {
            try StartPhaseUseCase.materializeOnceCalibrationComplete(
                component: component, instance: instance, phase: phase, mix: mix, asOf: Date(),
                ownerUserID: instance.ownerUserID, performanceProfile: performanceProfile,
                availability: availability, materializationContext: materializationContext, context: modelContext
            )
            return true
        } catch {
            return false
        }
    }
}
