# Next Up — M2 Dispatch 2: Activity

**Slices:** M2 · S3
**Briefs:** docs/milestones/M2-health.md §S3; docs/decisions/0004
**Done when:** per the briefs. The Activity tab shows a four-week calendar of strength and walking workouts, daily walking distance, latest body weight, and one exercise’s progression line from completion snapshots; the exercise picker remembers its key and defaults to the first weighted exercise of the first workout; Health-backed empty states read “Nothing from Health yet.”
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Read Health on demand without caching it. Walking days come only from `.walking` workouts; `.hiking` stays out.
