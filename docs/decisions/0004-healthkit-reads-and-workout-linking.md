# ADR-0004 — HealthKit: narrow reads, and link the Watch workout instead of starting one

*Status: **proposed** — 2026-11-15, ratified by Jon merging the plan PR that adds it.*

Summary: The app reads walking workouts, strength workouts, their distance, and body mass from Health,
on demand, with no local copy. It doesn't start workouts. Jon keeps starting strength workouts on the
Watch, and the app links the resulting Health workout to the completion, offering to complete the
next workout when one appears.

## Context

Jon starts a strength workout on the Watch today to record it in Apple's world, and asked whether
the app could start it. As far as we know, no public API lets an app start Apple's Workout app.
The only way is a Watch app of our own (HealthKit can launch it with a workout configuration),
which reverses a non-goal and would be the biggest piece of the app. Jon chose linking (2026-11-15).

## Decision

### D1 — Permissions

- **Read:** workouts, walking + running distance, body mass.
- **Write:** body mass only, for the scale (ADR-0005), requested when the scale arrives, not before.
- Nothing else: no sleep, HRV, VO₂ max, energy, or rings.

### D2 — Queries

- **Walks:** workouts of activity type `.walking` in the window. Distance comes from each workout's
  own statistics for walking + running distance, not from a separate distance-sample query, so
  nothing is counted twice and incidental daily walking stays out. Whether `.hiking` counts is open.
- **Strength:** workouts of `.traditionalStrengthTraining` and `.functionalStrengthTraining`.
- **Body weight:** the latest body-mass sample, read when the screen appears. No cache.
- All of it behind a `HealthClient` dependency with preview and test values.

### D3 — Linking the Watch workout

When the app comes forward and Health has a strength workout that ended in the last 12 hours,
started after the latest completion, and isn't linked to one, the Next Workout screen offers:
"48-minute strength workout at 7:10 — mark Workout A done?" Accepting completes with completed-at
set to the workout's end and stores its UUID. Declining hides the offer for that workout. Completing
by hand stays available and never requires Health.

The Activity calendar counts a day as a strength day if it has a completion or any Health strength
workout; a day is marked once, however many it has.

*Amended 2026-11-16, while designing M2:* "started after", not "ended after". Tapping Complete by hand
during or just before ending the Watch session would otherwise leave that workout ending after the
completion, and the app would offer to mark the *following* workout done. An unlinked Health
strength workout (a class, a session off-program) now counts as a strength day too. "What have I been
doing" includes it, and the old "not both" only guarded against counting a day twice.

### D4 — Unknown access

Health never says whether read access was denied. Every Health-backed element has an empty state
that reads correctly either way ("Nothing from Health yet"), and nothing in M1's core loop depends on
Health.

### D5 — Not doing

Writing strength workouts to Health: the Watch already does that. A Watch app: revisit only if
starting the session on the Watch becomes a nuisance in practice.
