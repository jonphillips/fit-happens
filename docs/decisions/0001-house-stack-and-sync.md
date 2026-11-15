# ADR-0001 — House stack, with CloudKit sync from day one

*Status: **proposed** — 2026-11-15, ratified by Jon merging the plan PR that adds it.*

Summary: Fit Happens is built on the jon-platform house stack with no exceptions: SwiftUI,
SQLiteData + CloudKit through CloudSyncKit, swift-dependencies, `@Observable` models, XcodeGen.
Sync is on from M1, even though there is one user and one iPhone.

## Context

The source brief proposed SwiftData and asked whether iCloud sync was worth it for a single-user,
single-iPhone app. Jon wants every app on the same stack (2026-11-15).

## Decision

### D1 — The stack

- SwiftUI, iPhone first. iPad runs whatever SwiftUI gives for free; it isn't a design target.
- SQLiteData for persistence and observation; reads through `@FetchAll` / `@FetchOne` / `@Fetch`.
  Not SwiftData.
- `@Observable` feature models with one `Destination` enum each; swift-navigation; no TCA.
- Everything with side effects is a `@Dependency` client: the database, date, UUID, HealthKit
  (ADR-0004), and the chat-access container (ADR-0002, ADR-0005).
- XcodeGen `project.yml`, SwiftLint, and git hooks per jon-platform `drift-control.md`. Domain logic
  lives in a Core Swift package so the MCP helper (ADR-0002) and the Mac listener (ADR-0005) build
  from the same code.

### D2 — CloudKit sync on, from M1

Private database only, through CloudSyncKit. No sharing. Reasons:

- It's the house default, and CloudSyncKit makes it cheap.
- History lives somewhere other than one phone.
- It costs almost nothing to follow the sharing laws in `persistence-and-sync.md` with a handful of
  tables, and a lot to retrofit them.

The schema follows those laws from the first slice: UUID primary keys, no unique constraints the
sync engine can't honor, edits that preserve row identity. Adopt CloudSyncKit's sync-health surface
and scheduled backups (jon-platform ADR-0008) as far as the kit provides them, not more.

### D3 — No AI boundary inside the app

The app makes no model calls, so it has no `ModelClient`. Program deliberation happens in ChatGPT
and comes back through the contract (ADR-0002).

## Consequences

- One more CloudKit container to promote to Production before TestFlight.
- The Mac listener (ADR-0005) doesn't need the sync engine; it only writes files.
