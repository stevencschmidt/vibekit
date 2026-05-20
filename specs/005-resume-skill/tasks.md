# Tasks: 005-resume-skill

- [x] T001 · Write templates/.claude/skills/resume/SKILL.md
- [x] T002 · Update templates/CLAUDE.md — add /resume to Session Policy
- [x] T003 · Update init.sh — copy resume skill during scaffold
- [x] T004 · CHANGELOG entries for spec 005

---

## T004 · CHANGELOG entries for spec 005
Depends on: T003
Verify: `grep -q "resume" CHANGELOG.md` exits 0
Relevant: docs/claude/conventions.md

Read `CHANGELOG.md`. Find the `## [Unreleased]` section. Add entries following the existing
format. If `### Added` and `### Changed` subsections already exist under `[Unreleased]`, append
to them. If they do not exist, create them.

Under **### Added**:
```
- `/resume` skill — resumes a paused session without replanning; checks `state/ralph.pid`, reads `sync.json` + active `tasks.md`, restarts Ralph if tasks remain or guides to `/vibeplan` if complete
```

Under **### Changed**:
```
- `templates/CLAUDE.md` — Session Policy now references `/resume` for post-pause recovery
- `init.sh` — scaffolds `resume` skill alongside `vibeplan` and `knowledge-graph-sync`
```

Do not modify any versioned release section or entries outside `[Unreleased]`.
