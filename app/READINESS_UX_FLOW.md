# Readiness UX Flow (Stage 8A design — not yet implemented)

The actual screen-by-screen flow, timed against the ~10-20 second target
for the common case.

## 1. Fast path — everything is fine (~10-15 seconds, 4 taps)

1. User taps **Start** on today's session.
2. One screen, three single-tap controls, no scrolling, no free text:
   *Sleep* (poor/ok/good) · *Energy* (low/normal/high) · *Overall
   recovery* (fresh/normal/sore) — this is Tier 0, and "overall recovery"
   here means general whole-body training soreness only; it carries no
   pain or stiffness information (`READINESS_MODEL.md` §1/§2).
3. One more single tap — the Tier 0.5 gateway: **"Pain or stiffness
   today?"** Yes / No.
4. All three Tier-0 answers "ok/normal/fresh or better" and the gateway
   answered **No** → **no follow-up screen, no recommendation screen** —
   straight into the session exactly as it starts today. This is the
   deliberate fast path (4 taps total); it must never grow a
   confirmation step "just in case."

## 2. Targeted follow-up — something is off (~+10-15 seconds, only when triggered)

Two independent triggers, each opening its own follow-up, never merged
into one control:

- **"Overall recovery" = sore** → a compact list of **only the muscle
  groups today's own materialized session actually trains** (not a
  full-body picker), multi-select, one tap per area, or "not sure/skip."
  This is the **local soreness** follow-up — it never needs the Tier 0.5
  gateway to be reached, and reaching it never implies pain or
  stiffness.
- **Tier 0.5 gateway answered Yes** → a follow-up screen asking **which
  kind** (pain/injury and/or stiffness/mobility limitation — not
  mutually exclusive, a user can select both), then, for whichever
  kind(s) are chosen, the same compact session-relevant body-area list.
  Selecting "pain" writes to `reportedPain`; selecting "stiffness"
  writes to `reportedStiffness` — two separate fields, never inferred
  from each other (D2, `READINESS_MODEL.md` §1/§4). Visually distinct
  from the soreness list (different heading/color, never the same
  control), reinforcing the soreness/pain/stiffness distinction at the
  interaction level, not just the data level.

No severity slider, no free-text description — a location (and, for the
gateway path, a kind) is enough input for the decision model to act on;
anything more detailed is explicitly out of scope (no medical
questionnaire).

## 3. Recommendation screen — only when there's something to say

Shown only if `EvaluateReadinessAdaptationUseCase` produced a non-empty
proposal. One short, plain-language explanation per affected item,
matching the brief's own examples exactly in tone:

> "Energy is low today. Keep the exercise but reduce the starting load
> by 5%."
>
> "Your shoulder is bothering you. Replace Barbell Overhead Press with a
> compatible shoulder-friendly alternative."
>
> "Recovery looks poor today. Reduce this exercise from 4 sets to 3."

Each item always shows, side by side: the **original** prescription and
the **proposed** one — never just the new number with the old one
silently gone. Per item, the user can:
- **Accept** the proposed change,
- **Keep original** (explicitly reject, session proceeds unadapted for
  that item),
- **Choose another valid alternative**, only where one genuinely exists
  (e.g. a different eligible substitute exercise) — never a free-form
  edit; the same `SubstitutionValidator`/eligibility rules the rest of
  the app already enforces apply here too, no new bypass.

Nothing is applied until the user finishes reviewing every item — no
partial auto-apply while still on this screen.

## 4. Skip check-in entirely

A visible, low-friction "Skip check-in" action is always available from
the first screen — readiness is optional end to end (design question
13). Skipping records no `ReadinessCheckIn` (or one with every field
`nil` — see `READINESS_MODEL.md` §5) and proceeds directly to the
original, unadapted prescription, identically to how a session starts
today.

## 5. What must never happen

- No adaptation is ever applied silently — every meaningfully different
  outcome is shown, explained, and requires an explicit accept.
- A high/positive readiness report never itself increases prescribed
  demand (adds a set, raises load beyond what was already programmed) —
  see `STAGE8A_DECISION_MEMO.md` item 10. "I feel great" can, at most,
  affirm the existing prescription (Level 1) — it is never itself a
  justification for Level 2+ in the *upward* direction.
- The recommendation screen never blocks indefinitely — "keep original"
  is always one tap away from starting the session exactly as
  originally prescribed.
