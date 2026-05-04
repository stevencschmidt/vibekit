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
[ralph] QC-T### complete — QC-identified gap fix
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

The QC agent emits `[QC_COMPLETE]` (standalone, no T-id) when no gaps remain against `brief.md`. In checkpoint QC (mid-spec), `[QC_COMPLETE]` means "no gaps here, continue"; in completion QC it exits the run. See `scripts/qc-prompt.md`.

## verify_build() Must Be Stack-Aware

`verify_build()` is the only thing standing between a broken commit and `git push`. A `return 0` stub defeats Ralph's 3-strike protection entirely. The `/plan` skill is responsible for writing a stack-appropriate body at bootstrap:

| Stack | Minimum verify |
|-------|----------------|
| Python | `python -c "import ast; ast.parse(open('<entry>').read())"` + importable entry check |
| Node | `npx tsc --noEmit 2>/dev/null || true` + `node --check <entry>.js` |
| Go | `go build ./...` |
| Rust | `cargo check --quiet` |
| Bash-only | `bash -n` on every `.sh` under `scripts/` |

If no plausible verify exists, `/plan` must ask the user rather than write `return 0`.

## Structured Delta Obligation (Sync Agent)

The sync agent's `Step 1.5` runs before free-form signal sniffing:

- Any change in `requirements.txt`, `package.json`, `go.mod`, `Cargo.toml`, or `pyproject.toml` vs. `stack.md` → mandatory write signal
- Any top-level import of a package not documented in `stack.md` → mandatory write signal

Structured signals cannot be silenced by the four-signal heuristic — they always trigger a `stack.md` update in the same commit.

## Session Policy

Interactive Claude Code sessions in a vibekit-scaffolded project are for planning and conversation only. Non-trivial implementation, fixes, or debugging go through `/plan` → Ralph, not inline. The policy lives in `templates/CLAUDE.md` under `## Session Policy` and is copied to every scaffolded project. The `/plan` skill ships a Fix/Debug mode for the `/plan <problem description>` invocation path.

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

## Archive File Naming

When `ralph.sh` or `/plan` splits a file into active + historical parts, the archive sibling is named `<base>-archive.md` in the same directory:

| Active file | Archive file |
|-------------|-------------|
| `specs/<slug>/tasks.md` | `specs/<slug>/tasks-archive.md` |
| `specs/<slug>/brief.md` | `specs/<slug>/brief-archive.md` |

Archive files are append-only and prepended with a `# Archive: <spec-slug>` header on first write. They are not loaded by default during task execution.

## Sync Hook Arg Convention

`sync-agent.sh` takes a single positional arg indicating the hook context:

```bash
bash scripts/sync-agent.sh precompact   # PreCompact hook — fire-and-forget
bash scripts/sync-agent.sh sessionend   # SessionEnd hook — timeout 10s, best-effort
```

Unknown or missing mode defaults to fire-and-forget for safety. This arg must be set in `.claude/settings.json`; the `/plan` skill writes it at bootstrap.

## Atomic Operations

`sync_write` and `session_log_append` always write atomically (temp file + rename) to avoid corrupt state on crash.

## Error Handling

- `sync-agent.sh` always exits 0 — never blocks compaction or session end
- Ralph's loop: rate limits do not count as stalls; stalls and build failures are tracked with separate counters
- `set -e` in ralph.sh — but rate-limit/sentinel operations use `|| true` to avoid aborting the loop
