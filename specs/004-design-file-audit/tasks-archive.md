# Archive: 004-design-file-audit

## T001 · Cleanup stale references + delete obsolete docs/archive/PLAN.md
Depends on: —
Verify: `grep -rn "knowledge-graph-brief" scripts/ vibekit.config.sh 2>/dev/null | grep -v '^Binary' | wc -l` outputs `0` AND `test ! -e docs/archive/PLAN.md`
Relevant: docs/claude/conventions.md

Three stale references and one obsolete file remain from the spec-004 pharmai removal
and the `knowledge-graph-brief.md → docs/design.md` rename. Fix in one task:

1. **`vibekit.config.sh` line 13** — change
   `BRIEF_FILE="$PROJECT_ROOT/knowledge-graph-brief.md"` to
   `BRIEF_FILE="$PROJECT_ROOT/docs/design.md"`.

2. **`scripts/qc-prompt.md` line 9** — the prose says
   `fall back to \`knowledge-graph-brief.md\``. Change `knowledge-graph-brief.md` to
   `docs/design.md`. Keep all other prose intact.

3. **`docs/archive/PLAN.md`** — remove via `git rm docs/archive/PLAN.md`. This file is
   the pre-implementation planning document for vibekit itself; its concepts are all
   reflected in `docs/claude/architecture.md`, `README.md`, and `CHANGELOG.md`. It is
   the last live file referencing `/plan` (now `/vibeplan`) outside append-only
   history.

**Do NOT modify:**
- `docs/claude/decisions.md` entries 001–007 (append-only history)
- Any file under `specs/00[1-3]/` (append-only history)
- The `SPEC_TASKS_FILE` line in `vibekit.config.sh` (already updated by `/vibeplan` to
  point at this active spec — the original "fix" target is moot)

After edits, run `verify_build` from `vibekit.config.sh` to confirm no syntax breakage.
Commit with `[ralph] T001 complete — stale-reference cleanup`.

---

## T002 · Audit ralph.sh empty SPEC_TASKS_FILE handling
Depends on: T001
Verify: `SPEC_TASKS_FILE_EMPTY_OK=1 bash -n scripts/ralph.sh` exits 0 AND a manual test of `SPEC_TASKS_FILE="" bash scripts/ralph.sh --dry-run` produces a human-readable error message (not a raw bash error like `[: : integer expression expected` or `command not found`)
Relevant: docs/claude/architecture.md, docs/claude/conventions.md

The plan envisioned `SPEC_TASKS_FILE=""` being valid when no spec is active. Read
`scripts/ralph.sh` preflight section carefully — search for every reference to
`SPEC_TASKS_FILE` and follow the control flow.

**If Ralph already errors cleanly on empty value:** no code change needed. Add one
sentence to `docs/claude/architecture.md` (in the existing ralph.sh component
description) noting that empty `SPEC_TASKS_FILE` produces a preflight error. Verify
exits 0.

**If Ralph fails obscurely (bash error, silent infinite loop, or undefined-variable
shell trace):** add a preflight check near the existing `vibekit.config.sh` source
that says:
```bash
if [[ -z "${SPEC_TASKS_FILE:-}" ]]; then
  echo "ERROR: SPEC_TASKS_FILE is empty in vibekit.config.sh — no active spec. Run /vibeplan to create one." >&2
  exit 2
fi
```
Match the existing style (no `set -e` if Ralph deliberately disables it; preserve
existing quoting conventions).

**Do not** add this check before the `--dry-run` path emits its preflight summary —
respect existing dry-run semantics; `--dry-run` should still report on a no-spec
state coherently.

Commit with `[ralph] T002 complete — ralph.sh empty SPEC_TASKS_FILE handling`.

---

