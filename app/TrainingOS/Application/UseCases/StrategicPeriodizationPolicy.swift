import Foundation

/// Long-Term Planner Intelligence (Vertical Completion V2): the explicit,
/// deterministic **TrainingOS strategic policy** deciding what each next
/// forward-filled phase's `PhaseType` and reason should be — replacing
/// `fillForwardPhases`'s previous mechanical `consecutivePrimary >= 2 ?
/// .maintenance : primaryType` counter, which produced an infinite
/// identical two-type loop with no strategic reasoning behind it.
///
/// **Authority boundary (this checkpoint's own §2):** every decision here
/// is a TrainingOS PRODUCT/ORCHESTRATION decision, never attributed to RP,
/// CrossFit, the Running source, or any workbook. Source authority still
/// owns concrete program structure/progression/deload/calibration —
/// nothing here touches any of that; this type only ever chooses WHICH
/// already-existing `PhaseType` (and therefore which already-existing
/// `candidateMixTemplates` case) comes next, and WHY.
///
/// **Deliberately reuses 100% pre-existing domain vocabulary — zero new
/// persisted schema beyond one new `PlannerReasonCode` case**
/// (`developmentPhaseSupportsPrimaryGoal`): the periodic down-regulation
/// slot reuses `PhaseType.maintenance` — its own real, sophisticated,
/// extensively-tested reduced-dose policy
/// (`maintenanceMix`/`maintenanceComponentDecisions`, unchanged, byte for
/// byte) is a strictly better fit than `.recovery`'s own current generic
/// fallback content, since it genuinely preserves whatever the athlete
/// was actually training rather than substituting an unrelated block —
/// see the `cycle(for:)` function's own doc comment for the full
/// reasoning. `.maintenance`'s semantics are NOT redefined (§10's own
/// explicit warning) — only `PlannerReasonCode.recoveryPhaseInserted`
/// (already existed, previously unused by the old mechanical loop) is now
/// attached, making the STRATEGIC REASON this phase exists explicit
/// ("a policy-driven periodized down-regulation") without changing what
/// `.maintenance` means or does anywhere else. `PhaseType.recovery`
/// itself remains fully intact and untouched, available for a future
/// checkpoint. A "development" phase inside a `GoalType.generalStrength`
/// plan reuses `PhaseType.muscleGain` verbatim
/// (Goal and Phase are already fully decoupled — a `.muscleGain`-typed
/// phase never mutates `Goal.primaryType`, confirmed architecturally in
/// the Product Model Alignment checkpoint) and resolves through the
/// EXISTING `candidateMixTemplates(.muscleGain)` candidates
/// (`muscleGainFocusedHypertrophyMix`/`muscleGainVariedMix`) unchanged.
///
/// **Superseded note, kept for history — corrected by the Final Duration
/// Fix**: an earlier pass argued that a `.strength`-typed phase's planned
/// `endDate` never needed to match Family D/E's real 5-week mesocycle
/// length, on the theory that `TrainingPhaseCompletion.isPhaseTerminal`
/// (real tactical exhaustion, never a planned date) is the only thing
/// that decides an ACTUAL transition, so an inflated estimate was
/// "merely" a display inaccuracy. Independent review correctly rejected
/// this: `TrainingOS PLAN = DIRECTION` — a strategic date TrainingOS
/// already KNOWS is wrong at planning time is knowingly incorrect product
/// information, not a harmless estimate, regardless of whether it also
/// happens to be safe against a forced-early-transition failure mode.
/// Planned duration is now resolved from the ACTUAL recommended/selected
/// `TrainingMix`'s real executable capability
/// (`ExecutablePhaseDurationResolver`, called from `fillForwardPhases`),
/// never from `PhaseType` alone — this file stays completely unaware of
/// *how* that resolution happens, which is the whole point of keeping it
/// separate.
enum StrategicPeriodizationPolicy {
    struct PhaseIntent {
        var type: PhaseType
        var reasonCodes: [PlannerReasonCode]
    }

    /// The deterministic, explainable cycle for a given primary phase
    /// type — a fixed-length repeating sequence of intents, indexed by
    /// `cyclePosition % cycle.count`. Same inputs (`primaryType`,
    /// `cyclePosition`) always produce the same output — no randomness,
    /// no date/clock read (§20).
    ///
    /// - `.strength` (GET STRONGER): development (capacity-building,
    ///   Hypertrophy content legitimately supporting the strength goal) ->
    ///   direct strength -> direct strength (a second, more specific
    ///   strength-development block) -> recovery. Never introduces
    ///   Powerlifting competition peaking — no such content exists to
    ///   select (`strengthFocusedMix()` only ever resolves to the
    ///   canonical General Strength Family D/E, confirmed unchanged this
    ///   checkpoint).
    /// - `.muscleGain` (BUILD MUSCLE): two primary-goal development
    ///   blocks -> recovery. Deliberately NOT alternating in on a Strength
    ///   phase merely for symmetry with Get Stronger (the directive's own
    ///   explicit instruction) — `candidateMixTemplates(.muscleGain)`
    ///   already offers 2 real, different Hypertrophy-primary candidates
    ///   (Focused vs. Varied) and the existing preference-driven
    ///   `rankCandidateMixes` logic (unchanged) already picks between them
    ///   per athlete signal; this policy does not attempt to force a
    ///   specific one per cycle position, since doing so would require
    ///   touching candidate-ranking logic outside this checkpoint's scope.
    /// - `.fatLoss`, `.functionalFitness`, `.enduranceEvent`: the same
    ///   "N primary-goal blocks, then a real recovery" shape — no
    ///   dedicated development/intensification sub-role invented for
    ///   these, since neither the directive nor current domain content
    ///   establishes one; see `LONG_TERM_PLANNER_INTELLIGENCE_COMPLETION.md`
    ///   §8/§9 for the explicit, disclosed limitation this represents for
    ///   Lose Fat/Functional Fitness specifically.
    /// - `.maintenance` (the athlete's actual primary goal IS
    ///   maintenance): no cycle at all — there is no accumulated
    ///   development to recover FROM when the ongoing goal already IS the
    ///   lower-intensity state; every phase stays `.maintenance`,
    ///   unchanged from the pre-existing behavior.
    /// - `.recovery`, `.transition`: never themselves a PRIMARY type (no
    ///   `GoalType` maps to either), included only so the switch stays
    ///   exhaustive; degrades to the same generic single-type cycle as a
    ///   safe fallback, never reached in practice.
    /// **`reasonCodes` here are ADDITIONAL to the caller's own
    /// `baseReasonCodes`** (every existing call site passes
    /// `[.phaseSelectedForGoal]`) — `nextPhaseIntent`'s caller
    /// (`fillForwardPhases`) appends these to `baseReasonCodes`, never
    /// duplicating it. An empty array here means "no reason beyond the
    /// caller's own base codes," exactly the old `.maintenance` phase's
    /// prior behavior.
    /// **Why the recovery/down-regulation slot uses `PhaseType.maintenance`,
    /// not `.recovery`:** `.maintenance` already carries a real,
    /// sophisticated, EXTENSIVELY tested policy
    /// (`LongTermPlanner.maintenanceMix`/`maintenanceComponentDecisions`)
    /// — it preserves whatever the athlete was ACTUALLY training in the
    /// immediately preceding phase, at a genuinely reduced dose, rather
    /// than replacing it with an unrelated generic block. That is exactly
    /// what a real periodized down-regulation period should do, and is a
    /// strictly better fit than `.recovery`'s own current content
    /// (`lowerDemandGenericMix` — a flat 2x generic-conditioning
    /// fallback, unrelated to whatever was actually being trained). Using
    /// `.maintenance` here does NOT redefine its semantics (§10's own
    /// explicit warning) — its policy, meaning, and every existing test
    /// remain byte-for-byte unchanged; this only adds a new, honest
    /// `PlannerReasonCode.recoveryPhaseInserted` explaining WHY this
    /// particular `.maintenance` phase exists (a policy-driven periodized
    /// down-regulation, not "the athlete's goal is now to maintain").
    /// `.recovery`'s own distinct identity and `candidateMixTemplates`
    /// arm remain fully intact, untouched, and available for a future
    /// checkpoint that wants a genuinely different (not dose-reduced-
    /// previous-mix) down-regulation policy.
    private static func cycle(for primaryType: PhaseType) -> [PhaseIntent] {
        switch primaryType {
        case .strength:
            return [
                PhaseIntent(type: .muscleGain, reasonCodes: [.developmentPhaseSupportsPrimaryGoal]),
                PhaseIntent(type: .strength, reasonCodes: []),
                PhaseIntent(type: .strength, reasonCodes: []),
                PhaseIntent(type: .maintenance, reasonCodes: [.recoveryPhaseInserted]),
            ]
        case .muscleGain:
            return [
                PhaseIntent(type: .muscleGain, reasonCodes: []),
                PhaseIntent(type: .muscleGain, reasonCodes: []),
                PhaseIntent(type: .maintenance, reasonCodes: [.recoveryPhaseInserted]),
            ]
        case .fatLoss:
            return [
                PhaseIntent(type: .fatLoss, reasonCodes: [.muscleRetentionPriority]),
                PhaseIntent(type: .fatLoss, reasonCodes: [.muscleRetentionPriority]),
                PhaseIntent(type: .maintenance, reasonCodes: [.recoveryPhaseInserted]),
            ]
        case .functionalFitness:
            return [
                PhaseIntent(type: .functionalFitness, reasonCodes: []),
                PhaseIntent(type: .functionalFitness, reasonCodes: []),
                PhaseIntent(type: .maintenance, reasonCodes: [.recoveryPhaseInserted]),
            ]
        case .enduranceEvent:
            return [
                PhaseIntent(type: .enduranceEvent, reasonCodes: []),
                PhaseIntent(type: .enduranceEvent, reasonCodes: []),
                PhaseIntent(type: .maintenance, reasonCodes: [.recoveryPhaseInserted]),
            ]
        case .maintenance, .recovery, .transition:
            return [PhaseIntent(type: .maintenance, reasonCodes: [])]
        }
    }

    /// The next phase's intent, given how many phases this same forward
    /// fill has already produced (`cyclePosition`, 0-based, incremented by
    /// the caller once per phase regardless of type — never reset except
    /// by starting a new fill call). Pure function of its 2 inputs.
    ///
    /// **Final Duration Fix — architectural boundary, explicit**: this
    /// type answers WHAT `PhaseType` comes next and WHY. It deliberately
    /// knows NOTHING about which concrete program/engine will actually
    /// implement that phase, nor how long that program's real executable
    /// lifecycle is — `PhaseType.strength` does not by itself determine
    /// whether the resulting phase runs 5 weeks (Family D/E, no
    /// succession) or longer (a Hypertrophy-engine alternate candidate,
    /// with real succession) — see `ExecutablePhaseDurationResolver`,
    /// which resolves that question from the ACTUAL recommended/selected
    /// `TrainingMix`, never from `PhaseType` alone. This file has zero
    /// reference to `PowerliftingProgramGenerator`/`HypertrophyProgramGenerator`/
    /// `StrengthSourceContentLibrary`/any other concrete engine type —
    /// confirmed directly, and guarded by
    /// `LongTermPlannerIntelligenceCompletionTests
    /// .testStrategicPeriodizationPolicyHasNoConcreteProgramEngineDependency`.
    static func nextPhaseIntent(primaryType: PhaseType, cyclePosition: Int) -> PhaseIntent {
        let pattern = cycle(for: primaryType)
        return pattern[cyclePosition % pattern.count]
    }

    /// Dogfood Round 1 (Finding 2): how many phases this primary type's
    /// own cycle defines before it repeats — the natural, already-designed
    /// boundary for "how far ahead does this policy have real strategic
    /// opinion," reused by `LongTermPlanner`'s no-target-date rolling
    /// horizon to decide how many NEAR-FUTURE phases to show beyond the
    /// current one. Exposes only the cycle's LENGTH, never its contents —
    /// every phase's actual type/reason still comes from `nextPhaseIntent`
    /// alone; this adds no new decision.
    static func cycleLength(for primaryType: PhaseType) -> Int {
        cycle(for: primaryType).count
    }
}
