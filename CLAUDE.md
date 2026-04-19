# vibekit

A Claude Code knowledge graph system and autonomous execution toolkit. Solves context bloat and context rot. Ships as a standalone repo; `init.sh` scaffolds the system into target projects.

---

## Domain Files

Load the relevant file(s) for your current task. Do not load all files.

| When working on... | Load |
|--------------------|------|
| Pillar architecture, component structure, data flow, boundaries | `docs/claude/architecture.md` |
| Script conventions, commit prefixes, sentinel protocol, skill format | `docs/claude/conventions.md` |
| Dependencies, bash/python/claude CLI, tooling | `docs/claude/stack.md` |

---

## Quick Facts

- **Run Ralph:** `bash scripts/ralph.sh [--tool claude|amp] [--model MODEL] [--max N] [--skip-qc] [--dry-run]`
- **Scaffold a project:** `./init.sh <target-dir> [project-name]`
- **No build step, no package manager** — bash + python3 + claude CLI

---

## Decision Log

Total decisions: 003

Read the last 5 entries from `docs/claude/decisions.md` when making architectural choices.

---

## Three Pillars

1. **Knowledge graph** — lean CLAUDE.md router + focused domain files in `docs/claude/`, updated automatically via hooks
2. **`/plan` skill** — one conversational Claude Code command produces a spec, task list, and populates sync.json for Ralph
3. **Ralph** — autonomous bash execution loop that runs tasks from `state/sync.json` using `claude --dangerously-skip-permissions --print`

## Running Ralph

```bash
bash scripts/ralph.sh [--tool claude|amp] [--model MODEL] [--max N] [--skip-qc] [--dry-run]
```

Ralph requires `vibekit.config.sh` at project root and `state/sync.json` to exist before running. Dry-run shows the preflight summary and exits without executing. `--skip-qc` bypasses the post-completion QC loop.

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

### `scripts/qc-prompt.md`
Prompt template for the QC agent. Runs after all tasks complete. Reads `brief.md`, surveys what was built, and either emits `[QC_COMPLETE]` (no gaps) or appends new tasks to `tasks.md` and updates `state/sync.json` for Ralph to continue.

### Sentinel protocol
Claude emits one of these at end of task output:
```
[TASK_COMPLETE: T042]
[TASK_BLOCKED: <specific human-readable reason>]
[SESSION_HANDOFF]
```
The QC agent emits `[QC_COMPLETE]` (no brackets pair — standalone) when no gaps are found.

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
    "relevant_files": [],
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

## Commit Prefixes

```
[claude-docs]   knowledge graph updates (sync agent)
[plan]          spec + task generation
[ralph]         task completions
[ralph] QC-T### complete — QC-identified gap fix
```
