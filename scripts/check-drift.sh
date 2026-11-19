#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"
platform=${JON_PLATFORM:-"$HOME/code/jon-platform"}
quiet_run="$platform/scripts/quiet-run"
xcodegen generate --quiet
"$quiet_run" swiftlint lint --strict --quiet
"$quiet_run" swift test --package-path FitHappensCore
"$quiet_run" swift test --package-path FitHappensMCP
"$quiet_run" swift test --package-path FitHappensInboxKit
"$quiet_run" xcodebuild -resolvePackageDependencies -project FitHappens.xcodeproj -scheme FitHappens
"$quiet_run" xcodebuild \
  -project FitHappens.xcodeproj \
  -scheme FitHappens \
  -destination 'generic/platform=iOS Simulator' \
  -skipMacroValidation \
  -onlyUsePackageVersionsFromResolvedFile \
  -derivedDataPath .build/DerivedData \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  build
"$platform/scripts/check-handoff"
