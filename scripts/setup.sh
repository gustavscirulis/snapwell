#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
existing=$(git config --get core.hooksPath || true)
if [[ -n "$existing" && "$existing" != .githooks ]]; then
    printf 'Existing hooksPath (%s) preserved. Integrate .githooks/pre-commit and .githooks/pre-push into that hook setup\n' "$existing"
else
    git config core.hooksPath .githooks
fi
if [[ "${CONDUCTOR_IS_LOCAL:-1}" != 0 ]]; then
    ./dev.sh doctor --platform macos
fi
