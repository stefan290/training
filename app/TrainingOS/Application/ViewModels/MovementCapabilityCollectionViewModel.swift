import Foundation
import SwiftData
import Observation

/// MUSCLE VERTICAL SLICE CONTINUATION, Sections 9-11: the smallest
/// coherent real capability-collection flow — the 3 movements this
/// checkpoint's own dogfood evidence named (Toes-to-Bar, Pull-up,
/// Handstand Push-up), never a full Assessment Week (out of this
/// checkpoint's scope; CLAUDE.md rule 11 — do not silently expand V1
/// scope). Mirrors `TrainingPreferencesViewModel`'s real load/edit/save
/// shape exactly. Reachable any time from Profile (matching the existing
/// "Set your starting weights" precedent's own discoverable, never-
/// blocking philosophy) — never a forced onboarding gate.
@MainActor
@Observable
final class MovementCapabilityCollectionViewModel {
    struct Row: Identifiable {
        let exercise: Exercise
        var isWorkoutReady: Bool
        /// Max unbroken reps — the one real, repeated-dose-relevant
        /// capacity type `TechnicalCapacityDoseAuthority` actually reads
        /// for these 3 movements (`repeatedDoseTrackedNames`).
        var maxUnbrokenReps: Int?
        var id: UUID { exercise.id }
    }

    private(set) var rows: [Row] = []
    private var performanceProfile: PerformanceProfile?
    private(set) var didSave = false

    /// MUSCLE VERTICAL SLICE CONTINUATION, Section 9: exactly the 3
    /// gated movements named in this checkpoint's own dogfood evidence —
    /// real, canonical `ExerciseCatalog` entries, never a hand-typed
    /// string lookup.
    func load(modelContext: ModelContext) {
        didSave = false
        let catalog = ExerciseCatalog.resolveOrInsert(context: modelContext)
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        performanceProfile = users.first?.performanceProfile

        let targets = [catalog.toesToBar, catalog.pullUp, catalog.handstandPushUp]
        rows = targets.map { exercise in
            if let existing = performanceProfile?.movementCapability(for: exercise) {
                return Row(
                    exercise: exercise,
                    isWorkoutReady: existing.proficiency == .workoutReady,
                    maxUnbrokenReps: existing.capacityType == .maxUnbrokenReps ? existing.capacityValue.map(Int.init) : nil
                )
            }
            return Row(exercise: exercise, isWorkoutReady: false, maxUnbrokenReps: nil)
        }
    }

    func setWorkoutReady(_ isReady: Bool, for id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isWorkoutReady = isReady
    }

    func setMaxUnbrokenReps(_ reps: Int?, for id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].maxUnbrokenReps = reps
    }

    /// Section 25 (existing, locked rule — restated, not reinterpreted
    /// here): this is the athlete's own explicit self-report, real,
    /// persisted `CapabilityEvidenceSource.selfReported` evidence — never
    /// auto-promoted from a logged result. A row left NOT workout-ready
    /// with no reps entered persists honestly as `.unknown`/no capacity,
    /// never a guessed default.
    @discardableResult
    func save(modelContext: ModelContext) -> Bool {
        guard let performanceProfile else { return false }
        for row in rows {
            let proficiency: MovementProficiency = row.isWorkoutReady ? .workoutReady : .unknown
            let capacityType: MovementCapacityType? = row.maxUnbrokenReps != nil ? .maxUnbrokenReps : nil
            RecordMovementCapabilityUseCase.record(
                exercise: row.exercise, proficiency: proficiency,
                capacityType: capacityType, capacityValue: row.maxUnbrokenReps.map(Double.init),
                evidenceSource: .selfReported, performanceProfile: performanceProfile, context: modelContext
            )
        }
        do {
            try modelContext.save()
            didSave = true
            return true
        } catch {
            return false
        }
    }
}
