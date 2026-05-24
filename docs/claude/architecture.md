# Architecture

> Load this file when working on vibekit's structure, pillars, or component relationships.

---

## Three-Pillar Architecture

```
Pillar 1: Knowledge Graph     — prevents context bloat and rot
Pillar 2: /vibeplan Skill      — spec + task generation (interactive)
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
4. Resolves the per-iteration model from the task's `tier` field (`MODEL_SIMPLE`/`MODEL_MEDIUM`/`MODEL_COMPLEX`); build-failure retries escalate one tier; `MODEL_AUTO=false` or `--model` flag uses `$MODEL` for all tasks; both QC stages always run on `MODEL_QC`
5. Runs `claude --dangerously-skip-permissions --print --model $_ITER_MODEL`
6. Detects sentinels in output, runs `verify_build()` on TASK_COMPLETE, rolls back on failure
7. After a successful task, increments `TASKS_SINCE_CHECKPOINT`; fires a checkpoint QC round if `>= CHECKPOINT_QC_EVERY` (default 3) AND ≥2 unchecked tasks remain
8. When all tasks are `[x]`, fires completion QC; exits on `[QC_COMPLETE]`

Empty `SPEC_TASKS_FILE` in `vibekit.config.sh` produces a clean preflight error (exit 2) with guidance to run `/vibeplan`; this check fires after the preflight summary and before any task execution or `--dry-run` exit.

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

### tasks.md / tasks-archive.md Split

`SPEC_TASKS_FILE` (e.g. `specs/001-slug/tasks.md`) holds the checkbox list and the bodies of **uncompleted** tasks only. After each verified task completion, `ralph.sh` moves the `## T###` body for that task to a sibling `tasks-archive.md` file (atomic write; header `# Archive: <spec-slug>` on first write). Readers that only need the checkbox list or the current task's body never load completed task descriptions. `tasks-archive.md` is available for historical reference but is not loaded by default.

### brief.md / brief-archive.md Split

The spec's `brief.md` describes the **current** scope. When `/vibeplan` is invoked in Fix/Debug mode on an existing spec, it trims the brief to reflect the new scope and appends the old content to `brief-archive.md`. The completion QC checks for the existence of `brief-archive.md`; if present, it compares the archived brief against the current `brief.md` and appends a reconciliation task to `tasks.md` if it detects a contradiction (e.g. a removed requirement that was actually implemented).

### scripts/sync-agent.sh
Hook runner. Invoked by `.claude/settings.json` PreCompact and SessionEnd hooks with a mode argument. Passes the knowledge-graph-sync skill content to `claude --print` as a sidecar process. Mode dispatch:
- **`precompact`** (default): fire-and-forget (`& disown`). Hook returns in <500 ms so Claude Code's auto-compact is never blocked.
- **`sessionend`**: best-effort with `timeout 10s`. Sync runs but cannot hang shutdown.

The skill performs two detection passes per invocation:
- **Structured delta checks** (`Step 1.5`) — compares `requirements.txt`/`package.json`/`go.mod`/`Cargo.toml`/`pyproject.toml` against `stack.md`, and compares source-file imports against documented deps; any mismatch is a mandatory write signal
- **Free-form signal sniffing** (`Step 2`) — the original four signals (decision, pattern, understanding shift, explicit resolution); fallback when structured checks pass

### templates/
Files copied verbatim (scripts) or with `PROJECT_NAME` substitution into target projects by `init.sh`. Includes `templates/docs/claude/manifest.json` — the routing index seeded at scaffold time.

### docs/claude/manifest.json (routing index)
Machine-readable index of every domain file: `{"files": [{"path", "summary", "tags"}]}`. Replaces the static routing table in CLAUDE.md. Session-open flow: Claude reads the manifest (~2,000 tokens at 40 files), self-selects 1–3 most relevant files by tags + summary, loads only those. Maintained exclusively by the sync agent — updated in the same commit as any domain file create/split/merge/update.

### init.sh
Entry point for setting up a new project. Copies scripts, templates, creates directory structure, optionally runs `git init`.

---

### State File Commit Gap (known, T011)

`ralph.sh` does not commit `state/sync.json` or `state/session-log.json` after QC completes or at run end. These files are left dirty and swept up by the *next* run's `safety_commit`, which incorrectly labels them "Claude did not commit." T011 will add explicit state-file commits at QC_COMPLETE, stall-exit, and max-iter paths.

### Inline Monitoring Pattern

The `/vibeplan` skill launches Ralph as a detached background process:

```bash
nohup bash scripts/ralph.sh >> state/ralph.log 2>&1 & disown
```

Ralph writes `state/ralph.pid` at startup and removes it on all exit paths. Use Monitor (`tail -f | grep`) for per-event progress mid-run:

```bash
tail -f state/ralph.log | grep -E "TASK_START|Completed|RATE_LIMIT|RATE_LIMIT_RESUMED|QC_CHECKPOINT|QC_FINAL|SPEC_COMPLETE|Stopped:|STALLED"
```

For terminal-state-only notification (no intermediate events), use a poll loop:

```bash
until grep -qE "QC_COMPLETE|Stopped:|Completed:" state/ralph.log; do sleep 5; done
```

**New log events** (added for vibeplan monitoring):
- `TASK_START task=T### title=...` — fires before each Claude invocation
- `RATE_LIMIT_RESUMED window=...` — fires when the rate-limit countdown ends (two variants: `window=<name>` for API-reachable resets, `window=api-unreachable` for connectivity failures)
- `QC_FINAL round=N` — fires before each final QC round
- `QC_CHECKPOINT n=N` — fires before each checkpoint QC round
- `SPEC_COMPLETE spec=<slug>` — fires inside the `exit 0` path of QC_COMPLETE, before Ralph exits

**Multi-brief orchestration** (see vibeplan SKILL.md for details):
- `/vibeplan briefs/` runs a one-time brief audit, then a planning+execution loop across all briefs
- On `SPEC_COMPLETE`, vibeplan automatically advances to Phase 1 of the next brief
- `vibekit.config.sh` stores `BRIEFS_DIR` so the directory can be recovered on session restart
- On session restart, `/vibeplan` checks `state/ralph.pid` and reconnects to a live Ralph process

### Design files (optional)

A `<brief-dir>/design/` subdirectory may contain any number of `*.md` files
describing the project's design constraints (architecture, data model, API contracts,
UX flows, screen layouts, glossary). When present, `/vibeplan` loads them as ambient
context across every brief and every planning phase and runs an audit pass that
surfaces concerns (coverage gaps, missing sections, UX inconsistencies, brief
contradictions, scope creep, ambiguous interactions) before Phase 1's scope-lock
questions. The audit flags concerns; it does not propose solutions.

Design files are not audited or loaded by QC — verification remains driven by task
`Verify:` commands and brief success criteria.

Format: plain markdown, optionally with `mermaid` fenced blocks for diagrams and
ASCII sketches for layouts. Image-only mockups (PNG, Figma exports) are not
supported. The recommended layout-file template names every interactive element via
an Elements table so the audit can enumerate fields/buttons/lists and target
questions per element. See `templates/.claude/skills/vibeplan/SKILL.md` for the full
templates.

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
