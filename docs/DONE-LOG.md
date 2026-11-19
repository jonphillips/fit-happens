# Done Log — completed work

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-19 — M2 Dispatch 2: Activity (`m2/s3-activity`)

- **Result:** Added the Activity tab with a four-week strength and walking calendar, daily walk distances, latest body weight, and selectable progression from completion snapshots.
- **Verification:** scripts/check-drift.sh passed: strict SwiftLint, all 37 Core tests, package resolution, iOS Simulator build, and strict handoff check.
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
