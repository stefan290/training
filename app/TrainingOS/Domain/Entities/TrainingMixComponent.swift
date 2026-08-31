import Foundation
import SwiftData

/// One training component inside a `TrainingMix` (Stage 4F §4-5) — e.g.
/// "Hypertrophy, 3 sessions/week, primary" or "Functional Fitness, 2
/// sessions/week, supporting." Deliberately typed fields, never an
/// arbitrary dictionary (§4's explicit instruction).
///
/// `programInstance` is **optional by design** — a `.recommended`
/// `TrainingMix`'s components describe a proposed composition before any
/// `ProgramInstance` exists for it (§3's own example: "Recommended: 5
/// Hypertrophy + 2 Zone 2" names no concrete instance yet). Once a
/// component is actually instantiated (a `.selected` mix, or a
/// recommendation the user accepted), `programInstance` is set to the
/// real, already-materialized `ProgramInstance` that
/// `HypertrophyProgramGenerator`/`SteadyStateProgramGenerator`/etc.
/// already produced — `TrainingMixComponent` never duplicates that
/// instance's own data (§5's explicit warning), it only adds the
/// scheduling-relevant metadata `ProgramInstance` itself doesn't carry
/// (frequency/flexibility/preferred days/spacing).
///
/// `priority` is this component's own field, not read from
/// `programInstance.priority` — necessarily, since a recommended,
/// not-yet-instantiated component has no `ProgramInstance` to read from
/// at all. Once `programInstance` is set, the two are expected to agree
/// (an application-layer invariant, not enforced by a sync mechanism
/// here — see `TRAINING_MIX.md` for the full reasoning).
@Model
final class TrainingMixComponent {
    @Attribute(.unique) var id: UUID
    var trainingMix: TrainingMix?
    /// The delete rule lives on `ProgramInstance.trainingMixComponents`
    /// — this side is a plain inverse property, same pattern as
    /// `TrainingWeek.programDefinition`.
    var programInstance: ProgramInstance?
    /// A human-readable label for this component even before any
    /// `ProgramInstance` exists — e.g. "Hypertrophy," "Functional
    /// Fitness," "Easy Running."
    var label: String
    /// Which `ProgrammingSystem` this component represents — knowable
    /// even before instantiation, unlike `programInstance`.
    var programmingSystem: ProgrammingSystemKind?
    var priority: GoalPriority
    /// Stage CP.2 addition: this component's own real
    /// `AdaptationObjective`s — orthogonal to `priority` (which answers
    /// "how protected," never "why present"). Empty is a real, honest
    /// state (not every `LongTermPlanner` builder yet has per-sub-
    /// objective signal for every component it constructs — see
    /// `TRAINING_MIX_CONCURRENT_PROGRAMMING_DESIGN.md`'s product-decision
    /// table), never defaulted to a fabricated non-empty guess.
    var adaptationObjectives: [AdaptationObjective]
    var frequency: SessionFrequency
    var flexibility: ComponentFlexibility
    /// §4: "whether double sessions are permitted" — this component's
    /// own opt-in/out, checked together with `UserAvailability.allowsDoubleSessions`
    /// (both must allow it for `ConcurrentScheduler` to pair this
    /// component's sessions same-day with another).
    var allowsDoubleSessionPairing: Bool
    var preferredDays: [Weekday]
    /// §5: "requiredSpacing if methodology defines it" — minimum days
    /// between two of this component's own sessions, e.g. a hard
    /// interval session requiring recovery before the next one. `nil`
    /// means no explicit spacing requirement.
    var requiredSpacingDays: Int?
    /// Stable position among a mix's components, assigned by
    /// `TrainingMix.addComponent(_:)`.
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        label: String,
        programmingSystem: ProgrammingSystemKind? = nil,
        priority: GoalPriority,
        adaptationObjectives: [AdaptationObjective] = [],
        frequency: SessionFrequency,
        flexibility: ComponentFlexibility = .preferred,
        allowsDoubleSessionPairing: Bool = true,
        preferredDays: [Weekday] = [],
        requiredSpacingDays: Int? = nil
    ) {
        self.id = id
        self.label = label
        self.programmingSystem = programmingSystem
        self.priority = priority
        self.adaptationObjectives = adaptationObjectives
        self.frequency = frequency
        self.flexibility = flexibility
        self.allowsDoubleSessionPairing = allowsDoubleSessionPairing
        self.preferredDays = preferredDays
        self.requiredSpacingDays = requiredSpacingDays
        self.sortIndex = 0
    }
}
