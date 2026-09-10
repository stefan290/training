import Foundation

/// Whether a running session's role is source-honestly "quality" (a
/// harder, purposeful stimulus) or "easy" — derived ONLY from the
/// already-existing `SessionRole` enum (`ENDURANCE_PROGRAMMING_MODEL.md`
/// §8's own finding: session roles are programming semantics, not a new
/// core entity). Returns `nil` rather than guessing for any role this
/// distinction cannot be honestly derived from (R2.10: "quality/easy
/// distinction ONLY if honestly derivable").
enum RunningSessionQualityClassification: String, Codable, CaseIterable {
    case quality
    case easy
}

/// Whether an RP cross-domain guideline is phrased by the source as a
/// non-negotiable constraint or as a recommended default with an explicit
/// override path — R2.10's own instruction: "Do not turn every source
/// recommendation into a hard global orchestrator constraint without
/// evaluating whether RP stated it as mandatory or advisory."
enum RunningOrchestrationRuleStrength: String, Codable, CaseIterable {
    case mandatory
    case advisory
}

/// One source-supported cross-domain rule, its strength classification,
/// and the exact citation that justifies the classification — so the
/// classification itself is reviewable, not asserted.
struct RunningOrchestrationRule: Codable, Equatable {
    let strength: RunningOrchestrationRuleStrength
    let citation: String
}

/// Running-side facts a future `ConcurrentScheduler` needs, computed ONLY
/// from already-existing, already-populated data
/// (`TrainingStressProfile`, `SessionRole`, `ActivityType`) — never a new
/// persisted schedule/placement decision. This checkpoint implements
/// metadata/contract only; it does not implement concurrent scheduling
/// itself (R2.10, R2.11).
struct RunningOrchestrationMetadata: Equatable {
    let activityType: ActivityType
    let qualityClassification: RunningSessionQualityClassification?
    /// Reused directly from `TrainingStressProfile.recoveryDemand` —
    /// R2.10's "recovery sensitivity" is already this existing field;
    /// no parallel field is introduced.
    let recoverySensitivity: LoadLevel?
    /// `true` only when the caller (whatever later feature tracks
    /// mesocycle/week structure) explicitly says this session falls in a
    /// planned reduction week — this type never computes that itself
    /// (R1's own operational deload test — a mileage drop vs. the prior
    /// week — requires data this metadata struct does not have access
    /// to).
    let isPlannedReductionWeek: Bool?
}

enum RunningOrchestrationContract {
    /// `nil` for any role where the distinction is not honestly
    /// derivable from existing `SessionRole` semantics (e.g. `.mixed`,
    /// `.strength`, `.functionalFitness`, `.skill` — none of these are a
    /// running-specific quality/easy question at all).
    static func qualityClassification(for role: SessionRole) -> RunningSessionQualityClassification? {
        switch role {
        case .tempo, .threshold, .interval: return .quality
        case .easy, .recovery, .aerobicBase, .long: return .easy
        case .strength, .hypertrophy, .functionalFitness, .skill, .mixed: return nil
        }
    }

    static func metadata(
        activityType: ActivityType,
        sessionRole: SessionRole,
        trainingStressProfile: TrainingStressProfile?,
        isPlannedReductionWeek: Bool?
    ) -> RunningOrchestrationMetadata {
        RunningOrchestrationMetadata(
            activityType: activityType,
            qualityClassification: qualityClassification(for: sessionRole),
            recoverySensitivity: trainingStressProfile?.recoveryDemand,
            isPlannedReductionWeek: isPlannedReductionWeek
        )
    }

    // MARK: Source-supported cross-domain rules (Program-Pairing Guide.docx)
    //
    // Every rule below is classified `.advisory`, never `.mandatory` —
    // verified directly against the source text: every cross-domain
    // guideline in `Program-Pairing Guide.docx`/FAQ's stacking discussion
    // is phrased with a hedge ("recommended," "should," "not
    // recommended," "usually") AND paired with an explicit override path
    // RP itself describes (e.g. non-stackability's own "If you're dead
    // set on mixing and matching, you could choose one workout per week
    // from one of the programs..."). No cross-domain rule in this source
    // material is phrased as an absolute prohibition with zero override
    // path, so none is classified `.mandatory` here.

    /// "Weight training days are listed within the training plan and are
    /// listed after the running workouts. Lifting should be performed
    /// afterwards whenever there is a 2-a-day scenario." — with an
    /// explicit override path stated a few lines later ("If the lifting
    /// is not a large portion of your other fitness activity or sport,
    /// then you can perform it before the running workout").
    static let liftingSequencedAfterRunning = RunningOrchestrationRule(
        strength: .advisory,
        citation: "Program-Pairing Guide.docx lines 6, 9, 15, 16"
    )

    /// "In the case that it cannot be separated and must be performed
    /// before a running workout, it is recommended that paces are slowed
    /// by 5-10%. This should be a last resort."
    static let liftingBeforeRunningRequiresPaceReduction = RunningOrchestrationRule(
        strength: .advisory,
        citation: "Program-Pairing Guide.docx line 17"
    )

    /// "it is not recommended that you run two training programs
    /// concomitantly. That is, the training programs are not
    /// 'stackable'." — immediately followed by an explicit workaround.
    static let enduranceProgramsNotStackable = RunningOrchestrationRule(
        strength: .advisory,
        citation: "FAQ Endrance Running.docx lines 54-56; Program-Pairing Guide.docx line 14"
    )

    /// "We don't recommend adding more than 2 lifting days to the
    /// prescribed schedule." / "Eliminating 2 or more days of lifting
    /// will likely lead to weakness."
    static let liftingFrequencyModificationLimits = RunningOrchestrationRule(
        strength: .advisory,
        citation: "Program-Pairing Guide.docx lines 24-26"
    )
}
