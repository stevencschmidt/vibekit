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

1. **Identify the right domain file.** Load the routing table from `CLAUDE.md` to find the best home. If ambiguous between two files, prefer the more specific one. If no existing file fits, consider creating a new one (only if the domain is genuinely distinct).

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

4. **Add cross-file references** in prose where relevant (e.g. "see docs/claude/decisions.md#031").

5. **Commit** with:
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
3. Update the routing table in `CLAUDE.md` to reference both new files
4. Commit the old file *before* deleting it so it remains in git history
5. Commit the two new files and the updated `CLAUDE.md`
6. Commit message: `[claude-docs] split <old-file> → <new1>, <new2> — domain separated`

**Merge if too small:** If any file has fewer than ~15 lines of real content and hasn't grown after multiple sessions, it isn't earning its routing overhead. Fold it into the most related file:
1. Move the content into the appropriate sibling file
2. Update `CLAUDE.md` routing table to remove the stale entry
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
- **Do not write content into `CLAUDE.md`.** CLAUDE.md is a router only. The only permitted mutations are: adding a row to the routing table when a new domain file is created, and incrementing the `Total decisions:` counter. All other content belongs in a domain file. If no existing domain file fits, create a new one.
