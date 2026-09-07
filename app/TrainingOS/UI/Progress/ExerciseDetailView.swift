import SwiftUI

/// V1 R4 (Progress reconciliation): the approved design's "exercise
/// detail" depth screen (`Training OS.dc.html` screen 15, "current vs
/// all-time"), expressed through real, current domain truth only.
///
/// **A real, disclosed adaptation of the mockup's literal framing:**
/// `ExercisePerformanceProfile` stores only the engine's CURRENT
/// `estimatedOneRepMax` — there is no persisted history of what that
/// estimate was at any earlier point, so a true "all-time e1RM" (the
/// highest the *estimate* itself ever reached) cannot be shown without
/// inventing a second estimation formula, which this checkpoint's own
/// instructions forbid. Instead this screen shows two real, honestly
/// distinct facts: the engine's current estimate, and the athlete's real
/// heaviest logged `PersonalRecord` (an actual lifted weight, its own
/// real rep count when a source `SetResult` is still linked, never
/// converted through any 1RM formula) — labeled for what they actually
/// are rather than force-fit into one "current vs all-time e1RM" pair.
struct ExerciseDetailView: View {
    let profile: ExercisePerformanceProfile

    private var heaviestRecord: PersonalRecord? {
        profile.personalRecords
            .filter { $0.context == .rx }
            .max { $0.value < $1.value }
    }

    /// Real records-by-rep-band, one row per real distinct band that has
    /// at least one Rx record — never fabricated bands, never Scaled
    /// results shown as if they competed with Rx.
    private var recordsByRepBand: [PersonalRecord] {
        let rxRecords = profile.personalRecords.filter { $0.context == .rx && $0.repBand != nil }
        var bestByBand: [String: PersonalRecord] = [:]
        for record in rxRecords {
            guard let band = record.repBand else { continue }
            if let existing = bestByBand[band], existing.value >= record.value { continue }
            bestByBand[band] = record
        }
        return bestByBand.values.sorted { ($0.repBand ?? "") < ($1.repBand ?? "") }
    }

    private var recentSets: [SetResult] {
        Array(profile.orderedSetResults.reversed().prefix(10))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                estimateTiles
                if !recordsByRepBand.isEmpty {
                    recordsCard
                }
                if !recentSets.isEmpty {
                    recentSetsCard
                }
            }
            .padding(Theme.screenPadding)
        }
        .background(Theme.ground)
        .navigationTitle(profile.exercise?.canonicalName ?? "Exercise")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.exercise?.canonicalName ?? "Exercise")
                .font(Theme.headingXL)
                .foregroundStyle(Theme.textPrimary)
            if let equipment = profile.exercise?.equipment {
                Text(equipment.capitalized)
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder private var estimateTiles: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CURRENT ESTIMATE")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.primary)
                if let estimate = profile.estimatedOneRepMax {
                    Text(formattedWeight(estimate))
                        .font(Theme.numeric.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let lastPerformedAt = profile.lastPerformedAt {
                        Text(ProgressPresentation.recencyLabel(lastPerformedAt, asOf: Date()) + " · " + ProgressPresentation.confidenceLabel(profile.confidence))
                            .font(Theme.label)
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Text("Not enough data yet")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .trainingOSCard(emphasized: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("BEST RECORDED LIFT")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
                if let heaviestRecord {
                    Text(formattedWeight(heaviestRecord.value))
                        .font(Theme.numeric.weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(heaviestRecord.achievedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("No PR yet")
                        .font(Theme.label)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .trainingOSCard()
        }
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Records by rep band").padding(.bottom, 10)
            ForEach(Array(recordsByRepBand.enumerated()), id: \.element.id) { index, record in
                HStack {
                    Text(record.repBand ?? "")
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if let reps = record.sourceSetResult?.reps {
                        Text("\(formattedWeight(record.value)) × \(reps)")
                            .font(Theme.numeric.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text(formattedWeight(record.value))
                            .font(Theme.numeric.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(Theme.label)
                        .foregroundStyle(Theme.textInactive)
                        .frame(width: 74, alignment: .trailing)
                }
                .padding(.vertical, 8)
                if index < recordsByRepBand.count - 1 { Divider().opacity(0.4) }
            }
        }
        .trainingOSCard()
    }

    private var recentSetsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Recent sets").padding(.bottom, 10)
            ForEach(Array(recentSets.enumerated()), id: \.element.id) { index, set in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formattedWeight(set.weight)) × \(set.reps)")
                        .font(Theme.numeric)
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text(set.completedAt.formatted(date: .abbreviated, time: .omitted))
                        if let rir = set.actualRir {
                            Text("· RIR \(rir)")
                        }
                    }
                    .font(Theme.label)
                    .foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 8)
                if index < recentSets.count - 1 { Divider().opacity(0.4) }
            }
        }
        .trainingOSCard()
    }

    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
