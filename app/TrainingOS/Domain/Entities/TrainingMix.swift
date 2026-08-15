import Foundation
import SwiftData

/// A named, typed training composition (Stage 4F §3-4) — e.g. "Muscle
/// Gain Hybrid: 3 Strength/Hypertrophy + 2 Functional Fitness + 1
/// Running." Exactly one of two kinds (`TrainingMixKind`): the system's
/// `.recommended` composition for a `TrainingPhase`, or the `.selected`
/// one the user actually chose to perform — both are real, comparable,
/// persisted objects, never a UI-only concept. They may differ (§3);
/// `ConcurrentScheduler` schedules whichever is `.selected` (§7/§36 — a
/// user's accepted choice is never silently overwritten back to the
/// recommendation).
///
/// **Temporary mixes** (§11/§45): `validFrom`/`validUntil` let a mix
/// apply for a bounded window ("CrossFit for the next 4 weeks") without
/// touching the enclosing `TrainingPlan`/`TrainingPhase` at all — the
/// annual plan and every `PerformanceProfile` remain exactly as they
/// were; only which `TrainingMix` is currently active changes. `nil`
/// bounds mean "active until explicitly superseded," the common case.
@Model
final class TrainingMix {
    @Attribute(.unique) var id: UUID
    var kind: TrainingMixKind
    var name: String
    /// The delete rule lives on `TrainingPhase.trainingMixes` — this side
    /// is a plain inverse property, same pattern as
    /// `TrainingWeek.programDefinition`.
    var phase: TrainingPhase?
    var validFrom: Date?
    var validUntil: Date?
    /// Only meaningful when `kind == .selected` — see
    /// `PreferenceStrength`'s own doc comment.
    var preferenceStrength: PreferenceStrength?

    @Relationship(deleteRule: .cascade, inverse: \TrainingMixComponent.trainingMix)
    var components: [TrainingMixComponent] = []

    init(
        id: UUID = UUID(),
        kind: TrainingMixKind,
        name: String,
        validFrom: Date? = nil,
        validUntil: Date? = nil,
        preferenceStrength: PreferenceStrength? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.validFrom = validFrom
        self.validUntil = validUntil
        self.preferenceStrength = preferenceStrength
    }

    /// The only way application code should attach a `TrainingMixComponent`.
    /// Mutates exactly one side (this array); SwiftData maintains
    /// `component.trainingMix` from the declared inverse.
    func addComponent(_ component: TrainingMixComponent) {
        component.sortIndex = components.count
        components.append(component)
    }

    var orderedComponents: [TrainingMixComponent] {
        components.sorted { $0.sortIndex < $1.sortIndex }
    }
}
