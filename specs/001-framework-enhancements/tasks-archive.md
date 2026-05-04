# Archive: 001-framework-enhancements

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
