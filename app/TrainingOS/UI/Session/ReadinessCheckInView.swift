import SwiftUI
import SwiftData

/// Stage 8B: the pre-workout readiness check-in — Tier 0 (3 taps) + Tier
/// 0.5 gateway (1 tap) + conditional Tier 1, exactly the flow
/// `READINESS_UX_FLOW.md` §1-2 specifies. Presented `.fullScreenCover`
/// before the Start transition fires, mirroring `HypertrophyFeedbackView`'s
/// own precedent at the other end of a session. Never a medical
/// questionnaire: no severity slider, no free text, no diagnosis language
/// anywhere in this view (Stage 8B §6).
struct ReadinessCheckInView: View {
    let session: Session
    /// `nil` means the user tapped Skip — no `ReadinessCheckIn` is built at
    /// all, matching `READINESS_MODEL.md` §5's "skipped is `nil`, never a
    /// defaulted-to-good row" rule.
    let onSubmit: (ReadinessCheckIn?) -> Void

    @State private var sleep: ReadinessLevel?
    @State private var energy: ReadinessLevel?
    @State private var overallRecovery: ReadinessLevel?
    @State private var gatewayAnswered = false
    @State private var hasPainOrStiffness = false
    @State private var showingTier1 = false
    @State private var reportsPain = false
    @State private var reportsStiffness = false
    @State private var selectedPainAreas: Set<MuscleGroup> = []
    @State private var selectedStiffnessAreas: Set<MuscleGroup> = []
    @State private var selectedSoreAreas: Set<MuscleGroup> = []

    /// Only the muscle groups TODAY's own materialized session actually
    /// trains — never a generic full-body picker (`READINESS_MODEL.md` §1/§5).
    private var todaysMuscleGroups: [MuscleGroup] {
        var groups = Set<MuscleGroup>()
        for block in session.orderedBlocks {
            for prescription in block.orderedPrescriptions {
                groups.formUnion(prescription.exercise?.primaryTargets ?? [])
            }
            if let ffPrescription = block.functionalFitnessPrescription {
                for movement in ffPrescription.orderedMovements {
                    groups.formUnion(movement.exercise?.primaryTargets ?? [])
                }
            }
        }
        return MuscleGroup.allCases.filter { groups.contains($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Before you start")
                        .font(Theme.heading)
                        .foregroundStyle(Theme.textPrimary)

                    levelRow(title: "Sleep", labels: ("Poor", "OK", "Good"), selection: $sleep)
                    levelRow(title: "Energy", labels: ("Low", "Normal", "High"), selection: $energy)
                    levelRow(title: "Overall recovery", labels: ("Sore", "Normal", "Fresh"), selection: $overallRecovery)

                    if overallRecovery == .poor && !todaysMuscleGroups.isEmpty {
                        areaPicker(title: "Where do you feel sore?", selection: $selectedSoreAreas)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Pain or stiffness today?")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 10) {
                            Button("No") { answerGateway(false) }
                                .buttonStyle(.bordered)
                            Button("Yes") { answerGateway(true) }
                                .buttonStyle(.bordered)
                        }
                    }

                    if showingTier1 {
                        VStack(alignment: .leading, spacing: 16) {
                            Toggle("Pain / discomfort", isOn: $reportsPain)
                            if reportsPain && !todaysMuscleGroups.isEmpty {
                                areaPicker(title: "Where?", selection: $selectedPainAreas)
                            }
                            Toggle("Stiffness / limited mobility", isOn: $reportsStiffness)
                            if reportsStiffness && !todaysMuscleGroups.isEmpty {
                                areaPicker(title: "Where?", selection: $selectedStiffnessAreas)
                            }
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 12)

                    Button("Continue", action: submit)
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                        .frame(maxWidth: .infinity)
                        .disabled(!canContinue)

                    Button("Skip check-in") { onSubmit(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(16)
            }
            .background(Theme.ground)
            .navigationTitle("Readiness")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// The fast path only requires the gateway to have been answered —
    /// Tier 0's three levels are optional (a skipped individual field is
    /// legitimate "no signal," never blocking, per `READINESS_MODEL.md` §5).
    private var canContinue: Bool { gatewayAnswered }

    private func answerGateway(_ yes: Bool) {
        gatewayAnswered = true
        hasPainOrStiffness = yes
        showingTier1 = yes
    }

    private func submit() {
        let checkIn = ReadinessCheckIn(
            recordedAt: Date(),
            sleep: sleep,
            energy: energy,
            overallRecovery: overallRecovery,
            soreMuscleGroups: Array(selectedSoreAreas),
            reportedPain: reportsPain ? Array(selectedPainAreas) : [],
            reportedStiffness: reportsStiffness ? Array(selectedStiffnessAreas) : []
        )
        onSubmit(checkIn)
    }

    private func levelRow(title: String, labels: (poor: String, ok: String, good: String), selection: Binding<ReadinessLevel?>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.body)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 10) {
                levelButton(labels.poor, level: .poor, selection: selection)
                levelButton(labels.ok, level: .ok, selection: selection)
                levelButton(labels.good, level: .good, selection: selection)
            }
        }
    }

    private func levelButton(_ label: String, level: ReadinessLevel, selection: Binding<ReadinessLevel?>) -> some View {
        Button(label) { selection.wrappedValue = level }
            .buttonStyle(.bordered)
            .tint(selection.wrappedValue == level ? Theme.primary : nil)
    }

    private func areaPicker(title: String, selection: Binding<Set<MuscleGroup>>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.label)
                .foregroundStyle(Theme.textSecondary)
            FlowChips(items: todaysMuscleGroups, selection: selection)
        }
    }
}

/// Minimal multi-select chip row — no external dependency, no scientific
/// design intent, just a compact tappable list.
private struct FlowChips: View {
    let items: [MuscleGroup]
    @Binding var selection: Set<MuscleGroup>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let isSelected = selection.contains(item)
                    Button(item.rawValue.capitalized) {
                        if isSelected { selection.remove(item) } else { selection.insert(item) }
                    }
                    .buttonStyle(.bordered)
                    .tint(isSelected ? Theme.primary : nil)
                }
            }
        }
    }
}
