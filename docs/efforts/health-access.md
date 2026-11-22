# Effort — Ask for Health access on every device

Status: Ready
Summary: The app asks for Health read access only from Next Workout, behind a once-only flag that can stick without ever asking, and Activity never asks. Ask from both screens every time, and say where to turn access on when Health returns nothing.

## Why

On 2026-11-21, Activity on Jon's iPad showed "Nothing from Health yet" while the iPad's Health app
was full. Privacy & Security → Health → Apps listed no apps: Fit Happens had never asked on that
device, and Next Workout didn't ask either. Deleting the app and reinstalling it from TestFlight
brought up the prompt at once. The cause is in the app:

- `WorkoutScreenModel.screenAppeared` asks only while the `fitHappensHealthAuthRequested` flag is
  false. That flag is per device and survives an install over an earlier build. It's set whenever the
  request returns, including when it throws, and when `requestReadAuthorization` returns early
  because Health isn't available. After that, the app never asks again, though HealthKit still has no
  answer.
- `ActivityScreenModel.screenAppeared` reads Health without asking, and turns any error into empty
  results. So a device that never opened Next Workout, or never asked, shows "Nothing from Health
  yet" for good.

HealthKit only shows its prompt when the request hasn't been answered, so asking each time a screen
appears costs nothing. The flag isn't needed.

## Dispatch 1 — Build

- **Core.** Add a `HealthClient` method that both models call before reading. It calls
  `requestReadAuthorization` every time, and returns whether reads can go ahead or the request
  failed. `CancellationError` propagates.
- **Next Workout.** `WorkoutScreenModel` drops `fitHappensHealthAuthRequested` and calls the new
  method on every `screenAppeared`. A failure keeps setting `healthReadFailed`, as today.
- **Activity.** `ActivityScreenModel` calls it before its reads.
  - When the request or a read fails, Activity says it couldn't read Health.
  - When Health returns no workouts and no body weight, the empty text adds where to look: Settings →
    Health → Data Access & Devices → Fit Happens. HealthKit hides a denied read, so the app can't
    tell "denied" from "nothing yet", and the text covers both.
- **Tests (Core).** With a test `HealthClient`:
  - the method asks on every call, not only the first;
  - a throwing request reports failure;
  - a cancelled request propagates `CancellationError`.

**Done when:**
- `scripts/check-drift.sh` passes, and the tests above exist.
- Closeout (ADR-0005 D16). The device gate: on a device where Fit Happens has never asked, opening
  Activity first brings up the Health prompt. After it's allowed, walks and body weight show there.
  On a device where it already has access, nothing prompts.

**Notes.** Reads only. Don't add share types: ADR-0004 asks for the body-mass write when the scale
arrives, not before.
