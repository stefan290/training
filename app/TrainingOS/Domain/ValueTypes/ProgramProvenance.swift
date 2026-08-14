import Foundation

/// Which concrete `ProgrammingSystem` generated a `ProgramDefinition`.
/// Additive: a new system gets a new case, never a repurposed one, since a
/// stored `ProgramDefinition` references its originating system by this
/// tag permanently.
enum ProgrammingSystemKind: String, Codable, CaseIterable {
    case hypertrophy
    case powerlifting
    case steadyState
    case interval
    case functionalFitness
}

/// Where a `ProgramDefinition`'s generated numbers trace back to — mirrors
/// `PROGRAM_REGRESSION_TEST_PLAN.md`'s sourced-vs-constructed labeling
/// convention, carried onto the persisted model itself (not just test
/// fixtures) so a real imported program and a demo/constructed one are
/// never confused in the running app. `.sourced` cites the exact
/// spreadsheet cell per `PROGRAM_LOGIC_SPEC.md`'s own citation format;
/// `.constructed` is what every current V1 built-in uses, since no real
/// source workbook exists in this repository — only the already-analyzed
/// rules/numbers documented in `PROGRAM_LOGIC_SPEC.md` survive.
enum ProgramProvenance: Codable, Equatable {
    case sourced(file: String, sheet: String, cell: String)
    case constructed(reason: String)
}
