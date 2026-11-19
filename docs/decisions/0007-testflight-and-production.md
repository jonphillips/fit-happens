# ADR-0007 — TestFlight, and the move to CloudKit Production

*Status: **proposed** — 2026-11-19, ratified by Jon merging the plan PR that adds it. Carries out
[ADR-0001](0001-house-stack-and-sync.md)'s "one more CloudKit container to promote to Production
before TestFlight". Adopts jon-platform ADR-0006 (backup and restore in `CloudSyncKit`) and ADR-0008
(automatic backups). Prior art: galavant ADR-0049 (the cutover order this follows) and Yes Chef
ADR-0056. Effort: [testflight-production](../efforts/testflight-production.md).*

Summary: Fit Happens ships to Jon's iPhone through TestFlight, built and uploaded by the always-on
mini, so a merged dispatch reaches the phone wherever Jon is. That moves sync to CloudKit Production,
so the app first gets an in-app sync switch, the push entitlement it's missing, and `CloudSyncKit`
backup and restore. A backup made on the development build reseeds Production. After the move, Jon's
phone runs only TestFlight builds.

## Context

Today the app reaches the phone only as a development build from Xcode, on a Mac at hand. Jon wants
to work remotely (2026-11-19): merge a dispatch, have the mini build it, and install it from TestFlight
on the phone. The device passes in [device-passes.md](../device-passes.md) are what that unlocks:
each one needs a build on the phone, and `testflight` already turns new gate lines into "Check on this
build."

A TestFlight build signs for CloudKit **Production**. Development builds use **Development**. They
are separate databases. The local store survives installing a TestFlight build over a development
build (same bundle ID), but SQLiteData's sync metadatabase is keyed by container, not environment.
Rows it thinks it already sent to Development may never reach Production. Yes Chef and Galavant hit
this, and a restore is the measured way to reseed (jon-platform ADR-0006, `SEAM-LEDGER.md`).

Reading the app against what a TestFlight build needs turned up four gaps:

- **Sync can't be turned on outside Xcode.** `FitHappensCloudSync` starts only once the
  `-FitHappensCloudKitSyncEnabled` launch argument has been persisted, and a TestFlight build gets no
  launch arguments. It's unknown whether sync has ever run on Jon's phone; M1 S3's second-device gate
  is still owed.
- **No push entitlement.** `Info.plist` declares the `remote-notification` background mode, but the
  entitlements have no `aps-environment`, so CloudKit's change pushes never arrive. `testflight` also
  requires `aps-environment = production` in the exported app.
- **No backup.** ADR-0001 D2 committed to adopting the kit's backups, and none landed. The cutover
  needs one, and the history is Jon's only record of his training.
- **`testflight` requires an app group,** and checks that the app carries exactly that set. Fit
  Happens has none and needs none.

## Decision

### D1 — TestFlight is how the app reaches the phone

Releases run `testflight` (jon-platform `docs/ios/testflight.md`) from clean `main`, on the mini.
Internal testing only: Jon is the one tester. The app keeps its existing App ID
`com.jonphillips.FitHappens`, because a new ID is a new app with an empty store. `testflight.conf`
sets that ID, `CLOUDKIT_CONTAINER=iCloud.com.jonphillips.fithappens`, the house team ID, and the
records files. `project.yml` gains `DEVELOPMENT_TEAM`, and `Info.plist` gains
`ITSAppUsesNonExemptEncryption = NO`, as Galavant's do.

### D2 — An in-app sync switch, and the push entitlement

- **iCloud Sync** is a switch, off by default, through `CloudSync.setManuallyEnabled` and
  `isManuallyEnabled` (the kit's manual enablement, already configured in `FitHappensCloudSync`).
  Turning it on starts the engine. Turning it off stops it. A restore turns it off, and turning it
  back on is the confirmed step the kit already provides. The launch argument keeps working for
  development builds.
- `project.yml` adds `aps-environment: development`. Export rewrites it to `production`.
- The switch shows the kit's `SyncHealth` status in one line, as far as the kit provides it (ADR-0001
  D2). No sync dashboard.

### D3 — Backup and restore come from `CloudSyncKit`

Configured, not copied (jon-platform ADR-0006 D1):

- **Back Up Now** exports a snapshot through the share sheet (`DatabaseBackupExportModel`).
- **Restore…** opens the file importer at the Backups folder and runs the kit's restore. The restore
  validates the file and keeps a pre-restore snapshot for **Undo Last Restore**. It also discards the
  metadatabase and holds sync off until Jon turns it back on. The kit's owner guard always passes,
  because Fit Happens shares nothing.
- **Automatic backups** (jon-platform ADR-0008) go to `Documents/Backups/` in the app's container,
  which has iCloud Documents since M3. They run on foreground when the last one is more than 24 hours
  old, with the kit's default retention. The status row is `AutomaticBackupModel`'s.
- The configuration identifies a Fit Happens store by its six tables, and counts `completions` for the
  shrink warning.

### D4 — The controls go on the Program screen

There's still no Settings screen. One **iCloud** section on the Program screen, below Chat Access,
holds the sync switch and its status, Back Up Now, Restore…, Undo Last Restore (only after a
restore), and the automatic backup's status. The Program screen already holds what changes the app's
data from outside (ADR-0006 D2), and a fourth screen would hold four rows.

### D5 — The cutover order

The checklist is in the effort brief. The order and its gates:

1. **The app work has shipped** on a development build. A backup restores on the same phone and the
   contents match, and the sync switch starts the engine.
2. **Check what Development holds.** In the CloudKit console, check the record types against the six
   tables `makeSyncEngine` registers, in both directions. Look for leftovers from experiments,
   because a deployed schema is permanent.
3. **Deploy the schema to Production.**
4. **Back up from the development build.** Check the file restores, and keep it in two places off the
   phone. It's both the reseed and the rollback.
5. **Install the TestFlight build over the development build.** Restore the step-4 backup, then turn
   sync on. Restore re-pushes every row.
6. **Check Production in the CloudKit console** (record counts, not the in-app status). Then install
   from TestFlight on a second device signed into the same account, turn sync on, and check that it
   pulls the whole program and history. That also closes M1 S3's second-device gate.

**Rollback:** until step 6 passes, Development and its data are untouched. Reinstalling a
development build gets the working app back.

### D6 — After the cutover, no development builds on Jon's phone

A development build with the same bundle ID would sync the same store against Development, and the
container-keyed metadatabase would corrupt its bookkeeping (jon-platform `SEAM-LEDGER.md`,
post-cutover dev variant). So every device pass after the cutover runs on a TestFlight build. Xcode
builds go to the simulator, or to a device that has never held Production data. There's no Dev variant
(M3 left it out of scope, and ADR-0006 D1 names where it would go). Revisit only if waiting for a
TestFlight build becomes a real cost. That would be its own ADR, following the seam ledger's shape.

### D7 — `testflight` stops requiring an app group

The script treats `APP_GROUP` as optional. When it's empty, the exported app must carry no app group,
and `EXTRA_APP_GROUPS` is an error. Galavant's and Yes Chef's configs and checks don't change. This
is shared code, so it's a jon-platform PR before the app PR (agent-collaboration, "Dispatches whose
code lands in jon-platform"). Merging this ADR is Jon's approval of that change. The alternative, an
unused app group in Fit Happens, adds an entitlement and an App ID capability that exist only to pass
a check.

## Consequences

- Jon can take a merged dispatch to the phone from anywhere the mini is reachable. A release costs
  one `testflight` run, plus up to 45 minutes of processing.
- History gets a copy outside CloudKit and the phone for the first time.
- Every device pass waits for a TestFlight build. Quick on-device iteration from Xcode ends at the
  cutover.
- New one-time ops: the App Store Connect app record, the schema deploy, and the cutover itself.
  The mini's `testflight` setup (the Team key and `asc`) is shared with Galavant and Yes Chef. It's
  done once per Mac (jon-platform `always-on-mac.md`, Phase 2 step 5), and if the mini hasn't done it
  yet, that comes first.
- TestFlight builds expire after 90 days, so the app needs a release at least that often. That's
  easy to miss for an app meant to be finished.
- M4's scale readings land on a Production container from the start.

## Alternatives considered

| Option | Verdict |
| --- | --- |
| **Stay on development builds** | Rejected: Jon wants remote installs. It's also the only way M3's and later device passes happen away from the Mac. |
| **Install TestFlight over the development build and turn on sync, no restore** | Not relied on: the metadatabase may skip rows it sent to Development. Trying it first is allowed (galavant ADR-0049 D3 step 5), because restore stays available. |
| **Reseed from the chat export or the latest program revision** | Rejected: the export has no row IDs, and a revision holds only the program, not history. |
| **A Settings screen for sync and backup** | Rejected for now: D4. Revisit if the Program screen's iCloud section grows past these rows. |
| **A Dev variant (`.dev` bundle ID, own app group, same container)** | Deferred: D6. |
| **An unused app group to satisfy `testflight`** | Rejected: D7. |
