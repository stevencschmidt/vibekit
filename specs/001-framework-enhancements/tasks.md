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

---

## T010 · Fix sync_write/safety_commit ordering in ralph.sh
Depends on: T009
Verify: `bash -n scripts/ralph.sh`
Relevant: docs/claude/conventions.md

**Problem:** Every task iteration produces a spurious "Claude did not commit" safety commit containing only `state/sync.json`. The root cause: `sync_write "ralph.last_sentinel"` (line ~673) runs *before* `safety_commit` (line ~723), so sync.json is always dirty when the safety check fires. Claude is committing its own work correctly — the safety commit is a false positive and its label is misleading.

**What to do:**

In `scripts/ralph.sh`, move the three `sync_write "ralph.last_sentinel"` calls (TASK_COMPLETE, TASK_BLOCKED, SESSION_HANDOFF paths — currently around lines 673, 677, 695) to *after* the `safety_commit "$TASK_ID"` call at line ~723.

Specifically:
1. Find the sentinel-detection block that writes `ralph.last_sentinel` for TASK_COMPLETE (~line 673), TASK_BLOCKED (~line 677), and SESSION_HANDOFF (~line 695).
2. Remove those three `sync_write "ralph.last_sentinel"` calls from their current location.
3. After `safety_commit "$TASK_ID"` (~line 723), add back only the TASK_COMPLETE write: `sync_write "ralph.last_sentinel" "[TASK_COMPLETE: ${TASK_ID}]"`.
4. For TASK_BLOCKED and SESSION_HANDOFF, the sync_write can remain where it is (those paths exit the iteration immediately and don't call safety_commit).

After this change, `safety_commit` will run on a clean tree when Claude has committed correctly, and the fallback will only fire when Claude genuinely left changes uncommitted.

Also rename the safety-commit log line from `"SAFETY COMMIT for $TASK_ID — Claude did not commit"` to `"POST-COMPLETE FALLBACK COMMIT for $TASK_ID"` so future occurrences are clearly exceptional.

Commit with `[ralph] T010 complete — fix sync_write/safety_commit ordering`.

