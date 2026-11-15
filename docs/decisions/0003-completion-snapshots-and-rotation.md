# ADR-0003 — Completions snapshot the prescription; rotation is derived

*Status: **proposed** — 2026-11-15, ratified by Jon merging the plan PR that adds it.*

Summary: Completing a workout writes a completion row plus one row per exercise, copying name,
prescription, and load at that moment. Nothing about history depends on the current program. The
next workout is computed from the latest completion, never stored.

## Decision

### D1 — Snapshot as rows, not a blob

- `completions`: id, workout key, completed-at, and an optional linked Health workout UUID (ADR-0004).
- `completionItems`: id, completion, exercise, position, and the name, prescription, load kind, and
  load as they were.

Rows, because the Activity view queries weight by exercise over time (jon-platform
`persistence-and-sync.md`: a blob only for what's never queried). Editing a working weight or
applying a new program never touches past rows.

### D2 — Rotation is derived

The next workout is the one after the latest completion's workout, in the current program's order,
wrapping around; with no completions, the first. There's no stored "next" state to fall out of sync.
If the latest completion's workout no longer exists, start from the first.

### D3 — Corrections

- **Undo** deletes the latest completion and its items; the rotation goes back by itself. Weights
  Jon changed before completing stay as they are.
- **Change date** edits completed-at ("did it yesterday"). Forgetting to tap is likelier than an
  accidental tap, so this matters more than undo.
- A short history list is the surface for both. It isn't a log browser.

### D4 — The honest ceiling

History records what was **prescribed**, not what was performed. Skipping an exercise or doing fewer
sets isn't captured, by design. If that's ever needed, it's a new decision, not a quiet field.

### D5 — Weight edits write through

Changing a stepper writes the exercise's current load immediately, so it survives closing the app and
is the default next time. Completion copies whatever is current.
