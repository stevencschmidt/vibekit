# Archive: 008-state-commit-hygiene

## T001 · templates/.gitignore: ignore state/
Depends on: —
Verify: `grep -qE '^state/?$' templates/.gitignore && bash -n init.sh` exits 0
Relevant: docs/claude/conventions.md
Tier: simple

Add a `state/` entry to `templates/.gitignore` (the file `init.sh` scaffolds into
new projects). vibekit's own root `.gitignore` already has this under a
"Runtime state" comment — mirror that. Add a short comment line above it, e.g.:

```
# Runtime state (logs, pid, sync) — project-specific, not for git
state/
```

Place it near the existing sections; do not remove or reorder existing entries.

[TASK_COMPLETE: T001] when `templates/.gitignore` ignores `state/` and Verify passes.

---

## T002 · init.sh: idempotently add state/ to an existing .gitignore
Depends on: T001
Verify: `bash -n init.sh && grep -q 'ensure state/ ignored' init.sh` exits 0
Relevant: docs/claude/conventions.md, docs/claude/architecture.md
Tier: medium

`init.sh` currently copies `templates/.gitignore` only when the target has none
(around `init.sh:125`, the `if [[ ! -f "$TARGET_DIR/.gitignore" ]]` block). So
existing projects never receive `.gitignore` fixes.

Extend that block: in the `else` branch (target already has a `.gitignore`),
ensure `state/` is ignored — if `grep -qE '^state/?$' "$TARGET_DIR/.gitignore"`
finds nothing, append a blank line, a comment `# ensure state/ ignored (vibekit
runtime state)`, and `state/` to the file, and echo a line so the user sees it.
Make it idempotent (no duplicate append if already present). Keep the existing
copy-if-absent path unchanged. The marker comment string `ensure state/ ignored`
must appear in `init.sh`.

[TASK_COMPLETE: T002] when re-running init.sh repairs an existing .gitignore and
Verify passes.

---

