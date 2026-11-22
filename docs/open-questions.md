# Open questions & candidates

The architect's and Jon's scratch pad. **The executor never reads this file** (jon-platform ADR-0005).
Seeded 2026-11-15.

## Decisions owed by Jon

- **Does `.hiking` count as a walk?** (ADR-0004 D2.) M2 leaves it out until Jon says otherwise.
- **Scale band widths.** A starting point of ±3 lb inner, ±8 lb outer (ADR-0005 D4).
- **Which scale.** It has to meet ADR-0005 D1. Check range from where it'll sit to the mini.

## To verify

- Whether macOS 27 can write to the user's Health store (ADR-0005 Open).
- The exact HealthKit authorization set the workout-statistics distance needs (ADR-0004 D1).

## Small follow-ups

- **`testflight`'s regenerate error prints a literal `\n`.** `regenerate_project` (jon-platform
  #163) passes `"…project.yml:\n$changed"` to `die`, which prints with `%s`, so the changed files
  follow a literal `\n` instead of starting on new lines. Use `$'\n'`. A one-line ride-along for the
  next jon-platform PR that touches `scripts/testflight`.

## Candidates (not committed)

- A widget showing the next workout.
- A body-weight chart in Activity.
- A Watch app that starts the session from the phone, only if starting it on the Watch becomes a
  nuisance (ADR-0004 D5).
