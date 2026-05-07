# spec-004: pharmai-scaffold

## Why

The user wants to start a new enterprise project ("Pharma Content AI" — an AI-powered
assistant for pharmaceutical marketers to generate MLR-compliant promotional content).
The project will leverage the working RAG framework from `sandbox/ragtest`, but evolve
it into a production-grade system with PostgreSQL, multi-index RAG, MLR review workflow,
and React frontend.

Two changes to vibekit itself are needed before the new project starts:

1. **Rename `/plan` → `/vibeplan`** so vibekit's planning skill doesn't collide with
   Claude Code's native `/plan` command.
2. **Scaffold the new project** at `/home/steven/pharmai`, fully self-contained
   (movable to any path), preloaded with the working ragtest source as
   `rag-engine/` and 14 project briefs queued in `briefs/` ready to feed to
   `/vibeplan` one at a time.

The 14 briefs were planned out earlier (in this conversation) and pre-written into
`specs/004-pharmai-scaffold/briefs/` so Ralph can copy them verbatim — the planning
quality is fixed at spec-creation time, not regenerated each task.

## Tasks

- T001 · Rename /plan skill to /vibeplan throughout vibekit
- T002 · Scaffold ~/pharmai via init.sh + copy working ragtest source as rag-engine/
- T003 · Customize pharmai with project-specific CLAUDE.md, brief.md, and domain files
- T004 · Copy the 14 pre-written project briefs into pharmai/briefs/
- T005 · Final QC: verify pharmai is self-contained, then commit all customizations

## Acceptance criteria

- `/vibeplan` works in any newly-scaffolded project; `/plan` skill no longer exists in vibekit
- `/home/steven/pharmai` is a complete vibekit project: scripts/, state/, docs/claude/,
  .claude/skills/vibeplan/, vibekit.config.sh, CLAUDE.md, brief.md
- pharmai/rag-engine/ contains working ragtest server.py, static/index.html, requirements.txt
- pharmai/briefs/ contains 14 brief files (P00A, P00B, P01–P12) plus a README
- No file in pharmai/ contains the absolute path `/home/steven/vibekit` or
  `/home/steven/pharmai` (everything uses `$PROJECT_ROOT` or relative paths)
- pharmai's git repo has an initial scaffold commit + a customization commit; can be
  moved to any directory and continue working

## Out of scope

- Executing any of the 14 briefs (the user feeds them to `/vibeplan` one at a time
  after setup completes)
- Changing vibekit's own decision log, architecture, or runtime behavior beyond the
  /plan → /vibeplan rename
- Migrating sandbox/ragtest in place (it stays as a working pilot reference)

## QC strategy

Run with `--skip-qc`. This spec is a one-shot scaffolding exercise; there is no brief
to QC against beyond this spec.md. The author will manually QC pharmai after Ralph
completes.
