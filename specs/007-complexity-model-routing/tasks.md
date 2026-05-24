# Tasks: 007-complexity-model-routing

- [x] T001 · Add model-routing config knobs (vibekit.config.sh + template)
- [x] T002 · Add tier_to_model() + escalate_tier() helpers to sync-helpers.sh
- [x] T003 · ralph.sh: parse Tier → sync.json, resolve per-task execution model
- [ ] T004 · ralph.sh: pin both QC stages to MODEL_QC
- [ ] T005 · ralph.sh: escalate one tier on build-failure retry
- [ ] T006 · vibeplan SKILL.md: emit Tier per task + write ralph.tier
- [ ] T007 · qc-prompt.md: tag QC-appended tasks with a tier
- [ ] T008 · Docs: CLAUDE.md schema/router + architecture/conventions/manifest

---

## T003 · ralph.sh: parse Tier → sync.json, resolve per-task execution model
Depends on: T002
Verify: `bash -n scripts/ralph.sh && grep -q 'ralph.tier' scripts/ralph.sh && grep -q 'tier_to_model' scripts/ralph.sh && grep -q '_ITER_MODEL' scripts/ralph.sh` exits 0
Relevant: docs/claude/architecture.md, docs/claude/conventions.md
Tier: complex

Wire per-task model resolution into `scripts/ralph.sh`. Four edits:

1. **CLI override flag** — where `--model` is parsed (the `--model)` / `--model=*`
   cases near the top), set `MODEL_OVERRIDE=1`. Initialize `MODEL_OVERRIDE=0`
   alongside the other CLI defaults.

2. **Extract Tier in the next-task parser** — the Python block that finds the
   next unchecked task (search for the section body regex `^## ' + re.escape(...)`
   that currently prints task_id / title / relevant_files). Also parse a
   `Tier:` line from the task body and print it as a 4th output line. In the
   bash that reads `_next_result` (the `sed -n '1p'..'3p'` block), read line 4 as
   `_next_tier` (default `medium` if empty) and `sync_write "ralph.tier"
   "$_next_tier"` alongside the existing task_id/title/relevant_files writes.

3. **Read tier per iteration** — where `TASK_TITLE=$(sync_read "ralph.task_title")`
   is read at the top of the loop, also read
   `TASK_TIER=$(sync_read "ralph.tier" 2>/dev/null || echo "medium")`; treat
   empty/null as `medium`.

4. **Resolve _ITER_MODEL and use it** — before the main task `claude` call (the
   `claude --dangerously-skip-permissions --print --model "$MODEL"` for task
   execution, NOT the QC calls), compute:
   ```bash
   if [[ "${MODEL_AUTO:-true}" == "true" && "${MODEL_OVERRIDE:-0}" -eq 0 ]]; then
     _ITER_MODEL=$(tier_to_model "$TASK_TIER")
   else
     _ITER_MODEL="$MODEL"
   fi
   ```
   Pass `--model "$_ITER_MODEL"` in that task call. Add `model=$_ITER_MODEL` to
   the existing `TASK_START` log line so the chosen model is observable.

Do NOT change the QC `claude` calls in this task (that is T004). Do not change
escalation yet (that is T005).

[TASK_COMPLETE: T003] when ralph.sh resolves and uses _ITER_MODEL for task
execution, writes ralph.tier, and passes Verify.

---

## T004 · ralph.sh: pin both QC stages to MODEL_QC
Depends on: T001
Verify: `bash -n scripts/ralph.sh && [ "$(grep -c 'MODEL_QC' scripts/ralph.sh)" -ge 2 ]` exits 0
Relevant: docs/claude/architecture.md
Tier: medium

In `scripts/ralph.sh`, the two QC `claude` invocations — the final/completion QC
call and the checkpoint QC call (both currently `claude
--dangerously-skip-permissions --print --model "$MODEL" "$_QC_RUN_PROMPT"` /
checkpoint equivalent) — must use `--model "${MODEL_QC:-$MODEL}"` instead of
`--model "$MODEL"`. This is independent of `MODEL_AUTO` and the `--model` CLI
override, so QC always runs on the strong model. Change only the QC calls; leave
the task-execution call (from T003) alone.

[TASK_COMPLETE: T004] when both QC calls use MODEL_QC and Verify passes.

---

## T005 · ralph.sh: escalate one tier on build-failure retry
Depends on: T003
Verify: `bash -n scripts/ralph.sh && grep -q 'escalate_tier' scripts/ralph.sh` exits 0
Relevant: docs/claude/architecture.md, docs/claude/conventions.md
Tier: complex

Add tier escalation on build-failure retry in `scripts/ralph.sh`. The existing
flow: on TASK_COMPLETE, `verify_build()` runs; on failure it `git reset --hard`s,
increments the per-task build-failure counter, and retries the SAME task.

- Maintain an effective tier per task: when the loop starts a task (task_id
  differs from the previously seen one), set `_EFFECTIVE_TIER="$TASK_TIER"`.
- On a build-failure retry (the path that rolls back and loops to retry the same
  task), set `_EFFECTIVE_TIER=$(escalate_tier "$_EFFECTIVE_TIER")` and log it
  (e.g. `escalated $TASK_ID to tier=$_EFFECTIVE_TIER`).
- Change the `_ITER_MODEL` resolution from T003 to use `$_EFFECTIVE_TIER`
  instead of `$TASK_TIER` (still gated on `MODEL_AUTO` true and no `--model`
  override).

Reset is automatic via the task-changed check. `complex` escalates to `complex`
(no-op), so a complex task that keeps failing still hits the existing 3-strike
build-failure limit unchanged.

[TASK_COMPLETE: T005] when escalation adjusts the model on retry and Verify
passes.

---

## T006 · vibeplan SKILL.md: emit Tier per task + write ralph.tier
Depends on: T001
Verify: `grep -q 'Tier:' templates/.claude/skills/vibeplan/SKILL.md && grep -q 'ralph.tier' templates/.claude/skills/vibeplan/SKILL.md` exits 0
Relevant: docs/claude/conventions.md, docs/claude/architecture.md
Tier: medium

Update `templates/.claude/skills/vibeplan/SKILL.md` so generated plans carry tier
tags:

1. In the `tasks.md` task-body template (Step 4, "Write spec files" — the
   `## T001 · Title` block showing `Depends on:` / `Verify:` / `Relevant:`), add
   a `Tier: simple | medium | complex` line after `Relevant:`.
2. Add a short rule near that template: assign each task a tier — `simple` =
   mechanical/single-file/config; `medium` = standard multi-file feature work;
   `complex` = core-logic, cross-cutting, or architectural change. Note the tier
   maps to a model via `MODEL_SIMPLE/MEDIUM/COMPLEX` in `vibekit.config.sh`
   (Haiku/Sonnet/Opus by default) and that an untagged task falls back to medium.
3. In Step 5 ("Populate state/sync.json"), also write `ralph.tier` from T001's
   `Tier:` line (default `"medium"` if absent), alongside task_id/title/
   relevant_files.

[TASK_COMPLETE: T006] when the SKILL emits Tier lines and writes ralph.tier, and
Verify passes.

---

## T007 · qc-prompt.md: tag QC-appended tasks with a tier
Depends on: T006
Verify: `grep -qi 'tier' scripts/qc-prompt.md` exits 0
Relevant: docs/claude/conventions.md, docs/claude/architecture.md
Tier: simple

In `scripts/qc-prompt.md`, where the QC agent is instructed to append new
`## T###` task bodies to `tasks.md` and update `state/sync.json`, add an
instruction to include a `Tier:` line on each appended task (same convention as
`/vibeplan`: simple/medium/complex; default `medium` when unsure) and to write
`ralph.tier` when it sets the next `ralph.task_id`. The QC agent runs on
`MODEL_QC` (Opus), so it can judge tier as well as `/vibeplan`.

[TASK_COMPLETE: T007] when qc-prompt.md instructs tier tagging on appended tasks
and Verify passes.

---

## T008 · Docs: CLAUDE.md schema/router + architecture/conventions/manifest
Depends on: T007
Verify: `grep -q '"tier"' CLAUDE.md && grep -qi 'tier' docs/claude/architecture.md && grep -qi 'routing' docs/claude/conventions.md && python3 -c "import json; json.load(open('docs/claude/manifest.json'))"` exits 0
Relevant: docs/claude/architecture.md, docs/claude/conventions.md
Tier: simple

Document the now-built feature (do not document anything not yet implemented):

1. `CLAUDE.md` — add `"tier": "medium"` to the `state/sync.json Schema` block;
   in the `vibekit.config.sh` example block add the five `MODEL_*` routing knobs;
   in `### scripts/ralph.sh` per-iteration list, note step 4 resolves the model
   from the task's tier (with QC pinned to `MODEL_QC`); add a Quick Fact line for
   `MODEL_AUTO`; bump the `Decision Log` count to `Total decisions: 009`.
2. `docs/claude/architecture.md` — in the `scripts/ralph.sh` per-iteration flow,
   note model resolution from tier + build-failure escalation; note both QC
   stages run on `MODEL_QC`.
3. `docs/claude/conventions.md` — add a short "Model Routing / Tier convention"
   section (tier names, tier→model mapping, untagged→medium, `--model` and
   `MODEL_AUTO` precedence, QC always `MODEL_QC`).
4. `docs/claude/manifest.json` — refresh the architecture.md and conventions.md
   summaries/tags to mention model routing (add tags like `model-routing`,
   `tier`). Keep it valid JSON.
5. Confirm `scripts/push-to-phramewerks.sh` already covers every file changed in
   this spec (all are pre-existing infra files); if any changed file is missing
   from the push list, add it.

[TASK_COMPLETE: T008] when docs reflect the shipped routing feature and Verify
passes.
