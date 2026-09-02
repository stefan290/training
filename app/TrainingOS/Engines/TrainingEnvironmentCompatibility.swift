import Foundation

/// Stage TE.1: whether a real, concrete equipment requirement can be met
/// in a given `TrainingEnvironment` — a genuine tri-state, never a `Bool`.
/// **`environment == nil` is never `.compatible`** — an unconfigured
/// environment means "we don't know what's available," which is a
/// different, weaker claim than "we know this fits" and must never be
/// silently treated as the same thing (locked amendment to the original
/// TE.1 design, which had proposed a `Bool`).
enum TrainingEnvironmentCompatibility: Equatable {
    case compatible
    case incompatible(missing: Set<EquipmentRequirement>)
    case environmentUnknown
}

/// The sole compatibility check every real call site routes through —
/// `SubstitutionValidator.isValid` (Exercise-based) and each endurance
/// materializer's own post-resolution check (ActivityType-based) both
/// call this, never a second ad hoc comparison.
enum TrainingEnvironmentCompatibilityRule {
    /// `required == []` is always `.compatible` once a real environment
    /// exists — a vacuous subset (matches Easy Run/Track Interval Run/
    /// running's real `[]` requirement). An environment with
    /// `availableEquipment == []` is a real, deliberately austere
    /// environment, not an error state — it is `.compatible` only for
    /// `[]`-requiring candidates. A future `EquipmentRequirement` case
    /// this environment predates fails closed automatically (the set
    /// subtraction simply never removes it).
    static func evaluate(required: [EquipmentRequirement], environment: TrainingEnvironment?) -> TrainingEnvironmentCompatibility {
        guard let environment else { return .environmentUnknown }
        let missing = Set(required).subtracting(Set(environment.availableEquipment))
        return missing.isEmpty ? .compatible : .incompatible(missing: missing)
    }
}

/// TE.1 closure pass: each materializer/resolver owns its own typed error
/// enum (deliberately — CLAUDE.md rule 16's "typed, never string-parsed"
/// discipline, and the earlier disclosed decision to keep
/// `ExerciseSlotResolutionError` distinct from `HypertrophyGenerationError`
/// rather than merge pipeline stages). Conforming each to this one marker
/// lets a ViewModel's `catch` detect "the user has no usable Training
/// Environment" without re-deriving a switch over every concrete error
/// type — the only cross-cutting concept these otherwise-unrelated enums
/// share.
protocol TrainingEnvironmentRequirementError {
    var isTrainingEnvironmentRequired: Bool { get }
}

extension ExerciseSlotResolutionError: TrainingEnvironmentRequirementError {
    var isTrainingEnvironmentRequired: Bool { self == .trainingEnvironmentRequired }
}

extension FunctionalFitnessMaterializationError: TrainingEnvironmentRequirementError {
    var isTrainingEnvironmentRequired: Bool { self == .trainingEnvironmentRequired }
}

extension SteadyStateMaterializationError: TrainingEnvironmentRequirementError {
    var isTrainingEnvironmentRequired: Bool { self == .trainingEnvironmentRequired }
}

extension IntervalMaterializationError: TrainingEnvironmentRequirementError {
    var isTrainingEnvironmentRequired: Bool { self == .trainingEnvironmentRequired }
}

/// TE.1 final UX closure: `isTrainingEnvironmentRequired` above answers
/// only "was NO environment configured at all" — deliberately narrower
/// than "can the user recover by opening Training Environment
/// configuration." `.environmentIncompatible` (a real, configured
/// environment that just can't satisfy one slot/activity) is a distinct
/// failure meaning — never redefined as `.trainingEnvironmentRequired` —
/// but both recover through the exact same destination
/// (`TrainingEnvironmentSettingsView`). This second, wider protocol lets
/// UI ask that recovery-affordance question directly, without collapsing
/// the two cases into one or string-matching an error description.
protocol TrainingEnvironmentRecoverableError {
    var needsTrainingEnvironmentConfiguration: Bool { get }
}

extension ExerciseSlotResolutionError: TrainingEnvironmentRecoverableError {
    var needsTrainingEnvironmentConfiguration: Bool {
        switch self {
        case .trainingEnvironmentRequired, .environmentIncompatible: return true
        }
    }
}

extension FunctionalFitnessMaterializationError: TrainingEnvironmentRecoverableError {
    var needsTrainingEnvironmentConfiguration: Bool {
        switch self {
        case .trainingEnvironmentRequired, .environmentIncompatible: return true
        case .previousExposureRequired, .stimulusValidationFailed: return false
        }
    }
}

extension SteadyStateMaterializationError: TrainingEnvironmentRecoverableError {
    var needsTrainingEnvironmentConfiguration: Bool {
        switch self {
        case .trainingEnvironmentRequired, .environmentIncompatible: return true
        }
    }
}

extension IntervalMaterializationError: TrainingEnvironmentRecoverableError {
    var needsTrainingEnvironmentConfiguration: Bool {
        switch self {
        case .trainingEnvironmentRequired, .environmentIncompatible: return true
        case .previousOutcomeRequired: return false
        }
    }
}

/// TE.1 final UX closure: the one shared place that turns any of the 4
/// real error enums into the user-facing distinction the product contract
/// requires — "no Training Environment configured" vs. "your configured
/// environment is missing required equipment" — without any ViewModel
/// re-deriving it or string-matching. Returns `nil` for any error that
/// isn't Training-Environment-recoverable at all (the caller's existing
/// generic failure message applies instead). Deliberately small: this is
/// the minimum "clear failure" text the product contract asks for, not a
/// new equipment-conflict explanation UI.
func trainingEnvironmentRecoveryMessage(for error: Error) -> String? {
    if let error = error as? ExerciseSlotResolutionError {
        switch error {
        case .trainingEnvironmentRequired: return "A Training Environment is required before this can continue."
        case .environmentIncompatible(_, let missingEquipment): return missingEquipmentMessage(missingEquipment)
        }
    }
    if let error = error as? FunctionalFitnessMaterializationError {
        switch error {
        case .trainingEnvironmentRequired: return "A Training Environment is required before this can continue."
        case .environmentIncompatible(_, let missingEquipment): return missingEquipmentMessage(missingEquipment)
        case .previousExposureRequired, .stimulusValidationFailed: return nil
        }
    }
    if let error = error as? SteadyStateMaterializationError {
        switch error {
        case .trainingEnvironmentRequired: return "A Training Environment is required before this can continue."
        case .environmentIncompatible(_, let missingEquipment): return missingEquipmentMessage(missingEquipment)
        }
    }
    if let error = error as? IntervalMaterializationError {
        switch error {
        case .trainingEnvironmentRequired: return "A Training Environment is required before this can continue."
        case .environmentIncompatible(_, let missingEquipment): return missingEquipmentMessage(missingEquipment)
        case .previousOutcomeRequired: return nil
        }
    }
    return nil
}

private func missingEquipmentMessage(_ missingEquipment: [EquipmentRequirement]) -> String {
    let names = missingEquipment.map(\.displayName).sorted().joined(separator: ", ")
    return "Your configured Training Environment is missing equipment this requires: \(names)."
}
