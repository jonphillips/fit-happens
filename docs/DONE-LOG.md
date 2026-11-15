# Done Log — completed work

History, newest first. The PR that completes a dispatch adds its entry naming its branch
(jon-platform ADR-0005 D5). No dispatch reads this file.

## 2026-11-15 — M1 Dispatch 1: scaffold and Core program application (`m1/s0-scaffold`)

- **Result:** Added the iOS scaffold, synced schema, versioned program decoder and change set, atomic program reconciliation with revision history, and reusable CI caller.
- **Verification:** scripts/check-drift.sh passed strict SwiftLint, 22 Core tests, package resolution, and the iOS Simulator build; closeout runs check-handoff --strict.
- **Owed:** M1 S0, M1 S1's device gate, in [device-passes.md](device-passes.md).
