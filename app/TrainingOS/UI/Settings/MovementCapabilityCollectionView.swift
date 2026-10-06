import SwiftUI

/// MUSCLE VERTICAL SLICE CONTINUATION, Sections 9-11: real, athlete-
/// driven capability collection — reached from Profile, matching the
/// existing "Set your starting weights" discoverable/non-blocking
/// precedent (`ProfileView`'s own doc comment). Not a wizard, not a
/// forced gate: a plain, editable list, exactly like
/// `TrainingPreferencesSettingsView`'s own shape.
struct MovementCapabilityCollectionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = MovementCapabilityCollectionViewModel()

    var body: some View {
        Form {
            Section {
                Text("For each movement, tell TrainingOS whether you can perform it reliably under real workout conditions, including fatigue. This is used to decide whether — and how much — the movement is safely programmed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(viewModel.rows) { row in
                Section(row.exercise.canonicalName) {
                    Toggle("Workout-ready", isOn: Binding(
                        get: { row.isWorkoutReady },
                        set: { viewModel.setWorkoutReady($0, for: row.id) }
                    ))
                    .accessibilityIdentifier("workoutReadyToggle.\(row.exercise.canonicalName)")

                    if row.isWorkoutReady {
                        HStack {
                            Text("Max unbroken reps")
                            Spacer()
                            TextField("e.g. 12", value: Binding(
                                get: { row.maxUnbrokenReps },
                                set: { viewModel.setMaxUnbrokenReps($0, for: row.id) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .accessibilityIdentifier("maxUnbrokenRepsField.\(row.exercise.canonicalName)")
                        }
                    }
                }
            }
        }
        .navigationTitle("Movement Capability")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if viewModel.save(modelContext: modelContext) {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("saveMovementCapabilityButton")
            }
        }
        .onAppear { viewModel.load(modelContext: modelContext) }
    }
}

#Preview {
    let container = PersistenceController.makeInMemoryContainer()
    SeedDataProvider.seedAll(in: container.mainContext)
    return NavigationStack {
        MovementCapabilityCollectionView()
    }
    .modelContainer(container)
}
