# Verification

The standing pattern for every dispatch (jon-platform ADR-0005). Compile and test, then hand off: Jon
reviews on his own device, so **no simulator walkthroughs, installs, screenshots, or taps**. Name any
device-only risk (HealthKit, CloudKit, Bluetooth) in the PR as unverified and stop.

## The gate

**M1 S0 writes this section**: `scripts/check-drift.sh` as the single entry point (SwiftLint, the Core
package's `swift test`, an app build, and jon-platform's `check-handoff`), with every noisy stage run
through `~/code/jon-platform/scripts/quiet-run`. Never paste a raw build log into a PR or chat.

Until then, a dispatch that touches only docs runs `~/code/jon-platform/scripts/check-handoff`.
