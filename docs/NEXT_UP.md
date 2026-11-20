# Next Up — Tabs and ramps · Dispatch 2: Ramped sets

**Slices:** Tabs and ramps · Dispatch 2
**Briefs:** docs/efforts/tabs-and-ramps.md §Dispatch 2; docs/decisions/0002-program-as-data-via-contract.md D1 and D2 (amended)
**Done when:** per the brief. Program contracts accept validated ramps, report relative ramp changes, and preserve them through application and stored revisions. One resolver produces the displayed prescription from each ramp and current working weight; Next Workout, Program, completion snapshots, and chat export use it. The export round trips ramp data. MCP instructions and tools handle valid and invalid ramps. The listed tests pass. Closeout (ADR-0005 D16).
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** The migration is additive. The app's production CloudKit cutover follows this dispatch, so its schema includes the ramp field.
