---
name: plan
description: The primary entry point for planning a new feature or project with vibekit. Run /plan <brief.md> to start.
trigger: /plan
---

# /plan — vibekit Planning Skill

You are running the vibekit planning skill. Your job is to turn a project brief into a complete, executable plan: knowledge graph files, a spec, and a task list that Ralph can run autonomously.

This is a **conversational skill** with 3 phases. Do not skip phases or write files until the user confirms the plan in Phase 3.

---

## Detecting Your Mode

When invoked, first determine which mode applies:

- **Build mode** — the argument is a file path (e.g. `/plan brief.md`). Proceed to "Before You Start" below.
- **Fix mode** — the argument is a problem description (e.g. `/plan the upload button returns 500`), or the user says "fix", "debug", "broken", or "not working". Proceed to "Fix/Debug Mode" below.

If unclear, ask: "Are you planning a new feature, or investigating/fixing something broken?"

---

## Fix/Debug Mode

Your job is to write diagnostic and fix tasks for Ralph — **not to investigate the problem yourself**. Do not run commands, read logs, or explore code. Every investigation and fix happens in a fresh Ralph session with clean context.

### Step 1 — Problem Definition (1 exchange)

Ask in a single message (skip any already answered by the user's description):
1. What is the symptom? (Expected behavior vs. actual behavior)
2. What was the last change before the problem appeared?
3. Is this a regression (worked before) or a first-time failure?

### Step 2 — Task Generation (internal, no back-and-forth)

Write 1–3 tasks to the current spec's `tasks.md`, continuing the T-number sequence from the last completed task. Read `state/sync.json` to find the current task sequence.

**Task shape for unknown root cause — write an investigation task first:**

```markdown
## T___ · Investigate: <symptom>
Depends on: T<prev>
Verify: `python -c "print('investigation complete')"` exits 0
Relevant: docs/claude/architecture.md, docs/claude/<relevant>.md

Read the relevant files. Investigate <symptom> by checking:
- <specific thing to check 1>
- <specific thing to check 2>
Emit TASK_COMPLETE with findings. Do not fix anything in this task — document root cause only.
```

**Task shape for known root cause — write a fix task directly:**

```markdown
## T___ · Fix: <specific problem>
Depends on: T<prev>
Verify: `<deterministic command>` exits 0
Relevant: docs/claude/architecture.md, docs/claude/<relevant>.md

<Precise fix description referencing specific files and patterns.>
Do not refactor surrounding code — fix only what's broken.
```

If root cause is obvious from the user's description, skip the investigation task.

### Step 3 — Commit and run

Update `state/sync.json` with the first new task. Update `SPEC_TASKS_FILE` in `vibekit.config.sh` if this targets a different spec. Add the new tasks to the checkbox list at the top of `tasks.md`. Commit with:
```
[plan] fix: <short problem description> — T___ ready for Ralph
```
Then run Ralph immediately:
```bash
bash scripts/ralph.sh
```

---

## Before You Start

Check whether `/advisor` is set to Opus. If the user hasn't set it, say:

> For best results on scope and dependency decisions, run `/advisor claude-opus-4-6` before continuing.

Then wait for them to set it or indicate they want to proceed without it.

Check whether this is a first run or an existing project:

- **First run:** No `docs/claude/` domain files exist yet. You will bootstrap the knowledge graph AND create the spec in one conversation.
- **Subsequent run:** `docs/claude/` files exist. Read them silently as context before Phase 1. The spec will build on existing patterns.

Read the brief file provided as the argument (e.g. `/plan brief.md` → read `brief.md`). Read it silently before asking anything.

---

## Phase 1 — Scope Lock (2–3 exchanges)

Ask these three questions in a single message:

1. What does success look like for a user? (What can they do after this feature ships that they couldn't before?)
2. What are the hard constraints? (Performance, compatibility, must-use libraries, deadline, etc.)
3. What is explicitly out of scope?

Do not proceed to Phase 2 until you have answers to all three. If the brief already answers them clearly, confirm your understanding and ask only what's missing.

---

## Phase 2 — Structure (1–2 exchanges)

Propose in a single message:

1. **Folder structure** — what new directories or files will be created in the project
2. **Domain files** — which `docs/claude/` files are warranted (no speculative files; only create what this spec genuinely needs)
3. **Stack additions** — any new dependencies or tooling to add to `stack.md`
4. **Spec number and slug** — e.g. `002-user-auth` (check existing `specs/` to pick the next number)

Wait for the user to confirm or adjust. One exchange — not a debate.

---

## Phase 3 — Plan Confirmation (1 exchange)

Show a structured summary before writing anything:

```
Plan: NNN-slug
──────────────────────────────────────
Tasks:   T001 – T00N (N tasks)
Verify:  <verify command>

Knowledge graph:
  CLAUDE.md                    ← router (update)
  docs/claude/architecture.md  ← existing | new
  docs/claude/conventions.md   ← existing | new
  docs/claude/stack.md         ← existing | new
  [any new domain files]       ← new

Settings:
  autoCompactThreshold: 0.5    ✓
  PreCompact hook: sync-agent.sh  ✓
  SessionEnd hook: sync-agent.sh  ✓

──────────────────────────────────────
Ready to generate? (yes / adjust)
```

Wait for "yes" (or adjustment). On adjustment, update and re-show the summary.

---

## On Confirmation — Write Everything

Execute these steps in order:

### 1. Write/update CLAUDE.md router

If first run: create `CLAUDE.md` from the template. Fill in project name, description, routing table, quick facts.
If existing: update the routing table if new domain files are being added.

### 2. Write/update domain files

For each domain file in the plan:
- If new: create from the template in `docs/claude/` with relevant content from the brief and spec conversation
- If existing: add only new content warranted by this spec (do not overwrite existing content)

### 3. Write decisions.md bootstrap entry (first run only)

Add `DECISION:001` to `docs/claude/decisions.md`:

```markdown
<!-- DECISION:001 | domains: project, architecture -->
## DECISION:001 — Bootstrap

- Files updated: CLAUDE.md, [list domain files]
- Why: Initial knowledge graph created from project brief
- Considered but rejected: —
```

**Domain tags are required** in every decision entry anchor (`<!-- DECISION:NNN | domains: ... -->`). Use the names of the domain files most relevant to the decision (e.g. `api`, `auth`, `stack`, `architecture`). Multiple tags are comma-separated. This enables per-domain filtered retrieval: a session working on `api` features reads only the last 3 `api`-tagged decisions rather than the last 5 globally.

For subsequent runs, add a decision entry only if this spec introduces a meaningful architectural choice.

### 4. Write spec files

Create `specs/NNN-slug/spec.md` with:
- Brief summary
- Success criteria (from Phase 1)
- Hard constraints (from Phase 1)
- Out of scope (from Phase 1)
- Technical approach
- Dependencies

Create `specs/NNN-slug/tasks.md` with a checkbox list at the top followed by detailed task sections:

```markdown
# Tasks: NNN-slug

- [ ] T001 · Title
- [ ] T002 · Title

---

## T001 · Title
Depends on: —
Verify: `<command>` exits 0
Relevant: docs/claude/conventions.md

Description precise enough for Ralph to start without asking. Reference specific files,
patterns, and conventions by name. One task = one completable session (~100K token budget).

---

## T002 · Title
Depends on: T001
Verify: `<command>` exits 0
Relevant: docs/claude/conventions.md

Description...
```

The checkbox list at the top is the progress tracker — Ralph marks `- [ ] T001` as `- [x] T001` when complete. The `##` sections are the full task descriptions Ralph reads and executes.

Rules for good tasks:
- Each task has a single verifiable output
- No implicit dependencies on uncommitted work
- `Verify:` is a deterministic command (not "check that it looks right")
- Description includes enough context that Ralph never needs to ask a question

### 5. Populate state/sync.json

Write `T001` into `ralph.task_id`, the task title into `ralph.task_title`, and the files from T001's `Relevant:` line into `ralph.relevant_files`:

```json
{
  "ralph": {
    "task_id": "T001",
    "task_title": "<title of T001>",
    "relevant_files": ["docs/claude/architecture.md", "docs/claude/conventions.md"],
    ...
  }
}
```

If T001 has no `Relevant:` line, write an empty array.

### 6. Update brief.md

Update `brief.md` to reflect any scope decisions, constraints, or out-of-scope items that
emerged during the planning conversation (Phases 1–2) but were not in the original brief.
Do not rewrite the brief — append or correct only what changed. If the brief already
accurately reflects the agreed scope, skip this step.

### 7. Update SPEC_TASKS_FILE in vibekit.config.sh

Update the `SPEC_TASKS_FILE` line in `vibekit.config.sh` to point to this spec's tasks.md:

```bash
SPEC_TASKS_FILE="$PROJECT_ROOT/specs/NNN-slug/tasks.md"
```

Replace the existing `SPEC_TASKS_FILE=` line with the correct path for this spec. This ensures Ralph reads the right tasks.md without any manual config change.

### 8. Verify/fix .claude/settings.json

Write `.claude/settings.json` with exactly this content:
```json
{
  "autoCompactThreshold": 0.5,
  "hooks": {
    "PreCompact": [{"hooks": [{"type": "command", "command": "bash scripts/sync-agent.sh"}]}],
    "SessionEnd":  [{"hooks": [{"type": "command", "command": "bash scripts/sync-agent.sh"}]}]
  }
}
```

After writing, read the file back and confirm:
- `autoCompactThreshold` is present with value `0.5`
- Both hook entries are present with the correct command

If either check fails, rewrite the file. Do not proceed to the commit step until the read-back confirms both values are correct.

### 9. Commit

Stage all changed files and create two commits:

**First commit** (knowledge graph changes):
```
[claude-docs] bootstrap — initial knowledge graph from brief
```
(or `[claude-docs] update <files> — <reason>` for subsequent runs)

**Second commit** (spec):
```
[plan] NNN-slug — N tasks ready for Ralph
```

### 10. Run Ralph

Run Ralph to begin execution immediately:

```bash
bash scripts/ralph.sh
```

Do not print instructions — just run the script. The user confirmed the plan; execution begins now.
