# Spec 004 — design-file audit + framework hygiene

## Summary

Extend `/vibeplan` to load **optional** design files from a `<brief-dir>/design/`
subdirectory and run a comprehensive audit pass before Phase 1 of planning. The audit
flags every identified concern (coverage gaps, missing sections, UX inconsistencies,
brief contradictions, ambiguous interactions, scope creep — anything) and surfaces them
as clarifying observations during the briefing stage. `/vibeplan` identifies; the user
decides. No solutions are proposed at the audit stage.

Bundled hygiene fixes: stale references (`BRIEF_FILE`, qc-prompt fallback name) and the
obsolete `docs/archive/PLAN.md` are cleaned up. Ralph's preflight handling of an empty
`SPEC_TASKS_FILE` is audited and patched only if it fails obscurely.

## Success Criteria

- `/vibeplan` loads `<brief-dir>/design/*.md` automatically in Build, Brief Audit, and
  Multi-Brief Sequential modes when the directory exists; proceeds silently when absent.
- Before Phase 1's scope-lock questions, `/vibeplan` presents a structured **Design audit
  — N concerns identified** block grouping concerns by category (coverage gaps,
  per-screen, cross-screen, contradictions, scope creep). Every concern names the brief
  item or design file it impacts.
- The audit is **open-ended** — the categories in the skill are illustrative; vibeplan
  surfaces anything it observes, not just listed examples. No artificial cap on count.
- `/vibeplan` does not propose solutions at the audit stage — it states the concern and
  waits for user direction.
- No stale references to `knowledge-graph-brief.md` or `004-pharmai-scaffold` remain in
  `vibekit.config.sh`, `scripts/*.sh`, or `scripts/*.md`.
- `docs/archive/PLAN.md` is removed.
- Ralph exits cleanly (not with a bash error) when `SPEC_TASKS_FILE=""` and no spec is
  active.

## Hard Constraints

- **Append-only history is sacred.** Do not modify `docs/claude/decisions.md` entries
  001–007, any file under `specs/00[1-3]/`, or historical mentions of `/plan` and
  `knowledge-graph-brief.md` in those files. They are historical artifacts.
- **No new domain files.** The design-file convention is documented as a subsection of
  `docs/claude/architecture.md`. No new file under `docs/claude/` is warranted.
- **Image-only mockups out of scope (v1).** Design files must be text/markdown so they
  can be diffed and reasoned over. PNG/Figma exports are not supported.
- **QC remains planning-only with respect to design files.** `scripts/qc-prompt.md` is
  modified only to fix the stale fallback name; QC does not load design files.
- **Per-brief design scoping (frontmatter `applies_to:`) out of scope (v1).** Design files
  are ambient context for every brief.
- **knowledge-graph-bootstrap consolidation out of scope.** That skill may be redundant
  with `/vibeplan`'s first-run path, but consolidating is a separate decision.

## Out of Scope

- QC reading or auditing design files
- Per-brief `applies_to:` frontmatter scoping
- Image/binary mockup support (PNG, Figma)
- Consolidating or removing `knowledge-graph-bootstrap` skill
- Subdirectories under `design/` (flat-only in v1)

## Technical Approach

The design-file convention is a single location rule applied across all modes:

```
location of brief argument          design directory checked
──────────────────────────────────  ─────────────────────────
/vibeplan brief.md (root)           ./design/
/vibeplan briefs/P00A.md            briefs/design/
/vibeplan briefs/  (multi-brief)    briefs/design/
```

`/vibeplan` loads every `*.md` in the design directory as ambient context. The active
audit pass runs once after design files load and before Phase 1 scope-lock questions.

The recommended layout-file format names every interactive element via an Elements table
so the audit can enumerate fields/buttons/lists and target questions per element.

Stale-reference cleanup is mechanical: edit two lines in `vibekit.config.sh`, one line in
`scripts/qc-prompt.md`, `git rm docs/archive/PLAN.md`.

Ralph's empty-SPEC_TASKS_FILE behavior is audited via read-only inspection; a patch is
applied only if Ralph currently fails with a bash error rather than a clean preflight
message.

## Dependencies

None. No new tools, no new packages. All changes are markdown edits, one shell config
edit, and one file deletion.

## Verify

`verify_build()` (existing) — bash syntax check on `scripts/*.sh`, JSON parse on
`docs/claude/manifest.json`, YAML frontmatter check on every `SKILL.md`.

Plus per-task `Verify:` commands listed in `tasks.md`.
