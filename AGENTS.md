# Fit Happens

A private, deliberately small iPhone app for one person: the next workout in an A/B (or A/B/C…) rotation,
current working weights, and one tap to record it done. A read-only Activity view adds walks and
body weight from Apple Health. A headless Mac listener on the always-on mini feeds Bluetooth scale
readings into Health. The aim is a **finished** app, not a platform. [docs/PRODUCT.md](docs/PRODUCT.md)
has the scope and the non-goals; read them before adding anything.

## Working mode: architect / executor

Claude = architect (docs, ADRs, milestones, reviews; **no feature code**). Codex = executor (builds
`docs/NEXT_UP.md`, one branch + PR per dispatch). Routing for a bare "go" is in jon-platform
`AGENTS.md`; the protocol is `jon-platform/docs/agent-collaboration.md` and ADR-0005. Jon approves
plans by merging plan PRs.

## Read first

1. `/Users/jon/code/jon-platform/AGENTS.md`: the house stack and rules. This repo holds only the
   workout domain.
2. [docs/README.md](docs/README.md): the map of this repo's docs.
3. [docs/decisions/](docs/decisions/): settled choices. Don't re-litigate them quietly; argue in the open.
4. [docs/NEXT_UP.md](docs/NEXT_UP.md): the one dispatch (executor: your only planning input; empty →
   stop and ask). Verification: [docs/verification.md](docs/verification.md).

## What's this app's own

- **The program is data, not code.** It arrives only through the program contract (ADR-0002), by
  paste or by the chat-access inbox, and a human tap applies it.
- **History snapshots what was prescribed**, not what was performed (ADR-0003).
- **Health is read, never mirrored.** The one write is body mass from the scale (ADR-0004, ADR-0005).
- **No AI inside the app.** Deliberation about the program happens in ChatGPT; the app stays dumb.
- Units are pounds, app-wide.
