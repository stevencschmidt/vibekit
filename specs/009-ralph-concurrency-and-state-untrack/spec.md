# Spec 009 — Ralph concurrency safety + state untracking on adopt

Brief: `docs/briefs/009-ralph-concurrency-and-state-untrack.md`

## Summary

Two vibekit flaws, diagnosed from a real phramewerks run (2026-05-29):

1. **`ralph.sh` has no concurrency guard.** It writes `state/ralph.pid` but never
   checks it — no lock anywhere. Two `bash scripts/ralph.sh` invocations ran
   concurrently against the same `sync.json`, causing duplicate task completions
   (session-log: `T001×3`, `T009×2`, `T008×2`), duplicate git commits (`904f568` /
   `05f5e98`), and a manual `[ralph-resume] advance sync.json to T003` recovery. The
   only existing protection is `vibe_resume`'s soft `kill -0` check, which is racy and
   only runs on the resume path — not on a direct `ralph.sh` invocation.

2. **`state/` stays git-tracked when vibekit is adopted into a project that already
   committed it.** Spec 008 fixed `templates/.gitignore` and made `init.sh` append
   `state/` to an existing `.gitignore`, but appending to `.gitignore` cannot untrack
   already-committed files. phramewerks still tracks all 7 `state/` files, producing
   residual/fallback commit noise and risking `ralph.log` truncation on rollback.

A related leak found while scoping: the "all tasks complete" exit path
(`ralph.sh:561-566`, the `--skip-qc`/no-brief case) exits `0` without calling
`notify_exit`, so it never removes `state/ralph.pid`, leaving a stale pid.

## Success criteria

- A second `ralph.sh` started while a live instance is running detects it and refuses
  (exit non-zero) with a message pointing to `/vibe_resume`. Works for direct
  `bash scripts/ralph.sh` invocation, not just the resume path.
- `--force` (or `RALPH_FORCE=1`) bypasses the guard for edge cases.
- A stale pid left by a crashed/ended run does not deadlock — it is detected via
  `kill -0`, removed, and startup proceeds.
- Every exit path (normal completion, QC complete, blocked, stall, max-iter, SIGINT)
  releases this instance's own pid file.
- `init.sh`, when adopted into a repo where `state/` is already tracked, removes those
  files from the index (`git rm -r --cached state/`) while keeping working copies;
  no-op and safe on fresh projects and on re-runs.
- A non-positive / non-numeric `ralph.session` in `sync.json` is treated as `1`.
- `bash -n` passes on all changed scripts; `verify_build()` stays green.

## Hard constraints

- bash + python3 + claude CLI only. No new dependencies.
- Portable: `flock` is not assumed (Windows/Git Bash) — use pid-file + `kill -0`
  liveness, the same mechanism `vibe_resume` already uses.
- Must not break the `vibe_resume` reconnect flow — guard semantics and
  `vibe_resume` SKILL.md step 1 must agree on liveness.
- After implementation, changes sync to phramewerks via
  `scripts/push-to-phramewerks.sh` (file sync only — git firewall).

## Out of scope

- Rate-limit handling (the multi-hour waits observed are the Claude plan's 5-hour
  window resetting; handled correctly already).
- The actual `git rm --cached state/` cleanup of the *existing* phramewerks repo —
  that runs in a phramewerks session (git firewall).

## Technical approach

- **Concurrency guard** (`ralph.sh`): add a startup block after the sync.json/git
  validation and before the main loop. Read `state/ralph.pid` if present; if
  `kill -0 <pid>` succeeds and the pid is not our own, refuse unless `--force` /
  `RALPH_FORCE=1`. Otherwise remove the stale pid and continue. Keep the existing
  `echo $$ > state/ralph.pid` write. Add an `EXIT` trap (extending the existing
  temp-prompt-cleanup trap) that removes the pid only if it still contains `$$`.
- **Session hardening** (`ralph.sh:526-529`): after reading `ralph.session`, coerce
  empty / `null` / `0` / non-numeric to `1`.
- **Untrack on adopt** (`init.sh`): after the `.gitignore` ensure-`state/` block, if
  `git -C "$TARGET_DIR" rev-parse` succeeds and `git ls-files state/` is non-empty,
  run `git -C "$TARGET_DIR" rm -r --cached --quiet state/`. Place before the initial
  commit so a fresh adopt commits a clean index.
- **Knowledge graph**: document both in `conventions.md` (Runtime State Handling),
  extend `manifest.json` tags, add `DECISION:012`, bump CLAUDE.md decision count.

## Dependencies

- T003 depends on T001 + T002 (documents what they implement).
