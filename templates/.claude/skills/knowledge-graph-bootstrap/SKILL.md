---
name: knowledge-graph-bootstrap
description: Initialize a new project's knowledge graph from a brief. Run once at project start. Invoke with: "initialize project from brief <path-to-brief.md>"
trigger: internal
---

# knowledge-graph-bootstrap

You are initializing a new vibekit project's knowledge graph. This is the highest-stakes operation in the system — assumptions made here propagate through every subsequent spec and task. Take your time. Consult Opus generously.

**Before starting:** If `/advisor` is not set to Opus, ask the user to run `/model opus` first.

---

## Phase 1 — Read the Brief

Read the brief file the user provided. Identify:
- The project's primary purpose (one sentence)
- The primary technology stack
- The target users and their core workflows
- Any explicit constraints (performance, compliance, platform)
- Ambiguities that could cause wrong assumptions downstream

---

## Phase 2 — Clarifying Conversation (3–5 exchanges)

Ask the user to resolve the ambiguities you found. Focus on questions where a wrong answer would change the domain file structure or architecture decisions. Do not ask about implementation details that will be resolved task-by-task.

One question per exchange. Stop when you have enough to generate a coherent initial file set.

---

## Phase 3 — Plan the File Set

Before writing anything, determine which domain files are warranted:

- **Always create:** `stack.md`, `architecture.md`, `conventions.md`, `decisions.md`
- **Create if relevant:** `api.md` (external APIs), `data-model.md` (DB schema), `auth.md` (auth flows), `deployment.md` (infra/deploy)
- **Do not create speculatively.** A file is warranted only if there is real content to put in it from the brief + clarifying conversation.

Present the planned file set to the user:
```
Planned knowledge graph:
- docs/claude/stack.md — <one-line summary>
- docs/claude/architecture.md — <one-line summary>
- docs/claude/conventions.md — <one-line summary>
- docs/claude/decisions.md — bootstrap entry
- [any additional files with justification]

CLAUDE.md will be initialized from templates/CLAUDE.md.
manifest.json will be generated from the file set above.

Proceed? (y/n)
```

Wait for confirmation before writing anything.

---

## Phase 4 — Write Everything

On confirmation:

1. **`CLAUDE.md`** — copy from `templates/CLAUDE.md`, replacing `PROJECT_NAME` with the project name, the description line, and updating `Total decisions: 000` to `Total decisions: 001`.

2. **`docs/claude/stack.md`** — primary language + runtime, key dependencies, why they were chosen (from brief/clarifying conversation).

3. **`docs/claude/architecture.md`** — system components, their responsibilities, and how they connect. No implementation details — structural facts only.

4. **`docs/claude/conventions.md`** — code style, naming rules, commit prefixes, any constraints the team has stated. Seed with vibekit's own conventions if none are specified.

5. **`docs/claude/decisions.md`** — one bootstrap entry:
   ```markdown
   <!-- DECISION:001 | domains: architecture, stack -->
   ## DECISION:001 — Initial knowledge graph bootstrap
   **Date:** <YYYY-MM-DD>
   **Context:** Project initialized from brief. Key decisions made during bootstrap:
   - <decision 1>
   - <decision 2>
   **Chosen:** See individual domain files for rationale.
   ```

6. **Any additional domain files** from the Phase 3 plan.

7. **`docs/claude/manifest.json`** — generate from the file set:
   ```json
   {
     "files": [
       { "path": "docs/claude/stack.md", "summary": "<one sentence>", "tags": ["stack"] },
       ...
     ]
   }
   ```

8. **Commit:**
   ```bash
   git add CLAUDE.md docs/claude/ && git commit -m "[claude-docs] bootstrap — initial knowledge graph from brief"
   ```

---

## Done

Tell the user the knowledge graph is initialized and they can now run `/plan <brief.md>` to start speccing features.
