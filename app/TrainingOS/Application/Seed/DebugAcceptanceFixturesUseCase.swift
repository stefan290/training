import Foundation
import SwiftData

/// Stage 8B manual-acceptance aid, **debug-only** (compiled out of
/// Release builds — see `TodayView`'s `#if DEBUG` call site). Not a
/// production feature, not a change to any start-eligibility rule: it
/// creates several independent, ad-hoc Sessions scheduled for TODAY so
/// the six Stage 8B acceptance scenarios can each be exercised on their
/// own session without needing to start a future-dated Session early.
///
/// Every Session here is deliberately `programInstance: nil` — the
/// existing, already-documented "a Session can be logged ad hoc, outside
/// any active program instance" case (`Session.swift`'s own doc comment),
/// not a new concept. Nothing here touches `ProgramInstance`,
/// `TrainingPhase`, `TrainingMix`, `TacticalWindowPolicy`, or any
/// existing Session/Day — this only ever inserts new, independent rows.
/// Reuses the real, already-seeded `Exercise` catalog rather than
/// inserting a second one (`Exercise.canonicalName` is unique).
enum DebugAcceptanceFixturesUseCase {
    private static let markerPrefix = "Acceptance — "

    /// Idempotent: a second tap is a no-op if today's acceptance fixtures
    /// already exist, so this is safe to wire to a plain repeatable button.
    static func seedIfNeeded(context: ModelContext) throws {
        let today = Calendar.current.startOfDay(for: Date())
        let existing = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        let alreadySeeded = existing.contains {
            $0.name.hasPrefix(markerPrefix) && Calendar.current.isDate($0.day?.date ?? .distantPast, inSameDayAs: today)
        }
        guard !alreadySeeded else { return }

        guard let user = try context.fetch(FetchDescriptor<User>()).first else { return }
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        func exercise(_ name: String) -> Exercise? { exercises.first { $0.canonicalName == name } }

        let day = Day(ownerUserID: user.id, date: today)
        context.insert(day)

        func makeSession(_ name: String) -> Session {
            let session = Session(name: markerPrefix + name, modality: .strength, status: .scheduled)
            context.insert(session)
            day.addSession(session)
            return session
        }

        func addExercise(
            _ exercise: Exercise, to session: Session, sets: Int, reps: Int, weight: Double, rir: Int = 0, slot: ExerciseSlot? = nil
        ) {
            let block = WorkoutBlock(type: .strength)
            context.insert(block)
            session.addBlock(block)
            let prescription = ExercisePrescription(exercise: exercise)
            prescription.sourceExerciseSlot = slot
            context.insert(prescription)
            block.addPrescription(prescription)
            for _ in 0..<sets {
                let set = SetPrescription(repRangeLow: reps, repRangeHigh: reps, targetWeight: weight, targetRir: rir)
                context.insert(set)
                prescription.addSetPrescription(set)
            }
        }

        // Scenario 1 — good day.
        if let backSquat = exercise("Back Squat") {
            addExercise(backSquat, to: makeSession("Good Day"), sets: 3, reps: 6, weight: 60)
        }

        // Scenario 2 — low readiness, reject then accept (two independent sessions).
        if let romanianDeadlift = exercise("Romanian Deadlift") {
            addExercise(romanianDeadlift, to: makeSession("Low Readiness (reject this one)"), sets: 4, reps: 8, weight: 80)
            addExercise(romanianDeadlift, to: makeSession("Low Readiness (accept this one)"), sets: 4, reps: 8, weight: 80)
        }

        // Scenario 3 — local pain must only affect the compatible exercise.
        // Back Squat gets a real slot-valid alternative (Front Squat) so a
        // genuine Level 3 substitution can be demonstrated, not just the
        // no-alternative fallback.
        if let backSquat = exercise("Back Squat"), let frontSquat = exercise("Front Squat"), let benchPress = exercise("Barbell Bench Press") {
            let painScenario = makeSession("Local Pain")
            let squatSlot = ExerciseSlot(name: "Acceptance Squat Slot", allowedExercises: [backSquat, frontSquat], resolvedExercise: backSquat)
            context.insert(squatSlot)
            addExercise(backSquat, to: painScenario, sets: 3, reps: 6, weight: 60, slot: squatSlot)
            addExercise(benchPress, to: painScenario, sets: 3, reps: 8, weight: 40)
        }

        // Scenario 4 — stiffness, no pain.
        if let legPress = exercise("Leg Press") {
            addExercise(legPress, to: makeSession("Stiffness"), sets: 3, reps: 10, weight: 100)
        }

        // Scenario 5 — postpone.
        if let bulgarianSplitSquat = exercise("Bulgarian Split Squat") {
            addExercise(bulgarianSplitSquat, to: makeSession("Postpone"), sets: 3, reps: 8, weight: 20)
        }

        // Scenario 6 — Stage 9B manual acceptance: the exact multi-exercise
        // lower-body/hinge fixture (Squat/RDL/Leg Press/Leg Curl/Calf
        // Raise) used throughout the automated Stage 9B test suite,
        // surfaced for Simulator inspection. Reuses the REAL production
        // materializer path (`SeedScenarios.materializedLowerASession` ->
        // the real `StrengthMaterializer`/`ExerciseSlot`/
        // `PrescriptionTemplate` machinery) rather than a hand-built
        // stand-in, so the generated warm-up is proven against genuine
        // production data end to end — never a mocked warm-up screen.
        // Produces its own new, independent `ProgramDefinition`/
        // `ProgramInstance` (not the real seeded annual plan's own) — the
        // same "additive, never touches existing data" discipline as
        // every other fixture in this file.
        if let catalog = reconstructExerciseCatalog(from: exercises) {
            let lowerBodyDay = Day(ownerUserID: user.id, date: today)
            context.insert(lowerBodyDay)
            let fixture = SeedScenarios.materializedLowerASession(
                day: lowerBodyDay, catalog: catalog, ownerUserID: user.id, modelContext: context
            )
            fixture.session.name = markerPrefix + "Lower Body (multi-exercise)"
        }

        try context.save()
    }

    /// Rebuilds the `ExerciseCatalog` struct from already-seeded `Exercise`
    /// rows (never re-inserts — `Exercise.canonicalName` is unique) so
    /// `SeedScenarios.materializedLowerASession` — a real production-path
    /// fixture builder — can be reused here exactly as the automated test
    /// suite uses it. `nil` if the app's own seed bootstrap hasn't run
    /// (should not happen in practice; a safe no-op rather than a crash).
    private static func reconstructExerciseCatalog(from exercises: [Exercise]) -> ExerciseCatalog? {
        func find(_ name: String) -> Exercise? { exercises.first { $0.canonicalName == name } }
        guard
            let benchPress = find("Barbell Bench Press"), let backSquat = find("Back Squat"),
            let inclineDumbbellPress = find("Incline Dumbbell Press"), let easyRun = find("Easy Run (Zone 2)"),
            let trackIntervalRun = find("Track Interval Run"), let wallBall = find("Wall Ball"),
            let burpee = find("Burpee"), let kettlebellSwing = find("Kettlebell Swing"), let thruster = find("Thruster"),
            let pullUp = find("Pull-up"), let bike = find("Assault Bike"), let row = find("Row Erg"),
            let skiErg = find("SkiErg"), let toesToBar = find("Toes-to-Bar"), let pushUp = find("Push-up"),
            let handstandPushUp = find("Handstand Push-up"), let deadlift = find("Deadlift"),
            let dumbbellSnatch = find("Dumbbell Snatch"), let romanianDeadlift = find("Romanian Deadlift"),
            let legPress = find("Leg Press"), let bulgarianSplitSquat = find("Bulgarian Split Squat"),
            let legCurl = find("Leg Curl"), let calfRaise = find("Calf Raise"), let frontSquat = find("Front Squat"),
            let conventionalDeadlift = find("Conventional Deadlift"), let seatedLegCurl = find("Seated Leg Curl"),
            let seatedCalfRaise = find("Seated Calf Raise"), let barbellCurl = find("Barbell Curl"),
            let cableTricepsPushdown = find("Cable Triceps Pushdown"), let dumbbellLateralRaise = find("Dumbbell Lateral Raise"),
            let barbellRow = find("Barbell Row")
        else { return nil }

        return ExerciseCatalog(
            benchPress: benchPress, backSquat: backSquat, inclineDumbbellPress: inclineDumbbellPress,
            easyRun: easyRun, trackIntervalRun: trackIntervalRun, wallBall: wallBall, burpee: burpee,
            kettlebellSwing: kettlebellSwing, thruster: thruster, pullUp: pullUp, bike: bike, row: row,
            skiErg: skiErg, toesToBar: toesToBar, pushUp: pushUp, handstandPushUp: handstandPushUp,
            deadlift: deadlift, dumbbellSnatch: dumbbellSnatch, romanianDeadlift: romanianDeadlift,
            legPress: legPress, bulgarianSplitSquat: bulgarianSplitSquat, legCurl: legCurl, calfRaise: calfRaise,
            frontSquat: frontSquat, conventionalDeadlift: conventionalDeadlift, seatedLegCurl: seatedLegCurl,
            seatedCalfRaise: seatedCalfRaise, barbellCurl: barbellCurl, cableTricepsPushdown: cableTricepsPushdown,
            dumbbellLateralRaise: dumbbellLateralRaise, barbellRow: barbellRow
        )
    }
}
