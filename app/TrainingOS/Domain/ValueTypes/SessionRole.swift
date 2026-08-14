import Foundation

/// Programming semantics for a Session — orthogonal to which
/// `ProgrammingSystem` produced its blocks and orthogonal to `TrainingModality`
/// (the existing UI grouping tag on `Session`). A `.tempo` running session
/// and a `.tempo`-equivalent cycling session are produced by different
/// modalities but the same *role* in a training week; this is metadata, not
/// a new core entity, per `ENDURANCE_PROGRAMMING_MODEL.md` §8's finding
/// ("session roles are programming semantics, not new core entity types").
///
/// Deliberately not overfit to running/cycling: `.strength`/`.hypertrophy`
/// cover lifting-focused sessions, `.functionalFitness` and `.skill` cover
/// non-parametric conditioning work, `.mixed` covers a Session whose blocks
/// don't share one dominant role (e.g. Strength + Metcon).
enum SessionRole: String, Codable, CaseIterable {
    case strength
    case hypertrophy
    case easy
    case recovery
    case long
    case tempo
    case threshold
    case interval
    case aerobicBase
    case functionalFitness
    case skill
    case mixed
}
