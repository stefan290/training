import Foundation

/// Stage 10R.1 Slice 1A: canonical identity for the source workbooks'
/// shared exercise/category database, recovered directly from the real
/// RP Excel workbooks (`SOURCE_PROGRAM_MANIFEST.md` §5) — confirmed
/// byte-identical across all 11 Family A ("General Hypertrophy") workbooks.
/// This is the authority for "which category is this slot," never
/// TrainingOS-invented content.
///
/// Only the cases actually needed for the 3-Day Full Body workbook's
/// Mesocycle 1 are defined here (13 of the full ~22-category source
/// database) — deliberately scoped, per Decision 4, to "prove the
/// architecture with one real mesocycle before expanding it." Adding the
/// remaining categories for the other 5 shipped Hypertrophy configurations
/// (Slice 2) is a pure, low-risk extension of this same enum, not a
/// redesign.
enum SourceHypertrophyCategory: String, Codable, CaseIterable {
    case horizontalPush
    case inclinePush
    case inclinePushOrFrontDelts
    case chestIsolationOrTriceps
    case horizontalPull
    case verticalPull
    case sideDelts
    case rearOrSideDelts
    case biceps
    case quads
    case glutes
    case hamstringsHipHinge
    case hamstringsIsolation
}

extension SourceHypertrophyCategory {
    /// **Decision 3 (category normalization).** Every literal display
    /// label observed so far across the recovered workbooks for this
    /// canonical category, keyed to the canonical case — preserves the
    /// source-label -> canonical-category audit trail so spelling/
    /// pluralization variance in the source data (e.g. "Rear or Side
    /// Delts" vs. "Rear Delts or Side Delts", both confirmed in real
    /// workbooks — `SOURCE_PROGRAM_MANIFEST.md` §5) never creates a
    /// duplicate domain concept. Extend this table, never add a second
    /// enum case, when a new label variant for an already-known category
    /// turns up in a future workbook.
    static let labelAliases: [String: SourceHypertrophyCategory] = [
        "Horizontal Push": .horizontalPush,
        "Incline Push": .inclinePush,
        "Incline Push or Front Delts": .inclinePushOrFrontDelts,
        "Chest Isolation or Triceps": .chestIsolationOrTriceps,
        "Horizontal Pull": .horizontalPull,
        "Vertical Pull": .verticalPull,
        "Side Delts": .sideDelts,
        "Rear or Side Delts": .rearOrSideDelts,
        "Rear Delts or Side Delts": .rearOrSideDelts,
        "Biceps": .biceps,
        "Quads": .quads,
        "Glutes": .glutes,
        "Hamstrings Hip Hinge": .hamstringsHipHinge,
        "Hamstrings Isolation": .hamstringsIsolation,
    ]

    /// The primary/most common label for this category, used when no
    /// specific source-file label needs preserving (e.g. display fallback).
    var primarySourceLabel: String {
        switch self {
        case .horizontalPush: return "Horizontal Push"
        case .inclinePush: return "Incline Push"
        case .inclinePushOrFrontDelts: return "Incline Push or Front Delts"
        case .chestIsolationOrTriceps: return "Chest Isolation or Triceps"
        case .horizontalPull: return "Horizontal Pull"
        case .verticalPull: return "Vertical Pull"
        case .sideDelts: return "Side Delts"
        case .rearOrSideDelts: return "Rear or Side Delts"
        case .biceps: return "Biceps"
        case .quads: return "Quads"
        case .glutes: return "Glutes"
        case .hamstringsHipHinge: return "Hamstrings Hip Hinge"
        case .hamstringsIsolation: return "Hamstrings Isolation"
        }
    }

    /// The real, recovered exercise names the source workbooks' dropdown
    /// permits for this category (`SOURCE_PROGRAM_MANIFEST.md` §5,
    /// `extract_tables.py` output) — the full set, for audit/testing.
    /// TrainingOS's currently-cataloged resolution (§ `HypertrophyProgramGenerator
    /// .sourceApprovedResolution`) may use only a subset of these; this
    /// list is never narrowed to match the catalog — the catalog is what
    /// should eventually grow to match this, not the reverse.
    var sourceApprovedExerciseNames: [String] {
        switch self {
        case .horizontalPush:
            return ["Medium Grip Bench Press", "Wide Grip Bench Press", "Flat Dumbbell Bench Press", "Close Grip Bench Press", "Flat Machine Bench Press", "Pushup", "Close Grip Pushup"]
        case .inclinePush:
            return ["Incline Medium Grip Bench Press", "Incline Wide Grip Bench Press", "Low Incline Dumbbell Press", "Incline Dumbbell Press", "Incline Close Grip Bench Press", "Incline Machine Bench Press"]
        case .inclinePushOrFrontDelts:
            return SourceHypertrophyCategory.inclinePush.sourceApprovedExerciseNames + [
                "Standing Barbell Shoulder Press", "Seated Barbell Shoulder Press", "Seated Dumbbell Shoulder Press",
                "High Incline Dumbbell Press", "Shoulder Press Machine", "Standing Dumbbell Shoulder Press",
            ]
        case .chestIsolationOrTriceps:
            return [
                "Flat Dumbbell Flye", "Skullcrusher", "Incline Dumbbell Flye", "EZ Bar Overhead Tricep Extension",
                "Cable Flye", "JM Press", "High Cable Flye", "Barbell Overhead Tricep Extension", "Machine Chest Flye",
                "Dips", "Cable Incline Flye", "Seated EZ Bar Overhead Tricep Extension", "Pec Dec Flye", "Assisted Dips",
                "Seated Barbell Overhead Tricep Extension", "Dumbbell Skullcrusher", "Cable Overhead Tricep Extension",
                "Cable Tricep Pushdown", "Cable Rope Pushdown", "Bar Skull",
            ]
        case .horizontalPull:
            return ["Barbell Bent Over Row", "Underhand EZ Bar Row", "Row to Chest", "1-Arm Dumbbell Row", "Chest Supported Row", "Row Machine", "2-Arm Dumbbell Row", "Cable Row"]
        case .verticalPull:
            return ["Overhand Pullup", "Parallel Pullup", "Underhand Pullup", "Wide Grip Pullup", "Assisted Overhand Pullup", "Assisted Parallel Pullup", "Assisted Underhand Pullup", "Normal Grip Pulldown", "Parallel Pulldown", "Underhand Pulldown", "Wide-Grip Pulldown", "Narrow Grip Pulldown"]
        case .sideDelts:
            return ["Barbell Upright Row", "Dumbbell Upright Row", "Cable Upright Row", "Dumbbell Side Lateral Raise", "Thumbs Down Lateral Raise"]
        case .rearOrSideDelts:
            return ["Barbell Facepull", "Dumbbell Facepull", "Cable Facepull", "Dumbbell Rear Lateral Raise"] + SourceHypertrophyCategory.sideDelts.sourceApprovedExerciseNames
        case .biceps:
            return ["Barbell Curl", "EZ Curl", "Close Grip Barbell Curl", "2-Arm Dumbbell Curl", "Cable Curl", "Incline Dumbbell Curl", "Dumbbell Twist Curl", "Hammer Curl", "Dumbbell Spider Curl", "Alternating Dumbbell Curl", "Cable Rope Twist Curl"]
        case .quads:
            return ["High Bar Squat", "Close Stance Feet Forward Squats", "Machine Feet Forward Squat", "Leg Press", "Hack Squat", "Front Squat", "Front Squat (Alternate Grip)"]
        case .glutes:
            return ["Barbell Walking Lunge", "Dumbbell Walking Lunge", "Sumo Squat", "Deficit Deadlift", "25's Deadlift", "Sumo Deadlift", "Deadlift", "Hex Bar Deadlift"]
        case .hamstringsHipHinge:
            return ["Stiff-Legged Deadlift", "Low Bar Good Morning", "High Bar Good Morning", "45 Degree Back Raise"]
        case .hamstringsIsolation:
            return ["Lying Leg Curl", "Seated Leg Curl", "Single-Leg Leg Curl"]
        }
    }

    /// The real muscle-group target this category trains, per its source
    /// intent — reused unchanged from `MuscleGroup`; never a new tag
    /// invented for this pass.
    var allowedTargets: [MuscleGroup] {
        switch self {
        case .horizontalPush, .inclinePush: return [.chest]
        case .inclinePushOrFrontDelts: return [.shoulders]
        case .chestIsolationOrTriceps: return [.chest, .triceps]
        case .horizontalPull, .verticalPull: return [.back]
        case .sideDelts: return [.lateralDelt]
        case .rearOrSideDelts: return [.rearDelt, .lateralDelt]
        case .biceps: return [.biceps]
        case .quads: return [.quadriceps]
        case .glutes: return [.glutes]
        case .hamstringsHipHinge: return [.hamstrings, .glutes]
        case .hamstringsIsolation: return [.hamstrings]
        }
    }

    /// The movement-intent constraint distinguishing this category from
    /// every other one it shares a target with — reused unchanged from
    /// `MovementFunction` (Stage 4E/10C1/10R1 seam, `SubstitutionValidator
    /// .isValid`'s existing "any-overlap-per-non-empty-dimension" rule).
    /// Left empty only where the target alone is already unambiguous in
    /// the current catalog, matching the discipline established in
    /// `HypertrophyProgramGenerator.movementFunctionIntent`.
    var allowedMovementFunctions: [MovementFunction] {
        switch self {
        case .horizontalPush, .inclinePush: return [.pressLoaded]
        case .inclinePushOrFrontDelts: return [.verticalPushLoaded]
        case .chestIsolationOrTriceps: return []
        case .horizontalPull: return [.horizontalPullLoaded]
        case .verticalPull: return [.verticalPullLoaded]
        case .sideDelts, .rearOrSideDelts: return []
        case .biceps: return []
        case .quads: return [.squatLoaded]
        // The real source list mixes lunge/squat-pattern and deadlift-
        // pattern movements (`SOURCE_PROGRAM_MANIFEST.md` §5) — scoped to
        // `.hingeLoaded` here because every exercise currently cataloged
        // as source-approved for this category (§ resolution table below)
        // is a deadlift variant; broadening to include the lunge/sumo-
        // squat half of the real list is a Slice-2-scale catalog addition,
        // not invented here.
        case .glutes: return [.hingeLoaded]
        case .hamstringsHipHinge: return [.hingeLoaded]
        case .hamstringsIsolation: return [.kneeFlexionLoaded]
        }
    }
}
