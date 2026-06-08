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
- Auto-resume across token-limit windows lives **inside `ralph.sh`** (in-process
  `wait_for_reset` + the T001 fix) — the one script vibeplan/vibe_resume already launch.
  There is no separate supervisor/wrapper to choose or remember.
- `scripts/ralph-prompt.md` forbids backgrounding *any* command and forbids ending a turn
  while a process is still running; the sentinel is emitted only after commands return.
- `templates/.claude/skills/vibeplan/SKILL.md` instructs the planner to floor "full
  suite"/"docs reconcile"-style tasks at `medium` tier (never `simple`).
- Knowledge graph reconciled: `DECISION:014` (the original fix) and `DECISION:015` (the
  supervisor reversal) recorded; `docs/claude/{conventions.md,architecture.md,
  manifest.json}` and `CLAUDE.md` carry no supervisor references; the decision count is
  correct.
- `verify_build()` passes (`bash -n` on all scripts, JSON valid).

> **Course-correction (T005–T006):** the supervisor wrapper originally shipped in
> T002/T004 was removed. The automated launch path (`nohup bash scripts/ralph.sh`) never
> called it, and `ralph.sh` already auto-resumes in-process — so the wrapper was redundant
> complexity. See DECISION:015.

## Hard Constraints

- bash + python3 only; no new runtime dependencies.
- One launch path — auto-resume inside `ralph.sh`, no separate wrapper the automated flow
  would never run.
- Nothing auto-restarts on stall/block/verify-fail/max-iter (preserves "stalls need
  human review").
- No change to the 3-strike machinery or the `/vibe_resume` skill.

## Out of Scope

- `/vibe_resume` skill changes.
- phramewerks migration (firewall — separate phramewerks session).
- A separate supervisor/wrapper process (rejected — DECISION:015).

## Technical Approach

- **T001** add a small `is_usage_exhausted` helper (reuses `get_usage`/`get_utilization`);
  call it at the top of each timeout branch before the stall classification. On exhaustion:
  `wait_for_reset` + `continue` (decrement `ITERATION` in the main-loop branch to match the
  existing rate-limit-wait pattern). *(kept)*
- **T002/T004 (superseded)** added a `RALPH_EXIT_RATE_LIMIT=75` code + `ralph-supervisor.sh`
  + scaffolding/doc references. **Reverted by T005–T006.**
- **T003** markdown edits to `ralph-prompt.md` and the vibeplan SKILL. *(kept)*
- **T005** delete `scripts/ralph-supervisor.sh`; revert the `RALPH_EXIT_RATE_LIMIT` exit
  code back to `exit 1`; revert `install-service.sh`, `init.sh`, and `push-to-phramewerks.sh`
  to no longer reference the supervisor. Keep T001's `is_usage_exhausted` logic intact.
- **T006** docs reconcile: add `DECISION:015` (supersedes the supervisor portion of
  DECISION:014); strip supervisor references from `CLAUDE.md` and `docs/claude/*`; correct
  the decision count. Verify scoped to `bash -n` + JSON (never a full suite).

## Verify

`verify_build()` — `bash -n` on `scripts/*.sh`, JSON validity on manifests.

## Dependencies

Builds on DECISION:013 (agent-session timeout), DECISION:010 (rate-limit detection),
DECISION:006 (ralph.sh runtime-fix precedent), spec 006 (auto-resume friction reduction).
