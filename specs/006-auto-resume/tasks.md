# Tasks: 006-auto-resume

- [ ] T001 · Update vibeplan SKILL.md — stop monitoring on RATE_LIMIT, offer at-command
- [ ] T002 · Update templates/CLAUDE.md — add Session Start Check section

---

## T001 · Update vibeplan SKILL.md — stop monitoring on RATE_LIMIT, offer at-command
Depends on: —
Verify: `grep -q "Stop monitoring" templates/.claude/skills/vibeplan/SKILL.md` exits 0
Relevant: docs/claude/conventions.md, templates/.claude/skills/vibeplan/SKILL.md

Read `templates/.claude/skills/vibeplan/SKILL.md`. Find the "Monitoring Ralph Progress" section
and locate the event translation table. Find this row:

```
| `RATE_LIMIT until ...` | "Rate limit hit. Ralph is waiting until `<reset_time>` — will resume automatically." |
```

Replace it with:

```
| `RATE_LIMIT until ...` | Stop monitoring immediately. Say: "Rate limit hit. Ralph will resume automatically at `<reset_time>` — no action needed on your end. Stopping chat monitoring now to preserve your remaining quota. Optional: to auto-restart Ralph at the shell if it stops, run `echo 'bash scripts/ralph.sh' \| at HH:MM` (replace HH:MM with the reset time; requires `at` to be installed). When you return after the reset, type `/resume` to check progress." |
```

Also find the `RATE_LIMIT_RESUMED` row:

```
| `RATE_LIMIT_RESUMED window=...` | "Rate limit cleared. Ralph resuming..." |
```

Add a note that this event will not be seen in chat (since monitoring stopped), but it will appear in `state/ralph.log` if the user checks manually:

```
| `RATE_LIMIT_RESUMED window=...` | (monitoring already stopped — this event appears in `state/ralph.log` only) |
```

Do not change any other rows in the table or any other section of the file.
Verify: `grep -q "Stop monitoring" templates/.claude/skills/vibeplan/SKILL.md` exits 0.

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
