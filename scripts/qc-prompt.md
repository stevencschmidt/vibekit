# QC Review Prompt

You are running a QC review after all planned tasks have been completed. Your job is to compare what was built against the project brief and identify any gaps, missing behaviors, or inconsistencies.

---

## Step 1 — Read the Brief

Read the project brief. Check for `brief.md` at the project root first. If it does not exist, check `vibekit.config.sh` for a `BRIEF_FILE` variable, then fall back to `knowledge-graph-brief.md`. Read whatever file you find completely.

---

## Step 2 — Survey What Was Built

Run these commands to understand the current state:

```bash
git log --oneline --grep="\[ralph\]"
```

Then read the relevant source files and project structure. Focus on the user-visible behaviors, outputs, and interfaces described in `brief.md`. You are not checking code quality — you are checking completeness against the brief.

---

## Step 3 — Identify Gaps

For each requirement or success criterion in `brief.md`, determine whether it is:

- **Satisfied** — the implementation clearly fulfills it
- **Missing** — no implementation exists for it
- **Partial** — some implementation exists but it is incomplete

List all missing and partial items.

---

## Step 3a — Brief Drift Check (completion QC only)

If `brief-archive.md` exists in the project root, read it after `brief.md`. Compare the two
for contradictions — for example, a hard constraint listed in `brief-archive.md` that has
been silently dropped from `brief.md` without a documented decision in `state/decisions.md`.

If contradictions are found: treat them as gaps. Proceed to Step 4's "If gaps are found"
path and append a task titled `## T### · Reconcile brief drift: <symptom>` to `tasks.md`
(and update `state/sync.json`). Do not emit `[QC_COMPLETE]`.

If no contradictions are found, or if `brief-archive.md` does not exist, proceed normally
to Step 4.

---

## Step 4 — Decision

**If no gaps are found:**

Emit exactly this on its own line and stop:

```
[QC_COMPLETE]
```

Do not write any files. Do not commit. Exit cleanly.

---

**If gaps are found:**

1. **Read `state/sync.json`** to find the `SPEC_TASKS_FILE` path — or read `vibekit.config.sh` to get it. This is the `tasks.md` for the current spec.

2. **Read `tasks.md`** and find the highest T-number currently in the file (e.g. if the last task is T007, start new tasks at T008). Completed task descriptions live in `tasks-archive.md` if you need historical context. The active checkbox list and unfinished task bodies remain in `tasks.md`.

3. **Append new tasks** to `tasks.md`:

   First, add unchecked entries to the checkbox list at the top:
   ```
   - [ ] T008 · <short title>
   ```

   Then add full task sections at the bottom:
   ```markdown
   ## T008 · <short title>
   Depends on: —
   Verify: `<deterministic command>` exits 0
   Relevant: docs/claude/<relevant-domain-file>.md

   <Description precise enough for Ralph to execute without asking questions.
   Reference specific files, patterns, or conventions. One task = one session.>
   ```

   Rules for good tasks:
   - Each task has a single verifiable output
   - `Verify:` is a deterministic command (not "check that it looks right")
   - No implicit dependencies on uncommitted work
   - Description includes enough context that Ralph never needs to ask a question

4. **Update `state/sync.json`**: write the first new task ID into `ralph.task_id`, the task title into `ralph.task_title`, and the files from its `Relevant:` line into `ralph.relevant_files`.

5. **Commit** the updated `tasks.md` and `state/sync.json`:
   ```
   [ralph] QC round N — N gap(s) found, T### tasks added
   ```
   Replace N with the actual QC round number and task count.

6. **Do not emit `[QC_COMPLETE]`.** Ralph will detect the new `task_id` in `sync.json` and resume execution.

---

## What NOT to Do

- Do not re-implement completed tasks
- Do not flag code style issues — only check functional completeness against the brief
- Do not create tasks for speculative improvements not mentioned in the brief
- Do not emit `[QC_COMPLETE]` if any gap remains
- Do not modify `state/decisions.md` or `docs/claude/` files
