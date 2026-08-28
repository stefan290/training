import Foundation

/// Stage 10R.5: which progression authority governs next-exposure load
/// for a `.rmBased` (recovered Family A) slot — a TrainingOS product
/// setting, never source behavior. `.source` reproduces the recovered
/// program's own fixed weekly schedule exactly, byte-for-byte, forever
/// selectable and tested (`STAGE10R5_LOAD_FIRST_PROGRESSION_OVERLAY_DESIGN.md`
/// D-10R5-1/15/16). `.loadFocused` layers `LoadFirstOverlayEngine`'s
/// Performance-Qualified Source Schedule on top, without ever mutating
/// the source's own `SetPrescription.targetWeight`.
enum ProgressionStyle: String, Codable, CaseIterable {
    case source
    case loadFocused
}
