# Stack

> Load this file when adding dependencies, configuring tooling, or checking what's in use.

---

## Language & Runtime

- **Shell:** bash (primary language for all scripts)
- **Python 3:** used for JSON operations in sync-helpers.sh (jq fallback available)
- No Node.js, no package manager, no build step

## Key Tools (Runtime Dependencies)

| Tool | Required | Purpose |
|------|----------|---------|
| `bash` | Yes | All scripts |
| `python3` | Yes (primary) | JSON read/write in sync-helpers.sh |
| `python` (≥3) | Fallback | If python3 not available |
| `jq` | Fallback | JSON ops if no Python 3 |
| `claude` CLI | Yes | Executing tasks (ralph.sh), running sync agent |
| `git` | Yes | Rollback, commit, history |
| `curl` | Yes | OAuth usage API (rate limit checking) |
| `amp` | Optional | Alternative to claude CLI (`--tool amp`) |

## Claude Models (Default)

- **Ralph:** `claude-sonnet-4-6` (configurable via `--model` or `vibekit.config.sh`)
- **Sync agent:** inherits session model (runs via `claude --print`)

## Skill Format

- YAML frontmatter + markdown body
- No external parser — Claude reads SKILL.md content directly
- `{{SKILLS_CONTEXT}}` placeholder substituted via Python in ralph.sh at runtime

## No External Dependencies

vibekit has no `package.json`, `requirements.txt`, `go.mod`, or similar. Everything runs with bash + python3 + claude CLI.
