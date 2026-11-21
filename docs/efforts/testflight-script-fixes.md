# Effort — `testflight`: empty upload slots and a stale project

Status: Ready
Summary: Two jon-platform `scripts/testflight` defects that Fit Happens' first release hit. A failed or `--no-upload` run leaves an empty App Store Connect upload slot that blocks the rerun, and a run after a pull archives a stale XcodeGen project.

## Why

Both showed up on 2026-11-21, during Fit Happens' first `testflight` run, from Jon's MBP
([testflight-production](archive/testflight-production.md) cutover).

- **Empty upload slots.** `export_archive … export` (method `app-store-connect`) registers a build
  upload in App Store Connect, even though nothing is uploaded. It's left in state
  `AWAITING_UPLOAD`. `asc builds next-build-number` counts in-flight uploads, so the next run's
  preflight fails with `build number 31 is behind App Store Connect's 32`. That happened after a
  `--no-upload` run (slot 31), after an export that failed validation (slot 31 again), and after a
  run on a stale project (slot 32). Each time, the architect deleted the slot with
  `asc builds uploads delete --id … --confirm`, and the next build number fell back to 1.
- **A stale project.** With `XCODEGEN=1`, the script runs `xcodegen generate` only in
  `version_bump`. Apps whose generated project and `Info.plist` are untracked build whatever was
  last generated. After a pull, `testflight` archived without the `NSHealthUpdateUsageDescription`
  that `main` had just added (fit-happens #31), and the upload failed validation. The repo's
  `xcodegen-sync` hooks would have regenerated it, but that clone had never run `scripts/setup.sh`,
  so `core.hooksPath` was unset. A release shouldn't depend on a per-clone hook (jon-platform
  `drift-control.md` records Galavant shipping the same gap).

## Dispatch 1 — Build

**S1 — jon-platform `scripts/testflight`.** This is a jon-platform PR, and it comes first.
- **Regenerate before preflight passes.** A new `regenerate_project` runs in `preflight` right after
  the clean-tree, branch, and `main == origin/main` checks. When `XCODEGEN=1`, it runs
  `xcodegen generate --quiet` in `$ROOT`. Then the tree must still be clean. If it isn't, it exits 10
  with a message that names the changed files and says the committed project disagrees with
  `project.yml`. With `XCODEGEN` unset or 0, it does nothing. Dry runs regenerate too: it's local.
- **Clear this build's empty slots.** A new `clear_empty_upload_slots VERSION NUMBER` runs in
  `preflight` before `asc builds next-build-number`.
  - It resolves the app with the existing `asc_app_id`, then lists
    `asc builds uploads list --app <id> --cf-bundle-short-version VERSION --cf-bundle-version NUMBER
    --platform IOS --state AWAITING_UPLOAD --output json`.
  - On a release or `--no-upload` run, it deletes each listed slot with
    `asc builds uploads delete --id <id> --confirm` and prints one line per slot.
  - On `--dry-run`, it deletes nothing. It prints that a release run would delete them, and preflight
    skips the build-number comparison, since that comparison would count the slots.
  - It never touches another version or build number, or any other state. A slot ahead of git's
    count still fails the check as today: it means a later commit was uploaded from somewhere else.
  - A failure to resolve, list, or delete exits 10 with what `asc` said.
- **Tests, in `scripts/test-testflight`.** Extend the `asc` stub with `builds uploads` list and
  delete, and stub `xcodegen`. Cover:
  - only the matching `AWAITING_UPLOAD` slots are deleted, and other versions, numbers, and states
    aren't;
  - a dry run deletes nothing;
  - a regeneration that leaves the tree clean passes; one that changes a tracked file exits 10;
    `XCODEGEN=0` doesn't call `xcodegen`.
- **Docs.** `docs/ios/testflight.md`'s troubleshooting row for the build-number message says the
  script clears this build's empty slots itself, so the message now means a real upload is ahead.
  Add one line saying that preflight regenerates an XcodeGen project.

**S2 — The app's records.** The companion PR here has no code. Closeout (ADR-0005 D16) adds the
`DONE-LOG.md` entry naming both branches and the jon-platform PR, archives this brief, and advances
`NEXT_UP.md`. The TestFlight and Production brief is Blocked, so it leaves `NEXT_UP.md` empty.

**Done when:**
- S1's PR is merged. It lists `scripts/test-testflight` passing, and `bash -n scripts/testflight`.
- `testflight --dry-run` isn't the executor's to run: it needs the Team key. The PR says so. Jon's
  next Fit Happens release is the live check.
- S2 is merged. There's no device gate.

**Notes.** Shared code: Galavant's and Yes Chef's configs must work unchanged. Both track their
generated project. The architect ran `xcodegen generate` on each app's `main` on 2026-11-21, and
neither tree changed, so the clean-tree rule doesn't block them. Don't change
`export_archive`, the upload, or `build_number_sufficient`.
