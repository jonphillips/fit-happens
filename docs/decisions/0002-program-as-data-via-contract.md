# ADR-0002 — The program is data, replaced only through a reviewed contract

*Status: **proposed** — 2026-11-15, ratified by Jon merging the plan PR that adds it. Builds on
jon-platform ADR-0007 (app data over local MCP) and ADR-0009 (`ChatAccessKit`); this app is their
third chat-access consumer after Yes Chef and Galavant.*

Summary: Workouts and exercises live in the database, not in Swift constants. A new program arrives
as a versioned text contract, by paste (M1) or staged by ChatGPT through the chat-access inbox
(later), and one decoder serves both. The app shows what will change; a tap applies it. Exercises
keep their identity across programs through a stable key, so working weights carry over.

## Context

The program today is Markdown in a private GitHub repo. Jon wants to discuss changes with ChatGPT
and have ChatGPT push the new routine to the app (2026-11-15). Bundled constants would mean a code
change and a release for every program change.

## Decision

### D1 — Schema

- `exercises`: id, **key** (a stable, readable slug such as `flat-bench-press`), name, load kind,
  current load, increment, an optional load label ("each"), optional notes, retired flag.
- `workouts`: id, key (`A`, `B`, …), position.
- `workoutItems`: id, workout, exercise, position, prescription text.
- `programRevisions`: id, accepted-at, and the full accepted contract text, written once and never
  edited.

The load is a Swift enum (`weight(pounds)`, `bodyweight`), however it's stored, so a bodyweight
exercise can't carry a weight. Working weight is **per exercise**: the same lift is the same weight in
every workout, and a real variant is a different key. The prescription is display text; nothing
computes on it. Add a duration load kind only when an exercise needs it.

The increment is optional and defaults to **5 lb** when absent: one named Core constant, applied
wherever a stepper reads an exercise's increment, never written back to the row. *Amended
2026-11-16, from the review of #3:* the real program left every weighted lift without an increment,
so the steppers had nothing to step by. A default keeps the real program importable as-is; a lift
that moves by something else says so in the contract.

*Amended 2026-11-20, Jon's call:* **a weighted item may be a ramp**, such as 10 reps at 155, 8 at
165, then 6 at 175. `workoutItems` gains an optional `ramp`: an ordered list of steps, each with reps
as text ("10", "8–10") and an offset in pounds from the working weight. The **working weight is the
heaviest step**, so at least one offset is 0 and none is above it. The app shows each step as working
weight + offset ("10 @ 155 · 8 @ 165 · 6 @ 175"). The stepper still moves the one working weight,
and the whole ramp moves with it. A step that would come out below 0 shows 0.
This is the one computation on a prescription, and it's arithmetic on the working weight, not
progression advice. The rest of D1 holds:

- **One weight per exercise.** An exercise ramped in one workout and done straight in another uses
  the same working weight in both. If they really differ, it's a different key.
- **Offsets, not percentages, and not one weight per set.** Jon's jumps are flat pounds, and
  percentages would need plate rounding. A weight per set would need a stepper per set, and it would
  drift out of step with the one working weight that history and Activity's progression line read.
- **One resolver.** Core turns an item into its display prescription in one place: the ramp written
  out against the current working weight, or else the prescription text. The overview, the Program
  tab, the completion snapshot (ADR-0003), and the chat export all read it, and nothing reads the
  stored text of a ramped item directly.
- The ramp is stored as JSON text in its column, since nothing queries it (jon-platform
  `persistence-and-sync.md`). The column is additive, so the CloudKit schema gains one field.

### D2 — The contract

A versioned block with a `HandoffContractMarker` (LLMHandoffKit), using the marker line
`FH-PROGRAM: v1`, carrying the whole program: workouts in order, each with its items. Each item names an exercise by
key, with its name, prescription, load kind, and optional increment (5 lb when omitted, D1), label,
and notes. Rules:

- **A known key is the same lift.** A new name is a rename, and the working weight carries over.
  A retired key that returns is restored and keeps its previous weight.
- **An unknown key is a new exercise** and must carry a starting weight if it's weighted.
- **Starting weights only.** For a known key whose load kind is unchanged, active or restored, a
  starting weight is ignored and the working weight carries over; the review shows it as ignored.
  A load-kind change to `weight` requires a starting weight; a change to `bodyweight` has no weight.
- *Amended 2026-11-19, Jon's call, with ADR-0006:* **a proposal may change a working weight.** An
  item for a known key that's weighted before and after may carry `newWeight`. The review shows it as
  old → new, and Apply sets it. A value equal to the current weight is no change. `newWeight` on a new
  key, a bodyweight item, or a load-kind change is an error that points to `startingWeight`.
  `startingWeight` keeps its meaning, so every stored contract still means what it meant, and
  **re-applying a stored revision ignores its `newWeight`s** (shown as ignored), so going back to an
  earlier program never rolls weights back. The marker stays `v1`: the field is additive, and the
  only readers are this app and its helper, built from the same Core. The app still computes no
  progression; a chat proposes and Jon approves.
- *Amended 2026-11-20:* **an item may carry `ramp`** instead of a prescription (D1):
  `"ramp": [{"reps": "10", "offset": -20}, {"reps": "8", "offset": -10}, {"reps": "6", "offset": 0}]`.
  With a ramp, `prescription` may be left out. If it's there, it's ignored without comment.
  *(Revised 2026-11-20, from the review of #23: `get_program` gives a ramped item its written-out
  text as `prescription`, so a chat that echoes the program back sends that text with every
  proposal. Flagging each one would fill the review with notes about proposals that change nothing.
  The ramp itself still shows in the review whenever it changes.)* A ramp needs at least two steps, non-empty reps, finite
  offsets, at least one offset of 0, and none above 0. It's an error on a bodyweight item. Like
  `newWeight`, the field is additive, so the marker stays `v1`. A stored contract without ramps
  still means what it meant. In the review, a ramp that's added, removed, or changed is a prescription
  change, written in relative form ("10 @ −20 · 8 @ −10 · 6 @ top"), since the same proposal may move
  the weight. `get_program` gives a ramped item both its `ramp` and the written-out prescription, so a
  chat that echoes the program back keeps the ramp (ADR-0006 D3).
- **A key that disappears retires the exercise.** It stays in history and is never deleted.
- Workouts and `workoutItems` are current-program rows. Apply deletes a workout or item that the
  accepted contract removes; completion snapshots and `programRevisions` remain independent.
- Any number of workouts is allowed; rotation follows program order (ADR-0003).

The rules live in one Core constant, used for ChatGPT Project instructions (paste path) and for the
MCP server's `instructions` (jon-platform ADR-0007 D6).

### D3 — Review, then apply

Every proposal, pasted or staged, opens the same review: exercises added, retired, and renamed,
prescriptions changed, workouts reordered, and which weights carry over. **Apply** is the only write.
It reconciles in one write transaction: upserts exercises and workouts by stable key, retires missing
exercises, deletes removed current workouts/items, and stores the contract as a new
`programRevisions` row. Completion snapshots do not reference current-program rows. Going back to an earlier program re-applies its stored contract through
the same review.

*Amended 2026-11-19, with ADR-0006:* the review also lists increment, load-label, and notes changes
for known keys. Apply already overwrote them, so a review could say "No exercise changes" while a
lift's step changed. That matters more once a chat stages proposals Jon didn't type.

### D4 — Two ways in, one decoder

- **Paste** (M1): also how the first program arrives. ChatGPT converts the Markdown into the
  contract.
- **Chat access** (later): the iPhone app writes a small export (the current program with keys,
  current weights, recent completions) to its iCloud Drive container. A Mac helper built on
  MCPServerKit and ChatAccessKit offers read tools on it and a `propose_program` tool that validates
  with the same decoder and stages the contract into the inbox. The app shows staged proposals and
  opens them in the review. Health data stays out of the export (jon-platform ADR-0007 D5) unless
  Jon adds it on purpose.

## Consequences

- The Markdown repo is retired as the source of truth after the first import.
- Key uniqueness can't be a database constraint under CloudKit. The importer looks up by key, and M1
  decides how a duplicate (two devices applying at once) resolves, per `persistence-and-sync.md`.
- The review screen is justified because it's the only way to change the program. (Since 2026-11-20 it's reached from the Program tab, PRODUCT.md.)
