// Reserved for external data sources (HealthKit first — handoff section 11).
//
// Nothing here yet: HealthKit is explicitly out of scope for this pass.
// When it lands, it must stay an integration, never a source of truth —
// per the handoff, no session, block or recommendation may be blocked by a
// missing Health permission, and programs/sets/reps/weight/RIR/PRs/
// progression/phases/planning stay owned by this app's own store in every
// case.
