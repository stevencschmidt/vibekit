# Tasks: 001-framework-enhancements

- [x] T001 · Auto-populate verify_build() in /plan skill
- [x] T002 · Structured delta checks in sync agent
- [x] T003 · Implement manifest.json end-to-end
- [x] T004 · Checkpoint QC triggers in ralph.sh
- [x] T005 · Make sync-agent.sh non-blocking (auto-compact fix)
- [ ] T006 · Split tasks.md — completed bodies move to tasks-archive.md
- [ ] T007 · Split brief.md + drift check in completion QC
- [ ] T008 · session_log_append coverage + QC stall diagnostic + commit hygiene
- [ ] T009 · Document new conventions in domain files

---

## T001 · Auto-populate verify_build() in /plan skill
Depends on: —
Verify: `grep -q "verify_build" templates/.claude/skills/plan/SKILL.md && grep -q "verify_build" sandbox/ragtest/.claude/skills/plan/SKILL.md && bash -n vibekit.config.sh`
Relevant: docs/claude/conventions.md

**Problem:** The current `/plan` skill writes `verify_build() { return 0; }` into `vibekit.config.sh` as a stub. During the ragtest pilot every task "passed" verification regardless of whether the code actually worked — T007 shipped a product whose server wouldn't start. Ralph's 3-strike failure protection is useless if `verify_build()` never returns non-zero.

**What to do:**

Edit `templates/.claude/skills/plan/SKILL.md` and `sandbox/ragtest/.claude/skills/plan/SKILL.md` (keep them in sync). In the "On Confirmation — Write Everything" section, add a new step (insert before the settings-verification step, renumber following steps) titled **"Populate verify_build() in vibekit.config.sh"** that instructs Claude to:

1. Detect the project's primary stack from the brief / proposed files:
   - Python if `requirements.txt`, `pyproject.toml`, or `.py` entry file
   - Node if `package.json`
   - Go if `go.mod`
   - Rust if `Cargo.toml`
   - Bash-only otherwise
2. Write a `verify_build()` body appropriate to the stack. Suggested templates:
   - **Python:** `python -c "import ast; ast.parse(open('<entry>').read())"` plus `python -c "from <module> import <name>"` if importable entry exists
   - **Node:** `npx tsc --noEmit 2>/dev/null || true` plus `node --check <entry>.js` if JS
   - **Go:** `go build ./...`
   - **Rust:** `cargo check --quiet`
   - **Bash:** `bash -n <each shell script>` for every `.sh` in scripts/
3. The skill must *not* write `return 0` as the only body. The skill should fail the plan if no plausible verify exists and ask the user for one.

Do NOT modify the existing `vibekit.config.sh` in the vibekit repo — this task is about the `/plan` skill's future behavior, not retroactively rewriting this project's config.

Add a decision entry to `docs/claude/decisions.md`:
```
<!-- DECISION:002 | domains: stack, conventions -->
## DECISION:002 — Stack-aware verify_build() populated by /plan

- Files updated: templates/.claude/skills/plan/SKILL.md, sandbox/ragtest/.claude/skills/plan/SKILL.md
- Why: ragtest pilot shipped broken code because verify_build() was a return-0 stub
- Considered but rejected: enforcing a single universal verify command (too restrictive); skipping verify entirely (removes Ralph's failure protection)
```

Increment the decision counter in `CLAUDE.md` from `001` to `002`.

Commit with `[ralph] T001 complete — verify_build auto-population in /plan`.

---

## T002 · Structured delta checks in sync agent
Depends on: T001
Verify: `grep -qi "structured delta\|requirements.txt\|dependency" templates/.claude/skills/knowledge-graph-sync/SKILL.md && grep -qi "structured delta\|requirements.txt\|dependency" sandbox/ragtest/.claude/skills/knowledge-graph-sync/SKILL.md`
Relevant: docs/claude/architecture.md

**Problem:** The ragtest pilot made three major dependency changes (`google-generativeai → google-genai`, removed `raganything`/`PyPDF2`/`python-docx`, changed embed model). The sync agent fired on every PreCompact/SessionEnd hook but never produced a `[claude-docs]` commit. The agent reads `git diff HEAD` looking for "signals" but a 339-line `server.py` diff buried the stack-level change.

**What to do:**

Edit `templates/.claude/skills/knowledge-graph-sync/SKILL.md` and `sandbox/ragtest/.claude/skills/knowledge-graph-sync/SKILL.md`. Insert a new step **"Step 1.5 — Structured Delta Checks"** between the existing Step 1 (Examine What Changed) and Step 2 (Check for Signals). The step must instruct the agent to:

1. **Manifest file vs stack.md.** If `requirements.txt`, `package.json`, `go.mod`, `Cargo.toml`, or `pyproject.toml` changed in the current diff, parse it and compare against `docs/claude/stack.md`:
   - Any package in the manifest file not listed in stack.md → mandatory signal (new dep, or renamed, or version-critical)
   - Any package in stack.md not in the manifest file → mandatory signal (removed)
2. **Imports vs documented deps.** For each changed source file (*.py, *.ts, *.js, *.go, etc.), extract top-level imports and compare against stack.md. A top-level import of an undocumented package → mandatory signal.
3. If any structured check fires, treat it as a confirmed write signal — do NOT exit silently even if the free-form signal check in Step 2 finds nothing. Update stack.md to match reality.

Keep the existing signal-based logic (the four signals) as the fallback for non-stack-structural changes.

Commit with `[ralph] T002 complete — structured delta checks in sync agent`.

---

## T003 · Implement manifest.json end-to-end
Depends on: T002
Verify: `test -f templates/docs/claude/manifest.json && python3 -c "import json; m = json.load(open('templates/docs/claude/manifest.json')); assert 'files' in m, 'missing files key'" && grep -q "manifest.json" templates/CLAUDE.md && grep -q "manifest.json" templates/.claude/skills/plan/SKILL.md && grep -q "manifest.json" templates/.claude/skills/knowledge-graph-sync/SKILL.md`
Relevant: docs/claude/architecture.md, knowledge-graph-brief.md

**Problem:** The knowledge-graph-brief.md was updated (three sessions ago) with the manifest.json design replacing the static routing table. The brief agrees it; the code doesn't exist. Without manifest.json the framework still relies on hand-maintained routing tables in CLAUDE.md, which will stop scaling as projects accumulate domain files.

**What to do:**

1. Create `templates/docs/claude/manifest.json` with the schema from knowledge-graph-brief.md:
   ```json
   {
     "files": [
       {
         "path": "docs/claude/architecture.md",
         "summary": "(one-line summary of what architecture.md covers)",
         "tags": ["architecture", "design", "boundaries"]
       },
       {
         "path": "docs/claude/conventions.md",
         "summary": "(one-line summary)",
         "tags": ["style", "patterns", "naming"]
       },
       {
         "path": "docs/claude/stack.md",
         "summary": "(one-line summary)",
         "tags": ["dependencies", "libraries", "tooling"]
       }
     ]
   }
   ```
   Use generic summaries appropriate for the template.

2. Update `templates/CLAUDE.md`: replace the current `## Domain Files` routing table with the standing instruction from the brief:
   > Before starting any task, read `docs/claude/manifest.json`. Based on the task at hand, identify the 1–3 most relevant domain files. Read only those files. State which files you loaded and why.

3. Update `templates/.claude/skills/plan/SKILL.md`: during bootstrap (first run), write `docs/claude/manifest.json` populated with entries for every domain file created. On subsequent runs, update the manifest if new domain files are added.

4. Update `templates/.claude/skills/knowledge-graph-sync/SKILL.md`: whenever a domain file is created, split, merged, or meaningfully updated, the agent must update the manifest entry (summary and tags) in the same commit.

5. Update `init.sh` to copy `templates/docs/claude/manifest.json` when scaffolding a new project.

Do NOT modify `sandbox/ragtest/` in this task — leave ragtest's routing table as-is. A future task can migrate it once the template is proven.

Add decision entry to `docs/claude/decisions.md`:
```
<!-- DECISION:003 | domains: architecture -->
## DECISION:003 — manifest.json replaces static routing table

- Files updated: templates/docs/claude/manifest.json (new), templates/CLAUDE.md, templates/.claude/skills/plan/SKILL.md, templates/.claude/skills/knowledge-graph-sync/SKILL.md, init.sh
- Why: The static routing table doesn't scale past ~10 domain files and must be manually maintained. The manifest lets Claude self-select the right files at session open.
- Considered but rejected: keyword-based routing (too imprecise); fuzzy vector search (infrastructure overkill for a markdown index)
```

Increment decision counter in `CLAUDE.md` from `002` to `003`.

Commit with `[ralph] T003 complete — manifest.json end-to-end`.

---

## T004 · Checkpoint QC triggers in ralph.sh
Depends on: T003
Verify: `bash -n scripts/ralph.sh && grep -q "CHECKPOINT_QC_EVERY\|checkpoint_qc" scripts/ralph.sh`
Relevant: docs/claude/conventions.md

**Problem:** The QC loop currently fires only when all tasks are marked `[x]`. By then, any architectural drift has been baked into every preceding commit. In ragtest, T002–T006 ran against a broken assumption (wrong SDK package name) and QC had to unwind it after the fact.

**What to do:**

Edit `scripts/ralph.sh` only. Leave the skill files and templates untouched. Add:

1. **New env var:** `CHECKPOINT_QC_EVERY` — default `3`. Reads from `vibekit.config.sh` if set there, else `3`. Value `0` disables checkpoint QC entirely (equivalent to current behavior).
2. **Counter:** `TASKS_SINCE_CHECKPOINT` — initialized to 0, incremented after every successful `safety_commit`, reset to 0 after a checkpoint QC runs.
3. **Trigger logic:** After a successful task commit, if `TASKS_SINCE_CHECKPOINT >= CHECKPOINT_QC_EVERY` AND there are still unchecked tasks remaining in `SPEC_TASKS_FILE`, fire a single checkpoint-QC iteration:
   - Same invocation pattern as the existing completion QC (uses `QC_PROMPT` + `BRIEF_FILE`)
   - Tag log lines as `[CKPT-N]` where N is the checkpoint number
   - If the checkpoint QC finds gaps, it appends tasks to `tasks.md` the same way the completion QC does, and Ralph picks them up on the next iteration
   - If the checkpoint QC emits `[QC_COMPLETE]`, that just means "no gaps at this checkpoint" — Ralph continues with the next scheduled task (does NOT exit)
   - Reset `TASKS_SINCE_CHECKPOINT` to 0 regardless
4. **Do not double-fire:** if the next task would be the final one, skip the checkpoint — the existing completion QC will run after it. Implement by checking that at least 2 unchecked tasks remain before triggering.

Update `scripts/ralph-prompt.md` if (and only if) necessary to note the new checkpoint behavior; Claude's per-task prompt shouldn't actually need to change.

This task only edits `scripts/ralph.sh`. It must not modify the currently executing ralph loop's behavior — the changes take effect on the next `bash scripts/ralph.sh` invocation. `bash -n` in verify_build() will catch syntax errors.

Commit with `[ralph] T004 complete — checkpoint QC triggers in ralph.sh`.

---

## T005 · Make sync-agent.sh non-blocking (auto-compact fix)
Depends on: T004
Verify: `bash -n scripts/sync-agent.sh && grep -q "disown" scripts/sync-agent.sh && grep -q "timeout 10s" scripts/sync-agent.sh && grep -q "precompact\|sessionend" scripts/sync-agent.sh && grep -q "sync-agent.sh precompact" templates/.claude/skills/plan/SKILL.md`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md

**Problem:** Claude Code's auto-compact failed to fire in a recent ragtest chat despite `autoCompactThreshold: 0.5` being set and the user not dismissing any prompt. The chat reached 62% context. Root cause: `scripts/sync-agent.sh:26` runs `claude --dangerously-skip-permissions --print "$SKILL"` synchronously with no timeout. Claude Code waits for the PreCompact hook to return before compacting; the sub-claude takes 30–120 s, so the parent chat keeps growing past the threshold while the hook is still in flight.

**What to do:**

Edit `scripts/sync-agent.sh`. Replace the existing single-mode invocation block (lines 24–30) with a mode-dispatch that takes the hook context as `$1`:

- `precompact` (default if unset): fire-and-forget. `( claude --dangerously-skip-permissions --print "$SKILL" >/dev/null 2>&1 || true ) & disown`. Hook returns in <500 ms; compaction NEVER blocks on this hook.
- `sessionend`: best-effort with hard timeout. `timeout 10s claude --dangerously-skip-permissions --print "$SKILL" >/dev/null 2>&1 || true`. Sync runs but cannot hang the shutdown.
- Unknown mode: default to fire-and-forget for safety.

Add a single-line append to `state/sync-agent.log` at the top of the script for diagnosability:
```bash
mkdir -p "$PROJECT_ROOT/state" 2>/dev/null || true
echo "[$(date -Iseconds)] sync-agent ${1:-precompact} pid=$$" >> "$PROJECT_ROOT/state/sync-agent.log" 2>/dev/null || true
```

The script must continue to `exit 0` always.

Update `templates/.claude/skills/plan/SKILL.md` step 9 (where `.claude/settings.json` is written): change the hook commands to pass the mode arg:
```json
"PreCompact": [{"hooks":[{"type":"command","command":"bash scripts/sync-agent.sh precompact"}]}],
"SessionEnd": [{"hooks":[{"type":"command","command":"bash scripts/sync-agent.sh sessionend"}]}]
```

Also update `sandbox/ragtest/.claude/settings.json` directly with the new commands so the live ragtest project benefits immediately.

Commit with `[ralph] T005 complete — sync-agent.sh non-blocking`.

---

## T006 · Split tasks.md — completed bodies move to tasks-archive.md
Depends on: T005
Verify: `bash -n scripts/ralph.sh && bash -n scripts/archive-completed-tasks.sh && grep -q "tasks-archive.md" scripts/ralph.sh && grep -q "tasks-archive.md" scripts/ralph-prompt.md && grep -q "tasks-archive.md" scripts/qc-prompt.md && grep -q "tasks-archive.md" templates/.claude/skills/plan/SKILL.md`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md

**Problem:** `specs/001-ragportal/tasks.md` is 32 KB / 708 lines because every completed task body lives in it forever. Each `/plan`, QC pass, and Ralph iteration loads the whole file even though only the checkbox list and the current task's `## T###` body are needed.

**Read-site mapping (verified safe via prior Phase 1 exploration):**
- `ralph.sh:713–726` — checkbox marking only
- `ralph.sh:732–760` — reads next *unchecked* task's body (still in tasks.md)
- `ralph.sh:777–783` — counts unchecked tasks
- `ralph-prompt.md` — reads current task's body (still in tasks.md)
- `qc-prompt.md` — reads checkbox list to find highest T-number; appends new tasks
- `/plan` fix mode — reads checkbox list; appends new tasks

No reader needs an *already-completed* task body during normal operation.

**What to do:**

1. **Extend `scripts/ralph.sh`** at the block currently at lines 713–726 (the checkbox-marking step after a verified task completion). After flipping `- [ ] T###` → `- [x] T###`, run a second Python step that:
   - Reads `tasks.md`, locates the `## T### …` heading for the just-completed task.
   - Extracts the section body bounded by the next `## T` heading or end-of-file.
   - Removes that section from `tasks.md` (write to `.tmp` + atomic rename).
   - Appends it to a sibling `tasks-archive.md` (same directory as `SPEC_TASKS_FILE`). On first write, prepend a `# Archive: <spec-slug>\n\n` header — derive slug from the parent directory name (e.g. `001-ragportal`).
   - If `SPEC_TASKS_FILE` is unset or missing, the archive step is a no-op.

2. **`scripts/ralph-prompt.md`** — under the "Task Format Reference" section, add: *"Completed task bodies are moved to `tasks-archive.md` after each task. You will not normally need to read it."*

3. **`scripts/qc-prompt.md`** — near the section discussing tasks.md structure, add: *"Completed task descriptions live in `tasks-archive.md` if you need historical context. The active checkbox list and unfinished task bodies remain in `tasks.md`."*

4. **`templates/.claude/skills/plan/SKILL.md`** — in Phase 3 step 4, after the tasks.md template block, add: *"As tasks complete, `ralph.sh` moves their `## T###` bodies to `tasks-archive.md`. `/plan` only writes to `tasks.md`."*

5. **Create `scripts/archive-completed-tasks.sh`** (NEW) — one-shot migration helper. Sources `vibekit.config.sh`, reads `SPEC_TASKS_FILE`, finds every `[x] T###` row in the checkbox list, extracts each matching `## T###` body, removes them from `tasks.md`, and writes them to `tasks-archive.md` with the `# Archive: <slug>` header. Atomic writes (`.tmp` + rename). Idempotent — running it twice is a no-op (no `[x]` task bodies remain in tasks.md to extract).

Commit with `[ralph] T006 complete — tasks.md split with archive`.

---

## T007 · Split brief.md + drift check in completion QC
Depends on: T006
Verify: `grep -q "brief-archive" scripts/qc-prompt.md && grep -q "brief-archive" templates/.claude/skills/plan/SKILL.md`
Relevant: docs/claude/architecture.md

**Problem:** `brief.md` is 15 KB and is loaded by every QC pass even when most of it is historical. As scope evolves, the brief should reflect current scope only with prior content in an archive. A drift check at end-of-spec ensures the archive stays consistent with the active brief — and runs inside Ralph (clean context) rather than in chat.

**What to do:**

1. **`templates/.claude/skills/plan/SKILL.md`** — extend Phase 3 step 6 ("Update brief.md") with:

   > When this is a NEW spec or a significant scope shift, ask the user before rewriting `brief.md` to reflect current scope only. If they confirm, append the prior `brief.md` content to `brief-archive.md` with a `## Archived <YYYY-MM-DD>: <reason>` header, then write the trimmed `brief.md`. For simple fix tasks, leave `brief.md` unchanged.

   Add one line to the Phase 3 confirmation block: `Brief: trim to current scope (Y/n)` — only shown when the planning conversation produced a scope shift.

2. **`scripts/qc-prompt.md`** — add a drift-check step to the **completion QC** review (NOT checkpoint QC):

   > If `brief-archive.md` exists, read it after `brief.md`. Report any contradictions between the two — e.g. a hard constraint in `brief-archive.md` that has been silently dropped from `brief.md` without a documented decision. If you find drift, append a `## T### · Reconcile brief drift: <symptom>` task to `tasks.md` (and update `state/sync.json`) instead of emitting `[QC_COMPLETE]`. If no drift is found, proceed to the normal `[QC_COMPLETE]` emission.

   Piggybacks on the existing completion-QC infrastructure — same Ralph invocation, same exit handling. Checkpoint QC is unchanged (drift check fires only at end-of-spec).

Do NOT trim `knowledge-graph-brief.md` or `sandbox/ragtest/brief.md` in this task — that's a manual user action.

Commit with `[ralph] T007 complete — brief.md split with drift check`.

---

## T008 · session_log_append coverage + QC stall diagnostic + commit hygiene
Depends on: T007
Verify: `bash -n scripts/ralph.sh && [ "$(grep -c "session_log_append" scripts/ralph.sh)" -ge 5 ] && grep -q "QC stalled — last" scripts/ralph.sh && grep -q "git status" scripts/ralph-prompt.md`
Relevant: docs/claude/conventions.md

**Problem:** Three small adjacent issues observable in the recent ragtest run:

1. `state/session-log.json` stays `[]` for normal runs — `session_log_append` is only called from the `SESSION_HANDOFF` branch (line 683). TASK_COMPLETE, QC_COMPLETE, stall-stop, and max-iter exits never write a record.
2. When QC fails to emit `[QC_COMPLETE]` *and* doesn't add a task (path at lines 553–559), the script just prints "QC stalled" with no diagnostic. The May-1 ragtest stall is undiagnosable.
3. Every task in the recent log shows "SAFETY COMMIT for T### — Claude did not commit" — Ralph isn't following the prompt's commit instruction.

**What to do:**

**(a) `session_log_append` coverage in `scripts/ralph.sh`:**

Add `session_log_append` calls at:
- **TASK_COMPLETE verified-success path** (after the `safety_commit` at line ~709): per-task record. Use `RALPH_SESSION` and `SESSION_START_ISO` for `started`; current ISO timestamp for `ended`. exit_reason=`TASK_COMPLETE`. tasks_json built from `[$TASK_ID]` (single-element JSON array).
- **QC_COMPLETE exit** (line ~549): final session record before `exit 0`. exit_reason=`QC_COMPLETE`. tasks_json from `TASKS_COMPLETED_SESSION` array.
- **Stall-3-strikes exit** (~line 903), **build-fail-3-strikes exit** (~line 873), **QC-stall exit** (~line 559), **max-iter exit** (~line 917): one record each, with `exit_reason` matching the situation (e.g. `STALL`, `BUILD_FAIL`, `QC_STALL`, `MAX_ITER`).

Pass `"0"` for `estimated_tokens` (field stays in schema; wiring real tokens is out of scope).

**(b) QC stall diagnostic in `scripts/ralph.sh`:**

At the QC-stall path (~lines 553–559) and the analogous checkpoint-QC stall path (~lines 833–838), before the exit/continue append the last 80 lines of `QC_OUTPUT` to the log:
```bash
echo "[QC-$QC_ROUND] QC stalled — last 80 lines of QC output:" >> "$LOG_FILE"
echo "$QC_OUTPUT" | tail -n 80 >> "$LOG_FILE"
echo "[QC-$QC_ROUND] --- end QC output ---" >> "$LOG_FILE"
```
(Use `CKPT-$CHECKPOINT_QC_ROUND` and `CKPT_OUTPUT` for the checkpoint analog.)

**(c) Commit-message enforcement in `scripts/ralph-prompt.md`:**

Replace the existing line 20 ("Commit your work...") with:

> **Commit your work before emitting any sentinel.** After running the `Verify:` command, mark the checkbox in `tasks.md` (`- [ ] T###` → `- [x] T###`), stage all changes with `git add -A`, and commit with message `[ralph] T### complete — <short description>`. Do NOT emit `[TASK_COMPLETE]` until `git status` shows a clean tree. If you emit `[TASK_COMPLETE]` without committing, the safety-commit fallback will fire and your commit message convention will be lost.

Optionally rename `scripts/ralph.sh`'s `safety_commit` log line from `"SAFETY COMMIT for $task_id — Claude did not commit"` to `"POST-COMPLETE FALLBACK COMMIT for $task_id — Claude did not commit"` so future occurrences read as the exception they're meant to be.

Commit with `[ralph] T008 complete — session log + QC diagnostic + commit hygiene`.

---

## T009 · Document new conventions in domain files
Depends on: T008
Verify: `grep -q "tasks-archive\|brief-archive" docs/claude/architecture.md && grep -q "tasks-archive\|brief-archive" docs/claude/conventions.md && grep -q "DECISION:005" docs/claude/decisions.md && grep -q "Total decisions: 005" CLAUDE.md`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md

**Problem:** The new conventions (tasks/brief split, archive files, brief drift check, async sync hook with mode arg) need to be documented so future sessions and the sync agent see them.

**What to do:**

1. **`docs/claude/architecture.md`** — add a paragraph documenting:
   - `tasks.md` (active) + `tasks-archive.md` (completed bodies) split, maintained by `ralph.sh` after each task.
   - `brief.md` (current scope) + `brief-archive.md` (historical) split, trimmed by `/plan` on scope shifts.
   - End-of-spec drift check piggybacks on completion QC: if `brief-archive.md` exists, QC compares it against `brief.md` and appends a reconciliation task on contradiction.
   - `sync-agent.sh` runs PreCompact in fire-and-forget mode; SessionEnd with 10 s `timeout`.
   - Update the manifest.json entry for architecture.md if its summary/tags changed materially.

2. **`docs/claude/conventions.md`** — add a terser version covering:
   - Archive file naming (`<base>-archive.md` for tasks and brief).
   - Hook arg convention (`bash scripts/sync-agent.sh precompact|sessionend`).
   - Update the manifest.json entry for conventions.md if needed.

3. Add decision entry to `docs/claude/decisions.md`:
```
<!-- DECISION:005 | domains: architecture, conventions -->
## DECISION:005 — Active/archive split for tasks.md and brief.md; non-blocking sync hook

- Files updated: scripts/ralph.sh, scripts/sync-agent.sh, scripts/qc-prompt.md, scripts/ralph-prompt.md, scripts/archive-completed-tasks.sh (new), templates/.claude/skills/plan/SKILL.md, docs/claude/{architecture,conventions}.md
- Why: 32KB tasks.md and 15KB brief.md were bloating chat context every /plan and QC pass; sync-agent.sh blocked Claude Code's auto-compact (chat reached 62% with no compaction).
- Considered but rejected: in-place truncation of completed task bodies (loses detail); auto-trim brief on every fix task (over-aggressive); synchronous hook with timeout only (still blocks compaction up to the timeout).
```

Increment the decision counter in `CLAUDE.md` from `004` to `005`.

Commit with `[ralph] T009 complete — document new conventions`.
