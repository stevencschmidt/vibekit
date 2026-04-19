# PROJECT_NAME

> One-line description of what this project does.

---

## Domain Files

Load the relevant file(s) for your current task. Do not load all files.

| When working on... | Load |
|--------------------|------|
| Architecture, system design, component boundaries | `docs/claude/architecture.md` |
| Code style, naming, patterns, error handling | `docs/claude/conventions.md` |
| Dependencies, frameworks, tooling, versions | `docs/claude/stack.md` |

Add rows as new domain files are created by the sync agent.

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
