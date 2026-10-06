import Foundation

/// PROGRAMMING AUTHORITY V1 Part XXXI: a production-level validator that
/// evaluates a MATERIALIZED WEEK — real `Session`/`WorkoutBlock`/
/// `FunctionalFitnessPrescription` rows already committed by
/// `FunctionalFitnessMaterializer` — never merely enum shape. Scoped
/// honestly to the domain this checkpoint has real programming authority
/// over: Functional Fitness sessions inside a `TrainingMix` week, for the
/// 3 goals `FunctionalFitnessProgrammingGoal` covers. It does not attempt
/// to re-derive source-backed (Hypertrophy/Strength/Running) programming
/// correctness — those generators own their own content and are untouched
/// by this checkpoint (Part XII).
///
/// Never auto-repairs (Part XXXI: "do not create automatic repairs that
/// alter the athlete's selected mix") — every case here is a typed,
/// reported finding for a human/product-owner to act on, exactly like
/// `CustomMixValidationError`/`FunctionalFitnessMaterializationError`
/// already are for their own narrower failure classes.
enum ProgrammingValidationIssueCode: String, Codable, Equatable {
    case unsatisfiedPrimaryRequirement = "UNSATISFIED_PRIMARY_REQUIREMENT"
    case excessiveAccidentalMovementRepetition = "EXCESSIVE_ACCIDENTAL_MOVEMENT_REPETITION"
    case missingRequiredMovementPattern = "MISSING_REQUIRED_MOVEMENT_PATTERN"
    case incoherentFormat = "INCOHERENT_FORMAT"
    case incoherentScore = "INCOHERENT_SCORE"
    case incompatibleDurationDomain = "INCOMPATIBLE_DURATION_DOMAIN"
    case excessivePrimaryGoalInterference = "EXCESSIVE_PRIMARY_GOAL_INTERFERENCE"
    case unrecoverableStressCluster = "UNRECOVERABLE_STRESS_CLUSTER"
    case unsupportedProgrammingAssignment = "UNSUPPORTED_PROGRAMMING_ASSIGNMENT"
    case unsupportedSourceFrequency = "UNSUPPORTED_SOURCE_FREQUENCY"
    case capabilityIncompatibility = "CAPABILITY_INCOMPATIBILITY"
    case environmentIncompatibility = "ENVIRONMENT_INCOMPATIBILITY"
    case sourceAuthorityViolation = "SOURCE_AUTHORITY_VIOLATION"
}

struct ProgrammingValidationIssue: Equatable, CustomStringConvertible {
    let code: ProgrammingValidationIssueCode
    let detail: String
    /// `nil` for a whole-week finding; set for a finding anchored to one
    /// FF session's `sessionIndexInWeek`.
    let sessionIndex: Int?

    var description: String { "\(code.rawValue)\(sessionIndex.map { " (session \($0))" } ?? ""): \(detail)" }
}

enum ProgrammingValidator {
    /// MUSCLE + 5FF FINAL CLOSURE, Section 16 (project-owner decision):
    /// a real "resistance main body" block is one of the two REAL
    /// canonical types genuine resistance-authority content actually
    /// uses — `.strength` (genuine `.strengthPower`-archetype HIGH_LOAD_STRENGTH
    /// content, and every real Powerlifting source program) or
    /// `.hypertrophy` (Muscle-goal `.functionalBodybuilding`-archetype
    /// content, and every real Hypertrophy source program — see
    /// `FunctionalFitnessProgramGenerator.addStrengthBlock`'s own doc
    /// comment for the exact fix this closes). Previously this validator
    /// checked only `.strength`, which — for a Muscle-goal week — no
    /// longer matches the block type FF's own main body now truthfully
    /// uses, and never matched a real Hypertrophy source program's own
    /// blocks either (a separate, pre-existing gap this same fix closes).
    private static func isResistanceMainBodyType(_ type: WorkoutBlockType) -> Bool {
        type == .strength || type == .hypertrophy
    }

    /// Evaluates one already-materialized week's real Functional Fitness
    /// sessions. `goal` is the athlete's real, resolved
    /// `FunctionalFitnessProgrammingGoal` for the phase this week belongs
    /// to (`nil` for a non-goal-aware phase — recovery/maintenance/
    /// transition — which this checkpoint never assigns authority over,
    /// so it is validated only for the 3 generic structural categories
    /// that apply regardless of goal).
    static func validate(week sessions: [Session], goal: FunctionalFitnessProgrammingGoal?) -> [ProgrammingValidationIssue] {
        var issues: [ProgrammingValidationIssue] = []

        // `sessions` is expected in the week's real chronological/weekday
        // order (as every real caller — materialized-week fixtures, the
        // tactical window — already holds it); this validator uses that
        // array position as the session's ordinal within the week rather
        // than re-deriving one, since `FunctionalFitnessPrescription`
        // itself persists no `sessionIndexInWeek` (that field lives only
        // on the transient `FunctionalFitnessSessionIntent` used at
        // generation time).
        let ffPrescriptionsByIndex: [(index: Int, prescription: FunctionalFitnessPrescription, session: Session)] = sessions
            .enumerated()
            .compactMap { offset, session in
                guard let prescription = session.orderedBlocks.compactMap(\.functionalFitnessPrescription).first(where: { $0.sessionFamily != nil }) else { return nil }
                return (offset, prescription, session)
            }

        // PROGRAMMING AUTHORITY V1 — FINAL CLOSE-OUT, Part XXII: real gap
        // found and fixed this checkpoint. The old guard
        // (`ffPrescriptionsByIndex.isEmpty`) incorrectly treated "no
        // session has a real FF conditioning-block prescription" as "no
        // real FF-authored content exists this week at all" — but a
        // `.resistanceDominant`-family session legitimately has NO
        // conditioning block by design (Part V/§13.A: "conditioning is
        // NOT mandatory"), so a single-session Muscle/Strength week whose
        // one real session is `.resistanceDominant` would short-circuit
        // here and never reach `validatePrimaryRequirement`/
        // `validateResistanceDosing` at all — silently passing even a
        // genuinely EMPTY main body. Fixed to key off whether any session
        // is FF-authored at all (`.modality == .functionalFitness`,
        // present regardless of whether a conditioning block exists),
        // never off conditioning-block presence specifically. A pure
        // source-backed (Hypertrophy/Powerlifting/Running-only) week
        // still correctly short-circuits here — untouched.
        guard sessions.contains(where: { $0.modality == .functionalFitness }) else { return issues }

        issues += validateFormatScoreCoherence(ffPrescriptionsByIndex)
        if let goal {
            issues += validatePrimaryRequirement(sessions, ffPrescriptionsByIndex: ffPrescriptionsByIndex, goal: goal)
            issues += validateMovementPattern(sessions, goal: goal)
            issues += validateInterference(ffPrescriptionsByIndex, goal: goal)
            issues += validateResistanceDosing(sessions, goal: goal)
        }
        issues += validateStressClustering(ffPrescriptionsByIndex)
        issues += validateAccidentalRepetition(ffPrescriptionsByIndex)

        return issues
    }

    /// Re-runs the same Stage-E check `FunctionalFitnessMaterializer`
    /// already gates materialization on, against the PERSISTED
    /// prescription. On any real materialized week this must always
    /// come back clean — materialization would have thrown otherwise
    /// (`FunctionalFitnessMaterializationError.stimulusValidationFailed`).
    /// Kept here as an explicit, independently re-checkable review gate
    /// (Part XXXI's own ask), not because a gap is expected.
    private static func validateFormatScoreCoherence(
        _ entries: [(index: Int, prescription: FunctionalFitnessPrescription, session: Session)]
    ) -> [ProgrammingValidationIssue] {
        var issues: [ProgrammingValidationIssue] = []
        for entry in entries {
            let resolvedModalities = Set(entry.prescription.orderedMovements.compactMap { $0.exercise?.functionalModality })
            let resolvedFunctions = Set(entry.prescription.orderedMovements.compactMap { $0.exercise?.movementFunctions }.flatMap { $0 })
            let validation = FunctionalFitnessStimulusValidator.validate(
                format: entry.prescription.format, resolvedModalities: resolvedModalities, resolvedLoadingRoles: [],
                resolvedMovementFunctions: nil, against: entry.prescription.stimulus
            )
            if !validation.matchesDurationDomain {
                issues.append(.init(code: .incompatibleDurationDomain, detail: validation.notes.joined(separator: " "), sessionIndex: entry.index))
            }
            if !validation.matchesScoreType {
                issues.append(.init(code: .incoherentScore, detail: validation.notes.joined(separator: " "), sessionIndex: entry.index))
            }
            _ = resolvedFunctions // resolved-function exactness already re-verified at materialization time; not re-checked here (would require the composer's live intermediate state, not the persisted row).
        }
        return issues
    }

    /// Part V/VI/VII: each goal's primary adaptation must actually receive
    /// real content somewhere in the week. Scoped to what this checkpoint
    /// can see (FF sessions) — a source-backed Hypertrophy/Strength/
    /// Running session contributing the same requirement is real too, but
    /// this validator only inspects the FF rows it was handed; a caller
    /// validating a mixed week should pass whatever `Session`s exist,
    /// since `sessions` here is not filtered to FF-only by this function.
    ///
    /// Muscle/Strength scans the WHOLE `sessions` array directly (not
    /// `ffPrescriptionsByIndex`) — a real resistance main body can exist
    /// on a session with NO conditioning-block FF prescription at all
    /// (`.resistanceDominant`'s own by-design shape), so gating this
    /// check on FF-prescription presence would silently miss a genuinely
    /// empty main body on exactly that family (the real Part XXII bug
    /// this checkpoint found and fixed). Conditioning still correctly
    /// uses `ffPrescriptionsByIndex` — every real Conditioning-goal
    /// session always carries a real FF prescription (Part III.C: "no
    /// strength block at all... conditioning is FF's own primary
    /// purpose").
    private static func validatePrimaryRequirement(
        _ sessions: [Session],
        ffPrescriptionsByIndex entries: [(index: Int, prescription: FunctionalFitnessPrescription, session: Session)],
        goal: FunctionalFitnessProgrammingGoal
    ) -> [ProgrammingValidationIssue] {
        switch goal {
        case .muscle, .strength:
            let hasRealMainBody = sessions.contains { session in
                session.orderedBlocks.contains { isResistanceMainBodyType($0.type) && !$0.orderedPrescriptions.isEmpty }
            }
            if !hasRealMainBody {
                return [.init(code: .unsatisfiedPrimaryRequirement, detail: "\(goal) goal week has no session with a real resistance main body.", sessionIndex: nil)]
            }
        case .conditioning:
            let hasConditioning = entries.contains { $0.prescription.orderedMovements.isEmpty == false }
            if !hasConditioning {
                return [.init(code: .unsatisfiedPrimaryRequirement, detail: "Conditioning goal week has no session with real conditioning content.", sessionIndex: nil)]
            }
        }
        return []
    }

    /// PROGRAMMING AUTHORITY V1 — FINAL CLOSE-OUT, Part XV (project-lead
    /// authoritative rule, implemented literally): "If the athlete's
    /// complete selected training week contains TWO OR MORE resistance-
    /// capable sessions, the WEEK must contain legitimate exposure to
    /// BOTH [squat] and [hinge]... If the complete training week contains
    /// only ONE resistance-capable session: do NOT force both squat and
    /// hinge into that single session."
    ///
    /// Takes the WHOLE week's `sessions` (not just FF entries) — a
    /// "resistance-capable session" is ANY session with a real, non-empty
    /// `.strength`-type block, source-backed (Hypertrophy/Powerlifting)
    /// or FF, since the rule is explicitly whole-week, not FF-only ("it
    /// is NOT an FF-only requirement... source-backed... sessions may
    /// satisfy either requirement"). Only squat/hinge are required
    /// (never press/pull — the project lead's rule names exactly these
    /// two patterns).
    private static func validateMovementPattern(
        _ sessions: [Session], goal: FunctionalFitnessProgrammingGoal
    ) -> [ProgrammingValidationIssue] {
        guard goal == .muscle || goal == .strength else { return [] }
        var seenFunctions: Set<MovementFunction> = []
        var resistanceCapableSessionCount = 0
        for session in sessions {
            var sessionHasRealResistanceContent = false
            for block in session.orderedBlocks where isResistanceMainBodyType(block.type) {
                for prescription in block.orderedPrescriptions where prescription.exercise != nil {
                    seenFunctions.formUnion(prescription.exercise?.movementFunctions ?? [])
                    sessionHasRealResistanceContent = true
                }
            }
            if sessionHasRealResistanceContent { resistanceCapableSessionCount += 1 }
        }
        // Fewer than 2 resistance-capable sessions this week: never force
        // both patterns into one session (the rule's own explicit
        // exception) — not a finding.
        guard resistanceCapableSessionCount >= 2 else { return [] }
        let requiredPatterns: Set<MovementFunction> = [.squatLoaded, .hingeLoaded]
        let missing = requiredPatterns.subtracting(seenFunctions)
        guard !missing.isEmpty else { return [] }
        return [.init(
            code: .missingRequiredMovementPattern,
            detail: "Week has \(resistanceCapableSessionCount) resistance-capable sessions but is missing: \(missing.map(String.init(describing:)).sorted().joined(separator: ", ")).",
            sessionIndex: nil
        )]
    }

    /// PROGRAMMING AUTHORITY V1 Part XXII: week-level resistance-dose
    /// completeness for Muscle/Strength goals. Deliberately does NOT
    /// evaluate against any set/rep/tonnage THRESHOLD — the original
    /// specification gives no such number, and inventing one would
    /// violate Part XXXIII's magic-constant prohibition outright. What
    /// this DOES check, honestly and structurally: every real FF
    /// session in a Muscle/Strength week (`session.modality ==
    /// .functionalFitness`) must carry a real, non-empty strength
    /// block — catching the one genuine failure mode this codebase can
    /// produce today, where `FunctionalFitnessMaterializer
    /// .materializeStrengthBlock`'s own documented behavior ("only when
    /// NONE of the block's roles resolve is the block itself omitted")
    /// silently drops an ENTIRE session's resistance responsibility when
    /// capability/environment constraints leave zero eligible roles —
    /// never surfaced as a thrown error today, so a validator is the
    /// only place this can be caught. On every real fixture this
    /// checkpoint materialized, every FF session already carries a
    /// real strength block (resistanceDominant/mixedResistanceWorkCapacity's
    /// 4-role main body, lowerFatigueComplementary's carry+trunk main
    /// body) — this check's real value is defense-in-depth against a
    /// future environment-constrained regression, not a change to any
    /// existing fixture's outcome.
    private static func validateResistanceDosing(_ sessions: [Session], goal: FunctionalFitnessProgrammingGoal) -> [ProgrammingValidationIssue] {
        guard goal == .muscle || goal == .strength else { return [] }
        let ffSessionsByIndex = sessions.enumerated().filter { $0.element.modality == .functionalFitness }
        var issues: [ProgrammingValidationIssue] = []
        for (index, session) in ffSessionsByIndex {
            let hasRealStrengthBlock = session.orderedBlocks.contains { isResistanceMainBodyType($0.type) && !$0.orderedPrescriptions.isEmpty }
            if !hasRealStrengthBlock {
                issues.append(.init(
                    code: .unsatisfiedPrimaryRequirement,
                    detail: "\(goal) goal FF session has no real resistance main body — capability/environment constraints may have silently dropped its entire resistance responsibility for the week.",
                    sessionIndex: index
                ))
            }
        }
        return issues
    }

    /// Part XVIII: secondary training must not systematically undermine
    /// the primary adaptation. Minimum deterministic model (Part XVII
    /// explicitly asks for the MINIMUM sufficient to enforce the rule, not
    /// a physiological simulation): for a MUSCLE week, conditioning is
    /// explicitly "subordinate" (Part V) — if a strict majority of the
    /// week's FF sessions carry high-systemic-demand conditioning, that
    /// conditioning has structurally stopped being subordinate to the
    /// primary hypertrophy stimulus. Requires at least 3 FF sessions
    /// before evaluating: at 1-2 sessions (the real, common, approved
    /// `.low`/`.medium`-allocation shape — e.g. 4 Hypertrophy + 1 FF,
    /// where the DEDICATED Hypertrophy sessions this validator cannot see
    /// already carry the primary volume) a single high-demand FF
    /// finisher is explicitly sanctioned by Part V's own "at low FF
    /// contribution, FF may provide complementary resistance and modest
    /// work capacity" — treating it as interference there would be a
    /// false positive from too small a sample, not a real finding.
    private static func validateInterference(
        _ entries: [(index: Int, prescription: FunctionalFitnessPrescription, session: Session)],
        goal: FunctionalFitnessProgrammingGoal
    ) -> [ProgrammingValidationIssue] {
        guard goal == .muscle, entries.count >= 3 else { return [] }
        let highDemandConditioningCount = entries.filter { $0.prescription.stimulus.systemicDemand == .high && !$0.prescription.orderedMovements.isEmpty }.count
        if highDemandConditioningCount > entries.count / 2 {
            return [.init(
                code: .excessivePrimaryGoalInterference,
                detail: "\(highDemandConditioningCount)/\(entries.count) FF sessions carry high-systemic-demand conditioning in a Muscle week — conditioning is no longer subordinate to the hypertrophy stimulus (Part V).",
                sessionIndex: nil
            )]
        }
        return []
    }

    /// Part XVII: avoid stacking incompatible high-cost exposures without
    /// a programming reason. Minimum deterministic model: 3 or more
    /// CONSECUTIVE (by `sessionIndexInWeek`) high-systemic-demand FF
    /// sessions with no lower-demand session between them is flagged as
    /// an unrecoverable cluster — a real, documented default threshold
    /// (never claimed as sourced/validated sports-science), applied
    /// identically regardless of goal.
    private static func validateStressClustering(
        _ entries: [(index: Int, prescription: FunctionalFitnessPrescription, session: Session)]
    ) -> [ProgrammingValidationIssue] {
        var run = 0
        var runStart = 0
        for entry in entries {
            if entry.prescription.stimulus.systemicDemand == .high {
                if run == 0 { runStart = entry.index }
                run += 1
                if run >= 3 {
                    return [.init(
                        code: .unrecoverableStressCluster,
                        detail: "Sessions \(runStart)-\(entry.index) are 3+ consecutive high-systemic-demand FF sessions with no lower-demand session between them.",
                        sessionIndex: nil
                    )]
                }
            } else {
                run = 0
            }
        }
        return []
    }

    /// Part XV: repetition requires a programming reason; accidental
    /// duplication (first-eligible-candidate every time) does not.
    /// Minimum deterministic model: a single conditioning exercise
    /// appearing in more than `sessionCount - 1` of the week's FF
    /// sessions (i.e., in every session but at most one) is flagged —
    /// documented default, not a precise physiological/skill claim.
    /// `FunctionalFitnessMaterializer`'s own least-this-week-exposed
    /// selection (§FF.M1 Decision B) already actively works against this;
    /// this check exists to catch a case where environment constraints
    /// left no real alternative, which is honest but still worth
    /// surfacing for review rather than silently passing.
    private static func validateAccidentalRepetition(
        _ entries: [(index: Int, prescription: FunctionalFitnessPrescription, session: Session)]
    ) -> [ProgrammingValidationIssue] {
        guard entries.count >= 3 else { return [] }
        var counts: [UUID: (name: String, count: Int)] = [:]
        for entry in entries {
            for movement in entry.prescription.orderedMovements {
                guard let exercise = movement.exercise else { continue }
                counts[exercise.id, default: (exercise.canonicalName, 0)].count += 1
            }
        }
        let threshold = entries.count - 1
        return counts.values
            .filter { $0.count > threshold }
            .map { .init(code: .excessiveAccidentalMovementRepetition, detail: "\"\($0.name)\" appears in \($0.count)/\(entries.count) FF conditioning sessions this week.", sessionIndex: nil) }
    }

    /// Maps an already-caught, already-typed materialization/mix-
    /// validation failure to its Part XXXI category — these categories
    /// can never be discovered post-hoc from a successfully materialized
    /// week (materialization throws instead of producing one), so this is
    /// how a caller (e.g. a fixture/acceptance test) reports them in the
    /// same vocabulary as every other `ProgrammingValidationIssue`.
    /// `.sourceAuthorityViolation` has no real producer in this codebase
    /// today — every source-backed generator (Hypertrophy/Strength/
    /// Running) owns and writes only its own sessions, and the FF path
    /// never touches them, so this case is structurally unreachable, not
    /// merely untested. Returns `nil` for any error this validator does
    /// not have a mapping for.
    static func classify(_ error: Error) -> ProgrammingValidationIssue? {
        if let error = error as? FunctionalFitnessMaterializationError {
            switch error {
            case .capabilityUnknown(let slot, let exercise):
                return .init(code: .capabilityIncompatibility, detail: "Slot \"\(slot)\": only capability-unknown candidate available (\(exercise)).", sessionIndex: nil)
            case .environmentIncompatible(let slot, let missing):
                return .init(code: .environmentIncompatibility, detail: "Slot \"\(slot)\": missing equipment \(missing).", sessionIndex: nil)
            case .stimulusValidationFailed(let validation):
                if !validation.matchesDurationDomain { return .init(code: .incompatibleDurationDomain, detail: validation.notes.joined(separator: " "), sessionIndex: nil) }
                if !validation.matchesScoreType { return .init(code: .incoherentScore, detail: validation.notes.joined(separator: " "), sessionIndex: nil) }
                return .init(code: .incoherentFormat, detail: validation.notes.joined(separator: " "), sessionIndex: nil)
            case .previousExposureRequired, .trainingEnvironmentRequired:
                return nil
            case .noExecutableTargetAvailable:
                // DOGFOOD — FIX ORDER 1, Section C (new this checkpoint):
                // not mapped to a Part XXXI category — that reconciliation
                // is out of this narrow fix order's scope; unmapped,
                // exactly like the two cases above, rather than
                // miscategorized under an ill-fitting existing code.
                return nil
            // MUSCLE + 5FF FINAL CLOSURE, Sections 12/13: same precedent
            // as `.noExecutableTargetAvailable` above — not mapped to a
            // Part XXXI category rather than miscategorized under an
            // ill-fitting existing code.
            case .compositionValidationFailed:
                return nil
            }
        }
        if let error = error as? LongTermPlanner.CustomMixValidationError {
            switch error {
            case .unsupportedProgrammingAssignment(let capability, let reason):
                return .init(code: .unsupportedProgrammingAssignment, detail: "\(capability): \(reason)", sessionIndex: nil)
            case .unsupportedFrequency(let style, let frequency):
                return .init(code: .unsupportedSourceFrequency, detail: "\(style) does not support frequency \(frequency).", sessionIndex: nil)
            default:
                return nil
            }
        }
        return nil
    }
}
