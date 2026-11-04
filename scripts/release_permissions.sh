#!/usr/bin/env bash

# Xcode creates distributable files; the caller keeps private receipts and logs.
run_release_command() (
    set -o pipefail
    umask 022
    if command -v xcbeautify &>/dev/null; then
        "$@" 2>&1 | xcbeautify --quiet
    else
        "$@"
    fi
)

prepare_release_bundle() {
    # Cached signing resources may retain 0600 even when codesign runs with 022.
    # The enclosing private archive directory continues to restrict local access.
    chmod -R a+rX "$1"
}
