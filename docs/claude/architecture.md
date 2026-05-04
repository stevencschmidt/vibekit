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
6. After a successful task, increments `TASKS_SINCE_CHECKPOINT`; fires a checkpoint QC round if `>= CHECKPOINT_QC_EVERY` (default 3) AND ≥2 unchecked tasks remain
7. When all tasks are `[x]`, fires completion QC; exits on `[QC_COMPLETE]`

### scripts/qc-prompt.md
Prompt template for the QC agent. Two invocation contexts:
- **Completion QC** (post-all-tasks) — reads brief.md, surveys the codebase, emits `[QC_COMPLETE]` or appends new tasks to `tasks.md`
- **Checkpoint QC** (mid-spec, every `CHECKPOINT_QC_EVERY` tasks) — same mechanism, tagged `[CKPT-N]` in logs; `[QC_COMPLETE]` means "no gaps here, continue" rather than "spec done"

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
Hook runner. Invoked by `.claude/settings.json` PreCompact and SessionEnd hooks. Passes the knowledge-graph-sync skill content to `claude --print` as a sidecar process. The skill performs two detection passes per invocation:
- **Structured delta checks** (`Step 1.5`) — compares `requirements.txt`/`package.json`/`go.mod`/`Cargo.toml`/`pyproject.toml` against `stack.md`, and compares source-file imports against documented deps; any mismatch is a mandatory write signal
- **Free-form signal sniffing** (`Step 2`) — the original four signals (decision, pattern, understanding shift, explicit resolution); fallback when structured checks pass

### templates/
Files copied verbatim (scripts) or with `PROJECT_NAME` substitution into target projects by `init.sh`. Includes `templates/docs/claude/manifest.json` — the routing index seeded at scaffold time.

### docs/claude/manifest.json (routing index)
Machine-readable index of every domain file: `{"files": [{"path", "summary", "tags"}]}`. Replaces the static routing table in CLAUDE.md. Session-open flow: Claude reads the manifest (~2,000 tokens at 40 files), self-selects 1–3 most relevant files by tags + summary, loads only those. Maintained exclusively by the sync agent — updated in the same commit as any domain file create/split/merge/update.

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
