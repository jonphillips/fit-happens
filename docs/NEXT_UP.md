# Next Up — TestFlight and Production · Dispatch 2: `build.sh`'s fixture path

**Slices:** TestFlight and Production · Dispatch 2 (S1 in jon-platform, then S2 here)
**Briefs:** docs/efforts/testflight-production.md §Dispatch 2
**Done when:** per the brief. S1: a jon-platform PR changes the `xcodebuild` stub in `scripts/tests/build.sh` to record `pwd -P` instead of `$PWD`, and nothing else. It lists three runs that each print `build checks passed`: direct, `/bin/bash`, and Homebrew `bash`. S2, here: a records-only PR with the `DONE-LOG.md` entry naming both branches and the jon-platform PR, and it empties `NEXT_UP.md`. Closeout (ADR-0005 D16), without archiving the effort: Jon's cutover is still ahead.
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** S1 is shared code, so it escalates to Jon. There's no device gate.
