---
name: vibe_resume
description: Resume a paused vibekit session. Checks Ralph state, reports progress, and picks up from the right point without replanning.
trigger: /vibe_resume
---

# /vibe_resume — Resume Paused vibekit Session

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
