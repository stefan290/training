import Foundation

/// Dogfood Round 1 (Finding 3A): a real, explicit **TrainingOS PRODUCT
/// DECISION** — never attributed to RP, CrossFit, or any source workbook
/// — for how the CURRENT phase's own adaptation priority biases
/// Functional Fitness programming. Before this checkpoint,
/// `FunctionalFitnessAuthoredProgramLibrary`'s weekly plan was applied
/// identically regardless of which phase/mix requested it — a real,
/// traced gap: a Muscle Gain phase and a pure Recovery phase produced
/// byte-identical FF programming.
///
/// **Only adjusts fields the real production pipeline already respects
/// end-to-end** — confirmed by direct trace of
/// `FunctionalFitnessMaterializer.materializeWeek`:
/// - `includeStrengthBlock` is read directly by `FunctionalFitnessProgramGenerator`
///   and produces a REAL second `WorkoutBlockTemplate` (`addStrengthBlock`)
///   — biasing this is a genuine, athlete-visible change.
/// - `stimulus.loading`/`.intensity`/`.systemicDemand` survive into
///   `FunctionalFitnessMaterializer`'s `finalStimulus` unchanged (only
///   `movementFunctions` gets overwritten there, by
///   `FunctionalFitnessMovementComposer`'s own real-time composition —
///   see that materializer's own Correction L comment) — biasing these
///   is real.
/// - Deliberately does **not** touch `stimulus.movementFunctions`: tracing
///   `FunctionalFitnessMaterializer.materializeWeek` proved the composer
///   ignores the authored value and recomputes it from real environment
///   eligibility/exposure rotation every time — biasing it here would be
///   pure fake precision with zero athlete-visible effect.
enum FunctionalFitnessPhaseBiasPolicy {
    static func apply(_ weeklyPlan: [FunctionalFitnessSessionIntent], phaseType: PhaseType?) -> [FunctionalFitnessSessionIntent] {
        switch phaseType {
        case .muscleGain, .strength:
            // Functional Bodybuilding bias: the phase's own hypertrophy/
            // strength priority carries over into how Functional Fitness
            // is programmed alongside it — every session pairs a real
            // strength/accessory block with its conditioning work,
            // never a bare metcon bolted onto an unrelated phase
            // (Finding 3E's own "distinct expression" requirement is met
            // by `FunctionalFitnessProgramGenerator.addStrengthBlock`'s
            // rotating-pattern, moderate-rep content — see that
            // function's own doc comment).
            return weeklyPlan.map { intent in
                var biased = intent
                biased.includeStrengthBlock = true
                return biased
            }
        case .recovery, .maintenance:
            // Down-regulation bias: no loaded strength block, lower
            // loading/intensity/systemic demand — conditioning-only,
            // genuinely lower fatigue, matching the same "reduced dose,
            // never an unrelated substitute" principle
            // `StrategicPeriodizationPolicy` already documents for this
            // phase type.
            return weeklyPlan.map { intent in
                var biased = intent
                biased.includeStrengthBlock = false
                biased.stimulus.loading = .bodyweightOnly
                biased.stimulus.intensity = .low
                biased.stimulus.systemicDemand = .low
                return biased
            }
        case .functionalFitness, .fatLoss, .enduranceEvent, .transition, nil:
            // A dedicated FF-performance phase is already the authored
            // plan's own intended shape — no bias needed. `.fatLoss`/
            // `.enduranceEvent`/`.transition`/unknown-phase: left exactly
            // as authored, not this checkpoint's focus — never a guessed
            // bias for a case Stefan's real dogfood never exercised.
            return weeklyPlan
        }
    }
}
