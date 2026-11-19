# Open questions & candidates

The architect's and Jon's scratch pad. **The executor never reads this file** (jon-platform ADR-0005).
Seeded 2026-11-15.

## Decisions owed by Jon

- **Contract sets starting weights only?** ADR-0002 D2 lets a proposal set weights only for new
  exercises, so the app owns weights and ChatGPT owns structure. The alternative is approving
  "bench to 145" from a proposal, at the cost of more review surface. M3 makes this sharper: with
  `get_history`, a chat can see a stalled lift and will want to propose a weight. M3 keeps the rule.
- **Health in the chat export?** ADR-0006 D3 leaves body weight and walks out, because Health is read,
  never mirrored (ADR-0004), and an export file is a copy. A chat deliberating over the program might
  want the body-weight trend. Jon's call; adding it amends ADR-0006 D3.
- **Does `.hiking` count as a walk?** (ADR-0004 D2.) M2 leaves it out until Jon says otherwise.
- **Scale band widths.** A starting point of ±3 lb inner, ±8 lb outer (ADR-0005 D4).
- **Which scale.** It has to meet ADR-0005 D1. Check range from where it'll sit to the mini.

## To verify

- Whether macOS 27 can write to the user's Health store (ADR-0005 Open).
- The exact HealthKit authorization set the workout-statistics distance needs (ADR-0004 D1).

## Small follow-ups

None open. The review gap found in #6 is M3 S1.

## Candidates (not committed)

- A widget showing the next workout.
- A body-weight chart in Activity.
- A Watch app that starts the session from the phone, only if starting it on the Watch becomes a
  nuisance (ADR-0004 D5).
