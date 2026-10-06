import Foundation

/// RESULT-DRIVEN RESISTANCE PROGRESSION V1: whether a completed exposure's
/// actual performance indicates the prescribed load was too light, on
/// target, or too heavy for the prescription the athlete was actually
/// asked to perform. This is a judgment about LOAD RELATIVE TO
/// PRESCRIPTION, never an athlete-quality/readiness/fitness score
/// (Section 5/34), and never a step toward estimating the athlete's true
/// physiological maximum (Section 2/3) — no generic e1RM equation is
/// introduced anywhere in this engine.
enum ExposureEvaluation: String, Codable, CaseIterable {
    /// The exposure indicates the load was easier than the prescribed
    /// rep/RIR target — a real equipment step up may be appropriate.
    case aboveTarget
    /// The exposure broadly matched the prescribed rep/RIR target — hold
    /// the current load.
    case onTarget
    /// The exposure indicates the load exceeded the prescribed target on
    /// at least one working set — a real equipment step down for the
    /// NEXT exposure only, never a rewrite of persisted tested-RM
    /// calibration (Section 15).
    case underTarget
    /// Too few real working-set results exist to make a truthful
    /// comparison (Section 27/28) — distinct from `.underTarget`; no
    /// upward progression follows.
    case insufficientEvidence
}

/// RESULT-DRIVEN RESISTANCE PROGRESSION V1. Answers the CORE QUESTION
/// (Section 3): was the recommended load too light, appropriate, or too
/// heavy for the prescription the athlete was asked to perform? Never
/// infers WHY (Section 9) — no reading of recovery/sleep/motivation into
/// the result. Prescription-relative by design (Section 25): takes the
/// actual prescription shape and completed working sets, never a
/// Strength-specific signature baked into the type system — but the
/// classification RULES implemented here (`evaluate`) are the Strength V1
/// policy specifically (Sections 6-11); see this engine's own Hypertrophy
/// integration note in `RESULT_DRIVEN_PROGRESSION_TRACE.md`-equivalent
/// documentation (this checkpoint's final report) for why Hypertrophy
/// integration was not attempted.
enum ResultDrivenProgressionEngine {
    /// One real, non-warmup working set's actual outcome — deliberately a
    /// plain struct, not `SetResult` itself, so this engine has zero
    /// SwiftData/persistence dependency (matching `BlockProgressionOutput`/
    /// `ProgrammingDecisionOutput`'s own "pure engine input" precedent).
    /// Callers are responsible for excluding warmup sets (`SetPrescription
    /// .isWarmup`) and calibration-entry interactions (which never produce
    /// a `SetResult` against a real working-set `SetPrescription` at all)
    /// before constructing this array (Section 4).
    struct WorkingSetPerformance {
        let setIndex: Int
        let weight: Double
        let reps: Int?
        /// `nil` means genuinely unknown — never fabricated (Section 26).
        let actualRir: Int?
    }

    /// Section 4: the decision unit is the EXPOSURE (every real working
    /// set for one exercise under one prescription in one session), never
    /// an isolated set. Section 30: the athlete may change load between
    /// working sets within one exposure (a genuine self-correction, e.g.
    /// "80kg felt too easy, moved to 82.5kg for the rest") — this engine
    /// evaluates the LAST distinct weight group reached (by `setIndex`),
    /// since that represents the athlete's settled choice for this
    /// exposure, and bases the next recommendation on that actual load,
    /// never a blended average across differing weights (explicitly
    /// forbidden).
    static func evaluate(
        prescribedSetCount: Int,
        repRangeLow: Int?,
        repRangeHigh: Int?,
        targetRir: Int?,
        targetRirHigh: Int?,
        workingSets: [WorkingSetPerformance]
    ) -> ExposureEvaluation {
        // Section 27/28: fewer real working-set results than the exposure's
        // own prescribed count is INSUFFICIENT_EVIDENCE, never UNDER_TARGET
        // — the athlete may simply have stopped training, not failed.
        guard prescribedSetCount > 0, workingSets.count >= prescribedSetCount else {
            return .insufficientEvidence
        }
        guard let lastSetIndex = workingSets.map(\.setIndex).max(),
              let terminalWeight = workingSets.first(where: { $0.setIndex == lastSetIndex })?.weight
        else {
            return .insufficientEvidence
        }
        let relevantSets = workingSets.filter { $0.weight == terminalWeight }

        // Section 11: UNDER_TARGET evidence outranks ABOVE_TARGET evidence
        // outranks ON_TARGET — checked first, unconditionally, across every
        // relevant set. A clearly over-demanding later set is never erased
        // by an easy earlier one (Section 10's conflicting-set example).
        for set in relevantSets {
            if let reps = set.reps, let low = repRangeLow, reps < low {
                return .underTarget
            }
            if let rir = set.actualRir, let low = targetRir, rir < low {
                return .underTarget
            }
        }

        // Section 26: missing RIR must NEVER itself produce ABOVE_TARGET.
        // A set with unknown RIR simply contributes no ABOVE_TARGET
        // evidence (it also already passed the UNDER_TARGET check above
        // using reps alone, where available) — never fabricated, never
        // silently promoted.
        for set in relevantSets {
            guard let rir = set.actualRir else { continue }
            if let high = targetRirHigh, rir > high {
                return .aboveTarget
            }
            if let reps = set.reps, let repsHigh = repRangeHigh {
                if reps > repsHigh { return .aboveTarget }
                if reps >= repsHigh, let low = targetRir, rir >= low { return .aboveTarget }
            }
        }

        return .onTarget
    }

    /// Sections 12-14: the progression unit is ONE PRACTICAL EQUIPMENT
    /// STEP, never a percentage. `.insufficientEvidence` holds (no upward
    /// progression is the only rule Section 27 requires; holding, not
    /// reducing, is the conservative choice when there's no evidence the
    /// load itself was the problem).
    static func nextSuggestedLoad(
        evaluation: ExposureEvaluation,
        actualLoad: Double,
        equipmentProfile: EquipmentProfile
    ) -> (weightKg: Double, reasonCode: StrengthReasonCode) {
        switch evaluation {
        case .aboveTarget:
            return (equipmentProfile.nextValidLoad(above: actualLoad), .loadIncreasedOneEquipmentStep)
        case .onTarget:
            return (actualLoad, .loadHeld)
        case .underTarget:
            return (equipmentProfile.nextValidLoad(below: actualLoad), .loadReducedOneEquipmentStep)
        case .insufficientEvidence:
            return (actualLoad, .loadHeld)
        }
    }
}
