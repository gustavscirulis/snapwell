# Release records

`./dev.sh release prepare --platform <macos|ios> --version <version>` creates a version
folder containing selected changelog entries, the independently verified build number and
a notes file. The agent drafts that file into 2–4 user-facing `•` bullets before committing.

Status progresses from `prepared` to `submitted` to `released` based on Apple responses.
Shared changelog IDs are tracked independently for each platform. Nothing in this folder
is an API credential. See [the release workflow](../docs/releases.md).
