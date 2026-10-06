import Foundation

/// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 5: an athlete's
/// real-world readiness to be programmed a specific movement for a
/// specific programming purpose — separate from `Exercise
/// .requiresDemonstratedCapability` (a global, non-athlete-specific flag
/// on the catalog entry itself). Three states only, per the project
/// lead's explicit instruction not to add a generic numerical "Functional
/// Fitness level":
///
/// - `.unknown`: TrainingOS has no evidence either way. Not workout-ready
///   for a gated technical movement (Section 8); may enter a skill-
///   assessment/onboarding path, never silently become high-intensity
///   work (Section 24).
/// - `.learning`: the athlete is actively developing the movement. Valid
///   for deliberate SKILL/PRACTICE assignments (Section 9); NOT workout-
///   ready for CONDITIONING/WORK_CAPACITY (Section 8).
/// - `.workoutReady`: the athlete may reliably use this movement under
///   real workout conditions, including fatigue.
///
/// Never auto-promoted merely because a movement appeared in a logged
/// result (Section 25) — promotion requires explicit athlete confirmation
/// or a future authoritative assessment rule, neither of which exists
/// yet. A plain, no-payload `String` enum, matching `MeasurementDimension`/
/// `MovementFunction`'s own proven-safe SwiftData persistence shape.
enum MovementProficiency: String, Codable, CaseIterable {
    case unknown
    case learning
    case workoutReady
}

/// Section 5: where a capability/capacity claim came from — required to
/// distinguish an athlete's own unverified self-report from something
/// TrainingOS actually observed or tested. Never used to auto-promote
/// proficiency (Section 25) — recorded strictly as provenance.
enum CapabilityEvidenceSource: String, Codable, CaseIterable {
    case selfReported
    case assessment
    case trainingResult
    case benchmark
}

/// Section 7: "capacity is movement-specific" — different movements
/// legitimately measure capacity in different units (max unbroken reps,
/// max reps, distance, load/RM), and not every movement needs the same
/// type. A plain, no-payload discriminator paired with
/// `MovementCapabilityProfile.capacityValue` (a bare `Double?`) rather
/// than an enum-with-associated-Double — this codebase has a documented,
/// previously-diagnosed SwiftData decode failure from persisting an
/// enum-with-associated-values directly (`StrengthProgressionRules`'s own
/// "Rule storage" doc comment); this type follows the same flattened
/// discriminator-plus-scalar shape used everywhere else for that reason.
enum MovementCapacityType: String, Codable, CaseIterable {
    case maxUnbrokenReps
    case maxReps
    case distanceMeters
    case loadKilograms
}
