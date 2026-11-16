# Fit Happens

A private iPhone app for a persistent A/B workout rotation. See [the product brief](docs/PRODUCT.md), [decisions](docs/decisions/README.md), and [the current dispatch](docs/NEXT_UP.md).

## Development

Generate the Xcode project from `project.yml` with XcodeGen, then open `FitHappens.xcodeproj` in Xcode. Run `scripts/check-drift.sh` for the local lint, Core tests, app build, and docs gate. Run `scripts/setup.sh --apply` once per clone to enable the tracked Git hooks.
