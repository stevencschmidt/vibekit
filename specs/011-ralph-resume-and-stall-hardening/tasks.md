# Tasks: 011-ralph-resume-and-stall-hardening

- [x] T001 · Fix timeout-vs-ratelimit misclassification in ralph.sh
- [x] T002 · Distinct rate-limit exit code + ralph-supervisor.sh auto-resume
- [x] T003 · Harden ralph-prompt.md no-background rule + vibeplan tier-floor
- [ ] T004 · Docs reconcile + DECISION:014 + manifest + ship new script

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
