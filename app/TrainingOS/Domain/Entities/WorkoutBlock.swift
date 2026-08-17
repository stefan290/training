import Foundation
import SwiftData

/// The modality-agnostic execution unit inside a Session. Every block has
/// its own prescription, execution model (`type`) and result — see
/// handoff section 2.2.
///
/// Block-level parameters (time caps, EMOM interval length, etc.) are kept
/// as flat optional fields rather than a nested value type for the
/// original (Stage 1-2) `.amrap`/`.emom`/`.forTime` path — deliberately
/// left untouched; see `STAGE3C_IMPLEMENTATION_REPORT.md`. Stage 3C's
/// typed `BlockPrescription`/`BlockResult` (below) is the "revisit if the
/// parameter set grows" this doc comment used to flag — implemented as
/// new, additive relationships, not a rewrite of the fields above.
@Model
final class WorkoutBlock {
    @Attribute(.unique) var id: UUID
    var session: Session?
    /// Stable position among a Session's blocks, assigned by
    /// `Session.addBlock(_:)`. This — not collection insertion order — is
    /// what "ordered by product definition" means for a Session's blocks.
    var sortIndex: Int
    var type: WorkoutBlockType
    var status: BlockStatus
    /// Stage 6B addition: `nil` until `status == .completed`. Refines
    /// `.completed` with "was every prescribed unit actually logged" —
    /// `BlockStatus` itself gains no new case (`SESSION_STATE_MACHINE.md`
    /// §5).
    var completionContext: BlockCompletionContext?
    /// Stage 6B addition: this block's own running clock, when it has
    /// one (rest timer, AMRAP, EMOM, an interval leg, a capped For
    /// Time-family block) — wall-clock anchored, never a tick count
    /// (`TIMER_ARCHITECTURE.md`).
    var timerState: TimerState?

    /// AMRAP / For Time (legacy path only — see type doc comment).
    var timeCapSeconds: Int?
    /// EMOM (legacy path only).
    var emomIntervalSeconds: Int?
    var emomTotalMinutes: Int?

    /// Coarse, deterministic scheduling metadata for a future
    /// `ConcurrentScheduler` — seeded/prototype data in this pass, per
    /// `TrainingStressProfile.swift`'s doc comment. `nil` is a valid,
    /// common state: most blocks in this pass don't set it.
    var trainingStressProfile: TrainingStressProfile?

    @Relationship(deleteRule: .cascade, inverse: \ExercisePrescription.workoutBlock)
    var exercisePrescriptions: [ExercisePrescription] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkoutResult.workoutBlock)
    var result: WorkoutResult?

    // MARK: Stage 3C — typed prescriptions (BlockPrescription.swift)

    /// Structural, block-scoped — cascades with the block, exactly like
    /// `exercisePrescriptions`.
    @Relationship(deleteRule: .cascade, inverse: \SteadyStatePrescription.workoutBlock)
    var steadyStatePrescription: SteadyStatePrescription?

    @Relationship(deleteRule: .cascade, inverse: \IntervalPrescription.workoutBlock)
    var intervalPrescription: IntervalPrescription?

    @Relationship(deleteRule: .cascade, inverse: \FunctionalFitnessPrescription.workoutBlock)
    var functionalFitnessPrescription: FunctionalFitnessPrescription?

    // MARK: Stage 3C — typed results (BlockResult.swift)

    /// **Nullify, not cascade** — unlike the legacy `result: WorkoutResult?`
    /// above. These results have a *permanent* home
    /// (`ActivityPerformanceProfile`/`BenchmarkPerformanceProfile`), so
    /// deleting this block (e.g. a program edit removes the session) must
    /// leave the result intact with `workoutBlock` becoming `nil` — the
    /// same reasoning as `ExercisePrescription.loggedSetResults`, not the
    /// same reasoning as the legacy `WorkoutResult` cascade. Getting this
    /// wrong would silently violate CLAUDE.md rule 1 ("never reset user
    /// performance when programs change") for every non-strength result;
    /// see `STAGE3C_IMPLEMENTATION_REPORT.md` for the full reasoning.
    @Relationship(deleteRule: .nullify, inverse: \SteadyStateResult.workoutBlock)
    var steadyStateResult: SteadyStateResult?

    @Relationship(deleteRule: .nullify, inverse: \IntervalResult.workoutBlock)
    var intervalResult: IntervalResult?

    @Relationship(deleteRule: .nullify, inverse: \FunctionalFitnessResult.workoutBlock)
    var functionalFitnessResult: FunctionalFitnessResult?

    init(
        id: UUID = UUID(),
        type: WorkoutBlockType,
        status: BlockStatus = .pending,
        timeCapSeconds: Int? = nil,
        emomIntervalSeconds: Int? = nil,
        emomTotalMinutes: Int? = nil,
        trainingStressProfile: TrainingStressProfile? = nil
    ) {
        self.id = id
        self.sortIndex = 0
        self.type = type
        self.status = status
        self.timeCapSeconds = timeCapSeconds
        self.emomIntervalSeconds = emomIntervalSeconds
        self.emomTotalMinutes = emomTotalMinutes
        self.trainingStressProfile = trainingStressProfile
    }

    /// The only way application code should attach an ExercisePrescription
    /// (a "movement") to a block. Mutates exactly one side; SwiftData
    /// maintains `prescription.workoutBlock` from the declared inverse.
    func addPrescription(_ prescription: ExercisePrescription) {
        prescription.sortIndex = exercisePrescriptions.count
        exercisePrescriptions.append(prescription)
    }

    /// The only way application code should attach this block's
    /// WorkoutResult. Mutates exactly one side (`result`); SwiftData
    /// maintains `result.workoutBlock` from the declared inverse.
    func attachResult(_ result: WorkoutResult) {
        self.result = result
    }

    /// The only way application code should attach a SteadyStatePrescription.
    func attachSteadyStatePrescription(_ prescription: SteadyStatePrescription) {
        steadyStatePrescription = prescription
    }

    /// The only way application code should attach an IntervalPrescription.
    func attachIntervalPrescription(_ prescription: IntervalPrescription) {
        intervalPrescription = prescription
    }

    /// The only way application code should attach a FunctionalFitnessPrescription.
    func attachFunctionalFitnessPrescription(_ prescription: FunctionalFitnessPrescription) {
        functionalFitnessPrescription = prescription
    }

    /// The only way application code should attach a SteadyStateResult.
    func attachSteadyStateResult(_ result: SteadyStateResult) {
        steadyStateResult = result
    }

    /// The only way application code should attach an IntervalResult.
    func attachIntervalResult(_ result: IntervalResult) {
        intervalResult = result
    }

    /// The only way application code should attach a FunctionalFitnessResult.
    func attachFunctionalFitnessResult(_ result: FunctionalFitnessResult) {
        functionalFitnessResult = result
    }

    var orderedPrescriptions: [ExercisePrescription] {
        exercisePrescriptions.sorted { $0.sortIndex < $1.sortIndex }
    }

    /// Synthesizes the generalized `BlockPrescription` from whichever
    /// typed relationship is populated. `nil` for a block that has none of
    /// them set (e.g. a bare warm-up with no formal prescription).
    /// `.exercise` is checked last and only returned when there's at least
    /// one movement, so an empty legacy block doesn't produce a spurious
    /// `.exercise([])` case.
    var blockPrescription: BlockPrescription? {
        if let steadyStatePrescription { return .steadyState(steadyStatePrescription) }
        if let intervalPrescription { return .intervals(intervalPrescription) }
        if let functionalFitnessPrescription { return .functionalFitness(functionalFitnessPrescription) }
        if !exercisePrescriptions.isEmpty { return .exercise(orderedPrescriptions) }
        return nil
    }

    /// Synthesizes the generalized `BlockResult` from whichever typed
    /// relationship is populated. Returns `nil` for a block whose only
    /// result is the legacy `WorkoutResult` (`result`) — that type is
    /// intentionally not one of `BlockResult`'s cases; see
    /// `STAGE3C_IMPLEMENTATION_REPORT.md`.
    var blockResult: BlockResult? {
        if let steadyStateResult { return .steadyState(steadyStateResult) }
        if let intervalResult { return .intervals(intervalResult) }
        if let functionalFitnessResult { return .functionalFitness(functionalFitnessResult) }
        let loggedResults = orderedPrescriptions.flatMap { $0.loggedSetResults }
        if !loggedResults.isEmpty { return .strength(StrengthBlockResult(setResults: loggedResults)) }
        return nil
    }
}
