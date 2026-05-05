# Tasks: 001-framework-enhancements

- [x] T001 · Auto-populate verify_build() in /plan skill
- [x] T002 · Structured delta checks in sync agent
- [x] T003 · Implement manifest.json end-to-end
- [x] T004 · Checkpoint QC triggers in ralph.sh
- [x] T005 · Make sync-agent.sh non-blocking (auto-compact fix)
- [x] T006 · Split tasks.md — completed bodies move to tasks-archive.md
- [x] T007 · Split brief.md + drift check in completion QC
- [x] T008 · session_log_append coverage + QC stall diagnostic + commit hygiene
- [x] T009 · Document new conventions in domain files
- [x] T010 · Fix sync_write/safety_commit ordering in ralph.sh
- [ ] T011 · Fix state file commit gap in ralph.sh
- [ ] T012 · Document inline monitoring pattern in conventions.md

---

## T011 · Fix state file commit gap in ralph.sh
Depends on: T010
Verify: `bash -n scripts/ralph.sh && grep -q "state files" scripts/ralph.sh`
Relevant: docs/claude/conventions.md, scripts/ralph.sh

**Problem:** `ralph.sh` never commits `state/sync.json` or `state/session-log.json` after QC completes or at run end. These state files are swept up by the *next* run's `safety_commit` with the misleading "POST-COMPLETE FALLBACK COMMIT" label, making it look like Claude failed to commit when it was actually just lingering state from the previous run.

**What to do:**

Add a small dedicated git commit for state files at three exit paths in `scripts/ralph.sh`:

1. **QC_COMPLETE path** — after the existing `break` that exits the QC loop, add:
   ```bash
   git add state/sync.json state/session-log.json 2>/dev/null || true
   git diff --cached --quiet || git commit -m "[claude-docs] state files post-QC_COMPLETE"
   ```

2. **Stall-exit path** — after the stall counter hits 3 and the loop exits, add the same two lines with message `"[claude-docs] state files post-stall-exit"`.

3. **Max-iter path** — after the max-iterations check exits the loop, add the same two lines with message `"[claude-docs] state files post-max-iter"`.

Use `git diff --cached --quiet || git commit` so the commit is a no-op when state files are already clean (idempotent).

Commit with `[ralph] T011 complete — fix state file commit gap`.

---

## T012 · Document inline monitoring pattern in conventions.md
Depends on: T011
Verify: `grep -q "run_in_background" docs/claude/conventions.md && grep -q "poll loop" docs/claude/conventions.md`
Relevant: docs/claude/conventions.md

**Problem:** When running Ralph from an interactive Claude Code session, the natural instinct is to use `Monitor` with `tail -f state/ralph.log`. But persistent `Monitor` tail pipes buffer notifications silently — terminal events are swallowed and Claude never sees them. The correct pattern (`Bash run_in_background` + a poll loop) is not documented anywhere.

**What to do:**

Add a new section **"Running Ralph from an Interactive Session"** to `docs/claude/conventions.md`:

```markdown
## Running Ralph from an Interactive Session

When launching Ralph from within Claude Code, use `Bash run_in_background` for the ralph.sh invocation, then monitor with a poll loop — NOT a persistent `Monitor tail -f` pipe.

**Correct pattern:**
```bash
# Launch (run_in_background: true)
nohup bash scripts/ralph.sh > state/ralph.log 2>&1

# Poll loop (run_in_background: true)
until grep -qE "QC_COMPLETE|=== Stopped" state/ralph.log; do sleep 5; done
```

`Monitor` with `tail -f` pipes buffer terminal events silently and Claude will not receive them. The poll loop exits as soon as the sentinel line appears, triggering a notification.
```

Place this section after the existing **"Atomic Operations"** section and before **"Error Handling"**.

Commit with `[ralph] T012 complete — document inline monitoring pattern`.

---

