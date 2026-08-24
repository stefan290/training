import Foundation

/// Stage 10B addition: what job a `PrescriptionTemplate`'s slot performs
/// within its day's training intent — never a biomechanical claim (see
/// `STAGE10B_IMPLEMENTATION_PLAN.md` §3 for why `.compound`/`.accessory`
/// or `{primaryCompound, secondaryCompound, isolation}` were rejected in
/// favor of this 3-value, emphasis-position representation). `nil` on a
/// `PrescriptionTemplate` (every pre-Stage-10B row, including every
/// Powerlifting row and every non-3-Day-Full-Body Hypertrophy row) means
/// "no slot role assigned" — not a hidden default of any specific role.
enum SlotRole: String, Codable, CaseIterable {
    /// This day's main emphasis muscle group(s) — the existing
    /// autoregulated, RM-anchored primary numeric treatment.
    case primary
    /// This day's supporting-but-still-substantial emphasis — reuses
    /// `.primary`'s exact numeric rule (Stage 10B decision D-10B-4: no
    /// distinct "secondary" numeric shape is sourced anywhere in this
    /// codebase). The job difference from `.primary` is purely which
    /// muscle groups a slot targets and its position in the day's
    /// emphasis (ordering, coverage accounting) — never a distinct
    /// numeric treatment.
    case secondary
    /// Supplemental, isolation-style work — the existing paired/
    /// accessory numeric treatment (fixed set schedule, higher-rep,
    /// non-to-failure, deload-omitted).
    case accessory
}
