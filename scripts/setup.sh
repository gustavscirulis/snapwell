#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
existing=$(git config --get core.hooksPath || true)
if [[ -n "$existing" && "$existing" != .githooks ]]; then
    printf 'Existing hooksPath (%s) preserved. Configure its pre-commit to run ./dev.sh test --platform changed --suite logic --staged\n' "$existing"
else
    git config core.hooksPath .githooks
fi
if [[ "${CONDUCTOR_IS_LOCAL:-1}" != 0 ]]; then
    ./dev.sh doctor --platform macos
fi
