# Milestone 1 — Core loop

*Status: **Designed** — 2026-11-15. Rules: jon-platform `AGENTS.md` and `docs/ios/`, and this repo's
[decisions](../decisions/). Where this doc and those conflict, stop and flag it.*

Summary: The app is useful without Health: a program arrives by paste, the Next Workout screen shows
it with working weights, one tap completes it and advances the rotation, and corrections work. Data
syncs to iCloud.

## The milestone in one sentence

Paste the program in, open the app, see the next workout at today's weights, tap **Complete**,
and see the other workout come up next, on a CloudKit-synced SQLiteData store.

## Identifiers

Set in S0 and permanent after the first CloudKit write: bundle ID `com.jonphillips.fithappens`,
CloudKit container `iCloud.com.jonphillips.fithappens`, Core package `FitHappensCore`, contract marker
`FH-PROGRAM: v1`. They follow the pattern of Yes Chef and Galavant.

## Slices

- [x] **S0 — Scaffold.** XcodeGen `project.yml`, an iPhone app target, a `FitHappensCore` Swift package,
  SwiftLint, git hooks, and `scripts/check-drift.sh` per jon-platform `drift-control.md`. SQLiteData with CloudSyncKit wired to the private database (ADR-0001
  D2). Fill in [verification.md](../verification.md) with the real gate. An empty launch screen is fine.
- [x] **S1 — Schema and the program contract (Core, no UI).** The tables of ADR-0002 D1 and ADR-0003 D1
  as one migration, following `persistence-and-sync.md`. The `Load` enum. The `FH-PROGRAM: v1` decoder
  with actionable coding-path errors, the rules constant (ADR-0002 D2), and a pure function from
  (current program, proposal) to a **change set**: added, retired, restored, renamed, load-kind
  changes, per-workout membership/prescription/order changes, carried weights, and ignored starting
  weights. Apply = reconcile
  exercises, workouts, and workout items by stable identity, then add a `programRevisions` row in one
  write transaction. Rotation and
  completion as pure functions (ADR-0003 D2, D3). Fixture-driven tests, including a fixture converted
  from the real Markdown program.
- [ ] **S2 — Next Workout.** The launch screen of PRODUCT.md § 1: next workout and last-done date,
  ordered exercises with prescription text, steppers in each exercise's increment that write through
  (ADR-0003 D5), bodyweight rows without a weight, and **Complete Workout**. An empty state when
  there's no program yet, pointing at import.
- [ ] **S3 — Import and review.** A paste sheet, then the review screen for the change set (ADR-0002
  D3), then Apply. A "Copy instructions for ChatGPT" action that copies the rules constant. Revert to
  an earlier revision through the same review.
- [ ] **S4 — History and corrections.** A short list of completions with undo for the latest and a
  date change for any (ADR-0003 D3). Reached from Next Workout, not a tab.

## Dispatches

- **Dispatch 1: S0 + S1.** Scaffold and Core share one mental model and no UI.
- **Dispatch 2: S2 + S4.** The same screen and model.
- **Dispatch 3: S3.**

## Done when

On Jon's iPhone: the real program is imported from a ChatGPT-converted paste, two workouts are
completed in turn with one weight changed between them, an undo and a date change both behave, and the
data appears on a second device signed into the same iCloud account.

## Out of scope

Everything Health (the next milestone), chat access, the scale, iPad layout work, widgets.
