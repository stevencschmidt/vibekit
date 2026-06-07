# Spec 011 — Ralph resume & stall hardening

## Summary

Fix two reliability failures from autonomous phramewerks runs:
1. a timeout-vs-ratelimit ordering bug that misclassifies a rate-limited hang as a stall,
2. missing process-level auto-resume after a usage-limit reset, and
3. an agent stall mode where a backgrounded long command strands the turn with no sentinel.

See `docs/briefs/011-ralph-resume-and-stall-hardening.md` for the full problem statement.

## Success Criteria

- In all three `timeout` branches of `ralph.sh` (main loop, final QC, checkpoint QC), a
  124/137 exit checks live usage first; if a window is ≥100% it runs `wait_for_reset` and
  continues without counting a stall/strike.
- The rate-limit-cap exit path uses a distinct exit code (not the generic `1` used by
  stall/block/verify-fail/max-iter).
- `scripts/ralph-supervisor.sh` exists: runs `ralph.sh` in a loop, re-launches **only** on
  the rate-limit exit code (after the reset), and stops on any other non-zero exit.
- `scripts/ralph-prompt.md` forbids backgrounding *any* command and forbids ending a turn
  while a process is still running; the sentinel is emitted only after commands return.
- `templates/.claude/skills/vibeplan/SKILL.md` instructs the planner to floor "full
  suite"/"docs reconcile"-style tasks at `medium` tier (never `simple`).
- `init.sh` and `scripts/push-to-phramewerks.sh` both copy `scripts/ralph-supervisor.sh`.
- Knowledge graph reconciled: `DECISION:014` added; `docs/claude/{conventions.md,
  architecture.md,manifest.json}` and `CLAUDE.md` updated; the decision-count drift
  (CLAUDE.md 013 vs decisions.md 012) corrected.
- `verify_build()` passes (`bash -n` on all scripts, JSON valid).

## Hard Constraints

- bash + python3 only; no new runtime dependencies.
- Auto-resume must NOT be systemd-only (supervisor wrapper is the portable primary).
- Auto-relaunch fires ONLY on the rate-limit exit code — never on stall/block/verify-fail/
  max-iter (preserves "stalls need human review").
- No change to the 3-strike machinery or the `/vibe_resume` skill.

## Out of Scope

- `/vibe_resume` skill changes.
- phramewerks migration (firewall — separate phramewerks session).

## Technical Approach

- **T001** add a small `is_usage_exhausted` helper (reuses `get_usage`/`get_utilization`);
  call it at the top of each timeout branch before the stall classification. On exhaustion:
  `wait_for_reset` + `continue` (decrement `ITERATION` in the main-loop branch to match the
  existing rate-limit-wait pattern).
- **T002** define a named constant for the rate-limit-cap exit code (e.g. `75`,
  EX_TEMPFAIL); use it on all three `RATE_LIMIT_CAP` exits. New `scripts/ralph-supervisor.sh`
  loops `ralph.sh`, inspects `$?`, re-execs only on `75` (with a `--max-relaunch` guard),
  exits through any other code. Wire `install-service.sh` `ExecStart` to the supervisor.
- **T003** markdown edits to `ralph-prompt.md` and the vibeplan SKILL.
- **T004** docs reconcile + DECISION:014 + manifest + add the new script to init.sh /
  push-to-phramewerks.sh. Verify scoped to `bash -n` (NOT a full suite — the exact trap
  that triggered this spec).

## Verify

`verify_build()` — `bash -n` on `scripts/*.sh`, JSON validity on manifests.

## Dependencies

Builds on DECISION:013 (agent-session timeout), DECISION:010 (rate-limit detection),
DECISION:006 (ralph.sh runtime-fix precedent), spec 006 (auto-resume friction reduction).
