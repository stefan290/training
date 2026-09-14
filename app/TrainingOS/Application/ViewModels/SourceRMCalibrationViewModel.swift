import Foundation
import SwiftData

/// Stage 10R.1C, revised by Dogfood Round 1 (Finding 1): drives the "Set
/// your starting weights" screen — an OPTIONAL, non-blocking early
/// opportunity to supply the literal, source-required RM values
/// `RequiredSourceCalibrationsUseCase` finds missing. Never estimates,
/// converts, or pre-fills a value; every row starts blank.
///
/// **No longer blocks Plan/Session creation.** Before Dogfood Round 1,
/// `StartPhaseUseCase` deferred materializing an entire `.rmBased`
/// component until every required calibration existed, and `RootTabView`
/// blocked the whole app behind this screen in the meantime — so "I'd
/// rather test this properly first" was a lie: choosing it could never
/// actually let the athlete proceed. `StartPhaseUseCase` now always
/// materializes real Sessions immediately, leaving an affected slot's
/// WEIGHT (never its reps/sets) honestly unresolved
/// (`ExercisePrescription.appliedLoadReasonCode == .calibrationRequired`).
/// This screen is now purely the "estimate now" path (per-exercise, at
/// the athlete's option) — the "test in first session" path is
/// `StrengthExecutionView`'s own in-session calibration prompt,
/// completely independent of whether the athlete ever opens this screen
/// at all.
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

    /// Every row has a real, parseable, positive value entered. No longer
    /// gates whether the athlete can proceed (Dogfood Round 1, Finding 1
    /// — this screen is optional and non-blocking now); kept as a simple
    /// "did I fill in everything" signal a caller may still use for its
    /// own display purposes.
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

    /// Dogfood Round 1 (Finding 1): the "estimate now" path — Sessions
    /// already exist by the time this screen can even appear (materialization
    /// is never deferred anymore), so this no longer "starts" anything; it
    /// records whatever the athlete filled in and resolves every dependent
    /// prescription this week that was waiting on it
    /// (`ResolveCalibrationDependentPrescriptionsUseCase`, the exact same
    /// per-exercise mechanism `StrengthExecutionView`'s in-session prompt
    /// uses). Never gated on every row being filled — a row left blank (or
    /// marked "test this properly first") simply stays unresolved until
    /// the athlete reaches that exercise in a real session; this is the
    /// per-exercise independence Finding 1 requires, not an all-or-nothing
    /// gate.
    func completeCalibrationAndStart(modelContext: ModelContext) {
        guard let instance = pendingInstance else { return }
        // Dogfood Round 1 — Final Close (Finding 1 correction): the real
        // per-exercise equipment/increment authority, never a blanket
        // barbell assumption — see `ResolveCalibrationDependentPrescriptionsUseCase`'s
        // own doc comment.
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        for row in rows {
            guard let value = Double(row.enteredText), value > 0 else { continue }
            try? ResolveCalibrationDependentPrescriptionsUseCase.resolve(
                exercise: row.exercise, rmType: row.rmType, kilograms: value,
                instance: instance, userProfile: users.first?.profile, modelContext: modelContext
            )
        }
        pendingInstance = nil
        rows = []
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
