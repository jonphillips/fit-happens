# Next Up — Tabs and ramps · Dispatch 1: Three tabs

**Slices:** Tabs and ramps · Dispatch 1
**Briefs:** docs/efforts/tabs-and-ramps.md §Dispatch 1; docs/PRODUCT.md §The three tabs; docs/decisions/0003 D3 (amended)
**Done when:** per the brief. The app has three tabs: Next Workout, Activity, and Program, with Program badged by ready proposals. Next Workout has no toolbar, and its "Last done" line opens date correction and undo for the latest completion. Activity ends with a Fix a workout row that pushes the completion list. The Program tab shows every workout in order with the next one marked, view-only, above the existing sections. A Core `ProgramOverview` shares one per-item mapping with `WorkoutOverview`, and its tests are listed in the brief. Corrections live in one model; the export model and its background write move to the app root. No simulator walkthrough; closeout (ADR-0005 D16).
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** No Core change to completion, undo, or date correction. Ramps are Dispatch 2. Don't start them here.
