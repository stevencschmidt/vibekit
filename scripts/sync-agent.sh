#!/usr/bin/env bash
# scripts/sync-agent.sh — Knowledge graph sync hook
#
# Invoked by .claude/settings.json PreCompact and SessionEnd hooks.
# Runs as a subprocess with no access to the parent session's conversation.
# Determines what to sync by examining git diff and current domain file state.
#
# Exits 0 always — never blocks compaction or session end.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL_FILE="$PROJECT_ROOT/.claude/skills/knowledge-graph-sync/SKILL.md"

# If the skill file doesn't exist, exit silently
if [[ ! -f "$SKILL_FILE" ]]; then
  exit 0
fi

SKILL=$(cat "$SKILL_FILE" 2>/dev/null) || exit 0

# Determine which claude binary to use
if command -v claude &>/dev/null; then
  claude --dangerously-skip-permissions --print "$SKILL" 2>/dev/null || true
fi

# Always exit 0 — never block compaction or session end
exit 0
