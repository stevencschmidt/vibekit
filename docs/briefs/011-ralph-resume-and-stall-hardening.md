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
   handling was correct. The actual gap was a timeout-vs-ratelimit ordering bug
   introduced by DECISION:013: at ralph.sh ~828 a timed-out agent (rc 124/137)
   sets `OUTPUT="[RALPH_TIMEOUT]"` **before** `is_rate_limited_output` runs, so a
   claude session that hangs *because it is rate-limited* is counted as a stall
   and exits instead of waiting for reset. Same pattern in the final-QC (~668)
   and checkpoint-QC (~1065) timeout branches.

   `ralph.sh` already auto-resumes across token-limit windows on its own: its
   in-process `wait_for_reset` reads the reset time from the usage API, sleeps,
   and continues the loop. No second process is needed. (Reboot survival, the only
   case a single script cannot self-handle, is covered by the existing
   `install-service.sh` systemd unit.)

## Goal

- A rate-limited hang is never misclassified as a stall.
- `ralph.sh` — the one script the skills launch — keeps auto-resuming after a
  usage-limit reset, in-process, with no separate supervisor to choose between.
- Real stalls/blocks/verify-failures still stop and require human review.
- Agents never strand a turn waiting on a backgrounded long-running command.

## Constraints

- vibekit source only (FIREWALL: never run git in phramewerks). Sync back via
  `scripts/push-to-phramewerks.sh` after completion.
- bash + python3 only — no new runtime dependencies.
- One launch path: auto-resume lives inside `ralph.sh` (what vibeplan/vibe_resume
  already launch). No separate wrapper script the automated flow would never call.
- Preserve the "stalls need review" intent: nothing auto-restarts on
  stall/block/verify-fail/max-iter.

## Out of scope

- Changes to the `/vibe_resume` skill.
- Migrating phramewerks (done in a phramewerks session).
- Re-architecting the 3-strike machinery.
- A separate supervisor/wrapper process (rejected — see DECISION:015).
