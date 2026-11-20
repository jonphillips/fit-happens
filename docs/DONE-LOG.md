# Done Log — completed work

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-20 — Bundle ID and the review flash (`effort/bundle-id-and-review-flash`)

- **Result:** Pinned the app bundle ID to com.jonphillips.fithappens and kept the reviewed program visible while the review route pops.
- **Verification:** scripts/check-drift.sh passed; simulator CFBundleIdentifier: com.jonphillips.fithappens.
- **Owed:** Bundle ID and the review flash Dispatch 1's device gate, in [device-passes.md](device-passes.md).

## 2026-11-20 — Tabs and ramps Dispatch 2: Ramped sets (`effort/ramped-sets`)

- **Result:** Added ramp contracts, additive workout item storage, one resolver across workout and program displays, completion snapshots, and chat export; added MCP ramp read and proposal support.
- **Verification:** scripts/check-drift.sh passed: strict SwiftLint, 69 Core tests, 9 FitHappensMCP tests, 1 FitHappensInboxKit test, package resolution, pinned iOS Simulator build, and check-handoff --strict.
- **Owed:** Tabs and ramps Dispatch 2's device gate, in [device-passes.md](device-passes.md).

## 2026-11-20 — Three tabs (`effort/three-tabs`)

- **Result:** Added the Next Workout, Activity, and Program tabs; moved corrections into a shared model; projected the full program; and moved Chat Access export ownership to the app root.
- **Verification:** scripts/check-drift.sh passed: SwiftLint, Core and helper tests, package resolution, and iOS Simulator build.
- **Owed:** Tabs and ramps Dispatch 1's device gate, in [device-passes.md](device-passes.md).

## 2026-11-19 — M3 Dispatch 2: Stage proposals in the review (`m3/s3-stage-proposals`)

- **Result:** Added propose_program validation and staging, plus the app inbox review, apply and discard claim flows, watcher lifecycle, and ready-count badge.
- **Verification:** scripts/check-drift.sh passed: strict SwiftLint, 58 Core tests, 8 FitHappensMCP tests, 1 FitHappensInboxKit test, pinned iOS Simulator build, and check-handoff --strict.
- **Owed:** M3 S3's device gate, in [device-passes.md](device-passes.md).

## 2026-11-19 — M3 · S1 + S2 device pass (`records/m3-d1-device-pass`)

- **Result:** Passed on Jon's iPhone. With Chat Access on and refreshed, the helper's `get_program`,
  `get_history`, and `get_activity` matched Next Workout (next workout A, every working weight), History
  (the last 90 days of completions), and Activity (the week's walks and the latest body weight) — called over
  stdio on the Mac, since the `fithappens` tunnel isn't set up yet. Also adds `DEVELOPMENT_TEAM` to
  `project.yml`: without it, every `xcodegen generate` dropped the signing team and device builds failed
  to register the bundle ID.
- **Verification:** Jon compared the three reads against the phone. After `xcodegen generate`, the project keeps
  `DEVELOPMENT_TEAM`, and Jon's device build signed with it.

## 2026-11-19 — M3 Dispatch 1: Review fidelity and read tools (`m3/s1-review-fidelity-read-tools`)

- **Result:** Added deliberate working-weight proposals, a complete exercise review, Core-owned contract errors, and the v1 iCloud export with three read tools.
- **Verification:** Strict SwiftLint; 54 Core tests; 6 FitHappensMCP tests; pinned iOS Simulator build; strict handoff check.
- **Owed:** M3 S1, M3 S2's device gate, in [device-passes.md](device-passes.md).

## 2026-11-19 — M1 · S2 + S4 and M2 · S1–S3 device passes

- **Result:** Passed on Jon's iPhone. **M2 S1 + S2:** Health read access granted; the app offered a
  finished Watch strength workout and recorded it at the workout's end; a declined offer stayed hidden.
  **M2 S3:** the Activity tab's calendar, walk distances, latest body weight, and progression line
  matched Health. **M1 S2 + S4:** weight steps, completion and rotation, undo confirmation, and date
  correction work, including the list-row buttons effort that folded into this gate. M2's done-when
  is met. M1 S3 (program paste, revisions, and second-device sync) is still owed.

## 2026-11-19 — M2 Dispatch 2: Activity (`m2/s3-activity`)

- **Result:** Added the Activity tab with a four-week strength and walking calendar, daily walk distances, latest body weight, and selectable progression from completion snapshots.
- **Verification:** scripts/check-drift.sh passed: strict SwiftLint, all 43 Core tests, package resolution, iOS Simulator build, and strict handoff check.
- **Owed:** M2 S3's device gate, in [device-passes.md](device-passes.md).

## 2026-11-19 — List-row buttons (`effort/list-row-buttons`)

- **Result:** Weight controls now have independent 44-point targets; History actions use borderless buttons; `project.yml` declares the shared app scheme.
- **Verification:** `scripts/check-drift.sh` passed unchanged, including SwiftLint, all 35 Core tests, the iOS app build, and `check-handoff --strict`.

## 2026-11-16 — Health access and Watch workout linking (`m2/s1-health-workout-linking`)

- **Result:** Added HealthKit read access, an injectable HealthClient, recent Watch workout matching, and the offer to link an eligible workout to a completion.
- **Verification:** scripts/check-drift.sh passed: 29 Core tests, strict SwiftLint, and the iOS Simulator build.
- **Owed:** M2 S1, M2 S2's device gate, in [device-passes.md](device-passes.md).

## 2026-11-16 — M1 S3 — Program import and review (`m1/s3-program-import-review`)

- **Result:** Added paste import, a review of proposed program changes, ChatGPT instructions copying, and review-based reapplication of accepted revisions.
- **Verification:** scripts/check-drift.sh passed strict SwiftLint, all 29 Core tests, package resolution, the iOS Simulator build, and strict handoff closeout.
- **Owed:** M1 S3's device gate, in [device-passes.md](device-passes.md).

## 2026-11-16 — M1 S2 + S4 — Next Workout and history (`m1/s2-next-workout`)

- **Result:** Added the Next Workout surface, transactional completion and weight stepping, rotation, short editable history, date correction, and undo confirmation. Unified canonical program projection so history snapshots retain the prescribed values.
- **Verification:** scripts/check-drift.sh passed strict SwiftLint, all 29 Core tests, package resolution, the iOS Simulator build, and the handoff hygiene check.
- **Owed:** M1 S2, M1 S4's device gate, in [device-passes.md](device-passes.md).

## 2026-11-15 — M1 Dispatch 1: scaffold and Core program application (`m1/s0-scaffold`)

- **Result:** Added the iOS scaffold, synced schema, versioned program decoder and change set, atomic program reconciliation with revision history, deterministic duplicate convergence, and reusable CI caller.
- **Verification:** scripts/check-drift.sh passed strict SwiftLint, 24 Core tests, package resolution, the iOS Simulator build, and strict handoff closeout.
- **Owed:** none. Second-device sync is checked in M1's done-when, once S3 can accept a program.
