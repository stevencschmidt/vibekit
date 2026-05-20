# Spec 005 — resume skill

## Summary

Add a `/resume` skill to vibekit that handles returning to a session after a Claude Pro
usage-limit pause or any other interruption. The skill checks whether Ralph is still running,
reads current state from `sync.json` and the active spec's `tasks.md`, reports progress, and
resumes automatically — restarting Ralph if tasks remain, or guiding to `/vibeplan` if all done.

## Success Criteria

- `templates/.claude/skills/resume/SKILL.md` exists with `name`, `description`, and `trigger`
  frontmatter and trigger value `/resume`.
- `/resume` reconnects to a running Ralph process (via PID check) without replanning.
- `/resume` reports a clean status block when Ralph has stopped: spec slug, tasks done/total,
  last log line.
- `/resume` restarts Ralph immediately when tasks remain; surfaces `TASK_BLOCKED` reason
  without restarting; guides to `/vibeplan` when all tasks are complete or no spec is active.
- `templates/CLAUDE.md` Session Policy mentions `/resume` for post-pause recovery.
- `init.sh` copies the resume skill alongside `vibeplan` and `knowledge-graph-sync`.
- `verify_build()` passes (new SKILL.md picked up by frontmatter check).

## Hard Constraints

- No changes to any existing spec, script logic, or domain file beyond the four files listed.
- The resume skill must NOT re-enter planning mode — recovery only.
- No new `docs/claude/` domain files warranted.

## Out of Scope

- Changes to vibeplan's own startup check (it already has Ralph reconnect logic)
- Multi-brief loop resume (resuming mid-loop between briefs)
- Automatic recovery from TASK_BLOCKED

## Technical Approach

Four files changed:

1. **New:** `templates/.claude/skills/resume/SKILL.md` — the skill body
2. **Edit:** `templates/CLAUDE.md` — one line added to Session Policy
3. **Edit:** `init.sh` — one `mkdir -p` + one `cp` for the resume skill
4. **Edit:** `CHANGELOG.md` — unreleased entries

The skill's logic mirrors vibeplan's Startup Check section but is a standalone recovery
command, not a pre-planning gate.

## Dependencies

None. Pure markdown + shell template changes.

## Verify

`verify_build()` — bash syntax on scripts, JSON on manifest files, frontmatter check on all
SKILL.md files (which now includes `templates/.claude/skills/resume/SKILL.md`).
