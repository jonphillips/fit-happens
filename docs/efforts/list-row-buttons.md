# Effort — List-row buttons

Status: Ready
Summary: The weight − and + buttons on Next Workout, and History's "Change date" beside "Undo", each act alone instead of firing every button in their row.

## The defect

In a SwiftUI `List`, a row whose buttons all use the default style becomes a single tap target, so
a tap anywhere in it runs every button's action. Two rows on `WorkoutScreen.swift` have this shape:

- **`WeightControl`.** One tap runs `loadStepperChanged(by: -1)` and then `(by: 1)`, so the weight
  never moves. It has been like this since M1 S2 (#3). `WorkoutHistoryOperations.stepLoad` and its
  Core tests are correct; the defect is only the tap target.
- **`HistoryRow`, latest completion.** Tapping "Change date" also sets `completionToUndo`, so the
  undo confirmation appears over the date screen.

The Health offer row is fine: `.bordered` and `.borderedProminent` buttons keep their own targets.

## The fix

- Give both `WeightControl` buttons `.buttonStyle(.borderless)` and a tap target of at least 44 pt
  square (`.frame(minWidth: 44, minHeight: 44)` with `.contentShape(.rect)`). Keep the icons, the
  labels, and `.disabled(load <= 0)` as they are.
- Give both `HistoryRow` buttons `.buttonStyle(.borderless)`.

No change to the model, Core, or the step rules. Don't swap in `Stepper` or add hold-to-repeat or
typed entry; those are product changes and need their own decision.

## Done when

- The two rows above carry the styles above, and no other row on the screen has two or more
  default-style buttons.
- `scripts/check-drift.sh` passes. The fix can't be shown in a Core test or a simulator tap
  ([verification.md](../verification.md)), so the PR says the taps are unverified on device.
- Closeout (ADR-0005 D16). The gate this effort owes is the M1 S2 and S4 line already in
  [device-passes.md](../device-passes.md) (weight steps, undo confirmation, date correction), so
  add no new gate line.
