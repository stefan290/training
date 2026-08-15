import Foundation

/// A calendar weekday, independent of any specific date — used by
/// `UserAvailability`/`TrainingMixComponent` to express recurring
/// weekly preferences (Stage 4F §15).
enum Weekday: Int, Codable, CaseIterable {
    case monday = 1
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

/// Which of the two mixes a `TrainingMix` represents (§3) — the system's
/// preferred composition for the current phase, or the one the user
/// actually chose. Both are real, persisted, comparable objects; neither
/// is a UI-only concept.
enum TrainingMixKind: String, Codable, CaseIterable {
    case recommended
    case selected
}

/// §39: whether a component's requested frequency can be reduced or
/// dropped under scheduling pressure. Never inferred from modality —
/// set explicitly by whoever authors the mix (a recommender, or the
/// user), per §39's own instruction.
enum ComponentFlexibility: String, Codable, CaseIterable {
    case required
    case preferred
    case optional
}

/// §44: the key information is that the user actively selected this mix
/// — not an attempt to predict motivation or adherence algorithmically.
/// Only meaningful on a `.selected` `TrainingMix`; `nil` on a
/// `.recommended` one (the system doesn't "prefer" its own recommendation
/// at varying strength).
enum PreferenceStrength: String, Codable, CaseIterable {
    case systemRecommended
    case userPrefers
    case userStronglyPrefers
}

/// §4/§42: "min/target/max where useful... do not require all components
/// to have ranges if a fixed count is sufficient" — the smallest clean
/// model that satisfies both. A fixed count is `SessionFrequency(target:
/// 3)`; a real range is `SessionFrequency(target: 2, minimum: 1, maximum: 3)`.
struct SessionFrequency: Codable, Equatable {
    var target: Int
    /// `nil` means "no explicit floor beyond hitting target if possible."
    var minimum: Int?
    /// `nil` means "no explicit ceiling beyond target."
    var maximum: Int?

    init(target: Int, minimum: Int? = nil, maximum: Int? = nil) {
        self.target = target
        self.minimum = minimum
        self.maximum = maximum
    }
}
