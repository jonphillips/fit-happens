# Milestone 3 — Chat access

*Status: **Done** — 2026-11-19. Rules: jon-platform `AGENTS.md` and `docs/ios/`, and this repo's
[decisions](../../decisions/). Where this doc and those conflict, stop and flag it.*

Summary: A chat can read the program, its history, and Jon's walks and body weight, and stage a new
program for review. A `fithappens-mcp` helper reads an export the iPhone writes to iCloud Drive, and
stages proposals into the app's inbox. A staged proposal opens the same review as a paste. A proposal
can now change a lift's working weight, and the review shows every field that Apply changes.

## The milestone in one sentence

In ChatGPT, ask "how has bench gone since September, and should B swap rows for pull-ups?". The chat
calls `get_history` and `get_program`, then `propose_program` with the swap and bench at 150. Open
Fit Happens, tap the badge on Program, review the change, and tap **Apply**.

## Identifiers

The iCloud Documents service on the existing `iCloud.com.jonphillips.fithappens` container (not
published to Files). Helper `fithappens-mcp`, tunnel profile `fithappens`, health port **8084**, inbox
item extension `fhprogram`, export `FitHappensChatExport` v1 (ADR-0006).

## Today

- **The paste path** is `ProgramImportModel` (`FitHappens/ProgramImportModel.swift`): decode, then
  `CurrentProgramQuery.make`, then `ProgramChanges.make`, then the review, then
  `ProgramApplication.apply`. Its error messages live in the app target (`message(for:)`).
- **The review doesn't show increment, label, or notes changes.** Apply overwrites all three for a
  known key, but `ProgramChangeSet` doesn't report them. A review can say "No exercise changes" while a
  lift's step goes from 5 to 2.5 (found in the review of #6).
- **A proposal can't change a known lift's weight.** `startingWeight` on a known key is ignored and
  shown as ignored (ADR-0002 D2 as first written). Stored revisions carry the `startingWeight`s of their
  day, which is why weight changes get their own field rather than a new meaning for that one.
- **Health reads:** `HealthClient` reads walking workouts in a window and only the latest body-mass
  sample (`FitHappensCore/Sources/FitHappensCore/HealthClient.swift`, live value in
  `FitHappens/HealthKitClient.swift`).
- **The container is CloudKit-only** (`project.yml`). There's no Settings screen. Galavant and Yes Chef
  use `ChatAccessKit` for exactly this transport, and `galavant/GalavantMCP` is the nearest working
  model for the helper.

## Slices

- [x] **S1 — Weight changes, and a review that shows everything Apply changes.** ADR-0002 D2 and D3,
  both amended.
  - **Weight changes:** `ProgramExercise` gains an optional `newWeight`. `ProgramChangeSet` gains
    weight changes (key, old → new pounds). Apply sets the working weight in the same transaction. A
    `newWeight` equal to the current weight is no change. On a new key, a bodyweight item, or an item
    whose load kind changes, it's a typed error whose sentence names `startingWeight`. A non-positive
    value is `invalidWeight`. **Re-applying a stored revision ignores its `newWeight`s:** the revision
    path tells `ProgramChanges.make` so, and the review lists them as ignored, next to ignored
    starting weights. `ProgramContractRules.instructions` gains the rule in one or two lines. The
    marker stays `v1`.
  - **Detail changes:** `ProgramChangeSet` reports increment (with the 5 lb default resolved on both
    sides, ADR-0002 D1), load label, and notes for known keys, each old → new.
  - **The review** lists weight and detail changes under Exercises, weight changes first. "No exercise
    changes" shows only when there are none.
  - **Errors in Core:** move the contract and review error messages from
    `ProgramImportModel.message(for:)` into Core as one function, since S3's tool returns the same
    sentences to the chat.
  - Tests: a weight change applied; an equal `newWeight` that isn't a change; each `newWeight` error; a
    revision re-apply that ignores its `newWeight` and leaves the weight alone; each detail change; a
    default-to-explicit 5 lb that isn't a change; no change when only a starting weight differs.
- [x] **S2 — Helper, export, and read tools.** ADR-0006 D1–D3 and D6.
  - **Core, test-first:** `FitHappensChatExport` v1 and a pure builder from rows (`CurrentProgramQuery`
    plus completions and their items): the program with working weights, retired exercises, the
    rotation (ADR-0003's derivation, not a copy of it), 365 days of completions, and the Health part:
    walks (date, miles) and body weight (date, pounds, the latest sample per day) for 365 days. Decoding
    a newer version is a typed error. The `get_history` and `get_activity` projections (window, optional
    key, load-change dates; walks, body weight, latest body weight) are pure functions over the export. `ProgramContractRules.chatServerInstructions`: a 512-character
    opening that stands alone, then `instructions` verbatim.
  - **`FitHappensMCP/`:** a macOS-only package shaped like `GalavantMCP`: a server target, a thin
    `main` that calls `ChatAccessHelperProcess.enableDatalessMaterialization()`, and a test target.
    Server name `fithappens`. Tools `get_program`, `get_history`, and `get_activity`, all read-only, reporting the
    export's age, size-capped, and reading through `ChatAccessExportReader`. No IDs or paths in
    results. `scripts/check-drift.sh` runs the helper's tests, and [verification.md](../../verification.md)
    says so.
  - **The app:** `project.yml` adds `CloudDocuments` and
    `com.apple.developer.ubiquity-container-identifiers`, with no `NSUbiquitousContainers`. It declares
    `ChatAccessKit`. A **Chat Access** section on the Program screen holds the device-local switch (off
    by default), **Refresh**, and the last export's time. The writer runs on background and on Refresh,
    off the main actor, through `ChatAccessExportWriter`, only while the switch is on.
  - **Health:** `HealthClient` gains `bodyMassSamples(start, end)`, with preview and test values; the
    live value is a `HKSampleQueryDescriptor` over body mass, in pounds. The export reads it and
    `walkingWorkouts` when it's written. A failed or empty Health read still writes the export, without
    that part, and `get_activity` then says "Nothing from Health yet" (ADR-0004 D4). No new
    authorization: both types are already read (ADR-0004 D1).
  - **Docs:** `docs/chat-access-setup.md`, indexed in `docs/README.md`, shaped like Galavant's. It
    covers only this app's values (helper path, profile, port 8084, tools) and how to reinstall and
    refresh. The general recipe stays in jon-platform `mcp-access.md`.
  - Tests: the builder against fixture rows (retired exercise, bodyweight, default increment), the
    history and activity projections (several weigh-ins on one day, a walk with no distance, an export
    with no Health part), a newer export version, the 512-character opening, and the helper's tools
    through `MCPServerKit`'s in-memory harness against a temporary container (no export yet, a good
    export, a newer one).
- [x] **S3 — `propose_program` and From Chat.** ADR-0006 D4 and D5.
  - **Core:** one `StagedProgram.check(text, export:)` that the helper uses. It decodes, then runs
    `ProgramChanges.make` against the export's program when there is one, and returns the change set
    or the S1 error sentence. Add a one-line change summary from a `ProgramChangeSet`.
  - **Helper:** `propose_program(text)`, not read-only and not destructive. It stages through
    `HandoffInbox(fileExtension: "fhprogram")` with slug `program`, and returns the summary and "Review
    it in Fit Happens → Program." A failed check writes nothing and returns `isError` with the sentence.
    An unreadable export never blocks.
  - **The app:** a `ChatInboxModel` owned at the app level (so Next Workout can show the badge) holds
    `ChatInboxWatcher`. It's created when the switch turns on and `stop()`ped when it turns off. It
    prepares and maintains on foreground with the `fhprogram` kind (`expiresUnclaimed: true`,
    `datesProcessedByClaim: true`). The Program screen gets a **From Chat** section with a row per file
    (D5). Tapping a row opens the existing review with the staged text. Apply, then claim, then drop
    the row. Backing out leaves it. Discard claims. `alreadyClaimed` drops the row quietly. The Program
    toolbar button on Next Workout shows a badge with the ready count.
  - Tests: `check` against an export (a missing starting weight caught, a `newWeight` on a new key
    caught, a rename passes), with no
    export (shape only), and with a newer marker. The helper stages a good proposal with the expected
    name and bytes, and a bad one writes nothing. The model claims only after a successful apply, a
    failed claim keeps the row, and Discard claims without applying.

## Dispatches

- **Dispatch 1: S1 + S2.** The review fix stands alone and is small. Read tools first, so the first
  proposal a chat stages is built on the real keys.
- **Dispatch 2: S3.**

## Done when

On Jon's iPhone with Chat Access on and the `fithappens` plugin in ChatGPT:
- A new chat with no paste calls `get_program` and names the next workout and today's weights.
- `get_history` reports bench's load changes, and `get_activity` matches the Activity tab's latest
  body weight and recent walks.
- A proposal staged by `propose_program` appears under From Chat with a badge, reviews correctly
  (including a weight change and an increment change), and applies.
- A second proposal is discarded and nothing changes.
- With the Mac asleep, the chat falls back to printing the program, and paste still works.

## Out of scope

Health strength workouts in the export, and any Health type beyond walks and body weight
(ADR-0006 D3). Plugin skills. A Dev variant. A Settings
screen. Scale readings in the inbox (M4, ADR-0005). Any `ChatAccessKit` change, which would stop and
escalate. Moving tunnels between Macs (jon-platform `always-on-mac.md`).
