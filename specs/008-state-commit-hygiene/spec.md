# Spec: 008-state-commit-hygiene

## Summary

Stop scaffolded projects from tracking runtime `state/` and stop Ralph's
`safety_commit` from firing misleading, over-broad fallback commits. Surfaced by
reviewing phramewerks (33× "Ralph post-complete fallback commit: T### (Claude did
not commit)" + a committed `state/ralph.pid`). See
`docs/briefs/008-state-commit-hygiene.md`.

## Success criteria

- A freshly `init.sh`-scaffolded project gitignores `state/`; after a Ralph run
  `git status` shows no tracked `state/` churn and `ralph.pid` is never committed.
- Re-running `init.sh` on a project whose `.gitignore` lacks `state/` appends it
  (idempotent).
- `safety_commit` no longer prints "Claude did not commit" when the agent did
  commit, and never stages files that were already dirty before the task ran.
- `architecture.md` no longer describes the "State File Commit Gap" as an open
  T011 item.

## Hard constraints

- bash + python3 only; no new dependencies.
- Match vibekit's own `.gitignore` (ignore `state/`). Safe because Ralph,
  `/vibe_resume`, and `/vibeplan` read `sync.json` from disk, not git.

## Out of scope

- Migrating phramewerks (firewall — phramewerks' `.gitignore` update +
  `git rm --cached state/…` happen in a phramewerks session, never from here).
- Changing the task agent's own `git add -A` in `ralph-prompt.md` (a clean
  per-task tree makes it acceptable; the fallback is where the unscoped sweep
  actually bit).

## Technical approach

- `templates/.gitignore`: add `state/`.
- `init.sh`: when the target already has a `.gitignore` lacking a `state/` rule,
  append it (idempotent); keep the existing copy-if-absent path.
- `scripts/ralph.sh`: snapshot the already-dirty path set at iteration start
  (`PRE_DIRTY`, alongside `PRE_SHA`); rewrite `safety_commit()` to stage only
  paths changed during the iteration (exclude `PRE_DIRTY`), choose an accurate
  message by comparing HEAD to `PRE_SHA`, and drop the "Claude did not commit"
  string. This **supersedes** the documented T011 "commit state files" plan.
- Docs: resolve the T011 note in `architecture.md`; add the state-gitignore
  convention to `conventions.md`; refresh `manifest.json`; DECISION:011.

## Dependencies

Self-contained within vibekit. Modifies the running orchestrator (`ralph.sh`) —
dogfooded. `verify_build()` (bash -n on scripts) guards each commit; failed tasks
roll back and are resumable from `state/sync.json`.
