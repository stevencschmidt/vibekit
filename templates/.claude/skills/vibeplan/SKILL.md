---
name: vibeplan
description: The primary entry point for planning a new feature or project with vibekit. Run /vibeplan <brief.md> to start.
trigger: /vibeplan
---

# /vibeplan — vibekit Planning Skill

You are running the vibekit planning skill. Your job is to turn a project brief into a complete, executable plan: knowledge graph files, a spec, and a task list that Ralph can run autonomously.

This is a **conversational skill** with 3 phases. Do not skip phases or write files until the user confirms the plan in Phase 3.

---

## Startup Check — Reconnect Running Ralph

Before detecting the mode, check whether Ralph is already running from a previous session:

1. Check if `state/ralph.pid` exists.
2. If it exists, read the PID value. Run `kill -0 <pid>` to check if the process is alive.
3. If alive: Say "Ralph is still running (PID `<pid>`). Reconnecting to progress monitoring..." then start monitoring (see "Monitoring Ralph Progress" below). Do not enter planning — return.
4. If not alive: Read the last 5 lines of `state/ralph.log`. Report: "Ralph process has ended. Last log events: `<last lines>`". Then:
   - If the last lines contain `SPEC_COMPLETE`: proceed to the multi-brief loop (see "Multi-Brief Sequential Mode" below) to advance to the next brief. To find the briefs directory: check `vibekit.config.sh` for a `BRIEFS_DIR` variable, or check `state/sync.json` for a `briefs_dir` field. If neither exists, ask the user: "What is the briefs directory path?" before proceeding.
   - Otherwise: Ask the user: "Ralph exited unexpectedly. Re-run? (y/n)". On yes, re-launch Ralph (see "Launching Ralph" below).
   - Remove `state/ralph.pid` in either case.
5. If `state/ralph.pid` does not exist: proceed normally to "Detecting Your Mode".

---

## Detecting Your Mode

When invoked, first determine which mode applies:

Before matching any mode: if the argument looks like a path (contains `/` or `.` or matches a filename pattern), run `stat` on it. If `stat` confirms it is a directory, treat it as Multi-brief mode regardless of whether it has a trailing slash. Only proceed to Build or Fix mode detection if `stat` confirms a file or the path doesn't exist.

- **Build mode** — the argument is a file path (e.g. `/vibeplan brief.md`). Proceed to "Before You Start" below.
- **Fix mode** — the argument is a problem description (e.g. `/vibeplan the upload button returns 500`), or the user says "fix", "debug", "broken", or "not working". Proceed to "Fix/Debug Mode" below.
- **Multi-brief mode** — the argument is a directory path (e.g. `/vibeplan briefs/`). Detected when the argument ends with `/` or when `stat` confirms it is a directory. If no `specs/` folder exists yet (or it contains no spec subdirectories), enter **Brief Audit Mode** below. Otherwise enter **Multi-Brief Sequential Mode** below.

If unclear, ask: "Are you planning a new feature, or investigating/fixing something broken?"

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

## Brief Audit Mode

This runs once, before any specs exist, when `/vibeplan` is given a directory path.

### Step A — Load all briefs silently

- Read `<dir>/brief.md` — this is the **project north star** (overall vision, tech stack, out-of-scope). You will use this as context throughout all briefs, but never modify it and never re-ask its content.
- Read all other `*.md` files in the directory (skip `README.md` and `brief.md` — those are infrastructure files, not briefs to audit).
- After loading briefs, also read every `*.md` file in `<dir>/design/` if the
  directory exists. These are not audited as briefs — they are loaded as ambient
  context and feed the active-analysis audit pass (see "Active-Analysis Audit Pass"
  below).
- If a `README.md` exists, note its file ordering as a suggestion (not authoritative).

### Step B — Structural analysis (internal, before presenting anything)

For each sub-brief, identify:
1. **Dependencies**: what does this brief assume already exists? (auth, schemas, specific APIs, data models, Docker setup)
2. **Ordering violations**: does the proposed order (from README.md or alphabetical) satisfy dependencies?
3. **Gaps**: any required capability not covered by any brief?
4. **Overlaps**: do two briefs duplicate effort?
5. **Granularity**: is any brief too large for one Ralph spec (rough guide: >2 independent workstreams that don't share state, or estimated >15 tasks)? Should it split? Are any briefs so small they should merge with a neighbor (rough guide: <3 tasks estimated)?

**File filtering when enumerating briefs:** skip `README.md`, `brief.md`, and any
path under a `design/` subdirectory.

**Splitting**: Create new sub-brief files with clearly named sub-components (e.g. `P02-ingestion-pipeline.md` → `P02A-ingestion-core.md` + `P02B-async-queue.md`).

**Merging**: Combine content into one file; remove the absorbed file.

### Step C — Present findings in one structured message

```
Brief Audit — <Project Name> (N sub-briefs found)

Dependency order:
  ✓ / ⚠  <brief-A> → <brief-B>: <reason if issue>

Structural changes recommended:
  SPLIT  <filename> — <reason> → <new-file-A> + <new-file-B>
  MERGE  <filename> into <filename> — <reason>

Gaps:
  • <description>

Proposed final order (M briefs after restructure):
  1. <file>  2. <file>  3. <file> ...

Design files loaded: N  (architecture.md, data-model.md, ...)   [omit line if 0]

Confirm, adjust, or override?
```

If no changes are needed, say so and confirm the order.

### Step D — Apply confirmed changes

Apply only what the user confirms:
- **Splits**: create the new sub-brief files, remove the original
- **Merges**: combine content, remove absorbed file; add a `## Merged from <filename>` header in the merged content
- **Reorders**: file content unchanged; order lives in README.md only
- **Gap stubs**: add `## Gap (added by audit): <description>` section to the relevant brief

### Step E — Write README.md

Write `<dir>/README.md` with the confirmed final ordered list. Format: one brief filename per line (no markdown, just filenames). This file is the canonical execution sequence — Ralph uses it to find the next brief.

After writing README.md, persist the briefs directory path: update `vibekit.config.sh` to add or update:
```bash
BRIEFS_DIR="$PROJECT_ROOT/<relative-path-to-briefs-dir>"
```

### Step F — Write audit decision

Append to `state/decisions.md`:
```
<!-- DECISION:NNN | domains: project, architecture -->
## DECISION:NNN — Brief Audit

- Briefs reviewed: N → M after restructure
- Changes: <list splits, merges, reorders>
- Why: Dependency ordering, granularity optimization for Ralph execution
```

Where NNN = next available decision number (read `state/decisions.md` or `docs/claude/decisions.md` to find it).

### Step G — Hand off

Say: "Audit complete. README.md written. Proceeding to plan brief 1 of M: `<filename>`."
→ Immediately proceed to Multi-Brief Sequential Mode (do not wait for another invocation).

---

## Multi-Brief Sequential Mode

This mode handles planning each brief in the sequence, one at a time, with the master brief always in context.

### Loading the next brief

1. Read `<dir>/brief.md` silently — project north star context. Never ask about it.
1a. Read every `*.md` in `<dir>/design/` if the directory exists. These are ambient
    context — loaded silently, never asked about, and feed the audit pass.
2. Read `<dir>/README.md` — the ordered list of brief filenames (one per line).
3. For each filename in order, derive the expected spec slug: lowercase the filename and strip the extension (e.g. `P00A-foundation-refactor.md` → `p00a-foundation-refactor`). Check whether `specs/NNN-<slug>/` exists (any NNN prefix). The first filename with no matching spec folder is the **active brief**.
4. If all briefs have matching spec folders: say "All briefs have been planned and executed. Project complete." Stop.
5. Read the active brief file. This drives Phase 1–3.
6. Say: "Loading brief N of M: `<filename>` — project context from `brief.md`
   [+ N design files]." (omit the "+ N design files" suffix if no design files
   loaded.)

### During the planning conversation

- The master `brief.md` constraints (tech stack, auth model, out-of-scope items) are silently present — do not re-ask questions it already answers.
- Spec number: count existing `specs/` folders + 1, zero-padded to 3 digits.
- Phase 1–3 proceed as normal.
- After confirmation, go to "On Confirmation" and execute all steps normally. Then immediately go to "Launching Ralph" (do not tell the user to run ralph manually).

---

## Before You Start

> This section applies to single-brief (file argument) mode only. For directory arguments, see "Multi-Brief Sequential Mode" above.

Check whether `/advisor` is set to Opus. If the user hasn't set it, say:

> For best results on scope and dependency decisions, run `/advisor claude-opus-4-6` before continuing.

Then wait for them to set it or indicate they want to proceed without it.

Check whether this is a first run or an existing project:

- **First run:** No `docs/claude/` domain files exist yet. You will bootstrap the knowledge graph AND create the spec in one conversation.
- **Subsequent run:** `docs/claude/` files exist. Read them silently as context before Phase 1. The spec will build on existing patterns.

Read the brief file provided as the argument (e.g. `/vibeplan brief.md` → read `brief.md`). Read it silently before asking anything.

Also read every `*.md` in `<brief-dir>/design/` if the directory exists, where
`<brief-dir>` is the parent directory of the brief file. These are loaded silently as
ambient context and feed the audit pass run before Phase 1.

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

## Phase 1 — Scope Lock (2–3 exchanges)

> If design files were loaded, the Active-Analysis Audit Pass runs immediately before these questions.

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
  docs/claude/manifest.json    ← routing index (update)
  docs/claude/architecture.md  ← existing | new
  docs/claude/conventions.md   ← existing | new
  docs/claude/stack.md         ← existing | new
  [any new domain files]       ← new

Settings:
  autoCompactThreshold: 0.5    ✓
  PreCompact hook: sync-agent.sh  ✓
  SessionEnd hook: sync-agent.sh  ✓

Brief: trim to current scope (Y/n)   ← only shown if scope shift detected

──────────────────────────────────────
Ready to generate? (yes / adjust)
```

Wait for "yes" (or adjustment). On adjustment, update and re-show the summary.

---

## On Confirmation — Write Everything

Execute these steps in order:

### 1. Write/update CLAUDE.md router

If first run: create `CLAUDE.md` from the template. Fill in project name, description, and quick facts. The routing table is replaced by `docs/claude/manifest.json` — do not add a routing table to CLAUDE.md.
If existing: do not add routing table rows. `manifest.json` is the routing index.

### 2. Write/update domain files

For each domain file in the plan:
- If new: create from the template in `docs/claude/` with relevant content from the brief and spec conversation
- If existing: add only new content warranted by this spec (do not overwrite existing content)

### 2a. Write/update manifest.json

Maintain `docs/claude/manifest.json` — the machine-readable index of every domain file.

**First run:** Create `docs/claude/manifest.json` with an entry for every domain file you just created:
```json
{
  "files": [
    {
      "path": "docs/claude/architecture.md",
      "summary": "<one-line summary of what this file covers>",
      "tags": ["architecture", "design", "boundaries"]
    },
    {
      "path": "docs/claude/conventions.md",
      "summary": "<one-line summary>",
      "tags": ["conventions", "style", "patterns", "naming"]
    },
    {
      "path": "docs/claude/stack.md",
      "summary": "<one-line summary>",
      "tags": ["dependencies", "libraries", "tooling", "stack"]
    }
  ]
}
```

Write a specific, accurate summary for each file based on its actual content. Tags should reflect the keywords a future session would use when searching for context relevant to that domain.

**Subsequent runs:** If new domain files were added in step 2, append their entries to the `files` array. Do not modify entries for existing files.

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
Tier: simple | medium | complex

Description precise enough for Ralph to start without asking. Reference specific files,
patterns, and conventions by name. One task = one completable session (~100K token budget).

---

## T002 · Title
Depends on: T001
Verify: `<command>` exits 0
Relevant: docs/claude/conventions.md
Tier: simple | medium | complex

Description...
```

The checkbox list at the top is the progress tracker — Ralph marks `- [ ] T001` as `- [x] T001` when complete. The `##` sections are the full task descriptions Ralph reads and executes.

As tasks complete, `ralph.sh` moves their `## T###` bodies to `tasks-archive.md`. `/vibeplan` only writes to `tasks.md`.

Rules for good tasks:
- Each task has a single verifiable output
- No implicit dependencies on uncommitted work
- `Verify:` is a deterministic command (not "check that it looks right")
- Description includes enough context that Ralph never needs to ask a question

Assign each task a tier:
- `simple` — mechanical/single-file/config change (e.g. add a flag, update a template)
- `medium` — standard multi-file feature work (default when unsure)
- `complex` — core-logic, cross-cutting, or architectural change

The tier maps to a model via `MODEL_SIMPLE/MEDIUM/COMPLEX` in `vibekit.config.sh` (Haiku/Sonnet/Opus by default). An untagged task falls back to `medium`.

### 5. Populate state/sync.json

Write `T001` into `ralph.task_id`, the task title into `ralph.task_title`, the files from T001's `Relevant:` line into `ralph.relevant_files`, and T001's `Tier:` value into `ralph.tier`:

```json
{
  "ralph": {
    "task_id": "T001",
    "task_title": "<title of T001>",
    "relevant_files": ["docs/claude/architecture.md", "docs/claude/conventions.md"],
    "tier": "medium",
    ...
  }
}
```

If T001 has no `Relevant:` line, write an empty array. If T001 has no `Tier:` line, write `"medium"` as the default.

### 6. Update brief.md (or sub-brief if multi-brief project)

**For single-brief projects:**
Update `brief.md` to reflect any scope decisions, constraints, or out-of-scope items that
emerged during the planning conversation (Phases 1–2) but were not in the original brief.
Do not rewrite the brief — append or correct only what changed. If the brief already
accurately reflects the agreed scope, skip this step.

When this is a **new spec** or a **significant scope shift** (prior brief content becomes
obsolete), ask the user before rewriting `brief.md`:

> "The planning conversation has shifted scope significantly. Trim `brief.md` to current
> scope only and archive the prior content to `brief-archive.md`? (Y/n)"

If they confirm, append the prior `brief.md` content to `brief-archive.md` with a
`## Archived <YYYY-MM-DD>: <reason>` header, then write the trimmed `brief.md`.
For simple fix tasks or minor additions, leave `brief.md` unchanged.

**For multi-brief projects** (if the argument is a file in `briefs/` directory):
The master `brief.md` at the root is the unchanging project vision — do not modify it.
Instead, scope adjustments from this planning conversation go into the sub-brief file itself
(e.g., `briefs/P00B-authentication.md`). Append or correct only what changed in that file.

### 7. Update config in vibekit.config.sh

Update the `SPEC_TASKS_FILE` line to point to this spec's tasks.md:

```bash
SPEC_TASKS_FILE="$PROJECT_ROOT/specs/NNN-slug/tasks.md"
```

**For multi-brief projects** (if the argument was a file in `briefs/` directory):
Also update `BRIEF_FILE` to point to the specific sub-brief currently being planned:

```bash
BRIEF_FILE="$PROJECT_ROOT/briefs/PNN-slug.md"
```

This makes QC precise — the QC agent compares against the *specific brief* being executed,
not the master `brief.md`. This is essential for accurate feedback across 10+ sequential briefs.

### 8. Populate verify_build() in vibekit.config.sh

Detect the project's primary stack from the brief and the proposed file structure (Phase 2):

- **Python** — `requirements.txt`, `pyproject.toml`, or a `.py` entry file is present
- **Node** — `package.json` is present
- **Go** — `go.mod` is present
- **Rust** — `Cargo.toml` is present
- **Bash-only** — none of the above apply

Replace the `verify_build() { return 0; }` stub in `vibekit.config.sh` with a body appropriate to the detected stack:

**Python:**
```bash
verify_build() {
  python -c "import ast; ast.parse(open('<entry>.py').read())" || return 1
  python -c "from <module> import <name>" || return 1
}
```
Use the actual entry file name (e.g. `server.py`, `main.py`, `app.py`). If an importable entry exists, include the import check. If no importable entry is obvious, omit the second line.

**Node (TypeScript):**
```bash
verify_build() {
  npx tsc --noEmit 2>/dev/null || return 1
}
```
If plain JS (no `tsconfig.json`): use `node --check <entry>.js`.

**Go:**
```bash
verify_build() {
  go build ./... || return 1
}
```

**Rust:**
```bash
verify_build() {
  cargo check --quiet || return 1
}
```

**Bash-only:**
```bash
verify_build() {
  for f in scripts/*.sh; do bash -n "$f" || return 1; done
}
```

**Rule:** Do not write `verify_build() { return 0; }` as the sole body. If you cannot determine a plausible verify command from the brief and proposed stack, stop and ask the user before continuing:

> "I need a `verify_build()` command for `vibekit.config.sh`. What command reliably exits 0 when the project is working and non-zero when it's broken? (e.g. `go build ./...`, `python -c "from app import main"`, `npm test -- --passWithNoTests`)"

Do not proceed to the next step until a real verify command is confirmed.

### 9. Verify/fix .claude/settings.json

Write `.claude/settings.json` with exactly this content:
```json
{
  "autoCompactThreshold": 0.5,
  "hooks": {
    "PreCompact": [{"hooks": [{"type": "command", "command": "bash scripts/sync-agent.sh precompact"}]}],
    "SessionEnd":  [{"hooks": [{"type": "command", "command": "bash scripts/sync-agent.sh sessionend"}]}]
  }
}
```

After writing, read the file back and confirm:
- `autoCompactThreshold` is present with value `0.5`
- Both hook entries are present with the correct command

If either check fails, rewrite the file. Do not proceed to the commit step until the read-back confirms both values are correct.

### 10. Commit

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

### 11. Launching Ralph

Start Ralph as a detached background process so it survives if this Claude Code session hits its usage limit:

```bash
nohup bash scripts/ralph.sh >> state/ralph.log 2>&1 & disown
```

ralph.sh writes `state/ralph.pid` itself at startup — do not write it here.

The `nohup` + `disown` ensures Ralph keeps running even if the parent Claude Code process exits. Output appends to `state/ralph.log` (not stdout) so history is preserved across sessions.

### Monitoring Ralph Progress

Immediately after launching, monitor `state/ralph.log` using the Monitor tool (or `tail -f ... | grep`):

```
tail -f state/ralph.log | grep -E "TASK_START|Completed|RATE_LIMIT|RATE_LIMIT_RESUMED|QC_CHECKPOINT|QC_FINAL|SPEC_COMPLETE|Stopped:|STALLED"
```

Translate matched events for the user as they arrive:

| Log event | Display |
|-----------|---------|
| `TASK_START task=T003 title=...` | "Ralph → T003 starting: `<title>`" |
| `Completed T003` | "✓ T003 done" |
| `RATE_LIMIT until ...` | Stop monitoring immediately. Say: "Rate limit hit. Ralph will resume automatically at `<reset_time>` — no action needed on your end. Stopping chat monitoring now to preserve your remaining quota. Optional: to auto-restart Ralph at the shell if it stops, run `echo 'bash scripts/ralph.sh' \| at HH:MM` (replace HH:MM with the reset time; requires `at` to be installed). When you return after the reset, type `/vibe_resume` to check progress." |
| `RATE_LIMIT_RESUMED window=...` | (monitoring already stopped — this event appears in `state/ralph.log` only) |
| `QC_CHECKPOINT n=N` | "Checkpoint QC `<N>` running..." |
| `QC_FINAL round=1` | "Final QC running..." |
| `SPEC_COMPLETE spec=...` | (see Multi-Brief Loop below) |
| `Stopped:` / `STALLED` | Surface with detail. Stop monitoring. Report outcome using the table below. |

Do not block waiting for Ralph — continue responding to the user while monitoring in the background.

### Multi-Brief Loop (directory mode only)

When `SPEC_COMPLETE` is detected in the log:

1. Stop monitoring.
2. Re-read `<dir>/README.md` and re-scan `specs/` to find the next unstarted brief (same algorithm as "Multi-Brief Sequential Mode" above).
3. If a next brief exists: say "Spec complete. Next brief: `<filename>` (N of M). Starting planning..." and immediately begin Phase 1 for that brief (loop back to "Multi-Brief Sequential Mode").
4. If no next brief: say "All M briefs planned and executed. Project complete." Show a one-line summary of all spec folders created.

The user is never prompted to re-invoke `/vibeplan` between briefs.

### Outcome reporting (single-brief or terminal states)

After Ralph exits (for single-brief mode, or on error in multi-brief mode), read `state/ralph.status` and parse the last JSON line for the `event` field:

| event | what to say |
|-------|-------------|
| `QC_COMPLETE` | "Brief complete." |
| `TASK_BLOCKED` | "Blocked on `<summary>`. Fix then: `bash scripts/ralph.sh --task T###`" |
| `TASK_STALL` | "Stalled 3×. Check `state/ralph.log` for details." |
| `VERIFY_FAILED` | "`verify_build()` failed 3×. Fix the verify command or task." |
| `MAX_ITER` | "Hit iteration limit. Re-run `bash scripts/ralph.sh` to continue." |
| `INTERRUPTED` | "Stopped. Re-run `bash scripts/ralph.sh` to resume." |
| `RATE_LIMIT_CAP` | "Rate limit cap hit. Wait for reset then re-run." |
