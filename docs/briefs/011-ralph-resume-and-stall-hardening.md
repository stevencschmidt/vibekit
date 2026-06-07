# Brief 011 — Ralph resume & stall hardening

## Problem

Two reliability failures surfaced running phramewerks autonomously.

1. **Stall on a background-command task.** A task whose body said "run the full
   suite" was executed on the simple/haiku tier. The agent ran the long test
   suite **in the background** and ended its turn narrating "I'm waiting for the
   test suite to complete" — without emitting `[TASK_COMPLETE]`. Ralph correctly
   classified each attempt as a stall, rolled back, and stopped after 3 strikes.
   The `RALPH_TASK_TIMEOUT` (DECISION:013) did not catch it: each turn returned
   voluntarily in 5–10 min, well under 1800s. `timeout` only catches a *blocking*
   hang, not an agent that detaches a process and returns early. The existing
   ralph-prompt rule against background commands was overridden because the task
   body itself asked for "full suite".

2. **Auto-resume after a usage-limit reset is incomplete.** Spec 006 only reduced
   *chat-session* friction (stop monitoring, session-start notice, optional `at`);
   it left process-level auto-resume out of scope and assumed ralph.sh rate-limit
   handling was correct. Two gaps remain:
   - **Scenario A (ralph exited):** the in-process `wait_for_reset` countdown only
     resumes while ralph stays alive. `install-service.sh` uses `Restart=no` by
     design. If the process dies during the multi-hour sleep (terminal/SSH closed,
     machine sleep) nothing relaunches it after the window resets.
   - **Scenario B (alive but hung):** a timeout-vs-ratelimit ordering bug
     introduced by DECISION:013. At ralph.sh ~828 a timed-out agent (rc 124/137)
     sets `OUTPUT="[RALPH_TIMEOUT]"` **before** `is_rate_limited_output` runs, so a
     claude session that hangs *because it is rate-limited* is counted as a stall
     and exits instead of waiting for reset. Same pattern in the final-QC (~668)
     and checkpoint-QC (~1065) timeout branches.

## Goal

- A rate-limited hang is never misclassified as a stall.
- Ralph can resume automatically after a usage-limit reset even when the process
  fully exits — without auto-restarting on real stalls/blocks/verify-failures
  (those still require human review).
- Agents never strand a turn waiting on a backgrounded long-running command.

## Constraints

- vibekit source only (FIREWALL: never run git in phramewerks). Sync back via
  `scripts/push-to-phramewerks.sh` after completion.
- bash + python3 only — no new runtime dependencies.
- Cross-platform (WSL / Git Bash / macOS) — the auto-resume mechanism must not be
  systemd-only.
- Preserve the "stalls need review" intent: auto-relaunch fires ONLY on the
  rate-limit exit path, never on stall/block/verify-fail/max-iter.

## Out of scope

- Changes to the `/vibe_resume` skill.
- Migrating phramewerks (done in a phramewerks session).
- Re-architecting the 3-strike machinery.
