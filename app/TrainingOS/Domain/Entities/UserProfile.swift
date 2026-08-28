import Foundation
import SwiftData

/// Mutable training preferences. Deliberately narrow in this pass — the
/// full Availability model (training days/week, minutes/day, doubles,
/// occasional long sessions) belongs to the planning engine work and is not
/// implemented here.
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var user: User?

    var weightUnit: WeightUnit
    /// Smallest loadable increment per equipment type, e.g. ["barbell": 2.5,
    /// "dumbbell": 2.0]. Kept as a flat dictionary rather than a modelled
    /// equipment entity — sufficient for stepper math, not a gear catalog.
    var equipmentIncrements: [String: Double]
    /// Stage 10R.5, D-10R5-15/16: the profile-level default for whether a
    /// newly-created, compatible `ProgramInstance` uses the recovered
    /// source program's own fixed schedule or TrainingOS's load-first
    /// overlay on top of it. `.loadFocused` is the approved DEFAULT for
    /// new instances — a deliberate TrainingOS product preference, never
    /// itself claimed as source behavior. `ProgramInstance
    /// .progressionStyleOverride` always wins over this when set; SOURCE
    /// mode remains permanently selectable regardless of this default.
    var preferredProgressionStyle: ProgressionStyle

    init(
        id: UUID = UUID(),
        weightUnit: WeightUnit = .kilograms,
        equipmentIncrements: [String: Double] = ["barbell": 2.5, "dumbbell": 2.0, "machine": 5.0],
        preferredProgressionStyle: ProgressionStyle = .loadFocused
    ) {
        self.id = id
        self.weightUnit = weightUnit
        self.equipmentIncrements = equipmentIncrements
        self.preferredProgressionStyle = preferredProgressionStyle
    }
}
