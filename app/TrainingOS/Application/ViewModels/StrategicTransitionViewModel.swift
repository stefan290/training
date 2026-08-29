import Foundation
import SwiftData
import Observation

/// Posted once, only after a successful strategic transition — lets
/// `RootTabView` re-check its app-wide "Set your starting weights" gate
/// (`SourceRMCalibrationViewModel.hasPendingCalibration`) without this
/// ViewModel needing to know anything about tab-level navigation.
extension Notification.Name {
    static let strategicPhaseTransitionCompleted = Notification.Name("strategicPhaseTransitionCompleted")
}

/// Stage 10R.7B: drives the compact "Start Next Phase" summary/action —
/// the one place a strategic transition is actually invoked from the UI.
/// Never reproduces `TransitionPhaseUseCase`'s logic; every write goes
/// through it (D-10R7B-6). Mirrors `PhaseDetailViewModel`'s existing
/// "one deliberate write, guarded, re-derives eligibility itself" shape.
///
/// **Stage 10R.7B-FIX — the product invariant this type exists to
/// guarantee:** what the user reviews IS what gets accepted IS what
/// `TransitionPhaseUseCase` starts. `LongTermPlanner.proposeTrainingMix`
/// is called exactly ONCE per `load` — never again in `startTransition`.
/// This is not merely a style preference: `proposeTrainingMix`'s ranking
/// stage reads `goal.preferences` (real, persisted, mutable state —
/// `LongTermPlanner.rankCandidateMixes`, `ADHERENCE_AWARE_PLANNING.md`
/// §5b's bounded promotion), so a second independent call between preview
/// and acceptance is not provably guaranteed to return the same
/// candidate — it is a real, not merely theoretical, divergence risk.
/// `reviewedMix` is the one resolved candidate this type ever holds;
/// `previewMixSummary`/`previewIncludesCalibrationRequiredSystem` are
/// computed directly FROM it (never independently derived) so they
/// cannot drift out of sync with what `startTransition` actually uses.
@Observable
final class StrategicTransitionViewModel {
    private(set) var currentPhase: TrainingPhase?
    /// The real, already-pre-planned next `TrainingPhase`
    /// (`TrainingPhaseCompletion.nextStrategicPhase`) — never fabricated.
    private(set) var nextPhase: TrainingPhase?
    /// The ONE `TrainingMix` candidate resolved during `load` — an
    /// uninserted, in-memory value at this point (exactly the same shape
    /// `SeedAnnualPlanJourney`/`TransitionPhaseUseCase` already handle:
    /// a caller-proposed candidate that was never explicitly inserted
    /// anywhere). Held here, in this one ViewModel instance, for the
    /// lifetime of one sheet presentation — never re-derived, never
    /// looked up by identity across a persistence boundary, because at
    /// this point it has no stable identity to look up by yet. This is
    /// the single source of truth `startTransition` passes directly to
    /// `TransitionPhaseUseCase.transition` — see this type's own top-level
    /// doc comment for why a second `proposeTrainingMix` call is unsafe.
    private(set) var reviewedMix: TrainingMix?

    /// This is a planner RECOMMENDATION, not yet a selected/accepted
    /// configuration — `TrainingMix.kind` only actually becomes `.selected`
    /// inside `StartPhaseUseCase.start`, the moment the user's tap commits
    /// it (mirrors the existing `recommendedTrainingMix`/`selectedTrainingMix`
    /// distinction `TrainingPhase`/`PhaseDetailView` already draw
    /// elsewhere). Computed directly from `reviewedMix` — see this type's
    /// own doc comment for why that's load-bearing, not incidental.
    var previewMixSummary: String? { reviewedMix.map(PlanPresentation.mixSummary) }
    /// `true` when the reviewed mix contains a Hypertrophy/Powerlifting
    /// component — every fresh `ProgramInstance` for an `.rmBased` system
    /// always needs fresh `SourceRMCalibration` (D-10R7-9/CLAUDE.md rule
    /// on calibration), so this is a deterministic fact about what's about
    /// to happen, not a guess. Computed from the SAME `reviewedMix`
    /// `startTransition` uses, never a second independent read.
    var previewIncludesCalibrationRequiredSystem: Bool {
        reviewedMix?.orderedComponents.contains {
            $0.programmingSystem == .hypertrophy || $0.programmingSystem == .powerlifting
        } ?? false
    }
    private(set) var isTransitioning = false
    private(set) var didSucceed = false
    private(set) var errorMessage: String?
    /// How many components the transition actually left awaiting
    /// calibration — `nil` until a transition has actually run.
    private(set) var componentsAwaitingCalibrationCount: Int?

    func load(currentPhase: TrainingPhase, modelContext: ModelContext) {
        self.currentPhase = currentPhase
        self.nextPhase = TrainingPhaseCompletion.nextStrategicPhase(for: currentPhase)
        didSucceed = false
        errorMessage = nil
        componentsAwaitingCalibrationCount = nil

        guard let nextPhase, let goal = currentPhase.plan?.goal else {
            reviewedMix = nil
            return
        }
        let candidates = LongTermPlanner.proposeTrainingMix(phase: nextPhase, goal: goal)
        reviewedMix = (candidates.first { $0.roles.contains(.recommended) } ?? candidates.first)?.mix
    }

    /// The one deliberate write this ViewModel performs. Guarded against
    /// re-entry two ways: `isTransitioning` (blocks a genuine concurrent
    /// double-tap) and `didSucceed` (blocks a second tap after success,
    /// since by then `currentPhase.status` is already `.completed` and
    /// there is nothing left to transition from). Uses `reviewedMix`
    /// exactly as `load` resolved it — never re-proposes.
    @discardableResult
    func startTransition(modelContext: ModelContext) -> Bool {
        guard !isTransitioning, !didSucceed else { return false }
        guard let currentPhase, nextPhase != nil, let mix = reviewedMix else {
            errorMessage = "No next phase is available to start."
            return false
        }
        isTransitioning = true
        defer { isTransitioning = false }
        errorMessage = nil

        let ownerUserID = currentPhase.primaryInstance?.ownerUserID ?? currentPhase.plan?.goal?.ownerUserID
        guard let ownerUserID else {
            errorMessage = "This phase's owner could not be determined."
            return false
        }

        // Same established candidate-pool pattern every other real caller
        // (SeedAnnualPlanJourney, PhaseDetailViewModel.advanceTacticalWeek/
        // startNextHypertrophyMesocycle) already uses — including the same
        // KNOWN DOMAIN GAP (no persisted equipment-inventory model yet).
        let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let materializationContext = TacticalMaterializationContext(
            equipmentProfile: EquipmentProfile(equipmentType: .barbell, smallestIncrementKg: 2.5),
            strengthCandidateExercises: exercises,
            functionalFitnessCandidateExercises: exercises
        )

        do {
            let result = try TransitionPhaseUseCase.transition(
                from: currentPhase, toNextPhaseWithMix: mix, asOf: Date(), ownerUserID: ownerUserID,
                performanceProfile: nil,
                availability: UserAvailability(trainingDaysPerWeek: 7, allowsDoubleSessions: false, maxSessionsPerDay: 1),
                materializationContext: materializationContext, context: modelContext
            )
            componentsAwaitingCalibrationCount = result.startResult.componentsAwaitingCalibration.count
            didSucceed = true
            NotificationCenter.default.post(name: .strategicPhaseTransitionCompleted, object: nil)
            return true
        } catch {
            errorMessage = "The phase transition could not be completed. The previous phase remains active and unchanged."
            return false
        }
    }
}
