# Tasks: 007-complexity-model-routing

- [x] T001 · Add model-routing config knobs (vibekit.config.sh + template)
- [x] T002 · Add tier_to_model() + escalate_tier() helpers to sync-helpers.sh
- [x] T003 · ralph.sh: parse Tier → sync.json, resolve per-task execution model
- [x] T004 · ralph.sh: pin both QC stages to MODEL_QC
- [x] T005 · ralph.sh: escalate one tier on build-failure retry
- [x] T006 · vibeplan SKILL.md: emit Tier per task + write ralph.tier
- [x] T007 · qc-prompt.md: tag QC-appended tasks with a tier
- [x] T008 · Docs: CLAUDE.md schema/router + architecture/conventions/manifest

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
