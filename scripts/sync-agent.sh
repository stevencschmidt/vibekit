#!/usr/bin/env bash
# scripts/sync-agent.sh — Knowledge graph sync hook
#
# Invoked by .claude/settings.json PreCompact and SessionEnd hooks.
# Runs as a subprocess with no access to the parent session's conversation.
# Determines what to sync by examining git diff and current domain file state.
#
# Usage: sync-agent.sh [precompact|sessionend]
#   precompact (default): fire-and-forget — returns in <500ms; compaction never blocks on this hook
#   sessionend: best-effort with 10s hard timeout — sync runs but cannot hang shutdown
#   unknown mode: defaults to fire-and-forget for safety
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

mkdir -p "$PROJECT_ROOT/state" 2>/dev/null || true
echo "[$(date -Iseconds)] sync-agent ${1:-precompact} pid=$$" >> "$PROJECT_ROOT/state/sync-agent.log" 2>/dev/null || true

MODE="${1:-precompact}"

if command -v claude &>/dev/null; then
  case "$MODE" in
    sessionend)
      # Best-effort with hard timeout — sync runs but cannot hang shutdown
      timeout 10s claude --dangerously-skip-permissions --print "$SKILL" >/dev/null 2>&1 || true
      ;;
    precompact|*)
      # Fire-and-forget — hook returns immediately so compaction is never blocked
      ( claude --dangerously-skip-permissions --print "$SKILL" >/dev/null 2>&1 || true ) & disown
      ;;
  esac
fi

# Always exit 0 — never block compaction or session end
exit 0
