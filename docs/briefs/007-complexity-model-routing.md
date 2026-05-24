# Brief: Complexity-Based Model Routing for Ralph

## Problem

Ralph currently runs every task — and both QC stages — on a single model
(`$MODEL`, default `claude-sonnet-4-6`), resolved once at startup from
`vibekit.config.sh` or the `--model` flag and reused for every `claude --model`
call in `scripts/ralph.sh`. This wastes quota: trivial tasks (typos, renames,
config bumps) burn the same per-token cost as genuinely hard architectural work,
and there's no way to reserve a stronger model for the tasks that need it.

The goal is **cost/quota efficiency, not raw token reduction**. Token *count*
per task is roughly model-independent (same prompt, same context); the win is
running cheap tasks on a cheap model and reserving the expensive model for hard
ones, stretching how many tasks complete per usage window on a Pro/Max plan.

## Goals

1. Let `/vibeplan` (run on Opus, which judges complexity better than a heuristic)
   tag each task with a complexity tier at plan time.
2. Have Ralph resolve that tier to a concrete model per iteration.
3. Self-correct when a task is mis-tagged as too easy.
4. Always run both QC stages on the strongest model.

## Design (locked)

### Tier → model mapping (3 tiers)

A lookup table in `vibekit.config.sh` maps tier names to model IDs:

| Tier      | Model                          |
|-----------|--------------------------------|
| `simple`  | `claude-haiku-4-5-20251001`    |
| `medium`  | `claude-sonnet-4-6`            |
| `complex` | `claude-opus-4-7`              |

Tasks carry the tier *name* (not the model ID) so a whole tier can be
re-pointed in one config line. `/vibeplan` writes the tier per task into
`tasks.md` and into `state/sync.json` alongside the existing per-task fields
(`task_id`, `task_title`, `relevant_files`).

### Per-task resolution in ralph.sh

Each iteration, after reading `ralph.task_id`, read the task's tier, map it to a
model (`_ITER_MODEL`), and use that in the main execution call
(`ralph.sh:701`). If no tier is present or it's unparseable, fall back to
`medium` (the current default).

### Failure escalation (safety net)

The planner judges complexity *before* hitting real code friction, so a task
tagged `simple` can turn out hard. On a `verify_build()` failure / rollback
retry, escalate one tier up: `simple → medium → complex`. `complex` stays at
`complex`. This reuses Ralph's existing build-failure counter and rollback path.
Escalation protects against the one failure mode that would otherwise eat the
savings (a weak model thrashing on a hard task, burning full tokens per failed
attempt before rollback).

### QC always on Opus

Both QC stages — final QC (`ralph.sh:575`) and checkpoint QC (`ralph.sh:920`) —
always run on a dedicated `MODEL_QC` config knob (default `claude-opus-4-7`),
independent of `MODEL_AUTO` and the per-task routing. QC is pure review, where
strong judgment matters most and frequency is low.

### Precedence

- `--model <m>` CLI flag forces the per-task execution model for the whole run
  (disables tier routing). It does **not** override QC; QC always uses
  `MODEL_QC`. (A separate `--qc-model` flag can be added later if needed.)
- A `MODEL_AUTO` toggle in config enables/disables tier routing; when off,
  behavior is identical to today (single `$MODEL`).

### QC-appended tasks

The QC agent (`scripts/qc-prompt.md`) already appends new tasks mid-run and runs
on Opus, so it tags each appended task with a tier the same way `/vibeplan`
does. Anything missing/unparseable defaults to `medium`; escalation catches the
genuinely hard ones.

## Affected files

- `scripts/ralph.sh` — per-task tier→model resolution; escalation on retry; QC
  calls pinned to `MODEL_QC`; `--model` precedence.
- `vibekit.config.sh` + `templates/vibekit.config.sh` — `MODEL_SIMPLE`,
  `MODEL_MEDIUM`, `MODEL_COMPLEX`, `MODEL_QC`, `MODEL_AUTO`.
- `templates/.claude/skills/vibeplan/SKILL.md` — emit a tier per task in
  `tasks.md` and `sync.json`.
- `scripts/qc-prompt.md` — tag tier on appended tasks.
- CLAUDE.md / docs — document the routing model and config knobs.
- `scripts/push-to-phramewerks.sh` — ensure any new infra files sync.

## Out of scope

- A runtime LLM classifier for complexity (planner tags suffice; avoids extra
  round-trips and rate-limit exposure).
- Changing token *counts* or context loading per task.
- Per-task model overrides from the CLI (only whole-run `--model`).

## Success criteria

- A task tagged `simple` runs on Haiku; `complex` runs on Opus; untagged runs on
  Sonnet — verifiable from `state/ralph.log` model lines.
- A `simple` task that fails `verify_build()` retries on `medium`, then
  `complex`.
- Both QC stages run on `MODEL_QC` regardless of the per-task models used.
- With `MODEL_AUTO` off (or `--model` set), behavior matches today exactly.
