# Next Up — Bundle ID and the review flash · Dispatch 1

**Slices:** Bundle ID and the review flash · Dispatch 1
**Briefs:** docs/efforts/bundle-id-and-review-flash.md §Dispatch 1; docs/decisions/0007 D1 (amended)
**Done when:** per the brief. `project.yml` sets `PRODUCT_BUNDLE_IDENTIFIER: com.jonphillips.fithappens` on the `FitHappens` target, and the built app's `CFBundleIdentifier` shows it (output pasted in the PR). `applyReviewedProgram` no longer sets `review` to nil. `scripts/check-drift.sh` passes. Device signing is unverified, and the PR says so. Closeout (ADR-0005 D16).
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Two changes only. The iCloud container and its references are already lowercase; don't touch them.
