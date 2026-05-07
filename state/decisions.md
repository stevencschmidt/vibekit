# Ralph Decisions Log (vibekit project)

Ralph-facing decisions and task-level notes. Distinct from `docs/claude/decisions.md` which is the project-wide architectural log.

## T024 — notify_exit helper

- Added `2>/dev/null || true` to the `printf >>` line in `notify_exit` (spec text described graceful missing-dir handling; spec code sample omitted it — chose safety).
- Covered all 6 rate-limit cap exits (QC pre/mid, task pre/mid, CKPT pre/mid) rather than just the 1 listed in the spec. "and other rate-limit cap exits" in the task description confirmed this intent. Final count: 15 call sites (≥10 required).
