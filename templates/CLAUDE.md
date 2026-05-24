# PROJECT_NAME

> One-line description of what this project does.

---

## Domain Files

Before starting any task, read `docs/claude/manifest.json`. Based on the task at hand, identify the 1–3 most relevant domain files. Read only those files. State which files you loaded and why.

---

## Session Start Check

At the start of every session, before responding to the user's first message: silently read
`state/sync.json`. If `ralph.task_id` is non-null, emit this notice on the first line of your
response:

> ⚡ Active work: `<spec-slug>` · T`<task_id>` — `<task_title>`. Type `/vibe_resume` to continue.

The spec-slug comes from `vibekit.config.sh` (`SPEC_TASKS_FILE` path, directory name only).
If `vibekit.config.sh` is unreadable, use the task_id and task_title from `sync.json` alone.

Then answer the user's question normally. Do not auto-invoke `/vibe_resume` — show the notice only.

---

## Quick Facts

- **Test command:** `<test command>`
- **Dev server:** `<dev server command>`
- **Branch convention:** `feature/<slug>`, `fix/<slug>`
- **Bootstrap:** `/knowledge-graph-bootstrap <brief>` (run once at project start)

---

## Session Policy

This session is for planning and conversation only. Do not implement, fix, or debug code inline.

When asked to build, fix, investigate, or debug anything non-trivial:
1. Use `/vibeplan` to generate Ralph tasks (new features) or `/vibeplan <problem description>` (fixes/debugging)
2. Run `bash scripts/ralph.sh` to execute

**After a usage-limit pause or session restart:** `/vibe_resume`

**Exception:** Single-file edits requiring one tool call with no iteration (e.g. fixing a typo, updating a config value).

---

## Decision Log

Total decisions: 000

Read the last 5 entries from `docs/claude/decisions.md` when making architectural choices.
For domain-specific work, filter by the relevant domain tag (e.g. `<!-- DECISION:NNN | domains: api -->` → load last 3 `api`-tagged entries instead of last 5 globally).
