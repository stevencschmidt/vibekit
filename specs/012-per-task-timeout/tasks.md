# Tasks: 012-per-task-timeout

- [x] T001 · Per-task Timeout override in ralph.sh
- [x] T002 · vibeplan fast-verify rule for docs tasks + document Timeout
- [x] T003 · Docs reconcile + DECISION:016 + manifest + sync.json schema

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
