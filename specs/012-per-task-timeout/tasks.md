# Tasks: 012-per-task-timeout

- [x] T001 · Per-task Timeout override in ralph.sh
- [ ] T002 · vibeplan fast-verify rule for docs tasks + document Timeout
- [ ] T003 · Docs reconcile + DECISION:016 + manifest + sync.json schema

---

## T001 · Per-task Timeout override in ralph.sh
Depends on: —
Verify: `bash -n scripts/ralph.sh && grep -q 'task_timeout' scripts/ralph.sh`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md, scripts/ralph.sh
Tier: complex

Add a per-task agent-session timeout that overrides the global `RALPH_TASK_TIMEOUT`
(default 1800s), mirroring the existing `Tier:` mechanism exactly. Motivating bug: a
markdown-only task whose `Verify:` ran the full Docker pytest suite always exceeded the
1800s watchdog → 3 stalls → stop. A task must be able to declare a longer timeout, or
`0` to disable the watchdog for itself.

1. **Parser** — in the next-task advance parser (the python block ~967-1000 that reads
   `Relevant:` and `Tier:` from the task's `## T###` section), also extract an optional
   `Timeout:` line: `^Timeout:\s*(\d+)\s*$`. Print it as a 5th output line (empty string
   if absent). After the existing `_next_tier` handling, capture `_next_timeout` and
   `sync_write "ralph.task_timeout" "$_next_timeout"` (write empty/`null` when absent so
   the loop falls back to the default).
2. **Loop read** — near where the loop reads `ralph.tier` (~603), also
   `TASK_TIMEOUT=$(sync_read "ralph.task_timeout" ...)`. Compute an effective value:
   `_ITER_TIMEOUT` = `$TASK_TIMEOUT` when it is a non-negative integer (including `0`),
   else `$RALPH_TASK_TIMEOUT`. Treat empty/`null`/non-numeric as "use the default".
3. **Apply** — make `ralph_timeout_prefix` use the effective value for the **task agent**
   invocation only. Cleanest: give `ralph_timeout_prefix` an optional first arg
   (`local secs="${1:-${RALPH_TASK_TIMEOUT:-1800}}"`) and call
   `mapfile -t _TO < <(ralph_timeout_prefix "$_ITER_TIMEOUT")` at the task-agent call
   site (~807). The final-QC (~652) and checkpoint-QC (~1050) calls must keep using the
   **global** default — call `ralph_timeout_prefix` with no arg there.
4. The timeout→stall classification logic (rc 124/137) and the T001-from-spec-011
   `is_usage_exhausted` guard are unchanged — they already read `RALPH_TASK_TIMEOUT` only
   to decide whether the watchdog is active; update those `-gt 0` guards to also treat a
   per-task `_ITER_TIMEOUT` of 0 as "watchdog disabled for this task" so a disabled-task
   timeout is never misread.

Do not change the global default or the 3-strike machinery. Do not refactor surrounding
code.

---

## T002 · vibeplan fast-verify rule for docs tasks + document Timeout
Depends on: T001
Verify: `grep -qi 'fast' templates/.claude/skills/vibeplan/SKILL.md && grep -q 'Timeout:' templates/.claude/skills/vibeplan/SKILL.md`
Relevant: docs/claude/conventions.md, templates/.claude/skills/vibeplan/SKILL.md
Tier: medium

Stop planners from gating light tasks on heavy suites, and document the new escape hatch.

1. In `templates/.claude/skills/vibeplan/SKILL.md`, in the task-authoring rules
   ("Rules for good tasks" / tier section ~553-564), add a rule: a docs/markdown-only
   task (and the recurring "reconcile docs + DECISION" final task) MUST use a fast,
   bounded `Verify:` — an AST parse, a `json.load`, or a `grep` assertion — and must NOT
   gate on the full test suite, the e2e/Playwright suite, or any `docker compose run`
   integration command. Those long suites exceed the agent-session watchdog and stall the
   task; the authoritative `verify_build()` already covers syntax post-completion.
2. Document the optional `Timeout:` line in the `## T###` task-shape template (alongside
   `Tier:`): `Timeout: <seconds>` overrides the global agent-session watchdog for that
   task; `Timeout: 0` disables it. State it is the escape hatch for a genuinely long task
   (and that the *right* fix for a docs task is a fast verify, not a long timeout).

Markdown edits only. Do not touch ralph.sh.

---

## T003 · Docs reconcile + DECISION:016 + manifest + sync.json schema
Depends on: T002
Verify: `for f in scripts/*.sh; do bash -n "$f" || exit 1; done && python3 -c "import json;json.load(open('docs/claude/manifest.json'))" && grep -q 'DECISION:016' docs/claude/decisions.md && grep -q 'task_timeout' CLAUDE.md`
Relevant: docs/claude/conventions.md, docs/claude/architecture.md, docs/claude/manifest.json, CLAUDE.md, docs/claude/decisions.md
Tier: medium

Reconcile the knowledge graph to the per-task timeout feature.

1. Append `DECISION:016` to `docs/claude/decisions.md` (anchor
   `domains: architecture, conventions`): per-task `Timeout:` override (parsed like
   `Tier:`, written to `ralph.task_timeout`, resolved to an effective per-iteration
   value; `0` disables the watchdog for that task); plus the vibeplan fast-verify rule for
   docs tasks. Reference the phramewerks stall that motivated it. Builds on DECISION:013.
2. Bump "Total decisions:" to `016` in BOTH `CLAUDE.md` and `docs/claude/decisions.md`.
3. In `CLAUDE.md`: add `task_timeout` to the `state/sync.json` schema block; add a
   Quick Fact / Running-Ralph note that a task may set `Timeout:` to override the
   per-task watchdog.
4. In `docs/claude/conventions.md` (tier/model-routing convention) and
   `docs/claude/architecture.md` (per-iteration flow): document the `Timeout:` parse →
   `ralph.task_timeout` → effective-timeout resolution. Update `docs/claude/manifest.json`
   summaries/tags if the covered topics changed enough to warrant it.

Verify is scoped to `bash -n` + JSON validity + greps — do NOT run any full test suite
(that watchdog-exceeding trap is exactly what this spec fixes).
