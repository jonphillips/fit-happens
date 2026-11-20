# Decisions

Settled choices for Fit Happens, one line each. House-wide decisions live in jon-platform
`docs/adr/`; these hold only what's this app's own.

- [ADR-0001](0001-house-stack-and-sync.md) — House stack, with CloudKit sync from day one.
- [ADR-0002](0002-program-as-data-via-contract.md) — The program is data, replaced only through a reviewed contract (paste or chat access); an item may be a ramp off the working weight.
- [ADR-0003](0003-completion-snapshots-and-rotation.md) — Completions snapshot the prescription as rows; rotation is derived.
- [ADR-0004](0004-healthkit-reads-and-workout-linking.md) — Narrow HealthKit reads; link the Watch workout instead of starting one.
- [ADR-0006](0006-chat-access.md) — Chat access: read tools over an export, and `propose_program` staging into the review.
- [ADR-0005](0005-scale-readings-through-the-mini.md) — Scale readings via a Mac listener, the iCloud Drive inbox, and Jon's weight band.
- [ADR-0007](0007-testflight-and-production.md) — TestFlight from the mini, and the move to CloudKit Production by backup and restore.
