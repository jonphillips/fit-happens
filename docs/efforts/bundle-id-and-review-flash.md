# Effort — Bundle ID and the review flash

Status: Ready
Summary: `project.yml` pins the App ID to `com.jonphillips.fithappens` so XcodeGen stops capitalizing it, and Apply on the Program tab stops flashing "Review unavailable". One small dispatch, then Jon moves the phone to the new ID.

## Why

- **The bundle ID.** M1 chose `com.jonphillips.fithappens`, but XcodeGen builds the ID from
  `bundleIdPrefix` and the target name, so it came out `com.jonphillips.FitHappens`. Any change made
  in Xcode is undone on the next generate. Jon wants the lowercase ID, and before TestFlight is the
  cheapest time to switch: there's no App Store Connect record and no Production schema yet.
  Decision: ADR-0007 D1 (amended 2026-11-20).
- **The flash.** After a successful Apply, `ProgramImportModel.applyReviewedProgram` sets
  `self.review = nil` in the same update that empties `path`. While the review screen pops, it redraws
  with no review and shows its "Review unavailable" placeholder. Found in the review of #21.

## Dispatch 1 — Pin the ID, drop the line

- **`project.yml`:** under the `FitHappens` target, add `settings: base: PRODUCT_BUNDLE_IDENTIFIER:
  com.jonphillips.fithappens`. Leave `bundleIdPrefix` as it is. Change nothing else: the iCloud
  container, the entitlements, and the `iCloud.com.jonphillips.fithappens` references in code are
  already lowercase and stay as they are.
- **`ProgramImportModel.applyReviewedProgram`:** delete `self.review = nil`. Keep the other resets:
  `path`, `programText`, and `stagedURL`. A popped review is reachable only through a new review,
  which replaces it, so the old one can't be applied twice.

**Done when:**
- `scripts/check-drift.sh` passes.
- The simulator build's `Info.plist` has `CFBundleIdentifier` = `com.jonphillips.fithappens`. Check
  it with `plutil -extract CFBundleIdentifier raw` on the built `.app`, and paste the output into the PR.
- Device signing with the new ID can't be checked here, so the PR says so.
- Closeout (ADR-0005 D16). The device gate: Jon's move below, through step 4.

## Then — Jon moves the phone to the new ID

1. **Before installing,** open the old app once with Chat Access on, so the chat export is current.
   It's the record of the program and weights if anything goes wrong.
2. **Install from Xcode.** The new ID installs as a second "Fit Happens", and the old app stays as it
   is.
   - If signing refuses the new ID because the capitalized App ID already exists, stop and tell the
     architect. Don't delete the old App ID in the developer portal: an App ID that's been deleted
     can't be registered again.
3. **Open the new app and wait for sync.** Don't paste or apply a program in it first: a second
   import before sync finishes makes duplicate keys (ADR-0002 Consequences).
   - The program, the current weights, the ramp, the revisions, and the history should all arrive.
   - Grant Health access again, and turn Chat Access back on.
4. **Apply a proposal** from the Program tab, and watch for the flash. It should be gone.
5. **Delete the old app** only once the new one shows everything.

If the new app stays empty, keep using the old one and tell the architect. The fallbacks are
reverting the one `project.yml` line, or making the move after the TestFlight effort's backup and
restore exist.
