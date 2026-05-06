# Tasks: 002-framework-hygiene

- [x] T015 · Tighten qc-prompt.md against hedging
- [x] T016 · Inline CLAUDE.md content into bootstrap skill
- [x] T017 · Make bootstrap skill user-discoverable
- [x] T018 · Document bootstrap workflow in README and templates/CLAUDE.md
- [x] T019 · Refactor state-file commits in ralph.sh into a helper
- [x] T020 · Create scripts/upgrade.sh for framework sync to scaffolded projects

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
