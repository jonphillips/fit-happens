# Effort — TestFlight and Production

Status: Designed
Summary: Ship Fit Happens through TestFlight from the mini, so a merged dispatch reaches Jon's iPhone wherever he is. The app gets a sync switch, the push entitlement, and CloudSyncKit backup and restore, and then moves to CloudKit Production (ADR-0007).

## Why

Today a build reaches the phone only from Xcode, on a Mac at hand. With TestFlight, the always-on mini
runs `testflight` after a merge, and Jon installs from the TestFlight app anywhere. Every device pass
then runs on a TestFlight build. Decisions: [ADR-0007](../decisions/0007-testflight-and-production.md).

## Dispatch 1 — Build: `testflight` without an app group, then the app work

**S1 — jon-platform `scripts/testflight` (ADR-0007 D7).** This is a jon-platform PR, and it comes
first.
- `APP_GROUP` becomes optional. When it's empty, `verify_bundle` expects no
  `com.apple.security.application-groups`, and a non-empty `EXTRA_APP_GROUPS` exits 10 with a
  message that says why.
- The script's stub tests cover an app with no group: it passes when it carries none, and fails when
  it carries one. Galavant's and Yes Chef's configs pass unchanged.
- `docs/ios/testflight.md` marks `APP_GROUP` as optional in the config table and says what empty
  means.

**S2 — The app (ADR-0007 D1–D4).** This is the companion PR, after S1 merges.
- **Release config.**
  - Add `testflight.conf`, with `APP_BUNDLE_ID=com.jonphillips.FitHappens`, no `APP_GROUP`,
    `CLOUDKIT_CONTAINER=iCloud.com.jonphillips.fithappens`, `SCHEMA_GATE=1`,
    `EXPECTED_SCHEMA_FIELDS=cloudkit-expected-fields.txt`, the `DONE_LOG` and `DEVICE_PASSES` paths,
    and `ASC_VERSION` and `TEAM_ID` matching Galavant's file.
  - Add `cloudkit-expected-fields.txt`, listing every column of the six synced tables from the
    migration.
  - In `project.yml`, set `CURRENT_PROJECT_VERSION` with Galavant's
    floor-value comment.
  - In `Info.plist`, set `ITSAppUsesNonExemptEncryption` to `NO`.
- **Push.** Add `aps-environment: development` to `project.yml`'s entitlements.
- **Sync switch.** Add an **iCloud Sync** switch, off by default, through
  `CloudSync.setManuallyEnabled` and `isManuallyEnabled`, with `FitHappensCloudSync.configuration`.
  - On starts the engine; off stops it.
  - One status line from `SyncHealth`, as far as the kit provides it.
  - The launch argument keeps working.
- **Backup and restore.** Configure `DatabaseBackupConfiguration` and `AutomaticBackupConfiguration`
  in Core.
  - Identify a Fit Happens store by the six tables. Count `completions` for the shrink warning.
  - Use the kit's default retention. Leave out the "Back Up Now" App Intent.
  - Wire the kit's models as they are: Back Up Now through the share sheet; Restore… through the file
    importer, starting at `Documents/Backups/`; Undo Last Restore; the confirmed re-enable of sync;
    and the automatic backup on foreground.
- **The Program screen** (the Program tab, after [tabs-and-ramps](archive/tabs-and-ramps.md)) gets one **iCloud** section below Chat Access (D4). It holds the switch and
  its status line, Back Up Now, Restore…, Undo Last Restore (shown only when the kit has one), and the
  automatic backup's status.
- **Tests (Core).**
  - The configuration accepts a Fit Happens store and rejects one without its tables.
  - A seeded store with a program, revisions, and completions round-trips through snapshot, prepare,
    and restore with every row intact.
  - Every column of every synced table is listed in `cloudkit-expected-fields.txt`, so a future
    migration can't drift from it silently.
- **Notes.**
  - Use `CloudSyncKit` as it is. If it needs a change, stop and flag it: shared code escalates to
    Jon.
  - Fit Happens shares nothing, so leave out the kit's participant handling.
  - No Settings screen and no Dev variant (ADR-0007 D4, D6).

**Done when:**
- S1's PR is merged, with its local verification listed.
- In S2, `scripts/check-drift.sh` passes and the tests above exist.
- `testflight --dry-run` isn't the executor's to run: it needs the Team key. The PR says so.
- Closeout (ADR-0005 D16). The device gate: on a development build, Back Up Now writes a file, and a
  restore of it on the same phone brings back the same program and history. The automatic backup
  appears, and the switch starts and stops sync.

## Then — Jon's cutover (ADR-0007 D5)

This isn't a dispatch. Jon does it with the architect, after Dispatch 1's device gate passes. When a
step is done, the architect records it in `DONE-LOG.md`.

1. **One-time, if not done yet.**
   - The mini's `testflight` setup (jon-platform `always-on-mac.md`, Phase 2 step 5).
   - A Remote Control server for this repo on the mini (`rc-server install ~/code/fit-happens`).
   - The App Store Connect app record for `com.jonphillips.FitHappens`, with Jon as an internal
     tester.
2. **`testflight --no-upload`** from clean `main` on the mini. This proves signing, the entitlements
   (`aps-environment`, the container, no app group), and the schema gate's Development export.
3. **Check what Development holds** in the CloudKit console against the six tables. Remove anything
   left over from an experiment.
4. **Deploy the schema to Production.** Then rerun `testflight --dry-run`, which should pass schema
   parity.
5. **Back up on the phone** with the development build. Check that the file restores, and keep it in
   two places off the phone.
6. **`testflight`**, then install the build from TestFlight over the development build.
7. **Restore** the step-5 backup, then turn on iCloud Sync and confirm.
8. **In the CloudKit console**, check that Production record counts match the backup's.
9. **On a second device** signed into the same account, install from TestFlight, turn on sync, and
   check that the whole program and history arrive. That also passes M1 S3's second-device gate.
10. **From then on,** Jon's phone takes only TestFlight builds (D6). Delete development builds from
    the second device, too.

Rollback, through step 8: reinstall a development build. Development and its data are untouched.

## Open for Jon

- **When.** *Updated 2026-11-20:* queued after [Three tabs, and ramped sets](archive/tabs-and-ramps.md), whose ramp column should be in the Production schema. Originally queued after M3 Dispatch 2. If remote device passes matter sooner, this can go ahead of
  M3 Dispatch 2. Then PR #15's `NEXT_UP.md` advance would point here instead.
- **The 90-day expiry.** A TestFlight build stops launching after 90 days. A finished app still needs
  a `testflight` run each quarter. It could be a scheduled task on the mini, or just a reminder.
