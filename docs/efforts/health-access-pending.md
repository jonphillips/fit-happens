# Effort — A Health request that never returns

Status: Ready
Summary: On Jon's iPhone the Health request never returns, so Activity spins for good and Next Workout shows nothing. Show Activity at once, show a request that's still waiting, let Connect to Health start a fresh request, and log each step of the request so a Console capture shows where it stops.

## Why

On 2026-11-24, Jon installed build 38 (`dca3edfe`, [health-access](archive/health-access.md)) on
his iPhone, and Activity stayed on its spinner. Build 36 had shown no prompt either. Both fit one
cause: `HKHealthStore.requestAuthorization` (or the status check before it) never returns on that
phone. Build 36 had no way to show that. In build 38 it locks the screens:

- `ActivityScreenModel.loadHealth` sets `hasLoaded` only after the Health request returns, and
  `ActivityScreen` shows a full-screen spinner until then. The calendar's completions and the
  progression are local data, but they wait on Health too.
- `HealthAuthorizationCoordinator` makes every later call await the request already in flight. A
  request that never returns holds every later call too, including Connect to Health.
- Next Workout shows a row only for `needsRequest` and `failed`. While the request is pending,
  `healthReadAccess` is `nil` and the screen says nothing.

Why the request doesn't return on that phone isn't known yet. This effort makes the app survive it,
show it, and log it.

## Dispatch 1 — Build

- **Activity shows at once.** Local content (the calendar's completions, the progression) doesn't
  wait on Health. The spinner goes, or covers only the Health parts until the first Health answer.
- **A pending request is a state.** `HealthReadAccess` gains `waiting`, for a request that's been
  made with no answer yet. Both screens show it as "Waiting for Health…" with a Connect to Health
  button, so a request that never returns still offers a way out.
- **Connect to Health starts a fresh request.** A tap doesn't join one that's pending. Screen
  activations still share the pending request, so two screens appearing together ask once. The
  coordinator drops a stale request's answer when a newer one has finished.
- **Log the request.** Use a `Logger` (subsystem `com.jonphillips.fithappens`, category `health`)
  for each step: the status before, the request starting, the request returning or throwing (with
  the error), and the status after. Jon can then read the Console capture and see where it stops.
- **Tests (Core).**
  - A request that hasn't returned reports `waiting` to a second caller instead of blocking it.
  - Connect to Health starts a new request while an earlier one is still pending.
  - A stale request that finishes after a newer one doesn't overwrite the newer answer.
  - Two screen activations still ask once.
  - Activity's local data is shown while the request is pending.

**Done when:**
- `scripts/check-drift.sh` passes, and the tests above exist.
- Closeout (ADR-0005 D16). The device gate, on Jon's iPhone with the TestFlight build:
  - Activity shows its calendar and progression at once.
  - If no prompt comes, both screens show "Waiting for Health…" and Connect to Health.
  - Jon captures Console (device: the iPhone, filter: category `health`) while tapping Connect to
    Health, and pastes the lines into the PR or `open-questions.md`.
  - If the prompt comes and access is allowed, walks and body weight show on Activity.

**Notes.** Reads only; no share types (ADR-0004). This replaces neither the status check nor the
coordinator from health-access. It stops a request that never returns from holding the screens.
