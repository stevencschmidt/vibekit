---
name: knowledge-graph-sync
description: Background knowledge graph maintenance. Invoked only by sync-agent.sh via PreCompact and SessionEnd hooks. Never call this directly.
trigger: internal
---

# Knowledge Graph Sync

You are running as a background sync agent. You were invoked by a PreCompact or SessionEnd hook — not by a user. Your job is to evaluate whether anything from the recent session is worth persisting to the knowledge graph files in `docs/claude/`.

**You are a sidecar process.** You do not have access to the parent session's conversation history. You determine what happened by examining git state.

---

## Step 1 — Examine What Changed

Run these commands and read their output:

```bash
git diff HEAD
git log --oneline -10
```

Also read the current state of all files in `docs/claude/`.

---

## Step 1.5 — Structured Delta Checks

Before checking for free-form signals, run structured comparisons against known manifest files and source imports. These checks catch stack-level changes that a large diff may bury.

**1. Manifest file vs stack.md**

Check whether any of these files appear in `git diff HEAD`:
- `requirements.txt` or `pyproject.toml` (Python)
- `package.json` (Node)
- `go.mod` (Go)
- `Cargo.toml` (Rust)

If any changed:
1. Parse the current version of the changed manifest to list all declared packages/dependencies.
2. Read `docs/claude/stack.md`.
3. Compare:
   - Any package in the manifest **not listed** in stack.md → mandatory write signal (new dependency, renamed, or version-critical change)
   - Any package in stack.md **not in the manifest** → mandatory write signal (dependency removed)

**2. Imports vs documented deps**

For each changed source file (`*.py`, `*.ts`, `*.js`, `*.go`, `*.rs`):
1. Extract top-level import statements from the current version of the file.
2. Compare against the packages listed in `docs/claude/stack.md`.
3. A top-level import of an undocumented package → mandatory write signal.

**3. Act on structured signals**

If any check above fires:
- Treat it as a confirmed write signal — proceed to Step 3. Do **not** exit silently even if Step 2 finds no free-form signals.
- Update `docs/claude/stack.md` to reflect current reality: add new packages, remove removed ones, note version or name changes.

If no structured checks fire, continue to Step 2.

---

## Step 2 — Check for Signals

Evaluate whether any of these four signals are present in the session's changes:

1. **A decision was made** — something was chosen over alternatives (a library, a pattern, an approach)
2. **A pattern was established** — "we now do X this way" across multiple files or repeated usage
3. **The project's understanding of itself changed** — new domain identified, boundary shifted, assumption invalidated
4. **Something was explicitly resolved after ambiguity** — even if no files were written about it yet

**If none of these signals are present → exit silently. Write nothing. Make no commit.**

---

## Step 3 — Write If Triggered

If one or more signals are present:

1. **Identify the right domain file.** Read `docs/claude/manifest.json` to find the best home for the update. If ambiguous between two files, prefer the more specific one. If no existing file fits, consider creating a new one (only if the domain is genuinely distinct).

2. **Write the update.** Be concise. Add to the relevant section. Do not rewrite existing content — append or insert only.

   **If signal 3 is present (project understanding changed / scope shifted):** also update `brief.md` to reflect the change. Do not rewrite the brief — append or correct only the section that changed.

3. **Log a decision entry** if a choice was made (signal 1). Add to `docs/claude/decisions.md`:
   ```markdown
   <!-- DECISION:NNN | domains: <domain-tags> -->
   ## DECISION:NNN — <short title>

   - Files updated: <file1>, <file2>
   - Why: <the reason this choice was made>
   - Considered but rejected: <alternatives, or "—">
   ```
   **Domain tags are required.** Use the domain file name(s) most relevant to the decision (e.g. `api`, `auth`, `stack`, `architecture`). Multiple tags are comma-separated. This enables per-domain filtered retrieval in future sessions.

   Increment the counter in the `Total decisions:` line in `decisions.md` and in `CLAUDE.md`.

4. **Update manifest.json.** Whenever you create, split, merge, or meaningfully update a domain file, update its entry in `docs/claude/manifest.json` in the same commit:
   - **New file:** append a new entry to the `files` array with an accurate `summary` and `tags`.
   - **Split:** replace the old entry with two new entries, one per new file.
   - **Merge:** remove the merged file's entry; update the target file's entry if its summary changed.
   - **Meaningful content update:** update the `summary` and/or `tags` for that file's entry if they no longer accurately describe its current content.

   The manifest entry format:
   ```json
   {
     "path": "docs/claude/<file>.md",
     "summary": "<one-line description of what this file covers>",
     "tags": ["keyword1", "keyword2", "keyword3"]
   }
   ```

   Keep summaries specific and accurate — they are what Claude reads to decide whether to load a file. Vague summaries degrade retrieval quality.

5. **Add cross-file references** in prose where relevant (e.g. "see docs/claude/decisions.md#031").

6. **Commit** with:
   ```
   [claude-docs] update <filename> — <brief reason>
   ```
   Or for new files:
   ```
   [claude-docs] create <filename> — <new domain>
   ```

---

## Step 4 — File Lifecycle Check

After any write (or independently if no write was triggered), check the size of each domain file in `docs/claude/`:

**Split if oversized:** If any file exceeds ~300 lines, it has become a catch-all and is degrading retrieval precision. Propose splitting it:
1. Identify the two natural sub-domains within the file
2. Create two new files with the split content
3. Update `docs/claude/manifest.json` — replace the old entry with two new entries
4. Commit the old file *before* deleting it so it remains in git history
5. Commit the two new files and the updated `manifest.json`
6. Commit message: `[claude-docs] split <old-file> → <new1>, <new2> — domain separated`

**Merge if too small:** If any file has fewer than ~15 lines of real content and hasn't grown after multiple sessions, it isn't earning its routing overhead. Fold it into the most related file:
1. Move the content into the appropriate sibling file
2. Update `docs/claude/manifest.json` — remove the merged file's entry, update the target file's entry
3. Commit: `[claude-docs] merge <small-file> into <target> — insufficient domain mass`

Do not split or merge speculatively — only act when the threshold is clearly crossed.

---

## What NOT to Do

- Do not write about mechanical changes (dependency bumps, generated files, formatting fixes)
- Do not duplicate content already in the domain files
- Do not create speculative domain files
- Do not modify `state/sync.json` or `state/decisions.md` — those are Ralph's files
- Do not emit any output if you write nothing — silence is correct behavior when no signals are present
- Do not block on errors — if a write fails, exit 0 anyway
- **Do not write content into `CLAUDE.md`.** CLAUDE.md is a router only. The only permitted mutations are: incrementing the `Total decisions:` counter. All other content belongs in a domain file. If no existing domain file fits, create a new one.
- **Always update `manifest.json`** when creating, splitting, merging, or meaningfully updating a domain file. The manifest and domain files must stay in sync.
