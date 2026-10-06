import Foundation

/// CONDITIONING DOSE AUTHORITY V1, Sections 10-13: the real technical-
/// movement conditioning-eligibility and repeated-dose-ceiling authority.
/// `MovementCapabilityProfile.capacityValue`/`.capacityType` (real,
/// persisted fields with zero production readers before this checkpoint)
/// become load-bearing here for the first time.
enum TechnicalCapacityDoseAuthority {
    /// Section 13: the 7 real gated movements where max-unbroken-reps (or
    /// max-reps) genuinely represents a truthful REPEATED conditioning
    /// dose. Exact canonical catalog names, confirmed directly against
    /// `ExerciseCatalog.swift`.
    static let repeatedDoseTrackedNames: Set<String> = [
        "Double-Unders", "Pull-up", "Chest-to-Bar Pull-up", "Toes-to-Bar",
        "Bar Muscle-Up", "Ring Muscle-Up", "Handstand Push-up",
    ]

    /// Section 13: the remaining gated movements this V1 authority does
    /// NOT cover — their stored `capacityType` (distance/load) does not
    /// represent a repeated conditioning dose truthfully, so "no approved
    /// conditioning dosage mapping exists" and they must never become a
    /// Conditioning dependency in V1, regardless of proficiency. A
    /// simpler valid movement must be selected instead (Section 13's own
    /// resolution).
    static let conditioningExcludedNames: Set<String> = [
        "Handstand Walk", "Rope Climb", "Clean", "Jerk", "Snatch",
    ]

    /// Section 11: the exact locked V1 repeated-dose ceiling table — a
    /// MAXIMUM, never a mandatory dose (Section 17). `nil` means capacity
    /// 1-5: not Conditioning-eligible at all.
    static func maxRepeatedDose(forCapacity capacityValue: Double) -> Int? {
        switch capacityValue {
        case ..<6: return nil
        case 6..<10: return 3
        case 10..<15: return 5
        case 15..<25: return 8
        case 25..<40: return 12
        default: return 15
        }
    }

    /// MUSCLE VERTICAL SLICE REPAIR, Section 13: this ceiling is a
    /// property of the EXERCISE + the athlete's own recorded capacity —
    /// never of which PURPOSE happened to select it. Before this
    /// checkpoint, the ceiling was only ever consulted inline at the one
    /// real Conditioning-purpose call site
    /// (`FunctionalFitnessMaterializer.materializeDynamicBlock`), so a
    /// resistance-purpose role that independently resolves to one of the
    /// same 7 gated movements (`materializeStrengthBlock`'s own
    /// `SubstituteExerciseUseCase`-resolved roles, an entirely separate
    /// resolution path from `MovementRoleExerciseSelector`) could author
    /// a literal rep target (e.g. a `.fixedReps` accessory role) that
    /// exceeds a known-real max-unbroken-rep capacity — e.g. Toes-to-Bar
    /// capacity 7 -> ceiling 3, yet an authored "3x12" accessory role
    /// would have prescribed 12 unclamped. This is the one, real, shared
    /// authority both call sites now use — a pure function of
    /// `(exercise, performanceProfile)`, with no purpose parameter at
    /// all, so there is nothing to gate: it always applies wherever a
    /// literal rep target for one of these 7 names is finalized.
    ///
    /// Returns `reps` unchanged whenever no real, usable capacity
    /// evidence exists (unclassified exercise, no recorded capability, or
    /// a non-repeated-dose capacity type/value) — this is a CLAMP, never
    /// a requirement to have capacity evidence before prescribing at all
    /// (that gating is `MovementRoleExerciseSelector.isCapabilityEligible`'s
    /// own, separate, Conditioning-purpose-specific job).
    static func clampedReps(_ reps: Int, for exercise: Exercise, performanceProfile: PerformanceProfile?) -> Int {
        guard repeatedDoseTrackedNames.contains(exercise.canonicalName),
              let capability = performanceProfile?.movementCapability(for: exercise),
              let capacityType = capability.capacityType, capacityType == .maxUnbrokenReps || capacityType == .maxReps,
              let capacityValue = capability.capacityValue,
              let ceiling = maxRepeatedDose(forCapacity: capacityValue),
              ceiling < reps
        else { return reps }
        return ceiling
    }
}
