# Milestone 2 — Health

*Status: **Designed** — 2026-11-16. Rules: jon-platform `AGENTS.md` and `docs/ios/`, and this repo's
[decisions](../decisions/). Where this doc and those conflict, stop and flag it.*

Summary: The app reads Apple Health and copies nothing from it. A strength workout from the Watch
becomes the usual way to complete the next workout, and an Activity tab answers "what have I been
doing physically lately?" from Health and the app's own history. Health is read only; the body-mass
write waits for the scale.

## The milestone in one sentence

Finish a strength workout on the Watch, open the app, accept "48-minute strength workout at 7:10 —
mark Workout A done?", and see that day marked on the Activity tab beside walks and the latest
body weight.

## Identifiers

The HealthKit capability (`com.apple.developer.healthkit`) on the existing app ID, and an
`NSHealthShareUsageDescription`. No `NSHealthUpdateUsageDescription` yet: the one write (body mass,
ADR-0005) arrives with the scale, and asks then.

## Slices

- [x] **S1 — Health access.** The HealthKit capability and usage string. A `HealthClient` dependency
  (ADR-0004 D2): request read authorization for workouts, walking + running distance, and body
  mass (D1's reads, nothing else); fetch strength workouts in a window (UUID, start, end); fetch
  walking workouts in a window (start, end, and distance from each workout's own statistics); fetch
  the latest body-mass sample (pounds, date). The interface, its preview and test values, and every
  pure function of this milestone live in Core; the HealthKit-backed live value lives in the app
  target. Ask for authorization once, when Next Workout first appears; the system shows its sheet
  only the first time. Nothing is cached or stored (ADR-0004 D2, D4).
- [x] **S2 — Link the Watch workout.** The offer of ADR-0004 D3 on Next Workout, checked whenever the
  app becomes active. A pure Core function picks the candidate: a strength workout that **started**
  after the latest completion (ADR-0004 D3, amended), ended in the last 12 hours, isn't any
  completion's `healthWorkoutID`, and wasn't declined; the most recent one wins. The offer names its
  length, its start time, and the next workout's key. **Mark done** completes through the existing
  transactional completion with `completedAt` = the workout's end and `healthWorkoutID` = its UUID
  (the column exists; no migration). **Not this one** hides the offer for that UUID, remembered on this
  device only (app storage, pruned of workouts that ended over 12 hours ago). Completing by hand
  is unchanged. No offer when there's no program or Health returns nothing.
- [ ] **S3 — Activity.** The second tab (jon-platform `ui-and-platforms.md`: tabs on iPhone), per
  PRODUCT.md § 2, read when the tab appears:
  - **Calendar:** four weeks ending with this one, weeks starting on the locale's first weekday,
    future days blank. Each day reads strength, walk, both, or neither. A strength day has a
    completion or a Health strength workout (ADR-0004 D3, amended). A walk day has a `.walking`
    workout and shows that day's walked distance in miles, one decimal. `.hiking` is out until Jon
    says otherwise.
  - **Body weight:** the latest body-mass sample in pounds, with its date.
  - **Progression:** one line of text for one exercise: its current working weight against its
    snapshot load on the latest completion at least 90 days old ("Bench press 145 lb · +15 lb since
    Aug 18"); with no completion that old, against its earliest one; with none, the weight alone. Jon
    picks the exercise from the active weighted ones, remembered on this device by key; the default
    is the first weighted exercise of the first workout. It reads `completionItems` by exercise
    (ADR-0003 D1).
  - Each Health-backed part has the empty state of ADR-0004 D4 ("Nothing from Health yet"); the
    progression line doesn't need Health.

## Dispatches

- **Dispatch 1: S1 + S2.** Access and linking share the client and the Next Workout screen. Linking is
  the daily payoff.
- **Dispatch 2: S3.**

## Done when

On Jon's iPhone: after a Watch strength workout, the app offers to mark the next workout done, and
accepting records it at the workout's end and advances the rotation; declining another workout
hides its offer; the Activity tab's calendar matches Health's strength and walking workouts for
the last four weeks, with walk distances, the latest body weight, and the progression line.

## Out of scope

Any Health write (the scale milestone), background delivery or observer queries, notifications,
charts, totals beyond the calendar, `.hiking`, iPad layout work, chat access, and a Watch app
(ADR-0004 D5).
