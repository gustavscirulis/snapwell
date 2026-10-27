# Agent workflow

1. Check Git state and task scope. Preserve unrelated changes; never stash or commit another task's work automatically.
2. Read only the relevant routed documentation and inspect the existing implementation.
3. For substantial changes, keep `.context/handoff-<task>.md`: goal, decisions, files investigated, validation and remaining gaps. Durable product requirements belong in committed docs.
4. Reproduce bugs and implement the smallest robust change. Keep storage writes and state ownership in their existing services. If the first fix fails, inspect logs/runtime evidence before guessing again.
5. Run targeted checks while working and affected-platform logic/UI checks before handoff. Classify toolchain failures separately from assertions or crashes.
6. Review the diff against the goal. For substantial work, use independent focused review when available: sync/storage compatibility and write ordering; state/concurrency ownership; native UI/gestures/accessibility; or validation quality. Reviewers receive the goal, relevant docs, diff and checks rather than the author's full reasoning.
7. Resolve high-severity findings before handoff. Record actionable lower-risk follow-ups without expanding the current task.
8. Run the public-content checks against the staged snapshot and outgoing commits, verify no-reply Git identities, and review the public PR text/artifact scope. Release work additionally requires the Apple read-back audit, private evidence backup, scoped cleanup and committed status records.
9. Add a user-facing changelog entry in the same PR, or explain why none applies. Update owning docs. Summarize changes, checks, evidence and limitations.

Use one task at a time in unattended backlog mode. Maintain a short queue in `.context/todos.md`
with pending, active, completed and needs-input items. Do not impose task worksheets or extra
commits on trivial changes. Publishing is done through the release workflow, not as an implicit
part of completing a coding task.
