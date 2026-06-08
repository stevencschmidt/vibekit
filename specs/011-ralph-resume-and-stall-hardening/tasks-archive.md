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

## T003 · Harden ralph-prompt.md no-background rule + vibeplan tier-floor
Depends on: T002
Verify: `grep -qi 'foreground' scripts/ralph-prompt.md && grep -qi 'tier' templates/.claude/skills/vibeplan/SKILL.md`
Relevant: docs/claude/conventions.md, scripts/ralph-prompt.md
Tier: simple

Root cause of the original stall: the agent backgrounded a long command (full test
suite) and ended its turn waiting, never emitting the sentinel.

1. In scripts/ralph-prompt.md, strengthen the existing rule (~line 26). Make
   explicit: never background ANY command (no trailing `&`, no `nohup`/`disown`, no
   "run in background" tool invocations); run every command synchronously in the
   foreground and wait for it to fully return before continuing; NEVER end the turn
   while a process is still running or "in progress"; emit the completion sentinel
   ONLY after all commands have returned and work is committed. Add a one-line
   reminder that a turn ending with "waiting for X to complete" and no sentinel is
   counted as a stall and wastes an attempt.
2. In templates/.claude/skills/vibeplan/SKILL.md tier-assignment section (~559),
   add a tier-floor note: any task that runs the full test suite, reconciles docs
   across multiple files, or otherwise spans several files MUST be tagged at least
   `medium` — never `simple`. The simple/Haiku tier is for mechanical single-file or
   config changes only.

Markdown edits only. Do not touch ralph.sh.

---

## T004 · Docs reconcile + DECISION:014 + manifest + ship new script
Depends on: T003
Verify: `for f in scripts/*.sh; do bash -n "$f" || exit 1; done && python3 -c "import json;json.load(open('docs/claude/manifest.json'))" && grep -q 'DECISION:014' docs/claude/decisions.md && grep -q 'ralph-supervisor.sh' init.sh scripts/push-to-phramewerks.sh`
Relevant: docs/claude/conventions.md, docs/claude/architecture.md, docs/claude/manifest.json, CLAUDE.md, docs/claude/decisions.md
Tier: medium

Reconcile the knowledge graph and ship the new script through the scaffolding.

1. `init.sh` (section 2, ~line 78): add `cp "$VIBEKIT_DIR/scripts/ralph-supervisor.sh"
   "$TARGET_DIR/scripts/ralph-supervisor.sh"` and a `chmod +x` for it.
2. `scripts/push-to-phramewerks.sh` (scripts section, ~line 42): add
   `copy_file "scripts/ralph-supervisor.sh" "scripts/ralph-supervisor.sh"` and a
   `chmod +x` line; also add `install-service.sh` if it is not already mirrored.
3. Append `DECISION:014` to `docs/claude/decisions.md` (anchor with
   `domains: architecture, conventions`) covering: the timeout-vs-ratelimit fix, the
   distinct rate-limit exit code + supervisor wrapper (and why it is gated to the
   rate-limit code only, not blanket systemd restart), and the ralph-prompt
   no-background hardening. Note it supersedes nothing but builds on DECISION:013/010.
4. Fix the decision-count drift: set "Total decisions: 014" in BOTH `CLAUDE.md`
   (~line 55) and the `Total decisions:` line in `docs/claude/decisions.md` (currently
   shows 012 — bump to 014).
5. Update `docs/claude/architecture.md` (per-iteration flow / rate-limit handling) and
   `docs/claude/conventions.md` (exit-code convention, supervisor, no-background rule)
   with brief notes. Update `docs/claude/manifest.json` summaries/tags only if the
   covered topics changed enough to warrant it.
6. Update CLAUDE.md "Running Ralph"/"Quick Facts" to mention `scripts/ralph-supervisor.sh`
   as the rate-limit auto-resume entry point.

Verify is intentionally scoped to `bash -n` + JSON validity + greps — do NOT run any
full test suite (that backgrounding trap is what this spec fixes).

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

