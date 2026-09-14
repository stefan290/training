import Foundation
import SwiftData
import Observation

/// Drives Strength/Hypertrophy/Accessory execution for one `WorkoutBlock`,
/// one movement (`ExercisePrescription`) at a time — `STRENGTH_EXECUTION_
/// FLOW.md`. Reused as-is for Powerlifting (Part G): nothing here branches
/// on programming methodology, only on the same materialized
/// prescription/result shapes every strength movement already has.
@Observable
final class StrengthExecutionViewModel {
    let block: WorkoutBlock
    private(set) var movementIndex: Int
    /// Captured once when a movement loads — what the user did last time,
    /// never recomputed as new sets are logged this same visit (a "you
    /// just did this a second ago" previous-performance line would be
    /// useless and confusing).
    private(set) var previousResults: [SetResult] = []

    /// Stage 6C: resumes at the first not-yet-complete movement rather
    /// than always index 0 — this is re-derived from persisted
    /// prescription/result state every time the view model is created
    /// (fresh app launch included), never a separately persisted
    /// "current exercise" flag (Part H/Y: completed exercises stay
    /// completed and logically resumable without redundant state).
    init(block: WorkoutBlock) {
        self.block = block
        let ordered = block.orderedPrescriptions
        self.movementIndex = ordered.firstIndex(where: { !StrengthExecutionViewModel.isComplete($0) }) ?? max(0, ordered.count - 1)
    }

    /// Canonical exercise order — `ExercisePrescription.sortIndex` via
    /// `WorkoutBlock.orderedPrescriptions`, never any transient SwiftUI
    /// ordering (Part G).
    var movements: [ExercisePrescription] { block.orderedPrescriptions }
    var movementCount: Int { movements.count }

    var currentMovement: ExercisePrescription? {
        movements.indices.contains(movementIndex) ? movements[movementIndex] : nil
    }

    var currentSetIndex: Int { currentMovement?.loggedSetResults.count ?? 0 }

    var currentSetPrescription: SetPrescription? {
        guard let movement = currentMovement else { return nil }
        let ordered = movement.orderedSetPrescriptions
        return ordered.indices.contains(currentSetIndex) ? ordered[currentSetIndex] : nil
    }

    /// Stage 10R.5, D-10R5-18: the weight the execution UI should
    /// actually show/prefill — the source's own untouched
    /// `SetPrescription.targetWeight` in SOURCE mode or for any exposure
    /// `LoadFirstOverlayEngine` doesn't apply to, or the frozen/computed
    /// `LoadFirstOverlayEngine` recommendation once LOAD_FOCUSED mode is
    /// active for an eligible `.rmBased` 3-Day-Full-Body exposure
    /// (D-10R5-20 — never silently activated elsewhere). Computed and
    /// frozen onto `ExercisePrescription.loadOverlayRecommendedWeight`
    /// the FIRST time this is read for a given exposure (D-10R5-19 — a
    /// completed exposure's provenance is never subject to later
    /// recomputation drift); every subsequent read of the same exposure
    /// simply returns the already-frozen value. Never mutates
    /// `SetPrescription.targetWeight` itself.
    func effectiveTargetWeight(modelContext: ModelContext) -> Double? {
        guard let movement = currentMovement, let setPrescription = currentSetPrescription else { return nil }
        guard let sourceWeight = setPrescription.targetWeight else { return nil }

        if let frozen = movement.loadOverlayRecommendedWeight { return frozen }

        guard let instance = movement.workoutBlock?.session?.programInstance else { return sourceWeight }
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let style = instance.effectiveProgressionStyle(userProfile: users.first?.profile)
        guard style == .loadFocused else { return sourceWeight }
        guard LoadFirstEligibility.isEligible(movement) else { return sourceWeight }
        guard let exercise = movement.exercise else { return sourceWeight }

        let isDeload = movement.appliedLoadReasonCode.map { LoadFirstOverlayEngine.deloadReasonCodes.contains($0) } ?? false
        let exposures = LoadFirstExposureResolver.recentEligibleExposures(for: exercise, in: instance, excluding: movement, limit: 2)
        let increment = users.first?.profile?.equipmentIncrements[exercise.equipment] ?? 2.5

        let recommendation = LoadFirstOverlayEngine.recommend(
            sourceWeight: sourceWeight,
            previousEffectiveWeight: exposures.first?.effectiveWeightUsed,
            isDeloadWeek: isDeload,
            recentEligibleExposureSurpluses: exposures.map(\.setSurpluses),
            equipmentIncrement: increment
        )
        movement.loadOverlayRecommendedWeight = recommendation.finalWeight
        movement.appliedLoadOverlayReasonCode = recommendation.reasonCode
        try? modelContext.save()
        return recommendation.finalWeight
    }

    /// Deterministic from authoritative persisted state alone (Part I):
    /// every required `SetPrescription` has a logged `SetResult`. No
    /// separate "ExerciseCompleted" entity — this is always recomputed,
    /// never cached.
    static func isComplete(_ movement: ExercisePrescription) -> Bool {
        !movement.orderedSetPrescriptions.isEmpty
            && movement.loggedSetResults.count >= movement.orderedSetPrescriptions.count
    }

    var isMovementComplete: Bool {
        guard let movement = currentMovement else { return true }
        return StrengthExecutionViewModel.isComplete(movement)
    }

    var completedMovementCount: Int { movements.filter(StrengthExecutionViewModel.isComplete).count }

    /// Every prescribed movement satisfied — never true for an empty
    /// block (Part J: completing exercise 1 of 5 must never complete the
    /// block; a block with zero movements has nothing to be "complete").
    var isBlockComplete: Bool {
        !movements.isEmpty && movements.allSatisfy(StrengthExecutionViewModel.isComplete)
    }

    // MARK: - Dogfood Round 1 (Finding 1): in-session calibration

    /// `true` only when the CURRENT movement's prescription was left
    /// honestly unresolved at materialization time because its required
    /// source RM calibration didn't exist yet — never true for a
    /// genuinely no-load prescription (`.none`) or a Hypertrophy V2
    /// double-progression slot, which never carries this reason code.
    var currentMovementNeedsCalibration: Bool {
        currentMovement?.appliedLoadReasonCode == .calibrationRequired
    }

    /// The exact `(exercise, rmType)` this movement is awaiting — read
    /// directly from the same `PrescriptionTemplate.rules.loadRule` the
    /// materializer itself used, never guessed. `nil` whenever
    /// `currentMovementNeedsCalibration` is false.
    var currentMovementCalibrationRequirement: (exercise: Exercise, rmType: RMType)? {
        guard currentMovementNeedsCalibration, let movement = currentMovement, let exercise = movement.exercise else { return nil }
        guard let loadRule = movement.sourcePrescriptionTemplate?.rules?.loadRule, case .rmBased(let payload) = loadRule else { return nil }
        return (exercise, payload.rmType)
    }

    /// Records the athlete's real, directly-entered starting weight for
    /// this movement and resolves every already-materialized prescription
    /// this week that depended on it — never a fabricated placeholder,
    /// never a silent estimate, and never a second formula: this is the
    /// exact same `StrengthProgressionEngine.resolveWeight` call the
    /// materializer itself uses, via
    /// `ResolveCalibrationDependentPrescriptionsUseCase`. Returns whether
    /// it actually resolved anything, so the caller knows whether to
    /// refresh its own cached display state.
    @discardableResult
    func submitCalibration(kilograms: Double, modelContext: ModelContext) -> Bool {
        guard kilograms > 0, let requirement = currentMovementCalibrationRequirement,
              let instance = currentMovement?.workoutBlock?.session?.programInstance
        else { return false }
        do {
            // Dogfood Round 1 — Final Close (Finding 1 correction): the
            // real per-exercise equipment/increment authority
            // (`EquipmentProfile.resolved(for:userProfile:)`), never a
            // blanket barbell assumption — resolved per prescription
            // inside the use case itself from each slot's own real
            // `Exercise`, using this athlete's own real
            // `UserProfile.equipmentIncrements` where a preference exists.
            let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
            try ResolveCalibrationDependentPrescriptionsUseCase.resolve(
                exercise: requirement.exercise, rmType: requirement.rmType, kilograms: kilograms, instance: instance,
                userProfile: users.first?.profile,
                modelContext: modelContext
            )
            return true
        } catch {
            return false
        }
    }

    var hasPreviousMovement: Bool { movementIndex > 0 }
    var hasNextMovement: Bool { movementIndex + 1 < movements.count }

    var nextMovementName: String? {
        hasNextMovement ? movements[movementIndex + 1].exercise?.canonicalName : nil
    }

    /// Inspecting an earlier/later exercise never corrupts completion
    /// state (Part G) — this only moves a transient view index; nothing
    /// here mutates any persisted status.
    func goToNextMovement(modelContext: ModelContext) {
        guard hasNextMovement else { return }
        movementIndex += 1
        loadPreviousPerformance(modelContext: modelContext)
    }

    func goToPreviousMovement(modelContext: ModelContext) {
        guard hasPreviousMovement else { return }
        movementIndex -= 1
        loadPreviousPerformance(modelContext: modelContext)
    }

    func loadPreviousPerformance(modelContext: ModelContext) {
        guard let exercise = currentMovement?.exercise else {
            previousResults = []
            return
        }
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let profile = users.first?.performanceProfile?.profile(for: exercise) else {
            previousResults = []
            return
        }
        previousResults = Array(profile.orderedSetResults.suffix(3))
    }

    /// Logs the current set and returns a display-ready highlight for the
    /// eventual completion screen to collect (`CompletionSummary`'s
    /// caller-accumulated `highlights`) — `nil` if nothing could be
    /// logged (no current movement/set, or no user/performance profile
    /// yet seeded).
    @discardableResult
    func logCurrentSet(weight: Double, reps: Int, actualRir: Int?, modelContext: ModelContext) -> LoggedResultHighlight? {
        guard let movement = currentMovement, let exercise = movement.exercise else { return nil }
        let setPrescription = currentSetPrescription
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        guard let performanceProfile = users.first?.performanceProfile else { return nil }
        let prBand = setPrescription.map { "\($0.repRangeLow)-\($0.repRangeHigh)" }

        guard let outcome = try? LogSetUseCase.logSet(
            setIndex: currentSetIndex,
            weight: weight,
            reps: reps,
            targetRir: setPrescription?.targetRir,
            actualRir: actualRir,
            prBand: prBand,
            scoringDirection: .higherIsBetter,
            context: .rx,
            setPrescription: setPrescription,
            exercisePrescription: movement,
            exercise: exercise,
            performanceProfile: performanceProfile,
            completedAt: Date(),
            modelContext: modelContext
        ) else { return nil }

        // Part J: derived completion and persisted state must agree —
        // the moment every movement's required sets are all logged, the
        // block itself transitions, automatically, to `.completed`.
        // Never left "In Progress" indefinitely waiting for a separate
        // confirmation the user has no way to give.
        if isBlockComplete {
            try? CompleteBlockUseCase.complete(block, context: .full, modelContext: modelContext)
        }

        return LoggedResultHighlight(
            label: exercise.canonicalName,
            value: "\(weight.formattedWeight) x \(reps)",
            isPersonalRecord: outcome.result.isPersonalRecord,
            isFirstEverEntry: outcome.isFirstEverEntry
        )
    }
}

extension Double {
    /// Trims a trailing `.0` for a whole-number weight (e.g. `60` not
    /// `60.0`) while still showing a fractional plate load (e.g. `62.5`).
    var formattedWeight: String {
        truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(format: "%.1f", self)
    }
}
