# Spec 012 — Per-task timeout override + fast-verify rule for docs tasks

## Summary

Add a per-task `Timeout:` override (parsed like `Tier:`) so a task can extend or disable
the agent-session watchdog for its own iteration, and add a vibeplan rule that
docs/markdown-only tasks must use a fast, bounded verify rather than the full integration
suite. Motivated by a phramewerks markdown-only task that stalled because its `Verify:`
ran the full Docker pytest suite past the 1800s watchdog.

See `docs/briefs/012-per-task-timeout.md` for the full problem statement.

## Success Criteria

- A `Timeout: <seconds>` line in a `## T###` task body is parsed by ralph.sh's next-task
  parser (the same one that reads `Tier:`/`Relevant:`) and written to
  `state/sync.json` as `ralph.task_timeout`.
- ralph.sh resolves an effective per-iteration timeout: the task's `task_timeout` when set
  (including `0` to disable the watchdog for that task), else the global
  `RALPH_TASK_TIMEOUT` default. The task agent session uses the effective value.
- The final/checkpoint QC stages continue to use the global default (not per-task).
- A task that declares no `Timeout:` behaves exactly as today (global 1800s default).
- `templates/.claude/skills/vibeplan/SKILL.md` instructs the planner: docs/markdown-only
  tasks (and the recurring "reconcile docs + decision" final task) must use a fast bounded
  `Verify:` (AST parse / JSON load / grep) and must NOT gate on the full, e2e, or Docker
  integration suite; the `Timeout:` line is the escape hatch for genuinely long tasks.
- The `Timeout:` field is documented in the task-shape template and the `state/sync.json`
  schema (CLAUDE.md + repo docs).
- Knowledge graph reconciled: `DECISION:016` added; count bumped; `CLAUDE.md` and
  `docs/claude/{conventions.md,architecture.md,manifest.json}` updated.
- `verify_build()` passes (`bash -n` on all scripts, JSON valid).

## Hard Constraints

- bash + python3 only; no new runtime dependencies.
- Mirror the `Tier:` mechanism exactly (parser → sync.json → loop read). No new file.
- `Timeout: 0` disables the watchdog for that task only (consistent with the global
  `RALPH_TASK_TIMEOUT=0` semantics in `ralph_timeout_prefix`).
- QC stages keep the global timeout. No change to the 3-strike machinery or DECISION:013.

## Out of Scope

- `/vibe_resume` skill changes.
- phramewerks migration / unblocking its T007.
- Auto-detecting long vs hung sessions.

## Technical Approach

- **T001** — in ralph.sh's next-task advance parser (the python block that emits
  task_id/title/relevant/tier), also extract a `Timeout:` line (int; default empty) and
  `sync_write "ralph.task_timeout"`. In the main loop, read `ralph.task_timeout`, compute
  `_ITER_TIMEOUT` (task value if a non-negative int, else `RALPH_TASK_TIMEOUT`), and make
  `ralph_timeout_prefix` use the effective value for the task agent call (e.g. accept an
  arg or set an effective env var before the call). QC/checkpoint calls keep the global
  default. Handle the QC-appended-task path gracefully (absent `task_timeout` → default).
- **T002** — vibeplan SKILL edits: the fast-verify rule for docs/markdown tasks; document
  the `Timeout:` line in the task-shape template and note it as the long-task escape hatch.
- **T003** — docs reconcile: DECISION:016, count bump, sync.json schema (`task_timeout`),
  CLAUDE.md Quick Facts/Running Ralph, conventions.md (tier+timeout convention),
  architecture.md, manifest.json. Verify scoped to `bash -n` + JSON (never a full suite —
  the exact trap this spec addresses).

## Verify

`verify_build()` — `bash -n` on `scripts/*.sh`, JSON validity on manifests.

## Dependencies

Builds on DECISION:013 (agent-session timeout), DECISION:009 (tier parser precedent),
spec 011 (no-background hardening + tier-floor).
