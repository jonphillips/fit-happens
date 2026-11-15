# Verification

The standing pattern for every dispatch (jon-platform ADR-0005). Compile and test, then hand off: Jon
reviews on his own device, so **no simulator walkthroughs, installs, screenshots, or taps**. Name any
device-only risk (HealthKit, CloudKit, Bluetooth) in the PR as unverified and stop.

## The gate

Use `scripts/check-drift.sh` as the single local entry point. It runs, in order:

1. `xcodegen generate --quiet`.
2. Strict SwiftLint through `~/code/jon-platform/scripts/quiet-run`.
3. The Core package tests through `quiet-run`.
4. Xcode package resolution, then the pinned iOS Simulator build with macro validation skipped and
   build caches under `.build/`.
5. `~/code/jon-platform/scripts/check-handoff`.

For a fast first pass, run a focused test before the full suite, for example:

```sh
~/code/jon-platform/scripts/quiet-run swift test --package-path FitHappensCore --filter ProgramContractTests
```

The full package command is:

```sh
~/code/jon-platform/scripts/quiet-run swift test --package-path FitHappensCore
```

Never paste a raw build log into a PR or chat. `quiet-run` retains it and reports the log path.

## CI

The GitHub Actions caller is intended to use Jon's `jonphillips/ci-workflows` reusable iOS workflow
with `package-path: FitHappensCore`. It needs the repository's read-only `JON_PLATFORM_PAT` secret to
clone the private `jon-platform` checkout for local Swift package dependencies. Jon adds that secret;
it is not stored in this repository. The hosted runner gate must skip green until its Swift toolchain
and SDK can build the iOS/macOS 27 package manifest, then run automatically when supported.
