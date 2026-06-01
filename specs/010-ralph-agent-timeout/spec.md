# Spec: 010-ralph-agent-timeout

## Summary

Bound every `claude`/`amp` agent invocation in `scripts/ralph.sh` with a timeout and
make a timed-out task recover like a stall, so a hung agent can never freeze an
unattended Ralph run.

## Success criteria

- Every agent invocation in `ralph.sh` (main task loop, final QC, checkpoint QC) is
  wrapped in `timeout`.
- A timed-out main-task agent is rolled back and counted against the existing 3-strike
  stall budget; the loop continues instead of blocking forever.
- The timeout is configurable via `RALPH_TASK_TIMEOUT` and has a sane built-in default
  (1800s) so it works with no config change.
- The agent prompt explicitly forbids non-terminating / background / follow commands.
- `bash -n scripts/ralph.sh` passes; the live `| tee` output behavior is preserved.

## Hard constraints

- Bash + python3 + coreutils `timeout` only. No `flock`.
- Capture the agent's true exit status through the pipe with `${PIPESTATUS[0]}`, not `$?`.
- Do not alter rate-limit handling or the 3-strike thresholds.

## Out of scope

- Per-tool-call timeouts inside the agent.
- Any change to phramewerks git history (sync is file-only, done after the spec).

## Technical approach

`timeout -k "${RALPH_KILL_GRACE:-30}" "${RALPH_TASK_TIMEOUT:-1800}" claude ... | tee "$_TMPOUT"`
then read `_rc=${PIPESTATUS[0]}`. `timeout` returns 124 when it sends the signal and 137
when the `-k` grace SIGKILL lands. On either, log a `TIMEOUT` event and force the
no-sentinel path so the existing stall branch rolls back and increments the stall
counter. For the two QC sites, a timeout is logged and treated as a no-progress round
(`continue`) — the `MAX_QC_ROUNDS` cap already bounds repeats.

## Dependencies

- Builds on spec 009 (ralph concurrency/robustness). No code dependency; 009 is complete.
