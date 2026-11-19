# Next Up — M3 Dispatch 2: Stage proposals in the review

**Slices:** M3 · S3
**Briefs:** docs/milestones/M3-chat-access.md §S3; docs/decisions/0006; docs/decisions/0002 D3 (amended)
**Done when:** per the brief. `StagedProgram.check` decodes and validates proposals against an available export using the S1 Core errors, and returns a change summary. `propose_program` stages valid text in the `fhprogram` inbox and rejects invalid text without writing. The Program screen lists staged proposals; tapping one opens the existing review, Apply claims after success, Discard claims without applying, and the Next Workout Program button shows a ready-count badge. The watcher follows the Chat Access switch. Tests cover valid and invalid staging, review/apply/claim paths, discard, and newer or unavailable exports. No simulator walkthrough; closeout (ADR-0005 D16).
**Owed:** see [device-passes.md](device-passes.md)
**Notes:** Use `ChatAccessKit` as it is. If it needs a change, stop and flag it: shared code escalates to Jon.
