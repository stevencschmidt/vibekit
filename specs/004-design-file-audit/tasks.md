# Tasks: 004-design-file-audit

- [x] T001 · Cleanup stale references + delete obsolete docs/archive/PLAN.md
- [x] T002 · Audit ralph.sh empty SPEC_TASKS_FILE handling
- [x] T003 · Add Design files subsection to docs/claude/architecture.md + manifest tag
- [x] T004 · Vibeplan: design-file loading + location rule + recommended templates
- [ ] T005 · Vibeplan: active-analysis audit pass before Phase 1
- [ ] T006 · CHANGELOG [Unreleased] entries for this spec

---

## T004 · Vibeplan: design-file loading + location rule + recommended templates
Depends on: T003
Verify: `grep -q "Design Files (optional)" templates/.claude/skills/vibeplan/SKILL.md` AND `grep -q "<brief-dir>/design/" templates/.claude/skills/vibeplan/SKILL.md` AND `head -5 templates/.claude/skills/vibeplan/SKILL.md | grep -q "^name: vibeplan"`
Relevant: templates/.claude/skills/vibeplan/SKILL.md, docs/claude/architecture.md, docs/claude/conventions.md

Wire design-file loading into `/vibeplan`. Edit
`templates/.claude/skills/vibeplan/SKILL.md` only — do not touch
`sandbox/ragtest/.claude/skills/vibeplan/SKILL.md` (it is a snapshot, separate
concern). YAML frontmatter must be preserved exactly.

**Edit 1 — new top-level section after `## Detecting Your Mode`:**

```markdown
---

## Design Files (optional)

If a `design/` subdirectory exists adjacent to the brief, `/vibeplan` loads every
`*.md` inside as ambient context for every planning phase and runs the active-analysis
audit pass (see "Active-Analysis Audit Pass" below) before Phase 1 scope-lock
questions.

**Location rule** (single rule, applied across all modes):

| Brief argument                | Design directory checked |
|-------------------------------|--------------------------|
| `/vibeplan brief.md` (root)   | `./design/`              |
| `/vibeplan briefs/P00A.md`    | `briefs/design/`         |
| `/vibeplan briefs/`           | `briefs/design/`         |

If the directory does not exist or is empty, proceed without comment — design files
are optional.

**File convention:** Any `*.md` file inside `design/` is a design file. Subdirectories
are ignored in v1. No README, no ordering — designs are ambient context.

**Recommended (non-enforced) layout template** — for web-app screens:

```markdown
# Screen: <name>

## Route
`/path/to/screen`

## Layout
(ASCII sketch, mermaid flowchart, or numbered list — name every interactive element
so it can be referenced: `btn-submit`, `field-email`, `link-forgot-password`.)

## Elements
| id              | type   | label / behavior                       |
| --------------- | ------ | -------------------------------------- |
| field-email     | input  | email; required                        |
| btn-submit      | button | submits form; → Dashboard on success   |

## States
- empty / default
- loading / submitting
- error (per field; global)
- success (where does the user land?)

## Open questions
Anything you already know is undefined.
```

The **Elements** table is the audit's extraction surface — naming each interactive
element lets the audit enumerate fields/buttons and target questions per element.

For other design types (architecture, data model, API contracts, glossary), use plain
markdown with `mermaid` fenced blocks where helpful. Image-only mockups (PNG, Figma)
are NOT supported.

---
```

**Edit 2 — Brief Audit Mode → Step A:** After the existing bullet that reads `*.md`
files, append a new bullet:

```markdown
- After loading briefs, also read every `*.md` file in `<dir>/design/` if the
  directory exists. These are not audited as briefs — they are loaded as ambient
  context and feed the active-analysis audit pass (see "Active-Analysis Audit Pass"
  below).
```

**Edit 3 — Brief Audit Mode → Step B:** Add a clarifying note at the end of the
existing list, before "Splitting" subsection:

```markdown
**File filtering when enumerating briefs:** skip `README.md`, `brief.md`, and any
path under a `design/` subdirectory.
```

**Edit 4 — Brief Audit Mode → Step C (presentation):** After "Proposed final order"
add a line in the structured output template:

```
Design files loaded: N  (architecture.md, data-model.md, ...)   [omit line if 0]
```

**Edit 5 — Multi-Brief Sequential Mode → Loading the next brief:** Change step 6 from
`"Loading brief N of M: \`<filename>\` — project context from \`brief.md\`."` to:

```markdown
6. Say: "Loading brief N of M: `<filename>` — project context from `brief.md`
   [+ N design files]." (omit the "+ N design files" suffix if no design files
   loaded.)
```

Also add a new step between current steps 1 and 2:

```markdown
1a. Read every `*.md` in `<dir>/design/` if the directory exists. These are ambient
    context — loaded silently, never asked about, and feed the audit pass.
```

**Edit 6 — Build Mode → "Before You Start":** After the existing line
"Read the brief file provided as the argument...", add:

```markdown
Also read every `*.md` in `<brief-dir>/design/` if the directory exists, where
`<brief-dir>` is the parent directory of the brief file. These are loaded silently as
ambient context and feed the audit pass run before Phase 1.
```

Do not modify Fix/Debug Mode — design files do not apply there.

Commit with `[ralph] T004 complete — vibeplan design-file loading`.

---

## T005 · Vibeplan: active-analysis audit pass before Phase 1
Depends on: T004
Verify: `grep -q "Active-Analysis Audit Pass" templates/.claude/skills/vibeplan/SKILL.md` AND `grep -q "Design audit — N concerns identified" templates/.claude/skills/vibeplan/SKILL.md` AND `head -5 templates/.claude/skills/vibeplan/SKILL.md | grep -q "^name: vibeplan"`
Relevant: templates/.claude/skills/vibeplan/SKILL.md, docs/claude/conventions.md

Add the open-ended audit pass that runs after design files load and before Phase 1's
standard scope-lock questions. Edit
`templates/.claude/skills/vibeplan/SKILL.md` only.

Insert a new top-level section **between** the existing `## Phase 1 — Scope Lock`
section and the section that precedes it (which depends on context; in Build Mode
this is "Before You Start", in Multi-Brief Sequential Mode this is the "During the
planning conversation" subsection). Place the new section so it runs *immediately
before* Phase 1's questions in every mode that reaches Phase 1.

**New section content:**

```markdown
---

## Active-Analysis Audit Pass

> This pass runs once, before Phase 1's scope-lock questions, whenever design files
> have been loaded. It does not run if no design files exist.

Audit every design file against the brief, against every other design file, and
against itself for missing or ambiguous behavior. The goal is **maximum coverage of
identified concerns** — surface anything that could affect the project. It is better
to surface a question the user dismisses than to miss something that becomes a late
bug. **You identify concerns; you do not propose solutions at this stage.**

### What to audit (illustrative — not exhaustive, go further)

- **Brief↔design coverage:** Does every user flow / feature in the brief have a
  corresponding design? Does every design correspond to something in the brief, or
  is it scope creep?
- **Design file completeness:** Does each layout have a Route, Elements table,
  States section, navigation? If any are missing, flag them.
- **Per-element specification:** For every named element (field, button, link, list,
  badge, modal, toast), is the behavior, data source, and side-effect fully defined?
- **Cross-screen consistency:** Are header / footer / nav patterns consistent? Do
  similar elements behave the same way? Are typography, spacing, and terminology
  choices coherent across screens?
- **State coverage:** Empty, loading, error, success, partial-data, unauthorized,
  offline — defined for each screen where they could occur?
- **UX flow plausibility:** Can a user reach every screen from a valid entry point
  and back? Dead-ends, orphans, infinite loops, no recoverable error states?
- **Auth and authorization:** Which screens require login? Which roles can access?
  Where does the user land if they fail auth?
- **Data lifecycle:** For every captured value — where stored, validation, conflict
  behavior, edit, delete, export, retention. For every displayed value — source,
  refresh policy, sort/filter/paginate semantics.
- **Accessibility / responsive concerns:** Anything implying keyboard, screen
  reader, mobile breakpoint behavior — defined or undefined?
- **Contradictions:** Anywhere the design says X but the brief says Y, or two
  designs disagree.
- **Anything else** — the bullets above are seeds, not a ceiling. Look broadly.

### Output format (present at start of Phase 1)

```
Design audit — N concerns identified
─────────────────────────────────────
Coverage gaps (designs missing for brief features):
  • <feature from brief> — no design file references it

Per-screen concerns:
  signup.md
    • field-org-name has no documented persistence target → impacts brief item "tenant isolation"
    • no error state defined for duplicate email → impacts brief item "user feedback"
  dashboard.md
    • "recent activity" list has no data source or refresh policy → impacts brief item "real-time updates"

Cross-screen / consistency:
  • Signup uses "Organization", Dashboard sidebar uses "Workspace" — same concept?

Contradictions:
  • brief.md says "guest checkout supported"; checkout.md has no guest path

Out of scope or scope creep:
  • settings.md describes admin panel; brief lists admin work as out-of-scope
```

Omit any category with no entries. If the entire audit finds zero concerns, present:

```
Design audit — 0 concerns identified
─────────────────────────────────────
Design files are internally consistent and aligned with the brief.
```

### Rules

- **Do not propose solutions.** State the concern and the brief item it impacts.
  Wait for the user.
- **No artificial cap.** Surface every concern. Do not hide concerns to keep the
  list short. The user may dismiss any item.
- After presenting the audit, proceed to Phase 1's scope-lock questions. Phase 1
  questions that the design files have already answered should be suppressed (same
  rule as for the brief).
- After Phase 1 responses, if the user has answered audit concerns inline, fold
  those answers into Phase 2 / Phase 3 as confirmed scope. If the user defers a
  concern, note it but do not block.

---
```

Make sure the section is correctly positioned: it must appear after design-file
loading happens (which depends on mode) and before Phase 1's questions are asked.
If Build Mode and Multi-Brief Sequential Mode reach Phase 1 through different
control paths, ensure both paths trigger the audit. Add a one-line cross-reference
near the top of Phase 1: `> If design files were loaded, the Active-Analysis Audit
Pass runs immediately before these questions.`

Commit with `[ralph] T005 complete — vibeplan active-analysis audit pass`.

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
