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
- [x] T011 · Fix state file commit gap in ralph.sh
- [x] T012 · Document inline monitoring pattern in conventions.md

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

