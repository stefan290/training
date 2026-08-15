import Foundation
import SwiftData

/// One training occasion. Holds an ordered list of WorkoutBlocks, which may
/// mix modalities freely (e.g. Strength block followed by a Metcon block)
/// — that is still one Session. `programInstance` is optional because a
/// Session can be logged ad hoc, outside any active program instance.
@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var day: Day?
    var programInstance: ProgramInstance?

    /// Stable position among a Day's Sessions, assigned by
    /// `Day.addSession(_:)`. Distinct from `scheduledTime`: this is
    /// persistence-safe ordering data, not a product-facing time.
    var sortIndex: Int
    var scheduledTime: Date?
    var name: String
    var modality: TrainingModality
    var status: SessionStatus
    var startedAt: Date?
    var completedAt: Date?
    /// Stage 3C addition (`SessionRole.swift`): programming semantics
    /// (Easy/Tempo/Interval/etc.), orthogonal to which `ProgrammingSystem`
    /// produced this Session's blocks and orthogonal to `modality` above
    /// (the pre-existing UI grouping tag). `nil` is the common case for
    /// every Session that existed before this pass.
    var role: SessionRole?
    /// Stage 4F addition: which `ConcurrentScheduler` version last placed
    /// this Session's `day` — mirrors `ProgramDefinition.generatorVersion`.
    /// `nil` means this Session has never been placed by
    /// `AcceptScheduleProposalUseCase` (e.g. still at its materializer's
    /// naive date, or logged ad hoc). Stamped, never read, by the
    /// scheduler itself — a later scheduler-version bump must never
    /// silently re-interpret an already-accepted placement.
    var schedulerVersion: Int?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutBlock.session)
    var blocks: [WorkoutBlock] = []

    init(
        id: UUID = UUID(),
        scheduledTime: Date? = nil,
        name: String,
        modality: TrainingModality,
        status: SessionStatus = .scheduled,
        role: SessionRole? = nil,
        schedulerVersion: Int? = nil
    ) {
        self.id = id
        self.sortIndex = 0
        self.scheduledTime = scheduledTime
        self.name = name
        self.modality = modality
        self.status = status
        self.role = role
        self.schedulerVersion = schedulerVersion
    }

    /// The only way application code should attach a WorkoutBlock to a
    /// Session. Mutates exactly one side of the relationship (this array);
    /// SwiftData maintains `block.session` from the declared inverse.
    /// Never set `block.session` directly elsewhere.
    func addBlock(_ block: WorkoutBlock) {
        block.sortIndex = blocks.count
        blocks.append(block)
    }

    /// Blocks in execution order. `blocks`'s raw collection order is not
    /// guaranteed to survive a save/refetch cycle — always read through
    /// this property, never sort by insertion order.
    var orderedBlocks: [WorkoutBlock] {
        blocks.sorted { $0.sortIndex < $1.sortIndex }
    }
}
