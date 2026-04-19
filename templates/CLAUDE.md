# PROJECT_NAME

> One-line description of what this project does.

---

## Domain Files

Before starting any task, read `docs/claude/manifest.json`. Based on the task at hand, identify the 1–3 most relevant domain files. Read only those files. State which files you loaded and why.

---

## Quick Facts

- **Test command:** `<test command>`
- **Dev server:** `<dev server command>`
- **Branch convention:** `feature/<slug>`, `fix/<slug>`

---

## Session Policy

This session is for planning and conversation only. Do not implement, fix, or debug code inline.

When asked to build, fix, investigate, or debug anything non-trivial:
1. Use `/plan` to generate Ralph tasks (new features) or `/plan <problem description>` (fixes/debugging)
2. Run `bash scripts/ralph.sh` to execute

**Exception:** Single-file edits requiring one tool call with no iteration (e.g. fixing a typo, updating a config value).

---

## Decision Log

Total decisions: 000

Read the last 5 entries from `docs/claude/decisions.md` when making architectural choices.
For domain-specific work, filter by the relevant domain tag (e.g. `<!-- DECISION:NNN | domains: api -->` → load last 3 `api`-tagged entries instead of last 5 globally).
