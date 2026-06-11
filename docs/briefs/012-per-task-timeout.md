# Brief 012 — Per-task timeout override + fast-verify rule for docs tasks

## Problem

A phramewerks task ("Docs reconcile + DECISION:016 + manifest + full suite") stalled
3× and stopped Ralph. Root cause: it was a **markdown-only** task whose `Verify:` line
was `bash scripts/test.sh` → `docker compose run --rm api pytest` (the full backend
integration suite, which includes tests that call the real `claude` CLI). That suite
outlives the global 1800s agent-session watchdog (DECISION:013): the agent ran it in
the foreground (correctly, per the spec-011 no-background rule), the watchdog killed it
at exactly 1800s (rc=124) twice, and the 3-strike stall stopped the run.

Every vibekit guardrail behaved as designed — this is not broken code. But it exposes
two real gaps:

1. **No per-task timeout.** `RALPH_TASK_TIMEOUT` is a single global (1800s). A task whose
   *legitimate* verify honestly needs longer can never pass — it always times out →
   stalls → stops. There is no way for a task to declare "I need more time" or "disable
   the watchdog for me".
2. **No planning guard against heavy verifies on light tasks.** vibekit's vibeplan SKILL
   does not stop a planner from giving a docs/markdown-only task a full-integration-suite
   `Verify:`. The recurring "+ full suite" final-task shape gates trivial markdown edits
   on a 30-min Docker/e2e run.

## Goal

- A task can declare a per-task timeout that overrides the global default (including a
  value that disables the watchdog for a genuinely long task).
- Ralph resolves and applies that per-task timeout for the task's agent session; the
  global default still applies when a task declares nothing.
- The vibeplan planner is instructed to give docs/markdown-only tasks a fast, bounded
  verify and never gate them on the full/e2e/Docker integration suite.

## Constraints

- vibekit source only (FIREWALL: never run git in phramewerks). Sync back via
  `scripts/push-to-phramewerks.sh` after completion.
- bash + python3 only — no new runtime dependencies.
- Follow the existing `Tier:` precedent exactly: a `Timeout:` line in the task body,
  parsed by the same next-task parser, written to `state/sync.json`, read by the loop.
- QC stages keep the global timeout (they are not per-task).
- No change to the 3-strike machinery or DECISION:013's kill-and-stall behavior.

## Out of scope

- Changes to the `/vibe_resume` skill.
- phramewerks migration / unblocking T007 (separate phramewerks session).
- Distinguishing "hung" from "legitimately long" automatically (the `Timeout:` override
  is the explicit mechanism instead).
