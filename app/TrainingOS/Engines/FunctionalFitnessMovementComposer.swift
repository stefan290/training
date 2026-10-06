import Foundation

/// Stage FF.M1: the two function CLASSES movement composition alternates
/// between (Design Lock/Amendment/Closure/Correction, all independently
/// reviewed). `CONDITIONING` (`monostructural`) is deliberately NOT a
/// third alternation member — it is Phase 2's secondary fill, never part
/// of the Phase 1 primary-coverage cycle (Correction 1: monostructural
/// must never be mechanically mandatory).
enum FunctionalFitnessMovementClass: CaseIterable {
    case loaded
    case gymnastics

    /// Fixed, stable declared order — the final deterministic tie-break
    /// within a class when same-week AND prior-week exposure are both
    /// tied. Never derived from `MovementFunction.allCases`' own
    /// declaration order (which includes functions outside FF.M1's
    /// accepted movement space) or from any Set/catalog iteration order.
    var orderedFunctions: [MovementFunction] {
        switch self {
        case .loaded: return [.squatLoaded, .hingeLoaded, .pressLoaded]
        case .gymnastics: return [.gymnasticsPull, .gymnasticsPush]
        }
    }

    var other: FunctionalFitnessMovementClass {
        self == .loaded ? .gymnastics : .loaded
    }
}

/// Stage FF.M1: Decision A — WHICH MovementFunctions belong in a session,
/// deterministically, continuous across an entire tactical week (not reset
/// per session). Never decides WHICH Exercise fills a chosen function —
/// that is `FunctionalFitnessMaterializer`'s own Stage-D-style resolution
/// (Decision B), unchanged in structure by this type.
///
/// **Two horizons, kept strictly separate (Correction 2):** `sameWeek`
/// exposure is PRIMARY — it alone decides whether primary coverage
/// (every currently-eligible function in `.loaded`/`.gymnastics` has ≥1
/// exposure this week) is still incomplete. `priorWeek` exposure is a
/// SECONDARY tie-break only, consulted exclusively when two functions are
/// otherwise equally valid under the same-week count — it can never cause
/// a worse same-week choice to be preferred over a better one.
///
/// **Role count is fixed at 3 per session** (reduced only by real
/// environment class-exclusion, handled by the caller passing a narrowed
/// `eligibleFunctions`/`monostructuralEligible` set — this type never
/// invents variety by varying role count itself).
struct FunctionalFitnessMovementComposer {
    private var sameWeekExposure: [MovementFunction: Int] = [:]
    private let priorWeekExposure: [MovementFunction: Int]
    private var nextClassDue: FunctionalFitnessMovementClass = .loaded

    init(priorWeekExposure: [MovementFunction: Int] = [:]) {
        self.priorWeekExposure = priorWeekExposure
    }

    /// Composes one session's movement functions. `eligibleFunctions` must
    /// already reflect TE.1 hard eligibility (only functions with ≥1
    /// real, environment-compatible candidate Exercise this week) —
    /// this composer performs no equipment reasoning itself, per the
    /// already-locked TE.1/composition boundary. `monostructuralEligible`
    /// is passed separately since CONDITIONING is never part of the
    /// primary `.loaded`/`.gymnastics` alternation.
    ///
    /// Returns FEWER than 3 roles only when `eligibleFunctions` (plus
    /// `monostructuralEligible`) genuinely cannot fill 3 — this is honest
    /// environment degradation, never invented variety (Correction 1/
    /// Amendment Part 15).
    /// Dogfood Round 2 (Finding 4): `archetype` is the real, explicit
    /// phase-driven input this checkpoint's trace found was missing —
    /// biasing only the authored `Stimulus.movementFunctions` field has
    /// zero athlete-visible effect, since this composer already
    /// recomputes roles from live eligibility/exposure every time (see
    /// `FunctionalFitnessPhaseBiasPolicy`'s own doc comment). Defaults to
    /// `.unbiased`, which reproduces this function's exact pre-existing
    /// behavior for every caller/test that doesn't pass one.
    /// FUNCTIONAL FITNESS V2 RESISTANCE AUTHORITY COMPLETION, Section
    /// 16-19: which loaded-pattern `MovementFunction`s this SAME session's
    /// own source-backed main body (Back Squat, etc. — a separate
    /// `WorkoutBlock` this composer never touches) already exposed
    /// meaningfully, for THIS ONE `composeSession` call only — never
    /// persisted into `sameWeekExposure` (which tracks conditioning-role
    /// assignments across the whole tactical week and must stay exactly
    /// that). Treated as a soft +1 same-session bonus when deciding
    /// primary-coverage priority, exactly like an existing same-week
    /// conditioning-role exposure would be — so the composer prefers an
    /// uncovered complementary pattern (e.g. hinge/press) over repeating
    /// squat when a genuine alternative exists, but still falls back to
    /// the exposed pattern when it's the only eligible one (Section 18:
    /// "do NOT prohibit repeated patterns when the assignment genuinely
    /// requires them"). Additive, defaults empty — every pre-existing
    /// call site/test is completely unaffected.
    mutating func composeSession(
        eligibleFunctions: Set<MovementFunction>, monostructuralEligible: Bool, targetRoleCount: Int = 3,
        archetype: FunctionalFitnessSessionArchetype = .unbiased,
        sameSessionMainBodyExposedFunctions: Set<MovementFunction> = []
    ) -> [MovementFunction] {
        var roles: [MovementFunction] = []
        var usedConditioningThisSession = false
        let preferLoadedFirst = archetype.prefersLoadedMovementEmphasis
        // Dogfood Round 2 (Finding E revision): for Muscle Gain, the
        // conditioning block is an OPTIONAL/SUBORDINATE short finisher, not
        // a standalone metcon — its own main body (a separate WorkoutBlock,
        // never composed by this type) already covers loaded/complementary/
        // accessory work, so this block's identity should be conditioning
        // itself, not another loaded role. Scoped narrowly to
        // `.functionalBodybuilding` (not the more general
        // `conditioningIsSubordinate`, which `.strengthPower` also
        // declares) so `.strengthPower`'s existing behavior is completely
        // unaffected — see this checkpoint's report for why extending this
        // to `.strengthPower` is a follow-up, not built here.
        let conditioningLeadsSession = archetype == .functionalBodybuilding

        while roles.count < targetRoleCount {
            if conditioningLeadsSession, !usedConditioningThisSession, monostructuralEligible {
                roles.append(.monostructural)
                usedConditioningThisSession = true
                continue
            }
            if let picked = pickPrimaryCoverage(
                eligibleFunctions: eligibleFunctions, preferLoadedFirst: preferLoadedFirst,
                sameSessionMainBodyExposedFunctions: sameSessionMainBodyExposedFunctions
            ) {
                roles.append(picked)
                sameWeekExposure[picked, default: 0] += 1
                continue
            }
            // Phase 2 (a): CONDITIONING fills the slot once primary
            // coverage is satisfied — a real programming reason
            // ("everything eligible has already been seen this week"),
            // never "it's next in a fixed loop" (Correction 1). Never
            // suppressed by archetype: an earlier version of this pass
            // suppressed it entirely for `.functionalBodybuilding`, which
            // — in a real environment with only one candidate per loaded/
            // gymnastics function — could force a THIRD role to repeat an
            // already-exhausted function/exercise instead of falling back
            // to this safe monostructural fill, leaving the role
            // genuinely unresolvable. `preferLoadedFirst` alone already
            // gives loaded compound patterns real priority; conditioning
            // remains available as the honest, always-safe fallback,
            // exactly as it already is for every other archetype.
            if !usedConditioningThisSession, monostructuralEligible {
                roles.append(.monostructural)
                usedConditioningThisSession = true
                continue
            }
            // Phase 2 (b): a second (or later) lap through the same
            // least-exposed-first rule — still deterministic, still
            // same-week-primary/prior-week-secondary.
            if let picked = pickLeastExposed(among: eligibleFunctions, sameSessionMainBodyExposedFunctions: sameSessionMainBodyExposedFunctions) {
                roles.append(picked)
                sameWeekExposure[picked, default: 0] += 1
                continue
            }
            // Nothing eligible at all beyond what's already been added —
            // an honest, smaller session (Correction 1/Part 7's minimum-
            // coherent-session floor). The caller is responsible for the
            // zero-classes-eligible `environmentIncompatible` throw.
            break
        }
        return roles
    }

    /// Phase 1: is there a currently-eligible function with ZERO same-week
    /// exposure? If so, pick the least-exposed one in whichever class is
    /// "due" per the continuous alternation cursor — falling back to the
    /// OTHER class if the due class has no uncovered candidate (alternation
    /// is a cadence heuristic, never allowed to block real coverage).
    ///
    /// Dogfood Round 2 (Finding 4): `preferLoadedFirst` overrides the
    /// alternation cursor to always try `.loaded` (squat/hinge/press)
    /// before `.gymnastics` — a real, deterministic bias toward compound
    /// loaded patterns for an archetype that wants them dominant, never a
    /// fabricated new movement vocabulary. `sameWeekExposure`/
    /// `priorWeekExposure` tie-breaking within a class is completely
    /// unaffected either way.
    private mutating func pickPrimaryCoverage(
        eligibleFunctions: Set<MovementFunction>, preferLoadedFirst: Bool,
        sameSessionMainBodyExposedFunctions: Set<MovementFunction>
    ) -> MovementFunction? {
        if preferLoadedFirst {
            if let picked = leastExposedUncovered(in: .loaded, eligibleFunctions: eligibleFunctions, sameSessionMainBodyExposedFunctions: sameSessionMainBodyExposedFunctions) {
                nextClassDue = .gymnastics
                return picked
            }
            if let picked = leastExposedUncovered(in: .gymnastics, eligibleFunctions: eligibleFunctions, sameSessionMainBodyExposedFunctions: sameSessionMainBodyExposedFunctions) {
                nextClassDue = .loaded
                return picked
            }
            return nil
        }
        let dueClass = nextClassDue
        if let picked = leastExposedUncovered(in: dueClass, eligibleFunctions: eligibleFunctions, sameSessionMainBodyExposedFunctions: sameSessionMainBodyExposedFunctions) {
            nextClassDue = dueClass.other
            return picked
        }
        let otherClass = dueClass.other
        if let picked = leastExposedUncovered(in: otherClass, eligibleFunctions: eligibleFunctions, sameSessionMainBodyExposedFunctions: sameSessionMainBodyExposedFunctions) {
            nextClassDue = otherClass.other
            return picked
        }
        return nil // primary coverage complete (or nothing eligible at all)
    }

    /// Section 16-19: a function already exposed by this SAME session's
    /// own source-backed main body is treated as NOT "uncovered" here —
    /// so a genuinely-uncovered complementary function wins primary
    /// coverage first. If every eligible function carries this bonus (no
    /// real alternative exists), this returns `nil` and Phase 2(b)'s
    /// `pickLeastExposed` below still allows it, ranked appropriately —
    /// never a hard prohibition.
    private func leastExposedUncovered(
        in cls: FunctionalFitnessMovementClass, eligibleFunctions: Set<MovementFunction>,
        sameSessionMainBodyExposedFunctions: Set<MovementFunction>
    ) -> MovementFunction? {
        let uncovered = cls.orderedFunctions.filter {
            eligibleFunctions.contains($0) && (sameWeekExposure[$0] ?? 0) == 0 && !sameSessionMainBodyExposedFunctions.contains($0)
        }
        guard !uncovered.isEmpty else { return nil }
        // Every candidate here is tied at same-week exposure 0 by
        // definition (that's what "uncovered" means) — so the real
        // tie-break is PRIOR-WEEK exposure (secondary), then fixed
        // declared order (final). Never skip straight to declared order
        // without consulting prior-week first.
        return uncovered.min { a, b in
            let priorA = priorWeekExposure[a] ?? 0
            let priorB = priorWeekExposure[b] ?? 0
            if priorA != priorB { return priorA < priorB }
            return (cls.orderedFunctions.firstIndex(of: a) ?? 0) < (cls.orderedFunctions.firstIndex(of: b) ?? 0)
        }
    }

    /// Phase 2(b): least SAME-WEEK exposed among all currently-eligible
    /// loaded/gymnastics functions (CONDITIONING excluded — it's handled
    /// separately, capped at 1/session), tie-broken by PRIOR-WEEK exposure
    /// (secondary), then fixed declared order (final).
    /// Section 16-19: a same-session-main-body-exposed function is ranked
    /// as if it carried one additional same-week exposure — a soft
    /// deprioritization, never an exclusion, so it remains selectable
    /// (and IS selected) when it is genuinely the only eligible function.
    private func pickLeastExposed(among eligibleFunctions: Set<MovementFunction>, sameSessionMainBodyExposedFunctions: Set<MovementFunction>) -> MovementFunction? {
        let candidates = FunctionalFitnessMovementClass.allCases.flatMap(\.orderedFunctions).filter { eligibleFunctions.contains($0) }
        guard !candidates.isEmpty else { return nil }
        let declaredOrder = FunctionalFitnessMovementClass.allCases.flatMap(\.orderedFunctions)
        return candidates.min { a, b in
            let sameWeekA = (sameWeekExposure[a] ?? 0) + (sameSessionMainBodyExposedFunctions.contains(a) ? 1 : 0)
            let sameWeekB = (sameWeekExposure[b] ?? 0) + (sameSessionMainBodyExposedFunctions.contains(b) ? 1 : 0)
            if sameWeekA != sameWeekB { return sameWeekA < sameWeekB }
            let priorA = priorWeekExposure[a] ?? 0
            let priorB = priorWeekExposure[b] ?? 0
            if priorA != priorB { return priorA < priorB }
            return (declaredOrder.firstIndex(of: a) ?? 0) < (declaredOrder.firstIndex(of: b) ?? 0)
        }
    }
}
