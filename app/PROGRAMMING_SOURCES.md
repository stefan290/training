# Programming Sources — Stage 3B

Every concept used in Stage 3B's modality-architecture validation is
classified as one of three things. This classification is the single
most important discipline in this document set — it must never be
collapsed, and a TRAININGOS-DESIGNED rule must never be presented as if a
study or an official program specified it.

- **SOURCE-DERIVED** — directly stated by the cited external source
  (a study's methods, an official program's published structure).
- **TRAININGOS INTERPRETATION** — our structured reading of source
  material that doesn't state something in exactly our domain-model terms,
  but is a reasonable, defensible restatement of what the source actually
  says (e.g. turning "3 runs a week, with a day of rest in between" into a
  `sessionsPerWeek: 3` parameter).
- **TRAININGOS-DESIGNED** — an architecture or product rule we introduce
  ourselves, with no source claim behind it at all.

**Research method note, stated once here rather than repeated five
times:** this environment's web-fetch tool could not directly load
nhs.uk, britishcycling.org.uk, pubmed.ncbi.nlm.nih.gov, or crossfit.com
(egress-blocked). Every fact below was obtained via search-engine result
snippets that quote or closely paraphrase those pages, cross-checked
against multiple independent snippets where possible, not by directly
reading the primary page myself. This is stated plainly on each source
below and should be re-verified against the live source before any of
these numbers are hardcoded into a shipped fixture (the same discipline
Stage 3A applied to spreadsheet cell citations, applied here to web
citations).

---

## 1. Running — NHS Couch to 5K

**Source:** NHS "Couch to 5K" plan, nhs.uk/better-health/get-active/get-running-with-couch-to-5k/ (landing and week-by-week plan pages). Verified via search-snippet extraction, not direct fetch.

| Concept | Classification | Detail |
|---|---|---|
| 9-week total duration | SOURCE-DERIVED | Stated directly ("in as little as 9 weeks"). |
| 3 sessions/week, rest day between sessions | SOURCE-DERIVED | "3 runs a week, with a day of rest in between" — stated directly. |
| Week 1 structure: 5-min warm-up walk, then alternating 60s run / 90s walk for ~20 min | SOURCE-DERIVED | From the official week-by-week plan page, via snippet extraction. |
| Week 5 structure: three *different* session shapes in one week, ending with 20 min continuous running on session 3 | SOURCE-DERIVED | Same source; this is the plan's steepest single jump and is used below as the key regression case. |
| Week 9 structure: 30 min continuous running, all 3 sessions | SOURCE-DERIVED | Same source. |
| 5-min warm-up walk / 5-min cool-down walk on every session | SOURCE-DERIVED | Stated as a structural principle on every session. |
| No numeric pace/HR target — "go at a pace that feels comfortable for you" | SOURCE-DERIVED | Direct phrasing from official app-store/plan descriptions. |
| "Talk test" / conversational-pace framing | TRAININGOS INTERPRETATION | This specific framing appears in secondary running-coach sources describing C25K, not confirmed as literal NHS wording. Used here only as *interpretation* of what "comfortable pace" implies for an RPE-style prescription, not presented as NHS's own words. |
| Rest days exist specifically because running is high-impact and needs recovery | TRAININGOS INTERPRETATION | Plausible and consistent with general injury-prevention practice, but the *causal explanation* is not confirmed as NHS's own stated rationale in the snippets found — the *fact* of the rest day is SOURCE-DERIVED, the *reason* given here is our interpretation. |
| Modeling the run/walk structure as an `IntervalProgrammingSystem` configuration with `recoveryIntensity = walking` rather than a bespoke "run/walk" mechanic | TRAININGOS-DESIGNED | The NHS plan itself has no notion of "interval programming system" — this is our architectural choice, made in `ENDURANCE_PROGRAMMING_MODEL.md`, not a claim about how NHS thinks about the plan. |
| No separate `RunningProgrammingSystem` engine — Running as a modality parameter cutting across `SteadyStateProgrammingSystem`/`IntervalProgrammingSystem` | TRAININGOS-DESIGNED | An architecture decision, fully ours; NHS's plan says nothing about engine architecture. |

## 2. Aerobic/Cycling — British Cycling structured training plans

**Source:** britishcycling.org.uk/knowledge/training-plans and related supporting-document articles (RPE scale, power/HR intensity guidance, winter-training intensity). Verified via search-snippet extraction, not direct fetch — treat exact wording as approximate.

| Concept | Classification | Detail |
|---|---|---|
| "Build 1 / Build 2 / Build 3" progressive weeks, then a Recovery/Post-Event week — a 3:1 build:recovery cadence | SOURCE-DERIVED | Stated terminology, per snippet extraction. |
| "Always return to Build 1" after a recovery week, rather than continuing to escalate indefinitely | SOURCE-DERIVED | Stated directly, per snippet extraction. |
| Numbered training zones (Zone 1–5), usable interchangeably for heart rate or power depending on what the athlete has tested | SOURCE-DERIVED | Stated directly; "Zone 3 (Tempo)," "Zone 4 (Threshold)" naming also appears directly. |
| A full 5-zone name table (Recovery/Endurance/Tempo/Threshold/VO2max) mapped to all 5 numbers | TRAININGOS INTERPRETATION | Zone 3=Tempo and Zone 4=Threshold are directly sourced; the *complete* 5-zone name table is assembled from third-party synthesis of British Cycling's approach, not one single direct quote enumerating every zone name. Treated as our structured reading, not a verbatim BC table. |
| FTP testing (30-min test, average power of final 20 min minus 5%) and threshold-HR-over-max-HR testing preference | SOURCE-DERIVED | Stated directly in BC's supporting documents. |
| RPE as an explicit fallback intensity measure for athletes without a tested FTP/threshold HR | SOURCE-DERIVED | Stated directly (dedicated RPE supporting-document article). |
| Named structured workouts: "Sweet Spot" intervals (e.g. 2×20 min, mid-Zone-3-to-mid-Zone-4), pyramid intervals, ramped VO2 intervals, endurance/steady weekend rides | SOURCE-DERIVED | Named directly in BC's own articles. |
| Weekly volume ranges (<4h Recovery week up to ~10h peak Build week) | SOURCE-DERIVED | Stated directly, though an exact week-by-week percentage progression formula was not found and is **not claimed here**. |
| Modeling "Build weeks" as a `recoveryWeekStrategy` parameter on a generic system rather than a bespoke cycling-only mechanic | TRAININGOS-DESIGNED | BC's plans don't describe their own software architecture; this generalization (reusable by any `SteadyStateProgrammingSystem`/`IntervalProgrammingSystem` instance, any modality) is ours. |
| "Aerobic Base" as a stimulus separable from the Bike/Row/Ski/Run modality executing it | TRAININGOS-DESIGNED | British Cycling's material is naturally cycling-only; the *generalization* to a modality-independent stimulus is our own architectural proposal, validated (not sourced) in `ENDURANCE_PROGRAMMING_MODEL.md` §2. |

## 3. VO2max — Helgerud et al. 2007

**Source:** Helgerud J, Høydal K, Wang E, et al. "Aerobic High-Intensity Intervals Improve V̇O2max More Than Moderate Training." *Medicine & Science in Sports & Exercise*, 2007;39(4):665–671. PubMed 17414804, DOI 10.1249/mss.0b013e3180304570. Verified via cross-checked secondary sources quoting the abstract, not a direct PubMed fetch.

| Concept | Classification | Detail |
|---|---|---|
| 4×4 protocol: 4 intervals of 4 min running at 90–95% HRmax, each followed by 3 min active recovery at 70% HRmax | SOURCE-DERIVED | The paper's own stated methods figures, corroborated across multiple independent secondary citations. |
| Modality: running (treadmill, ~5.3% incline) | SOURCE-DERIVED (incline detail from a secondary source describing the methods) | |
| 3 sessions/week for 8 weeks | SOURCE-DERIVED (secondary-sourced, not personally read on PubMed) | Reported consistently and specifically across sources; flagged as one level removed from primary-source verification. |
| 4 comparison groups: long slow distance (70% HRmax), lactate threshold (85% HRmax), 15/15 intervals (90–95%/70% HRmax, 15s/15s), and 4×4 | SOURCE-DERIVED | Corrects an initial assumption of a "4×4 vs. 4×8" comparison — no 4×8 arm exists in this study. |
| Using this single protocol as *one* reference fixture for `IntervalProgrammingSystem`, not as proof that 4×4 is the only valid VO2 method | TRAININGOS-DESIGNED | Explicit instruction from the brief; this document and `ENDURANCE_PROGRAMMING_MODEL.md` treat 4×4 as one named parameter preset, never as an exhaustive claim about VO2 programming. |
| No separate `VO2ProgrammingSystem` class — VO2 work as a preset of the generic `IntervalProgrammingSystem` | TRAININGOS-DESIGNED | An architecture decision; the study says nothing about software architecture. |

## 4. Functional Fitness — CrossFit's own programming methodology

**Source:** CrossFit Training's "Programming Basics Part 1" and "Part 2" (crossfit.com/pro-coach/programming-basics-part-1/-2); Glassman, "A Theoretical Template for CrossFit's Programming" (2003, library.crossfit.com/free/pdf/06_03_CF_Template.pdf); crossfit.com/essentials pages on movement modalities, formats, hitting the stimulus, and variance. Verified via search-snippet extraction, not direct fetch.

| Concept | Classification | Detail |
|---|---|---|
| A sequence of: set the goal/stimulus → program the workout (movements, load, duration domain, format) → analyze the programmed workout against the goal and adjust | SOURCE-DERIVED (paraphrased structure) | This is a paraphrase of Programming Basics Part 1's described structure, not a verbatim numbered "Step 1/2/3" list — CrossFit's own enumeration wording was not directly confirmed. |
| Extending single-workout stimulus design to 1–2 week block-level planning, checking for prior gaps/repetition before programming forward (Part 2) | SOURCE-DERIVED (paraphrased) | |
| Three modalities — metabolic conditioning ("cardio"/monostructural), gymnastics (bodyweight/calisthenics, body control), weightlifting (Olympic lifts + powerlifting basics) | SOURCE-DERIVED | Near-verbatim from the Theoretical Template and the movement-modalities essentials page. |
| The Theoretical Template's original 3-day-on/1-off cadence: day 1 single element, day 2 couplet, day 3 triplet | SOURCE-DERIVED | Stated directly in the 2003 template. |
| "Randomized within some parameters" — planned/constrained variance, explicitly not unconstrained randomness | SOURCE-DERIVED | Near-direct quote from the Theoretical Template; reinforced by the separate "variance" essentials pages describing deliberate, analyzed variety rather than "throwing random activities together." |
| Format (AMRAP/EMOM/For Time/couplet/chipper/etc.) as a distinct concept from stimulus (the intended physiological effect: short-heavy-intense vs. long-moderate-light) | SOURCE-DERIVED | Explicitly distinguished across two current CrossFit essentials pages ("The Four Formats," "Hitting the Stimulus"). |
| Duration-domain scaling rule of thumb (slowest athlete's time ≤ ~2× fastest) as a tool for keeping scaled results matched to intended stimulus | SOURCE-DERIVED (paraphrased) | |
| Do not build a random WOD generator | TRAININGOS-DESIGNED (explicit product constraint, consistent with the source's own "not randomness" framing) | This is our own product decision, though it happens to align with — not contradict — CrossFit's own stated philosophy. |
| Representing "stimulus" as a structured value object (`targetDurationDomain`, `intensity`, `loading`, `movementFunctions`, `movementModalityMix`, `skillDemand`, `localFatigue`, `systemicDemand`, `scoreType`) as distinct fields, separate from `format` | TRAININGOS INTERPRETATION | CrossFit's source material draws the *conceptual* line between stimulus and format; the specific *field list* is our structured translation of that concept into typed domain values, not a table CrossFit itself publishes. |
| `FunctionalFitnessProgrammingSystem`'s five-stage pipeline (Stimulus → Format → Movement slots → Concrete exercise selection → Stimulus validation) | TRAININGOS INTERPRETATION | A direct structural mapping of the source's own sequence (goal → program → analyze) onto our `ProgrammingSystem` vocabulary — an interpretation, not an invention, but expressed in our terms. |
| Rolling exposure metadata (duration/loading/modality/skill-demand history a future generator could query) | TRAININGOS-DESIGNED | CrossFit's variance philosophy motivates this, but the specific metadata schema is ours; CrossFit publishes no such schema. |

## 5. Concurrent/Hybrid — interference literature

**Sources:** Wilson JM, Marín PJ, Rhea MR, et al. "Concurrent Training: A Meta-Analysis Examining Interference of Aerobic and Resistance Exercise." *J Strength Cond Res*, 2012;26(8):2293–2307. PubMed 22002517. Schumann M, Feuerbacher JF, Sünkeler M, et al. "Compatibility of Concurrent Aerobic and Strength Training for Skeletal Muscle Size and Function: An Updated Systematic Review and Meta-Analysis." *Sports Med*, 2022. Lundberg TR, Feuerbacher JF, Sünkeler M, Schumann M, 2022 (fiber-level meta-analysis, PMC9474354). Eddens L, van Someren K, Howatson G, 2018 (intra-session sequencing systematic review, PMC5752732). Verified via search-snippet extraction, not direct fetch.

| Concept | Classification | Detail |
|---|---|---|
| Wilson 2012: concurrent training reduced hypertrophy, maximal strength, and power effect sizes vs. resistance-only, with power showing the largest relative reduction | SOURCE-DERIVED | Stated effect-size figures from the paper's own pooled analysis, per corroborated secondary sources. |
| Wilson 2012: running (but not cycling) produced significant hypertrophy/strength decrements | SOURCE-DERIVED | |
| Wilson 2012: endurance frequency and duration negatively correlated with strength/hypertrophy/power gains | SOURCE-DERIVED | |
| Wilson 2012's own framing: interference is *conditional* on modality/frequency/duration, not universal | SOURCE-DERIVED | The paper's stated purpose was to identify *which components* are detrimental, implying not all combinations are. |
| Schumann 2022 (43 studies): no meaningful group difference vs. resistance-only for maximal strength or hypertrophy, independent of modality/frequency/training status/age; explosive/power strength attenuated, especially with same-session stacking | SOURCE-DERIVED | A materially more nuanced, more recent finding than Wilson 2012's whole-outcome reductions. |
| Lundberg 2022: fiber-level (esp. Type I) hypertrophy interference detectable, more pronounced with running than cycling, even where whole-muscle meta-analysis found none | SOURCE-DERIVED | Shows the literature is not fully settled and depends on measurement level. |
| Eddens 2018: intra-session sequencing (resistance-before-endurance vs. reverse) has a favorable but inconsistent effect on lower-body dynamic strength specifically; flagged by the review's own authors as open/context-dependent | SOURCE-DERIVED | |
| "≥6 hours between sessions to let signaling resolve" | TRAININGOS INTERPRETATION, low-confidence | Found only in broader secondary search results, not directly verified against either focal paper — carried here explicitly labeled as a lower-confidence, not-directly-verified claim, per the research agent's own flag. Not to be hardcoded as a rule without further verification. |
| Factors a scheduler should model: endurance modality, frequency, session duration, same-session sequencing/stacking, inter-session recovery time, which adaptation is prioritized, training status | TRAININGOS INTERPRETATION | The literature identifies these as *moderators* worth modeling; the decision to expose them as literal `ConcurrentScheduler` input fields (`CONCURRENT_SCHEDULER_MODEL.md` §2) is our structured translation of that finding into architecture, not a claim the papers specify software inputs. |
| `ConcurrentScheduler` does not use a fixed rule like "cardio kills gains" | TRAININGOS-DESIGNED (directly motivated by the source's own conditional framing) | The decision to avoid a single universal rule is explicitly supported by both papers' own context-dependent conclusions — this is the one TRAININGOS-DESIGNED item in this document that a source most directly argues *for*, even though the specific scheduler mechanism is still ours. |
| Any specific numeric scheduling rule (e.g. "always separate sessions by exactly N hours," "always sequence strength before cardio") | Explicitly **not** produced by this analysis | Per the brief's own instruction: do not turn individual study findings into rigid universal scheduling laws. `CONCURRENT_SCHEDULER_MODEL.md` models these as *inputs the scheduler weighs*, not fixed rules it obeys unconditionally. |
