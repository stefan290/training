import Foundation

/// Stage 7 (Tactical Planning Orchestration): closes the gap `ExerciseSlot`'s
/// own doc comment already names but nothing ever implemented — a slot is
/// "resolved to a concrete `Exercise`... when a specific user's
/// `ProgramInstance` is created from the template." Before this use case,
/// nothing ever set `ExerciseSlot.resolvedExercise` for a generated (not
/// hand-curated) `ProgramDefinition`, so `SubstituteExerciseUseCase.resolvedExercise`
/// always returned `nil` for a real Hypertrophy/Powerlifting instance —
/// no exercise name, no weight resolution, no PR lookup possible.
///
/// **No second exercise-selection mechanism.** This reuses exactly the
/// same deterministic "first candidate satisfying the slot's typed
/// constraints" rule `FunctionalFitnessMaterializer.materializeWeek`
/// already established (`SubstitutionValidator.isValid`, the same
/// eligibility check `SubstituteExerciseUseCase`/`SubstitutionCandidateRanking`
/// already use) — sorted by `canonicalName` first so the pick is
/// deterministic even if the caller's pool isn't in a stable order.
/// Unlike Functional Fitness's per-materialization-call fallback, this
/// picks **once**, at instance-creation time, and persists the result onto
/// `ExerciseSlot.resolvedExercise` — matching `ExerciseSlot`'s own
/// documented "survives resolution" contract and letting every later
/// `materializeWeek` call (week 1, 2, ...) see the same already-resolved
/// exercise with no re-resolution mechanism of its own.
///
/// **Never mutates `ProgramDefinition`'s methodology.** Only
/// `ExerciseSlot.resolvedExercise` is written — never `allowedTargets`,
/// never a rule field. The `ProgramDefinition` a `LongTermPlanner.proposeProgram`
/// candidate carries is always freshly `.constructed` per call (never a
/// shared/cached row reused across other instances or other users), so
/// this is safe to call unconditionally on the one candidate that becomes
/// a real `ProgramInstance` — never on the candidates the user didn't
/// pick, and never touching some other instance's own slots.
///
/// **Never silently invalid.** A slot with no eligible candidate in the
/// pool is left `nil` — not defaulted to an arbitrary exercise. Every
/// downstream caller (`RollTacticalWindowUseCase.strengthSlotContext`)
/// already treats a `nil` resolved exercise as `.calibrationRequired`,
/// exactly the explicit "selection required" condition this must produce
/// instead of guessing.
///
/// **`SlotSelectionOverride` still wins.** This only ever sets the
/// template *default* (`slot.resolvedExercise`); `SubstituteExerciseUseCase.resolvedExercise`
/// already checks `instance.slotSelectionOverride(for:)` first — unchanged
/// by this use case.
enum ResolveProgramInstanceExerciseSlotsUseCase {
    /// Resolves every not-yet-resolved `ExerciseSlot` in `definition`'s
    /// whole template graph (every `PrescriptionTemplate`'s slot, across
    /// every `TemplateSession`/`WorkoutBlockTemplate`) against
    /// `candidateExercises`. Idempotent — an already-resolved slot (e.g.
    /// a curated built-in program authored with a `resolvedExercise` of
    /// its own) is never overwritten.
    ///
    /// **Distinct slots within the same training day never silently
    /// collapse to the same concrete Exercise merely because they share
    /// the alphabetically-first eligible candidate** (Stage 7 Slice 4
    /// acceptance finding: a "Horizontal Push" slot and a "Chest
    /// Isolation" slot in the same session both resolving to "Barbell
    /// Bench Press" is a real selection bug, not a valid program). Scoped
    /// to one `TemplateSession` at a time — repeating the same exercise
    /// across *different* training days (e.g. every "Day 1" of every
    /// week) is methodologically normal and untouched; this only avoids
    /// duplication among the slots that would otherwise appear together
    /// in one Session. Falls back to reusing an already-picked candidate
    /// only when no distinct eligible alternative exists — this must
    /// never leave a slot unresolved (`.calibrationRequired`) merely to
    /// enforce distinctness.
    static func resolve(definition: ProgramDefinition, candidateExercises: [Exercise]) {
        guard !candidateExercises.isEmpty else { return }
        let sortedCandidates = candidateExercises.sorted { $0.canonicalName < $1.canonicalName }

        for templateSession in definition.orderedTemplateSessions {
            var usedExerciseIDs: Set<UUID> = []
            let slots = templateSession.orderedBlockTemplates
                .flatMap(\.orderedPrescriptionTemplates)
                .compactMap(\.exerciseSlot)

            for slot in slots {
                if let alreadyResolved = slot.resolvedExercise {
                    usedExerciseIDs.insert(alreadyResolved.id)
                    continue
                }
                let eligible = sortedCandidates.filter { SubstitutionValidator.isValid(candidate: $0, for: slot) }
                let chosen = eligible.first { !usedExerciseIDs.contains($0.id) } ?? eligible.first
                slot.resolvedExercise = chosen
                if let chosen { usedExerciseIDs.insert(chosen.id) }
            }
        }
    }
}
