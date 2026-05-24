#!/usr/bin/env bash
# vibekit.config.sh — Ralph configuration for the vibekit project itself.
# Ralph is dogfooded here — these enhancements edit the very framework running them.

TOOL="claude"
MODEL="claude-sonnet-4-6"

SYNC_FILE="$PROJECT_ROOT/state/sync.json"
SESSION_LOG_FILE="$PROJECT_ROOT/state/session-log.json"
RALPH_PROMPT="$PROJECT_ROOT/scripts/ralph-prompt.md"
DECISIONS_FILE="$PROJECT_ROOT/state/decisions.md"
LOG_FILE="$PROJECT_ROOT/state/ralph.log"
BRIEF_FILE="$PROJECT_ROOT/docs/briefs/007-complexity-model-routing.md"
QC_PROMPT="$PROJECT_ROOT/scripts/qc-prompt.md"

SPEC_TASKS_FILE="$PROJECT_ROOT/specs/007-complexity-model-routing/tasks.md"

SKILLS=()

# verify_build — runs after every task completion. Catches structural breakage
# in the self-modifying framework before it commits.
verify_build() {
  # Bash syntax for all scripts
  for f in scripts/ralph.sh scripts/sync-agent.sh scripts/sync-helpers.sh scripts/monitor.sh vibekit.config.sh templates/vibekit.config.sh; do
    if [[ -f "$f" ]]; then
      bash -n "$f" || { echo "verify_build: syntax error in $f" >&2; return 1; }
    fi
  done

  # JSON validity for any manifest.json we create
  for f in templates/docs/claude/manifest.json docs/claude/manifest.json; do
    if [[ -f "$f" ]]; then
      python3 -c "import json, sys; json.load(open('$f'))" 2>/dev/null \
        || { echo "verify_build: invalid JSON in $f" >&2; return 1; }
    fi
  done

  # Skill files must have YAML frontmatter with name+description
  for f in templates/.claude/skills/*/SKILL.md sandbox/ragtest/.claude/skills/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    head -5 "$f" | grep -q "^name:" || { echo "verify_build: missing name in $f" >&2; return 1; }
    head -5 "$f" | grep -q "^description:" || { echo "verify_build: missing description in $f" >&2; return 1; }
  done

  return 0
}
