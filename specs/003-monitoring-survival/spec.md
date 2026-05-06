# spec-003: monitoring-survival

## Why

Ralph runs autonomously, but the orchestration loop has been losing visibility in three ways:

1. **Polling false-positives.** Spec-002's poll loop matched the literal `[QC_COMPLETE]` text inside checkpoint-QC review prose and exited early (Bug C3).
2. **No notification when the user's Claude subscription quota hits.** Ralph keeps running in the background, but the user has no way to learn when it has resumed or finished.
3. **Ralph dies on host reboot.** `nohup` survives terminal close but not a reboot.

The user has rejected a separate-pane TUI and asked for in-terminal progress (integrated into Claude Code's existing UI). They've prioritized reboot survival and accepted local notifications as a starting point.

## Tasks

- T021 · Custom statusline script for in-terminal ralph progress
- T022 · Tighten Claude polling pattern in conventions doc (anchored regex; fixes C3)
- T023 · Audit + harden ralph.sh rate-limit detection (raise cap, structured log)
- T024 · `notify_exit` helper + status file + libnotify integration
- T025 · systemd --user unit installer for reboot survival

## Acceptance criteria

All five tasks ship with passing `Verify:` commands. After spec close:

- `scripts/statusline.sh` produces vibekit state when run from project root, empty elsewhere
- Polling pattern in `docs/claude/conventions.md` is anchored
- Rate-limit detection covers all known phrasings; cap raised to 50 (overridable)
- `notify_exit` is called from all 10 ralph.sh exit paths; `state/ralph.status` is gitignored
- `scripts/install-service.sh` generates a working systemd --user unit and prints the linger/enable commands

## Out of scope (known deferred)

- **Bug C1** — T010 incomplete fix (`last_updated` writes before `safety_commit`, fallback commits fire spuriously). Cosmetic — defer to spec-004.
- **Bug C2** — T015 Decision Check guardrail not structurally enforced; QC still hedges. Needs research on enforcement design. Defer.
- **Telegram notifications** — easy add once `notify_exit` exists, deferred for now.

## QC strategy

Run with `--skip-qc`. C2 means QC will likely stall again; addressing it is itself out of scope.
