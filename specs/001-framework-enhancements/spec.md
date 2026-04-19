# Spec 001 — Framework Enhancements from ragtest Pilot

## Summary

Four enhancements identified from the ragtest pilot review. Each addresses a specific gap that caused context rot or false-positive task completion during that project's execution.

## Success Criteria

- `/plan` skill populates a meaningful `verify_build()` during bootstrap — no more `return 0` stubs
- Sync agent performs structured delta checks (requirements.txt ↔ stack.md) in addition to diff-based signal detection — so a dependency swap always triggers a graph update
- `manifest.json` exists as the machine-readable routing index, per the knowledge-graph-brief.md design, and is maintained by the sync agent
- Ralph triggers QC checkpoints mid-spec (not only at completion) — catches drift before all tasks have run on bad assumptions

## Hard Constraints

- Must not break the currently running Ralph loop. T004 (which edits `scripts/ralph.sh`) runs last. Changes to ralph.sh take effect on the next run, not this one.
- `sandbox/ragtest/` is a separate git repo and is gitignored — Ralph will not touch it during rollbacks. Updates to ragtest skill files are mirrored manually, not rolled back.
- Every modification to a SKILL.md must keep the YAML frontmatter valid (`name`, `description`, `trigger`) — `verify_build()` enforces this.

## Out of Scope

- Session Policy enforcement hook (PreToolUse on Edit/Write) — deferred; the soft policy in CLAUDE.md is sufficient until it fails in practice.
- Migrating the ragtest project to use manifest.json — the templates are updated but ragtest's routing table stays for now.
- Changing Ralph's sentinel protocol.

## Technical Approach

Four atomic tasks, executed in dependency order. Each modifies both `templates/` (canonical) and `sandbox/ragtest/` (existing instantiation) where applicable, so a fresh `init.sh` scaffold gets the improvements AND the pilot can exercise them.
