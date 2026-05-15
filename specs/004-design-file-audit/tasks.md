# Tasks: 004-design-file-audit

- [x] T001 · Cleanup stale references + delete obsolete docs/archive/PLAN.md
- [x] T002 · Audit ralph.sh empty SPEC_TASKS_FILE handling
- [x] T003 · Add Design files subsection to docs/claude/architecture.md + manifest tag
- [x] T004 · Vibeplan: design-file loading + location rule + recommended templates
- [x] T005 · Vibeplan: active-analysis audit pass before Phase 1
- [x] T006 · CHANGELOG [Unreleased] entries for this spec

---

## T006 · CHANGELOG [Unreleased] entries for this spec
Depends on: T005
Verify: `grep -q "briefs/design/" CHANGELOG.md` AND `grep -q "docs/archive/PLAN.md" CHANGELOG.md`
Relevant: docs/claude/conventions.md

Append to the `[Unreleased] — Production readiness` section of `CHANGELOG.md` (do not
create a new section). Add bullets:

```markdown
- `briefs/design/` convention: `/vibeplan` now loads optional design files as ambient
  context across all modes and runs an active-analysis audit pass before Phase 1
- Vibeplan audit: surfaces brief↔design coverage gaps, missing sections, cross-screen
  inconsistencies, brief contradictions, and scope creep — flags concerns without
  proposing solutions
- `vibekit.config.sh`: fix stale `BRIEF_FILE` (was `knowledge-graph-brief.md`, now
  `docs/design.md`)
- `scripts/qc-prompt.md`: fix stale fallback name (`knowledge-graph-brief.md` →
  `docs/design.md`)
- `docs/archive/PLAN.md` removed (superseded by current architecture docs)
- `ralph.sh`: clean preflight error when `SPEC_TASKS_FILE=""` (no active spec)
```

Keep the existing `[Unreleased]` bullets intact above the new additions.

Commit with `[ralph] T006 complete — CHANGELOG entries for spec 004`.
