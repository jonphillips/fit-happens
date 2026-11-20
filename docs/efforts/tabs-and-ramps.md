# Effort — Three tabs, and ramped sets

Status: Ready
Summary: Next Workout loses its toolbar. Program becomes a tab that shows the whole program, and History becomes a "Fix a workout" link in Activity plus a tappable "Last done" line. Then an item can be a ramp (10 @ 155 · 8 @ 165 · 6 @ 175) that moves with the one working weight.

## Why

Jon, 2026-11-20, during the M3 device passes:

- Nowhere in the app shows the whole program. Next Workout shows the next workout only, and the
  Program sheet holds paste, chat, and revisions but never the program itself.
- The two toolbar buttons on Next Workout open a lot of function and setup. History is for fixing
  mistakes: the Activity calendar already shows what he did.
- One lift is a ramp, 10 reps at 155, 8 at 165, then 6 at 175, and the program can't say that.

Decisions: [PRODUCT.md](../PRODUCT.md) (the three tabs), ADR-0003 D3 (amended 2026-11-20), and
ADR-0002 D1 and D2 (amended 2026-11-20). The word is **ramp**, not "progression": Activity already
has a progression line, and automated progression advice is a non-goal.

## Dispatch 1 — Three tabs

**Core.**
- A `ProgramOverview` projection: every current workout in program order, each with the rows
  `WorkoutOverview` builds today (name, prescription, load kind, weight, label), and the next
  workout's key from `WorkoutRotation`. Build both from one per-item mapping so they can't drift.
  `WorkoutOverview` can become the next workout's slice of it.
- Tests: workouts in program order; the next one marked, including when the latest completion's
  workout is gone (ADR-0003 D2); bodyweight rows carry no weight; no program gives `nil`.

**App.**
- **Tabs:** Next Workout, Activity, Program, in that order. The Program tab shows
  `chatInbox.readyCount` as its `.badge` (none at 0), which replaces the hand-built capsule.
- **Next Workout** has no toolbar. Remove the History and Program buttons and their sheet
  destinations. The empty state's Import Program button selects the Program tab.
- **"Last done"** becomes a button when there's a completion. It opens a sheet for the latest
  completion with the existing date correction and an **Undo Workout X** button that uses the existing
  confirmation. "No workouts completed yet" stays plain text.
- **Activity** ends with a **Fix a workout** navigation row. It pushes the existing completion list
  (change date on any row, undo on the latest) and the date screen, titled "Fix a Workout". Since it's
  pushed, it has no Done button.
- **One corrections model.** History, change date, and undo move out of `WorkoutScreenModel` into one
  model that both surfaces use. `WorkoutHistoryOperations` doesn't change.
- **Program tab:** the current Program screen becomes the tab's root, with no Done button. Sections,
  top to bottom:
  1. From Chat, only when it has proposals or a message.
  2. The program: one section per workout, headed "Workout A" with the next one marked "Next". Each
     row shows name, prescription, and weight with its label, or "Bodyweight". It's view-only, with
     no steppers and no tap action.
  3. Paste, Instructions, Chat Access, and Accepted revisions, in today's order.
  The review still pushes onto this stack.
- **Ownership:** `ChatAccessExportModel` moves to the app root, and so does its background export on
  `scenePhase`, so the export doesn't depend on which tab was last open.
- Keep every list row to one default-style button, or make each `.borderless`
  ([list-row-buttons](archive/list-row-buttons.md)).

**Done when:**
- `scripts/check-drift.sh` passes, with the Core tests above and the inbox tests unchanged.
- No simulator walkthrough ([verification.md](../verification.md)).
- Closeout (ADR-0005 D16). The device gate: on iPhone, three tabs. Program shows every workout with
  the next one marked, and a staged proposal badges the tab. Tapping "Last done" changes the date and
  undoes. Fix a workout in Activity changes an older completion's date.

## Dispatch 2 — Ramped sets

**Core: the contract (ADR-0002 D2, amended).**
- `ProgramExercise` gains an optional `ramp: [{reps: String, offset: Double}]`.
- Add a `ProgramContractError` case for each of these, with its sentence in `ProgramErrorMessage`:
  - fewer than two steps
  - empty reps
  - a non-finite offset, or one above 0
  - no step at 0
  - a ramp on a bodyweight item
- `emptyPrescription` applies only to an item without a ramp. A prescription that comes with a ramp
  is ignored and listed in the change set, like `IgnoredStartingWeight`.
- `ProgramChanges` reports a ramp that's added, removed, or changed as a `PrescriptionChange`, in
  relative form (`10 @ −20 · 8 @ −10 · 6 @ top`).
- `ProgramContractRules.instructions` gets one sentence and the example line from ADR-0002 D2. The MCP
  server's instructions pick it up automatically.

**Core: storage and the resolver (ADR-0002 D1, amended).**
- An additive migration adds a nullable `ramp` text column (JSON) to `workoutItems`. Apply writes it
  and clears it when an item loses its ramp. Re-applying a stored revision restores exactly that
  revision's ramps.
- One resolver turns an item plus the working weight into its display prescription: the steps joined
  with " · ", each as `reps @ weight`. Weights are formatted like the weight control, and a step
  below 0 shows 0. `WorkoutOverview`, `ProgramOverview`, `CompletionSnapshots`, and the chat export
  all go through it. Nothing reads a ramped item's stored prescription directly.
- In the export, `ChatWorkoutItem` gains an optional `ramp`, and its `prescription` is the
  resolver's text. The export stays version 1.

**App.** Next Workout and the Program tab show the resolved text where the prescription sits now. Let
it wrap. The stepper doesn't change.

**Tests:**
- Decoding, and each new error with its message.
- Apply, re-apply, and ramp removal.
- Resolver text, including a floor at 0 and a 2.5 lb increment.
- A stepped weight moves the whole resolved ramp.
- The snapshot stores the resolved text with the working weight as its load.
- The review's relative form, and the ignored prescription.
- An export round trip.
- In `FitHappensMCP`: `get_program` shows the ramp, `propose_program` stages a valid ramp, and it
  rejects a bad one with the review's sentence.

**Done when:**
- `scripts/check-drift.sh` passes with the tests above.
- Closeout (ADR-0005 D16). The device gate: a chat proposes a ramp for one lift through
  `propose_program`. The review shows it, Apply puts it on Next Workout, the stepper moves all its
  steps, and `get_program` returns it.

## Open for Jon

- **Queue.** This goes ahead of [TestFlight and Production](testflight-production.md). Dispatch 2 adds
  a CloudKit field, so landing it first means the Production schema deploys with it. Adding it after
  the cutover would also work, but would need a second Production deploy.
- **After Dispatch 2,** copy the updated instructions from the Program tab into the ChatGPT Project.
  Until then, the paste path doesn't know about ramps, but chat access does.
- **Until it ships,** a ramp can be plain text: prescription `10 @ 155 · 8 @ 165 · 6 @ 175` with a
  working weight of 175. The text won't move with the stepper.
