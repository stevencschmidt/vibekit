# Conventions

> Load this file when writing scripts, skills, or templates for vibekit.

---

## Script Conventions

- All scripts use `#!/usr/bin/env bash` and `set -e`
- `SCRIPT_DIR` and `PROJECT_ROOT` are computed at the top of each script using `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`
- Scripts that are sourced (sync-helpers.sh, monitor.sh) do not use `set -e` at top level — callers own error handling
- Python interpreter resolved via `PYTHON` variable: try `python3` first, fall back to `python` if it's Python 3

## Commit Prefixes

```
[claude-docs]   knowledge graph updates (sync agent)
[plan]          spec + task generation
[ralph]         task completions
```

These prefixes make git history queryable:
```bash
git log --oneline --grep="\[ralph\]"
git log --oneline --grep="\[claude-docs\]"
```

## Sentinel Protocol

Claude emits exactly one sentinel at end of output, on its own line:
```
[TASK_COMPLETE: T042]
[TASK_BLOCKED: <specific human-readable reason>]
[SESSION_HANDOFF]
```

## Skill Format

Claude Code skills use YAML frontmatter + markdown body:
```yaml
---
name: skill-name
description: one-line description
trigger: /slash-command | internal
---
```

## File Naming

- Scripts: `kebab-case.sh`
- Skill files: always `SKILL.md` (uppercase)
- Template files: match the target filename exactly
- Domain files: `kebab-case.md` (e.g. `stack.md`, `architecture.md`)

## Two Distinct "Skills" Concepts

| Term | Location | Purpose |
|------|----------|---------|
| Claude Code skills | `.claude/skills/*/SKILL.md` | Slash commands for interactive sessions |
| Vibekit domain skills | `skills/<name>/manifest.md` | Domain knowledge injected into ralph-prompt via `{{SKILLS_CONTEXT}}` |

## Atomic Operations

`sync_write` and `session_log_append` always write atomically (temp file + rename) to avoid corrupt state on crash.

## Error Handling

- `sync-agent.sh` always exits 0 — never blocks compaction or session end
- Ralph's loop: rate limits do not count as stalls; stalls and build failures are tracked with separate counters
- `set -e` in ralph.sh — but rate-limit/sentinel operations use `|| true` to avoid aborting the loop
