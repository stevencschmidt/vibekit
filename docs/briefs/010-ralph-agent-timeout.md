# Brief: 010-ralph-agent-timeout

## Problem

Ralph's execution loop freezes indefinitely when the inner `claude`/`amp` agent
runs a non-terminating command or otherwise hangs. `scripts/ralph.sh` wraps every
agent invocation as `claude ... | tee "$_TMPOUT"` with **no timeout**. If the agent
never exits, ralph.sh blocks on that pipe forever.

All of ralph's recovery machinery — stall counter, build-fail counter, rate-limit
countdown, 3-strike rollback — runs *after* `claude` returns. When `claude` never
returns, none of it can fire. A single hung child wedges the whole unattended loop.

Confirmed in phramewerks: iteration 9 on T008 launched a `claude --print` agent that
ran `tail -f state/ralph.log | grep ...` via its Bash tool. `tail -f` never exits;
the agent's Bash tool blocked on it; `claude --print` never returned; `ralph.sh`
(PID 390663) sat blocked on the pipe for 13+ hours until killed manually.

## Goal

Make every agent invocation time-bounded and every hang recoverable, so an
unattended Ralph run can never freeze permanently.

## Approach

1. **ralph.sh** — wrap all three agent invocations (main task loop, final QC,
   checkpoint QC) in `timeout`. Detect the timeout exit code and treat a timed-out
   task exactly like a stall: roll back, count it against the 3-strike stall budget,
   and continue. Timeout duration is configurable; defaults sanely without config.
2. **ralph-prompt.md** — instruct the agent never to run non-terminating / background
   / follow commands, reinforcing the existing "run only the Verify: command" rule.
3. **config + docs** — expose `RALPH_TASK_TIMEOUT` as a documented override, record
   the decision, and note the hang-recovery convention.

## Out of scope

- Per-tool-call timeouts inside the agent (we bound the whole agent session, not
  individual tool calls).
- Changing the stall/build-fail 3-strike counts.
- Rate-limit handling (unchanged).

## Hard constraints

- Bash + python3 only; must stay portable (no `flock`). `timeout` is coreutils —
  acceptable (already assumed by the stack).
- The fix must not break the existing pipe-to-`tee` live-output behavior.
- Capturing the agent's real exit code through the pipe requires `${PIPESTATUS[0]}`
  (a plain `$?` returns `tee`'s exit status, not the agent's).
