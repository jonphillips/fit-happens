# Next Up — TestFlight and Production · Dispatch 1: `testflight` without an app group, then the app work

**Slices:** TestFlight and Production · Dispatch 1 (S1 in jon-platform, then S2 here)
**Briefs:** docs/efforts/testflight-production.md §Dispatch 1; docs/decisions/0007 D1–D4, D7
**Done when:** per the brief. S1: a jon-platform PR makes `APP_GROUP` optional in `scripts/testflight`, with the stub tests and `docs/ios/testflight.md` updated. Galavant's and Yes Chef's configs pass unchanged, and it merges before S2 starts. S2, here: `testflight.conf`, `cloudkit-expected-fields.txt` covering every migration, the version floor, the encryption key, `aps-environment`, the iCloud Sync switch with its status line, and CloudSyncKit backup and restore wired as the kit provides, in one iCloud section on the Program tab. It includes the Core tests the brief lists. `testflight --dry-run` needs the Team key, so the PR says it wasn't run. Closeout (ADR-0005 D16).
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** S1 is shared code, so it escalates to Jon. Use `CloudSyncKit` as it is; if it needs a change, stop and flag it. The bundle ID is `com.jonphillips.fithappens` (ADR-0007 D1, amended). The cutover after this dispatch is Jon's, not a dispatch.
