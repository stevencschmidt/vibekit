# Tasks: 001-framework-enhancements

- [x] T001 · Auto-populate verify_build() in /plan skill
- [x] T002 · Structured delta checks in sync agent
- [ ] T003 · Implement manifest.json end-to-end
- [ ] T004 · Checkpoint QC triggers in ralph.sh

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
