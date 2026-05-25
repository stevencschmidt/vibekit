# Brief: State-File & Commit Hygiene

## Problem

Surfaced reviewing phramewerks (2026-05-24/25). Two related defects in how
vibekit scaffolds projects and how Ralph commits.

1. **`templates/.gitignore` omits `state/`.** vibekit's own `.gitignore` ignores
   `state/`, but the template `init.sh` scaffolds does not. So every scaffolded
   project tracks the whole runtime `state/` dir — `ralph.pid` (a PID file!),
   `ralph.log`, `sync-agent.log`, `sync.json`, `session-log.json`. In phramewerks
   this produced **33 "Ralph post-complete fallback commit: T### (Claude did not
   commit)"** commits (verified: they swept only `ralph.log`/`sync-agent.log`/
   `sync.json` churn that `ralph.sh` writes *after* the task agent's own commit),
   and a committed stale `state/ralph.pid` (latent risk: `vibe_resume`'s
   `kill -0 <pid>` can false-positive on a reused PID).

2. **The safety/fallback commit in `ralph.sh` is mislabeled and over-broad.** It
   fires "...(Claude did not commit)" even when the agent *did* commit (the
   residue is ralph's own post-commit state writes), and it uses unscoped
   `git add -A` — the same blind sweep that pulled unrelated pre-existing files
   into vibekit's spec-007 commits. This is the documented "State File Commit
   Gap (known, T011)" in `docs/claude/architecture.md`.

## Goals

- New scaffolded projects never track runtime state or fire spurious fallback
  commits.
- When the safety commit does fire, its message is accurate and it does not
  blind-stage unrelated working-tree changes.
- Resolve the T011 gap and update the docs that describe it.

## Design (proposed — confirm in planning)

- **gitignore approach over the old T011 "commit state files" approach.** Match
  vibekit's own `.gitignore`: ignore `state/` in `templates/.gitignore`. Ralph,
  `/vibe_resume`, and `/vibeplan` all read `sync.json` from disk, not git, so
  ignoring it is functionally safe; the only trade-off is `session-log.json`
  history no longer lives in git (vibekit already forgoes this). This supersedes
  T011's plan to *commit* volatile state.
- **Harden the safety commit** (`safety_commit` / post-complete fallback in
  `ralph.sh`): detect whether HEAD advanced during the iteration; if the agent
  already committed, do not claim "Claude did not commit." Avoid blind
  `git add -A` of files unrelated to the task. Keep the fallback as a genuine
  safety net for the real "agent emitted TASK_COMPLETE without committing" case.
- **init.sh migration gap (optional):** `init.sh` only copies `.gitignore` when
  one is absent (`init.sh:125`), so existing projects never receive the fix.
  Consider having `init.sh` append a `state/` rule when an existing `.gitignore`
  lacks it (idempotent), so re-running init.sh repairs older projects.

## Affected files

- `templates/.gitignore` — ignore `state/`.
- `scripts/ralph.sh` — safety/fallback commit accuracy + scoping.
- `init.sh` — optional idempotent `.gitignore` repair.
- `docs/claude/architecture.md` — update the "State File Commit Gap (T011)" note
  to reflect the gitignore resolution.
- `docs/claude/decisions.md` — DECISION entry.
- `scripts/push-to-phramewerks.sh` — confirm coverage (no new infra files
  expected; `.gitignore`/config are intentionally not synced).

## Out of scope

- Migrating phramewerks itself (firewall: phramewerks' `.gitignore` update +
  `git rm --cached state/…` happen in a phramewerks session, never from here).
- Changing the task agent's own commit flow in `ralph-prompt.md` beyond what's
  needed (its `git add -A` is acceptable for clean per-task trees).

## Success criteria

- A freshly scaffolded project (via `init.sh`) has `state/` gitignored;
  `git status` after a Ralph run shows no tracked `state/` churn and no
  `ralph.pid` in git.
- The fallback commit no longer prints "Claude did not commit" when the agent
  committed, and does not stage files unrelated to the task.
- `architecture.md` no longer describes T011 as an open gap.
