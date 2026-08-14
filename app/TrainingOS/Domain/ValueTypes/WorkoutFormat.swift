import Foundation

/// The structural container for a Functional Fitness block — deliberately
/// a separate type from `Stimulus` (Stimulus.swift). Two workouts sharing a
/// `WorkoutFormat` (e.g. two AMRAPs) can have completely different
/// stimuli; conflating the two into one type would make that
/// impossible to represent, per `FUNCTIONAL_FITNESS_PROGRAMMING_MODEL.md` §2.
enum WorkoutFormat: Codable, Equatable {
    case amrap(capSeconds: Int)
    case emom(intervalSeconds: Int, totalSeconds: Int)
    case forTime(capSeconds: Int?)
    case roundsForTime(rounds: Int, capSeconds: Int?)
    case chipper(capSeconds: Int?)
    case ladder(direction: LadderDirection, capSeconds: Int?)
    case maxLoad
    case maxReps(capSeconds: Int)
    case intervals(count: Int, workSeconds: Int, restSeconds: Int)
}

enum LadderDirection: String, Codable, CaseIterable {
    case ascending
    case descending
}
