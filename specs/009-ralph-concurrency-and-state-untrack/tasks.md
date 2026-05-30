# Tasks: 009-ralph-concurrency-and-state-untrack

- [x] T001 · ralph.sh: single-instance lock + EXIT-trap pid release + session hardening
- [x] T002 · init.sh: untrack state/ on adopt
- [x] T003 · Knowledge-graph reconcile + DECISION:012

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
