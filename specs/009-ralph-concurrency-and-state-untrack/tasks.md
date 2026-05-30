# Tasks: 009-ralph-concurrency-and-state-untrack

- [x] T001 · ralph.sh: single-instance lock + EXIT-trap pid release + session hardening
- [x] T002 · init.sh: untrack state/ on adopt
- [ ] T003 · Knowledge-graph reconcile + DECISION:012

---

## T002 · init.sh: untrack state/ on adopt
Depends on: —
Verify: `bash -n init.sh` exits 0
Relevant: init.sh, templates/.gitignore, docs/claude/conventions.md
Tier: medium

`init.sh` (lines 124-132) appends `state/` to an existing `.gitignore`, but appending
to `.gitignore` cannot untrack files already committed. A project scaffolded before
spec 008 (e.g. phramewerks) keeps all `state/` files tracked, producing residual /
fallback commit noise and risking `state/ralph.log` truncation on `git reset --hard`.

In `init.sh`, after the `.gitignore` ensure-`state/` block (around line 132) and
BEFORE the initial-commit block (line 163), add a guarded untrack step:

- Only act if `$TARGET_DIR` is inside a git repo: `git -C "$TARGET_DIR" rev-parse
  --git-dir &>/dev/null`.
- Only act if any `state/` path is currently tracked: test that
  `git -C "$TARGET_DIR" ls-files state/` is non-empty.
- If both hold, run `git -C "$TARGET_DIR" rm -r --cached --quiet state/` (removes from
  the index only — working files stay on disk) and echo a one-line notice
  ("Untracked already-committed state/ from the index").
- Must be a no-op on a fresh project (nothing tracked yet) and safe to run repeatedly.
- Note: the actual commit of this index change happens via the existing initial-commit
  block for fresh adopts; for an already-initialized repo, init.sh does not create a
  commit, so leave the staged removal for the project's own session to commit. Do not
  add a new `git commit` to init.sh.

After editing, run `bash -n init.sh` — it must exit 0.

---

## T003 · Knowledge-graph reconcile + DECISION:012
Depends on: T001, T002
Verify: `python3 -c "import json; json.load(open('docs/claude/manifest.json'))"` exits 0
Relevant: docs/claude/conventions.md, docs/claude/manifest.json, docs/claude/decisions.md, CLAUDE.md, scripts/push-to-phramewerks.sh
Tier: simple

Reconcile the knowledge graph with what T001 and T002 implemented (read those files'
final state first — do not document intended behavior, document actual behavior).

1. `docs/claude/conventions.md` — under "Runtime State Handling", add: (a) the
   single-instance concurrency guard in `ralph.sh` (pid + `kill -0` liveness,
   `--force`/`RALPH_FORCE=1` override, EXIT-trap pid release, reconciled with
   `vibe_resume`), and (b) `init.sh` untracks already-committed `state/` on adopt via
   `git rm -r --cached`.
2. `docs/claude/manifest.json` — extend the `tags` for `conventions.md` (and
   `architecture.md` if it gains relevant content) with terms like `concurrency`,
   `lock`, `pid`, `untrack`. Keep summaries accurate. Validate JSON.
3. `docs/claude/decisions.md` — append `DECISION:012` with anchor
   `<!-- DECISION:012 | domains: architecture, conventions -->` recording the
   concurrency guard + untrack-on-adopt and why (single-instance safety; appending to
   .gitignore cannot untrack committed files).
4. `CLAUDE.md` — bump "Total decisions: 011" to "Total decisions: 012".
5. Confirm `scripts/push-to-phramewerks.sh` already copies `scripts/ralph.sh` and
   `init.sh` to the target. If either is missing from the sync list, add it. (No new
   infra files were introduced by this spec, so most likely no change is needed —
   verify and report.)

After editing, validate: `python3 -c "import json; json.load(open('docs/claude/manifest.json'))"` exits 0.
