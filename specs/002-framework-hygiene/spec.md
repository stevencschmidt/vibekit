# spec-002: framework-hygiene

## Why

Spec-001 closed cleanly with `[QC_COMPLETE]`, but a retrospective review surfaced four bugs and four enhancements in the framework infrastructure itself — issues that don't change the user-facing protocol but make vibekit more correct, discoverable, and maintainable.

## Bugs addressed

- **B1:** QC stalls when it identifies non-firm gaps (qc-prompt.md doesn't forbid hedging — agents output prose and exit without a sentinel).
- **B2:** `knowledge-graph-bootstrap` skill references `templates/CLAUDE.md`, a path that won't exist in scaffolded projects.
- **B3:** Bootstrap workflow ordering (init.sh → brief → bootstrap → /plan → ralph) is undocumented.
- **B4:** Bootstrap skill has `trigger: internal`, making it non-discoverable as a slash command.

## Enhancements implemented

- **E1:** `scripts/upgrade.sh` to sync framework changes from vibekit into scaffolded projects (the manual sync done at end of spec-001 should be one command).
- **E2:** Tighten `qc-prompt.md` against hedging (paired with B1).
- **E3:** Refactor the 3 near-identical state-file commit blocks in `ralph.sh` (added by T011) into a single `commit_state_files` helper.
- **E4:** Bootstrap skill template path resolution (paired with B2 — solved by inlining).

## Acceptance criteria

All six tasks (T015–T020) ship with passing `Verify:` commands and the spec exits via `[QC_COMPLETE]`. Post-spec, running `bash scripts/upgrade.sh sandbox/ragtest` propagates the changes to the ragtest sandbox cleanly.

## Out of scope

- B5 was a pre-existing template/ragtest drift in `.claude/settings.json`; already fixed during the post-spec-001 manual sync.
- E5 (documenting bootstrap workflow) is folded into T018 alongside B3.
- Running upgrade.sh against ragtest is a manual user action after spec-002 closes — not a task.
