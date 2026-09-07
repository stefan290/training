import Foundation
import SwiftData
import Observation

/// V1 R4 (Progress reconciliation): the real, permanent record Progress
/// reads from — `PerformanceProfile`'s own `exerciseProfiles`/
/// `activityProfiles`/`benchmarkProfiles`, plus a read-only, real
/// derivation of recent training consistency from persisted `Session`
/// status. Fundamentally read-only: this type performs zero writes and
/// recalculates nothing that `RecordSetResultUseCase`/
/// `RecordFunctionalFitnessResultUseCase`/etc. already own — it only
/// reads and reshapes what those use cases already decided.
@Observable
final class ProgressViewModel {
    /// A single real, already-canonical `PersonalRecord` — from an
    /// exercise, an activity, or a benchmark — reshaped into one common,
    /// presentable label. Never a fabricated record; `label`/`valueLabel`
    /// are pure formatting over the record's own real fields.
    struct RecordSummary: Identifiable {
        let id: UUID
        let label: String
        let valueLabel: String
        let achievedAt: Date
        let context: ResultContext
    }

    private(set) var exerciseProfiles: [ExercisePerformanceProfile] = []
    private(set) var benchmarkProfiles: [BenchmarkPerformanceProfile] = []
    /// Every real canonical `PersonalRecord` achieved within the last 7
    /// real days, most recent first — the approved design's "New this
    /// week" callout. Empty (never a fabricated "0 PRs" state) when none
    /// exist.
    private(set) var recentRecords: [RecordSummary] = []
    /// `nil` when there is no honest recent window to report against (no
    /// real Session has a real, already-passed scheduled date yet) —
    /// never a fabricated 0%. `(completed, eligible)` where `eligible` is
    /// every real Session whose own real Day falls on or before
    /// `referenceDate` within the trailing 28 days, and `completed` is
    /// however many of those are truthfully `.completed` — no session
    /// that never existed, no future session, no R0 pre-program day (none
    /// exist to query in the first place), no fabricated debt.
    private(set) var consistency: (completed: Int, eligible: Int)?

    /// Whether Progress has ANY real history at all — the signal for the
    /// intentional empty state (a brand-new athlete), never inferred from
    /// any single sub-collection being empty (a strength-only athlete
    /// with zero benchmark history is not "no history").
    var hasAnyHistory: Bool {
        !exerciseProfiles.isEmpty || !benchmarkProfiles.isEmpty
    }

    func load(modelContext: ModelContext, referenceDate: Date = Date()) {
        let users = (try? modelContext.fetch(FetchDescriptor<User>())) ?? []
        let performanceProfile = users.first?.performanceProfile

        exerciseProfiles = (performanceProfile?.exerciseProfiles ?? []).sorted {
            ($0.lastPerformedAt ?? .distantPast) > ($1.lastPerformedAt ?? .distantPast)
        }
        benchmarkProfiles = (performanceProfile?.benchmarkProfiles ?? []).sorted {
            ($0.lastPerformedAt ?? .distantPast) > ($1.lastPerformedAt ?? .distantPast)
        }

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        var records: [RecordSummary] = []
        for profile in exerciseProfiles {
            for record in profile.personalRecords where record.achievedAt >= weekAgo && record.achievedAt <= referenceDate {
                let reps = record.sourceSetResult?.reps
                let valueLabel = reps.map { "\(formattedWeight(record.value)) × \($0)" } ?? formattedWeight(record.value)
                records.append(RecordSummary(
                    id: record.id, label: profile.exercise?.canonicalName ?? "Exercise",
                    valueLabel: valueLabel, achievedAt: record.achievedAt, context: record.context
                ))
            }
        }
        for profile in benchmarkProfiles {
            for record in profile.personalRecords where record.achievedAt >= weekAgo && record.achievedAt <= referenceDate {
                let scoreLabel = record.sourceFunctionalFitnessResult.map { ProgressPresentation.scoreValueLabel($0.scoreValue) } ?? formattedWeight(record.value)
                let suffix = record.context == .rx ? "" : " Sc"
                records.append(RecordSummary(
                    id: record.id, label: profile.benchmark?.name ?? "Benchmark",
                    valueLabel: "\(scoreLabel)\(suffix)", achievedAt: record.achievedAt, context: record.context
                ))
            }
        }
        recentRecords = records.sorted { $0.achievedAt > $1.achievedAt }

        consistency = Self.consistency(modelContext: modelContext, referenceDate: referenceDate)
    }

    /// Real, read-only derivation over persisted `Session`/`Day` state —
    /// no new domain semantics. Window: the trailing 28 real days
    /// (inclusive of `referenceDate`). A `Session` is "eligible" once its
    /// own real `Day.date` has arrived; `.completed` is the only status
    /// counted as adherence — `.scheduled`/`.inProgress` on a day that has
    /// already passed are real, honest non-adherence (mirrors
    /// `SessionStatus`'s own real, already-persisted truth, never
    /// re-derived). Returns `nil` when zero eligible Sessions exist in
    /// the window (a brand-new athlete, or one whose program has not
    /// truthfully started yet per R0) — never a fabricated 0%.
    private static func consistency(modelContext: ModelContext, referenceDate: Date) -> (completed: Int, eligible: Int)? {
        let windowStart = Calendar.current.date(byAdding: .day, value: -28, to: referenceDate) ?? referenceDate
        let days = (try? modelContext.fetch(FetchDescriptor<Day>())) ?? []
        let eligibleSessions = days
            .filter { $0.date >= windowStart && $0.date <= referenceDate }
            .flatMap(\.orderedSessions)
        guard !eligibleSessions.isEmpty else { return nil }
        let completed = eligibleSessions.filter { $0.status == .completed }.count
        return (completed, eligibleSessions.count)
    }

    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
