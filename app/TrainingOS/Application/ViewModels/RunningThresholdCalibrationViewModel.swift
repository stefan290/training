import Foundation
import SwiftData

/// Running Athlete Journey Completion (Vertical Completion V1): drives
/// "Set your running pace" — the minimum UI necessary for a real athlete
/// to supply the Threshold Pace value `RequiredRunningCalibrationUseCase`
/// finds missing, before a %threshold-prescribed Running block can
/// honestly resolve a real target pace. Mirrors
/// `SourceRMCalibrationViewModel`'s exact discipline (never estimates,
/// converts, or pre-fills a value — the field always starts blank) with
/// one deliberate difference: Running's own materialization is NOT
/// deferred on calibration (`RunningProgramMaterializer.materializeAllWeeks`
/// already runs regardless — nothing in that program depends on a live
/// per-week result), so this view-model never calls a materialization use
/// case. Its only job is to persist the athlete's entry via
/// `RecordRunningThresholdCalibrationUseCase.record` so
/// `ThresholdPaceEngine`'s resolution path (`IntensityPresentation
/// .resolvedLabel`) has a real value to read.
@Observable
final class RunningThresholdCalibrationViewModel {
    private(set) var pendingInstance: ProgramInstance?
    /// View-local text entry, same pattern as `SourceRMCalibrationViewModel.Row.enteredText`.
    var enteredMinutesText: String = ""
    var enteredSecondsText: String = ""

    /// Whether there is anything to show — `RootTabView` uses this exactly
    /// like `SourceRMCalibrationViewModel.hasPendingCalibration`.
    var hasPendingCalibration: Bool { pendingInstance != nil }

    /// A real, parseable, positive mm:ss entry — never satisfied by an
    /// empty/zero value, so the athlete can't proceed with no real number
    /// (mirrors `SourceRMCalibrationViewModel.allSatisfied`'s same rule).
    var isSatisfied: Bool {
        guard let minutes = Int(enteredMinutesText), minutes >= 0 else { return false }
        let seconds = enteredSecondsText.isEmpty ? 0 : Int(enteredSecondsText)
        guard let seconds, (0..<60).contains(seconds) else { return false }
        return minutes > 0 || seconds > 0
    }

    /// Scans every `.active` `ProgramInstance` for an outstanding Running
    /// Threshold Pace requirement and loads the first one found — mirrors
    /// `SourceRMCalibrationViewModel.load`'s own "first is unambiguous in
    /// practice today" scoping note.
    func load(modelContext: ModelContext) {
        let instances = (try? modelContext.fetch(FetchDescriptor<ProgramInstance>())) ?? []
        for instance in instances where instance.status == .active {
            guard let definition = instance.programDefinition else { continue }
            if RequiredRunningCalibrationUseCase.isThresholdCalibrationRequired(for: definition, instance: instance) {
                pendingInstance = instance
                return
            }
        }
        pendingInstance = nil
    }

    /// Records the athlete's first-ever Threshold Pace entry via the real,
    /// already-gated use case (`isScheduledCheckpoint: false` — this is
    /// always the athlete's initial entry from this screen;
    /// `RunningThresholdRecalibrationGate` itself decides whether that's
    /// allowed, this view-model never second-guesses it) and clears the
    /// pending state only once persistence actually succeeds. Never
    /// called until `isSatisfied`.
    func completeCalibration(modelContext: ModelContext) {
        guard let instance = pendingInstance, isSatisfied else { return }
        guard let minutes = Int(enteredMinutesText) else { return }
        let seconds = enteredSecondsText.isEmpty ? 0 : (Int(enteredSecondsText) ?? 0)
        let totalSeconds = Double(minutes * 60 + seconds)
        let recorded = RecordRunningThresholdCalibrationUseCase.record(
            thresholdPaceSecondsPerKilometer: totalSeconds,
            for: instance,
            isScheduledCheckpoint: false,
            modelContext: modelContext
        )
        guard recorded != nil, (try? modelContext.save()) != nil else { return }
        pendingInstance = nil
        enteredMinutesText = ""
        enteredSecondsText = ""
    }
}
