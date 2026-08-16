import Foundation

/// `TACTICAL_PLANNING_HANDOFF.md` §2's exhaustive, deterministic list of
/// reasons a new tactical window is generated — never a bare timer, and
/// never "because calendar time passed" alone.
enum TacticalWindowTrigger: String, Codable, CaseIterable {
    /// Today is within a configured buffer of the current window's last
    /// placed day — lead time to review/approve the next one.
    case windowApproachingEnd
    /// A fallback catch-up trigger: the window has already fully elapsed
    /// with no successor generated yet (the approaching-end lead time was
    /// missed entirely).
    case windowCompleted
    /// The phase changed (`PHASE_PLANNING_RULES.md` §4) — the new
    /// phase's mix needs its own first tactical window immediately.
    case phaseChanged
    /// The user changed `TrainingMix`/preferences materially — a bounded
    /// temporary mix accepted or its expiry/materiality prompt resolved,
    /// or a stable preference/mix swap accepted directly.
    case mixOrPreferenceChanged
    /// The user paused, then resumed — a fresh window is generated from
    /// the resume date, never backfilled for missed time.
    case pauseResumed
    /// An accepted strategic plan revision, minor or major
    /// (`PLAN_REVISION_MODEL.md` §4).
    case planRevised
}
