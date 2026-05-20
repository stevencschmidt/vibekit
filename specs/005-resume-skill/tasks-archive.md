# Archive: 005-resume-skill

## T001 · Write templates/.claude/skills/resume/SKILL.md
Depends on: —
Verify: `head -5 templates/.claude/skills/resume/SKILL.md | grep -q "^name:"` exits 0
Relevant: docs/claude/conventions.md, templates/.claude/skills/vibeplan/SKILL.md

Create `templates/.claude/skills/resume/SKILL.md`. This is a new Claude Code skill that
resumes a paused vibekit session without replanning.

**Frontmatter (required — must be the first lines of the file):**

```
---
name: resume
description: Resume a paused vibekit session. Checks Ralph state, reports progress, and picks up from the right point without replanning.
trigger: /resume
---
```

**Skill body — write this content verbatim after the frontmatter:**

```
# /resume — Resume Paused vibekit Session

You are resuming a session interrupted by a usage limit, terminal close, or restart.
Do not replan. Do not regenerate specs. Pick up exactly where things left off.

## Step 1 — Check Ralph

1. Check if `state/ralph.pid` exists. If it does, read the PID.
2. Run `kill -0 <pid>` to test if the process is alive.
3. **If alive:** Say "Ralph is still running (PID `<pid>`). Reconnecting..." then monitor:
   ```
   tail -f state/ralph.log | grep -E "TASK_START|Completed|RATE_LIMIT|RATE_LIMIT_RESUMED|QC_CHECKPOINT|QC_FINAL|SPEC_COMPLETE|Stopped:|STALLED"
   ```
   Translate events per vibeplan's monitoring table. Stop here — do not continue to Step 2.
4. **If not alive (or no pid file):** Delete `state/ralph.pid` if present. Continue to Step 2.

## Step 2 — Read State

Read silently:
- `state/sync.json` → `ralph.task_id`, `ralph.task_title`, `execution.current_task_status`
- `vibekit.config.sh` → find `SPEC_TASKS_FILE`
- The file at `SPEC_TASKS_FILE` → count `- [x]` (done) vs `- [ ]` (pending)
- Last 20 lines of `state/ralph.log`

## Step 3 — Report

Present a single status block:

```
Resume — <spec-slug from SPEC_TASKS_FILE path>
─────────────────────────────────
Tasks:    <N done> of <M total> complete
Current:  <task_id> · <task_title>
Last log: <last meaningful line from ralph.log>
```

**Edge cases (report and stop — do not proceed to Step 4):**
- `ralph.task_id` is null and no `- [ ]` tasks remain → "All tasks complete. Run `/vibeplan` to scope the next spec."
- `SPEC_TASKS_FILE` is unset or the file does not exist → "No active spec found. Run `/vibeplan <brief>` to start."

## Step 4 — Resume

Immediately after the status report, take one action based on the condition that applies:

| Condition | Action |
|-----------|--------|
| Pending `- [ ]` tasks remain | Run `bash scripts/ralph.sh` immediately |
| Last log shows `TASK_BLOCKED: <reason>` | Surface the reason. Say "Resolve the block then run `bash scripts/ralph.sh`." Do NOT restart Ralph. |
| All tasks complete | Say "All tasks done. Run `/vibeplan` to scope the next spec." |
| No active spec | Say "Run `/vibeplan <brief>` to start." |
```

Ensure the file ends with a newline. The frontmatter must appear at the very top of the file
(line 1 must be `---`).

---

## T002 · Update templates/CLAUDE.md — add /resume to Session Policy
Depends on: T001
Verify: `grep -q "/resume" templates/CLAUDE.md` exits 0
Relevant: docs/claude/conventions.md

Read `templates/CLAUDE.md`. Locate the Session Policy section. After the line:

```
2. Run `bash scripts/ralph.sh` to execute
```

Add this line immediately after (same indentation level, blank line before it):

```
**After a usage-limit pause or session restart:** `/resume`
```

Do not change any other content in the file.

---

## T003 · Update init.sh — copy resume skill during scaffold
Depends on: T002
Verify: `bash -n init.sh` exits 0
Relevant: docs/claude/conventions.md

Read `init.sh`. Make exactly two edits:

**Edit 1** — After the line:
```
mkdir -p "$TARGET_DIR/.claude/skills/knowledge-graph-sync"
```
Add:
```
mkdir -p "$TARGET_DIR/.claude/skills/resume"
```

**Edit 2** — After the block:
```
cp "$VIBEKIT_DIR/templates/.claude/skills/knowledge-graph-sync/SKILL.md" \
   "$TARGET_DIR/.claude/skills/knowledge-graph-sync/SKILL.md"
```
Add:
```
cp "$VIBEKIT_DIR/templates/.claude/skills/resume/SKILL.md" \
   "$TARGET_DIR/.claude/skills/resume/SKILL.md"
```

Verify with `bash -n init.sh` exits 0 before emitting TASK_COMPLETE.

---

## T004 · CHANGELOG entries for spec 005
Depends on: T003
Verify: `grep -q "resume" CHANGELOG.md` exits 0
Relevant: docs/claude/conventions.md

Read `CHANGELOG.md`. Find the `## [Unreleased]` section. Add entries following the existing
format. If `### Added` and `### Changed` subsections already exist under `[Unreleased]`, append
to them. If they do not exist, create them.

Under **### Added**:
```
- `/resume` skill — resumes a paused session without replanning; checks `state/ralph.pid`, reads `sync.json` + active `tasks.md`, restarts Ralph if tasks remain or guides to `/vibeplan` if complete
```

Under **### Changed**:
```
- `templates/CLAUDE.md` — Session Policy now references `/resume` for post-pause recovery
- `init.sh` — scaffolds `resume` skill alongside `vibeplan` and `knowledge-graph-sync`
```

Do not modify any versioned release section or entries outside `[Unreleased]`.
