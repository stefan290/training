import Foundation
import SwiftData

/// The template-graph analogue of `ExercisePrescription` — reusable
/// methodology, not one user's dated execution. Carries rule
/// *parameters*, never a resolved number: "4x5-6 @ 2 RIR, load rule = X"
/// belongs here; "92.5 kg for Stefan" belongs to `Recommendation`/
/// `ExercisePrescription` once a `ProgramInstance` is materialized (Stage 4
/// architecture decision).
@Model
final class PrescriptionTemplate {
    @Attribute(.unique) var id: UUID
    var workoutBlockTemplate: WorkoutBlockTemplate?
    /// Stable position among a block template's slots, assigned by
    /// `WorkoutBlockTemplate.addPrescriptionTemplate(_:)`.
    var sortIndex: Int

    /// Cascade: an `ExerciseSlot` has no independent meaning outside its
    /// template.
    @Relationship(deleteRule: .cascade, inverse: \ExerciseSlot.prescriptionTemplate)
    var exerciseSlot: ExerciseSlot?

    // MARK: - Rule storage
    //
    // `LoadRule`/`SetCountRule` (enums with associated values) are never
    // stored directly, nor nested inside a `StrengthProgressionRules`
    // struct field. Two failure modes were found and fixed during this
    // pass's own round-trip tests:
    //   1. An enum case with 3+ associated values crashed
    //      `Decodable.init(from:)` with a dynamic-cast failure, regardless
    //      of the individual value types (fixed by bundling `.rmBased`'s 3
    //      values into one `RMBasedLoad` struct).
    //   2. Two `PrescriptionTemplate` rows in the same store holding
    //      *different* `LoadRule` cases silently decoded the second row's
    //      case as `nil` — confirmed with `IntensityTarget` (Stage 3C,
    //      unaffected) vs. `LoadRule` (affected) side by side, and
    //      confirmed independent of arity/array content. Root cause not
    //      fully isolated; the fix is structural, not case-shape tuning.
    //
    // The properties below are instead a manually flattened tagged union —
    // a discriminator `Kind` enum (plain `String` rawValue, no associated
    // values) plus one flat scalar/array field per case's parameter. This
    // is the same shape used everywhere else in this codebase for
    // anything that varies per row (e.g. `WorkoutResult`'s per-block-type
    // optional fields) and is proven safe under heterogeneous sibling
    // rows by this file's own diagnostic tests
    // (`TemplateGraphPersistenceTests`). `loadRule`/`setCountRule`/`rules`
    // below are computed convenience accessors — never themselves
    // persisted.
    var loadRuleKind: LoadRuleKind?
    var loadRuleRMType: RMType?
    var loadRuleWeekOneFactor: Double?
    var loadRuleLaterWeekMultipliers: [Double] = []
    var loadRuleFractionOfSourceResult: Double?

    var setCountRuleKind: SetCountRuleKind?
    var setCountRuleSetsByWeek: [Int] = []
    var setCountRuleBaselineSets: Int?
    /// `AutoregulatedSetCount`'s 2 extra fields (Stage 4B) — flat for the
    /// same reason as everything else here, though these two are plain
    /// `Bool`/`Int?` (not an enum-with-payload) so they were never at risk
    /// of the failure modes documented above; kept flat anyway for
    /// consistency with the rest of this tagged union.
    var setCountRuleApplyRatingOnFinalWeek: Bool = true
    var setCountRuleFreezeAfterWeek: Int?

    /// Parallel arrays, index-aligned — `RepGoal` is a plain struct with
    /// no enum-with-payload field, so it is not implicated in either
    /// failure mode above, but is kept flat anyway for consistency and
    /// because arrays of primitives are the single most-proven-safe shape
    /// in this codebase.
    var repGoalReps: [Int] = []
    var repGoalToFailure: [Bool] = []

    var deloadWeightAction: DeloadExerciseAction = DeloadExerciseAction.standard
    var deloadRepAction: DeloadExerciseAction = DeloadExerciseAction.standard
    var deloadRepFraction: Double = 0.5
    /// `DeloadPositionOverride` is a plain struct (`Int`/`Double` fields
    /// only, no enum-with-payload nested) — the already-proven-safe shape
    /// (`TrainingStressProfile`/`HypertrophyProgramConfiguration`), so
    /// these 2 are stored directly rather than needing further
    /// flattening.
    var deloadWeightPositionOverride: DeloadPositionOverride?
    var deloadRepPositionOverride: DeloadPositionOverride?
    var deloadSetCount: Int = 2

    /// Structural, authoring-time reference to another slot in the *same*
    /// template graph — the target of `autoregulatedSetCount`'s rating
    /// input or `LoadRule.linkedToPairedSlot`'s source result. Resolved
    /// once when the generator builds the graph; never re-resolved
    /// dynamically through recent training history (Stage 3 decision A5).
    var pairedSlot: PrescriptionTemplate?

    /// `pairedSlot`'s required inverse — nothing reads this collection.
    /// Needed only because an un-inversed to-one reference to a type that
    /// can be deleted crashes instead of nullifying cleanly; see
    /// `ProgramDefinition.instances`'s identical comment and
    /// `DELETE_RULE_MATRIX.md`.
    @Relationship(deleteRule: .nullify, inverse: \PrescriptionTemplate.pairedSlot)
    var referencedAsPairedSlotBy: [PrescriptionTemplate] = []

    /// Stage 6D addition: `ExercisePrescription.sourcePrescriptionTemplate`'s
    /// required inverse — nothing reads this collection directly (the
    /// resolver walks it via a fetch, not this relationship, since it
    /// needs the *instance*-scoped, chronologically-latest match — but a
    /// real inverse is still required for `.nullify` to work cleanly on
    /// delete, same reasoning as `referencedAsPairedSlotBy`). `.nullify`
    /// keeps every materialized movement (and its logged history) intact
    /// if this template's `ProgramDefinition` is later deleted (CLAUDE.md
    /// rule 1).
    @Relationship(deleteRule: .nullify, inverse: \ExercisePrescription.sourcePrescriptionTemplate)
    var materializedPrescriptions: [ExercisePrescription] = []

    init(id: UUID = UUID(), rules: StrengthProgressionRules? = nil) {
        self.id = id
        self.sortIndex = 0
        self.rules = rules
    }

    /// The only way application code should attach this slot's
    /// `ExerciseSlot`. Mutates exactly one side; SwiftData maintains
    /// `slot.prescriptionTemplate` from the declared inverse.
    func attachExerciseSlot(_ slot: ExerciseSlot) {
        exerciseSlot = slot
    }

    var loadRule: LoadRule? {
        get {
            // `if let` rather than `switch loadRuleKind` deliberately —
            // `LoadRuleKind` has its own case named `none`, which makes an
            // unqualified `case .none:` in a switch over `LoadRuleKind?`
            // ambiguous with the Optional's own `nil` case (a real Swift
            // pitfall, not a copy-paste slip).
            guard let kind = loadRuleKind else { return nil }
            switch kind {
            case .rmBased:
                guard let rmType = loadRuleRMType, let weekOneFactor = loadRuleWeekOneFactor else { return nil }
                return .rmBased(RMBasedLoad(rmType: rmType, weekOneFactor: weekOneFactor, laterWeekMultipliers: loadRuleLaterWeekMultipliers))
            case .linkedToPairedSlot:
                guard let fraction = loadRuleFractionOfSourceResult else { return nil }
                return .linkedToPairedSlot(fractionOfSourceResult: fraction)
            case .none:
                return LoadRule.none
            }
        }
        set {
            loadRuleRMType = nil
            loadRuleWeekOneFactor = nil
            loadRuleLaterWeekMultipliers = []
            loadRuleFractionOfSourceResult = nil
            guard let value = newValue else {
                loadRuleKind = nil
                return
            }
            switch value {
            case .rmBased(let payload):
                loadRuleKind = .rmBased
                loadRuleRMType = payload.rmType
                loadRuleWeekOneFactor = payload.weekOneFactor
                loadRuleLaterWeekMultipliers = payload.laterWeekMultipliers
            case .linkedToPairedSlot(let fraction):
                loadRuleKind = .linkedToPairedSlot
                loadRuleFractionOfSourceResult = fraction
            case .none:
                loadRuleKind = LoadRuleKind.none
            }
        }
    }

    var setCountRule: SetCountRule? {
        get {
            guard let kind = setCountRuleKind else { return nil }
            switch kind {
            case .fixed:
                return .fixed(setsByWeek: setCountRuleSetsByWeek)
            case .autoregulated:
                guard let baseline = setCountRuleBaselineSets else { return nil }
                return .autoregulated(AutoregulatedSetCount(
                    baselineSets: baseline,
                    applyRatingOnFinalWeek: setCountRuleApplyRatingOnFinalWeek,
                    freezeAfterWeek: setCountRuleFreezeAfterWeek
                ))
            }
        }
        set {
            setCountRuleSetsByWeek = []
            setCountRuleBaselineSets = nil
            setCountRuleApplyRatingOnFinalWeek = true
            setCountRuleFreezeAfterWeek = nil
            switch newValue {
            case .fixed(let sets):
                setCountRuleKind = .fixed
                setCountRuleSetsByWeek = sets
            case .autoregulated(let config):
                setCountRuleKind = .autoregulated
                setCountRuleBaselineSets = config.baselineSets
                setCountRuleApplyRatingOnFinalWeek = config.applyRatingOnFinalWeek
                setCountRuleFreezeAfterWeek = config.freezeAfterWeek
            case nil:
                setCountRuleKind = nil
            }
        }
    }

    var repGoalSchedule: [RepGoal] {
        get { zip(repGoalReps, repGoalToFailure).map { RepGoal(reps: $0, toFailure: $1) } }
        set {
            repGoalReps = newValue.map(\.reps)
            repGoalToFailure = newValue.map(\.toFailure)
        }
    }

    /// Ergonomic bundle over the flat stored properties above. `nil` only
    /// when neither `loadRule` nor `setCountRule` has been set.
    var rules: StrengthProgressionRules? {
        get {
            guard let loadRule, let setCountRule else { return nil }
            return StrengthProgressionRules(
                loadRule: loadRule,
                setCountRule: setCountRule,
                repGoalSchedule: repGoalSchedule,
                deloadWeightAction: deloadWeightAction,
                deloadRepAction: deloadRepAction,
                deloadRepFraction: deloadRepFraction,
                deloadRepPositionOverride: deloadRepPositionOverride,
                deloadWeightPositionOverride: deloadWeightPositionOverride,
                deloadSetCount: deloadSetCount
            )
        }
        set {
            loadRule = newValue?.loadRule
            setCountRule = newValue?.setCountRule
            repGoalSchedule = newValue?.repGoalSchedule ?? []
            deloadWeightAction = newValue?.deloadWeightAction ?? .standard
            deloadRepAction = newValue?.deloadRepAction ?? .standard
            deloadRepFraction = newValue?.deloadRepFraction ?? 0.5
            deloadRepPositionOverride = newValue?.deloadRepPositionOverride
            deloadWeightPositionOverride = newValue?.deloadWeightPositionOverride
            deloadSetCount = newValue?.deloadSetCount ?? 2
        }
    }
}
