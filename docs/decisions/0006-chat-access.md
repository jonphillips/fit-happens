# ADR-0006 — Chat access: read the program, stage proposals into the review

*Status: **proposed** — 2026-11-19, ratified by Jon merging the plan PR that adds it. Milestone:
[M3](../milestones/M3-chat-access.md). Carries out [ADR-0002](0002-program-as-data-via-contract.md) D4
on jon-platform ADR-0007 (with its Amendment 1) and ADR-0009 (`ChatAccessKit`). Fit Happens is the
third app on the iCloud Drive transport, after Yes Chef and Galavant.*

Summary: A local `fithappens-mcp` helper gives a ChatGPT or Claude chat two read tools and one write
tool. `get_program` and `get_history` read an export the iPhone writes to iCloud Drive.
`propose_program` checks a program contract with the app's own code and stages it into the inbox. The
Program screen lists staged proposals, and tapping one opens the review that a paste opens. **Apply**
is still the only write.

## Context

Jon talks through the program with ChatGPT. Today the chat knows the program only from what he pastes
or remembers, and the app has no way to hand it the exercise keys. A proposal that guesses keys can't
go through quietly: a renamed key retires the lift and adds a "new" one that needs a starting weight,
and the review shows that. But it costs a round trip every time. The return trip also means copying
from the chat and pasting into the app.

ADR-0002 D4 already chose the shape: an export, read tools, `propose_program`, and the inbox. Yes
Chef's and Galavant's device passes taught lessons this app gets without paying for them again. Models
skip a tool unless the instructions say to call it. Models drop the contract line. The Mac evicts
container files. One chat can stage more than once. And a chat should be able to start in the
assistant and pull what it needs through tools. This ADR records the choices that are Fit Happens'
own.

## Decision

### D1 — A standalone helper, built from Core

A macOS-only `FitHappensMCP/` package depends on `FitHappensCore`, `MCPServerKit`, `ChatAccessKit`,
and `LLMHandoffKit`. It stays out of the package graph the iOS app resolves. `install-mcp-helper`
installs it to `~/.local/bin/fithappens-mcp`. It runs under a `fithappens` tunnel profile on health
port **8084** (Vinyl Fever has 8080, Yes Chef 8081, Galavant 8082, Yes Chef Dev 8083), on whichever
Mac is the chat host (jon-platform `mcp-access.md`). The helper never opens the database.

**One variant.** Fit Happens has no Dev build, so every caller passes `isDevelopment: false`, and the
helper takes no `--variant`. If a Dev variant ever ships, it uses `MCP-Dev/` (ADR-0009 D2).

### D2 — The transport is the app's iCloud Drive container

The existing `iCloud.com.jonphillips.fithappens` container gains the iCloud Documents service. It
isn't published to Files. `MCP/Inbox/` holds staged proposals, `MCP/Inbox/Processed/` holds claimed
ones for 30 days, and `MCP/Exports/` holds one export file per device. All of it goes through
`ChatAccessKit`; nothing is copied from Yes Chef or Galavant.

**A device-local Chat Access switch on the Program screen gates it,** and it's off by default. When
it's off, the app resolves no container, runs no watcher, and writes no export. The app has no
Settings screen, and the Program screen is where the program changes, so the switch goes there.
Later, the scale's readings (ADR-0005 D3) share the container and the watcher as their own item kind.
The switch gates only chat access, and M4 decides how readings are gated.

### D3 — Two read tools, from a derived export

- **`get_program`:** workouts in order. Each item gives the exercise key, name, prescription, load
  kind, **working weight**, increment, load label, and notes. Retired exercises give key, name, and
  last working weight, so a chat can restore one by key. The rotation gives the next workout's key and
  the last completion's date and key. The weight field is named `workingWeight`, not `startingWeight`,
  so a chat that copies it back doesn't produce a contract field. The rules already say a starting
  weight on a known key is ignored.
- **`get_history(days, exercise?)`:** completions in the window (default 90 days, at most 365): the
  date, the workout key, and each item's key and snapshot load. With `exercise`, only that key. For
  each key, it also lists the dates its snapshot load changed. That's the progression a chat
  deliberates over, and it's what ADR-0003 snapshots record: prescribed, not performed.
- **The export, version 1** (`FitHappensChatExport`, in Core): `generatedAt`, a device label, the
  program as above, and completions from the last 365 days. It holds no row IDs (keys are enough), no
  file paths, and **no Health data**. Health is read, never mirrored (ADR-0004), and an export file
  in iCloud Drive would be a copy. A newer version is a typed error, as ADR-0007 D2 requires.
- **Written** on background and from a **Refresh** button beside the switch, through
  `ChatAccessExportWriter`, throttled to one per 15 minutes. Results report the export's age and are
  size-capped. "No export yet" tells Jon to open Fit Happens and tap Refresh.

### D4 — One write tool; the helper runs the review's checks before staging

`propose_program(text)`:

- **`text`** is exactly what the chat would otherwise print for pasting.
- **The checks are the review's, from the same Core code.** First the decoder: a newer marker is an
  error, and a missing or older one is silent at this door. When the export reads successfully, it
  then runs `ProgramChanges.make` against the export's program. That catches what only the current
  program can show: a new weighted key without a starting weight, or a load-kind change without one.
  A missing, unreadable, timed-out, or newer-format export never blocks staging, because the app runs
  the full review against the live database anyway.
- **One error text.** A failed check returns `isError` with the same sentence the review shows. The
  messages move from `ProgramImportModel` into Core so the helper and the app can't drift.
- **The file:** `HandoffInbox(root: …/MCP/Inbox, fileExtension: "fhprogram")`, slug `program`, with
  the text unchanged.
- **Annotations:** not read-only, not destructive, so ChatGPT asks first. That's the second
  checkpoint (ADR-0007 D3).
- **The result** says where it went. With the export, it's a one-line change summary ("2 added,
  1 retired, 3 prescription changes"); without it, just that it was staged. Either way it ends with
  "Review it in Fit Happens → Program." The chat says that, not "saved" or "applied".

### D5 — Staged proposals open the existing review

- **A From Chat section on the Program screen** lists every staged file, newest first: when it was
  staged, and "Downloading…" or the download error while the file isn't current. The newest is
  labelled. The Program button on Next Workout shows a badge with the count of ready rows.
- **The tap opens the same review as Paste,** with the staged text. ADR-0002 D3 is unchanged: Apply
  reconciles in one transaction and writes a `programRevisions` row. **Apply, then claim.** If the
  claim fails, the row stays with its error. Applying it again changes nothing and writes another
  revision row, which is harmless.
- **Backing out of the review leaves the row.** **Discard** claims the file and writes nothing.
  `alreadyClaimed` (another device took it) drops the row quietly.
- **No superseding.** Every proposal is a whole program, reviewed against the live one, so an older
  row is still correct to review. Two chats can each stage one, and keeping only the newest could
  lose one unseen (Yes Chef ADR-0061).

### D6 — The contract travels with the server; paste stays the fallback

`ProgramContractRules.chatServerInstructions` has an opening whose first 512 characters stand alone.
It says: start with `get_program` and reuse its keys; propose with `propose_program` rather than
printing the program; if the tool fails or times out, print the program with its `FH-PROGRAM: v1`
line for pasting. Then comes `ProgramContractRules.instructions` verbatim. The contract and its marker
don't change. Paste and **Copy instructions for ChatGPT** stay as they are.

### D7 — What's shared

| Shared | Where |
| --- | --- |
| Container paths, watcher, claim, retention, export read and write, dataless reads | `ChatAccessKit` |
| Protocol loop and tool registry | `MCPServerKit` |
| Inbox files and the contract marker | `LLMHandoffKit` |
| Tunnel ops and helper install | `scripts/mcp-tunnel`, `scripts/install-mcp-helper` |

**Fit Happens' own:** the tools, the export's shape and builder, the checks, the rows, and the switch.
No kit change is expected. If one turns out to be needed, it's shared code, so it escalates to Jon
(jon-platform `agent-collaboration.md`).

## Consequences

- A chat can start in ChatGPT, read the program with its keys, and stage a proposal. Neither crossing
  needs copying.
- Using it from ChatGPT on any device needs the chat-host Mac awake with the tunnel running. Without
  that, paste works as it does today.
- iCloud Drive adds a delay of a few seconds between staging and the row.
- New ops: one Platform tunnel, one profile, one login agent, and one ChatGPT plugin. The App ID may
  need iCloud Documents turned on by hand the first time it's signed with the entitlement.
- The CloudDocuments entitlement and the watcher are also what the scale needs (ADR-0005 D3), so M4
  starts with the transport in place.

## Alternatives considered

| Option | Verdict |
| --- | --- |
| **Propose only, with no read tools** | Rejected: a chat that can't see the keys proposes renames as retire-and-add, and the round trip is the cost this milestone removes. |
| **Read the database from the helper** | Rejected: ADR-0007 Amendment 1. The app has no Mac presence, and the database lives on the phone. |
| **Typed program fields in the tool schema** | Rejected: a second shape beside the contract. The text form has one decoder, and its errors go back to the chat. |
| **Auto-apply staged proposals** | Rejected: ADR-0002 D3 and ADR-0007 D3. The tap in the app is the only write. |
| **Keep only the newest proposal** | Rejected: D5. |
| **Include body weight and walks in the export** | Out for now: ADR-0004 says Health isn't mirrored. Jon can add it on purpose ([open questions](../open-questions.md)). |
| **A Settings screen for the switch** | Rejected: a fourth screen for one toggle. The Program screen already owns everything chat can change. |
