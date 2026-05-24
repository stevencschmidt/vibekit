# vibekit

Autonomous execution toolkit for Claude Code. Solves two problems that compound across a project's lifetime:

- **Context bloat** — monolithic CLAUDE.md files grow to 10,000+ tokens and get loaded in full every session, most of it irrelevant
- **Context rot** — decisions and patterns established in conversation evaporate between sessions because nothing persists them

vibekit ships as a standalone repo. `init.sh` scaffolds the system into any target project in under a minute.

---

## How it works in one session

Write a brief, run one command, watch it build:

```
User writes brief.md
  → opens Claude Code in project directory
  → runs /vibeplan brief.md
  → 3-phase conversation (scope / structure / confirm)
  → types "yes"
  → Claude writes spec + tasks, starts Ralph automatically
  → Ralph executes tasks autonomously, commits each one
  → QC loop reviews against brief.md
  → emits QC_COMPLETE when done
```

No separate commands after "yes". Ralph runs, verifies, commits, and QCs — all without supervision. When it finishes, Claude reports the outcome and (for multi-brief projects) tells you the exact command to start the next phase.

---

## Three pillars

**1. Knowledge graph** — replaces a monolithic CLAUDE.md with a lean router (~50 lines, always loaded) that points to focused domain files (`docs/claude/`). Each session loads only the files relevant to the current task (~2,500 tokens vs. 8,000–15,000 for a bloated CLAUDE.md). A background sync agent (`sync-agent.sh`) runs on `PreCompact` and `SessionEnd` hooks to persist decisions and patterns before they evaporate.

**2. `/vibeplan` skill** — a structured 3-phase conversation in Claude Code that turns a project brief into a complete, executable plan: knowledge graph files, a spec, and a task list that Ralph can run autonomously. One command, one conversation, one "yes".

**3. Ralph** — autonomous bash execution loop. Reads tasks from `state/sync.json`, runs `claude --print` for each task, detects completion sentinels, verifies the build, commits, and loops. Handles rate limits with live countdowns, rolls back partial work on failure, and stops with a structured reason when blocked.

---

## Prerequisites

- `bash`
- `python3`
- `git`
- `claude` CLI (Claude Code) — authenticated (`claude login`)
- A Claude Pro subscription (Ralph uses `--dangerously-skip-permissions --print`)

---

## Setup (once per project)

**1. Clone vibekit:**
```bash
git clone https://github.com/stevencschmidt/vibekit ~/vibekit
```

**2. Scaffold into your project:**
```bash
~/vibekit/init.sh ~/my-project "My Project"
```

This creates the full project structure under `~/my-project/` and makes an initial git commit.

That's it — you can start planning immediately. `vibekit.config.sh` has sensible defaults and requires no changes to get started.

---

## Bootstrap

After `init.sh` scaffolds a project, you write a brief (`brief.md` at project root, ~1 page describing what the project should do) and invoke the bootstrap skill once:

```
/knowledge-graph-bootstrap brief.md
```

Bootstrap reads the brief, has a 3–5 exchange clarifying conversation, and generates the initial knowledge graph: `CLAUDE.md` router + the warranted domain files under `docs/claude/` + `manifest.json` + a bootstrap entry in `decisions.md`. Bootstrap commits with `[claude-docs] bootstrap — initial knowledge graph from brief`.

Bootstrap is the highest-stakes invocation in the framework — assumptions made here propagate through every subsequent spec. Run with `/model opus` enabled.

**Workflow summary:**
```
init.sh → write brief.md → /knowledge-graph-bootstrap → /vibeplan → bash scripts/ralph.sh
```

---

## Planning and Building a Feature (`/vibeplan`)

Write `brief.md` in your project directory — a plain markdown file describing what you want to build, about a page. Cover what success looks like, any hard constraints, and what's out of scope. No special format required.

Then open Claude Code in your project directory. Before running `/vibeplan`, set the advisor model for better judgment on scope and dependency decisions:

```
/advisor claude-opus-4-6
```

Then run:

```
/vibeplan brief.md
```

The `/vibeplan` skill runs a 3-phase conversation:

**Phase 1 — Scope lock** (2–3 exchanges)
Claude reads the brief and asks three questions: user-visible outcome, hard constraints, out of scope. Confirm or correct.

**Phase 2 — Structure** (1–2 exchanges)
Claude proposes the folder layout and which knowledge graph domain files to create. Confirm or adjust in one message.

**Phase 3 — Plan confirmation** (1 exchange)
Claude shows a full summary before writing anything:
```
Plan: 001-my-feature
──────────────────────────────────────
Tasks:   T001 – T007 (7 tasks)
Verify:  npm test exits 0

Knowledge graph:
  CLAUDE.md                    ← router (update)
  docs/claude/architecture.md  ← new
  docs/claude/conventions.md   ← new
  docs/claude/stack.md         ← new

Settings:
  autoCompactThreshold: 0.5    ✓
  PreCompact hook: sync-agent.sh  ✓
  SessionEnd hook: sync-agent.sh  ✓

──────────────────────────────────────
Ready to generate? (yes / adjust)
```

Type **yes**. Claude writes all files, commits, and starts Ralph immediately — no separate command needed.

---

## Execution (Ralph)

Ralph starts automatically when you confirm the plan. If you need to resume after a stop, you have two options:

**From Claude Code** (after a usage-limit pause or session restart):
```
/vibe_resume
```
The `/vibe_resume` skill checks whether Ralph is still running, reads current state, and either reconnects to a live Ralph process or restarts it — without replanning.

**From the terminal** (after `TASK_BLOCKED` or manual interrupt):
```bash
bash scripts/ralph.sh --max 50
```

Ralph reads `state/sync.json` for the current task, runs Claude to execute it, verifies the build, commits, and loops until all tasks are done or it needs to stop.

**Options:**
```
--tool claude|amp    # default: claude
--model MODEL        # default: claude-sonnet-4-6
--max N              # max iterations before stopping (default: 50)
--task T###          # resume from a specific task (e.g. after TASK_BLOCKED)
--skip-qc            # skip the post-completion QC loop
--dry-run            # show preflight summary and exit without executing
```

**What Ralph does each iteration:**
1. Checks rate limit before starting (waits with live countdown if needed)
2. Saves `HEAD` SHA for rollback
3. Runs `claude --dangerously-skip-permissions --print` with the task prompt
4. Detects sentinel in output (`TASK_COMPLETE`, `TASK_BLOCKED`, or `SESSION_HANDOFF`)
5. On `TASK_COMPLETE`: runs `verify_build()` from your config
   - Pass: safety commit if needed, marks task `[x]` in tasks.md, clears task from sync.json
   - Fail: `git reset --hard` to pre-iteration SHA, retries (3-strike limit)
6. On stall (no sentinel): rollback and retry (3-strike limit, tracked separately from build failures)
7. On `TASK_BLOCKED`: stops with a structured reason for human review
8. When all tasks complete: enters QC loop — runs Claude against `brief.md` to find gaps, appends new tasks if found, repeats until `[QC_COMPLETE]` (use `--skip-qc` to bypass)

**Rate limits:** Ralph checks OAuth usage before each iteration and detects rate limit messages in output. On limit, it calculates the exact reset time and shows a live countdown. Rate limits do not count against the stall counter.

---

## Multi-brief projects

Large projects decompose into sequential briefs — one per major phase or feature area. The knowledge graph accumulates across all of them automatically.

```
briefs/
  README.md            # execution sequence + dependency graph
  P00A-foundation.md   # phase 1 brief
  P00B-auth.md         # phase 2 brief
  P01-schema.md        # phase 3 brief
  ...
```

Run one brief at a time:
```
/vibeplan briefs/P00A-foundation.md  →  Ralph runs  →  QC_COMPLETE
/vibeplan briefs/P00B-auth.md        →  Ralph runs  →  QC_COMPLETE
...
```

After each `QC_COMPLETE`, Claude reads `briefs/README.md` and gives you the exact command to start the next phase. The master `brief.md` at the root stays as the unchanging project vision — sub-brief scope adjustments go into the individual brief files.

By brief 5, `/vibeplan` asks fewer questions and Ralph stalls less — the knowledge graph compounds.

---

## Monitoring

```bash
# Live log
tail -f state/ralph.log

# Task completions
git log --oneline --grep="\[ralph\]"

# Knowledge graph updates
git log --oneline --grep="\[claude-docs\]"

# Current task status
cat state/sync.json
```

---

## Wiring statusline into Claude Code

`scripts/statusline.sh` reads `state/sync.json` and `state/ralph.log` and emits a one-line ralph progress indicator. Wire it into Claude Code's custom statusline via `~/.claude/settings.json`:

**Replace ccstatusline:**
```json
{
  "statusLine": {
    "command": "bash /path/to/vibekit/scripts/statusline.sh"
  }
}
```

**Wrap ccstatusline** (keep your existing statusline and append ralph status):
```bash
#!/usr/bin/env bash
# ~/.local/bin/my-statusline.sh
VIBEKIT="$(bash /path/to/vibekit/scripts/statusline.sh)"
CCSTATUS="$(ccstatusline)"
if [[ -n "$VIBEKIT" && -n "$CCSTATUS" ]]; then
  printf '%s · %s\n' "$CCSTATUS" "$VIBEKIT"
elif [[ -n "$VIBEKIT" ]]; then
  printf '%s\n' "$VIBEKIT"
else
  printf '%s\n' "$CCSTATUS"
fi
```
Then set `statusLine.command` to `bash ~/.local/bin/my-statusline.sh`.

The script exits silently (empty stdout) when run outside a vibekit project, so wrapping is always safe.

---

## Notifications

For desktop popup notifications, install libnotify-bin (Debian/Ubuntu: `sudo apt install libnotify-bin`). Without it, ralph still emits a terminal bell on exit and writes structured events to `state/ralph.status` for the statusline to display.

---

## Reboot Survival

Long-running specs may need to survive host reboots. Vibekit ships a systemd --user unit installer:

```
bash scripts/install-service.sh
```

Then follow the printed instructions to enable linger and start the service. After that, ralph will auto-resume from `state/sync.json` on every boot. `Restart=no` means stalls and failures still require human review — this is reboot survival, not auto-recovery from real failures.

---

## Project Structure After `init.sh`

```
my-project/
  CLAUDE.md                  # Router — always loaded, points to docs/claude/
  vibekit.config.sh          # Tool/model/paths + verify_build()

  scripts/
    ralph.sh                 # Autonomous execution loop
    sync-helpers.sh          # sync_read / sync_write / session_log_append
    monitor.sh               # Sentinel detection from Claude output
    ralph-prompt.md          # Prompt template Ralph feeds to Claude each iteration
    qc-prompt.md             # Prompt template for post-completion QC review agent
    sync-agent.sh            # PreCompact/SessionEnd hook — runs knowledge-graph-sync

  state/
    sync.json                # Current task, last sentinel, session counter
    session-log.json         # Per-session execution history
    decisions.md             # Ralph's inter-task pattern/decision log
    ralph.log                # Append-only run log (created on first run)

  docs/claude/               # Knowledge graph domain files
    decisions.md             # Append-only audit log (architectural decisions with anchors)
    architecture.md
    conventions.md
    stack.md

  specs/
    NNN-slug/
      spec.md                # Full context, decisions, constraints
      tasks.md               # Checkbox task list Ralph executes

  skills/                    # Optional: domain knowledge packages
    <name>/
      manifest.md            # Injected into ralph-prompt via {{SKILLS_CONTEXT}}
      verify.sh              # Optional per-skill post-completion check

  .claude/
    skills/
      vibeplan/SKILL.md      # /vibeplan slash command
      knowledge-graph-sync/SKILL.md  # Background sync (invoked by hooks only)
      vibe_resume/SKILL.md   # /vibe_resume — recover from usage-limit pauses without replanning
    settings.json            # autoCompactThreshold: 0.5 + hook config
```

---

## `vibekit.config.sh` Reference

```bash
TOOL="claude"                # claude | amp
MODEL="claude-sonnet-4-6"    # any Claude model
SYNC_FILE="$PROJECT_ROOT/state/sync.json"
SESSION_LOG_FILE="$PROJECT_ROOT/state/session-log.json"
RALPH_PROMPT="$PROJECT_ROOT/scripts/ralph-prompt.md"
DECISIONS_FILE="$PROJECT_ROOT/state/decisions.md"
LOG_FILE="$PROJECT_ROOT/state/ralph.log"
SPEC_TASKS_FILE="$PROJECT_ROOT/specs/001-slug/tasks.md"  # auto-updated by /vibeplan
BRIEF_FILE="$PROJECT_ROOT/brief.md"                      # auto-updated for multi-brief projects
SKILLS=()                    # e.g. ("typescript" "react") — maps to skills/<name>/manifest.md

verify_build() {
  # Run after each task completion. Return 0 = pass, non-zero = fail + rollback.
  return 0
}
```

---

## Domain Skills (Optional)

Domain skills inject project-specific knowledge into every Ralph iteration. Create `skills/<name>/manifest.md` with whatever context Ralph should always have for that domain (patterns, conventions, API shapes), then register it:

```bash
# vibekit.config.sh
SKILLS=("typescript" "prisma")
```

Ralph loads all registered skill manifests and injects them at the bottom of its prompt via `{{SKILLS_CONTEXT}}`.

Optionally add `skills/<name>/verify.sh` for per-skill post-completion verification (runs after `verify_build()`).

---

## When Ralph Stops

| Reason | What happened | What to do |
|--------|---------------|------------|
| `TASK_BLOCKED` | Task has an unresolvable dependency or ambiguity | Read the reason in `state/ralph.log`, fix the task or unblock the dependency, then: `bash scripts/ralph.sh --task T### --max 50` |
| Stalled 3x | Claude didn't complete the task 3 times in a row | Task may be too large or missing context — split it in tasks.md or add a `Relevant:` line |
| Build failed 3x | Task completed but `verify_build()` failed 3 times | Fix the verify command or the task description, run ralph again |
| Max iterations | Reached `--max` limit | Run ralph again to continue |
| QC round cap (5x) | QC loop identified gaps 5 times without resolving them | Review `brief.md` and the QC-added tasks — the brief may be under-specified or tasks may be too vague |

---

## Workflow Summary

```
1. Write brief.md in your project directory (~1 page)
2. Open Claude Code in the project directory
3. /vibeplan brief.md  →  answer 3 rounds  →  yes  →  Ralph starts automatically
4. Watch progress / tail state/ralph.log
5. After a usage-limit pause or session restart: /vibe_resume
6. On TASK_BLOCKED: read the reason, fix the task, then resume:
   bash scripts/ralph.sh --task T### --max 50
```

### Optional: build verification

By default, Ralph marks tasks complete without running any external check. To add a post-task gate, edit `vibekit.config.sh`:

```bash
verify_build() {
  npm test    # return 0 = pass, non-zero = rollback and retry
}
```

After the first spec, start the next one with `/vibeplan brief2.md` (or `/vibeplan briefs/next.md` for multi-brief projects). The knowledge graph from prior specs loads automatically, so `/vibeplan` asks fewer questions and Ralph stalls less. The system compounds.
