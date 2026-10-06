import Foundation

/// FUNCTIONAL FITNESS V2 — RESISTANCE AUTHORITY RESOLUTION, Sections 2-13:
/// the general, evidence-backed WEEKLY muscle-volume fallback — used ONLY
/// to fill a gap behind real source-backed program contribution, never to
/// override or truncate it. This is the project lead's own locked
/// programming decision (Section 2, citing the 2026 ACSM Position Stand);
/// this type implements it, it does not re-derive or second-guess it.
///
/// Deliberately NOT a per-session, per-movement-pattern, or per-frequency
/// target (Sections 4/8) — the ledger is scoped to the WHOLE selected
/// week, once, regardless of how many resistance-capable sessions exist.
enum MuscleVolumeRequirementCalculator {
    /// Section 2's locked anchor. A baseline target, not a maximum, not a
    /// minimum, not a per-session/per-pattern value.
    static let weeklyFallbackSetCreditTarget: Double = 10.0

    /// Section 5: the minimal tracked major-muscle-region set for this
    /// checkpoint's general fallback, reusing the existing, already-
    /// catalog-owned `MuscleGroup` enum (no new type needed — Section 5's
    /// own instruction to check existing metadata before adding a new
    /// domain). Arms/core/calves/forearms/delt-subdivisions are
    /// deliberately excluded from the LEDGER (Section 5: arms only "if
    /// existing source/catalog semantics support doing so cleanly" — for
    /// this checkpoint they don't have a clean, separate weekly-target
    /// meaning distinct from the muscle groups they already ride along
    /// with in the catalog's own `primaryTargets` tagging).
    static let trackedGroups: Set<MuscleGroup> = [.quadriceps, .hamstrings, .glutes, .chest, .back, .shoulders]

    /// Section 6/9: real source-backed weekly contribution, read directly
    /// from every Hypertrophy `TrainingMixComponent`'s real
    /// `ProgramDefinition` — never a rewrite of the source, never an
    /// inference from exercise names. `ExerciseSlot.allowedTargets` is
    /// the source program's OWN declared muscle-group intent for that
    /// slot (Stage 4C's existing, pre-existing field), independent of
    /// whether real vs. placeholder exercise content currently resolves
    /// it — this is deliberate: the manifest's own disclosed "2 of 26
    /// real slots" content gap for Hypertrophy does not mean the SOURCE
    /// PROGRAM's declared muscle-group responsibility is unknown, only
    /// that its exercise CONTENT is incomplete. Crediting from the slot's
    /// declared target is honest source-contribution accounting; crediting
    /// from a placeholder exercise's own (nonexistent/generic) tags would
    /// not be.
    ///
    /// Each row's Week-1 set count (a `.fixed` schedule's first entry, or
    /// an `.autoregulated` rule's `baselineSets`) credits 1.0 per tracked
    /// declared target group — Section 6 gives no basis for a fractional
    /// per-slot credit at the SOURCE side (unlike Section 7's real
    /// direct/indirect distinction, which governs FF's OWN exercise
    /// selection only, Section 7's own explicit scope).
    static func sourceContribution(mix: TrainingMix) -> [MuscleGroup: Double] {
        var totals: [MuscleGroup: Double] = [:]
        for component in mix.orderedComponents where component.programmingSystem == .hypertrophy {
            guard let definition = component.programInstance?.programDefinition else { continue }
            for session in definition.orderedTemplateSessions {
                // MUSCLE RESISTANCE — FINAL PRODUCTION-PATH PROOF: real
                // production-path testing (`testProductionJourney_SourceOverage_...`)
                // caught a genuine defect here — every real Hypertrophy
                // program's own blocks are constructed with
                // `WorkoutBlockType.hypertrophy` (confirmed directly:
                // `HypertrophyProgramGenerator.swift`'s two real block
                // constructions both use `WorkoutBlockTemplate(type:
                // .hypertrophy)`), never `.strength` — `.strength` is a
                // DIFFERENT, distinct `WorkoutBlockType` case FF's own
                // materializer happens to use for its own main-body role.
                // The old `== .strength` filter therefore matched ZERO
                // real Hypertrophy template blocks ever, meaning
                // `sourceContribution` silently returned an empty
                // dictionary for every real Hypertrophy mix — the
                // "source contributes first" principle was never actually
                // active in production; every FF allocation was computed
                // against the full, un-reduced 10.0 fallback regardless of
                // how much real dedicated Hypertrophy volume existed.
                // Fixed to the real block type Hypertrophy actually uses.
                for block in session.orderedBlockTemplates where block.type == .hypertrophy {
                    for template in block.orderedPrescriptionTemplates {
                        guard let slot = template.exerciseSlot else { continue }
                        let weekOneSets = weekOneSetCount(for: template.rules?.setCountRule)
                        guard weekOneSets > 0 else { continue }
                        for group in slot.allowedTargets where trackedGroups.contains(group) {
                            totals[group, default: 0] += Double(weekOneSets)
                        }
                    }
                }
            }
        }
        return totals
    }

    private static func weekOneSetCount(for rule: SetCountRule?) -> Int {
        switch rule {
        case .fixed(let setsByWeek): return setsByWeek.first ?? 0
        case .autoregulated(let auto): return auto.baselineSets
        case nil: return 0
        }
    }

    /// Section 8/9/10: `max(0, fallback - source)` per tracked group —
    /// never negative, never truncating source overage. An over-target
    /// source contribution (Section 10) simply drives its own group's
    /// remaining requirement to exactly 0; the real source volume itself
    /// is never touched, reduced, or reported as "too much" anywhere in
    /// this type.
    static func remainingRequirement(sourceContribution: [MuscleGroup: Double]) -> [MuscleGroup: Double] {
        var remaining: [MuscleGroup: Double] = [:]
        for group in trackedGroups {
            let already = sourceContribution[group] ?? 0
            remaining[group] = max(0, weeklyFallbackSetCreditTarget - already)
        }
        return remaining
    }

    /// Section 11/12/13: how many ADDITIONAL physical sets a specific,
    /// already-selected `Exercise` should receive from the remaining
    /// weekly ledger. Always an integer (Section 12 — a programmed set is
    /// an integer set; set credits are an accounting abstraction only),
    /// keyed on the SINGLE most-underserved group the exercise directly
    /// credits — never the SUM of every group it touches, since one
    /// physical set legitimately closes every group's ledger entry it
    /// hits simultaneously (Section 12's own "one physical set may
    /// contribute to multiple group ledgers... do not sum all
    /// muscle-group deficits and create one physical set for each ledger
    /// entry").
    ///
    /// Section 13's exact rounding rule: a remaining deficit under 1.0
    /// set credit is already considered satisfied — `.down`, never
    /// `.up`, so a fractional remainder alone never manufactures an
    /// extra whole physical set.
    ///
    /// Only `exercise.primaryTargets` (DIRECT contribution) counts toward
    /// this calculation — Section 7's INDIRECT (0.5-credit) tier exists
    /// for future, more granular per-set accounting, but Section 12
    /// itself only ever asks for an integer physical-set COUNT here, not
    /// a fractional indirect credit sum; using DIRECT-only for this
    /// specific "how many sets" decision avoids Section 13's forbidden
    /// "manufacture an extra set from a fractional indirect credit."
    static func neededSets(for exercise: Exercise, remainingRequirement: [MuscleGroup: Double]) -> Int {
        let directGroups = Set(exercise.primaryTargets).intersection(trackedGroups)
        guard !directGroups.isEmpty else { return 0 }
        let maxDeficit = directGroups.map { remainingRequirement[$0] ?? 0 }.max() ?? 0
        return Int(maxDeficit.rounded(.down))
    }

    /// Section 11/15: whole-week-first, deterministic, order-independent
    /// distribution across every eligible FF hypertrophy-resistance
    /// session in the week (never a duplicate copy of the same total —
    /// Journeys B/C's explicit requirement). Depends only on the total
    /// needed sets and how many eligible sessions exist this week, keyed
    /// by `sessionIndexInWeek` — never on materialization call order, so
    /// reversing iteration order cannot change any session's assigned
    /// share (Section 31/36).
    ///
    /// Disclosed simplification, not silently claimed as complete: this
    /// is an EVEN split (earlier `sessionIndexInWeek` values absorb the
    /// integer remainder) — real capability/environment/recovery-aware
    /// weighting across sessions (Section 11's fuller "capability-aware,
    /// environment-aware... recovery/coherence-aware" list) is not
    /// implemented this checkpoint; distribution is source-aware,
    /// pattern-aware (via `neededSets`'s own per-exercise deficit), and
    /// frequency-aware (Section 8/14: more FF sessions divide the SAME
    /// total, never multiply it) but not the full multi-factor model the
    /// order's fuller language describes.
    static func distributedSetCount(totalNeededSets: Int, sessionIndexAmongEligible: Int, eligibleSessionCount: Int) -> Int {
        guard eligibleSessionCount > 0 else { return 0 }
        let base = totalNeededSets / eligibleSessionCount
        let remainder = totalNeededSets % eligibleSessionCount
        return base + (sessionIndexAmongEligible < remainder ? 1 : 0)
    }

    /// FUNCTIONAL FITNESS V2 — RESISTANCE COMPLETION, Sections 2-8: the
    /// real fix for the disclosed cross-pattern double-count defect.
    /// `neededSets`/`distributedSetCount` above each independently asked
    /// "how many total sets does THIS exercise's own worst group need
    /// across the whole week," against a STATIC, never-updated snapshot —
    /// so a squat-pattern session and a hinge-pattern session sharing a
    /// tracked group (e.g. glutes) each computed their own share from the
    /// SAME original deficit, never seeing what the other already
    /// consumed. This function replaces that per-session-independent
    /// computation with the one real shared, MUTATING ledger Section 2/3
    /// requires — kept as the caller's single source of truth for the
    /// whole week, computed ONCE in a planning pass before any Session
    /// materializes (never recomputed per-session against a stale
    /// snapshot).
    ///
    /// `sessionExercises` is every Hypertrophy-authority-eligible
    /// session's own real, already-resolved `Exercise` for the week
    /// (resolved via the exact same `SubstituteExerciseUseCase
    /// .resolvedExercise` the real materializer itself uses — this
    /// function never re-selects or second-guesses which exercise a
    /// session gets, only how many SETS of it). Sorted internally by
    /// `sessionIndex` before any ledger consumption, so the returned
    /// map depends only on the SET of (sessionIndex, exercise) pairs
    /// supplied — never on what order the caller happened to build that
    /// array in (Section 23's order-independence requirement).
    ///
    /// Round-robin, one physical set at a time, in `sessionIndex` order
    /// (Section 8's "avoid concentrating the whole week's volume in one
    /// session," Section 11's "balanced exposure"): each granted set
    /// atomically subtracts its exercise's COMPLETE direct-contribution
    /// vector (every tracked group in `exercise.primaryTargets`, all at
    /// once) from the ONE shared ledger — never a separate physical set
    /// per group the exercise happens to touch (Section 4/12's explicit
    /// "one physical compound set may satisfy multiple muscle-group
    /// deficits... do not create one physical set per muscle ledger
    /// entry"). A session is skipped once its own exercise's most
    /// under-served tracked group drops below 1.0 remaining credit —
    /// Section 13's exact "a remaining deficit < 1.0 set credit may be
    /// considered satisfied" rule, never rounded up into an extra set.
    /// The loop terminates once no eligible session can usefully absorb
    /// another set (every relevant group already <1.0) — the allocator
    /// never creates volume after the shared ledger is satisfied
    /// (Section 7's own termination requirement).
    /// MUSCLE + 5FF FINAL CLOSURE, Section 1 (project-owner decision):
    /// a real, previously-undiscovered gap in the "cross-pattern double-
    /// count defect" fix above — a session's main body may legitimately
    /// carry MORE THAN ONE Hypertrophy-authority role (PRIMARY +
    /// COMPLEMENTARY loaded pattern; `materializeStrengthBlock` already
    /// applies ONE uniform set count across all of them). The caller
    /// previously supplied only ONE representative exercise per session
    /// index, so a session's own COMPLEMENTARY pattern's muscle groups
    /// were never checked/decremented against the ledger at all — once
    /// real per-session pattern diversity was introduced, this let the
    /// week's total credited sets for a muscle group exceed the shared
    /// fallback target (confirmed empirically:
    /// `testMuscleVolumeJourneyC_...` regressed from 10 to 20 sets for a
    /// single tracked group). Fixed by tracking the full set of
    /// Hypertrophy-authority exercises PER SESSION (not one
    /// representative) and treating a session's own granted set as
    /// consuming the UNION of every one of its exercises' direct target
    /// groups together — matching the real physical fact that the
    /// materializer doses every role in a session by the SAME set count,
    /// so one "set" of a session's main body really does consume all of
    /// it at once.
    /// MUSCLE + 5FF FINAL CLOSURE, Section 1 (project-owner decision): a
    /// further real gap the responsibility-reassignment exercise-
    /// diversity fix exposed — the round-robin below continues crediting
    /// a session as long as the WORST (max) deficit among the groups its
    /// exercises touch is still unmet. A session whose main body touches
    /// a tracked group NO OTHER eligible session this week touches (an
    /// "exclusive" group — confirmed via real production evidence: a
    /// squat+press session whose press-role resolves to the week's only
    /// chest-targeting exercise) could ride that one group's own full
    /// weekly deficit all the way to `weeklyFallbackSetCreditTarget`,
    /// silently carrying its SHARED group (e.g. quadriceps) along for
    /// the ride each round. This was invisible while every such
    /// exclusive-group session in a week happened to share the SAME
    /// exclusive group by coincidence (two squat+press sessions both
    /// keyed on the same single catalog chest exercise moved in
    /// lockstep, correctly bounding their combined share) — confirmed
    /// empirically to break (`testMuscleVolumeJourneyC` regressing from
    /// a correctly-capped 10 to 25) the moment real per-session exercise
    /// diversity let two sessions land on two DIFFERENT exclusive
    /// groups instead. Section 8's own "frequency redistributes, never
    /// multiplies" already gives the fix: bound EVERY session's total
    /// accumulated credit — regardless of which specific group is
    /// driving its continued eligibility — by its fair, deterministic
    /// share of the fallback target among however many Hypertrophy-
    /// authority-eligible sessions genuinely exist this week, reusing
    /// this file's own pre-existing `distributedSetCount` (previously
    /// defined but never wired into this function) rather than inventing
    /// a new numeric threshold. `directGroups`'s union-of-exercises
    /// per-set decrement (Section 12: one physical set may satisfy
    /// multiple deficits at once) is otherwise unchanged.
    static func allocateSets(
        sessionExercises: [(sessionIndex: Int, exercises: [Exercise])],
        remainingRequirement: [MuscleGroup: Double]
    ) -> [Int: Int] {
        let sorted = sessionExercises.sorted { $0.sessionIndex < $1.sessionIndex }
        var ledger = remainingRequirement
        var allocated: [Int: Int] = [:]
        for pair in sorted { allocated[pair.sessionIndex] = 0 }
        guard !sorted.isEmpty else { return allocated }

        let perSessionCap: [Int: Int] = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { position, pair in
            (pair.sessionIndex, distributedSetCount(
                totalNeededSets: Int(weeklyFallbackSetCreditTarget),
                sessionIndexAmongEligible: position,
                eligibleSessionCount: sorted.count
            ))
        })

        var madeProgressThisPass = true
        while madeProgressThisPass {
            madeProgressThisPass = false
            for pair in sorted {
                guard (allocated[pair.sessionIndex] ?? 0) < (perSessionCap[pair.sessionIndex] ?? 0) else { continue }
                let directGroups = Set(pair.exercises.flatMap(\.primaryTargets)).intersection(trackedGroups)
                guard !directGroups.isEmpty else { continue }
                let maxDeficit = directGroups.map { ledger[$0] ?? 0 }.max() ?? 0
                guard maxDeficit >= 1.0 else { continue }
                for group in directGroups {
                    ledger[group] = max(0, (ledger[group] ?? 0) - 1.0)
                }
                allocated[pair.sessionIndex, default: 0] += 1
                madeProgressThisPass = true
            }
        }
        return allocated
    }
}
