# Tasks: 004-pharmai-scaffold

- [x] T001 · Rename /plan skill to /vibeplan throughout vibekit
- [x] T002 · Scaffold ~/pharmai via init.sh + copy ragtest source as rag-engine/
- [ ] T003 · Customize pharmai with project-specific CLAUDE.md, brief.md, and domain files
- [ ] T004 · Copy the 14 pre-written project briefs into pharmai/briefs/
- [ ] T005 · Final QC: verify pharmai is self-contained, then commit customizations

---

## T001 · Rename /plan skill to /vibeplan throughout vibekit
Depends on: —
Verify: `test -f templates/.claude/skills/vibeplan/SKILL.md && test ! -d templates/.claude/skills/plan && grep -q "skills/vibeplan" init.sh && grep -q "/vibeplan" templates/CLAUDE.md && grep -q "/vibeplan" README.md`
Relevant: docs/claude/conventions.md

The `/plan` slash command in vibekit collides with Claude Code's native `/plan`.
Rename it to `/vibeplan` everywhere it appears in vibekit, including the skill
directory itself, frontmatter, init.sh logic, and all documentation references.

**File operations (use `git mv` where appropriate to preserve history):**

1. Rename the skill directories:
   - `templates/.claude/skills/plan/` → `templates/.claude/skills/vibeplan/`
   - `sandbox/ragtest/.claude/skills/plan/` → `sandbox/ragtest/.claude/skills/vibeplan/`

2. In each renamed `SKILL.md`, update the YAML frontmatter:
   - `name: plan` → `name: vibeplan`
   - `trigger: /plan` → `trigger: /vibeplan`
   - Description: replace any `/plan` references with `/vibeplan`
   - Update body content: every `/plan` invocation example → `/vibeplan`

3. In `init.sh`:
   - Line 67: `mkdir -p "$TARGET_DIR/.claude/skills/plan"` → `…/skills/vibeplan`
   - Lines 129–130: cp source/dest paths use `/skills/plan/` → `/skills/vibeplan/`
   - Line 181: `echo "     /plan brief.md"` → `/vibeplan brief.md`
   - Line 183: `echo "     /plan will guide"` → `/vibeplan will guide`

4. In `templates/CLAUDE.md`: replace every `/plan` with `/vibeplan` (the session
   policy block has multiple references).

5. In `README.md`: replace every `/plan` mention with `/vibeplan`. Includes the
   pillar description, command-flow diagrams, the "Planning and Building a Feature"
   section heading, and example invocations.

6. In `CLAUDE.md` (vibekit root, not templates/): replace `/plan` with `/vibeplan`.

7. In `knowledge-graph-brief.md`: replace `/plan` with `/vibeplan` in all body text.

8. In `docs/claude/architecture.md` and `docs/claude/conventions.md`: replace `/plan`
   with `/vibeplan` in body text. Do NOT modify file paths under `templates/.claude/skills/`
   in these docs unless the path itself contained `/plan/` (it should now be `/vibeplan/`).

9. In `docs/claude/manifest.json`: update the architecture.md `summary` field — change
   `"Three-pillar architecture (Knowledge Graph, /plan, Ralph)..."` to use `/vibeplan`.

10. In `docs/claude/decisions.md`: this is an append-only log of past decisions. Do NOT
    rewrite history. Append a new decision entry at the bottom documenting this rename
    (pattern: `## DECISION:NNN — Rename /plan slash command to /vibeplan`, with date,
    files updated, why). Increment the total count in the existing log header if there
    is one.

11. In `scripts/ralph-prompt.md` and `scripts/qc-prompt.md`: search for `/plan` and replace
    with `/vibeplan` if any references exist.

**After all edits, run `verify_build()` from vibekit.config.sh** to confirm the existing
syntax/JSON/skill-frontmatter checks still pass. The `templates/.claude/skills/*/SKILL.md`
glob will now match `vibeplan/SKILL.md` — its frontmatter must have `name:` and
`description:` lines.

**Commit message:** `[ralph] T001 complete — rename /plan slash command to /vibeplan`

Then write `[TASK_COMPLETE: T001]` and exit.

---

## T002 · Scaffold ~/pharmai via init.sh + copy ragtest source as rag-engine/
Depends on: T001
Verify: `test -d /home/steven/pharmai/scripts && test -f /home/steven/pharmai/scripts/ralph.sh && test -f /home/steven/pharmai/.claude/skills/vibeplan/SKILL.md && test ! -d /home/steven/pharmai/.claude/skills/plan && test -f /home/steven/pharmai/rag-engine/server.py && test -f /home/steven/pharmai/rag-engine/static/index.html && test -f /home/steven/pharmai/rag-engine/requirements.txt && test -d /home/steven/pharmai/briefs`
Relevant: —

Scaffold the new project at `/home/steven/pharmai` using the (now-renamed) init.sh.
After init.sh runs, add the project-specific top-level subfolders and copy the
working RAG source code from sandbox/ragtest into `rag-engine/`.

**Steps:**

1. From the vibekit project root, run:
   ```
   ./init.sh /home/steven/pharmai "Pharma Content AI"
   ```
   This creates the full vibekit scaffold in pharmai/, initializes git, and makes
   an initial scaffold commit.

2. Verify the rename from T001 propagated correctly: pharmai must have
   `.claude/skills/vibeplan/SKILL.md`, NOT `.claude/skills/plan/`.

3. Create the project-specific top-level directories:
   ```
   mkdir -p /home/steven/pharmai/rag-engine
   mkdir -p /home/steven/pharmai/briefs
   ```

4. Copy the working RAG source from sandbox/ragtest into pharmai/rag-engine/:
   ```
   cp /home/steven/vibekit/sandbox/ragtest/server.py        /home/steven/pharmai/rag-engine/
   cp /home/steven/vibekit/sandbox/ragtest/requirements.txt /home/steven/pharmai/rag-engine/
   cp -r /home/steven/vibekit/sandbox/ragtest/static        /home/steven/pharmai/rag-engine/
   ```

5. Copy the ragtest project's CLAUDE.md and brief.md as **reference** files
   (not active routers — they describe the original ragtest pilot, useful as
   context when refactoring):
   ```
   cp /home/steven/vibekit/sandbox/ragtest/CLAUDE.md  /home/steven/pharmai/rag-engine/REFERENCE-CLAUDE.md
   cp /home/steven/vibekit/sandbox/ragtest/brief.md   /home/steven/pharmai/rag-engine/REFERENCE-brief.md
   ```

6. Do NOT copy: state/, data/, rag_sets/, uploads/, scripts/, specs/,
   troubleshooting/, __pycache__/, *.pyc, vibekit.config.sh, docs/, skills/, .claude/.
   Those are runtime artifacts or duplicates of what init.sh already produced.

**Important:** All work in this task is OUTSIDE the vibekit git repo (the changes
are in /home/steven/pharmai, which is its own git repo). Vibekit's `git status`
will show no changes after this task. That is expected — the safety-commit fallback
in ralph.sh will create an empty trace commit; that is fine and intentional.

After completing all steps, write `[TASK_COMPLETE: T002]` and exit.

---

## T003 · Customize pharmai with project-specific CLAUDE.md, brief.md, and domain files
Depends on: T002
Verify: `grep -q "Pharma Content AI" /home/steven/pharmai/CLAUDE.md && test -f /home/steven/pharmai/brief.md && grep -qi "fastapi\|postgresql\|rag" /home/steven/pharmai/docs/claude/stack.md && grep -q "rag-engine" /home/steven/pharmai/docs/claude/architecture.md`
Relevant: docs/claude/architecture.md, docs/claude/conventions.md, templates/CLAUDE.md

Replace the generic templates in pharmai with pharma-specific content. The router
(CLAUDE.md), the project brief, the domain files, and vibekit.config.sh all need to
describe THIS project — not a generic vibekit project.

**Files to write/update in /home/steven/pharmai:**

1. **`CLAUDE.md`** (overwrite the generic init.sh-produced version): use the
   `templates/CLAUDE.md` skeleton from vibekit but specialize for pharma:
   - Title: `# Pharma Content AI`
   - One-line: AI assistant for pharmaceutical marketers to generate MLR-compliant promotional content
   - Quick Facts: Test command `pytest`, Dev command `docker-compose up`, Branch convention `feature/<slug>`,
     Bootstrap `/knowledge-graph-bootstrap brief.md`, Plan command `/vibeplan briefs/P00A-foundation-refactor.md`
   - Session Policy: standard vibekit copy
   - Decision Log: `Total decisions: 000`, points to docs/claude/decisions.md

2. **`brief.md`** (new file at pharmai root): the master project overview. Two pages.
   - Section: Overview — pharma marketing AI, four RAGs, MLR workflow, production output
   - Section: Technical Architecture — FastAPI backend, React frontend, PostgreSQL, LightRAG x4
   - Section: The Four RAGs — Brand, Compliance, Market Intelligence, Competitive Intelligence
   - Section: Core User Flow — chat → tracking intent → content generation → MLR review → production
   - Section: Stack — Python 3.11+, FastAPI, SQLAlchemy/Alembic, React+Vite, Docker Compose,
     Anthropic SDK (OAuth in dev / API key in prod)
   - Section: Existing Code — references rag-engine/ as starting point (working ragtest pilot)
   - Section: Out of Scope — actual final asset builder (HTML email templates, weasyprint PDF, etc.),
     SSO/SAML, multi-tenancy, mobile UI

3. **`docs/claude/architecture.md`**: replace generic content with:
   - Pharma project architecture (FastAPI app/ structure, four LightRAG indexes,
     PostgreSQL schema overview, React frontend layout)
   - Reference: rag-engine/ contains the working ragtest pilot server.py — used as
     algorithm reference, not directly mounted
   - Component map: routers/, services/, models/, frontend/, rag_sets/

4. **`docs/claude/stack.md`**: replace generic content:
   - Backend: Python 3.11, FastAPI, uvicorn, SQLAlchemy, Alembic, psycopg2-binary, pydantic-settings
   - RAG: lightrag-hku, rag-anything (from rag-engine/requirements.txt)
   - LLM: anthropic SDK (production), claude CLI (dev OAuth fallback)
   - Frontend: React 18, TypeScript, Vite, TailwindCSS, Zustand, React Query
   - Infra: Docker, docker-compose, PostgreSQL 16
   - Test: pytest + httpx (backend), Playwright (frontend smoke tests)

5. **`docs/claude/conventions.md`**: keep most of the generic vibekit conventions
   (commit prefixes, sentinel protocol, archive naming) but ADD a project-specific
   section for: Python module layout (app/), API route conventions (/api prefix,
   versioning), database migration naming, RAG index naming.

6. **`docs/claude/decisions.md`**: write the seed entry — DECISION:001 says
   "Built on ragtest as algorithm reference; refactored to modular FastAPI + PostgreSQL
   for enterprise deployment." Update header counter to 001.

7. **`docs/claude/manifest.json`**: update the four file summaries to reflect the
   pharma-specific content. Tags should include "pharma", "rag", "fastapi", "postgresql".

8. **`vibekit.config.sh`**: update so it points at the FIRST brief's spec when the user
   runs `/vibeplan briefs/P00A-foundation-refactor.md`. The `SPEC_TASKS_FILE` should be
   left as `$PROJECT_ROOT/specs/001-slug/tasks.md` (placeholder — vibeplan rewrites it).
   Set `verify_build()` to a sensible default for this stack:
   ```bash
   verify_build() {
     # Will be specialized per-spec by /vibeplan after first brief is processed.
     # Default: backend syntax check + docker-compose validate if present.
     command -v python3 >/dev/null && python3 -c "import ast; [ast.parse(open(f).read()) for f in __import__('glob').glob('app/**/*.py', recursive=True)]" 2>/dev/null
     [ -f docker-compose.yml ] && docker-compose config -q 2>/dev/null
     return 0
   }
   ```

After all edits, write `[TASK_COMPLETE: T003]` and exit.

---

## T004 · Copy the 14 pre-written project briefs into pharmai/briefs/
Depends on: T003
Verify: `test $(ls /home/steven/pharmai/briefs/P*.md 2>/dev/null | wc -l) -eq 14 && test -f /home/steven/pharmai/briefs/README.md`
Relevant: —

The 14 briefs are pre-written in `specs/004-pharmai-scaffold/briefs/`. Copy them
verbatim into `/home/steven/pharmai/briefs/`. Do not modify them.

**Steps:**

1. Verify the 14 briefs exist:
   ```
   ls specs/004-pharmai-scaffold/briefs/P*.md | wc -l   # should output 14
   ```

2. Copy them all into pharmai/briefs/:
   ```
   cp specs/004-pharmai-scaffold/briefs/*.md /home/steven/pharmai/briefs/
   ```

3. Confirm the README is in place at `pharmai/briefs/README.md` (it explains the
   intended order for feeding briefs to `/vibeplan`).

After completion, write `[TASK_COMPLETE: T004]` and exit.

---

## T005 · Final QC: verify pharmai is self-contained, then commit customizations
Depends on: T004
Verify: `test -d /home/steven/pharmai/.git && cd /home/steven/pharmai && git status --porcelain | grep -qE '^\s*$' || git status --porcelain | head -1 && ! grep -rE "/home/steven/(vibekit|pharmai)" /home/steven/pharmai --include='*.sh' --include='*.md' --include='*.json' 2>/dev/null | grep -v 'briefs/\|REFERENCE-\|rag-engine/'`
Relevant: —

QC pharmai for self-containment, then commit the customizations from T003 + T004
into pharmai's own git repo so the entire scaffolding is preserved as a clean
initial state.

**Steps:**

1. Search for hardcoded absolute paths that would break if pharmai is moved:
   ```
   grep -rE "/home/steven/(vibekit|pharmai)" /home/steven/pharmai \
       --include='*.sh' --include='*.md' --include='*.json' 2>/dev/null \
       | grep -v 'briefs/\|REFERENCE-\|rag-engine/'
   ```
   Acceptable hits: REFERENCE-*.md and rag-engine/* (those are reference copies of
   ragtest content that may contain old absolute paths — not active code).
   briefs/ may contain example paths in code blocks — also acceptable as documentation.
   No hits in scripts/, vibekit.config.sh, CLAUDE.md, docs/claude/, .claude/.
   If any found in those locations, fix them to use $PROJECT_ROOT or relative paths.

2. Verify no symlinks point outside pharmai:
   ```
   find /home/steven/pharmai -type l -exec readlink {} \; 2>/dev/null | grep -v '^[^/]\|^\.\.'
   ```
   Output must be empty.

3. Verify all shell scripts are executable:
   ```
   test -x /home/steven/pharmai/scripts/ralph.sh
   test -x /home/steven/pharmai/scripts/sync-agent.sh
   ```

4. Stage and commit pharmai's customizations from T003 + T004:
   ```
   cd /home/steven/pharmai
   git add -A
   git commit -m "Initial pharmai customization: brief.md, domain files, 14 project briefs, rag-engine/ reference"
   ```

5. Confirm pharmai's git log shows two commits: the init.sh scaffold + the customization:
   ```
   cd /home/steven/pharmai && git log --oneline | wc -l   # should output 2
   ```

**Important:** This task does work in pharmai's git repo, NOT vibekit's. Vibekit's
git tree will be clean after this task — the safety-commit fallback in ralph.sh
will fire; that is expected and intentional.

After completion, write `[TASK_COMPLETE: T005]` and exit.
