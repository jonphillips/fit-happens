# Verification

The standing pattern for every dispatch (jon-platform ADR-0005). Compile and test, then hand off: Jon
reviews on his own device, so **no simulator walkthroughs, installs, screenshots, or taps**. Name any
device-only risk (HealthKit, CloudKit, Bluetooth) in the PR as unverified and stop.

## The gate

Use `scripts/check-drift.sh` as the single local entry point. It runs, in order:

1. `xcodegen generate --quiet`.
2. Strict SwiftLint through `~/code/jon-platform/scripts/quiet-run`.
3. The Core package tests through `quiet-run`.
4. The `FitHappensMCP` helper tests through `quiet-run`.
5. The `FitHappensInboxKit` model tests through `quiet-run`.
6. Xcode package resolution, then the pinned iOS Simulator build with macro validation skipped and
   build caches under `.build/`.
7. `~/code/jon-platform/scripts/check-handoff`.

`FitHappensInboxKit` owns the injectable inbox model so its apply/claim/discard behavior and watcher
lifecycle tests run with SwiftPM on macOS, without booting a simulator.

For a fast first pass, run a focused test before the full suite, for example:

```sh
~/code/jon-platform/scripts/quiet-run swift test --package-path FitHappensCore --filter ProgramContractTests
```

The full package command is:

```sh
~/code/jon-platform/scripts/quiet-run swift test --package-path FitHappensCore
```

The helper's tests are:

```sh
~/code/jon-platform/scripts/quiet-run swift test --package-path FitHappensMCP
```

The inbox model tests are:

```sh
~/code/jon-platform/scripts/quiet-run swift test --package-path FitHappensInboxKit
```

Never paste a raw build log into a PR or chat. `quiet-run` retains it and reports the log path.

## CI

`.github/workflows/ci.yml` calls Jon's `jonphillips/ci-workflows` reusable iOS workflow with
`package-path: FitHappensCore`. It inherits repository secrets so the test job can clone private
`jon-platform` for local Swift package dependencies with the read-only `JON_PLATFORM_PAT`. That
secret is configured in the GitHub repository and is not stored here.

The caller pins `macos-26` and sets a Swift 6.4 floor. The reusable workflow skips the test job green
when the hosted runner has an older toolchain; it runs automatically once the runner can build the
iOS/macOS 27 package manifest. The local full gate remains the verification path until then.
