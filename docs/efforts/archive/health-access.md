# Effort — Ask for Health access on every device

Status: Ready
Summary: A Health request that fails or doesn't take is silent and permanent: a once-only flag stops the app asking again, and Activity never asks. Ask from both screens until HealthKit has an answer, show a Connect to Health button while it hasn't, and show the error when the request fails.

## Why

**2026-11-21, iPad.** Activity showed "Nothing from Health yet" while the iPad's Health app was
full. Privacy & Security → Health → Apps listed no apps: Fit Happens had never asked on that device.
Deleting the app and reinstalling it from TestFlight brought up the prompt at once.

**2026-11-24, iPhone.** Jon deleted the app and installed build 36 from TestFlight fresh. No prompt
came, and Fit Happens isn't listed under Health access in Settings. So a reinstall isn't a reliable
fix. The build isn't at fault: the architect checked build 36's exported IPA, and it carries
`com.apple.developer.healthkit` in both its signature and its profile, plus both purpose strings,
the same as build 32, which prompted on the iPad. The app asked and the request didn't take, and
the app has no way to show that or to recover:

- `WorkoutScreenModel.screenAppeared` asks only while the `fitHappensHealthAuthRequested` flag is
  false. It sets the flag whenever the request returns, including when it throws, and when
  `requestReadAuthorization` returns early because Health isn't available. After one failed
  attempt, the app never asks again on that install, though HealthKit still has no answer.
- A thrown request only sets `healthReadFailed`, which shows only beside a program. A fresh install
  has no program until sync runs, so the failure shows nothing, and its error is never shown.
- The request runs in `.task(id: scenePhase)`. A phase change while the prompt is coming up cancels
  the task, and so the request, part-way through.
- `ActivityScreenModel.screenAppeared` reads Health without asking, and turns any error into empty
  results. So it shows "Nothing from Health yet" for good.

HealthKit says whether it still needs to ask: `HKHealthStore.statusForAuthorizationRequest(toShare:read:)`
returns `.shouldRequest` until the person answers, and `.unnecessary` after. It doesn't say whether
reads were allowed or denied. The app can use the status to tell "never answered" from "answered".

## Dispatch 1 — Build

- **Core.** Replace the bare request with one `HealthClient` method that both models call before
  reading. It returns an enum, not flags:
  - `ready`: HealthKit has an answer (`.unnecessary`), so reads can go ahead;
  - `needsRequest`: it asked, and the status is still `.shouldRequest`;
  - `failed(String)`: the request or the status check threw, with the error's description.

  The live client checks the status, asks only while it's `.shouldRequest`, then checks again.
  Health not being available is `failed`, not `ready`. `CancellationError` propagates.
- **The request survives a phase change.** A scene-phase change doesn't cancel a request that's in
  flight, and a second call while one is pending waits for it rather than asking twice.
- **Next Workout.** `WorkoutScreenModel` drops `fitHappensHealthAuthRequested` and calls the new
  method each time the screen becomes active. `needsRequest` and `failed` show whether or not
  there's a program.
- **Activity.** `ActivityScreenModel` calls it before its reads.
- **Both screens, same rows.**
  - `needsRequest` shows a **Connect to Health** button that asks again on a tap.
  - `failed` shows "Couldn't read Health" with the error text, so a device pass can report it.
  - `ready` with no workouts and no body weight shows the empty text, plus where to look: Settings →
    Health → Data Access & Devices → Fit Happens. HealthKit hides a denied read, so the app can't
    tell "denied" from "nothing yet", and the text covers both.
- **Tests (Core).** With a test `HealthClient`:
  - each screen asks on every activation while the answer is `needsRequest`, not only the first time;
  - `.shouldRequest` after asking gives `needsRequest`, and `.unnecessary` gives `ready`;
  - a throwing request gives `failed` with its description;
  - a cancelled request propagates `CancellationError`;
  - two overlapping calls ask once.

**Done when:**
- `scripts/check-drift.sh` passes, and the tests above exist.
- Closeout (ADR-0005 D16). The device gate, on Jon's iPhone with the TestFlight build:
  - On a fresh install, opening the app brings up the Health prompt. If it doesn't, Next Workout
    shows Connect to Health or the error text, and Jon reports which.
  - Connect to Health brings up the prompt. Once access is allowed, walks and body weight show on
    Activity, and Fit Happens is listed in Settings → Health → Data Access & Devices.
  - Where Fit Happens already has access, nothing prompts and no Connect to Health row shows.

**Notes.** Reads only. Don't add share types: ADR-0004 asks for the body-mass write when the scale
arrives, not before.
