# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

vibekit is a Claude Code knowledge graph system and autonomous execution toolkit. It solves two problems: **context bloat** (CLAUDE.md files growing to 15K tokens) and **context rot** (decisions evaporating between sessions). It ships as a standalone repo; `init.sh` scaffolds the system into target projects.

Three pillars:
1. **Knowledge graph** — lean CLAUDE.md router + focused domain files in `docs/claude/`, updated automatically via hooks
2. **`/plan` skill** — one conversational Claude Code command produces a spec, task list, and populates sync.json for Ralph
3. **Ralph** — autonomous bash execution loop that runs tasks from `state/sync.json` using `claude --dangerously-skip-permissions --print`

## Running Ralph

```bash
bash scripts/ralph.sh [--tool claude|amp] [--model MODEL] [--max N] [--dry-run]
```

Ralph requires `vibekit.config.sh` at project root and `state/sync.json` to exist before running. Dry-run shows the preflight summary and exits without executing.

## Script Architecture

### `scripts/ralph.sh`
The execution loop. Per iteration:
1. Sources `vibekit.config.sh` (project-specific config + `verify_build()`) and `scripts/sync-helpers.sh` + `scripts/monitor.sh`
2. Reads `ralph.task_id` from `state/sync.json`
3. Builds a prompt from `scripts/ralph-prompt.md` (substituting `{{SKILLS_CONTEXT}}` with loaded skill manifests)
4. Runs `claude --dangerously-skip-permissions --print --model $MODEL "Read <prompt> and execute the task in state/sync.json"`
5. Detects sentinels in output, runs `verify_build()` on TASK_COMPLETE, rolls back via `git reset --hard` on failure

Separate stall and build-failure counters per task; 3-strike limit on each. Rate limits trigger a live countdown sleep (not a stall). SIGINT rolls back the current iteration.

### `scripts/sync-helpers.sh`
Three functions that operate on `$SYNC_FILE` (dot-notation path access into JSON):
- `sync_read "ralph.task_id"` — reads a field, returns plain value or JSON for objects/arrays
- `sync_write "ralph.last_sentinel" "[TASK_COMPLETE: T001]"` — writes atomically via temp file + rename; infers JSON types
- `session_log_append <layer> <session> <started> <ended> <exit_reason> <tokens> <tasks_json>` — appends to `$SESSION_LOG_FILE`

Requires `$SYNC_FILE` and `$SESSION_LOG_FILE` (set in `vibekit.config.sh`). Python 3 primary, jq fallback.

### `scripts/monitor.sh`
Three functions for sentinel detection from Claude output strings:
- `detect_sentinel "$OUTPUT"` — prints `TASK_COMPLETE`, `TASK_BLOCKED`, `SESSION_HANDOFF`, or empty
- `extract_task_id "$OUTPUT"` — extracts `T###` from a TASK_COMPLETE sentinel
- `extract_block_reason "$OUTPUT"` — extracts the reason string from a TASK_BLOCKED sentinel

### Sentinel protocol
Claude emits one of these at end of task output:
```
[TASK_COMPLETE: T042]
[TASK_BLOCKED: <specific human-readable reason>]
[SESSION_HANDOFF]
```

## `vibekit.config.sh` (per-project, not in this repo)

What ralph.sh sources from project root:
```bash
TOOL="claude"           # claude | amp
MODEL="claude-sonnet-4-6"
SYNC_FILE="$PROJECT_ROOT/state/sync.json"
SESSION_LOG_FILE="$PROJECT_ROOT/state/session-log.json"
RALPH_PROMPT="$PROJECT_ROOT/scripts/ralph-prompt.md"
DECISIONS_FILE="$PROJECT_ROOT/state/decisions.md"
LOG_FILE="$PROJECT_ROOT/state/ralph.log"
SPEC_TASKS_FILE="$PROJECT_ROOT/specs/001-slug/tasks.md"
SKILLS=()               # domain skill names under skills/<name>/manifest.md

verify_build() { return 0; }  # project-specific
```

## `state/sync.json` Schema

```json
{
  "ralph": {
    "task_id": null,
    "task_title": "",
    "last_sentinel": null,
    "last_updated": null,
    "session": 1
  },
  "execution": {
    "current_task_status": "idle"
  }
}
```

## Vibekit Domain Skills vs Claude Code Skills

Two different things share the word "skill":
- **Vibekit domain skills** (`skills/<name>/manifest.md`) — domain knowledge injected into `ralph-prompt.md` via `{{SKILLS_CONTEXT}}`. Project-specific, zero shipped with vibekit.
- **Claude Code skills** (`.claude/skills/*/SKILL.md`) — slash commands for interactive sessions. vibekit ships two: `/plan` (planning) and `knowledge-graph-sync` (background hook).

## What Still Needs to Be Built

Per the implementation plan:
- Reorganize root scripts → `scripts/` subdirectory
- `scripts/ralph-prompt.md` — prompt template with `{{SKILLS_CONTEXT}}`
- `scripts/sync-agent.sh` — PreCompact/SessionEnd hook runner
- `templates/vibekit.config.sh` — project config template
- `templates/state/` — sync.json, session-log.json, decisions.md
- `templates/CLAUDE.md` — router template
- `templates/docs/claude/` — domain file stubs
- `.claude/skills/plan/SKILL.md` — unified planning skill
- `.claude/skills/knowledge-graph-sync/SKILL.md` — background sync skill
- `.claude/settings.json` — hooks + 50% autocompact threshold
- `templates/.obsidian/` — vault config for docs/claude/
- `init.sh` — scaffolds vibekit into a target project

## Commit Prefixes

```
[claude-docs]   knowledge graph updates (sync agent)
[plan]          spec + task generation
[ralph]         task completions
```
