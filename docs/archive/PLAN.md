# vibekit Implementation Plan

## Context

Building **vibekit** — a Claude Code knowledge graph system that solves context bloat and rot across project lifetimes. Distribution model mirrors spec-kit: vibekit is a standalone repo; `init.sh` scaffolds the system into target projects. All three pillars in v1. Skills install per-project into `.claude/skills/`. No Anthropic API required — works on Claude Pro (OAuth) via `claude --dangerously-skip-permissions --print`.

**Existing files (keep, some need reorganization/cleanup):**
- `ralph.sh` — complete execution loop, move to `scripts/ralph.sh`
- `sync-helpers.sh` — functional but references old multi-agent architecture (`architect`, `supervisor` layers); move to `scripts/` and clean up
- `monitor.sh` — clean sentinel detection; move to `scripts/monitor.sh`

**Everything else is built from scratch.**

---

## Directory Structure

### vibekit repo (what we build)

```
vibekit/
  README.md
  init.sh                          # Scaffolds vibekit into a target project

  scripts/                         # Runtime scripts (copied verbatim into target projects)
    ralph.sh                       # Autonomous execution loop [EXISTS — move here]
    sync-helpers.sh                # sync_read/sync_write/session_log_append [EXISTS — move + clean]
    monitor.sh                     # detect_sentinel/extract_block_reason [EXISTS — move here]
    ralph-prompt.md                # Prompt template Claude reads to execute tasks [BUILD]
    sync-agent.sh                  # PreCompact/SessionEnd hook runner [BUILD]

  templates/                       # Files copied into target projects (some need substitution)
    vibekit.config.sh              # Project config template [BUILD]
    state/
      sync.json                    # Initial Ralph state schema [BUILD]
      session-log.json             # Empty session log (JSON array) [BUILD]
      decisions.md                 # Ralph's inter-task decisions log [BUILD]
    CLAUDE.md                      # Router-only template [BUILD]
    docs/claude/
      architecture.md              # Stub [BUILD]
      conventions.md               # Stub [BUILD]
      stack.md                     # Stub [BUILD]
      decisions.md                 # KG append-only audit log [BUILD]
    .claude/
      skills/                      # Claude Code slash command skills [BUILD]
        plan/SKILL.md              # Unified planning skill — user's primary entry point
        knowledge-graph-sync/SKILL.md  # Background sync — invoked by hooks only
      settings.json                # Hook config + 50% autocompact [BUILD]
```

### Target project after `init.sh`

```
my-project/
  CLAUDE.md                        # Router pointing to docs/claude/
  vibekit.config.sh                # Tool/model/path config + verify_build()

  scripts/
    ralph.sh
    sync-helpers.sh
    monitor.sh
    ralph-prompt.md
    sync-agent.sh

  state/
    sync.json                      # Ralph state: task_id, sentinels, session counter
    session-log.json               # Per-session execution history
    decisions.md                   # Ralph's pattern/decision log (inter-task coherence)
    ralph.log                      # Append-only run log

  docs/claude/                     # Knowledge graph domain files
    decisions.md                   # Append-only audit log (KG layer)
    architecture.md
    conventions.md
    stack.md

  specs/
    NNN-slug/
      spec.md
      tasks.md

  skills/                          # Optional: domain knowledge packages for Ralph
    <name>/
      manifest.md                  # Skill content injected into ralph-prompt via {{SKILLS_CONTEXT}}
      verify.sh                    # Optional per-skill verification hook

  .claude/
    skills/
      plan/SKILL.md
      knowledge-graph-sync/SKILL.md
    settings.json
```

---

## Build Steps

### Step 1 — Move and clean existing scripts

Reorganize into `scripts/`:
- `ralph.sh` → `scripts/ralph.sh` (no changes to logic)
- `monitor.sh` → `scripts/monitor.sh` (no changes needed — clean already)
- `sync-helpers.sh` → `scripts/sync-helpers.sh` — remove references to `architect`/`supervisor` layers; these were from an older multi-agent design. `session_log_append` layer argument stays flexible but the header comment should reflect `ralph` as the primary layer.

### Step 2 — `templates/vibekit.config.sh`

Defines everything ralph.sh sources. Variables ralph.sh needs:

```bash
TOOL="claude"               # claude | amp
MODEL="claude-sonnet-4-6"   # override with --model flag
SYNC_FILE="$PROJECT_ROOT/state/sync.json"
SESSION_LOG_FILE="$PROJECT_ROOT/state/session-log.json"
RALPH_PROMPT="$PROJECT_ROOT/scripts/ralph-prompt.md"
DECISIONS_FILE="$PROJECT_ROOT/state/decisions.md"
LOG_FILE="$PROJECT_ROOT/state/ralph.log"
SPEC_TASKS_FILE="$PROJECT_ROOT/specs/001-slug/tasks.md"  # update per spec
SKILLS=()                   # e.g. ("typescript" "react")

verify_build() {
  # Project-specific verification command
  # Return 0 = pass, non-zero = fail
  return 0
}
```

`PROJECT_ROOT` is already set by ralph.sh before sourcing this file.

### Step 3 — `state/sync.json` schema

Fields ralph.sh reads/writes via `sync_read`/`sync_write`:

```json
{
  "ralph": {
    "task_id": null,
    "task_title": "",
    "last_sentinel": null,
    "last_updated": null,
    "session": 1
  },
  "execution": {
    "current_task_status": "idle"
  }
}
```

`state/session-log.json` → empty JSON array: `[]`

### Step 4 — `scripts/ralph-prompt.md`

The prompt Claude reads on every iteration. Structure:

```
# Ralph Execution Prompt

You are Ralph, an autonomous task executor...

## Your Task
Read state/sync.json. The current task is in ralph.task_id.

[Instructions for reading tasks.md, executing the task, committing, emitting sentinels]

## Sentinel Protocol
- On completion: emit [TASK_COMPLETE: T###]
- On blocker: emit [TASK_BLOCKED: <specific reason>]
- On context limit: emit [SESSION_HANDOFF]

## Skills Context
{{SKILLS_CONTEXT}}
```

`{{SKILLS_CONTEXT}}` is substituted by ralph.sh with content from registered `skills/<name>/manifest.md` files.

### Step 5 — `scripts/sync-agent.sh`

Runs as the PreCompact and SessionEnd hook. Invokes the knowledge-graph-sync skill via `claude --print`.

Key constraint: this runs as a subprocess with no direct access to the parent session's conversation. It determines what to sync by examining:
1. `git diff HEAD` — what changed in this session
2. `git log --oneline -10` — recent commits
3. Current state of domain files in `docs/claude/`

```bash
#!/usr/bin/env bash
# Invoked by .claude/settings.json PreCompact and SessionEnd hooks
SKILL=$(cat "$(dirname "$0")/../.claude/skills/knowledge-graph-sync/SKILL.md" 2>/dev/null) || exit 0
claude --dangerously-skip-permissions --print "$SKILL" 2>/dev/null || true
exit 0  # Never block compaction
```

### Step 6 — Knowledge graph templates

**`templates/CLAUDE.md`** (~50 lines, router only):
- Project name + one-liner
- Routing table: domain → when to load
- Quick facts (test command, dev server, branch convention)
- Decision counter + "read last 5 entries from docs/claude/decisions.md"

**`templates/docs/claude/decisions.md`** (KG audit log):
- Header with counter `Total decisions: 000`
- Bootstrap entry (DECISION:001) written by /plan skill on first run
- Anchor format: `<!-- DECISION:NNN | domains: x, y -->`

**`templates/docs/claude/architecture.md`**, **`conventions.md`**, **`stack.md`** — minimal stubs with section headers; content filled by /plan on first run.

**`templates/state/decisions.md`** (Ralph's inter-task log, distinct from KG decisions.md):
- Plain markdown
- Ralph appends patterns and key choices here for inter-task coherence
- Created empty by ralph.sh if missing

### Step 7 — Claude Code skills (`.claude/skills/`)

Each is `SKILL.md` with YAML frontmatter + skill body. Two skills ship with vibekit.

---

**`plan/SKILL.md`** — the primary user-facing skill

Single entry point for everything: ingests a brief, runs a structured planning conversation, confirms settings, and produces all files Ralph needs to execute. `/plan` is the only command a user needs to know.

The skill detects whether this is a first run (no `docs/claude/` domain files) or an existing project, and adjusts accordingly:
- **First run**: bootstraps the knowledge graph AND plans the spec in one conversation
- **Subsequent runs**: reads existing domain files as context, then plans the new feature

**Conversation structure (3 phases, ~10–15 min total):**

*Phase 1 — Scope* (2–3 exchanges)
- Reads the brief silently before asking anything
- Asks: "What does success look like for a user? What are the hard constraints? What's explicitly out of scope?"
- Does not proceed until scope is locked

*Phase 2 — Structure* (1–2 exchanges)
- Proposes folder structure for the project
- Proposes which `docs/claude/` domain files are warranted (no speculative files)
- Proposes tech stack entries for `stack.md`
- User confirms or adjusts — one exchange, not a debate

*Phase 3 — Plan confirmation* (1 exchange)
Shows a structured summary before writing anything:
```
Plan: 001-my-feature
──────────────────────────────────────
Tasks:   T001 – T007 (7 tasks)
Verify:  npm test exits 0

Knowledge graph:
  docs/claude/CLAUDE.md        ← router
  docs/claude/architecture.md  ← new
  docs/claude/conventions.md   ← new
  docs/claude/stack.md         ← new

Settings:
  autoCompactThreshold: 0.5    ✓
  PreCompact hook:     sync-agent.sh  ✓
  SessionEnd hook:     sync-agent.sh  ✓

──────────────────────────────────────
Ready to generate? (yes / adjust)
```

On confirmation:
1. Writes `CLAUDE.md` router (or updates existing)
2. Creates/updates domain files (`architecture.md`, `conventions.md`, `stack.md`, + any new domains)
3. Writes `docs/claude/decisions.md` DECISION:001 bootstrap entry
4. Writes `specs/NNN-slug/spec.md`
5. Writes `specs/NNN-slug/tasks.md` with checkbox tasks
6. Populates `state/sync.json` with T001
7. Verifies `.claude/settings.json` has correct autocompact + hooks (writes/corrects if not)
8. Commits: `[claude-docs] bootstrap — initial knowledge graph from brief` + `[plan] 001-slug — N tasks ready for Ralph`
9. Prints: `Plan ready. Run: bash scripts/ralph.sh --max 50`

**Task format written by `/plan`:**
```
## T001 · Title
Depends on: —
Verify: `<command>` exits 0
Relevant: docs/claude/architecture.md

Description precise enough for Ralph to start without asking.
```

---

**`knowledge-graph-sync/SKILL.md`** — background maintenance only (never called directly by user)

Invoked exclusively by `sync-agent.sh` via PreCompact and SessionEnd hooks.
- Examines `git diff HEAD`, `git log --oneline -10`, current state of `docs/claude/`
- Checks for 4 signals: decision made, pattern established, project understanding changed, ambiguity resolved
- If none → silent exit (no write, no commit)
- If triggered → writes to the right domain file, adds decision anchor with `<!-- DECISION:NNN -->`, references related files by path in prose (e.g. "see docs/claude/decisions.md#031")
- Commits: `[claude-docs] update <file> — <reason>`

### Step 8 — `.claude/settings.json` template

```json
{
  "autoCompactThreshold": 0.5,
  "hooks": {
    "PreCompact": [{"hooks": [{"type": "command", "command": "bash scripts/sync-agent.sh"}]}],
    "SessionEnd":  [{"hooks": [{"type": "command", "command": "bash scripts/sync-agent.sh"}]}]
  }
}
```

### Step 9 — `init.sh`

Usage: `./init.sh <target-dir> [project-name]`

1. Create target directory structure
2. Copy `scripts/` verbatim (ralph.sh, sync-helpers.sh, monitor.sh, ralph-prompt.md, sync-agent.sh)
3. Copy templates (substituting `PROJECT_NAME` in vibekit.config.sh and CLAUDE.md)
4. Make scripts executable
5. Create `state/` with sync.json, session-log.json, decisions.md
6. Create `docs/claude/` with stub domain files
7. Install `.claude/skills/` from templates
8. Write `.claude/settings.json`
9. `git init` if no .git present
10. Print next steps

### Step 10 — vibekit's own knowledge graph

Apply vibekit to itself:
- Populate `CLAUDE.md` router for the vibekit repo
- `docs/claude/architecture.md` — three-pillar structure
- `docs/claude/conventions.md` — skill format, sentinel protocol, script conventions
- `docs/claude/stack.md` — bash, SKILL.md format, claude --print, Python 3 for JSON ops

---

## Two Distinct "Skills" Concepts (important)

| Term | Location | Purpose |
|------|----------|---------|
| **Claude Code skills** | `.claude/skills/*/SKILL.md` | Slash commands for interactive sessions (`/plan`, background sync) |
| **Vibekit domain skills** | `skills/<name>/manifest.md` | Domain knowledge injected into ralph-prompt via `{{SKILLS_CONTEXT}}`. Project-specific — zero shipped with vibekit. |

---

## User Experience

The full UX has three phases: **setup** (once), **plan** (per feature), **execute** (autonomous). The user actively participates only in setup and plan. Everything else is automatic.

### Phase 0 — Setup (once, ~5 minutes)

```bash
git clone <vibekit-repo> ~/vibekit
~/vibekit/init.sh ~/my-project "My Project"
cd ~/my-project
git add -A && git commit -m "initial commit"
```

`init.sh` creates the full project scaffold: `scripts/`, `state/`, `docs/claude/`, `.claude/skills/`, `.claude/settings.json`. The user edits one thing before planning: `vibekit.config.sh` to set their `verify_build()` command.

No global install. Deps: `bash`, `python3`, `claude` CLI.

### Phase 1 — Plan (per feature, ~15 minutes in Claude Code)

```
/plan brief.md
```

Three rounds:

**Round 1 — Scope lock**
Claude summarises the brief's outcome, constraints, and out-of-scope. User confirms or corrects.

**Round 2 — Structure**
Claude proposes domain files and folder layout. User confirms or adjusts in one message.

**Round 3 — Plan confirmation**
```
Plan: 001-my-feature
──────────────────────────────────────
Tasks:   T001 – T007 (7 tasks)
Verify:  npm test exits 0

Knowledge graph:
  docs/claude/CLAUDE.md        ← router
  docs/claude/architecture.md  ← new
  docs/claude/conventions.md   ← new
  docs/claude/stack.md         ← new

Settings:
  autoCompactThreshold: 0.5    ✓
  PreCompact hook:     sync-agent.sh  ✓
  SessionEnd hook:     sync-agent.sh  ✓

──────────────────────────────────────
Ready to generate? (yes / adjust)
```

User types **yes**. Claude writes all files, commits, and prints:
```
Plan ready. Run: bash scripts/ralph.sh --max 50
```

One command, one conversation, one yes.

### Phase 2 — Execute (autonomous, zero user input)

```bash
bash scripts/ralph.sh --max 50
```

Ralph streams output per iteration, handles rate limits with a live countdown, rolls back on failure, stops with a structured reason on TASK_BLOCKED. User resolves the block and runs ralph again.

### Background — Knowledge graph stays current (automatic)

PreCompact and SessionEnd hooks fire `sync-agent.sh` on every interactive Claude Code session. The sync agent checks for 4 signals (decision made, pattern established, understanding changed, ambiguity resolved) and writes to `docs/claude/` only when warranted. A `[claude-docs]` commit appears silently in git; if nothing worth persisting happened, silence.

**Git history over time:**
```
[ralph] T007 complete — stripe webhook handler
[ralph] T006 complete — checkout flow
[claude-docs] update conventions.md — error handling pattern established
[ralph] T005 complete — cart persistence
[claude-docs] update architecture.md — switched to server components
[plan] 001-my-feature — 7 tasks ready for Ralph
[claude-docs] bootstrap — initial knowledge graph from brief
```

By spec 5, `/plan` asks fewer questions. By spec 10, Ralph stalls less. The system compounds.

### Monitoring

```bash
tail -f state/ralph.log
git log --oneline --grep="\[ralph\]"
git log --oneline --grep="\[claude-docs\]"
```

---

## Key Design Notes

- **`ralph-prompt.md` is the linchpin** — everything Ralph does flows through it; must give precise instructions for reading tasks.md, committing, and emitting sentinels
- **`sync-agent.sh` context access** — no direct conversation history; uses `git diff HEAD` + `git log` as proxy signals (v1 constraint; meaningful decisions leave traces)
- **Two `decisions.md` files** — `state/decisions.md` (Ralph's inter-task log) vs `docs/claude/decisions.md` (KG audit log); distinct purposes, must not be confused
- **`sync-helpers.sh` cleanup** — remove `architect`/`supervisor` references from header comments; these are from an older multi-agent design

---

## Verification

1. `./init.sh ~/test-project "Test"` → confirm full directory structure
2. `/plan brief.md` in Claude Code → walk through 3-round conversation → confirm yes
3. Confirm files: `docs/claude/` domain files, `CLAUDE.md` router, `docs/claude/decisions.md` DECISION:001, `specs/001-test/tasks.md`, `state/sync.json` with T001
4. Confirm commits: `[claude-docs] bootstrap` + `[plan] 001-test`
5. `bash scripts/ralph.sh --max 1 --dry-run` → preflight shows T001, exits cleanly
6. `bash scripts/ralph.sh --max 1` → T001 executed, verified, `[ralph] T001 complete` commit, checkbox marked
7. Open new session, make a notable decision, close → `[claude-docs]` commit appears (or silence)
