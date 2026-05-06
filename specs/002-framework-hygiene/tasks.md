# Tasks: 002-framework-hygiene

- [x] T015 · Tighten qc-prompt.md against hedging
- [x] T016 · Inline CLAUDE.md content into bootstrap skill
- [x] T017 · Make bootstrap skill user-discoverable
- [ ] T018 · Document bootstrap workflow in README and templates/CLAUDE.md
- [ ] T019 · Refactor state-file commits in ralph.sh into a helper
- [ ] T020 · Create scripts/upgrade.sh for framework sync to scaffolded projects

---

## T017 · Make bootstrap skill user-discoverable
Depends on: T016
Verify: `grep -q "^trigger: /knowledge-graph-bootstrap" templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md`
Relevant: templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md

**Problem:** The bootstrap skill's frontmatter has `trigger: internal`, which means it can't be invoked as a slash command. The brief (Pillar 1c, knowledge-graph-brief.md) states the skill is "Invoked by: 'initialize project from brief'" — implying user-facing invocation. The intent is for the user to run it explicitly at project start, after writing `brief.md`.

**What to do:**

In `templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md`, edit the frontmatter:

1. Change `trigger: internal` → `trigger: /knowledge-graph-bootstrap` (matches `/plan`'s convention of slash-command name = skill name).
2. Update the `description:` line to mention the slash-command invocation explicitly: `Initialize a new project's knowledge graph from a brief. Run once at project start with /knowledge-graph-bootstrap <path-to-brief.md>.`

Do not change anything below the frontmatter `---`.

Commit with `[ralph] T017 complete — make bootstrap skill user-discoverable`.

---

## T018 · Document bootstrap workflow in README and templates/CLAUDE.md
Depends on: T017
Verify: `grep -q "knowledge-graph-bootstrap" README.md && grep -q "knowledge-graph-bootstrap" templates/CLAUDE.md`
Relevant: README.md, templates/CLAUDE.md

**Problem:** A new vibekit user has no way to learn the correct sequence: `init.sh` → write `brief.md` → `/knowledge-graph-bootstrap` → `/plan` → `bash scripts/ralph.sh`. The current README jumps from Setup straight to `/plan`, skipping the bootstrap step entirely. Scaffolded projects' `templates/CLAUDE.md` also doesn't reference bootstrap.

**What to do:**

1. **`README.md`** — insert a new `## Bootstrap` section between the existing `## Setup` and `## Planning & Building (`/plan`)` sections. Content:

   ```markdown
   ## Bootstrap

   After `init.sh` scaffolds a project, you write a brief (`brief.md` at project root, ~1 page describing what the project should do) and invoke the bootstrap skill once:

   ```
   /knowledge-graph-bootstrap brief.md
   ```

   Bootstrap reads the brief, has a 3–5 exchange clarifying conversation, and generates the initial knowledge graph: `CLAUDE.md` router + the warranted domain files under `docs/claude/` + `manifest.json` + a bootstrap entry in `decisions.md`. Bootstrap commits with `[claude-docs] bootstrap — initial knowledge graph from brief`.

   Bootstrap is the highest-stakes invocation in the framework — assumptions made here propagate through every subsequent spec. Run with `/model opus` enabled.

   **Workflow summary:**
   ```
   init.sh → write brief.md → /knowledge-graph-bootstrap → /plan → bash scripts/ralph.sh
   ```
   ```

2. **`templates/CLAUDE.md`** — under the existing `## Quick Facts` section, append one line:
   ```
   - **Bootstrap:** `/knowledge-graph-bootstrap <brief>` (run once at project start)
   ```

Commit with `[ralph] T018 complete — document bootstrap workflow`.

---

## T019 · Refactor state-file commits in ralph.sh into a helper
Depends on: T018
Verify: `bash -n scripts/ralph.sh && [ "$(grep -c 'commit_state_files' scripts/ralph.sh)" -ge 4 ]`
Relevant: docs/claude/conventions.md, scripts/ralph.sh

**Problem:** T011 added 3 near-identical 2-line blocks at the QC_COMPLETE, stall-exit, and max-iter exit paths in `scripts/ralph.sh`. Each is `git add state/sync.json state/session-log.json … || git commit -m "[claude-docs] state files post-<reason>"`. Future exit paths added to ralph.sh would have to remember this pattern. A helper centralizes it.

**What to do:**

In `scripts/ralph.sh`:

1. Add a helper function near the top of the file (after the SCRIPT_DIR/PROJECT_ROOT setup, before the main loop):

   ```bash
   commit_state_files() {
     local reason="$1"
     git -C "$PROJECT_ROOT" add state/sync.json state/session-log.json 2>/dev/null || true
     git -C "$PROJECT_ROOT" diff --cached --quiet || \
       git -C "$PROJECT_ROOT" commit -m "[claude-docs] state files post-${reason}"
   }
   ```

2. Replace the 3 existing call sites (around lines 569, 969, 987) with helper calls:
   - Post-QC_COMPLETE → `commit_state_files "QC_COMPLETE"`
   - Post-stall-exit → `commit_state_files "stall-exit"`
   - Post-max-iter → `commit_state_files "max-iter"`

3. Leave the preceding `session_log_append` call in place at each site — only the 2-line git block is being replaced.

The verify command grep-counts ≥ 4 occurrences of `commit_state_files` (1 definition + 3 callsites).

Commit with `[ralph] T019 complete — refactor state-file commits into helper`.

---

## T020 · Create scripts/upgrade.sh for framework sync to scaffolded projects
Depends on: T019
Verify: `test -x scripts/upgrade.sh && bash -n scripts/upgrade.sh && bash scripts/upgrade.sh /tmp/nonexistent-vibekit-target 2>&1 | grep -q "vibekit.config.sh"`
Relevant: docs/claude/conventions.md, init.sh

**Problem:** When framework changes ship in vibekit, propagating them to existing scaffolded projects is fully manual: identify changed files, diff each one, copy each one, commit. The post-spec-001 sync to ragtest required ~6 manual file copies. This should be one command.

**What to do:**

Create a new file `scripts/upgrade.sh` (executable). Behavior:

1. **Usage:** `bash scripts/upgrade.sh <target-project-dir>`. If no arg, print usage and exit 1.

2. **Sanity check:** if `<target>/vibekit.config.sh` does not exist, print an error mentioning `vibekit.config.sh` and exit 1 (this is what the verify grep checks for).

3. **Copy framework files** from this vibekit repo's root (compute via `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`, `VIBEKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"`):
   - From `$VIBEKIT_ROOT/scripts/`: `ralph.sh`, `sync-helpers.sh`, `monitor.sh`, `ralph-prompt.md`, `qc-prompt.md`, `sync-agent.sh`
   - From `$VIBEKIT_ROOT/templates/.claude/skills/`: copy each subdirectory recursively (`plan/`, `knowledge-graph-sync/`, `knowledge-graph-bootstrap/`)

4. **Skip:** do not touch `CLAUDE.md`, `docs/claude/`, `state/`, `vibekit.config.sh`, `.gitignore`, `.claude/settings.json` in the target. These are project-customized.

5. **Report:** for each file, classify as `added`, `updated` (different content), or `identical` (no change). Print a summary at the end:
   ```
   Updated: N files
   Added: M files
   Identical: K files
   ```

6. **Use `set -e`** at top, standard SCRIPT_DIR/VIBEKIT_ROOT pattern, and follow conventions in `docs/claude/conventions.md`.

7. **Make executable:** `chmod +x scripts/upgrade.sh` after creation.

8. **Do not commit anything in the target.** The user runs `git status && git commit` in the target after reviewing changes.

The script should not require any external dependencies beyond bash, cp, and diff (or `cmp -s`).

Commit with `[ralph] T020 complete — create upgrade.sh for framework sync`.

---
