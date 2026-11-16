# Done Log — completed work

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

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
