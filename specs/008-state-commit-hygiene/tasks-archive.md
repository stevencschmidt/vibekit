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

## T003 · ralph.sh safety_commit: accurate message + don't sweep pre-existing WIP
Depends on: T001
Verify: `bash -n scripts/ralph.sh && grep -q 'PRE_DIRTY' scripts/ralph.sh && ! grep -q 'Claude did not commit' scripts/ralph.sh` exits 0
Relevant: docs/claude/architecture.md, docs/claude/conventions.md
Tier: complex

Two changes in `scripts/ralph.sh`:

1. **Snapshot the pre-iteration dirty set.** Where `PRE_SHA=$(git -C
   "$PROJECT_ROOT" rev-parse HEAD)` is captured at iteration start (~line 687),
   also capture the paths already modified/untracked BEFORE the task runs:
   ```bash
   PRE_DIRTY=$(git -C "$PROJECT_ROOT" status --porcelain | awk '{print $NF}')
   ```
   This is pre-existing working-tree work (WIP) that the task must not sweep.

2. **Rewrite `safety_commit()` (~line 358).** Keep the early return when the tree
   is clean. Otherwise:
   - Stage only paths changed during THIS iteration — i.e. current
     `git status --porcelain` paths that are NOT in `$PRE_DIRTY`. Do not run a
     blind `git add -A`. If nothing remains to stage after excluding `$PRE_DIRTY`,
     return without committing.
   - Choose the commit message by comparing HEAD to `$PRE_SHA`: if HEAD advanced
     (the agent committed), use `Ralph residual-changes commit: $task_id`; if HEAD
     == `$PRE_SHA` (agent committed nothing), use `Ralph fallback commit: $task_id
     (agent emitted TASK_COMPLETE without committing)`.
   - The literal string `Claude did not commit` must be removed entirely.

Do not change the call site (line ~807). With `state/` now gitignored (T001), the
routine residue disappears, so this fallback should rarely fire at all.

[TASK_COMPLETE: T003] when safety_commit is scoped + accurately messaged and
Verify passes.

---

## T004 · Docs: resolve T011 note + DECISION:011 + conventions/manifest
Depends on: T003
Verify: `! grep -q 'known, T011' docs/claude/architecture.md && grep -qi 'state/' docs/claude/conventions.md && python3 -c "import json; json.load(open('docs/claude/manifest.json'))" && grep -q 'Total decisions: 011' CLAUDE.md` exits 0
Relevant: docs/claude/architecture.md, docs/claude/conventions.md
Tier: simple

Document the shipped fix (do not document anything not implemented):

1. `docs/claude/architecture.md` — update the "State File Commit Gap (known,
   T011)" subsection: the gap is now resolved by gitignoring `state/` (volatile
   runtime state is no longer tracked) plus the hardened `safety_commit`. Remove
   the "known, T011" open-gap framing; describe the resolution and reference
   DECISION:011.
2. `docs/claude/conventions.md` — add a short note: scaffolded projects gitignore
   `state/` (runtime logs/pid/sync); `safety_commit` stages only task-iteration
   changes, never pre-existing WIP.
3. `CLAUDE.md` — bump the Decision Log to `Total decisions: 011` (the DECISION:011
   entry was added to `docs/claude/decisions.md` at plan time).
4. `docs/claude/manifest.json` — refresh the architecture.md / conventions.md
   summaries if their scope changed; keep valid JSON.
5. Confirm `scripts/push-to-phramewerks.sh` still covers every changed infra file
   (`.gitignore` and config are intentionally NOT synced — leave that as is).

[TASK_COMPLETE: T004] when docs reflect the resolved gap and Verify passes.
