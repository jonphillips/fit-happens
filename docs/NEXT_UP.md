# Next Up — `testflight`: empty upload slots and a stale project · Dispatch 1

**Slices:** testflight-script-fixes Dispatch 1 (S1 in jon-platform, then S2 here)
**Briefs:** docs/efforts/testflight-script-fixes.md §Dispatch 1
**Done when:** per the brief. S1: a jon-platform PR adds `regenerate_project` and `clear_empty_upload_slots` to `scripts/testflight`'s preflight, with stub tests in `scripts/test-testflight` and the `testflight.md` lines. It lists `scripts/test-testflight` and `bash -n scripts/testflight` passing. S2, here: a records-only PR. Closeout (ADR-0005 D16) archives the brief and leaves `NEXT_UP.md` empty.
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** S1 is shared code. The architect merges it after rerunning its verification. There's no device gate; Jon's next Fit Happens release is the live check.
