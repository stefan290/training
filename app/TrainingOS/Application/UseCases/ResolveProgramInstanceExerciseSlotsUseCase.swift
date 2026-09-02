import Foundation

/// Stage TE.1: thrown by `ResolveProgramInstanceExerciseSlotsUseCase.resolve`
/// — the Hypertrophy/Powerlifting instance-creation-time sibling of
/// `FunctionalFitnessMaterializationError`'s identical two cases. Its own
/// enum, not folded into `HypertrophyGenerationError` (which is thrown by
/// the GENERATOR, a different pipeline stage that never sees a candidate
/// pool or an environment) — Powerlifting shares this same enum rather
/// than getting its own, since both route through this one shared
/// resolver with no separate Powerlifting-specific resolution mechanism.
enum ExerciseSlotResolutionError: Error, Equatable {
    /// No `TrainingEnvironment` was supplied at all — thrown before any
    /// slot in the graph is resolved.
    case trainingEnvironmentRequired
    /// A real, configured environment exists, and at least one candidate
    /// satisfies every OTHER constraint on this slot, but every such
    /// candidate is equipment-incompatible with it. Deliberately NOT
    /// thrown when a slot simply has no semantically-eligible candidate at
    /// all regardless of environment — that is a separate, pre-existing,
    /// out-of-TE.1's-scope unresolved-slot state (see `resolve`'s own doc
    /// comment).
    case environmentIncompatible(slot: String, missingEquipment: [EquipmentRequirement])
}

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
/// **Checkpoint-gate correction:** the claim above ("every downstream
/// caller already treats a `nil` resolved exercise as an explicit,
/// blocking `.calibrationRequired` state") was not accurate.
/// `RequiredSourceCalibrationsUseCase.stillRequired` explicitly `continue`s
/// past any slot with no resolved exercise — it never lists such a slot as
/// needing calibration — and `StrengthMaterializer` unconditionally builds
/// an `ExercisePrescription` from whatever `SubstituteExerciseUseCase
/// .resolvedExercise` returns, including `nil`, with no guard. Left alone,
/// an environment-caused unresolved slot could silently reach a real,
/// startable, athlete-facing Session whose prescription has `exercise ==
/// nil` (rendered as a generic "Exercise" placeholder throughout the UI),
/// with no calibration prompt ever firing to surface it. The
/// `.environmentIncompatible` throw above (added when at least one
/// candidate is semantically eligible but excluded only by equipment)
/// closes exactly that gap, before any Session for this component is ever
/// materialized — `StartPhaseUseCase.start` calls this before
/// `RequiredSourceCalibrationsUseCase`/`RollTacticalWindowUseCase
/// .materializeFirstWindow` run. A slot with NO semantically-eligible
/// candidate at all (regardless of environment) is unaffected by this
/// fix and remains the pre-existing, out-of-TE.1's-scope `nil` state.
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
    static func resolve(definition: ProgramDefinition, candidateExercises: [Exercise], environment: TrainingEnvironment?) throws {
        guard !candidateExercises.isEmpty else { return }
        let sortedCandidates = candidateExercises.sorted { $0.canonicalName < $1.canonicalName }

        for templateSession in definition.orderedTemplateSessions {
            var usedExerciseIDs: Set<UUID> = []
            let slots = templateSession.orderedBlockTemplates
                .flatMap(\.orderedPrescriptionTemplates)
                .compactMap(\.exerciseSlot)

            // Stage TE.1 fail-fast guard: checked once per template
            // session, before this session's own candidate-resolution
            // loop — never entered with an unknown environment silently
            // treated as "anything goes."
            if !slots.isEmpty, environment == nil {
                throw ExerciseSlotResolutionError.trainingEnvironmentRequired
            }

            for slot in slots {
                if let alreadyResolved = slot.resolvedExercise {
                    usedExerciseIDs.insert(alreadyResolved.id)
                    continue
                }

                // Stage TE.1 (§K/§L): a narrowed main-lift/competition
                // slot is precisely attributable to environment — see
                // `FunctionalFitnessMaterializer`'s identical reasoning.
                if !slot.allowedExercises.isEmpty,
                   !slot.allowedExercises.contains(where: {
                       TrainingEnvironmentCompatibilityRule.evaluate(required: $0.requiredEquipment, environment: environment) == .compatible
                   }) {
                    let missing = Set(slot.allowedExercises.flatMap(\.requiredEquipment)).subtracting(Set(environment?.availableEquipment ?? []))
                    throw ExerciseSlotResolutionError.environmentIncompatible(slot: slot.name, missingEquipment: Array(missing))
                }

                let eligible = sortedCandidates.filter { SubstitutionValidator.isValid(candidate: $0, for: slot, environment: environment) }

                // Stage TE.1 checkpoint-gate fix: a KNOWN environment that
                // simply has no candidate at all for this slot (unrelated
                // to equipment) is a pre-existing, out-of-scope unresolved-
                // slot state (`slot.resolvedExercise` stays `nil`, exactly
                // as before this stage). But if at least one candidate
                // satisfies every OTHER constraint on this slot and is
                // excluded only by equipment, that is a real, attributable
                // environment conflict — it must be a typed, blocking
                // failure BEFORE any Session materializes, never a
                // silently-unresolved slot that could still reach an
                // athlete-facing prescription with no exercise (CLAUDE.md
                // rule 14/the locked TE.1 invariant: every prescription
                // must be executable in the selected environment).
                if eligible.isEmpty {
                    let semanticallyEligible = sortedCandidates.filter {
                        SubstitutionValidator.matchesSemanticConstraints(candidate: $0, for: slot)
                    }
                    if !semanticallyEligible.isEmpty {
                        let missing = Set(semanticallyEligible.flatMap(\.requiredEquipment))
                            .subtracting(Set(environment?.availableEquipment ?? []))
                        throw ExerciseSlotResolutionError.environmentIncompatible(slot: slot.name, missingEquipment: Array(missing))
                    }
                    continue
                }

                let chosen = eligible.first { !usedExerciseIDs.contains($0.id) } ?? eligible.first
                slot.resolvedExercise = chosen
                if let chosen { usedExerciseIDs.insert(chosen.id) }
            }
        }
    }
}
