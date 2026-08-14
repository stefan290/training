import Foundation
import SwiftData

/// The outcome of a non-set-based block (STEADY_STATE, INTERVALS, AMRAP,
/// EMOM, FOR_TIME, or a completed WARMUP/COOLDOWN/MOBILITY). One flexible
/// model with optional fields per type, rather than a subclass per block
/// type — SwiftData has no first-class polymorphism, and the field set per
/// type is small. Revisit if the payload shape grows materially.
@Model
final class WorkoutResult {
    @Attribute(.unique) var id: UUID
    var workoutBlock: WorkoutBlock?
    var type: WorkoutBlockType
    var scoringDirection: ScoringDirection
    var resultContext: ResultContext
    var completedAt: Date

    // WARMUP / COOLDOWN / MOBILITY
    var durationSeconds: Int?
    var completedFlag: Bool?

    // STEADY_STATE / INTERVALS
    var distanceMeters: Double?
    var averageHeartRate: Int?

    // AMRAP
    var rounds: Int?
    var extraReps: Int?

    // EMOM
    var minutesCompleted: Int?
    var incompleteMinuteIndexes: [Int]

    // FOR_TIME
    var elapsedSeconds: Int?
    var cappedAtSeconds: Int?
    var splitSeconds: [Int]

    init(
        id: UUID = UUID(),
        type: WorkoutBlockType,
        scoringDirection: ScoringDirection,
        resultContext: ResultContext = .rx,
        completedAt: Date = Date(),
        durationSeconds: Int? = nil,
        completedFlag: Bool? = nil,
        distanceMeters: Double? = nil,
        averageHeartRate: Int? = nil,
        rounds: Int? = nil,
        extraReps: Int? = nil,
        minutesCompleted: Int? = nil,
        incompleteMinuteIndexes: [Int] = [],
        elapsedSeconds: Int? = nil,
        cappedAtSeconds: Int? = nil,
        splitSeconds: [Int] = []
    ) {
        self.id = id
        self.type = type
        self.scoringDirection = scoringDirection
        self.resultContext = resultContext
        self.completedAt = completedAt
        self.durationSeconds = durationSeconds
        self.completedFlag = completedFlag
        self.distanceMeters = distanceMeters
        self.averageHeartRate = averageHeartRate
        self.rounds = rounds
        self.extraReps = extraReps
        self.minutesCompleted = minutesCompleted
        self.incompleteMinuteIndexes = incompleteMinuteIndexes
        self.elapsedSeconds = elapsedSeconds
        self.cappedAtSeconds = cappedAtSeconds
        self.splitSeconds = splitSeconds
    }
}
