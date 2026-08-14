import Foundation

/// A coarse, deterministic classification of how costly a block/session was
/// to the body — the shared vocabulary every future `ProgrammingSystem`
/// stamps its own output with, so a future `ConcurrentScheduler` can reason
/// about placement without needing modality-specific code
/// (`CONCURRENT_SCHEDULER_MODEL.md` §2).
///
/// **Explicitly not a physiological measurement.** Every field is a small,
/// closed `LoadLevel`/`DurationDomain` enum, not a computed score out of
/// 100 — there is no formula here, and none should be added under the
/// guise of "more precision." Stage 3C seeds this data by hand on each new
/// scenario (`STAGE3C_IMPLEMENTATION_REPORT.md`); automatic estimation from
/// a block's actual content is explicitly out of scope for this pass.
struct TrainingStressProfile: Codable, Equatable {
    var overallIntensity: LoadLevel
    var systemicDemand: LoadLevel
    var lowerBodyLoad: LoadLevel
    var upperBodyLoad: LoadLevel
    var impactLoading: LoadLevel
    var metabolicDemand: LoadLevel
    var durationClassification: DurationDomain
    var modality: ActivityType?
    var recoveryDemand: LoadLevel
}

enum LoadLevel: String, Codable, CaseIterable {
    case none
    case low
    case moderate
    case high
}
