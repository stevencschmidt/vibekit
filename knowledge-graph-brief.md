# Project Brief: Claude Code Knowledge Graph System

## What This Is

A system that solves two distinct but related problems with how Claude Code operates over
time: **context bloat** and **context rot**. It replaces the monolithic `CLAUDE.md` pattern
with a lean, auto-maintained network of focused markdown files, and pairs that knowledge
graph with a spec-driven autonomous execution engine. The goal is a repeatable, templated
approach to working with Claude Code across an entire project lifecycle — not just a single
session or feature.

## The Core Problems

### Context bloat
`CLAUDE.md` files grow without bound. Every session loads everything, whether relevant or
not. A mature project easily accumulates 8,000–15,000 tokens of context that Claude reads
in full before writing a single line of code. Most of it is irrelevant to the current task.

### Context rot
Claude Code has no memory between sessions. Decisions made in conversation evaporate.
Patterns established in one session are unknown to the next. Over time the model's
understanding of the project degrades — not because the code changed, but because the
knowledge was never persisted anywhere structured.

### What this system is not
This is not a spec authoring tool. Tools like spec-kit solve the problem of writing a good
spec document. This system solves how Claude Code **operates** across sessions, across
features, across a project's entire lifetime. The spec phase is an input to the system, not
its purpose.

---

## The Three-Pillar Architecture

```
Pillar 1: Knowledge Graph     — prevents context bloat and rot
Pillar 2: Spec Engine         — produces atomic, verifiable tasks
Pillar 3: Ralph Execution     — autonomous task execution loop
```

These are independent systems that integrate at well-defined boundaries. Ralph is not a
context management tool. The sync agent is not an execution tool. Conflating them produces
a worse design for both.

---

## Pillar 1: Knowledge Graph

### The Problem It Solves

Every Claude Code session should open with precisely the context it needs and nothing more.
The knowledge graph makes this possible by replacing one monolithic file with a network of
focused domain files, each loaded only when relevant to the current task.

### File Structure

```
CLAUDE.md                        ← router only (~50 lines, always loaded)
docs/claude/
  decisions.md                   ← append-only audit log
  architecture.md                ← universal core
  conventions.md                 ← universal core
  stack.md                       ← universal core
  [auto-created as domains emerge]
  api.md
  auth.md
  data-models.md
  testing.md
  integrations.md
  ...
```

### CLAUDE.md Is a Router, Not a Document

`CLAUDE.md` contains only:
- Project identity (name, one-line description)
- Context-loading instruction pointing to `docs/claude/manifest.json` (the routing table no longer lives in CLAUDE.md and is never manually maintained there)
- Quick facts (test command, dev server, branch convention)
- Decision log counter + instruction to read only the last 5 entries

It never contains content. It points to content. A session that opens CLAUDE.md and loads
two relevant domain files uses ~2,500 tokens. A session that loads a bloated CLAUDE.md uses
8,000–15,000. The router pattern makes this difference structural and permanent.

**CLAUDE.md is never a write target.** Neither the sync agent nor Ralph may write content
into CLAUDE.md. The only permitted mutations are: updating the routing table when a new
domain file is created, and incrementing the decision counter. Any content that doesn't fit
in an existing domain file belongs in a new domain file — not in CLAUDE.md. This invariant
must be explicitly enforced in both `knowledge-graph-sync` and `ralph-prompt.md`.

### decisions.md Is an Append-Only Audit Log

Structured with anchors for precise retrieval:

```markdown
<!-- DECISION:047 | domains: api, stack -->
## 2026-04-11 — Switched to tRPC
- Files updated: api.md, stack.md
- Why: Type safety across client/server eliminated a class of runtime errors
- Considered but rejected: GraphQL (schema overhead too high), REST+Zod (loses end-to-end inference)
```

`CLAUDE.md` keeps a live counter and instructs Claude to read only the last 5 entries,
anchored from the bottom. Domain tags allow further filtering — an API task reads the last
3 API-tagged decisions, not the last 5 of everything.

### relevant_files Convention

Each task in `sync.json` carries a `relevant_files` array specifying which domain md files
Claude Code should load for that task. This is the bridge between the knowledge graph and
the execution engine — it makes context loading precise rather than routing-table-based.

```json
"ralph": {
  "task_id": "T012",
  "relevant_files": ["docs/claude/api.md", "docs/claude/auth.md"]
}
```

### Manifest-Driven Context Loading

The routing table is replaced by `docs/claude/manifest.json` — a machine-readable index of every domain file maintained exclusively by the sync agent. `CLAUDE.md` contains one standing instruction:

> Before starting any task, read `docs/claude/manifest.json`. Based on the task at hand, identify the 1–3 most relevant domain files. Read only those files. State which files you loaded and why.

The manifest entry for each domain file contains: its path, a one-line summary of what it covers, and a `tags` array of keywords. At 40 files, the full manifest costs ~2,000 tokens to read — from which Claude self-selects 1–3 files at ~800 tokens each. Total context overhead stays under 5,000 tokens regardless of how many domain files the project accumulates.

The manifest schema:

```json
{
  "files": [
    {
      "path": "docs/claude/auth.md",
      "summary": "Authentication patterns using Supabase Auth. Server component pattern. JWT handling.",
      "tags": ["auth", "jwt", "session", "login", "signup", "oauth"]
    }
  ]
}
```

Claude self-selects context rather than following a hand-coded routing table. This is more precise than keyword matching and requires zero infrastructure. The manifest scales gracefully — a 40-file project is as navigable as a 10-file one because the selection intelligence lives in the model, not the routing rules.

### Routing Intelligence

Retrieval efficiency comes from four compounding mechanisms:

1. **`manifest.json` self-selection** — Claude reads the manifest at session open and self-selects the 1–3 most relevant domain files. Selection intelligence lives in the model, not in hand-coded routing rules. Improves as manifest summaries and tags are refined by the sync agent.

2. **`relevant_files` in sync.json** — the spec engine populates this array per task so each task carries the exact domain files it needs. Early specs require judgment from the spec engine; later specs are easier to populate correctly because domain boundaries are clearer and files have more signal.

3. **Domain file content quality** — improves continuously as the sync agent adds patterns and decisions, and splits or merges files to maintain signal density. A domain file at spec 10 is richer and more precise than at spec 1. Ralph stalls less because the context it loads is directly relevant.

4. **decisions.md domain tags** — allow Claude to read only the last N decisions tagged for the relevant domain rather than the last N decisions globally. An API task reads the last 3 `api`-tagged decisions, not the last 5 of everything.

These four mechanisms compound over time. By spec 10, the manifest is more precise, the domain files are richer, and `relevant_files` is populated with less ambiguity because domain boundaries are clearer. The system gets better at loading the right context as it accumulates knowledge of the project.

---

## Pillar 1a: Context Management Policy

This is independent of Ralph. It governs interactive Claude Code sessions — conversations
where a human is working directly with Claude Code. This is where context rot and bloat
occur in practice. Ralph's sessions are short by design and do not accumulate context rot;
this policy applies only to human-driven sessions.

### The Invariant

**Autocompact must never fire while the md files are out of date.**

If autocompact fires mid-session and the knowledge graph hasn't been updated, any decisions
or patterns from that session exist only in the compaction summary — ephemeral, lossy,
gone when the session ends. The md files are the durable record. The conversation is
disposable working memory. Compaction is only safe when the two are in sync.

### autoCompactThreshold Verification

The `/plan` skill writes `autoCompactThreshold: 0.5` to `.claude/settings.json`. This
setting must be verified at plan time — if the key is missing or malformed the invariant
breaks silently. The `/plan` skill's settings verification step (step 7) must read back
the file after writing and confirm the key is present with value `0.5`. If Claude Code's
expected key name or format changes across versions, the template must be updated.

### Mechanism: PreCompact Hook

Claude Code's `settings.json` supports a `PreCompact` hook that fires before the
compaction summary is generated. This is the insertion point. The hook runs the sync
agent, which evaluates the session, writes to md files if warranted, commits, then exits.
Autocompact proceeds only after the hook exits cleanly.

```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/sync-agent.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash scripts/sync-agent.sh"
          }
        ]
      }
    ]
  }
}
```

The autocompact threshold is set aggressively — 50% of the context window. Compact early,
while there is still enough context for the summary to be coherent. The sync agent runs
frequently as a result, but most runs will be silent (nothing worth persisting), so the
cost impact is low.

### Session End Hook

The `SessionEnd` hook runs the same sync agent on session close, catching anything that
didn't trigger a mid-session compaction. This ensures no session ends with knowledge
stranded in conversation history.

### The Four Signals That Trigger a Write

The sync agent evaluates whether any of these occurred before writing anything:

1. A decision was made (something chosen over alternatives)
2. A pattern was established ("we now do X this way")
3. The project's understanding of itself changed (new domain, shifted boundary, invalidated assumption)
4. Something was explicitly resolved after ambiguity in conversation — even if no files were written yet

If none of these signals are present, the sync agent exits silently and autocompact
proceeds. Nothing is written. No commit is made.

### brief.md as Living Scope Document

`brief.md` is not a static input. It must stay current with the project's actual scope.
Two moments trigger an update:

1. **Post-planning** — the `/plan` skill updates `brief.md` after Phase 3 confirmation to
   reflect any scope decisions, constraints, or out-of-scope items that emerged during the
   planning conversation but weren't in the original brief.
2. **Scope change in session** — if the sync agent detects that the project's scope or
   definition changed (signal 3 above), it updates `brief.md` in addition to the relevant
   domain file.

`brief.md` is the canonical record of what the project is meant to do. The QC loop (see
Pillar 3) reads it directly when evaluating completion.

---

## Pillar 1b: The Sync Agent (`knowledge-graph-sync`)

### What It Does

The sync agent is an **interactive session concern only**. It runs in response to the
`PreCompact` and `SessionEnd` hooks during human-driven Claude Code sessions. Ralph handles
its own knowledge updates through task completion and commit discipline — the sync agent
does not run as part of Ralph's execution loop.

After each hook event, the sync agent answers one question:

> *"Given what just happened in this conversation, is there anything future-Claude needs
> to know that isn't already in the md files?"*

If no → silent. Nothing written. No commit.
If yes → identifies the right file, writes the update, logs a decision if a choice was
made, references related files by path in prose (e.g. "see docs/claude/decisions.md#031"), commits.

Whenever the sync agent creates, splits, merges, or meaningfully updates a domain file, it also updates `manifest.json` — the summary and tags for that file. The manifest is always current because it is updated in the same commit as the file change that warrants it.

**Conversation-decision mode:** The agent recognizes when a long exploratory conversation
has reached a conclusion and persists that decision *before* code is written. This is the
hardest judgment call — Opus handles it.

### What It Does NOT Do

- Watch file changes (too noisy, misses meaning)
- Update docs after every micro-task
- Log mechanical churn (refactors that don't change patterns, dependency updates,
  generated files)
- Run inside Ralph's execution loop (Ralph is self-contained)
- Run in the main conversation context (it is a sidecar — separate context window,
  doesn't pollute the session)

### Model Configuration

The sync agent runs within an interactive Claude Code session. The `/advisor` slash
command, set to Opus at session start, is available throughout — including when the
`PreCompact` hook fires. Sonnet drives the task; Opus is consulted for judgment calls.

**At the start of any interactive session, set:**
```
/advisor → Opus 4.6
```

This persists for the entire session. Every `PreCompact` and `SessionEnd` hook invocation
of the sync agent benefits from Opus advisory without any additional configuration.

**Model roles:**

| Role | Model | Handles |
|------|-------|---------|
| Executor | Sonnet 4.6 | Reading context, writing md files, formatting decisions, adding cross-file path references |
| Advisor | Opus 4.6 | Judging whether something is worth persisting, recognizing conversational closure, resolving ambiguous domain file placement |

### Escalation Trigger Instructions

The sync agent's system prompt must explicitly define when to invoke the advisor. Sonnet
escalates to Opus when:

- Determining whether something constitutes a real decision worth logging vs. a mechanical
  implementation detail
- Evaluating whether a pattern has been established or whether this is a one-off
- Identifying which domain file is the right home for an update when it's ambiguous
- Recognizing that a conversational conclusion has been reached and needs to be persisted
  before code is written
- Detecting that an existing assumption in the md files has been invalidated

For everything else — writing the markdown, formatting the decision entry, adding
cross-file path references — Sonnet handles it without escalation.

---

## Pillar 1c: The Bootstrap Skill (`knowledge-graph-bootstrap`)

**Triggered:** Once, explicitly, at project start
**Invoked by:** `"initialize project from brief"`
**Input:** An initial project brief `.md` file you write (~1 page)

### What It Does

1. Reads the brief
2. Has a clarifying conversation (3–5 exchanges) to resolve ambiguities
3. Determines which md files are warranted — no speculative file creation
4. Generates `CLAUDE.md` router + initial domain file set
5. Creates the first `decisions.md` bootstrap entry
6. Makes the first git commit: `[claude-docs] bootstrap — initial knowledge graph from brief`

The clarifying conversation is load-bearing. Ambiguities resolved here prevent wrong
assumptions from propagating through every subsequent spec and task.

### Model Configuration

Bootstrap runs as an interactive Claude Code session with `/advisor` set to Opus. It is
the highest-stakes invocation in the system — errors made here compound through every
subsequent spec and task. Opus should be consulted generously throughout.

**At session start, set:**
```
/advisor → Opus 4.6
```

---

## Pillar 2: Spec Engine

### The Problem It Solves

Ralph needs atomic, verifiable tasks. A human writing tasks.md by hand produces tasks that
are too large, ambiguously defined, or missing verify conditions. The spec engine produces
tasks that Ralph can execute autonomously — each one completable in a single session, each
one with a deterministic verify command.

### The Workflow

The spec engine follows a structured conversation in Claude Code using slash commands
modelled on spec-kit's interface:

```
/speckit.constitution   — project principles, code standards (once or updated)
/speckit.specify        — what to build and why, not how
/speckit.clarify        — resolve ambiguities before planning
/speckit.plan           — technical approach, reads domain md files automatically
/speckit.tasks          — atomic task decomposition with Verify lines
```

The critical divergence from vanilla spec-kit: `/speckit.plan` **automatically reads the
relevant domain md files** before generating the plan. It already knows your conventions,
your existing patterns, and what decisions have already been made. Each subsequent spec
benefits from the accumulated knowledge of every prior spec. Spec-kit starts fresh each
time. This system compounds.

### Model Configuration

Spec engine conversations run with `/advisor` set to Opus. Sonnet drives; Opus is
consulted on scope decisions that touch existing architectural decisions, and on task
dependency ordering during decomposition.

**At session start, set:**
```
/advisor → Opus 4.6
```

### The Spec Conversation

The conversation runs in three phases:

**Phase 1 — Scope lock** (2–3 exchanges)
- What is the user-visible outcome?
- What are the hard constraints?
- What is explicitly out of scope?

**Phase 2 — Dependency mapping** (1–2 exchanges)
- Which domain md files are relevant to this spec?
- Are there decisions in `decisions.md` that constrain this spec?
- What does this depend on that doesn't exist yet?

**Phase 3 — Decomposition** (internal, no back-and-forth)
- Generates atomic tasks with Verify lines and relevant_files annotations
- Updates `brief.md` to reflect any scope decisions, constraints, or out-of-scope items
  that emerged during Phases 1–2 but weren't in the original brief

### Atomic Task Format

What makes a task atomic for Ralph:
- Completable in a single Claude Code session (~100K token budget)
- Has a single verifiable output (a file exists, a test passes, a command exits 0)
- Has no implicit dependencies on tasks not yet marked `[x]`
- Described precisely enough that Ralph can start without asking a question

```markdown
## T003 · Email/password signup flow
Depends on: T002
Verify: `npm test -- --grep "signup"` exits 0
Relevant: docs/claude/conventions.md, docs/claude/architecture.md

Implement the signup flow using Supabase Auth. Create /app/auth/signup/page.tsx
following the server component pattern in architecture.md. Error handling per
conventions.md error-boundary pattern.
```

The `Verify:` line is what Ralph's `verify_build()` runs. One command, deterministic,
no human judgment required. This is what makes the loop fully autonomous.

### Spec Output Structure

```
specs/
  NNN-slug/
    spec.md          ← full context, decisions, constraints
    tasks.md         ← checkbox list Ralph executes against
    sync.json        ← ralph state for this spec
```

### Model Usage Summary

All interactive sessions follow the same pattern: `/advisor` set to Opus at session start,
Sonnet drives, Opus handles judgment calls. No API configuration. No orchestration layer.

| Session type | Executor | Advisor | When Opus is consulted |
|---|---|---|---|
| Bootstrap | Sonnet 4.6 | Opus 4.6 | Throughout — highest stakes |
| Sync agent (PreCompact) | Sonnet 4.6 | Opus 4.6 | Judgment on what to persist |
| Sync agent (SessionEnd) | Sonnet 4.6 | Opus 4.6 | Judgment on what to persist |
| Spec conversation | Sonnet 4.6 | Opus 4.6 | Scope and dependency decisions |
| Task decomposition | Sonnet 4.6 | Opus 4.6 | Dependency ordering, sizing |

---

## Pillar 3: Ralph Execution Loop

### The Problem It Solves

Ralph is an autonomous task execution engine. It is not a context management tool — that
is Pillar 1's job. Ralph's purpose is to execute the atomic tasks produced by the spec
engine without human supervision: handling rate limits, rolling back on failure, detecting
stalls, and verifying completion before committing.

Ralph is self-contained. It does not run the sync agent. Task completion is recorded by
marking `[x]` in tasks.md and committing with a `[ralph]` prefix. The knowledge graph
stays current because Ralph's tasks are atomic and deterministic — there is no ambiguous
judgment to make and no conversation history to evaluate.

### How It Works

```bash
./scripts/ralph.sh --max 30
```

Per iteration:
1. Reads `sync.json` → current task and `relevant_files`
2. Loads `CLAUDE.md` + the domain files specified in `relevant_files`
3. Calls Claude Code: executes the task
4. Detects `TASK_COMPLETE` sentinel in output
5. Runs `verify_build()` — the task's Verify command
6. On pass: `safety_commit` → marks `[x]` in tasks.md → clears task_id → loops
7. On fail: `git reset --hard` to pre-iteration SHA → retries (3-strike limit)
8. On stall: rollback → retries (3-strike limit, separate counter from build failures)

### Safety Features

- **Git rollback:** Saves HEAD SHA before each iteration. On stall or verification failure,
  `git reset --hard` to that SHA. No partial work survives a failed iteration.
- **Rate limit handling:** Checks OAuth usage before each iteration. On rate limit,
  calculates exact reset time, sleeps until renewal + 30s buffer. Does not count rate
  limits as stalls.
- **TASK_BLOCKED sentinel:** If Claude Code emits `TASK_BLOCKED`, Ralph stops immediately
  with a structured reason. The block reason is human-readable and specific enough for the
  spec engine to use when revising task decomposition.
- **3-strike limits:** Stall failures and build verification failures are tracked
  independently. Three consecutive failures of either type halt execution.

### Session Handoff

Ralph deliberately keeps sessions short — one atomic task per session. This is not a
limitation; it is the design. Fresh context per task means no context rot accumulates
within Ralph's execution loop. The knowledge graph provides continuity across sessions;
the conversation history provides none and is intentionally discarded.

### QC Loop (Post-Completion)

When Ralph exhausts all tasks in `tasks.md` (no unchecked `- [ ]` entries remain), it
does not stop — it enters an automated QC loop before declaring the spec done.

**Loop steps per iteration:**

1. **Review** — run Claude against `brief.md` + the project codebase to identify gaps,
   missing behaviors, or inconsistencies between what was built and what the brief specifies
2. **Triage** — if no gaps are found, emit `[QC_COMPLETE]` and stop. The spec is done.
3. **Task generation** — if gaps are found, append new tasks to `tasks.md` (continuing
   the existing T-number sequence) and update `state/sync.json` with the first new task
4. **Execute** — Ralph resumes normal task execution for the new tasks
5. **Repeat** — after the new tasks complete, re-enter the QC loop from step 1

This loop runs entirely autonomously. It terminates only when Claude finds no remaining
gaps against the brief, or when a `TASK_BLOCKED` sentinel halts execution for human review.

**New sentinel:** `[QC_COMPLETE]` — emitted by the QC agent when review finds no gaps.
This is distinct from `TASK_COMPLETE` and causes Ralph to exit cleanly.

**New file:** `scripts/qc-prompt.md` — the prompt template for the QC agent. Reads
`brief.md`, surveys the codebase, and either emits `[QC_COMPLETE]` or outputs new task
descriptions for Ralph to append to `tasks.md`.

**Commit prefix for QC-added tasks:** `[ralph] QC-T### complete — <description>`

### QC Loop (Checkpoint, Mid-Spec)

Post-completion QC is not enough by itself — by the time all tasks are marked `[x]`,
any architectural drift has been baked into every preceding commit. The ragtest pilot
proved this: T002–T006 all ran against a broken SDK assumption and QC had to unwind
retroactively. Checkpoint QC fires the same review mid-spec so drift is caught while
the delta is still small.

**Trigger:** `CHECKPOINT_QC_EVERY` environment variable (default `3`). After every N
successful task commits, Ralph fires one checkpoint QC iteration provided ≥2 unchecked
tasks still remain (otherwise the completion QC will catch it). Value `0` disables
checkpoint QC entirely (original behavior).

**Semantics:** Uses the same `qc-prompt.md`, `brief.md`, and `[QC_COMPLETE]` sentinel
as completion QC. Log lines tagged `[CKPT-N]`. A checkpoint emitting `[QC_COMPLETE]`
means "no gaps here, continue" — Ralph proceeds to the next scheduled task rather than
exiting. Found gaps are appended to `tasks.md` and picked up on the next iteration.

---

## Git as Version Store

All md files live in the project repo under `docs/claude/`. Two commit prefixes keep
history queryable:

```bash
# All knowledge graph changes
git log --oneline docs/claude/

# Only agent-driven updates
git log --oneline --grep="\[claude-docs\]"

# Only Ralph task completions
git log --oneline --grep="\[ralph\]"

# When a specific decision was made
git log --grep="tRPC" docs/claude/

# State of any file at any point
git show HEAD~5:docs/claude/architecture.md
```

`decisions.md` is the *why* layer. Git is the *what* layer. Together they are a complete
audit trail of every decision, when it was made, and what files it affected.

Commit message formats:
- `[claude-docs] bootstrap — initial knowledge graph from brief`
- `[claude-docs] update api.md, stack.md — switched to tRPC`
- `[claude-docs] create billing.md — new domain from billing spec`
- `[ralph] T007 complete — stripe webhook handler`
- `[ralph] QC-T008 complete — missing error state on signup form`

---

## Token Economics

```
Session open:        CLAUDE.md loads                    ~200 tokens
Manifest read:       full manifest (scales to 40 files) ~2,000 tokens
Domain files loaded: 1–3 self-selected files            ~800 tokens each
Decisions tail:      last N domain-tagged entries        ~300 tokens
─────────────────────────────────────────────────────────────────────
Total overhead per session:                             ~4,000 tokens (worst case)

vs. bloated CLAUDE.md:                                  ~8,000–15,000 tokens
```

**Compaction strategy:** Knowledge lives in the md files, not in conversation history.
The conversation is disposable working memory. Compact aggressively — the 50% threshold
enforces this. The md files are the persistent brain; the compaction summary is irrelevant
as long as the sync agent ran before it fired.

---

## What Remains Manual

| Situation | Your effort |
|-----------|-------------|
| Starting a project | Write the initial brief (~1 page) |
| Bootstrap conversation | 3–5 clarifying answers |
| Spec conversation | Phase 1 + 2 answers (~10 minutes) |
| Task list review | Read tasks.md, adjust if needed |
| New domain appears | Answer 1 question |
| Conflicting decisions detected | Answer 1 question |
| TASK_BLOCKED | Read reason, revise task or unblock |
| QC loop gap found | Zero — Ralph adds tasks and continues |
| Everything else | Zero |

---

## The Compounding Effect

This is the property that separates this system from a one-shot spec tool. The knowledge
graph gets more useful with every feature, not less.

By spec 5: the spec agent asks fewer questions because the domain files already contain
the answers. By spec 10: Ralph stalls less because the context it loads is precise and
current. By spec 20: new domain files created by the sync agent encode patterns that
didn't exist at project start — the system has learned the project.

The alternative — a bloated CLAUDE.md that grows to 15,000 tokens and gets loaded in full
every session — degrades in the opposite direction.

---

## File Lifecycle

**File splitting:** When a domain file exceeds ~300 lines, the sync agent advises splitting
it. The router is updated, the old file is committed before deletion, and the two new files
take its place.

**File merging:** If a domain stays small after months, the sync agent advises folding it
into a broader file. Small isolated files add routing overhead without payoff.

**File creation:** The sync agent creates new domain files when it recognizes a new domain
emerging. It does not create files speculatively at bootstrap — only the bootstrap brief
determines the initial file set.

---

## Build Order

1. `knowledge-graph-bootstrap` skill — brief → clarifying conversation → initial file graph → first commit
2. `CLAUDE.md` router template
2a. `manifest.json` schema + sync agent manifest-update responsibility
3. `decisions.md` template + anchor/counter system
4. `knowledge-graph-sync` agent — `PreCompact` hook, `SessionEnd` hook
5. `.claude/settings.json` — hook configuration, 50% autocompact threshold
6. Spec engine slash commands — constitution, specify, clarify, plan, tasks
7. `sync.json` schema + `relevant_files` convention
8. Ralph integration — `TASK_BLOCKED` structured format
9. `init.sh` — bootstraps a new project from scratch end-to-end

---

## Spec Status

**spec-001 (framework-enhancements):** T001–T010 complete. Two tasks pending:
- **T011** — Commit state files (`sync.json`, `session-log.json`) at run end so the next run's safety_commit doesn't sweep up orphaned state with a misleading "Claude did not commit" label.
- **T012** — Document the inline monitoring pattern in `conventions.md`: use `Bash run_in_background` with a poll loop for terminal events, not persistent Monitor `tail -f`.

---

## Open Questions

- **Multi-person projects:** Agent git commits (`[claude-docs]`) create a clear record
  of AI-driven vs. human changes. A team convention is needed for who resolves sync agent
  conflicts when two people work in parallel.
- **Advisor tool in non-interactive contexts:** The `/advisor` slash command is
  session-scoped and interactive only. If a future Claude Code release exposes advisor
  configuration as a CLI flag, scripted invocations could benefit from it. Worth watching.
- **Routing table maintenance:** Resolved. The routing table has been eliminated from CLAUDE.md entirely. The manifest serves as the routing index and is maintained automatically by the sync agent. CLAUDE.md is now fully frozen — it never needs to change as the project grows.
- **TASK_BLOCKED → spec revision loop:** Currently requires human intervention. A future
  iteration could have the spec engine ingest the block reason and automatically revise
  the task decomposition.
