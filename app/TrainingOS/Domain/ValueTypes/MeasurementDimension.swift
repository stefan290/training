import Foundation

/// Dogfood Round 2 Continuation (Finding J): the real, composable capability
/// signal `Exercise` was missing — "dimensions this exercise supports," NOT
/// "dimensions every prescription for this exercise must contain" (that
/// remains `SetPrescription`'s own job, via which optional target fields it
/// actually populates). A plain, non-payload enum — this codebase has a
/// real, previously-diagnosed SwiftData decode failure from storing an
/// enum-with-associated-values directly with heterogeneous sibling rows
/// (`PrescriptionTemplate`'s own "Rule storage" doc comment); this type
/// deliberately carries no associated values, matching `MovementFunction`/
/// `MuscleGroup`'s own proven-safe shape.
enum MeasurementDimension: String, Codable, CaseIterable {
    case reps
    case load
    case distance
    case duration
    /// FUNCTIONAL FITNESS PROGRAMMING AUTHORITY V2, Section 10: `ScoreType`
    /// already supports `.calories` as a workout-level score, but no
    /// per-movement target dimension existed for it — an Assault Bike/
    /// Row/SkiErg calorie target is a real, distinct measured quantity
    /// from `.distance` (both are legitimate ways to dose the same
    /// machine; they are never interchangeable or inferred from one
    /// another).
    case calories
}
