#!/bin/sh
set -eu
expected=.githooks
actual=$(git config --get core.hooksPath || true)
if [ "$actual" = "$expected" ]; then
  echo "Git hooks are enabled ($expected)."
elif [ "${1:-}" = "--apply" ]; then
  git config core.hooksPath "$expected"
  echo "Enabled Git hooks ($expected)."
else
  echo "Git hooks are not enabled. Run scripts/setup.sh --apply to enable them."
  exit 1
fi
