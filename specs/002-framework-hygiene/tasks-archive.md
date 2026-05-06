# Archive: 002-framework-hygiene

## T015 · Tighten qc-prompt.md against hedging
Depends on: —
Verify: `grep -q "Decision Check" scripts/qc-prompt.md && grep -q "protocol violation" scripts/qc-prompt.md`
Relevant: docs/claude/conventions.md, scripts/qc-prompt.md

**Problem:** During spec-001's post-T012 QC pass, the QC agent found two real gaps (a missing bootstrap skill and stale routing-table text) but produced prose-only output — neither emitted `[QC_COMPLETE]` nor created tasks. Ralph treated this as a stall. The qc-prompt.md has both paths clearly documented (lines 54–104) but no explicit prohibition on hedging. The agent's natural response to ambiguity is to describe rather than decide.

**What to do:**

Edit `scripts/qc-prompt.md`. After the existing **Step 4 — Decision** block (the one that ends around line 104 with "Do not emit `[QC_COMPLETE]`. Ralph will detect the new `task_id` in `sync.json` and resume execution."), insert a new section:

```markdown
---

## Step 4.5 — Decision Check (mandatory)

Before exiting, you must have either:

- **(a)** emitted `[QC_COMPLETE]` on its own line, OR
- **(b)** committed new tasks to `tasks.md` and updated `state/sync.json` with the first new task ID

**Prose-only output is a protocol violation.** If you describe gaps but neither create tasks nor emit `[QC_COMPLETE]`, Ralph will treat this as a stall and exit — the gaps will be lost.

If you cannot confidently decide whether something is a gap:

- Treat it as a gap and create a task. The user will dismiss it if wrong — that is far cheaper than losing it.
- Mark uncertainty in the task description (e.g. "Possibly out of scope — confirm with user").

Do not exit without committing to one of (a) or (b).
```

Commit with `[ralph] T015 complete — tighten QC prompt against hedging`.

---

## T016 · Inline CLAUDE.md content into bootstrap skill
Depends on: T015
Verify: `! grep -q "templates/CLAUDE.md" templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md`
Relevant: templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md, templates/CLAUDE.md

**Problem:** `templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md` references `templates/CLAUDE.md` in two places (lines 51 and 65 — Phase 3 file-set preview and Phase 4 step 1). When the skill is invoked in a scaffolded project, that path doesn't exist — `templates/` only lives in the vibekit repo. Invoking the skill currently fails at Phase 4 step 1.

**What to do:**

In `templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md`:

1. **Phase 3 preview block** (currently `"CLAUDE.md will be initialized from templates/CLAUDE.md."`): replace with `"CLAUDE.md will be initialized from the inline template in Phase 4 step 1."`.

2. **Phase 4 step 1** (currently `"copy from templates/CLAUDE.md, replacing PROJECT_NAME..."`): replace with the full content of `templates/CLAUDE.md` (38 lines) embedded in a fenced code block, with `<-- placeholders -->` for `PROJECT_NAME` and the description line. The skill should instruct Claude to write this content directly to `CLAUDE.md` at the project root, substituting:
   - `PROJECT_NAME` → the project name
   - `> One-line description of what this project does.` → the actual one-liner from the brief
   - `Total decisions: 000` → `Total decisions: 001` (since bootstrap creates one decision)

Read `templates/CLAUDE.md` first to get the exact content to inline. Do not paraphrase — preserve every line including blank lines, headers, and the existing PROJECT_NAME placeholder syntax.

After this change, the skill is fully self-contained — it has no external file dependencies on `templates/`.

Commit with `[ralph] T016 complete — inline CLAUDE.md content into bootstrap skill`.

---

## T017 · Make bootstrap skill user-discoverable
Depends on: T016
Verify: `grep -q "^trigger: /knowledge-graph-bootstrap" templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md`
Relevant: templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md

**Problem:** The bootstrap skill's frontmatter has `trigger: internal`, which means it can't be invoked as a slash command. The brief (Pillar 1c, knowledge-graph-brief.md) states the skill is "Invoked by: 'initialize project from brief'" — implying user-facing invocation. The intent is for the user to run it explicitly at project start, after writing `brief.md`.

**What to do:**

In `templates/.claude/skills/knowledge-graph-bootstrap/SKILL.md`, edit the frontmatter:

1. Change `trigger: internal` → `trigger: /knowledge-graph-bootstrap` (matches `/plan`'s convention of slash-command name = skill name).
2. Update the `description:` line to mention the slash-command invocation explicitly: `Initialize a new project's knowledge graph from a brief. Run once at project start with /knowledge-graph-bootstrap <path-to-brief.md>.`

Do not change anything below the frontmatter `---`.

Commit with `[ralph] T017 complete — make bootstrap skill user-discoverable`.

---

## T018 · Document bootstrap workflow in README and templates/CLAUDE.md
Depends on: T017
Verify: `grep -q "knowledge-graph-bootstrap" README.md && grep -q "knowledge-graph-bootstrap" templates/CLAUDE.md`
Relevant: README.md, templates/CLAUDE.md

**Problem:** A new vibekit user has no way to learn the correct sequence: `init.sh` → write `brief.md` → `/knowledge-graph-bootstrap` → `/plan` → `bash scripts/ralph.sh`. The current README jumps from Setup straight to `/plan`, skipping the bootstrap step entirely. Scaffolded projects' `templates/CLAUDE.md` also doesn't reference bootstrap.

**What to do:**

1. **`README.md`** — insert a new `## Bootstrap` section between the existing `## Setup` and `## Planning & Building (`/plan`)` sections. Content:

   ```markdown
   ## Bootstrap

   After `init.sh` scaffolds a project, you write a brief (`brief.md` at project root, ~1 page describing what the project should do) and invoke the bootstrap skill once:

   ```
   /knowledge-graph-bootstrap brief.md
   ```

   Bootstrap reads the brief, has a 3–5 exchange clarifying conversation, and generates the initial knowledge graph: `CLAUDE.md` router + the warranted domain files under `docs/claude/` + `manifest.json` + a bootstrap entry in `decisions.md`. Bootstrap commits with `[claude-docs] bootstrap — initial knowledge graph from brief`.

   Bootstrap is the highest-stakes invocation in the framework — assumptions made here propagate through every subsequent spec. Run with `/model opus` enabled.

   **Workflow summary:**
   ```
   init.sh → write brief.md → /knowledge-graph-bootstrap → /plan → bash scripts/ralph.sh
   ```
   ```

2. **`templates/CLAUDE.md`** — under the existing `## Quick Facts` section, append one line:
   ```
   - **Bootstrap:** `/knowledge-graph-bootstrap <brief>` (run once at project start)
   ```

Commit with `[ralph] T018 complete — document bootstrap workflow`.

---

## T019 · Refactor state-file commits in ralph.sh into a helper
Depends on: T018
Verify: `bash -n scripts/ralph.sh && [ "$(grep -c 'commit_state_files' scripts/ralph.sh)" -ge 4 ]`
Relevant: docs/claude/conventions.md, scripts/ralph.sh

**Problem:** T011 added 3 near-identical 2-line blocks at the QC_COMPLETE, stall-exit, and max-iter exit paths in `scripts/ralph.sh`. Each is `git add state/sync.json state/session-log.json … || git commit -m "[claude-docs] state files post-<reason>"`. Future exit paths added to ralph.sh would have to remember this pattern. A helper centralizes it.

**What to do:**

In `scripts/ralph.sh`:

1. Add a helper function near the top of the file (after the SCRIPT_DIR/PROJECT_ROOT setup, before the main loop):

   ```bash
   commit_state_files() {
     local reason="$1"
     git -C "$PROJECT_ROOT" add state/sync.json state/session-log.json 2>/dev/null || true
     git -C "$PROJECT_ROOT" diff --cached --quiet || \
       git -C "$PROJECT_ROOT" commit -m "[claude-docs] state files post-${reason}"
   }
   ```

2. Replace the 3 existing call sites (around lines 569, 969, 987) with helper calls:
   - Post-QC_COMPLETE → `commit_state_files "QC_COMPLETE"`
   - Post-stall-exit → `commit_state_files "stall-exit"`
   - Post-max-iter → `commit_state_files "max-iter"`

3. Leave the preceding `session_log_append` call in place at each site — only the 2-line git block is being replaced.

The verify command grep-counts ≥ 4 occurrences of `commit_state_files` (1 definition + 3 callsites).

Commit with `[ralph] T019 complete — refactor state-file commits into helper`.

---

