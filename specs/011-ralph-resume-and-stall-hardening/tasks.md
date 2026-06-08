# Tasks: 011-ralph-resume-and-stall-hardening

- [x] T001 · Fix timeout-vs-ratelimit misclassification in ralph.sh
- [x] T002 · Distinct rate-limit exit code + ralph-supervisor.sh auto-resume
- [x] T003 · Harden ralph-prompt.md no-background rule + vibeplan tier-floor
- [x] T004 · Docs reconcile + DECISION:014 + manifest + ship new script
- [ ] T005 · Remove ralph-supervisor.sh and revert its plumbing
- [ ] T006 · Docs reconcile: DECISION:015 + strip supervisor from knowledge graph

---

## T005 · Remove ralph-supervisor.sh and revert its plumbing
Depends on: —
Verify: `for f in scripts/*.sh; do bash -n "$f" || exit 1; done && [ ! -f scripts/ralph-supervisor.sh ] && ! grep -rqn 'ralph-supervisor\|RALPH_EXIT_RATE_LIMIT' scripts init.sh`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md, scripts/ralph.sh, scripts/install-service.sh
Tier: medium

Course-correction: the supervisor wrapper added in T002/T004 is dead code — the
automated launch path (`nohup bash scripts/ralph.sh`, used by both the vibeplan and
vibe_resume skills) never calls it, and `ralph.sh` already auto-resumes across
token-limit windows in-process via `wait_for_reset`. Remove the wrapper and revert
everything it touched. **Keep T001's `is_usage_exhausted` logic and all three timeout
branches intact — that is the real fix and stays.**

1. Delete `scripts/ralph-supervisor.sh`.
2. In `scripts/ralph.sh`:
   - Remove the `RALPH_EXIT_RATE_LIMIT=75` constant (added ~line 76).
   - Revert every `exit "$RALPH_EXIT_RATE_LIMIT"` / `exit $RALPH_EXIT_RATE_LIMIT`
     back to `exit 1` (6 occurrences: the RATE_LIMIT_CAP paths in the task loop,
     final-QC pre-check + mid-execution, and checkpoint-QC pre-check + mid-execution).
   - Do NOT touch `is_usage_exhausted` or the timeout-branch `wait_for_reset` calls.
3. In `scripts/install-service.sh`: revert `ExecStart` to point at
   `scripts/ralph.sh` (not the supervisor) and revert the inline note edits that
   described the supervisor. `Restart=no` stays as before.
4. In `init.sh`: remove the `cp` and `chmod +x` lines for `ralph-supervisor.sh`.
5. In `scripts/push-to-phramewerks.sh`: remove the `copy_file`/`chmod` lines for
   `ralph-supervisor.sh`. (Leave the `install-service.sh` mirror line if T004 added
   it — that script is still valid.)

Do not refactor surrounding code. Markdown/script edits + one deletion only.

---

## T006 · Docs reconcile: DECISION:015 + strip supervisor from knowledge graph
Depends on: T005
Verify: `for f in scripts/*.sh; do bash -n "$f" || exit 1; done && python3 -c "import json;json.load(open('docs/claude/manifest.json'))" && grep -q 'DECISION:015' docs/claude/decisions.md && ! grep -rqn 'ralph-supervisor' CLAUDE.md docs/claude`
Relevant: docs/claude/conventions.md, docs/claude/architecture.md, docs/claude/manifest.json, CLAUDE.md, docs/claude/decisions.md
Tier: medium

Reconcile the knowledge graph to the corrected design (auto-resume in `ralph.sh`,
no supervisor).

1. Append `DECISION:015` to `docs/claude/decisions.md` (anchor
   `domains: architecture, conventions`): the supervisor wrapper from DECISION:014 is
   removed because the automated launch path never invoked it and `ralph.sh` already
   auto-resumes in-process. State that DECISION:015 **supersedes the supervisor /
   distinct-exit-code portion of DECISION:014**; the T001 timeout-vs-ratelimit fix and
   the T003 no-background hardening from 014 remain in force.
2. Bump "Total decisions:" to `015` in BOTH `CLAUDE.md` and `docs/claude/decisions.md`.
3. In `CLAUDE.md`: remove the supervisor Quick Fact line and the "For unattended runs
   … `ralph-supervisor.sh`" block under Running Ralph. Replace with a one-line note
   that `ralph.sh` auto-resumes across rate-limit windows in-process (no wrapper
   needed).
4. In `docs/claude/conventions.md` and `docs/claude/architecture.md`: remove any
   supervisor references added by T004; describe auto-resume as an in-process
   behavior of `ralph.sh`. Update `docs/claude/manifest.json` summaries/tags only if
   they mention the supervisor.

Verify is scoped to `bash -n` + JSON validity + greps — do NOT run any full test
suite.
