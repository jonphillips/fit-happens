# Next Up — M3 Dispatch 1: Review fidelity and read tools

**Slices:** M3 · S1, M3 · S2
**Briefs:** docs/milestones/M3-chat-access.md §S1, §S2; docs/decisions/0006; docs/decisions/0002 D3 (amended)
**Done when:** per the briefs. The review lists increment, load-label, and notes changes, and the contract errors live in Core. A `FitHappensMCP` helper serves `get_program` and `get_history` from a `FitHappensChatExport` v1 that the app writes while the Program screen's Chat Access switch is on. `scripts/check-drift.sh` runs the helper's tests and passes. `docs/chat-access-setup.md` exists. No simulator walkthrough; closeout (ADR-0005 D16).
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Use `ChatAccessKit` as it is. If it needs a change, stop and flag it: shared code escalates to Jon. `galavant/GalavantMCP` is the working model for the helper. No Health data in the export.
