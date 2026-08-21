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
    /// Stage 6B addition: `nil` until `status == .completed`. Distinct
    /// question from `status` itself — "is this Session finished" vs.
    /// "was it the whole thing" — `SESSION_STATE_MACHINE.md` §2.
    var completionContext: SessionCompletionContext?
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
    /// Hardening-pass addition: marks this Session as more important than
    /// a sibling within the same `TrainingMixComponent` — e.g. a running
    /// week's long run or threshold session vs. an easy run. `false` (the
    /// default) is the common case for every Session that existed before
    /// this pass and for any component with no internal importance
    /// distinction. `ConcurrentScheduler` uses this only to decide which
    /// of a component's OWN sessions get first claim on scarce days/are
    /// least likely to end up unplaced — it never changes the *relative*
    /// calendar order of sessions that do get placed, and it never
    /// crosses component boundaries (see `CONCURRENT_SCHEDULER.md`'s
    /// "key sessions" section).
    var isKeySession: Bool

    @Relationship(deleteRule: .cascade, inverse: \WorkoutBlock.session)
    var blocks: [WorkoutBlock] = []

    /// Stage 8B addition: what the user reported before starting this
    /// Session, at most one — cascade, mirroring `WorkoutBlock.result`'s
    /// exact shape. A `ReadinessCheckIn` has no meaning outside the
    /// Session it was reported for, same reasoning as `Session -> WorkoutBlock`
    /// above; deleting the Session deletes its own readiness report along
    /// with it. This is a real, additive schema change on `Session` — see
    /// `DELETE_RULE_MATRIX.md`'s Stage 8B section.
    @Relationship(deleteRule: .cascade, inverse: \ReadinessCheckIn.session)
    var readinessCheckIn: ReadinessCheckIn?

    /// Stage 9B addition: the generated pre-workout warm-up for this
    /// Session, at most one — cascade, mirroring `readinessCheckIn`'s
    /// exact shape. A `WarmupSequence` has no meaning outside the Session
    /// it was generated for.
    @Relationship(deleteRule: .cascade, inverse: \WarmupSequence.session)
    var warmupSequence: WarmupSequence?

    init(
        id: UUID = UUID(),
        scheduledTime: Date? = nil,
        name: String,
        modality: TrainingModality,
        status: SessionStatus = .scheduled,
        role: SessionRole? = nil,
        schedulerVersion: Int? = nil,
        isKeySession: Bool = false
    ) {
        self.id = id
        self.sortIndex = 0
        self.scheduledTime = scheduledTime
        self.name = name
        self.modality = modality
        self.status = status
        self.role = role
        self.schedulerVersion = schedulerVersion
        self.isKeySession = isKeySession
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

    /// The only way application code should attach a ReadinessCheckIn.
    /// Mutates exactly one side (`readinessCheckIn`); SwiftData maintains
    /// `checkIn.session` from the declared inverse.
    func attachReadinessCheckIn(_ checkIn: ReadinessCheckIn) {
        readinessCheckIn = checkIn
    }

    /// The only way application code should attach a WarmupSequence.
    /// Mutates exactly one side (`warmupSequence`); SwiftData maintains
    /// `sequence.session` from the declared inverse.
    func attachWarmupSequence(_ sequence: WarmupSequence) {
        warmupSequence = sequence
    }
}
