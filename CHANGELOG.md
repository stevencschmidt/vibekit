# Changelog

All notable changes to vibekit are documented here.

---

## [Unreleased] — Production readiness

- `.gitignore`: added `.env`, `state/sync.json`, `state/session-log.json`, `state/decisions.md`
- Removed pharmai scaffold artifacts (`specs/004-pharmai-scaffold/`)
- `/vibeplan` step 11: now monitors Ralph exit via `state/ralph.status` and reports outcome; suggests next brief command for multi-brief projects
- `/vibeplan` step 6: multi-brief scoping — scope adjustments go into sub-brief, not master `brief.md`
- `/vibeplan` step 7: multi-brief `BRIEF_FILE` config — QC compares against the active sub-brief
- `knowledge-graph-brief.md` → `docs/design.md`
- `changes.md` → `CHANGELOG.md`
- `state/sync.json` reset to blank template

---

## Spec-004 — Pharmai scaffold

- Renamed `/plan` slash command to `/vibeplan` across all framework files
- Scaffolded `~/pharmai` project with ragtest source as rag-engine
- Customized pharmai with 14 sequential project briefs in `briefs/`

---

## Spec-003 — Monitoring + survival

- `scripts/statusline.sh`: in-terminal Ralph progress via Claude Code status line
- `scripts/notify_exit`: cross-platform exit notification helper
- Rate-limit detection hardened: regex anchored, false positives eliminated
- `scripts/install-service.sh`: systemd `--user` unit for reboot survival
- `scripts/upgrade.sh`: framework sync helper
- Anchored polling pattern documented in `docs/claude/conventions.md`

---

## Spec-002 — Framework hygiene

- QC prompt tightened against hedging language
- `knowledge-graph-bootstrap` skill made user-discoverable
- Stale routing-table text removed from domain files
- `state/sync.json` and `state/session-log.json` committed at run end (prevents misleading "Claude did not commit" safety commits on next run)
- Inline monitoring pattern documented: `Bash run_in_background` + poll loop, not `Monitor tail -f`

---

## Spec-001 — Framework enhancements

- `verify_build()` auto-populated in `vibekit.config.sh` by `/vibeplan`
- Structured delta checks in sync agent (semantic diff before writing)
- `docs/claude/manifest.json` end-to-end: created, maintained by sync agent, self-selection in sessions
- Checkpoint QC: fires every N tasks mid-spec (default 3), catches architectural drift early
- `scripts/sync-agent.sh`: made non-blocking — fires and exits, does not stall Ralph or interactive sessions
- `brief.md` drift check: split with archive if scope has shifted significantly
- `tasks-archive.md` split: completed task bodies moved out of `tasks.md` on completion
- Session log: structured JSON appended to `state/session-log.json` on each Ralph exit
- State-file commits: `sync.json` + `session-log.json` committed at Ralph run end
- `scripts/sync-helpers.sh`: `sync_write` / `safety_commit` ordering fixed (write before commit, not after)

---

## Initial release

- `scripts/ralph.sh`: autonomous task execution loop with rate-limit handling, rollback, 3-strike limits, QC loop
- `scripts/ralph-prompt.md`: task prompt template with `{{SKILLS_CONTEXT}}` substitution
- `scripts/qc-prompt.md`: QC agent prompt — reviews against brief, appends gaps as tasks
- `scripts/sync-helpers.sh`: `sync_read`, `sync_write`, `session_log_append`
- `scripts/monitor.sh`: `detect_sentinel`, `extract_task_id`, `extract_block_reason`
- `scripts/sync-agent.sh`: PreCompact/SessionEnd hook wrapper
- `templates/`: full scaffold for `init.sh` — CLAUDE.md, settings.json, vibeplan + knowledge-graph-sync skills
- `init.sh`: one-command project scaffolding
- Knowledge graph: CLAUDE.md router + `docs/claude/` domain files + `manifest.json` routing index
- `state/sync.json` schema: `ralph.task_id`, `ralph.relevant_files`, `ralph.last_sentinel`, session counter
