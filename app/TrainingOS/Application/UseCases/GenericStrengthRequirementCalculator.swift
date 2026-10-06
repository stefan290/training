import Foundation

/// FUNCTIONAL FITNESS V2 — GENERIC STRENGTH AUTHORITY V1, Sections 1-17:
/// the minimal, evidence-backed weekly HIGH_LOAD_STRENGTH_EXPOSURE
/// requirement/allocation model — the project lead's own locked
/// programming decision (Section 1, citing the 2026 ACSM Position
/// Stand). This type implements the ALLOCATION half of that decision
/// (how many weekly exposures are required, how many a real source
/// program already satisfies, and which remaining eligible FF sessions
/// carry the rest) — it never resolves the actual PRESCRIPTION (load/
/// reps/RIR), which is a separate, distinct authority question (see
/// this checkpoint's own trace, sections 18-23 of the final report).
///
/// Mirrors `MuscleVolumeRequirementCalculator`'s shape (source
/// contribution -> remaining requirement -> deterministic allocation)
/// per Section 29's own instruction to reuse existing weekly-requirement
/// patterns rather than inventing parallel infrastructure — but this is
/// a simple integer EXPOSURE COUNT, never a set-credit vector: an
/// "exposure" is a session-level adaptation responsibility, not a
/// muscle-group ledger (Section 4 is explicit that pattern and exposure
/// are separate dimensions; this type never conflates them).
enum GenericStrengthRequirementCalculator {
    /// Section 3's locked fallback anchor — used only when no authored
    /// source program (Strength/Powerlifting) already provides sufficient
    /// weekly high-load exposure. Never a per-session, per-pattern, or
    /// frequency-multiplied value (Sections 4/8/15/20).
    static let weeklyRequiredHighLoadExposures = 2

    /// Section 5/6: real source-backed weekly contribution. Both Family B
    /// ("Strength") and Family C ("Powerlifting") share the same real
    /// execution engine identity (`programmingSystem == .powerlifting`,
    /// content distinguished only by `strengthContentSelector` — see
    /// `TrainingMixComponent`'s own doc comment) — Section 5 explicitly
    /// permits BOTH to count toward this requirement ("Eligible source
    /// contributions may include: authored Strength program sessions;
    /// authored Powerlifting program sessions"), since both genuinely
    /// provide meaningful high-load resistance work every real session.
    /// One real weekly session of either program is one real exposure —
    /// never rewritten, never extracted into a constant (Section 5A).
    static func sourceContribution(mix: TrainingMix) -> Int {
        mix.orderedComponents
            .filter { $0.programmingSystem == .powerlifting }
            .reduce(0) { $0 + $1.frequency.target }
    }

    /// Section 5/10: `max(0, fallback - source)` — never negative, never
    /// truncates a source program that already exceeds the fallback
    /// (Section 5A's absolute non-override rule).
    static func remainingRequirement(sourceContribution: Int) -> Int {
        max(0, weeklyRequiredHighLoadExposures - sourceContribution)
    }

    /// Section 8: the 4 real loaded movement patterns this checkpoint's
    /// generic Strength authority can assign responsibility for — the
    /// same vocabulary the week-level squat/hinge rule and
    /// `FunctionalBodybuildingPattern` already use, never a new taxonomy.
    static let strengthCapablePatterns: [MovementFunction] = [.squatLoaded, .hingeLoaded, .pressLoaded, .horizontalPullLoaded]

    /// Section 7/8/9/30: deterministic, order-independent whole-week
    /// allocation. Given the remaining exposure count and which patterns
    /// a real source program already covers this week, assigns each
    /// remaining exposure to the lowest-index eligible FF session,
    /// preferring a pattern the source has NOT already covered (Section
    /// 8's "prefer unresolved... rather than automatically adding
    /// another heavy squat") — cycling back through covered patterns
    /// only if remaining exceeds the number of genuinely unresolved
    /// patterns. Sorting `eligibleFFSessionIndices` internally (never
    /// trusting caller order) is what makes this order-independent: the
    /// same real input set always produces the same assignment
    /// regardless of the order sessions were discovered/iterated in.
    static func allocateFFAssignments(
        eligibleFFSessionIndices: [Int],
        remaining: Int,
        patternsAlreadyCoveredBySource: Set<MovementFunction> = []
    ) -> [Int: MovementFunction] {
        guard remaining > 0, !eligibleFFSessionIndices.isEmpty else { return [:] }
        let unresolved = strengthCapablePatterns.filter { !patternsAlreadyCoveredBySource.contains($0) }
        let alreadyCovered = strengthCapablePatterns.filter { patternsAlreadyCoveredBySource.contains($0) }
        let preferenceOrder = unresolved + alreadyCovered
        guard !preferenceOrder.isEmpty else { return [:] }

        let sortedSessions = eligibleFFSessionIndices.sorted()
        var assignments: [Int: MovementFunction] = [:]
        for (offset, sessionIndex) in sortedSessions.prefix(remaining).enumerated() {
            assignments[sessionIndex] = preferenceOrder[offset % preferenceOrder.count]
        }
        return assignments
    }
}
