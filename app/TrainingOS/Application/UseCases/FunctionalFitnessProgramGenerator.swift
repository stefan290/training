import Foundation
import SwiftData

/// Builds and persists a `FunctionalFitnessPrescriptionTemplate`-based
/// template graph from a `FunctionalFitnessProgramConfiguration` — the
/// Functional Fitness sibling of `HypertrophyProgramGenerator`/
/// `SteadyStateProgramGenerator`/`IntervalProgramGenerator`.
///
/// **The five-stage pipeline, at generation time (§2):** Stage A
/// (`configuration.targetStimulus`) is supplied by the caller, not
/// invented here — a real "given a training goal, choose a stimulus"
/// decision is a product/content authoring concern, out of this pass's
/// scope (§34's V1 constraint). Stage B (`configuration.format`) is
/// likewise supplied directly. **Stages C-E run here**: Stage C derives
/// one `FunctionalFitnessMovementSlotTemplate` per `ModalityCount` entry
/// in the target stimulus's `movementModalityMix` (a couplet's 2 counts
/// become 2 slots, a triplet's 3 become 3), each constrained by
/// `allowedModalities`/`allowedMovementFunctions` — never a literal,
/// hard-coded exercise list (§8). Stage D (concrete exercise selection)
/// and Stage E (stimulus validation) are deliberately **not** run at
/// generation time — they depend on live exposure history and available
/// candidates, so they run at `FunctionalFitnessMaterializer` time
/// instead, exactly mirroring how Stage 4A deferred strength's concrete-
/// exercise resolution to materialization.
///
/// **Scope, stated plainly (§34, same discipline as every other Stage 4
/// generator):** single-modality conditioning, couplets, triplets, basic
/// longer mixed-modal workouts, strength+metcon composition, and
/// benchmark-shaped prescriptions are all provable through this one
/// generator — not an infinite CrossFit programmer, not a curated V1
/// content library (no `V1_PROGRAM_LIBRARY.md` entry names one, matching
/// every endurance generator's identical finding).
enum FunctionalFitnessProgramGenerator {
    static let currentVersion = 1
    static let functionalStrengthGeneratorVersion = 2

    @discardableResult
    static func generate(
        configuration: FunctionalFitnessProgramConfiguration,
        provenance: ProgramProvenance,
        context: ModelContext
    ) -> ProgramDefinition {
        var configuration = configuration
        if configuration.trainingStyle != nil, configuration.weeklyPlan == nil {
            // A styled recipe always stores exact-week intents, including direct
            // callers outside the planner. The materializer reads this same shape.
            configuration.weeklyPlan = (0..<configuration.lengthWeeks).flatMap { week in
                (0..<configuration.daysPerWeek).map { day in
                    FunctionalFitnessSessionIntent(
                        relativeWeek: week, sessionIndexInWeek: day,
                        stimulus: configuration.targetStimulus, format: configuration.format,
                        includeStrengthBlock: configuration.includeStrengthBlock,
                        varianceConstraints: configuration.varianceConstraints,
                        sessionRole: configuration.sessionRole
                    )
                }
            }
        }
        configuration.weeklyPlan = configuration.weeklyPlan?.map { original in
            var intent = configuration.resolvedIntent(original)
            if configuration.trainingStyle == .functionalStrength, intent.includeConditioningBlock {
                intent.format = .amrap(capSeconds: FunctionalStrengthSessionBudget.conditioningAllowanceSeconds)
                intent.stimulus.targetDurationDomain = .medium
                intent.stimulus.scoreType = .roundsAndReps
            }
            return intent
        }
        let definition = ProgramDefinition(
            name: "\(configuration.daysPerWeek)-Day \(configuration.trainingStyle?.displayName ?? "Functional Fitness") (\(configuration.sessionRole.rawValue))",
            lengthWeeks: configuration.lengthWeeks,
            intent: "Functional Fitness, \(configuration.format), \(configuration.targetStimulus.targetDurationDomain) duration domain",
            programmingSystem: .functionalFitness,
            generatorVersion: configuration.trainingStyle == .functionalStrength ? functionalStrengthGeneratorVersion : currentVersion,
            provenance: provenance,
            functionalFitnessConfiguration: configuration
        )
        context.insert(definition)

        for _ in 0..<configuration.lengthWeeks {
            let week = TrainingWeek(isDeload: false)
            context.insert(week)
            definition.addWeek(week)
        }

        // FF Multi-Week V1: an authored `weeklyPlan` builds one distinct,
        // week-pinned `TemplateSession` per intent instead of the
        // recurring-single-stimulus path below — see
        // `FunctionalFitnessSessionIntent`'s own doc comment and
        // `FunctionalFitnessMaterializer`'s matching exact-equality
        // filter branch.
        if let weeklyPlan = configuration.weeklyPlan {
            for intent in weeklyPlan {
                let session = TemplateSession(
                    name: "Week \(intent.relativeWeek + 1) — Session \(intent.sessionIndexInWeek + 1)",
                    role: intent.sessionRole,
                    activeFromWeek: intent.relativeWeek
                )
                context.insert(session)
                definition.addTemplateSession(session)

                if configuration.trainingStyle == .functionalStrength {
                    addTimeBudgetedFunctionalStrengthBlock(to: session, intent: intent, context: context)
                } else if intent.includeStrengthBlock {
                    addStrengthBlock(
                        to: session, relativeWeek: intent.relativeWeek, archetype: intent.archetype,
                        family: intent.sessionFamily, requiredLoadedPattern: intent.requiredLoadedPattern,
                        genericStrengthAssignment: intent.genericStrengthAssignment,
                        sessionIndexInWeek: intent.sessionIndexInWeek, context: context
                    )
                }

                // GENERAL PROGRAMMING ALLOCATION ARCHITECTURE V1 §13.A/§17:
                // "not every FF session requires... even a conditioning
                // block" — a `.resistanceDominant`-purpose session's real
                // main body (just authored above) already carries the
                // session's whole resistance stimulus, so the conditioning
                // block is genuinely omitted, never a placeholder, never
                // forced to exist merely because this is a Functional
                // Fitness session. `includeConditioningBlock` defaults
                // `true` so every pre-existing authored entry/test
                // (`archetype == .unbiased`, no `muscleSessionPurpose`)
                // is completely unaffected.
                if intent.includeConditioningBlock {
                    let ffBlock = WorkoutBlockTemplate(type: .functionalFitness)
                    context.insert(ffBlock)
                    session.addBlockTemplate(ffBlock)

                    let prescriptionTemplate = FunctionalFitnessPrescriptionTemplate(
                        stimulus: intent.stimulus,
                        format: configuration.trainingStyle == .functionalStrength ? .amrap(capSeconds: FunctionalStrengthSessionBudget.conditioningAllowanceSeconds) : intent.format,
                        requiresRecentExposureToProgress: false,
                        varianceConstraints: intent.varianceConstraints,
                        isDynamicallyComposed: true,
                        archetype: intent.archetype,
                        sessionFamily: intent.sessionFamily
                    )
                    context.insert(prescriptionTemplate)
                    ffBlock.attachFunctionalFitnessPrescriptionTemplate(prescriptionTemplate)
                }
            }
            return definition
        }

        for dayIndex in 0..<configuration.daysPerWeek {
            let session = TemplateSession(name: "Day \(dayIndex + 1)", role: configuration.sessionRole)
            context.insert(session)
            definition.addTemplateSession(session)

            if configuration.includeStrengthBlock {
                addStrengthBlock(to: session, context: context)
            }

            let ffBlock = WorkoutBlockTemplate(type: .functionalFitness)
            context.insert(ffBlock)
            session.addBlockTemplate(ffBlock)

            let prescriptionTemplate = FunctionalFitnessPrescriptionTemplate(
                stimulus: configuration.targetStimulus,
                format: configuration.format,
                requiresRecentExposureToProgress: configuration.requiresRecentExposureToProgress,
                varianceConstraints: configuration.varianceConstraints,
                isDynamicallyComposed: configuration.isDynamicallyComposed
            )
            context.insert(prescriptionTemplate)
            ffBlock.attachFunctionalFitnessPrescriptionTemplate(prescriptionTemplate)

            // Stage FF.M1: Stage C (movement-slot composition) moved to
            // materialization time for dynamically-composed FF
            // (`FunctionalFitnessMaterializer`/`FunctionalFitnessMovementComposer`)
            // — pre-baking a fixed slot set here, before any real week's
            // FINAL stimulus is known, is exactly the frozen-CONFIGURED
            // contradiction FF.M1 closes. `isDynamicallyComposed == false`
            // (no real content today) is the only case that still needs
            // slots attached at generation time.
            if !prescriptionTemplate.isDynamicallyComposed {
                for movementSlotTemplate in movementSlots(for: configuration.targetStimulus, context: context) {
                    prescriptionTemplate.addMovementSlot(movementSlotTemplate)
                }
            }
        }

        return definition
    }

    /// Stage C: one `FunctionalFitnessMovementSlotTemplate` per
    /// `ModalityCount` entry (expanded by its own `count`), each
    /// constrained by that entry's modality and one round-robin-assigned
    /// movement function from `stimulus.movementFunctions` — deterministic,
    /// never a hard-coded exercise (§8).
    private static func movementSlots(for stimulus: Stimulus, context: ModelContext) -> [FunctionalFitnessMovementSlotTemplate] {
        var slots: [FunctionalFitnessMovementSlotTemplate] = []
        var slotIndex = 0
        for modalityCount in stimulus.movementModalityMix {
            for _ in 0..<modalityCount.count {
                let assignedFunction: MovementFunction? = stimulus.movementFunctions.isEmpty
                    ? nil
                    : stimulus.movementFunctions[slotIndex % stimulus.movementFunctions.count]

                let slot = ExerciseSlot(
                    name: "\(modalityCount.modality.rawValue) slot \(slotIndex + 1)",
                    allowedMovementFunctions: assignedFunction.map { [$0] } ?? [],
                    allowedModalities: [modalityCount.modality]
                )
                context.insert(slot)

                let movementSlotTemplate = FunctionalFitnessMovementSlotTemplate(loadingRole: stimulus.loading)
                context.insert(movementSlotTemplate)
                movementSlotTemplate.attachExerciseSlot(slot)
                slots.append(movementSlotTemplate)
                slotIndex += 1
            }
        }
        return slots
    }

    /// §20: strength + metcon composition — a plain, fixed, non-
    /// progressing strength block (5×5), proving composition works
    /// through the existing `Session`/`WorkoutBlock` architecture without
    /// needing any new entity. Deliberately not wired to
    /// `StrengthProgressionEngine`'s full autoregulation/deload machinery
    /// — that's out of scope for what this composition proof needs to
    /// demonstrate.
    /// Dogfood Round 1 (Finding 3E), a **TrainingOS PRODUCT DECISION**:
    /// Functional Bodybuilding as a distinct expression, not "a Hypertrophy
    /// session with conditioning bolted on" — moderate rep range (10, not
    /// a strength-test 5), a lighter %RM appropriate to accessory-style
    /// work (never RP's/any source's own Hypertrophy or Powerlifting
    /// rep/load scheme), and rotating through the 4 fundamental movement
    /// patterns across the week index rather than always the same squat.
    /// Still 100% pre-existing domain vocabulary (`RMType`/
    /// `StrengthProgressionRules`/`ExerciseSlot`) — no new schema.
    private enum FunctionalBodybuildingPattern: Int, CaseIterable {
        case squat, hinge, press, pull

        var slotName: String {
            switch self {
            case .squat: return "Functional Bodybuilding — Squat"
            case .hinge: return "Functional Bodybuilding — Hinge"
            case .press: return "Functional Bodybuilding — Press"
            case .pull: return "Functional Bodybuilding — Pull"
            }
        }

        var allowedTargets: [MuscleGroup] {
            switch self {
            case .squat: return [.quadriceps, .glutes]
            case .hinge: return [.hamstrings, .glutes, .back]
            case .press: return [.shoulders, .chest, .triceps]
            case .pull: return [.back, .biceps]
            }
        }

        /// PROGRAMMING AUTHORITY V1 — FINAL CLOSE-OUT, Part XV: a real,
        /// pre-existing latent defect this checkpoint's stricter validator
        /// surfaced (not introduced by it) — `allowedTargets` alone
        /// (`MuscleGroup`) cannot distinguish a genuine hip-hinge/deadlift
        /// movement from a hamstrings-isolation exercise that merely
        /// shares the `.hamstrings` target; `MovementFunction.kneeFlexionLoaded`
        /// exists in this codebase specifically to name that distinction
        /// (see its own doc comment), but this slot never constrained
        /// against it. Without this, the "Hinge" slot could silently
        /// resolve to a leg-curl-family exercise, which is never a real
        /// hip-hinge pattern — meaning even the PRE-EXISTING mesocycle
        /// rotation could not truthfully guarantee a "hinge week" actually
        /// contained hinge-pattern work. Fixed generally (every loaded-
        /// pattern slot, not only Part XV's own override), since this is
        /// the slot's own declared intent, not new scope.
        var allowedMovementFunctions: [MovementFunction] {
            switch self {
            case .squat: return [.squatLoaded]
            case .hinge: return [.hingeLoaded]
            case .press: return [.pressLoaded]
            case .pull: return [.horizontalPullLoaded, .verticalPullLoaded]
            }
        }
    }

    /// Complete functional-strength session, with conditioning replacing one
    /// resistance section inside the same time budget. Existing heavy assignments
    /// retain their original rules. Supporting work is TrainingOS-authored 8-12
    /// reps at 3 RIR, four sets, using the existing calibrated RM-based load and
    /// result-driven progression. This is not imported Functional Bodybuilding.
    private static func addTimeBudgetedFunctionalStrengthBlock(
        to session: TemplateSession, intent: FunctionalFitnessSessionIntent,
        context: ModelContext
    ) {
        let block = WorkoutBlockTemplate(type: intent.genericStrengthAssignment == nil ? .hypertrophy : .strength)
        context.insert(block)
        session.addBlockTemplate(block)
        let allPatterns = FunctionalBodybuildingPattern.allCases
        let start = (intent.relativeWeek + intent.sessionIndexInWeek) % allPatterns.count
        let count = intent.includeConditioningBlock ? 3 : 4
        var used: Set<Int> = []
        if let assignment = intent.genericStrengthAssignment {
            addGenericHighLoadStrengthPrescription(pattern: assignment, to: block, context: context)
            let assignedPattern: FunctionalBodybuildingPattern = switch assignment {
            case .squatLoaded: .squat
            case .hingeLoaded: .hinge
            case .pressLoaded: .press
            default: .pull
            }
            used.insert(assignedPattern.rawValue)
        }
        for offset in 0..<allPatterns.count where used.count < count {
            let pattern = allPatterns[(start + offset) % allPatterns.count]
            guard !used.contains(pattern.rawValue) else { continue }
            used.insert(pattern.rawValue)
            let template = PrescriptionTemplate(rules: StrengthProgressionRules(
                loadRule: .rmBased(RMBasedLoad(
                    rmType: .rm10,
                    weekOneFactor: HypertrophyProgramGenerator.primaryWeekOneFactor(for: .basicHypertrophy),
                    laterWeekMultipliers: HypertrophyProgramGenerator.laterWeekMultipliers
                )),
                setCountRule: .fixed(setsByWeek: [4, 4, 4, 4]),
                repGoalSchedule: [RepGoal(prescription: .fixedReps(8), repRangeHigh: 12, targetRir: 3)]
            ))
            context.insert(template)
            block.addPrescriptionTemplate(template)
            let slot = ExerciseSlot(name: pattern.slotName, allowedTargets: pattern.allowedTargets, allowedMovementFunctions: pattern.allowedMovementFunctions)
            context.insert(slot)
            template.attachExerciseSlot(slot)
        }
    }

    private static func addStrengthBlock(
        to session: TemplateSession, relativeWeek: Int = 0,
        archetype: FunctionalFitnessSessionArchetype = .unbiased,
        family: FunctionalFitnessSessionFamily? = nil,
        requiredLoadedPattern: MovementFunction? = nil,
        genericStrengthAssignment: MovementFunction? = nil,
        // MUSCLE + 5FF FINAL CLOSURE, Section 1/4 (project-owner
        // decision): `0` for every pre-existing call site/test
        // (completely unaffected). The one real weekly-plan call site
        // passes each session's own real `sessionIndexInWeek`, so the
        // fallback loaded-pattern rotation below (used whenever
        // `requiredLoadedPattern` is `nil`) varies BY SESSION within the
        // same real week, not only week-to-week — without this, every
        // session beyond the first two explicitly-overridden ones
        // collided on the exact same pattern (the real, traced root
        // cause of "Sessions 1/3/4 nearly identical").
        sessionIndexInWeek: Int = 0, context: ModelContext
    ) {
        // MUSCLE + 5FF FINAL CLOSURE, Section 16 (project-owner decision):
        // `.functionalBodybuilding`-archetype content (the Muscle-goal
        // main body) is genuine Hypertrophy prescription authority —
        // `addLoadedPatternPrescription` below uses
        // `HypertrophyProgramGenerator`'s own real, source-cited load
        // factors and rep/RIR schedule, never a Strength-goal
        // HIGH_LOAD_STRENGTH exposure. It was previously always typed
        // `.strength` — the SAME canonical type a genuine
        // `.strengthPower`-archetype session (real heavy/power/generic-
        // strength content) or a real Powerlifting source program uses —
        // "accidentally classifying all resistance work as strength
        // because the domain lacks a better type" (Section 16's own
        // language). `WorkoutBlockType.hypertrophy` already exists and is
        // already the real, established canonical type
        // `HypertrophyProgramGenerator`'s own blocks use for the
        // identical kind of content; every other archetype (`.strengthPower`,
        // `.unbiased`) is unaffected — kept exactly `.strength`, since
        // those really do represent (or, for `.unbiased`, predate this
        // Muscle-vs-Strength distinction and are out of this specific
        // audit's scope).
        let block = WorkoutBlockTemplate(type: archetype == .functionalBodybuilding ? .hypertrophy : .strength)
        context.insert(block)
        session.addBlockTemplate(block)

        // GENERIC STRENGTH PRESCRIPTION AUTHORITY V1, Section 14/17: when
        // the weekly allocator has assigned this session a genuine
        // remaining HIGH_LOAD_STRENGTH_EXPOSURE responsibility, that takes
        // precedence over every family-based branch below — this is a
        // completely separate adaptation (Section 7: "adaptation" is why
        // this work exists, distinct from `family`'s own dosing semantics).
        // `nil` for every pre-existing call site/test (completely
        // unaffected) and for every non-`.strengthPower` archetype.
        if let genericStrengthAssignment {
            addGenericHighLoadStrengthPrescription(pattern: genericStrengthAssignment, to: block, context: context)
            return
        }

        // PROGRAMMING AUTHORITY V1 — FINAL CLOSE-OUT, Part XV: `nil` for
        // every pre-existing call site/test — completely unaffected, the
        // `relativeWeek`-keyed rotation below applies exactly as before.
        // When set, overrides only the PRIMARY pattern for whichever
        // branch below picks one; a 2-pattern (`.functionalBodybuilding`)
        // session's complementary pattern is still derived from the
        // required one (`+2`, i.e. squat's complement is press, hinge's
        // is pull) rather than dropped, preserving that shape's real
        // 2-pattern main body.
        let requiredPattern: FunctionalBodybuildingPattern? = {
            switch requiredLoadedPattern {
            case .squatLoaded: return .squat
            case .hingeLoaded: return .hinge
            default: return nil
            }
        }()

        // FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V1 (Part IV.2/IV.3):
        // Strength-priority sessions (`.strengthPower` archetype) get
        // their own family-driven main body — heavy compound work for
        // `.heavyStrength`, low-volume quality work for `.powerAthletic`
        // — reusing the exact same real `StrengthProgressionRules`/
        // `RMBasedLoad`/`ExerciseSlot` machinery the Muscle-side roles
        // already use, never a new load-resolution system. `family ==
        // nil` (every pre-existing `.strengthPower` call site/test) keeps
        // the exact original single-pattern behavior, completely
        // unaffected.
        if archetype == .strengthPower, let family {
            switch family {
            case .heavyStrength, .powerAthletic:
                // GENERIC STRENGTH PRESCRIPTION AUTHORITY V1, Section 20/21:
                // reaching here means `genericStrengthAssignment` was `nil`
                // for THIS session — the weekly allocator did not assign it
                // a remaining HIGH_LOAD_STRENGTH_EXPOSURE responsibility
                // (either the fallback's 2-exposure target was already met
                // by earlier sessions this week, or by a real source
                // program). "Remaining FF sessions do NOT automatically
                // become heavy Strength days" (Section 20/21's explicit
                // requirement, confirmed by `testFixtureE_StrengthFourPowerliftingOneFF`/
                // `testFixtureG_StrengthFiveFFAlone`'s own doc comments) —
                // an unassigned heavyStrength/powerAthletic session falls
                // back to the same real, load-formula-free carry+trunk
                // content `.lowerFatigueComplementary` already uses, never
                // an invented duplicate heavy/power pattern.
                addDistanceAccessoryPrescription(name: "Functional Bodybuilding — Carry", movementFunction: .carry, targetDistanceMeters: 40, setCount: 3, to: block, context: context)
                addMovementFunctionAccessoryPrescription(name: "Functional Bodybuilding — Trunk", movementFunction: .trunk, to: block, context: context)
                return
            case .mixedResistanceWorkCapacity:
                // The same real, moderate loaded-pattern content Muscle
                // Gain's own single-lift path already uses — a Strength-
                // priority week's own lighter fallback slot borrows this
                // rather than inventing a second moderate-load scheme.
                let pattern = requiredPattern ?? FunctionalBodybuildingPattern.allCases[(relativeWeek + sessionIndexInWeek) % FunctionalBodybuildingPattern.allCases.count]
                addLoadedPatternPrescription(pattern: pattern, to: block, context: context)
                return
            case .lowerFatigueComplementary:
                addDistanceAccessoryPrescription(name: "Functional Bodybuilding — Carry", movementFunction: .carry, targetDistanceMeters: 40, setCount: 3, to: block, context: context)
                addMovementFunctionAccessoryPrescription(name: "Functional Bodybuilding — Trunk", movementFunction: .trunk, to: block, context: context)
                return
            default:
                break // resistanceDominant never reached in the Strength allocator branch.
            }
        }

        guard archetype == .functionalBodybuilding else {
            // Every other archetype (and the pre-Round-2 recurring path,
            // which never carries an archetype at all): exactly the
            // original single-lift behavior, completely unchanged.
            // `requiredPattern` is never actually non-nil on this path in
            // practice (Part XV's override only ever accompanies
            // `.functionalBodybuilding`/`.strengthPower`), included only
            // for defensive consistency with every other branch above.
            let pattern = requiredPattern ?? FunctionalBodybuildingPattern.allCases[(relativeWeek + sessionIndexInWeek) % FunctionalBodybuildingPattern.allCases.count]
            addLoadedPatternPrescription(pattern: pattern, to: block, context: context)
            return
        }

        // GENERAL PROGRAMMING ALLOCATION ARCHITECTURE V1 §13.C: a
        // `.lowerFatigueComplementary`-family session's own "reduced
        // systemic cost" comes from the MAIN BODY here — carry + trunk
        // only (the two roles Section 13.C's own language names
        // verbatim: "complementary patterns... carries... trunk"),
        // never the two heavier loaded compound patterns — rather than
        // from re-touching `stimulus.intensity`/`.systemicDemand`
        // directly (`FunctionalFitnessPhaseBiasPolicy`'s own established,
        // hard-won discipline: that path decouples Stage E's format/
        // duration-domain pairing via the decision engine's same-week
        // repair logic). Every other family (`.resistanceDominant`,
        // `.mixedResistanceWorkCapacity`) keeps the full, original 4-role
        // main body, completely unchanged.
        if family == .lowerFatigueComplementary {
            addDistanceAccessoryPrescription(name: "Functional Bodybuilding — Carry", movementFunction: .carry, targetDistanceMeters: 40, setCount: 3, to: block, context: context)
            addMovementFunctionAccessoryPrescription(name: "Functional Bodybuilding — Trunk", movementFunction: .trunk, to: block, context: context)
            return
        }

        // MUSCLE + 5FF FINAL CLOSURE, Section 5 (project-owner decision):
        // "Carry/trunk roles are legitimate programming roles. They are
        // NOT mandatory decorations for every Functional Fitness
        // session... Only add them when the session responsibility/week
        // requirements justify them." Previously EVERY resistanceDominant/
        // mixedResistanceWorkCapacity session unconditionally appended a
        // Carry + Trunk accessory pair here — since only one real catalog
        // exercise (Farmer's Carry/Toes-to-Bar) satisfies each narrow
        // role, this made both appear in every session of the week
        // regardless of real programming need (the exact reported
        // defect). The main body for these two families is now the real
        // PRIMARY + COMPLEMENTARY LOADED MOVEMENT pair only — two solid
        // compound lifts is a legitimate, complete resistance
        // responsibility on its own; carry/trunk work remains a real,
        // reachable role, but only for `.lowerFatigueComplementary`
        // (handled by its own dedicated branch above), where it is the
        // session's own deliberate, justified reduced-main-body shape —
        // never appended here as a default.
        let primaryPattern = requiredPattern ?? FunctionalBodybuildingPattern.allCases[(relativeWeek + sessionIndexInWeek) % FunctionalBodybuildingPattern.allCases.count]
        let complementaryPattern = FunctionalBodybuildingPattern.allCases[(primaryPattern.rawValue + 2) % FunctionalBodybuildingPattern.allCases.count]
        addLoadedPatternPrescription(pattern: primaryPattern, to: block, context: context)
        addLoadedPatternPrescription(pattern: complementaryPattern, to: block, context: context)
    }

    /// SOURCE AUTHORITY REUSE IMPLEMENTATION (FF V2 corrected architecture),
    /// Section 2/3/6: this role carries a genuine HYPERTROPHY_RESISTANCE
    /// responsibility (Muscle-goal `.functionalBodybuilding` sessions, and
    /// Strength's own `.mixedResistanceWorkCapacity` fallback, which
    /// already deliberately borrowed this same function pre-this-change —
    /// see that call site's own "the same real, moderate loaded-pattern
    /// content Muscle Gain's own single-lift path already uses" comment).
    /// The load rule and rep/RIR schedule now come DIRECTLY from
    /// `HypertrophyProgramGenerator`'s own real, source-cited Basic
    /// Hypertrophy policy — `primaryWeekOneFactor(for: .basicHypertrophy)`
    /// (0.85, `SOURCE_PROGRAM_MANIFEST.md`'s `MROUND(10RM×0.85, ...)`
    /// formula), `laterWeekMultipliers` ([1.05, 1.075, 1.1]), and
    /// `repGoalSchedule` ([.rir(3), .rir(3), .rir(2), .rir(1)]) — a
    /// reference to the SAME static source, never a copied literal, so a
    /// future change to Hypertrophy's own authority automatically carries
    /// here too. This REPLACES the prior, unsourced `weekOneFactor: 0.65`/
    /// `laterWeekMultipliers: [1.0, 1.0, 1.0]`/`.fixedReps(10)` — verified
    /// by direct source-workbook reconciliation to be unsourced and, for
    /// this checkpoint's purposes, superseded by the real Hypertrophy
    /// authority every other loaded-pattern role in this file now shares.
    private static func addLoadedPatternPrescription(pattern: FunctionalBodybuildingPattern, to block: WorkoutBlockTemplate, context: ModelContext) {
        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(
                rmType: .rm10,
                weekOneFactor: HypertrophyProgramGenerator.primaryWeekOneFactor(for: .basicHypertrophy),
                laterWeekMultipliers: HypertrophyProgramGenerator.laterWeekMultipliers
            )),
            setCountRule: .fixed(setsByWeek: [4, 4, 4, 4]),
            repGoalSchedule: HypertrophyProgramGenerator.repGoalSchedule
        ))
        context.insert(template)
        block.addPrescriptionTemplate(template)

        let slot = ExerciseSlot(name: pattern.slotName, allowedTargets: pattern.allowedTargets, allowedMovementFunctions: pattern.allowedMovementFunctions)
        context.insert(slot)
        template.attachExerciseSlot(slot)
    }

    /// GENERIC STRENGTH PRESCRIPTION AUTHORITY V1, Sections 9-13: the real
    /// weekly-allocator-assigned HIGH_LOAD_STRENGTH_EXPOSURE responsibility
    /// — a real, moderate-rep-range loaded pattern (3-6 reps, 2-3 RIR),
    /// distinct from both `.heavyStrength`'s 4x5 and `.powerAthletic`'s
    /// 3x3, since this is a fallback covering a real weekly requirement
    /// gap, not a family's own dedicated main body. Slot name prefixed
    /// "Generic Strength" so callers (`ProgrammingValidator`, this
    /// checkpoint's own tests) can distinguish it from every other
    /// loaded-pattern slot without a new stored field.
    private static func addGenericHighLoadStrengthPrescription(pattern: MovementFunction, to block: WorkoutBlockTemplate, context: ModelContext) {
        let bodybuildingPattern: FunctionalBodybuildingPattern
        switch pattern {
        case .squatLoaded: bodybuildingPattern = .squat
        case .hingeLoaded: bodybuildingPattern = .hinge
        case .pressLoaded: bodybuildingPattern = .press
        default: bodybuildingPattern = .pull
        }
        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .rmBased(RMBasedLoad(
                rmType: .rm1,
                weekOneFactor: 0.8,
                laterWeekMultipliers: HypertrophyProgramGenerator.laterWeekMultipliers
            )),
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]),
            repGoalSchedule: [RepGoal(prescription: .fixedReps(3), repRangeHigh: 6, targetRir: 2, targetRirHigh: 3)]
        ))
        context.insert(template)
        block.addPrescriptionTemplate(template)

        let slot = ExerciseSlot(
            name: "Generic Strength — \(bodybuildingPattern.slotName.replacingOccurrences(of: "Functional Bodybuilding — ", with: ""))",
            allowedTargets: bodybuildingPattern.allowedTargets, allowedMovementFunctions: bodybuildingPattern.allowedMovementFunctions
        )
        context.insert(slot)
        template.attachExerciseSlot(slot)
    }

    /// Dogfood Round 2 Continuation (Finding J): a carry is load- and
    /// distance-measured, never rep-measured.
    private static func addDistanceAccessoryPrescription(
        name: String, movementFunction: MovementFunction, targetDistanceMeters: Double, setCount: Int,
        to block: WorkoutBlockTemplate, context: ModelContext
    ) {
        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .fixed(setsByWeek: Array(repeating: setCount, count: 4)),
            repGoalSchedule: []
        ))
        template.targetDistanceMeters = targetDistanceMeters
        context.insert(template)
        block.addPrescriptionTemplate(template)

        let slot = ExerciseSlot(name: name, allowedMovementFunctions: [movementFunction])
        context.insert(slot)
        template.attachExerciseSlot(slot)
    }

    /// Trunk work: no real tested-RM basis, so no load rule is invented.
    private static func addMovementFunctionAccessoryPrescription(
        name: String, movementFunction: MovementFunction,
        to block: WorkoutBlockTemplate, context: ModelContext
    ) {
        let template = PrescriptionTemplate(rules: StrengthProgressionRules(
            loadRule: .none,
            setCountRule: .fixed(setsByWeek: [3, 3, 3, 3]),
            repGoalSchedule: [.fixedReps(15)]
        ))
        context.insert(template)
        block.addPrescriptionTemplate(template)

        let slot = ExerciseSlot(name: name, allowedMovementFunctions: [movementFunction])
        context.insert(slot)
        template.attachExerciseSlot(slot)
    }
}
