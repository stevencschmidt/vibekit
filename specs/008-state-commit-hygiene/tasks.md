# Tasks: 008-state-commit-hygiene

- [x] T001 · templates/.gitignore: ignore state/
- [x] T002 · init.sh: idempotently add state/ to an existing .gitignore
- [x] T003 · ralph.sh safety_commit: accurate message + don't sweep pre-existing WIP
- [x] T004 · Docs: resolve T011 note + DECISION:011 + conventions/manifest

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
