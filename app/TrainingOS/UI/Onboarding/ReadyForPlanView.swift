import SwiftUI

/// Stage V1.Checkpoint 1's landing state: onboarding is complete (a real
/// Goal + Training Environment exist) but no strategic plan has been
/// accepted yet. Checkpoint 2 owns TrainingMix recommendation and plan
/// acceptance — this is deliberately a placeholder, not a preview of that
/// work.
struct ReadyForPlanView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 44))
                .foregroundStyle(Theme.primary)
            Text("You're all set")
                .font(Theme.heading)
                .foregroundStyle(Theme.textPrimary)
            Text("Your training plan is coming soon.")
                .font(Theme.body)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground)
    }
}

#Preview {
    ReadyForPlanView()
}
