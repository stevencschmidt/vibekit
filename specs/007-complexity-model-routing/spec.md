# Spec: 007-complexity-model-routing

## Summary

Make Ralph run each task on a model chosen by a plan-time **complexity tier**
instead of a single static `$MODEL`, escalate one tier on build-failure retry,
and always run both QC stages on the strongest model. Goal is cost/quota
efficiency (cheap tasks on a cheap model, expensive model reserved for hard
ones) without changing per-task token counts. See
`docs/briefs/007-complexity-model-routing.md`.

## Success criteria

- A task tagged `simple` runs on Haiku, `medium` on Sonnet, `complex` on Opus;
  an untagged task runs on Sonnet — observable in `state/ralph.log` model lines.
- A `simple` task that fails `verify_build()` retries on `medium`, then
  `complex` (complex stays complex).
- Both QC stages (final + checkpoint) run on `MODEL_QC` regardless of the
  per-task models used.
- With `MODEL_AUTO="false"` (or `--model` passed on the CLI), execution behavior
  matches today exactly: every task uses `$MODEL`.

## Hard constraints

- bash + python3 only; no new dependencies.
- Tasks carry the tier **name** (`simple|medium|complex`), not a model id, so a
  whole tier re-points in one `vibekit.config.sh` line.
- `--model <m>` forces the per-task execution model for the whole run (disables
  routing) but never overrides QC; QC always uses `MODEL_QC`.
- Tier resolution reuses the existing per-task metadata path: the tier travels
  in each `## T###` body as a `Tier:` line (alongside `Relevant:`) and is written
  to `state/sync.json` as `ralph.tier` by the same next-task parser that already
  writes `task_title`/`relevant_files`.

## Out of scope

- A runtime LLM classifier for complexity (plan-time tags suffice; avoids extra
  round-trips and rate-limit exposure).
- Per-task model overrides from the CLI (only whole-run `--model`).
- Changing token counts or context loading per task.

## Technical approach

- **Config** (`vibekit.config.sh` + `templates/vibekit.config.sh`): add
  `MODEL_AUTO`, `MODEL_SIMPLE`, `MODEL_MEDIUM`, `MODEL_COMPLEX`, `MODEL_QC`.
- **Pure helpers** (`scripts/sync-helpers.sh`): `tier_to_model <tier>` (reads the
  `MODEL_*` env vars; unknown/empty → medium) and `escalate_tier <tier>`
  (simple→medium→complex→complex). Sourceable, unit-testable.
- **`scripts/ralph.sh`**: extend the next-task parser to extract `Tier:` and
  write `ralph.tier`; read it per iteration; resolve `_ITER_MODEL` via
  `tier_to_model` when `MODEL_AUTO` is true and `--model` was not forced; use
  `_ITER_MODEL` in the main execution call and log it; pin both QC calls to
  `MODEL_QC`; escalate the effective tier one step on each build-failure retry.
- **`templates/.claude/skills/vibeplan/SKILL.md`**: emit a `Tier:` line per task
  and write `ralph.tier` into `sync.json`.
- **`scripts/qc-prompt.md`**: tag QC-appended tasks with a tier (default medium).
- **Docs**: `CLAUDE.md` (schema + routing), `docs/claude/architecture.md`,
  `docs/claude/conventions.md`, `docs/claude/manifest.json`.

## Dependencies

Self-contained within vibekit. Modifies the running orchestrator (`ralph.sh`) —
dogfooded per `vibekit.config.sh` policy. `verify_build()` (`bash -n` on scripts
+ JSON validity) guards each commit; failed tasks roll back via `git reset
--hard` and are resumable from `state/sync.json`.
