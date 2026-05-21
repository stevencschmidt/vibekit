# Spec 006 — auto-resume on usage limit reset

## Summary

Two small changes that together minimize the friction when a Claude Pro usage limit is hit:

1. **vibeplan stops monitoring when rate-limit detected** — prevents the chat session from burning remaining quota waiting for a reset that Ralph handles automatically. Reports the reset time and offers an `at` command for system-level auto-restart.
2. **CLAUDE.md template auto-checks state at session start** — when the user returns after a limit pause and opens Claude Code, a one-line notice surfaces any pending work before they have to remember to type `/resume`.

## Success Criteria

- `templates/.claude/skills/vibeplan/SKILL.md` RATE_LIMIT monitoring row instructs Claude to stop monitoring, report the reset time, offer an optional `at` command, and tell the user to type `/resume` when they return.
- `templates/CLAUDE.md` has a "Session Start Check" section that instructs Claude to read `state/sync.json` silently at session start and emit a one-line notice if `ralph.task_id` is non-null.
- `verify_build()` passes (SKILL.md frontmatter check, bash syntax).

## Hard Constraints

- Exactly two files changed: `templates/.claude/skills/vibeplan/SKILL.md` and `templates/CLAUDE.md`.
- No changes to ralph.sh, init.sh, resume skill, or any other file.
- The `at` command must be presented as optional (may not be installed on all systems).
- The session-start check must NOT auto-invoke `/resume` — it surfaces a notice only.

## Out of Scope

- Changes to ralph.sh rate-limit handling (already correct)
- System-level cron or daemon scripts
- Changes to the `/resume` skill itself

## Technical Approach

Both changes are markdown edits to template files:

- vibeplan SKILL.md: in the monitoring event table, replace the RATE_LIMIT row to add stop-monitoring instruction and the `at` command suggestion
- CLAUDE.md template: insert a new "Session Start Check" section after the "Domain Files" section

## Verify

`verify_build()` — bash syntax on scripts, JSON on manifests, frontmatter on SKILL.md files.
