# Next Up — M2 Dispatch 1: Health access and Watch-workout linking

**Slices:** M2 · S1, M2 · S2
**Briefs:** docs/milestones/M2-health.md §Identifiers, §S1–S2; docs/decisions/0003 D1, 0004
**Done when:** per the briefs. Next Workout asks for Health read access once, and offers to mark the next workout done from a recent unlinked strength workout; accepting completes it at the workout's end with its UUID, declining hides that offer, and Core's tests cover candidate selection (started after the latest completion, the 12-hour window, linked, declined, most recent wins).
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Read-only Health: no write permission or update usage string. No schema change. Everything that touches HealthKit is device-only; name it in the PR as unverified.
