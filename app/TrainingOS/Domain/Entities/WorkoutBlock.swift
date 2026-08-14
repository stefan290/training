import Foundation
import SwiftData

/// The modality-agnostic execution unit inside a Session. Every block has
/// its own prescription (via `exercisePrescriptions`), execution model
/// (`type`) and result (`result`) — see handoff section 2.2.
///
/// Block-level parameters (time caps, EMOM interval length, etc.) are kept
/// as flat optional fields rather than a nested value type. SwiftData can
/// store Codable structs, but flattening keeps this first pass simple to
/// read and migrate; revisit if the parameter set grows.
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

    /// AMRAP / For Time.
    var timeCapSeconds: Int?
    /// EMOM.
    var emomIntervalSeconds: Int?
    var emomTotalMinutes: Int?

    @Relationship(deleteRule: .cascade, inverse: \ExercisePrescription.workoutBlock)
    var exercisePrescriptions: [ExercisePrescription] = []

    @Relationship(deleteRule: .cascade, inverse: \WorkoutResult.workoutBlock)
    var result: WorkoutResult?

    init(
        id: UUID = UUID(),
        type: WorkoutBlockType,
        status: BlockStatus = .pending,
        timeCapSeconds: Int? = nil,
        emomIntervalSeconds: Int? = nil,
        emomTotalMinutes: Int? = nil
    ) {
        self.id = id
        self.sortIndex = 0
        self.type = type
        self.status = status
        self.timeCapSeconds = timeCapSeconds
        self.emomIntervalSeconds = emomIntervalSeconds
        self.emomTotalMinutes = emomTotalMinutes
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

    var orderedPrescriptions: [ExercisePrescription] {
        exercisePrescriptions.sorted { $0.sortIndex < $1.sortIndex }
    }
}
