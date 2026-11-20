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

- **The review flashes "Review unavailable" after Apply** (from the review of #21). On success,
  `ProgramImportModel.applyReviewedProgram` sets `self.review = nil` in the same update that empties
  `path`. During the pop animation, the outgoing review screen redraws with no review and shows its
  placeholder. The fix is deleting that line, since a popped review is reachable only through a new
  review, which replaces it. `scripts/check-drift.sh` passed with the line deleted. It's cosmetic. It
  can ride along with Tabs and ramps Dispatch 2, which touches the Program tab.

The review gap found in #6 is M3 S1.

## Candidates (not committed)

- A widget showing the next workout.
- A body-weight chart in Activity.
- A Watch app that starts the session from the phone, only if starting it on the Watch becomes a
  nuisance (ADR-0004 D5).
