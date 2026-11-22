# Effort — TestFlight renewal on the mini

Status: Ready
Summary: A jon-platform `scripts/testflight-renew` that the mini runs daily. It reads each app's TestFlight expiry from App Store Connect, runs `testflight` 14 days before it, and iMessages Jon the result (jon-platform ADR-0010).

## Why

A TestFlight build stops launching after 90 days, and Fit Happens is meant to be finished, so it can
go a quarter without a merge. Build 1.0.0 (32) expires 2027-02-19. Jon decided on 2026-11-21 that the
mini releases on its own and reports by iMessage. The design is jon-platform
[ADR-0010](https://github.com/jonphillips/jon-platform/blob/main/docs/adr/0010-testflight-renewal.md),
and this brief builds it.

## Dispatch 1 — Build

**S1 — jon-platform `scripts/testflight-renew`.** This is a jon-platform PR, and it comes first.
Follow `scripts/rc-server`'s conventions for the LaunchAgent, labels, and logs.
- **`install --to HANDLE [--days 14] [--at HH:MM] REPO...`**
  - Check that each `REPO` has a `testflight.conf`. Then write and bootstrap one user LaunchAgent that
    runs `testflight-renew run` with the same handle, days, and repos, daily at `--at` (default 04:17).
  - Its `EnvironmentVariables` set a `PATH` that finds `asc`, `xcodegen`, `gh`, and `testflight`, since
    launchd's default `PATH` finds none of them.
  - Logs go under `~/Library/Logs/testflight-renew/`. The handle lives only in the plist.
- **`uninstall`.** Boot out the agent and remove the plist.
- **`status`.** Show whether the agent is loaded and when it last ran, then each repo's newest build,
  its expiry, and the days left.
- **`run [--force] [--dry-run] --to HANDLE [--days N] REPO...`**, one repo at a time, under a lock.
  A second run exits at once, and a stale lock (dead PID) is taken over.
  1. Read `APP_BUNDLE_ID` from `testflight.conf`, and resolve the app the way `testflight`'s
     `asc_app_id` does.
  2. Take the newest build that is `VALID` and not expired, and its `expirationDate`. No such build:
     log it and skip the repo, with no message.
  3. More than N days left, and no `--force`: log the days left and go on.
  4. Otherwise, if the clone isn't clean or isn't on `main`, send a failure message and don't touch
     it. Else run `git pull --ff-only`, then `testflight`, with the output to the log.
  5. Exit 0: read the new expiry and send "Released <app> <version> (<build>); it expires <date>."
     Non-zero: send the app, the exit code, the last `testflight:` line of the output, and the log path.
  - `--dry-run` prints each decision and runs no `testflight`, `git pull`, or message.
- **`notify-test --to HANDLE`.** Send one test message.
- **Sending.** Use `osascript` with an `on run argv` script, which takes the handle and the text as
  arguments, and send through Messages' iMessage account. Never interpolate either one into the
  AppleScript source. A send failure is logged, and `run` still exits non-zero.
- **Tests, in `scripts/tests/testflight-renew.sh`.** Stub `asc`, `testflight`, `osascript`,
  `launchctl`, and `git` where needed, the way `scripts/tests/rc-server.sh` does. Cover:
  - 20 days left: no `testflight` and no message;
  - 10 days left, and already expired: `testflight` runs, and the success message names the new expiry;
  - no valid build: skipped, with no message;
  - a dirty tree, or a branch other than `main`: no `testflight`, and a failure message;
  - `testflight` failing with exit 11: the message carries 11 and its last `testflight:` line;
  - `--force` with 60 days left releases, and `--dry-run` runs nothing and sends nothing;
  - a second run while the lock is held exits without work;
  - `install` writes a plist that passes `plutil -lint`, with the args, `PATH`, and calendar interval;
  - the handle and text reach `osascript` as arguments, unchanged, including quotes in the text.
- **Docs.**
  - `scripts/README.md` gets the script's line.
  - `docs/ios/testflight.md` § Renewal gets the install command.
  - `docs/always-on-mac.md` Phase 2 step 8 names the subcommands it runs.

**S2 — The app's records.** The companion PR here has no code. Closeout (ADR-0005 D16) adds the
`DONE-LOG.md` entry naming both branches and the jon-platform PR, appends the gate below, archives
this brief, and advances `NEXT_UP.md`.

**Done when:**
- S1's PR is merged. It lists `scripts/tests/testflight-renew.sh` passing and the syntax check for the
  script's shell.
- Installing on the mini isn't the executor's to do. The PR says so.
- S2 is merged, with closeout (ADR-0005 D16). The gate, on the mini: after `install`, `notify-test`
  alerts Jon's phone. Then, installed with `--days 90` so any build is due, `launchctl kickstart` of the
  agent releases Fit Happens and reports it by iMessage. That proves launchd's `PATH`, the Keychain,
  and the Messages grant. Reinstall with the default afterwards (jon-platform `always-on-mac.md`
  Phase 2 step 8).

**Notes.** This needs jon-platform #164 (ADR-0010) merged; if it isn't, stop and ask. Shared code,
used by every app with a `testflight.conf`. Don't change `scripts/testflight`.
If the mini isn't set up when this merges, the gate waits for it.
