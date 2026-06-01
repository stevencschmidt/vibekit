# Conventions

> Load this file when writing scripts, skills, or templates for vibekit.

---

## Script Conventions

- All scripts use `#!/usr/bin/env bash` and `set -e`
- `SCRIPT_DIR` and `PROJECT_ROOT` are computed at the top of each script using `$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`
- Scripts that are sourced (sync-helpers.sh, monitor.sh) do not use `set -e` at top level — callers own error handling
- Python interpreter resolved via `PYTHON` variable: try `python3` first, fall back to `python` if it's Python 3

## Runtime State Handling

Scaffolded projects gitignore `state/` (logs, pid, sync state). The `templates/.gitignore` mirrors this, and `init.sh` patches existing projects idempotently. `ralph.sh`'s `safety_commit` function scopes staging to iteration changes only (comparing current `git status` against a pre-iteration snapshot in `$PRE_DIRTY`), and reports accurately by checking whether HEAD advanced since iteration start. See DECISION:011.

### Single-Instance Concurrency Guard

`ralph.sh` maintains a `state/ralph.pid` file to enforce single-instance execution. Two concurrent Ralph instances against the same `state/sync.json` corrupt each other's state, so the guard:

- Writes `$$` (current process ID) to `state/ralph.pid` at startup
- On startup, checks if an existing pid file's process is alive using `kill -0 <pid>` (liveness test, no signal sent)
- If a live process is detected and neither `--force` flag nor `RALPH_FORCE=1` env var is set, exits with an error directing the user to `/vibe_resume` or `--force`
- With `--force` or `RALPH_FORCE=1`, warns and overrides (used when a process has gone away but the pid is held by an unrelated process reusing the ID)
- Registers an EXIT trap (`_ralph_exit_cleanup`) that releases the pid file by verifying ownership: only deletes the file if the stored pid matches the exiting process's `$$`

This mechanism is reconciled with `/vibe_resume`, which uses the same pid-liveness pattern to detect whether Ralph is running.

### Untrack Already-Committed State on Adopt

`init.sh` runs idempotently on both fresh repositories and existing projects with vibekit added later. When adopting vibekit into an existing project that may have already committed `state/` artifacts, `init.sh` untrracks the `state/` directory from the git index using `git rm -r --cached state/` (no-op on fresh repos where state/ was never committed). This ensures that future Ralph runs write temporary files (.pid, .log, sync.json snapshots) without creating git churn. See DECISION:011 for the rationale: gitignore prevents commits, but `.gitignore` entries do not untrack already-committed files — the `git rm --cached` call is necessary.

### Agent-Session Hang Recovery

Agent sessions are bounded by `RALPH_TASK_TIMEOUT` (default 1800 seconds; set to `0` to disable). If an agent hangs indefinitely (e.g., running a non-terminating command like `tail -f`), ralph.sh kills it after the timeout and classifies the hang as a stall, reusing the existing 3-strike failure machinery. The agent prompt forbids non-terminating commands to prevent this. See DECISION:013 for details.

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

`verify_build()` is the only thing standing between a broken commit and `git push`. A `return 0` stub defeats Ralph's 3-strike protection entirely. The `/vibeplan` skill is responsible for writing a stack-appropriate body at bootstrap:

| Stack | Minimum verify |
|-------|----------------|
| Python | `python -c "import ast; ast.parse(open('<entry>').read())"` + importable entry check |
| Node | `npx tsc --noEmit 2>/dev/null || true` + `node --check <entry>.js` |
| Go | `go build ./...` |
| Rust | `cargo check --quiet` |
| Bash-only | `bash -n` on every `.sh` under `scripts/` |

If no plausible verify exists, `/vibeplan` must ask the user rather than write `return 0`.

## Model Routing / Tier Convention

Tasks carry an optional `Tier:` field (`simple`, `medium`, `complex`). When `MODEL_AUTO=true` (the default) and no `--model` flag is passed, Ralph resolves the execution model from the tier:

| Tier | Default model | Use for |
|------|--------------|---------|
| `simple` | `MODEL_SIMPLE` | mechanical changes, doc edits, single-file tweaks |
| `medium` | `MODEL_MEDIUM` | standard feature work (untagged tasks default here) |
| `complex` | `MODEL_COMPLEX` | multi-file refactors, architecture changes |

- **Untagged tasks** are treated as `medium`.
- **Build-failure retries** escalate one tier (simple→medium→complex) before each retry attempt.
- **Both QC stages** (checkpoint and completion) always run on `MODEL_QC`, regardless of task tier.
- **`MODEL_AUTO=false`** or passing `--model` on the CLI bypasses routing and runs every task on `$MODEL`.
- `/vibeplan` writes a `Tier:` line per task and writes `ralph.tier` in `state/sync.json`; QC-appended tasks also carry a tier.

## Structured Delta Obligation (Sync Agent)

The sync agent's `Step 1.5` runs before free-form signal sniffing:

- Any change in `requirements.txt`, `package.json`, `go.mod`, `Cargo.toml`, or `pyproject.toml` vs. `stack.md` → mandatory write signal
- Any top-level import of a package not documented in `stack.md` → mandatory write signal

Structured signals cannot be silenced by the four-signal heuristic — they always trigger a `stack.md` update in the same commit.

## Session Policy

Interactive Claude Code sessions in a vibekit-scaffolded project are for planning and conversation only. Non-trivial implementation, fixes, or debugging go through `/vibeplan` → Ralph, not inline. The policy lives in `templates/CLAUDE.md` under `## Session Policy` and is copied to every scaffolded project. The `/vibeplan` skill ships a Fix/Debug mode for the `/vibeplan <problem description>` invocation path.

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

When `ralph.sh` or `/vibeplan` splits a file into active + historical parts, the archive sibling is named `<base>-archive.md` in the same directory:

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

Unknown or missing mode defaults to fire-and-forget for safety. This arg must be set in `.claude/settings.json`; the `/vibeplan` skill writes it at bootstrap.

## Atomic Operations

`sync_write` and `session_log_append` always write atomically (temp file + rename) to avoid corrupt state on crash.

## archive-completed-tasks.sh Usage

Accepts an optional `PROJECT_ROOT` argument to target any vibekit-scaffolded project:

```bash
bash scripts/archive-completed-tasks.sh                          # vibekit itself
bash scripts/archive-completed-tasks.sh /path/to/sandbox/ragtest  # another project
```

Without the argument, `PROJECT_ROOT` defaults to the script's parent directory.

## Running Ralph from an Interactive Session

When launching Ralph from within Claude Code, use `Bash run_in_background` for the ralph.sh invocation, then monitor with a poll loop — NOT a persistent `Monitor tail -f` pipe.

**Correct pattern:**
```bash
# Launch (run_in_background: true)
nohup bash scripts/ralph.sh > state/ralph.log 2>&1

# Poll loop (run_in_background: true)
until grep -qE '^\[QC_COMPLETE\]$|^=== Stopped' state/ralph.log; do sleep 5; done
```

> **Why anchored?** The unanchored pattern `QC_COMPLETE|=== Stopped` will false-positive-match the literal sentinel text appearing inside checkpoint-QC review prose (the agent often quotes `[QC_COMPLETE]` while explaining the protocol). Anchored regex (`^...$`) only matches when the sentinel is on its own line — which is how ralph.sh actually emits it. This was Bug C3 from spec-002.

`Monitor` with `tail -f` pipes buffer terminal events silently and Claude will not receive them. The poll loop exits as soon as the sentinel line appears, triggering a notification.

**Per-task polling alternative** — use this when you want a notification after each task completes rather than waiting for end-of-spec:
```bash
# Per-task polling — exits after each TASK_COMPLETE so Claude can announce progress
until grep -qE '^\[TASK_COMPLETE: T[0-9]+\]$|^=== Stopped' state/ralph.log; do sleep 5; done
```
The caller is responsible for tracking which TASK_COMPLETE was last seen and re-polling for the next one.

## Error Handling

- `sync-agent.sh` always exits 0 — never blocks compaction or session end
- Ralph's loop: rate limits do not count as stalls; stalls and build failures are tracked with separate counters
- `set -e` in ralph.sh — but rate-limit/sentinel operations use `|| true` to avoid aborting the loop
