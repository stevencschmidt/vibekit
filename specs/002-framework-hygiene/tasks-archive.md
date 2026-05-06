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

