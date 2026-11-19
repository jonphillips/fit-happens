# Fit Happens docs

The map of every doc in this repo. Nothing is homeless: anything that records a decision, a plan, or a
design is linked from here. This repo runs the jon-platform ADR-0005 document shape: one document per
audience, and GitHub PR state is the only status.

| Doc | Holds | Reader |
| --- | --- | --- |
| [PRODUCT.md](PRODUCT.md) | What the app is, the two screens, the phases, and the non-goals | Everyone, before adding anything |
| [decisions/](decisions/README.md) | Settled choices (ADR-0001 to ADR-0006) | Everyone, before proposing architecture |
| [NEXT_UP.md](NEXT_UP.md) | Exactly one dispatch | **Executor** (its only planning input); architect |
| [milestones/](milestones/README.md) | Live build orders | Architect; executor only via `NEXT_UP.md` |
| [efforts/](efforts/README.md) | Off-arc briefs | Architect; executor only via `NEXT_UP.md` |
| [open-questions.md](open-questions.md) | Decisions owed, things to verify, candidates | Architect and Jon, **never the executor** |
| [verification.md](verification.md) | The standing check pattern | Executor |
| [chat-access-setup.md](chat-access-setup.md) | Fit Happens helper values and refresh steps | Jon |
| [device-passes.md](device-passes.md) | Device-only checks still owed to Jon | Jon; architect |
| [DONE-LOG.md](DONE-LOG.md) | History, newest first | Humans; no dispatch reads it |
