# Tasks: 006-auto-resume

- [x] T001 · Update vibeplan SKILL.md — stop monitoring on RATE_LIMIT, offer at-command
- [x] T002 · Update templates/CLAUDE.md — add Session Start Check section

---

## T002 · Update templates/CLAUDE.md — add Session Start Check section
Depends on: T001
Verify: `grep -q "Session Start Check" templates/CLAUDE.md` exits 0
Relevant: docs/claude/conventions.md, templates/CLAUDE.md

Read `templates/CLAUDE.md`. Find the "Domain Files" section. After the closing `---` of the
Domain Files section (and before the next section header), insert a new section:

```markdown
## Session Start Check

At the start of every session, before responding to the user's first message: silently read
`state/sync.json`. If `ralph.task_id` is non-null, emit this notice on the first line of your
response:

> ⚡ Active work: `<spec-slug>` · T`<task_id>` — `<task_title>`. Type `/resume` to continue.

The spec-slug comes from `vibekit.config.sh` (`SPEC_TASKS_FILE` path, directory name only).
If `vibekit.config.sh` is unreadable, use the task_id and task_title from `sync.json` alone.

Then answer the user's question normally. Do not auto-invoke `/resume` — show the notice only.

---
```

The section must appear between "Domain Files" and whatever section follows it (currently
"Quick Facts"). Do not change any other content.
Verify: `grep -q "Session Start Check" templates/CLAUDE.md` exits 0.
Commit with: `[ralph] T002 complete — Session Start Check in CLAUDE.md template`
