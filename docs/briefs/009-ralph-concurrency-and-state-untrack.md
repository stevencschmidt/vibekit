# Brief: Ralph concurrency safety + state untracking on adopt

## Problem

Diagnosed from a real run in the phramewerks test project (2026-05-29). Two distinct
vibekit flaws produced corrupted execution state and noisy git history. Spec 008
(state-commit-hygiene) addressed part of the second flaw but left a gap.

### Flaw A — `ralph.sh` has no concurrency guard (primary)

`scripts/ralph.sh` writes a pid file (`echo $$ > state/ralph.pid`, line ~462) and
removes it on exit (line ~412), but **never reads or checks it**. There is no
`flock`, `pgrep`, or "already running" guard anywhere in the script. The only
protection that exists is `vibe_resume`'s soft `kill -0` check (SKILL.md step 1),
which is racy and only runs on the resume path — not on a direct
`bash scripts/ralph.sh` invocation, which is exactly what `CLAUDE.md` and
`vibe_resume` step 4 instruct the user to run.

**Observed consequence:** two Ralph loops ran concurrently against the same
`state/sync.json`. The log shows one process re-executing already-completed T001
(`ralph.log:923` — `[3] Starting T001 … 11:37:27`) while a second run started on T003
three minutes later. This caused:
- Duplicate task completions in `state/session-log.json` (e.g. session 4 lists
  `T001, T001, T001`; session 3 `T009, T009`; session 5 `T008, T008`).
- Duplicate git commits (`904f568` and `05f5e98`, both "[ralph] T008 complete —
  register routers…").
- A manual recovery commit: `[ralph-resume] advance sync.json to T003
  (durable reset baseline)`.

### Flaw B — `state/` stays git-tracked in projects scaffolded before spec 008

Spec 008 fixed vibekit's own `templates/.gitignore` (now ignores `state/`) and made
`init.sh` idempotently append `state/` to an existing `.gitignore`. But:
1. The `.gitignore` edit **cannot untrack files already committed** — phramewerks
   still has all 7 `state/` files tracked (`git ls-files state/`), so it still
   produces `Ralph residual-changes commit` / `Ralph post-complete fallback commit`
   noise, and a rollback (`git reset --hard`) can truncate `state/ralph.log`.
2. There is no step that removes already-tracked state files from the index when
   vibekit is adopted into a project that already committed them.

## Desired outcome

1. A second Ralph instance cannot silently run against the same `sync.json`. Starting
   `ralph.sh` while another instance is alive should detect it and refuse (or clearly
   instruct the user), rather than racing. The guard must work for direct
   `bash scripts/ralph.sh` invocations, not just the resume path. Must clean up a
   stale pid/lock left by a crashed run (don't deadlock on a dead pid). SIGINT/SIGTERM
   and normal exit must release the lock.
2. `init.sh` (and the adopt/scaffold path) must ensure `state/` is both ignored AND
   untracked when adopted into a project where those files are already committed —
   i.e. `git rm -r --cached state/` (index only, keep working files) when applicable,
   guarded so it's safe to run repeatedly and on a fresh project where nothing is
   tracked yet.

## Constraints / notes

- Keep it bash + python3 + claude CLI. No new dependencies. Must stay portable
  (the script already accommodates Windows/Git Bash — `flock` may not exist there,
  so the lock approach needs a fallback, e.g. pid-file + `kill -0` liveness check).
- Do not break the existing `vibe_resume` reconnect flow — reconcile the new guard
  with `vibe_resume` SKILL.md step 1 so they agree on liveness semantics.
- This is a vibekit-source change. After implementation, sync to phramewerks via
  `scripts/push-to-phramewerks.sh`. The actual `git rm --cached state/` cleanup of
  the *existing* phramewerks repo must happen in a phramewerks session (git firewall —
  never run git in phramewerks from a vibekit session).
- New infrastructure touched by `init.sh` must also be reflected in
  `push-to-phramewerks.sh`.
- Minor/cosmetic (include only if cheap): `sync.json` ended up with `"session": 0`
  because `RALPH_SESSION` only defaults to 1 on empty/null, not on a literal 0.
  Optional hardening, not the focus.

## Out of scope

- Rate-limit handling (the multi-hour waits observed are the Claude plan's 5-hour
  window resetting; ralph handled them correctly).
