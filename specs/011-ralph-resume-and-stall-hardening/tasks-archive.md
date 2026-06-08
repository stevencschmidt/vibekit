# Archive: 011-ralph-resume-and-stall-hardening

## T001 · Fix timeout-vs-ratelimit misclassification in ralph.sh
Depends on: —
Verify: `bash -n scripts/ralph.sh && grep -q 'is_usage_exhausted' scripts/ralph.sh`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md, scripts/ralph.sh
Tier: complex

A claude/amp session that HANGS because it is rate-limited gets killed by the
`timeout` wrapper (exit 124/137) and is then misclassified as a stall, because the
timeout→stall classification runs BEFORE `is_rate_limited_output`. This burns the
3-strike counter and exits instead of waiting for the reset.

Fix:
1. Add a small helper near `is_rate_limited_output` (scripts/ralph.sh ~266):
   `is_usage_exhausted()` — returns 0 when the live OAuth usage API reports any
   window (`five_hour` or `seven_day`) at ≥100% utilization. Reuse the existing
   `get_usage` and `get_utilization` helpers and the python float-compare pattern
   already used in `check_usage_before_iteration`. Return non-zero (not exhausted)
   when usage is unavailable, so a genuine hang with no usage signal still counts
   as a stall.
2. In the **main-loop** timeout branch (scripts/ralph.sh ~828, the block that sets
   `OUTPUT="[RALPH_TIMEOUT]"`): before forcing the stall marker, call
   `is_usage_exhausted`. If exhausted, log it, run `wait_for_reset "$TASK_ID"
   "timeout-ratelimit"`, do `ITERATION=$((ITERATION - 1))` and `continue` — matching
   the existing mid-execution rate-limit-wait pattern. Only fall through to the
   `OUTPUT="[RALPH_TIMEOUT]"` stall marker when NOT exhausted.
3. Apply the same guard to the **final-QC** timeout branch (~668) and the
   **checkpoint-QC** timeout branch (~1065): on 124/137, if `is_usage_exhausted`,
   run `wait_for_reset` and `continue` (final-QC) / fall through to the existing
   rate-limit handling (checkpoint) instead of treating the timeout as a skip/retry.

Do not change the `RALPH_TASK_TIMEOUT` default or the 3-strike machinery. Do not
refactor surrounding code.

---

## T002 · Distinct rate-limit exit code + ralph-supervisor.sh auto-resume
Depends on: T001
Verify: `bash -n scripts/ralph.sh && bash -n scripts/ralph-supervisor.sh && grep -q 'RALPH_EXIT_RATE_LIMIT' scripts/ralph.sh scripts/ralph-supervisor.sh`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md, scripts/ralph.sh, scripts/install-service.sh
Tier: medium

Give rate-limit-cap exits a distinct, machine-detectable code so a supervisor can
auto-resume on a usage limit WITHOUT auto-resuming on real failures.

1. In scripts/ralph.sh define a constant near the other config (~72):
   `RALPH_EXIT_RATE_LIMIT=75` (EX_TEMPFAIL). Change every `RATE_LIMIT_CAP` exit path
   (there are three: pre-check in the task loop ~742, pre-check/mid in final QC ~639
   & ~677, and checkpoint QC ~1040 & ~1072) to `exit $RALPH_EXIT_RATE_LIMIT` instead
   of `exit 1`. Leave stall/block/verify-fail/max-iter exits at `exit 1`.
2. Create `scripts/ralph-supervisor.sh` (chmod +x, same header style as ralph.sh):
   - Resolves `SCRIPT_DIR`/`PROJECT_ROOT` like ralph.sh.
   - Defines `RALPH_EXIT_RATE_LIMIT=75` (kept in sync; single source is fine via a
     comment cross-reference).
   - Accepts `--max-relaunch N` (default e.g. 100) and passes any other args through
     to `ralph.sh`.
   - Loop: run `bash "$SCRIPT_DIR/ralph.sh" "$@"`; capture `rc=$?`. If
     `rc -eq RALPH_EXIT_RATE_LIMIT` and relaunch count < max: log "rate-limit exit —
     relaunching after reset", increment count, `continue` (ralph.sh itself does the
     reset wait on its next pre-iteration usage check, so the supervisor can relaunch
     immediately or after a short fixed backoff). For ANY other `rc` (including 0):
     exit with that same `rc` and stop — stalls/blocks/verify-fails still require
     human review.
   - Honor SIGINT/SIGTERM cleanly (do not relaunch after an interrupt).
3. Update `scripts/install-service.sh`: point the unit `ExecStart` at
   `ralph-supervisor.sh` instead of `ralph.sh`, and update the inline notes to
   explain that the supervisor handles rate-limit auto-resume while systemd handles
   reboot survival (keep `Restart=no`).

Do NOT add a blanket `Restart=on-failure` to systemd. The supervisor's exit-code
gate is the only auto-relaunch mechanism.

---

