import Foundation

/// Composes a Session's own `TrainingStressProfile` from its ordered
/// `WorkoutBlock`s — deterministic, categorical worst-case composition
/// per dimension, never an arbitrary numeric average
/// (`TrainingStressProfile.swift`'s own "no fabricated precision" doc
/// comment applies at the Session level too). This is what
/// `ConcurrentScheduler` actually reasons about when placing a
/// multi-block Session (e.g. a Strength block followed by a Metcon
/// finisher): the worse of the two on every `LoadLevel` dimension, not
/// the average.
enum SessionStressComposer {
    /// `nil` when none of the Session's blocks carry a
    /// `trainingStressProfile` — composing nothing produces nothing,
    /// rather than a fabricated all-`.none` profile.
    static func compose(_ session: Session) -> TrainingStressProfile? {
        let profiles = session.orderedBlocks.compactMap(\.trainingStressProfile)
        guard !profiles.isEmpty else { return nil }

        let modality: ActivityType? = {
            let modalities = Set(profiles.compactMap(\.modality))
            return modalities.count == 1 ? modalities.first : nil
        }()

        return TrainingStressProfile(
            overallIntensity: worstCase(profiles.map(\.overallIntensity)),
            systemicDemand: worstCase(profiles.map(\.systemicDemand)),
            lowerBodyLoad: worstCase(profiles.map(\.lowerBodyLoad)),
            upperBodyLoad: worstCase(profiles.map(\.upperBodyLoad)),
            impactLoading: worstCase(profiles.map(\.impactLoading)),
            metabolicDemand: worstCase(profiles.map(\.metabolicDemand)),
            durationClassification: longest(profiles.map(\.durationClassification)),
            modality: modality,
            recoveryDemand: worstCase(profiles.map(\.recoveryDemand))
        )
    }

    private static func worstCase(_ levels: [LoadLevel]) -> LoadLevel {
        levels.max { $0.ordinal < $1.ordinal } ?? .none
    }

    private static func longest(_ domains: [DurationDomain]) -> DurationDomain {
        domains.max { $0.ordinal < $1.ordinal } ?? .short
    }
}

private extension DurationDomain {
    var ordinal: Int {
        switch self {
        case .short: return 0
        case .medium: return 1
        case .long: return 2
        }
    }
}
