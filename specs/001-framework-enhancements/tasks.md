# Tasks: 001-framework-enhancements

- [x] T001 · Auto-populate verify_build() in /plan skill
- [x] T002 · Structured delta checks in sync agent
- [x] T003 · Implement manifest.json end-to-end
- [x] T004 · Checkpoint QC triggers in ralph.sh
- [x] T005 · Make sync-agent.sh non-blocking (auto-compact fix)
- [x] T006 · Split tasks.md — completed bodies move to tasks-archive.md
- [x] T007 · Split brief.md + drift check in completion QC
- [x] T008 · session_log_append coverage + QC stall diagnostic + commit hygiene
- [x] T009 · Document new conventions in domain files
- [x] T010 · Fix sync_write/safety_commit ordering in ralph.sh
- [x] T011 · Fix state file commit gap in ralph.sh
- [x] T012 · Document inline monitoring pattern in conventions.md
- [x] T013 · Fix stale routing-table text in ralph-prompt.md and knowledge-graph-brief.md
- [ ] T014 · Create knowledge-graph-bootstrap skill

---

## T013 · Fix stale routing-table text in ralph-prompt.md and knowledge-graph-brief.md
Depends on: T012
Verify: `! grep -q "routing table row" scripts/ralph-prompt.md && ! grep -q "updating the routing table when a new domain file" knowledge-graph-brief.md`
Relevant: docs/claude/conventions.md, scripts/ralph-prompt.md

**Problem:** Two files contradict the decision (captured in `knowledge-graph-brief.md` lines 77-78 and section "Pillar 1a") that the routing table was eliminated and replaced by `manifest.json`. The stale text implies Ralph should manually update CLAUDE.md when creating a domain file — which is wrong.

1. **`scripts/ralph-prompt.md` line 24** currently reads:
   > The only permitted mutations are adding a routing table row when a new domain file is created or incrementing the decision counter.

   Replace with:
   > The only permitted mutation is incrementing the decision counter. New domain files are created and registered in `docs/claude/manifest.json` by the sync agent — not by Ralph.

2. **`knowledge-graph-brief.md` lines 85–89** currently reads:
   > **CLAUDE.md is never a write target.** Neither the sync agent nor Ralph may write content into CLAUDE.md. The only permitted mutations are: updating the routing table when a new domain file is created, and incrementing the decision counter. Any content that doesn't fit in an existing domain file belongs in a new domain file — not in CLAUDE.md. This invariant must be explicitly enforced in both `knowledge-graph-sync` and `ralph-prompt.md`.

   Replace the sentence "The only permitted mutations are: updating the routing table when a new domain file is created, and incrementing the decision counter." with:
   > The only permitted mutation is incrementing the decision counter.

   The surrounding sentences are correct and should stay unchanged.

Commit with `[ralph] T013 complete — fix stale routing-table text`.

---

## T014 · Create knowledge-graph-bootstrap skill
Depends on: T013
Verify: `test -f templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md && grep -q "knowledge-graph-bootstrap" templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md`
Relevant: docs/claude/conventions.md, docs/claude/architecture.md

**Problem:** The brief (Pillar 1c, lines 331–360 of `knowledge-graph-brief.md`) specifies a `knowledge-graph-bootstrap` skill as a first-class vibekit component — the highest-stakes invocation in the system, where errors compound through every subsequent spec. No such skill file exists anywhere in the repo.

**What to do:**

Create `templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md` with the following structure and content:

```markdown
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
```

Commit with `[ralph] T014 complete — create knowledge-graph-bootstrap skill`.

---

