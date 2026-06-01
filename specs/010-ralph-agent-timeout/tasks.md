# Tasks: 010-ralph-agent-timeout

- [x] T001 · ralph.sh: timeout-wrap all agent invocations + classify timeout as a stall
- [x] T002 · ralph-prompt.md: forbid non-terminating / background commands
- [x] T003 · config default + DECISION:013 + docs note

---

## T003 · config default + DECISION:013 + docs note
Depends on: T002
Verify: `grep -q 'RALPH_TASK_TIMEOUT' templates/vibekit.config.sh && grep -q 'DECISION:013' docs/claude/decisions.md` exits 0
Relevant: docs/claude/conventions.md, docs/claude/decisions.md, CLAUDE.md
Tier: simple

Three small edits:

1. **`templates/vibekit.config.sh`** — add a documented, commented override line near
   the other tunables (e.g. after `MODEL_QC`):
   ```bash
   # RALPH_TASK_TIMEOUT=1800   # seconds before a hung agent session is killed; 0 disables. Default 1800 (set in ralph.sh).
   ```
   Add the same commented line to the repo-root `vibekit.config.sh` (the live one) so
   it is discoverable, but leave it commented (ralph.sh defaults it).

2. **`docs/claude/decisions.md`** — append:
   ```markdown
   <!-- DECISION:013 | domains: architecture, conventions -->
   ## DECISION:013 — Agent-session timeout (hang recovery)

   - ralph.sh now wraps every claude/amp invocation in `timeout -k 30 ${RALPH_TASK_TIMEOUT:-1800}`.
   - A timed-out agent (exit 124/137) is rolled back and counted as a stall, reusing the
     existing 3-strike machinery. The prompt forbids non-terminating commands (`tail -f`, etc.).
   - Why: a hung inner agent (observed: an agent ran `tail -f` on ralph's own log) blocked
     ralph.sh on the `claude | tee` pipe for 13+ hours. Recovery only ran after the agent
     returned, so nothing fired. Bounding the session makes every hang recoverable.
   - Considered but rejected: per-tool-call timeouts (not reachable from the loop); `flock`-style
     watchdog process (heavier, less portable than coreutils `timeout`).
   ```
   Then bump the counter in `CLAUDE.md` ("Total decisions: 012" → "Total decisions: 013").

3. **`docs/claude/conventions.md`** — add a short note under the concurrency/robustness
   material recording the hang-recovery convention: agent sessions are time-bounded by
   `RALPH_TASK_TIMEOUT` (default 1800s, `0` disables); a timeout is classified as a stall;
   the agent prompt forbids non-terminating commands. Cross-reference DECISION:013.

Commit: `[ralph] T003 complete — RALPH_TASK_TIMEOUT config + DECISION:013 + conventions note`
