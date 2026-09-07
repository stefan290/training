import Foundation

/// V1 R4 (Progress reconciliation): pure display-string mapping for
/// Progress's real domain concepts — mirrors `PlanPresentation`'s own
/// established pattern (one file per surface, no business logic, only
/// translating real engine/domain values into athlete language).
enum ProgressPresentation {
    /// Translates `ExercisePerformanceProfile.confidence` (a continuous
    /// 0...1 engine value, lowered by RECENCY_DECAY) into the approved
    /// product's descriptive language — never shown as a raw number to
    /// the athlete. These three tiers are a presentation-only choice
    /// (never a persisted threshold, never fed back into any engine
    /// decision) — the underlying continuous value is preserved exactly
    /// as the engine computed it.
    static func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case 0.7...: "high confidence"
        case 0.35..<0.7: "moderate confidence"
        default: "low confidence"
        }
    }

    /// "3 d ago" / "Today" / "5 mo ago" — a compact, real-elapsed-time
    /// label from a real timestamp. `nil` (never performed) is the
    /// caller's responsibility to handle — this only formats a real date.
    static func recencyLabel(_ date: Date, asOf: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: date), to: Calendar.current.startOfDay(for: asOf)).day ?? 0
        if days <= 0 { return "Today" }
        if days == 1 { return "1 d ago" }
        if days < 30 { return "\(days) d ago" }
        if days < 60 { return "1 mo ago" }
        return "\(days / 30) mo ago"
    }

    /// Whether `lastPerformedAt` is old enough that showing its numeric
    /// estimate without qualification would be misleading — a real,
    /// disclosed product judgment call (90 days), never a silent
    /// assumption baked into the number itself. Distinct from
    /// `confidence` (an engine-computed value) — this is purely about
    /// how long ago the underlying set was actually logged.
    static func isStale(lastPerformedAt: Date, asOf: Date) -> Bool {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: lastPerformedAt), to: Calendar.current.startOfDay(for: asOf)).day ?? 0
        return days > 90
    }

    static func resultContextLabel(_ context: ResultContext) -> String {
        switch context {
        case .rx: "Rx"
        case .scaled: "Scaled"
        }
    }

    /// A real, already-logged `ScoreValue` formatted for display — never
    /// a derived/estimated number. `roundsAndReps` mirrors the approved
    /// design's own "rounds + reps" compact notation.
    static func scoreValueLabel(_ value: ScoreValue) -> String {
        switch value {
        case .time(let seconds):
            let minutes = seconds / 60
            let remainder = seconds % 60
            return String(format: "%d:%02d", minutes, remainder)
        case .roundsAndReps(let rounds, let partialReps):
            return partialReps > 0 ? "\(rounds)+\(partialReps)" : "\(rounds)"
        case .repetitions(let reps):
            return "\(reps) reps"
        case .calories(let calories):
            return "\(calories) cal"
        case .distance(let meters):
            return meters >= 1000 ? String(format: "%.2f km", meters / 1000) : "\(Int(meters)) m"
        case .load(let kilograms):
            return kilograms.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f kg", kilograms) : String(format: "%.1f kg", kilograms)
        case .completedIntervals(let count):
            return "\(count) intervals"
        }
    }

    /// The approved design's explicit "lower is better, stated" principle
    /// — never left implicit for a time/rounds-based result the athlete
    /// might otherwise misread as "bigger number = better."
    static func scoreDirectionLabel(_ direction: ScoreDirection) -> String {
        switch direction {
        case .lowerIsBetter: "Lower is better"
        case .higherIsBetter: "Higher is better"
        }
    }
}
