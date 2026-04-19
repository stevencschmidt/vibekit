# Architecture

> Load this file when working on vibekit's structure, pillars, or component relationships.

---

## Three-Pillar Architecture

```
Pillar 1: Knowledge Graph     — prevents context bloat and rot
Pillar 2: /plan Skill         — spec + task generation (interactive)
Pillar 3: Ralph Execution     — autonomous task execution loop
```

These are independent systems that integrate at well-defined boundaries. The sync agent is not part of Ralph. Ralph is not a context management tool.

---

## Components

### scripts/ralph.sh
Autonomous execution loop. Per iteration:
1. Sources `vibekit.config.sh` + `scripts/sync-helpers.sh` + `scripts/monitor.sh`
2. Reads `ralph.task_id` from `state/sync.json`
3. Substitutes `{{SKILLS_CONTEXT}}` in `scripts/ralph-prompt.md` with loaded skill manifests
4. Runs `claude --dangerously-skip-permissions --print --model $MODEL`
5. Detects sentinels in output, runs `verify_build()` on TASK_COMPLETE, rolls back on failure

### scripts/sync-helpers.sh
Three functions operating on `$SYNC_FILE`:
- `sync_read "ralph.task_id"` — dot-notation field access
- `sync_write "ralph.last_sentinel" "..."` — atomic write via temp file + rename
- `session_log_append` — appends to `$SESSION_LOG_FILE`

### scripts/monitor.sh
Sentinel detection from Claude output strings:
- `detect_sentinel "$OUTPUT"` → `TASK_COMPLETE | TASK_BLOCKED | SESSION_HANDOFF | ""`
- `extract_task_id "$OUTPUT"` → `T###`
- `extract_block_reason "$OUTPUT"` → reason string

### scripts/ralph-prompt.md
The prompt template Claude reads each iteration. Contains task execution rules, sentinel protocol, and `{{SKILLS_CONTEXT}}` placeholder substituted at runtime.

### scripts/sync-agent.sh
Hook runner. Invoked by `.claude/settings.json` PreCompact and SessionEnd hooks. Passes the knowledge-graph-sync skill content to `claude --print` as a sidecar process.

### templates/
Files copied verbatim (scripts) or with `PROJECT_NAME` substitution into target projects by `init.sh`.

### init.sh
Entry point for setting up a new project. Copies scripts, templates, creates directory structure, optionally runs `git init`.

---

## Key Boundaries

- Ralph does NOT run the sync agent. Ralph is self-contained.
- The sync agent has NO access to the parent session's conversation history. It uses `git diff HEAD` + `git log` as proxy signals.
- Two `decisions.md` files exist with distinct purposes:
  - `state/decisions.md` — Ralph's inter-task coherence log (patterns, choices per task)
  - `docs/claude/decisions.md` — KG audit log (architectural decisions with anchors)
- `vibekit.config.sh` is **not** in this repo — it lives in target projects.

---

## Distribution Model

vibekit is a standalone repo. `init.sh` scaffolds the system into target projects. No global install. Deps: `bash`, `python3`, `claude` CLI.
